# Story Batch desktop

Story Batch generates sequential offline image batches from metaprompts. The TypeScript/Electron application provides separate parameter, prompt and field editors, a frozen queue, image inspection, collections, image-to-image and native LoRAs. Draw Things CLI serves macOS; a dedicated local ComfyUI service serves Windows. The working Swift application remains available in `../app` with separate data.

Mac desktop/native-render checks pass. Windows native image quality, GPU compatibility, offline rendering and workhorse acceptance require verification on Windows; see [Phase 3 evidence](../app/docs/typescript-phase-3.md) and [Phase 4 evidence](../app/docs/typescript-phase-4.md).

## Setup and launch

Use Node 22.12+ and npm. From this directory:

```sh
npm ci
npm run setup:electron
npm start
```

Dependency/Electron procurement is explicit and can require networking. Ordinary launch uses the installed runtime and fails visibly if it is missing. No model, adapter or renderer service is downloaded by the application. Packaged applications bundle Node/Chromium and need no system Node/npm. In PowerShell, use `npm.cmd` if the local execution policy blocks `npm.ps1`.

Choose **Renderer configuration…** and select a local config file based on `renderer.example.json` or `comfyui.example.json`. Model assets and the renderer must already be installed. A source checkout also recognizes `renderer.local.json` in this directory; `STORYBATCH_CONFIG` is an explicit path override. Renderer selection/output settings persist outside the repository. Invalid native config or rendering never falls back to synthetic output.

**Use synthetic** selects dimension-correct color swatches for testing editing/queue/viewer flows without a GPU. The renderer label and report framework identify synthetic output. It is not image inference or a quality/performance benchmark.

## Windows setup

Install Node 22.12+ and run these commands in PowerShell from the repository's `typescript/` directory:

```powershell
npm ci
npm run setup:electron
npm run host:probe
npm start
```

Use `npm.cmd` instead of `npm` if PowerShell's execution policy blocks `npm.ps1`. The host probe checks desktop integration without a model; select **Use synthetic** to check the UI before configuring real rendering.

For image generation, install a dedicated local ComfyUI instance and the required model assets, start its loopback service, and select **Renderer configuration…** with a local configuration based on [`comfyui.example.json`](comfyui.example.json). Dependency and model procurement can require networking; rendering must work offline afterward. Native Windows GPU compatibility, image quality and offline rendering require verification on the target machine.

## Edit and generate

