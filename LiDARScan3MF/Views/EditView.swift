import SwiftUI
import SceneKit
import Metal
import ModelIO

/// SceneKit 网格预览（线框）
struct MeshPreviewView: UIViewRepresentable {
    let mesh: MeshData?
    var wireframe: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.autoenablesDefaultLighting = true
        v.allowsCameraControl = true
        v.antialiasingMode = .multisampling2X
        return v
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let mesh = mesh, !mesh.isEmpty else {
            uiView.scene = nil
            return
        }
        let scene = SCNScene()
        let node = SCNScene.loadMesh(mesh, wireframe: wireframe)
        scene.rootNode.addChildNode(node)

        let camera = SCNNode()
        camera.camera = SCNCamera()
        let d = max(0.35, mesh.maxDimension * 2.4)
        camera.position = SCNVector3(0, 0, d)
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 100
        scene.rootNode.addChildNode(camera)

        uiView.scene = scene
        uiView.pointOfView = camera
    }
}

extension SCNScene {
    /// 把 MeshData 转成 SceneKit 节点（先居中再显示）
    static func loadMesh(_ mesh: MeshData, wireframe: Bool) -> SCNNode {
        let centered = mesh.centered()
        let node = SCNNode()

        guard let device = MTLCreateSystemDefaultDevice(),
              let mdl = centered.toMDLMesh(device: device) else { return node }

        let geometry = SCNGeometry(mdlMesh: mdl)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(red: 0.21, green: 0.89, blue: 0.76, alpha: 1.0)
        material.emission.contents = UIColor(red: 0.06, green: 0.22, blue: 0.20, alpha: 1.0)
        material.roughness.contents = 0.75
        material.metalness.contents = 0.0
        material.fillMode = wireframe ? .lines : .fill
        material.isDoubleSided = true
        geometry.materials = [material]

        node.geometry = geometry
        return node
    }
}

/// 第 3 屏：编辑与修复
struct EditView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showSaveDialog = false
    @State private var saveName = ""

    private var mesh: MeshData? { app.mesh }

    private var settingsButton: some View {
        HStack(spacing: 5) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
            Text("细部化")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(Theme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.card)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .onTapGesture { app.screen = .detail }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                NavBar(title: "编辑模型",
                       onBack: { app.screen = .home },
                       trailing: AnyView(settingsButton))
                    .padding(.horizontal, 20)

                // 预览区
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.card)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 1)
                    MeshPreviewView(mesh: mesh, wireframe: true)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    // 角标数据
                    VStack {
                        HStack {
                            Text("\(mesh?.faceCount.grouped ?? "0") 面")
                                .font(Theme.data)
                                .foregroundColor(Theme.accent)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                            Spacer()
                            Text(mesh.map { String(format: "%.0f × %.0f × %.0f mm",
                                                   abs($0.size.x * 1000),
                                                   abs($0.size.y * 1000),
                                                   abs($0.size.z * 1000)) } ?? "-")
                                .font(Theme.data)
                                .foregroundColor(Theme.text2)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                        }
                        Spacer()
                    }
                    .padding(12)
                }
                .frame(height: 300)
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 工具 chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        toolChip("降噪", icon: "wand.and.stars") { runDenoise() }
                        toolChip("补洞", icon: "circle.dashed") { runFillHoles() }
                        toolChip("简化", icon: "square.on.square.dashed") { runSimplify() }
                        toolChip("平滑", icon: "water.waves") { runSmooth() }
                        toolChip("裁剪", icon: "crop") { app.toast = "裁剪将在下一版本提供" }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.top, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        printCheckCard
                        Color.clear.frame(height: 4)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                // 底部动作
                HStack(spacing: 12) {
                    Button {
                        saveName = "扫描 \(shortStamp())"
                        showSaveDialog = true
                    } label: {
                        Text("保存到模型库")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Theme.chip)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    Button {
                        app.screen = .export
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("导出")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(Theme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 20)
            }
        }
        .alert("保存模型", isPresented: $showSaveDialog) {
            TextField("模型名称", text: $saveName)
            Button("保存") { app.saveCurrentModel(named: saveName) }
            Button("取消", role: .cancel) { }
        } message: {
            Text("模型将以 OBJ 格式存入本地模型库。")
        }
    }

    // MARK: - 工具 chip

    private func toolChip(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
            Text(title)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundColor(Theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(Theme.stroke, lineWidth: 1))
        .onTapGesture { action() }
    }

    // MARK: - 打印检查卡

    private var printCheckCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("3D 打印检查")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text)
                    Spacer()
                    Text(app.isWatertight ? "通过" : "需处理")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(app.isWatertight ? Theme.accent : Color(hex: 0xE2A85A))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background((app.isWatertight ? Theme.accent : Color(hex: 0xE2A85A)).opacity(0.12))
                        .clipShape(Capsule())
                }
                checkRow("水密性", app.isWatertight ? "封闭实体" : "存在开口", ok: app.isWatertight)
                checkRow("开放边界", "\(app.holeCount) 处", ok: app.holeCount == 0)
                checkRow("面数规模", "\(app.mesh?.faceCount.grouped ?? "0") 面", ok: true)
                checkRow("最小壁厚", app.mesh == nil ? "-" : minWallThickness(), ok: true)
            }
        }
    }

    private func checkRow(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundColor(ok ? Theme.accent : Color(hex: 0xE2A85A))
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.text2)
            Spacer()
            Text(value)
                .font(Theme.data)
                .foregroundColor(Theme.text)
        }
    }

    /// 壁厚估算（启发式）：取包围盒最短边长的比例作为参考值
    private func minWallThickness() -> String {
        guard let m = app.mesh else { return "-" }
        let s = m.size
        let shortest = min(abs(s.x), min(abs(s.y), abs(s.z))) * 1000
        let estimate = max(0.8, shortest * 0.02)
        return String(format: "约 %.1f mm", estimate)
    }

    private func shortStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: Date())
    }

    // MARK: - 工具动作

    private func runDenoise() {
        guard let m = app.mesh else { return }
        app.mesh = MeshProcessor.clean(m)
        app.refreshStats()
        app.toast = "已移除退化面"
    }

    private func runFillHoles() {
        guard let m = app.mesh else { return }
        let r = MeshProcessor.fillHoles(m)
        app.mesh = MeshProcessor.clean(r.mesh)
        app.refreshStats()
        app.toast = r.filled > 0 ? "已补 \(r.filled) 个洞" : "未检测到可补的洞"
    }

    private func runSimplify() {
        guard let m = app.mesh else { return }
        let target = max(2_000, m.faceCount / 2)
        app.mesh = MeshProcessor.simplify(m, targetFaces: target)
        app.refreshStats()
        app.toast = "已简化至 \(app.mesh?.faceCount.grouped ?? "0") 面"
    }

    private func runSmooth() {
        guard let m = app.mesh else { return }
        app.mesh = MeshProcessor.smooth(m, strength: max(0.25, app.settings.smoothing))
        app.refreshStats()
        app.toast = "已应用拉普拉斯平滑"
    }
}
