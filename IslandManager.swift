import Foundation
import SwiftUI
import AVKit
import AVFoundation
import CoreMotion
import MediaPlayer
import Combine

class IslandManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published var currentTrack: String = "No Media Playing"
    @Published var currentArtist: String = "Play music to expand"
    @Published var isPlayingMusic: Bool = false
    
    @Published var stepCount: Int = 0
    @Published var stopwatchTime: TimeInterval = 0
    @Published var isStopwatchRunning: Bool = false
    @Published var isPiPActive: Bool = false
    @Published var autoPopOutOnExit: Bool = true
    
    private let pedometer = CMPedometer()
    private var stopwatchStartDate: Date?
    private var accumulatedStopwatchTime: TimeInterval = 0
    
    private var silentAudioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var renderSourceTimer: DispatchSourceTimer?
    
    let sampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController?
    
    override init() {
        super.init()
        setupContinuousBackgroundAudio()
        startStepTracking()
        setupNowPlayingObserver()
        setupPiP()
        startHighPriorityFrameRenderer()
    }
    
    private func setupContinuousBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            
            let wavData = Self.makeSilentWavData()
            silentAudioPlayer = try AVAudioPlayer(data: wavData)
            silentAudioPlayer?.numberOfLoops = -1
            silentAudioPlayer?.volume = 0.01
            silentAudioPlayer?.prepareToPlay()
            silentAudioPlayer?.play()
        } catch {
            print("Background Audio Error: \(error)")
        }
    }
    
    func ensureBackgroundExecution() {
        if silentAudioPlayer?.isPlaying == false {
            silentAudioPlayer?.play()
        }
        if backgroundTaskID == .invalid {
            backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "KeepIslandAlive") { [weak self] in
                if let id = self?.backgroundTaskID {
                    UIApplication.shared.endBackgroundTask(id)
                }
                self?.backgroundTaskID = .invalid
            }
        }
        if autoPopOutOnExit, let pip = pipController, !pip.isPictureInPictureActive {
            pip.startPictureInPicture()
        }
    }
    
    private static func makeSilentWavData() -> Data {
        let sampleRate: Int32 = 8000
        let numSamples: Int32 = 8000
        let dataSize: Int32 = numSamples * 2
        let fileSize: Int32 = 36 + dataSize
        
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: Int32(16).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(1).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: (sampleRate * 2).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(2).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: Int16(16).littleEndian) { Data($0) })
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize)))
        return data
    }
    
    func startStepTracking() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let startOfDay = Calendar.current.startOfDay(for: Date())
        pedometer.startUpdates(from: startOfDay) { [weak self] data, error in
            guard let data = data, error == nil else { return }
            DispatchQueue.main.async {
                self?.stepCount = data.numberOfSteps.intValue
            }
        }
    }
    
    func setupNowPlayingObserver() {
        let musicPlayer = MPMusicPlayerController.systemMusicPlayer
        musicPlayer.beginGeneratingPlaybackNotifications()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateNowPlaying),
            name: .MPMusicPlayerControllerNowPlayingItemDidChange,
            object: musicPlayer
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateNowPlaying),
            name: .MPMusicPlayerControllerPlaybackStateDidChange,
            object: musicPlayer
        )
        updateNowPlaying()
    }
    
    @objc func updateNowPlaying() {
        let player = MPMusicPlayerController.systemMusicPlayer
        DispatchQueue.main.async {
            if let item = player.nowPlayingItem {
                self.currentTrack = item.title ?? "Unknown Track"
                self.currentArtist = item.artist ?? "Unknown Artist"
                self.isPlayingMusic = (player.playbackState == .playing)
            } else {
                self.isPlayingMusic = (player.playbackState == .playing)
            }
        }
    }
    
    func toggleStopwatch() {
        if isStopwatchRunning {
            if let start = stopwatchStartDate {
                accumulatedStopwatchTime += Date().timeIntervalSince(start)
            }
            stopwatchStartDate = nil
            isStopwatchRunning = false
        } else {
            stopwatchStartDate = Date()
            isStopwatchRunning = true
        }
    }
    
    func resetStopwatch() {
        stopwatchStartDate = nil
        accumulatedStopwatchTime = 0
        stopwatchTime = 0
        isStopwatchRunning = false
    }
    
    func formattedStopwatch() -> String {
        let total = stopwatchTime
        let totalSeconds = Int(total)
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        let tenths = Int((total - Double(totalSeconds)) * 10)
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
    
    func setupPiP() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        sampleBufferDisplayLayer.videoGravity = .resizeAspect
        pushIslandFrame()
        
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: sampleBufferDisplayLayer,
            playbackDelegate: self
        )
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController?.delegate = self
        if #available(iOS 14.2, *) {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        pipController?.requiresLinearPlayback = true
    }
    
    func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }
    
    func startHighPriorityFrameRenderer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.isStopwatchRunning, let start = self.stopwatchStartDate {
                self.stopwatchTime = self.accumulatedStopwatchTime + Date().timeIntervalSince(start)
            }
            self.pushIslandFrame()
        }
        timer.resume()
        renderSourceTimer = timer
    }
    
    private func pushIslandFrame() {
        let size = CGSize(width: 660, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            
            UIColor.black.setFill()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 60)
            path.fill()
            
            UIColor(white: 0.25, alpha: 1.0).setStroke()
            path.lineWidth = 3
            path.stroke()
            
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 23, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .medium),
                .foregroundColor: UIColor.systemGray
            ]
            let stepAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.systemGreen
            ]
            let timerAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold),
                .foregroundColor: UIColor.systemOrange
            ]
            
            let musicIcon = isPlayingMusic ? "🎵 " : "⏸️ "
            let trackText = (musicIcon + currentTrack) as NSString
            trackText.draw(in: CGRect(x: 32, y: 24, width: 340, height: 32), withAttributes: titleAttrs)
            
            let artistText = currentArtist as NSString
            artistText.draw(in: CGRect(x: 32, y: 60, width: 340, height: 26), withAttributes: subAttrs)
            
            let stepsString = "👟 \(stepCount)" as NSString
            stepsString.draw(in: CGRect(x: 410, y: 24, width: 220, height: 32), withAttributes: stepAttrs)
            
            let swString = "⏱️ \(formattedStopwatch())" as NSString
            swString.draw(in: CGRect(x: 410, y: 60, width: 220, height: 32), withAttributes: timerAttrs)
        }
        
        if let sampleBuffer = image.toCMSampleBuffer() {
            if sampleBufferDisplayLayer.status == .failed {
                sampleBufferDisplayLayer.flush()
            }
            sampleBufferDisplayLayer.enqueue(sampleBuffer)
        }
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
    }
}

extension IslandManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        DispatchQueue.main.async {
            self.toggleStopwatch()
        }
    }
    
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
    
    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        return false
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}

extension UIImage {
    func toCMSampleBuffer() -> CMSampleBuffer? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        
        var pixelBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32ARGB,
            attrs,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else {
            CVPixelBufferUnlockBaseAddress(buffer, [])
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else { return nil }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 10),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: CMTime.invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}
