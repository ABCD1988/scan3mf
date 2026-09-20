import Foundation
import simd

// MARK: - STL（二进制，毫米，Z-up）

enum STLWriter {

    @discardableResult
    static func write(_ mesh: MeshData, scale: Float, to url: URL) -> Bool {
        guard !mesh.isEmpty else { return false }

        // 毫米 + Z-up（与 3MF 导出保持一致的坐标约定）
        let factor = scale * 1000
        let faces = mesh.faceCount

        var data = Data()
        data.reserveCapacity(84 + faces * 50)

        // 80 字节头
        var header = [UInt8](repeating: 0, count: 80)
        let tag = Array("LiDARScan3MF binary STL".utf8)
        for (i, b) in tag.enumerated() where i < 80 { header[i] = b }
        data.append(contentsOf: header)

        appendU32(UInt32(faces), to: &data)

        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.vertices[Int(mesh.indices[i])]
            let b = mesh.vertices[Int(mesh.indices[i + 1])]
            let c = mesh.vertices[Int(mesh.indices[i + 2])]
            i += 3

            let n = simd_cross(b - a, c - a)
            let len = simd_length(n)
            let normal = len > 0 ? n / len : SIMD3<Float>(0, 0, 1)

            appendVec(convert(normal, factor: 1), to: &data)   // 法线不缩放
            appendVec(convert(a, factor: factor), to: &data)
            appendVec(convert(b, factor: factor), to: &data)
            appendVec(convert(c, factor: factor), to: &data)

            var attr: UInt16 = 0
            withUnsafeBytes(of: &attr) { data.append(contentsOf: $0) }
        }

        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// ARKit Y-up（米）→ Z-up（目标单位）
    private static func convert(_ v: SIMD3<Float>, factor: Float) -> SIMD3<Float> {
        SIMD3<Float>(v.x * factor, -v.z * factor, v.y * factor)
    }

    private static func appendVec(_ v: SIMD3<Float>, to data: inout Data) {
        for f in [v.x, v.y, v.z] {
            var bits = f.bitPattern
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }

    private static func appendU32(_ v: UInt32, to data: inout Data) {
        var x = v
        withUnsafeBytes(of: &x) { data.append(contentsOf: $0) }
    }
}

// MARK: - OBJ（毫米，Z-up；同时用于本地模型库存档）

enum OBJWriter {

    @discardableResult
    static func write(_ mesh: MeshData, scale: Float, to url: URL) -> Bool {
        guard !mesh.isEmpty else { return false }

        let factor = scale * 1000
        var text = "# LiDARScan3MF export\n"
        text += "# vertices: \(mesh.vertexCount)  faces: \(mesh.faceCount)\n"
        text.reserveCapacity(mesh.vertexCount * 40)

        for v in mesh.vertices {
            let x = v.x * factor
            let y = -v.z * factor
            let z = v.y * factor
            text += "v \(String(format: "%.4f", x)) \(String(format: "%.4f", y)) \(String(format: "%.4f", z))\n"
        }

        var i = 0
        while i + 2 < mesh.indices.count {
            // OBJ 索引从 1 开始
            let a = mesh.indices[i] + 1
            let b = mesh.indices[i + 1] + 1
            let c = mesh.indices[i + 2] + 1
            i += 3
            text += "f \(a) \(b) \(c)\n"
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - OBJ 读取（打开模型库中的模型）

enum OBJLoader {

    static func load(url: URL) -> MeshData? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        var mesh = MeshData()
        // OBJ 里是毫米 Z-up，读回来统一转成 ARKit 的米 + Y-up：(x, z, -y) / 1000
        text.enumerateLines { line, _ in
            if line.hasPrefix("v ") {
                let parts = line.dropFirst(2).split(separator: " ")
                guard parts.count >= 3,
                      let x = Float(parts[0]),
                      let y = Float(parts[1]),
                      let z = Float(parts[2]) else { return }
                mesh.vertices.append(SIMD3<Float>(x / 1000, z / 1000, -y / 1000))
            } else if line.hasPrefix("f ") {
                let parts = line.dropFirst(2).split(separator: " ")
                guard parts.count >= 3 else { return }
                var ids: [UInt32] = []
                for p in parts.prefix(3) {
                    // 支持 v / v/vt / v//vn 形式
                    let vStr = p.split(separator: "/").first.map(String.init) ?? String(p)
                    guard let vi = Int(vStr) else { return }
                    let resolved = vi > 0 ? vi - 1 : mesh.vertices.count + vi
                    ids.append(UInt32(max(0, resolved)))
                }
                guard ids.count == 3 else { return }
                mesh.indices.append(contentsOf: ids)
            }
        }

        return mesh.isEmpty ? nil : mesh
    }
}
