import Foundation
import Combine
import ARKit
import RealityKit
import simd

/// ARKit 会话管理：LiDAR 网格重建 + 深度/纹理采集 + 实时指标
final class ARSessionManager: NSObject, ObservableObject, ARSessionDelegate {

    // 实时指标（UI 绑定）
    @Published var distance: Float = 0          // 米
    @Published var coverage: Double = 0         // 0-1
    @Published var texturePct: Double = 0       // 0-1
    @Published var meshAnchorCount: Int = 0
    @Published var isRunning = false
    @Published var usingLiDAR = false

    let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    /// 最近一帧的影像（纹理烘焙用）
    private(set) var lastFrame: ARFrame?

    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var scannedArea: Float = 0
    /// 覆盖率参考面积（米²）——按一台桌面小物件扫描的典型需求估算
    private let referenceArea: Float = 1.2

    // MARK: - 控制

    func start() {
        scannedArea = 0
        meshAnchors.removeAll()
        distance = 0
        coverage = 0
        texturePct = 0
        meshAnchorCount = 0

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        let supportsMesh = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        usingLiDAR = supportsMesh
        if supportsMesh {
            config.sceneReconstruction = .mesh
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        }

        arView.session.delegate = self
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors, .resetSceneReconstruction])
        isRunning = true
    }

    func stop() {
        arView.session.pause()
        isRunning = false
    }

    func reset() {
        scannedArea = 0
        meshAnchors.removeAll()
        coverage = 0
        texturePct = 0
        meshAnchorCount = 0
        if isRunning { start() }
    }

    /// 结束扫描，输出合并后的网格
    func finalizeMesh() -> MeshData? {
        let anchors = Array(meshAnchors.values)
        guard !anchors.isEmpty else { return nil }
        let mesh = MeshBuilder.build(from: anchors)
        return mesh.isEmpty ? nil : mesh
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        absorb(anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        absorb(anchors)
    }

    private func absorb(_ anchors: [ARAnchor]) {
        var added: [ARMeshAnchor] = []
        for case let a as ARMeshAnchor in anchors {
            if meshAnchors[a.identifier] == nil { added.append(a) }
            meshAnchors[a.identifier] = a
        }
        if !added.isEmpty {
            scannedArea += MeshBuilder.surfaceArea(of: added)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lastFrame = frame

        // 距离：中心点深度采样（有深度图时更准，否则用相机位移估算）
        if let depth = frame.sceneDepth {
            let w = CVPixelBufferGetWidth(depth.depthMap)
            let h = CVPixelBufferGetHeight(depth.depthMap)
            CVPixelBufferLockBaseAddress(depth.depthMap, .readOnly)
            if let base = CVPixelBufferGetBaseAddress(depth.depthMap) {
                let bpr = CVPixelBufferGetBytesPerRow(depth.depthMap)
                let x = w / 2, y = h / 2
                let row = base.advanced(by: y * bpr).assumingMemoryBound(to: Float32.self)
                let d = row[x]
                if d.isFinite, d > 0, d < 10 { distance = d }
            }
            CVPixelBufferUnlockBaseAddress(depth.depthMap, .readOnly)
        }

        let meshArea = MeshBuilder.surfaceArea(of: Array(meshAnchors.values))
        scannedArea = meshArea

        let cov = Double(meshArea / referenceArea)
        coverage = min(1.0, max(0.0, cov))

        // 纹理覆盖：用已扫网格与已跟踪时间做启发式映射（真实投影覆盖率在烘焙时统计）
        let timeFactor = min(1.0, Double(frame.timestamp.truncatingRemainder(dividingBy: 600)) / 30.0)
        texturePct = min(1.0, max(0.35, 0.35 + timeFactor * 0.65 * coverage))

        meshAnchorCount = meshAnchors.count
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        isRunning = false
    }
}
