import Foundation
import simd

/// 3MF 导出：OPC 包（zip）= [Content_Types].xml + _rels/.rels + 3D/3dmodel.model
///
/// 坐标转换：ARKit 为右手 Y-up（米） → 3MF 约定 Z-up
///   (x, y, z) → (x, -z, y)
/// 值 = 顶点坐标 × 导出比例 × 单位换算（mm:1000 / cm:100 / m:1）
enum ThreeMFWriter {

    @discardableResult
    static func write(mesh: MeshData, unit: ExportUnit, scale: Float, to url: URL) -> Bool {
        guard !mesh.isEmpty else { return false }

        let model = buildModelXML(mesh: mesh, unit: unit, scale: scale)

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

    private static func buildModelXML(mesh: MeshData, unit: ExportUnit, scale: Float) -> String {
        let factor = scale * unit.metersToUnit

        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="\(unit.rawValue)" xml:lang="en-US" xmlns="http://schemas.microsoft.com/3dmanufacturing/core/2015/02">
          <metadata name="Application">LiDARScan3MF</metadata>
          <resources>
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
            xml += "          <triangle v1=\"\(mesh.indices[i])\" v2=\"\(mesh.indices[i + 1])\" v3=\"\(mesh.indices[i + 2])\" />\n"
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
}
