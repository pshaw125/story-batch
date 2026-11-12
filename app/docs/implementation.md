# Implementation handoff

- `Sources/StoryBatchCore/MetaPrompt.swift`: header parsing, validation, recursive fragment syntax tree, weighted lazy expansion. Adding a parameter requires extending `BatchParameters`, its allowed-key list, parser and tests.
- `Generation.swift`: fixed generation recipe, image planning, exact lexical shift handling, report and event types. Preview resolves the first four plans. Launch/Queue Next materializes remaining plans with `freezingPlans`, so all queued recipes are inspectable and immutable. `rebased` changes only numbering/filenames against the latest destination report, retaining frozen noise seeds, shifts and expanded prompts.
- Shift defaults to uniformly sampled thousandths from 1.500 through 2.250 inclusive. Optional `shiftValues` stores ordered comma-separated values and is validated against parsed count. Planning uses a zero-based index within the round, separate from cumulative filename numbering; both previews and lazy plans restart at the first value on Generate More. Viewer variants clear list/range fields and pin the source's actual shift. Optional Codable fields retain compatibility with older reports.
- Optional `seedValues: [Int?]?` stores ordered seeds, using null entries for `_` placeholders and an absent outer value for scalar/default mode. Both list types use the same `roundIndex` to pair entries, including lazy plans after the first four previews and subsequent rounds. A final `_*` in a seed list expands to null placeholders up to count during parsing; it may stand alone and cannot follow more than count entries. Placeholder seeds are independently sampled during planning; preview plans remain frozen. Viewer variants clear the seed list and retain the source's realized seed. Header validation and feedback reject bad entries or count mismatches before generation.
- `ShiftValue.evaluating` preserves valid plain literals verbatim and otherwise uses a bounded recursive-descent decimal arithmetic parser (+, -, *, /, parentheses, unary signs and scientific notation). Scalar shifts, list entries and range bounds share this path. Final results pass the existing positive finite Float32-compatible validation. Expressions never execute code. The metaprompt retains original expressions; shift values in plans/configs/filenames are numeric results. Decimal operations have finite precision; repeating divisions can round. List feedback retains the entry position and underlying arithmetic error.
- Shift expression values can be scalars or vectors. Parenthesized comma lists support scalar broadcasting on either side and pairwise operations between equal-length vectors. Top-level list splitting preserves plain literals and item feedback; expanded vector values are validated against count. `seeds` is normalized to `seed` during header parsing and duplicate detection.
- Each runner invocation sets a fresh `latestRunID` and tags image records with `runID`, independently of the cumulative batch ID. `latestCompletedPlans` selects completed records for that invocation in raw generation order. Collect Seeds/Shifts update only the header via quote-aware `replacingParameter`, preserving body and unrelated fields and removing duplicate seed aliases. The model tracks completed plans while running and reloads them from reports after completion/open/relaunch. Older reports use the last recorded request count as a fallback.
- `BatchRunner.swift`: sequential process execution, incremental raw logs and sampling progress, per-image timing, unique output folder, atomic report updates, flushed event lines, cancellation with forced termination fallback. No shell interprets title or prompt content. PNG signature and terminal IEND chunk are checked before marking completion.
- `Sources/StoryBatchApp/StoryBatchApp.swift`: app entry point and quit/cancellation lifecycle only.
- `AppModel.swift`: main-thread editor/session state, queue orchestration, batch/refinement commands, and collection actions. Generation runs on a background queue. Session restoration suppresses persistence until the saved folder/report is loaded.
- `MainView.swift`: primary editor and tab composition, settings and syntax guide. `MainTab.swift` names the tabs and makes pane selection exhaustive rather than relying on integer tags.
- `PromptEditor.swift`: native plain NSTextView, undo/find behavior, and the Fields window; smart substitutions remain disabled.
- `ImageViewer.swift`: viewer/window lifecycle, scoped arrow navigation, fullscreen, recipe inspector and image-specific commands.
- `ImageCollections.swift`: shared gallery card and shortlist/favorite actions, reused by Images, Shortlist and Favorites. `GalleryItem.swift` represents image path plus optional recipe availability; external images never display placeholder generation parameters.
- `StoryBatchCore/ImageSelections.swift`: persisted per-batch shortlist references. Legacy favorite flags are ignored when decoding older files. `FavoritesFolder.swift`: directory scanning, collision-safe byte-for-byte copies, recipe/config sidecars and removal; disk image files are the sole favorite membership source. The model caches scan results only for rendering, refreshing on startup, tab entry, output-root change and favorite actions.
- Shortlist variant requests capture `shortlistOnCompletion` at enqueue, carrying it through launch to successful completion. Later tab changes do not change whether the result is shortlisted. Completed variants remain regular batch records.
- `PromptFindModel` tracks literal, case-insensitive UTF-16 match ranges and the active occurrence. The editor uses layout-manager temporary background attributes for yellow/orange highlights, preserving plain text and undo history. Find commands, inline controls and text-view selection changes share this model. External document updates refresh the Find state asynchronously to avoid publishing during SwiftUI view updates.
- Image-only full screen uses native `NSWindow.toggleFullScreen`. Window delegate notifications switch the preview state so native green-button entry also hides all viewer chrome. F toggles and Esc exits; the window continues routing plain left/right arrows to the same navigation state. Entry/exit transitions are guarded against repeated toggles. Both modes share an aspect-fit image view; full screen removes padding and uses black letterboxing.
- `EditorSession.swift`: atomic draft, output-folder and last-report reference persistence. The running recipe is independent of the live editor. Matching titles permit continuation of the last completed/stopped round; prompt, fields and parameter edits apply to new images in the same folder. New Batch explicitly forces a fresh folder, including when the title is unchanged. The parsed header uses the latest title as a fallback only when no title is supplied; all other omitted fields use their ordinary defaults. The next image number follows the highest prior attempt. Cancellation removes folders only when their cumulative report has no completed images. Report-level source and parameters update for regular rounds, while each record retains its own source metaprompt and request parameters. Optional record fields keep old reports readable.
- Open Batch (⇧⌘O) uses a directory picker and `AppModel.loadBatch`: validate the saved report/metaprompt first, then restore source, images, report reference, parent output directory and Images tab. Existing generation prevents loading. Invalid batches do not replace draft/gallery state. Loading reads reports without modifying batch files and persists the new session reference; subsequent Generate More uses the batch's latest header and cumulative numbering.
- Preview refinements use `PreparedBatch.refinement`: exactly one frozen image plan with either new steps or a new shift, retaining the source image's other settings and expanded prompt. Shift offsets use checked `NSDecimalAdd`; zero, negative and unsupported results are rejected. `AppModel` queues both request types on the main thread and launches them sequentially after a completed round, reloading the source report before each request so numbering and prior records remain current. Requests arriving during completion are handled by the same queue. Stop and failures clear pending requests. Queue state is session-only. Report-level metaprompt parameters stay unchanged; image records contain the actual refinement recipe and `refinementOf` path.
- `QueuedWork` unifies pending rounds and viewer variants in request order; current-round waiting images are exposed separately and concatenated for the Queue tab. Queue More compares the live title with the active compiled title, snapshots all plans, and pins the destination (via an active token until the folder exists). Removing a future row stores its original offset; upon rebasing, that offset maps to the correct reserved number, preserving seed/shift-list pairing. `BatchRunner.cancelQueuedImage` uses a lock-protected pending set: the worker claims an image before starting it, so individual cancellation cannot target an already-starting process. Skipped records remain in reports and cumulative numbering but are excluded from gallery order. Stop/failure clears both queues. Queued normal rounds do not overwrite newer editor drafts.
- `build.sh`: direct compiler/bundle/sign workflow. `test.sh` executes the same core cases using a small standalone assertion runner on Command Line Tools installations without XCTest. Native build intermediates stay under `.build/`; generated app under `dist/`.