- **Parameters** is one semicolon-delimited line. **Prompt** contains illustration text and field references; **Fields** contains raw multiline `NAME=value` definitions. The [usage reference](../app/README.md#metaprompt-files) describes the language and defaults. These panels save as the portable header/body/`%%FIELDS%%` format.
- **Find** uses Cmd/Ctrl+F across parameters, prompt and fields. Every match has a faint yellow highlight; the active match is light orange. Cmd/Ctrl+G, Shift+Cmd/Ctrl+G, Enter/Shift+Enter or the search arrows move between matches. Clicking a matching term makes it active. Highlighting preserves native text editing and undo.
- **Open / Save / Save as** read/write metaprompt files. Standard editing, undo/redo, cut/copy/paste and select-all use native text controls/menu shortcuts. Save writes the chosen file only when requested.
- **Resolve preview** displays up to four exact expanded prompts and chosen parameters. Generate/Queue More reuses unchanged preview choices. If a viewer variant reserves an intervening number, the preview's jobs are renumbered without rerolling. Edited or already-queued previews are labelled so they are not mistaken for the next request.
- **Generate / Queue More** freezes and saves every image before execution. Same-title requests continue the current folder even when parameters, fields or prompt change. Later editor changes affect later requests only. **New Batch** forces a separate folder and is disabled during a run. A changed title starts a separate folder when idle; it cannot switch folders mid-run.
- **Stop Batch** cancels the current owned image and clears waiting requests while preserving completed files. Renderer validation/cancellation is not retried. Confirmed render failure gets one retry; persistent failure stops waiting work. Uncertain API work requires reconciliation before new submission.
- **Stop After Current** clears waiting images and lets the current image finish. **Queue** has per-image Up/Down/⏭ Run Next/Cancel controls and **Skip current**. Moves preserve frozen seed/shift/prompt pairing and reserved filenames. Skipping cancels only the current owned image; uncertain cancellation still requires reconciliation. Explicitly queueing more after Stop After Current adds new work.
- **Collect Seeds / Collect Shifts** replace the corresponding header value with completed images from the most recently executed logical request, in actual execution order. Canceled/failed images are excluded; a viewer variant is its own one-image request. Collection does not change `count`: align it with the collected list before queueing a partially completed or differently sized request.
- **Open batch…** loads a TypeScript report and its latest queued editor source. It displays saved images without resuming old work. Viewer variants retain their source's recipe and do not replace the latest editor source. Swift reports/collections are copied through **Import Swift…**.

**Preview / Images / Activity / Queue / Shortlist / Favorites / Rejected** provide resolved inputs, fitted image cards/running placeholders, queued seed/shift/step/dimension summaries, and completion filenames/timings. The bottom progress row includes active seed, shift and steps. Numbers reserve their place when queued, including canceled images. **Seeded** sorts by seed → shift → steps; **Seeded-Step** by seed → steps → shift; **Newest** puts recently finished images first. Sorting is shared by the gallery and viewer; changing it keeps the selected image visible and updates its index. Execution order is recorded separately.

Click a completed image to inspect it. The viewer fits the image without stretching and uses nonwrapping arrows. **Prompt & parameters** displays/copies the frozen recipe and OS/framework provenance. Higher step buttons (4, 6, 7, 8), shift offsets and a positive absolute shift with up to three decimals append a one-image request using the source's resolved prompt, seed, dimensions and native recipe. The metaprompt editor is unchanged. Absolute-shift text supports normal caret keys; clicking away restores image arrow navigation.

The 📌 **Shortlist**, ⭐ **Favorite**, and 🚫 **Reject** image actions have hover descriptions. Shortlist and rejection are independent batch flags. Rejection hides an image from Images without deleting its file or recipe; Rejected has a Restore action. Shortlist/Favorites/Rejected are separate views with scoped, nonwrapping viewer navigation. Removing the viewed item chooses the next image, or the previous one at the end. Variants queued from Shortlist are shortlisted immediately, including their running placeholders.

**Favorites** reads the selected output root's `_favorites/` directory. Favoriting copies the image plus a recipe/provenance sidecar. Startup, entering the view, or **Refresh Favorites** rescans the directory; external image additions/removals are supported. Sidecar hashes must match the copied artwork. Files without usable sidecars show unknown parameters and have no recipe/variant controls. A cross-batch favorite offers **Open source batch** before batch-specific actions; its copied image and recipe remain readable if the original folder is unavailable. Unfavoriting moves the copy into `_favorites/.removed/`; the batch original is preserved. The output root selects the Favorites library; an open batch can have a different physical parent.

## Image inspection controls

| Action | Controls |
| --- | --- |
| Zoom around the pointer | Ctrl+wheel or Alt/Option+wheel; trackpad pinch uses the same Ctrl-wheel gesture path |
| Pan | Left drag, middle drag, or Space+left drag |
| Vertical / horizontal pan | Wheel / Shift+wheel |
| Zoom at the view center | `+` or `=` / `-`, including **numpad Add/Subtract**; visible +/− buttons |
| Reset zoom and pan to fit | `0` or **Fit** |
| Image-only fullscreen | `F` or **Fullscreen**; `F` or Escape returns to the viewer |
| Previous / next image | Left/right arrows or buttons, without wrapping |

Zoom ranges from fit to 16× fit; displayed percentages are relative to fit, not native pixel size. The image keeps its aspect ratio. Panning stays bounded; an axis that still fits remains centered. Pointer anchoring applies within these bounds. Mouse capture keeps a drag working outside the image area until release, and blur/cancel clears the drag.

Same-seed images retain the current normalized inspection point and zoom, including after changing sort order. A new seed resets to fit. While zoomed, crossing to a known different seed requires a second fresh press/click in that direction; held-key repeats cannot confirm. An amber notice appears by the navigation area, or as the sole text overlay in fullscreen. Fit clears the pending confirmation. Returning to an earlier seed starts at fit; there is no per-seed viewport history. Unknown-seed images reset on identity changes.

Viewer shortcuts yield to text inputs, selectors and the recipe dialog. Image zoom does not zoom the application UI. The [Phase 6 viewer evidence](../app/docs/typescript-phase-6.md) distinguishes automated mouse/fullscreen checks from physical-device and Windows checks.

## Images, adapters and Swift import

**Image-to-image & LoRAs** contains render tools for future jobs. **Choose canvas…** opens a local image; **Use as canvas** in the viewer uses an existing image/Favorite and its resolved source prompt. No model or adapter is downloaded by the app.

- **Append** resolves the editor's change text/fragments/fields, then appends it to the literal source prompt. **Replace** uses only the resolved editor text. Empty change text is allowed when appending a nonempty source prompt. Both modes create new output images; neither replaces original artwork.
- Image strength is a separate native 0–1 control. **Match** requires the same aspect ratio; **Center-crop** explicitly crops to the output aspect. Both resize using recorded bilinear interpolation with alpha composited on white before either backend sees the canvas. The copied original, processed PNG hashes/dimensions, crop, strength, source and final prompt are recorded. Canvases are content-addressed under `.inputs/` and archived in the batch's `inputs/`; retries retain the same bytes/settings. Open batch restores the last editor request's canvas, falling back to archived copies. New jobs use the current renderer/LoRA setup; frozen historical jobs remain unchanged.
- LoRA lines are `filename | weight | optional Draw Things version`. **Apply LoRAs** freezes the list for subsequent requests; edits do not alter queued images. Draw Things requires a converted local `.ckpt` tensor store and either catalog registration or an explicit native version. Raw SafeTensors are rejected before rendering. ComfyUI uses already-installed model-only SafeTensors adapters without Draw Things version labels. Triggers belong in the prompt and are not inserted by Story Batch. Empty the list and apply to turn adapters off.
- **Text render · current setup** in the viewer explicitly creates a new text-to-image job with that image's resolved prompt, seed, steps, shift and dimensions, using the current model/LoRAs. It ignores the selected canvas. Ordinary step/shift variants keep their source's complete native recipe and canvas instead.
- **Import Swift…** selects one legacy batch and displays its recorded old folder → selected folder mapping for confirmation. Optional selections JSON and Favorites directory are copied too. Imported outputs, raw report/configuration/input records and historical Draw Things recipes are retained; source files stay untouched. Old waiting work is canceled, never resumed. Missing/unsupported data is reported. Historical images require an explicit current-setup render or Use as canvas; their numeric native settings are not silently reassigned to ComfyUI. Other-batch Favorites keep usable historical metadata without inventing source mappings.

The [Phase 5 guide/evidence](../app/docs/typescript-phase-5.md) describes format/compatibility limits and native verification. Asset file existence and successful loading do not establish that every third-party adapter is compatible with a model.

## Local data

Default application data is `story-batch-typescript` under the platform application-data directory (`~/Library/Application Support/` on Mac, `%APPDATA%` on Windows). Images/reports default to its `Batches/` folder. **Output folder…** selects the destination for new folders; an open batch retains its existing location. Swift data is neither moved nor replaced. The draft, selected collection/sort and last batch persist in `session.json`, separately from explicit metaprompt saves. Restoration opens the last batch for inspection and retains unfinished/invalid editor text; it never resumes waiting jobs. Autosave is debounced and flushed on normal window/application closure. A damaged session file is reported and backed up before replacement. Explicit Save remains the way to write a metaprompt file.

New batch folders use timestamp, sanitized title and stable batch ID; older UUID-only folders remain readable. Each batch contains `report.json` and completed PNGs. The output root's `.attempts/<hashed job+attempt>/` holds native prompts/configuration/invocations/logs or workflows/receipts/history, including partial output. These are private. The main renderer releases completed PNG buffers after durable storage; the gallery/viewer reads files from the selected batch. Canceling a newly created batch before any image completes removes its otherwise empty folder and archives its canceled report under `.attempts/cancelled-batches/`; existing/loaded batches and folders containing other files are preserved. Files are created exclusively and report updates preserve existing frozen jobs/run contexts.

Saved waiting/running work is displayed as interrupted. Saved unknown work remains unresolved and blocks submission until the dedicated renderer is checked and its configuration explicitly reselected. ComfyUI also verifies the dedicated instance is idle before submitting. Do not interpret a config reset as a retry of a missing image.

## Renderer CLI and checks

The same adapters are available without the desktop UI:

```sh
npm run render -- --config renderer.local.json --source smoke.local.txt --output Batches
```

Config-relative executable/model directory paths stay local. Optional complete native `recipe` settings override the named backend preset. Draw Things sampler 17/Scale Alike are native identifiers; ComfyUI records its own workflow/sampler/scheduler. Unsupported nodes/assets/options fail visibly. Compatible LoRAs are supported; ComfyUI requests with adapters use the explicit tools/v2 workflow. Image-to-image is configured in the desktop canvas panel.

```sh
npm test
npm run host:probe
npm run package
```

Tests use temporary synthetic files and fake process/HTTP/WebSocket backends. The hidden desktop probe covers editing/undo, preview, frozen batches, continuation, native-setup copies, image-to-image append/replace/frozen options, legacy inspection, variants, viewer navigation/sort identity, queue editing, Stop After, collections, external Favorites, search highlights, and durable draft/page restore without resuming work. It does not require a model. Set `STORYBATCH_PROBE_NATIVE_FULLSCREEN=1` when running the host probe to include visible native fullscreen checks; the default probe stays hidden. CI configures Windows/macOS runs; recorded evidence distinguishes configured checks from executed checks.

Packaging creates an unpacked native application under ignored `artifacts/` using compiled source, a minimal manifest, runtime libraries and Electron. Prompts, fields, local config, outputs, models and test fixtures are excluded. Build on the destination OS/architecture. Electron distribution procurement can be needed during packaging; ordinary application launch cannot download it. Signing/installers are release work.

## Module boundaries and limits

- `src/core`: prompt language, sizing, frozen jobs, native recipes, reports and desktop/renderer contracts; no Node/Electron imports.
- `src/node`: native adapters, atomic report storage, sequential execution, desktop session/queue and file operations.
- `src/desktop`: native window/dialog/menu/IPC adapters and a sandboxed TypeScript/DOM UI. Context isolation and restricted IPC keep Node/filesystem/process access in the main process. UI resources are bundled; external navigation/requests are denied. There is no updater or telemetry dependency.

Expressions are parsed with 38-significant-digit decimal arithmetic, never evaluated as code. Plain shift literals retain supplied precision; precision extremes/repeating division can differ from Foundation Decimal. Request/source limits are 100,000 images/2 MB; integers must fit JS safe integers. Fragment/field/output/expression bounds remain 256 depth / 64 chain / 1 MB expansion / 4096 characters and 64 depth. Native output decoding additionally caps at 64 megapixels and validates complete PNG data, dimensions and CRC.

The new report format supports multiple runs/OS/framework contexts in a batch. Swift import preserves old native settings as historical records; new backend requests are explicit. Rendering stays sequential, offline after procurement, and explicit about unsupported capabilities. Synthetic tests do not pass native quality/performance gates.

See the [migration plan](../app/docs/typescript-migration-plan.md), [host decision](../app/docs/typescript-host-decision.md), [Phase 2 native evidence](../app/docs/typescript-phase-2.md) and [Phase 3 evidence](../app/docs/typescript-phase-3.md). This repository intentionally has no project license; third-party libraries retain their own licenses.
