# Phase 2 — native adapters and recovery

Recorded 2026-11-12. Phase 1 was committed/pushed as `234e79b`. Phase 2 implements the native adapters and recovery contracts. Contract tests and Mac Draw Things native image/cancellation/offline checks pass. Windows/ComfyUI native verification remains pending.

## Delivered contracts

- Draw Things process adapter: explicit local/offline/no-download flags, imported checkpoint identifiers, frozen native configuration, explicit negative prompt, isolated per-attempt prompt/config/invocation/log/output files, progress parsing, streamed logs, deadline termination and cancellation. The executable/model directory belong to ignored local config. CLI version and executable hash are recorded; unknown hardware/components remain explicit.
- ComfyUI adapter: dedicated loopback service only, native node/model/input validation, versioned built-in Z-Image workflow, literal resolved text/seed/steps/shift/dimensions, native sampler/scheduler, WebSocket progress, history-based completion and PNG retrieval. No models, nodes or services are installed/downloaded automatically.
- Lost acknowledgements use an ownership token retained in queue/history; newer servers also receive a client-generated prompt ID. Older servers can assign their own ID. An uncertain response never causes a second blind POST. Socket loss does not establish failure. Unknown work occupies the adapter and stops waiting jobs if unresolved.
- Cancellation targets the owned pending/running prompt, checks for foreign work before interruption, and waits for confirmation. A dedicated instance is required even where targeted interrupts exist. Local process cancellation waits for child closure before advancing.
- Sequential executor: one image, frozen retry, at most two submission attempts; validation/cancel are not retried. A second confirmed render failure stops waiting jobs. Stop/skip target the current image. Saved queues are never silently resumed.
- PNG output is fully decoded with dimensions, chunks/CRC and pixel completeness checks, with a 64-megapixel decode limit. Per-attempt partial output and native artifacts remain identified. Published outputs use exclusive creation; an existing file is never overwritten.
- Reports retain requested/effective recipes, run OS/framework context, optional service OS (loopback may bridge Windows to WSL), cache flags, loading-inclusive controller/adapter timings and renderer observations where reported. Cached sampler output is labelled separately from fresh inference.
- `npm run render -- ...` exercises the real adapters independently of the future workhorse UI. Public configuration examples contain placeholders only; paths, sources, weights, batches and native artifacts remain ignored. Packaging includes decimal.js and pngjs; WebSocket server tooling is test-only.

## Evidence and open gates

| Check | Status |
| --- | --- |
| TypeScript strict build and shared/adapter contracts | 100 tests passed, 0 failed on macOS arm64, Node 24.22.2 |
| Draw Things fake process | Exact offline args/config, progress, complete/incomplete/wrong-size output, one recovery, persistent failure/missing assets, launch validation, timeout, stop/skip targeting |
| ComfyUI fake HTTP/WebSocket server | Success, missing model/node, invalid workflow, bounded failure, cached output, socket loss, lost acknowledgement with either ID policy, owned queued/running cancellation, foreign-work refusal, uncertain timeout |
| PNG integrity | Valid synthetic image, corrupt CRC and truncated data checked |
| Mac packaging/host regression | Packaged with decimal.js + pngjs; isolated DOM/IPC/filesystem/process/loopback/synthetic completion/cancellation probe passed |
| Native Draw Things cancellation/recovery | Passed: initial startup cancellation at ~1.03s; later canceled an eight-step request after its first real sampling step (~12.02s elapsed), one attempt. Waiting image cleared with zero attempts. The same adapter/executor then completed a new 512px four-step image in 33.16s (CLI reported 29.54s), uncached, one attempt |
| Native Draw Things 512px rendering | Passed on retry: same prompt/seed 1234, three steps, shifts 1.75 and 2.0; two complete 512×512 PNGs, one attempt each. Loading-inclusive controller times 31.01s and 26.99s; native CLI reported 27.74s and 23.65s. Both uncached; native reported three sampling steps. Decoded pixels differ (250,202/262,144); visual inspection shows coherent red ceramic cups with soft lighting |
| Mac filesystem access | User reported a macOS access prompt while away. The retry after their return progressed into sampling and completed. This supports pending privacy approval as the earlier blocker. No system permissions were changed by the agent and no assets were relocated |
| Real ComfyUI / Windows / GPU | Pending; no ComfyUI installation or inference on this Mac, no Windows execution in this session |
| Intended-resolution offline native inference | Passed for Node/Draw Things path: 1024×1024, seed 1234, shift 1.75, four steps; one uncached attempt, 105.01s controller / 101.14s CLI-reported generation time. PNG validation and visual inspection passed. Node + renderer inherited the verified process-scoped sandbox profile below; outbound TCP probe failed with EPERM. Full Electron GUI and Windows/ComfyUI offline inference remain separate gates |

