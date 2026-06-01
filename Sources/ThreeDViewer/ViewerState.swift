import Foundation
import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO
import AppKit
import UniformTypeIdentifiers

enum DisplayMode: String, CaseIterable, Identifiable {
    case shaded = "Shaded"
    case wireframe = "Wireframe"
    case shadedWireframe = "Shaded + Wireframe"
    case points = "Points"
    var id: String { rawValue }
}

enum LightingPreset: String, CaseIterable, Identifiable {
    case studio = "Studio"
    case threePoint = "Three-Point"
    case outdoor = "Outdoor"
    case topDown = "Top-Down"
    case singleKey = "Single Key"
    case dramatic = "Dramatic"
    case flat = "Flat"
    case sunset = "Sunset"
    case moonlight = "Moonlight"
    case environment = "Environment"
    var id: String { rawValue }
}

enum LightingModelOption: String, CaseIterable, Identifiable {
    case asLoaded = "As Loaded"
    case physicallyBased = "Physically Based"
    case blinn = "Blinn"
    case phong = "Phong"
    case constant = "Constant"
    var id: String { rawValue }

    /// The SceneKit lighting model to apply, or nil to leave the file's own.
    var scnModel: SCNMaterial.LightingModel? {
        switch self {
        case .asLoaded: return nil
        case .physicallyBased: return .physicallyBased
        case .blinn: return .blinn
        case .phong: return .phong
        case .constant: return .constant
        }
    }
}

enum BackgroundStyle: String, CaseIterable, Identifiable {
    case dark = "Dark"
    case light = "Light"
    case checkerboard = "Checkerboard"
    case environment = "Environment"
    var id: String { rawValue }
}

enum ExportFormat {
    case scn, usdz
    var utType: UTType {
        switch self {
        case .scn: return UTType("public.scenekit.scene") ?? .data
        case .usdz: return UTType("com.pixar.universal-scene-description-mobile") ?? .usdz
        }
    }
    var ext: String { self == .scn ? "scn" : "usdz" }
}

struct MeshEntry: Identifiable {
    let id = UUID()
    let node: SCNNode
    let name: String
    let materialSummary: String
    let swatch: Color?
    let isTextured: Bool
    var isHidden: Bool = false
}

@MainActor
final class ViewerState: ObservableObject {
    @Published var scene: SCNScene?
    @Published var fileName: String?
    @Published var fileURL: URL?
    @Published var errorMessage: String?
    @Published var statistics: ModelStatistics?
    @Published var recentFiles: [URL] = []

    @Published var displayMode: DisplayMode = .shaded { didSet { applyDisplayMode() } }
    @Published var lightingPreset: LightingPreset = .studio { didSet { applyLighting() } }
    @Published var backgroundStyle: BackgroundStyle = .dark { didSet { applyBackground() } }
    @Published var showBoundingBox = false { didSet { refreshDebugOptions() } }
    @Published var showWireframeOverlay = false { didSet { refreshDebugOptions() } }
    @Published var showAxes = false { didSet { applyAxes() } }
    @Published var showNormals = false { didSet { applyNormals() } }
    @Published var showBackfaces = true { didSet { applyCulling() } }
    @Published var showLights = false { didSet { applyLightMarkers() } }
    @Published var autoRotate = false

    // Material overrides. Applied to the loaded model's materials only when the
    // user changes a slider, so file-authored materials are kept until touched.
    // Blinn/Phong materials use specular + shininess; physically based materials
    // use metalness + roughness. We set all four; SceneKit ignores the ones that
    // don't apply to a given lighting model.
    @Published var lightingModelOption: LightingModelOption = .asLoaded { didSet { applyMaterialOverrides() } }
    @Published var specularIntensity: Double = 0.5 { didSet { applyMaterialOverrides() } }
    @Published var shininess: Double = 0.25 { didSet { applyMaterialOverrides() } }
    @Published var metalness: Double = 0.0 { didSet { applyMaterialOverrides() } }
    @Published var roughness: Double = 0.5 { didSet { applyMaterialOverrides() } }

    /// The lighting model each loaded material had on import, keyed by material,
    /// so the "As Loaded" option can restore it.
    private var originalLightingModels: [ObjectIdentifier: SCNMaterial.LightingModel] = [:]

    /// Global color-management preference. When true, SceneKit's linear-space
    /// workflow is disabled so colors are lit/displayed in gamma space, matching
    /// legacy non-sRGB OpenGL renderers. SceneKit reads this key once at init,
    /// so a change only takes effect after the app restarts.
    static let disableLinearKey = "SCNDisableLinearSpaceRendering"
    @Published var disableLinearRendering = UserDefaults.standard.bool(forKey: ViewerState.disableLinearKey)

