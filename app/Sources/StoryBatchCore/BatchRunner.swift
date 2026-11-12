import Foundation
import Darwin

public final class BatchRunner {
    private let lock = NSLock()
    private var cancelled = false
    private var finishAfterCurrent = false
    private var hasClaimedImage = false
    private var current: Process?
    private var currentNumber: Int?
    private var skipRequested = false
    private var yieldedPending = false
    private var queuedNumbers: Set<Int>
    private var removedNumbers: Set<Int> = []
    public init(queuedImageNumbers: [Int] = []) { queuedNumbers = Set(queuedImageNumbers) }
    /// Yield at the next image boundary; atomically identify jobs not yet claimed.
    public func detachPendingImages() -> [Int]? {
        lock.lock(); defer { lock.unlock() }
        guard hasClaimedImage, !cancelled else { return nil }
        finishAfterCurrent = true; yieldedPending = true
        return queuedNumbers.sorted()
    }
    @discardableResult
    public func cancelQueuedImage(number: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, queuedNumbers.remove(number) != nil else { return false }
        removedNumbers.insert(number); return true
    }
    public func cancel() {
        lock.lock(); cancelled = true; let process = current; lock.unlock()
        terminate(process)
    }
    /// Target a specific claimed image so a late click cannot cancel its successor.
    @discardableResult
    public func skipCurrentImage(number: Int) -> Bool {
        lock.lock()
        guard !cancelled, currentNumber == number, !skipRequested else { lock.unlock(); return false }
        skipRequested = true; let process = current; lock.unlock()
        terminate(process)
        return true
    }
    private func terminate(_ process: Process?) {
        guard let process, process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            self.lock.lock(); let same = self.current === process; self.lock.unlock()
            if same && process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
    /// Leave the claimed image running; prevent the next image from being claimed.
    /// During preparation, allow the first available image to finish.
    public func stopAfterCurrentImage() {
        lock.lock(); finishAfterCurrent = true; lock.unlock()
    }
    private var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    @discardableResult
    public func run(prepared: PreparedBatch, outputRoot: URL, executable: URL, continuing previous: BatchReport? = nil,
                    event: @escaping (BatchEvent) -> Void) throws -> BatchReport {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MetaPromptError("Draw Things CLI was not found. Install it or choose its executable in Settings.")
        }
        defer { lock.lock(); let active = current?.isRunning ?? false; lock.unlock(); if active { cancel() } }
        let compiled = prepared.compiled; let p = compiled.parameters
        let stamp = BatchFormatting.fileTimestamp(); let id = prepared.logicalRunID ?? UUID().uuidString
        let requestParameters = prepared.requestParameters ?? p
        let requestedCount = prepared.requestedCountOverride ?? p.count
        let folderName = stamp + "_" + CompiledMetaPrompt.safeComponent(p.title, maxBytes: 70) + "_" + id.prefix(8)
        let folder = previous.map { URL(fileURLWithPath: $0.folder, isDirectory: true) } ?? outputRoot.appendingPathComponent(String(folderName), isDirectory: true)
        if let previous {
            guard previous.parameters.title == compiled.parameters.title,
                  prepared.startingNumber == (previous.images.map(\.plan.number).max() ?? 0) + 1,
                  FileManager.default.fileExists(atPath: folder.appendingPathComponent(previous.reportFilename).path) else {
                throw MetaPromptError("The previous batch is unavailable or does not match this metaprompt.")
            }
        } else if prepared.startingNumber != 1 { throw MetaPromptError("A new batch must start at image 1.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["prompts", "configs", "logs"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        var inputURL: URL?
        var inputRelative: String?
        if let path = prepared.inputImagePath {
            let original = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: original.path) else { throw MetaPromptError("The refinement source image is unavailable: \(path)") }
            let ext = original.pathExtension.isEmpty ? "png" : original.pathExtension.lowercased()
            inputRelative = "inputs/root.\(ext)"
            inputURL = folder.appendingPathComponent(inputRelative!)
            try FileManager.default.createDirectory(at: inputURL!.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: inputURL!.path) { try FileManager.default.copyItem(at: original, to: inputURL!) }
        }
        try compiled.source.write(to: folder.appendingPathComponent("metaprompt.txt"), atomically: true, encoding: .utf8)
        let version = cliVersion(executable)
        var report = BatchReport(id: id, createdAt: BatchFormatting.timestamp(), source: compiled.source, parameters: requestParameters,
                                 executable: executable.path, cliVersion: version, folder: folder.path, reportFilename: "report_" + stamp + ".json", model: (prepared.preview.first?.recipe ?? prepared.rendererRecipe ?? .zImageTurbo).model)
        report.requestedImageCount = requestedCount
        if var existing = previous {
            existing.status = "running"; existing.finishedAt = nil; existing.error = nil
            existing.latestRunID = id
            // Preserve the original header for older image records before updating round defaults.
            for index in existing.images.indices {
                if existing.images[index].sourceMetaprompt == nil { existing.images[index].sourceMetaprompt = existing.sourceMetaprompt }
                if existing.images[index].requestParameters == nil { existing.images[index].requestParameters = existing.parameters }
            }
            let requested = (existing.requestedImageCount ?? existing.parameters.count).addingReportingOverflow(requestedCount)
            guard !requested.overflow else { throw MetaPromptError("Requested image count exceeds the supported limit.") }
            existing.requestedImageCount = requested.partialValue
            if prepared.refinementSource == nil {
                existing.sourceMetaprompt = compiled.source
                existing.parameters = requestParameters
            }
            report = existing
        }
        if let context = prepared.refinementContext { report.refinementContext = context }
        try writeReport(report)
        event(.batchStarted(folder))
        var rng = SystemRandomNumberGenerator()
        func newRecord(_ plan: ImagePlan) -> ImageRecord {
            var record = ImageRecord(plan: plan)
            record.refinementOf = prepared.refinementSource; record.sourceMetaprompt = compiled.source
            record.requestParameters = requestParameters; record.runID = id
            record.inputImageFile = inputRelative; record.inputStrength = prepared.inputStrength
            record.refinementContext = prepared.refinementContext
            return record
        }
        let lastNumber = prepared.startingNumber + p.count - 1
        var number = prepared.startingNumber
        while number <= lastNumber && !isCancelled {
            let offset = number - prepared.startingNumber
            var plan = try prepared.frozenPlans?[offset] ?? (offset < prepared.preview.count ? prepared.preview[offset] : compiled.plan(number: number, roundIndex: offset, using: &rng))
            if plan.recipe == nil { plan.recipe = prepared.rendererRecipe }
            var record = newRecord(plan)
            lock.lock()
            if finishAfterCurrent && hasClaimedImage { lock.unlock(); break }
            let removed = removedNumbers.contains(number)
            queuedNumbers.remove(number)
            if !removed { hasClaimedImage = true; currentNumber = number; skipRequested = false }
            lock.unlock()
            if removed {
                record.status = "skipped"; record.finishedAt = BatchFormatting.timestamp(); record.error = "Removed from queue before generation."
                report.images.append(record); try writeReport(report); try appendEvent(folder, name: "image_skipped", record: record)
                event(.imageSkipped(record))
                if number == lastNumber { break }; number += 1; continue
            }
            let stem = String(plan.filename.dropLast(4))
            let promptRelative = "prompts/" + stem + ".txt"; let configRelative = "configs/" + stem + ".json"; let logRelative = "logs/" + stem + ".log"
            let promptURL = folder.appendingPathComponent(promptRelative); let configURL = folder.appendingPathComponent(configRelative); let logURL = folder.appendingPathComponent(logRelative); let outputURL = folder.appendingPathComponent(plan.filename)
            guard !FileManager.default.fileExists(atPath: outputURL.path) else { throw MetaPromptError("Refusing to overwrite \(plan.filename).") }
            try plan.prompt.write(to: promptURL, atomically: true, encoding: .utf8)
            try plan.configurationJSON(strength: prepared.inputStrength ?? 1).write(to: configURL, atomically: true, encoding: .utf8)
            var args = ["generate", "--local", "--offline", "--no-download-missing", "--model", (plan.recipe ?? .zImageTurbo).model,
                        "--prompt-file", promptURL.path, "--config-file", configURL.path, "--seed", String(plan.seed), "--output", outputURL.path]
            if let inputURL, let strength = prepared.inputStrength {
                args += ["--image", inputURL.path, "--strength", String(strength)]
                if prepared.cropInput { args.append("--crop") }
            }
            record.startedAt = BatchFormatting.timestamp(); record.status = "running"
            record.command = [executable.path] + args; record.logFile = logRelative; record.configurationFile = configRelative; record.promptFile = promptRelative
            report.images.append(record); try writeReport(report); try appendEvent(folder, name: "image_started", record: record)
            event(.imageStarted(record))
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
            let log = try FileHandle(forWritingTo: logURL)
            let start = ProcessInfo.processInfo.systemUptime
            var accumulated = Data(); var launchError: Error?; var exitCode: Int32?
            for attempt in 1...2 {
                let process = Process(); let pipe = Pipe()
                process.executableURL = executable; process.arguments = args; process.currentDirectoryURL = folder
                process.standardOutput = pipe; process.standardError = pipe
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = executable.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
                process.environment = env
                accumulated = Data(); launchError = nil; exitCode = nil
                lock.lock()
                if cancelled || skipRequested { lock.unlock(); break }
                do { try process.run(); current = process; record.renderAttempts = attempt; lock.unlock() }
                catch { lock.unlock(); launchError = error }
                if launchError == nil {
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        try log.write(contentsOf: data); accumulated.append(data)
                        let tail = String(decoding: accumulated.suffix(4096), as: UTF8.self)
                        if let pair = Self.samplingProgress(tail) { event(.progress(image: number, step: pair.0, total: pair.1)) }
                    }
                    process.waitUntilExit(); exitCode = process.terminationStatus
                }
                try? pipe.fileHandleForReading.close()
                lock.lock()
                current = nil
                let interrupted = cancelled || skipRequested
                lock.unlock()
                let succeeded = launchError == nil && exitCode == 0 && Self.isPNG(outputURL)
                // Validation and process-launch failures are not model failures. Never retry user stops/skips.
                guard attempt == 1, launchError == nil, !interrupted, !succeeded else { break }
                // Preserve any failed output, but don't let it masquerade as a successful retry.
                if FileManager.default.fileExists(atPath: outputURL.path) {
                    try FileManager.default.moveItem(at: outputURL, to: folder.appendingPathComponent("logs/" + stem + ".attempt-1.png"))
                }
                let reason = "Render attempt 1 failed (exit \(exitCode ?? -1)); retrying once with the same recipe."
                try log.write(contentsOf: Data(("\n" + reason + "\n").utf8))
                record.elapsedSeconds = ProcessInfo.processInfo.systemUptime - start
                report.images[report.images.count - 1] = record
                try writeReport(report); try appendEvent(folder, name: "image_retry", record: record)
                event(.message("\(plan.filename) · " + reason))
                event(.progress(image: number, step: 0, total: plan.steps))
            }
            try? log.close()
            lock.lock()
            let skipped = skipRequested
            current = nil; currentNumber = nil; skipRequested = false
            lock.unlock()
            record.elapsedSeconds = ProcessInfo.processInfo.systemUptime - start; record.finishedAt = BatchFormatting.timestamp()
            let text = String(decoding: accumulated, as: UTF8.self)
            record.generationSeconds = Self.captureNumber(#"Total generation time \(including model loading\):\s*([0-9.]+)\s*s"#, text)
            record.actualSteps = Self.captureNumber(#"Sampling step time \(([0-9]+) step"#, text).map(Int.init)
            record.exitCode = exitCode
            let outputValid = Self.isPNG(outputURL)
            if skipped && !isCancelled {
                record.status = "skipped"; record.error = "Skipped by user while generating."
                report.images[report.images.count - 1] = record
                try writeReport(report); try appendEvent(folder, name: "image_skipped", record: record)
                event(.imageFinished(record))
            } else if !isCancelled && launchError == nil && exitCode == 0 && outputValid {
                record.status = "completed"
                record.outputBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int)
                report.images[report.images.count - 1] = record
                try writeReport(report); try appendEvent(folder, name: "image_finished", record: record)
                let line = BatchFormatting.finishedLine(record); print(line); fflush(stdout)
                event(.imageFinished(record))
            } else {
                record.status = isCancelled ? "cancelled" : "failed"
                record.error = launchError?.localizedDescription ?? (isCancelled ? "Stopped by user." : "Draw Things exited with code \(exitCode ?? -1). " + (outputValid ? "" : "No complete PNG was written. ") + Self.cleanLog(text).components(separatedBy: .newlines).suffix(12).joined(separator: "\n"))
                report.images[report.images.count - 1] = record
                report.status = isCancelled ? "cancelled" : "failed"; report.error = record.error
                try writeReport(report); try appendEvent(folder, name: record.status, record: record)
                event(.imageFinished(record)); break
            }
            if number == lastNumber { break }; number += 1
        }
        lock.lock(); let removedAtYield = yieldedPending ? removedNumbers.sorted() : []; lock.unlock()
        for number in removedAtYield where !isCancelled && number >= prepared.startingNumber && number <= lastNumber && !report.images.contains(where: { $0.plan.number == number }) {
            let offset = number - prepared.startingNumber
            let plan = try prepared.frozenPlans?[offset] ?? compiled.plan(number: number, roundIndex: offset, using: &rng)
            var record = newRecord(plan)
            record.status = "skipped"; record.finishedAt = BatchFormatting.timestamp(); record.error = "Removed from queue before generation."
            report.images.append(record); try writeReport(report); try appendEvent(folder, name: "image_skipped", record: record)
            event(.imageSkipped(record))
        }
        if report.status == "running" { report.status = isCancelled ? "cancelled" : "completed" }
        report.finishedAt = BatchFormatting.timestamp(); try writeReport(report)
        if report.status == "cancelled" && !report.images.contains(where: { $0.status == "completed" }) {
            try FileManager.default.removeItem(at: folder)
            event(.batchRemoved(folder))
        }
        event(.batchFinished(report)); return report
    }

    private func cliVersion(_ url: URL) -> String {
        let p = Process(); let pipe = Pipe(); p.executableURL = url; p.arguments = ["--version"]; p.standardOutput = pipe; p.standardError = pipe
        do { try p.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        catch { return "Unavailable: " + error.localizedDescription }
    }
    public static func cleanLog(_ text: String) -> String {
        text.replacingOccurrences(of: #"\u001B\[[0-9;?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
    }
    private static func samplingProgress(_ text: String) -> (Int, Int)? {
        let clean = cleanLog(text)
        guard let regex = try? NSRegularExpression(pattern: #"Sampling\.\.\.\s*([0-9]+)\s*/\s*([0-9]+)"#),
              let match = regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)).last,
              let a = Range(match.range(at: 1), in: clean), let b = Range(match.range(at: 2), in: clean),
              let step = Int(clean[a]), let total = Int(clean[b]) else { return nil }
        return (step, total)
    }
    private static func captureNumber(_ pattern: String, _ text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let r = Range(m.range(at: 1), in: text) else { return nil }
        return Double(text[r])
    }
    private static func isPNG(_ url: URL) -> Bool {
        guard let f = try? FileHandle(forReadingFrom: url) else { return false }; defer { try? f.close() }
        guard let data = try? f.read(upToCount: 24), data.count == 24 else { return false }
        guard data.prefix(8) == Data([137,80,78,71,13,10,26,10]),
              let size = try? f.seekToEnd(), size >= 36 else { return false }
        try? f.seek(toOffset: size - 12)
        return (try? f.read(upToCount: 12)) == Data([0,0,0,0,73,69,78,68,174,66,96,130])
    }
    private func writeReport(_ report: BatchReport) throws {
        let folder = URL(fileURLWithPath: report.folder, isDirectory: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: folder.appendingPathComponent(report.reportFilename), options: .atomic)
        var text = "# \(report.parameters.title)\n\nCreated: \(report.createdAt)\nStatus: \(report.status)\nRequested images across rounds: \(report.requestedImageCount ?? report.parameters.count)\nModel: \(report.model)\nCLI: \(report.cliVersion)\nNotes: \(report.parameters.notes)\n\n"
        text += "Seed selection: \(report.parameters.seedDescription)\nShift selection: \(report.parameters.shiftDescription)\n\n"
        if let context = report.refinementContext {
            text += "## Refinement source\n\nInput: \(context.sourceImagePath)\nPrompt mode: \(context.promptMode)\n"
            if let batch = context.sourceBatchFolder { text += "Source batch: \(batch)\n" }
            if let filename = context.sourceFilename { text += "Source image: \(filename)\n" }
            text += "\n### Source resolved prompt\n\n" + context.sourcePrompt.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n")
            text += "\n\n### Refinement text\n\n" + context.refinementText.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n") + "\n\n"
        }
        text += "Fixed settings: local/offline; sampler 17 (UniPC Trailing), seed mode 2 (Scale Alike), guidance 1, resolution-dependent shift off, no refiner/upscaler. Explicit shifts retain their supplied spelling; Draw Things itself uses Float32 precision.\n\n"
        for image in report.images {
            let p = image.plan
            text += "## Image \(p.number): \(p.filename)\n\nStatus: \(image.status)\nSeed: \(p.seed)\nShift: \(p.shift.text)\nSteps: \(p.steps)\nResolution: \(p.width)*\(p.height)\n"
            text += "Model for this image: \(p.recipe?.model ?? report.model)\n"
            if let attempts = image.renderAttempts { text += "Render attempts: \(attempts)\n" }
            if let elapsed = image.elapsedSeconds { text += "Elapsed: \(String(format: "%.3f", elapsed)) seconds\n" }
            if let generation = image.generationSeconds { text += "CLI generation including model loading: \(generation) seconds\n" }
            if let actual = image.actualSteps { text += "Actual sampling steps: \(actual)\n" }
            if let original = image.refinementOf { text += "Refinement of: \(original)\n" }
            if let input = image.inputImageFile { text += "Image input: \(input)\n" }
            if let strength = image.inputStrength { text += "Image-to-image strength: \(strength)\n" }
            if let context = image.refinementContext { text += "Prompt construction: \(context.promptMode)\n" }
            if let parameters = image.requestParameters { text += "Notes for this round: \(parameters.notes)\n" }
            if let error = image.error { text += "Error: \(error)\n" }
            text += "\n### Expanded prompt\n\n" + p.prompt.components(separatedBy: "\n").map { "    " + $0 }.joined(separator: "\n") + "\n\n"
        }
        let markdown = report.reportFilename.replacingOccurrences(of: ".json", with: ".md")
        try text.write(to: folder.appendingPathComponent(markdown), atomically: true, encoding: .utf8)
    }
    private func appendEvent(_ folder: URL, name: String, record: ImageRecord) throws {
        let url = folder.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        struct EventRecord: Encodable { let timestamp: String; let event: String; let filename: String; let elapsedSeconds: Double?; let image: ImageRecord }
        let data = try JSONEncoder().encode(EventRecord(timestamp: BatchFormatting.timestamp(), event: name, filename: record.plan.filename, elapsedSeconds: record.elapsedSeconds, image: record))
        let file = try FileHandle(forWritingTo: url); defer { try? file.close() }; try file.seekToEnd(); try file.write(contentsOf: data + Data([10])); try file.synchronize()
    }
}
