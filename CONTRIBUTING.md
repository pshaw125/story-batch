# Development

Keep application code, tests, build scripts and usage/implementation documentation in Git. Keep user prompts, field libraries, batches, reference images, model/LoRA weights, local configuration, logs, build products and editor/session state out of Git. The root ignore file deliberately uses an inclusion list: review it when introducing a new source directory or fixture type.

Use `bash app/test.sh` and `bash app/build.sh` with a compatible macOS Swift toolchain. The tests use a temporary fake CLI and synthetic data, not real image generation. All app source files are compiled by both scripts. Do not automatically restart the app: a user may have work in flight.

Draw Things is the current renderer boundary. Keep executable discovery/local configuration and model/adapter recipe serialization in their dedicated core types. New queued work must freeze its recipe. Viewer variants, copied favorites, rebased queues, logs and reports must retain provenance. Remain offline; do not add implicit model downloads.

Keep platform UI/windowing, process lifecycle and renderer availability behind explicit platform boundaries. Do not claim that a model, adapter or sampler is portable merely because its settings can be serialized.

Before proposing a commit, inspect `git status --short --untracked-files=all`, `git diff`, and the complete eligible file list (`git ls-files --cached --others --exclude-standard`). Check for personal paths, credentials, media, model weights and unintended prompt data. Never bypass the ignore rules to include local assets. Publish only after review of the concrete candidate contents.

The [TypeScript migration plan](app/docs/typescript-migration-plan.md) defines the proposed phased replacement and offline/data-preservation gates. The [renderer compatibility decision](app/docs/renderer-compatibility.md) permits native backend differences while requiring OS/framework provenance. These plans do not change the shipped macOS build or authorize implicit downloads.

The shared implementation lives in `typescript/`; see its README for explicit dependency procurement, `npm test`, host probes and packaging. Shared core modules must not import Node/Electron. Keep native access in the Node/desktop boundaries. Stage only reviewed source/manifests/lockfiles; the package script uses a separate inclusion-list staging directory, never the live checkout. Phase progress belongs in `app/docs/typescript-phase-*.md`. Windows/macOS CI is configured but execution evidence must be recorded separately.

Desktop queue/session behavior belongs in `typescript/src/node/desktop-session.ts`; report writers must merge updates through the serialized store instead of saving stale whole reports during rendering. Viewer variants preserve their source recipe and the latest editor source separately. UI code lives under `src/desktop/ui/` and is bundled locally at build time. Use the synthetic desktop probe for routine UI checks; native smoke tests require explicit local config/output and preserve their proof artifacts.
