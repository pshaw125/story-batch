import Foundation

public struct FavoriteImage: Identifiable {
    public let url: URL
    public let source: SavedImageSelection?
    public let record: ImageRecord?
    public var id: String { url.standardizedFileURL.path }
}

private struct FavoriteMetadata: Codable {
    let source: SavedImageSelection
    let record: ImageRecord
}

/// Directory contents, rather than a saved index, determine membership.
public struct FavoritesFolder {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func images() throws -> [FavoriteImage] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        return files.filter { ["png", "jpg", "jpeg", "webp", "heic", "tif", "tiff", "gif", "bmp"].contains($0.pathExtension.lowercased()) && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { file in
                let metadata = try? JSONDecoder().decode(FavoriteMetadata.self, from: Data(contentsOf: file.appendingPathExtension("json")))
                return FavoriteImage(url: file, source: metadata?.source, record: metadata?.record)
            }
    }
    public func add(record: ImageRecord, folder: URL) throws {
        let source = SavedImageSelection(folder: folder, record: record)
        if try images().contains(where: { $0.source?.id == source.id }) { return }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var target = url.appendingPathComponent(record.plan.filename)
        if record.plan.filename.utf8.count > 220 || FileManager.default.fileExists(atPath: target.path) {
            let stem = CompiledMetaPrompt.safeComponent(String(record.plan.filename.dropLast(4)), maxBytes: 180)
            target = url.appendingPathComponent(stem + "_" + UUID().uuidString + "." + URL(fileURLWithPath: record.plan.filename).pathExtension)
        }
        try FileManager.default.copyItem(at: folder.appendingPathComponent(record.plan.filename), to: target)
        var copied = record
        let p = record.plan
        copied.plan = ImagePlan(number: p.number, seed: p.seed, shift: p.shift, steps: p.steps, width: p.width, height: p.height, prompt: p.prompt, filename: target.lastPathComponent, recipe: p.recipe)
        copied.configurationFile = nil
        do {
            if let config = ImageRecipeSnapshot(record: record, folder: folder).configuration {
                let name = target.lastPathComponent + ".config.json"
                try config.write(to: url.appendingPathComponent(name), atomically: true, encoding: .utf8)
                copied.configurationFile = name
            }
            try JSONEncoder().encode(FavoriteMetadata(source: source, record: copied)).write(to: target.appendingPathExtension("json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.removeItem(at: target.appendingPathExtension("config.json"))
            throw error
        }
    }
    public func remove(_ image: FavoriteImage) throws {
        guard image.url.deletingLastPathComponent().standardizedFileURL == url.standardizedFileURL else { return }
        try FileManager.default.removeItem(at: image.url)
        for suffix in ["json", "config.json"] {
            let sidecar = image.url.appendingPathExtension(suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) { try FileManager.default.removeItem(at: sidecar) }
        }
    }
}
