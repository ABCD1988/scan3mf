import Foundation
import ARKit

enum Screen { case home, scan, edit, export, detail, settings }

enum ExportFormat: String, CaseIterable, Identifiable {
    case threeMF = "3MF"
    case stl = "STL"
    case obj = "OBJ"
    case usdz = "USDZ"
    var id: String { rawValue }
    var fileExtension: String {
        switch self {
        case .threeMF: return "3mf"
        case .stl: return "stl"
        case .obj: return "obj"
        case .usdz: return "usdz"
        }
    }
}

enum ExportScale: String, CaseIterable, Identifiable {
    case half = "1:2"
    case one = "1:1"
    case double = "2:1"
    var id: String { rawValue }
    var factor: Float {
        switch self {
        case .half: return 0.5
        case .one: return 1.0
        case .double: return 2.0
        }
    }
}

enum ExportUnit: String, CaseIterable, Identifiable {
    case mm = "mm"
    case cm = "cm"
    case m = "m"
    var id: String { rawValue }
    var metersToUnit: Float {
        switch self {
        case .mm: return 1000
        case .cm: return 100
        case .m: return 1
        }
    }
}

/// 细部化设置（对应设计稿第 5 屏）
struct ScanSettings {
    var targetFaces: Double = 42_180      // 网格密度（目标面数）
    var smoothing: Double = 0.4           // 平滑强度 0-1
    var textureSourceIndex: Int = 0       // 0 摄像头RGB / 1 LiDAR反照率
    var resolutionIndex: Int = 1          // 0 1K / 1 2K / 2 4K
    var depthFusion: Bool = true          // LiDAR+RGB 深度融合
    var autoFillHoles: Bool = true        // 自动补洞
    var fixNonManifold: Bool = false      // 非流形修复

    mutating func reset() { self = ScanSettings() }
}

final class AppModel: ObservableObject {
    @Published var screen: Screen = .home
    @Published var settings = ScanSettings()
    @Published var mesh: MeshData?
    @Published var holeCount = 0
    @Published var isWatertight = false
    @Published var toast: String?
    @Published var shareURL: URL?

    let store = ModelStore()
    let session = ARSessionManager()

    var lidarAvailable: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }

    // MARK: - 扫描流程

    func startScan() {
        guard lidarAvailable else {
            toast = "此设备不支持 LiDAR 网格重建"
            return
        }
        session.start()
        screen = .scan
    }

    func cancelScan() {
        session.stop()
        screen = .home
    }

    func finishScan() {
        let raw = session.finalizeMesh() ?? MeshData()
        session.stop()
        guard raw.faceCount > 0 else {
            toast = "未捕获到网格，请重新扫描"
            screen = .home
            return
        }
        let result = MeshProcessor.applyAutoFix(raw, settings: settings)
        mesh = result.mesh
        refreshStats(result.mesh)
        screen = .edit
    }

    func refreshStats(_ m: MeshData? = nil) {
        guard let m = m ?? mesh else { return }
        let s = MeshProcessor.stats(m)
        holeCount = s.holes
        isWatertight = s.boundaryEdges == 0
    }

    // MARK: - 模型库

    func openModel(_ model: ScanModel) {
        guard let m = OBJLoader.load(url: store.url(for: model)) else {
            toast = "模型文件读取失败"
            return
        }
        mesh = m
        refreshStats(m)
        screen = .edit
    }

    func saveCurrentModel(named name: String) {
        guard let m = mesh, m.faceCount > 0 else {
            toast = "没有可保存的模型"
            return
        }
        let fileName = UUID().uuidString + ".obj"
        let url = store.dir.appendingPathComponent(fileName)
        guard OBJWriter.write(m, scale: 1.0, to: url) else {
            toast = "保存失败"
            return
        }
        let s = m.size * 1000
        let st = MeshProcessor.stats(m)
        store.add(ScanModel(name: name,
                            createdAt: Date(),
                            faceCount: m.faceCount,
                            vertexCount: m.vertexCount,
                            sizeMM: [Double(abs(s.x)), Double(abs(s.y)), Double(abs(s.z))],
                            watertight: st.boundaryEdges == 0,
                            holeCount: st.holes,
                            fileName: fileName))
        toast = "已保存到模型库"
    }

    // MARK: - 导出

    @discardableResult
    func exportMesh(format: ExportFormat, scale: ExportScale, unit: ExportUnit) -> URL? {
        guard let m = mesh, m.faceCount > 0 else {
            toast = "没有可导出的模型"
            return nil
        }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = String(Int(Date().timeIntervalSince1970))
        let url = dir.appendingPathComponent("Scan-\(stamp).\(format.fileExtension)")
        let ok: Bool
        switch format {
        case .threeMF:
            ok = ThreeMFWriter.write(mesh: m, unit: unit, scale: scale.factor, to: url)
        case .stl:
            ok = STLWriter.write(m, scale: scale.factor, to: url)
        case .obj:
            ok = OBJWriter.write(m, scale: scale.factor, to: url)
        case .usdz:
            ok = USDZExporter.write(m, scale: scale.factor, to: url)
        }
        if ok { return url }
        toast = "导出失败"
        return nil
    }
}
