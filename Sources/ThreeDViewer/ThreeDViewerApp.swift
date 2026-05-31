import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    static private(set) var shared: AppDelegate?
    var onOpen: ((URL) -> Void)?
    private var pendingURL: URL?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` produces a bare executable, not a .app bundle, so macOS
        // launches us as an accessory process: no Dock icon, no Cmd-Tab entry,
        // and the window opens without coming to the front. Promote to a
        // regular app and pull ourselves forward.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if let handler = onOpen {
            handler(url)
        } else {
            pendingURL = url
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let url = pendingURL, let handler = onOpen {
            pendingURL = nil
            handler(url)
        }
    }
}

@main
struct ThreeDViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = ViewerState()

    var body: some Scene {
        WindowGroup("3D Viewer") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 660)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    state.presentOpenPanel()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Menu("Open Recent") {
                    if state.recentFiles.isEmpty {
                        Text("No Recent Files")
                    } else {
                        ForEach(state.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                state.load(url: url)
                            }
                        }
                        Divider()
                        Button("Clear Menu") {
                            state.clearRecents()
                        }
                    }
                }
            }

            CommandGroup(after: .newItem) {
                Divider()
                Button("Close Model") {
                    state.clear()
                }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .disabled(state.scene == nil)
            }

            CommandMenu("Model") {
                Button("Reset Camera") {
                    state.resetCamera()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(state.scene == nil)

                Divider()

                Button("Save Snapshot…") {
                    state.saveSnapshot()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(state.scene == nil)

                Button("Copy Snapshot") {
                    state.copySnapshot()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(state.scene == nil)

                Divider()

                Button("Export as .scn…") {
                    state.export(as: .scn)
                }
                .disabled(state.scene == nil)

                Button("Export as .usdz…") {
                    state.export(as: .usdz)
                }
                .disabled(state.scene == nil)

                Button("Export Turntable GIF…") {
                    state.exportTurntable()
                }
                .disabled(state.scene == nil)
            }
        }
    }
}
