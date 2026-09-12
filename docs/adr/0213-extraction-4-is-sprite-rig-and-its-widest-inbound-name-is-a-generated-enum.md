# Extraction #4 is `Sprite Rig`, and its widest inbound name is a generated enum

Extraction order is chosen by measured isolation
([ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md) dec. 2),
and on that method as literally written **`Sprite Rig` fails**: its inbound
surface is seventeen distinct names, and dec. 2's gloss is *"One symbol is a
port; twelve is a surface with no interface."*
[ADR-0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)
dec. 9 rejected it on exactly that count and dec. 8 named `Character Catalogue`
the strongest candidate for #4.

**This ADR selects `Sprite Rig` anyway, and says which reading decided.** Its
outbound is 6 lines in one file — the best number any unextracted system has ever
read — its autoload shipping debt is 23 lines against `Battlefield`'s 120, and its
path-reference cost is 37 lines against `Battlefield`'s 284. The inbound gate is
overridden, not satisfied, on the ground that **its unit is wrong**: 41 of the 119
inbound lines — 34.5%, the widest single name in the surface — name
`DisplayActivity`, which is a **generated enum**. An enum crossing a seam is a
shared vocabulary, not an interface, and ADR-0141 dec. 2 has no term that
separates a name that is *called* from a name that is merely *named*.

Status: accepted (2026-08-31). Loop **pass 1** of extraction #4. Amends
`docs/agents/refactor-loop.md` → *Extraction order*. Applies ADR-0141 dec. 2's
method a **third** time, and is the experiment ADR-0157 → *Soft spots* S1
scheduled.

Code at trunk `127f4112e`, classifier at `a3cd7ac19`, `touch_matrix.py` at
`3881ab52c` — *"a reading is only meaningful against a stated commit AND a stated
classifier revision — quote both or quote neither"*
([ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md),
the fourth amendment, immediately above dec. 6). ⚠️ **That rule is not dec. 6**,
which is *"the reach count is a FLOOR"*; ADR-0145 and others cite the amendment
under dec. 6's number, and this ADR does not repeat that.

## Context

Extraction #1 is `Render` (ADR-0141 / 0147 / 0148). #2 is `Audio` (ADR-0153).
#3 is `Battlefield` (ADR-0157, built through pass 10; five registers read 0 at
this trunk). Pass 1 is a query, and its method is fixed: three readings off
`classify_blueprint.py` and `touch_matrix.py` — **size**, **inbound
concentration read by distinct symbol**, and **outbound reach into other
systems**, with `platform`, `schema` and `Debug` excluded from the outbound
count.

⚠️ **The unit is the LINE, not the file-edge** (ADR-0131 dec. 5).

⚠️ **`classify_blueprint.py`'s `SH.F` / `SH.LINES` columns are the SHADER half of
each row, not a "shared" surface.** They are `shader_files[b]` and
`shader_lines[b]`. Read as entanglement they invert the truth: `Sprite Rig`'s
1,338 shader lines are **25% of its own body** — one 907-line
`unit_sprite_body.gdshaderinc` — against `Battlefield`'s 959 of 9,151, or 10%.
On this reading `Sprite Rig` is the more shader-heavy system, not the lighter one.

### The reading — trunk `127f4112e`

