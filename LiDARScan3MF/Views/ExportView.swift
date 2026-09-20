import SwiftUI

/// 第 4 屏：导出设置
struct ExportView: View {
    @EnvironmentObject private var app: AppModel
    @State private var format: ExportFormat = .threeMF
    @State private var scale: ExportScale = .one
    @State private var unit: ExportUnit = .mm
    @State private var shareURL: URL?

    private let formatNotes: [ExportFormat: String] = [
        .threeMF: "推荐 · 含颜色与单位，3D 打印切片器首选",
        .stl: "通用格式，仅几何，无色与单位信息",
        .obj: "兼容性广，可带顶点色，适合后续建模",
        .usdz: "苹果原生 AR 格式，可用于「快速查看」"
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                NavBar(title: "导出模型", onBack: { app.screen = .edit })
                    .padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        summaryCard
                        formatSection
                        optionSection
                        detailEntry
                        Color.clear.frame(height: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                actions
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
            }
        }
        .shareSheet(url: $shareURL)
    }

    // MARK: - 模型摘要

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("待导出模型")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text2)
                    Spacer()
                    Text(app.isWatertight ? "水密" : "非水密")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(app.isWatertight ? Theme.accent : Color(hex: 0xE2A85A))
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(app.mesh?.faceCount.grouped ?? "0")
                        .font(.system(size: 22, weight: .semibold).monospaced())
                        .foregroundColor(Theme.text)
                    Text("个三角面")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3)
                    Spacer()
                    Text(sizeLabel)
                        .font(Theme.data)
                        .foregroundColor(Theme.text2)
                }
            }
        }
    }

    private var sizeLabel: String {
        guard let m = app.mesh else { return "-" }
        let s = m.size
        return String(format: "%.0f × %.0f × %.0f mm",
                      abs(s.x * 1000 * scale.factor),
                      abs(s.y * 1000 * scale.factor),
                      abs(s.z * 1000 * scale.factor))
    }

    // MARK: - 格式选择

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "导出格式")
            VStack(spacing: 0) {
                ForEach(Array(ExportFormat.allCases.enumerated()), id: \.offset) { idx, f in
                    formatRow(f)
                    if idx < ExportFormat.allCases.count - 1 {
                        Divider().background(Theme.stroke).padding(.leading, 44)
                    }
                }
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(format == .threeMF ? Theme.accent.opacity(0.5) : Theme.stroke, lineWidth: 1))
        }
    }

    private func formatRow(_ f: ExportFormat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .stroke(format == f ? Theme.accent : Theme.stroke, lineWidth: 1.5)
                    .frame(width: 18, height: 18)
                if format == f {
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(f.rawValue)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    if f == .threeMF {
                        Text("推荐")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.bg)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(formatNotes[f] ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture { format = f }
    }

    // MARK: - 比例与单位

    private var optionSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "导出比例")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SegmentedControl(options: ExportScale.allCases.map { $0.rawValue },
                                         selection: Binding(
                                            get: { ExportScale.allCases.firstIndex(of: scale) ?? 1 },
                                            set: { scale = ExportScale.allCases[$0] }),
                                         mono: true)
                        Text("原始尺寸 1:1，缩放后模型为原件的 \(scale.rawValue) 比例")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.text3)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "单位")
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        SegmentedControl(options: ExportUnit.allCases.map { $0.rawValue },
                                         selection: Binding(
                                            get: { ExportUnit.allCases.firstIndex(of: unit) ?? 0 },
                                            set: { unit = ExportUnit.allCases[$0] }),
                                         mono: true)
                        Text("导出文件中的尺寸单位，建议与切片器保持一致")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.text3)
                    }
                }
            }
        }
    }

    // MARK: - 细部化入口

    private var detailEntry: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Theme.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("细部化设置")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Text("网格密度 \(Int(app.settings.targetFaces).grouped) 面 · 平滑 \(Int(app.settings.smoothing * 100))% · \(app.settings.depthFusion ? "深度融合开" : "深度融合关")")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.text3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text3)
            }
        }
        .onTapGesture { app.screen = .detail }
    }

    // MARK: - 底部动作

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if let url = app.exportMesh(format: format, scale: scale, unit: unit) {
                    shareURL = url
                }
            } label: {
                Text("导出并分享 \(format.rawValue)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Text("文件保存到 App 沙盒 exports/ 目录，可通过分享面板存到「文件」或用其它 App 打开")
                .font(.system(size: 11))
                .foregroundColor(Theme.text3)
                .multilineTextAlignment(.center)
        }
    }
}
