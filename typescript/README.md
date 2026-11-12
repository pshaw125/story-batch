# TypeScript Phase 1

This is the shared core and Electron host spike. The working Swift app remains in `../app`. This spike only generates synthetic 1×1 PNGs; it does not connect to Draw Things or ComfyUI and cannot demonstrate model quality or performance.

## Setup and run

Use Node 22.12+ and npm on macOS or Windows. From this directory:

```sh
npm ci
npm run setup:electron
npm test
npm run host:probe
npm start
```

The first two commands are explicit dependency/runtime procurement and can require networking. Start/probe use the installed Electron executable directly; a missing runtime produces an error instead of invoking Electron's download-on-demand launcher. After setup, `npm test` and `npm start` require no external services. Packaged applications bundle Node/Chromium and need no system Node/npm. No models or user prompts are distributed.

On PowerShell, use `npm.cmd` if the local script-execution policy blocks `npm.ps1`; no policy change is needed. Test discovery and child-process commands do not rely on a Unix shell. `.github/workflows/typescript.yml` exercises tests, host probe and packaging on Windows and macOS when run; configuration is not proof those checks passed.

The small UI accepts the existing combined portable metaprompt format, resolves up to four preview cards as JSON, and runs/cancels a sequential synthetic batch. Running an unchanged preview uses the same frozen jobs; subsequent drafts do not edit active work. Reports are separate from Swift: `story-batch-typescript-spike` under the platform application-data directory, then `spike-batches/<id>/report.json`. Automated host probes use an isolated temporary directory. Normal launch never loads or resumes a saved queue.

```sh
npm run package
```

Packaging builds an unpacked application for the current OS/architecture under ignored `artifacts/`. It stages only compiled application source, the minimal manifest and decimal.js runtime, then bundles Electron. Existing prompts, fields, reports and renderer configuration never enter the staging directory. Packaging can procure an Electron distribution if it is not cached; ordinary app launch cannot. Installers, signing and release distribution are later work.

## Boundaries

- `src/core`: portable parser, decimal arithmetic, sizing, resolution, immutable jobs, native recipes, report contracts and renderer interface. No Node, Electron, shell or network imports.
- `src/node`: report persistence, environment capture and local host probe. Files are created exclusively; report replacement is serialized and atomic. Previously frozen recipes/run contexts cannot be rewritten. Reload is read-only until explicitly saved; it never submits work.
- `src/desktop`: Electron main, a narrow typed preload bridge, sandboxed DOM UI. No generic IPC/path/shell API is exposed. The main process owns filesystem/process access; the page cannot make network requests.
- `test`: synthetic contract tests, with injected random values and temporary files. No private fixture batches or actual inference.

A native recipe is tagged `draw-things` or `comfyui`; sampler 17 and Scale Alike remain Draw Things concepts. `drawThingsPreset()` preserves the original q6p starting recipe. The ComfyUI type describes required identities/settings; it is not an installed or validated preset. There is no renderer executable path hardcoded in this tree. Real native adapters and local config arrive in Phase 2.

## Contracts and deliberate bounds

The current parameter/fragment/field language follows the Swift usage guide. Defaults remain count 4, steps 3, random seeds and shifts 1.500–2.250; aspect sizing retains the 64-pixel grid. Plain shift literals retain supplied precision, while arithmetic uses an isolated 38-significant-digit decimal context; repeating division rounds. No expression executes as JavaScript. Exact edge-case decimal rounding is not promised to match Foundation Decimal.

To avoid unsafe JS allocations, a request is limited to 100,000 images and source to 2 MB. Integers must be safely representable in JavaScript; a pixel cap is at most `Number.MAX_SAFE_INTEGER`. These are explicit validation errors, not silent truncation. Existing fragment depth 256, field chain depth 64, expanded size 1 MB and expression length/depth 4096/64 are retained. Filenames additionally sanitize Windows-reserved characters/device names; historical files are unchanged.

Each job freezes source, resolved text/shared field choices, seed/shift/steps/dimensions and the complete native recipe. Reports version their schema and hold all run contexts separately, so continuation can retain OS/framework/version per image. Missing hardware/driver/runtime/hash information is explicitly `unknown`. These are new TypeScript reports, not a legacy-import implementation.

Renderer submission is idempotent by job ID plus attempt. Attempt 2 requires a confirmed failure and identical job; unknown status requires reconciliation, never blind retry. Cancellation/validation failures cannot enter retry. The fake renderer provides explicit `advance`/`fail` controls for deterministic tests, one active image, status/result/progress/cancel, and rejects unsupported LoRAs. Its synthetic PNG intentionally does not match requested dimensions; full output validation and recovery orchestration belong to Phase 2.

Pinned packaging overrides for glob/minimatch remove reported transitive advisories; packaging is tested with these versions. No auto-updater or telemetry package is included. This source intentionally has no project license; third-party dependencies retain their own licenses.

See [host decision](../app/docs/typescript-host-decision.md), [Phase 1 evidence](../app/docs/typescript-phase-1.md), and [migration plan](../app/docs/typescript-migration-plan.md).
