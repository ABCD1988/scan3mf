import Foundation
import simd
import ARKit

/// 把 ARKit 的 ARMeshAnchor 集合拼成一个统一网格（世界坐标系，单位为米）
enum MeshBuilder {

    static func build(from anchors: [ARMeshAnchor]) -> MeshData {
        var mesh = MeshData()

        for anchor in anchors {
            append(anchor, into: &mesh)
        }

        return mesh
    }

    // MARK: - 单个锚点展开

    private static func append(_ anchor: ARMeshAnchor, into mesh: inout MeshData) {
        let geometry = anchor.geometry
        let transform = anchor.transform
        let baseIndex = UInt32(mesh.vertices.count)

        // --- 顶点 ---
        let vSource = geometry.vertices
        let vCount = vSource.count
        // ARGeometryElement 没有 stride；顶点是 3×Float32，固定 12 字节
        let vStride = MemoryLayout<Float>.stride * 3
        let vRaw = vSource.buffer.contents()

        mesh.vertices.reserveCapacity(mesh.vertices.count + vCount)
        for i in 0..<vCount {
            let ptr = vRaw.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
            let local = SIMD3<Float>(ptr[0], ptr[1], ptr[2])
            // 局部 → 世界
            let world = transform * SIMD4<Float>(local, 1)
            mesh.vertices.append(SIMD3<Float>(world.x, world.y, world.z))
        }

        // --- 索引 ---
        let fSource = geometry.faces
        let fCount = fSource.count
        let indexCount = fSource.indexCountPerPrimitive   // 3
        let bytesPerIndex = fSource.bytesPerIndex
        let fStride = indexCount * bytesPerIndex
        let fRaw = fSource.buffer.contents()

        mesh.indices.reserveCapacity(mesh.indices.count + fCount * indexCount)

        if bytesPerIndex == 4 {
            for f in 0..<fCount {
                let ptr = fRaw.advanced(by: f * fStride).assumingMemoryBound(to: UInt32.self)
                for k in 0..<indexCount {
                    mesh.indices.append(ptr[k] + baseIndex)
                }
            }
        } else if bytesPerIndex == 2 {
            for f in 0..<fCount {
                let ptr = fRaw.advanced(by: f * fStride).assumingMemoryBound(to: UInt16.self)
                for k in 0..<indexCount {
                    mesh.indices.append(UInt32(ptr[k]) + baseIndex)
                }
            }
        }
    }

    /// 估算若干锚点覆盖的表面积（米²）——用于覆盖率进度
    static func surfaceArea(of anchors: [ARMeshAnchor]) -> Float {
        var sum: Float = 0
        for anchor in anchors {
            let geometry = anchor.geometry
            let vSource = geometry.vertices
            let vCount = vSource.count
            let vStride = MemoryLayout<Float>.stride * 3
            let vRaw = vSource.buffer.contents()

            var local: [SIMD3<Float>] = []
            local.reserveCapacity(vCount)
            for i in 0..<vCount {
                let ptr = vRaw.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
                local.append(SIMD3<Float>(ptr[0], ptr[1], ptr[2]))
            }

            let fSource = geometry.faces
            let fCount = fSource.count
            let indexCount = fSource.indexCountPerPrimitive
            let bytesPerIndex = fSource.bytesPerIndex
            let fStride = indexCount * bytesPerIndex
            let fRaw = fSource.buffer.contents()

            for f in 0..<fCount {
                var ids: [UInt32] = []
                if bytesPerIndex == 4 {
                    let ptr = fRaw.advanced(by: f * fStride).assumingMemoryBound(to: UInt32.self)
                    for k in 0..<indexCount { ids.append(ptr[k]) }
                } else {
                    let ptr = fRaw.advanced(by: f * fStride).assumingMemoryBound(to: UInt16.self)
                    for k in 0..<indexCount { ids.append(UInt32(ptr[k])) }
                }
                guard ids.count == 3,
                      Int(ids[0]) < local.count,
                      Int(ids[1]) < local.count,
                      Int(ids[2]) < local.count else { continue }
                let a = local[Int(ids[0])], b = local[Int(ids[1])], c = local[Int(ids[2])]
                sum += simd_length(simd_cross(b - a, c - a)) * 0.5
            }
        }
        return sum
    }
}
