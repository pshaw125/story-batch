import SwiftUI
import AppKit
import StoryBatchCore

@MainActor
final class ImagePreviewState: ObservableObject {
    private struct SeedBoundary: Equatable {
        let from: String
        let to: String
        let direction: Int
    }
    @Published private(set) var record: ImageRecord
    @Published private(set) var folder: URL?
    @Published private(set) var hasRecipe = true
    @Published var isFullScreen = false
    @Published private(set) var isZoomed = false
    @Published private var pendingSeedBoundary: SeedBoundary?
    var seedNavigationNotice: String? {
        guard isZoomed, let boundary = pendingSeedBoundary else { return nil }
        return boundary.direction == 1 ? "Next seed; press again to proceed" : "Previous seed; press again to proceed"
    }
    func updateZoom(_ magnification: CGFloat, for imageIdentity: String? = nil) {
        if let imageIdentity, imageIdentity != identity { return }
        let zoomed = magnification > 1.000001
        if isZoomed != zoomed { isZoomed = zoomed }
        if !zoomed, pendingSeedBoundary != nil { pendingSeedBoundary = nil }
    }
    let model: AppModel
    private let snapshot: [PreviewImageItem]
    private var navigationOrder: [String] = []
    private var navigationTab: MainTab?
    var selectionChanged: ((ImageRecord) -> Void)?
    var toggleFullScreen: (() -> Void)?
    init(record: ImageRecord, folder: URL?, model: AppModel) {
        self.record = record; self.folder = folder; self.model = model
        if let folder, folder.standardizedFileURL != model.folder?.standardizedFileURL {
            let batchImages = (try? BatchReport.load(in: folder).images) ?? [record]
            snapshot = batchImages.map { PreviewImageItem(record: $0, folder: folder, hasRecipe: true) }
        } else { snapshot = model.images.compactMap { r in folder.map { PreviewImageItem(record: r, folder: $0, hasRecipe: true) } } }
        if let item = items.first(where: { $0.id == identity }) { hasRecipe = item.hasRecipe }
        rememberOrder()
    }
    private var identity: String { folder.map { SavedImageSelection.identity(folder: $0, filename: record.plan.filename) } ?? "" }
    var items: [PreviewImageItem] {
        let source: [PreviewImageItem]
        if model.selectedTab == .favorites { source = model.favoriteImages.map { PreviewImageItem(favorite: $0) } }
        else if model.selectedTab == .shortlist { source = model.shortlistedImages.map { PreviewImageItem(record: $0.record, folder: URL(fileURLWithPath: $0.folderPath), hasRecipe: true) } }
        else if model.selectedTab == .rejected { source = model.rejectedImages.compactMap { record in model.folder.map { PreviewImageItem(record: record, folder: $0, hasRecipe: true) } } }
        else if model.folder?.standardizedFileURL == folder?.standardizedFileURL {
            source = model.displayImages.compactMap { r in model.folder.map { PreviewImageItem(record: r, folder: $0, hasRecipe: true) } }
        } else {
            let byFilename = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.record.plan.filename, $0) })
            source = model.imageSort.sorted(snapshot.map(\.record)).compactMap { byFilename[$0.plan.filename] }
        }
        return source.filter { $0.record.status == "completed" && FileManager.default.fileExists(atPath: $0.id) }
    }
    var records: [ImageRecord] { items.map(\.record) }
    var index: Int? { items.firstIndex { $0.id == identity } }
    var canPrevious: Bool { (index ?? 0) > 0 }
    var canNext: Bool { index.map { $0 + 1 < items.count } ?? false }
    func sortChanged() {
        pendingSeedBoundary = nil
        rememberOrder()
    }
    func restoreScope() {
        pendingSeedBoundary = nil
        // Selecting Images restores the current batch even after browsing favorites.
        if model.selectedTab == .images, let folder = model.folder {
            if self.folder != folder {
                if let first = model.displayImages.first(where: { $0.status == "completed" }) {
                    select(PreviewImageItem(record: first, folder: folder, hasRecipe: true))
                }
            }
        }
        let available = items
        if index == nil {
            var replacement = available.first
            if model.selectedTab == navigationTab,
               let removedIndex = navigationOrder.firstIndex(of: identity) {
                let remaining = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
                replacement = navigationOrder.dropFirst(removedIndex + 1).compactMap { remaining[$0] }.first
                    ?? navigationOrder.prefix(removedIndex).reversed().compactMap { remaining[$0] }.first
                    ?? replacement
            }
            if let replacement { select(replacement) }
        }
        rememberOrder()
    }
    private func rememberOrder() {
        navigationOrder = items.map(\.id); navigationTab = model.selectedTab
    }
    private func select(_ item: PreviewImageItem) {
        if !hasRecipe || !item.hasRecipe || record.plan.seed != item.record.plan.seed { isZoomed = false }
        pendingSeedBoundary = nil
        record = item.record; folder = item.folder; hasRecipe = item.hasRecipe; selectionChanged?(record)
        rememberOrder()
    }
    func move(by offset: Int, isRepeat: Bool = false) {
        let available = items
        guard let current = available.firstIndex(where: { $0.id == identity }), offset == -1 || offset == 1 else { return }
        let next = current + offset
        guard available.indices.contains(next) else { pendingSeedBoundary = nil; return }
        let target = available[next]
        if isZoomed, hasRecipe, target.hasRecipe, target.record.plan.seed != record.plan.seed {
            let boundary = SeedBoundary(from: identity, to: target.id, direction: offset)
            guard pendingSeedBoundary == boundary else { pendingSeedBoundary = boundary; return }
            guard !isRepeat else { return }
        }
        select(target)
    }
}

