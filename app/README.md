# Story Batch

A native Mac app for sequential, private Z-Image Turbo batches. Open **dist/Story Batch.app**, edit or open a metaprompt, optionally preview its resolved values, then choose **Generate**. Each finished image appears with its filename and elapsed time; the Activity tab records the same completion message immediately. Stop Batch interrupts the current image and preserves completed work and reports. If cancellation happens before any image in the folder completes, the entire batch folder is removed.

The bottom progress area shows the active image's actual seed, shift and steps, including viewer-requested variants. These details are hidden when no image is running. The image viewer shows the same selectable recipe details for the currently viewed image; seeds have no thousands separators.

The built-in editor supports standard Undo (⌘Z) and Redo (⇧⌘Z). Opening or creating a different metaprompt clears its previous editing history.

Generation parameters have their own compact editor above the prompt. **Fields…** opens a separate, nonmodal fields window that can remain open beside the main editor. Both panels edit one saved metaprompt, so Open/Save, session restore and Open Batch retain the complete document. Find searches the prompt in the main window and the field definitions when the Fields window is active.

**⌘F** opens the editor's Find bar. Search is literal, case-insensitive, and updates as you type. All matches have faint yellow backgrounds; the active match has a stronger translucent light orange background. Use **⌘G**, **⇧⌘G**, Enter, or the Find bar's arrows to move between matches (wrapping at either end). Clicking an occurrence in the editor makes it active. **Esc** or the close button hides Find and clears the highlights. Search highlighting never changes prompt text or undo history.

Click a finished image to open a resizable preview window filling the current screen's available area, with the menu bar and Dock retained. Use **← / →** or the preview's chevrons to browse completed images in gallery order; navigation stops at either end without wrapping. Images added to the same batch become available as they finish. Each image scales proportionally to fit the current window size. **Reveal in Finder** reveals the currently viewed image file and closes the preview.

**Prompt & Parameters…** shows the viewed image's saved, fully resolved prompt and per-image parameters, with Copy Prompt, Copy Parameters and Copy All. Its full saved configuration is available when the file exists. This inspector is pinned to the image and never rerolls choices or reads the current editor draft. Missing configuration files are identified; known image parameters remain available.

## Refinement Batch

Choose **Branch as Refinement…** in an image viewer to use a completed Story Batch image as an image-to-image root, or choose **Open Image for Refinement…** for an external image. A Story Batch root inherits its exact seed, shift, steps, dimensions, and resolved prompt; an imported image starts at its nearest 64-pixel canvas size with a blank prompt. The root PNG is copied into `inputs/root.png` when the refinement batch starts, so the output folder remains self-contained.

The default prompt mode, **Add changes to source prompt**, leaves the editable instructions pane empty. It appends those instructions to the source image's exact resolved prompt P; Preview shows the final prompt that will be sent. Use **Replace source prompt** when a requested change conflicts with P. It starts an editable Q prompt copied from P. Reports record P, the selected mode, the change text or Q, the exact final prompt per image, copied image path, and strength; the mode is a user-selected provenance value and is never inferred from prompt text.

Refinement defaults to one image at strength `0.35`. Start around `0.25–0.45` for close variants; higher values increasingly reinterpret the image. Keep the inherited explicit resolution when geometry matters. Changing it applies center-cropping to retain the image canvas and can weaken composition preservation. **Exit Refinement** returns to Queue Batch mode and discards the in-app refinement draft and gallery, while retaining generated files. If a batch is running when Refinement is requested, choose whether to stop immediately, finish the current image, or remain in the batch.

Pinch/spread on the trackpad to zoom into viewer details (up to 16× the fitted view); two-finger scroll pans while zoomed. Zoom-out stops at the complete image fitting the pane. Moving between images with the same seed preserves zoom and pan for detail comparisons across shifts and steps. Changing the seed resets to full-image fit. Images without a known seed reset when changing files. This applies in the windowed and image-only full-screen viewer.

While zoomed in, moving left or right to a **different seed** needs two presses.
The first stays on the image and shows an amber “Next seed; press again to
proceed” (or “Previous seed…”) beside the arrows. The second press in that same
direction crosses the boundary. Arrow-key repeat cannot confirm it. Same-seed
navigation and navigation at full-image fit remain immediate. Zooming back to fit
or changing direction clears the pending confirmation. Full screen shows the
boundary warning temporarily over the image.

