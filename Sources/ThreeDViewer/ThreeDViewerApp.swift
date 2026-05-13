import SwiftUI
import AppKit

@main
struct ThreeDViewerApp: App {
    @StateObject private var viewerState = ViewerState()

    var body: some Scene {
        WindowGroup("3D Viewer") {
            ContentView()
                .environmentObject(viewerState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    viewerState.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Close Model") {
                    viewerState.clear()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(viewerState.scene == nil)
            }
        }
    }
}
