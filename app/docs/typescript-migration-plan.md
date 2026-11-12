# TypeScript migration plan

Status: phase 0 approved; Phase 1 implemented and Mac-verified; Phase 2 adapter contracts implemented and Mac Draw Things image/cancellation/offline checks passed; Windows/ComfyUI native image proof remains pending. Phase 3 desktop UI is implemented and Mac-verified; Windows workhorse acceptance remains pending. Phase 4 daily iteration/collections is implemented and Mac-verified; Windows iteration acceptance remains pending. Phase 5 import/render tools are implemented and Mac-verified; native Windows tool acceptance remains pending. The Phase 6 viewer controls are implemented and Mac-verified; full platform adoption/native polish and physical-device checks remain open. Updated 2026-11-12. See [Phase 1 evidence](typescript-phase-1.md), [Phase 2 evidence](typescript-phase-2.md), [Phase 3 evidence](typescript-phase-3.md), [Phase 4 evidence](typescript-phase-4.md), and [Phase 5 evidence](typescript-phase-5.md), and [Phase 6 viewer evidence](typescript-phase-6.md).

The target is a shared TypeScript application with Windows ComfyUI and macOS Draw Things CLI adapters. The committed Swift app remains the working reference and fallback. Windows can become the workhorse once useful batches are proven; full Mac UI parity and advanced gestures do not gate that milestone.

TypeScript is the owner's selected direction, including its relevance beyond this personal project. The [host decision](typescript-host-decision.md) selects Electron and a plain TypeScript DOM UI for the Phase 1 spike. Any richer UI framework is deferred. The Swift app remains the shipped reference.

## Priorities and feature inventory

Tier 1 is offline batches of viable images with frozen, inspectable parameter blobs and run provenance. Supporting parser/storage/cancellation requirements below are proposed safeguards for that core. Tier 2 restores productivity features. Tier 3 is optional interaction polish. Features can move between tiers through an explicit recorded decision; no syntax or saved recipe may silently change meaning.

Current syntax is owned by the [usage guide](../README.md) and [field reference](prompt-fields.md). Native backend differences are covered by the [compatibility decision](renderer-compatibility.md).

| Feature group | Phase | Priority |
| --- | --- | --- |
| Header validation; seed/shift scalar/list/range/remainder syntax; arithmetic; aspect sizing/pixel cap | 1 | Tier 1 supporting contract |
| Nested weighted fragments; multiline fields; shared/fresh references; bounded validation | 1 | Tier 1 supporting contract |
| Frozen plans, IDs, numbering, native recipe types and report/storage contracts | 1 | Tier 1 |
| Native model/encoder/VAE selection, seed/steps/shift/guidance/sampler/scheduler | 2 | Tier 1 |
| Draw Things and ComfyUI adapters, with fake adapters for tests | 2 | Tier 1 |
| Sequential render, progress/timing, Stop Batch, output validation and one retry | 2–3 | Tier 1 supporting contract |
| Parameter/field/prompt editing, Open/Save, basic undo/redo, validation and resolved preview | 3 | Tier 1 supporting contract |
| Queue More/New Batch, title continuity, batch reload, editor changes for later requests | 3 | Tier 1 supporting contract |
| Fit-to-pane gallery/viewer, basic arrows, resolved prompt/recipe copy and environment details | 3 | Tier 1 |
| Step and absolute/offset shift variants preserving the source native recipe | 3 | Tier 1 comparison workflow |
| Queue removal/reorder/Run Next, Skip current, Stop After This Image | 4 | Tier 2 |
| Collect Seeds/Shifts, editor search/highlights, draft persistence | 4 | Tier 2 |
| Shortlist, disk Favorites, Rejected/Restore, scoped navigation and three sort modes | 4 | Tier 2 |
| Legacy Swift batch/collection import and explicit path mapping | 5 | Tier 2 |
| Image-to-image append/replace modes, copied canvas, crop/strength and provenance | 5 | Tier 2 |
| Compatible LoRA loading and native weights | 5; recipe schema in 1–2 | Tier 2 |
| Mac replacement UI, native shortcuts/dialog/reveal integration | 6 | Later platform completion |
| Fullscreen, pinch zoom/pan, same-seed viewport retention and seed-boundary guard | 6 or later | Tier 3 |
| New ControlNet/inpainting/upscaling features, cloud generation or parallel GPU scheduling | Outside migration | No implied commitment |

## Hard-line invariants

These apply to every implemented phase, including fake-renderer stages.