| system | files | lines | IN | in-names | in-files | OUT | top inbound name | OUT ÷ size |
|---|---:|---:|---:|---:|---:|---:|---|---:|
| `Effects` | 190 | 58,045 | 25 | 9 | 6 | 6 | `PSXCameraConvert` 9 | 0.010% |
| `UI` | 140 | 41,505 | 2 | 1 | 1 | 153 | `UICombatManager` 2 | 0.369% |
| `Battle` | 77 | 23,047 | 187 | 15 | 19 | 126 | `UnitProgression` 41 | 0.547% |
| `Cutscene` | 56 | 16,452 | 17 | 6 | 6 | 73 | `ScenarioDebugSession` 8 | 0.444% |
| **`Sprite Rig`** | **29** | **5,343** | **119** | **19** † | **15** | **6** | **`DisplayActivity` 41** | **0.112%** |
| `Character Catalogue` | 14 | 2,118 | 25 | 7 | 9 | 41 | `CharacterCatalog` 10 | 1.936% |
| `Campaign` | 9 | 1,544 | 32 | 5 | 10 | 47 | `WorldMapProgress` 19 | 3.044% |
| ~~`Battlefield`~~ *(#3)* | 50 | 9,151 | 26 | 1 | 23 | **0** | `ExMateriaBattlefield` 26 | 0.000% |
| ~~`Audio`~~ *(#2)* | 14 | 1,903 | 21 | 4 | 8 | 3 | `SfxRouter` 15 | 0.158% |
| ~~`Render`~~ *(#1)* | 5 | 506 | 1 | 1 | 1 | 0 | `ExMateriaRender` 1 | 0.000% |

† distinct name-strings, which is what the method's "distinct symbols" counts.
The instrument emits **39** `(kind, file, name)` rows carrying them. It resolves
to **17 distinct names** — see dec. 2.

`Debug` is excluded from every OUT cell. Cross-system total **895 lines** over
**290 file-edges**. **This is a FLOOR** (ADR-0131 dec. 6) — duck-typed reaches
carry no type name and are invisible to it.

**The three extracted systems are the method's own control arm, and they read the
way it predicts.** `Render` and `Battlefield` are OUT **0**, and each is now
reached through exactly **one** published name — `ExMateriaRender` (1 line) and
`ExMateriaBattlefield` (26 lines over 23 host files). `Battlefield` went in at
131 inbound lines over 9 symbols and comes out at one façade name; that is what
an extraction is supposed to do to a surface, and it is the strongest available
evidence that a wide inbound count is a fact about the *host's* spelling rather
than an irreducible property of the system. `Audio` is the exception that shows
the cost of a package rather than an addon: OUT 3 and **21 inbound over 4 names**,
because 12 host-side files stayed behind.

## Decision

**1. Extraction #4 is `Sprite Rig`, and outbound plus shipping debt is what
decided.** The inbound gate was overridden on dec. 4's ground, not met.

ADR-0157 → *Soft spots* S1 established that the method actually applied across
its dec. 8 and dec. 9 is **inbound concentration as a gate that outbound cannot
override, with outbound deciding among the systems that pass it**, and that this
was an assertion first made in that ADR rather than anything ADR-0141 ranked. S1
then named #4 as the experiment that settles it, and asked that *"it should say
which reading decided rather than inheriting the sentence above."*

This is that statement. **The gate does not survive contact with its own unit.**
S1's falsification condition was *"an extraction where a wide-but-shallow inbound
surface costs more than a narrow outbound reach"* — the test is run in dec. 4 and
dec. 5, and the width turns out to be largely vocabulary.

**And the gate's premise is already falsified by the control arm.** The gate
treats a wide inbound count as a property of the system — a surface too broad to
publish. `Battlefield` entered extraction #3 with **131 inbound lines over nine
symbols** and reads, at this trunk, **26 lines over one name**
(`ExMateriaBattlefield`). `Render` entered with eleven system edges and reads
**one line over one name**. Neither system's behaviour shrank; the *host's
spelling of it* did. An inbound count therefore measures how many of a system's
internals the host has learned to name, which is the debt the extraction is for.
Using it as an entry gate declines the systems that most need the work.

**2. The count is seventeen, not twenty, and it conflates three kinds of name.**
ADR-0157 dec. 9 and `refactor-loop.md` → *Extraction order* both say **twenty
distinct symbols**. At this trunk `touch_matrix.py` emits **19 rows** carrying
119 lines, and two of those rows are a `res://` preload path spelling a class
that is already in the list under its `class_name`:

- `src/animation/WeaponAnimationSelector.gd` 1 line, beside `WeaponAnimationSelector` 3
- `src/animation/SpriteLayerManager.gd` 1 line, beside `SpriteLayerManager` 14

A third, `src/animation/DistortMovementController.gd` (1 line), is path-only and
has no `class_name` row. So the surface is **17 distinct names — 16 classes and
one path-only file.** Whether the drop from twenty is a real fall or a
measurement difference is not established here: ADR-0157's figure was taken at
`126dfec9b` with a classifier two `Sprite Rig` rebookings older (ADR-0189 dec.
3/7 moved three unit shaders in), and no per-name enumeration was published then
to diff against. **Recorded as a correction to the stated number, not as
progress.**

**3. The outbound is six lines, in one file, and every one is debt.**

| → | lines | site |
|---|---:|---|
| `Battle` | 3 | `src/animation/UnitDisplay.gd` → `Unit` (30, 103, 362) |
| `Battle` | 3 | `src/animation/UnitDisplay.gd` → `ReactionType` (659, 686, 732) |

That is the complete list. There is no `PSXDisplay`-style exclusion to argue
about, because there is nothing else: **6 ÷ 5,343 = 0.112%**, and unlike
`Battlefield`'s eleven — which fell to nine, then rose to ten when a `.tscn`
`ext_resource` was found (ADR-0157 → *Soft spots* C2) — none of these six is a
port reach that extraction produces. `Battlefield`'s comparable debt figure was
**0.121%**.

⚠️ **A published identity between those two numbers has broken, and this is
where it broke.** `refactor-loop.md` → *Extraction order* records, of
`Battlefield`'s ten-line debt, *"At ten the ratio is 0.121% — `Sprite Rig`'s to
three decimal places."* That was exact at `126dfec9b` (6 ÷ 4,957 = 0.12104%
against 10 ÷ 8,247 = 0.12126%). **It no longer holds.** `Sprite Rig`'s outbound
did not move — it is the same six lines — but the system **grew 386 lines**
(4,957 → 5,343, ADR-0189 dec. 3/7's three unit shaders), so the denominator rose
and the ratio fell to 0.112%.

The coincidence is retired rather than repaired, and the sentence in
`refactor-loop.md` is annotated in the same commit. It is a small instance of
ADR-0131's standing warning: **a ratio moved without anybody touching the thing
it measures.** Note it also cuts the other way for dec. 1 — a *falling* outbound
ratio here is not an improving boundary, it is a growing system, and this ADR
does not claim it as progress.

**One file holds the entire outbound severance problem.** `UnitDisplay.gd` is 739
lines, the system's second largest. Nothing else in the system names a class in
another system at all.

**4. `DisplayActivity` is 34.5% of the inbound surface and it is a GENERATED
enum.** This is the finding that overrides the gate.

`src/animation/DisplayActivity.gd` is 25 lines, opens with *"THIS FILE IS
GENERATED -- DO NOT EDIT."*, and is produced from `tools/activity_taxonomy.yaml`
by `tools/gen_activity_taxonomy.py`. It is the only generated file in
`src/animation/`. Its body is one `enum Activity`. **41 of the 119 inbound lines
name it**, 40 of them from `Battle`.

A caller writing `DisplayActivity.Activity.IDLE` is not calling the system. It is
spelling a word in a taxonomy the system happens to host, and the file's own
header says the integer values *"are declaration-order and not a contract."*
Counting those 41 lines as interface width measures the vocabulary's reach, which
is what a taxonomy is *for*.

Reading the 17 names by what a caller does with them:

| kind | names | lines | share |
|---|---:|---:|---:|
| **vocabulary** — enums | `DisplayActivity`, `AnimationOpcodes` | 42 | 35.3% |
| **data carriers** — frozen bundles / Resources read field-wise | `UnitAnimationSet`, `AnimationResolutionMap` | 6 | 5.0% |
| **behaviour** — the rest | 13 names | 71 | 59.7% |

**The behavioural surface is 71 lines over 13 names**, and its own head is
`AnimationStateController` 26 + `SpriteLayerManager` 14 = 40 of 71 (56%). Still
not `Render`'s one name or `Battlefield`'s two — this ADR does not claim
`Sprite Rig` is secretly concentrated. It claims the published figure is
inflated by roughly a third by names no interface design can remove, because
removing them means removing the shared vocabulary itself.

**5. The shipping debt is 23 lines across 5 files, against `Battlefield`'s 120
across 13.** ADR-0157 → *Soft spots* S4 named this *"not the number that decides
whether this system can ship. That one is 120."* It is the reading that most
favours `Sprite Rig`, and the method has no term for it.

| name | bucket | lines | files |
|---|---|---:|---:|
| `DebugConfig` | `Debug` | 17 | 5 |
| `GameLogger` | `Debug` | 4 | 2 |
| `Tune` | `platform` | 2 | 1 |

`Tune` is **two lines in one file** (`SpriteLayerManager.gd:86,759`), against
`Battlefield`'s 62 across 7 — and `Tune` is the reach ADR-0159 spent an entire
pass inverting. `tools/check_addon_portability.py` arm 2 is the guard that reads
these, and this system arrives with a fifth of #3's load.

**6. Path references are 37 lines across 22 files, against `Battlefield`'s 284
across 152.** ADR-0157 → *Soft spots* S3 asked that #4's pass 1 measure path
references **as a reading in its own right** rather than trusting size to cover
them. Done, and the method is stated so it reproduces: a fixed-string scan over
`.gd`, `.tscn`, `.tres`, `.gdshader`, `.gdshaderinc` and `.py` for
`res://src/animation/`, `res://assets/shaders/unit*`,
`res://assets/shaders/crystal_fold`, `res://src/units/CrystalSprite3D`,
`res://src/data/SpritePaletteResolver` and
`res://src/effects/CrystalSpriteCompositor`.

**Production 20 / tests 11 / tools 6.** This is the reading on which `Sprite Rig` is genuinely easier than #3 — a factor
of 7.7 — and ADR-0157's own correction record is why it is measured rather than
estimated: its first figure was **21**, blind to `tests/`, where four fifths of
the real count lived.

**The `tools/` six are the interesting ones, and three of them are a guard.**
`tools/check_unit_shader_paths.py:60-62` hardcodes
`res://assets/shaders/unit.gdshader`, `unit_additive.gdshader` and
`unit_flat.gdshader` — three of the five shaders this system takes with it. The
other three are fixtures in `tools/test_materialize_tunables.py:233,251,259`,
naming `res://src/animation/SpriteLayerManager.gd`.

This is **ADR-0184's finding arriving before the pass that produces it**: *"a
hardcoded directory inside a GUARD is the same defect as one inside a `.tscn`"*,
and *"pass 6 of any system should grep its own guards for the directories it is
about to empty."* `Battlefield` found five such guards the hard way. `Sprite Rig`
has at least one, identified at pass 1 — and per ADR-0184 the dangerous arms are
the ones asserting a **negative**, which go quiet rather than red.

**7. The inbound read by CALLER is 15 host files and `Unit.gd` is 41% of it —
recorded, and NOT used to pass the gate.** ADR-0141 dec. 2 says *"Read inbound by
symbol, never by system count."* Reading by *file* is a third axis it also does
not authorise, and this ADR does not smuggle it in as a substitute.

| host file | system | lines | cum |
|---|---|---:|---:|
| `src/units/Unit.gd` | `Battle` | 49 | 41.2% |
| `src/gpu/CombatLoop.gd` | `Battle` | 12 | 51.3% |
| `src/scenarios/ScenarioVM.gd` | `Cutscene` | 12 | 61.3% |
| `src/gpu/GPUVisualBridge.gd` | `Battle` | 8 | 68.1% |
| *(11 more, none above 7)* | | 38 | 100% |

It matters for **pass 3**, not for selection: a seam designed against
`Unit.gd` alone reaches 41% of the traffic, and against four files 68%. That is a
statement about where to look, and it is why dec. 10 leaves the seam open.

**8. `Character Catalogue` is rejected again, and its blocking objection is
still unsettled.** ADR-0141 closed its alternative with *"Strong candidate for
#3."* and named the objection in the same paragraph: *"a store reaching the
simulator is backwards, and settling that is a boundary question the pass would
have to answer before it could start."* ADR-0157 dec. 8 re-measured it, promoted
it to *"strongest candidate for #4"*, and left the objection exactly where it
was. **Three extractions later nobody has settled it.**

Measured now: **41 outbound lines, 38 of them into `Battle`, 1.936% of its
size** — seventeen times `Sprite Rig`'s ratio. Its inbound is the better number
(25 lines over 7 names, top `CharacterCatalog` 10). ⚠️ The outbound reads **41,
not ADR-0157's 47, and 38 into `Battle`, not 44**; a six-line fall this ADR does
not explain and does not claim credit for.

Choosing it for #4 would mean opening the pass with a grilling that ADR-0157 dec.
8 says *"does not belong inside a pass"*, on the largest outbound severance of
any small system. **It remains the strongest candidate for #5**, and the
objection should be grilled *before* that pass rather than inside it — which is
now the third ADR to say so.

**9. `Campaign` is rejected — its ratio got worse, and #11's collision is now
live.** 1,544 lines, **47 outbound, 3.044% of its own size, still the worst
ratio in the table**. ADR-0157 dec. 7 read 47 out of 1,180 lines (3.98%); the
system grew 364 lines and the ratio improved while the absolute reach did not
move.

The blocker is dec. 11's, and selecting `Sprite Rig` defers it again:
`WorldMapProgress` is now `Campaign`'s **top inbound name at 19 lines**, and
`src/world_map/`'s files are booked `content` under ADR-0156 dec. 1 while the
live world-map build runs on them. ADR-0157 dec. 11 said this *"becomes live
again the moment `Campaign` is scheduled."* It is not scheduled here.

**10. What this ADR does NOT decide.** Pass 1 selects; pass 3 designs
(ADR-0126). Four questions are named and left open:

- **Where `DisplayActivity` lives.** It is generated into the system from
  `tools/`, and 40 of its 41 inbound lines are `Battle`'s. `schema` is the
  obvious home for a vocabulary two systems share, and the kernel is *"enumerated
  by the schema list"* (ADR-0139) — but a *generated* member is a shape the
  kernel has never held, and the generator would have to write across the addon
  boundary. This is the system's version of `Battlefield`'s `CursorBob`.
- **Whether the system splits.** The 17 names sort cleanly into an animation
  half (11 names) and a sprite-presentation half (6), and `SpriteLayerManager`
  (883) + `UnitDisplay` (739) are 30% of the body between them. Naming the split
  here would decide the seam before the audit ADR-0126 requires.
- **How `UnitDisplay.gd`'s six lines are severed.** `Unit` and `ReactionType`
  are `Battle`'s, `Battle` is not extracting, and dec. 3 makes this the whole
  outbound problem.
- **`BLUEPRINT.md`'s claims about this system.** ADR-0126 check 2 — *"Test the
  blueprint's claim about this system; do not inherit it"* — is **not discharged
  here.** #3 pulled it forward into pass 1 as a selection input and found three
  of six crossings were zero and a fourth ran backwards. That was ADR-0157's
  choice, not a rule; this ADR does not repeat it, and pass 2 or 3 owes it in
  full.

**11. Extraction #4 DOES inherit a red baseline, and #3 did not.**
ADR-0157 dec. 10 closed with *"Extraction #3's pass 9 measures against a green
baseline; extraction #2's did not."* At this trunk that is no longer true:

```
check_blueprint_walk: 1 problem(s)
  UNCLASSIFIED — assets/shaders/effect_particle_fold.gdshaderinc  (56 lines)
```

**Cause, traced:** commit `e4c175228`, *"the six `effect_*` entries become stubs
over one include — ADR-0191 dec. 6"*. The refactor was right and the six wrappers
are correctly booked; the **new shared include it created was never given a rule
in `classify_blueprint.RULES`**, so it falls through to `UNCLASSIFIED` and
`check_blueprint_walk.py` — the guard whose whole purpose is that an unbucketed
file is a failure rather than a default (prologue pass 4) — has been red ever
since. All six of its includers are `Effects`, so the rule is one line and the 56
lines belong to `Effects`.

**Not fixed in this commit, deliberately.** Adding the rule moves a published
census row, and ADR-0131 requires that such a move land where it can be measured
rather than as a side effect of a decision document. This pass-1 commit changes
no walked file and moves no number. **Filed as [#728](https://github.com/timbermania/fft-monorepo/issues/728); it must be green
before pass 9 measures anything**, and this is the third time (ADR-0148,
ADR-0184's five hardcoded guard directories) that a file moving somewhere new has
gone silently unbucketed.

## Considered alternatives

**`Character Catalogue`, on ADR-0157 dec. 8's explicit recommendation.**
Rejected in dec. 8 on a re-measurement, and on the ground that its blocking
objection is a grilling rather than a pass. This is a deliberate departure from a
standing recommendation in an accepted ADR, which is why dec. 1 states the
deciding reading rather than asserting the recommendation was wrong.

**`Campaign`, on smallest-first.** Rejected in dec. 9. Worst ratio in the table
for the third consecutive selection.

**`Effects`, on isolation.** IN 25 over 9 names, OUT 6, **0.010%** — numerically
the most isolated system in the package and 28.9% of the host. Scheduled **last**
by `refactor-loop.md` → *Extraction order* because wayfinder map #262 is live on
that tree. Not reopened.

**Defer #4 until the inbound gate is re-specified.** Rejected. The gate's defect
is only visible against a concrete system, and ADR-0157 S1 scheduled #4 as the
experiment precisely so the re-specification would be paid for by evidence. Fixing
the method first would decide it on argument, which is what S1 criticised in
ADR-0157 dec. 1.

**Take `Sprite Rig` but call the inbound gate satisfied**, on dec. 4's
vocabulary split (behaviour is 71 lines over 13 names) or dec. 7's caller
concentration (15 files, 41% in one). Rejected as laundering. **Thirteen is still
past twelve**, and both readings are axes ADR-0141 dec. 2 does not have. The
honest statement is that the gate was overridden with reasons, which is
falsifiable at pass 9; *"it passed all along"* is not.

## Consequences

- `refactor-loop.md` → *Extraction order* gains a `#4` entry and its
  `Sprite Rig` rejection line is corrected — seventeen names, not twenty.
- **Pass 9 scores whether the override was right.** The falsifiable claim is
  dec. 1's: that publishing a 17-name API costs less than severing 38 outbound
  lines into `Battle`. If `Sprite Rig`'s pass 9 reads worse than `Battlefield`'s
  on goals #2 and #5, the gate was right and this ADR was wrong.
- **ADR-0141 dec. 2 is not amended here.** Its unit is shown to be wrong for one
  system; one system is not a re-specification. If #4 lands cleanly, the
  amendment is owed at pass 9 and should distinguish a *called* name from a
  *named* one.
- **`check_blueprint_walk.py` must be green before pass 9** — [#728](https://github.com/timbermania/fft-monorepo/issues/728), dec. 11.
- `Character Catalogue`'s boundary objection is now explicitly owed **before**
  #5, as a grilling. It has been deferred by three consecutive selection ADRs.
- Pass 2 anchors the vault notes before anything moves (ADR-0111 dec. 7,
  ADR-0147 dec. 6's `## Vault: [[…]]` form). `src/animation/` is 18 files and
  none of them carries an anchor today.

## Soft spots

Recorded against this ADR on the ADR-0156 / ADR-0157 precedent, because dec. 1 is
load-bearing and ADR-0157's omission of its own soft spots was itself a finding.

**S1. Dec. 4's vocabulary/behaviour split is a judgement, and it is mine.** No
instrument emits it. `touch_matrix.py` records a name and a line; the three-way
sort in dec. 4 was made by reading each of the 17 files and asking what a caller
does with the name. `AnimationResolutionMap` is the soft one — 392 lines with a
real dispatcher in it, booked *data carrier* because its 5 inbound lines read it
field-wise. Book it *behaviour* and the behavioural surface is 76 lines over 14
names, which does not change dec. 1 and does change the tidiness of dec. 4's
table. **What would falsify the split:** pass 3 finding that
`DisplayActivity`'s 41 lines cannot in fact be published as a vocabulary — that
callers depend on it in some way an enum does not capture — in which case the
gate's count was measuring something real and dec. 1 loses its ground.

**S2. Dec. 2's fall from twenty to seventeen is unexplained, and I did not
reproduce the twenty.** Checking it means running `touch_matrix.py` at
`126dfec9b` with that trunk's classifier, which was not done. Three names moved
into the system between the two readings (ADR-0189 dec. 3/7, unit shaders) and
shaders carry no `class_name`, so they cannot be the cause — which makes the
gap more interesting, not less, and it is recorded as unexplained rather than
smoothed. It does not touch dec. 1: at seventeen the gate still fails.

**S3. The path-reference scan is a fixed-string pattern I wrote, not a tool.**
`Battlefield`'s 284 came from `tools/check_res_paths.py` and a published
manifest; this ADR's 37 came from a `grep -rE` whose pattern is printed in dec. 6
so it reproduces. The two numbers are **not instrument-comparable**, and the
7.7× should be read as an order of magnitude, not a ratio. A pattern that misses
a spelling under-reports, and the failure mode is silent — ADR-0148's shape
exactly. Pass 2 should re-take this with the real tool before any move is
budgeted.

**S4. Selecting against a standing recommendation is the thing most likely to be
wrong here.** ADR-0141 and ADR-0157 both named `Character Catalogue` for the next
slot, and dec. 8's re-measurement did not change its shape — it is still a small
store reaching the simulator. The argument for going around it is that its
blocker is a *design* question with no measurement that resolves it, while
`Sprite Rig`'s blockers are all measured. That is a real argument and it is also
exactly what someone would say to avoid a hard problem for a fourth time. **The
mitigation is in the Consequences and it is weak** — "owed before #5" is what
was said before #3 and before #4.

---

> ⚠️ **CORRECTED 2026-08-31 by [ADR-0214](0214-sprite-rigs-scope-is-anchored-and-its-pass-1-numbers-were-taken-through-a-keyhole.md)
> (extraction #4 loop pass 2). Five numbers above are wrong, including the one in
> the title.** One cause: `touch_matrix.py`'s `record()` stores every bucket and
> its **printed matrix iterates SYSTEMS only**. This ADR read the printout.
>
> | above | corrected |
> |---|---|
> | *title*: the widest inbound name is a generated enum | **`SpriteLayerManager` 56 lines** beats `DisplayActivity` 44 |
> | dec. 4: 119 inbound lines, `DisplayActivity` 34.5% | **206 lines**, `DisplayActivity` **21.4%**; `assembler` is 87 (42%) |
> | dec. 7: `Unit.gd` is 41% of the inbound | **23.8%**; `src/scenes/SequenceViewer.gd` (66) is the widest caller, not `Unit.gd` (49) |
> | dec. 3: six outbound lines, *"that is the complete list … nothing else"* | **49 lines across 15 files**, two of them **literally `PSXDisplay`** (`CameraRelativeRenderer.gd:36,44`). The **six** is dec. 2's defined metric and is correct as that; the *"nothing else"* is not |
> | dec. 5: shipping debt 23 lines / 5 files | **25 / 6** — `PSXDisplay` is missing from the table; `tools/autoload_reach.py` reads 25 |
>
> **S3 is discharged** and dec. 6's 7.7× splits: **11.3× inbound, 1.5× outbound**,
> and per line the outbound is a wash (0.41 vs 0.40 per 100 lines) —
> `docs/EXTRACTION-4-PATH-REFERENCES.md`.
>
> **Dec. 1 stands.** The selection is unchanged; the sentence carrying the
> override is not. See ADR-0214 dec. 5 and dec. 10.
>
> ⚠️ **Line numbers in this ADR are 4-5 lower than the tree** — pass 2 wrote 40
> vault anchor comments into 14 files (`6fb4f0ad8`), which is also the whole of
> the census move from 5,343 to 5,383.
