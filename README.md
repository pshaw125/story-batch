# Story Batch

A native macOS app for sequential, fully offline image batches through **Draw Things CLI**. It provides weighted prompt fragments and reusable fields, frozen generation queues, image inspection, step/shift variants, image-to-image refinement, and batch collections.

This repository contains the application, tests and documentation. Personal prompts, fields, batches, reference images, model/LoRA weights, renderer paths, build products and experiment archives stay local and are ignored by Git.

## Build and run (macOS)

Requires macOS 13 or newer, a compatible Swift toolchain/Command Line Tools, and a separately installed Draw Things CLI with a model and all required encoders/VAEs already available locally. The application does not download dependencies or models.

```sh
cp app/renderer.example.json app/renderer.local.json
# Edit app/renderer.local.json: set your Draw Things CLI path and recipe.
bash app/test.sh
bash app/build.sh
open "app/dist/Story Batch.app"
```

`app/renderer.local.json` is ignored. Set `executablePath` to the absolute path of your `draw-things-cli`. The example recipe preserves the original tested Z-Image Turbo q6p defaults; you may replace its model identifier, sampler, seed mode, guidance and resolution-dependent shift to suit another **Draw Things-compatible** imported model. Choose appropriate steps/shift in generation parameters; the example's settings are not recommendations for every model.

Optional LoRAs use Draw Things' imported identifiers, for example:

```json
"loras": [{ "file": "my-imported-style-lora.ckpt", "weight": 0.4 }]
```

Import/convert compatible adapters into Draw Things separately. For unregistered local LoRAs, the installed CLI also supports an optional `version` property identifying the correct architecture; use the value documented for your adapter/CLI, rather than guessing. `DRAWTHINGS_MODELS_DIR` can select your local model store in the app launch environment. Copying a third-party `.safetensors` filename into this list does not establish import or architecture compatibility. This repository distributes no models, adapters or reference images and does not grant rights to external assets.

Settings saves executable-path changes to the local config. Restart after manually editing its recipe. If absent, the app creates a starting config using CLI discovery from `STORYBATCH_CLI`/`PATH`; otherwise use Settings to select the executable. `STORYBATCH_CONFIG` can point to a different config file (set it in the app's launch environment). Malformed config is reported and blocks generation instead of silently being replaced. For an installed/copied app, use the explicit environment override if its build-workspace config is unavailable.

Each new image plan records its recipe; queued images and viewer variants retain it even after defaults change. Saved configuration JSON records the actual model and adapters. Legacy batches without an embedded recipe use the original Z-Image Turbo preset. Rendering always invokes Draw Things directly with `--local --offline --no-download-missing`.

## Local data and source control

Default outputs are under `app/Batches/`; the output folder can be changed in Settings. Drafts, fields, batch references, shortlist and rejection flags live outside this checkout in macOS Application Support. Favorites are copied into the selected output root's `_favorites` directory. Treat saved batches as private: their reports contain resolved prompts, model/adapter identifiers, commands and local paths.

The root `.gitignore` includes only approved source directories/files and also excludes media, archives, weights, local configs, logs and runtime state. `app/examples/` and private experiment archives are intentionally excluded. The general experiment process is documented separately from app usage. Synthetic prompts in tests and syntax examples in documentation are source fixtures, not a personal prompt library. Avoid `git add -f` for local assets; inspect every proposed commit. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation and platform scope

- [App usage and parameter reference](app/README.md)
- [Prompt fields](app/docs/prompt-fields.md)
- [Aspect sizing](app/docs/aspect-sizing.md)
- [Implementation and verification](app/docs/implementation.md)
- [Illustration experiment process and historical findings](app/docs/illustration-process.md)
- [TypeScript migration plan](app/docs/typescript-migration-plan.md)
- [Draw Things / ComfyUI parameter compatibility](app/docs/renderer-compatibility.md)

The UI, build scripts and process termination are currently macOS-specific. The renderer recipe is separate from app state, but a Windows UI/backend/CLI integration still needs design and implementation. This checkout is **not yet Windows-compatible**.