- **I1 — Offline runtime:** after explicit procurement of models, libraries, drivers and dependencies, the app and renderer work without external networking. Local loopback IPC is allowed. No cloud fallback, online credentials requirement, telemetry dependency, remote UI resources, implicit downloads or automatic updates during ordinary use. Missing components fail visibly. This also covers renderer extensions/dependencies.
- **I2 — Frozen jobs:** save resolved prompts, field choices and selected values before queueing. Later edits affect later requests only. Retries retain the same resolved recipe. Record actual native settings and applied defaults.
- **I3 — Preserve data:** no migration side effect overwrites/deletes original images, prompts or batches. Imports use copies or explicit read-only mappings. Swift retains access to its original data. Failed/partial outputs remain identified; interrupted work never silently resumes.
- **I4 — Provenance:** OS name/version/architecture and generation framework/version are required run details. Each image references run context and its effective recipe. Record hardware, drivers/runtime, component identities/precision, workflow/node versions and input preprocessing where available; unknowns are explicit. Version the report schema.
- **I5 — Native backend behavior:** identical tuples may differ across engines/platforms. No Scale Alike or exact UniPC Trailing emulation is required. Unsupported controls fail explicitly; changing backend creates a new native recipe rather than an exact-reproduction claim.
- **I6 — Queue/recovery ownership:** Story Batch owns pending jobs and submits one image at a time to a dedicated renderer instance. Stop preserves completed work. Validation errors and user cancellations are not retried. A render failure gets at most one retry; reconcile uncertain API job status before resubmitting. A second failure stops waiting work unless policy is explicitly changed.
- **I7 — Private source boundary:** prompts, fields, runs, weights, artwork and local configuration/paths stay out of committed source. Synthetic fixtures are allowed. No project license is added by this migration.
- **I8 — Honest readiness:** compilation, fake-backend tests, real rendering, visual quality and performance are separate evidence. Windows-render-ready requires actual Windows Z-Image output. Swift remains available until its replacement is accepted.

## Phase 0 — Baseline, compatibility and plan

**Features:** this inventory, priority tiers, compatibility decisions, platform boundaries, hardware gates and the reference baseline (`ce33965` plus current Swift docs/tests).

**Invariants:** I1–I8 shape all targets. Existing assets stay untouched; cross-backend pixel reproduction is not a goal.

**Gate:** document native differences and undecided host/UI choices; give each later phase a useful deliverable and measurable acceptance target. This document is the accepted planning baseline; later gates remain uncompleted.

## Phase 1 — TypeScript core and host spike

**Features:** parser/fields, safe decimal arithmetic, sizing, freezing, IDs and reports. Separate common requests from tagged Draw Things and ComfyUI recipe settings. Define renderer validation/submission/progress/status/result/cancel and capability contracts. Add fake-renderer tests. Prototype only enough desktop hosting to establish local filesystem/process/API access on both OSes.

**Invariants:** I1–I8; expressions are parsed, never evaluated as JavaScript. Core tests need no GPU/private assets. Legacy sampler 17 stays a Draw Things identifier.

**Gate:** shared tests run on Windows and Mac and cover supported Swift syntax/errors, lazy choices and list pairing. Inject randomness for contract tests; field choices do not have to match across languages merely because image seeds match. Fake jobs prove frozen edits, persistence and cancellation. Record the desktop host/UI decision and packaging strategy before scaffolding. Review ignore-rule changes for the new TypeScript source tree; the current inclusion list intentionally will not admit it automatically.

## Phase 2 — Renderer adapters and real-image proof

**Features:** Draw Things process adapter and ComfyUI API adapter with a versioned local Z-Image Turbo workflow. Configure native components and controls; normalize progress, PNG retrieval, status, cancellation, elapsed timing and one retry. Record backend/OS context. Keep ComfyUI running between jobs.

**Invariants:** I1–I8; use appropriate native presets, with explicitly procured local assets and local-only nodes. A lost socket does not establish render failure. Global interruption is only for the dedicated instance's owned job.

**Gate A — contracts:** fake process/server tests cover successful jobs, invalid workflow, missing model, progress, incomplete output, retry limit, stop/skip targeting, timeout and lost connection after successful completion. No new GPU is needed for this gate.

**Gate B — real images:** each adapter produces valid native-resolution output with applied parameters and environment records. ComfyUI proves a changed step/shift request is applied and cancellation leaves the next job usable. Inspect a predeclared small fixed-prompt/seed set at intended dimensions; Swift is a quality/style reference, not a pixel target. Record actual model precision and components.

**Offline gate:** after procurement, launch and render with external networking unavailable, allowing loopback for app/server communication. Missing assets fail without downloading. Record versions and test method. Identify cached returns so they are not presented as fresh inference timings.

## Phase 3 — Minimum Windows workhorse

**Features:** shared UI for parameters, fields, prompt, validation, resolved preview, file Open/Save and ordinary editing/undo. Generate batches sequentially with active parameters/progress, completion filename/timing and recorded recipe blobs. Add Queue More/New Batch and title continuity, batch reload, Stop Batch, fitted gallery/viewer, nonwrapping arrows, recipe/prompt copy, environment details and source-preserving step/shift variants. Defer advanced gestures if necessary.

