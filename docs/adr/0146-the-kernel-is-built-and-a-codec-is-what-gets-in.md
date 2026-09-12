# The kernel is built, and a codec is what gets in

Prologue pass 6 moves the shared kernel into
`godot-learning/addons/exmateria_schema/` — six source members plus the fold
layer resource — and answers the membership question passes 4 and 5 deferred:
`psx_par` and `psx_dither` stay out, because **a member has a counterpart, not a
writer**. The move is the instrument's calibration shot and it found two
instrument defects, which is what a calibration shot is for.

Status: accepted (2026-08-21). Builds
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) and
sharpens its dec. 7; amends its dec. 9; extends
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 3's walk and discharges half of
[ADR-0145](0145-the-baseline-is-taken-and-the-series-opens.md) dec. 5; satisfies
[ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) dec. 5's *"built
before any extraction"*.

Code at `23f4318c1`; classifier at the same commit as the reading it is scored
against. Per ADR-0131's fourth amendment both are named, because either alone
moves the numbers.

## Context

ADR-0139 enumerated the kernel and gave it a name, a slot and an admission test,
and left three things for the pass that builds it.

The **position** is the whole point of the pass. ADR-0139 dec. 8 put the move
*after* the baseline so that the largest single relocation in the plan is not
hidden inside the reading everything else is scored against, and predicted a
delta of **zero for the eleven systems**. Anything else the instrument reports
is instrument error, found before a real extraction can be blamed for it. That
prediction is now tested rather than asserted, because ADR-0145 made `--delta` a
command.

The **census** had drifted. ADR-0139 says *"6 files, 1,063 lines (886 `.gd` +
177 `.gdshaderinc`)"*. The shaders still read 177; the `.gd` half reads **909**,
not 886 — 23 lines since it was written — and `Fold.gd` was at
`src/effects/Fold.gd`, not `src/core/`. Correcting a prior pass's number is the
normal cadence here, not an accusation.

The **membership question** was deferred twice. `psx_par.gdshaderinc` (70 lines)
and `psx_dither.gdshaderinc` (45) have the kernel's outward shape and ADR-0139
does not list them as members. Passes 4 and 5 booked them `platform` rather than
silently widening a kernel they were not allowed to redefine, and said pass 6
decides.

## Decision

**1. The kernel is seven files, not six: `fold_layer.tres` moves with `Fold.gd`.**
ADR-0139's table counts *source*, and `asset_census.py` already booked
`assets/fold_layer.tres` to `schema` — *"ADR-0138's membership interface, as a
resource"*. It is the single shared held-out layer every fold carrier joins, and
`Fold.gd`'s only outbound reference of any kind is `preload`ing it. Leaving it
behind would make the kernel's one outbound edge point **into the host**, which
ADR-0139 dec. 10's promotion path cannot survive: a released addon cannot depend
on a path inside the game that consumed it. Two instruments disagreeing about
the kernel's membership by one file is exactly the drift the enumerated list
exists to prevent, and the resource half was the half nobody had to name out
loud.

**2. Layout: one directory per schema, and the two languages sit side by side.**

```
addons/exmateria_schema/
  compositing_key/   DepthMode.gd  psx_ot_depth.gdshaderinc  Fold.gd  fold_layer.tres
  colour_model/      ColorRecipe.gd  ColorStack.gd  psx_color_stack.gdshaderinc
  plugin.cfg  plugin.gd  README.md
```

The directory names are the schema names from ADR-0118 dec. 1's table verbatim,
including its spelling of *colour model* against the code's `Color`. That is
load-bearing rather than fussy: dec. 3's gate is *"realises a named published
schema"*, so a reviewer checks membership with `ls`, and adding a member means
either landing in a schema's directory or **creating one**, which is visible in
a diff as what it is — a new schema. Putting each codec's CPU and GPU halves in
the same directory is ADR-0139 dec. 7's argument made physical: splitting a
codec is what makes drift invisible.

