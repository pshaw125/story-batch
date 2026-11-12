# Draw Things and ComfyUI compatibility

Planning decision recorded 2026-11-11. The shipped app still uses Draw Things CLI. This review is based on source inspection, not completed ComfyUI integration or GPU benchmarking.

## Accepted boundary

Identical seed–dimension–step–shift combinations may produce different images across platforms/frameworks. This is accepted. Recreating Scale Alike, emulating exact UniPC Trailing behavior, and matching historical Mac pixels are not migration requirements.

The portable product contract is resolved inputs, native applied settings, viable images, offline operation and complete provenance. Moving a recipe to another backend creates an explicitly different recipe rather than claiming exact reproduction.

## Parameter mapping

| Control | Translation | Decision |
| --- | --- | --- |
| Title, notes, count, batch identity | Application-owned | Keep existing semantics; submit one image at a time. |
| Fields, fragments, seed/shift lists, ranges, arithmetic and remainder markers | Resolve in shared TypeScript code before submission | Backend receives the final text and chosen numeric values, not Story Batch syntax. |
| Aspect and pixel cap | Resolve to exact dimensions in shared code | Preserve the existing 64-pixel grid contract. |
| Resolved prompt | Pass literal text into native Z-Image text conditioning | Record encoder identity/precision and processing. Equal strings do not guarantee equal embeddings. |
| Seed | Pass the supported integer to the native noise generator | The number transfers, its image identity does not. |
| Seed mode / Scale Alike | Use each backend's native noise layout | No Scale Alike emulation required. |
| Steps | Configure native sampling count | Effective schedule, evaluations and image-to-image work can differ. Record actual work when available. |
| Shift | Configure the compatible native Z-Image flow-shift control | Inspected implementations use the same rational shift transform. Overall visual response may differ because other recipe components differ. |
| Sampler and schedule | Preserve native settings separately | Draw Things sampler 17 is not a portable identifier. ComfyUI records solver and scheduler; exact UniPC Trailing emulation is unnecessary. |
| Guidance | Configure native CFG/text guidance for the model | Retain the requested and applied values; presets remain backend-specific. |
| Resolution-dependent shift | Baseline uses an explicit fixed shift with automatic adjustment off | Adding an automatic policy requires a named implementation; it is outside the minimum baseline. |
| Model, text encoder, VAE and quantization | Select compatible local components and loaders | Begin with Z-Image Turbo on both backends. Do not assume a Draw Things q6p checkpoint loads directly in ComfyUI. |
| LoRAs | Select compatible adapters and native weights | Retain model/encoder strength distinctions when relevant. Converted Draw Things files and metadata are not assumed portable. |
| Input images and crop | Explicitly load/preprocess/encode the saved input | Preserve source identity and record resize/crop behavior rather than relying on implicit canvas/reference defaults. |
| Image-to-image strength | Use native strength/denoise semantics | Equal values need not mean equal edits or equal step counts. This is independent of LoRA weight. |
| Disabled refiner/upscaler/control/cache features | Omit optional stages from the baseline local workflow | Unused settings need no invented matching flags. Future features require separate capability tests. |
| Offline execution | CLI offline/local flags versus an installed local-only ComfyUI workflow | The invariant is no external-network dependence after procurement, not identical launch flags. |

## Terms behind the differences

Scale Alike rearranges seed-generated starting noise in nested squares. It does not lock scene identity. Native ComfyUI noise can replace it under the accepted cross-backend variability policy.

A sampler determines how the latent image is updated while noise is removed. A schedule determines which noise levels are visited. UniPC Trailing combines those choices in a Draw Things setting; ComfyUI represents related choices separately. Six steps can visit different levels, with different details, without losing the shared six-step control.

Image-to-image strength determines departure from an input image. Low strength usually preserves more of the source; high strength allows greater reinterpretation. Native schedule truncation and step counts differ. A LoRA changes the model through adapter weights and can be applied without an input image. Its weight is a separate scalar.

## Required run provenance

OS name/version/architecture and renderer framework/version are required run details. Each image references its run context and saves its immutable effective recipe. Where obtainable, also record:

- GPU/memory, driver and compute-runtime versions.
- Model, encoder, VAE and adapter identities, precision/quantization and hashes or stable revisions.
- ComfyUI workflow identity/version and required node versions, or Draw Things CLI version/configuration.
- Native sampler, scheduler/noise policy, seed, dimensions, steps, guidance, shift, preprocessing and input/adapter strengths.
- Output identity, elapsed timing, attempts, failures and interruptions.

Optional unknown details are marked unknown. Private absolute paths are not substitutes for asset identity. Exact-repeat behavior is evaluated within a pinned backend environment; cross-backend image equality is not an acceptance test.

## Remaining proof

Verify the chosen installed workflow applies each exposed control; prove generation without external networking after procurement; inspect actual Windows Z-Image outputs; and exercise cancellation, repeat behavior and bounded recovery. Resolve uncertain job status before retrying a disconnected API request, to avoid duplicate renders. Image-to-image and LoRAs have their own tests and do not block basic text-to-image batches.

## Primary references

Reviewed 2026-11-11; implementation must pin installed versions because upstream branches change.

- [Draw Things flow shift](https://github.com/drawthingsai/draw-things-community/blob/main/Libraries/SwiftDiffusion/Sources/Denoiser.swift) and [ComfyUI flow sampling](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy/model_sampling.py).
- [Draw Things noise/sampler selection](https://github.com/drawthingsai/draw-things-community/blob/main/Libraries/LocalImageGenerator/Sources/LocalImageGenerator.swift) and [ComfyUI noise](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy/sample.py).
- [Draw Things UniPC](https://github.com/drawthingsai/draw-things-community/blob/main/Libraries/SwiftDiffusion/Sources/Samplers/UniPCSampler.swift), [ComfyUI schedules](https://github.com/Comfy-Org/ComfyUI/blob/master/comfy/samplers.py) and [native nodes](https://github.com/Comfy-Org/ComfyUI/blob/master/nodes.py).
- [Official Z-Image Turbo guide](https://docs.comfy.org/tutorials/image/z-image/z-image-turbo), [local API](https://docs.comfy.org/development/comfyui-server/comms_routes) and [execution messages](https://docs.comfy.org/development/comfyui-server/comms_messages).
