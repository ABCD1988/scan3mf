import SwiftUI

/// 第 1 屏：模型库（首页）
struct HomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var tab = 0
    @State private var pendingDelete: ScanModel?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // 页头
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("模型库")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text("LiDAR 扫描建模 · 3MF 导出 · by \(AppInfo.author)")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text3)
                    }
                    Spacer()
                    // LiDAR 状态徽标
                    HStack(spacing: 5) {
                        Circle()
                            .fill(app.lidarAvailable ? Theme.accent : Color(hex: 0xE2705A))
                            .frame(width: 6, height: 6)
                        Text(app.lidarAvailable ? "LiDAR 就绪" : "无 LiDAR")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(app.lidarAvailable ? Theme.accent : Color(hex: 0xE2705A))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Theme.card)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        modeCard
                        storageCard
                        modelGrid
                        Color.clear.frame(height: 8)
                    }
                    .padding(.horizontal, 20)
                }

                scanButton
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                PillTabBar(items: ["模型库", "扫描", "设置"], selection: $tab) { idx in
                    switch idx {
                    case 0: break
                    case 1: app.startScan(); tab = 0
                    default: app.screen = .settings; tab = 0
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
        }
        .confirmDelete(pendingDelete) { model in
            app.store.delete(model)
            app.toast = "已删除 \(model.name)"
            pendingDelete = nil
        }
    }

    // MARK: - 扫描模式

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "扫描模式")
            HStack(spacing: 10) {
                ForEach(ScanMode.allCases) { m in
                    modeButton(m)
                }
            }
            Text(app.mode.detail)
                .font(.system(size: 11))
                .foregroundColor(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func modeButton(_ m: ScanMode) -> some View {
        let selected = app.mode == m
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: m.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(m.rawValue)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundColor(selected ? Theme.accent : Theme.text)

            Text(m.subtitle)
                .font(.system(size: 10))
                .foregroundColor(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)

            Text("采集半径 \(m.radiusText)")
                .font(Theme.data)
                .foregroundColor(selected ? Theme.accent : Theme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(selected ? Theme.accent.opacity(0.10) : Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(selected ? Theme.accent.opacity(0.6) : Theme.stroke, lineWidth: 1))
        .onTapGesture { app.selectMode(m) }
    }

    // MARK: - 存储卡

    private var storageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("本地存储")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text2)
                    Spacer()
                    Text("\(app.store.models.count) 个模型")
                        .font(Theme.data)
                        .foregroundColor(Theme.text3)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(app.store.usedMB.fixed1)
                        .font(.system(size: 24, weight: .semibold).monospaced())
                        .foregroundColor(Theme.accent)
                    Text("MB 已用")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3)
                    Spacer()
                    Text("可用 \(app.store.freeMB.fixed0) MB")
                        .font(Theme.data)
                        .foregroundColor(Theme.text3)
                }
                GeometryReader { geo in
                    let ratio = app.store.freeMB > 0
                        ? min(1.0, app.store.usedMB / (app.store.usedMB + app.store.freeMB))
                        : 1.0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.stroke).frame(height: 4)
                        Capsule().fill(Theme.accent)
                            .frame(width: geo.size.width * CGFloat(ratio), height: 4)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    // MARK: - 模型网格

    @ViewBuilder
    private var modelGrid: some View {
        if app.store.models.isEmpty {
            Card(padding: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(Theme.text3)
                    Text("还没有扫描模型")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text2)
                    Text("点下方按钮开始第一次 LiDAR 扫描")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.text3)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(app.store.models) { model in
                    modelCell(model)
                }
            }
        }
    }

    private func modelCell(_ model: ScanModel) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.bg)
                    Image(systemName: "cube.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(Theme.accent.opacity(0.75))
                }
                .frame(height: 82)

                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)

                Text("\(model.faceCount.grouped) 面")
                    .font(Theme.data)
                    .foregroundColor(Theme.text2)

                HStack(spacing: 5) {
                    Circle()
                        .fill(model.watertight ? Theme.accent : Color(hex: 0xE2A85A))
                        .frame(width: 5, height: 5)
                    Text(model.statusLabel)
                        .font(.system(size: 10))
                        .foregroundColor(Theme.text3)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
        .onTapGesture { app.openModel(model) }
        .onLongPressGesture { pendingDelete = model }
    }

    // MARK: - 开始扫描

    private var scanButton: some View {
        Button {
            app.startScan(mode: app.mode)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                Text("开始\(app.mode.rawValue)")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(Theme.bg)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(app.lidarAvailable ? Theme.accent : Theme.stroke)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(!app.lidarAvailable)
    }
}

// MARK: - 删除确认

private extension View {
    func confirmDelete(_ model: ScanModel?, action: @escaping (ScanModel) -> Void) -> some View {
        alert("删除模型",
              isPresented: Binding(
                get: { model != nil },
                set: { if !$0 { /* 由按钮回调清理 */ } }
              ),
              presenting: model) { m in
            Button("删除", role: .destructive) { action(m) }
            Button("取消", role: .cancel) { }
        } message: { m in
            Text("确定删除「\(m.name)」？该操作不可撤销。")
        }
    }
}
