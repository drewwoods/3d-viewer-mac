import SwiftUI
import SceneKit

struct InspectorView: View {
    @EnvironmentObject private var state: ViewerState

    var body: some View {
        Form {
            if state.scene == nil {
                Section {
                    Text("No model loaded.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else {
                fileSection
                displaySection
                lightingSection
                overlaysSection
                if state.cameraNames.count > 1 {
                    cameraSection
                }
                measurementSection
                meshesSection
                statisticsSection
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - File

    private var fileSection: some View {
        Section("File") {
            LabeledContent("Name", value: state.fileName ?? "—")
            if let url = state.fileURL {
                LabeledContent("Format", value: url.pathExtension.uppercased())
            }
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            Picker("Mode", selection: $state.displayMode) {
                ForEach(DisplayMode.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Background", selection: $state.backgroundStyle) {
                ForEach(BackgroundStyle.allCases) { Text($0.rawValue).tag($0) }
            }
        }
    }

    // MARK: - Lighting

    private var lightingSection: some View {
        Section("Lighting") {
            Picker("Preset", selection: $state.lightingPreset) {
                ForEach(LightingPreset.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Load Environment Image…") {
                state.loadEnvironment()
            }
            if let url = state.environmentURL {
                LabeledContent("Environment", value: url.lastPathComponent)
            }
        }
    }

    // MARK: - Overlays

    private var overlaysSection: some View {
        Section("Overlays") {
            Toggle("Show Backfaces", isOn: $state.showBackfaces)
            Toggle("Bounding Box", isOn: $state.showBoundingBox)
            Toggle("Wireframe Overlay", isOn: $state.showWireframeOverlay)
            Toggle("Axes Gizmo", isOn: $state.showAxes)
            Toggle("Vertex Normals", isOn: $state.showNormals)
        }
    }

    // MARK: - Cameras

    private var cameraSection: some View {
        Section("Cameras") {
            Picker("Active", selection: $state.selectedCameraName) {
                ForEach(state.cameraNames, id: \.self) { name in
                    Text(SceneHelpers.displayName(forCamera: name)).tag(Optional(name))
                }
            }
            Button("Reset to Default View") {
                state.resetCamera()
            }
        }
    }

    // MARK: - Measurement

    private var measurementSection: some View {
        Section("Measure") {
            Toggle("Measurement Mode", isOn: $state.measurementMode)
            if state.measurementMode {
                Text("Click two surface points to measure distance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let distance = state.measurementDistance {
                LabeledContent("Distance", value: formatNumber(distance))
            }
        }
    }

    // MARK: - Meshes

    private var meshesSection: some View {
        Section("Meshes (\(state.meshNodes.count))") {
            ForEach($state.meshNodes) { $entry in
                HStack(spacing: 8) {
                    Button {
                        entry.isHidden.toggle()
                        entry.node.isHidden = entry.isHidden
                    } label: {
                        Image(systemName: entry.isHidden ? "eye.slash" : "eye")
                            .foregroundStyle(entry.isHidden ? .secondary : .primary)
                    }
                    .buttonStyle(.plain)

                    if let swatch = entry.swatch {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(swatch)
                            .frame(width: 14, height: 14)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.secondary.opacity(0.4)))
                    } else {
                        Image(systemName: entry.isTextured ? "photo" : "circle.dashed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 14)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.callout)
                            .lineLimit(1)
                        Text(entry.materialSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Statistics

    private var statisticsSection: some View {
        Section("Statistics") {
            if let stats = state.statistics {
                LabeledContent("Nodes", value: stats.nodeCount.formatted())
                LabeledContent("Meshes", value: stats.meshCount.formatted())
                LabeledContent("Vertices", value: stats.vertexCount.formatted())
                LabeledContent("Triangles", value: stats.triangleCount.formatted())
                LabeledContent("Surface Area", value: formatNumber(stats.surfaceArea))
                LabeledContent("Volume", value: formatNumber(stats.volume))
            }
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        if abs(value) < 0.001 || abs(value) >= 1_000_000 {
            return String(format: "%.3e", value)
        }
        return String(format: "%.4g", value)
    }
}
