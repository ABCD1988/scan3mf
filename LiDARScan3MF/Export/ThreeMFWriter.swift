import Foundation
import simd

/// 3MF 导出：OPC 包（zip）= [Content_Types].xml + _rels/.rels + 3D/3dmodel.model
///
/// 坐标转换：ARKit 为右手 Y-up（米） → 3MF 约定 Z-up
///   (x, y, z) → (x, -z, y)
/// 值 = 顶点坐标 × 导出比例 × 单位换算（mm:1000 / cm:100 / m:1）
///
/// 颜色：3MF 核心规范没有顶点色，用 Materials & Properties 扩展的
/// `<basematerials>` + 三角形的 pid/p1/p2/p3 逐角指定颜色（切片器会插值成顶点色）。
enum ThreeMFWriter {

    @discardableResult
    static func write(mesh: MeshData,
                      unit: ExportUnit,
                      scale: Float,
                      style: ExportStyle = .textured,
                      to url: URL) -> Bool {
        guard !mesh.isEmpty else { return false }

        let model = buildModelXML(mesh: mesh, unit: unit, scale: scale, style: style)

        // OPC 包内的三个必需部件
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" />
          <Default Extension="model" ContentType="application/vnd.ms-package.3dmanufacturing-3dmodel+xml" />
        </Types>
        """

        let rels = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Target="/3D/3dmodel.model" Id="rel0" Type="http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel" />
        </Relationships>
        """

        let files: [ZIPWriter.Entry] = [
            ZIPWriter.Entry(name: "[Content_Types].xml", data: Data(contentTypes.utf8)),
            ZIPWriter.Entry(name: "_rels/.rels", data: Data(rels.utf8)),
            ZIPWriter.Entry(name: "3D/3dmodel.model", data: Data(model.utf8))
        ]

        return ZIPWriter.write(files: files, to: url)
    }

    // MARK: - 模型 XML

    private static func buildModelXML(mesh: MeshData,
                                      unit: ExportUnit,
                                      scale: Float,
                                      style: ExportStyle) -> String {
        let factor = scale * unit.metersToUnit

        // 颜色资源：nil 表示不写材质
        let palette = Palette.build(mesh: mesh, style: style)

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="\(unit.rawValue)" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <metadata name="Application">LiDARScan3MF</metadata>
          <metadata name="Author">\(AppInfo.author)</metadata>
          <metadata name="ExportStyle">\(style.rawValue)</metadata>
          <resources>

        """

        if let p = palette {
            xml += "    <basematerials id=\"1\" name=\"ScanColors\">\n"
            for (i, hex) in p.colors.enumerated() {
                xml += "      <base name=\"c\(i)\" displaycolor=\"#\(hex)\" />\n"
            }
            xml += "    </basematerials>\n"
        }

        xml += """
            <object id="1" type="model">
              <mesh>
                <vertices>

        """

        for v in mesh.vertices {
            // ARKit Y-up → 3MF Z-up
            let x = v.x * factor
            let y = -v.z * factor
            let z = v.y * factor
            xml += "          <vertex x=\"\(fmt(x))\" y=\"\(fmt(y))\" z=\"\(fmt(z))\" />\n"
        }

        xml += "        </vertices>\n        <triangles>\n"

        var i = 0
        while i + 2 < mesh.indices.count {
            let a = mesh.indices[i]
            let b = mesh.indices[i + 1]
            let c = mesh.indices[i + 2]
            if let p = palette {
                let p1 = p.index(for: a)
                let p2 = p.index(for: b)
                let p3 = p.index(for: c)
                xml += "          <triangle v1=\"\(a)\" v2=\"\(b)\" v3=\"\(c)\" pid=\"1\" p1=\"\(p1)\" p2=\"\(p2)\" p3=\"\(p3)\" />\n"
            } else {
                xml += "          <triangle v1=\"\(a)\" v2=\"\(b)\" v3=\"\(c)\" />\n"
            }
            i += 3
        }

        xml += """
                </triangles>
              </mesh>
            </object>
          </resources>
          <build>
            <item objectid="1" />
          </build>
        </model>
        """

        return xml
    }

    private static func fmt(_ v: Float) -> String {
        String(format: "%.6f", v)
    }

    // MARK: - 调色板

    /// 颜色量化到 5 bit/通道（32768 色）后去重，返回 3MF 的 base material 列表
    private struct Palette {
        var colors: [String] = []                 // "#RRGGBBAA"
        var vertexToIndex: [Int] = []             // 顶点 → 调色板下标

        static func build(mesh: MeshData, style: ExportStyle) -> Palette? {
            switch style {
            case .plain:
                return nil
            case .accent:
                var p = Palette()
                p.colors = ["35E2C2FF"]
                p.vertexToIndex = Array(repeating: 0, count: mesh.vertexCount)
                return p
            case .textured:
                guard let src = mesh.vertexColors, src.count == mesh.vertexCount else {
                    // 没有颜色数据时退回素模，保证文件合法
                    return nil
                }
                var lookup: [UInt16: Int] = [:]
                var palette = Palette()
                palette.vertexToIndex = Array(repeating: 0, count: mesh.vertexCount)

                for v in 0..<mesh.vertexCount {
                    let c = src[v]
                    let key = Palette.quantKey(c)
                    if let idx = lookup[key] {
                        palette.vertexToIndex[v] = idx
                    } else {
                        let idx = palette.colors.count
                        lookup[key] = idx
                        palette.colors.append(Palette.hex(c))
                        palette.vertexToIndex[v] = idx
                    }
                }
                return palette.colors.isEmpty ? nil : palette
            }
        }

        func index(for vertex: UInt32) -> Int {
            let i = Int(vertex)
            return i < vertexToIndex.count ? vertexToIndex[i] : 0
        }

        private static func quantKey(_ c: SIMD3<UInt8>) -> UInt16 {
            let r = UInt16(c.x >> 3)
            let g = UInt16(c.y >> 3)
            let b = UInt16(c.z >> 3)
            return (r << 10) | (g << 5) | b
        }

        private static func hex(_ c: SIMD3<UInt8>) -> String {
            let r = c.x >> 3
            let g = c.y >> 3
            let b = c.z >> 3
            let r8 = (Int(r) * 255 + 15) / 31
            let g8 = (Int(g) * 255 + 15) / 31
            let b8 = (Int(b) * 255 + 15) / 31
            return String(format: "%02X%02X%02XFF", r8, g8, b8)
        }
    }
}