Press **F** or click the preview's Full Screen icon for image-only full screen. The image fits the screen proportionally on a black background, with viewer text and controls hidden. **← / →** still navigate without wrapping. **F** or **Esc** returns to the windowed viewer; the macOS green full-screen control also uses the same image-only mode.

The preview offers **Step 4**, **Step 6**, **Step 7**, and **Step 8** when higher than the viewed image's current step count: six-step images offer Steps 7 and 8, and seven-step images offer Step 8. These generate one new image from the exact saved expanded prompt, seed, shift, dimensions and model settings, changing only sampling steps. Fragments are not rerolled and this is a fresh generation rather than image-to-image. While a round runs, requests queue in click order after all its images; when idle, a request starts immediately. Each refinement goes into its source image's folder at the next number, with its source recorded in the report. The editor metaprompt and subsequent Queue More defaults stay unchanged. Stop Batch clears queued requests; generation failures after the automatic retry also stop the refinement queue.

Use the **Seeded / Seeded-Step / Newest** switch beside the main view tabs to set gallery and arrow-key navigation order. **Seeded** sorts by **seed → numeric shift → steps**. **Seeded-Step** sorts by **seed → steps → numeric shift**. Both ascend numerically and use image number to break ties; Images, Shortlist, Rejected and their viewer navigation share this setting. **Newest** places the latest generated image first. Filenames, numbering, reports and Collect Seeds/Shifts retain generation order.

The preview's **Shift** controls (`-1`, `-0.25`, `-0.1`, `-0.05`, `+0.05`, `+0.1`, `+0.25`, `+1`) create one variant with that offset added to the viewed image's shift. Step count, seed, expanded prompt, dimensions and other generation settings stay fixed. Decimal arithmetic preserves fine shifts without binary rounding artifacts. Bumps producing zero, negative or unsupported shifts are disabled. Shift variants use the same queue, sorted display order, numbering and reports as step refinements; the metaprompt remains untouched.

### Shortlists and favorites

Use **📌** to toggle an image in its batch’s shortlist and **🤍 / ❤️** to toggle
favorites across batches. These actions appear beside Prompt & Parameters in the
viewer and below gallery thumbnails. Hover for descriptive text. An image can
belong to both collections independently.

**Shortlist** and **Favorites** are separate tabs beside Preview, Images, Activity
and Queue. Viewer arrows stay within the selected tab; switching back to Images
restores navigation through the current batch. Removing the viewed image from
Shortlist selects the next image, or the previous image when removing the last.
Step and shift variants requested
from Shortlist are automatically shortlisted after successful generation, even if
you switch tabs while they run. Shortlist shows their running placeholder until
the completed image replaces it. Viewer arrows skip unfinished images. These
variants also remain in the main batch gallery.

Shortlist membership survives restart in
`~/Library/Application Support/StoryBatch/image-selections.json`. Favoriting instead
**copies** the image into `<batch output folder>/_favorites`. The Favorites tab
scans that directory on startup, whenever opened, and after favorite actions.
Files added or removed externally are reflected on the next scan. Same-named
images from different batches get distinct filenames without overwriting.

App-created favorites include JSON sidecars preserving the source recipe and
original batch reference, plus a saved configuration when available. The copied
image remains viewable after its original is deleted. External images without
sidecars can be viewed and removed; unavailable recipe controls are disabled.
Unfavoriting deletes only the image in `_favorites` and its app metadata, never
the batch original. Legacy in-memory/list favorite flags are no longer used for
membership. Switching batches or viewing favorites leaves the editor draft intact.

You can keep editing during generation. The running round uses a snapshot of its prompt and parameters; edits apply to the next round. The editor draft (including unfinished syntax), output folder, and last batch reference are saved automatically under `~/Library/Application Support/StoryBatch/session.json` and restored on launch. Saving a separate metaprompt file is still explicit.

**Queue More** adds another round to the current batch when the title matches, using the edited prompt, fields and parameters. When idle it starts immediately; while running it joins the queue. **New Batch** creates a fresh folder even with the same title and is disabled while generation runs. A changed title requires New Batch, so Queue More is disabled until a batch with that title is started. Queued rounds and viewer variants run in request order, one image at a time. Random seeds, shifts and expanded prompts are frozen when queued; later edits do not change waiting work.

Waiting images have **↑**, **↓**, and **⏭ Run next** controls (hover for descriptions).
Reorder individual images across current-round, queued-round, and viewer-variant
boundaries. Run next places the image immediately after the running one; it does
not interrupt that render. Frozen prompts, seed/shift pairings, image inputs and
per-request collection remain intact. Output image numbers are assigned in the
resulting execution order; queued filename numbers can therefore change.

