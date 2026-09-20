import Foundation
import Combine

/// 本地模型库：Documents/models/ 下存 OBJ 文件 + models.json 元数据
final class ModelStore: ObservableObject {
    @Published private(set) var models: [ScanModel] = []

    let dir: URL
    private let metaURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        dir = docs.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        metaURL = dir.appendingPathComponent("models.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: metaURL),
              let list = try? JSONDecoder().decode([ScanModel].self, from: data) else { return }
        models = list
    }

    func persist() {
        guard let data = try? JSONEncoder().encode(models) else { return }
        try? data.write(to: metaURL, options: .atomic)
    }

    func add(_ model: ScanModel) {
        models.insert(model, at: 0)
        persist()
    }

    func delete(_ model: ScanModel) {
        models.removeAll { $0.id == model.id }
        try? FileManager.default.removeItem(at: url(for: model))
        persist()
    }

    func url(for model: ScanModel) -> URL {
        dir.appendingPathComponent(model.fileName)
    }

    var usedMB: Double {
        let bytes = models.reduce(0.0) { acc, m in
            let attr = try? FileManager.default.attributesOfItem(atPath: url(for: m).path)
            return acc + ((attr?[.size] as? Double) ?? 0)
        }
        return bytes / 1_048_576.0
    }

    var freeMB: Double {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let v = try? docs.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Double(v?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_048_576.0
    }
}
