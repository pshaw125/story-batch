#if canImport(XCTest)
import XCTest
#else
import Foundation
#endif
@testable import StoryBatchCore

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64 = 987654321
    mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
}
private struct CountingRNG: RandomNumberGenerator {
    var calls = 0
    mutating func next() -> UInt64 { calls += 1; return 0 }
}

final class StoryBatchCoreTests: XCTestCase {
    func testDefaultsAndHeader() throws {
        let p = try CompiledMetaPrompt.compile("\nhello", now: Date(timeIntervalSince1970: 123456)).parameters
        XCTAssertEqual(p.title, "123456"); XCTAssertNil(p.seed); XCTAssertNil(p.shift)
        XCTAssertEqual(p.steps, 3); XCTAssertEqual(p.count, 4); XCTAssertEqual(p.width, 1024); XCTAssertEqual(p.height, 1024)
        XCTAssertEqual(p.notes, "")
        let q = try CompiledMetaPrompt.compile("title=Jane's cafe; notes=\"soft light; lovely hair = yes\"; resolution=768*1024\nA portrait").parameters
        XCTAssertEqual(q.title, "Jane's cafe"); XCTAssertEqual(q.notes, "soft light; lovely hair = yes"); XCTAssertEqual(q.width, 768)
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("steps=4; steps=5\nportrait"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("unknown=4\nportrait"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("seed=2147483648\nportrait"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("steps=0\nportrait"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("count=-1\nportrait"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("resolution=513*512\nportrait"))
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("title=header only"))
    }
    func testFixedParametersAndDecimalPrecision() throws {
        let p = try CompiledMetaPrompt.compile("title=happy cafe scene; seed=1234; shift=4.550123400; steps=5; count=8; notes=not a prompt\nThe apple is {red|green}.")
        var rng = SeededRNG()
        for i in 1...8 {
            let image = try p.plan(number: i, using: &rng)
            XCTAssertEqual(image.seed, 1234); XCTAssertEqual(image.shift.text, "4.550123400")
            XCTAssertEqual(image.filename, "happy cafe scene_1234_5_4.550123400_\(i).png")
            let json = try image.configurationJSON()
            XCTAssertTrue(json.contains("\"shift\": 4.550123400"))
            let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            XCTAssertEqual(parsed["seed"] as? Int, 1234); XCTAssertEqual(parsed["resolutionDependentShift"] as? Bool, false)
            XCTAssertFalse(image.prompt.contains("not a prompt"))
        }
        XCTAssertEqual(try ShiftValue(".500000").jsonNumber, "0.500000")
        XCTAssertEqual(try ShiftValue("004.5500001").jsonNumber, "4.5500001")
        for s in ["0", "-1", "nan", "inf", "1e99", "1e-99", "x"] { XCTAssertThrowsError(try ShiftValue(s)) }
    }
    func testImageRefinementCopiesSourceAndRecordsPromptStrategy() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let input = dir.appendingPathComponent("fixture.png")
        let source = "title=portrait refinement; seed=1234; shift=1.75; steps=6; count=1; resolution=64*64\nA source prompt.\nA narrower pair of glasses."
        let context = RefinementContext(sourceImagePath: input.path, sourceBatchFolder: "/old/batch", sourceFilename: "keeper.png", sourcePrompt: "A source prompt.", promptMode: "appendDelta", refinementText: "A narrower pair of glasses.")
        let prepared = try PreparedBatch.prepare(source).usingImage(path: input.path, strength: 0.35, crop: false, context: context)
        let report = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(report.refinementContext, context)
        guard let record = report.images.first else { return XCTFail("Expected a refinement image") }
        XCTAssertEqual(record.inputImageFile, "inputs/root.png"); XCTAssertEqual(record.inputStrength, 0.35)
        XCTAssertEqual(record.refinementContext, context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: report.folder).appendingPathComponent("inputs/root.png").path))
        XCTAssertTrue(record.command?.contains("--image") == true); XCTAssertTrue(record.command?.contains("--strength") == true)
        guard let configurationFile = record.configurationFile else { return XCTFail("Expected a configuration file") }
        let config = try String(contentsOf: URL(fileURLWithPath: report.folder).appendingPathComponent(configurationFile), encoding: .utf8)
        XCTAssertTrue(config.contains("\"strength\" : 0.35") || config.contains("\"strength\": 0.35"))
        XCTAssertThrowsError(try PreparedBatch.prepare(source).usingImage(path: input.path, strength: 1.01, crop: false, context: context))
    }
    func testRandomSeedsAndThousandthShifts() throws {
        let p = try CompiledMetaPrompt.compile("\nA portrait")
        var rng = SeededRNG(); var seeds = Set<Int>(); var shifts = Set<String>()
        for i in 1...300 {
            let image = try p.plan(number: i, using: &rng)
            XCTAssertTrue((0...Int(Int32.max)).contains(image.seed))
            XCTAssertNotNil(image.shift.text.range(of: #"^[1-2]\.[0-9]{3}$"#, options: .regularExpression))
            XCTAssertTrue((1.5...2.25).contains(Double(image.shift.text)!))
            seeds.insert(image.seed); shifts.insert(image.shift.text)
        }
        XCTAssertGreaterThan(seeds.count, 290); XCTAssertGreaterThan(shifts.count, 200)
    }
    func testSeedListsPairWithShiftListsAndRandomPlaceholders() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "seed=1234,_,_,0,2147483647,1234,_*; shift=1,2,3,4,5,6; count=6; resolution=64*64\nAn apple"
        var rng = SeededRNG()
        let prepared = try PreparedBatch.prepare(source, using: &rng)
        let expected: [Int?] = [1234, nil, nil, 0, Int(Int32.max), 1234]
        XCTAssertEqual(prepared.compiled.parameters.seedValues, expected)
        XCTAssertEqual(prepared.compiled.parameters.seedDescription, "1234, _, _, 0, 2147483647, 1234")
        XCTAssertEqual(prepared.preview[0].seed, 1234)
        XCTAssertEqual(prepared.preview.map { $0.shift.text }, ["1", "2", "3", "4"])
        XCTAssertTrue(prepared.preview[1].seed != prepared.preview[2].seed)
        let first = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(first.images.map { $0.plan.shift.text }, ["1", "2", "3", "4", "5", "6"])
        for (index, image) in first.images.enumerated() {
            if let fixed = expected[index] { XCTAssertEqual(image.plan.seed, fixed) }
            XCTAssertTrue((0...Int(Int32.max)).contains(image.plan.seed))
        }
        XCTAssertEqual(first.images[1].plan.seed, prepared.preview[1].seed)
        let more = try PreparedBatch.prepare(source, continuing: first, using: &rng)
        XCTAssertEqual(more.startingNumber, 7)
        XCTAssertEqual(more.preview[0].seed, 1234)
        XCTAssertEqual(more.preview.map { $0.shift.text }, ["1", "2", "3", "4"])
        XCTAssertTrue(more.preview[1].seed != prepared.preview[1].seed)
        let next = try BatchRunner().run(prepared: more, outputRoot: dir, executable: cli, continuing: first) { _ in }
        XCTAssertEqual(next.images[10].plan.seed, Int(Int32.max))
        XCTAssertEqual(next.images[11].plan.seed, 1234)
        XCTAssertEqual(next.images[11].plan.shift.text, "6")
        let variant = try PreparedBatch.refinement(of: next.images[1].plan, steps: 7, continuing: next)
        XCTAssertEqual(variant.preview[0].seed, next.images[1].plan.seed)
        XCTAssertNil(variant.compiled.parameters.seedValues)
        let decoded = try JSONDecoder().decode(BatchParameters.self, from: JSONEncoder().encode(prepared.compiled.parameters))
        XCTAssertEqual(decoded.seedValues, expected)
        let scalarShift = try PreparedBatch.prepare("seed=1,2,3; shift=4.55001; count=3\nPortrait")
        XCTAssertEqual(scalarShift.preview.map(\.seed), [1, 2, 3])
        XCTAssertEqual(scalarShift.preview.map { $0.shift.text }, ["4.55001", "4.55001", "4.55001"])
        let scalarSeed = try PreparedBatch.prepare("seed=1234; shift=1,2,3; count=3\nPortrait")
        XCTAssertEqual(scalarSeed.preview.map(\.seed), [1234, 1234, 1234])
        XCTAssertEqual(try PreparedBatch.prepare("seed=_; count=3\nPortrait").preview.count, 3)
        for header in ["seed=1,2; count=3", "seed=1,,3; count=3", "seed=1,_; shift=1,2,3; count=2", "seed=1,-1; count=2", "seed=2147483648,_; count=2", "seed=1.5,_; count=2", "seed=1,_x; count=2", "seed=1,; count=2"] {
            XCTAssertThrowsError(try PreparedBatch.prepare(header + "\nPortrait"), header)
        }
    }
    func testMixedShiftRangesAndRemainder() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "title=mixed shifts; seed=1234,_*; shift=1.3,2.4,1.3..1.4,1.3..2.0*; count=6; resolution=64*64\nPortrait"
        var rng = SeededRNG()
        let prepared = try PreparedBatch.prepare(source, using: &rng)
        let parameters = prepared.compiled.parameters
        XCTAssertEqual(parameters.shiftEntries?.count, 6)
        XCTAssertEqual(try JSONDecoder().decode(BatchParameters.self, from: JSONEncoder().encode(parameters)), parameters)
        let report = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(report.status, "completed")
        XCTAssertEqual(report.images[0].plan.seed, 1234)
        XCTAssertEqual(report.images[0].plan.shift.text, "1.3")
        XCTAssertEqual(report.images[1].plan.shift.text, "2.4")
        XCTAssertTrue((1.3...1.4).contains(Double(report.images[2].plan.shift.text)!))
        for image in report.images.dropFirst(3) {
            XCTAssertTrue((1.3...2.0).contains(Double(image.plan.shift.text)!))
            XCTAssertEqual(image.plan.shift.text.split(separator: ".").last?.count, 3)
        }
        for index in prepared.preview.indices { XCTAssertEqual(report.images[index].plan.shift, prepared.preview[index].shift) }
        let more = try PreparedBatch.prepare(source, continuing: report, using: &rng)
        XCTAssertEqual(more.preview[0].shift.text, "1.3")
        XCTAssertEqual(more.preview[1].shift.text, "2.4")
        let variant = try PreparedBatch.refinement(of: report.images[0].plan, steps: 6, continuing: report)
        XCTAssertNil(variant.compiled.parameters.shiftEntries)
        XCTAssertEqual(variant.preview[0].shift.text, "1.3")
        XCTAssertEqual(try BatchParameters.parse("shift=1..2*; count=3").shiftEntries?.count, 3)
        XCTAssertEqual(try BatchParameters.parse("shift=1,2..3*; count=1").shiftEntries?.count, 1)
        XCTAssertEqual(try BatchParameters.parse("shift=(1,2)+0.5,2..3; count=3").shiftEntries?.map(\.text), ["1.5", "2.5", "2..3"])
        for header in ["shift=1,2..3; count=3", "shift=1..2*,3; count=3", "shift=1,2,3..4*; count=1", "shift=1,3..2*; count=3", "shift=1,,2..3*; count=4", "shift=1*,2..3; count=2", "shift=1..2*,2..3*; count=4"] {
            XCTAssertThrowsError(try BatchParameters.parse(header), header)
        }
    }
    func testSeedRandomRemainder() throws {
        let parameters = try BatchParameters.parse("seed=1234,_, _*; count=6")
        XCTAssertEqual(parameters.seedValues, [1234, nil, nil, nil, nil, nil])
        XCTAssertEqual(try BatchParameters.parse("seeds=_*; count=3").seedValues, [nil, nil, nil])
        XCTAssertEqual(try BatchParameters.parse("seed=7,_*; count=1").seedValues, [7])
        XCTAssertEqual(try BatchParameters.parse("seed=7,_*").seedValues, [7, nil, nil, nil])
        var rng = SeededRNG()
        let prepared = try PreparedBatch.prepare("seed=1234,_*; count=6; shift=1,2,3,4,5,6\nPortrait", using: &rng).freezingPlans()
        let plans = prepared.frozenPlans ?? []
        XCTAssertEqual(plans.count, 6)
        XCTAssertEqual(plans.first?.seed, 1234)
        XCTAssertEqual(plans.map { $0.shift.text }, ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(Set(plans.dropFirst().map(\.seed)).count, 5)
        XCTAssertTrue(plans.allSatisfy { (0...Int(Int32.max)).contains($0.seed) })
        for header in ["seed=_*,1; count=3", "seed=_*,_*; count=3", "seed=1,2,_*; count=1", "seed=1,,_*; count=3", "seed=1,_*,; count=3"] {
            XCTAssertThrowsError(try BatchParameters.parse(header), header)
        }
    }
    func testOrderedShiftListsValidationAndContinuation() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let values = ["0.05", "1", "2.1740001", "4.5", "4.55", "6.5"]
        let source = "seed=967027539; shift=" + values.joined(separator: ", ") + "; count=6; resolution=64*64\nAn apple"
        let prepared = try PreparedBatch.prepare(source)
        XCTAssertEqual(prepared.compiled.parameters.shiftValues?.map(\.text), values)
        XCTAssertEqual(prepared.preview.map { $0.shift.text }, Array(values.prefix(4)))
        let first = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(first.images.map { $0.plan.shift.text }, values)
        let secondPlan = try PreparedBatch.prepare(source, continuing: first)
        XCTAssertEqual(secondPlan.startingNumber, 7)
        XCTAssertEqual(secondPlan.preview.map { $0.shift.text }, Array(values.prefix(4)))
        let second = try BatchRunner().run(prepared: secondPlan, outputRoot: dir, executable: cli, continuing: first) { _ in }
        XCTAssertEqual(second.images.map { $0.plan.shift.text }, values + values)
        XCTAssertEqual(second.images.map(\.plan.number), Array(1...12))
        let refined = try PreparedBatch.refinement(of: first.images[0].plan, steps: 6, continuing: second)
        XCTAssertEqual(refined.preview[0].shift.text, values[0])
        XCTAssertNil(refined.compiled.parameters.shiftValues)
        let decoded = try JSONDecoder().decode(BatchParameters.self, from: JSONEncoder().encode(prepared.compiled.parameters))
        XCTAssertEqual(decoded.shiftValues?.map(\.text), values)
        let duplicate = try PreparedBatch.prepare("count=2; shift=4.5501234,4.5501234\nPortrait")
        XCTAssertEqual(duplicate.preview.map { $0.shift.text }, ["4.5501234", "4.5501234"])
        XCTAssertEqual(try PreparedBatch.prepare("shift=1,2,3,4\nPortrait").preview.count, 4)
        do {
            _ = try PreparedBatch.prepare("shift=1,2,3\nPortrait")
            XCTFail("Expected count mismatch")
        } catch let error as MetaPromptError {
            XCTAssertTrue(error.message.contains("3 values")); XCTAssertTrue(error.message.contains("count is 4"))
        }
        for header in ["count=2; shift=1,2,3", "count=3; shift=1,,3", "count=2; shift=1,", "count=2; shift=0,1", "count=3; shift=1..2,3", "count=2; shift=1,nan"] {
            XCTAssertThrowsError(try PreparedBatch.prepare(header + "\nPortrait"), header)
        }
    }
    func testSkipCurrentImageBeforeLaunchPreservesRemainder() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let prepared = try PreparedBatch.prepare("count=3; seeds=11,12,13; resolution=64*64\nAn apple").freezingPlans()
        let runner = BatchRunner(queuedImageNumbers: [1, 2, 3])
        XCTAssertFalse(runner.skipCurrentImage(number: 1))
        let report = try runner.run(prepared: prepared, outputRoot: dir, executable: cli) { event in
            if case .imageStarted(let record) = event {
                if record.plan.number != 2 {
                    XCTAssertTrue(runner.skipCurrentImage(number: record.plan.number))
                    XCTAssertFalse(runner.skipCurrentImage(number: record.plan.number))
                } else { XCTAssertFalse(runner.skipCurrentImage(number: 1)) }
            }
        }
        XCTAssertEqual(report.status, "completed")
        XCTAssertEqual(report.images.map(\.status), ["skipped", "completed", "skipped"])
        XCTAssertEqual(report.images.map(\.plan.seed), [11, 12, 13])
        XCTAssertTrue(report.images[0].error?.contains("Skipped by user") == true)
        XCTAssertNil(report.images[0].exitCode)
        XCTAssertEqual(report.images[1].exitCode, 0)
        XCTAssertFalse(runner.skipCurrentImage(number: 3))
        XCTAssertEqual(ImageRecord.displayOrder(report.images).map(\.plan.number), [2])
    }
    func testQueueFragmentsKeepInputsAccountingAndCanceledAttempts() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir), input = dir.appendingPathComponent("fixture.png")
        let source = "title=fragments; count=3; seeds=11,12,13; shift=1,2,3; resolution=64*64\nA portrait."
        let context = RefinementContext(sourceImagePath: input.path, sourceBatchFolder: nil, sourceFilename: nil, sourcePrompt: "Original", promptMode: "appendDelta", refinementText: "A portrait.")
        var prepared = try PreparedBatch.prepare(source).freezingPlans().usingImage(path: input.path, strength: 0.35, crop: true, context: context)
        prepared.logicalRunID = "logical-fragment-run"
        let runner = BatchRunner(queuedImageNumbers: [1, 2, 3])
        let report = try runner.run(prepared: prepared, outputRoot: dir, executable: cli) { event in
            if case .imageStarted = event {
                XCTAssertTrue(runner.cancelQueuedImage(number: 3))
                XCTAssertEqual(runner.detachPendingImages(), [2])
            }
        }
        XCTAssertEqual(report.images.map(\.status), ["completed", "skipped"])
        XCTAssertEqual(report.images.map(\.plan.number), [1, 3])
        let fragment = try prepared.fragment(at: 1, runID: "logical-fragment-run").rebased(continuing: report)
        XCTAssertEqual(fragment.inputImagePath, input.path); XCTAssertEqual(fragment.inputStrength, 0.35)
        XCTAssertTrue(fragment.cropInput); XCTAssertEqual(fragment.refinementContext, context)
        let result = try BatchRunner().run(prepared: fragment, outputRoot: dir, executable: cli, continuing: report) { _ in }
        XCTAssertEqual(result.requestedImageCount, 3)
        XCTAssertEqual(result.parameters.count, 3)
        XCTAssertEqual(result.latestCompletedPlans.map(\.seed), [11, 12])
        XCTAssertEqual(result.images.last?.requestParameters?.count, 3)
        XCTAssertTrue(result.images.last?.command?.contains("--image") == true)
        XCTAssertTrue(result.images.last?.command?.contains("--crop") == true)
        XCTAssertEqual(result.images.last?.inputStrength, 0.35)
        XCTAssertEqual(result.images.last?.plan.shift.text, "2")
    }
    func testFrozenQueueCancellationPreservesPairingAndNumbering() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "count=3; seed=11,12,13; shift=1,2,3; resolution=64*64\nAn {apple|orange}"
        let batch = try PreparedBatch.prepare(source).freezingPlans()
        XCTAssertEqual(batch.frozenPlans?.count, 3)
        let runner = BatchRunner(queuedImageNumbers: batch.frozenPlans!.map(\.number))
        var skipped: [ImageRecord] = []
        let report = try runner.run(prepared: batch, outputRoot: dir, executable: cli) { event in
            if case .imageStarted(let record) = event, record.plan.number == 1 {
                XCTAssertFalse(runner.cancelQueuedImage(number: 1))
                XCTAssertTrue(runner.cancelQueuedImage(number: 2))
                XCTAssertFalse(runner.cancelQueuedImage(number: 2))
            }
            if case .imageSkipped(let record) = event { skipped.append(record) }
        }
        XCTAssertEqual(report.status, "completed")
        XCTAssertEqual(report.images.map(\.status), ["completed", "skipped", "completed"])
        XCTAssertEqual(report.images.map(\.plan.seed), [11, 12, 13])
        XCTAssertEqual(report.images.map { $0.plan.shift.text }, ["1", "2", "3"])
        XCTAssertEqual(skipped.count, 1)
        XCTAssertNil(skipped[0].startedAt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: report.folder).appendingPathComponent(skipped[0].plan.filename).path))
        XCTAssertEqual(ImageRecord.displayOrder(report.images).map(\.plan.number), [1, 3])
        let queued = try PreparedBatch.prepare("count=6; shift=1,2,3,4,5,6\nAn {apple|orange}", defaultTitle: report.parameters.title).freezingPlans()
        let rebased = try queued.rebased(continuing: report)
        XCTAssertEqual(rebased.startingNumber, 4)
        XCTAssertEqual(rebased.frozenPlans?.map(\.seed), queued.frozenPlans?.map(\.seed))
        XCTAssertEqual(rebased.frozenPlans?.map(\.prompt), queued.frozenPlans?.map(\.prompt))
        XCTAssertEqual(rebased.frozenPlans?.map { $0.shift.text }, ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(rebased.frozenPlans?.map(\.number), [4, 5, 6, 7, 8, 9])
    }
    func testShiftArithmeticInScalarsListsAndRanges() throws {
        let source = "count=4; seed=1234; shift=2.25+0.5,2.25+0.5,2.4-0.1,2.1+2; resolution=64*64\nAn apple"
        let batch = try PreparedBatch.prepare(source)
        XCTAssertEqual(batch.preview.map { $0.shift.text }, ["2.75", "2.75", "2.3", "4.1"])
        XCTAssertEqual(batch.compiled.source, source)
        for (expression, expected) in [
            ("2.25 + 0.5 * 2", "3.25"), ("(2.25 + 0.5) * 2", "5.5"),
            ("2.4 - 0.1", "2.3"), (".5 + .25", "0.75"), ("2.5 + -0.1", "2.4"),
            ("2.25e0 + 5e-1", "2.75"), ("1e-3 + 2e-3", "0.003"),
            ("4.5501234+0.05", "4.6001234"), ("2.25/2", "1.125")
        ] { XCTAssertEqual(try ShiftValue.evaluating(expression).text, expected) }
        XCTAssertEqual(try ShiftValue.evaluating("4.550123400").text, "4.550123400")
        let scalar = try PreparedBatch.prepare("count=3; shift=2.25+0.5\nPortrait")
        XCTAssertEqual(scalar.preview.map { $0.shift.text }, ["2.75", "2.75", "2.75"])
        let range = try ShiftRange("(2+0.25)..(3-0.5)")
        XCTAssertEqual(range.text, "2.25..2.5")
        XCTAssertEqual(range.lowerThousandth, 2250); XCTAssertEqual(range.upperThousandth, 2500)
        for expression in ["2+", "2**3", "2/0", "(2+1", "2+1)", "2-2", "2-3", "2^3", "sqrt(4)", "1e++2", "1e1000+1", "2+foo"] {
            XCTAssertThrowsError(try PreparedBatch.prepare("shift=" + expression + "\nPortrait"), expression)
        }
        do {
            _ = try PreparedBatch.prepare("count=2; shift=2+0.5,1/0\nPortrait")
            XCTFail("Expected arithmetic feedback")
        } catch let error as MetaPromptError {
            XCTAssertTrue(error.message.contains("item 2")); XCTAssertTrue(error.message.contains("Division by zero"))
        }
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let report = try BatchRunner().run(prepared: batch, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(report.images.map { $0.plan.shift.text }, ["2.75", "2.75", "2.3", "4.1"])
        XCTAssertEqual(report.sourceMetaprompt, source)
        let config = try String(contentsOf: URL(fileURLWithPath: report.folder).appendingPathComponent(report.images[2].configurationFile!), encoding: .utf8)
        XCTAssertTrue(config.contains("\"shift\": 2.3")); XCTAssertFalse(config.contains("2.4-0.1"))
    }
    func testWrappedShiftOperationsAndCollectedParameters() throws {
        for expression in ["(2.25,2.25,2.4,2.1)+0.5", "0.5+(2.25,2.25,2.4,2.1)"] {
            let batch = try PreparedBatch.prepare("count=4; shift=" + expression + "\nPortrait")
            XCTAssertEqual(batch.preview.map { $0.shift.text }, ["2.75", "2.75", "2.9", "2.6"])
        }
        for (expression, expected) in [
            ("(2.25+0.5,2.4-0.1)*2", ["5.5", "4.6"]),
            ("2/(1,2,4)", ["2", "1", "0.5"]),
            ("5-(1,2)", ["4", "3"]),
            ("((1,2)+(.1,.2))*2", ["2.2", "4.4"])
        ] { XCTAssertEqual(try ShiftValue.evaluatingList(expression).map(\.text), expected) }
        for expression in ["(1,2)+(3,4,5)", "(1,,2)+.5", "()+1", "(0,1)-0.1", "2/(1,0)", "(1,2)+.5)"] {
            XCTAssertThrowsError(try PreparedBatch.prepare("count=2; shift=" + expression + "\nPortrait"), expression)
        }
        XCTAssertThrowsError(try PreparedBatch.prepare("count=3; shift=(1,2)+.5\nPortrait"))
        let original = "title=study; seed=8; notes=\"seed=9; keep this\"; shift=1..3; count=4\nBody {red|green}\n"
        let seeds = try BatchParameters.replacingParameter(in: original, key: "seeds", value: "34,1,678,4656")
        let shifts = try BatchParameters.replacingParameter(in: seeds, key: "shift", value: "2.100,1.750,1.501,2.250")
        let parameters = try CompiledMetaPrompt.compile(shifts).parameters
        XCTAssertEqual(parameters.seedValues, [34, 1, 678, 4656])
        XCTAssertEqual(parameters.shiftValues?.map(\.text), ["2.100", "1.750", "1.501", "2.250"])
        XCTAssertEqual(parameters.notes, "seed=9; keep this")
        XCTAssertEqual(CompiledMetaPrompt.promptBody(in: original), CompiledMetaPrompt.promptBody(in: shifts))
        XCTAssertTrue(shifts.contains("seeds=34,1,678,4656"))
        XCTAssertEqual(try CompiledMetaPrompt.compile("seeds=1234,_,_; count=3\nPortrait").parameters.seedValues, [1234, nil, nil])
        XCTAssertThrowsError(try CompiledMetaPrompt.compile("seed=1; seeds=2\nPortrait"))
        let deduplicated = try BatchParameters.replacingParameter(in: "seed=1; seeds=2; count=2\nPortrait", key: "seeds", value: "8,3")
        XCTAssertEqual(try CompiledMetaPrompt.compile(deduplicated).parameters.seedValues, [8, 3])
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let first = try PreparedBatch.prepare("seeds=34,1,678,4656; shift=(1,1.5,2,2.25)+.1; count=4; resolution=64*64\nAn apple")
        let report = try BatchRunner().run(prepared: first, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(report.latestCompletedPlans.map(\.seed), [34, 1, 678, 4656])
        let more = try PreparedBatch.prepare("seeds=3,2; shift=1.7; count=2; resolution=64*64\nAn apple", continuing: report)
        let result = try BatchRunner().run(prepared: more, outputRoot: dir, executable: cli, continuing: report) { _ in }
        XCTAssertEqual(result.latestCompletedPlans.map(\.seed), [3, 2])
        XCTAssertEqual(result.latestCompletedPlans.map { $0.shift.text }, ["1.7", "1.7"])
        XCTAssertTrue(report.latestRunID != result.latestRunID)
        XCTAssertEqual(try BatchReport.load(in: URL(fileURLWithPath: result.folder)).latestCompletedPlans.map(\.seed), [3, 2])
    }
    func testConstrainedShiftRange() throws {
        let compiled = try CompiledMetaPrompt.compile("shift=4.2..4.8; seed=1234\nPortrait")
        XCTAssertNil(compiled.parameters.shift)
        XCTAssertEqual(compiled.parameters.shiftRange?.text, "4.2..4.8")
        var rng = SeededRNG(); var seen = Set<String>()
        for i in 1...1000 {
            let plan = try compiled.plan(number: i, using: &rng)
            XCTAssertTrue((4.2...4.8).contains(Double(plan.shift.text)!))
            XCTAssertNotNil(plan.shift.text.range(of: #"^[0-9]+\.[0-9]{3}$"#, options: .regularExpression))
            seen.insert(plan.shift.text)
        }
        XCTAssertGreaterThan(seen.count, 400)
        let exact = try ShiftRange("4.001..4.001")
        XCTAssertEqual(exact.random(using: &rng).text, "4.001")
        let narrow = try ShiftRange("4.5501..4.5519")
        XCTAssertEqual(narrow.random(using: &rng).text, "4.551")
        XCTAssertEqual(try ShiftRange(" 3 .. 6 ").text, "3..6")
        for raw in ["6..3", "0..1", "-1..3", "nan..5", "3..", "..6", "3..4..5", "4.5501..4.5502", "1e30..2e30"] {
            XCTAssertThrowsError(try PreparedBatch.prepare("shift=" + raw + "\nPortrait"), raw)
        }
        let prepared = try PreparedBatch.prepare("shift=3.9..4.1\nPortrait", using: &rng)
        XCTAssertEqual(prepared.preview.count, 4)
        for plan in prepared.preview { XCTAssertTrue((3.9...4.1).contains(Double(plan.shift.text)!)) }
        let encoded = try JSONEncoder().encode(compiled.parameters)
        let decoded = try JSONDecoder().decode(BatchParameters.self, from: encoded)
        XCTAssertEqual(decoded.shiftRange, compiled.parameters.shiftRange)
    }
    func testWeightsNestedBranchesAndDuplicates() throws {
        let p = try CompiledMetaPrompt.compile("\n{red:::2|green:::3|red with a {worm|caterpillar}:::0.5}")
        var rng = SeededRNG(); var counts: [String: Int] = [:]
        for _ in 0..<11000 { counts[p.resolve(using: &rng), default: 0] += 1 }
        XCTAssertEqual(Set(counts.keys), Set(["red", "green", "red with a worm", "red with a caterpillar"]))
        XCTAssertEqual(Double(counts["green"]!) / 11000, 3 / 5.5, accuracy: 0.025)
        XCTAssertEqual(Double(counts["red"]!) / 11000, 2 / 5.5, accuracy: 0.025)
        XCTAssertEqual(Double(counts["red with a worm"]!) / 11000, 0.25 / 5.5, accuracy: 0.015)
        let duplicates = try CompiledMetaPrompt.compile("\n{red|red|green}"); var red = 0
        for _ in 0..<6000 { if duplicates.resolve(using: &rng) == "red" { red += 1 } }
        XCTAssertEqual(Double(red) / 6000, 2.0 / 3, accuracy: 0.03)
        let zero = try CompiledMetaPrompt.compile("\n{never:::0|always}")
        for _ in 0..<20 { XCTAssertEqual(zero.resolve(using: &rng), "always") }
    }
    func testEmptySingleAndLazyNestedTerms() throws {
        var rng = CountingRNG()
        XCTAssertEqual(try CompiledMetaPrompt.compile("\n{} {one}").resolve(using: &rng), " one"); XCTAssertEqual(rng.calls, 0)
        XCTAssertEqual(try CompiledMetaPrompt.compile("\n{chosen|{a|{b|c}}}").resolve(using: &rng), "chosen")
        XCTAssertEqual(rng.calls, 1, "Unselected nested choices must not consume randomness.")
        XCTAssertEqual(try CompiledMetaPrompt.compile("\n{only {nested}}").resolve(using: &rng), "only nested")
        XCTAssertEqual(try CompiledMetaPrompt.compile("\n{:::2}").resolve(using: &rng), "")
        XCTAssertEqual(try CompiledMetaPrompt.compile("\n{|}").resolve(using: &rng), "")
        XCTAssertEqual(try CompiledMetaPrompt.compile("\n" + #"\{a\|b\} C:\temp"#).resolve(using: &rng), #"{a|b} C:\temp"#)
    }
    func testMalformedBranchesFailBeforeGeneration() throws {
        let bad = ["{a|b", "{a|{b|c}", "}", "{x:::oops|y}", "{x:::-1|y}", "{a:::0|b:::0}", "{chosen|{broken:::0}"]
        for prompt in bad { XCTAssertThrowsError(try PreparedBatch.prepare("\n" + prompt), prompt) }
        do { _ = try CompiledMetaPrompt.compile("\nfirst line\n{unclosed"); XCTFail("Expected error") }
        catch let e as MetaPromptError { XCTAssertEqual(e.line, 3); XCTAssertEqual(e.column, 1) }
    }
    func testSafeFilenamesAndUnicodeLength() throws {
        let p = try CompiledMetaPrompt.compile("title=../../" + String(repeating: "猫", count: 200) + "; seed=1; shift=3.0001\nPortrait")
        var rng = SeededRNG(); let image = try p.plan(number: 1, using: &rng)
        XCTAssertFalse(image.filename.contains("/")); XCTAssertLessThanOrEqual(image.filename.utf8.count, 250)
        XCTAssertTrue(image.filename.hasSuffix("_1_3_3.0001_1.png"))
    }
    func testPreviewIsExactlyUsedAndReportsWrittenPerImage() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let text = "title=sample $(touch HACKED); seed=1234; shift=4.55001; resolution=64*64; count=2; notes=private notes\n{red|green} apple"
        var rng = SeededRNG(); let prepared = try PreparedBatch.prepare(text, using: &rng)
        var finished: [ImageRecord] = []; var reportWasPresent = true
        let report = try BatchRunner().run(prepared: prepared, outputRoot: dir.appendingPathComponent("batches"), executable: cli) { event in
            if case .imageFinished(let record) = event { finished.append(record) }
            if case .batchStarted(let folder) = event { reportWasPresent = (try? FileManager.default.contentsOfDirectory(atPath: folder.path).contains(where: { $0.hasPrefix("report_") && $0.hasSuffix(".json") })) ?? false }
        }
        XCTAssertEqual(report.status, "completed"); XCTAssertEqual(finished.count, 2); XCTAssertTrue(reportWasPresent)
        XCTAssertEqual(report.images.map(\.plan), prepared.preview)
        XCTAssertFalse(FileManager.default.fileExists(atPath: URL(fileURLWithPath: report.folder).appendingPathComponent("HACKED").path))
        let reportURL = URL(fileURLWithPath: report.folder).appendingPathComponent(report.reportFilename)
        let saved = try JSONDecoder().decode(BatchReport.self, from: Data(contentsOf: reportURL))
        XCTAssertEqual(saved.parameters.notes, "private notes"); XCTAssertEqual(saved.images.count, 2)
        for record in saved.images {
            XCTAssertEqual(record.status, "completed"); XCTAssertEqual(record.generationSeconds, 0.02); XCTAssertEqual(record.actualSteps, 3)
            XCTAssertFalse(record.plan.prompt.contains("private notes")); XCTAssertNotNil(record.elapsedSeconds)
            XCTAssertTrue(record.command!.contains("--local")); XCTAssertTrue(record.command!.contains("--offline"))
            XCTAssertTrue(BatchFormatting.finishedLine(record).contains(record.plan.filename))
        }
        let lines = try String(contentsOf: URL(fileURLWithPath: report.folder).appendingPathComponent("events.jsonl")).split(separator: "\n")
        XCTAssertEqual(lines.count, 4)
        let final = try JSONSerialization.jsonObject(with: Data(lines.last!.utf8)) as! [String: Any]
        XCTAssertEqual(final["event"] as? String, "image_finished"); XCTAssertNotNil(final["elapsedSeconds"])
    }
    func testCancellationStopsCurrentImageAndDoesNotStartNext() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir, sleeping: true)
        let prepared = try PreparedBatch.prepare("count=3; resolution=64*64\nPortrait")
        let runner = BatchRunner(); let done = expectation(description: "Cancelled batch saved")
        DispatchQueue.global().async {
            do {
                let report = try runner.run(prepared: prepared, outputRoot: dir.appendingPathComponent("batches"), executable: cli) { event in
                    if case .imageStarted = event { DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { runner.cancel() } }
                }
                XCTAssertEqual(report.status, "cancelled"); XCTAssertEqual(report.images.count, 1); XCTAssertEqual(report.images[0].status, "cancelled")
                XCTAssertFalse(FileManager.default.fileExists(atPath: report.folder))
            } catch { XCTFail(error.localizedDescription) }
            done.fulfill()
        }
        wait(for: [done], timeout: 6)
    }
    func testGenerateMoreAppendsWithoutOverwritingAndKeepsImplicitTitle() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "seed=1234; shift=4.55; count=2; resolution=64*64\n{red|green} apple"
        var rng = SeededRNG()
        let first = try PreparedBatch.prepare(source, now: Date(timeIntervalSince1970: 100), using: &rng)
        let report = try BatchRunner().run(prepared: first, outputRoot: dir, executable: cli) { _ in }
        let original = try Data(contentsOf: URL(fileURLWithPath: report.folder).appendingPathComponent(report.images[0].plan.filename))
        let more = try PreparedBatch.prepare(source, now: Date(timeIntervalSince1970: 900), continuing: report, using: &rng)
        XCTAssertEqual(more.startingNumber, 3)
        XCTAssertEqual(more.compiled.parameters.title, "100")
        XCTAssertEqual(more.preview.map(\.number), [3, 4])
        let result = try BatchRunner().run(prepared: more, outputRoot: dir, executable: cli, continuing: report) { _ in }
        XCTAssertEqual(result.folder, report.folder); XCTAssertEqual(result.id, report.id)
        XCTAssertEqual(result.reportFilename, report.reportFilename)
        XCTAssertEqual(result.images.map(\.plan.number), [1, 2, 3, 4])
        XCTAssertEqual(result.requestedImageCount, 4)
        XCTAssertEqual(result.images.map(\.status), Array(repeating: "completed", count: 4))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: report.folder).appendingPathComponent(report.images[0].plan.filename)), original)
        let saved = try JSONDecoder().decode(BatchReport.self, from: Data(contentsOf: URL(fileURLWithPath: result.folder).appendingPathComponent(result.reportFilename)))
        XCTAssertEqual(saved.images.count, 4)
        XCTAssertEqual(try PreparedBatch.prepare(source + " changed", continuing: report).startingNumber, 3)
        let fresh = try PreparedBatch.prepare(source + " changed")
        XCTAssertEqual(fresh.startingNumber, 1)
    }
    func testParameterOnlyEditsContinueWithNewSettingsAndPreserveHistory() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let body = "A {red|green} apple\nOn a wooden table."
        let original = "title=new title; seed=1234; shift=4.5; count=2; resolution=64*64; notes=first round\n" + body
        var rng = SeededRNG()
        let first = try PreparedBatch.prepare(original, now: Date(timeIntervalSince1970: 100), using: &rng)
        let previous = try BatchRunner().run(prepared: first, outputRoot: dir, executable: cli) { _ in }
        let changed = "title=new title; seed=5678; shift=4.6..4.8; steps=6; count=1; resolution=128*64; notes=second round\n" + body
        let next = try PreparedBatch.prepare(changed, continuing: previous, using: &rng)
        XCTAssertEqual(next.startingNumber, 3); XCTAssertEqual(next.preview.count, 1)
        let plan = next.preview[0]
        XCTAssertEqual(plan.seed, 5678); XCTAssertEqual(plan.steps, 6)
        XCTAssertTrue((4.6...4.8).contains(Double(plan.shift.text)!))
        XCTAssertEqual(plan.width, 128); XCTAssertEqual(plan.height, 64)
        XCTAssertTrue(plan.filename.hasPrefix("new title_"))
        let result = try BatchRunner().run(prepared: next, outputRoot: dir, executable: cli, continuing: previous) { _ in }
        XCTAssertEqual(result.folder, previous.folder); XCTAssertEqual(result.id, previous.id)
        XCTAssertEqual(result.images.map(\.plan.number), [1, 2, 3])
        XCTAssertEqual(result.sourceMetaprompt, changed)
        XCTAssertEqual(result.parameters.count, 1); XCTAssertEqual(result.parameters.steps, 6)
        XCTAssertEqual(result.parameters.notes, "second round"); XCTAssertEqual(result.requestedImageCount, 3)
        XCTAssertEqual(result.images[0].sourceMetaprompt, original)
        XCTAssertEqual(result.images[0].requestParameters?.notes, "first round")
        XCTAssertEqual(result.images[2].sourceMetaprompt, changed)
        XCTAssertEqual(result.images[2].requestParameters?.notes, "second round")
        let omittedTitle = "count=1; shift=4.7\n" + body
        let again = try PreparedBatch.prepare(omittedTitle, now: Date(timeIntervalSince1970: 900), continuing: result, using: &rng)
        XCTAssertEqual(again.compiled.parameters.title, "new title")
        XCTAssertNil(again.compiled.parameters.seed); XCTAssertEqual(again.compiled.parameters.steps, 3)
        XCTAssertEqual(again.preview[0].width, 1024); XCTAssertEqual(again.startingNumber, 4)
        XCTAssertEqual(try PreparedBatch.prepare(changed + " changed", continuing: result).startingNumber, 4)
        XCTAssertThrowsError(try PreparedBatch.prepare(changed.replacingOccurrences(of: "title=new title", with: "title=another title"), continuing: result))
        XCTAssertFalse(CompiledMetaPrompt.samePromptBody(changed, "count=1\n" + body + " "))
        XCTAssertFalse(CompiledMetaPrompt.samePromptBody(changed, "missing newline"))
    }
    func testCanceledMorePreservesExistingImagesAndSkipsAttemptedNumber() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "count=1; resolution=64*64\nPortrait"
        let first = try PreparedBatch.prepare(source)
        let report = try BatchRunner().run(prepared: first, outputRoot: dir, executable: cli) { _ in }
        _ = try fakeCLI(in: dir, sleeping: true)
        let more = try PreparedBatch.prepare(source, continuing: report)
        let runner = BatchRunner()
        let canceled = try runner.run(prepared: more, outputRoot: dir, executable: cli, continuing: report) { event in
            if case .imageStarted = event { DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { runner.cancel() } }
            if case .batchRemoved = event { XCTFail("An existing completed image must preserve the folder") }
        }
        XCTAssertEqual(canceled.status, "cancelled")
        XCTAssertEqual(canceled.images.map(\.status), ["completed", "cancelled"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: canceled.folder))
        XCTAssertTrue(FileManager.default.fileExists(atPath: URL(fileURLWithPath: canceled.folder).appendingPathComponent(report.images[0].plan.filename).path))
        _ = try fakeCLI(in: dir)
        let retry = try PreparedBatch.prepare(source, continuing: canceled)
        XCTAssertEqual(retry.startingNumber, 3)
        let result = try BatchRunner().run(prepared: retry, outputRoot: dir, executable: cli, continuing: canceled) { _ in }
        XCTAssertEqual(result.images.map(\.plan.number), [1, 2, 3])
        XCTAssertEqual(result.images.last?.status, "completed")
    }
    func testDraftPersistenceAndRunningRecipeSnapshot() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = EditorSessionStore(url: dir.appendingPathComponent("state/session.json"))
        XCTAssertNil(try store.load())
        var source = "count=1; shift=4.5\nOriginal {red|green} apple"
        let prepared = try PreparedBatch.prepare(source)
        source = "steps=invalid\nUnfinished draft {"
        let session = EditorSession(source: source, lastReportPath: "/a/report.json")
        try store.save(session)
        let reopened = EditorSessionStore(url: store.url)
        XCTAssertEqual(try reopened.load(), session)
        XCTAssertEqual(prepared.compiled.source, "count=1; shift=4.5\nOriginal {red|green} apple")
        XCTAssertEqual(prepared.preview[0].steps, 3)
        XCTAssertTrue(prepared.preview[0].prompt.hasPrefix("Original"))
        try store.save(EditorSession(source: "", lastReportPath: nil))
        XCTAssertEqual(try reopened.load()?.source, "")
    }
    func testRefinementStepButtonsAndExactRecipe() throws {
        let source = try PreparedBatch.prepare("title=spike; count=1; seed=1234; shift=4.550123; resolution=64*128\nA {red|green} apple with {a leaf|a worm}.")
        for (steps, expected) in [(1, [4, 6, 7, 8]), (2, [4, 6, 7, 8]), (3, [4, 6, 7, 8]), (4, [6, 7, 8]), (5, [6, 7, 8]), (6, [7, 8]), (7, [8]), (8, []), (10, [])] {
            let plan = source.preview[0]
            let variant = ImagePlan(number: plan.number, seed: plan.seed, shift: plan.shift, steps: steps, width: plan.width, height: plan.height, prompt: plan.prompt, filename: plan.filename)
            XCTAssertEqual(variant.refinementSteps, expected)
        }
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let original = try BatchRunner().run(prepared: source, outputRoot: dir, executable: cli) { _ in }
        let image = original.images[0].plan
        let refined = try PreparedBatch.refinement(of: image, steps: 6, continuing: original)
        XCTAssertEqual(refined.compiled.source, original.sourceMetaprompt)
        XCTAssertEqual(refined.compiled.parameters.count, 1)
        XCTAssertEqual(refined.preview.count, 1)
        let plan = refined.preview[0]
        XCTAssertEqual(plan.seed, image.seed); XCTAssertEqual(plan.shift, image.shift)
        XCTAssertEqual(plan.width, image.width); XCTAssertEqual(plan.height, image.height)
        XCTAssertEqual(plan.prompt, image.prompt); XCTAssertEqual(plan.steps, 6)
        XCTAssertEqual(plan.number, 2); XCTAssertTrue(plan.filename.hasSuffix("_6_\(image.shift.text)_2.png"))
        let a = try JSONSerialization.jsonObject(with: Data(image.configurationJSON().utf8)) as! [String: Any]
        let b = try JSONSerialization.jsonObject(with: Data(plan.configurationJSON().utf8)) as! [String: Any]
        var originalConfig = a; originalConfig["steps"] = 6
        XCTAssertEqual(NSDictionary(dictionary: originalConfig), NSDictionary(dictionary: b))
        XCTAssertEqual(try PreparedBatch.refinement(of: image, steps: 7, continuing: original).preview[0].steps, 7)
        XCTAssertThrowsError(try PreparedBatch.refinement(of: image, steps: 5, continuing: original))
        let completed = try BatchRunner().run(prepared: refined, outputRoot: dir, executable: cli, continuing: original) { _ in }
        XCTAssertEqual(completed.images.count, 2); XCTAssertEqual(completed.images[1].plan.prompt, image.prompt)
        XCTAssertEqual(completed.images[1].refinementOf, URL(fileURLWithPath: original.folder).appendingPathComponent(image.filename).path)
        XCTAssertEqual(completed.sourceMetaprompt, original.sourceMetaprompt)
        XCTAssertEqual(completed.parameters.steps, 3); XCTAssertEqual(completed.parameters.count, 1)
        XCTAssertEqual(completed.requestedImageCount, 2)
        let reloaded = try BatchReport.load(in: URL(fileURLWithPath: completed.folder))
        XCTAssertEqual(reloaded.images.last?.refinementOf, completed.images.last?.refinementOf)
    }
    func testShiftBumpsPreservePrecisionAndOnlyChangeShift() throws {
        for value in ["1", "0.001", "2.125", ".25", " 3.50 "] {
            XCTAssertEqual(try ShiftValue.viewerInput(value).text, value.trimmingCharacters(in: .whitespaces))
        }
        for value in ["0", "0.000", "-1", "1.2345", "1e2", "1+2", "", "nan", "1,2"] {
            XCTAssertThrowsError(try ShiftValue.viewerInput(value), value)
        }
        let shift = try ShiftValue("4.550123")
        let expected = ["3.550123", "4.300123", "4.450123", "4.500123", "4.600123", "4.650123", "4.800123", "5.550123"]
        for (bump, result) in zip(ShiftBump.allCases, expected) { XCTAssertEqual(try shift.bumped(by: bump).text, result) }
        XCTAssertEqual(try ShiftValue("4.55").bumped(by: .plusFiveHundredths).text, "4.6")
        XCTAssertThrowsError(try ShiftValue("0.05").bumped(by: .minusFiveHundredths))
        XCTAssertThrowsError(try ShiftValue("0.5").bumped(by: .minusOne))
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "title=shift bump; count=1; steps=8; seed=4321; shift=4.550123; resolution=64*128\nA {red|green} apple"
        let first = try PreparedBatch.prepare(source)
        let report = try BatchRunner().run(prepared: first, outputRoot: dir, executable: cli) { _ in }
        let image = report.images[0].plan
        let bumped = try image.shift.bumped(by: .plusFiveHundredths)
        let next = try PreparedBatch.refinement(of: image, shift: bumped, continuing: report)
        let plan = next.preview[0]
        XCTAssertEqual(plan.steps, 8); XCTAssertEqual(plan.seed, image.seed)
        XCTAssertEqual(plan.width, image.width); XCTAssertEqual(plan.height, image.height)
        XCTAssertEqual(plan.prompt, image.prompt); XCTAssertEqual(plan.shift.text, "4.600123")
        let originalConfig = try JSONSerialization.jsonObject(with: Data(image.configurationJSON().utf8)) as! [String: Any]
        let changedConfig = try JSONSerialization.jsonObject(with: Data(plan.configurationJSON().utf8)) as! [String: Any]
        var expectedConfig = originalConfig; expectedConfig["shift"] = Double(bumped.text)!
        XCTAssertEqual(NSDictionary(dictionary: expectedConfig), NSDictionary(dictionary: changedConfig))
        XCTAssertThrowsError(try PreparedBatch.refinement(of: image, steps: 8, shift: bumped, continuing: report))
        let result = try BatchRunner().run(prepared: next, outputRoot: dir, executable: cli, continuing: report) { _ in }
        XCTAssertEqual(result.parameters.shift?.text, "4.550123")
        XCTAssertEqual(result.sourceMetaprompt, source)
        XCTAssertEqual(result.images.last?.requestParameters?.shift?.text, "4.600123")
        XCTAssertEqual(result.images.last?.refinementOf, URL(fileURLWithPath: report.folder).appendingPathComponent(image.filename).path)
    }
    func testRefinementsFollowAllImagesInCurrentRoundInOrder() throws {
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir)
        let source = "count=3; resolution=64*64; shift=4.2..4.8\nA {red|green|yellow} apple"
        let batch = try PreparedBatch.prepare(source)
        var queued: [RefinementRequest] = []
        let round = try BatchRunner().run(prepared: batch, outputRoot: dir, executable: cli) { event in
            if case .imageFinished(let record) = event, record.plan.number == 1 {
                // Two clicks while the original three-image round is still running.
                queued = [6, 8].map { RefinementRequest(image: record.plan, steps: $0, folder: dir) }
            }
        }
        XCTAssertEqual(round.images.map(\.plan.number), [1, 2, 3])
        var cumulative = round
        for request in queued {
            let next = try PreparedBatch.refinement(of: request.image, steps: request.steps, continuing: cumulative)
            cumulative = try BatchRunner().run(prepared: next, outputRoot: dir, executable: cli, continuing: cumulative) { _ in }
        }
        XCTAssertEqual(cumulative.images.map(\.plan.steps), [3, 3, 3, 6, 8])
        XCTAssertEqual(cumulative.images.map(\.plan.number), [1, 2, 3, 4, 5])
        for index in [3, 4] {
            XCTAssertEqual(cumulative.images[index].plan.seed, round.images[0].plan.seed)
            XCTAssertEqual(cumulative.images[index].plan.shift, round.images[0].plan.shift)
            XCTAssertEqual(cumulative.images[index].plan.prompt, round.images[0].plan.prompt)
        }
        XCTAssertEqual(cumulative.sourceMetaprompt, source)
        XCTAssertEqual(cumulative.parameters.steps, 3); XCTAssertEqual(cumulative.parameters.count, 3)
        // Generate More still uses the metaprompt's original count and step count.
        let more = try PreparedBatch.prepare(source, continuing: cumulative)
        XCTAssertEqual(more.startingNumber, 6); XCTAssertEqual(more.preview.count, 3)
        XCTAssertEqual(more.preview.map(\.steps), [3, 3, 3])
    }
    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-batch-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true); return dir
    }
    func testRenderRetriesOnceWithFrozenRecipe() throws {
        for invalidOutput in [false, true] {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let cli = try fakeCLI(in: dir, failAttempts: 1, invalidOutput: invalidOutput)
            let prepared = try PreparedBatch.prepare("seed=1234; count=2; resolution=64*64\nA {red|green} apple").freezingPlans()
            var retries = 0; var starts = 0
            let report = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) {
                if case .message(let message) = $0, message.contains("retrying once") { retries += 1 }
                if case .imageStarted = $0 { starts += 1 }
            }
            XCTAssertEqual(report.status, "completed")
            XCTAssertEqual(report.images.count, 2); XCTAssertEqual(starts, 2); XCTAssertEqual(retries, 2)
            for (index, image) in report.images.enumerated() {
                XCTAssertEqual(image.renderAttempts, 2)
                XCTAssertEqual(image.plan.prompt, prepared.frozenPlans?[index].prompt)
                XCTAssertEqual(image.plan.seed, 1234)
                let folder = URL(fileURLWithPath: report.folder)
                let log = try String(contentsOf: folder.appendingPathComponent(image.logFile!), encoding: .utf8)
                XCTAssertTrue(log.contains("simulated failure")); XCTAssertTrue(log.contains("retrying once"))
                XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("logs/" + String(image.plan.filename.dropLast(4)) + ".attempt-1.png").path))
            }
        }
        let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cli = try fakeCLI(in: dir, failAttempts: 9)
        let prepared = try PreparedBatch.prepare("count=2; resolution=64*64\nPortrait")
        let report = try BatchRunner().run(prepared: prepared, outputRoot: dir, executable: cli) { _ in }
        XCTAssertEqual(report.status, "failed"); XCTAssertEqual(report.images.count, 1)
        XCTAssertEqual(report.images.first?.renderAttempts, 2)
        for cancel in [false, true] {
            let dir = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
            let cli = try fakeCLI(in: dir, failAttempts: 1)
            let runner = BatchRunner(); var interrupted = false
            let result = try runner.run(prepared: prepared, outputRoot: dir, executable: cli) {
                if case .message = $0, !interrupted {
                    interrupted = true
                    if cancel { runner.cancel() }
                    else { XCTAssertTrue(runner.skipCurrentImage(number: 1)) }
                }
            }
            XCTAssertEqual(result.images.first?.renderAttempts, 1)
            XCTAssertEqual(result.images.first?.status, cancel ? "cancelled" : "skipped")
            XCTAssertEqual(result.status, cancel ? "cancelled" : "completed")
            XCTAssertEqual(result.images.count, cancel ? 1 : 2)
        }
    }
    func fakeCLI(in dir: URL, sleeping: Bool = false, failAttempts: Int = 0, invalidOutput: Bool = false) throws -> URL {
        let fixture = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAeklEQVR4nO3PUQkAIBTAwBfMEEY0qiH8OITBAtzm7PV1wwUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWNKAFDWhBA1rQgBY0oAUNaEEDWtCAFjSgBQ1oQQNa0IAWPHYB80jBDxFDmmcAAAAASUVORK5CYII=")!
        try fixture.write(to: dir.appendingPathComponent("fixture.png"))
        let cli = dir.appendingPathComponent("fake image cli")
        let body = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo fake-1; exit 0; fi
        \(sleeping ? "exec /bin/sleep 30" : "")
        while [ "$#" -gt 0 ]; do
          case "$1" in --output) shift; out="$1" ;; esac
          shift
        done
        here="$(dirname "$0")"
        if [ \(failAttempts) -gt 0 ]; then
          attempts=0
          if [ -f "$out.calls" ]; then attempts=$(cat "$out.calls"); fi
          attempts=$((attempts + 1)); echo "$attempts" > "$out.calls"
          if [ "$attempts" -le \(failAttempts) ]; then
            echo 'simulated failure'; echo partial > "$out"; exit \(invalidOutput ? 0 : 1)
          fi
        fi
        cp "$here/fixture.png" "$out"
        echo 'Sampling... 3 / 3'
        echo 'Total generation time (including model loading): 0.02 s'
        echo 'Sampling step time (3 step(s)): avg 0.01 s'
        """
        try body.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        return cli
    }
}
