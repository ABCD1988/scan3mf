import SwiftUI
import ARKit

/// 第 6 屏：设置
struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var tab = 2
    @State private var showAbout = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                NavBar(title: "设置")
                    .padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        deviceCard
                        guideCard
                        aboutCard
                        Color.clear.frame(height: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                PillTabBar(items: ["模型库", "扫描", "设置"], selection: $tab) { idx in
                    switch idx {
                    case 0: app.screen = .home
                    case 1: app.startScan()
                    default: break
                    }
                    tab = 2
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .alert("关于 \(AppInfo.name)", isPresented: $showAbout) {
            Button("好", role: .cancel) { }
        } message: {
            Text("作者：\(AppInfo.author)\n\nLiDAR 实扫建模工具，支持物体扫描与空间扫描，可导出 3MF / STL / OBJ / USDZ。\n版本 \(Self.version)")
        }
    }

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: - 设备能力

    private var deviceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("设备能力")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                infoRow("LiDAR 网格重建",
                        value: app.lidarAvailable ? "支持" : "不支持",
                        ok: app.lidarAvailable)
                infoRow("场景深度",
                        value: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) ? "支持" : "不支持",
                        ok: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth))
                infoRow("平滑深度",
                        value: ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) ? "支持" : "不支持",
                        ok: ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth))
                infoRow("6DoF 世界跟踪",
                        value: ARWorldTrackingConfiguration.isSupported ? "支持" : "不支持",
                        ok: ARWorldTrackingConfiguration.isSupported)
            }
        }
    }

    private func infoRow(_ label: String, value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(ok ? Theme.accent : Color(hex: 0xE2705A))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.text2)
            Spacer()
            Text(value)
                .font(Theme.data)
                .foregroundColor(Theme.text)
        }
    }

    // MARK: - 使用建议

    private var guideCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("扫描建议")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                bullet("保持 0.3–0.8m 距离，移动速度不宜过快")
                bullet("先扫四周再补顶面与底部，覆盖率到 90% 以上")
                bullet("反光、透明、纯黑表面 LiDAR 容易漏扫")
                bullet("导出 3MF 前建议检查水密性，缺口可自动补洞")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.accent.opacity(0.7))
                .frame(width: 4, height: 4)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 关于

    private var aboutCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("关于")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text("版本 \(Self.version)")
                        .font(Theme.data)
                        .foregroundColor(Theme.text3)
                }
                Divider().background(Theme.stroke)
                infoRow("作者", value: AppInfo.author, ok: true)
                Divider().background(Theme.stroke)
                Button {
                    showAbout = true
                } label: {
                    HStack {
                        Text("版本说明与已知限制")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text2)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.text3)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}
