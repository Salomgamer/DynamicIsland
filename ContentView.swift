import SwiftUI
import AVKit
import AVFoundation

class SampleBufferUIView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }
    var sampleBufferLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }
}

struct PiPLayerView: UIViewRepresentable {
    @ObservedObject var manager: IslandManager
    
    func makeUIView(context: Context) -> SampleBufferUIView {
        let view = SampleBufferUIView()
        view.backgroundColor = .black
        DispatchQueue.main.async {
            manager.attachDisplayLayer(view.sampleBufferLayer)
        }
        return view
    }
    
    func updateUIView(_ uiView: SampleBufferUIView, context: Context) {}
}

struct ContentView: View {
    @EnvironmentObject var manager: IslandManager
    @State private var isExpanded: Bool = false
    
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.09), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Spacer().frame(height: 65)
                    
                    // Live Stream Preview Card
                    VStack(spacing: 10) {
                        HStack {
                            Circle()
                                .fill(manager.currentSwiftUIColor)
                                .frame(width: 8, height: 8)
                            Text("FLOATING PIP STREAM PREVIEW")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(manager.currentSwiftUIColor)
                                .tracking(1.0)
                            Spacer()
                            Text("Pinch PiP to resize")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.horizontal, 8)
                        
                        PiPLayerView(manager: manager)
                            .frame(width: 260 * manager.pipScale, height: (manager.isCompactMode ? 48 : 54) * manager.pipScale)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(manager.currentSwiftUIColor.opacity(0.6), lineWidth: 1.5)
                            )
                            .shadow(color: manager.currentSwiftUIColor.opacity(0.25), radius: 10, x: 0, y: 4)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.horizontal, 16)
                    
                    // Primary Action Button
                    Button(action: { manager.togglePiP() }) {
                        HStack(spacing: 10) {
                            Image(systemName: manager.isPiPActive ? "pip.exit" : "pip.enter")
                                .font(.system(size: 18, weight: .bold))
                            Text(manager.isPiPActive ? "Close Floating Island" : "Pop Out Floating Island")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(manager.isPiPActive ? Color.red : manager.currentSwiftUIColor)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                        .shadow(color: (manager.isPiPActive ? Color.red : manager.currentSwiftUIColor).opacity(0.4), radius: 12, x: 0, y: 5)
                    }
                    .padding(.horizontal, 16)
                    
                    // CUSTOMIZE STATS CARD (New!)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle.portrait")
                                .foregroundColor(manager.currentSwiftUIColor)
                            Text("Customize What You See")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Left Side")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Picker("Left Metric", selection: $manager.leftMetric) {
                                    ForEach(IslandMetric.allCases) { metric in
                                        Text(metric.rawValue).tag(metric)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(manager.currentSwiftUIColor)
                                .padding(8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Right Side")
                                    .font(.caption.bold())
                                    .foregroundColor(.gray)
                                Picker("Right Metric", selection: $manager.rightMetric) {
                                    ForEach(IslandMetric.allCases) { metric in
                                        Text(metric.rawValue).tag(metric)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(manager.currentSwiftUIColor)
                                .padding(8)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    
                    // Notch Position & Size Sliders Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                                .foregroundColor(manager.currentSwiftUIColor)
                            Text("Notch Fit & Island Size")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Spacer()
                            Button("Reset") {
                                withAnimation(.spring()) {
                                    manager.pillWidth = 210
                                    manager.pillHeight = 36
                                    manager.topOffset = 0
                                    manager.pipScale = 1.0
                                }
                            }
                            .font(.caption.bold())
                            .foregroundColor(manager.currentSwiftUIColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Notch Pill Width")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(Int(manager.pillWidth)) pt")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.white)
                            }
                            Slider(value: $manager.pillWidth, in: 130...340, step: 1)
                                .tint(manager.currentSwiftUIColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Notch Pill Height")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(Int(manager.pillHeight)) pt")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.white)
                            }
                            Slider(value: $manager.pillHeight, in: 24...64, step: 1)
                                .tint(manager.currentSwiftUIColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Vertical Notch Position (Y-Offset)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(Int(manager.topOffset)) pt")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.white)
                            }
                            Slider(value: $manager.topOffset, in: -18...40, step: 1)
                                .tint(manager.currentSwiftUIColor)
                        }
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        Toggle("Minimal Slim Pill Mode", isOn: $manager.isCompactMode)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .tint(manager.currentSwiftUIColor)
                        
                        Toggle("Auto-Pop Out on Home Swipe", isOn: $manager.autoPopOutOnExit)
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                            .tint(manager.currentSwiftUIColor)
                        
                        // Accent Color Picker
                        HStack {
                            Text("Glow Theme")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                            Spacer()
                            ForEach(0..<4, id: \.self) { idx in
                                let colors: [Color] = [.green, .purple, .orange, .cyan]
                                Circle()
                                    .fill(colors[idx])
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: manager.accentColorIndex == idx ? 2.5 : 0)
                                    )
                                    .onTapGesture {
                                        withAnimation { manager.accentColorIndex = idx }
                                    }
                            }
                        }
                    }
                    .padding(18)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    
                    // Quick Testing Card
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button(action: { manager.toggleStopwatch() }) {
                                HStack {
                                    Image(systemName: manager.isStopwatchRunning ? "pause.fill" : "stopwatch.fill")
                                    Text(manager.isStopwatchRunning ? "Pause Timer" : "Start Timer")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                            }
                            
                            Button(action: { manager.resetStopwatch() }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .padding(14)
                                    .background(Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .clipShape(Circle())
                            }
                        }
                        
                        Button(action: {
                            withAnimation(.spring()) {
                                manager.isPlayingMusic.toggle()
                                if manager.isPlayingMusic && manager.currentTrack == "No Media Playing" {
                                    manager.currentTrack = "Let It Happen"
                                    manager.currentArtist = "Tame Impala"
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "waveform")
                                Text(manager.isPlayingMusic ? "Stop Demo Track" : "Simulate Music Playback")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(Color.purple.opacity(0.22))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
            }
            
            // REAL NOTCH-HUGGING DYNAMIC ISLAND OVERLAY
            VStack(spacing: 0) {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(Color.black)
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(manager.currentSwiftUIColor.opacity(0.45), lineWidth: 1.2)
                        )
                        .shadow(color: .black.opacity(0.8), radius: 10, x: 0, y: 4)
                    
                    if isExpanded {
                        VStack(spacing: 12) {
                            Spacer().frame(height: 14)
                            HStack(spacing: 12) {
                                ZStack {
                                    Circle()
                                        .fill(manager.currentSwiftUIColor.opacity(0.2))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: manager.isPlayingMusic ? "waveform" : "sparkles")
                                        .foregroundColor(manager.currentSwiftUIColor)
                                        .font(.system(size: 18, weight: .bold))
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(manager.currentTrack)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text(manager.currentArtist)
                                        .font(.system(size: 12))
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("👟 \(manager.stepCount)")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(manager.currentSwiftUIColor)
                                    Text("⏱️ \(manager.formattedStopwatch())")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                            .padding(.horizontal, 18)
                            
                            HStack(spacing: 20) {
                                Button(action: { manager.toggleStopwatch() }) {
                                    Label(manager.isStopwatchRunning ? "Pause" : "Timer", systemImage: manager.isStopwatchRunning ? "pause.fill" : "play.fill")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 7)
                                        .background(Color.orange.opacity(0.25))
                                        .foregroundColor(.orange)
                                        .clipShape(Capsule())
                                }
                                Button(action: { manager.togglePiP() }) {
                                    Label("Float PiP", systemImage: "pip.enter")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 7)
                                        .background(manager.currentSwiftUIColor.opacity(0.25))
                                        .foregroundColor(manager.currentSwiftUIColor)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.bottom, 10)
                        }
                    } else {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(manager.currentSwiftUIColor)
                                Text(manager.textForMetric(manager.leftMetric))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                            .padding(.leading, 12)
                            
                            Spacer()
                            
                            HStack(spacing: 4) {
                                Text(manager.textForMetric(manager.rightMetric))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(manager.currentSwiftUIColor)
                            }
                            .padding(.trailing, 12)
                        }
                    }
                }
                .frame(
                    width: isExpanded ? 340 : manager.pillWidth,
                    height: isExpanded ? 125 : manager.pillHeight
                )
                .offset(y: manager.topOffset)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                        isExpanded.toggle()
                    }
                }
            }
            .ignoresSafeArea(.all, edges: .top)
        }
    }
}
