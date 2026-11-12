# Phase 3 — desktop workhorse UI

Recorded 2026-11-12. Phase 2 was committed/pushed as `c458a60`. Phase 3 is implemented and Mac-verified; its Windows workhorse acceptance gate remains open. The Swift reference application and its data remain untouched.

## Delivered

- Separate parameter, prompt and multiline field editors using the existing shared language, live preflight validation and frozen resolved previews. Portable metaprompt Open/Save/Save As, native editing/menu shortcuts and undo/redo.
- Explicit Draw Things/ComfyUI configuration selection with local paths/assets; persistent renderer/output settings; a clearly labelled synthetic mode for CPU-only workflow tests. Native failures never fall back to synthetic output.
- A desktop session controller independent of Electron/DOM: title-based continuation, Queue More during execution, forced New Batch while idle, persisted immutable requests and reserved numbering. Draft edits and field changes do not alter queued work. Outstanding preview choices survive viewer-variant renumbering.
- Serialized report mutations that merge active image updates and newly appended rounds. Existing jobs/run contexts cannot be overwritten; continuation does not lose completed records. New folders include a timestamp/title/ID for file-picker identification; existing UUID-only folders are preserved. Latest editor source is distinct from source-preserving viewer variants.
- Sequential native execution, progress and active seed/shift/steps, queue summaries, completion filename/timing activity, Stop Batch and bounded recovery. Window closure waits for active cancellation, including preparation before submission. Interrupted saved work never resumes implicitly; unresolved work remains blocked pending an explicit renderer check/reset.
- Fitted gallery and viewer, aspect-correct queued/running placeholders, nonwrapping arrows, selectable seed/shift/step metadata, prompt/recipe/environment sheet and copy. Higher step buttons, decimal shift offsets and constrained absolute shift queue variants without modifying the editor. Image reads are scoped to the selected report and reject paths redirected outside its folder.
- Completed adapter PNG buffers are released after durable output/report storage; file-backed inspection preserves status/idempotency and original files. Unknown work retains its reconciliation state.
- Modular TypeScript DOM UI with esbuild at build time. Context isolation, sandboxed preload, scoped IPC, bundled-only resources and denied external UI navigation/network remain in place. Native renderer access stays in the main process. No runtime/model procurement or automatic updates were introduced.

## Evidence

Environment: macOS arm64 (Darwin 25.6.0), Node 24.22.2, TypeScript 5.9.3, Electron 45.3.1, esbuild 0.28.2.

| Check | Result |
| --- | --- |
| Strict build / core, renderer and desktop-session contracts | 116 tests passed, 0 failed on Mac |
| Shared desktop session | Frozen preview reuse; append during active rendering; title and forced-new behavior; stop with waiting rounds; latest source after variants/reload; interrupted/unknown saved work; scoped file access; configured ComfyUI fake API without fallback |
| File operations | Metaprompt file round trip, Save/Save As targets, invalid Open preserving prior save target; user file-picker interaction itself remains a manual OS check |
| Hidden Electron UI probe | Passed: fixed four-image request, mixed continuation, draft edits while queued, separate title/new folder, recipe/environment sheet, step variant, fitted image, arrow keys, Stop Batch, report reload, native text undo/redo |
| Three four-image requests at 1 MP | Passed using synthetic PNGs in session tests. This proves queue/storage/UI contracts only, not inference quality, GPU support or speed |
| Real UI → Draw Things | Passed with one 512×512, three-step Z-Image Turbo q6p image: 29.03s loading-inclusive controller time, one attempt. Editor → preview → queue → native child → gallery/viewer completed; an editor change during generation did not change the frozen resolved prompt. Outputs/report remain in ignored local test storage |
| Packaged Mac app | Built as `Story Batch.app` for darwin-arm64; same hidden UI/host probe passed. Native app identity/data directory is separate from Swift. Package inclusion audit passed; no prompts, batches, local renderer config or test fixtures |
| Windows core/UI/package | Pending actual Windows execution; CI definitions exist. Public GitHub API did not provide run evidence in this session |
| Windows native workhorse / offline inference | Pending actual compatible GPU/runtime, owner image review and intended-resolution batches. Fake tests and Mac output do not close this gate |

UI screenshots were inspected locally using synthetic content. The native UI smoke test is explicit (`--native-ui-smoke` with local config/output environment values), bounded, and preserves its output; it is not part of ordinary startup or CI. No existing app was restarted automatically.

## Acceptance on Windows

After explicitly procuring a pinned ComfyUI runtime and compatible Z-Image components, select `comfyui.example.json` copied/edited as ignored local configuration. Confirm installed hardware/driver/precision and keep ComfyUI dedicated and loopback-only. The [Phase 2 instructions](typescript-phase-2.md) cover native setup/offline requirements.

Complete three four-image requests at intended dimensions: fixed recipe, paired/mixed seed+shift settings, and a continuation with edited fields/prompt/parameters. Verify exact saved prompts/settings/numbering and that later editor edits do not change queued images. Exercise Stop Batch, reload without resume, a source-preserving viewer variant, and error recovery. Review actual image viability, record cold/warm timings and cache state, and render without external networking while permitting loopback. Only that evidence passes the Windows workhorse gate.

## Deferred scope

Phase 4 contains queue-item removal/reorder/Run Next, Skip/Stop After controls, Collect Seeds/Shifts, editor find, draft/session persistence, collections and sort modes. Empty canceled-batch cleanup is also a remaining workflow detail. Phase 5 contains Swift report/collection import, LoRAs and image-to-image. Phase 6 contains full Mac adoption, advanced fullscreen/zoom/pan interactions, remaining native polish and release packaging/signing. Native picker behavior and window lifecycle deserve owner testing on each OS.

These deferrals do not change frozen-input, offline, source-only Git or original-file preservation requirements. No Swift retirement or Windows quality/performance claim is implied by this implementation checkpoint.