    @Published var debugOptions: SCNDebugOptions = []
    @Published var backgroundContents: Any?

    @Published var cameraNames: [String] = []
    @Published var selectedCameraName: String?

    @Published var hasAnimation = false
    @Published var isPlaying = false
    @Published var sceneDuration: TimeInterval = 0
    @Published var sceneTime: TimeInterval = 0

    @Published var measurementMode = false {
        didSet { if !measurementMode { clearMeasurement() } }
    }
    @Published var measurementDistance: Double?

    @Published var meshNodes: [MeshEntry] = []
    @Published var environmentURL: URL?

    weak var viewport: SceneViewportCoordinator?

    var modelNodes: [SCNNode] = []
    var modelBoundingRadius: CGFloat = 1
    var modelCenter: SCNVector3 = SCNVector3Zero
    private var pointGeometryCache: [ObjectIdentifier: (original: SCNGeometry, points: SCNGeometry)] = [:]

    private let recentsKey = "RecentFiles.v1"
    static let supportedExtensions = ["scn", "dae", "obj", "usd", "usdz", "usda", "usdc", "abc", "ply", "stl"]
    static let supportedTypes: [UTType] = supportedExtensions.compactMap { UTType(filenameExtension: $0) }

    init() { loadRecents() }

    // MARK: - Loading

    func load(url: URL) {
        errorMessage = nil
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            errorMessage = "Unsupported file type: .\(ext)"
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let loaded: SCNScene
            switch ext {
            case "obj", "ply", "stl":
                let asset = MDLAsset(url: url)
                asset.loadTextures()
                loaded = SCNScene(mdlAsset: asset)
            default:
                loaded = try SCNScene(url: url, options: [
                    .checkConsistency: true,
                    .createNormalsIfAbsent: true
                ])
            }
            adopt(scene: loaded, url: url)
            addRecent(url)
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    private func adopt(scene loaded: SCNScene, url: URL) {
        pointGeometryCache.removeAll()
        modelNodes = loaded.rootNode.childNodes

        let (center, radius) = SceneHelpers.bounds(of: modelNodes)
        modelCenter = center
        modelBoundingRadius = radius
        SceneHelpers.installCamera(in: loaded, center: center, radius: radius)

        scene = loaded
        fileName = url.lastPathComponent
        fileURL = url

        // Record originals so "As Loaded" can restore them, but don't apply the
        // slider overrides here — leave the file's authored materials intact
        // until the user actually changes a material control.
        captureOriginalLightingModels()
        applyLighting()
        applyBackground()
        applyDisplayMode()
        applyAxes()
        applyNormals()
        applyCulling()
        applyLightMarkers()
        refreshDebugOptions()

        cameraNames = SceneHelpers.cameraNames(in: loaded)
        selectedCameraName = SceneHelpers.autoCameraName

        sceneDuration = SceneHelpers.animationDuration(in: loaded)
        hasAnimation = sceneDuration > 0
        isPlaying = false
        sceneTime = 0

        meshNodes = SceneHelpers.meshEntries(from: modelNodes)
        statistics = GeometryAnalysis.statistics(for: modelNodes)

        measurementMode = false
        measurementDistance = nil
    }

    func clear() {
        scene = nil
        fileName = nil
        fileURL = nil
        errorMessage = nil
        statistics = nil
        modelNodes = []
        meshNodes = []
        cameraNames = []
        selectedCameraName = nil
        hasAnimation = false
        isPlaying = false
        sceneDuration = 0
        sceneTime = 0
        measurementMode = false
        measurementDistance = nil
        pointGeometryCache.removeAll()
    }

    // MARK: - File pickers

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.supportedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose a 3D model file"
        if panel.runModal() == .OK, let url = panel.url {
            load(url: url)
        }
    }

