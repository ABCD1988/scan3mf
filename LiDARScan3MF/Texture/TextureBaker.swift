import Foundation
import ARKit
import CoreVideo
import simd

/// 一个彩色关键帧：相机位姿 + 降采样后的 RGB 像素
///
/// 内存控制：1920×1440 的相帧按 step=4 降采样后约 480×360×3 ≈ 518 KB，
/// 上限 40 帧 ≈ 20 MB，可接受。
struct ColorKeyFrame {
    let view: simd_float4x4          // 世界 → 相机
    let proj: simd_float4x4          // 相机 → 裁剪
    let camPos: SIMD3<Float>         // 相机在世界坐标中的位置
    let width: Int
    let height: Int
    let rgb: [UInt8]                 // 行优先，每像素 3 字节
}

/// 彩色关键帧采集 + 多视角顶点着色
enum TextureBaker {

    // MARK: - 关键帧采集

    /// 从 ARFrame 抽一个降采样彩色帧；失败返回 nil
    static func captureKeyFrame(_ frame: ARFrame, step: Int = 4) -> ColorKeyFrame? {
        guard let pb = frame.capturedImage as CVPixelBuffer? else { return nil }

        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        guard w > 0, h > 0, step > 0 else { return nil }

        guard let baseY = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return nil }
        let bprY = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let yPtr = baseY.assumingMemoryBound(to: UInt8.self)

        let planeCount = CVPixelBufferGetPlaneCount(pb)
        let format = CVPixelBufferGetPixelFormatType(pb)
        // iPhone 相机是双平面 NV12（CbCr 交错），不是三平面
        let isBiPlanar = format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                      || format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let fullRange = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange

