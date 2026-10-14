import Foundation
import SwiftUI
import UIKit
import AVKit
import AVFoundation
import CoreMotion
import MediaPlayer
import Combine

enum IslandMetric: String, CaseIterable, Identifiable {
    case clock = "Clock"
    case steps = "Step Count"
    case battery = "Battery Level"
    case stopwatch = "Stopwatch Timer"
    case media = "Now Playing"
    
    var id: String { self.rawValue }
}

class IslandManager: NSObject, ObservableObject, AVPictureInPictureControllerDelegate {
    @Published var currentTrack: String = "No Media Playing"
    @Published var currentArtist: String = "Idle • Ready"
    @Published var isPlayingMusic: Bool = false
    
    @Published var stepCount: Int = 0
    @Published var batteryLevel: Int = 100
    @Published var isCharging: Bool = false
    @Published var stopwatchTime: TimeInterval = 0
    @Published var isStopwatchRunning: Bool = false
    @Published var isPiPActive: Bool = false
    
    // Customizable Metrics
    @Published var leftMetric: IslandMetric = .media
    @Published var rightMetric: IslandMetric = .stopwatch
    
    // Notch Customization Sliders
    @Published var pillWidth: CGFloat = 165
    @Published var pillHeight: CGFloat = 34
    @Published var topOffset: CGFloat = 4
    @Published var pipScale: CGFloat = 1.0
    @Published var isCompactMode: Bool = true
    @Published var accentColorIndex: Int = 0 // 0: Green, 1: Purple, 2: Orange, 3: Cyan
    
