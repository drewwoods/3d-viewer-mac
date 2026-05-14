import Cocoa
import Quartz
import SceneKit
import ModelIO
import SceneKit.ModelIO

// Quick Look preview for 3D model files.
//
// This file is NOT part of the SwiftPM executable — SwiftPM cannot build app
// extensions. Add it to an Xcode "Quick Look Preview Extension" target embedded
// in the host app. See QuickLookExtension/README.md for setup steps.
class PreviewViewController: NSViewController, QLPreviewingController {

    private let sceneView = SCNView()

    override func loadView() {
        sceneView.autoenablesDefaultLighting = true
        sceneView.allowsCameraControl = true
        sceneView.antialiasingMode = .multisampling4X
        sceneView.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 1)
        view = sceneView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        let ext = url.pathExtension.lowercased()
        let scene: SCNScene
        if ["obj", "ply", "stl"].contains(ext) {
            let asset = MDLAsset(url: url)
            asset.loadTextures()
            scene = SCNScene(mdlAsset: asset)
        } else {
            scene = try SCNScene(url: url, options: [.createNormalsIfAbsent: true])
        }
        frameCamera(in: scene)
        scene.background.contents = NSColor(calibratedWhite: 0.1, alpha: 1)
        await MainActor.run {
            sceneView.scene = scene
        }
    }

    private func frameCamera(in scene: SCNScene) {
        var minV = SCNVector3(CGFloat.greatestFiniteMagnitude,
                              CGFloat.greatestFiniteMagnitude,
                              CGFloat.greatestFiniteMagnitude)
        var maxV = SCNVector3(-CGFloat.greatestFiniteMagnitude,
                              -CGFloat.greatestFiniteMagnitude,
                              -CGFloat.greatestFiniteMagnitude)
        var found = false
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            let (lmin, lmax) = node.boundingBox
            let m = node.worldTransform
            for corner in [SCNVector3(lmin.x, lmin.y, lmin.z),
                           SCNVector3(lmax.x, lmax.y, lmax.z),
                           SCNVector3(lmin.x, lmax.y, lmin.z),
                           SCNVector3(lmax.x, lmin.y, lmax.z)] {
                let w = SCNVector3(
                    m.m11 * corner.x + m.m21 * corner.y + m.m31 * corner.z + m.m41,
                    m.m12 * corner.x + m.m22 * corner.y + m.m32 * corner.z + m.m42,
                    m.m13 * corner.x + m.m23 * corner.y + m.m33 * corner.z + m.m43
                )
                found = true
                minV.x = min(minV.x, w.x); minV.y = min(minV.y, w.y); minV.z = min(minV.z, w.z)
                maxV.x = max(maxV.x, w.x); maxV.y = max(maxV.y, w.y); maxV.z = max(maxV.z, w.z)
            }
        }
        guard found else { return }
        let center = SCNVector3((minV.x + maxV.x) / 2, (minV.y + maxV.y) / 2, (minV.z + maxV.z) / 2)
        let dx = maxV.x - minV.x, dy = maxV.y - minV.y, dz = maxV.z - minV.z
        let radius = max(sqrt(dx * dx + dy * dy + dz * dz) / 2, 0.001)
        let distance = radius * 2.8

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true
        cameraNode.position = SCNVector3(center.x + distance * 0.55,
                                         center.y + distance * 0.42,
                                         center.z + distance * 0.9)
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)
    }
}