The app intentionally has no parallel generation, downloading, automatic prompt rewriting, automatic interrupted-job resume, or external dependencies. Executable choices are saved in the ignored local renderer config; exporting a metaprompt file is explicit. The live editor draft is saved automatically. The gallery retains previous rounds in the current folder and restores the last folder on launch; other past batches remain accessible in Finder.

## Build and verification

`ZoomableImageView.swift` embeds an NSScrollView/NSImageView in both viewer modes.
Its document canvas tracks the pane size; magnification 1 therefore means a full
aspect-fit image, not native pixel size. Trackpad magnify events clamp to 1–16
without elastic undershoot and anchor at the gesture location. Native scrolling
pans the magnified document. The image path controls content replacement; the known seed controls zoom/pan reset.
Same-seed variants retain the viewport, even across folders, while unknown-seed
files reset on file changes. Native-view checks cover minimum magnification,
content replacement with retained zoom/pan, seed changes and pane resizing.

Running-image Skip targets the runner's lock-protected claimed image number,
including the preparation window before Process.run. Stale or duplicate requests
cannot affect the next image. Termination and its forced-kill fallback are shared
with batch cancellation, but Skip never sets the batch-cancel flag. The existing
running record is updated through imageFinished as skipped (not appended again),
retaining elapsed time/logs and reserving its number. Subsequent images and queued
rounds/variants continue, including after a skipped one-image variant round.

