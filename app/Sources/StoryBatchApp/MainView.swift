import SwiftUI
import AppKit
import StoryBatchCore

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var find: PromptFindModel
    @FocusState private var findFocused: Bool
    init(model: AppModel) { self.model = model; self.find = model.find }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 28)).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.isRefinementMode ? "Story Batch · Refinement" : "Story Batch").font(.title2.weight(.semibold))
                    Text(model.isRefinementMode ? "Reference-guided local illustration" : "Metaprompts → local story illustrations").foregroundStyle(.secondary).font(.subheadline)
                }
                Spacer()
                Button("Open Image for Refinement…") { model.openImageForRefinement() }
                Button("Open Batch…") { model.openBatch() }.disabled(model.isRunning)
                if model.isRefinementMode { Button("Exit Refinement") { model.exitRefinement() }.disabled(model.isRunning) }
                Label("Local · Offline", systemImage: "lock.shield").font(.callout).foregroundStyle(.secondary)
                Button { model.showHelp = true } label: { Image(systemName: "questionmark.circle") }.help("Syntax guide")
                Button { model.showSettings = true } label: { Image(systemName: "gearshape") }.help("Settings")
            }.padding(20)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(model.isRefinementMode ? "REFINEMENT BATCH" : "METAPROMPT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if !model.isRefinementMode {
                            Button("Open…") { model.openDocument() }.disabled(model.isRunning)
                            Button("Save…") { model.saveDocument() }
                        }
                    }
                    Text("GENERATION PARAMETERS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("title=…; seed=…; shift=…; steps=…; resolution=… or aspect=…; pixel_max=…; count=…", text: Binding(get: { model.parameterText }, set: { model.parameterText = $0 }), axis: .vertical)
                        .font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder).lineLimit(2...4)
                    HStack {
                        Button("Collect Seeds") { model.collectSeeds() }.disabled(!model.canCollectValues)
                        Button("Collect Shifts") { model.collectShifts() }.disabled(!model.canCollectValues)
                        Spacer()
                    }.help("Replace parameter values with those from completed images in the latest run, in generation order")
                    if model.isRefinementMode {
                        HStack {
                            Text("IMAGE-TO-IMAGE STRENGTH").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Spacer()
                            TextField("0.35", text: Binding(get: { model.refinementStrengthText }, set: { model.refinementStrengthText = $0 }))
                                .frame(width: 70).font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder)
                        }
                        Text("0.25 preserves closely · 0.35 refines · 0.45 adjusts · 0.55+ increasingly reinterprets. The source image is copied into the refinement batch when it starts.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Prompt construction", selection: $model.refinementPromptMode) {
                            ForEach(RefinementPromptMode.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        DisclosureGroup("Original resolved prompt") {
                            Text(model.refinementOriginalPrompt.isEmpty ? "No saved prompt is available for this imported image." : model.refinementOriginalPrompt)
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                    }
                    HStack {
                        Text(model.isRefinementMode ? (model.refinementPromptMode == .appendDelta ? "REFINEMENT INSTRUCTIONS" : "FULL REPLACEMENT PROMPT") : "PROMPT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Extract Choices") { model.extractChoices(); model.openFieldsEditor() }.disabled(model.parameters == nil)
                            .help("Move each outer {...} choice into a named field; nested choices stay together")
                        Button("Fields (\(model.fieldCount))…") { model.openFieldsEditor() }
                    }
                    if find.visible {
                        HStack(spacing: 7) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Find in prompt", text: $find.query)
                                .textFieldStyle(.roundedBorder).focused($findFocused)
                                .onSubmit { find.move(by: 1) }
                                .onExitCommand { find.close() }
                                .onAppear { findFocused = true }
                            Text(find.counter).font(.caption).foregroundStyle(.secondary).fixedSize()
                            Button { find.move(by: -1) } label: { Image(systemName: "chevron.up") }
                                .disabled(find.matches.isEmpty).help("Previous match (⇧⌘G)")
                            Button { find.move(by: 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(find.matches.isEmpty).help("Next match (⌘G)")
                            Button { find.close() } label: { Image(systemName: "xmark") }.help("Close Find (Esc)")
                        }
                    }
                    PlainPromptEditor(text: Binding(get: { model.promptText }, set: { model.promptText = $0 }), find: find)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.25)))
                    if model.isRefinementMode && model.refinementPromptMode == .appendDelta {
                        Text("Describe only what should change. The original resolved prompt is retained behind the scenes and the final prompt is shown in Preview.").font(.caption).foregroundStyle(.secondary)
                    }
                    if model.isRunning {
                        Text("Edits apply to your next round. The current round keeps its original prompt and settings.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let p = model.parameters {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(p.count) images  ·  \(p.width) × \(p.height)  ·  \(p.steps) steps").font(.callout.weight(.medium))
                            Text("Seed: \(p.seedDescription)  ·  Shift: \(p.shiftDescription)").font(.caption).foregroundStyle(.secondary)
                            if let aspect = p.aspect {
                                Text("Aspect \(aspect) · \(String(p.width * p.height)) / \(String(p.pixelMax ?? BatchParameters.defaultPixelMax)) pixels").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let error = model.validationError {
                        HStack(alignment: .top) { Image(systemName: "exclamationmark.circle.fill"); Text(error).textSelection(.enabled).lineLimit(5) }.font(.caption).foregroundStyle(.red)
                    }
                    Text(model.isRefinementMode ? "The source image and prompt strategy are recorded with every output. Changing resolution center-crops the input canvas." : "[NAME] shares one field value per image · [NAME*] resolves fresh at each occurrence. Parameter and field edits keep the batch live.").font(.caption).foregroundStyle(.secondary)
                    if model.isRunning {
                        HStack {
                            Spacer()
                            Button("Stop Batch", role: .destructive) { model.stop() }.disabled(model.stopping)
                            Button(model.stoppingAfterImage ? "Finishing Image…" : "Stop After This Image") { model.stopAfterCurrentImage() }
                                .disabled(model.stopping || model.stoppingAfterImage)
                                .help("Finish and save the current image, then stop. Clears all waiting images and queued rounds.")
                        }
                    }
                    HStack {
                        Button(model.prepared == nil ? "Preview Batch" : "Reroll Preview") { model.preview() }.disabled(model.isRunning || model.parameters == nil)
                        Spacer()
                        Button("Queue More") { if model.isRunning { model.queueNext() } else { model.start() } }
                            .buttonStyle(.borderedProminent).disabled(!model.canQueueMore)
                            .keyboardShortcut(.return, modifiers: [.command])
                        Button("New Batch") { model.start(forceNewBatch: true) }
                            .disabled(model.isRunning || model.parameters == nil)
                    }
                }.padding(18).frame(minWidth: 390, idealWidth: 470)
                VStack(spacing: 12) {
                    Picker("View", selection: $model.selectedTab) {
                        ForEach(MainTab.allCases) { tab in
                            Text(tab == .queue ? "Queue (\(model.queueImages.count))" : tab.label).tag(tab)
                        }
                    }.pickerStyle(.segmented)
                    HStack(spacing: 8) {
                        Text("Image order").font(.caption).foregroundStyle(.secondary)
                        Picker("Image order", selection: $model.imageSort) {
                            ForEach(ImageSort.allCases) { Text($0.label).tag($0) }
                        }.labelsHidden().pickerStyle(.segmented).frame(width: 280)
                            .help("Seeded: seed, shift, steps. Seeded-Step: seed, steps, shift. Newest: latest generated first.")
                        Spacer()
                    }
                    selectedPane
                }.padding(18).frame(minWidth: 430)
            }
            Divider()
            VStack(spacing: 8) {
                HStack {
                    if model.isRunning { ProgressView().controlSize(.small) }
                    Text(model.status).font(.callout.weight(.medium))
                    if model.isRunning && model.currentImage > 0 {
                        Text(model.step >= model.totalSteps ? "Finishing image…" : "Sampling \(model.step)/\(model.totalSteps)").font(.caption).foregroundStyle(.secondary)
                        Text(BatchFormatting.duration(model.currentElapsed)).monospacedDigit().foregroundStyle(.secondary).font(.caption)
                    }
                    Spacer()
                    Button("Queue (\(model.queueImages.count))") { model.selectedTab = .queue }.font(.caption)
                    if model.folder != nil { Button("Show Batch Folder") { model.revealBatch() } }
                }
                if let plan = model.activeImagePlan {
                    ImageRecipeDetails(plan: plan).frame(maxWidth: .infinity, alignment: .leading)
                }
                if model.isRunning { ProgressView(value: model.progress).progressViewStyle(.linear) }
                HStack { Text("Z-Image Turbo · six-bit · one image at a time"); Spacer(); Text(model.outputRoot.path).lineLimit(1).truncationMode(.middle) }.font(.caption2).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 940, minHeight: 650)
        .onChange(of: model.source) { _ in model.validate() }
        .onChange(of: find.focusRequest) { _ in findFocused = true }
        .sheet(isPresented: $model.showHelp) { SyntaxGuide() }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
    }
    @ViewBuilder private var selectedPane: some View {
        switch model.selectedTab {
        case .preview: previewPane
        case .images: resultsPane
        case .activity: activityPane
        case .queue: queuePane
        case .shortlist, .favorites, .rejected: collectionPane
        }
    }
    private var previewPane: some View {
        ScrollView {
            if let batch = model.prepared {
                VStack(alignment: .leading, spacing: 14) {
                    Text("These resolved prompts and values will be used when generation starts.").font(.callout).foregroundStyle(.secondary)
                    if batch.compiled.parameters.count > batch.preview.count { Text("Showing \(batch.preview.count) previews for this round of \(batch.compiled.parameters.count). Remaining images are resolved when queued.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(batch.preview) { plan in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Image \(plan.number)").font(.headline)
                            Text(plan.filename).font(.caption.monospaced()).textSelection(.enabled)
                            Text("Seed \(String(plan.seed)) · Shift \(plan.shift.text) · \(plan.steps) steps · \(plan.width) × \(plan.height)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Divider()
                            Text(plan.prompt.isEmpty ? "(empty prompt)" : plan.prompt).font(.callout).textSelection(.enabled)
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "curlybraces").font(.system(size: 46)).foregroundStyle(.secondary)
                    Text("See the prompt before it renders").font(.title3.weight(.medium))
                    Text("Preview resolves weighted fragments, seeds, and shifts without generating an image.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Preview Batch") { model.preview() }.disabled(model.parameters == nil || model.isRunning)
                }.padding(35).frame(maxWidth: .infinity).padding(.top, 70)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var resultsPane: some View {
        ScrollView {
            if let root = model.refinementRoot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("REFINEMENT SOURCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if let image = NSImage(contentsOfFile: root.imagePath) {
                        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 180)
                    }
                    Text(URL(fileURLWithPath: root.imagePath).lastPathComponent).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Seed \(root.seed.map(String.init) ?? "imported") · Shift \(root.shift?.text ?? "imported") · \(root.steps) steps · \(root.width) × \(root.height)").font(.caption2).foregroundStyle(.secondary)
                }.padding(12).background(Color.accentColor.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.bottom, 10)
            }
            if model.displayImages.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text(model.rejectedImages.isEmpty ? "Finished images appear here" : "No visible images").font(.headline)
                    Text(model.rejectedImages.isEmpty ? "Each completion is logged with its filename and elapsed time." : "Hidden images are available in the Rejected tab.").foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.padding(35).padding(.top, 70).frame(maxWidth: .infinity)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205, maximum: 340))], spacing: 16) {
                    ForEach(model.displayImages) { record in
                        if let folder = model.folder {
                            GalleryImageCard(model: model, item: PreviewImageItem(record: record, folder: folder, hasRecipe: true))
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var collectionPane: some View {
        ScrollView {
            let items = model.selectedTab == .shortlist
                ? model.shortlistedImages.map { PreviewImageItem(record: $0.record, folder: URL(fileURLWithPath: $0.folderPath), hasRecipe: true) }
                : model.selectedTab == .rejected
                    ? model.rejectedImages.compactMap { record in model.folder.map { PreviewImageItem(record: record, folder: $0, hasRecipe: true) } }
                    : model.favoriteImages.map { PreviewImageItem(favorite: $0) }
            if items.isEmpty {
                Text(model.selectedTab == .shortlist ? "📌 Add images to this batch’s shortlist." : model.selectedTab == .rejected ? "No rejected images in this batch." : "❤️ Favorite images or add image files to _favorites.")
                    .foregroundStyle(.secondary).padding(30)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 205, maximum: 340))], spacing: 16) {
                    ForEach(items) { item in GalleryImageCard(model: model, item: item) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var queuePane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let plan = model.activeImagePlan {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Generating now · Image \(plan.number)", systemImage: "hourglass").font(.headline)
                            Spacer()
                            Button(model.skippingImage == plan.number ? "Skipping…" : "Skip", role: .destructive) { model.skipCurrentImage() }
                                .disabled(model.stopping || model.skippingImage == plan.number)
                                .help("Cancel this image and continue with the remaining jobs")
                        }
                        Text("\(plan.width) × \(plan.height)").font(.caption)
                        ImageRecipeDetails(plan: plan)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 9))
                }
                Text("Waiting to run · \(model.queueImages.count)").font(.headline)
                Text("Recipes are fixed when queued. Stop After This Image clears waiting jobs and saves the current image; Stop Batch interrupts it immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                if model.queueImages.isEmpty { Text("No images waiting.").foregroundStyle(.secondary).padding(.top, 20) }
                ForEach(model.queueImages) { job in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(job.label).font(.callout.weight(.medium))
                            Spacer()
                            let position = model.queueImages.firstIndex { $0.id == job.id } ?? 0
                            Button { model.moveQueuedImage(id: job.id, direction: .next) } label: { Text("⏭") }
                                .disabled(!model.canReorderQueue || position == 0).help("Run next, immediately after the current image")
                                .accessibilityLabel("Run next")
                            Button { model.moveQueuedImage(id: job.id, direction: .up) } label: { Image(systemName: "arrow.up") }
                                .disabled(!model.canReorderQueue || position == 0).help("Move up one place")
                                .accessibilityLabel("Move up")
                            Button { model.moveQueuedImage(id: job.id, direction: .down) } label: { Image(systemName: "arrow.down") }
                                .disabled(!model.canReorderQueue || position + 1 >= model.queueImages.count).help("Move down one place")
                                .accessibilityLabel("Move down")
                            Button("Remove", role: .destructive) { model.cancelQueuedImage(id: job.id) }
                                .disabled(model.stopping).help("Cancel this image before generation starts")
                        }
                        Text("\(job.plan.width) × \(job.plan.height)").font(.caption).foregroundStyle(.secondary)
                        ImageRecipeDetails(plan: job.plan)
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 9))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var activityPane: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(model.activity.isEmpty ? "No batch events yet." : model.activity.joined(separator: "\n\n"))
                    .font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                Color.clear.frame(height: 1).id("bottom")
            }.background(Color(nsColor: .textBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 9))
                .onChange(of: model.activity.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.title2.weight(.semibold))
            Text("Draw Things CLI").font(.headline)
            HStack { TextField("Executable path", text: $model.executablePath); Button("Choose…") { model.chooseExecutable() } }
            Text("Batch output folder").font(.headline)
            HStack { Text(model.outputRoot.path).font(.callout).textSelection(.enabled); Spacer(); Button("Choose…") { model.chooseOutput() } }
            Divider()
            Text("Generation defaults").font(.headline)
            Text(model.rendererDescription).font(.callout).foregroundStyle(.secondary)
            Text("Model, sampler and LoRA settings come from the local renderer config. Edit it and reopen the app to reload. Queued jobs keep their saved recipes.")
            Text(model.rendererConfigurationPath).font(.caption.monospaced()).textSelection(.enabled).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 610)
    }
}
struct SyntaxGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Metaprompt syntax").font(.title2.weight(.semibold))
            Text("One parameter line, then a newline and your prompt. A blank first line uses all defaults.")
            Text("title=happy cafe scene; seed=1234; shift=4.5501; steps=5; aspect=1:1; count=4; notes=study one").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Divider()
            Text("Defaults").font(.headline)
            Text("Title: epoch seconds · Seed: random 0–2³¹−1 per image · Shift: random 1.500–2.250 per image · Steps: 3 · Resolution: 1024*1024 · Count: 4")
            Text("A fixed seed applies to every image. A fixed shift retains its decimals. Use shift=4.2..4.8 for independent random shifts inside that inclusive range, at three decimal places. Notes are recorded but do not affect generation.")
            Text("Use either resolution=1152*896 or aspect=9:7. Equivalent ratios such as 18:14 resolve identically. aspect chooses the largest exact-ratio size in 64-pixel increments within pixel_max, which defaults to 1048576. Override with pixel_max=(1024*1024) or another positive whole-number arithmetic expression. Explicit resolutions exceeding the cap are rejected. Some exact ratios leave budget unused; 16:9 gives 1024*576 at the default cap.").font(.callout)
            Text("Use shift=2,3.5,4.55; count=3 for ordered shifts, one per image. The list length must equal count (default 4); otherwise generation is blocked with an explanation. Generate More repeats the list from its first value.").font(.callout)
            Text("Seed lists work the same way: seed=1234,_,_; shift=2,3.5,4.55; count=3 pairs entries by position. Each _ draws an independent random seed. End with _* to fill the remainder: seed=1234,_*; count=4 uses one fixed seed and three random seeds. Single numeric seeds and shifts apply to every image. Shift lists can mix values and ranges; a final range* fills the rest (shift=1.3,2.4,1.3..1.4,1.3..2.0*).").font(.callout)
            Text("Fragments").font(.headline)
            Text("{red|green}  ·  {red:::2|green:::3|red with a {worm|caterpillar}:::0.5}").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
            Text("Weights default to 1. Empty terms and duplicates are kept. {} resolves empty; {one} resolves one. Only selected nested branches are resolved. Every brace must close; malformed fragments stop the batch before generation.")
            Text("Named fields").font(.headline)
            Text("Open Fields and enter COLOR={red|green}. Use [COLOR] to reuse one complete resolution throughout each image, including nested choices. Use [COLOR*] to resolve afresh at each occurrence. Fields can span lines and refer to other fields; names are case-sensitive. Undefined fields and cycles block generation.").font(.callout)
            Text("Extract Choices moves outer fragments into FIELD_1, FIELD_2, … while retaining nested syntax. Prompt, fields and parameters can change within the same batch while its title stays unchanged. Queue More continues it; New Batch starts a fresh folder even with the same title. A changed title requires New Batch.").font(.callout)
            Text("Quote a header value to include semicolons: notes=\"soft light; good hair\". Escape literal prompt braces or bars with a backslash: \\{ \\} \\|. Weights must be finite and nonnegative, with at least one positive alternative.").font(.callout)
            Text("Resolution dimensions must be positive multiples of 64. Filenames keep spaces, but path separators/control characters are replaced and overlong titles are shortened; the full title is preserved in the report.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(25).frame(width: 660)
    }
}
