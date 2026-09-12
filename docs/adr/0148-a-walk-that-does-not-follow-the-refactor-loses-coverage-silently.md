# A walk that does not follow the refactor loses coverage silently

Extraction #1's loop pass 9. Three instruments had the same defect and none of
them reported it: **a scan root that does not follow the refactor's own output
stops covering an extracted file and goes green because it no longer looks.**
ADR-0146 dec. 5 closed this for the census; the guards and the reach matrix had
it too. All three are fixed here, measured both ways, **before extraction #1's
number is published** — and the measurements correct four of ADR-0147's own
predictions.

Status: accepted (2026-08-21). Discharges [ADR-0145](0145-the-baseline-is-taken-and-the-series-opens.md)
dec. 5's REACH half and [ADR-0147](0147-renders-seam-is-the-fold-bracket-and-one-port.md)
dec. 8. Builds [ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md)
dec. 5. Corrects ADR-0147 dec. 3, dec. 8 and dec. 9.

Code at `e0323e7bf`, classifier at `e0323e7bf`. Per ADR-0131's fourth amendment
both are named, because either alone moves the numbers.

## Context

[ADR-0145](0145-the-baseline-is-taken-and-the-series-opens.md) dec. 5 has two
halves. The LINE half — *"source that leaves the walk's roots is counted
nowhere, so a relocation reads as a deletion"* — was fixed at prologue pass 6 by
making `classify_blueprint.WALK_ROOTS` the single definition of the walk
(ADR-0146 dec. 5). The REACH half was not: the 22 lines reaching into the already
extracted `addons/exmateria_sound/` are counted nowhere, so **every extraction
hands the series a reach fall it did not earn.** ADR-0145 gave it a slot at loop
pass 9 and ADR-0147 dec. 8 put a second item in the same slot.

Extraction #1 then found a third, and found it the only way this class of defect
can be found: by moving a file and checking whether the thing that used to guard
it still did.

## The defect, reproduced

`assets/shaders/depth_debug.gdshader` moved into `addons/exmateria_render/`.
With the seam `#include` deleted and `DEPTH = psx_ot_computed_depth;` replaced by
a raw `DEPTH = 0.5;`, `tools/check_depth_shaders.py` printed

    OK: all DEPTH-writing shaders use the psx_ot_depth seam (ADR-0009).

That is not a guard failing to catch a defect. It is a guard **reporting a clean
result about a set it no longer contains** — the same shape as the census
counting a relocation as a deletion, one layer down, and strictly worse, because
a line count that drops is at least visible in the diff.

## Decision

**1. The uncounted reach into an extracted addon is a READING, not a caveat.**
`check_baseline.py --delta` printed *"it does not see reaches into an extracted
addon (ADR-0145 dec. 5)"* as a footnote. ADR-0145 dec. 1's whole finding is that
a number living in prose moves without code changing — a *caveat* in prose has
the same problem, and is worse, because it cannot even be checked. `--delta` now
measures it and prints it:

    UNCOUNTED — lines reaching the extracted addons/exmateria_sound/: 22  (Effects 14, Audio 8)

22, Effects 14, Audio 8 — independently re-derived, and identical to ADR-0145
dec. 5's figure.