**Skip** on the running image in Queue cancels only that image and continues the remaining round and future jobs. The attempt is recorded as skipped with its timing and logs, and its number stays reserved. Skipped images stay out of the galleries. **Stop Batch** still cancels the whole queue.

The **Queue** tab (also available from the bottom Queue button) lists the running image and every waiting image, including the remainder of the current round. Each waiting job shows dimensions, seed, shift and steps and has **Remove** to cancel just that job before it starts. Removing a seed/shift-list entry does not shift the remaining pairings. A removed job in a started round is recorded as skipped and reserves its image number; skipped jobs do not appear in the image gallery. Removing every image in a future round removes that round entirely. **Stop Batch** cancels the active image and clears all waiting work. Generation failures after the automatic retry also clear waiting work. Waiting queues are session-only and are not restored after closing the app.

Use **Open Batch…** in the top bar or **⇧⌘O** to select a previous batch folder. It restores the latest used metaprompt from that batch's report and opens its images in the Images pane, retaining sorted variants and viewer navigation. **Queue More** continues that folder's numbering and uses the restored parameters. Opening is disabled while a round is running; finish or stop it first. Invalid folders show feedback without replacing the current draft or gallery. Opening a batch starts no generation and leaves saved outputs untouched. The selected batch becomes the one restored on the next app launch.

Batch continuity follows the title, regardless of prompt wording, whitespace, field definitions, or variable placement. An omitted title retains the current batch title. Numbering follows the highest prior attempt, including canceled/failed attempts. This works after reopening, provided the folder still exists; interrupted rounds are not resumed automatically. New Batch is the explicit way to split a study without renaming it.

## Metaprompt files

Put parameters on **one first line**, separated by semicolons. The newline starts the prompt. A blank first line uses all defaults.

The UI displays the parameter line separately. Optional named definitions follow a reserved standalone `%%FIELDS%%` line after the prompt. Legacy files without that section still work.

```text
title=happy cafe scene; seed=1234; shift=4.5501; steps=5; aspect=1:1; count=4; notes="soft light; good hair"
A richly shaded story illustration. The apple is {red:::2|green:::3|red with a {worm|caterpillar}:::0.5}.
```

| Parameter | Default | Meaning |
| --- | --- | --- |
| title | Epoch seconds when the batch is prepared | Image filename prefix and report title |
| seed | Independent random integer 0–2147483647 per image | One number applies to all; a comma-separated list supplies one entry per image; `_` means random |
| shift | Independent random 1.500–2.250 per image | Fixed value, random range (`4.2..4.8`), or ordered list (`2,3.5,4.55`) |
| steps | 3 | Positive integer sampling steps |
| resolution | 1024*1024 when neither sizing key is present | Exact width and height, positive multiples of 64; cannot accompany aspect |
| aspect | Unset | Preferred for new compositions: positive integer width:height ratio, automatically sized within pixel_max |
| pixel_max | 1048576 | Maximum width × height; positive whole-number arithmetic such as (1024*1024) |
| count | 4 | Positive number of images, generated sequentially |
| notes | Empty | Recorded for you; never sent to the model |

Only the listed keys and the `seeds` alias for `seed` are accepted. Unknown or duplicate keys are errors, including specifying both `seed` and `seeds`. Quote values containing semicolons; values can contain `=`. Quoted values support escaped quotes and backslashes. Huge dimensions and step counts may be syntactically valid but impractical on this Mac; the defaults are the tested operating range.

### Aspect and pixel budget

Prefer `aspect` for new compositions; use `resolution` to reproduce exact saved dimensions. They are mutually exclusive. Equivalent ratios are reduced before sizing: `aspect=9:7` and `aspect=18:14` both select **1152×896** with the default cap. Sizing chooses the largest exact-ratio pair with both dimensions multiples of 64. It never approximates the ratio to fill more pixels, so `aspect=16:9` gives **1024×576**, leaving some budget unused. A ratio whose smallest grid-compatible size exceeds the cap produces an error.

`pixel_max=(2048*2048)` raises the cap; for example, `aspect=9:7` then gives **2304×1792**. The cap accepts scalar decimal arithmetic (`+`, `-`, `*`, `/`, parentheses), with a final positive whole-number result. Explicit resolutions above the cap are rejected, as is the default 1024×1024 if you lower the cap alone. For automatic smaller square sizing, use `aspect=1:1; pixel_max=(512*512)`. Existing larger batches remain viewable; their unchanged drafts require an explicit higher cap before new generation.

