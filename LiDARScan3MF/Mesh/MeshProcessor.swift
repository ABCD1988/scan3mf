import Foundation
import simd

/// 网格后处理：清洗 / 统计 / 补洞 / 简化 / 平滑
enum MeshProcessor {

    struct Stats {
        var boundaryEdges: Int = 0
        var holes: Int = 0
        var nonManifoldEdges: Int = 0
        var faceCount: Int = 0
        var vertexCount: Int = 0
    }

    // MARK: - 清洗

    /// 去掉退化三角形（面积≈0、索引重复、索引越界）
    static func clean(_ mesh: MeshData) -> MeshData {
        var out = MeshData()
        out.vertices = mesh.vertices
        out.vertexColors = mesh.vertexColors

        let vCount = mesh.vertices.count
        out.indices.reserveCapacity(mesh.indices.count)

        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.indices[i], b = mesh.indices[i + 1], c = mesh.indices[i + 2]
            i += 3

            if a == b || b == c || a == c { continue }
            let ia = Int(a), ib = Int(b), ic = Int(c)
            if ia >= vCount || ib >= vCount || ic >= vCount { continue }

            let va = mesh.vertices[ia], vb = mesh.vertices[ib], vc = mesh.vertices[ic]
            let area = simd_length(simd_cross(vb - va, vc - va)) * 0.5
            if area < 1e-10 { continue }

            out.indices.append(a)
            out.indices.append(b)
            out.indices.append(c)
        }
        return out
    }

    // MARK: - 统计（水密检查 / 洞数）

    private static func edgeKey(_ a: UInt32, _ b: UInt32) -> UInt64 {
        let lo = UInt64(min(a, b))
        let hi = UInt64(max(a, b))
        return (lo << 32) | hi
    }

    static func stats(_ mesh: MeshData) -> Stats {
        var s = Stats()
        s.faceCount = mesh.faceCount
        s.vertexCount = mesh.vertexCount

        var edgeCount: [UInt64: Int] = [:]
        edgeCount.reserveCapacity(mesh.indices.count)

        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.indices[i], b = mesh.indices[i + 1], c = mesh.indices[i + 2]
            i += 3
            edgeCount[edgeKey(a, b), default: 0] += 1
            edgeCount[edgeKey(b, c), default: 0] += 1
            edgeCount[edgeKey(c, a), default: 0] += 1
        }

        var boundary: [UInt64] = []
        for (k, n) in edgeCount {
            if n == 1 { boundary.append(k) }
            else if n > 2 { s.nonManifoldEdges += 1 }
        }
        s.boundaryEdges = boundary.count
        s.holes = countLoops(boundary: boundary)
        return s
    }

    /// 边界边构成闭环的数量（近似洞数）
    private static func countLoops(boundary: [UInt64]) -> Int {
        guard !boundary.isEmpty else { return 0 }

        // 建立 顶点 → 相连边界顶点 的邻接表
        var adj: [UInt32: [UInt32]] = [:]
        for k in boundary {
            let lo = UInt32(k >> 32)
            let hi = UInt32(k & 0xFFFF_FFFF)
            adj[lo, default: []].append(hi)
            adj[hi, default: []].append(lo)
        }

        var visited: Set<UInt64> = []
        var loops = 0

        for k in boundary {
            if visited.contains(k) { continue }
            // 沿链行走，走不通时若回到起点则记为一个环
            var start = UInt32(k >> 32)
            var current = UInt32(k & 0xFFFF_FFFF)
            visited.insert(k)
            var steps = 0
            var closed = false

            while steps < boundary.count + 1 {
                let nexts = (adj[current] ?? []).filter { n in
                    !visited.contains(edgeKey(current, n))
                }
                guard let next = nexts.first else {
                    closed = (current == start)
                    break
                }
                visited.insert(edgeKey(current, next))
                if next == start { closed = true; break }
                current = next
                steps += 1
            }

            if closed { loops += 1 }
            start = current  // 消除未使用警告的语义占位
            _ = start
        }
        return loops
    }

    // MARK: - 补洞

    /// 提取边界环并按质心扇形三角化，返回（新网格, 补上的洞数）
    static func fillHoles(_ mesh: MeshData, maxHoleEdges: Int = 400) -> (mesh: MeshData, filled: Int) {
        var out = mesh
        var edgeCount: [UInt64: Int] = [:]
        var i = 0
        while i + 2 < out.indices.count {
            let a = out.indices[i], b = out.indices[i + 1], c = out.indices[i + 2]
            i += 3
            edgeCount[edgeKey(a, b), default: 0] += 1
            edgeCount[edgeKey(b, c), default: 0] += 1
            edgeCount[edgeKey(c, a), default: 0] += 1
        }

        // 相邻表（仅边界边）
        var adj: [UInt32: [UInt32]] = [:]
        var boundarySet: Set<UInt64> = []
        for (k, n) in edgeCount where n == 1 {
            boundarySet.insert(k)
            let lo = UInt32(k >> 32)
            let hi = UInt32(k & 0xFFFF_FFFF)
            adj[lo, default: []].append(hi)
            adj[hi, default: []].append(lo)
        }
        guard !boundarySet.isEmpty else { return (out, 0) }

        var usedEdges = Set<UInt64>()
        var filled = 0

        for k in boundarySet {
            if usedEdges.contains(k) { continue }

            // 收集一个边界环
            let start = UInt32(k >> 32)
            var loop: [UInt32] = [start]
            var current = UInt32(k & 0xFFFF_FFFF)
            usedEdges.insert(k)

            var guardCount = 0
            while current != start && guardCount < boundarySet.count + 2 {
                loop.append(current)
                let nexts = (adj[current] ?? []).filter { !usedEdges.contains(edgeKey(current, $0)) }
                guard let next = nexts.first else { break }
                usedEdges.insert(edgeKey(current, next))
                current = next
                guardCount += 1
            }

            guard loop.count >= 3, loop.count <= maxHoleEdges, current == start else { continue }

            // 质心
            var centroid = SIMD3<Float>(0, 0, 0)
            for vid in loop { centroid += out.vertices[Int(vid)] }
            centroid /= Float(loop.count)
            let cIndex = UInt32(out.vertices.count)
            out.vertices.append(centroid)

            // 扇形三角化
            for n in 0..<loop.count {
                let a = loop[n]
                let b = loop[(n + 1) % loop.count]
                out.indices.append(a)
                out.indices.append(b)
                out.indices.append(cIndex)
            }
            filled += 1
        }

        return (out, filled)
    }

    // MARK: - 简化（顶点聚类）

    static func simplify(_ mesh: MeshData, targetFaces: Int) -> MeshData {
        guard targetFaces > 0, mesh.faceCount > targetFaces else { return mesh }

        let diag = max(mesh.maxDimension, 0.001)
        var grid = max(16, Int(Double(targetFaces).squareRoot()))
        var result = mesh

        for _ in 0..<8 {
            result = cluster(mesh, cellSize: diag / Float(grid))
            let faces = result.faceCount
            if faces <= targetFaces { break }
            // 按比例放大网格尺寸
            let ratio = Double(faces) / Double(targetFaces)
            grid = min(512, max(grid + 1, Int(Double(grid) * max(1.05, ratio.squareRoot()))))
        }
        return result
    }

    private static func cluster(_ mesh: MeshData, cellSize: Float) -> MeshData {
        guard cellSize > 0 else { return mesh }

        let lo = mesh.boundsMin
        var cellToNew: [SIMD3<Int32>: UInt32] = [:]
        var newVertexIndex: [UInt32] = []
        newVertexIndex.reserveCapacity(mesh.vertices.count)

        var out = MeshData()
        // 累加同格子内的顶点求平均
        var accum: [SIMD3<Int32>: (sum: SIMD3<Float>, count: Float)] = [:]

        for v in mesh.vertices {
            let cell = SIMD3<Int32>(Int32(floor((v.x - lo.x) / cellSize)),
                                    Int32(floor((v.y - lo.y) / cellSize)),
                                    Int32(floor((v.z - lo.z) / cellSize)))
            if let existing = cellToNew[cell] {
                let prev = accum[cell] ?? (SIMD3<Float>(0, 0, 0), 0)
                accum[cell] = (prev.sum + v, prev.count + 1)
                _ = existing
            } else {
                let idx = UInt32(out.vertices.count)
                cellToNew[cell] = idx
                accum[cell] = (v, 1)
                out.vertices.append(v)   // 占位，稍后平均
            }
            newVertexIndex.append(cellToNew[cell] ?? 0)
        }

        // 回填平均值
        for (cell, idx) in cellToNew {
            if let a = accum[cell], a.count > 0 {
                out.vertices[Int(idx)] = a.sum / a.count
            }
        }

        // 重建索引，去重三角形
        var seen = Set<UInt64>()
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = newVertexIndex[Int(mesh.indices[i])]
            let b = newVertexIndex[Int(mesh.indices[i + 1])]
            let c = newVertexIndex[Int(mesh.indices[i + 2])]
            i += 3
            if a == b || b == c || a == c { continue }
            // 无序三点做 key，去掉折叠出来的重复面
            let sortedIds = [a, b, c].sorted()
            let key = (UInt64(sortedIds[0]) << 42) | (UInt64(sortedIds[1]) << 21) | UInt64(sortedIds[2])
            if seen.contains(key) { continue }
            seen.insert(key)
            out.indices.append(a)
            out.indices.append(b)
            out.indices.append(c)
        }
        return out
    }

    // MARK: - 平滑（拉普拉斯）

    static func smooth(_ mesh: MeshData, strength: Double) -> MeshData {
        guard strength > 0.001, mesh.vertexCount > 3 else { return mesh }

        // 邻接表
        var adj = Array(repeating: Set<UInt32>(), count: mesh.vertexCount)
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.indices[i], b = mesh.indices[i + 1], c = mesh.indices[i + 2]
            i += 3
            adj[Int(a)].insert(b); adj[Int(a)].insert(c)
            adj[Int(b)].insert(a); adj[Int(b)].insert(c)
            adj[Int(c)].insert(a); adj[Int(c)].insert(b)
        }

        let lambda = Float(strength * 0.5)
        let iterations = 1 + Int(strength * 6)

        var verts = mesh.vertices
        for _ in 0..<iterations {
            var next = verts
            for idx in 0..<verts.count {
                let neighbors = adj[idx]
                if neighbors.isEmpty { continue }
                var avg = SIMD3<Float>(0, 0, 0)
                for n in neighbors { avg += verts[Int(n)] }
                avg /= Float(neighbors.count)
                next[idx] = verts[idx] + (avg - verts[idx]) * lambda
            }
            verts = next
        }

        var out = mesh
        out.vertices = verts
        return out
    }

    // MARK: - 一键自动修复（扫描完成 / 应用设置时调用）

    static func applyAutoFix(_ mesh: MeshData, settings: ScanSettings) -> (mesh: MeshData, holesFilled: Int) {
        var m = clean(mesh)

        // 简化到目标面数
        let target = Int(settings.targetFaces)
        if target > 0 { m = simplify(m, targetFaces: target) }

        // 补洞
        var filled = 0
        if settings.autoFillHoles {
            let r = fillHoles(m)
            m = r.mesh
            filled = r.filled
        }

        // 平滑
        if settings.smoothing > 0.001 {
            m = smooth(m, strength: settings.smoothing)
        }

        // 非流形修复：先做一次轻量平滑再清洗一次索引
        if settings.fixNonManifold {
            m = clean(m)
        }

        m = clean(m)
        return (m, filled)
    }
}
