import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: ViewerState
    @State private var isDropTargeted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            InspectorView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            detailView
        }
        .onAppear {
            AppDelegate.shared?.onOpen = { url in state.load(url: url) }
        }
        .onOpenURL { url in
            state.load(url: url)
        }
    }

    private var detailView: some View {
        ZStack {
            Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 1))
                .ignoresSafeArea()

            if state.scene != nil {
                SceneViewport(state: state)
                    .ignoresSafeArea()
            } else {
                DropPromptView(isTargeted: isDropTargeted) {
                    state.presentOpenPanel()
                }
            }

            VStack(spacing: 10) {
                Spacer()
                if state.hasAnimation {
                    playbackBar
                }
                if let error = state.errorMessage {
                    errorBanner(error)
                }
            }
            .padding(16)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            state.load(url: url)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .toolbar { toolbarContent }
        .navigationTitle(state.fileName ?? "3D Viewer")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                state.presentOpenPanel()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .help("Open a 3D file (⌘O)")

            Button {
                state.resetCamera()
            } label: {
                Label("Reset Camera", systemImage: "arrow.counterclockwise")
            }
            .disabled(state.scene == nil)
            .help("Reset camera (⌘R)")

            Button {
                state.saveSnapshot()
            } label: {
                Label("Snapshot", systemImage: "camera")
            }
            .disabled(state.scene == nil)
            .help("Save snapshot (⌘S)")

            Menu {
                Button("Export as .scn…") { state.export(as: .scn) }
                Button("Export as .usdz…") { state.export(as: .usdz) }
                Divider()
                Button("Export Turntable GIF…") { state.exportTurntable() }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(state.scene == nil)
        }
    }

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button {
                state.isPlaying.toggle()
            } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            Slider(value: $state.sceneTime, in: 0...max(state.sceneDuration, 0.01)) { editing in
                if editing { state.isPlaying = false }
            }

            Text(timeLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 520)
    }

    private var timeLabel: String {
        String(format: "%.1f / %.1f s", state.sceneTime, state.sceneDuration)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.callout)
            Spacer()
            Button {
                state.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
        .background(Color.red.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct DropPromptView: View {
    let isTargeted: Bool
    let onBrowse: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 96, weight: .ultraLight))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .scaleEffect(isTargeted ? 1.08 : 1.0)
                .animation(.easeInOut(duration: 0.18), value: isTargeted)

            Text("Drop a 3D file here")
                .font(.title2.weight(.medium))

            Text("OBJ · USDZ · USD · DAE · SCN · PLY · STL · ABC")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Browse…", action: onBrowse)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(24)
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}