**3. `psx_par` and `psx_dither` are NOT members. A member has a counterpart; these
have a writer.** ADR-0139 dec. 7 declined them as *"anchor space"* and
*"techniques"* and said *"shared implementation is not a crossing"*. That is the
right answer resting on a soft reason — it describes what the files are about
rather than testing them — and the reach evidence points the other way hard
enough to deserve a mechanical answer: `psx_par` is `#include`d by **16 shaders
across six buckets** and has its own guard (`check_par_shaders.py`, ADR-0060),
which is precisely the profile `psx_ot_depth.gdshaderinc` has.

The test that separates them is the one dec. 5 already implies. A kernel shader
member is one half of a **codec** — an encoding implemented twice, once per
language, where the two must agree byte for byte:

| | CPU side | what the CPU side is |
|---|---|---|
| `psx_ot_depth` | `DepthMode.gd` | re-declares all eight calibration magnitudes and re-implements `psx_ot_depth()` |
| `psx_color_stack` | `ColorStack.gd` | `_pack` writes exactly the four arrays the include unpacks; `ColorStackGpuParityTest` asserts byte-exactness |
| `psx_par` | `PSXDisplay._apply_par` | one `RenderingServer.global_shader_parameter_set(&"psx_par", v)` |
| `psx_dither` | `DebugConfig._apply_dither` | one `global_shader_parameter_set("psx_dither_enabled", on)` |

`psx_par_full` and `psx_dither_and_quantize` are implemented **once**, in GLSL.
Their CPU side pushes a value through a port and never re-derives the maths.
There is no second implementation, so there is nothing for two sides to disagree
about, so there is no encoding to publish — and a schema is an agreement between
two parties, not a function two callers share. `PSXDitherCurves.gd` looks like a
counterexample and is not: it is FFT's 64 colour-interpolation curves, unrelated
to the ordered dither matrix, and it is an orphan in `docs/RESIDUE.tsv`.

Reach was never the test — ADR-0139 dec. 2 refuted a reach threshold by showing
it admits `DebugConfig` and `Tune` before it admits `Fold`. This is the same
refutation applied to the one case where the reach evidence was genuinely
tempting, and the answer is unchanged. **The 115 lines stay put, so `--delta`
reports no rebooking.**

**4. Their bucket is `platform`, and that corrects ADR-0139 dec. 7's "stay
`Render`'s".** Dec. 7 was written before the walk saw shaders at all
(ADR-0144). `Render` is a system that extracts; a PSX display fact that six
buckets include cannot live inside it without dragging it behind all six — which
is the serialisation ADR-0118 dec. 5 exists to prevent, arriving through the
back door. `platform` is where `PsxNum.gd` already sits and is the right answer
for the same reason. Pass 4's booking stands; this decision is what makes it a
decision rather than a holding pattern.

**5. The walk follows the refactor's own output, or a relocation reads as a
deletion.** ADR-0131 dec. 3 scoped the walk to `src/` and `assets/`, which was
the whole of the host's hand-written source the day it was written. This pass
moves 1,086 lines out of both. Left alone, the `schema` row would have gone to
zero and the kernel's lines would have been counted **nowhere** — ADR-0145
dec. 5's hole, arriving one pass earlier than that decision scheduled the fix
for, because dec. 5 was reasoning about extracted *systems* and did not notice
the kernel leaves the same way.

