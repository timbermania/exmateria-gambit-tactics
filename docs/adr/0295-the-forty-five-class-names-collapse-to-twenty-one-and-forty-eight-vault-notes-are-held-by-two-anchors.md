# The forty-five class_names collapse to twenty-one, and forty-eight vault notes are held by two anchors

Passes 1–4 of extraction #7 settled *what* moves and *where*. Neither they nor any
instrument they ran priced what the destination **already obliges**, and this pass found
two obligations nobody had opened. Both are the same shape as extraction #4's pass-4
lesson — *the design was never checked against the conventions the DESTINATION already
enforces* — and here they arrive one pass later, at fifty times the scale.

**The first is the global-name surface.** Every one of the nine addons under `addons/`
declares exactly **one** `class_name`, the folder-named façade, and
[ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1 is the rule: *"one global `class_name`, spelled `ExMateriaX`, in `addons/exmateria_x/"*
(`tools/check_addon_globals.py:12`). The 67-file membership declares **45**.
`exmateria_battlefield` was seeded at 30 and drained in one pass; `exmateria_effects` is
the largest such collapse this corpus has attempted. ADR-0212 is cited by none of
[ADR-0286](0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md),
[ADR-0287](0287-the-backwards-edge-is-one-misfiled-file-and-the-arm-that-fails-is-the-one-no-selection-ever-ran.md),
[ADR-0288](0288-the-sixty-one-debug-lines-are-four-booleans-and-the-seam-is-three-addresses-once-the-psx-trio-goes-home.md)
or [ADR-0290](0290-an-addon-was-never-a-system-and-the-arm-4b-blocker-is-four-throwaway-probe-shaders.md),
and `check_addon_globals.py` is named by none of them either.

**The second is the anchors.** `tools/check_vault_anchors.py` reports `Effects` at **2**
anchors naming **1** note — against `Sprite Rig` 40, `Battlefield` 34 and `Audio` 168. And
**48 vault notes cite a `src/effects/` path**. Loop pass 2 owed those anchors
([ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md) dec. 7,
[#310](https://github.com/timbermania/fft-monorepo/issues/310)) and
`docs/agents/refactor-loop.md` says of exactly this that it **cannot be detected after the
fact**: once the old code is gone, pass 8 cannot tell a dropped behaviour from an
unmarked reimplementation. 48 notes' path citations rot on the `git mv`; two comments
survive it.

Status: accepted (2026-09-11). Loop **pass 5** of extraction #7 — plan
(`docs/agents/refactor-loop.md`), which is `/to-spec` → `/to-tickets`. This pass decides
as little as it can and measures as much as it can: three of its eight decisions are
numbers pass 4 named as unmeasured, one corrects a pass-4 row whose stated premise does
not survive a grep, and one coins the name pass 4 deliberately left open.
Corrects **ADR-0290 dec. 5** (the `PSXCameraConvert` row) and **completes** its `PsxUnits`
row. Corrects nothing in ADR-0286, ADR-0287 or ADR-0288.

The plan this pass produces is spec [#1214](https://github.com/timbermania/fft-monorepo/issues/1214)
and eleven tickets [#1215](https://github.com/timbermania/fft-monorepo/issues/1215)–[#1225](https://github.com/timbermania/fft-monorepo/issues/1225). Four block the move —
#1215 (the anchors), #1216 (the manifest), #1217 (the three pre-move edits) and #1220 (the
PSX trio). #1224 (the overlay merge) is droppable without re-opening any decision, which is
what ADR-0290 dec. 7's split bought. **Start with #1215**: it is the only item here that
cannot be recovered after the `git mv`.

## Context

### The membership and every carried number reproduce at `d693cbb47`

ADR-0288's exact command, no `--inside=`:

```
uv run python tools/membership_arms.py \
  $(ls src/effects/*.gd | grep -vE 'CompositorAutopilot|EffectScoreModel|PSXDitherCurves') \
  src/effects/callbacks/*.gd \
  assets/shaders/effect_*.gdshader assets/shaders/effect_*.gdshaderinc \
  assets/shaders/trap_charge_line.gdshader
```

**67 files / 14,441 lines** — 55 `.gd` + 12 shaders, unchanged across four passes and
seventeen commits of `main`. 45 of the 55 `.gd` files declare a `class_name`; the other
ten are the four autoloads and six files reached only by `res://` path.

### The 1,044 test-and-tool references, opened at last

ADR-0287 S5 and ADR-0288 S5 both deferred this to pass 5. ADR-0287's table counted
**shapes**; what a plan needs is **edits**, and the two channels are not paid in the same
unit.

Instrument: a scan over the **2,658 code files** git tracks with a `.gd`, `.tscn`,
`.gdshader`, `.gdshaderinc` or `.tres` suffix, comments stripped from `.gd`, and — the
correction that matters — **string literals stripped before the type scan**. Without that
step every `preload("res://src/effects/EffectData.gd")` is counted a second time as a bare
`EffectData` reach, and the two channels appear to overlap almost completely. They do not.

| channel | lines | files | how it is paid |
|---|---:|---:|---|
| **A** — `res://` path bind (`preload`/`load`) | 414 | 200 | **per LINE.** Each literal is rewritten. Where the file also uses the bound name below, the rewritten line *becomes* the alias line and the count does not grow |
| **B** — bare `class_name` reach (type annotation, static call) | 671 | 116 | **per FILE.** One `const X = ExMateriaEffects.X` at the top and every use below is unchanged — [ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) dec. 4 |
| **C** — bare autoload identifier | 48 | 20 | **free.** The script moves, the `[autoload]` line stays the host's (ADR-0262 dec. 6) |

Channel A splits production 29 / tests 370 / tools 15; channel B splits 59 / 605 / 7.
82 files carry both. **The union is 234 distinct code files — 183 `tests/`, 35 production,
16 `tools/`.** That is the move's bill, and it is a file count, not the 1,044.

Two facts inside it move the plan:

- **Seventeen of the 45 `class_name`s are never reached bare from outside the
  membership**, and a further eleven are reached only from `tests/` or `tools/`. A name
  nothing outside names does not need to be published at all — it drops its `class_name`
  and is reached by in-addon `preload`.
- **Fifteen files reach only the PSX trio.** Their alias line names
  `ExMateriaPlatform`, not `ExMateriaEffects`, so they are the port's bill and not this
  addon's.

### The twelve shaders cost nothing, and the zero has a control

No file outside the membership names a member shader by `res://` path or `#include` —
production, `tests/` and `tools/` all read 0. The instrument is not blind: the same regex
finds `#include "res://assets/shaders/effect_particle_stp.gdshaderinc"` at
`assets/shaders/effect_particle_fold.gdshaderinc:49` and
`assets/shaders/effect_particle_opaque.gdshader:9`, and excludes both because they are
members. `tools/probe_shaders/` does **not** include the membership — it declares
`psx_gamma` itself, which is ADR-0290 dec. 3's whole finding restated from the other side.

### What the façade must publish, derived rather than assumed

A member belongs on `ExMateriaEffects` when something outside the new addon reaches it —
by either channel. Sorted that way the 67 members are:

| | count | what it means |
|---|---:|---|
| reached from **production** outside the addon | 24 | must be published |
| of which leave to `ExMateriaPlatform` | 3 | `PsxUnits`, `CameraCalib`, `PSXCameraConvert` |
| **→ required on `ExMateriaEffects`** | **21** | |
| reached **only** from `tests/`+`tools/` | 15 | a publish *decision*, not a requirement |
| reached from nowhere outside | 28 | 12 shaders, 4 autoloads, 12 internal `.gd` |

The 21 are `CameraData`, `CinematicFacingResolver`, `CurveExplode`, `EffectCurve`,
`EffectData`, `EffectEmitter`, `EffectEndModel`, `EffectInstance`, `EffectManager`,
`EffectPhase`, `EngineFoldCompositor`, `PaletteData`, `PaletteSubsystem`, `PhaseBlock`,
`ScreenData`, `ScreenSubsystem`, `TimelineData`, `TrapChargeLineEffect`, `TrapEffect`,
`TrapOrbitalEffect`, `UnifiedPrimStager`.

### Eight façade citations in three OTHER addons name a member path

`check_addon_globals.py`'s CITE arm requires that a published constant's host-use citation
still resolve and still name its symbol. Eight such lines name a `src/effects/` path:

| citer | lines | member named |
|---|---|---|
| `addons/exmateria_schema/exmateria_schema.gd` | `:71`, `:72`, `:80`, `:91`, `:92`, `:99` | `EngineFoldCompositor.gd`, `callbacks/EffectCallback.gd`, `OTDepthPrimOrder.gd`, `PaletteSubsystem.gd`, `ScreenSubsystem.gd`, `ScreenEffectOverlay.gd` |
| `addons/exmateria_battlefield/exmateria_battlefield.gd` | `:133` | `PaletteSubsystem.build_illumination()` |
| `addons/exmateria_render/exmateria_render.gd` | `:60` | `EngineFoldCompositor.gd` |

All eight go stale on the `git mv`, in **sibling addons this extraction does not
otherwise touch**, and each must be re-labelled a SIBLING ADDON citation (ADR-0212 dec. 7)
in the same commit. The `exmateria_battlefield` row is the one ADR-0288 dec. 8 wants
deleted as production-dead: closing [#1192](https://github.com/timbermania/fft-monorepo/issues/1192)
drains a CITE row as well as four arm-5 lines.

### The PSX trio is three axes, not two and a façade

ADR-0290 dec. 5 ruled `PSXCameraConvert` into *"`CameraCalibration`'s façade"* on the
ground that *"it publishes no arithmetic of its own"*. Measured, it publishes the
chirality axis — and both of its siblings refuse that axis **by charter, in their own
docstrings**:

- `src/effects/PsxUnits.gd:19` — *"MAGNITUDE axis; sign/chirality"* is *"a separate axis"*
- `src/effects/CameraCalib.gd:5` — *"PsxUnits owns the pure PSX magnitude↔game conversions and stays free of"* calibration
- `src/effects/PSXCameraConvert.gd:10` — *"The Y-flip stays here"*, naming the same two decisions the other two do

Its 70 call sites split three ways, and the split is the decision:

| function group | sites | what it is |
|---|---:|---|
| `psx_angle_to_deg`, `deg_to_psx_angle` | 21 | pure delegation to `PsxUnits` |
| `psx_zoom_to_ortho_size`, `ortho_size_to_psx_zoom` | 21 | pure delegation to `CameraCalib` |
| `psx_position_to_godot`, `godot_position_to_psx`, `psx_angles_to_godot_rotation` | 38 | **its own arithmetic** — the Y-negate and the `-pitch` |

**42 of 70 sites are pass-throughs, and the file's own stated reason for keeping them
expires under this move.** `src/effects/PSXCameraConvert.gd:11` — *"Kept as a facade so its
call sites"* do not churn — is true only while nothing churns them. Dec. 4's `git mv`
churns all 70.

### The studio gate is measurably open, and the hot half is the other one

ADR-0286 dec. 11 gates pass 6 on the studio quiescing or an agreed flag-day window
against [#262](https://github.com/timbermania/fft-monorepo/issues/262). Commits by ISO
week:

| | W32 | W33 | W34 | W35 | W36 | W37 |
|---|---:|---:|---:|---:|---:|---:|
| `src/effects/studio/` | 43 | 135 | 162 | 15 | 0 | 0 |
| the 67-file membership | 8 | 21 | 15 | 26 | 7 | 0 |

The studio's last commit is **2026-08-30**; the membership's is **2026-09-06**. #262 was
last updated 2026-08-23. Six branches carry unmerged studio commits and the newest of
them is 2026-09-01. The gate as written watches the half that has been cold for two
weeks.

### The Godot debt is a cache warm of twenty-two seconds, not a hang

Measured in this worktree immediately after fast-forwarding 17 commits of `main`:
`godot --path . -e --quit` completes in **22 s** with **zero** script or parse errors.
The post-merge hang the handoff warns about is real after a *merge*; a fast-forward did
not reproduce it. So the budget line is twenty-two seconds, and the expensive half of the
debt is not the warm — it is that three items still need a Godot process to say anything
at all, and no pass has started one.

### The move manifest is a pass-5 deliverable and three extractions skipped it

`tools/check_move_manifest.py:4` — *"Written at loop **pass 5** by #565, satisfied at pass
6, checked at pass 7"* — [ADR-0168](0168-the-manifest-is-the-only-register-that-can-say-the-right-files-moved.md).
`docs/EXTRACTION-3-MOVE-MANIFEST.tsv` is the only one in the tree; extractions #4, #5 and
#6 wrote none. Its argument is not extraction-#3-specific: once `classify_blueprint.py`
books by location, **a wrongly moved file reads as a win on two instruments** and only a
set-equality register can say the right files moved.

Separately, **110 lines across `docs/` name a member path** and nothing guards them. That
is the trap this line has already paid for once (`BLUEPRINT.md` wrong by 129 lines).

## Decision

**1. The addon publishes 21 names, and the burn-down is seeded at 45 and drained in the
move commit.** `ExMateriaEffects` is the folder-named façade required by ADR-0212 dec. 1;
the 21 names above are its `const X = preload(...)` rows. The 15 test-only names are
**not** published — a name on the façade for a test's convenience widens a consumer's
global surface for a consumer who will never run the test, which is the failure ADR-0212
exists to prevent. Those 15 are reached by in-addon `res://` path from `tests/`, which is
`check_lattice_scene.py` criterion 4's axis and is **declared there**, not hidden.

⚠️ Criterion 4 is therefore **not** 0 for this addon at the move, and that is the
designed outcome rather than a slip. Extraction #4's precedent is the opposite reading of
the same trade and both are defensible; what is not defensible is arriving at pass 9 with
the number unexplained.

**2. Four instruments need ten register seeds, and all ten land in the move commit.**
`WALK_ROOTS` in `classify_blueprint.py` also feeds `check_addon_portability.py`'s
`_walk_roots.addon_roots()`, so **one line arms two instruments at once** — the nine arms
of ADR-0288 dec. 10's prediction all go live on the same commit as the `git mv`, and its
predicted values must be true that commit or the pre-flight reds.

| instrument | registers |
|---|---|
| `classify_blueprint.py` | `WALK_ROOTS` |
| `check_addon_globals.py` | `FACADES` (`:88`), `BURN_DOWN` (`:121`), and `MIN_GD_FILES` in `tools/test_check_addon_globals.py` — its own test asserts all three key sets are equal |
| `check_addon_install.py` | `SUBJECTS`, `INSTALL_BURN_DOWN` — a **hand count**, which that file calls the only evidence its scanner is right |
| `check_lattice_scene.py` | `SUBJECTS`, `DECLARED_MOUNTS`, `SCENE_BURN_DOWN`, `SCENE_ORACLES` |

The ordering constraint extraction #4 discovered holds here unchanged: the `FACADES` row
**cannot precede the addon folder**, because the creep arm fails on a missing directory
unconditionally. Folder, rows and seeds are one commit.

**3. `PsxUnits` becomes `PsxMagnitude`.** The word is not coined here: ADR-0091's own
filename is `0091-psx-magnitudes-convert-to-game-units-at-a-single-per-subsystem-seam.md`,
and `PsxUnits.gd:3` calls itself *"The ONE home for PSX continuous-magnitude"* conversions.
It is the continuous half of `PsxNum`'s discrete/continuous charter split, so the pair reads
`ExMateriaPlatform.PsxNum` / `ExMateriaPlatform.PsxMagnitude` — same prefix, same shape, one
noun each. It carries neither of the collisions ADR-0290 dec. 5 named: *Units* meaning
measurement is gone, and `Unit` the combatant cannot be confused with it. `Magnitude` appears
as an identifier in **three** lines tree-wide and as a `class_name` in none.

Rejected: `PsxScale` (`scale` is a colour-op field and a `Transform3D` property),
`PsxMetric` (*metric* is this refactor's own word, ADR-0114), `PsxQuantity` and
`PsxContinuous` (neither appears in the file, the ADR, or the repo).

**4. `PSXCameraConvert` becomes `PsxChirality`, and ADR-0290 dec. 5's row for it is
corrected rather than carried.** Dec. 5's destination is right and is not re-litigated;
its *reason* is falsified by the 38 sites above. The 42 pass-through sites re-point to
`ExMateriaPlatform.PsxMagnitude` and `.CameraCalibration` directly — they are being
re-spelled anyway, and routing a rewritten line through a delegate that exists only to
stop rewrites is paying the cost and keeping the indirection. What is left is exactly the
sign axis, which is `chirality` — the word ADR-0052, ADR-0057 and all three docstrings
already use.

The trio therefore stays three names and completes ADR-0091 §2's split instead of
compressing it:

| today | at `addons/exmateria_platform/` | axis |
|---|---|---|
| `PsxUnits` | **`PsxMagnitude`** | continuous magnitude ↔ game units |
| `CameraCalib` | **`CameraCalibration`** (ADR-0290 dec. 5, unchanged) | the dialled-in camera mapping — `GODOT_CAMERA_SIZE = 12.6` |
| `PSXCameraConvert` | **`PsxChirality`** | sign / handedness, the ADR-0052 180°-about-X |

This also closes a hole both siblings leave open: each says chirality is *applied by the
caller*, and after this it has an address.

⚠️ **Fallback, stated so pass 6 is not blocked by a naming argument.** If dec. 4 is
rejected on review, the minimum that still discharges ADR-0290 dec. 5 is the spelling fix
`PSXCameraConvert` → `PsxCameraConvert`, matching `PsxNum`. The 38-site measurement stands
either way and belongs in the translation table regardless.

**5. The eight sibling-façade citations are a ticket of their own, and it blocks the
move.** They live in three addons this extraction otherwise does not open, they are
enforced, and they are invisible to every instrument the four pass ADRs ran. Re-labelling
them is mechanical; *finding* them was not.

**6. The studio gate is satisfied on the measurement above, and the window is named as a
date rather than a state.** Pass 6 may start. The half that can collide is the membership,
not the studio, so the gate's operative form for this extraction is: **the `git mv` lands
in one commit, and no other branch holds unmerged commits to the 67 files at that moment.**
`git log --oneline origin/main..<ref> -- <the 67 paths>` over every ref is the check, and it
is cheap. #262 is not closed and is not this line's to close.

**7. The Godot verification debt is three items, and each names its assertion.** ADR-0157
Spike A's rule — verify by loading and asserting, never by watching it come up — applies to
all three. Budget 22 s for the cache warm and a test process each.

| item | why static analysis cannot answer it | the assertion |
|---|---|---|
| ADR-0288 dec. 3's `Unit` → `Node3D` on `EffectManager.gd:48/132/258` | a duck-typed reach or a non-literal `load()` is invisible to every scan used here | load the combat scene, spawn an effect on a unit anchor, assert the instance exists and is parented |
| ADR-0288 dec. 7's autoload merge, 4 → 2 | `[autoload]` resolution is engine behaviour, not a static edge | assert `TintedSurfaces` resolves, that `SURFACE_MAP` and a unit id coexist, and that the two deleted names are gone |
| ADR-0290 dec. 6's `studio_audition_*` rename | held by two `has_method` **string literals** at `EffectViewerScene.gd:773/783` — nothing reds if one is missed | drive the studio's audition action and assert the sound starts |

**8. Extraction #7 writes `docs/EXTRACTION-7-MOVE-MANIFEST.tsv`, 67 rows, at this pass.**
ADR-0168's obligation is generic and lapsed three times; this pass does not back-fill the
three (that would be a register filled in by someone who did not measure it — ADR-0290
dec. 10's own rule) but it does not inherit the lapse either. The manifest's second
register is the vault edges, which is why it and decision 9 are one ticket.

**9. The 48 unanchored vault notes block pass 6, and this is the only decision here that
cannot be deferred.** `Effects` reads 2 anchors; 48 notes cite a `src/effects/` path.
Extraction #2 authored 159 anchors over 67 files for this reason. The anchors are written
**while the files are still at their old address**, because the `R:` path is the only
thing that maps note → file today and the move destroys it. Anything not anchored before
the `git mv` is not recoverable by any later pass.

This is loop pass 2's work, unpaid, surfacing at pass 5 — recorded as that rather than as
a pass-5 invention, because the reason it was missed is instructive: `check_vault_anchors.py`
**reports** coverage and never asserts it (#310, deliberately), so two anchors and forty
look identical in a green pre-flight.

## Considered alternatives

**Publish all 36 externally-reached names on the façade.** Rejected. Fifteen of them are
reached only by tests, and a global name is a global name in every consumer's project
whether or not that consumer runs our tests. The cost of declining is visible and
declared (criterion 4); the cost of accepting is invisible and lands on a stranger.

**Fold `PSXCameraConvert`'s chirality into `CameraCalibration`, as ADR-0290 dec. 5 said.**
Rejected on both siblings' stated charters: `CameraCalib.gd:3` is *"The thin, CALIBRATED
render/camera layer atop PsxUnits (ADR-0091 §2)"* and chirality is exact, not calibrated.
A fold would put the one axis both files name as *separate* inside the one of them that
is dialled in by hand.

**Keep the 45 `class_name`s and ask for an ADR-0212 exemption.** Rejected without
argument: nine addons satisfy the rule, one was drained from 30, and the exemption would
be requested by the largest violator.

**Let pass 6 write the vault anchors as it moves each file.** Rejected. The anchor's
input is the note's `R:` path, which resolves at the *old* address; a pass-6 session
holding a half-moved tree has neither. Extraction #2 authored them before the move and
that ordering is the whole mechanism.

**Back-fill the three missing move manifests.** Rejected, same ground as ADR-0290 dec. 10:
a register completed by someone who did not run the extraction is worse than a missing
one, because it reads as evidence.

## Consequences

- **The move is 234 file edits, not 1,044 reference edits**, and 183 of them are tests.
  Any plan that quoted 1,044 was quoting a shape count.
- **Nine portability arms go live on the `git mv` commit** via one `WALK_ROOTS` line.
  ADR-0288 dec. 10's predicted table is therefore not a pass-9 prediction only — it is a
  pass-6 acceptance criterion.
- **`check_lattice_scene.py` criterion 4 will be non-zero for `exmateria_effects`**, by
  decision 1, and `tools/check_lattice_scene.py:99`'s own warning — a burn-down that cannot reach 0
  *"stops being read"* — cuts the other way here: a declared non-zero is read, and a silent
  zero is not.
- **Three sibling addons are edited by an extraction that does not otherwise touch them.**
  Pass 7's review must read those three diffs as part of this extraction.
- **`PsxChirality` gives the sign axis an address for the first time.** Anything that was
  hand-rolling a Y-negate is now visible as not calling it; nothing here looks for those.
- **The anchor work is a real cost pass 5 did not invent and cannot price precisely.**
  Extraction #2 spent 159 anchors over 67 files; 48 notes here is the same order.

## Soft spots

**S1 — the 234 is a static scan and shares every blind spot the four prior passes have.**
A duck-typed reach, a string-built path, a `load()` on a concatenated name: none of them is
in it. `closure.py` counts 225 non-literal `load()` sites tree-wide. Read 234 as a **floor**.

**S2 — the 21-name façade surface is derived from the same scan, so a name reached only
dynamically reads as internal and would fail at runtime, not at the guard.** The three
Godot items in decision 7 are the only thing that can find such a name, and they are
scoped to dec. 3 and dec. 7 rather than to the façade. A fourth item — load every root
scene with the façade in place and assert no `Invalid access` — is not specified here and
should be.

**S3 — decision 4 re-opens a row ADR-0290 dec. 11 listed as settled.** It is re-opened on
a measurement rather than on a preference, and the fallback in dec. 4 keeps pass 6 moving
if the grill disagrees. But the general risk is real: a pass that can re-open settled rows
on its own evidence can re-open all of them, and this pass re-opened exactly one.

**S4 — the studio quiescence is a commit-rate reading, and a flag day is about conflicts,
not rates.** Zero commits in two weeks with six branches holding unmerged studio work is
consistent with *finished* and with *paused*. #262 is open and nobody was asked.

**S5 — no number here was taken with the pre-flight green.** `main` is red on
`check_adr_shape` — ADR-0275 carries **three** `## Amendment` sections
([#1207](https://github.com/timbermania/fft-monorepo/issues/1207), worse than the two that
ticket records) — and the pre-flight exits at its first red guard, so the guards behind it
are unrun. Every measurement above was taken by running its instrument directly. The
`godot --path . -e --quit` sweep is the one whole-tree check this pass did get green.

**S6 — decision 9 asserts a gap from two counts and a `grep -l`.** *48 notes cite a
`src/effects/` path* is a path-literal scan; a note that discusses the effect runtime
without citing a path is invisible to it, so 48 is a floor on the work and **not**
evidence that the other 207 notes are out of scope. Nobody has read the 48.