### Preparing content for the UI

Content prepared for Story Batch is delivered in separate fenced `text` blocks in this order: **parameters**, **fields**, **prompt**. Parameters occupy one semicolon-delimited line. Fields contain raw `NAME=value` definitions; the prompt contains illustration text and references. The portable-file `%%FIELDS%%` marker is not included in these UI blocks.

Include all three blocks by default. The fields block may be omitted only when its definitions are unchanged from the previous run by the same author or agent; uncertain continuity means including the complete definitions. Omission retains existing fields. Explicitly clear obsolete definitions when removal is intended.

### Shift values and lists

`shift=4.2..4.8` independently samples a shift per image from the inclusive range, uniformly over values at three decimal places. Bounds must be positive and ordered. Bounds with finer precision are rounded inward to the nearest thousandths, keeping every result within the requested range. A range containing no thousandth is an error; use a fixed value for finer precision. Both requested bounds and each chosen shift are retained in the JSON report.

`shift=2,3.5,4.550123; count=3` uses those three shifts in order, one per image. The number of values must exactly equal `count` (which defaults to 4 when omitted). A count mismatch, empty entry or invalid number blocks generation and explains the reason in the editor feedback. Lists may also contain ranges, with a final `range*` filling the remainder as described below. Duplicates are allowed; supplied decimal precision is retained. **Queue More** repeats the list from its first value while continuing image numbering. Use a fixed seed and a prompt without random fragments for a controlled shift sweep. Viewer step/shift variants keep their single chosen shift and do not consume entries from the list.

Shift values also accept decimal arithmetic: `+`, `-`, `*`, `/`, parentheses, and scientific notation, with ordinary precedence. For example, `count=4; shift=2.25+0.5,2.25+0.5,2.4-0.1,2.1+2` resolves to `2.75,2.75,2.3,4.1`. A scalar expression applies across the round; expressions can also be used for range endpoints, such as `(2+0.25)..(3-0.5)`. Every final shift must remain positive and supported by Draw Things. Invalid syntax, division by zero and numeric overflow block generation with feedback identifying the list item when applicable. Expressions use finite-precision decimal arithmetic, not executable code; repeating divisions are rounded to decimal precision. The source metaprompt retains the expression, while filenames, previews, queue entries, configurations and per-image recipes use the evaluated number. Plain numeric overrides still retain their supplied decimal spelling.

Wrapping a shift list applies arithmetic to every member: `shift=(2.25,2.25,2.4,2.1)+0.5` and `shift=0.5+(2.25,2.25,2.4,2.1)` both produce `2.75,2.75,2.9,2.6`. Inner math resolves first, so `(2.25+0.5,2.4-0.1)*2` gives `5.5,4.6`. Scalars work on either side, preserving subtraction/division order. Two lists used together combine by position and must have equal lengths. The final expanded list must still match count.

**Collect Seeds** and **Collect Shifts** below the editor toolbar replace or append the relevant parameter using completed images from the latest run, in generation order. Collect Seeds writes `seeds=...` (a supported alias for `seed`) and replaces either spelling without creating duplicates. Collect Shifts writes the actual numeric shifts, including values drawn from custom/default ranges. Other parameters, count, notes and the prompt body are retained. The buttons become available when generation is idle and at least one image completed. A viewer variant counts as its own one-image run; after partial/canceled runs only completed images are collected. If a multi-value collection differs from the current count, normal validation explains the mismatch. Run identifiers preserve exact latest-run collection after reload; pre-upgrade reports fall back to the latest recorded request's count.

`seed=1234,_,_; shift=2,3.5,4.55; count=3` pairs entries by position: shift 2 with seed 1234, shift 3.5 with a random seed, and shift 4.55 with another independently drawn random seed. Seed lists must contain exactly `count` entries unless the final entry is `_*`, which fills every remaining slot with an independent random seed: `seed=1234,_*; count=4` keeps seed 1234 first and generates three random seeds. `seed=_*` makes the entire round random. The marker is allowed only at the end; entries before it cannot exceed count (an empty remainder is valid). Shift lists require exactly `count` entries unless a final `range*` fills the remainder. They may mix fixed values and independently sampled ranges: `shift=1.3,2.4,1.3..1.4,1.3..2.0*; count=6` uses 1.3, then 2.4, then one random value from 1.3–1.4, then three independent random values from 1.3–2.0. Ranges sample inclusive thousandths. Only the final range may carry the trailing `*`; preceding entries cannot exceed count, and an empty remainder is valid. Each new round samples ranges again; previews and queued recipes retain their chosen values. Each numeric seed must be an integer from 0 to 2147483647; `_` is allowed for seeds only. A single numeric seed or single shift applies across the whole round. Omitted seed or `seed=_` means random independently per image. Generate More repeats fixed entries and draws fresh seeds for placeholders; previewed seeds are reused exactly when Generate is pressed. Reports store the actual chosen seeds. Viewer variants keep the source image's actual seed.

