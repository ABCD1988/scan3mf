import Foundation
import SceneKit
import ModelIO
import Metal

/// USDZ 导出：MeshData → MDLMesh → MDLAsset.export → .usdz
enum USDZExporter {

    @discardableResult
    static func write(_ mesh: MeshData, scale: Float, to url: URL) -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }

        // 缩放 + 居中，避免模型离原点过远
        let m = mesh.scaled(by: scale).centered()
        guard let mdlMesh = m.toMDLMesh(device: device, name: "ScanMesh") else { return false }

        let asset = MDLAsset()
        asset.add(mdlMesh)

        // 注意：不使用 SCNScene(mdlAsset:) —— 该 ModelIO 桥接构造器 iOS 上不可用。
        // MDLAsset.export(to:) 会依据扩展名导出 usdz。
        do {
            try asset.export(to: url)
            return FileManager.default.fileExists(atPath: url.path)
        } catch {
            NSLog("USDZ export failed: \(error.localizedDescription)")
            return false
        }
    }
}
