import Foundation
import ARKit
import CoreVideo
import simd

/// 纹理烘焙（MVP）：把最后一帧相机影像按顶点投影采色，写入 vertexColors
///
/// 已知局限（README 已声明）：
/// - 只使用最后一帧，未做多视角融合与接缝处理
/// - 仅校正画幅比例、未逐帧精确求解外参旋转，允许存在整体色偏
enum TextureBaker {

    /// 返回带顶点色的网格副本；失败时原样返回
    static func bake(_ mesh: MeshData, frame: ARFrame, resolution: Int) -> MeshData {
        guard let pixels = frame.capturedImage as CVPixelBuffer? else { return mesh }

        let width = CVPixelBufferGetWidth(pixels)
        let height = CVPixelBufferGetHeight(pixels)
        guard width > 0, height > 0 else { return mesh }

        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }

        guard let baseY = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return mesh }
        let bprY = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let hasChroma = CVPixelBufferGetPlaneCount(pixels) > 1
        var baseCb: UnsafeMutableRawPointer? = nil
        var baseCr: UnsafeMutableRawPointer? = nil
        var bprC: Int = 0
        if hasChroma {
            baseCb = CVPixelBufferGetBaseAddressOfPlane(pixels, 1)
            baseCr = CVPixelBufferGetBaseAddressOfPlane(pixels, 2)
            bprC = CVPixelBufferGetBytesPerRowOfPlane(pixels, 1)
        }

        let yPtr = UnsafePointer<UInt8>(baseY.assumingMemoryBound(to: UInt8.self))

        // 投影矩阵：世界 → NDC
        let viewport = CGSize(width: 390, height: 844)
        let view = frame.camera.viewMatrix(for: .portrait)
        let proj = frame.camera.projectionMatrix(for: .portrait,
                                                 viewportSize: viewport,
                                                 zNear: 0.01,
                                                 zFar: 40)
        let vp = proj * view

        var out = mesh
        var colors = [SIMD3<UInt8>]()
        colors.reserveCapacity(mesh.vertexCount)

        for v in mesh.vertices {
            let clip = vp * SIMD4<Float>(v, 1)
            guard clip.w > 0.0001 else {
                colors.append(SIMD3<UInt8>(128, 128, 128))
                continue
            }
            let ndc = SIMD3<Float>(clip.x / clip.w, clip.y / clip.w, clip.z / clip.w)
            // 传感器横置：把竖屏 NDC 映射回影像像素坐标（近似）
            let u = (ndc.y + 1) * 0.5
            let t = 1 - (ndc.x + 1) * 0.5
            guard u >= 0, u <= 1, t >= 0, t <= 1 else {
                colors.append(SIMD3<UInt8>(128, 128, 128))
                continue
            }

            let px = min(width - 1, max(0, Int(u * Float(width))))
            let py = min(height - 1, max(0, Int(t * Float(height))))

            let yy = Float(yPtr[py * bprY + px])

            var cb: Float = 128, cr: Float = 128
            if hasChroma, let cbBase = baseCb, let crBase = baseCr {
                let cx = min(width / 2 - 1, max(0, px / 2))
                let cy = min(height / 2 - 1, max(0, py / 2))
                let cbPtr = cbBase.assumingMemoryBound(to: UInt8.self)
                let crPtr = crBase.assumingMemoryBound(to: UInt8.self)
                cb = Float(cbPtr[cy * bprC + cx])
                cr = Float(crPtr[cy * bprC + cx])
            }

            // YCbCr → RGB（BT.601 视频范围）
            let y1 = (yy - 16) * 1.164
            let c1 = cb - 128
            let c2 = cr - 128
            var r = y1 + 1.596 * c2
            var g = y1 - 0.392 * c1 - 0.813 * c2
            var b = y1 + 2.017 * c1
            r = min(255, max(0, r))
            g = min(255, max(0, g))
            b = min(255, max(0, b))
            _ = resolution
            colors.append(SIMD3<UInt8>(UInt8(r), UInt8(g), UInt8(b)))
        }

        out.vertexColors = colors
        return out
    }
}
