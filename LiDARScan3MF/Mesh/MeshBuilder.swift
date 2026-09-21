import Foundation
import simd
import ARKit

/// 把 ARKit 的 ARMeshAnchor 集合拼成一个统一网格（世界坐标系，单位为米）
///
/// - center / radius：给定时只保留"三个顶点都落在球内"的三角形，用于物体模式剔除远处的墙、地
enum MeshBuilder {

    static func build(from anchors: [ARMeshAnchor]) -> MeshData {
        build(from: anchors, center: nil, radius: 0)
    }

    static func build(from anchors: [ARMeshAnchor], center: SIMD3<Float>?, radius: Float) -> MeshData {
        var mesh = MeshData()
        let crop = (center != nil) && radius > 0
        for anchor in anchors {
            append(anchor, into: &mesh, center: crop ? center : nil, radius: radius)
        }
        return mesh
    }

    // MARK: - 单个锚点展开

    private static func append(_ anchor: ARMeshAnchor,
                               into mesh: inout MeshData,
                               center: SIMD3<Float>?,
                               radius: Float) {
        let geometry = anchor.geometry
        let transform = anchor.transform

        // --- 顶点：局部 → 世界 ---
        let vSource = geometry.vertices
        let vCount = vSource.count
        // ARGeometryElement 没有 stride；顶点是 3×Float32，固定 12 字节
        let vStride = MemoryLayout<Float>.stride * 3
        let vRaw = vSource.buffer.contents()

        var world: [SIMD3<Float>] = []
        world.reserveCapacity(vCount)
        for i in 0..<vCount {
            let ptr = vRaw.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
            let local = SIMD4<Float>(ptr[0], ptr[1], ptr[2], 1)
            let w = transform * local
            world.append(SIMD3<Float>(w.x, w.y, w.z))
        }

        // --- 索引 ---
        let fSource = geometry.faces
        let fCount = fSource.count
        let indexCount = fSource.indexCountPerPrimitive   // 3
        let bytesPerIndex = fSource.bytesPerIndex
        let fStride = indexCount * bytesPerIndex
        let fRaw = fSource.buffer.contents()
        guard bytesPerIndex == 4 || bytesPerIndex == 2 else { return }

        // 局部索引 → 全局索引（只登记真正被用到的顶点，避免留一堆孤立点）
        var localToGlobal = [UInt32: UInt32]()
        localToGlobal.reserveCapacity(vCount)

        let radius2 = radius * radius

        for f in 0..<fCount {
            var ids: [UInt32] = []
            ids.reserveCapacity(3)
            if bytesPerIndex == 4 {
                let ptr = fRaw.advanced(by: f * fStride).assumingMemoryBound(to: UInt32.self)
                for k in 0..<indexCount { ids.append(ptr[k]) }
            } else {
                let ptr = fRaw.advanced(by: f * fStride).assumingMemoryBound(to: UInt16.self)
                for k in 0..<indexCount { ids.append(UInt32(ptr[k])) }
            }
            guard ids.count == 3,
                  Int(ids[0]) < world.count,
                  Int(ids[1]) < world.count,
                  Int(ids[2]) < world.count else { continue }

            // 距离裁剪：三个顶点必须都在球内
            if let c = center {
                let a = world[Int(ids[0])], b = world[Int(ids[1])], d = world[Int(ids[2])]
                if simd_distance_squared(a, c) > radius2 { continue }
                if simd_distance_squared(b, c) > radius2 { continue }
                if simd_distance_squared(d, c) > radius2 { continue }
            }

            for local in ids {
                if let g = localToGlobal[local] {
                    mesh.indices.append(g)
                } else {
                    let g = UInt32(mesh.vertices.count)
                    localToGlobal[local] = g
                    mesh.vertices.append(world[Int(local)])
                    mesh.indices.append(g)
                }
            }
        }
    }

    /// 估算若干锚点在指定球内的表面积（米²）——用于覆盖率进度
    static func surfaceArea(of anchors: [ARMeshAnchor]) -> Float {
        surfaceArea(of: anchors, center: nil, radius: 0)
    }

    static func surfaceArea(of anchors: [ARMeshAnchor], center: SIMD3<Float>?, radius: Float) -> Float {
        var sum: Float = 0
        let crop = (center != nil) && radius > 0
        let radius2 = radius * radius

        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let vSource = geometry.vertices
            let vCount = vSource.count
            let vStride = MemoryLayout<Float>.stride * 3
            let vRaw = vSource.buffer.contents()

            var local: [SIMD3<Float>] = []
            local.reserveCapacity(vCount)
            for i in 0..<vCount {
                let ptr = vRaw.advanced(by: i * vStride).assumingMemoryBound(to: Float.self)
                let w = transform * SIMD4<Float>(ptr[0], ptr[1], ptr[2], 1)
                local.append(SIMD3<Float>(w.x, w.y, w.z))
            }

            let fSource = geometry.faces
            let fCount = fSource.count
            let indexCount = fSource.indexCountPerPrimitive
            let bytesPerIndex = fSource.bytesPerIndex
            let fStride = indexCount * bytesPerIndex
            let fRaw = fSource.buffer.contents()
            guard bytesPerIndex == 4 || bytesPerIndex == 2 else { continue }

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

                if crop, let c = center {
                    let a = local[Int(ids[0])], b = local[Int(ids[1])], d = local[Int(ids[2])]
                    if simd_distance_squared(a, c) > radius2 { continue }
                    if simd_distance_squared(b, c) > radius2 { continue }
                    if simd_distance_squared(d, c) > radius2 { continue }
                }

                let a = local[Int(ids[0])], b = local[Int(ids[1])], c = local[Int(ids[2])]
                sum += simd_length(simd_cross(b - a, c - a)) * 0.5
            }
        }
        return sum
    }
}
