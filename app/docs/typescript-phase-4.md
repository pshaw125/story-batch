# Phase 4 — daily iteration and collections

Recorded 2026-11-12. Phase 3 is committed/pushed as `fa2709e`. Phase 4 implements the shared daily iteration workflow; Mac synthetic/core/UI/package verification is recorded below. Windows execution and real iteration acceptance remain pending. Swift data and the native renderer algorithms/settings are unchanged.

## Delivered

- Individual frozen waiting jobs with Up/Down/⏭ Run Next, removal, guarded Skip current and Stop After Current. Reordering preserves pairings, IDs and reserved filenames; execution index and start/finish timestamps are separate from numbering and gallery order. Stop After clears existing waiting work and permits subsequent explicit requests.
- Collect Seeds/Shifts from completed images in the latest executed logical request, in execution order. One-image variants form separate requests. Canceled/failed images are excluded. The collector replaces seed aliases without altering prompt/fields; `count` remains an explicit user choice and normal list-count validation applies.
- Native editor find with Cmd/Ctrl+F, next/previous shortcuts, match count, faint yellow highlights and a stronger orange active match across parameters, prompt and fields. Non-destructive mirror layers preserve native editor undo/caret behavior; clicking a match selects its active highlight. Search opens collapsed fields when needed.
- Atomic debounced draft/view/session persistence, including unfinished invalid text. Normal closure flushes the latest draft and waits for cancellation. Last-batch restore is inspection-only; saved queue work never resumes. Corrupt session data is reported and backed up before replacement.
- Shared numeric Seeded (seed/shift/steps), Seeded-Step (seed/steps/shift) and Newest ordering in galleries and viewer. Mode changes retain selected image identity. Shortlist/Favorites/Rejected have scoped completed-image navigation; removing a selected item advances adjacent, falling back to previous at the end.
- Independent persistent batch shortlist/rejection flags with Restore. Reject never deletes artwork or recipes. Shortlist-derived variants are flagged before rendering and appear as correctly proportioned running placeholders. Selection mutations are separate from renderer record updates.
- Directory-backed Favorites under the selected output root. Copies include recipe/environment/source sidecars; external supported image additions/removals are rescanned at startup, view entry or Refresh. Sidecar hashes verify the copied artwork before attributing a recipe. Unknown metadata stays unknown with unavailable recipe controls. Cross-batch actions require opening the source batch. Copied artwork/recipes remain inspectable without the original folder. Unfavoriting archives the copy; it does not remove original artwork.
- Newly created, fully canceled batches with no output/extra files have their report archived under `.attempts/cancelled-batches/` before removing the empty folder. Loaded/existing data is never auto-cleaned.

## Evidence

Environment: macOS arm64, Darwin 25.6.0, Node 24.22.2, TypeScript 5.9.3, Electron 45.3.1. No new dependency/model procurement or GPU generation was needed for these workflow changes.

| Check | Result |
| --- | --- |
| Strict build and automated contracts | 124 tests passed, 0 failed |
| Queue contracts | Actual reordered execution/collection order; preserved frozen list pairs; waiting removal without render; guarded skip with next job completion; Stop After and explicit continuation; canceled empty-folder cleanup with diagnostic retention |
| Collections/storage | Independent shortlist/reject; shortlist variant placeholders/membership through completion/reload; copied Favorite bytes/recipe; external additions/removals; unknown metadata; source-batch reopening; original preservation; copied Favorite readable after source removal |
| Draft and sorting contracts | Invalid draft and view state persistence; corrupt-file backup; numeric three-mode ordering and filtering; parameter collection preserving fields/prompt |
| Electron UI probe | Preview/batches/frozen edits/variants/undo regression checks plus actual queue reordering/removal, Stop After, shortlist adjacency/variants, reject/restore, file Favorites/external refresh, selected-image retention during sort, search count/highlight layout, collectors, durable draft and page reload without resume |
| Packaged Mac app | Unpacked darwin-arm64 build and the same isolated synthetic UI/host probe passed; no private data or local renderer configuration in package |
| Visual inspection | Synthetic gallery/editor/search screenshots inspected; fixed a stylesheet media-rule boundary uncovered by inspection |
| Windows execution and native iteration | Pending Windows tests and owner iteration with actual ComfyUI images. Mac/synthetic checks do not pass the Windows gate |

The probe uses temporary application data and synthetic images; normal app data and ongoing user runs are not restarted. Draft store reconstruction and UI page reload are automated; full OS relaunch/window close and native menu/picker behavior also merit owner checks on each platform.

## Remaining gates and scope

On Windows run `npm test` and `npm run host:probe`, then exercise a real iteration session with paired lists, reordered/skipped/canceled jobs, Stop After, collectors, shortlist-derived variants, external Favorites changes, reject/restore and viewer sorting. Close/reopen with an unfinished draft and verify that no waiting work resumes. Review copied provenance and original-file preservation.

Phase 5 covers Swift batch/collection import, compatible LoRAs and image-to-image. Phase 6 covers adoption/native polish, fullscreen and optional zoom/pan/seed-boundary behavior. This checkpoint does not retire Swift or establish Windows quality/performance/offline-inference evidence.