@MainActor
final class ImagePreviewWindow: NSWindow {
    var navigate: ((Int, Bool) -> Void)?
    var toggleImageOnly: (() -> Void)?
    var fullScreenTransition = false
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let contentView,
           let editor = firstResponder as? NSTextView, editor.isEditable {
            let point = contentView.convert(event.locationInWindow, from: nil)
            var target = contentView.hitTest(point)
            var clickedEditor = false
            while let view = target {
                if let text = view as? NSTextView, text.isEditable { clickedEditor = true; break }
                if let field = view as? NSTextField, field.isEditable { clickedEditor = true; break }
                target = view.superview
            }
            if !clickedEditor { makeFirstResponder(nil) }
        }
        let editingText = (firstResponder as? NSTextView)?.isEditable == true
        if attachedSheet == nil, !editingText, event.type == .keyDown,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            if event.keyCode == 123 || event.keyCode == 124 {
                navigate?(event.keyCode == 123 ? -1 : 1, event.isARepeat)
                return
            }
            if event.charactersIgnoringModifiers?.lowercased() == "f" {
                if !event.isARepeat { toggleImageOnly?() }
                return
            }
            if event.keyCode == 53 && (styleMask.contains(.fullScreen) || fullScreenTransition) {
                toggleImageOnly?()
                return
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class ImagePreviewController: NSObject, NSWindowDelegate {
    static let shared = ImagePreviewController()
    private var window: ImagePreviewWindow?
    private var state: ImagePreviewState?

    func show(record: ImageRecord, folder: URL?, model: AppModel) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 760)
        let preview = window ?? ImagePreviewWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        preview.isReleasedWhenClosed = false
        preview.tabbingMode = .disallowed
        preview.collectionBehavior = [.fullScreenPrimary]
        preview.delegate = self
        preview.title = record.plan.filename
        preview.minSize = NSSize(width: 540, height: 360)
        let state = ImagePreviewState(record: record, folder: folder, model: model)
        self.state = state
        state.isFullScreen = preview.styleMask.contains(.fullScreen)
        let toggle = { [weak preview] in
            guard let preview, !preview.fullScreenTransition else { return }
            preview.toggleFullScreen(nil)
        }
        state.toggleFullScreen = toggle
        preview.toggleImageOnly = toggle
        state.selectionChanged = { [weak preview] in preview?.title = $0.plan.filename }
        preview.navigate = { [weak state] direction, repeated in state?.move(by: direction, isRepeat: repeated) }
        preview.contentView = NSHostingView(rootView: ImageDetail(preview: state, model: model) { [weak preview] in preview?.close() })
        window = preview
        // Use the screen's work area, preserving the menu bar and Dock.
        if !state.isFullScreen { preview.setFrame(frame, display: true) }
        preview.makeKeyAndOrderFront(nil)
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        window?.fullScreenTransition = true; window?.titleVisibility = .hidden; state?.isFullScreen = true
    }
    func windowDidEnterFullScreen(_ notification: Notification) { window?.fullScreenTransition = false }
    func windowWillExitFullScreen(_ notification: Notification) {
        window?.fullScreenTransition = true; window?.titleVisibility = .visible; state?.isFullScreen = false
    }
    func windowDidExitFullScreen(_ notification: Notification) { window?.fullScreenTransition = false }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        self.window?.fullScreenTransition = false; self.window?.titleVisibility = .visible; state?.isFullScreen = false
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        self.window?.fullScreenTransition = false; self.window?.titleVisibility = .hidden; state?.isFullScreen = true
    }
}

