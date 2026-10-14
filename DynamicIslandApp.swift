import SwiftUI

@main
struct DynamicIslandApp: App {
    @StateObject private var manager = IslandManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(manager)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .inactive || newPhase == .background {
                        manager.ensureBackgroundExecution()
                    }
                }
        }
    }
}
