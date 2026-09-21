import Foundation

/// 全局常量
enum AppInfo {
    static let name = "LiDARScan3MF"
    static let author = "超哥！"
}

/// 扫描模式
///
/// - object：物体扫描 —— 摆件 / 零件，近距离 360° 环绕，只保留焦点附近球体以内的网格，高精度
/// - space：空间扫描 —— 房间 / 大场景，远距离大范围，整体偏粗，可贴近局部补扫提精度
enum ScanMode: String, CaseIterable, Identifiable {
    case object = "物体扫描"
    case space  = "空间扫描"

    var id: String { rawValue }

    /// 采集半径（米）：距焦点超过这个距离的网格直接丢掉
    var captureRadius: Float {
        switch self {
        case .object: return 1.0
        case .space:  return 8.0
        }
    }

    /// 覆盖率 100% 对应的参考表面积（米²）
    var referenceArea: Float {
        switch self {
        case .object: return 1.8
        case .space:  return 28.0
        }
    }

    /// 默认目标面数（细部化里还能改）
    var defaultTargetFaces: Double {
        switch self {
        case .object: return 160_000   // 几乎不简化，保留细节
        case .space:  return 70_000
        }
    }

    var defaultSmoothing: Double {
        switch self {
        case .object: return 0.25
        case .space:  return 0.45
        }
    }

    var icon: String {
        switch self {
        case .object: return "cube.transparent"
        case .space:  return "house"
        }
    }

    var subtitle: String {
        switch self {
        case .object: return "摆件 / 零件 · 近距离环绕 · 高精度"
        case .space:  return "房间 / 大场景 · 远距离 · 可贴近补扫"
        }
    }

    var radiusText: String {
        captureRadius >= 1 ? String(format: "%.0f m", captureRadius)
                           : String(format: "%.1f m", captureRadius)
    }

    var detail: String {
        switch self {
        case .object:
            return "只保留焦点 \(radiusText) 以内的网格，远的墙面、地面全部剔除，360° 环绕扫一圈即可直接建模。"
        case .space:
            return "保留 \(radiusText) 以内的大场景，整体精度偏粗；想让某处更精细，走近一点、多扫一会儿。"
        }
    }

    var hints: [String] {
        switch self {
        case .object:
            return ["对准物体按下开始，先站定 1 秒锁定焦点",
                    "绕物体缓慢走一圈，保持 0.3–0.8 m",
                    "蹲下补扫底部与侧面，360° 都扫到",
                    "纯白 / 反光 / 透明表面请贴近补扫"]
        case .space:
            return ["站在房间中央缓慢转身，扫完整圈墙面",
                    "想让某处更精细，就走近它多停留几秒",
                    "远距离精度有限，关键位置建议贴近补扫"]
        }
    }

    /// 是否按焦点球裁剪
    var usesFocusCrop: Bool {
        switch self {
        case .object: return true
        case .space:  return false
        }
    }
}

/// 导出样式
enum ExportStyle: String, CaseIterable, Identifiable {
    case textured = "真实色彩"
    case plain    = "素模"
    case accent   = "激光青"

    var id: String { rawValue }

    var note: String {
        switch self {
        case .textured: return "带上扫描时的真实颜色，看模型最直观"
        case .plain:    return "纯几何白模，切片器兼容性最好"
        case .accent:   return "统一青色单色模型，便于区分与展示"
        }
    }

    /// 是否需要写入顶点颜色
    var needsVertexColor: Bool { self == .textured }
}

/// 预览显示样式（编辑页用）
enum PreviewStyle: String, CaseIterable, Identifiable {
    case shaded    = "真实色彩"
    case solid     = "素模"
    case wireframe = "线框"

    var id: String { rawValue }
}
