# Phase 5 — existing data and optional render tools

Recorded 2026-11-12. Phase 4 is committed/pushed as `ef66d2f`. The shared import/image-to-image/LoRA implementation has Mac contract, desktop and native Draw Things evidence below. Windows ComfyUI native image/adapter/offline acceptance remains pending. Swift source/data remain the reference and fallback.

## Import and historical recipes

**Import Swift…** copies one selected Swift folder into a new TypeScript batch. The confirmation displays the report's old folder and the actual selected folder: this explicit mapping handles a renamed checkout or a batch copied to another OS. Optional `image-selections.json` and a Swift `_favorites` directory import shortlist/rejection flags and Favorite copies. References outside the selected folder are not followed; additional/missing assets are reported rather than guessed.

The copy retains the full raw report, available configuration/input artifacts, source metaprompt, expanded prompts, original record/filename and native settings. Output filenames follow the current safe cross-platform scheme. Completed readable PNGs remain completed; missing/corrupt outputs are failed historical records with warnings. Old waiting/running work is canceled. Import never resumes inference or modifies the original. A private staging folder holds partial imports; only a fully constructed batch is published. Favorite-copy errors are reported separately.

Imported jobs keep tagged Draw Things recipes and explicit unknown OS/hardware details. Recipe origin distinguishes a recorded plan/configuration from assumed legacy defaults. A missing negative prompt is not presented as known. Historical step/shift buttons are disabled: **Text render · current setup** explicitly creates a new native text recipe, or **Use as canvas** begins image-to-image from the visible output. Neither operation reclassifies the original record. A Favorite from another batch retains a usable historical sidecar without claiming its unmapped source is an openable TypeScript batch.

## Image-to-image

The canvas picker and viewer action copy a local input before queueing. Content-addressed original/processed PNGs and batch archives preserve it after the original is deleted. Each frozen job records source, dimensions, hashes, crop/resize method, native strength, prompt mode/instructions and final resolved prompt. Changed/corrupt input hashes fail visibly; they do not trigger fresh random choices or silent fallback.

**Append** resolves only the change text, then appends it to the literal source prompt. Existing braces/field-like text in a resolved source are never re-expanded. **Replace** uses only the resolved replacement. Both produce new output files. **Match** requires equal aspect ratio; **Center-crop** explicitly takes a centered source rectangle. Both use `bilinear-rgba-white-v1` preprocessing before either renderer sees an exact-size canvas. Alpha is composited on white. This is a documented common input policy, not an assertion that native strength/noise schedules match across engines.

Open batch restores the latest editor request's canvas, including archive-path fallback after a move, without rewriting old jobs or resuming work. Current renderer/LoRA defaults remain explicit controls for new requests. Step/shift variants retain source input bytes and recipe. Clearing the canvas returns to text-to-image. Canceling an otherwise empty new canvas batch archives its report/input copies with diagnostics and removes the visible folder.

