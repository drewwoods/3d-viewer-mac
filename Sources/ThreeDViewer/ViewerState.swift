import Foundation
import SwiftUI
import SceneKit
import ModelIO
import SceneKit.ModelIO
import AppKit
import UniformTypeIdentifiers

@MainActor
final class ViewerState: ObservableObject {
    @Published var scene: SCNScene?
    @Published var fileName: String?
    @Published var errorMessage: String?
    @Published var statistics: ModelStatistics?

    static let supportedExtensions: [String] = [
        "scn", "dae", "obj", "usd", "usdz", "usda", "usdc", "abc", "ply", "stl"
    ]

    static let supportedTypes: [UTType] = {
        var types: [UTType] = []
        for ext in supportedExtensions {
            if let t = UTType(filenameExtension: ext) {
                types.append(t)
            }
        }
        return types
    }()

    func load(url: URL) {
        errorMessage = nil
        let ext = url.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else {
            errorMessage = "Unsupported file type: .\(ext)"
            return
        }

        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }

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
            SceneFramer.frame(scene: loaded)
            self.statistics = ModelStatistics.compute(from: loaded)
            self.scene = loaded
            self.fileName = url.lastPathComponent
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
    }

    func clear() {
        scene = nil
        fileName = nil
        errorMessage = nil
        statistics = nil
    }

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
}

struct ModelStatistics {
    let nodeCount: Int
    let meshCount: Int
    let vertexCount: Int
    let triangleCount: Int

    static func compute(from scene: SCNScene) -> ModelStatistics {
        var nodes = 0
        var meshes = 0
        var vertices = 0
        var triangles = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            nodes += 1
            guard let geometry = node.geometry else { return }
            meshes += 1
            for source in geometry.sources where source.semantic == .vertex {
                vertices += source.vectorCount
            }
            for element in geometry.elements {
                switch element.primitiveType {
                case .triangles: triangles += element.primitiveCount
                case .triangleStrip: triangles += element.primitiveCount
                default: break
                }
            }
        }
        return ModelStatistics(
            nodeCount: nodes,
            meshCount: meshes,
            vertexCount: vertices,
            triangleCount: triangles
        )
    }
}

enum SceneFramer {
    static func frame(scene: SCNScene) {
        let (minVec, maxVec) = scene.rootNode.boundingBox
        let dx = CGFloat(maxVec.x - minVec.x)
        let dy = CGFloat(maxVec.y - minVec.y)
        let dz = CGFloat(maxVec.z - minVec.z)
        let radius = max(sqrt(dx * dx + dy * dy + dz * dz) / 2.0, 0.001)
        let center = SCNVector3(
            (minVec.x + maxVec.x) / 2,
            (minVec.y + maxVec.y) / 2,
            (minVec.z + maxVec.z) / 2
        )

        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 50

        let cameraNode = SCNNode()
        cameraNode.name = "AutoCamera"
        cameraNode.camera = camera
        let distance = radius * 2.6
        cameraNode.position = SCNVector3(
            center.x,
            center.y,
            center.z + CGFloat(distance)
        )
        cameraNode.look(at: center)
        scene.rootNode.addChildNode(cameraNode)

        scene.background.contents = NSColor(calibratedWhite: 0.09, alpha: 1.0)
    }
}
