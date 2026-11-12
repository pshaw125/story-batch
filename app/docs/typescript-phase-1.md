# Phase 1 implementation and evidence

Recorded 2026-11-11. Implementation is present; the full Phase 1 gate remains pending Windows execution. No real renderer integration or model inference was performed. No existing Swift source, batch, prompt library, field library or model asset was changed.

## Delivered

- Shared TypeScript header parser: defaults/aliases/quotes, seed lists and `_`/`_*`, fixed/ranged/list shifts with remainder, safe scalar/vector decimal arithmetic, exact aspect sizing/pixel cap and feedback errors.
- Nested weighted/empty/duplicate fragments, escapes, multiline fields, shared `[NAME]` and fresh `[NAME*]`, lazy selection, all-branch validation, dependency/size bounds and injected randomness independent of image noise seed.
- Deep-frozen image jobs, source/resolved text/shared field snapshots, safe filenames in title_seed_steps_shift_number order, continued numbering and source-preserving variants.
- Tagged Draw Things/ComfyUI native recipes and explicit model/encoder/VAE/LoRA/workflow identities. Original Draw Things q6p starting preset retained; no invented ComfyUI sampling preset.
- Versioned reports with per-image run identity and required OS/framework details, multiple runs per batch, atomic serialized report writes, exclusive outputs, immutable prior recipes and no automatic resume. New format only; legacy import remains Phase 5.
- Renderer capability/validate/submit/progress/status/result/cancel contract. Idempotent attempts, explicit unknown status and one confirmed-failure retry boundary. Fake renderer tests cancellation, subsequent work and immutable effective jobs. Real failure recovery is Phase 2.
- Electron + plain TypeScript DOM host spike, isolated preload IPC, filesystem/process/loopback probe, bundled-only UI, fake batch completion/cancel and unchanged-preview reuse.
- Pinned dependencies/lockfile, explicit Electron runtime setup, portable test runner, reviewed source-only ignores, OS-native unpacked packaging and Windows/macOS CI workflow.

Host choice and packaging strategy were recorded [before scaffolding](typescript-host-decision.md). Run instructions and module boundaries are in [the TypeScript README](../../typescript/README.md).

## Evidence

Environment: macOS Darwin 25.6.0, arm64; Node 24.22.2, TypeScript 5.9.3, Electron 45.3.1. Times in generated reports use UTC; this progress record uses the owner's local date.

| Check | Evidence/status |
| --- | --- |
| Strict TypeScript compilation | Passed |
| Shared parser/planning/report/fake/host tests | 72 passed, 0 failed on Mac |
| Owner manual Mac smoke test | Passed: owner confirmed synthetic batch completion, host probe success and remaining checks good; deliberate count/list mismatch rejected as expected |
| Actual Electron host, sandboxed renderer/preload/main IPC | Passed: DOM preview, two-image synthetic completion, cancellation during another batch, filesystem write/read, child process and loopback HTTP |
| Native Mac package | Built for darwin-arm64; packaged executable passed the same DOM/IPC/fake-batch/host probe. ASAR audit passed: application code + decimal.js only; no tests, prompts, runs or local config |
| Dependency audit | 0 advisories after pinned glob/minimatch overrides; development and production dependencies audited |
| Enforced offline host run | Not verified: sandbox-exec network-denial wrapper prevented Chromium child-sandbox initialization before page load; normal Chromium sandbox remains enabled |
| Windows core/host/package | Pending. CI workflow and local commands exist; neither has been executed on a Windows host in this session |
| Real Draw Things / ComfyUI output, offline inference, performance | Outside Phase 1; not tested |

The ordinary host probe uses only local files, child processes and loopback. UI network requests/navigation/new windows are denied, no remote resources/updater are bundled, and launch errors if Electron is absent. This is implementation/test evidence, not proof that an OS-level external-network-denial run succeeded. Phase 2 must perform the stronger offline rendering gate.

## Explicit deviations and deferred items

- JS safe-integer limits, 100,000-image request limit and 2 MB source limit fail visibly. Decimal arithmetic uses 38 significant digits and may differ at precision extremes from Foundation. Windows-unsafe filename characters receive additional sanitization. No ordinary prompt syntax was intentionally removed.
- Basic host UI only; separate parameters/fields editors, dialogs, queue productivity tools and full workhorse flows retain their planned later phases. The spike does not replace Swift.
- Fake PNGs are valid synthetic 1×1 files, regardless of requested dimensions. Their completion proves application flow only. Native dimension/completeness checking, API disconnect reconciliation and retry orchestration remain Phase 2.
- Packaging stages compiled app source plus decimal.js, excluding tests/dev tooling/private data. Signing/installers and optional UI-framework adoption are deferred.

## Next gate

Run `npm ci`, `npm run setup:electron`, `npm test`, `npm run host:probe`, and `npm run package` in `typescript/` on Windows (use `npm.cmd` if needed), or run the checked-in CI workflow after review/push. Record actual OS/Node/Electron versions and results. A GPU is not needed. Only then mark the entire Phase 1 gate passed. Phase 2 contract work may proceed independently; real Windows inference is still a separate requirement.
