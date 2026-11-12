import Foundation
import AppKit
import Combine
import StoryBatchCore

@main @MainActor struct AppModelTests {
    static func main() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("story-batch-model-tests-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let find = PromptFindModel()
            let textView = NSTextView(frame: .zero)
            let searchText = "🙂 Hair hair hairstyle\nhair"
            textView.string = searchText
            find.attach(textView); find.query = "hair"; find.open()
            XCTAssertEqual(find.matches.map(\.location), [3, 8, 13, 23])
            XCTAssertEqual(find.counter, "1 of 4")
            XCTAssertEqual(textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 3, effectiveRange: nil) as? NSColor, PromptFindModel.activeColor)
            XCTAssertEqual(textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 8, effectiveRange: nil) as? NSColor, PromptFindModel.matchColor)
            find.move(by: 1); XCTAssertEqual(find.activeIndex, 1)
            find.activate(at: 14); XCTAssertEqual(find.activeIndex, 2)
            find.move(by: -1); XCTAssertEqual(find.activeIndex, 1)
            for _ in 0..<3 { find.move(by: 1) }
            XCTAssertEqual(find.activeIndex, 0)
            find.move(by: -1); XCTAssertEqual(find.activeIndex, 3)
            XCTAssertEqual(textView.string, searchText)
            find.close(); XCTAssertFalse(find.visible)
            XCTAssertNil(textView.layoutManager?.temporaryAttribute(.backgroundColor, atCharacterIndex: 3, effectiveRange: nil))
            find.query = "missing"; find.open()
            XCTAssertEqual(find.counter, "No matches"); XCTAssertNil(find.activeIndex)
            find.query = "hair"; textView.string = "A single Hair"; find.updateText(textView.string)
            XCTAssertEqual(find.matches.count, 1); XCTAssertEqual(find.activeIndex, 0)
            find.query = ""; XCTAssertTrue(find.matches.isEmpty)
            print("Checked: live Find ranges, Unicode, navigation, click activation and temporary highlight colors")
            let cli = try StoryBatchCoreTests().fakeCLI(in: dir)
            // Leave enough time to add refinements while the original round is in flight.
            let script = try String(contentsOf: cli, encoding: .utf8).replacingOccurrences(of: "while [", with: "/bin/sleep 0.2\nwhile [")
            try script.write(to: cli, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
            let store = EditorSessionStore(url: dir.appendingPathComponent("state/session.json"))
            let model = AppModel(sessionStore: store)
            model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("batches")
            model.source = "count=4; shift=2.25+0.5,2.25+0.5,2.4-0.1,2.1+2\nPortrait"; model.validate(); model.preview()
            XCTAssertEqual(model.prepared?.preview.map { $0.shift.text }, ["2.75", "2.75", "2.3", "4.1"])
            model.source = "count=2; shift=2+0.5,1/0\nPortrait"; model.validate()
            XCTAssertNil(model.parameters)
            XCTAssertTrue(model.validationError?.contains("item 2") == true)
            XCTAssertTrue(model.validationError?.contains("Division by zero") == true)
            let source = "title=model queue; count=3; resolution=64*64; shift=4.5501\nA {red|green} apple"
            model.source = source; model.validate(); model.start()
            try await waitUntil { model.activeImagePlan != nil }
            XCTAssertEqual(model.activeImagePlan?.shift.text, "4.5501")
            XCTAssertEqual(model.activeImagePlan?.steps, 3)
            try await waitUntil { model.images.first?.status == "completed" && model.isRunning }
            let image = model.images[0]; let folder = model.folder!
            let draft = "steps=unfinished\nAn unfinished {draft"
            model.source = draft; model.validate()
            model.queueRefinement(record: image, folder: folder, steps: 6)
            model.queueRefinement(record: image, folder: folder, steps: 8)
            XCTAssertEqual(model.pendingRefinements.map(\.steps), [6, 8])
            try await waitUntil { !model.isRunning }
            XCTAssertNil(model.activeImagePlan)
            XCTAssertEqual(model.images.map(\.plan.steps), [3, 3, 3, 6, 8])
            XCTAssertEqual(model.images.map(\.plan.number), [1, 2, 3, 4, 5])
            XCTAssertEqual(model.source, draft)
            XCTAssertNotNil(model.validationError)
            XCTAssertTrue(model.pendingRefinements.isEmpty)
            for index in [3, 4] {
                XCTAssertEqual(model.images[index].plan.prompt, image.plan.prompt)
                XCTAssertEqual(model.images[index].plan.seed, image.plan.seed)
                XCTAssertEqual(model.images[index].plan.shift, image.plan.shift)
            }
            // Idle click: exactly one image, even though the editor is currently invalid.
            let six = model.images[3]
            model.queueRefinement(record: six, folder: folder, steps: 8)
            XCTAssertTrue(model.isRunning)
            try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.images.count, 6)
            XCTAssertEqual(model.images.last?.plan.steps, 8)
            XCTAssertEqual(model.images.last?.plan.number, 6)
            XCTAssertEqual(model.source, draft)
            let sortedNumbers = model.images.sorted { a, b in
                if a.plan.seed != b.plan.seed { return a.plan.seed < b.plan.seed }
                if a.plan.steps != b.plan.steps { return a.plan.steps < b.plan.steps }
                return a.plan.number < b.plan.number
            }.map(\.plan.number)
            XCTAssertEqual(model.displayImages.map(\.plan.number), sortedNumbers)
            let reopened = AppModel(sessionStore: store)
            XCTAssertEqual(reopened.source, draft)
            XCTAssertEqual(reopened.images.count, 6)
            XCTAssertEqual(reopened.displayImages.map(\.plan.number), sortedNumbers)
            model.source = source; model.validate()
            XCTAssertEqual(model.generateTitle, "Generate More")
            // Stop must discard pending refinements rather than start them afterward.
            model.start()
            XCTAssertTrue(model.isRunning)
            model.queueRefinement(record: image, folder: folder, steps: 6)
            XCTAssertEqual(model.pendingRefinements.count, 1)
            model.stop()
            try await waitUntil { !model.isRunning }
            XCTAssertTrue(model.pendingRefinements.isEmpty)
            XCTAssertFalse(model.images.contains(where: { $0.plan.number >= 7 && $0.plan.steps == 6 }))
            // Preview navigation skips unfinished records, stops at both ends,
            // and stays with its original folder if the gallery changes batches.
            let ordered = model.displayImages.filter { $0.status == "completed" }
            let preview = ImagePreviewState(record: ordered[0], folder: folder, model: model)
            preview.isFullScreen = true
            var selectedFilename: String?
            preview.selectionChanged = { selectedFilename = $0.plan.filename }
            XCTAssertFalse(preview.canPrevious); XCTAssertTrue(preview.canNext)
            preview.move(by: -1)
            XCTAssertEqual(preview.record.plan.number, ordered[0].plan.number)
            for record in ordered.dropFirst() {
                preview.move(by: 1)
                XCTAssertEqual(preview.record.plan.number, record.plan.number)
            }
            for _ in 0..<20 { preview.move(by: 1) }
            XCTAssertEqual(preview.record.plan.number, ordered.last!.plan.number)
            XCTAssertEqual(selectedFilename, ordered.last!.plan.filename)
            XCTAssertFalse(preview.canNext)
            model.folder = dir.appendingPathComponent("different batch")
            for _ in 0..<20 { preview.move(by: -1) }
            XCTAssertEqual(preview.record.plan.number, ordered[0].plan.number)
            XCTAssertEqual(preview.records.count, 6)
            XCTAssertFalse(preview.canPrevious)
            XCTAssertEqual(preview.folder, folder)
            XCTAssertTrue(preview.isFullScreen)
            preview.isFullScreen = false
            model.folder = folder
            model.source = source.replacingOccurrences(of: "count=3", with: "count=1; seed=42; steps=5")
            model.validate()
            XCTAssertEqual(model.generateTitle, "Generate More")
            model.start()
            try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.folder, folder)
            XCTAssertEqual(model.images.last?.plan.seed, 42)
            XCTAssertEqual(model.images.last?.plan.steps, 5)
            XCTAssertEqual(model.images.filter { $0.plan.seed == 42 }.count, 1)
            let restoredParameters = AppModel(sessionStore: store)
            XCTAssertEqual(restoredParameters.generateTitle, "Generate More")
            XCTAssertEqual(restoredParameters.source, model.source)
            model.source += " changed body"; model.validate()
            XCTAssertEqual(model.generateTitle, "Generate More")
            let untouchedDraft = model.source
            let eight = model.images.first { $0.plan.steps == 8 }!
            let sixStep = model.images.first { $0.plan.steps == 6 }!
            XCTAssertTrue(model.queueShiftBump(record: eight, folder: folder, bump: .plusFiveHundredths))
            XCTAssertTrue(model.isRunning)
            model.queueRefinement(record: sixStep, folder: folder, steps: 8)
            XCTAssertEqual(model.pendingRefinements.count, 1)
            try await waitUntil { !model.isRunning }
            let variants = Array(model.images.suffix(2))
            XCTAssertEqual(variants.map(\.plan.steps), [8, 8])
            XCTAssertEqual(variants[0].plan.shift.text, "4.6001")
            XCTAssertEqual(variants[0].plan.seed, eight.plan.seed)
            XCTAssertEqual(variants[0].plan.prompt, eight.plan.prompt)
            XCTAssertEqual(variants[1].plan.shift, sixStep.plan.shift)
            XCTAssertEqual(model.source, untouchedDraft)
            let absoluteShift = try ShiftValue.viewerInput("1.875")
            XCTAssertTrue(model.queueShift(record: eight, folder: folder, shift: absoluteShift))
            try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.images.last?.plan.shift.text, "1.875")
            XCTAssertEqual(model.images.last?.plan.seed, eight.plan.seed)
            XCTAssertEqual(model.images.last?.plan.steps, eight.plan.steps)
            XCTAssertEqual(model.images.last?.plan.prompt, eight.plan.prompt)
            XCTAssertEqual(model.source, untouchedDraft)
            model.source = "count=4; shift=1,2,3\nAn apple"; model.validate()
            XCTAssertNil(model.parameters)
            XCTAssertTrue(model.validationError?.contains("Shift list has 3 values, but count is 4") == true)
            model.source = "count=3; shift=0.1,2.174,5.00001; resolution=64*64\nAn apple"; model.validate()
            XCTAssertNil(model.validationError)
            model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.images.map { $0.plan.shift.text }, ["0.1", "2.174", "5.00001"])
            model.start(); try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.images.map { $0.plan.shift.text }, ["0.1", "2.174", "5.00001", "0.1", "2.174", "5.00001"])
            let spikeFolder = model.folder!
            let spikeSource = model.source
            let spikeNumbers = model.displayImages.map(\.plan.number)
            try model.loadBatch(from: folder)
            XCTAssertEqual(model.folder, folder)
            XCTAssertEqual(model.source, source.replacingOccurrences(of: "count=3", with: "count=1; seed=42; steps=5"))
            XCTAssertEqual(model.selectedTab, .images)
            XCTAssertEqual(model.generateTitle, "Generate More")
            XCTAssertFalse(model.isRunning)
            XCTAssertEqual(model.displayImages.filter { $0.status == "completed" }.count, 10)
            let restoredBatch = AppModel(sessionStore: store)
            XCTAssertEqual(restoredBatch.folder, folder)
            XCTAssertEqual(restoredBatch.source, model.source)
            let priorSource = model.source; let priorImages = model.images.map(\.plan.filename)
            XCTAssertThrowsError(try model.loadBatch(from: dir))
            XCTAssertEqual(model.source, priorSource)
            XCTAssertEqual(model.images.map(\.plan.filename), priorImages)
            try model.loadBatch(from: spikeFolder)
            XCTAssertEqual(model.source, spikeSource)
            XCTAssertEqual(model.displayImages.map(\.plan.number), spikeNumbers)
            model.start()
            XCTAssertThrowsError(try model.loadBatch(from: folder))
            try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.images.count, 9)
            XCTAssertEqual(model.images.map(\.plan.number), Array(1...9))
            model.source = "seed=1234,_,_; shift=1,2,3; count=3; resolution=64*64\nAn apple"; model.validate()
            XCTAssertNil(model.validationError)
            model.start(); try await waitUntil { !model.isRunning }
            XCTAssertEqual(model.images.last?.plan.number, 12)
            let paired = Array(model.images.suffix(3))
            XCTAssertEqual(paired[0].plan.seed, 1234)
            XCTAssertEqual(paired.map { $0.plan.shift.text }, ["1", "2", "3"])
            XCTAssertTrue(paired[1].plan.seed != paired[2].plan.seed)
            model.source = "seed=1,2; count=3\nAn apple"; model.validate()
            XCTAssertNil(model.parameters)
            XCTAssertTrue(model.validationError?.contains("Seed list has 2 values, but count is 3") == true)
            print("Checked: paired seed/shift lists continue prior numbering and report seed-count feedback")
            print("Checked: opening prior batches, latest headers, gallery restoration, continued numbering, busy guard and invalid-folder preservation")
            print("Checked: ordered shift lists, feedback errors and Generate More restart")
            print("Checked: shift bumps and step refinements share the sequential queue without editing the draft")
            print("Checked: parameter-only edits retain folder and apply to the next round")
            print("Checked: preview navigation, boundaries, unfinished images and folder isolation")
            print("Checked: live AppModel queue, idle refinement, unchanged draft, restore and stop")
            try await checkQueuedRounds(in: dir, cli: cli)
            try await checkCollectValues(in: dir, cli: cli)
            try await checkPromptFields(in: dir, cli: cli)
            try await checkAspectSizing(in: dir, cli: cli)
            try await checkStopAfterImage(in: dir, cli: cli)
            try await checkTitleBatchesAndSort(in: dir, cli: cli)
            try await checkImageRefinementMode(in: dir, cli: cli)
            try await checkImageSelections(in: dir, cli: cli)
            try await checkRendererConfiguration(in: dir, cli: cli)
            try await checkRejectedImages(in: dir, cli: cli)
            try await checkCollectionScopesAndDisk(in: dir, cli: cli)
            try await checkSkipCurrentImage(in: dir, cli: cli)
            checkImageZoom()
            checkViewerEditingFocus()
            try await checkQueueReordering(in: dir, cli: cli)
            try await checkZoomSeedNavigationGuard(in: dir, cli: cli)
        } catch { XCTFail(error.localizedDescription) }
        #if !canImport(XCTest)
        print("App model checks: \(failures) failures")
        exit(failures == 0 ? 0 : 1)
        #endif
    }
    static func checkQueuedRounds(in dir: URL, cli: URL) async throws {
        let store = EditorSessionStore(url: dir.appendingPathComponent("queue-state/session.json"))
        let model = AppModel(sessionStore: store)
        model.outputRoot = dir.appendingPathComponent("queue-batches"); model.executablePath = cli.path
        let source = "title=queue test; count=3; seed=11,12,13; shift=1,2,3; resolution=64*64\nAn apple"
        model.source = source; model.validate(); model.start()
        try await waitUntil { model.activeImagePlan?.number == 1 }
        let folder = model.folder!
        XCTAssertEqual(model.nextActionTitle, "Queue Next"); XCTAssertTrue(model.canQueueNext)
        let second = model.currentQueuedImages.first { $0.plan.number == 2 }!
        model.cancelQueuedImage(id: second.id)
        XCTAssertFalse(model.queueImages.contains { $0.id == second.id })
        let nextSource = "title=queue test; count=3; seed=21,22,23; shift=1.5,1.6,1.7; steps=5; resolution=128*64\nAn apple"
        model.source = nextSource; model.validate(); model.queueNext()
        XCTAssertEqual(model.queuedWork.count, 1)
        let frozenJobs = model.queuedWork[0].visibleImages
        XCTAssertEqual(frozenJobs.map(\.plan.seed), [21, 22, 23])
        XCTAssertEqual(frozenJobs.map(\.plan.width), [128, 128, 128])
        model.cancelQueuedImage(id: frozenJobs[1].id)
        XCTAssertEqual(model.queuedWork[0].visibleImages.map(\.plan.seed), [21, 23])
        try await waitUntil { model.images.first?.status == "completed" && model.isRunning }
        let originalImage = model.images[0]
        model.queueRefinement(record: originalImage, folder: folder, steps: 7)
        model.source = "title=different title; count=1; seed=999; shift=2; steps=8\nChanged body"; model.validate()
        XCTAssertEqual(model.nextActionTitle, "New Batch"); XCTAssertFalse(model.canQueueNext)
        let count = model.queuedWork.count; model.queueNext(); XCTAssertEqual(model.queuedWork.count, count)
        model.source = "count=1; seed=999; shift=2; steps=8\nAn apple"; model.validate()
        XCTAssertTrue(model.canQueueNext)
        try await waitUntil { !model.isRunning }
        XCTAssertTrue(model.queueImages.isEmpty)
        XCTAssertEqual(model.folder, folder)
        XCTAssertEqual(model.images.map(\.plan.number), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(model.images.map(\.status), ["completed", "skipped", "completed", "completed", "skipped", "completed", "completed"])
        XCTAssertEqual(model.images.map(\.plan.seed), [11, 12, 13, 21, 22, 23, 11])
        XCTAssertEqual(model.images.map(\.plan.steps), [3, 3, 3, 5, 5, 5, 7])
        XCTAssertEqual(model.images[3].plan.shift.text, "1.5"); XCTAssertEqual(model.images[5].plan.shift.text, "1.7")
        XCTAssertEqual(model.source, "count=1; seed=999; shift=2; steps=8\nAn apple")
        XCTAssertEqual(model.parameters?.seed, 999)
        XCTAssertEqual(try BatchReport.load(in: folder).sourceMetaprompt, nextSource)
        // Removing every job in a queued round prevents it from launching at all.
        model.source = "count=2; seed=41; shift=2; resolution=64*64\nAnother apple"; model.validate(); model.start()
        try await waitUntil { model.activeImagePlan != nil }
        model.queueNext(); XCTAssertEqual(model.queuedWork.count, 1)
        for job in model.queuedWork[0].visibleImages { model.cancelQueuedImage(id: job.id) }
        XCTAssertTrue(model.queuedWork.isEmpty)
        model.queueRefinement(record: originalImage, folder: folder, steps: 7)
        XCTAssertEqual(model.pendingRefinements.count, 1)
        let variant = model.queuedWork[0].visibleImages[0]
        model.cancelQueuedImage(id: variant.id)
        XCTAssertTrue(model.pendingRefinements.isEmpty)
        model.queueRefinement(record: originalImage, folder: folder, steps: 7)
        model.stop(); try await waitUntil { !model.isRunning }
        XCTAssertTrue(model.queueImages.isEmpty)
        print("Checked: Queue Next snapshots, FIFO variants, individual removal, body-change guard and whole-queue stop")
    }
    static func checkCollectValues(in dir: URL, cli: URL) async throws {
        let store = EditorSessionStore(url: dir.appendingPathComponent("collect-state/session.json"))
        let model = AppModel(sessionStore: store)
        model.outputRoot = dir.appendingPathComponent("collect-batches"); model.executablePath = cli.path
        model.source = "title=collect test; count=4; seeds=34,1,678,4656; shift=1.5..2.25; resolution=64*64; notes=\"keep; these notes\"\nAn apple"
        model.validate(); model.start(); XCTAssertFalse(model.canCollectValues)
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.latestRunPlans.map(\.seed), [34, 1, 678, 4656])
        let actualShifts = model.latestRunPlans.map { $0.shift.text }
        model.source = "count=4; seed=1234; shift=1..4; notes=\"keep; these notes\"\nAn apple"; model.validate()
        model.collectSeeds(); model.collectShifts()
        XCTAssertTrue(model.source.contains("seeds=34,1,678,4656"))
        XCTAssertTrue(model.source.contains("shift=" + actualShifts.joined(separator: ",")))
        XCTAssertEqual(model.parameters?.seedValues, [34, 1, 678, 4656])
        XCTAssertEqual(model.parameters?.shiftValues?.map(\.text), actualShifts)
        XCTAssertEqual(model.parameters?.notes, "keep; these notes")
        XCTAssertEqual(CompiledMetaPrompt.promptBody(in: model.source), "An apple")
        model.source = "count=2; seeds=9,2; shift=(1.5,1.75)+.1; resolution=64*64\nAn apple"; model.validate(); model.start()
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.latestRunPlans.map(\.seed), [9, 2])
        XCTAssertEqual(model.latestRunPlans.map { $0.shift.text }, ["1.6", "1.85"])
        model.collectSeeds(); model.collectShifts()
        XCTAssertEqual(model.parameters?.seedValues, [9, 2])
        XCTAssertEqual(model.parameters?.shiftValues?.map(\.text), ["1.6", "1.85"])
        let reopened = AppModel(sessionStore: store)
        XCTAssertEqual(reopened.latestRunPlans.map(\.seed), [9, 2])
        XCTAssertTrue(reopened.canCollectValues)
        try model.loadBatch(from: model.folder!)
        XCTAssertEqual(model.latestRunPlans.map(\.seed), [9, 2])
        XCTAssertEqual(model.parameters?.shiftValues?.map(\.text), ["1.6", "1.85"])
        print("Checked: Collect Seeds/Shifts preserve usage order, collect only the latest run and survive batch reload/relaunch")
    }
    static func checkPromptFields(in dir: URL, cli: URL) async throws {
        let store = EditorSessionStore(url: dir.appendingPathComponent("field-session/state.json"))
        let model = AppModel(sessionStore: store)
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("field-batches")
        model.source = "count=1; seed=23; shift=1.75; resolution=64*64\nA {red} scarf."; model.validate()
        model.start(); try await waitUntil { !model.isRunning }
        let folder = model.folder
        model.extractChoices()
        XCTAssertEqual(model.promptText, "A [FIELD_1] scarf.")
        XCTAssertEqual(model.fieldText, "FIELD_1={red}")
        XCTAssertEqual(model.generateTitle, "Generate More")
        model.fieldText = "FIELD_1={blue}"
        XCTAssertEqual(model.generateTitle, "Generate More")
        model.start(); try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.folder, folder)
        XCTAssertEqual(model.images.map(\.plan.prompt), ["A red scarf.", "A blue scarf."])
        let saved = ImageRecipeSnapshot(record: model.images[0], folder: folder)
        XCTAssertEqual(saved.prompt, "A red scarf.")
        model.parameterText = "count=1; seed=99; shift=2; resolution=64*64"
        XCTAssertEqual(model.fieldText, "FIELD_1={blue}")
        XCTAssertEqual(model.generateTitle, "Generate More")
        model.promptText = "Different [FIELD_1] scarf."
        XCTAssertEqual(model.generateTitle, "Generate More")
        model.promptText = "A [FIELD_1] scarf."
        model.fieldText = "FIELD_1={red}"
        model.start()
        model.fieldText = "FIELD_1={blue}"
        XCTAssertEqual(model.nextActionTitle, "Queue Next"); XCTAssertTrue(model.canQueueNext)
        model.queueNext()
        model.fieldText = "FIELD_1={green}"
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.folder, folder)
        XCTAssertEqual(model.images.suffix(2).map(\.plan.prompt), ["A red scarf.", "A blue scarf."])
        XCTAssertEqual(model.fieldText, "FIELD_1={green}")
        XCTAssertEqual(saved.prompt, "A red scarf.")
        let restored = AppModel(sessionStore: store)
        XCTAssertEqual(restored.source, model.source)
        XCTAssertEqual(restored.fieldText, "FIELD_1={green}")
        if let folder { try restored.loadBatch(from: folder) }
        XCTAssertEqual(restored.fieldText, "FIELD_1={blue}")
        restored.fieldText = "FIELD_1=[MISSING]"
        XCTAssertNotNil(restored.validationError); XCTAssertNil(restored.parameters)
        print("Checked: split editors, choice extraction, field-only continuation, frozen queued fields, pinned recipes, session and batch reload")
    }
    static func checkAspectSizing(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("aspect-session/state.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("aspect-batches")
        model.source = "count=1; seed=23; aspect=18:14\nA portrait."
        model.validate()
        XCTAssertEqual(model.parameters?.aspect, "9:7")
        model.start(); try await waitUntil { !model.isRunning }
        let folder = model.folder
        XCTAssertEqual(model.images.last?.plan.width, 1152)
        XCTAssertEqual(model.images.last?.plan.height, 896)
        model.parameterText = "count=1; seed=23; aspect=1:1; pixel_max=512*512"
        XCTAssertEqual(model.generateTitle, "Generate More")
        model.start()
        model.parameterText = "count=1; seed=23; aspect=3:2; pixel_max=1024*1024"
        model.queueNext()
        model.parameterText = "count=1; seed=23; aspect=1:1; pixel_max=64*64"
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.folder, folder)
        XCTAssertEqual(model.images.map(\.plan.width), [1152, 512, 1152])
        XCTAssertEqual(model.images.map(\.plan.height), [896, 512, 768])
        XCTAssertEqual(model.parameters?.width, 64)
        model.parameterText = "aspect=9:7; resolution=1152*896"
        XCTAssertNil(model.parameters); XCTAssertTrue(model.validationError?.contains("not both") == true)
        model.parameterText = "resolution=1536*1024"
        XCTAssertNil(model.parameters); XCTAssertTrue(model.validationError?.contains("pixel_max") == true)

        // Old over-cap reports remain reviewable without silently raising the draft's cap.
        let legacyFolder = dir.appendingPathComponent("legacy-over-cap")
        try FileManager.default.createDirectory(at: legacyFolder, withIntermediateDirectories: true)
        let oldSource = "count=1; resolution=1536*1024\nA portrait."
        var legacyParameters = try CompiledMetaPrompt.compile("count=1; resolution=1536*1024; pixel_max=1536*1024\nA portrait.").parameters
        legacyParameters.pixelMax = nil
        var legacy = BatchReport(id: "legacy", createdAt: "old", source: oldSource, parameters: legacyParameters, executable: cli.path, cliVersion: "test", folder: legacyFolder.path, reportFilename: "report_legacy.json")
        legacy.status = "completed"
        try JSONEncoder().encode(legacy).write(to: legacyFolder.appendingPathComponent(legacy.reportFilename))
        try model.loadBatch(from: legacyFolder)
        XCTAssertEqual(model.folder, legacyFolder); XCTAssertEqual(model.source, oldSource)
        XCTAssertNil(model.parameters); XCTAssertTrue(model.validationError?.contains("pixel_max") == true)
        model.parameterText += "; pixel_max=1536*1024"
        XCTAssertNotNil(model.parameters)
        print("Checked: aspect/cap feedback, folder continuation, frozen queued dimensions and legacy over-cap review")
    }
    static func checkStopAfterImage(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("finish-image/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("finish-image/batches")
        model.source = "count=3; seed=23; resolution=64*64\nAn apple."
        model.validate(); model.start()
        // A click during preparation must still allow one image to complete.
        model.stopAfterCurrentImage()
        XCTAssertTrue(model.stoppingAfterImage); XCTAssertFalse(model.canQueueNext)
        XCTAssertTrue(model.queueImages.isEmpty)
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.images.count, 1); XCTAssertEqual(model.images.first?.status, "completed")
        XCTAssertFalse(model.stoppingAfterImage)
        let folder = model.folder!
        let original = model.images[0]
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(original.plan.filename).path))
        XCTAssertEqual(try BatchReport.load(in: folder).status, "completed")
        XCTAssertEqual(model.generateTitle, "Generate More")

        model.start(); try await waitUntil { model.activeImagePlan != nil }
        model.queueNext()
        model.queueRefinement(record: original, folder: folder, steps: 6)
        XCTAssertEqual(model.queuedWork.count, 2)
        model.stopAfterCurrentImage(); model.stopAfterCurrentImage() // Idempotent.
        XCTAssertTrue(model.queueImages.isEmpty)
        model.queueNext(); model.queueRefinement(record: original, folder: folder, steps: 8)
        XCTAssertTrue(model.queueImages.isEmpty)
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.images.map(\.status), ["completed", "completed"])
        XCTAssertEqual(model.images.map(\.plan.number), [1, 2])
        XCTAssertEqual(try BatchReport.load(in: folder).images.count, 2)
        XCTAssertEqual(model.folder, folder)
        XCTAssertFalse(model.stopping); XCTAssertFalse(model.stoppingAfterImage)
        print("Checked: finish-current during preparation and rendering, clearing rounds/variants, saved output and continuation")
    }
    static func checkTitleBatchesAndSort(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("title-batches/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("title-batches/outputs")
        model.source = "title=study; count=3; seeds=10,2,10; shift=10,2,2; resolution=64*64\nFirst portrait."
        model.validate(); model.start(forceNewBatch: true)
        try await waitUntil { !model.isRunning }
        let folder = model.folder!
        XCTAssertEqual(model.displayImages.map(\.plan.number), [2, 3, 1])
        XCTAssertTrue(model.queueShiftBump(record: model.images[2], folder: folder, bump: .plusFiveHundredths))
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.displayImages.map(\.plan.number), [2, 3, 4, 1])
        model.parameterText = "title=study; count=1; seed=10; shift=2; steps=6; resolution=64*64"
        model.promptText = "Completely different [COLOR] landscape."
        model.fieldText = "COLOR={blue}"
        XCTAssertTrue(model.canQueueMore)
        model.start()
        model.fieldText = "COLOR={red}"
        XCTAssertTrue(model.canQueueNext); model.queueNext()
        model.fieldText = "COLOR={green}"
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.folder, folder)
        XCTAssertEqual(model.images.suffix(2).map(\.plan.prompt), ["Completely different blue landscape.", "Completely different red landscape."])
        XCTAssertEqual(model.images[0].sourceMetaprompt?.contains("First portrait."), true)
        XCTAssertEqual(model.displayImages.map(\.plan.number), [2, 3, 5, 6, 4, 1])
        for image in model.images { model.toggleShortlist(image, folder: folder) }
        XCTAssertEqual(model.shortlistedImages.map(\.record.plan.number), [2, 3, 5, 6, 4, 1])
        model.selectedTab = .shortlist
        let sortedViewer = ImagePreviewState(record: model.images[0], folder: folder, model: model)
        let viewedFilename = sortedViewer.record.plan.filename
        sortedViewer.updateZoom(2)
        XCTAssertEqual(sortedViewer.index, 5)
        model.imageSort = .seededStep
        sortedViewer.sortChanged()
        XCTAssertEqual(sortedViewer.record.plan.filename, viewedFilename)
        XCTAssertEqual(sortedViewer.index, 3)
        XCTAssertTrue(sortedViewer.isZoomed)
        XCTAssertEqual(model.displayImages.map(\.plan.number), [2, 3, 4, 1, 5, 6])
        XCTAssertEqual(model.shortlistedImages.map(\.record.plan.number), [2, 3, 4, 1, 5, 6])
        XCTAssertEqual(sortedViewer.records.map(\.plan.number), [2, 3, 4, 1, 5, 6])
        model.imageSort = .newest
        sortedViewer.sortChanged()
        XCTAssertEqual(sortedViewer.record.plan.filename, viewedFilename)
        XCTAssertEqual(sortedViewer.index, 5)
        XCTAssertTrue(sortedViewer.isZoomed)
        XCTAssertEqual(model.displayImages.map(\.plan.number), model.images.filter { $0.status != "skipped" }.reversed().map(\.plan.number))
        model.imageSort = .seeded
        model.parameterText = "title=renamed; count=1; seed=10; shift=2; resolution=64*64"
        XCTAssertFalse(model.canQueueMore); XCTAssertNil(model.continuation)
        model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        let renamed = model.folder!
        XCTAssertTrue(renamed != folder); XCTAssertEqual(model.images.first?.plan.number, 1)
        // Explicitly force a fresh folder even with identical title and config.
        model.preview(); model.start(forceNewBatch: true)
        try await waitUntil { !model.isRunning }
        XCTAssertTrue(model.folder != renamed); XCTAssertEqual(model.images.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        print("Checked: numeric gallery sorting, inserted shift variants, title-based prompt/field continuation, frozen queues and forced fresh folders")
    }
    static func checkImageRefinementMode(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("image-refinement/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("image-refinement/batches")
        model.source = "title=keeper; seed=1234; shift=1.75; steps=6; count=1; resolution=64*64\nA warm portrait with red glasses."; model.validate(); model.start(forceNewBatch: true)
        try await waitUntil { !model.isRunning }
        let normalSource = model.source, normalFolder = model.folder!, root = model.images[0]
        model.beginRefinement(record: root, folder: normalFolder)
        XCTAssertTrue(model.isRefinementMode); XCTAssertEqual(model.promptText, "")
        XCTAssertEqual(model.refinementOriginalPrompt, root.plan.prompt)
        XCTAssertEqual(model.parameters?.seed, 1234); XCTAssertEqual(model.parameters?.shift?.text, "1.75")
        XCTAssertEqual(model.parameters?.count, 1); XCTAssertEqual(model.parameters?.width, 64)
        XCTAssertEqual(model.refinementStrengthText, "0.35")
        model.promptText = "Slightly narrower glasses, retaining the pose and light."
        XCTAssertTrue(model.source.contains(root.plan.prompt)); XCTAssertTrue(model.source.contains("Slightly narrower glasses"))
        model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        let refinementFolder = model.folder!
        let report = try BatchReport.load(in: refinementFolder)
        XCTAssertEqual(report.refinementContext?.promptMode, "appendDelta")
        XCTAssertEqual(report.refinementContext?.sourcePrompt, root.plan.prompt)
        XCTAssertEqual(report.refinementContext?.refinementText, "Slightly narrower glasses, retaining the pose and light.")
        XCTAssertEqual(report.images.first?.inputStrength, 0.35)
        XCTAssertTrue(FileManager.default.fileExists(atPath: refinementFolder.appendingPathComponent("inputs/root.png").path))
        model.refinementPromptMode = .fullOverride
        XCTAssertEqual(model.promptText, root.plan.prompt)
        model.promptText = "A cinematic portrait in warm light, with blue glasses."
        XCTAssertTrue(model.source.contains("blue glasses")); XCTAssertFalse(model.source.contains("Slightly narrower glasses"))
        model.exitRefinement()
        XCTAssertFalse(model.isRefinementMode); XCTAssertEqual(model.source, normalSource); XCTAssertEqual(model.folder, normalFolder)
        XCTAssertEqual(model.images.count, 1)
        print("Checked: image-root refinement prompt strategies, copied input provenance, inherited controls and exit back to Queue Batch")
    }
    static func checkRendererConfiguration(in dir: URL, cli: URL) async throws {
        let store = EditorSessionStore(url: dir.appendingPathComponent("renderer-config/session.json"))
        let renderer = RendererConfigurationStore(url: store.url.deletingLastPathComponent().appendingPathComponent("renderer.local.json"))
        var recipe = RenderRecipe.zImageTurbo; recipe.model = "model-a.ckpt"
        recipe.loras = [DrawThingsLoRA(file: "adapter-a.ckpt", weight: 0.5)]
        try renderer.save(RendererConfiguration(executablePath: cli.path, recipe: recipe))
        let model = AppModel(sessionStore: store)
        XCTAssertEqual(model.executablePath, cli.path)
        model.executablePath = cli.path
        XCTAssertEqual(try renderer.load()?.recipe, recipe)
        model.outputRoot = dir.appendingPathComponent("renderer-config/batches")
        model.source = "title=config; count=1; resolution=64*64\nA synthetic test apple."
        model.validate(); model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        let source = model.images[0], folder = model.folder!
        XCTAssertEqual(source.plan.recipe, recipe)
        var next = recipe; next.model = "model-b.ckpt"; next.loras = []
        try renderer.save(RendererConfiguration(executablePath: cli.path, recipe: next))
        let reloaded = AppModel(sessionStore: store)
        XCTAssertEqual(reloaded.images[0].plan.recipe, recipe)
        reloaded.queueRefinement(record: source, folder: folder, steps: 6)
        try await waitUntil { !reloaded.isRunning }
        XCTAssertEqual(reloaded.images.last?.plan.recipe, recipe)
        reloaded.start(); try await waitUntil { !reloaded.isRunning }
        XCTAssertEqual(reloaded.images.last?.plan.recipe, next)
        try Data("broken config".utf8).write(to: renderer.url)
        let invalid = AppModel(sessionStore: store)
        XCTAssertNil(invalid.parameters)
        XCTAssertTrue(invalid.validationError?.contains("renderer config") == true)
        invalid.executablePath = cli.path
        XCTAssertEqual(try String(contentsOf: renderer.url, encoding: .utf8), "broken config")
        print("Checked: local renderer settings persistence, alternate models, source-recipe variants and malformed-config preservation")
    }
    static func checkRejectedImages(in dir: URL, cli: URL) async throws {
        let store = EditorSessionStore(url: dir.appendingPathComponent("rejection/session.json"))
        let model = AppModel(sessionStore: store)
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("rejection/batches")
        model.source = "title=rejection; seeds=10,20,30; count=3; shift=1.75; resolution=64*64\nA portrait."
        model.validate(); model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        let folder = model.folder!, first = model.images[0], second = model.images[1], third = model.images[2]
        let image = try Data(contentsOf: folder.appendingPathComponent(second.plan.filename))
        let prompt = try Data(contentsOf: folder.appendingPathComponent(second.promptFile!))
        model.selectedTab = .images
        let viewer = ImagePreviewState(record: second, folder: folder, model: model)
        model.toggleShortlist(second, folder: folder); model.toggleFavorite(second, folder: folder)
        model.toggleRejected(second, folder: folder); viewer.restoreScope()
        XCTAssertEqual(model.displayImages.map(\.plan.seed), [10, 30])
        XCTAssertEqual(model.rejectedImages.map(\.plan.seed), [20])
        XCTAssertEqual(viewer.record.plan.seed, 30)
        XCTAssertTrue(model.isShortlisted(second, folder: folder)); XCTAssertTrue(model.isFavorite(second, folder: folder))
        model.toggleRejected(third, folder: folder); viewer.restoreScope()
        XCTAssertEqual(viewer.record.plan.seed, 10)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(second.plan.filename)), image)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent(second.promptFile!)), prompt)
        model.selectedTab = .rejected
        let rejected = ImagePreviewState(record: second, folder: folder, model: model)
        XCTAssertEqual(rejected.records.map(\.plan.seed), [20, 30])
        model.toggleRejected(second, folder: folder); rejected.restoreScope()
        XCTAssertEqual(rejected.record.plan.seed, 30)
        XCTAssertEqual(model.displayImages.map(\.plan.seed), [10, 20])
        let restored = AppModel(sessionStore: store)
        XCTAssertEqual(restored.rejectedImages.map(\.plan.seed), [30])
        restored.toggleShortlist(third, folder: folder); restored.toggleShortlist(third, folder: folder)
        XCTAssertTrue(AppModel(sessionStore: store).isRejected(third, folder: folder))
        model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        XCTAssertTrue(model.rejectedImages.isEmpty)
        XCTAssertEqual(model.displayImages.count, 3)
        try model.loadBatch(from: folder)
        XCTAssertEqual(model.rejectedImages.map(\.plan.seed), [30])
        model.toggleRejected(third, folder: folder)
        XCTAssertEqual(model.displayImages.map(\.plan.seed), [10, 20, 30])
        XCTAssertEqual(MainTab.allCases.suffix(2), [.favorites, .rejected])
        let legacy = SavedImageSelection(folder: folder, record: first, shortlisted: true)
        XCTAssertNil(try JSONDecoder().decode(SavedImageSelection.self, from: JSONEncoder().encode(legacy)).rejected)
        print("Checked: batch rejection/restore, next/previous navigation, persistence, collection independence and unchanged image/prompt files")
    }
    static func checkImageSelections(in dir: URL, cli: URL) async throws {
        XCTAssertEqual(ShiftBump.minusTenth.rawValue, "-0.1")
        let store = EditorSessionStore(url: dir.appendingPathComponent("selections/session.json"))
        let model = AppModel(sessionStore: store)
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("selection-batches")
        model.source = "title=selection; count=2; seeds=10,20; shift=1.75; resolution=64*64\nA portrait."
        model.validate(); model.start(forceNewBatch: true)
        try await waitUntil { !model.isRunning }
        let firstFolder = model.folder!, first = model.images[0], second = model.images[1]
        model.toggleShortlist(first, folder: firstFolder)
        model.toggleShortlist(second, folder: firstFolder)
        model.toggleFavorite(first, folder: firstFolder)
        XCTAssertEqual(model.shortlistedImages.map(\.record.plan.seed), [10, 20])
        model.imageSort = .newest
        XCTAssertEqual(model.shortlistedImages.map(\.record.plan.seed), [20, 10])
        XCTAssertEqual(model.favoriteImages.count, 1)
        model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        let secondFolder = model.folder!, other = model.images[0]
        XCTAssertEqual(first.plan.filename, other.plan.filename)
        XCTAssertTrue(model.shortlistedImages.isEmpty)
        model.toggleFavorite(other, folder: secondFolder)
        XCTAssertEqual(model.favoriteImages.count, 2)
        XCTAssertFalse(model.isShortlisted(other, folder: secondFolder))
        let draft = model.source
        let preview = ImagePreviewState(record: first, folder: firstFolder, model: model)
        XCTAssertTrue(preview.records.contains { $0.runID == first.runID })
        XCTAssertFalse(preview.records.contains { $0.runID == other.runID })
        XCTAssertEqual(model.folder, secondFolder); XCTAssertEqual(model.source, draft)
        let restored = AppModel(sessionStore: store)
        XCTAssertEqual(restored.folder, secondFolder)
        XCTAssertEqual(restored.favoriteImages.count, 2)
        try restored.loadBatch(from: firstFolder)
        XCTAssertEqual(restored.shortlistedImages.count, 2)
        XCTAssertTrue(restored.isShortlisted(first, folder: firstFolder))
        restored.toggleFavorite(first, folder: firstFolder)
        XCTAssertTrue(restored.isShortlisted(first, folder: firstFolder))
        XCTAssertFalse(restored.isFavorite(first, folder: firstFolder))
        // An absent original remains removable, without discarding other selections.
        try FileManager.default.removeItem(at: secondFolder.appendingPathComponent(other.plan.filename))
        let afterMissing = AppModel(sessionStore: store)
        XCTAssertEqual(afterMissing.folder, firstFolder)
        XCTAssertEqual(afterMissing.favoriteImages.count, 1)
        afterMissing.toggleFavorite(other, folder: secondFolder)
        XCTAssertTrue(afterMissing.favoriteImages.isEmpty)
        XCTAssertEqual(afterMissing.shortlistedImages.count, 2)
        afterMissing.toggleShortlist(first, folder: firstFolder)
        XCTAssertFalse(afterMissing.isShortlisted(first, folder: firstFolder))
        XCTAssertEqual(AppModel(sessionStore: store).shortlistedImages.count, 1)
        print("Checked: shortlist/favorite independence, batch isolation, same-name files, persistence, foreign previews and missing-file removal")
    }
    static func checkCollectionScopesAndDisk(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("disk-collections/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("disk-collections/batches")
        model.source = "title=collection scope; count=2; seeds=10,20; shift=1.75; resolution=64*64\nA portrait."
        model.validate(); model.start(forceNewBatch: true); try await waitUntil { !model.isRunning }
        let folder = model.folder!, first = model.images[0]
        model.toggleShortlist(first, folder: folder)
        model.selectedTab = .shortlist
        let shortlist = ImagePreviewState(record: first, folder: folder, model: model)
        XCTAssertEqual(shortlist.records.count, 1); XCTAssertFalse(shortlist.canNext)
        model.queueRefinement(record: first, folder: folder, steps: 6)
        XCTAssertTrue(model.queueShiftBump(record: first, folder: folder, bump: .plusQuarter))
        try await waitUntil { model.activeImagePlan?.steps == 6 }
        XCTAssertEqual(model.shortlistedImages.filter { $0.record.status == "running" }.count, 1)
        XCTAssertEqual(model.shortlistedImages.count, 2)
        XCTAssertEqual(shortlist.records.count, 1) // Viewer skips unfinished images.
        XCTAssertFalse(model.imageSelections.contains { $0.record.status == "running" })
        model.selectedTab = .images; shortlist.restoreScope()
        try await waitUntil { model.activeImagePlan?.number == 4 }
        XCTAssertEqual(model.shortlistedImages.filter { $0.record.status == "running" }.first?.record.plan.shift.text, "2")
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.images.count, 4); XCTAssertEqual(model.shortlistedImages.count, 3)
        XCTAssertTrue(model.shortlistedImages.allSatisfy { $0.record.status == "completed" })
        XCTAssertEqual(shortlist.records.count, 4)
        model.selectedTab = .shortlist; shortlist.restoreScope(); XCTAssertEqual(shortlist.records.count, 3)
        XCTAssertFalse(shortlist.records.contains { $0.plan.seed == 20 })
        let ordered = shortlist.records
        shortlist.move(by: 1)
        XCTAssertEqual(shortlist.record.plan.filename, ordered[1].plan.filename)
        model.toggleShortlist(shortlist.record, folder: folder); shortlist.restoreScope()
        XCTAssertEqual(shortlist.record.plan.filename, ordered[2].plan.filename)
        model.toggleShortlist(shortlist.record, folder: folder); shortlist.restoreScope()
        XCTAssertEqual(shortlist.record.plan.filename, ordered[0].plan.filename)
        model.toggleShortlist(shortlist.record, folder: folder); shortlist.restoreScope()
        XCTAssertTrue(shortlist.records.isEmpty); XCTAssertFalse(shortlist.canPrevious); XCTAssertFalse(shortlist.canNext)
        XCTAssertEqual(model.images.count, 4)
        model.toggleFavorite(first, folder: folder)
        let copy = model.favoriteImages[0]
        XCTAssertEqual(copy.url.deletingLastPathComponent().resolvingSymlinksInPath(), model.favoritesFolder.resolvingSymlinksInPath())
        let originalData = try Data(contentsOf: folder.appendingPathComponent(first.plan.filename))
        XCTAssertEqual(try Data(contentsOf: copy.url), originalData)
        // An unindexed external image is discovered from the directory itself.
        let external = model.favoritesFolder.appendingPathComponent("external.png")
        try originalData.write(to: external)
        model.selectedTab = .favorites
        XCTAssertEqual(model.favoriteImages.count, 2)
        let externalItem = PreviewImageItem(favorite: model.favoriteImages.first { $0.source == nil }!)
        let favoritePreview = ImagePreviewState(record: externalItem.record, folder: externalItem.folder, model: model)
        XCTAssertFalse(favoritePreview.hasRecipe); XCTAssertEqual(favoritePreview.records.count, 2)
        model.selectedTab = .images; favoritePreview.restoreScope()
        XCTAssertEqual(favoritePreview.folder, folder); XCTAssertEqual(favoritePreview.records.count, 4)
        // Deleting the original never removes its saved favorite copy.
        try FileManager.default.removeItem(at: folder.appendingPathComponent(first.plan.filename))
        model.refreshFavorites(); XCTAssertEqual(model.favoriteImages.count, 2)
        try FileManager.default.removeItem(at: external)
        model.selectedTab = .favorites; XCTAssertEqual(model.favoriteImages.count, 1)
        model.toggleFavorite(copy.record!, folder: model.favoritesFolder)
        XCTAssertTrue(model.favoriteImages.isEmpty)
        print("Checked: tab-scoped navigation, inherited shortlist variants, copied favorites, external additions/deletions and metadata-free viewing")
    }
    static func checkSkipCurrentImage(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("skip-image/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("skip-image/batches")
        model.source = "title=skip test; count=1; seed=10; shift=1.75; resolution=64*64\nA portrait."
        model.validate(); model.start(); try await waitUntil { !model.isRunning }
        let folder = model.folder!, keeper = model.images[0]
        model.parameterText = "title=skip test; count=2; seed=10; shift=1.75; resolution=64*64"
        model.start(); try await waitUntil { model.activeImagePlan?.number == 2 }
        model.queueNext()
        model.queueRefinement(record: keeper, folder: folder, steps: 6)
        model.queueNext()
        let waiting = model.queueImages.count
        model.skipCurrentImage(); model.skipCurrentImage()
        XCTAssertEqual(model.skippingImage, 2); XCTAssertFalse(model.stopping)
        XCTAssertEqual(model.queueImages.count, waiting)
        try await waitUntil { model.activeImagePlan?.number == 6 }
        XCTAssertEqual(model.images.first { $0.plan.number == 2 }?.status, "skipped")
        model.skipCurrentImage()
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.images.map(\.status), ["completed", "skipped", "completed", "completed", "completed", "skipped", "completed", "completed"])
        XCTAssertEqual(model.folder, folder); XCTAssertTrue(model.queueImages.isEmpty); XCTAssertNil(model.skippingImage)
        let report = try BatchReport.load(in: folder)
        XCTAssertEqual(report.status, "completed"); XCTAssertEqual(report.images.count, 8)
        XCTAssertEqual(model.displayImages.map(\.plan.number), [1, 3, 4, 5, 7, 8])
        print("Checked: skip active render and one-image variant without clearing current-round or future jobs")
    }
    static func checkQueueReordering(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("ordering/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("ordering/batches")
        model.source = "title=ordering; count=1; seed=1; shift=1; resolution=64*64\nKeeper."
        model.validate(); model.start(); try await waitUntil { !model.isRunning }
        let keeper = model.images[0], folder = model.folder!
        model.source = "title=ordering; count=3; seeds=11,12,13; shift=1,2,3; resolution=64*64\nOriginal round."
        model.validate(); model.start(); try await waitUntil { model.activeImagePlan?.seed == 11 }
        model.source = "title=ordering; count=2; seeds=21,22; shift=4,5; resolution=64*64\nNew round."
        model.validate(); model.queueNext()
        model.queueRefinement(record: keeper, folder: folder, steps: 6)
        model.source = "title=ordering; count=1; seed=31; shift=6; resolution=64*64\nCanceled round."
        model.validate(); model.queueNext()
        let untouched = model.source
        func job(_ seed: Int) -> UUID { model.queueImages.first { $0.plan.seed == seed }!.id }
        model.moveQueuedImage(id: job(22), direction: .next)
        XCTAssertEqual(model.queueImages.map(\.plan.seed), [22, 12, 13, 21, 1, 31])
        model.moveQueuedImage(id: job(13), direction: .up)
        model.moveQueuedImage(id: job(31), direction: .up)
        model.moveQueuedImage(id: job(21), direction: .down)
        XCTAssertEqual(model.queueImages.map(\.plan.seed), [22, 13, 12, 31, 21, 1])
        model.cancelQueuedImage(id: job(31))
        model.moveQueuedImage(id: job(1), direction: .next)
        XCTAssertEqual(model.queueImages.map(\.plan.seed), [1, 22, 13, 12, 21])
        XCTAssertEqual(model.activeImagePlan?.seed, 11)
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.images.map(\.plan.seed), [1, 11, 1, 22, 13, 12, 21])
        XCTAssertEqual(model.images.map(\.plan.steps), [3, 3, 6, 3, 3, 3, 3])
        XCTAssertEqual(model.images.map { $0.plan.shift.text }, ["1", "1", "1", "5", "3", "2", "4"])
        XCTAssertTrue(model.images.allSatisfy { $0.status == "completed" })
        XCTAssertEqual(model.images.map(\.plan.number), Array(1...7))
        XCTAssertEqual(model.images[1].runID, model.images[4].runID)
        XCTAssertEqual(model.images[1].runID, model.images[5].runID)
        XCTAssertEqual(model.images[3].runID, model.images[6].runID)
        XCTAssertEqual(model.images[4].requestParameters?.count, 3)
        XCTAssertEqual(model.images[3].requestParameters?.count, 2)
        let report = try BatchReport.load(in: folder)
        XCTAssertEqual(report.requestedImageCount, 7)
        XCTAssertEqual(report.latestCompletedPlans.map(\.seed), [22, 21])
        XCTAssertEqual(report.parameters.count, 2)
        XCTAssertEqual(model.source, untouched); XCTAssertEqual(model.folder, folder)
        model.source = "title=reserved slots; count=3; seeds=41,42,43; shift=1; resolution=64*64\nPortrait."
        model.validate(); model.start(forceNewBatch: true)
        try await waitUntil { model.activeImagePlan?.seed == 41 }
        model.moveQueuedImage(id: job(43), direction: .next)
        model.cancelQueuedImage(id: job(42))
        XCTAssertEqual(model.queueImages.map(\.plan.seed), [43])
        try await waitUntil { !model.isRunning }
        XCTAssertEqual(model.images.map(\.plan.seed), [41, 43, 42])
        XCTAssertEqual(model.images.map(\.status), ["completed", "completed", "skipped"])
        XCTAssertEqual(try BatchReport.load(in: model.folder!).requestedImageCount, 3)
        print("Checked: cross-round Run Next/up/down, cancellation, variants, frozen pairings and logical-run collection/accounting")
    }
    static func checkZoomSeedNavigationGuard(in dir: URL, cli: URL) async throws {
        let model = AppModel(sessionStore: EditorSessionStore(url: dir.appendingPathComponent("seed-guard/session.json")))
        model.executablePath = cli.path; model.outputRoot = dir.appendingPathComponent("seed-guard/batches")
        model.source = "title=guard; count=4; seeds=10,10,20,20; shift=1,2,1,2; resolution=64*64\nPortrait."
        model.validate(); model.start(); try await waitUntil { !model.isRunning }
        let preview = ImagePreviewState(record: model.images[0], folder: model.folder, model: model)
        var updates = 0
        let observation = preview.objectWillChange.sink { updates += 1 }
        defer { observation.cancel() }
        preview.updateZoom(1); preview.updateZoom(1)
        XCTAssertEqual(updates, 0) // Native reconciliation must settle without a view-update loop.
        preview.updateZoom(3)
        preview.move(by: 1)
        XCTAssertEqual(preview.record.plan.number, 2); XCTAssertNil(preview.seedNavigationNotice)
        preview.move(by: 1)
        XCTAssertEqual(preview.record.plan.number, 2)
        XCTAssertEqual(preview.seedNavigationNotice, "Next seed; press again to proceed")
        preview.move(by: 1, isRepeat: true)
        XCTAssertEqual(preview.record.plan.number, 2)
        preview.move(by: -1) // Reversing within the seed cancels confirmation.
        XCTAssertEqual(preview.record.plan.number, 1); XCTAssertNil(preview.seedNavigationNotice)
        preview.move(by: 1); preview.move(by: 1); preview.move(by: 1)
        XCTAssertEqual(preview.record.plan.number, 3); XCTAssertFalse(preview.isZoomed)
        XCTAssertNil(preview.seedNavigationNotice)
        preview.updateZoom(4)
        preview.move(by: -1)
        XCTAssertEqual(preview.seedNavigationNotice, "Previous seed; press again to proceed")
        preview.move(by: -1, isRepeat: true); XCTAssertEqual(preview.record.plan.number, 3)
        preview.move(by: -1); XCTAssertEqual(preview.record.plan.number, 2)
        preview.updateZoom(3); preview.move(by: 1)
        preview.updateZoom(1) // Returning to fit removes the guard.
        XCTAssertNil(preview.seedNavigationNotice)
        preview.move(by: 1); XCTAssertEqual(preview.record.plan.number, 3)
        let previousPath = model.folder!.appendingPathComponent(model.images[1].plan.filename).standardizedFileURL.path
        preview.updateZoom(4, for: previousPath) // Ignore late callbacks from the old image.
        XCTAssertFalse(preview.isZoomed)
        preview.move(by: -1); XCTAssertEqual(preview.record.plan.number, 2)
        print("Checked: zoomed seed boundaries in both directions, explicit second press, autorepeat, reversal, fit reset and stale callbacks")
    }
    static func checkViewerEditingFocus() {
        let window = ImagePreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let editor = NSTextView(frame: NSRect(x: 20, y: 20, width: 100, height: 30))
        editor.isEditable = true; editor.string = "1.875"
        content.addSubview(editor); window.contentView = content
        var moves = 0
        window.navigate = { _, _ in moves += 1 }
        XCTAssertTrue(window.makeFirstResponder(editor))
        let arrow = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{F703}", charactersIgnoringModifiers: "\u{F703}", isARepeat: false, keyCode: 124)!
        window.sendEvent(arrow)
        XCTAssertEqual(moves, 0)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 250, y: 150), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        window.sendEvent(click)
        XCTAssertFalse(window.firstResponder === editor)
        window.sendEvent(arrow)
        XCTAssertEqual(moves, 1)
        editor.isEditable = false; editor.isSelectable = true
        XCTAssertTrue(window.makeFirstResponder(editor))
        window.sendEvent(arrow)
        XCTAssertEqual(moves, 2)
        window.close()
        print("Checked: viewer arrows edit active input, resume after clicking away, and ignore selectable-label focus")
    }
    static func checkImageZoom() {
        let scroll = ImageZoomScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let image = NSImage(size: NSSize(width: 1024, height: 512))
        var reportedZoom: CGFloat = 1
        scroll.zoomChanged = { reportedZoom = $0 }
        scroll.show(image, identity: "/batch-a/image.png", seed: 1234); scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.magnification, 1)
        XCTAssertEqual(scroll.documentView?.frame.size, scroll.contentView.frame.size)
        XCTAssertEqual((scroll.documentView as? NSImageView)?.imageScaling, .scaleProportionallyUpOrDown)
        scroll.setMagnification(3, centeredAt: NSPoint(x: 400, y: 300))
        XCTAssertEqual(scroll.magnification, 3)
        XCTAssertEqual(reportedZoom, 3)
        XCTAssertTrue(scroll.contentView.bounds.width < scroll.documentView!.frame.width)
        scroll.show(image, identity: "/batch-a/image.png", seed: 1234)
        XCTAssertEqual(scroll.magnification, 3)
        scroll.setMagnification(0.1, centeredAt: NSPoint(x: 400, y: 300))
        XCTAssertEqual(scroll.magnification, 1)
        XCTAssertEqual(reportedZoom, 1)
        scroll.setMagnification(4, centeredAt: NSPoint(x: 400, y: 300))
        scroll.contentView.scroll(to: NSPoint(x: 150, y: 120))
        let position = scroll.contentView.bounds.origin
        let variant = NSImage(size: NSSize(width: 1024, height: 512))
        scroll.show(variant, identity: "/batch-b/shift-variant.png", seed: 1234); scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.magnification, 4)
        XCTAssertEqual(scroll.contentView.bounds.origin, position)
        XCTAssertTrue((scroll.documentView as? NSImageView)?.image === variant)
        scroll.show(image, identity: "/batch-b/shift-variant.png", seed: 5678); scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.magnification, 1)
        XCTAssertEqual(scroll.contentView.bounds.origin, .zero)
        scroll.setMagnification(3, centeredAt: NSPoint(x: 400, y: 300))
        scroll.show(image, identity: "/favorites/external-a.png", seed: nil)
        scroll.setMagnification(3, centeredAt: NSPoint(x: 400, y: 300))
        scroll.show(variant, identity: "/favorites/external-b.png", seed: nil)
        XCTAssertEqual(scroll.magnification, 1)
        scroll.setFrameSize(NSSize(width: 600, height: 400)); scroll.layoutSubtreeIfNeeded()
        XCTAssertEqual(scroll.documentView?.frame.size, scroll.contentView.frame.size)
        XCTAssertEqual(scroll.magnification, 1)
        print("Checked: native zoom/pan preservation for same-seed variants, seed-change reset, unknown seeds and minimum fit")
    }
    static func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<400 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw MetaPromptError("App model test timed out.")
    }
}