    func loadEnvironment() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an environment image (HDR / EXR / JPG / PNG)"
        if panel.runModal() == .OK, let url = panel.url {
            environmentURL = url
            if let img = NSImage(contentsOf: url) {
                scene?.lightingEnvironment.contents = img
                lightingPreset = .environment
                backgroundStyle = .environment
            }
        }
    }

    // MARK: - Display / lighting / background

    private func applyDisplayMode() {
        guard scene != nil else { return }
        for node in modelNodes {
            node.enumerateHierarchy { n, _ in
                guard let geometry = n.geometry,
                      !(n.name?.hasPrefix(SceneHelpers.prefix) ?? false) else { return }
                let key = ObjectIdentifier(n)
                if pointGeometryCache[key] == nil {
                    pointGeometryCache[key] = (geometry, SceneHelpers.pointGeometry(from: geometry))
                }
                guard let pair = pointGeometryCache[key] else { return }
                switch displayMode {
                case .shaded, .shadedWireframe:
                    n.geometry = pair.original
                    pair.original.materials.forEach { $0.fillMode = .fill }
                case .wireframe:
                    n.geometry = pair.original
                    pair.original.materials.forEach { $0.fillMode = .lines }
                case .points:
                    n.geometry = pair.points
                }
            }
        }
        refreshDebugOptions()
    }

    private func applyLighting() {
        guard let scene else { return }
        SceneHelpers.applyLighting(lightingPreset, to: scene, radius: modelBoundingRadius, center: modelCenter)
        if lightingPreset != .environment {
            scene.lightingEnvironment.contents = nil
        } else if let url = environmentURL, let img = NSImage(contentsOf: url) {
            scene.lightingEnvironment.contents = img
        }
        // Light positions change with the preset, so refresh any visible markers.
        applyLightMarkers()
    }

    private func applyLightMarkers() {
        guard let scene else { return }
        SceneHelpers.setLightMarkers(showLights, in: scene, radius: modelBoundingRadius)
    }

    private func applyBackground() {
        // Compute the background even when no scene is loaded, so the empty-state
        // backdrop (see `backdropColor`) tracks the selected theme too.
        switch backgroundStyle {
        case .dark:
            backgroundContents = NSColor(calibratedWhite: 0.09, alpha: 1)
        case .light:
            backgroundContents = NSColor(calibratedWhite: 0.93, alpha: 1)
        case .checkerboard:
            backgroundContents = SceneHelpers.checkerboardImage()
        case .environment:
            if let url = environmentURL, let img = NSImage(contentsOf: url) {
                backgroundContents = img
            } else {
                backgroundContents = NSColor(calibratedWhite: 0.09, alpha: 1)
            }
        }
        scene?.background.contents = backgroundContents
    }

    /// Solid backdrop color for the detail view behind the viewport / drop
    /// prompt. With no model loaded there's no scene background to show, so the
    /// backdrop follows the system light/dark appearance to match the app
    /// chrome. Once a model is loaded it mirrors the selected background theme
    /// (image themes fall back to neutral dark so the model stays legible).
    var backdropColor: Color {
        guard scene != nil else {
            return Color(nsColor: .windowBackgroundColor)
        }
        switch backgroundStyle {
        case .light: return Color(white: 0.93)
        default: return Color(white: 0.09)
        }
    }

    private func refreshDebugOptions() {
        var options: SCNDebugOptions = []
        if showBoundingBox { options.insert(.showBoundingBoxes) }
        if showWireframeOverlay || displayMode == .shadedWireframe {
            options.insert(.showWireframe)
        }
        debugOptions = options
    }

    private func applyAxes() {
        guard let scene else { return }
        SceneHelpers.setAxes(showAxes, in: scene, radius: modelBoundingRadius, center: modelCenter)
    }

    private func applyNormals() {
        guard let scene else { return }
        SceneHelpers.setNormals(showNormals, in: scene, modelNodes: modelNodes, radius: modelBoundingRadius)
    }

    /// When `showBackfaces` is on, render both sides of every face (cullMode is
    /// effectively disabled); otherwise fall back to SceneKit's default back-face
    /// culling. Viewer-added helper nodes (prefixed) are left untouched.
    private func applyCulling() {
        for node in modelNodes {
            node.enumerateHierarchy { n, _ in
                guard let geometry = n.geometry,
                      !(n.name?.hasPrefix(SceneHelpers.prefix) ?? false) else { return }
                geometry.materials.forEach { $0.isDoubleSided = showBackfaces }
            }
        }
    }

    // MARK: - Color management

    /// Persists the requested linear/gamma setting and relaunches the app, since
    /// SceneKit only reads `SCNDisableLinearSpaceRendering` at startup. Returns
    /// without relaunching if the value already matches what's stored.
    func setDisableLinearRendering(_ disabled: Bool) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.disableLinearKey) != disabled else { return }
        defaults.set(disabled, forKey: Self.disableLinearKey)
        defaults.synchronize()
        relaunchApp()
    }

    private func relaunchApp() {
        let url = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
        let task = Process()
        // Re-exec the same binary (works for both a bundled .app and `swift run`).
        if Bundle.main.bundleURL.pathExtension == "app" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", Bundle.main.bundleURL.path]
        } else {
            task.executableURL = url
            task.arguments = Array(CommandLine.arguments.dropFirst())
        }
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Materials

    /// The lighting model the sliders will actually affect: the picker's choice,
    /// or — for "As Loaded" — the model the loaded materials were imported with
    /// (first captured material; nil if nothing loaded yet).
    var effectiveLightingModel: SCNMaterial.LightingModel? {
        if let forced = lightingModelOption.scnModel { return forced }
        return originalLightingModels.values.first
    }

    /// Whether specular/shininess apply under the effective lighting model.
    var specularControlsActive: Bool {
        let m = effectiveLightingModel
        return m == .blinn || m == .phong
    }

    /// Whether metalness/roughness apply under the effective lighting model.
    var pbrControlsActive: Bool {
        effectiveLightingModel == .physicallyBased
    }

    /// Applies the lighting-model override and property sliders to every loaded
    /// mesh material, skipping viewer-added helper nodes. `shininess` maps to a
    /// usable Phong exponent; specular/metalness/roughness map straight through
    /// (0...1). Specular/shininess only take effect on Blinn/Phong materials;
    /// metalness/roughness only on physically based ones — so use the Lighting
    /// Model picker to choose which set is live.
    private func applyMaterialOverrides() {
        let specular = NSColor(calibratedWhite: specularIntensity, alpha: 1)
        let phongShininess = shininess * 50.0   // 0...50, a sensible highlight range
        for node in modelNodes {
            node.enumerateHierarchy { n, _ in
                guard let geometry = n.geometry,
                      !(n.name?.hasPrefix(SceneHelpers.prefix) ?? false) else { return }
                for material in geometry.materials {
                    // Lighting model: override, or restore the file's original.
                    if let forced = lightingModelOption.scnModel {
                        material.lightingModel = forced
                    } else if let original = originalLightingModels[ObjectIdentifier(material)] {
                        material.lightingModel = original
                    }
                    material.specular.contents = specular
                    material.shininess = CGFloat(phongShininess)
                    material.metalness.contents = metalness
                    material.roughness.contents = roughness
                }
            }
        }
    }

    /// Records each material's lighting model at load time so "As Loaded" can
    /// restore it after the user has forced a different model.
    private func captureOriginalLightingModels() {
        originalLightingModels.removeAll()
        for node in modelNodes {
            node.enumerateHierarchy { n, _ in
                guard let geometry = n.geometry,
                      !(n.name?.hasPrefix(SceneHelpers.prefix) ?? false) else { return }
                for material in geometry.materials {
                    originalLightingModels[ObjectIdentifier(material)] = material.lightingModel
                }
            }
        }
    }

    // MARK: - Camera

    func resetCamera() {
        guard let scene else { return }
        SceneHelpers.installCamera(in: scene, center: modelCenter, radius: modelBoundingRadius)
        selectedCameraName = SceneHelpers.autoCameraName
        viewport?.applyCamera(named: SceneHelpers.autoCameraName)
    }

    // MARK: - Measurement

    private func clearMeasurement() {
        measurementDistance = nil
        viewport?.clearMeasurement()
    }

    // MARK: - Snapshot

    func saveSnapshot() {
        guard let image = viewport?.snapshot() else {
            errorMessage = "Nothing to capture"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = (fileName.map { ($0 as NSString).deletingPathExtension } ?? "snapshot") + ".png"
        if panel.runModal() == .OK, let url = panel.url {
            guard let data = Self.pngData(from: image) else {
                errorMessage = "Could not encode PNG"
                return
            }
            do { try data.write(to: url) }
            catch { errorMessage = "Save failed: \(error.localizedDescription)" }
        }
    }

    func copySnapshot() {
        guard let image = viewport?.snapshot() else {
            errorMessage = "Nothing to capture"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Export

    func export(as format: ExportFormat) {
        guard !modelNodes.isEmpty else {
            errorMessage = "No model to export"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        let base = fileName.map { ($0 as NSString).deletingPathExtension } ?? "model"
        panel.nameFieldStringValue = "\(base).\(format.ext)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let exportScene = SceneHelpers.cleanCopy(of: modelNodes)
        let ok = exportScene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
        if !ok { errorMessage = "Export failed" }
    }

    func exportTurntable() {
        guard viewport != nil, scene != nil else {
            errorMessage = "No model to record"
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        let base = fileName.map { ($0 as NSString).deletingPathExtension } ?? "turntable"
        panel.nameFieldStringValue = "\(base).gif"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        viewport?.exportTurntableGIF(to: url, frames: 48) { [weak self] ok in
            if !ok { self?.errorMessage = "Turntable export failed" }
        }
    }

    // MARK: - Recent files

    private func loadRecents() {
        let paths = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
        recentFiles = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addRecent(_ url: URL) {
        var list = recentFiles.filter { $0.standardizedFileURL != url.standardizedFileURL }
        list.insert(url.standardizedFileURL, at: 0)
        if list.count > 10 { list = Array(list.prefix(10)) }
        recentFiles = list
        UserDefaults.standard.set(list.map { $0.path }, forKey: recentsKey)
    }

    func clearRecents() {
        recentFiles = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }
}
