import Foundation

/// Draw Things imported model identifiers, not bundled weights or a remote service.
public struct DrawThingsLoRA: Codable, Equatable {
    public var file: String
    public var weight: Double
    public var version: String? = nil
    public init(file: String, weight: Double, version: String? = nil) { self.file = file; self.weight = weight; self.version = version }
}

public struct RenderRecipe: Codable, Equatable {
    public var model: String
    public var sampler: Int
    public var seedMode: Int
    public var guidanceScale: Double
    public var resolutionDependentShift: Bool
    public var loras: [DrawThingsLoRA]
    /// A tested starting preset; other models require their own compatible settings.
    public static let zImageTurbo = RenderRecipe(model: "z_image_turbo_1.0_q6p.ckpt", sampler: 17, seedMode: 2, guidanceScale: 1, resolutionDependentShift: false, loras: [])
    public init(model: String, sampler: Int, seedMode: Int, guidanceScale: Double, resolutionDependentShift: Bool, loras: [DrawThingsLoRA]) {
        self.model = model; self.sampler = sampler; self.seedMode = seedMode
        self.guidanceScale = guidanceScale; self.resolutionDependentShift = resolutionDependentShift; self.loras = loras
    }
    public func validate() throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sampler >= 0, seedMode >= 0,
              guidanceScale.isFinite, guidanceScale >= 0, Float(guidanceScale).isFinite,
              loras.allSatisfy({ !$0.file.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.weight.isFinite && Float($0.weight).isFinite }) else {
            throw MetaPromptError("Renderer recipe requires a model, nonnegative sampler/seed mode/guidance, and LoRAs with identifiers and finite weights.")
        }
    }
}

public struct RendererConfiguration: Codable, Equatable {
    public var executablePath: String
    public var recipe: RenderRecipe
    public init(executablePath: String, recipe: RenderRecipe = .zImageTurbo) {
        self.executablePath = executablePath; self.recipe = recipe
    }
    public func validate() throws {
        guard !executablePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MetaPromptError("Set executablePath in renderer.local.json or choose Draw Things CLI in Settings.")
        }
        try recipe.validate()
    }
}

public struct RendererConfigurationStore {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> RendererConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let configuration = try JSONDecoder().decode(RendererConfiguration.self, from: Data(contentsOf: url))
        try configuration.validate()
        return configuration
    }
    public func save(_ configuration: RendererConfiguration) throws {
        try configuration.validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(configuration).write(to: url, options: .atomic)
    }
}
