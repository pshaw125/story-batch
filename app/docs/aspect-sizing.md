# Aspect sizing implementation handoff

BatchParameters accepts mutually exclusive `aspect` and `resolution`, plus
`pixel_max` (default 1,048,576). Requested aspect is stored normalized; resolved
width/height remain the generation recipe. AspectSizing reduces positive integer
ratios with GCD and chooses the largest k such that `(64*p*k)*(64*q*k)` fits
the cap and each axis fits Draw Things' UInt16 grid. Binary search avoids
floating-point boundary rounding. Ratios remain exact, even if budget is unused.

The existing bounded decimal arithmetic parser also evaluates scalar pixel caps.
Its error label is configurable; final pixel caps must be positive integers
within Int. Explicit/default dimensions are checked against the cap after
parsing. Reports retain requested aspect/cap and actual dimensions; no extra
Draw Things configuration keys are needed. Viewer variants pin source dimensions
and clear requested aspect, while still honoring the report's pixel cap.

New Codable properties are optional so historical reports decode. Open Batch
can validate an old over-cap report for review with a temporary validation-only
cap; the original draft is restored unchanged and normal feedback prevents new
generation until the user supplies an explicit cap. It never rewrites old files.

AspectSizingTests checks normalization, invalid and overflow cases, exact cap
boundaries, backward decoding and maximal sizing against independent exhaustive
grid enumeration. AppModelTests checks feedback, batch continuation, queued
dimension snapshots and legacy report review. Tests use a fake CLI, without GPU
generation. Run `app/test.sh` and `app/build.sh`.

Agent-facing delivery and field rules live in app/README.md and app/docs/prompt-fields.md. New examples use
aspect; exact reproduction should keep the saved width/height.