**Invariants:** I1–I8; typing never changes frozen jobs, existing Swift files remain untouched, and completion reflects actual execution.

**Gate:** on the new Windows GPU, complete at least three four-image batches at intended working dimensions: fixed recipe, mixed seed/shift recipe, and continued batch with draft edits. Verify prompts/parameters, numbering, reload, safe cancellation, one source variant and error recovery. Owner reviews image viability. Record cold/warm timings without inventing a speed target. This is the earliest Windows workhorse milestone.

## Phase 4 — Daily iteration and collections

**Features:** pending removal/reordering/Run Next, Skip and Stop After This Image; Collect Seeds/Shifts; editor find/highlights; draft persistence. Restore Seeded/Seeded-Step/Newest in galleries/viewer while retaining the viewed image during mode changes. Add Shortlist, file-backed Favorites and Rejected/Restore, transient running placeholders and scoped completed-image navigation.

**Invariants:** I1–I8; reorder never rerolls jobs or breaks list pairing. Execution order/logical runs remain distinct from gallery sort. Reject does not delete; unfavorite does not delete the original. Shortlist-derived variants retain membership. Session restore never automatically reruns waiting jobs.

**Gate:** queue race/cancel checks, restart persistence and independent collection tests pass on Windows. Exercise a real iteration session, including shortlisted variants, external favorite changes, rejection/restore, sorted insertion and viewer sort switching. Mac shared-core tests pass; Mac UI parity is not required yet.

## Phase 5 — Existing data and optional render tools

**Features:** legacy report/metaprompt import and collection import with explicit old-path mapping. Add image-to-image append/replace modes, copied input, crop/resize policy, native strength and source/final prompt provenance. Add compatible LoRAs with native metadata and weights.

**Invariants:** I1–I8; old Draw Things recipes are not silently reclassified as ComfyUI. Image strength and LoRA weight remain distinct. Missing assets/unsupported formats are explicit. Real private fixture batches and weights stay ignored.

**Gate:** load a copied legacy batch without modifying its original; retain text/settings as records and explicitly create a native recipe when switching backend. Verify source/crop/strength and append/replace behavior. Test a compatible adapter off/on with other settings fixed. Equal numeric strength need not give equal edits across engines.

## Phase 6 — Mac replacement and optional polish

**Features:** package the TypeScript UI with Draw Things on Mac. Finish shortcuts, dialogs, reveal-folder and safe process/window lifecycle. Optionally add fullscreen, zoom/pan, same-seed viewport retention and seed-boundary warnings through shared interaction code or small OS adapters.

**Invariants:** I1–I8; gesture parity does not block useful Windows operation. Native adapters do not duplicate queue/parser/storage logic. Swift and its data remain recoverable.

**Gate:** run Tier-1 acceptance on the TypeScript Mac app, compare an inspection session with Swift, and verify offline packaging/lifecycle behavior. Owner chooses adoption. Deferred polish is listed explicitly; removing Swift requires a separate decision.

## Hardware and evidence schedule

The current Windows machine has a GTX 970 with 4 GiB VRAM; an RTX 5070 is expected after this planning checkpoint. The new GPU may already be installed by the time real-render tests begin. Check hardware availability then; confirm actual VRAM, driver and supported runtime before choosing model precision or predicting throughput.

| Environment | Useful checks | Limits |
| --- | --- | --- |
| Mac with Swift/Draw Things | Reference behavior, contracts, Draw Things adapter, quality comparison | Cannot establish Windows CUDA/runtime compatibility |
| Windows with GTX 970 | TypeScript build/UI/filesystem, fake backend/API and queue tests; real runtime checks if supported | A large model may fail to load rather than just run slowly; not representative of RTX 5070 speed/memory |
| Windows with RTX 5070 after installation | Real output, offline proof, precision/component choice, cold/warm timing and sustained batches | No exact Mac-seed equivalence or claims about unmeasured workflows |

Phases 0–1 and phase-2 contract checks can proceed before the new GPU arrives. Real Windows rendering stays pending until supported hardware/runtime is available: fake tests cannot pass it, and GTX 970 limitations do not fail the entire port. Phase 3 workhorse acceptance requires actual Windows images.

## Progress records

For every phase, record delivered features, test/build environments, artifact/commit references, deviations and remaining gates. Store private prompts/results in ignored local test folders; repository evidence uses synthetic fixtures and nonprivate summaries. Hardware evidence can remain pending while other work is complete. Only passed gates are marked complete.

The Phase 1 implementation and verification status are recorded in [its progress report](typescript-phase-1.md). Later phases and real image generation retain their own gates; a fake host probe is not native renderer readiness.
