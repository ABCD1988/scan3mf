import Foundation

struct ScanModel: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date
    var faceCount: Int
    var vertexCount: Int
    var sizeMM: [Double]
    var watertight: Bool
    var holeCount: Int
    var fileName: String

    var createdLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: createdAt)
    }

    var sizeLabel: String {
        guard sizeMM.count == 3 else { return "-" }
        return String(format: "%.1f × %.1f × %.1f mm", sizeMM[0], sizeMM[1], sizeMM[2])
    }

    var statusLabel: String {
        watertight ? "水密通过" : "待修复 \(holeCount)"
    }
}
