import Foundation

/// References and saved recipes only; original images stay in their batch folders.
public struct SavedImageSelection: Codable, Identifiable {
    public let folderPath: String
    public var record: ImageRecord
    public var shortlisted: Bool
    /// Optional so selections saved before rejection support still decode.
    public var rejected: Bool? = nil
    public var id: String { Self.identity(folder: URL(fileURLWithPath: folderPath), filename: record.plan.filename) }
    public static func identity(folder: URL, filename: String) -> String {
        folder.appendingPathComponent(filename).standardizedFileURL.path
    }
    public init(folder: URL, record: ImageRecord, shortlisted: Bool = false) {
        self.folderPath = folder.standardizedFileURL.path; self.record = record
        self.shortlisted = shortlisted
    }
}

public struct ImageSelectionStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [SavedImageSelection] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SavedImageSelection].self, from: Data(contentsOf: url))
    }
    public func save(_ selections: [SavedImageSelection]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(selections).write(to: url, options: .atomic)
    }
}
