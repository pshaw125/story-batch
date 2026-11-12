import Foundation

/// Pinned to the viewed image, never the current editor or a new random draw.
public struct ImageRecipeSnapshot: Identifiable {
    public let id = UUID()
    public let filename: String
    public let prompt: String
    public let parameters: String
    public let configuration: String?
    public var copyText: String {
        filename + "\n\n" + parameters + "\n\nResolved prompt\n" + prompt
            + (configuration.map { "\n\nSaved configuration\n" + $0 } ?? "")
    }
    public init(record: ImageRecord, folder: URL?) {
        filename = record.plan.filename; prompt = record.plan.prompt
        var object: [String: Any]?
        if let folder, let relative = record.configurationFile {
            let root = folder.resolvingSymlinksInPath().standardizedFileURL
            let url = folder.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
            if url.path.hasPrefix(root.path + "/"),
               let data = try? Data(contentsOf: url), data.count <= 1_000_000,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { object = json }
        }
        if let object, let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            configuration = String(decoding: data, as: UTF8.self)
        } else { configuration = nil }
        var lines = ["Seed: \(record.plan.seed)", "Shift: \(record.plan.shift.text)", "Steps: \(record.plan.steps)", "Resolution: \(record.plan.width) × \(record.plan.height)"]
        for (key, label) in [("model", "Model"), ("sampler", "Sampler"), ("seedMode", "Seed mode"), ("guidanceScale", "Guidance"), ("resolutionDependentShift", "Resolution-dependent shift")] {
            if let value = object?[key] { lines.append(label + ": " + String(describing: value)) }
        }
        if let actual = record.actualSteps { lines.append("Reported sampling steps: \(actual)") }
        if let input = record.inputImageFile { lines.append("Image input: \(input)") }
        if let strength = record.inputStrength { lines.append("Image-to-image strength: \(strength)") }
        if let context = record.refinementContext { lines.append("Prompt construction: \(context.promptMode)") }
        if let aspect = record.requestParameters?.aspect { lines.append("Requested aspect: " + aspect) }
        if let limit = record.requestParameters?.pixelMax { lines.append("Pixel maximum: \(limit)") }
        if let elapsed = record.elapsedSeconds { lines.append("Elapsed: " + BatchFormatting.duration(elapsed)) }
        if let notes = record.requestParameters?.notes, !notes.isEmpty { lines.append("Notes: " + notes) }
        parameters = lines.joined(separator: "\n")
    }
}