**It is deliberately not counted, and that stays true.** `addons/exmateria_sound/`
is a drifted copy of another package (#326), and ADR-0131 dec. 8 reads its
baseline row from the canonical `exmateria-sound/`. Walking it would double-count
it against the `extracted` row. The defect was never the exclusion; it was that
the size of the exclusion was invisible. **Reported, never asserted** — ADR-0145
dec. 4, applied to the instrument's own blind spot.

**2. `touch_matrix.py`'s blind spot is the two-step path, it is worth 2, and
ADR-0147 dec. 8 was wrong about its shape twice.** Dec. 8 said the matrix *"cannot
see a `res://` path held in a `const` and passed to `load()`"* and named
`src/effects/CompositorAutopilot.gd:18` as *"the live instance"*.

The mechanism is sharper than that. The matrix DOES see `load("res://…")` and
`preload("res://…")`, including a bare inline `load` — shape 1 matches the **raw**
line. What it misses is the dependency written in **two statements**: the `const`
line carries no `load(` for shape 1 to match, and `strip_noncode` blanks every
string literal, so by the time any other shape reads the line the path is already
gone. The instrument is not blind to `const`; it is blind to **a literal bound to
a name before it is used**.

And it is small. Measured over the walk:

| `const X := "res://…"` declarations | count |
|---|---:|
| total | 196 |
| target is not walked source (`.tscn`, `.json`) | 117 |
| same bucket on both ends | 77 |
| **cross-bucket** | **2** |

The two are `CompositorAutopilot.gd:18 → EngineFoldCompositor.gd` and
`src/ui3/detail/DetailSceneBoot.gd:22 → src/ui3/shaders/formation_background.gdshader`.
Dec. 8 inferred a large hole from one instance; there is one more instance and it
is in a different system.

**The fix changes the published total by zero, and that is the interesting part.**
Both cross-bucket instances have `assembler` as their source, and `assembler` is
not one of the eleven systems the matrix prints or sums. So a perfect instrument
would have scored them 0 in the cross-system total anyway. The matrix was never
wrong about the *number*; it was wrong about the *edge list*, which is what a
`--edges` reader uses to decide where a seam goes. Both instances are visible now,
and the total is unmoved — so extraction #1's number carries no instrument
discontinuity and none has to be attributed.

This also settles ADR-0146's *"when two registers describe the same set, diff
them."* `closure.py` always saw these, because it scans for `res://` literals
rather than for call syntax. The two registers now agree.

**3. A guard's scan root is a walk, and it reads `WALK_ROOTS`.** **Fourteen**
guards hard-coded `assets/shaders`, `src`, or both. `tools/_walk_roots.py` extracts
`classify_blueprint.WALK_ROOTS` — the pattern `touch_matrix.py` established, with
`SystemExit` caught — and the guards read it. Extraction #2 adds its addon to one
tuple and every guard follows. `tools/asset_census.py`'s `ASSET_ROOTS` had the same
defect *in a comment quoting ADR-0146 dec. 5*, and now derives its addon members
the same way.

**Fourteen, not nine**, and the difference is the review pass: nine were the ones
the extraction's own red output pointed at. The other five —
`check_no_env_vars`, `check_no_raw_psx_units`, `check_body_sprite_id_naming`,
`check_unit_progression_resource`, `check_battle_materials` — scan `src` for
`.gd` generically and were **already green**, which is the entire failure mode this
ADR is about. Reading the diff for "which roots did I not touch" found them; nothing
in the suite would have.

**One guard is exempt and it is named rather than quietly skipped.**
`check_location_ownership.py` takes a single root, reports `owner_file_path`
relative to that root's *parent*, and is called with a temp directory by its own
unit test — so multi-root support is a signature change and a display-path
decision, not a rescope. Verified at extraction #1 that neither addon declares a
`<ns>.loc.<name>` slug, so nothing is uncovered today; the limitation is written
into the file beside the root it keeps.

**Scanning `addons/` wholesale is not the fix, and this was measured rather than
assumed.** It was tried first; it drags in the vendored `addons/exmateria_sound/`,
whose asset-path resolver legitimately reads eight environment variables, and
`check_no_env_vars.py` went red immediately on another package's code. `WALK_ROOTS`
already excludes it, for that reason, with that reasoning written beside it. The
question *"which source does this refactor own"* has one answer and the guards
should not each re-answer it.

**4. `src/ui3/shaders/` has never been scanned by the depth or PAR seam guards,
and the debt goes on a ratchet rather than being fixed or hidden.** Widening the
walk found 6 files writing `DEPTH` outside `psx_ot_depth` and 11 writing
`POSITION` without the PAR seam — all Formation/Changejob shaders, and all of them
`UI`'s.

Fixing them inside a `Render` extraction would change `UI`'s rendering, which is
scope creep. Narrowing the guard back would hide them again, which is the defect
this ADR is about. They go on a `BURN_DOWN` list of the shape
`check_compositor_routing.py` already uses: **a new violation anywhere fails, and
an entry that stops violating fails too**, forcing its removal. The list emptying
is the chart. Issue [#363](https://github.com/timbermania/fft-monorepo/issues/363).

**A violation there is not automatically a defect** — both guards carry an
`-exempt:` marker and the Formation screen mounts under the map's *ortho* camera
(ADR-0137). Some may be correct as written and simply owe a marker. The list makes
no claim either way.

**5. Direction-test the fix, not just the defect — again.** ADR-0146 dec. 8 paid
for this once. The stale arm of both ratchets was written first as *"if the path
is in `BURN_DOWN`, mark it listed"*, which passes a reading of the code and fails
a test: a listed path that no longer violates was still marked, so the stale arm
only ever fired when a file left the walk **entirely**, and an entry for a clean
file would have sat there forever reading as debt. Caught by adding
`assets/shaders/unit.gdshader` — a clean file — to `BURN_DOWN` and watching the
guard pass. It now marks on the file *still violating*. Three arms tested on each
guard: the extracted file is covered, the list is load-bearing, and a stale entry
fails. The rescope itself is direction-tested the same way — an
`OS.get_environment` added to `addons/exmateria_render/display_port/PSXDisplay.gd`
is now reported by `check_no_env_vars.py` and was not before.

**6. Extraction #1's published metric, and where ADR-0147 predicted wrong.**

| reading | ADR-0147 dec. 9 predicted | measured at `e0323e7bf` | |
|---|---:|---:|---|
| `Render` files / lines | 7 / 701 | **7 / 699** | ✓ |
| `Render` shader files / lines | 3 / 119 | **3 / 119** | ✓ |
| `Effects` files / lines | 191 / 57,942 | **191 / 57,955** | ✓ |
| fold carriers owned by `Render` | 0 of 16 | **0 of 16** | ✓ |
| `Render` → systems (lines) | **0** | **5** | ✗ |
| systems → `Render` (lines) | 26 | **28** | ✗ |
| distinct inbound symbols | 1 | **2** | ✗ |
| cross-system total (lines) | *rises* | **1,132, a fall of 11** | ✗ |

Line arithmetic was asserted and holds: `Render` −464 against the frozen baseline,
`Effects` +475, every other system +0. (699 not 701 and 57,955 not 57,942 because
`ea146bced` added 17 anchor and exemption lines after dec. 9's census, and because
the two debug panels shed one `preload` line each on the way into the addon.)
`infrastructure` gains 23 — the addon's `plugin.gd` — which dec. 9's *"everything
else +0"* did not allow for. It is new source and it is reported, not absorbed.

**Three of the four misses have the same cause: dec. 9's table did not apply
dec. 9's own prose.**

- **`Render` → systems is 5, not 0.** Dec. 3 said *"once it moves, `Render`'s
  outbound into any system is ZERO"*, reasoning only about `ColorTimelineModel`'s
  two edges into `Effects`. Those are gone — `Render` → `Effects` is 0. But
  ADR-0147's own audit table records *"out, into `Debug`: 9"* and its own
  Consequences say *"`Render` reaches `Debug` on 9 lines"*. The two debug panels
  travelled with the system and still `extends BaseDebugPanel` and call
  `TuneField.add`. **The sink veto holds against every system except the one no
  ADR has decided about**, and that is a sharper statement of the `Debug` problem
  than the one ADR-0147 closed with.
- **Inbound is 28, not 26,** and the **published surface is two symbols, not one.**
  Dec. 9's prose predicted this exactly — *"the same relationship, once the file
  sits in `Effects` and reaches `Fold` and `FoldSurface` by `class_name`, is worth
  +1 to +2"* — and it landed at +2, with `−1` for the `ColorTimelineModel` line
  that went home. Dec. 2's *"`FoldSurface` … has no inbound edge at all"* was true
  only while `EngineFoldCompositor` was inside `Render`. **Dec. 1 created the
  bracket's first inbound edge and dec. 2 did not notice.**
- **The cross-system total FELL by 11**, where dec. 9 predicted a rise and called
  the direction *"the prediction that matters."* It decomposes exactly: −6 for the
  six `#include effect_particle_stp.gdshaderinc` carriers whose ends are now both
  `Effects`, −3 for `ColorTimelineModel`'s three `Render`↔`Effects` lines going
  internal, −4 for the two panel `preload` lines, +2 for
  `EngineFoldCompositor` → `FoldSurface`. Dec. 9 named all four terms and got the
  sign wrong because it weighed the +2 against the six `#include`s and left out
  `ColorTimelineModel` and the panels.

**Dec. 9 was right that either direction is the instrument behaving correctly, and
it is worth being explicit that a fall here is not progress.** −11 of 1,143 is
1.0%, on an extraction that moved 705 lines out of the host. The series must not
be read as monotone (ADR-0131 dec. 6, ADR-0134, ADR-0137 dec. 12).

**7. ADR-0137 dec. 12's prediction is tested, and it dissolved.** Dec. 12 measured
`EngineFoldCompositor`'s poll of `EffectMultiMeshPool` — by node **name**, then
`get_active_effect_buckets` by **string** — as the biggest thing `Effects` hands
`Render`, worth **0** of the cross-system total. After dec. 1 both ends are
`Effects`, so it is not a crossing at all. The instrument never had to get better
at seeing it; the boundary moved to the right place and the question stopped being
asked. That is the outcome an extraction is supposed to produce, and it is not
evidence that the matrix improved.

## Considered alternatives

- **Count `addons/exmateria_sound/` in the walk so the 22 lines are not lost.**
  Rejected: ADR-0131 dec. 8 reads that row from the canonical package, so walking
  the host's drifted copy double-counts it. The exclusion is right; its invisibility
  was the defect.
- **Give each guard its own explicit addon list.** Rejected — that is the
  re-scope-by-hand-every-pass failure ADR-0146 dec. 5 named. Extraction #2 would
  have to remember nine files.
- **Scan `addons/` wholesale instead of reading `WALK_ROOTS`.** Rejected, and
  measured: it turns another package's legitimate code into eight guard failures.
- **Fix the two `src/ui3/shaders/` seam violations sets as part of this pass.**
  Rejected: 15 files in `UI`, whose rendering would change, inside a `Render`
  extraction.
- **Leave `touch_matrix.py`'s two-step blind spot alone, since it is worth 2 and
  both are `assembler`-sourced.** Rejected. ADR-0145 reserved this slot precisely
  so the instrument would be fixed *between* extractions rather than during one,
  and the cost of fixing it now is provably zero: the printed total does not move.
  Deferring a zero-cost fix to a pass where it might not be zero is the trade
  backwards.
- **Re-take the baseline now that three instruments changed.** Rejected. None of
  the three moves a baseline number: the census walk is unchanged, the reach total
  is unchanged, and the guards do not feed `BASELINE.tsv`. The freeze holds
  (ADR-0145 dec. 2).

## Consequences

- **`--delta` now prints a number it used to describe.** Every future extraction's
  reach fall can be read against the 22 lines it did not earn.
- **`Render` → `Debug` is 5 and it is the only outbound `Render` has.** `Debug` is
  the largest shared surface in the plan — 528 inbound reach-lines, 46.6% of the
  package total — and **no ADR says whether it is a system that extracts or host
  machinery that never does.** Extraction #1 did not need the answer. It is now the
  single thing standing between `Render` and a clean sink veto, and extraction #2
  meets it immediately.
- **The addon's published surface is `PSXDisplay` and `FoldSurface`.** ADR-0147
  dec. 2's *"ONE symbol"* is amended: 26 of 28 inbound lines are still the port, and
  the other 2 are `Effects` reaching the bracket it hands work to.
- **`BURN_DOWN` lists exist on two more guards**, both ratcheting, both empty-able.
- **A green guard suite says nothing about coverage.** Fourteen guards had a stale
  root and 28 of 28 were green throughout. The only thing that surfaced any of it
  was moving a file and asking, per guard, whether the thing that used to watch it
  still did. **Extraction #2 owes that question again**, and it is cheap now: the
  answer for every guard but one is "it reads `WALK_ROOTS`."
- **ADR-0137 is discharged except dec. 10.** `native_blend`'s partiality — zero of
  the ten direct `Fold.add` producers consult it — needs a second read on the
  `owns_compositing()` port that every producer answers: ten producers, four
  systems. `Effects`' pass.
- **A prediction table should be re-derived from the prose that justifies it.**
  Three of ADR-0147 dec. 9's four misses are the table disagreeing with its own
  paragraph, and the fourth (dec. 3's zero) is the table disagreeing with the audit
  four sections above it. The scope pass predicted well and transcribed badly.
