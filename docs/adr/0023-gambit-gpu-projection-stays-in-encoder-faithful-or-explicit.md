# The Gambit→GPU projection stays in the encoder; faithful-or-explicit, no silent fallback

`GambitEncoder` projects a `Gambit` domain object (its `TargetSelector` /
`GambitCondition` graph) into the flat config dict the GPU consumes — the
**producer** side of the encoding whose **consumer** side
[ADR-0016](0016-gambit-encode-flat-schema-conditions-hand-packed.md) made a
looped schema. Three problems had accumulated on the producer side:

1. **A dead input path.** The encoder accepted two shapes — `Gambit` objects
   *and* a string-keyed dict (`target_type: "nearest_enemy"`) decoded by
   `_encode_from_dict` + three `_*_type_map`s + `_parse_*`. Nothing feeds the
   string shape: the sole caller (`GPUArena.gd:244`) passes `Gambit` objects,
   and the test scenes feed pre-encoded integer configs straight to
   `set_unit_gambits`. `arena_roster.json` chose the integer shape; `Gambit.to_dict()`
   produces a nested-`TargetSelector` shape — the flat string shape was adopted
   by no one.
2. **Silent, lossy fallbacks.** `_target_selector_to_gpu` and
   `_encode_gambit_condition` map only a subset of the domain enums; everything
   else falls through to `TARGET_NEAREST_ENEMY` / `COND_ALWAYS`. Because
   `UIGambitEditor` exposes the **full** domain vocabulary, a player can author
   a rule the GPU silently runs as something else — `ENEMY_IN_RANGE` becomes
   `ALWAYS` (a *meaning inversion*), `SPECIFIC_UNITS` becomes nearest-enemy.
3. **No producer-side drift net.** ADR-0016 guards that the CPU writer *covers*
   the buffer, but nothing guards that the encoder *covers the domain enums*. A
   new `GambitCondition.Type` (or one newly exposed by the editor) silently
   joins the fallback.

## Status

accepted

## Decision

- **The projection lives in `GambitEncoder` (`src/gpu`).** It is the adapter
  between the `Gambit` domain and the shader-authoritative GPU vocabulary
  ([ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md)), and
  it sits in the layer that may know both. The domain (`src/data`) stays
  GPU-agnostic.
- **Faithful-or-explicit.** The encoder either maps a domain value correctly or
  treats it as **`UNSUPPORTED`** — never silently substitutes. A single
  declared `UNSUPPORTED` set names the `GambitCondition.Type` /
  `TargetSelector.PoolType` / `ResolutionStrategy` values with no faithful GPU
  mapping; it is the canonical "features the GPU AI doesn't implement yet" list
  and doubles as the follow-up backlog.
- **Unsupported → skip + warn.** An unsupported gambit is dropped from the
  encoded list with a `push_error` naming the feature; the unit falls through
  to its remaining gambits (or its default). An unrunnable rule is ignored, not
  silently mis-run.
- **A completeness test in `src/gpu`** (pure, no `RenderingDevice`) asserts
  every `GambitCondition.Type`, `TargetSelector.PoolType`, and
  `ResolutionStrategy` value is either mapped or in `UNSUPPORTED`. This is the
  producer-side analogue of ADR-0016's whole-buffer completeness check: a new
  enum value the encoder doesn't handle fails the suite instead of joining a
  silent fallback.
- **The dead string-keyed dict path is deleted** (`_encode_from_dict`, the
  three `_*_type_map`s, `_parse_*`, the `is Dictionary` branches, the empty
  `PRESET GAMBITS` trailer). The encoder's interface collapses to one job:
  `Gambit → encoded config dict`.

## Considered options

- **Keep the projection in the encoder + faithful-or-explicit (chosen).** The
  encoder is already the correctly-layered adapter; the work is to make its
  reduction honest and machine-checked, not to relocate it.
- **Move the projection onto the domain objects** (`TargetSelector.to_gpu_target()`,
  `GambitCondition.to_gpu_condition()`). Rejected: it mirrors the two
  projections those objects already own (`to_dict`, `get_ui_display_data`), but
  it introduces the **first** `src/data → GPUConstants` dependency, spending a
  currently-pristine layer separation to buy co-location. The co-location win
  (drift-resistance) is recovered instead by the completeness test, which costs
  no layering. `GPUConstants` is shader-generated, so the domain would
  transitively depend on the shader layout.
- **Extract a standalone `GambitCodec`.** Rejected: there is exactly one GPU
  target for this projection, and the save/UI projections already live
  elsewhere — *one adapter is a hypothetical seam, not a real one.* A "codec"
  module would be `GambitEncoder`-minus-dead-path with a new name: a rename
  dressed as a seam, adding a module without adding depth.
- **Grow the GPU/shader vocabulary to remove the `UNSUPPORTED` set entirely.**
  Out of scope here — that is feature work in shader territory (ADR-0001),
  tracked per-feature as the `UNSUPPORTED` set is drained.

## Consequences

- **Silent meaning-inversions become loud, test-guarded gaps.** The
  `ENEMY_IN_RANGE → ALWAYS` class of bug can no longer ship silently.
- **The `UNSUPPORTED` set is the backlog.** Removing an entry is gated by the
  completeness test — you can't drop a value from `UNSUPPORTED` until the
  encoder really maps it. Revealed follow-ups are tracked as issues: #32
  (`*_IN_RANGE` → `ALWAYS`, bridgeable to `DISTANCE_*`), #33 (editor authors
  GPU-unrunnable options), #34 (HP/MP condition subject vs `cond_target_type`
  unenforced). Implementation of this ADR is tracked in #35.
- **Honest scope, matching ADR-0016.** ADR-0016 de-duplicated only the *write*
  side and left the encoder branchy on purpose; this ADR doesn't try to make
  the encoder loop a table either. It adds a *coverage* guarantee over the
  domain enums, the producer-side complement to ADR-0016's buffer coverage.
- **`GambitEncoder` shrinks** from 270 to 150 lines once the dead path is gone
  (the three string→enum maps, the three `_parse_*`, `_encode_from_dict`, the
  inlined `_encode_single_gambit` pass-through, and the empty trailer), and
  gains the `UNSUPPORTED` set + skip-and-warn; its interface is now exactly
  `encode_gambits(Array[Gambit]) -> Array[Dictionary]`. (The dead-path deletion
  landed ahead of the rest as pure cleanup — see #35.)
- **Behavior changes for already-broken cases only.** Faithfully-mapped gambits
  encode identically; previously-silently-degraded gambits are now skipped with
  a logged warning rather than mis-run. No faithfully-authored rule changes.
