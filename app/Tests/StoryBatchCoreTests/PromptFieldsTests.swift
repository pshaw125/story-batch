#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
@testable import StoryBatchCore

private struct FieldRNG: RandomNumberGenerator {
    var state: UInt64 = 123456
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
private struct FieldCountingRNG: RandomNumberGenerator {
    var calls = 0
    mutating func next() -> UInt64 { calls += 1; return 0 }
}

extension StoryBatchCoreTests {
    func testSharedFreshFieldsAndNestedResolution() throws {
        let source = "\n[OUTER]|[OUTER]|[X]|[X]|[X*]|[X*]\n%%FIELDS%%\nOUTER={near|far} [X*] {a|b}\nX={red|green|blue}\nUNUSED={never|draw}"
        let compiled = try CompiledMetaPrompt.compile(source)
        var rng = FieldRNG(); var sharedValues = Set<String>(); var freshVaried = false
        for _ in 0..<150 {
            let parts = compiled.resolve(using: &rng).components(separatedBy: "|")
            XCTAssertEqual(parts.count, 6)
            XCTAssertEqual(parts[0], parts[1], "A shared parent freezes its entire nested result")
            XCTAssertEqual(parts[2], parts[3], "Shared references are identical within the image")
            sharedValues.insert(parts[2]); freshVaried = freshVaried || parts[4] != parts[5]
        }
        XCTAssertGreaterThan(sharedValues.count, 1); XCTAssertTrue(freshVaried)
        let fresh = try CompiledMetaPrompt.compile("\n[X*][X][X][X*]\n%%FIELDS%%\nX={a|b}\nUNUSED={a|b}")
        var counting = FieldCountingRNG(); _ = fresh.resolve(using: &counting)
        XCTAssertEqual(counting.calls, 3, "Fresh occurrences neither seed nor overwrite the shared cache; unused fields draw nothing")
        let global = try CompiledMetaPrompt.compile("\n[A] [B]\n%%FIELDS%%\nA=[B]\nB={red|green}")
        for _ in 0..<30 { let parts = global.resolve(using: &rng).split(separator: " "); XCTAssertEqual(parts.first, parts.last) }
    }

