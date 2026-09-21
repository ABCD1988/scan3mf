import SwiftUI
import ARKit
import RealityKit

/// ARView 容器
struct ARViewContainer: UIViewRepresentable {
    let arView: ARView

    func makeUIView(context: Context) -> ARView { arView }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

/// 第 2 屏：扫描中
struct ScanView: View {
    @EnvironmentObject private var app: AppModel
    @State private var paused = false
    @State private var hintIndex = 0

    /// 提示语随模式变化
    private var currentHints: [String] { app.mode.hints }

    private var session: ARSessionManager { app.session }

    var body: some View {
        ZStack {
            // 相机画面
            ARViewContainer(arView: session.arView)
                .ignoresSafeArea()

            // 扫描取景框
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                .frame(width: 250, height: 250)
                .frame(maxHeight: .infinity, alignment: .center)
                .offset(y: -60)

            LinearGradient(colors: [Color.black.opacity(0.55), .clear, Color.black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .onAppear {
            // ARView 此时已加入视图层级，ARSession 才能正常采集 LiDAR 网格
            if !app.session.isRunning {
                app.session.start()
            }
        }
        .onDisappear {
            app.session.stop()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                // 模式芯片
                HStack(spacing: 6) {
                    Image(systemName: app.mode.icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(app.mode.rawValue) · \(app.mode.radiusText)")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(session.usingLiDAR ? Theme.accent : Theme.warn)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.55))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.accent.opacity(0.35), lineWidth: 1))

                Spacer()

                Text("\(session.meshAnchorCount) 块 · \(session.meshVertexCount.grouped) 顶点")
                    .font(Theme.data)
                    .foregroundColor(session.meshAnchorCount > 0 ? Theme.accent : Theme.text2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
            }

            // 物体模式：焦点还没锁定时先提示对准
            if app.mode.usesFocusCrop && !session.focusLocked {
                Text("对准物体、站定约 1 秒，锁定焦点后开始环绕")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.warn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.warn.opacity(0.45), lineWidth: 1))
            } else if session.noMeshWarning {
                Text(session.usingLiDAR
                     ? "还没采到网格：请缓慢平移手机，避免纯白或纯黑表面"
                     : "此设备不支持 LiDAR 网格重建，无法生成扫描网格")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.warn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.warn.opacity(0.45), lineWidth: 1))
            } else {
                Text(currentHints[hintIndex % currentHints.count])
                    .font(.system(size: 12))
                    .foregroundColor(Theme.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .onTapGesture { hintIndex += 1 }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    // MARK: - 底部面板

    private var bottomPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 26) {
                metricRing
                VStack(alignment: .leading, spacing: 10) {
                    metricRow("距离",         session.distance.fixed2 + " m", accent: false)
                    metricRow("网格覆盖率",    "\(Int(session.coverage * 100)) %", accent: true)
                    metricRow("纹理覆盖",      "\(Int(session.texturePct * 100)) %", accent: false)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 12) {
                Button {
                    app.cancelScan()
                } label: {
                    Text("取消")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text2)
                        .frame(width: 88, height: 46)
                        .background(Theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(Theme.stroke, lineWidth: 1))
                }

                Button {
                    paused.toggle()
                    if paused { session.stop() } else { session.start() }
                } label: {
                    Text(paused ? "继续" : "暂停")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text)
                        .frame(width: 88, height: 46)
                        .background(Theme.chip)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }

                Button {
                    app.finishScan()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                        Text("完成")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 18)
        .padding(.bottom, 26)
        .background(
            LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.72)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var metricRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: 6)
                .frame(width: 92, height: 92)
            Circle()
                .trim(from: 0, to: CGFloat(session.coverage))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 92, height: 92)
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: session.coverage)
            VStack(spacing: 1) {
                Text("\(Int(session.coverage * 100))")
                    .font(.system(size: 24, weight: .semibold).monospaced())
                    .foregroundColor(Theme.text)
                Text("%")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.text3)
            }
        }
    }

    private func metricRow(_ label: String, _ value: String, accent: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.text3)
                .frame(width: 66, alignment: .leading)
            Text(value)
                .font(accent ? Theme.dataAccent : Theme.data)
                .foregroundColor(accent ? Theme.accent : Theme.text)
        }
    }
}
