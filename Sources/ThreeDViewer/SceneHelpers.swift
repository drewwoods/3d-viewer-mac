import Foundation
import SceneKit
import AppKit
import SwiftUI

enum SceneHelpers {
    static let prefix = "__viewer_"
    static let autoCameraName = "__viewer_camera"

    // MARK: - Bounds

    static func bounds(of nodes: [SCNNode]) -> (center: SCNVector3, radius: CGFloat) {
        var minV = SCNVector3(CGFloat.greatestFiniteMagnitude,
                              CGFloat.greatestFiniteMagnitude,
                              CGFloat.greatestFiniteMagnitude)
        var maxV = SCNVector3(-CGFloat.greatestFiniteMagnitude,
                              -CGFloat.greatestFiniteMagnitude,
                              -CGFloat.greatestFiniteMagnitude)
        var found = false

        for root in nodes {
            root.enumerateHierarchy { node, _ in
                guard node.geometry != nil else { return }
                let (lmin, lmax) = node.boundingBox
                if lmin.x == 0, lmin.y == 0, lmin.z == 0,
                   lmax.x == 0, lmax.y == 0, lmax.z == 0 { return }
                let m = node.worldTransform
                let corners = [
                    SCNVector3(lmin.x, lmin.y, lmin.z), SCNVector3(lmax.x, lmin.y, lmin.z),
                    SCNVector3(lmin.x, lmax.y, lmin.z), SCNVector3(lmax.x, lmax.y, lmin.z),
                    SCNVector3(lmin.x, lmin.y, lmax.z), SCNVector3(lmax.x, lmin.y, lmax.z),
                    SCNVector3(lmin.x, lmax.y, lmax.z), SCNVector3(lmax.x, lmax.y, lmax.z)
                ]
                for c in corners {
                    let w = GeometryAnalysis.transform(c, m)
                    found = true
                    minV.x = min(minV.x, w.x); minV.y = min(minV.y, w.y); minV.z = min(minV.z, w.z)
                    maxV.x = max(maxV.x, w.x); maxV.y = max(maxV.y, w.y); maxV.z = max(maxV.z, w.z)
                }
            }
        }

        guard found else { return (SCNVector3Zero, 1) }
        let center = SCNVector3((minV.x + maxV.x) / 2,
                                (minV.y + maxV.y) / 2,
                                (minV.z + maxV.z) / 2)
        let dx = maxV.x - minV.x, dy = maxV.y - minV.y, dz = maxV.z - minV.z
        let radius = max(sqrt(dx * dx + dy * dy + dz * dz) / 2, 0.001)
        return (center, radius)
    }

    // MARK: - Camera

    static func installCamera(in scene: SCNScene, center: SCNVector3, radius: CGFloat) {
        scene.rootNode.childNode(withName: autoCameraName, recursively: false)?.removeFromParentNode()
        let camera = SCNCamera()
        camera.automaticallyAdjustsZRange = true
        camera.fieldOfView = 50
        let node = SCNNode()
        node.name = autoCameraName
        node.camera = camera
        let distance = radius * 2.8
        node.position = SCNVector3(
            center.x + distance * 0.55,
            center.y + distance * 0.42,
            center.z + distance * 0.9
        )
        node.look(at: center)
        scene.rootNode.addChildNode(node)
    }

