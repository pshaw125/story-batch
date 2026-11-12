import Foundation

public enum GenerationDefaults {
    public static let model = RenderRecipe.zImageTurbo.model
    public static func executable() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        let paths = [environment["STORYBATCH_CLI"]].compactMap { $0 } + (environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/draw-things-cli" }
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
}

/// Records how a refinement prompt was assembled. The model receives only the
/// final resolved prompt; this is provenance for later review.
public struct RefinementContext: Codable, Equatable {
    public let sourceImagePath: String
    public let sourceBatchFolder: String?
    public let sourceFilename: String?
    public let sourcePrompt: String
    public let promptMode: String
    public let refinementText: String
    public init(sourceImagePath: String, sourceBatchFolder: String?, sourceFilename: String?, sourcePrompt: String, promptMode: String, refinementText: String) {
        self.sourceImagePath = sourceImagePath; self.sourceBatchFolder = sourceBatchFolder; self.sourceFilename = sourceFilename
        self.sourcePrompt = sourcePrompt; self.promptMode = promptMode; self.refinementText = refinementText
    }
}

public struct ImagePlan: Codable, Equatable, Identifiable {
    public var id: Int { number }
    public let number: Int
    public let seed: Int
    public let shift: ShiftValue
    public let steps: Int
    public let width: Int
    public let height: Int
    public let prompt: String
    public let filename: String
    public var recipe: RenderRecipe? = nil
    public var refinementSteps: [Int] { [4, 6, 7, 8].filter { $0 > steps } }
    public init(number: Int, seed: Int, shift: ShiftValue, steps: Int, width: Int, height: Int, prompt: String, filename: String, recipe: RenderRecipe? = nil) {
        self.number = number; self.seed = seed; self.shift = shift; self.steps = steps
        self.width = width; self.height = height; self.prompt = prompt; self.filename = filename; self.recipe = recipe
    }

