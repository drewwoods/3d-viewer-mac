import SwiftUI
import SceneKit
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct SceneViewport: NSViewRepresentable {
    @ObservedObject var state: ViewerState

    func makeCoordinator() -> SceneViewportCoordinator {
        SceneViewportCoordinator(state: state)
    }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = true
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.isJitteringEnabled = true
        view.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 1)

        let click = NSClickGestureRecognizer(target: context.coordinator,
                                             action: #selector(SceneViewportCoordinator.handleClick(_:)))
        view.addGestureRecognizer(click)

        context.coordinator.scnView = view
        state.viewport = context.coordinator
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        coordinator.state = state
        state.viewport = coordinator

        if view.scene !== state.scene {
            view.scene = state.scene
            coordinator.measurementPoints.removeAll()
            coordinator.appliedCameraName = nil
            if let scene = state.scene,
               let camera = scene.rootNode.childNode(withName: SceneHelpers.autoCameraName, recursively: true) {
                view.pointOfView = camera
                coordinator.appliedCameraName = SceneHelpers.autoCameraName
            }
        }

        // Only switch cameras when the selection actually changes. Re-asserting
        // pointOfView on every update would clobber the user's orbit/pan/zoom
        // (camera control swaps in its own pointOfView) whenever any unrelated
        // option is toggled. Explicit reselects / Reset go through applyCamera.
        if let name = state.selectedCameraName,
           name != coordinator.appliedCameraName,
           let node = state.scene?.rootNode.childNode(withName: name, recursively: true) {
            view.pointOfView = node
            coordinator.appliedCameraName = name
        }

        view.debugOptions = state.debugOptions
        view.allowsCameraControl = !state.measurementMode

        if let background = state.backgroundContents {
            state.scene?.background.contents = background
        }

        view.loops = true
        if view.isPlaying != state.isPlaying {
            view.isPlaying = state.isPlaying
        }
        if !state.isPlaying {
            view.sceneTime = state.sceneTime
        }

        coordinator.ensurePlaybackTimer()
    }
}

@MainActor
final class SceneViewportCoordinator: NSObject {
    weak var scnView: SCNView?
    var state: ViewerState
    var measurementPoints: [SCNVector3] = []
    /// The camera name currently applied to the view's pointOfView. Tracks
    /// deliberate switches so updateNSView won't re-apply (and reset) the view.
    var appliedCameraName: String?
    private var playbackTimer: Timer?

    init(state: ViewerState) {
        self.state = state
        super.init()
    }

    // MARK: - Playback sync

    func ensurePlaybackTimer() {
        guard playbackTimer == nil else { return }
        playbackTimer = Timer.scheduledTimer(timeInterval: 1.0 / 15.0,
                                             target: self,
                                             selector: #selector(playbackTick),
                                             userInfo: nil,
                                             repeats: true)
    }

    @objc private func playbackTick() {
        guard let view = scnView, view.isPlaying, state.hasAnimation else { return }
        let duration = state.sceneDuration
        let time = duration > 0 ? view.sceneTime.truncatingRemainder(dividingBy: duration) : view.sceneTime
        if abs(time - state.sceneTime) > 0.001 {
            state.sceneTime = time
        }
    }

    // MARK: - Camera

    func applyCamera(named name: String) {
        guard let view = scnView,
              let node = view.scene?.rootNode.childNode(withName: name, recursively: true) else { return }
        view.pointOfView = node
        appliedCameraName = name
    }

    // MARK: - Measurement

    @objc func handleClick(_ recognizer: NSClickGestureRecognizer) {
        guard let view = scnView, state.measurementMode else { return }
        let location = recognizer.location(in: view)
        let options: [SCNHitTestOption: Any] = [
            .boundingBoxOnly: false,
            .ignoreHiddenNodes: true,
            .searchMode: SCNHitTestSearchMode.closest.rawValue
        ]
        let hits = view.hitTest(location, options: options)
        guard let hit = hits.first(where: { !($0.node.name?.hasPrefix(SceneHelpers.prefix) ?? false) }) else { return }
        addMeasurementMarker(at: hit.worldCoordinates)
    }

    private func addMeasurementMarker(at world: SCNVector3) {
        guard let scene = scnView?.scene else { return }
        let container = SceneHelpers.measurementContainer(in: scene)

        if measurementPoints.count >= 2 {
            measurementPoints.removeAll()
            container.childNodes.forEach { $0.removeFromParentNode() }
            state.measurementDistance = nil
        }

        measurementPoints.append(world)
        let markerRadius = max(state.modelBoundingRadius * 0.012, 0.0005)
        let marker = SCNNode(geometry: SCNSphere(radius: markerRadius))
        marker.geometry?.firstMaterial?.diffuse.contents = NSColor.systemOrange
        marker.geometry?.firstMaterial?.lightingModel = .constant
        marker.position = world
        marker.name = SceneHelpers.prefix + "marker"
        container.addChildNode(marker)

        if measurementPoints.count == 2 {
            let line = SceneHelpers.lineNode(from: measurementPoints[0], to: measurementPoints[1])
            container.addChildNode(line)
            state.measurementDistance = Double(distanceBetween(measurementPoints[0], measurementPoints[1]))
        }
    }

    func clearMeasurement() {
        measurementPoints.removeAll()
        guard let scene = scnView?.scene else { return }
        scene.rootNode.childNode(withName: SceneHelpers.prefix + "measure", recursively: false)?
            .childNodes.forEach { $0.removeFromParentNode() }
    }

    // MARK: - Snapshot

    func snapshot() -> NSImage? {
        scnView?.snapshot()
    }

    // MARK: - Turntable GIF

    func exportTurntableGIF(to url: URL, frames: Int, completion: @escaping (Bool) -> Void) {
        guard let view = scnView,
              let camera = view.pointOfView else {
            completion(false)
            return
        }

        let center = state.modelCenter
        let savedTransform = camera.transform
        let dx = camera.position.x - center.x
        let dz = camera.position.z - center.z
        let height = camera.position.y
        let horizontalRadius = max(sqrt(dx * dx + dz * dz), 0.001)

        let gifType = (UTType.gif.identifier) as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, gifType, frames, nil) else {
            completion(false)
            return
        }
        let fileProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        let frameProperties: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: 0.05
            ]
        ]

        for i in 0..<frames {
            let angle = CGFloat(i) / CGFloat(frames) * 2 * .pi
            camera.position = SCNVector3(
                center.x + sin(angle) * horizontalRadius,
                height,
                center.z + cos(angle) * horizontalRadius
            )
            camera.look(at: center)
            let image = view.snapshot()
            if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                CGImageDestinationAddImage(destination, cgImage, frameProperties as CFDictionary)
            }
        }

        camera.transform = savedTransform
        let success = CGImageDestinationFinalize(destination)
        completion(success)
    }
}
