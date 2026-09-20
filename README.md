# Scan3MF · LiDAR 扫描建模 App

iPhone LiDAR 扫描建模，导出 3MF / STL / OBJ / USDZ。目标设备：**iPhone 13 Pro**（LiDAR ✓）。

对应设计稿：`LiDAR扫描建模App-功能界面`（5 屏：首页 / 扫描 / 编辑 / 导出 / 细部化设置），390×844 深色仪器风，强调色激光青 #35E2C2。

## 工程结构

```
LiDARScan3MF/
├─ .github/workflows/build-tipa.yml   # 一键云编译 → .tipa
├─ LiDARScan3MF.xcodeproj             # Xcode 工程（无第三方依赖）
└─ LiDARScan3MF/
   ├─ App/         入口、主题色、全局状态
   ├─ Models/      模型元数据 + 本地模型库
   ├─ Mesh/        ARKit 网格采集、合并、简化/平滑/补洞/水密检查
   ├─ Texture/     摄像头帧 → 顶点色
   ├─ Export/      3MF(OPC+ZIP)、STL、OBJ、USDZ 写出器
   └─ Views/       5 屏 SwiftUI 界面
```

## 三条编译路线

### ① GitHub 云编译（推荐，免费，无需 Mac）

1. 注册/登录 GitHub → 新建仓库（Public 即可）
2. 把 `LiDARScan3MF` 整个文件夹的内容上传（解压 zip 后拖拽上传即可）
3. 仓库页 → **Actions** → 选 **Build TIPA** → **Run workflow**
4. 跑完（约 3-5 分钟）→ 点进这次运行 → **Artifacts** 下载 `LiDARScan3MF-tipa`
5. 得到 `.tipa` → 传到手机（隔空投送不行就用 网盘/文件 App/爱思助手）→ 巨魔安装

### ② 本地 Mac

```bash
xcodebuild -project LiDARScan3MF.xcodeproj -target LiDARScan3MF \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
# 产物 .app 打包成 Payload/*.tipa 或直接 Xcode Run 到真机
```

### ③ Codex CLI / 其他编程 AI

直接把本目录丢给它，说"按 README 的路线②编译"。

## 巨魔（TrollStore）安装要求

**你的设备已确认：iPhone 13 Pro / iOS 16.3 → 巨魔支持 ✓，直接装。**

| iOS 版本 | 巨魔支持 |
|---|---|
| 14.0 – 16.6.1 | ✓ ← **你在这一档（16.3）** |
| 17.0 | ✓（仅部分安装方式） |
| 17.1 及以上 | ✗ 需改用 SideStore / Sideloadly |

具体操作步骤见 **`装机说明.md`**。

## 功能边界（当前 MVP 版本）

- 网格来源：ARKit `sceneReconstruction(.mesh)`（LiDAR 实扫），非拍照建模
- 纹理：MVP 用最后一帧摄像头图像做**顶点色**近似；"纹理来源/分辨率"设置已入库，逐帧深度融合烘焙在下一版实装
- 覆盖率：按已扫表面积 / 1.2㎡ 估算，是引导值不是精确值
- 已实装工具：降噪(拉普拉斯)、补洞(边界环扇形填充)、简化(顶点聚类到目标面数)、平滑；"裁剪"按钮占位
- 水密检查：边界边统计 + 孔洞环计数
- 3MF：标准 OPC 包（`[Content_Types].xml` + `_rels` + `3D/3dmodel.model`），含比例/单位，网格带颜色时写入 basematerials

## 数据位置

- **工程本体**：`C:\Users\xiaoc\Desktop\LiDARScan3MF\`（同目录另有 `LiDARScan3MF.zip`，即本工程的压缩包，可直接上传 GitHub）
- 模型库与导出文件在 App 沙盒 `Documents/models/` 与 `Documents/exports/`；「导出并分享」会弹出系统分享面板，可存到"文件"App 再传电脑。