    @Published var autoPopOutOnExit: Bool = true {
        didSet {
            if #available(iOS 14.2, *) {
                pipController?.canStartPictureInPictureAutomaticallyFromInline = autoPopOutOnExit
            }
        }
    }
    
    private let pedometer = CMPedometer()
    private var stopwatchStartDate: Date?
    private var accumulatedStopwatchTime: TimeInterval = 0
    
    private var silentAudioPlayer: AVAudioPlayer?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var renderSourceTimer: DispatchSourceTimer?
    
    private weak var displayLayer: AVSampleBufferDisplayLayer?
    private var pipController: AVPictureInPictureController?
    private var wasInterruptedByOtherPiP: Bool = false
    
    private let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df
    }()
    
    var currentUIColor: UIColor {
        switch accentColorIndex {
        case 1: return UIColor.systemPurple
        case 2: return UIColor.systemOrange
        case 3: return UIColor.systemCyan
        default: return UIColor.systemGreen
        }
    }
    
    var currentSwiftUIColor: Color {
        switch accentColorIndex {
        case 1: return .purple
        case 2: return .orange
        case 3: return .cyan
        default: return .green
        }
    }
    
    override init() {
        super.init()
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryInfo()
        setupContinuousBackgroundAudio()
        setupAudioInterruptionObserver()
        startStepTracking()
        setupNowPlayingObserver()
        startHighPriorityFrameRenderer()
    }
    
    private func updateBatteryInfo() {
        let level = UIDevice.current.batteryLevel
        batteryLevel = level >= 0 ? Int(level * 100) : 100
        let state = UIDevice.current.batteryState
        isCharging = (state == .charging || state == .full)
    }
    
    private func setupContinuousBackgroundAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
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
    
    private func setupAudioInterruptionObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.ensureBackgroundExecution()
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        ensureBackgroundExecution()
        pushIslandFrame()
        pipController?.invalidatePlaybackState()
    }
    
    func attachDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        guard self.displayLayer !== layer else { return }
        self.displayLayer = layer
        layer.videoGravity = .resizeAspectFill
        
        var timebase: CMTimebase?
        CMTimebaseCreateWithSourceClock(
            allocator: nil,
            sourceClock: CMClockGetHostTimeClock(),
            timebaseOut: &timebase
        )
        if let tb = timebase {
            CMTimebaseSetTime(tb, time: CMClockGetTime(CMClockGetHostTimeClock()))
            CMTimebaseSetRate(tb, rate: 1.0)
            layer.controlTimebase = tb
        }
        
        pushIslandFrame()
        
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let pip = AVPictureInPictureController(contentSource: contentSource)
        pip.delegate = self
        if #available(iOS 14.2, *) {
            pip.canStartPictureInPictureAutomaticallyFromInline = autoPopOutOnExit
        }
        pip.requiresLinearPlayback = false
        self.pipController = pip
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.pushIslandFrame()
            self?.pipController?.invalidatePlaybackState()
        }
    }
    
    func ensureBackgroundExecution() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}
        
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
            } else if self.currentTrack == "No Media Playing" {
                self.isPlayingMusic = false
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
    
    func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }
    
    func textForMetric(_ metric: IslandMetric) -> String {
        switch metric {
        case .clock: return timeFormatter.string(from: Date())
        case .steps: return "👟\(stepCount)"
        case .battery: return "\(isCharging ? "⚡" : "🔋")\(batteryLevel)%"
        case .stopwatch: return "⏱️\(formattedStopwatch())"
        case .media: return isPlayingMusic ? currentTrack : "DynamicIsland"
        }
    }
    
    func startHighPriorityFrameRenderer() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(250))
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            if self.isStopwatchRunning, let start = self.stopwatchStartDate {
                self.stopwatchTime = self.accumulatedStopwatchTime + Date().timeIntervalSince(start)
            }
            if self.silentAudioPlayer?.isPlaying == false {
                self.silentAudioPlayer?.play()
            }
            self.updateBatteryInfo()
            self.pushIslandFrame()
            
            if self.wasInterruptedByOtherPiP,
               UIApplication.shared.applicationState != .active,
               let pip = self.pipController,
               !pip.isPictureInPictureActive,
               pip.isPictureInPicturePossible {
                pip.startPictureInPicture()
            }
        }
        timer.resume()
        renderSourceTimer = timer
    }
    
    private func pushIslandFrame() {
        guard let layer = displayLayer else { return }
        
        // COMPACT PILL RENDER SIZE (Forces iOS PiP to be small and pill-shaped)
        let size = CGSize(width: 360, height: 72)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        
        let accent = currentUIColor
        
        let image = renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            
            UIColor.black.setFill()
            ctx.fill(rect)
            
            let pillRect = rect.insetBy(dx: 2, dy: 2)
            let path = UIBezierPath(roundedRect: pillRect, cornerRadius: 34)
            
            UIColor.black.setFill()
            path.fill()
            
            accent.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 2.0
            path.stroke()
            
            let mainAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 17, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let rightAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .bold),
                .foregroundColor: accent
            ]
            
            let leftText = textForMetric(leftMetric)
            (leftText as NSString).draw(in: CGRect(x: 18, y: (72 - 22) / 2, width: 160, height: 24), withAttributes: mainAttrs)
            
            let rightText = textForMetric(rightMetric)
            (rightText as NSString).draw(in: CGRect(x: 195, y: (72 - 22) / 2, width: 150, height: 24), withAttributes: rightAttrs)
        }
        
        if let sampleBuffer = image.toCMSampleBuffer() {
            if layer.status == .failed {
                layer.flush()
            }
            layer.enqueue(sampleBuffer)
        }
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = true
        wasInterruptedByOtherPiP = false
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isPiPActive = false
        if UIApplication.shared.applicationState != .active {
            wasInterruptedByOtherPiP = true
            ensureBackgroundExecution()
        }
    }
}

extension IslandManager: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        DispatchQueue.main.async {
            self.toggleStopwatch()
            pictureInPictureController.invalidatePlaybackState()
        }
    }
    
    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        return CMTimeRange(start: .zero, duration: CMTime(seconds: 86400 * 365, preferredTimescale: 600))
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
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        let status = CVPixelBufferCreate(
            nil,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        
        guard let context = CGContext(
            data: pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: rgbColorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: buffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else { return nil }
        
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 5),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil,
            imageBuffer: buffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        
        if let sb = sampleBuffer, let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: true) {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dict,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }
        
        return sampleBuffer
    }
}
