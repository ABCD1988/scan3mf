import SwiftUI

/// 第 5 屏：细部化设置
struct DetailSettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var targetFaces: Double = 42_180
    @State private var smoothing: Double = 0.4
    @State private var textureSource = 0
    @State private var resolution = 1
    @State private var depthFusion = true
    @State private var autoFillHoles = true
    @State private var fixNonManifold = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                NavBar(title: "细部化设置", onBack: { app.screen = .export })
                    .padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // 网格与简化
                        SectionHeader(title: "网格与简化")
                        meshDensityCard
                        smoothingCard

                        // 纹理与融合
                        SectionHeader(title: "纹理与融合").padding(.top, 4)
                        textureSourceCard
                        resolutionCard

                        // 自动修复
                        SectionHeader(title: "自动修复").padding(.top, 4)
                        repairCard
                        Color.clear.frame(height: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
        }
        .onAppear(perform: loadFromSettings)
    }

    // MARK: - 网格密度

    private var meshDensityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("网格密度")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Int(targetFaces).grouped)
                            .font(.system(size: 13, weight: .semibold).monospaced())
                            .foregroundColor(Theme.accent)
                        Text("面")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.text3)
                    }
                }
                SliderBar(value: Binding(
                    get: { normalizeFaces(targetFaces) },
                    set: { targetFaces = denormalizeFaces($0) }
                ))
                HStack {
                    Text("5,000").font(.system(size: 10)).foregroundColor(Theme.text3)
                    Spacer()
                    Text("200,000").font(.system(size: 10)).foregroundColor(Theme.text3)
                }
            }
        }
    }

    private func normalizeFaces(_ faces: Double) -> Double {
        let lo = log10(5_000.0), hi = log10(200_000.0)
        return min(1, max(0, (log10(max(5_000, faces)) - lo) / (hi - lo)))
    }

    private func denormalizeFaces(_ t: Double) -> Double {
        let lo = log10(5_000.0), hi = log10(200_000.0)
        let v = pow(10, lo + (hi - lo) * min(1, max(0, t)))
        return (v / 100).rounded() * 100
    }

    // MARK: - 平滑

    private var smoothingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("平滑强度")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text("\(Int(smoothing * 100)) %")
                        .font(.system(size: 13, weight: .semibold).monospaced())
                        .foregroundColor(Theme.accent)
                }
                SliderBar(value: $smoothing)
                Text("强度越高表面越平滑，细节与锐边损失越多")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
            }
        }
    }

    // MARK: - 纹理来源

    private var textureSourceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("纹理来源")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                SegmentedControl(options: ["摄像头 RGB", "LiDAR 反照率"], selection: $textureSource)
                Text(textureSource == 0
                     ? "使用相机影像逐顶点采色，颜色真实但受光照影响"
                     : "使用激光回波强度着色，稳定但无色相信息")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
            }
        }
    }

    // MARK: - 输出分辨率

    private var resolutionCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("输出分辨率")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text("纹理采样精度")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text3)
                }
                SegmentedControl(options: ["1K", "2K", "4K"], selection: $resolution)
            }
        }
    }

    // MARK: - 深度融合与修复

    private var repairCard: some View {
        Card {
            VStack(spacing: 0) {
                toggleRow("深度融合", "点云与影像逐帧对齐，合成彩色模型", $depthFusion)
                Divider().background(Theme.stroke)
                toggleRow("自动补洞", "扫描结束后自动封闭开放边界", $autoFillHoles)
                Divider().background(Theme.stroke)
                toggleRow("非流形修复", "修正自交与多余共享边，提高可打印性", $fixNonManifold)
            }
        }
    }

    private func toggleRow(_ title: String, _ subtitle: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            CapsuleSwitch(isOn: binding)
        }
        .padding(.vertical, 11)
    }

    // MARK: - 页脚

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                app.settings.reset()
                loadFromSettings()
                app.toast = "已恢复默认设置"
            } label: {
                Text("恢复默认")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.text2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1))
            }

            Button {
                applyToSettings()
                app.toast = "设置已应用"
                app.screen = .export
            } label: {
                Text("应用设置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }

    // MARK: - 同步

    private func loadFromSettings() {
        targetFaces = app.settings.targetFaces
        smoothing = app.settings.smoothing
        textureSource = app.settings.textureSourceIndex
        resolution = app.settings.resolutionIndex
        depthFusion = app.settings.depthFusion
        autoFillHoles = app.settings.autoFillHoles
        fixNonManifold = app.settings.fixNonManifold
    }

    private func applyToSettings() {
        app.settings.targetFaces = targetFaces.rounded()
        app.settings.smoothing = smoothing
        app.settings.textureSourceIndex = textureSource
        app.settings.resolutionIndex = resolution
        app.settings.depthFusion = depthFusion
        app.settings.autoFillHoles = autoFillHoles
        app.settings.fixNonManifold = fixNonManifold
    }
}
