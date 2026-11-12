import Foundation

public struct EditorSession: Codable, Equatable {
    public let source: String
    public let lastReportPath: String?
    public let outputRoot: String?
    public init(source: String, lastReportPath: String?, outputRoot: String? = nil) {
        self.source = source; self.lastReportPath = lastReportPath; self.outputRoot = outputRoot
    }
}

public struct EditorSessionStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> EditorSession? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(EditorSession.self, from: Data(contentsOf: url))
    }
    public func save(_ session: EditorSession) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(session).write(to: url, options: .atomic)
    }
}