`app/build.sh` and `app/test.sh` compile every Swift source in the app target, so
adding a focused source file does not require extending a hand-maintained list.
Core tests and fake-CLI AppModel checks verify frozen recipes, report history,
scoped navigation, disk favorites (including external files), duplicate filenames,
shortlist inheritance and persistence without local GPU generation.

The app model remains the orchestration boundary. Further changes should keep
filesystem storage in core stores and reusable rendering in gallery/viewer files,
rather than rebuilding the former all-in-one source. A wholesale queue/state
rewrite is not needed for this extraction.

## Queue ordering

`QueueOrdering.swift` splits waiting regular rounds into frozen execution units
only when the user reorders. BatchRunner.detachPendingImages atomically yields
after the claimed image and returns unclaimed numbers; racing jobs already
claimed are excluded. Removed original slots are still written as skipped before
yield. AppModel then interleaves those units with queued rounds and variants.

QueuedRound shares one logical run ID and once-only requested-count accounting
across its units. PreparedBatch.fragment retains original request parameters and
all img2img input/crop/prompt metadata; rebased copies the whole preparation and
changes only numbering/plans. Reports retain physical usage order and one logical
run identity for Collect Seeds/Shifts. Partial-round removals become hidden skipped
slots; wholly canceled future rounds disappear. Reordering changes future execution
boundaries without stopping the running process.

## Zoomed seed-boundary navigation

ImageZoomScrollView reports live magnification to ImagePreviewState; representable
updates reconcile asynchronously and ignore callbacks for obsolete image paths.
Zoom state publishes only actual changes, avoiding an update/reconciliation loop.
The navigation guard records source path, destination path and direction. A fresh
second press confirms that exact boundary; key-repeat events cannot confirm it.
Same-seed moves stay immediate. Returning to fit, selecting an image or changing
scope clears pending confirmation. Buttons and keyboard arrows share this logic.
The native-view test covers magnification reporting; AppModel tests cover both
boundary directions, reversal, autorepeat, default-fit bypass and stale callbacks.

Rendering retries: `BatchRunner` allows at most two CLI executions per claimed image. Arguments and artifacts are frozen across attempts; failed output moves into logs before a retry. Only launched-process failures (nonzero exit or incomplete PNG) qualify, and cancellation/skip is checked before each launch. `renderAttempts` is optional for old-report compatibility; `image_retry` events and the combined log preserve recovery evidence. Image elapsed time spans both attempts; CLI sampling metrics describe the final attempt. Persistent failures retain the existing stop-queue behavior.

Mixed shift lists use optional `shiftEntries: [ShiftListEntry]?`, preserving old scalar/range/shiftValues report decoding. Entries hold fixed values or unresolved ranges; final range* expands to the count during validation. Planning samples each range independently, including lazy plans beyond the preview; freezing preserves realized choices. Viewer variants clear shiftEntries and pin the source shift.

Rejections share `ImageSelectionStore` with shortlist flags, using optional `SavedImageSelection.rejected` for older saved-state compatibility. Keep entries while either flag is set. Gallery filtering happens in `displayImages`; `images` and reports retain every result. `rejectedImages` is batch-scoped and uses the same ordering. Viewer scope changes follow the next surviving item, then the previous, when a selection is removed. Favorites map rejection actions to the original batch image without removing the copied favorite.

## Renderer configuration and portability

`RendererConfiguration.swift` isolates local executable selection and the Draw Things model/sampler/seed-mode/guidance/LoRA recipe from prompt and queue logic. `ImagePlan.recipe` captures per-image settings; missing fields in legacy reports use the original Z-Image Turbo preset. Frozen rounds, rebased fragments and viewer variants retain this recipe. Reports record the actual first model and per-image settings; changing model does not invalidate an existing batch folder. Only Draw Things-compatible imported checkpoints/adapters can be used; compatibility and performance are not inferred from a filename. No weights are bundled or downloaded.

The current application is macOS-only: SwiftUI/AppKit viewer/editor/window management, native bundle signing scripts, Darwin process termination and CLI availability require separate Windows work. The configuration and recipe boundary is preparation for that work, not a Windows renderer implementation.