Draw Things receives an exact-size copied `--image`, explicit dimensions/strength, and the existing local/offline/no-download flags. ComfyUI uses a verified local PNG upload, `LoadImage` → `VAEEncode` → native denoising. Upload failure cannot cause duplicate inference submission. This follows the core [image/VAE nodes](https://github.com/comfyanonymous/ComfyUI/blob/master/nodes.py) and [upload API](https://github.com/comfyanonymous/ComfyUI/blob/master/server.py); installed node inputs/assets are checked before inference.

## Native LoRAs

The UI accepts ordered `filename | weight | optional Draw Things version` lines, including zero/negative finite native weights subject to backend validation. Apply affects later jobs only. Asset identity/precision/revision/hash have explicit unknown values when unavailable. Prompt triggers are user text; Story Batch does not add them implicitly.

Draw Things uses converted SQLite `.ckpt` LoRAs. Preflight checks the local tensor-store header and requires catalog registration or an explicit native version; raw SafeTensors/missing files fail before launch. Custom Z-Image adapters use `z_image` metadata. The installed CLI's `generate --help` documents per-invocation LoRA version handling and its separate image-strength option. A successful general model import is not proof of a working LoRA conversion.

ComfyUI uses model-only adapters, ordered before model sampling, with local file/node/weight validation. It does not accept Draw Things version labels or nonzero encoder weights. The [core model-only LoRA loader](https://github.com/comfyanonymous/ComfyUI/blob/master/nodes.py) supplies this boundary. Tool requests record `story-batch/z-image-turbo-tools/2`; existing text-only v1 recipes remain supported. An unsupported custom workflow is not silently replaced. Formats and equal weights do not establish cross-engine parity.

### Local compatibility procurement

With explicit owner permission, the test procured the creator-published [Elusarca Anime Style for Z-Image Turbo](https://huggingface.co/reverentelusarca/elusarca-anime-style-lora-z-image-turbo), pinned at `2218987fb6996131bacf9ea434dc7d97f300caa6`, Apache 2.0. The creator targets an illustration/anime style and lists the trigger `elusarca anime style`. This is a compatibility fixture, not a replacement style recommendation for all scenes.

Private local procurement stores revision/checksum metadata next to the assets. The 170,128,320-byte SafeTensors SHA256 is `4e2edb94c3cf7573af9734e7ce171c1c3176119febfa81470acc326d671774a8`. Conversion produced a 660-tensor native checkpoint with SHA256 `3d4e3936fd7bf36661de4dc56d99da1c0df90399557d747645558f4ff996d6d7`.

The installed general model importer failed with `tensorWritesFailed` for this LoRA. A separately procured [published LoRAConverter](https://github.com/kernkraft235/dt-model-helper/tree/0cee83adf0e3923794fd159ace959a3f262968d2/bundle/bin), pinned to its publisher revision, converted it with `--version z_image`; its signature/platform and resulting tensor store were inspected. The converter is a local preparation tool, not an application dependency or bundled binary. Its procurement checksum is recorded locally. Conversion and inference ran with outbound networking denied.

Weights, converter, test config and images live only in ignored `typescript/local-assets/`, `typescript/renderer.lora-test.local.json`, and `typescript/Batches/`. The test model directory uses existing local base/encoder/VAE assets and tensor-cache sidecars. Omitting the sidecars caused the renderer to rebuild its text-encoder cache; that owned attempt was stopped and retained. Reusing the existing sidecars avoided treating initialization cost as LoRA inference overhead. The active model registry was not populated with test adapters.

## Verification

Environment: macOS arm64, Darwin 25.6.0, Node 24.22.2, TypeScript 5.9.3, Electron 45.3.1, Homebrew Draw Things CLI 26.1023.0 (`--version` reports `dev`; executable identity is recorded). Native tests used Z-Image Turbo q6p, 512×512, four steps, shift 1.75, sampler 17, seed mode 2 and guidance 1.

| Check | Evidence |
| --- | --- |
| Strict build/contracts | 139 tests passed, 0 failed |
| Canvas/frozen plans | Literal append vs replacement; deterministic crop/resize/alpha policy; copied original removal; changed-hash failure; archived inputs and reopen fallback; source-preserving variants; draft tool restore; cancellation before native submission |
| Adapter contracts | Draw Things ordered files/weights/native versions/strength/flags; raw/missing/unregistered adapter rejection; ComfyUI graph/upload hash checks, model-only chain, native denoise, upload/missing-asset failure before submission, bounded frozen retry |
| Import contracts | Explicit mapping; copied PNG/raw report/native recipe; canceled saved waiting work; shortlist/reject; mapped and other-batch Favorites; escaped paths; immutable source and explicit current-renderer copies |
| Actual Swift encoder | Compiled the unchanged Swift core and emitted a report/selection using its own `JSONEncoder`; TypeScript imported the copy with `1.7500`, native LoRA version and shortlist intact; original report bytes unchanged |
| Desktop probe | Prior phase regressions plus LoRA editor/apply, current-setup text copy, canvas from viewer, append/replace preview, in-flight tool edits preserving frozen inputs, historical recipe inspection and explicit native copy |
| Native image-to-image | Baseline 34.36s; strengths 0.35/0.70 took 18.55s/30.15s. CLI reported 4/1/3 sampling steps respectively. All one attempt; original PNG preserved. Images inspected locally. Functional observations, not a general throughput claim |
| Native LoRA off/zero/on | Same complete prompt/configuration except adapter list/weight: 30.73s / 30.43s / 32.64s at off/0/0.8. Decoded off vs zero pixels identical; off vs 0.8 mean absolute RGB difference 26.51 on a 0–255 scale, proving an applied effect, not measuring style quality |
| Offline native execution | OS sandbox denied outbound network while allowing loopback; the native image-to-image and LoRA comparison jobs completed with CLI local/offline/no-download flags |
| Packaged Mac application | Build and isolated synthetic UI/host probe passed; source-only package inclusion audit excludes procured assets, configs, test batches and fixtures |
| Windows native tools | Pending actual ComfyUI/GPU tests, compatible adapter output, offline operation, image review and timing |

The checkout's original Swift `app/Batches` directory is empty. Import evidence therefore uses synthetic fixtures and an independently Swift-encoded report, not a claim that an old private production batch was found or validated. Native OS picker interaction, full application close/relaunch and Windows behavior retain owner verification.

Phase 6 contains adoption/native polish and optional fullscreen/zoom/pan behavior. No Swift retirement, model switching, cloud fallback or background download is part of this checkpoint.
