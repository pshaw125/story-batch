# Story Batch desktop

Story Batch generates sequential offline image batches from metaprompts. The TypeScript/Electron application provides separate parameter, prompt and field editors, a frozen queue, image inspection and step/shift variants. Draw Things CLI serves macOS; a dedicated local ComfyUI service serves Windows. The working Swift application remains available in `../app` with separate data.

Mac desktop/native-render checks pass. Windows native image quality, GPU compatibility, offline rendering and workhorse acceptance require verification on Windows; see [Phase 3 evidence](../app/docs/typescript-phase-3.md).

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

## Edit and generate

- **Parameters** is one semicolon-delimited line. **Prompt** contains illustration text and field references; **Fields** contains raw multiline `NAME=value` definitions. The [usage reference](../app/README.md#metaprompt-files) describes the language and defaults. These panels save as the portable header/body/`%%FIELDS%%` format.
- **Open / Save / Save as** read/write metaprompt files. Standard editing, undo/redo, cut/copy/paste and select-all use native text controls/menu shortcuts. Save writes the chosen file only when requested.
- **Resolve preview** displays up to four exact expanded prompts and chosen parameters. Generate/Queue More reuses unchanged preview choices. If a viewer variant reserves an intervening number, the preview's jobs are renumbered without rerolling. Edited or already-queued previews are labelled so they are not mistaken for the next request.
- **Generate / Queue More** freezes and saves every image before execution. Same-title requests continue the current folder even when parameters, fields or prompt change. Later editor changes affect later requests only. **New Batch** forces a separate folder and is disabled during a run. A changed title starts a separate folder when idle; it cannot switch folders mid-run.
- **Stop Batch** cancels the current owned image and clears waiting requests while preserving completed files. Renderer validation/cancellation is not retried. Confirmed render failure gets one retry; persistent failure stops waiting work. Uncertain API work requires reconciliation before new submission.
- **Open batch…** loads a TypeScript report and its latest queued editor source. It displays saved images without resuming old work. Viewer variants retain their source's recipe and do not replace the latest editor source. Swift batch import is a later migration phase.

**Preview / Images / Queue / Activity** provide resolved inputs, fitted image cards/running placeholders, queued seed/shift/step/dimension summaries, and completion filenames/timings. The bottom progress row includes active seed, shift and steps. Numbers reserve their place when queued, including canceled images.

Click a completed image to inspect it. The viewer fits the image without stretching and uses nonwrapping arrows. **Prompt & parameters** displays/copies the frozen recipe and OS/framework provenance. Higher step buttons (4, 6, 7, 8), shift offsets and a positive absolute shift with up to three decimals append a one-image request using the source's resolved prompt, seed, dimensions and native recipe. The metaprompt editor is unchanged. Absolute-shift text supports normal caret keys; clicking away restores image arrow navigation.

## Local data

Default application data is `story-batch-typescript` under the platform application-data directory (`~/Library/Application Support/` on Mac, `%APPDATA%` on Windows). Images/reports default to its `Batches/` folder. **Output folder…** selects the destination for new folders; an open batch retains its existing location. Swift data is neither moved nor replaced. Draft autosave/session restore and collections are later features; save metaprompts explicitly.

New batch folders use timestamp, sanitized title and stable batch ID; older UUID-only folders remain readable. Each batch contains `report.json` and completed PNGs. The output root's `.attempts/<hashed job+attempt>/` holds native prompts/configuration/invocations/logs or workflows/receipts/history, including partial output. These are private. The main renderer releases completed PNG buffers after durable storage; the gallery/viewer reads files from the selected batch. Files are created exclusively and report updates preserve existing frozen jobs/run contexts.

Saved waiting/running work is displayed as interrupted. Saved unknown work remains unresolved and blocks submission until the dedicated renderer is checked and its configuration explicitly reselected. ComfyUI also verifies the dedicated instance is idle before submitting. Do not interpret a config reset as a retry of a missing image.

## Renderer CLI and checks

The same adapters are available without the desktop UI:

```sh
npm run render -- --config renderer.local.json --source smoke.local.txt --output Batches
```

Config-relative executable/model directory paths stay local. Optional complete native `recipe` settings override the named backend preset. Draw Things sampler 17/Scale Alike are native identifiers; ComfyUI records its own workflow/sampler/scheduler. Unsupported nodes/assets/options fail visibly. LoRAs and image-to-image have separate later gates.

```sh
npm test
npm run host:probe
npm run package
```

Tests use temporary synthetic files and fake process/HTTP/WebSocket backends. The hidden desktop probe covers editing/undo, preview, batches, continuation, frozen edits, variants, viewer navigation, stop and reload. It does not require a model. CI configures Windows/macOS runs; recorded evidence distinguishes configured checks from executed checks.

Packaging creates an unpacked native application under ignored `artifacts/` using compiled source, a minimal manifest, runtime libraries and Electron. Prompts, fields, local config, outputs, models and test fixtures are excluded. Build on the destination OS/architecture. Electron distribution procurement can be needed during packaging; ordinary application launch cannot download it. Signing/installers are release work.

## Module boundaries and limits

- `src/core`: prompt language, sizing, frozen jobs, native recipes, reports and desktop/renderer contracts; no Node/Electron imports.
- `src/node`: native adapters, atomic report storage, sequential execution, desktop session/queue and file operations.
- `src/desktop`: native window/dialog/menu/IPC adapters and a sandboxed TypeScript/DOM UI. Context isolation and restricted IPC keep Node/filesystem/process access in the main process. UI resources are bundled; external navigation/requests are denied. There is no updater or telemetry dependency.

Expressions are parsed with 38-significant-digit decimal arithmetic, never evaluated as code. Plain shift literals retain supplied precision; precision extremes/repeating division can differ from Foundation Decimal. Request/source limits are 100,000 images/2 MB; integers must fit JS safe integers. Fragment/field/output/expression bounds remain 256 depth / 64 chain / 1 MB expansion / 4096 characters and 64 depth. Native output decoding additionally caps at 64 megapixels and validates complete PNG data, dimensions and CRC.

The new report format supports multiple runs/OS/framework contexts in a batch. It is not a Swift import converter. Rendering stays sequential, offline after procurement, and explicit about unsupported capabilities. Synthetic tests do not pass native quality/performance gates.

See the [migration plan](../app/docs/typescript-migration-plan.md), [host decision](../app/docs/typescript-host-decision.md), [Phase 2 native evidence](../app/docs/typescript-phase-2.md) and [Phase 3 evidence](../app/docs/typescript-phase-3.md). This repository intentionally has no project license; third-party libraries retain their own licenses.
