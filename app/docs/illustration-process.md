# Illustration experiment process

This document records the process developed while exploring local story illustrations and building Story Batch. It is optional background for people and agents conducting experiments, rather than an automatically loaded agent instruction file.

Current app behavior, parameters and prompt delivery are documented in the [usage guide](../README.md), [field reference](prompt-fields.md) and [renderer setup](../../README.md). Development procedures belong in [CONTRIBUTING.md](../../CONTRIBUTING.md). Those documents own the current contracts; this process document does not repeat their defaults or syntax.

## Experiment workflow

1. Establish a visual goal and a reference baseline. Separate composition, rendering style and individual defects so that an improvement in one does not conceal a regression in another.
2. State a hypothesis and vary one control while keeping the rest of the recipe fixed. Exploratory prompt overhauls can establish a new baseline, but do not isolate the effect of a single setting.
3. Screen candidates with inexpensive runs, then validate promising choices at the intended output dimensions and step count. A small or low-step preview is evidence about that recipe, not a guarantee of the finished result.
4. Compare complete images and native-resolution details. Record the outcome, limitations and next useful comparison, including failed or interrupted runs.

Manual experiments were grouped into numbered folders with prompts, configs, native outputs, logs, timings and conclusions together. Story Batch creates its own timestamped batch folders and records resolved prompts and settings per image. Benchmark originals and completed outputs are preserved; experiment data stays outside the source-control baseline.

Generation runs sequentially and fully offline. Work is bounded by the agreed launch deadline and stop requests. After an interruption, completed files and running jobs are inspected before resuming, to avoid overwriting results or duplicating expensive work.

## Reproducibility and timing

A complete recipe includes the model and quantization, expanded prompt, seed, dimensions, noise seed mode, sampler, sampling steps, guidance, shift, adapters and their weights, and any input images, crop behavior or denoising strength. Random fragments and fields are resolved before a controlled comparison; a fixed image seed alone does not freeze those choices.

Exact-repeat checks compare decoded pixels rather than compressed file bytes. Once a recipe has reproduced identical pixels, additional repeats add little unless timing variability is itself under study. A changed seed or canvas size is a new generation; matching aspect ratio or enabling Scale Alike does not establish composition preservation.

Timing records include loading, per-image wall time, total elapsed time, reported actual steps, failures and interruptions. A retry contributes to elapsed cost. Timing scatter alone does not establish a parameter's intrinsic cost, particularly on thermally constrained hardware.

## Visual review

Review dimensions separately:

- Composition, framing, pose and scene details.
- Style balance: flat illustration, modeled depth, cinematic lighting and photographic realism.
- Hair volume, distinctive color patterns, strand separation and highlights.
- Glasses, eyes, facial contours and other fine boundaries.
- Hands, fingers, clothing contours and small props; yarn and loose strands when present.

Native detail crops help distinguish improvements from display resizing. Resized previews and exaggerated difference images are labeled as such. More steps or a stronger adjustment can clarify one feature while introducing another defect.

## Findings from the original experiment set

These observations concern the tested Z-Image Turbo six-bit recipes and seed–resolution combinations. The starting setup used sampler 17, seed mode 2, guidance 1 and resolution-dependent shift off. These are historical observations, not universal model limits or current configuration requirements.

| Control | Observed outcome | Scope and limitation |
| --- | --- | --- |
| Seed and resolution | Either could dramatically change style and composition. Identical complete recipes reproduced identical pixels locally. | Scale Alike did not preserve the desired style across dimensions; final-size validation remained necessary. |
| Sampling steps | Three to four steps screened rough composition; six was a useful refined working point. | Low steps could misrepresent later style. One 512-pixel case became predictive around five to six steps. Higher counts did not consistently improve quality; the original set did not test steps one to two. |
| Shift | Values 3–6 gave useful detail variants at 1024. A 0.05 change was subtler than 0.5. | Response was nonlinear and not localized. Shift adds no sampling steps; measured timing did not establish a meaningful cost difference. |
| Shift extremes | A value of 1 was usable and sometimes improved illustration or hair treatment. Artifacts appeared at 8, especially around glasses at 512; 12 degraded tested images. | The original set did not test below 1 or at 7. These observations do not establish thresholds for other seeds, prompts or dimensions. |
| Prompt changes | Rewrites could change rendering style substantially. | Prompt revisions require a new comparison baseline rather than an assumption of scene identity. |
| Image-to-image | Strengths 0.35 and 0.65 preserved a source in one comparison; 0.78 was promising and 0.9 flattened it. | Those outcomes are source- and recipe-specific, not general recommended strengths. |
| Alternate model | One faster DreamShaper control missed scene details. | It was not a fair model ranking. |

Seed modes, guidance, samplers, quantization and conditioning tools were not systematically compared in that original set. Later model/adapter work is evaluated as a separate experiment rather than extending these findings by assumption.
