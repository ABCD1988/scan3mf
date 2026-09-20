import Foundation
import SceneKit
import ModelIO
import Metal

/// USDZ 导出：MeshData → MDLMesh → SCNScene → .usdz
enum USDZExporter {

    @discardableResult
    static func write(_ mesh: MeshData, scale: Float, to url: URL) -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }

        // 缩放 + 居中，避免模型离原点过远
        let m = mesh.scaled(by: scale).centered()
        guard let mdlMesh = m.mdlMesh(device: device, name: "ScanMesh") else { return false }

        let asset = MDLAsset()
        asset.add(mdlMesh)

        let scene = SCNScene(mdlAsset: asset)

        // 给一个中性材质，避免预览纯白/纯黑
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.78, green: 0.82, blue: 0.86, alpha: 1.0)
        material.roughness.contents = 0.6
        material.metalness.contents = 0.0
        scene.rootNode.childNodes.forEach { node in
            node.geometry?.materials = [material]
        }

        // write(to:) 会按 url 扩展名推断 usdz 格式，避免多 nil 参数的类型歧义
        return scene.write(to: url)
    }
}
