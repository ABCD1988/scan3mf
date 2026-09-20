import Foundation
import simd
import ModelIO
import MetalKit

/// 通用三角网格容器：顶点 + 三角索引（+ 可选逐顶点颜色）
struct MeshData {
    var vertices: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    var vertexColors: [SIMD3<UInt8>]? = nil

    var faceCount: Int { indices.count / 3 }
    var vertexCount: Int { vertices.count }
    var isEmpty: Bool { faceCount == 0 || vertexCount == 0 }

    // MARK: - 包围盒

    var boundsMin: SIMD3<Float> {
        guard var lo = vertices.first else { return .zero }
        for v in vertices {
            lo = simd_min(lo, v)
        }
        return lo
    }

    var boundsMax: SIMD3<Float> {
        guard var hi = vertices.first else { return .zero }
        for v in vertices {
            hi = simd_max(hi, v)
        }
        return hi
    }

    /// 尺寸（米）
    var size: SIMD3<Float> { boundsMax - boundsMin }

    var maxDimension: Float {
        let s = size
        return max(s.x, max(s.y, s.z))
    }

    var center: SIMD3<Float> { (boundsMin + boundsMax) * 0.5 }

    /// 表面积（米²）——用于扫描覆盖率估算
    var surfaceArea: Float {
        var sum: Float = 0
        var i = 0
        while i + 2 < indices.count {
            let a = vertices[Int(indices[i])]
            let b = vertices[Int(indices[i + 1])]
            let c = vertices[Int(indices[i + 2])]
            sum += simd_length(simd_cross(b - a, c - a)) * 0.5
            i += 3
        }
        return sum
    }

    // MARK: - 平移/缩放工具

    /// 返回把网格移到原点附近（包围盒中心归零）后的副本
    func centered() -> MeshData {
        let c = center
        var m = self
        m.vertices = vertices.map { $0 - c }
        return m
    }

    /// 按比例缩放（导出比例用），单位仍为米
    func scaled(by factor: Float) -> MeshData {
        guard abs(factor - 1.0) > 0.0001 else { return self }
        var m = self
        m.vertices = vertices.map { $0 * factor }
        return m
    }

    /// 三角形法线
    func faceNormal(_ i0: UInt32, _ i1: UInt32, _ i2: UInt32) -> SIMD3<Float> {
        let a = vertices[Int(i0)], b = vertices[Int(i1)], c = vertices[Int(i2)]
        let n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        return len > 0 ? n / len : SIMD3<Float>(0, 0, 1)
    }

    // MARK: - ModelIO 桥接（USDZ 导出 / SceneKit 预览）

    /// 生成 MDLMesh（设备坐标系为右手 Y-up，米）
    func mdlMesh(device: MTLDevice? = nil, name: String = "ScanMesh") -> MDLMesh? {
        guard !isEmpty, let device = device ?? MTLCreateSystemDefaultDevice() else { return nil }

        let allocator = MTKMeshBufferAllocator(device: device)

        // 顶点缓冲（Data 构造，避免 newBuffer 重载歧义）
        let vCount = vertices.count
        let vStride = MemoryLayout<SIMD3<Float>>.stride
        let vData = vertices.withUnsafeBufferPointer { buf in Data(buffer: buf) }
        guard let vBuffer = allocator.newBuffer(with: vData, type: .vertex) else { return nil }

        // 索引缓冲
        let iCount = indices.count
        let iData = indices.withUnsafeBufferPointer { buf in Data(buffer: buf) }
        guard let iBuffer = allocator.newBuffer(with: iData, type: .index) else { return nil }

        // 顶点描述符：position only
        let vd = MDLVertexDescriptor()
        vd.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                              format: .float3,
                                              offset: 0,
                                              bufferIndex: 0)
        vd.layouts[0] = MDLVertexBufferLayout(stride: vStride)

        let submesh = MDLSubmesh(indexBuffer: iBuffer,
                                 indexCount: iCount,
                                 indexType: .uInt32,
                                 geometryType: .triangles,
                                 material: nil)

        return MDLMesh(vertexBuffer: vBuffer,
                       vertexCount: vCount,
                       descriptor: vd,
                       submeshes: [submesh])
    }
}
