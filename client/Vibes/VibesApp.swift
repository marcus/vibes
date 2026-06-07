import SwiftUI

@main
struct VibesApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(model)
    }
    .windowResizability(.contentSize)

    MenuBarExtra("Vibes", systemImage: "dot.radiowaves.left.and.right") {
      Button("Show Vibes") {
        NSApp.activate(ignoringOtherApps: true)
      }
      Divider()
      Picker("Mode", selection: Binding(
        get: { model.mode },
        set: { model.setMode($0) }
      )) {
        ForEach(PresenceMode.allCases) { mode in
          Text(mode.label).tag(mode)
        }
      }
      Button("Scan Now") {
        Task { await model.scanPublishAndFetch() }
      }
      Divider()
      Button("Quit") {
        model.publishOfflineBeforeQuit()
        NSApp.terminate(nil)
      }
    }
  }
}