`classify_blueprint.WALK_ROOTS` is now `("src", "assets",
"addons/exmateria_schema")`, and it is the single definition three other
instruments read: `closure.py`'s subject, `asset_census.py`'s byte universe and
reader scan, and `touch_matrix.py` (through `walk()`). `addons/exmateria_sound/`
is deliberately **not** a root: it is a drifted copy of another package
([#326](https://github.com/timbermania/fft-monorepo/issues/326)) whose baseline
row ADR-0131 dec. 8 reads from the canonical package, and walking it would
double-count it. The test is authorship, not the `addons/` path — this repo's
blueprint owns `exmateria_schema`, and each extracted system joins the tuple in
its own pass.

**This closes the LINE half of ADR-0145 dec. 5 and not the REACH half.** Reaches
into `exmateria_sound` (`Effects` 14, `Audio` 8) are still counted nowhere, and
that fix is still owed at extraction #1's loop pass 9, as its own ADR, measured
both ways. Saying so is the point: the two halves have the same cause and only
one of them is fixed here.

**6. The addon's scaffolding is not a member, so it is not in the `schema`
bucket.** `plugin.gd` is 16 hand-written lines that exist so `plugin.cfg` has a
`script=`. By dec. 3's own rule it realises no schema and is not in the kernel;
by dec. 9's *"one directory prefix"* it would land in the bucket that **is** the
membership list. One exact rule ahead of the prefix books it `infrastructure`,
so `schema` keeps reading exactly ADR-0139 dec. 11's table while every *other*
new file under the addon still trips the prefix and shows up in the classifier
diff as a kernel admission. That amends dec. 9: the prefix is the gate for
members, and the gate needs one door for the doorframe.

**7. An addon's `plugin.cfg` `script=` is a declaration, and `closure.py` now
seeds it.** Without that, `plugin.gd` was unreachable from every declared root —
correctly, since the *engine* loads it, not the game — and landed in the residue
register, where `residue.py` attributed it to seven files that merely contain
the English word *"plugin"*. That is a fourth false-claim mechanism, and a new
one: the register's needle is the file's **stem**, and `plugin` is a common word
where `EffectTimelineView` is not. Seeding the manifest is the honest fix
because the claim is real — `plugin.cfg` names the file, in the same way
`project.godot`'s `[autoload]` block names an autoload, and closure already
seeds from that. **The stem collision itself is NOT fixed**, only avoided: no
entry in the register has a common-word stem today, and the next one will
mis-attribute the same way. It is named here so the next reader is not surprised
by it.

**8. A seam guard must check the file exists, not just the basename.**
`check_depth_shaders.py` and `check_color_shaders.py` resolved an `#include` by
`endswith("psx_ot_depth.gdshaderinc")` and never asked whether the path
resolved. That was harmless while the seam had lived at one path forever. This
pass moved it, which turns a stale `res://assets/shaders/...` include into a
*silent* loss of the seam: it compiles to nothing and reads to the guard as
compliant. Direction-tested both ways, and the first fix was not enough — the
colour guard also answered on `path.name == INCLUDE` **before** testing
existence, so a dangling path still passed until the order was swapped.
`tools/test_check_color_shaders.py` gains the case.

## Considered alternatives

- **Ship no `plugin.cfg`/`plugin.gd`, so the delta is a clean zero everywhere.**
  Rejected. It buys a prettier number by deleting a file Godot wants, and the
  16 lines are real new code that a truthful instrument should report. It also
  breaks the one landed precedent (ADR-0121 dec. 1). Dec. 6 books them where
  they belong instead, which costs `infrastructure` +1 file / +16 lines,
  attributed.
- **Leave `plugin.gd` in the residue register with its `tool` attribution.**
  Rejected by dec. 7: the attribution is false, and it is false through the
  exact mechanism ADR-0145's `INSTRUMENTS` exclusion was written to prevent —
  a hit in a classifier's rules table read as a consumer.
- **Flat layout inside the addon, with a README table mapping file to schema.**
  Rejected by dec. 2. A README is prose, and this series' repeated finding is
  that prose is evidence and never a claim. Directories are mechanical.
- **Admit `psx_par` on its reach.** Rejected by dec. 3 — it is ADR-0139 dec. 2's
  refuted test wearing a different hat. Sixteen consumers of a technique is a
  well-used library entry, which is what ADR-0129 dec. 5 already called it.
- **Move `psx_par`/`psx_dither` to `Render` per ADR-0139 dec. 7's letter.**
  Rejected by dec. 4: it would put a fact six buckets depend on inside the first
  system to extract.
- **Extend the walk to all of `addons/`.** Rejected by dec. 5: it double-counts
  `exmateria_sound` against the baseline's `extracted` row, whose whole point
  (ADR-0131 dec. 8) is that it is read canonically and not from the host's copy.
- **Fix the reach half of ADR-0145 dec. 5 here too.** Rejected: it is a
  different measurement with a different unit, the baseline is frozen, and
  ADR-0145 gave it a slot. Doing it inside a calibration shot would mean the
  shot no longer calibrates anything.

## Consequences

- **`docs/BASELINE.tsv` does not move and the freeze is untouched.** The eleven
  system rows read identically after the move; `schema` reads identically;
  `infrastructure` gains the 16-line scaffold. `check_baseline.py` stays green
  without an edit, which is the guard behaving as designed — the file is frozen,
  and pass 6 gave it no reason to change.
- **The calibration shot passed, and it earned its keep.** The predicted zero
  held exactly for all eleven systems. It also surfaced two defects that a real
  extraction would have been blamed for — the walk root (dec. 5) and the
  basename-only seam check (dec. 8) — plus one false register row (dec. 7).
  Both defects are of the same kind: **an instrument that hard-codes where
  things live cannot survive things moving**, and every remaining pass moves
  things.
- **`WALK_ROOTS` is now a shared definition, so the next extraction is one line.**
  Four instruments read it. Extraction #1 adds `addons/exmateria_render` to that
  tuple and the closure, the census and the touch matrix follow.
- **ADR-0139 carries amendment blocks for all of this** — at dec. 7 (the census, the seventh member, the codec test, the `platform` bucket), dec. 8 (renumbered to pass 6, and the shot's result) and dec. 9 (the scaffolding door). The kernel is
  **6 source files / 1,086 lines** (909 `.gd` + 177 `.gdshaderinc`) plus
  `fold_layer.tres`, and `Fold.gd` came from `src/effects/`.
- **`Fold`, `DepthMode`, `ColorStack` and `ColorRecipe` are still reached by
  `class_name`**, so no consumer changed except its `preload` path. 59 path
  references were rewritten across 47 files: 7 `preload`s in `src/`, 11 in
  `tests/`, 28 `#include`s, and the rest docstrings and living docs. ADRs were
  left alone — they record what was true when written.
- **The sink veto is now mechanically true, and stronger than when it was
  written.** Outbound edges from the `schema` bucket: **0**. Dec. 1 is why it is
  a clean zero rather than one `preload` pointing at the host — `Fold.gd`'s only
  outbound reference of any kind now resolves inside the addon.
- **The kernel's inbound reads 75 file-edges / 97 lines, against ADR-0139
  dec. 1's 46, and that is not a coupling change.** 26 of the 29 extra edges are
  `#include`, a shape that did not exist when dec. 1 was measured — ADR-0144
  dec. 1 added it with the shader walk. Excluding it the reading is **49**
  against 46, the residue of ADR-0140's `Debug` correction, ADR-0144's
  re-bookings and 23 lines of code drift. Per the eleven systems: `UI` 20,
  `Battlefield` 17, `Effects` 17, `Battle` 8, `Sprite Rig` 5, `Render` 4,
  `Cutscene` 3, plus the one assembler edge dec. 1 called out. `Render`'s own
  four are dec. 1's argument in its strongest form — the provider depending on
  the same encoding its consumers do.
- **ADR-0121 dec. 5's *"built before any extraction"* is satisfied**, and
  ADR-0138 dec. 8's serialisation risk is retired: `Effects` can bind `Fold`
  without `Render` extracting first.
- **The prologue is finished.** The next pass is extraction #1, `Render`
  (ADR-0141), which begins the per-system loop and owes the reach half of
  ADR-0145 dec. 5 at its pass 9.
- **[#326](https://github.com/timbermania/fft-monorepo/issues/326) is worse than
  its own headline and now has runtime symptoms.** The host's
  `addons/exmateria_sound/` differs from the canonical package across **6 files
  / 72 changed lines**. Two of them break at runtime today, independently of
  this pass: `SMDOpcodes.param_count_of()` is missing, which is a *parse* error
  that takes `EffectEditSession.gd` and the Effect Studio down with it, and
  `play_feds_pair` is short a parameter, which throws a `SCRIPT ERROR` on every
  cast in every combat test. Both are pre-existing at trunk and neither is
  caused by, or fixed by, this pass.
