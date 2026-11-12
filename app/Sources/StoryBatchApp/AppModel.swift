import SwiftUI
import AppKit
import StoryBatchCore

import UniformTypeIdentifiers
import ImageIO

struct QueuedImage: Identifiable {
    let id = UUID()
    let offset: Int
    let plan: ImagePlan
    let label: String
}
final class QueuedRound {
    let id: String
    let count: Int
    var counted: Bool
    init(id: String, count: Int, counted: Bool) { self.id = id; self.count = count; self.counted = counted }
}
struct QueuedWork {
    let id = UUID()
    let prepared: PreparedBatch?
    let refinement: RefinementRequest?
    var folder: URL?
    let origin: UUID?
    let images: [QueuedImage]
    var removedOffsets: Set<Int> = []
    var round: QueuedRound? = nil
    var shortlistOnCompletion = false
    var visibleImages: [QueuedImage] { images.filter { !removedOffsets.contains($0.offset) } }
}

enum RefinementPromptMode: String, CaseIterable, Identifiable {
    case appendDelta, fullOverride
    var id: String { rawValue }
    var label: String { self == .appendDelta ? "Add changes to source prompt" : "Replace source prompt" }
}

enum ImageSort: String, CaseIterable, Identifiable {
    case seeded, seededStep, newest
    var id: String { rawValue }
    var label: String {
        switch self {
        case .seeded: return "Seeded"
        case .seededStep: return "Seeded-Step"
        case .newest: return "Newest"
        }
    }
    func sorted(_ records: [ImageRecord]) -> [ImageRecord] {
        switch self {
        case .seeded: return ImageRecord.displayOrder(records, stepsFirst: false)
        case .seededStep: return ImageRecord.displayOrder(records, stepsFirst: true)
        case .newest: return records.reversed().filter { $0.status != "skipped" }
        }
    }
}


struct RefinementRoot {
    let imagePath: String
    let sourceBatchFolder: String?
    let sourceFilename: String?
    let sourcePrompt: String
    let title: String
    let seed: Int?
    let shift: ShiftValue?
    let steps: Int
    let width: Int
    let height: Int
}

private struct QueueModeSnapshot {
    let source: String
    let lastReport: BatchReport?
    let folder: URL?
    let images: [ImageRecord]
    let latestRunPlans: [ImagePlan]
    let selectedTab: MainTab
}