    public func configurationJSON(strength: Double = 1) throws -> String {
        let recipe = recipe ?? .zImageTurbo
        try recipe.validate()
        let base: [String: Any] = [
            "model": recipe.model, "width": width, "height": height, "steps": steps,
            "seed": seed, "seedMode": recipe.seedMode, "sampler": recipe.sampler, "guidanceScale": recipe.guidanceScale,
            "resolutionDependentShift": recipe.resolutionDependentShift, "batchSize": 1, "batchCount": 1,
            "strength": strength, "sharpness": 0, "loras": recipe.loras.map { lora -> [String: Any] in
                var value: [String: Any] = ["file": lora.file, "weight": lora.weight]
                if let version = lora.version { value["version"] = version }
                return value
            }, "controls": [], "hiresFix": false,
            "teaCache": false, "tiledDiffusion": false, "tiledDecoding": false,
            "refinerModel": "", "upscaler": ""
        ]
        let data = try JSONSerialization.data(withJSONObject: base, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        var json = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        json.removeLast() // Replace the final brace so the exact shift decimal can be emitted as a JSON number.
        return json + ",\n  \"shift\": " + shift.jsonNumber + "\n}\n"
    }
}

public struct PreparedBatch {
    public private(set) var compiled: CompiledMetaPrompt
    public private(set) var preview: [ImagePlan]
    public private(set) var startingNumber: Int
    public let refinementSource: String?
    public var inputImagePath: String? = nil
    public var inputStrength: Double? = nil
    public var cropInput: Bool = false
    public var refinementContext: RefinementContext? = nil
    public var frozenPlans: [ImagePlan]? = nil
    public var logicalRunID: String? = nil
    public var requestedCountOverride: Int? = nil
    public var requestParameters: BatchParameters? = nil
    public var rendererRecipe: RenderRecipe? = nil
    public func usingRenderer(_ recipe: RenderRecipe) throws -> PreparedBatch {
        try recipe.validate()
        var result = self; result.rendererRecipe = recipe
        result.preview = preview.map { plan in var plan = plan; plan.recipe = recipe; return plan }
        result.frozenPlans = frozenPlans?.map { plan in var plan = plan; plan.recipe = recipe; return plan }
        return result
    }
    /// Execute a frozen image independently without changing its logical request or recipe.
    public func fragment(at offset: Int, runID: String) throws -> PreparedBatch {
        let frozen = try freezingPlans()
        guard let plans = frozen.frozenPlans, plans.indices.contains(offset) else { throw MetaPromptError("Queued image is unavailable.") }
        var result = frozen
        result.requestParameters = requestParameters ?? compiled.parameters
        var parameters = compiled.parameters; parameters.count = 1
        result.compiled = CompiledMetaPrompt(source: compiled.source, parameters: parameters, nodes: compiled.nodes, fieldNodes: compiled.fieldNodes)
        result.preview = [plans[offset]]; result.frozenPlans = [plans[offset]]
        result.startingNumber = plans[offset].number; result.logicalRunID = runID
        result.requestedCountOverride = 0
        return result
    }
    public static func prepare<R: RandomNumberGenerator>(_ source: String, now: Date = Date(), continuing previous: BatchReport? = nil, defaultTitle: String? = nil, using rng: inout R) throws -> PreparedBatch {
        let compiled = try CompiledMetaPrompt.compile(source, now: now, defaultTitle: previous?.parameters.title ?? defaultTitle)
        let lastNumber = previous?.images.map(\.plan.number).max() ?? 0
        if let previous {
            guard previous.parameters.title == compiled.parameters.title else { throw MetaPromptError("A changed title must start a new batch folder.") }
        }
        guard lastNumber < Int.max - compiled.parameters.count else { throw MetaPromptError("Image numbering exceeds the supported limit.") }
        let first = lastNumber + 1
        var preview: [ImagePlan] = []
        for offset in 0..<min(compiled.parameters.count, 4) { preview.append(try compiled.plan(number: first + offset, roundIndex: offset, using: &rng)) }
        return PreparedBatch(compiled: compiled, preview: preview, startingNumber: first, refinementSource: nil)
    }
    public static func prepare(_ source: String, continuing previous: BatchReport? = nil, defaultTitle: String? = nil) throws -> PreparedBatch {
        var rng = SystemRandomNumberGenerator(); return try prepare(source, continuing: previous, defaultTitle: defaultTitle, using: &rng)
    }
    public func freezingPlans() throws -> PreparedBatch {
        if frozenPlans != nil { return self }
        var plans = preview; var rng = SystemRandomNumberGenerator()
        for offset in preview.count..<compiled.parameters.count {
            var plan = try compiled.plan(number: startingNumber + offset, roundIndex: offset, using: &rng)
            plan.recipe = rendererRecipe
            plans.append(plan)
        }
        var result = self; result.frozenPlans = plans; return result
    }
    public func usingImage(path: String, strength: Double, crop: Bool, context: RefinementContext) throws -> PreparedBatch {
        guard strength >= 0, strength <= 1, strength.isFinite else { throw MetaPromptError("Refinement strength must be a finite value from 0 to 1.") }
        guard FileManager.default.fileExists(atPath: path) else { throw MetaPromptError("The refinement source image is unavailable: \(path)") }
        var result = self; result.inputImagePath = path; result.inputStrength = strength; result.cropInput = crop; result.refinementContext = context
        return result
    }
    public func rebased(continuing report: BatchReport) throws -> PreparedBatch {
        guard compiled.parameters.title == report.parameters.title else { throw MetaPromptError("Queued title no longer matches its destination batch.") }
        let last = report.images.map(\.plan.number).max() ?? 0
        guard last < Int.max - compiled.parameters.count else { throw MetaPromptError("Image numbering exceeds the supported limit.") }
        let plans = try freezingPlans().frozenPlans!.enumerated().map { offset, plan in
            try plan.renumbered(last + 1 + offset, title: compiled.parameters.title)
        }
        var result = self
        result.preview = Array(plans.prefix(4)); result.startingNumber = last + 1; result.frozenPlans = plans
        return result
    }
    public static func refinement(of source: ImagePlan, steps: Int? = nil, shift: ShiftValue? = nil, continuing previous: BatchReport) throws -> PreparedBatch {
        guard (steps != nil) != (shift != nil),
              steps.map({ source.refinementSteps.contains($0) }) ?? true,
              previous.images.contains(where: { $0.plan == source && $0.status == "completed" }) else {
            throw MetaPromptError("Choose one available step or shift adjustment for a completed image.")
        }
        let steps = steps ?? source.steps
        let shift = shift ?? source.shift
        let last = previous.images.map(\.plan.number).max() ?? 0
        guard last < Int.max - 1 else { throw MetaPromptError("Image numbering exceeds the supported limit.") }
        let first = last + 1
        var parameters = previous.parameters
        parameters.count = 1; parameters.steps = steps
        parameters.seed = source.seed; parameters.seedValues = nil; parameters.shift = shift; parameters.shiftRange = nil; parameters.shiftValues = nil; parameters.shiftEntries = nil
        parameters.width = source.width; parameters.height = source.height
        parameters.aspect = nil // A viewer variant keeps the source's exact dimensions.
        try AspectSizing.validate(width: source.width, height: source.height, pixelMax: parameters.pixelMax ?? BatchParameters.defaultPixelMax)
        let parsed = try CompiledMetaPrompt.compile(previous.sourceMetaprompt)
        let compiled = CompiledMetaPrompt(source: previous.sourceMetaprompt, parameters: parameters, nodes: parsed.nodes, fieldNodes: parsed.fieldNodes)
        let suffix = "_\(source.seed)_\(steps)_\(shift.text)_\(first).png"
        guard suffix.utf8.count < 250 else { throw MetaPromptError("The shift spelling is too long to fit in an output filename.") }
        let title = CompiledMetaPrompt.safeComponent(previous.parameters.title, maxBytes: 250 - suffix.utf8.count)
        let plan = ImagePlan(number: first, seed: source.seed, shift: shift, steps: steps, width: source.width, height: source.height,
                             prompt: source.prompt, filename: title + suffix, recipe: source.recipe)
        return PreparedBatch(compiled: compiled, preview: [plan], startingNumber: first,
                             refinementSource: URL(fileURLWithPath: previous.folder).appendingPathComponent(source.filename).path)
    }
}

public struct RefinementRequest {
    public var shortlistOnCompletion = false
    public let image: ImagePlan
    public let steps: Int
    public let shift: ShiftValue?
    public let folder: URL
    public init(image: ImagePlan, steps: Int, folder: URL) { self.image = image; self.steps = steps; self.shift = nil; self.folder = folder }
    public init(image: ImagePlan, shift: ShiftValue, folder: URL) { self.image = image; self.steps = image.steps; self.shift = shift; self.folder = folder }
    public var previewPlan: ImagePlan {
        ImagePlan(number: image.number, seed: image.seed, shift: shift ?? image.shift, steps: steps, width: image.width, height: image.height, prompt: image.prompt, filename: image.filename, recipe: image.recipe)
    }
}

extension ImagePlan {
    public func renumbered(_ number: Int, title: String) throws -> ImagePlan {
        let suffix = "_\(seed)_\(steps)_\(shift.text)_\(number).png"
        guard suffix.utf8.count < 250 else { throw MetaPromptError("The shift spelling is too long to fit in an output filename.") }
        return ImagePlan(number: number, seed: seed, shift: shift, steps: steps, width: width, height: height, prompt: prompt,
                         filename: CompiledMetaPrompt.safeComponent(title, maxBytes: 250 - suffix.utf8.count) + suffix, recipe: recipe)
    }
}

extension CompiledMetaPrompt {
    public func plan<R: RandomNumberGenerator>(number: Int, roundIndex: Int? = nil, using rng: inout R) throws -> ImagePlan {
        let p = parameters
        let index = roundIndex ?? (number - 1)
        let seed: Int
        if let values = p.seedValues {
            guard values.indices.contains(index) else { throw MetaPromptError("No seed list value is available for image \(number) in this round.") }
            seed = values[index] ?? Int.random(in: 0...Int(Int32.max), using: &rng)
        } else { seed = p.seed ?? Int.random(in: 0...Int(Int32.max), using: &rng) }
        let shift: ShiftValue
        if let entries = p.shiftEntries {
            guard entries.indices.contains(index) else { throw MetaPromptError("No shift list entry is available for image \(number) in this round.") }
            shift = entries[index].resolve(using: &rng)
        } else if let values = p.shiftValues {
            guard values.indices.contains(index) else { throw MetaPromptError("No shift list value is available for image \(number) in this round.") }
            shift = values[index]
        } else { shift = p.shift ?? p.shiftRange?.random(using: &rng) ?? ShiftValue.random(using: &rng) }
        let suffix = "_\(seed)_\(p.steps)_\(shift.text)_\(number).png"
        let budget = 250 - suffix.utf8.count
        guard budget >= 1 else { throw MetaPromptError("The shift spelling is too long to fit in an output filename.") }
        let title = Self.safeComponent(p.title, maxBytes: budget)
        return ImagePlan(number: number, seed: seed, shift: shift, steps: p.steps, width: p.width, height: p.height,
                         prompt: resolve(using: &rng), filename: title + suffix)
    }
    public static func safeComponent(_ value: String, maxBytes: Int = 100) -> String {
        var result = ""
        for c in value {
            let safe = c.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) || c == "/" || c == "\\" || c == ":" ? "_" : String(c)
            if result.utf8.count + safe.utf8.count > maxBytes { break }
            result += safe
        }
        return result.isEmpty ? "untitled" : result
    }
}

public struct ImageRecord: Codable, Identifiable {
    public var id: Int { plan.number }
    public var plan: ImagePlan
    public var status: String
    public var startedAt: String?
    public var finishedAt: String?
    public var elapsedSeconds: Double?
    public var generationSeconds: Double?
    public var actualSteps: Int?
    public var renderAttempts: Int?
    public var exitCode: Int32?
    public var error: String?
    public var command: [String]?
    public var logFile: String?
    public var configurationFile: String?
    public var promptFile: String?
    public var outputBytes: Int?
    public var refinementOf: String?
    public var sourceMetaprompt: String?
    public var requestParameters: BatchParameters?
    public var runID: String?
    public var inputImageFile: String?
    public var inputStrength: Double?
    public var refinementContext: RefinementContext?
    public init(plan: ImagePlan) { self.plan = plan; status = "planned" }
    /// Reports retain usage order; galleries can prioritize steps or numeric shift within a seed.
    public static func displayOrder(_ records: [ImageRecord], stepsFirst: Bool = true) -> [ImageRecord] {
        records.enumerated().filter { $0.element.status != "skipped" }.sorted {
            let a = $0.element.plan, b = $1.element.plan
            if a.seed != b.seed { return a.seed < b.seed }
            if stepsFirst, a.steps != b.steps { return a.steps < b.steps }
            let x = Decimal(string: a.shift.jsonNumber, locale: Locale(identifier: "en_US_POSIX"))
            let y = Decimal(string: b.shift.jsonNumber, locale: Locale(identifier: "en_US_POSIX"))
            if let x, let y, x != y { return x < y }
            if x == nil || y == nil {
                let dx = Double(a.shift.jsonNumber)!, dy = Double(b.shift.jsonNumber)!
                if dx != dy { return dx < dy }
            }
            if a.steps != b.steps { return a.steps < b.steps }
            if a.number != b.number { return a.number < b.number }
            return $0.offset < $1.offset
        }
        .map(\.element)
    }
}
public struct BatchReport: Codable {
    public let version: Int
    public let id: String
    public let createdAt: String
    public var finishedAt: String?
    public var status: String
    public var sourceMetaprompt: String
    public var parameters: BatchParameters
    public let model: String
    public let executable: String
    public let cliVersion: String
    public let folder: String
    public let reportFilename: String
    public var images: [ImageRecord]
    public var error: String?
    public var requestedImageCount: Int?
    public var latestRunID: String?
    public var refinementContext: RefinementContext?
    public var latestCompletedPlans: [ImagePlan] {
        if let latestRunID { return images.filter { $0.runID == latestRunID && $0.status == "completed" }.map(\.plan) }
        // Older reports did not identify rounds; use the last recorded request's count.
        guard let last = images.last(where: { $0.status == "completed" }) else { return [] }
        return images.filter { $0.status == "completed" }.suffix(last.requestParameters?.count ?? parameters.count).map(\.plan)
    }
    public static func load(in folder: URL) throws -> BatchReport {
        let reports = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("report_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let url = reports.first else { throw MetaPromptError("The image's batch report is missing.") }
        let report = try JSONDecoder().decode(BatchReport.self, from: Data(contentsOf: url))
        guard URL(fileURLWithPath: report.folder).standardizedFileURL == folder.standardizedFileURL else { throw MetaPromptError("The image's batch report does not match this folder.") }
        return report
    }
    public init(id: String, createdAt: String, source: String, parameters: BatchParameters, executable: String, cliVersion: String, folder: String, reportFilename: String, model: String = GenerationDefaults.model) {
        self.version = 1; self.id = id; self.createdAt = createdAt; self.status = "running"
        self.sourceMetaprompt = source; self.parameters = parameters; self.model = model
        self.executable = executable; self.cliVersion = cliVersion; self.folder = folder; self.reportFilename = reportFilename; self.images = []
        self.requestedImageCount = parameters.count
        self.latestRunID = id
    }
}
public enum BatchEvent {
    case batchStarted(URL)
    case batchRemoved(URL)
    case imageStarted(ImageRecord)
    case progress(image: Int, step: Int, total: Int)
    case imageFinished(ImageRecord)
    case imageSkipped(ImageRecord)
    case message(String)
    case batchFinished(BatchReport)
}

public enum BatchFormatting {
    public static func timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.string(from: date)
    }
    public static func fileTimestamp(_ date: Date = Date()) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd_HH-mm-ss_SSS"; return f.string(from: date)
    }
    public static func duration(_ seconds: Double) -> String {
        seconds >= 60 ? String(format: "%dm %.1fs", Int(seconds) / 60, seconds.truncatingRemainder(dividingBy: 60)) : String(format: "%.1fs", seconds)
    }
    public static func finishedLine(_ record: ImageRecord) -> String {
        "Finished \(record.plan.filename) in \(duration(record.elapsedSeconds ?? 0))"
    }
}
