# Prompt fields implementation handoff

The single persisted AppModel.source remains the source of truth. The UI
projects it into header, template and field definitions via PromptDocument;
old combined files and report/session Codable schemas remain readable.
Transport: first-line header, newline/template, optional standalone
%%FIELDS%%, then column-one NAME= multiline definitions.

PromptNode.field(name, fresh:) extends the fragment AST. Compilation parses all
definitions, validates references/cycles even in unused branches, and bounds
expansion/dependency depth. Resolution is lazy in prompt order; one dictionary
per image caches complete shared resolutions. Fresh references bypass that
field's cache; nested references obey their own mode. This preserves selected
branch RNG behaviour and exact shared parent strings.

Batch continuity follows the compiled title, including inherited titles when the
header omits one. Prompt text and field changes do not split a batch. Queue More
continues the current folder; New Batch forces a fresh folder and is disabled
while running. PreparedBatch and BatchRunner enforce matching titles at prepare,
rebase and execution boundaries. Queued plans freeze expanded prompts on enqueue;
per-image source snapshots preserve each run's own definitions. The old
samePromptBody helper remains a structural comparison utility only.

ImageRecord.displayOrder sorts gallery and viewer records by numeric seed, steps,
and numeric shift, with image number as tie-breaker. Reports remain in generation
order, preserving usage-order collection.

## Image refinement handoff

PreparedBatch can carry an input image, strength, crop flag and RefinementContext.
BatchRunner copies the root into `inputs/root.<extension>` once per output folder,
passes it as `--image` with explicit `--strength` (and `--crop` only if canvas
dimensions differ), and records both per-image input fields and exact prompt
provenance, with a report-level latest-context summary. ImagePlan configuration JSON accepts the strength separately;
regular text-to-image remains at strength 1.

AppModel holds RefinementRoot separately from the generated metaprompt. Append
mode exposes a blank editable delta while compiling the root's exact resolved P
plus the delta; full-override mode exposes Q, initially copied from P. The final
source remains normal PromptDocument text, so existing fragment/field compilation
and frozen queue behavior still apply. QueueModeSnapshot restores the previous
normal editor on Exit Refinement without removing generated refinement folders.

Extract Choices validates first, scans balanced outer ranges with escapes,
preserves raw nested syntax, allocates unused FIELD_N names, and replaces each
range with a reference. RNG equivalence tests protect previous behaviour and
folder continuity.

The nonmodal Fields window has separate NSTextView/undo/search state and local
Cmd-F/G shortcuts. Header and prompt editors remain in the main window. All
changes persist in the combined document. The viewer's pinned recipe sheet
uses the selected record's expanded prompt and actual values, with its saved
configuration read only inside the batch folder. Missing config files are
labelled; defaults are not invented as historical settings. Viewer navigation
and fullscreen shortcuts yield to an attached sheet.

Tests cover shared/fresh/global nested semantics, per-image cache reset, lazy
draw counts, multiline/forward/empty fields, missing/duplicate fields, cycles,
output/depth bounds, extraction RNG equivalence, continuation/frozen queues,
split editor changes, session/reload and historical recipes. Build/test with
app/build.sh and app/test.sh; no GPU runs are needed.