        var cPtr: UnsafePointer<UInt8>? = nil
        var bprC: Int = 0
        if planeCount >= 2, let baseC = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
            // UnsafeMutablePointer → UnsafePointer 要显式构造，不能隐式转换
            cPtr = UnsafePointer<UInt8>(baseC.assumingMemoryBound(to: UInt8.self))
            bprC = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        }

        // 色度采样步长：Y 是 step，UV 是 step/2（420 下采样）
        let uvStep = max(1, step / 2)

        let outW = w / step
        let outH = h / step
        guard outW > 0, outH > 0 else { return nil }

        var rgb = [UInt8]()
        rgb.reserveCapacity(outW * outH * 3)

        let yOffset: Float = fullRange ? 0 : 16
        let yScale: Float = fullRange ? 1.0 : (255.0 / 219.0)

        var oy = 0
        while oy < outH {
            var ox = 0
            while ox < outW {
                let px = ox * step
                let py = oy * step
                let yv = Float(yPtr[py * bprY + px])

                var cb: Float = 128
                var cr: Float = 128
                if let cp = cPtr {
                    let cx = px / 2
                    let cy = py / 2
                    if isBiPlanar {
                        // NV12：Cb、Cr 在同一个平面里交错排列
                        let base = cy * bprC + cx * 2
                        cb = Float(cp[base])
                        cr = Float(cp[base + 1])
                    } else {
                        // 三平面：plane1 全是 Cb，plane2 全是 Cr（这里退化为只用 Cb 平面按步长取）
                        cb = Float(cp[cy * bprC + cx])
                        if planeCount >= 3, let baseCr = CVPixelBufferGetBaseAddressOfPlane(pb, 2) {
                            let crPtr = baseCr.assumingMemoryBound(to: UInt8.self)
                            cr = Float(crPtr[cy * bprC + cx])
                        }
                    }
                }
                _ = uvStep

                let yp = (yv - yOffset) * yScale
                let c1 = cb - 128
                let c2 = cr - 128
                // BT.601
                var r = yp + 1.402 * c2
                var g = yp - 0.344136 * c1 - 0.714136 * c2
                var b = yp + 1.772 * c1
                r = min(255, max(0, r))
                g = min(255, max(0, g))
                b = min(255, max(0, b))
                rgb.append(UInt8(r))
                rgb.append(UInt8(g))
                rgb.append(UInt8(b))
                ox += 1
            }
            oy += 1
        }

        let view = frame.camera.viewMatrix(for: .portrait)
        let viewport = CGSize(width: 390, height: 844)
        let proj = frame.camera.projectionMatrix(for: .portrait,
                                                 viewportSize: viewport,
                                                 zNear: 0.01,
                                                 zFar: 40)
        let invView = view.inverse
        let camPos = SIMD3<Float>(invView.columns.3.x, invView.columns.3.y, invView.columns.3.z)

        return ColorKeyFrame(view: view,
                             proj: proj,
                             camPos: camPos,
                             width: outW,
                             height: outH,
                             rgb: rgb)
    }

    // MARK: - 多视角顶点着色

    /// 给网格上真实颜色：对每个顶点，在所有关键帧里挑"看得最正"的那一帧取色
    static func bake(_ mesh: MeshData, frames: [ColorKeyFrame]) -> MeshData {
        guard !mesh.isEmpty, !frames.isEmpty else { return mesh }

        // 顶点数 × 帧数控制在 300 万以内，避免完成扫描时卡太久
        let budget = 3_000_000
        var usedFrames = frames
        if mesh.vertexCount * frames.count > budget {
            let keep = max(8, budget / max(1, mesh.vertexCount))
            usedFrames = Array(frames.suffix(keep))
        }

        // 1) 顶点法线（面积加权）
        var normals = [SIMD3<Float>](repeating: SIMD3<Float>(0, 0, 0), count: mesh.vertexCount)
        var i = 0
        while i + 2 < mesh.indices.count {
            let ia = mesh.indices[i], ib = mesh.indices[i + 1], ic = mesh.indices[i + 2]
            let n = mesh.faceNormal(ia, ib, ic)
            normals[Int(ia)] += n
            normals[Int(ib)] += n
            normals[Int(ic)] += n
            i += 3
        }
        for k in 0..<normals.count {
            let len = simd_length(normals[k])
            if len > 0.00001 { normals[k] /= len }
        }

        // 2) 逐帧打分取色
        var bestScore = [Float](repeating: -2, count: mesh.vertexCount)
        var colors = [SIMD3<UInt8>](repeating: SIMD3<UInt8>(150, 150, 150), count: mesh.vertexCount)

        for f in usedFrames {
            let m = f.proj * f.view
            for v in 0..<mesh.vertexCount {
                let p = mesh.vertices[v]
                let clip = m * SIMD4<Float>(p, 1)
                guard clip.w > 0.0001 else { continue }
                let nx = clip.x / clip.w
                let ny = clip.y / clip.w
                if nx < -1 || nx > 1 || ny < -1 || ny > 1 { continue }

                // 传感器横置：竖屏 NDC → 影像像素（近似映射）
                let u = (ny + 1) * 0.5
                let t = 1 - (nx + 1) * 0.5
                let px = min(f.width - 1, max(0, Int(u * Float(f.width))))
                let py = min(f.height - 1, max(0, Int(t * Float(f.height))))

                // 视线与法线夹角：正对相机的面取色最准
                var toCam = f.camPos - p
                let len = simd_length(toCam)
                guard len > 0.0001 else { continue }
                toCam /= len
                let facing = simd_dot(normals[v], toCam)
                guard facing > 0.2 else { continue }   // 背对相机的一面不取色

                // 距离越近越可信，做一点加权
                let distScore = 1.0 / (1.0 + len * 0.35)
                let score = facing * 0.75 + distScore * 0.25
                if score > bestScore[v] {
                    bestScore[v] = score
                    let idx = (py * f.width + px) * 3
                    colors[v] = SIMD3<UInt8>(f.rgb[idx], f.rgb[idx + 1], f.rgb[idx + 2])
                }
            }
        }

        var out = mesh
        out.vertexColors = colors
        return out
    }

    /// 单帧兜底着色（关键帧为空时使用）
    static func bake(_ mesh: MeshData, frame: ARFrame) -> MeshData {
        guard let kf = captureKeyFrame(frame) else { return mesh }
        return bake(mesh, frames: [kf])
    }
}