Native proof artifacts are under ignored `typescript/Batches/`, including `.attempts/`. The first canceled batch and later blocked batch remain on disk for inspection. Those canceled/blocked runs must not be treated as successful images or speed measurements. The successful retry is a separate batch. The earlier blocked request waited ~279.78s in a local settings-file open at 0% CPU/~7 MB footprint before cancellation; its waiting variant was cleared without starting. The Swift app and original batches were untouched.

## Native offline verification method

The Node CLI and its Draw Things child ran under this process-scoped profile; machine networking was unchanged:

```text
(version 1)(allow default)(deny network-outbound)(allow network-outbound (remote ip "localhost:*"))
```

Before rendering, the same `sandbox-exec` profile rejected a Node TCP connection to an external IP with `EPERM`. The inherited-profile render then completed successfully with local/offline/no-download CLI flags. Loopback was allowed; no external connection or dependency procurement was needed. The successful batch has an ignored `verification.local.json` recording the method and result. This proves the native Node/Draw Things route; it does not retroactively pass the earlier Electron nested-sandbox test or prove ComfyUI offline behavior.

These are individual loading-inclusive observations, not a sustained/cold-versus-warm benchmark or a character-style quality evaluation. The synthetic scene was a red ceramic cup on a wooden table; coherent scene output was inspected at 512px and 1024px. Native logs confirm requested three/four sampling steps; the fixed-prompt three-step shift pair changed decoded pixels. No new style conclusions are drawn from this smoke test.

## Workflow boundary

The workflow builder is `src/node/comfy-workflow.ts`, ID `story-batch/z-image-turbo-txt2img/1`. Its manifest hash identifies the declared workflow version/policy; every exact submitted graph and receipt is saved separately. Stock nodes load UNet/Qwen/VAE locally, encode text, zero negative conditioning, allocate one SD3 latent, apply AuraFlow shift, sample, decode and save one PNG. There are no partner/API/custom nodes in this graph. The initial native preset follows the inspected upstream template's `res_multistep`/`simple` choices; it is not claimed to match Draw Things sampler 17 or to be measured on the owner's GPU.

Native assets in the example preset are `z_image_turbo_bf16.safetensors`, `qwen_3_4b.safetensors` and `ae.safetensors`. Compatibility and memory/performance remain untested. Pin the eventual Windows ComfyUI/runtime/dependencies and record actual asset precision; the adapter checks installed node inputs/assets instead of silently substituting settings. LoRAs and image-to-image remain disabled capabilities until their later phase.

## Repeat Mac checks / finish Windows native gates

From `typescript/`, copy/edit `renderer.example.json` to ignored `renderer.local.json`, then create an ignored `smoke.local.txt` metaprompt. Run:

```sh
npm run render -- --config renderer.local.json --source smoke.local.txt --output Batches
```

The Mac checks above are complete for the current Node/Draw Things path. The earlier settings-file stall cleared after the user returned and handled the macOS access prompt. If it recurs, check the pending approval before interpreting the delay as model performance. The recorded invocation/config/log files support controlled comparisons; do not change model files to hide an access problem.

For Windows, use `comfyui.example.json` as the local config basis. Explicitly procure a pinned Portable/runtime installation and required compatible assets before ordinary use. Check actual GPU/VRAM/driver/PyTorch support before choosing precision. Launch a dedicated loopback service with installed local frontend assets and no custom nodes/manager. Where supported by the pinned build, use `--listen 127.0.0.1 --disable-auto-launch --disable-all-custom-nodes --offline`; set a local `--front-end-root` if needed to avoid frontend acquisition. These flags supplement the offline gate; `--offline` is documented as restricting frontend networking/partner nodes, not a universal block on every Python dependency. No download/update command belongs in normal startup.

After setup, prove one native Windows image, native step/shift application, cancellation followed by another usable job, image review and offline execution. Record cached versus fresh inference and cold/warm timings. The workhorse UI is Phase 3; its existing Phase 1 window remains synthetic-only.

## Primary references

Inspected 2026-11-12; upstream branches can change and are not an installed-version pin.

- [Official Z-Image workflow template](https://github.com/Comfy-Org/workflow_templates/blob/main/templates/image_z_image_turbo.json) and [guide](https://docs.comfy.org/tutorials/image/z-image/z-image-turbo).
- [ComfyUI routes](https://docs.comfy.org/development/comfyui-server/comms_routes), [messages](https://docs.comfy.org/development/comfyui-server/comms_messages) and [server implementation](https://github.com/Comfy-Org/ComfyUI/blob/master/server.py).
- [Native shift node](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy_extras/nodes_model_advanced.py) and [startup flags](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy/cli_args.py).
- Installed `draw-things-cli generate --help` and existing Swift BatchRunner configuration/flags. No model download was performed.