Fragments choose one alternative at random:

- `{a|b|c}` gives equal weights. Repeated terms retain their individual chances.
- `{red:::2|green:::3|red with a {worm|caterpillar}:::0.5}` uses relative weights. Worm/caterpillar is chosen only when its containing term wins.
- `{a||b}` includes an empty alternative. `{one}` becomes `one`; `{}` becomes empty.
- Weights default to 1, must be finite and nonnegative, and need one positive alternative per nonempty fragment.
- Escape literal braces, bars, colons or backslashes with `\`. Other text, whitespace and newlines are preserved. No language model rewrites your prompt.
- Every branch is checked before starting. Unclosed or malformed fragments abort the whole batch, even inside an alternative that might not be selected. Maximum nesting is 256.

Seed controls image noise, **not fragment selection**. Fixed seed and shift still allow different expanded prompts. Use Preview to inspect the first four images; Generate uses exactly those previews. Remaining images are resolved when the round is queued so the Queue tab shows their actual recipes. Reroll Preview intentionally chooses new random values.

### Named fields and consistent references

```text
title=matching colors; count=4; steps=3
She wears a [COLOR] blouse and matching [COLOR] ribbon. She is [EXPRESSION].
Two cups are [CUP_COLOR*] and [CUP_COLOR*]. [DESCRIPTION]
%%FIELDS%%
COLOR={maroon|deep green:::2|blue}
EXPRESSION={smiling|thoughtful|looking at a {book|cup}}
CUP_COLOR={white|cream|blue}
DESCRIPTION=Soft window light models her face.
Her hair catches a warm rim light.
```

- `[NAME]` resolves that field once **per image**, caching the entire final string, including selected nested choices and references. Repeated occurrences reuse it exactly.
- `[NAME*]` resolves fresh at each occurrence. It may happen to choose the same result. Fresh uses do not seed or overwrite that field's shared cache.
- Every image starts with an empty cache. Fixed image seeds do not freeze field randomness; exact expanded prompts are retained in image recipes.
- Fields can contain weighted/nested fragments, multiline text, and shared/fresh references to other fields. Forward references work. Names are case-sensitive ASCII letters/digits/underscores, starting with a letter or underscore.
- Start each `NAME=` definition at the left margin. Following lines belong to that field until the next definition. Whitespace around a whole value is trimmed; internal newlines are retained. Empty values are valid. Indent a continuation line if its literal text resembles another definition.
- Duplicate/undefined fields, cycles and malformed fragments are rejected before generation, including in unused fields or unselected branches. Field nesting is limited to 64 and expanded output to 1 MB.
- Escape literal square brackets with a backslash. The standalone `%%FIELDS%%` marker is reserved and is not sent to the model.
- **Extract Choices** moves each outer inline fragment into a unique `FIELD_1`, `FIELD_2`, … definition and inserts a shared reference. Nested syntax stays together and existing names are skipped. Initially each new field is used once, preserving independent choices and random-draw order. Rename fields/references afterward if desired.
- Parameters and fields remain editable during generation. Queued plans retain their frozen expanded prompts. Step/shift variants reuse the source image's exact resolved prompt.

## Outputs

**Stop After This Image**, beside **Stop Batch**, finishes and saves the current
image, clears all waiting images (including queued rounds and viewer variants),
and returns to idle. During preparation it lets the first image finish. While
finishing, adding jobs is disabled; **Stop Batch** remains available to interrupt
immediately. Completed images and reports are retained, and **Queue More**
can continue the same batch afterward.

Each **New Batch** creates a unique timestamped folder in `app/Batches` (change it in Settings). Queue More reuses the current folder while its title stays the same, including prompt and field overhauls. Changing the title requires a fresh folder; existing folders and images are preserved. Images are named:

```text
{title}_{seed}_{steps}_{shift}_{image number}.png
```

Image numbering starts at 1 and continues across rounds in the folder. Spaces remain; path separators, colons and control characters are replaced. Very long titles are shortened for filesystem limits; full titles remain in the report. Existing images are never overwritten.

Every folder contains the latest metaprompt, expanded prompt and exact configuration per image, CLI logs, an append-only `events.jsonl`, and timestamped JSON and Markdown reports. Reports exist **before the first image** and update after every completion, failure or cancellation. Each image records wall time, CLI generation time including loading when available, actual steps when reported, filename, full prompt, parameters, command and exit code. The JSON report retains each image's source metaprompt and request parameters, preserving earlier rounds when the header changes. Report-level parameters describe the latest regular round; viewer refinements leave those defaults unchanged. A crash or power loss can leave the last image marked running; completed records remain saved. The app does not resume interrupted batches automatically.

Explicit shift text is retained without rounding in the filename/report/configuration. Draw Things ultimately consumes floating-point values, so differences smaller than its Float32 precision cannot affect generation.

## Local renderer configuration

Requires a locally installed `draw-things-cli` and a compatible imported model with all of its dependencies. Copy `renderer.example.json` to `renderer.local.json` beside this app README, then set `executablePath` and the `recipe`. See the [repository setup guide](../README.md). Settings saves executable changes to that ignored file; restart after editing model/LoRA settings. `STORYBATCH_CONFIG` can select another local config file. Settings also lets you choose the output folder. The app does not download models. It invokes the CLI directly, without a shell, using `--local --offline --no-download-missing`.

The included starting preset is Z-Image Turbo q6p with UniPC Trailing sampler 17, Scale Alike seed mode 2, guidance 1 and resolution-dependent shift off. These settings are configurable, not universal recommendations for other models. LoRAs are an optional list of Draw Things imported identifiers and weights in the local recipe. New plans capture the recipe, viewer step/shift variants retain the source recipe, and older reports without a recipe retain the original preset. Every image saves its actual configuration. Generation stays one image per invocation, offline, with no ControlNet/refiner/upscaler. Style may change substantially with resolution even at the same seed.

## Build and checks

Requires Apple Silicon macOS 13+ and Apple Command Line Tools. No external packages or network are needed.

```sh
./app/build.sh
./app/test.sh
```

The build creates `app/dist/Story Batch.app` with a local ad hoc signature. It embeds the build workspace as the initial output location. It does not install to Applications. The direct compiler scripts work with Command Line Tools alone; `Package.swift` additionally supports ordinary SwiftPM/XCTest development with a matching Xcode installation.

Checks cover defaults, header validation, nested weighted distributions, empty/duplicate/lazy branches, malformed syntax, decimal preservation, seed/shift ranges, safe filenames, sequential execution, preview reuse, reports, completion timing and cancellation. Fake CLI fixtures are confined to temporary test folders.

Failed renders automatically retry **once**, using the exact same resolved prompt, seed, configuration and image input. Activity announces the retry, the image log retains both attempts, reports record the attempt count, and elapsed time includes both attempts. Failed output is preserved under `logs/*.attempt-1.png` before retrying. Invalid metaprompts/configuration formulas fail validation before rendering; process-launch errors, Stop and Skip are not retried. A second render failure stops the queue with the saved error.

The image viewer also offers an **Absolute shift** box and **Queue Shift** button (or Return). Enter a number above zero with at most three decimal places, such as `1.875`. This queues one variant using the viewed image’s saved resolved prompt, seed, steps and dimensions, or starts it immediately when idle. It follows the same queue and shortlist behavior as shift bumps; the editor draft stays unchanged. Clicking outside the shift box or successfully submitting it ends editing and restores image arrow-key navigation.

**Reject** (🚫), beside Shortlist and Favorite, hides an image from its batch’s **Images** gallery and viewer navigation. **Rejected**, after Favorites, shows rejected images for the current batch; ↩️ restores one to Images. Rejection is saved across restarts and does not delete or modify images, prompts, configurations or reports. Shortlist membership and favorite copies remain independent. Rejected images retain the selected Seeded/Seeded-Step/Newest ordering. Selection buttons remain visible but disabled while rendering.

The single-image viewer has an **Image order** menu beside its navigation arrows (Images, Shortlist and Rejected). Switching between Seeded, Seeded-Step and Newest keeps the current image and zoom/pan, updates the position counter, and changes arrow navigation to the new order. It shares the gallery’s ordering setting.

For the experiment workflow and scoped historical findings behind these features, see [Illustration experiment process](docs/illustration-process.md).
