import SwiftUI
import AVKit

struct PiPLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        layer.frame = CGRect(x: 0, y: 0, width: 330, height: 60)
        view.layer.addSublayer(layer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        layer.frame = uiView.bounds
    }
}

struct ContentView: View {
    @EnvironmentObject var manager: IslandManager
    @State private var isExpanded: Bool = false
    
    var body: some View {
        ZStack(alignment: .top) {
            Color(red: 0.04, green: 0.04, blue: 0.07)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                VStack {
                    HStack(spacing: 14) {
                        Image(systemName: manager.isPlayingMusic ? "waveform.circle.fill" : "music.note")
                            .font(.system(size: 24))
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.currentTrack)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(manager.currentArtist)
                                .font(.system(size: 11))
                                .foregroundColor(.gray)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("👟 \(manager.stepCount)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                            Text("⏱️ \(manager.formattedStopwatch())")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                        }
                    }
                    
                    if isExpanded {
                        Divider().background(Color.gray.opacity(0.4)).padding(.vertical, 6)
                        HStack(spacing: 24) {
                            Button(action: { manager.toggleStopwatch() }) {
                                Label(manager.isStopwatchRunning ? "Pause" : "Start", systemImage: manager.isStopwatchRunning ? "pause.fill" : "play.fill")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.orange.opacity(0.25))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                            
                            Button(action: { manager.resetStopwatch() }) {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color.gray.opacity(0.25))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 6)
                .padding(.horizontal, 16)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        isExpanded.toggle()
                    }
                }
                
                VStack(spacing: 6) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Always-On Out-of-App Floating Stream")
                            .font(.caption.bold())
                            .foregroundColor(.green)
                    }
                    
                    PiPLayerView(layer: manager.sampleBufferDisplayLayer)
                        .frame(width: 330, height: 60)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.green.opacity(0.5), lineWidth: 1))
                }
                
                VStack(spacing: 14) {
                    Toggle("Auto-Pop Out When Swiping Home", isOn: $manager.autoPopOutOnExit)
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                    
                    Button(action: { manager.togglePiP() }) {
                        HStack {
                            Image(systemName: manager.isPiPActive ? "pip.exit" : "pip.enter")
                            Text(manager.isPiPActive ? "Hide Floating Island" : "Activate Floating Island Now")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(manager.isPiPActive ? Color.red : Color.green)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    HStack(spacing: 12) {
                        Button(action: { manager.toggleStopwatch() }) {
                            HStack {
                                Image(systemName: manager.isStopwatchRunning ? "pause.circle.fill" : "stopwatch.fill")
                                Text(manager.isStopwatchRunning ? "Pause Timer" : "Start Stopwatch")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        
                        Button(action: { manager.resetStopwatch() }) {
                            Image(systemName: "arrow.counterclockwise")
                                .padding()
                                .background(Color.white.opacity(0.1))
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    
                    Button(action: {
                        manager.isPlayingMusic.toggle()
                        if manager.isPlayingMusic && manager.currentTrack == "No Media Playing" {
                            manager.currentTrack = "Let It Happen"
                            manager.currentArtist = "Tame Impala"
                        }
                    }) {
                        HStack {
                            Image(systemName: "music.note.list")
                            Text("Test Media Expansion")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .background(Color.purple.opacity(0.25))
                        .foregroundColor(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(18)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .padding(.horizontal, 16)
                
                Spacer()
                
                Text("Swipe up to your Home Screen or open any app—the black Dynamic Island pill pops out automatically and updates live in the background!")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
            .padding(.top, 8)
        }
    }
}
