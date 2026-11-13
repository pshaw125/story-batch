# Phase 6 — image inspection controls

Recorded 2026-11-12. Phase 5 is committed locally as `4fbac65`. This checkpoint implements the agreed viewer subset: fullscreen, pinch/mouse zoom and pan, same-seed viewport retention and seed-boundary confirmation. It does not mark the entire platform-adoption phase complete.

## Controls and behavior

- Ctrl+wheel and Alt/Option+wheel zoom around the pointer. Left/middle drag pan; Space+left drag works as the same hand interaction. Unmodified wheel pans vertically; Shift+wheel pans horizontally. Image changes remain on arrows/buttons.
- Regular `+`, `=`, `-`, **numpad Add/Subtract**, visible +/− buttons and `0`/Fit work without modifiers. Key handling recognizes both physical numpad codes and ordinary/legacy key values. Inputs, selectors and the recipe dialog keep their keyboard behavior.
- Fit is the minimum; maximum zoom is 16× fit. Aspect ratio is preserved. Panning is bounded, and axes that still fit remain centered. Zoom percentages are relative to fit. Cursor anchoring respects those bounds; fractional layout/event coordinates are retained rather than rounded to whole pixels.
- One active viewport stores normalized focus, so same-seed shifts/steps/dimensions and sorting retain inspection state. A confirmed seed change resets to fit. Reopening or returning to an earlier seed starts at fit; there is no per-seed memory. Different unknown-seed images reset by identity.
- While zoomed, crossing a known seed boundary requires two fresh presses/clicks for the same source, target and direction. Key repeats cannot confirm. Fit, selection/scope/sort changes or a changed adjacent target clear stale confirmation. Nonwrapping navigation and collection-scoped image lists remain intact.
- F/button requests native fullscreen and hides all viewer chrome. The image fills available space while retaining aspect ratio, with the seed warning as the sole text overlay when needed. Arrows, mouse/keyboard zoom and pan remain active. F or Escape returns to the same viewer; Escape from the ordinary viewer closes it.

Fullscreen goes through narrow, sender-validated Electron IPC and waits for OS enter/leave events. Transitions are serialized and fail visibly if unconfirmed. Browser page zoom is disabled so image gestures cannot enlarge the editor/application chrome. [Electron documents asynchronous Mac fullscreen confirmation](https://www.electronjs.org/docs/latest/api/browser-window#winsetfullscreenflag) and separate [visual/page zoom controls](https://www.electronjs.org/docs/latest/api/web-contents#contentssetvisualzoomlevellimitsminimumlevel-maximumlevel).

## Implementation boundaries

`src/core/inspection.ts` owns fit/zoom/pan geometry, identity retention and seed confirmation. `src/desktop/ui/image-viewport.ts` translates DOM wheel/pointer/resize events. `viewer-input.ts` owns keyboard/wheel normalization. `viewer.ts` coordinates selection, loading, notices and fullscreen presentation. `src/desktop/fullscreen.ts` owns the native window transition contract; the renderer receives no general window or filesystem authority.

No renderer invocation, model setting, batch report, artwork or original Swift data is changed by inspection. Loading remains guarded against stale asynchronous image responses. The same viewport is used in normal and fullscreen presentation.

## Evidence

Environment: macOS arm64, Darwin 25.6.0, Node 24.22.2, TypeScript 5.9.3, Electron 45.3.1. All images in these checks are synthetic; no GPU generation or new dependency procurement is required.

| Check | Result |
| --- | --- |
| Strict build and automated contracts | 149 tests passed, 0 failed |
| Geometry | Aspect-correct fit/letterboxing, fit floor/max, cursor anchoring, bounded panning, normalized focus during resize, nonfinite input rejection |
| Keyboard/seed contracts | Regular/numpad/legacy Add/Subtract; modified shortcut exclusion; same-seed/unknown identity policy; fresh-press confirmation, held-repeat rejection and invalidation |
| Native window contract | OS-event confirmation, serialized enter/exit, timeout/destroyed-window failures and recovery |
| Full desktop probe | Existing phase regressions plus numpad and regular zoom, text focus, Ctrl/Alt wheel, anchoring, horizontal/vertical pan, retained same-seed/sort state, fit floor, seed/repeat guards and no viewport history |
| Trusted input injection | Mouse left/middle drag and release; Ctrl/Alt wheel changes image zoom while application zoom remains 1 |
| Actual Mac fullscreen | Visible focused temporary test window enters/leaves native fullscreen; chrome hidden; arrows and seed notice work; Escape returns to an open viewer and F toggles again |
| Packaged Mac application | Build, the same isolated desktop/host probe, visual inspection and source-only package inclusion audit passed |
| Physical trackpads / Windows | Pending owner checks; Windows currently has no trackpad. Mouse/numpad controls are the primary Windows path. Synthetic gesture events do not establish physical trackpad behavior |

The host probe briefly shows and focuses its temporary synthetic window for trusted mouse-input checks: Electron requires a focused BrowserWindow for `sendInputEvent`. It waits for image zoom to change rather than relying on a fixed input-delivery delay, and reports focus, visibility and zoom values on failure. Set `STORYBATCH_PROBE_NATIVE_FULLSCREEN=1` to opt into native fullscreen checks. The isolated native-fullscreen probe briefly activates its own temporary window with synthetic images; it does not restart the user's application or load private prompts/images. macOS requires an active foreground application for this probe's native transition. Earlier inactive-window attempts correctly failed the confirmation deadline rather than reporting fullscreen success.

## Remaining Phase 6 gates

Owner verification covers real mouse/numpad behavior on Windows, physical Mac pinch/pan, multi-monitor/DPI transitions, OS Escape/window controls and full application close/relaunch. Native reveal integration, adoption/signing/distribution polish and any remaining platform UI parity retain separate scope. Windows native rendering/offline/quality acceptance from earlier phases remains pending, and Swift retirement still requires an explicit decision.
