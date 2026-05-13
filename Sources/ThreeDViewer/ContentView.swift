import SwiftUI
import SceneKit
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var state: ViewerState
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            Color(nsColor: NSColor(calibratedWhite: 0.09, alpha: 1.0))
                .ignoresSafeArea()

            if let scene = state.scene {
                SceneView(
                    scene: scene,
                    options: [
                        .allowsCameraControl,
                        .autoenablesDefaultLighting,
                        .temporalAntialiasingEnabled
                    ]
                )
                .ignoresSafeArea()
            } else {
                DropPromptView(isTargeted: isDropTargeted) {
                    state.presentOpenPanel()
                }
            }

            VStack {
                if state.scene != nil {
                    topBar
                }
                Spacer()
                if let error = state.errorMessage {
                    errorBanner(error)
                }
            }
            .padding(16)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14)
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
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cube.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.fileName ?? "")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let stats = state.statistics {
                        Text(formatStats(stats))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            Button {
                state.presentOpenPanel()
            } label: {
                Image(systemName: "folder")
                    .padding(8)
            }
            .buttonStyle(.borderless)
            .background(.ultraThinMaterial, in: Circle())
            .help("Open File (⌘O)")

            Button {
                state.clear()
            } label: {
                Image(systemName: "xmark")
                    .padding(8)
            }
            .buttonStyle(.borderless)
            .background(.ultraThinMaterial, in: Circle())
            .help("Close Model (⇧⌘W)")
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .font(.callout)
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

    private func formatStats(_ s: ModelStatistics) -> String {
        let nodes = s.nodeCount.formatted()
        let verts = s.vertexCount.formatted()
        let tris = s.triangleCount.formatted()
        return "\(nodes) nodes • \(verts) verts • \(tris) tris"
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
                .foregroundStyle(.primary)

            Text("OBJ · USDZ · USD · DAE · SCN · PLY · STL · ABC")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Browse…", action: onBrowse)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
                .keyboardShortcut("o", modifiers: [.command])
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
