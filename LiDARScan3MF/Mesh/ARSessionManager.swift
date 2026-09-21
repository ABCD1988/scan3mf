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
    @Published var meshVertexCount: Int = 0
    @Published var isRunning = false
    @Published var usingLiDAR = false
    /// 会话跑了一段时间仍一个网格块都没有 → 多为设备不支持或环境太暗/纹理太少
    @Published var noMeshWarning = false
    /// 物体模式下焦点是否已锁定
    @Published var focusLocked = false

    /// 当前扫描模式（由 AppModel 在开始扫描前写入）
    var mode: ScanMode = .object

    let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

    /// 最近一帧的影像（纹理烘焙用）
    private(set) var lastFrame: ARFrame?
    /// 物体模式的裁剪球心（第一次拿到有效中心深度时锁定）
    private(set) var focusPoint: SIMD3<Float>?
    /// 彩色关键帧（多视角顶点着色用）
    private(set) var colorFrames: [ColorKeyFrame] = []

    private var meshAnchors: [UUID: ARMeshAnchor] = [:]
    private var scannedArea: Float = 0
    private var frameTick: Int = 0
    private var keyFrameTick: Int = 0
    /// 彩色关键帧上限
    private let maxColorFrames = 40

    // MARK: - 控制

    func start() {
        scannedArea = 0
        meshAnchors.removeAll()
        distance = 0
        coverage = 0
        texturePct = 0
        meshAnchorCount = 0
        meshVertexCount = 0
        noMeshWarning = false
        frameTick = 0
        keyFrameTick = 0
        focusPoint = nil
        focusLocked = false
        colorFrames.removeAll()

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

        // 显示 LiDAR 重建出的扫描网格（不打开就看不到任何扫描覆盖）
        arView.debugOptions.insert(.showSceneUnderstanding)

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
        meshVertexCount = 0
        frameTick = 0
        keyFrameTick = 0
        noMeshWarning = false
        focusPoint = nil
        focusLocked = false
        colorFrames.removeAll()
        if isRunning { start() }
    }

    /// 结束扫描，输出合并后的网格（物体模式按焦点球剔除远处）
    func finalizeMesh() -> MeshData? {
        let anchors = Array(meshAnchors.values)
        guard !anchors.isEmpty else { return nil }
        let mesh = MeshBuilder.build(from: anchors,
                                     center: cropCenter(),
                                     radius: mode.captureRadius)
        return mesh.isEmpty ? nil : mesh
    }

    /// 裁剪球心：只有物体模式才用焦点裁剪
    private func cropCenter() -> SIMD3<Float>? {
        guard mode.usesFocusCrop else { return nil }
        return focusPoint
    }

    /// 覆盖率参考面积随模式变化
    private var referenceArea: Float { mode.referenceArea }

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
                if d.isFinite, d > 0, d < 10 {
                    distance = d
                    // 物体模式：第一次拿到有效中心深度，就把焦点锁在正前方
                    if mode.usesFocusCrop, focusPoint == nil, d > 0.15, d < 6 {
                        let t = frame.camera.transform
                        let world = t * SIMD4<Float>(0, 0, -d, 1)
                        focusPoint = SIMD3<Float>(world.x, world.y, world.z)
                        focusLocked = true
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(depth.depthMap, .readOnly)
        }

        // 彩色关键帧：约每 0.2s 存一帧，用于扫描结束后的多视角上色
        keyFrameTick += 1
        if keyFrameTick % 12 == 0, colorFrames.count < maxColorFrames {
            if let kf = TextureBaker.captureKeyFrame(frame) {
                colorFrames.append(kf)
            }
        }

        // 性能关键：表面积要遍历全部三角形，绝不能每帧算（会把主线程卡死，
        // 表现为进度条完全不动）。改为每 15 帧（约 0.25s）更新一次。
        frameTick += 1
        if frameTick % 15 == 0 {
            let meshArea = MeshBuilder.surfaceArea(of: Array(meshAnchors.values),
                                                   center: cropCenter(),
                                                   radius: mode.captureRadius)
            scannedArea = meshArea

            let cov = Double(meshArea / referenceArea)
            coverage = min(1.0, max(0.0, cov))

            var vCount = 0
            for a in meshAnchors.values { vCount += a.geometry.vertices.count }
            meshVertexCount = vCount

            // 纹理覆盖：启发式映射（真实投影覆盖率在烘焙时统计）
            texturePct = min(1.0, max(0.35, 0.35 + coverage * 0.65))
        }

        meshAnchorCount = meshAnchors.count

        // 跑满约 3 秒仍然零网格 → 明确提示，避免用户对着一个不动的进度条干等
        if frameTick == 180, meshAnchors.isEmpty {
            noMeshWarning = true
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        isRunning = false
    }
}