struct ImageRecipeDetails: View {
    let plan: ImagePlan
    var body: some View {
        Text("Seed \(String(plan.seed)) · Shift \(plan.shift.text) · Steps \(String(plan.steps))")
            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
}

struct ImageDetail: View {
    @ObservedObject var preview: ImagePreviewState
    private var record: ImageRecord { preview.record }
    private var folder: URL? { preview.folder }
    @ObservedObject var model: AppModel
    @State private var queueMessage: String?
    @State private var shiftInput = ""
    @State private var shiftInputError: String?
    @FocusState private var shiftFocused: Bool
    @State private var recipe: ImageRecipeSnapshot?
    let close: () -> Void
    var body: some View {
        Group {
            if preview.isFullScreen {
                ZStack {
                    Color.black
                    if let folder, let image = NSImage(contentsOf: folder.appendingPathComponent(record.plan.filename)) {
                        fittedImage(image)
                    }
                    if let notice = preview.seedNavigationNotice {
                        VStack { Text(notice).font(.callout).foregroundStyle(.orange).padding(8).background(.black.opacity(0.75)).clipShape(RoundedRectangle(cornerRadius: 6)); Spacer() }
                            .padding(.top, 18).allowsHitTesting(false)
                    }
                }.ignoresSafeArea()
            } else { normalViewer }
        }.onChange(of: record.plan.filename) { _ in queueMessage = nil; shiftInput = ""; shiftInputError = nil }
            .onChange(of: model.selectedTab) { _ in preview.restoreScope() }
            .onChange(of: model.imageSort) { _ in preview.sortChanged() }
            .onChange(of: model.favoriteImages.map(\.id)) { _ in if model.selectedTab == .favorites { preview.restoreScope() } }
            .onChange(of: model.imageSelections.map { $0.id + String($0.shortlisted) + String($0.rejected ?? false) }) { _ in
                if model.selectedTab != .favorites {
                    preview.restoreScope()
                    if preview.items.isEmpty { close() }
                }
            }
            .sheet(item: $recipe) { snapshot in ResolvedRecipeView(snapshot: snapshot) }
    }
    private func fittedImage(_ image: NSImage) -> some View {
        let identity = folder.map { SavedImageSelection.identity(folder: $0, filename: record.plan.filename) } ?? record.plan.filename
        return ZoomableImageView(image: image, identity: identity, seed: preview.hasRecipe ? record.plan.seed : nil, zoomChanged: { preview.updateZoom($0, for: identity) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func submitShift(folder: URL) {
        guard !model.stopping, !model.stoppingAfterImage else { return }
        do {
            let shift = try ShiftValue.viewerInput(shiftInput)
            if model.queueShift(record: record, folder: folder, shift: shift) {
                queueMessage = "Shift \(shift.text) requested"; shiftInputError = nil
                shiftFocused = false
            }
        } catch { shiftInputError = error.localizedDescription }
    }
    private var normalViewer: some View {
        VStack(spacing: 12) {
            HStack {
                Text(record.plan.filename).font(.headline).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Spacer()
                if model.selectedTab != .favorites {
                    Picker("Image order", selection: $model.imageSort) {
                        ForEach(ImageSort.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).frame(width: 145)
                        .help("Change navigation order while keeping this image and zoom in view")
                }
                Button { preview.move(by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!preview.canPrevious).help("Previous image (←)")
                Text("\((preview.index ?? 0) + 1) of \(preview.records.count)").font(.caption).foregroundStyle(.secondary)
                Button { preview.move(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!preview.canNext).help("Next image (→)")
                if let notice = preview.seedNavigationNotice {
                    Text(notice).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Button { preview.toggleFullScreen?() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Image-only Full Screen (F)")
                    .accessibilityLabel("Full Screen")
                Button("Done", action: close).keyboardShortcut(.cancelAction)
            }
            if let folder, let image = NSImage(contentsOf: folder.appendingPathComponent(record.plan.filename)) {
                fittedImage(image)
                HStack {
                    if preview.hasRecipe {
                        ImageRecipeDetails(plan: record.plan)
                        Text("\(record.plan.width) × \(record.plan.height)").foregroundStyle(.secondary)
                    } else { Text("No saved generation recipe").foregroundStyle(.secondary) }
                    Spacer()
                    if let queueMessage { Text(queueMessage).foregroundStyle(.secondary) }
                }.font(.caption)
                if preview.hasRecipe {
                HStack(spacing: 8) {
                    Text("Shift").font(.caption.weight(.medium))
                    ForEach(ShiftBump.allCases) { bump in
                        let target = try? record.plan.shift.bumped(by: bump)
                        Button(bump.rawValue) {
                            if model.queueShiftBump(record: record, folder: folder, bump: bump) {
                                queueMessage = "Shift \(target?.text ?? "") requested"
                            }
                        }.disabled(model.stopping || model.stoppingAfterImage || target == nil)
                            .help(target.map { "Generate one image at shift \($0.text), keeping \(record.plan.steps) steps and all other settings" } ?? "This adjustment would produce an unsupported shift")
                    }
                    TextField("Absolute shift", text: $shiftInput)
                        .focused($shiftFocused)
                        .textFieldStyle(.roundedBorder).frame(width: 100)
                        .accessibilityLabel("Absolute shift")
                        .onSubmit { submitShift(folder: folder) }
                        .onChange(of: shiftInput) { _ in shiftInputError = nil }
                    Button("Queue Shift") { submitShift(folder: folder) }
                        .disabled(model.stopping || model.stoppingAfterImage || shiftInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Queue this shift, keeping the viewed image’s other settings; up to 3 decimal places, above 0")
                    Spacer()
                }.font(.caption)
                if let shiftInputError { Text(shiftInputError).font(.caption).foregroundStyle(.orange) }
                }
                HStack {
                    ForEach(preview.hasRecipe ? record.plan.refinementSteps : [], id: \.self) { steps in
                        Button("Step \(steps)") {
                            model.queueRefinement(record: record, folder: folder, steps: steps)
                            queueMessage = "Step \(steps) requested"
                        }.disabled(model.stopping || model.stoppingAfterImage)
                            .help("Generate one image with the same expanded prompt, seed, shift and resolution at \(steps) steps")
                    }
                    Spacer()
                    Button("Prompt & Parameters…") { recipe = ImageRecipeSnapshot(record: record, folder: folder) }.disabled(!preview.hasRecipe)
                    ImageSelectionButtons(model: model, record: record, folder: folder, allowShortlist: preview.hasRecipe)
                    Button("Branch as Refinement…") { model.beginRefinement(record: record, folder: folder); close() }.disabled(!preview.hasRecipe)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder.appendingPathComponent(record.plan.filename)])
                        close()
                    }
                }.font(.caption)
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ResolvedRecipeView: View {
    let snapshot: ImageRecipeSnapshot
    @Environment(\.dismiss) private var dismiss
    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    private func readable(_ text: String) -> some View {
        ScrollView {
            Text(text).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        }.background(Color(nsColor: .textBackgroundColor))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Resolved Prompt & Parameters").font(.title2.weight(.semibold))
            Text(snapshot.filename).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("The saved recipe for this image. Choices are already resolved; edits in the main window do not change it.").font(.callout)
            TabView {
                readable(snapshot.prompt).tabItem { Text("Resolved Prompt") }
                VStack(alignment: .leading, spacing: 10) {
                    readable(snapshot.parameters)
                    if let configuration = snapshot.configuration {
                        DisclosureGroup("Full Saved Configuration") { readable(configuration).frame(height: 180) }
                    } else { Text("The saved configuration file is unavailable. Known image parameters are shown above.").font(.caption).foregroundStyle(.secondary) }
                }.padding(12).tabItem { Text("Parameters") }
            }
            HStack {
                Button("Copy Prompt") { copy(snapshot.prompt) }
                Button("Copy Parameters") { copy(snapshot.parameters) }
                Button("Copy All") { copy(snapshot.copyText) }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(22).frame(width: 760, height: 600)
    }
}