@MainActor
final class AppModel: ObservableObject {
    static let example = "steps=3; aspect=1:1; count=4\n"
    @Published var source = AppModel.example { didSet { persistSession() } }
    @Published private(set) var refinementRoot: RefinementRoot?
    @Published var refinementPromptMode: RefinementPromptMode = .appendDelta { didSet { updateRefinementPrompt() } }
    @Published var refinementInstructions = "" { didSet { updateRefinementPrompt() } }
    @Published var refinementFullPrompt = "" { didSet { updateRefinementPrompt() } }
    @Published var refinementStrength = 0.35 { didSet { validate() } }
    @Published var parameters: BatchParameters?
    @Published var validationError: String?
    @Published var prepared: PreparedBatch?
    @Published var isRunning = false
    @Published var stopping = false
    @Published private(set) var stoppingAfterImage = false
    @Published private(set) var skippingImage: Int?
    @Published var status = "Ready"
    @Published var activity: [String] = []
    @Published var images: [ImageRecord] = []
    @Published var selectedTab: MainTab = .preview { didSet { if selectedTab == .favorites { refreshFavorites() } } }
    @Published var imageSort: ImageSort = .seeded
    @Published private(set) var favoriteImages: [FavoriteImage] = []
    @Published private(set) var imageSelections: [SavedImageSelection] = []
    @Published var folder: URL?
    @Published var step = 0
    @Published var totalSteps = 1
    @Published var currentImage = 0
    @Published var currentElapsed = 0.0
    @Published var showSettings = false
    @Published var showHelp = false
    @Published var outputRoot: URL { didSet { if !restoringSession { refreshFavorites() } } }
    @Published var executablePath: String { didSet { persistRendererConfiguration() } }
    let find = PromptFindModel()
    let fieldsFind = PromptFindModel()
    private var fieldsWindow: FieldsEditorWindow?
    var isRefinementMode: Bool { refinementRoot != nil }
    var refinementOriginalPrompt: String { refinementRoot?.sourcePrompt ?? "" }
    var refinementPromptText: String { refinementPromptMode == .appendDelta ? refinementInstructions : refinementFullPrompt }
    var refinementFinalPrompt: String {
        guard let root = refinementRoot else { return PromptDocument(source).prompt }
        if refinementPromptMode == .fullOverride { return refinementFullPrompt }
        let delta = refinementInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return delta.isEmpty ? root.sourcePrompt : root.sourcePrompt + "\n" + delta
    }
    var refinementStrengthText: String {
        get { String(format: "%.3f", refinementStrength).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression).replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression) }
        set { if let value = Double(newValue.trimmingCharacters(in: .whitespaces)) { refinementStrength = value } else { validationError = "Refinement strength must be a number from 0 to 1." } }
    }
    var parameterText: String {
        get { PromptDocument(source).header }
        set { var document = PromptDocument(source); document.header = newValue.replacingOccurrences(of: "\n", with: " "); source = document.source; validate() }
    }
    var promptText: String {
        get { isRefinementMode ? refinementPromptText : PromptDocument(source).prompt }
        set {
            if isRefinementMode {
                if refinementPromptMode == .appendDelta { refinementInstructions = newValue } else { refinementFullPrompt = newValue }
            } else { var document = PromptDocument(source); document.prompt = newValue; source = document.source; validate() }
        }
    }
    var fieldText: String {
        get { PromptDocument(source).fieldsText }
        set { var document = PromptDocument(source); document.fieldsText = newValue; document.hasFieldsSection = true; source = document.source; validate() }
    }
    var fieldCount: Int { (try? PromptDocument(source).fields().count) ?? 0 }
    private var updatingRefinementPrompt = false
    private func updateRefinementPrompt() {
        guard isRefinementMode, !updatingRefinementPrompt else { return }
        updatingRefinementPrompt = true; defer { updatingRefinementPrompt = false }
        if refinementPromptMode == .fullOverride, refinementFullPrompt.isEmpty { refinementFullPrompt = refinementOriginalPrompt }
        var document = PromptDocument(source); document.prompt = refinementFinalPrompt; source = document.source; validate()
    }
    func extractChoices() {
        do { source = try PromptDocument(source).extractingChoices().source; validate(); add("Moved inline choices into named fields") }
        catch { validationError = error.localizedDescription }
    }
    func openFieldsEditor() {
        if let fieldsWindow { fieldsWindow.makeKeyAndOrderFront(nil); return }
        let window = FieldsEditorWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 620), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Prompt Fields"; window.isReleasedWhenClosed = false
        window.find = fieldsFind; window.contentView = NSHostingView(rootView: FieldsEditor(model: self))
        window.center(); fieldsWindow = window; window.makeKeyAndOrderFront(nil)
    }
    var sourceURL: URL?
    private var runner: BatchRunner?
    private var imageStarted: Date?
    private var timer: Timer?
    @Published private var lastReport: BatchReport?
    @Published private(set) var queuedWork: [QueuedWork] = []
    @Published private(set) var currentQueuedImages: [QueuedImage] = []
    @Published private(set) var latestRunPlans: [ImagePlan] = []
    var canCollectValues: Bool { !isRunning && !latestRunPlans.isEmpty }
    var pendingRefinements: [RefinementRequest] { queuedWork.compactMap(\.refinement) }
    var queueImages: [QueuedImage] { currentQueuedImages + queuedWork.flatMap(\.visibleImages) }
    private var activeCompiled: CompiledMetaPrompt?
    private var activePrepared: PreparedBatch?
    private var activeQueueDetached = false
    private var activeToken = UUID()
    private let sessionStore: EditorSessionStore
    private let rendererConfigurationStore: RendererConfigurationStore
    private var rendererConfiguration: RendererConfiguration
    private var rendererConfigurationError: String?
    var rendererConfigurationPath: String { rendererConfigurationStore.url.path }
    var rendererDescription: String {
        let recipe = rendererConfiguration.recipe
        return "\(recipe.model) · sampler \(recipe.sampler) · seed mode \(recipe.seedMode) · guidance \(recipe.guidanceScale) · \(recipe.loras.count) LoRA(s) · local and offline"
    }
    private func persistRendererConfiguration() {
        guard !restoringSession, rendererConfigurationError == nil else { return }
        rendererConfiguration.executablePath = executablePath
        do { try rendererConfigurationStore.save(rendererConfiguration) }
        catch { validationError = "Could not save renderer configuration: " + error.localizedDescription }
    }
    private let imageSelectionStore: ImageSelectionStore
    private var restoringSession = true
    private var activeStart = 1
    private var activeCount = 0
    private var removedActiveFolder = false
    private var queuedRefinementRoot: RefinementRoot?
    private var shortlistOnCompletion = false
    private var queueModeSnapshot: QueueModeSnapshot?
    init(sessionStore suppliedStore: EditorSessionStore? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        sessionStore = suppliedStore ?? EditorSessionStore(url: support.appendingPathComponent("StoryBatch/session.json"))
        imageSelectionStore = ImageSelectionStore(url: sessionStore.url.deletingLastPathComponent().appendingPathComponent("image-selections.json"))
        let workspace = Bundle.main.object(forInfoDictionaryKey: "StoryBatchWorkspace") as? String
        let fallback = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
        outputRoot = URL(fileURLWithPath: workspace ?? fallback.path).appendingPathComponent("Batches", isDirectory: true)
        let configurationURL: URL
        if suppliedStore != nil { configurationURL = sessionStore.url.deletingLastPathComponent().appendingPathComponent("renderer.local.json") }
        else if let path = ProcessInfo.processInfo.environment["STORYBATCH_CONFIG"] { configurationURL = URL(fileURLWithPath: path) }
        else { configurationURL = URL(fileURLWithPath: workspace ?? fallback.path).appendingPathComponent("renderer.local.json") }
        rendererConfigurationStore = RendererConfigurationStore(url: configurationURL)
        rendererConfiguration = RendererConfiguration(executablePath: GenerationDefaults.executable()?.path ?? "draw-things-cli")
        do {
            if let saved = try rendererConfigurationStore.load() { rendererConfiguration = saved }
            else { try rendererConfigurationStore.save(rendererConfiguration) }
        } catch { rendererConfigurationError = "Could not read renderer config at \(configurationURL.path): " + error.localizedDescription }
        executablePath = rendererConfiguration.executablePath
        if let session = try? sessionStore.load() {
            source = session.source
            if let path = session.outputRoot { outputRoot = URL(fileURLWithPath: path, isDirectory: true) }
            if let path = session.lastReportPath,
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let report = try? JSONDecoder().decode(BatchReport.self, from: data) {
                lastReport = report; folder = URL(fileURLWithPath: report.folder); images = report.images; latestRunPlans = report.latestCompletedPlans
            }
        }
        validate()
        do { imageSelections = try imageSelectionStore.load().filter { $0.shortlisted || $0.rejected == true } }
        catch { add("Could not load shortlist/favorites: " + error.localizedDescription) }
        restoringSession = false
        refreshFavorites()
    }
    var shortlistedImages: [SavedImageSelection] {
        guard let folder else { return [] }
        var selected = imageSelections.filter { $0.shortlisted && $0.folderPath == folder.standardizedFileURL.path }
        // Show the in-flight variant without persisting it as a successful selection.
        if isRunning, shortlistOnCompletion {
            let selectedPaths = Set(selected.map(\.id))
            selected += images.filter { $0.status == "running" }.compactMap { record in
                let item = SavedImageSelection(folder: folder, record: record, shortlisted: true)
                return selectedPaths.contains(item.id) ? nil : item
            }
        }
        let positions = Dictionary(uniqueKeysWithValues: orderedImages.enumerated().map { ($0.element.id, $0.offset) })
        return selected.sorted { (positions[$0.record.id] ?? Int.max) < (positions[$1.record.id] ?? Int.max) }
    }
    var favoritesFolder: URL { outputRoot.appendingPathComponent("_favorites", isDirectory: true) }
    func refreshFavorites() {
        do { favoriteImages = try FavoritesFolder(url: favoritesFolder).images() }
        catch { validationError = "Could not read favorites: " + error.localizedDescription }
    }
    func favoriteEntry(_ record: ImageRecord, folder: URL) -> FavoriteImage? {
        let id = SavedImageSelection.identity(folder: folder, filename: record.plan.filename)
        return favoriteImages.first { $0.id == id || $0.source?.id == id }
    }
    func originalSelection(_ record: ImageRecord, folder: URL) -> SavedImageSelection? {
        favoriteEntry(record, folder: folder)?.source
    }
    func isShortlisted(_ record: ImageRecord, folder: URL) -> Bool {
        let original = originalSelection(record, folder: folder)
        let id = original?.id ?? SavedImageSelection.identity(folder: folder, filename: record.plan.filename)
        return imageSelections.first { $0.id == id }?.shortlisted ?? false
    }
    func isFavorite(_ record: ImageRecord, folder: URL) -> Bool {
        favoriteEntry(record, folder: folder) != nil
    }
    func toggleFavorite(_ record: ImageRecord, folder: URL) {
        defer { refreshFavorites() }
        do {
            let store = FavoritesFolder(url: favoritesFolder)
            if let entry = favoriteEntry(record, folder: folder) { try store.remove(entry) }
            else { try store.add(record: record, folder: folder) }
        } catch { validationError = "Could not update favorites: " + error.localizedDescription }
    }
    func toggleShortlist(_ record: ImageRecord, folder: URL) {
        updateSelection(record, folder: folder) { $0.shortlisted.toggle() }
    }
    func isRejected(_ record: ImageRecord, folder: URL) -> Bool {
        let original = originalSelection(record, folder: folder)
        let id = original?.id ?? SavedImageSelection.identity(folder: folder, filename: record.plan.filename)
        return imageSelections.first { $0.id == id }?.rejected == true
    }
    func toggleRejected(_ record: ImageRecord, folder: URL) {
        guard folder.standardizedFileURL != favoritesFolder.standardizedFileURL || originalSelection(record, folder: folder) != nil else { return }
        updateSelection(record, folder: folder) { $0.rejected = !($0.rejected ?? false) }
    }
    private func updateSelection(_ record: ImageRecord, folder: URL, change: (inout SavedImageSelection) -> Void) {
        let original = originalSelection(record, folder: folder)
        let record = original?.record ?? record
        let folder = original.map { URL(fileURLWithPath: $0.folderPath) } ?? folder
        let id = SavedImageSelection.identity(folder: folder, filename: record.plan.filename)
        var updated = imageSelections
        let index: Int
        if let found = updated.firstIndex(where: { $0.id == id }) { index = found }
        else {
            guard record.status == "completed", FileManager.default.fileExists(atPath: id) else { return }
            updated.append(SavedImageSelection(folder: folder, record: record)); index = updated.count - 1
        }
        change(&updated[index])
        updated[index].record = record
        updated.removeAll { !$0.shortlisted && $0.rejected != true }
        do { try imageSelectionStore.save(updated); imageSelections = updated }
        catch { validationError = "Could not save image selections: " + error.localizedDescription }
    }
    var completed: Int { images.filter { $0.status == "completed" }.count }
    var activeImagePlan: ImagePlan? {
        guard isRunning else { return nil }
        return images.last(where: { $0.plan.number == currentImage && $0.status == "running" })?.plan
    }
    var displayImages: [ImageRecord] {
        guard let folder else { return orderedImages }
        return orderedImages.filter { !isRejected($0, folder: folder) }
    }
    var rejectedImages: [ImageRecord] {
        guard let folder else { return [] }
        return orderedImages.filter { isRejected($0, folder: folder) }
    }
    private var orderedImages: [ImageRecord] {
        imageSort.sorted(images)
    }
    var continuation: BatchReport? {
        guard let report = lastReport, report.status != "running", report.parameters.title == parameters?.title,
              URL(fileURLWithPath: report.folder).deletingLastPathComponent().standardizedFileURL == outputRoot.standardizedFileURL,
              FileManager.default.fileExists(atPath: URL(fileURLWithPath: report.folder).appendingPathComponent(report.reportFilename).path) else { return nil }
        return report
    }
    var generateTitle: String {
        if continuation != nil { return "Generate More" }
        return lastReport == nil ? "Generate \(parameters?.count ?? 4) Images" : "New Batch"
    }
    var nextActionTitle: String {
        guard let activeCompiled, activeCompiled.parameters.title == parameters?.title else { return "New Batch" }
        return "Queue Next"
    }
    var canQueueNext: Bool { isRunning && !stopping && !stoppingAfterImage && parameters != nil && nextActionTitle == "Queue Next" }
    var canQueueMore: Bool { isRunning ? canQueueNext : (parameters != nil && continuation != nil) }
    var progress: Double {
        guard activeCount > 0 else { return 0 }
        let finished = images.filter { $0.plan.number >= activeStart && ["completed", "skipped"].contains($0.status) }.count
        let partial = imageStarted != nil ? Double(step) / Double(max(totalSteps, 1)) : 0
        return min(1, (Double(finished) + partial) / Double(activeCount))
    }
    func validate() {
        if let rendererConfigurationError { validationError = rendererConfigurationError; parameters = nil; return }
        prepared = nil
        do {
            guard !isRefinementMode || (refinementStrength.isFinite && refinementStrength >= 0 && refinementStrength <= 1) else { throw MetaPromptError("Refinement strength must be a value from 0 to 1.") }
            parameters = try CompiledMetaPrompt.compile(source, defaultTitle: activeCompiled?.parameters.title ?? lastReport?.parameters.title).parameters; validationError = nil
        }
        catch { parameters = nil; validationError = error.localizedDescription }
    }
    private func quotedHeader(_ value: String) -> String {
        if value.contains(";") || value.contains("\"") { return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
        return value
    }
    private func makeRefinementSource(_ root: RefinementRoot) -> String {
        var header = ["title=\(quotedHeader(root.title + " refinement"))", "steps=\(root.steps)", "resolution=\(root.width)*\(root.height)", "pixel_max=\(root.width * root.height)", "count=1"]
        if let seed = root.seed { header.insert("seed=\(seed)", at: 1) }
        if let shift = root.shift { header.insert("shift=\(shift.text)", at: min(2, header.count)) }
        return header.joined(separator: "; ") + "\n" + root.sourcePrompt
    }
    private func enterRefinement(_ root: RefinementRoot) {
        guard !isRunning else { return }
        if !isRefinementMode { queueModeSnapshot = QueueModeSnapshot(source: source, lastReport: lastReport, folder: folder, images: images, latestRunPlans: latestRunPlans, selectedTab: selectedTab) }
        refinementRoot = root; refinementPromptMode = .appendDelta; refinementInstructions = ""; refinementFullPrompt = ""; refinementStrength = 0.35
        lastReport = nil; folder = nil; images = []; latestRunPlans = []; queuedWork = []; currentQueuedImages = []; prepared = nil; sourceURL = nil
        source = makeRefinementSource(root); updateRefinementPrompt(); validate(); selectedTab = .preview
        status = "Refinement ready · source image pinned"; activity = []; add("Opened refinement from \(URL(fileURLWithPath: root.imagePath).lastPathComponent)")
    }
    func exitRefinement() {
        guard isRefinementMode, !isRunning else { return }
        refinementRoot = nil; refinementInstructions = ""; refinementFullPrompt = ""; refinementPromptMode = .appendDelta
        if let snapshot = queueModeSnapshot {
            source = snapshot.source; lastReport = snapshot.lastReport; folder = snapshot.folder; images = snapshot.images; latestRunPlans = snapshot.latestRunPlans; selectedTab = snapshot.selectedTab
        } else { source = Self.example; lastReport = nil; folder = nil; images = []; latestRunPlans = []; selectedTab = .preview }
        queueModeSnapshot = nil; prepared = nil; validationError = nil; status = "Ready"; activity = []; validate(); persistSession()
    }
    private func prepareCurrent(continuing previous: BatchReport? = nil, defaultTitle: String? = nil) throws -> PreparedBatch {
        var batch = try PreparedBatch.prepare(source, continuing: previous, defaultTitle: defaultTitle).usingRenderer(rendererConfiguration.recipe)
        if let root = refinementRoot {
            guard !refinementFinalPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MetaPromptError("Enter refinement instructions or switch to a full replacement prompt.") }
            let crop = batch.compiled.parameters.width != root.width || batch.compiled.parameters.height != root.height
            let context = RefinementContext(sourceImagePath: root.imagePath, sourceBatchFolder: root.sourceBatchFolder, sourceFilename: root.sourceFilename, sourcePrompt: root.sourcePrompt, promptMode: refinementPromptMode.rawValue, refinementText: refinementPromptText)
            batch = try batch.usingImage(path: root.imagePath, strength: refinementStrength, crop: crop, context: context)
        }
        return batch
    }
    private func persistSession() {
        guard !restoringSession else { return }
        let path = lastReport.map { URL(fileURLWithPath: $0.folder).appendingPathComponent($0.reportFilename).path }
        do { try sessionStore.save(EditorSession(source: source, lastReportPath: path, outputRoot: outputRoot.path)) }
        catch { add("Could not restore this draft next launch: " + error.localizedDescription) }
    }
    func newDocument() { guard !isRunning else { return }; if isRefinementMode { exitRefinement() }; sourceURL = nil; source = Self.example; validate() }
    func openDocument() {
        guard !isRunning else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.plainText, .text]; panel.title = "Open metaprompt"; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { source = try String(contentsOf: url, encoding: .utf8); sourceURL = url; validate() }
        catch { validationError = "Could not open file: " + error.localizedDescription }
    }
    func openBatch() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.title = "Open previous batch"; panel.prompt = "Open Batch"
        panel.message = "Choose a batch folder to restore its latest metaprompt and images."
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.directoryURL = outputRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try loadBatch(from: url) }
        catch { validationError = "Could not open batch: " + error.localizedDescription }
    }
    private func requestRefinement(_ root: RefinementRoot) {
        guard isRunning else { enterRefinement(root); return }
        let alert = NSAlert(); alert.messageText = "A batch is still running"
        alert.informativeText = "Stop it before opening Refinement? Stop Batch interrupts the current image; Finish This Image saves it first. Waiting jobs are cleared either way."
        alert.addButton(withTitle: "Stop Batch & Open")
        alert.addButton(withTitle: "Finish This Image & Open")
        alert.addButton(withTitle: "Stay Here")
        switch alert.runModal() {
        case .alertFirstButtonReturn: queuedRefinementRoot = root; stop()
        case .alertSecondButtonReturn: queuedRefinementRoot = root; stopAfterCurrentImage()
        default: break
        }
    }
    func beginRefinement(record: ImageRecord, folder: URL) {
        guard record.status == "completed" else { return }
        let path = folder.appendingPathComponent(record.plan.filename).path
        let title = record.requestParameters?.title ?? lastReport?.parameters.title ?? "refinement"
        requestRefinement(RefinementRoot(imagePath: path, sourceBatchFolder: folder.path, sourceFilename: record.plan.filename, sourcePrompt: record.plan.prompt, title: title, seed: record.plan.seed, shift: record.plan.shift, steps: record.plan.steps, width: record.plan.width, height: record.plan.height))
    }
    private func imageSize(_ url: URL) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
    func openImageForRefinement() {
        let panel = NSOpenPanel(); panel.title = "Open image for refinement"; panel.prompt = "Open Refinement"
        panel.message = "The selected image will be copied into a new refinement batch when generation begins."
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let size = imageSize(url) else { return }
        let width = max(64, (size.0 / 64) * 64), height = max(64, (size.1 / 64) * 64)
        let title = url.deletingPathExtension().lastPathComponent.isEmpty ? "refinement" : url.deletingPathExtension().lastPathComponent
        requestRefinement(RefinementRoot(imagePath: url.path, sourceBatchFolder: nil, sourceFilename: nil, sourcePrompt: "", title: title, seed: nil, shift: nil, steps: 6, width: width, height: height))
    }
    func loadBatch(from url: URL) throws {
        guard !isRunning else { throw MetaPromptError("Finish or stop the current round before opening another batch.") }
        let report = try BatchReport.load(in: url)
        // Validate before replacing the current draft or gallery.
        var reviewSource = report.sourceMetaprompt
        let legacyPixels = report.parameters.width.multipliedReportingOverflow(by: report.parameters.height)
        if report.parameters.pixelMax == nil, !legacyPixels.overflow, legacyPixels.partialValue > BatchParameters.defaultPixelMax {
            var document = PromptDocument(reviewSource)
            if document.header.range(of: #"(?:^|;)\s*pixel_max\s*="#, options: [.regularExpression, .caseInsensitive]) == nil {
                // Validate the old document for viewing without silently raising
                // its generation cap. The original draft still shows the error.
                document.header += "; pixel_max=\(legacyPixels.partialValue)"
                reviewSource = document.source
            }
        }
        _ = try CompiledMetaPrompt.compile(reviewSource, defaultTitle: report.parameters.title)
        lastReport = report; folder = url
        outputRoot = url.deletingLastPathComponent()
        images = report.images; latestRunPlans = report.latestCompletedPlans; queuedWork = []; currentQueuedImages = []; prepared = nil
        activeStart = 1; activeCount = 0; currentImage = 0; step = 0; currentElapsed = 0
        sourceURL = url.appendingPathComponent("metaprompt.txt")
        source = report.sourceMetaprompt; validate()
        selectedTab = .images; activity = []
        status = "Opened batch · \(completed) completed image\(completed == 1 ? "" : "s")"
        add("Opened \(url.lastPathComponent) · latest metaprompt restored")
        if report.status == "running" { add("The saved report records an unfinished round. Completed images are available for review; no generation has been resumed.") }
        persistSession()
    }
    func saveDocument() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = sourceURL?.lastPathComponent ?? "metaprompt.txt"; panel.title = "Save metaprompt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try source.write(to: url, atomically: true, encoding: .utf8); sourceURL = url; add("Saved \(url.lastPathComponent)") }
        catch { validationError = "Could not save file: " + error.localizedDescription }
    }
    func collectSeeds() { collectValues(key: "seeds", values: latestRunPlans.map { String($0.seed) }) }
    func collectShifts() { collectValues(key: "shift", values: latestRunPlans.map { $0.shift.text }) }
    private func collectValues(key: String, values: [String]) {
        guard canCollectValues else { return }
        do {
            source = try BatchParameters.replacingParameter(in: source, key: key, value: values.joined(separator: ","))
            validate()
            add("Collected \(values.count) \(key == "seeds" ? "seeds" : "shifts") from the latest run, in generation order")
        } catch { validationError = error.localizedDescription }
    }
    func chooseOutput() {
        let panel = NSOpenPanel(); panel.title = "Choose batch output folder"; panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.directoryURL = outputRoot
        if panel.runModal() == .OK, let url = panel.url { outputRoot = url; prepared = nil; persistSession() }
    }
    func chooseExecutable() {
        let panel = NSOpenPanel(); panel.title = "Choose draw-things-cli"; panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.directoryURL = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
        if panel.runModal() == .OK, let url = panel.url { executablePath = url.path }
    }
    func preview() {
        do { prepared = try prepareCurrent(continuing: continuation, defaultTitle: parameters?.title); parameters = prepared?.compiled.parameters; validationError = nil; selectedTab = .preview }
        catch { validationError = error.localizedDescription }
    }
    func start(forceNewBatch: Bool = false) {
        guard !isRunning else { return }
        do {
            let previous = forceNewBatch ? nil : continuation
            let nextNumber = (previous?.images.map(\.plan.number).max() ?? 0) + 1
            let candidate = isRefinementMode ? nil : self.prepared.flatMap { $0.compiled.source == source && $0.startingNumber == nextNumber ? $0 : nil }
            let prepared = try candidate ?? prepareCurrent(continuing: previous, defaultTitle: parameters?.title)
            try launch(prepared: prepared, previous: previous)
        } catch { validationError = error.localizedDescription }
    }
    private func launch(prepared initial: PreparedBatch, previous: BatchReport?, refinement: Bool = false, queued: Bool = false, skipping: Set<Int> = [], shortlistOnCompletion: Bool = false) throws {
            guard !isRunning else { throw MetaPromptError("An image is already being generated.") }
            if let rendererConfigurationError { throw MetaPromptError(rendererConfigurationError) }
            var configured = try initial.freezingPlans()
            if configured.logicalRunID == nil { configured.logicalRunID = UUID().uuidString }
            let prepared = configured
            let plans = prepared.frozenPlans!
            let executable = URL(fileURLWithPath: executablePath)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw MetaPromptError("Draw Things CLI was not found. Choose its executable in Settings.") }
            if !refinement && !queued { parameters = prepared.compiled.parameters; validationError = nil; activity = [] }
            let runner = BatchRunner(queuedImageNumbers: plans.map(\.number))
            for offset in skipping { runner.cancelQueuedImage(number: prepared.startingNumber + offset) }
            self.runner = runner; isRunning = true; stopping = false; stoppingAfterImage = false
            self.shortlistOnCompletion = shortlistOnCompletion
            latestRunPlans = []
            activeCompiled = prepared.compiled; activeToken = UUID()
            activePrepared = prepared; activeQueueDetached = false
            currentQueuedImages = plans.enumerated().filter { !skipping.contains($0.offset) }.map {
                QueuedImage(offset: $0.offset, plan: $0.element, label: "Current round · Image \($0.element.number)")
            }
            status = "Preparing batch…"; images = previous?.images ?? []; folder = previous.map { URL(fileURLWithPath: $0.folder) }; currentImage = 0; step = 0; totalSteps = prepared.compiled.parameters.steps
            if !queued { selectedTab = .images }
            activeStart = prepared.startingNumber; activeCount = prepared.compiled.parameters.count; removedActiveFolder = false
            // Snapshot the running recipe; editor changes only affect the next round.
            self.prepared = nil
            let output = outputRoot
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in if let start = self?.imageStarted { self?.currentElapsed = Date().timeIntervalSince(start) } }
            }
            add(refinement ? "Variant requested · \(prepared.compiled.parameters.steps) steps · shift \(prepared.preview[0].shift.text) · saved source prompt" : "Batch requested · \(prepared.compiled.parameters.count) images · local / offline")
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                do {
                    try runner.run(prepared: prepared, outputRoot: output, executable: executable, continuing: previous) { event in
                        DispatchQueue.main.async { self?.receive(event) }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.add("Error: " + error.localizedDescription); self?.validationError = error.localizedDescription
                        self?.status = "Batch failed"; self?.queuedWork = []; self?.finish()
                    }
                }
            }
    }
    func queueNext() {
        guard canQueueNext else { return }
        do {
            let batch = try prepareCurrent(defaultTitle: activeCompiled?.parameters.title).freezingPlans()
            let rows = batch.frozenPlans!.enumerated().map {
                QueuedImage(offset: $0.offset, plan: $0.element, label: "Next round · \(batch.compiled.parameters.title) · \($0.offset + 1)")
            }
            queuedWork.append(QueuedWork(prepared: batch, refinement: nil, folder: folder, origin: activeToken, images: rows))
            add("Queued next round · \(rows.count) images · recipes frozen")
            prepared = nil
        } catch { validationError = error.localizedDescription }
    }
    func cancelQueuedImage(id: UUID) {
        if let row = currentQueuedImages.first(where: { $0.id == id }) {
            guard runner?.cancelQueuedImage(number: row.plan.number) == true else { add("Image \(row.plan.number) is already starting; use Stop Batch to interrupt it."); return }
            currentQueuedImages.removeAll { $0.id == id }; add("Removed queued image \(row.plan.number)")
            return
        }
        guard let index = queuedWork.firstIndex(where: { $0.visibleImages.contains(where: { $0.id == id }) }),
              let row = queuedWork[index].visibleImages.first(where: { $0.id == id }) else { return }
        if let round = queuedWork[index].round {
            queuedWork[index].removedOffsets.insert(row.offset)
            // Keep a hidden skipped slot for partial rounds, but drop a wholly canceled future round.
            if !round.counted && !queuedWork.contains(where: { $0.round === round && !$0.visibleImages.isEmpty }) {
                queuedWork.removeAll { $0.round === round }
            }
            add("Removed queued job · seed \(row.plan.seed)"); return
        }
        queuedWork[index].removedOffsets.insert(row.offset)
        if queuedWork[index].visibleImages.isEmpty { queuedWork.remove(at: index) }
        add("Removed queued job · seed \(row.plan.seed) · shift \(row.plan.shift.text)")
    }
    var canReorderQueue: Bool { isRunning && !stopping && !stoppingAfterImage && activeImagePlan != nil }
    func moveQueuedImage(id: UUID, direction: QueueMove) {
        guard canReorderQueue, let position = queueImages.firstIndex(where: { $0.id == id }) else { return }
        guard direction == .down ? position + 1 < queueImages.count : position > 0 else { return }
        do {
            guard try detachQueueForOrdering() else { return }
            guard let index = queuedWork.firstIndex(where: { $0.visibleImages.first?.id == id }) else {
                add("That image is already starting; its position was left unchanged."); return
            }
            let visible = queuedWork.indices.filter { !queuedWork[$0].visibleImages.isEmpty }
            guard let position = visible.firstIndex(of: index) else { return }
            let target = direction == .next ? visible[0] : visible[direction == .up ? max(0, position - 1) : min(visible.count - 1, position + 1)]
            let work = queuedWork.remove(at: index); queuedWork.insert(work, at: target)
            add("Reordered queued image · seed \(work.visibleImages[0].plan.seed) · position \(target + 1)")
        } catch { validationError = "Could not reorder queue: " + error.localizedDescription }
    }
    private func detachQueueForOrdering() throws -> Bool {
        let future = try queuedWork.flatMap { try $0.fragmented() }
        if activeQueueDetached { queuedWork = future; return true }
        guard let prepared = activePrepared, let runID = prepared.logicalRunID else { return false }
        let round = QueuedRound(id: runID, count: prepared.requestParameters?.count ?? prepared.compiled.parameters.count, counted: true)
        let waiting = try currentQueuedImages.map { row -> QueuedWork in
            var work = QueuedWork(prepared: try prepared.fragment(at: row.offset, runID: runID), refinement: nil,
                                  folder: folder, origin: activeToken, images: [row])
            work.round = round; work.shortlistOnCompletion = shortlistOnCompletion
            return work
        }
        guard let numbers = runner?.detachPendingImages() else { return false }
        let unclaimed = Set(numbers)
        queuedWork = waiting.filter { unclaimed.contains($0.images[0].plan.number) } + future
        currentQueuedImages = []; activeQueueDetached = true
        return true
    }
    private func enqueueVariant(_ request: RefinementRequest) {
        let row = QueuedImage(offset: 0, plan: request.previewPlan, label: "Variant · source image \(request.image.number)")
        queuedWork.append(QueuedWork(prepared: nil, refinement: request, folder: request.folder, origin: nil, images: [row]))
        if !isRunning { startNextWork() }
    }
    func queueRefinement(record: ImageRecord, folder: URL, steps: Int) {
        guard !stopping, !stoppingAfterImage, record.status == "completed", record.plan.refinementSteps.contains(steps) else { return }
        if folder.standardizedFileURL == favoritesFolder.standardizedFileURL {
            guard let original = originalSelection(record, folder: folder) else { return }
            queueRefinement(record: original.record, folder: URL(fileURLWithPath: original.folderPath), steps: steps); return
        }
        add("Queued Step \(steps) · \(record.plan.filename) · after current round")
        var request = RefinementRequest(image: record.plan, steps: steps, folder: folder)
        request.shortlistOnCompletion = selectedTab == .shortlist
        enqueueVariant(request)
    }
    @discardableResult
    func queueShiftBump(record: ImageRecord, folder: URL, bump: ShiftBump) -> Bool {
        do { return queueShift(record: record, folder: folder, shift: try record.plan.shift.bumped(by: bump)) }
        catch { validationError = error.localizedDescription; return false }
    }
    @discardableResult
    func queueShift(record: ImageRecord, folder: URL, shift: ShiftValue) -> Bool {
        guard !stopping, !stoppingAfterImage, record.status == "completed" else { return false }
        if folder.standardizedFileURL == favoritesFolder.standardizedFileURL {
            guard let original = originalSelection(record, folder: folder) else { return false }
            return queueShift(record: original.record, folder: URL(fileURLWithPath: original.folderPath), shift: shift)
        }
        add("Queued shift \(record.plan.shift.text) → \(shift.text) · \(record.plan.steps) steps · \(record.plan.filename)")
        var request = RefinementRequest(image: record.plan, shift: shift, folder: folder)
        request.shortlistOnCompletion = selectedTab == .shortlist
        enqueueVariant(request)
        return true
    }
    private func startNextWork() {
        guard !isRunning, !queuedWork.isEmpty else { return }
        let work = queuedWork.removeFirst()
        do {
            guard let destination = work.folder else { throw MetaPromptError("The queued batch's destination is unavailable.") }
            let report = try BatchReport.load(in: destination)
            guard report.status != "running" else { throw MetaPromptError("The source image's batch is still running.") }
            if let request = work.refinement {
                let prepared = try PreparedBatch.refinement(of: request.image, steps: request.shift == nil ? request.steps : nil, shift: request.shift, continuing: report)
                try launch(prepared: prepared, previous: report, refinement: true, queued: true, shortlistOnCompletion: request.shortlistOnCompletion)
            } else if var batch = work.prepared {
                if let round = work.round { batch.requestedCountOverride = round.counted ? 0 : round.count }
                let skipping = work.round == nil ? work.removedOffsets : work.visibleImages.isEmpty ? Set([0]) : []
                try launch(prepared: batch.rebased(continuing: report), previous: report, queued: true, skipping: skipping, shortlistOnCompletion: work.shortlistOnCompletion)
                work.round?.counted = true
            }
        } catch {
            queuedWork = []; validationError = error.localizedDescription
            status = "Queued job could not start"; add(error.localizedDescription)
        }
    }
    func stop() {
        guard isRunning else { return }; stopping = true; queuedWork = []; currentQueuedImages = []; status = "Stopping current image…"; add("Stop requested; all queued jobs cleared and completed files kept."); runner?.cancel()
    }
    func stopAfterCurrentImage() {
        guard isRunning, !stopping, !stoppingAfterImage else { return }
        runner?.stopAfterCurrentImage()
        stoppingAfterImage = true; queuedWork = []; currentQueuedImages = []
        status = "Finishing current image…"
        add("Stop after this image requested; all waiting jobs cleared. Current image will finish and be saved.")
    }
    func skipCurrentImage() {
        guard isRunning, !stopping, let plan = activeImagePlan, skippingImage != plan.number else { return }
        guard runner?.skipCurrentImage(number: plan.number) == true else {
            add("Image \(plan.number) is already finishing; the next image was left untouched."); return
        }
        skippingImage = plan.number; status = "Skipping image \(plan.number)…"
        add("Skip requested · \(plan.filename) · remaining jobs kept")
    }
    private func receive(_ event: BatchEvent) {
        switch event {
        case .batchStarted(let url):
            folder = url
            for index in queuedWork.indices where queuedWork[index].origin == activeToken { queuedWork[index].folder = url }
            add("Report created · \(url.lastPathComponent)")
        case .batchRemoved:
            removedActiveFolder = true; folder = nil; images = []
            add("Canceled before any image completed; batch folder removed.")
        case .imageStarted(let record):
            skippingImage = nil
            currentQueuedImages.removeAll { $0.plan.number == record.plan.number }
            images.append(record); currentImage = record.plan.number; step = 0; totalSteps = record.plan.steps
            imageStarted = Date(); currentElapsed = 0; status = stoppingAfterImage ? "Finishing current image…" : "Generating image \(currentImage) · \(currentImage - activeStart + 1) of \(activeCount) this round"
            add("Started \(record.plan.filename)")
        case .progress(let image, let step, let total):
            if currentImage == image { self.step = step; totalSteps = total }
        case .imageFinished(let record):
            if skippingImage == record.plan.number { skippingImage = nil }
            if shortlistOnCompletion, record.status == "completed", let folder, !isShortlisted(record, folder: folder) {
                toggleShortlist(record, folder: folder)
            }
            if let i = images.firstIndex(where: { $0.id == record.id }) { images[i] = record }
            if record.status == "completed" { latestRunPlans.append(record.plan); add(BatchFormatting.finishedLine(record)) }
            else { add("\(record.status.capitalized) · \(record.plan.filename)" + (record.error.map { "\n" + $0 } ?? "")) }
            imageStarted = nil
        case .message(let line): add(line)
        case .imageSkipped(let record):
            currentQueuedImages.removeAll { $0.plan.number == record.plan.number }
            images.append(record); add("Skipped image \(record.plan.number) · removed from queue")
        case .batchFinished(let report):
            latestRunPlans = report.latestCompletedPlans
            if removedActiveFolder {
                if lastReport?.id == report.id { lastReport = nil }
            } else { lastReport = report; images = report.images }
            persistSession()
            status = report.status == "completed" ? "Completed \(completed) image\(completed == 1 ? "" : "s")" : report.status.capitalized
            if report.status == "failed" { validationError = report.error }
            if !removedActiveFolder { add("Batch \(report.status) · \(completed) completed · report saved") }
            if report.status != "completed" { queuedWork = [] }
            finish()
            if let root = queuedRefinementRoot {
                queuedRefinementRoot = nil; enterRefinement(root); return
            }
            startNextWork()
        }
    }
    private func finish() { isRunning = false; stopping = false; stoppingAfterImage = false; skippingImage = nil; runner = nil; timer?.invalidate(); timer = nil; imageStarted = nil; prepared = nil; currentQueuedImages = []; activeCompiled = nil; activePrepared = nil; activeQueueDetached = false }
    private func add(_ line: String) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        activity.append("\(formatter.string(from: Date()))  \(line)")
        if activity.count > 1000 { activity.removeFirst(activity.count - 1000) }
    }
    func revealBatch() { if let folder { NSWorkspace.shared.open(folder) } }
}
