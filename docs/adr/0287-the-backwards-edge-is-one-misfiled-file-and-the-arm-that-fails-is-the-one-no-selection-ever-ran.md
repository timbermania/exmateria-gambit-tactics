# The backwards edge is one misfiled file, and the arm that FAILS is the one no selection ever ran

[ADR-0286](0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md)
selected extraction #7 on **arm 7 = 1 name / 3 lines** and warned, citing
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 2/3, that the other eight arms would find something the selection instrument was
structurally blind to. **They did, three times.**

**One.** ADR-0286 dec. 6 called `src/effects/EffectScoreModel.gd`'s reach into the studio a
**five-line** backwards edge. It is **twenty-five**. Five are `class_name` — which is all
arm 7 can see — and the other twenty are `preload("res://src/effects/studio/…")`, which is
arm 6. That file's header is an eighteen-line block of studio preloads. **It is a studio
file living in the runtime's directory**, and its only consumers outside `src/effects/studio/`
and `tests/` are `src/scenes/EffectViewerScene.gd` — *the studio's own assembler*
([ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md) dec. 3) — and
three `tools/verify_*.gd` probes. Moving one file takes the blocker from 25 lines to
**zero**.

**Two.** **Arm 4b does not report debt, it FAILS.**
[ADR-0190](0190-a-global-uniform-earns-its-host-entry-by-having-a-writer.md) dec. 3:
*"`check_addon_portability.py` gains arm 4b, and unlike arm 4 it ENFORCES: only an addon that
is not one of the eleven systems may DECLARE a `global uniform`."* `assets/shaders/effect_particle_stp.gdshaderinc` declares two — `psx_gamma`
(:56) and `psx_fx_stretch` (:66). `Effects` is a system. **The addon is red on arm 4b the
day it exists**, and no selection pass in six extractions has ever run this arm.

**Three.** 396 lines of the proposed membership are reached by nothing.
`src/effects/PSXDitherCurves.gd` (159 lines) is named in the entire tree **only by its own
`class_name` line** — not by a test, not by a scene — and `src/debug/EffectTimelineView.gd`
(237) by three doc comments. `tools/closure.py` reports both UNREACHED, independently of
anything here.