    func testFieldPreflightAndMultilineValues() throws {
        let source = "count=1\n[A] [EMPTY] \\[literal\\]\n%%FIELDS%%\nA=First line\nSecond line [B]\nB={red}\nEMPTY=\n"
        var rng = FieldRNG()
        XCTAssertEqual(try CompiledMetaPrompt.compile(source).resolve(using: &rng), "First line\nSecond line red  [literal]")
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[UNKNOWN]"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[A]\n%%FIELDS%%\nA=[B*]\nB=[A]"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\nplain\n%%FIELDS%%\nUNUSED={[MISSING]:::0|ok}"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[A]\n%%FIELDS%%\nA=red\nA=blue"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[A*\n%%FIELDS%%\nA=red"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[bad-name]"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\nplain\n%%FIELDS%%\nnot a definition"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\nplain\n%%FIELDS%%\nA={missing"))
        let chain = (0..<66).map { i in "F\(i)=" + (i == 0 ? "end" : "[F\(i - 1)]") }.joined(separator: "\n")
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[F65]\n%%FIELDS%%\n" + chain))
        let expansion = "A=" + String(repeating: "x", count: 1024) + "\n" + (1..<12).map { "F\($0)=" + String(repeating: $0 == 1 ? "[A]" : "[F\($0 - 1)]", count: 2) }.joined(separator: "\n")
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("\n[F11]\n%%FIELDS%%\n" + expansion))
    }

    func testExtractionAndFieldBatchIdentity() throws {
        let source = "seed=1234\nA {smile|{left|right}} in {red:::2|green}, holding [FIELD_1]. Literal \\{brace\\}.\n%%FIELDS%%\nFIELD_1={book|cup}"
        let extracted = try PromptDocument(source).extractingChoices()
        XCTAssertTrue(extracted.prompt.contains("[FIELD_2]")); XCTAssertTrue(extracted.prompt.contains("[FIELD_3]"))
        XCTAssertTrue(extracted.fieldsText.contains("FIELD_2={smile|{left|right}}"))
        XCTAssertTrue(extracted.prompt.contains("\\{brace\\}"))
        XCTAssertTrue(CompiledMetaPrompt.samePromptBody(source, extracted.source))
        let before = try CompiledMetaPrompt.compile(source), after = try CompiledMetaPrompt.compile(extracted.source)
        var a = FieldRNG(), b = FieldRNG()
        for _ in 0..<100 { XCTAssertEqual(before.resolve(using: &a), after.resolve(using: &b)) }
        var edited = extracted; edited.fieldsText += "\nNEW=more"; edited.fieldsText = edited.fieldsText.replacingOccurrences(of: "red:::2|green", with: "red|green|blue")
        XCTAssertTrue(CompiledMetaPrompt.samePromptBody(source, edited.source))
        XCTAssertTrue(CompiledMetaPrompt.samePromptBody("\nA {red|green} scarf", "steps=6\nA {blue|gold} scarf"))
        var literalEdit = edited; literalEdit.prompt += " changed template"
        XCTAssertFalse(CompiledMetaPrompt.samePromptBody(source, literalEdit.source))
        let crlf = extracted.source.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertTrue(CompiledMetaPrompt.samePromptBody(crlf, extracted.source))
        XCTAssertEqual(try CompiledMetaPrompt.compile(crlf).fieldNodes, after.fieldNodes)
        XCTAssertEqual(PromptDocument(extracted.source).source, extracted.source)
    }

    func testFieldContinuationFrozenQueueAndRecipeSnapshots() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-batch-fields-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "count=1; seed=19; shift=1.75; resolution=64*64; notes=first\nA [COLOR] scarf and [COLOR] ribbon.\n%%FIELDS%%\nCOLOR={red}"
        let first = try PreparedBatch.prepare(source).freezingPlans()
        let report = try BatchRunner().run(prepared: first, outputRoot: dir, executable: cli) { _ in }
        let folder = URL(fileURLWithPath: report.folder)
        let snapshot = ImageRecipeSnapshot(record: report.images[0], folder: folder)
        XCTAssertEqual(snapshot.prompt, "A red scarf and red ribbon.")
        XCTAssertTrue(snapshot.parameters.contains("Seed: 19")); XCTAssertTrue(snapshot.parameters.contains("Shift: 1.75"))
        XCTAssertTrue(snapshot.configuration?.contains("sampler") == true)
        let changed = source.replacingOccurrences(of: "COLOR={red}", with: "COLOR={blue}")
        let queued = try PreparedBatch.prepare(changed, continuing: report).freezingPlans()
        XCTAssertEqual(queued.preview[0].prompt, "A blue scarf and blue ribbon.")
        let editedAgain = changed.replacingOccurrences(of: "blue", with: "green")
        XCTAssertEqual(try PreparedBatch.prepare(editedAgain, continuing: report).preview[0].prompt, "A green scarf and green ribbon.")
        let continued = try BatchRunner().run(prepared: queued, outputRoot: dir, executable: cli, continuing: report) { _ in }
        XCTAssertEqual(continued.folder, report.folder)
        XCTAssertEqual(continued.images.map { $0.plan.prompt }, ["A red scarf and red ribbon.", "A blue scarf and blue ribbon."])
        XCTAssertEqual(ImageRecipeSnapshot(record: continued.images[0], folder: folder).prompt, snapshot.prompt)
        let variant = try PreparedBatch.refinement(of: continued.images[0].plan, steps: 6, continuing: continued)
        XCTAssertEqual(variant.preview[0].prompt, snapshot.prompt)
        var missing = continued.images[0]; missing.configurationFile = "../outside.json"
        XCTAssertNil(ImageRecipeSnapshot(record: missing, folder: folder).configuration)
        XCTAssertNil(ImageRecipeSnapshot(record: missing, folder: nil).configuration)
    }
}
