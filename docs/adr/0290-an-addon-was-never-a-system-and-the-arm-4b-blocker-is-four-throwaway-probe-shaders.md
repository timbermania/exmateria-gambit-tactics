# An addon was never a system, and the arm-4b blocker is four throwaway probe shaders

[ADR-0288](0288-the-sixty-one-debug-lines-are-four-booleans-and-the-seam-is-three-addresses-once-the-psx-trio-goes-home.md)
left pass 4 two questions it could not answer from a count, and both had a premise that
does not survive measurement.

**The first — *"what is the addon CALLED, and can it be?"* — rests on the claim that an
addon holding part of a system would be a new thing in this corpus.** It would not.
`exmateria_almanac` ships **795 lines booked `UI` and 2,745 booked `Battle`** and is named
for neither system;
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 4 already ruled on it in four words. `exmateria_catalogue` holds **76.9%** of
`Character Catalogue` and leaves 582 lines in the host. `Audio` ships as **two** addons in
a package the walk does not enter. An addon is a shipping unit and a system is a
capability, and the two have coincided in exactly three of the six extractions so far.

**The second — `psx_gamma`, the one item that can *stop* extraction #7 — is not a blocker
and has not been one since the ADR-0074 fold endgame.** `check_addon_portability.py:136`
says *"22 shader files read it"*. Measured at this commit the name has **seven** code
readers tree-wide — three in `UI`'s shaders, four in `tools/probe_shaders/` — and **zero
inside the 67-file membership.** The membership's only involvement is the *declaration* at
`assets/shaders/effect_particle_stp.gdshaderinc:56`, which exists so four throwaway probes
compile. Its sibling `psx_brightness` was deleted from that same include in the same
endgame and now lives as a local `const` in each probe, three lines above. Do that and arm
4b's `Effects` red closes **inside `tools/`** — with no dependency on `exmateria_platform`,
on `UI`, or on [#1187](https://github.com/timbermania/fft-monorepo/issues/1187).

Status: accepted (2026-09-11). Loop **pass 4** of extraction #7 — grill and name
([ADR-0286](0286-extraction-7-is-the-effects-runtime-and-the-studio-that-is-seventy-percent-of-the-bucket-is-a-root-set-that-stays.md)
selection,
[ADR-0287](0287-the-backwards-edge-is-one-misfiled-file-and-the-arm-that-fails-is-the-one-no-selection-ever-ran.md)
audit, ADR-0288 crossings). **Amends nothing and supersedes nothing**; it *declines* to
amend [ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md) dec. 4
and says why (dec. 1). Emits the **Extraction #7 translation table (`Effects`)** into
`docs/context/15-effect-orchestration.md` — goal #2's artifact, and the only thing in the
nine passes that produces one. Reads
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 3/4 for the capability test,
[ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) dec. 1/4 for the address rule
and the temporary-name rule,
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md) check 2 for the blueprint
record, [ADR-0220](0220-the-addon-that-declares-a-global-uniform-provides-it.md) dec. 1/4
for the `psx_gamma` split,
[ADR-0234](0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md)
for the `_12bit` spelling this table reuses rather than re-coins, and
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 4/5 for an addon that is not a system. Ticket:
[#1191](https://github.com/timbermania/fft-monorepo/issues/1191) (selection
[#1184](https://github.com/timbermania/fft-monorepo/issues/1184)). This pass filed two:
[#1198](https://github.com/timbermania/fft-monorepo/issues/1198) (`psx_gamma`'s `Effects`
half, which **removes extraction #7's last blocker**) and
[#1199](https://github.com/timbermania/fft-monorepo/issues/1199) (goal #2's artifact, absent
for extractions #5 and #6). It re-scopes
[#1187](https://github.com/timbermania/fft-monorepo/issues/1187) from *blocks extraction #7
pass 6* to *blocks `UI`* rather than closing it.

⚠️ **This ADR was written as `0289` and renumbered to `0290` before it merged** — its
number collided on `main` with `0289-the-entd-level-byte-is-not-a-level-…`, which landed
while this pass was running and which had itself just been renumbered `0288 → 0289` away
from ADR-0288. **Three different `0289`s existed simultaneously**: that one, this one, and
an unpushed `0289-dont-target-self-is-the-cursor-rule-…` in a third worktree. A high-water
scan is a scan of a moment, and the pass-4 handoff's reservation of `0289`–`0295` was made
from a tree that was already stale by the time this pass opened it.
[#1031](https://github.com/timbermania/fft-monorepo/issues/1031) is collision #15 and is
still unowned.

## Context

### The membership reproduces at `e1d58ab6d`

ADR-0288's own invocation, re-run after merging `main` to the tip:

```
ls src/effects/*.gd | grep -vE 'CompositorAutopilot|EffectScoreModel|PSXDitherCurves'
src/effects/callbacks/*.gd
assets/shaders/effect_*.gdshader assets/shaders/effect_*.gdshaderinc
assets/shaders/trap_charge_line.gdshader
```

**67 files / 14,441 lines**, unchanged. Every number below is taken at this commit and
each names the instrument that produced it.

### An addon has never been a system, and three of the six extractions prove it

`tools/classify_blueprint.py`'s own `classify()` over its own `walk()`, split by whether
the file sits under `addons/`:

| system | in an addon | in the host | in-addon | files in / out |
|---|---:|---:|---:|---|
| `Sprite Rig` | 6,579 | 0 | **100%** | 34 / 0 |
| `Render` | 506 | 0 | **100%** | 5 / 0 |
| `Battlefield` | 12,981 | 24 | 99.8% | 55 / 1 |
| `Character Catalogue` | 1,937 | 582 | **76.9%** | 12 / 3 |
| `Battle` | 2,745 | 29,649 | 8.5% | 15 / 73 |
| `UI` | 795 | 48,909 | 1.6% | 6 / 148 |
| `Effects` | 0 | 58,124 | 0% | 0 / 191 |

Two rows are the finding.

- **`Character Catalogue` — the most recent extraction — already ships an addon holding
  77% of its system.** The other 23% is three `src/debug/` panels
  (`ProgressionDebugPanel` 420, `BattleBindingDebugPanel` 92, `RosterUniverseDebugPanel`
  70). Whether that is residue or a ruling, it is the shipped state and nobody called it a
  category error.
- **`Battle`'s 2,745 in-addon lines and `UI`'s 795 are inside `exmateria_almanac`**, an
  addon named for neither, and that placement was *argued*: ADR-0262 dec. 5 rejected
  folding the catalogue into it on four grounds and accepted 55 arm-5 debt lines to keep
  the two apart. ADR-0262 dec. 4's heading is the sentence: **`exmateria_almanac` is not a
  system.**

ADR-0121 dec. 1 is the rule that looks like it says otherwise — `godot-learning/addons/<system>/`.
It is an **address** rule, and its own worked example has since split: dec. 1 cites
`addons/exmateria_sound/` as `Audio`, landed, and `Audio` today is **two** addons
(`exmateria_spu` + `exmateria_sound`) in a package
[ADR-0153](0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md) dec. 1
deliberately put outside the walk. One system, two addons, zero of them in
`godot-learning/addons/`.

### What the blueprint actually says `Effects` is

`docs/context/37-the-blueprint.md:35-38`, the whole entry:

> **Effects**: The effect timeline player — a multi-channel script over time, its particle
> simulation, and the **channel vocabulary** every consumer implements. Depends on
> nothing. _Avoid_: VFX, effect system (the vault's ROM-shaped cluster).

**Not one clause of that names the studio.** The three parts are the timeline, the particle
simulation and the channel vocabulary, and `BLUEPRINT.md:424-427` tabulates exactly those
three. The 67-file membership is all three and nothing else. So the addon holds **100% of
what the blueprint says `Effects` is** and **24.8%** (14,441 of 58,124) of what
`classify_blueprint.py` books to the bucket — and the bucket is a **consumer census**
(ADR-0243 dec. 3, restated by ADR-0262 dec. 4), not a capability.

The _Avoid_ list bars **VFX** and **effect system**. It does not bar `Effects`, and the
list governs vocabulary rather than package names: `Audio`'s entry bars *sound* and the
shipped addon is `exmateria_sound`, which the blueprint records in the same sentence
rather than forbidding. `Render`'s entry states the rule outright — the blueprint names the
role, the shipped addon gets its own name.

### `psx_gamma` — every code site, this commit

`grep` over the four shader suffixes, then each hit's comment stripped, so a line survives
only if the name is in *code*:

| where | sites | what |
|---|---:|---|
| `assets/shaders/effect_particle_stp.gdshaderinc:56` | 1 | **declaration**, inside the membership. No shader that includes it reads the name |
| `src/ui3/shaders/` — `formation_box.gdshader:20`, `formation_box_sub.gdshader:20`, `formation_orb.gdshader:26` | 3 | reads, `UI`'s, declared by `UI`'s two `.gdshaderinc`s |
| `tools/probe_shaders/` — `effect_particle_mode0..3.gdshader` | 4 | reads, in throwaway probes that `#include` the membership's file for the declaration |

Seven code sites, seven files, **none of them an `Effects` production shader.** The
`22 shader files read it` in `check_addon_portability.py:136` and ADR-0190's prose behind it
predate the ADR-0074 fold endgame that deleted the `pow(col, psx_gamma)` branches;
`src/effects/EngineFoldCompositor.gd:130` records the deletion and
`assets/shaders/effect_particle_fold.gdshaderinc:24` records the result.

The repair pattern is in the same file, three lines above the declaration. The endgame
deleted `psx_brightness` from the shared include, and
`tools/probe_shaders/effect_particle_mode3.gdshader:9-11` now carries:

```glsl
// psx_brightness: a plain local const on these throwaway probe copies (the shared global was
// deleted in the ADR-0074 endgame; the production folds bake their gain per-producer).
const float psx_brightness = 2.2;
```

### Goal #7 inside the membership, and who owns it

`tools/score_goals.py`'s own lexicon and its own comment/docstring stripping
(`JARGON`, `_cut_comment`, `strip_noncode`, `_blank_block_comments`), applied to the 67
files: **111 jargon code lines** — `psx` ×109, `fft` ×2 — over **25 files**. The top five
are `CinematicFacingResolver.gd` 15, `PSXCameraConvert.gd` 14,
`callbacks/SpiralMeshCallback.gd` 11, `EffectInstance.gd` 7, three callbacks 6 each.

**38 of the 111 either live in one of ADR-0288 dec. 4's three files or name one of them.**
That matters because of where dec. 4 sends them. `PLATFORM_EXEMPT` in `score_goals.py` has
**exactly one entry** — `Render`, on ADR-0150's grounds — and goal #7 is scored
**per system**, over `docs/GOALS.tsv`. `platform` is a tier, not one of the eleven, so no
goal row reads it and no run scores it.

[#583](https://github.com/timbermania/fft-monorepo/issues/583) already says this about the
sibling file: once `PSXDisplay.gd` sits in the platform bucket its 26 jargon lines have no
exemption, and the rename *"is what discharges them rather than importing the defect"*.
Extraction #4's own table carries the executed version — `psx_camera_angle_12bit` →
`camera_angle_12bit`, on the finding that the port does not spell it `psx` and the prefix
was echoing nothing (ADR-0234, #848).

### The three annotations, and the six that are prose

Every `Unit`-shaped token in the membership:

| site | kind |
|---|---|
| `EffectManager.gd:48`, `:132`, `:258` | **type annotations** — `caster: Unit`, `target: Unit`. This is arm 7's 1 name / 3 lines, and ADR-0288 dec. 3's repair |
| `EffectInstance.gd:841-842`, `CameraSubsystem.gd:147`, `UnitTintOverlay.gd:15/35/49` | **prose** — docstrings naming `Battle`'s class |

`spawn_trap_effect` (`:206`) takes its target **untyped**, which is why dec. 3 is three
lines and not four. The six prose sites score nothing and are not debt to any arm — and
they are the addon's own docstrings teaching a reader the coupling ADR-0126 check 2 just
established does not exist.

### The overlay merge's real blast radius

`UnitTintOverlay` is named on **34** lines, `MapTintOverlay` on **40**. Two of the namers
are inside already-shipped addons —
`addons/exmateria_battlefield/terrain/DynamicGeometryBuilder.gd:33/561` and
`addons/exmateria_schema/colour_model/ColorStack.gd:325` — and **all three are comments**.
The live reach was inverted to a `map_material_created` signal at #589 (ADR-0175 dec. 5),
and the comments narrate the old design. So no extracted addon's *code* breaks on a rename
or a merge; three lines of *prose* in two shipped addons go stale.

### The audition pair is already half-marked

ADR-0288 dec. 6 books `EffectInstance.audition_container` / `audition_sound` to the studio
without moving them. Read end to end, the chain is four hops and **the host half already
carries the marker**:

```
studio/SoundContainerProjector.gd:115   {"kind": "audition_container", …}
studio/EffectStudioPage.gd:6727         _host.has_method("studio_audition_container")
src/scenes/EffectViewerScene.gd:768     func studio_audition_container(index)
src/scenes/EffectViewerScene.gd:773     _current_effect.has_method("audition_container")
src/effects/EffectInstance.gd:480       func audition_container(...)          ← the runtime's, unmarked
```

### Goal #2's artifact has lapsed for two extractions

`docs/GOALS.tsv` carries rows for four subjects: `Render`, `Audio`, `Battlefield`,
`Sprite Rig`. `grep 'translation table' docs/context/*.md` returns three tables, for
extractions #1–#4. **Extraction #5 (the almanac, ADR-0251) and extraction #6 (the
catalogue, ADR-0267) both landed with neither.** Neither ADR mentions `GOALS.tsv` or a
translation table at all.

## Decision

**1. An addon is a shipping unit, a system is a capability, and ADR-0134 dec. 4 stands
unamended.** It rules on the **system** — the studio and the runtime are one, by
ADR-0115 dec. 3's asymmetry test. ADR-0286 dec. 4 rules on the **addon** — the runtime
ships, the studio is a root set that stays. Those are claims about two different objects
and neither contradicts the other. The only rule that could have coupled them is ADR-0121
dec. 1, and it is an address rule whose own exemplar has since become two addons outside
`godot-learning/addons/` entirely.

What *is* new about extraction #7 is the **fraction**: 24.8% against
`Character Catalogue`'s 76.9%. That is a fact about the studio's size, not a new category,
and ADR-0134 dec. 5 already published it (`Effects` is 38,162 lines, not 16,176). Record
the distinction as a term rather than an amendment, because the thing that goes wrong is a
reader inferring the system's boundary from an `ls` of `addons/`.

**2. The addon is `addons/exmateria_effects/`.** It is what ADR-0288 dec. 10 already wrote
into the metric prediction, and it is admissible on every rule that governs the choice:
the _Avoid_ list bars *VFX* and *effect system*, not `Effects`; the blueprint's `Render`
entry licenses a shipped addon naming itself; `exmateria_sound` is already an addon whose
name sits on its own system's _Avoid_ list, recorded rather than forbidden.

**A qualified name — `exmateria_effect_runtime`, `exmateria_effect_player` — is rejected
on ADR-0121 dec. 4's own ground.** Dec. 4 rejects temporary names because *"a temporary
name has to be un-renamed later, in the commit where attention is lowest."* A qualifier
here encodes one fact — the studio has not moved yet — that ADR-0286 dec. 11 expects to
change, into a name that 67 files, a façade global, a walk root, a `classify_blueprint.py`
rule and every future citation would have to carry.

⚠️ **Add `addons/exmateria_effects/` to `WALK_ROOTS` in the same commit as the move**
(ADR-0288 dec. 10). Checked while ruling dec. 1: `check_addon_portability.py`'s
`_system_of` is a majority vote over `classify()` buckets among an addon's own files, and
all 67 book `Effects`, so the new addon reads `Effects` and not the ADR-0262 dec. 4
artefact. The studio stays booked `Effects` in the host, which is correct and is why the
bucket does not shrink.

**3. `#1187` does not block extraction #7, and the `Effects` half of arm 4b is payable
inside `tools/`.** Delete `global uniform float psx_gamma;` from
`assets/shaders/effect_particle_stp.gdshaderinc:56` and give
`tools/probe_shaders/effect_particle_mode{0,1,2,3}.gdshader` the declaration they are the
only readers of — as a local `const float psx_gamma = 1.4;` matching `project.godot:882`,
which is verbatim what the same four files already do for `psx_brightness` and keeps the
probe self-contained, or as their own `global uniform` line if a future session wants the
value to stay scrubbable from the F3 panel. Either spelling removes the name from the
membership; the `const` is the one with a precedent in the file.

Filed as [#1198](https://github.com/timbermania/fft-monorepo/issues/1198). Combined with
ADR-0287 dec. 3's `psx_fx_stretch` delete-and-include, **arm 4b goes to 0 for
this membership with no cross-package dependency at all**, which is ADR-0288 dec. 10's
predicted `2 → 0` reached by a cheaper route than the one it predicted.

**4. `#1187`'s circularity argument is wrong, and the ticket survives it.** The stated loop
is *the addon does not provide `psx_gamma` because nobody declared it in an addon, and
nobody can declare it in an addon because the addon does not provide it.* The second half
is false: nothing prevents a `.gdshaderinc` under `addons/exmateria_platform/display_port/`
from declaring the name, and `psx_sprite_stretch.gdshaderinc:41` + `plugin.gd:116` are the
same addon doing exactly that for `psx_fx_stretch`. `plugin.gd:37` is a faithful
**description of this tree**, not a refusal on principle, and ADR-0220 dec. 4 says so in
its own words — the question is left **open**, which is not the same as blocked.

So #1187 is re-scoped, not closed: it is still the right fix for `UI`'s two declarers and
still the only version that closes ADR-0220 dec. 4, and it stops being a **gate on pass
6**. Its `Blocks` field moves from extraction #7 to `UI`'s.

**5. ADR-0288 dec. 4's move carries a rename, or it launders 38 jargon lines into a tier
nothing scores.** The destination is right and is not re-litigated: `PsxUnits.gd:3` calls
itself the one home for PSX magnitude conversions, ADR-0091 declares that seam, and
`ExMateriaPlatform.PsxNum` is already the discrete half of the same charter split. What
dec. 4 does not say is that `platform` has **no** goal-#7 exemption (`PLATFORM_EXEMPT` is
`{"Render"}`) and **no** goal-#7 row (`GOALS.tsv` is per system), so three `Psx`-spelled
names crossing into it are not paid, they are *unscored*. Three rows, all reusing the
family #583 opened rather than coining rivals:

| today | say now |
|---|---|
| `CameraCalib` | **`CameraCalibration`** — spelled out, beside `DisplayCalibration` (#583) |
| `PSXCameraConvert` | **`CameraCalibration`'s façade** — it already calls itself a thin facade over ADR-0091's seams; it publishes no arithmetic of its own |
| `PsxUnits` | ⚠️ **open, and this ADR does not coin it.** `Units` here means *measurement*, and `Unit` in this repo is a combatant — the most dangerous collision available |

`pitch_psx` / `yaw_psx` / `base_yaw_psx` in `CinematicFacingResolver.gd` take
`_12bit`, which is ADR-0234's executed spelling and not a new word.

**6. "Booked but not moved" becomes checkable by one rename, and this is what makes dec. 6
a state rather than a deferral.** A booking with no mechanical carrier is a sentence in an
ADR; `classify_blueprint.py` books *files* and `ROOT_SET.tsv` books *roots*, and neither
can book a **method**. Rename `EffectInstance.audition_container` / `audition_sound` to
**`studio_audition_container`** / **`studio_audition_sound`**, matching the host wrappers
that already carry the prefix, and `grep -rn studio_audition` returns the entire four-hop
chain. Cost: two `func` lines, two `has_method` string literals at
`EffectViewerScene.gd:773/783`, and no test — the eight test references name the *action
kind* `"audition_container"`, which is the projector's vocabulary and does not change.

**7. ADR-0288 dec. 7 splits into a rename and a merge, and only the merge is new code.**
Its S3 says the decision is *designed so that it is separable*; this makes the seam
concrete rather than principled.

- **The rename is pass 6's, free, and lands whatever else happens.** `UnitTintOverlay` →
  **`TintedSurfaces`**, `register_unit` → `register_surface`, `unit_id` → `surface_id`.
  Measured: 34 namers, no code reach from any shipped addon, and the name is
  already justified by ADR-0288's own reading — the class never dereferences the id it is
  keyed by.
- **The merge is the new code and takes its own ticket**: deleting `MapTintOverlay`,
  reserving `SURFACE_MAP`, and moving `BattlefieldWiring.gd:76-78` onto the merged verb.
  If extraction #7's window will not hold it, the rename still lands and the translation
  table still reads true, because `MapTintOverlay` is then *documented* as the erased-key
  case rather than *implemented* as it.

The payload keeps the word it already has: **colour op** (`37-the-blueprint.md:349`,
ADR-0128), `ExMateriaSchema.ColorRecipe` in code. This ADR coins nothing for it, which is
the correction PR #1197 made to ADR-0288's first draft and the reason this pass exists.

**8. The translation table is emitted into `docs/context/15-effect-orchestration.md`**, as
*"Extraction #7 translation table (`Effects`)"*, with two terms added to `CONTEXT.md`'s
entry for that cluster. **Ten rows** — the addon's identity, addon-vs-system, the two
overlays, the PSX trio, the `_12bit` parameters, the audition pair, `EffectsDebug`, the
sound façade, and the spent *colour recipe* row kept as the warning. It is
written at pass 4 and **re-measured at pass 9**, which is extraction #4's precedent — that
table's rows say what the tree does, not what the plan said.

**9. The blueprint's three claims are recorded in `BLUEPRINT.md`, not rewritten.** ADR-0288
dec. 3 ruled it and did not do it; this is the edit. *"Depends on nothing"* already carries
a `#315` blockquote from the pluckability audit, so the falsification is **appended with
numbers** to what is there rather than opened as a second note; *"`Effects` reads `Audio`'s
`feds.bin`"* is recorded **confirmed**, because a register that only ever records failures
cannot be read as a measurement; and the role-binding sentence is recorded **true in
behaviour, false on three annotations**. ADR-0126 check 2 is not re-run (ADR-0288 discharged
it) — this writes down what it found.

**10. Goal #2's artifact has lapsed twice and gets a ticket, not a silent catch-up.**
Extractions #5 and #6 landed with no translation table and no `GOALS.tsv` rows. Writing
them now from outside their passes would be this corpus's own named failure — a register
filled in by someone who did not measure it. Filed as
[#1199](https://github.com/timbermania/fft-monorepo/issues/1199), which also asks for the
cheapest honest guard: nothing today distinguishes *no rows yet* from *never measured*,
because `score_goals.py` prints the former for both.

**11. What pass 5 inherits, and what it must not re-open.** Settled here: the addon's name
(dec. 2), whether `ADR-0134` needs amending (dec. 1, no), whether `#1187` gates pass 6
(dec. 3/4, no), the seven table rows, and dec. 7's split (dec. 7). Still open and **owed to
pass 5**: `PsxUnits`' new name (dec. 5), the studio's ~43,700 lines and the
[#262](https://github.com/timbermania/fft-monorepo/issues/262) flag-day gate (ADR-0286
dec. 11), and the **1,044 test-and-tool references** ADR-0287 S5 and ADR-0288 S5 have both
carried unopened.

## Considered alternatives

**Amend `ADR-0134` dec. 4 to permit an "Effect Authoring" system.** Rejected, and it is
the trap this pass was set to find. The amendment is not needed: dec. 4's clause is about
the **system**, and ADR-0286 dec. 4 never claimed otherwise. Amending it to license an
addon boundary would put a *packaging* fact into an ADR whose subject is the ADR-0115
dec. 3 capability test, and would leave the next reader believing the studio had been
re-categorised when nothing about it changed.

**Name the addon `exmateria_effect_runtime` so the name is honest about the 24.8%.**
Rejected — ADR-0121 dec. 4, above. The qualifier is true today and expected to stop being
true, and un-renaming a published façade global is the most expensive rename this corpus
has.

**Name it for what it holds, `exmateria_almanac`-style, and free it from the system name
entirely.** Genuinely considered, and it is the strongest alternative: the almanac's name
is *why* ADR-0262 dec. 4's `_system_of` artefact is legible as an artefact. Rejected
because the almanac earned its name by holding pieces of **three** systems and no
capability; this addon holds **one** capability, and it is precisely the one the blueprint
names in its `Effects` entry. A non-system name here would hide a clean mapping rather than
disclose a messy one.

**Take `#1187` as the blocker it was filed as and wait.** Rejected on the measurement: the
membership does not read `psx_gamma`, so waiting buys nothing an edit under `tools/` does
not. ⚠️ It is worth saying what would have happened otherwise — extraction #7's pass 6
would have been gated on `UI`'s shaders and on another addon's `plugin.gd`, on the strength
of a count in a guard's comment that the fold endgame had already invalidated. **The
blocker was real, the reason for it was stale, and nothing in nine arms could tell the
difference** — an arm reports that a declaration exists, never whether anything reads it.

**Rename the PSX trio inside `Effects` before dec. 4 moves it.** Rejected: the rename is
the *platform's* vocabulary question and #583 owns that family. Renaming in the losing
package means doing it twice and reviewing it in the commit that also changes 10 files'
addresses.

**Land the `TintedSurfaces` rename in this pass.** Rejected — pass 4 decides names, pass 6
executes them. Extraction #4 is the precedent: ADR-0217 is pass 4 and the 61 alias
declarations landed at #746. A rename in the pass before the addon exists has to be rebased
through the `git mv` that creates it.

**Write extraction #5's and #6's translation tables while the format is in hand.** Rejected.
A translation table is *old term → new*, and neither pass measured one; filling the rows
from outside the extraction produces a register whose evidence column cites nothing —
the failure ADR-0148 and ADR-0149 are both about. A ticket, owned by someone who can
measure, is the honest form.

## Consequences

- **The one item that could stop extraction #7 is gone, and it was gone before this pass
  started.** ADR-0287 S3 filed it, ADR-0288 dec. 11 (c) ordered it first, and both were
  reading `check_addon_portability.py`'s own prose. The general lesson is narrower than
  "check your sources": **a portability arm answers *is this name declared here*, and never
  *does anything here read it*** — so a declaration with no local reader is invisible to
  the arm that reds it, and the fix looks like another package's work when it is a delete.
- **Three of the six extractions did not put their system in one addon, and nobody wrote it
  down.** `Audio` is two addons outside the walk, `Character Catalogue` leaves 23% in
  `src/debug/`, and `exmateria_almanac` holds three systems' files. Extraction #7 is the
  first to *ask*, which is why the question read as novel.
- **Moving a file into `platform` removes it from goal #7's reach.** `PLATFORM_EXEMPT` is a
  map so a second system cannot acquire an exemption silently (ADR-0220's sibling
  reasoning), but the tiers are outside the scored set entirely, so a `Psx`-named file
  reaching `exmateria_platform` stops being counted rather than stops being jargon. #583
  knows this for one file; dec. 5 says it for three more.
- **Two passes' worth of naming was recoverable from the tree itself.** The `studio_`
  prefix on the audition pair and the `_12bit` spelling for the facing parameters are both
  already in the repo, on the other side of the exact seams in question. ADR-0288 dec. 7's
  *"colour recipe"* slip and these two are the same shape read from opposite ends:
  **check whether the word exists before coining it, and the place to check is the caller.**
- **A markdown line citation is a reference that rots when anyone edits above it, and one
  had already rotted by 129 lines before this pass touched it.** `BLUEPRINT.md:477` is
  cited by `docs/WORLD_MAP_PORT_LIST.md:33` and ADR-0156:40 for §9 Campaign; at
  `e1d58ab6d` line 477 is **blank** and the target is line 606. Both citations are
  repaired here (to `:635`, after this pass's own inserts). ⚠️ It is also why dec. 9's note
  in `docs/context/37-the-blueprint.md` is written as an **extension of the existing line**
  rather than as a new paragraph: `:349` (*colour op*), `:372` and `:384` (*Port*, *Role
  binding*) are cited by ADR-0288, by this ADR and by the pass-4 handoff, and a nine-line
  insert above them would have moved all three silently. The file is 387 lines before and
  after. **This corpus cites markdown by line and has no guard for it** —
  `check_adr_classification.py` proves a *link* resolves and `check_adr_quotes.py` proves a
  *quotation* is present; nothing proves a line number points at what it claims.
- **Goal #2's artifact is produced by exactly one pass and the loop has skipped it twice.**
  Nothing reds when it is missing — `score_goals.py` reads `GOALS.tsv`, and a system with no
  rows is reported as *"no rows in docs/GOALS.tsv yet"*, which reads as *not yet* rather than
  *never*.

## Soft spots

**S1 — this pass started no Godot process either, and that is now three in a row.**
ADR-0287 S2 and ADR-0288 S2 both said it. The honest statement is that pass 4 changed no
code, so a run would have proved nothing about *this* pass — and that the debt it names is
not pass 4's to pay: dec. 3's `Unit` → `Node3D` and dec. 7's autoload merge are pass 6's
edits and must be verified by loading and asserting, per ADR-0157's Spike A. ⚠️ There is a
second reason this pass declined, and it should be measured before pass 5 assumes the run
is cheap: this worktree fast-forwarded 11 commits immediately before the pass, and a cold
or post-merge `.godot` class cache is a known hang in this repo. **Budget a cache warm, not
a two-second scene load.**

**S2 — dec. 3's claim that the probes are the only readers is a static scan over four
shader suffixes, and shaders can be built as strings.** Every `psx_gamma` site was read by
hand and the seven are unambiguous, but a `Shader.new()` with `code = "…"` would be
invisible to it, as would a name assembled at runtime. `RenderingServer.global_shader_parameter_set(&"psx_gamma", v)`
at `PSXDisplay.gd:193` proves the *value* is pushed; it does not prove nothing reads it in
a way this scan missed.

**S3 — dec. 5 names two of the trio and leaves the third open, which is exactly the shape
ADR-0286 dec. 7 warned about.** A binary or blank in a soft spot is a guess about the
shape. `PsxUnits` is left open deliberately — the collision with `Unit`-the-combatant is
real and the right word may be `PsxNum`'s (the charter split is *discrete* versus
*continuous*, and neither of those words is in either name) — but it is one row of a
translation table that ships without it.

**S4 — the 24.8% is measured against a bucket that includes the studio, and the studio is
still moving.** `src/effects/` took ~495 commits in 60 days. The ratio will be different on
the day the addon lands and the *fraction* is not load-bearing for dec. 1 or dec. 2; only
the direction is. Anyone quoting 24.8% after pass 6 should re-take it.

**S5 — dec. 6's rename is argued from a `grep` returning the whole chain, and the chain is
held together by two `has_method` string literals.** That is the property being exploited —
a duck-typed call is invisible to `closure.py` — and it is also the risk: the rename must
change the literal and the `func` together, and nothing mechanical will red if one is
missed. It is two pairs of lines; it is still the kind of edit that reads green and behaves
dead.
