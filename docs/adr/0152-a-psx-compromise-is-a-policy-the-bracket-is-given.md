# A PSX compromise is a policy the bracket is given, not a constant it owns

Goal #8's **code half** for `Render`. The fold's RGB555 quantization stops being
`31.0` welded into GLSL and becomes a level the bracket is handed; the PAR
constants turn out to be **four dead literals**, one of which contradicts the
value the game actually runs at, and are deleted. The **register half is not
done and cannot be** — the known-drops register is epilogue E1 — so goal #8
stays `open` for `Render` and this ADR says exactly which half is which.

Status: accepted (2026-08-22). Discharges the code half of goal #8 for `Render`,
as scoped by [ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md)
dec. 5. Follows [ADR-0150](0150-psxdisplay-stays-because-render-is-the-playstation-look.md),
which separated compromise from vocabulary. Builds
[ADR-0074](0074-display-space-fold-is-a-material-contract-not-a-module.md) / [ADR-0080](0080-the-fold-composites-pre-transparent-to-layer-modern-over-psx.md)'s
bracket.

Code at `bb5f7fefa`, classifier at `bb5f7fefa`.

## Context

ADR-0150 established that `psx_par` and `psx_gamma` are `Render`'s **vocabulary**
— the PSX look is what `Render` is — and that the thing #394 actually surfaced
was a different goal: `PAR := 1.25` and `quantize5()`'s `31.0` are PSX
**compromises**. The PlayStation stored five bits per channel and stretched
256×240 to 4:3 because of the hardware it had. A tactics RPG does not need
either.

ADR-0117 records that goal #8 *"runs backwards inside `Render`, where a PSX
compromise is the product and a known drop is a regression."* That inverts the
**direction** of the goal, not its content: the compromise still has to be
**named and switchable**, it just keeps the PSX value as its default. A consumer
who wants the display-space fold without the 5-bit crush should not have to fork
a shader.

## Decision

**1. The fold's quantization level is a push-constant policy, defaulting to
31.0.** `quantize5(c)` becomes `quantize(c, levels)`; `levels <= 0.0` returns the
colour untouched. The level travels in the resolve pass's push constant, in the
slot that was **already there as padding** — `Params` was `vec2 raster_size; vec2
_pad;` and is now `vec2 raster_size; float quantize_levels; float _pad;`. Still
16 bytes, which the exact-size rule requires. **The divorce costs zero bytes and
one branch.**

**2. `FoldSurface.quantize_levels` is a `static var`, and 31.0 is its default.**
The ADR-0068 shape — a tunable living as a `static var` in its production owner.
It is read every frame at push-constant build time, so a consumer that sets it
takes effect without rebuilding the pass. It stays 31.0 because `Render` IS the
PlayStation look (ADR-0117 dec. 6, ADR-0150); **changing it is a known drop and
owes a register entry at E1.**

Not a `Tune` slug. `Tune` is a `platform` port and reaching it would not cost
goal #5 anything, but the value is read inside a `CompositorEffect` render
callback, and ADR-0068 dec. 12's corollary is specifically about not fanning a
tunable out from a surface that is not its owner. A live scrub is a separate
feature, and a `static var` is already the switch goal #8 asks for.

**3. `PSXDisplay`'s four PAR constants are deleted.** `INTERNAL_WIDTH`,
`INTERNAL_HEIGHT`, `DISPLAY_WIDTH` and `PAR` had **zero readers** — not inside
the file, not anywhere in the tree, including `.tscn` and shader source. The
file's own docstring called `PAR := 1.25` *"the canonical constant"* while the
value the game runs is `project.godot [shader_globals] psx_par`, which reads
**1.0**.

So PAR was already divorced and nobody had noticed: **the number lives in the
host's `project.godot`, which is precisely goal #8's "a policy the host
supplies."** What remained was a dead rival literal contradicting the live one —
the exact failure this file's own single-source-of-truth argument (ADR-0036
Option A) forbids.

**4. Goal #8 stays `open` for `Render`, and the evidence says which half.** The
goal's words are *"PSX compromises divorced, **each recorded as a known drop with
its reason and the ADR that authorised it**"*. The recording half is E1's
register. Marking #8 `met` on the code half alone would be the kind of claim
ADR-0149 exists to make impossible.

## Considered alternatives

- **Leave `quantize5` hardcoded; `Render` is the PSX look so the compromise is
  the product.** Rejected, and it is the tempting one after ADR-0150. But
  ADR-0117 inverts goal #8's *direction*, not its content, and goal #5 asks that
  the addon ship to another tactics RPG **with its interface intact** — a
  consumer that wants the fold without the crush currently forks the GLSL, which
  is not an intact interface.
- **Make the level a `Tune` slug** so it appears on the Registry page. Rejected
  by dec. 2, on the read site rather than on portability.
- **Keep `PAR := 1.25` as documentation of the PSX value.** Rejected: a constant
  is not a comment, and this one asserted a number the running game contradicts.
  The fact belongs in prose, where it now is.
- **Fix the four UI3 elements' `1.25` literals too.** Out of scope and left
  alone: `UIChar` / `UIText` / `UIPortrait` / `UIFrame` each hardcode `1.25` as
  an `@export` default that `PSXDisplay.live_ui_par` overwrites on first sync
  (and whose own default is 1.0). That is `UI`'s compromise, for `UI`'s
  extraction. Only the dangling `= PSXDisplay.PAR` citations are repointed here —
  five comments across five host files, so deleting a constant does not orphan
  the sentences that explained it.

## Consequences

- **The switch is verified on real hardware, not declared.**
  `tests/FoldQuantizePolicyTest.gd` runs `foldsurface_resolve.glsl` through a
  local `RenderingDevice` and asserts two arms: an **off-lattice** input (0.5)
  moves between `levels = 31` and `levels = 0` (`srgb_to_lin(16/31) = 0.22927`
  vs `srgb_to_lin(0.5) = 0.21404`), and an **on-lattice** input (`16/31`) is
  identical under both. One arm alone proves nothing — a transform that differs
  is not necessarily a quantizer.
- **A trap, paid for once and worth more than the test.** The first run of that
  test failed with *both* levels producing the 31.0 result. The cause was not the
  code: an edited `.glsl` runs from the **stale SPIR-V in `.godot/imported/`**
  until Godot reimports it. Two earlier scene-level probes had already been run
  against the old shader and read as "the policy does nothing". **After editing
  any `.glsl`, `touch` it and run one `godot --path . --editor --quit` before
  believing a result.**
- **`Render` scores 5 met, 2 n/a, 3 open.** Goal #8 is unchanged in the register
  and materially advanced in the code, which is exactly what ADR-0149 dec. 5's
  split scope was written to be able to express.
- **E1 inherits two named entries** rather than a search: the fold's 5-bit
  quantize (`FoldSurface.quantize_levels`, authorised here, PSX value kept) and
  world PAR (`project.godot [shader_globals] psx_par`, currently 1.0 — **already
  a drop from the PSX 1.25, taken silently and never recorded**). The second is
  the more interesting finding: goal #8's register would have been written
  believing PAR was 1.25.
- **A dead constant is invisible to the residue register.** `docs/RESIDUE.tsv`
  is per-file and `PSXDisplay.gd` is very much reached, so four unread constants
  inside it were unreachable by every instrument in the package. Goal #3's
  machinery does not see symbols. Recorded, not solved.
