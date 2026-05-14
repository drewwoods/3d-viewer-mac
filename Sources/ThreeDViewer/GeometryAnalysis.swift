import Foundation
import SceneKit

struct ModelStatistics {
    let nodeCount: Int
    let meshCount: Int
    let vertexCount: Int
    let triangleCount: Int
    let surfaceArea: Double
    let volume: Double
}

enum GeometryAnalysis {

    static func statistics(for nodes: [SCNNode]) -> ModelStatistics {
        var nodeCount = 0
        var meshCount = 0
        var vertexCount = 0
        var triangleCount = 0
        var surfaceArea = 0.0
        var signedVolume = 0.0

        for root in nodes {
            root.enumerateHierarchy { node, _ in
                if node.name?.hasPrefix(SceneHelpers.prefix) ?? false { return }
                nodeCount += 1
                guard let geometry = node.geometry else { return }
                meshCount += 1

                for source in geometry.sources where source.semantic == .vertex {
                    vertexCount += source.vectorCount
                }

                guard let vertexSource = geometry.sources(for: .vertex).first else { return }
                let worldMatrix = node.worldTransform
                let verts = readVectors(vertexSource).map { transform($0, worldMatrix) }

                for element in geometry.elements {
                    let indices = readIndices(element)
                    switch element.primitiveType {
                    case .triangles:
                        var i = 0
                        while i + 2 < indices.count {
                            let a = indices[i], b = indices[i + 1], c = indices[i + 2]
                            if a < verts.count, b < verts.count, c < verts.count {
                                triangleCount += 1
                                surfaceArea += triangleArea(verts[a], verts[b], verts[c])
                                signedVolume += signedTetraVolume(verts[a], verts[b], verts[c])
                            }
                            i += 3
                        }
                    case .triangleStrip:
                        var i = 0
                        while i + 2 < indices.count {
                            let a = indices[i], b = indices[i + 1], c = indices[i + 2]
                            if a < verts.count, b < verts.count, c < verts.count {
                                triangleCount += 1
                                surfaceArea += triangleArea(verts[a], verts[b], verts[c])
                                signedVolume += signedTetraVolume(verts[a], verts[b], verts[c])
                            }
                            i += 1
                        }
                    default:
                        break
                    }
                }
            }
        }

        return ModelStatistics(
            nodeCount: nodeCount,
            meshCount: meshCount,
            vertexCount: vertexCount,
            triangleCount: triangleCount,
            surfaceArea: surfaceArea,
            volume: abs(signedVolume)
        )
    }

    // MARK: - Geometry buffer readers

    static func readVectors(_ source: SCNGeometrySource) -> [SCNVector3] {
        let count = source.vectorCount
        let stride = source.dataStride
        let offset = source.dataOffset
        let bytesPerComponent = source.bytesPerComponent
        var result: [SCNVector3] = []
        result.reserveCapacity(count)

        source.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            for i in 0..<count {
                let p = base + i * stride + offset
                if bytesPerComponent == 4 {
                    let x = p.loadUnaligned(as: Float.self)
                    let y = (p + 4).loadUnaligned(as: Float.self)
                    let z = (p + 8).loadUnaligned(as: Float.self)
                    result.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
                } else if bytesPerComponent == 8 {
                    let x = p.loadUnaligned(as: Double.self)
                    let y = (p + 8).loadUnaligned(as: Double.self)
                    let z = (p + 16).loadUnaligned(as: Double.self)
                    result.append(SCNVector3(CGFloat(x), CGFloat(y), CGFloat(z)))
                } else {
                    result.append(SCNVector3Zero)
                }
            }
        }
        return result
    }

    static func readIndices(_ element: SCNGeometryElement) -> [Int] {
        let count = element.primitiveCount
        let perPrimitive: Int
        switch element.primitiveType {
        case .triangles: perPrimitive = 3
        case .triangleStrip: perPrimitive = count > 0 ? count + 2 : 0
        case .line: perPrimitive = 2
        case .point: perPrimitive = 1
        case .polygon: perPrimitive = 0
        @unknown default: perPrimitive = 3
        }
        let total = element.primitiveType == .triangleStrip ? perPrimitive : count * perPrimitive
        guard total > 0 else { return [] }
        let bytesPerIndex = element.bytesPerIndex
        var result: [Int] = []
        result.reserveCapacity(total)

        element.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let available = raw.count / max(bytesPerIndex, 1)
            let n = min(total, available)
            for i in 0..<n {
                let p = base + i * bytesPerIndex
                switch bytesPerIndex {
                case 1: result.append(Int(p.loadUnaligned(as: UInt8.self)))
                case 2: result.append(Int(p.loadUnaligned(as: UInt16.self)))
                case 4: result.append(Int(p.loadUnaligned(as: UInt32.self)))
                case 8: result.append(Int(p.loadUnaligned(as: UInt64.self)))
                default: break
                }
            }
        }
        return result
    }

    // MARK: - Math

    static func transform(_ p: SCNVector3, _ m: SCNMatrix4) -> SCNVector3 {
        SCNVector3(
            m.m11 * p.x + m.m21 * p.y + m.m31 * p.z + m.m41,
            m.m12 * p.x + m.m22 * p.y + m.m32 * p.z + m.m42,
            m.m13 * p.x + m.m23 * p.y + m.m33 * p.z + m.m43
        )
    }

    private static func triangleArea(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) -> Double {
        let ux = Double(b.x - a.x), uy = Double(b.y - a.y), uz = Double(b.z - a.z)
        let vx = Double(c.x - a.x), vy = Double(c.y - a.y), vz = Double(c.z - a.z)
        let cx = uy * vz - uz * vy
        let cy = uz * vx - ux * vz
        let cz = ux * vy - uy * vx
        return 0.5 * (cx * cx + cy * cy + cz * cz).squareRoot()
    }

    private static func signedTetraVolume(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3) -> Double {
        let ax = Double(a.x), ay = Double(a.y), az = Double(a.z)
        let bx = Double(b.x), by = Double(b.y), bz = Double(b.z)
        let cx = Double(c.x), cy = Double(c.y), cz = Double(c.z)
        return (ax * (by * cz - bz * cy)
              - ay * (bx * cz - bz * cx)
              + az * (bx * cy - by * cx)) / 6.0
    }
}

func distanceBetween(_ a: SCNVector3, _ b: SCNVector3) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y, dz = a.z - b.z
    return sqrt(dx * dx + dy * dy + dz * dz)
}