    static func cameraNames(in scene: SCNScene) -> [String] {
        var names: [String] = []
        var index = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            guard node.camera != nil else { return }
            if node.name == nil { node.name = "Camera \(index)" }
            index += 1
            if let name = node.name { names.append(name) }
        }
        if let idx = names.firstIndex(of: autoCameraName), idx != 0 {
            names.remove(at: idx)
            names.insert(autoCameraName, at: 0)
        }
        return names
    }

    static func displayName(forCamera name: String) -> String {
        name == autoCameraName ? "Default View" : name
    }

    // MARK: - Animation

    static func animationDuration(in scene: SCNScene) -> TimeInterval {
        var maxDuration: TimeInterval = 0
        scene.rootNode.enumerateHierarchy { node, _ in
            for key in node.animationKeys {
                if let player = node.animationPlayer(forKey: key) {
                    maxDuration = max(maxDuration, player.animation.duration)
                }
            }
        }
        return maxDuration
    }

    // MARK: - Mesh entries

    static func meshEntries(from nodes: [SCNNode]) -> [MeshEntry] {
        var entries: [MeshEntry] = []
        var index = 0
        for root in nodes {
            root.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix(prefix) ?? false { return }
                guard let geometry = node.geometry else { return }
                index += 1
                let name = node.name ?? geometry.name ?? "Mesh \(index)"
                let materials = geometry.materials
                let summary: String
                if materials.isEmpty {
                    summary = "No material"
                } else if materials.count == 1 {
                    summary = materials[0].name ?? "1 material"
                } else {
                    summary = "\(materials.count) materials"
                }
                var swatch: Color?
                var textured = false
                if let first = materials.first {
                    if let color = first.diffuse.contents as? NSColor {
                        swatch = Color(nsColor: color)
                    } else if first.diffuse.contents is NSImage || first.diffuse.contents is URL {
                        textured = true
                    }
                }
                entries.append(MeshEntry(node: node,
                                         name: name,
                                         materialSummary: summary,
                                         swatch: swatch,
                                         isTextured: textured))
            }
        }
        return entries
    }

    // MARK: - Display geometry

    static func pointGeometry(from geometry: SCNGeometry) -> SCNGeometry {
        guard let vertexSource = geometry.sources(for: .vertex).first else { return geometry }
        let count = vertexSource.vectorCount
        let element = SCNGeometryElement(data: nil,
                                         primitiveType: .point,
                                         primitiveCount: count,
                                         bytesPerIndex: MemoryLayout<Int32>.size)
        element.pointSize = 5
        element.minimumPointScreenSpaceRadius = 1.5
        element.maximumPointScreenSpaceRadius = 5
        let result = SCNGeometry(sources: [vertexSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.white
        material.lightingModel = .constant
        result.materials = [material]
        return result
    }

    // MARK: - Lighting

    static func applyLighting(_ preset: LightingPreset, to scene: SCNScene, radius: CGFloat, center: SCNVector3) {
        scene.rootNode.childNode(withName: prefix + "lights", recursively: false)?.removeFromParentNode()
        let rig = SCNNode()
        rig.name = prefix + "lights"
        let d = max(radius, 0.001) * 4

        // Subtle color temperatures so multi-light rigs read as slightly warm
        // key / neutral fill / cool rim rather than flat white.
        let warm = NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.79, alpha: 1)
        let cool = NSColor(calibratedRed: 0.80, green: 0.87, blue: 1.0, alpha: 1)

        func directional(_ intensity: CGFloat, _ color: NSColor, from: SCNVector3) -> SCNNode {
            let light = SCNLight()
            light.type = .directional
            light.intensity = intensity
            light.color = color
            let node = SCNNode()
            node.light = light
            node.position = SCNVector3(center.x + from.x, center.y + from.y, center.z + from.z)
            node.look(at: center)
            return node
        }
        func ambient(_ intensity: CGFloat, _ color: NSColor) -> SCNNode {
            let light = SCNLight()
            light.type = .ambient
            light.intensity = intensity
            light.color = color
            let node = SCNNode()
            node.light = light
            return node
        }

        switch preset {
        case .studio:
            // Warm key, neutral fill, cool back light.
            rig.addChildNode(directional(900, warm, from: SCNVector3(d * 0.7, d * 0.8, d)))
            rig.addChildNode(directional(350, .white, from: SCNVector3(-d, d * 0.2, d * 0.6)))
            rig.addChildNode(directional(500, cool, from: SCNVector3(0, d * 0.4, -d)))
            rig.addChildNode(ambient(250, .white))
        case .threePoint:
            // Warm key (front-right), neutral fill (front-left), cool rim (behind).
            rig.addChildNode(directional(1000, warm, from: SCNVector3(d, d * 0.6, d * 0.8)))
            rig.addChildNode(directional(300, .white, from: SCNVector3(-d * 0.9, d * 0.3, d * 0.7)))
            rig.addChildNode(directional(850, cool, from: SCNVector3(-d * 0.2, d * 0.5, -d)))
            rig.addChildNode(ambient(120, .white))
        case .outdoor:
            rig.addChildNode(directional(1100,
                NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.88, alpha: 1),
                from: SCNVector3(d * 0.5, d, d * 0.4)))
            rig.addChildNode(ambient(600,
                NSColor(calibratedRed: 0.72, green: 0.80, blue: 1.0, alpha: 1)))
        case .topDown:
            // Slight z offset so look(at:) doesn't degenerate when pointing straight down.
            rig.addChildNode(directional(1000, .white, from: SCNVector3(0, d, d * 0.05)))
            rig.addChildNode(ambient(300, .white))
        case .singleKey:
            rig.addChildNode(directional(1000, .white, from: SCNVector3(d * 0.6, d * 0.7, d)))
            rig.addChildNode(ambient(120, .white))
        case .dramatic:
            // One hard low side key, minimal ambient -> deep shadows, high contrast.
            rig.addChildNode(directional(1300, .white, from: SCNVector3(d, d * 0.15, d * 0.3)))
            rig.addChildNode(ambient(30, .white))
        case .flat:
            // High ambient plus a soft front fill -> near shadowless, good for detail.
            rig.addChildNode(directional(250, .white, from: SCNVector3(0, d * 0.3, d)))
            rig.addChildNode(ambient(700, .white))
        case .sunset:
            // Low warm/orange key with a dim purple-blue fill from the opposite side.
            rig.addChildNode(directional(1100,
                NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.28, alpha: 1),
                from: SCNVector3(d, d * 0.18, d * 0.5)))
            rig.addChildNode(directional(300,
                NSColor(calibratedRed: 0.45, green: 0.40, blue: 0.75, alpha: 1),
                from: SCNVector3(-d * 0.8, d * 0.4, -d * 0.4)))
            rig.addChildNode(ambient(160,
                NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.55, alpha: 1)))
        case .moonlight:
            // Cool dim key from above with low blue ambient.
            rig.addChildNode(directional(450,
                NSColor(calibratedRed: 0.62, green: 0.74, blue: 1.0, alpha: 1),
                from: SCNVector3(d * 0.3, d, d * 0.5)))
            rig.addChildNode(ambient(90,
                NSColor(calibratedRed: 0.40, green: 0.50, blue: 0.78, alpha: 1)))
        case .environment:
            rig.addChildNode(ambient(80, .white))
        }
        scene.rootNode.addChildNode(rig)
    }

    // MARK: - Light markers

    /// Places a small constant-shaded sphere at each non-ambient light's
    /// position, tinted to the light's color, so the user can see where the
    /// lights sit. Reads positions from the current light rig; call after
    /// `applyLighting` so the rig exists.
    static func setLightMarkers(_ show: Bool, in scene: SCNScene, radius: CGFloat) {
        scene.rootNode.childNode(withName: prefix + "lightmarkers", recursively: false)?.removeFromParentNode()
        guard show,
              let rig = scene.rootNode.childNode(withName: prefix + "lights", recursively: false) else { return }
        let container = SCNNode()
        container.name = prefix + "lightmarkers"
        let markerRadius = max(radius * 0.04, 0.0005)
        for lightNode in rig.childNodes {
            guard let light = lightNode.light, light.type != .ambient else { continue }
            let sphere = SCNSphere(radius: markerRadius)
            let color = (light.color as? NSColor) ?? .white
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.emission.contents = color
            material.lightingModel = .constant
            sphere.materials = [material]
            let marker = SCNNode(geometry: sphere)
            marker.position = lightNode.position
            container.addChildNode(marker)
        }
        scene.rootNode.addChildNode(container)
    }

    // MARK: - Axes

    static func setAxes(_ show: Bool, in scene: SCNScene, radius: CGFloat, center: SCNVector3) {
        scene.rootNode.childNode(withName: prefix + "axes", recursively: false)?.removeFromParentNode()
        guard show else { return }
        let length = max(radius, 0.001) * 0.7
        let container = SCNNode()
        container.name = prefix + "axes"
        container.position = center

        let xAxis = axisBar(length: length, color: .systemRed)
        xAxis.eulerAngles = SCNVector3(0, 0, -CGFloat.pi / 2)
        let yAxis = axisBar(length: length, color: .systemGreen)
        let zAxis = axisBar(length: length, color: .systemBlue)
        zAxis.eulerAngles = SCNVector3(CGFloat.pi / 2, 0, 0)

        container.addChildNode(xAxis)
        container.addChildNode(yAxis)
        container.addChildNode(zAxis)
        scene.rootNode.addChildNode(container)
    }

    private static func axisBar(length: CGFloat, color: NSColor) -> SCNNode {
        let barRadius = max(length * 0.012, 0.00005)
        let cylinder = SCNCylinder(radius: barRadius, height: length)
        cylinder.firstMaterial?.diffuse.contents = color
        cylinder.firstMaterial?.lightingModel = .constant
        let bar = SCNNode(geometry: cylinder)
        bar.position = SCNVector3(0, length / 2, 0)

        let cone = SCNCone(topRadius: 0, bottomRadius: barRadius * 2.6, height: length * 0.14)
        cone.firstMaterial?.diffuse.contents = color
        cone.firstMaterial?.lightingModel = .constant
        let tip = SCNNode(geometry: cone)
        tip.position = SCNVector3(0, length + length * 0.07, 0)

        let container = SCNNode()
        container.addChildNode(bar)
        container.addChildNode(tip)
        return container
    }

    // MARK: - Normals

    static func setNormals(_ show: Bool, in scene: SCNScene, modelNodes: [SCNNode], radius: CGFloat) {
        scene.rootNode.childNode(withName: prefix + "normals", recursively: false)?.removeFromParentNode()
        guard show else { return }
        let container = SCNNode()
        container.name = prefix + "normals"
        let length = max(radius * 0.03, 0.0001)
        for root in modelNodes {
            root.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix(prefix) ?? false { return }
                guard let geometry = node.geometry,
                      let lines = normalsGeometry(from: geometry, length: length) else { return }
                let child = SCNNode(geometry: lines)
                child.transform = node.worldTransform
                container.addChildNode(child)
            }
        }
        scene.rootNode.addChildNode(container)
    }

    private static func normalsGeometry(from geometry: SCNGeometry, length: CGFloat) -> SCNGeometry? {
        guard let vSource = geometry.sources(for: .vertex).first,
              let nSource = geometry.sources(for: .normal).first else { return nil }
        let verts = GeometryAnalysis.readVectors(vSource)
        let norms = GeometryAnalysis.readVectors(nSource)
        guard !verts.isEmpty, verts.count == norms.count else { return nil }

        var points: [SCNVector3] = []
        points.reserveCapacity(verts.count * 2)
        var indices: [Int32] = []
        indices.reserveCapacity(verts.count * 2)
        for i in 0..<verts.count {
            let p = verts[i]
            let n = norms[i]
            points.append(p)
            points.append(SCNVector3(p.x + n.x * length, p.y + n.y * length, p.z + n.z * length))
            indices.append(Int32(i * 2))
            indices.append(Int32(i * 2 + 1))
        }
        let source = SCNGeometrySource(vertices: points)
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let result = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemTeal
        material.lightingModel = .constant
        result.materials = [material]
        return result
    }

    // MARK: - Backgrounds

    static func checkerboardImage() -> NSImage {
        let size = 512
        let tiles = 16
        let tile = size / tiles
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let light = NSColor(calibratedWhite: 0.30, alpha: 1)
        let dark = NSColor(calibratedWhite: 0.18, alpha: 1)
        for row in 0..<tiles {
            for col in 0..<tiles {
                ((row + col) % 2 == 0 ? light : dark).setFill()
                NSRect(x: col * tile, y: row * tile, width: tile, height: tile).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    // MARK: - Measurement

    static func measurementContainer(in scene: SCNScene) -> SCNNode {
        if let existing = scene.rootNode.childNode(withName: prefix + "measure", recursively: false) {
            return existing
        }
        let node = SCNNode()
        node.name = prefix + "measure"
        scene.rootNode.addChildNode(node)
        return node
    }

    static func lineNode(from a: SCNVector3, to b: SCNVector3) -> SCNNode {
        let source = SCNGeometrySource(vertices: [a, b])
        let element = SCNGeometryElement(indices: [Int32(0), Int32(1)], primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.systemOrange
        material.lightingModel = .constant
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = prefix + "measure_line"
        return node
    }

    // MARK: - Export

    static func cleanCopy(of nodes: [SCNNode]) -> SCNScene {
        let scene = SCNScene()
        for node in nodes {
            scene.rootNode.addChildNode(node.clone())
        }
        return scene
    }
}