Status: accepted (2026-09-11). This is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s **pass 2** for extraction
#7 — the audit that rules membership before anything moves. **Corrects ADR-0286 dec. 2
(70 files → 67) and dec. 6 (5 lines → 25, and the remedy);** its other nine decisions
stand. Reads [ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 5 for the arm-5 comparison,
[ADR-0273](0273-free-ness-inside-the-rules-tier-is-declared-per-member-because-a-package-of-tables-is-not-all-tables.md)
for what makes an almanac reach free,
[ADR-0271](0271-the-tier-is-declared-in-plugin-cfg-because-a-vote-over-consumers-cannot-see-a-fourth-tier.md)
for the declared tier that makes arm 5 readable at all,
[ADR-0190](0190-a-global-uniform-earns-its-host-entry-by-having-a-writer.md) for arm 4b,
[ADR-0220](0220-the-addon-that-declares-a-global-uniform-provides-it.md)
for the precedent that already solved it once, and
[ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md) for what UNREACHED means.
**Supersedes nothing.** Ticket: [#1184](https://github.com/timbermania/fft-monorepo/issues/1184).

## Context

### The instrument, and why ADR-0286's soft spot S1 did not bite

`tools/membership_arms.py`, all nine arms plus `--inbound`, over an **explicit file list**.
ADR-0286 S1 asked pass 2 to repair `arm7_membership.all_shapes`' `inside_prefixes`, which
is a prefix test and therefore cannot spell *"`src/effects/` but not `src/effects/studio/`."*
**It did not need repairing for this reading**: `membership_arms.py` takes its members as
argv paths and `all_shapes` tests `dst in members` before it tests any prefix, so passing
no `--inside=` at all makes the membership exact. Every number below is one command.

The defect is real and still there for callers who *do* pass a prefix — `selection_sweep.py`
is one — and it stays open as a ticket rather than being fixed mid-audit. What changes is
its severity: it is a **usage hazard on one entry point**, not a hole in the pass-2 reading.

### All nine arms, before and after the corrections

| arm | what it asks | pass 1's 70 | **audited 67** |
|---|---|---:|---:|
| 1 | reach into one of the eleven systems | 92 | **67** |
| 2 | foreign host autoload, bare `Name.` | 72 | **72** |
| 2b | autoload by `/root/` node path | 0 | **0** |
| 3 | `#include` outside every addon root | 7 | **7** |
| 4 | shader global bound but not owned | 0 | **0** |
| 4b | **global uniform DECLARED inside** | **2** | **2** 🔴 |
| 5 | sibling `class_name` (guard's own rule) | 63 / 19 rows | **63 / 19 rows** |
| 6 | `res://` outside every addon root | 22 | **2** |
| 7 | host `class_name` | 3 names / 8 lines | **1 name / 3 lines** |

Size: **70 files / 16,599 lines → 67 files / 14,441 lines.**

**Arm 7 returns to the selection's number and arm 6 collapses by twenty** — both from the
single move in dec. 2. Nothing else moved, which is the useful part: the corrections are
attributable to one file rather than spread across the membership.

### Arm 5 is 63 lines and 53 of them are free, because #1059 landed

This is the arm ADR-0262 dec. 5 accepted **55 debt lines** on for extraction #6, and the
reason it reads differently here is that the declared tier now exists (ADR-0271) and
free-ness inside `rules` is declared per member (ADR-0273):

| target addon | declared tier | lines | free? |
|---|---|---:|---|
| `exmateria_schema` | `kernel` | 46 | **free** — ADR-0139, a shared vocabulary is not coupling |
| `exmateria_almanac` | `rules` | 4 | **free** — all four are `ExMateriaAlmanac.AbilityDatabase`, declared `"table"` at `exmateria_almanac.gd:451` (ADR-0273) |
| `exmateria_platform` | `port` | 3 | **free** — ADR-0157 dec. 2 |
| `exmateria_battlefield` | `system` | 6 | **debt** — `MapIlluminationDDA` ×4, `Lattice` ×2 |
| `exmateria_render` | `system` | 3 | **debt** — `FoldSurface` ×3 |
| `exmateria_sound` | `system` | 1 | **debt** — `FedsBank` ×1 |
| | | **63** | **10 debt** |

**Ten, against the catalogue's fifty-five.** The shape scan reads this as 18 lines; the
guard's own rule reads 63, because it binds `const X = Facade.Y` aliases first and scores
every bare `X` below them (ADR-0211 dec. 4). The instrument's docstring warns that the
shape scan under-reads, and here it under-reads by 45.

### Arm 2 is 72, and eleven of them are extraction #2's own package

| target | lines | files |
|---|---:|---|
| `DebugConfig` | 61 | 19 of 67 |
| `ExMateriaEffectSfx` | 11 | `src/effects/EffectInstance.gd` alone |

The second row is the one nobody predicted. `ExMateriaEffectSfx` is
`addons/exmateria_sound/`'s autoload — the package `Audio` extracted into at #2 — and
**arm 2 has no tier exemption of any kind** (`membership_arms.py`'s own docstring: arm 2
*"takes the WHOLE host autoload map and has no such filter"*, unlike arm 2b). So a
completed extraction's package is arm-2 debt for the next one, spelled `X.foo()` and free
spelled `get_node_or_null("/root/X")`. Arm 2b reads **0**.

Four autoloads are declared **inside** the membership and are reached on 15 member lines
(`UnitTintOverlay` 8, `ScreenEffectOverlay` 4, `MapTintOverlay` 3, `EffectMultiMeshPool` 0).
Those 15 become free the moment the scripts ship with the addon under ADR-0262 dec. 6 —
that is what "the script moves, the `[autoload]` line stays the host's" buys.

### Arm 3 is seven lines and all seven are free

Four `#include`s of `addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc` and
three of `addons/exmateria_schema/compositing_key/ot_depth.gdshaderinc` — the port and the
kernel. This is the shape ADR-0220 describes, already working.

### The inbound surface, re-taken on the audited membership

| shape | total | production | `tests/` + `tools/` |
|---|---:|---:|---:|
| `class_name` | 664 over 27 names | 50 over 11 | 614 |
| `res://` path | 425 over 39 targets | 30 over 14 | 395 |
| autoload | 43 over 4 names | 8 over 3 | 35 |
| **total** | **1,132** | **88** | **1,044 (92.2%)** |

ADR-0286's figures were 1,207 / 90 / 1,117; the deltas are dec. 2's file moving out of the
membership. **The conclusion does not move: it is still roughly four times `Battlefield`'s
284, and still 92% test-and-tool.**

### `EffectScoreModel.gd`, read rather than counted

1,905 lines — the largest file in the runtime — and 63 of the last 60 days' commits. Its
`const` header block is eighteen consecutive `preload("res://src/effects/studio/…")` lines
(`:27`–`:44`), plus two more at `:1137`/`:1142`, naming `EffectScriptPattern`,
`InspectionTarget`, five `*Projector`s, `PaletteChannel`, `ScreenChannel`,
`SpacerVerdicts`, `CameraValueSemantics`, `EmitterParamRows`, `CurveShapeSet`, four
`Emitter*` types and `InspectorProjectorRegistry`. Every one of those is editor
vocabulary — *projector*, *inspector*, *param row*, *spacer verdict*.

Who reaches it, outside `src/effects/studio/` and `tests/`:

| referrer | what it is |
|---|---|
| `src/scenes/EffectViewerScene.gd:56` | **the Effect Studio's assembler** (ADR-0134 dec. 3) |
| `tools/probe_studio_inspector.gd`, `tools/verify_gradient_stop_edit.gd`, `tools/verify_screen_color_edit.gd` | studio probes |
| `src/effects/EffectEndModel.gd:10`, `src/effects/EffectInstance.gd:653` | **`##` doc comments** — not code |

**No runtime file executes a line of it.** It is booked `Effects` by `classify()` and it
belongs to the studio by every other reading.

### `CompositorAutopilot.gd` is the exception ADR-0134 already recorded

ADR-0286 dec. 2 stated the membership as a directory rule, `src/effects/*.gd`. That rule
sweeps in `src/effects/CompositorAutopilot.gd` (94 lines), which `classify()` books
`assembler` — and
[ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
dec. 9a names it by name: *"`CompositorAutopilot.gd` is the one recorded exception, and it
stays."* It is referenced by 11 files across seven systems, so it fails ADR-0135 dec. 8 on
its face, and ADR-0129 booked it on its identity anyway. Pass 1 said 69 files; the rule as
written produces **70**.

## Decision

**1. The audited membership is 67 files / 14,441 lines**, and it is a directory rule
**minus a named exception list**, not a directory rule alone. ADR-0286 dec. 2 is corrected:

```
src/effects/*.gd                                        45 files
src/effects/callbacks/*.gd                              12
assets/shaders/{effect_*,trap_charge_line}.{gdshader,gdshaderinc}   12
  minus  src/effects/CompositorAutopilot.gd             (dec. 4)
  minus  src/effects/EffectScoreModel.gd                (dec. 2)
  minus  src/effects/PSXDitherCurves.gd                 (dec. 5)
                                                     = 67 files / 14,441 lines
```

A directory rule with an exception list is what `check_move_manifest.py` needs anyway
(ADR-0184), so the manifest is not made harder by this; it is made honest.

**2. `src/effects/EffectScoreModel.gd` moves to `src/effects/studio/` and this is the
first build ticket.** It is a studio file by its preload block, by its consumers, and by
its vocabulary. **ADR-0286 dec. 6 is corrected in both its number and its remedy**: the
backwards edge is 25 lines, not 5, and the fix is not to invert two `class_name` references
— it is to put one file where it belongs. On the audited membership arm 6 falls **22 → 2**
and arm 7 **3 names / 8 lines → 1 name / 3 lines**, which is the selection's own figure,
recovered rather than claimed.

**3. Arm 4b is a hard red with two different fixes, and both land before pass 6.** ADR-0190
dec. 3's arm enforces, and `assets/shaders/effect_particle_stp.gdshaderinc` declares two
global uniforms:

- **`psx_fx_stretch` (:66) is mechanical.** The canonical declaration seam already exists
  at `addons/exmateria_platform/display_port/psx_sprite_stretch.gdshaderinc:41`, and this
  shader **already `#include`s the platform** (arm 3, `:63`). Delete the local declaration,
  include the seam. This is `exmateria_battlefield`'s precedent verbatim — that addon
  carried this exact name among five and now declares none (`plugin.gd:129–138`,
  ADR-0220 dec. 2).
- **`psx_gamma` (:56) is a decision, not a move.** It is declared by **no addon file
  anywhere in the tree** — only by three host shaders and `project.godot` — and
  `addons/exmateria_platform/plugin.gd:37` records that it is deliberately not provided
  there, and that addon's `README.md:94` calls it the one name the port pushes and does not
  provide.
  `Effects` cannot declare it and cannot inherit it. This is ADR-0190 dec. 4's residual
  block reaching a system that is trying to leave, and it is the first time that has
  happened.

**4. `src/effects/CompositorAutopilot.gd` is not a member.** `classify()` books it
`assembler` and ADR-0135 dec. 9a names it as the corpus's one recorded exception to the
assembler rule. It stays in the host. (Dec. 9a also says *"The exception dissolves when the
split lands"* — ADR-0129's — which is not this pass's work, and nothing here depends on
it.)

**5. `src/effects/PSXDitherCurves.gd` is dead and is not moved.** Its own `class_name`
declaration is the only occurrence of the name in the tree — no test, no scene, no tool —
and `closure.py` reports it UNREACHED from all 64 seeds, independently. Under ADR-0112 that
is a candidate, not a verdict, so this ADR **removes it from the membership** and does not
delete it; deletion is `tools/delete_dead_code.py`'s job and its own ticket. **An
extraction must not carry dead code into an addon**, where a later reader will find it
inside a published package and assume it is part of the interface.

**6. `src/debug/EffectTimelineView.gd` (237 lines) is the same finding on the other side of
dec. 3 of ADR-0286**, and it exposes a gap in that decision's mechanism. ADR-0286 dec. 3
ruled six `src/debug/` files non-members; **`arm7_membership.panel_subclasses()` catches
only three of them**, because it tests for `BaseDebugPanel` subclasses and
`EffectTimelineView` / `EffectTimelineModel` / `ColorTimelineModel` are the panel's private
view and models (`extends Control` / `extends RefCounted`). Dec. 3 is still correct — those
three are excluded by the *directory* rule in dec. 1, since no `src/debug/` path is in the
membership — but it rests on dec. 1, not on ADR-0257's detector. **A debug panel's private
model is not a `BaseDebugPanel` subclass, and ADR-0257's rule cannot see it.** Recorded, not
fixed: widening that detector re-prices three shipped extractions, which is exactly what
ADR-0262 declined to do mid-pass.

**7. Arm 5's debt is ten lines and they are named**: `ExMateriaBattlefield.MapIlluminationDDA`
×4 and `.Lattice` ×2 (`PaletteSubsystem.gd`, `CinematicFacingResolver.gd`),
`ExMateriaRender.FoldSurface` ×3 (`EngineFoldCompositor.gd`),
`ExMateriaSound.FedsBank` ×1 (`EffectData.gd`). The other 53 are free **by declared tier**,
which is #1059's mechanism doing the job it was built for — the same reading before #1059
would have counted the almanac's four against a system that does not exist. ADR-0262 dec. 5
accepted 55 for extraction #6; this pass accepts **10**, and names all four symbols so pass
3 designs against them rather than against a count.

**8. Arm 2's 72 lines split 61 `Debug` / 11 `Audio`, and the second half is a finding about
the METHOD, not about `Effects`.** An extracted package's autoload is arm-2 debt for every
subsequent extraction, free spelled one way and debt spelled the other. `Effects` reaches
`ExMateriaEffectSfx` on 11 lines of one file. This is the crossing
[ADR-0124](0124-effects-tells-audio-a-code-and-a-time.md) already designed — *`Effects`
tells `Audio` a code and a time* — arriving as a portability number, and pass 3 should
design it as that crossing rather than as 11 autoload reaches.

**9. The verdict: the membership is audited and extraction #7 is viable.** Three items
must land **before** pass 6, in this order — dec. 2's file move (unblocks everything and
is pure `git mv` plus 20 preload paths), dec. 3's `psx_fx_stretch` include, and dec. 3's
`psx_gamma` decision. Dec. 5's dead file and dec. 8's crossing design are pass-3 work.
**Nothing found here disqualifies the selection**: after dec. 2 the audited membership
reads arm 7 = 3 lines, arm 5 debt = 10, arm 6 = 2, which is the best nine-arm sentence any
unextracted system has produced.

## Considered alternatives

**Leave `EffectScoreModel.gd` in the runtime and invert the two `class_name` references,
as ADR-0286 dec. 6 proposed.** Rejected on the measurement that decision did not have: the
edge is 25 lines over 20 distinct studio files, and inverting it would mean the runtime
addon publishes — or duplicates — twenty editor types. The file's own consumers say which
side it is on.

**Split `EffectScoreModel.gd`, keeping a runtime core.** Considered because 1,905 lines is
large and `EffectEndModel` and `EffectInstance` mention it in doc comments. Rejected: those
mentions are comments, no runtime file calls it, and a split is a design decision for pass
3 with an actual reading of the file. Moving it whole is reversible; splitting it is not.

**Add `rules`-style per-member freeing to arm 2 so the `ExMateriaEffectSfx` lines stop
printing.** Rejected — the same shape ADR-0273 rejected for the free set: arm 2 and arm 2b
report the same dependency differently *on purpose* (`membership_arms.py`'s docstring), and
widening arm 2 would re-price three shipped extractions from inside an audit of a fourth.

**Declare `psx_gamma` in `exmateria_platform` so `Effects` can `#include` it.** The obvious
fix, and out of scope here: `plugin.gd:37` records a deliberate decision not to, and that
addon's `README.md:94` names it as the single global the port pushes without providing.
Overturning that is the platform's ADR to write, and dec. 3 asks for it rather than doing
it.

**Delete `PSXDitherCurves.gd` in this pass.** Rejected: ADR-0112 makes UNREACHED a ceiling
on deadness, not a verdict, and `closure.py` reports 225 non-literal `load()` sites it
cannot see. Removing it from the membership costs nothing and asserts nothing; deleting it
asserts something this pass did not verify.

**Widen `panel_subclasses()` to catch a panel's private models (dec. 6).** Rejected for
ADR-0262's reason, verbatim: widening an enforcing rule's subject re-prices shipped
extractions, which an audit cannot do to a neighbouring subject mid-pass.

## Consequences

- ADR-0286 dec. 2 and dec. 6 are corrected. **A selection ADR's blocker was wrong by 5× and
  its remedy was wrong in kind**, and both were found by running the eight arms the
  selection does not run. ADR-0262 dec. 2/3's warning has now fired on two consecutive
  extractions; it should be read as the default expectation, not a caution.
- **Arm 4b has never been run by a selection pass and it is the only arm that ENFORCES on a
  fact about the tree.** Six extractions have been selected without it. `Battlefield`
  survived by having its five names moved out under ADR-0190/ADR-0220 *after* it shipped.
- The audited nine-arm sentence for extraction #7: **67 files / 14,441 lines; arm 1 = 67
  (61 of them `Debug`), arm 2 = 72, arm 2b = 0, arm 3 = 7 (all free), arm 4 = 0, arm 4b = 2
  🔴, arm 5 = 63 of which 10 debt, arm 6 = 2, arm 7 = 3.**
- Pass 3 inherits three designed crossings rather than a count: the role binding for
  `Unit` ×3 (ADR-0286 dec. 8), ADR-0124's code-and-a-time for the 11 `Audio` lines, and the
  port question for 61 `DebugConfig` lines.
- `tools/membership_arms.py` has now been run on a membership that is **not** a proposed
  addon directory — three directories and an exception list — and needed no change to do
  it. That is the first evidence its `_FileSet` abstraction generalises.

## Soft spots

**S1 — the 61 `DebugConfig` lines are STILL unexamined.** ADR-0286 S3 said so and this pass
reproduced the count without reading a single one. They are 61 lines across 19 of 67 files,
the largest single thing the membership reaches, and nobody has checked whether they are one
port's two signatures or 61 independent decisions. This is now the oldest unpaid item in
the extraction and pass 3 must not inherit it a third time.

**S2 — dec. 2 is asserted from consumers and comments, not from running anything.** No
Godot process was started for this pass. The claim that no runtime file executes
`EffectScoreModel` rests on a name-and-path scan over 2,545 files plus reading its two doc
comments; a duck-typed reach or a non-literal `load()` would be invisible (ADR-0131 dec. 6,
and `closure.py` counts 225 such sites tree-wide). **The move should be verified by loading
the runtime's scenes and asserting, not by watching them come up** — ADR-0157's Spike A
lesson, which is exactly the shape of this risk.

**S3 — `psx_gamma` has no owner and this ADR does not give it one.** Dec. 3 splits arm 4b's
two names into "mechanical" and "a decision", and the decision is deferred to an ADR nobody
has been asked to write. If it is still open at pass 6 the extraction stops, because arm 4b
enforces. It is the one item here that can block on somebody else's corpus.

**S4 — arm 5's free set is now read off `plugin.cfg`, and that is a claim about a file.**
53 of 63 lines are free because `exmateria_schema` says `tier="kernel"`, `exmateria_platform`
says `tier="port"`, and `exmateria_almanac.gd:451` says `AbilityDatabase` is a `"table"`.
Those are the right answers today and they are *declarations*, not derivations — which is
#1059's whole point and also its residual risk. A wrong `tier=` would make this pass's
headline number wrong silently, and nothing in this audit re-derives them.

**S5 — the 1,044 test-and-tool references were counted, never opened.** Pass 5 prices them.
The one thing pass 2 can say is that the number did not move materially when the membership
shrank by three files, which suggests it is spread rather than concentrated — and that is
an inference from two totals, not a measurement of the distribution.
