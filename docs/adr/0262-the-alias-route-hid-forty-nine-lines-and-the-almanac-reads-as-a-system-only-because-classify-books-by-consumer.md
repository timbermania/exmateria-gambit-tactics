# The alias route hid forty-nine lines, and the almanac reads as a system only because classify books by consumer

[ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md)
selected `Character Catalogue` as extraction #6 on one number: arm 7, zero over ten files,
the cleanest opening the corpus has had. That number is still zero. It is also one arm of
nine, and
[#1025](https://github.com/timbermania/fft-monorepo/issues/1025) item 5 says so:

```
arm 6 is seven lines and unexamined. Arms 1, 3, 4, 5 are not measured at all.
```

This pass measures the other eight. The headline is arm 5. A shape scan over the
membership reports **12** sibling-addon lines; the guard's own arm 5, run over the same
ten files, reports **61**. The difference is not a bug in either — it is
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md)
dec. 4's alias route working exactly as designed. `const JobDatabase =
ExMateriaAlmanac.JobDatabase` is one line to a `class_name` token scan and the head of a
chain to arm 5, which binds the alias and then scores every bare `JobDatabase` below it.
Forty-nine lines of this membership's dependency on `exmateria_almanac` live in that gap,
and every selection ADR in this corpus that quoted a sibling count quoted the shape scan.

Fifty-three of those 61 lines target `exmateria_almanac`, which makes the destination
question — a fourth addon, or fold into the almanac — look like it has an obvious answer.
It does not, and the reason is the second finding: `check_addon_portability.py` computes
its arm-5 free set from `_system_of`, a majority vote over `classify()` buckets, and
`classify()` books a file to the system that CONSUMES it
([ADR-0243](0243-the-src-data-tier-is-a-third-addon-and-the-split-the-selection-assumed-does-not-exist.md)
dec. 3). The almanac's 34 files vote `Battle` 14, `content` 11, `UI` 5. So the guard
believes `addons/exmateria_almanac` **is the Battle system's addon**, when
[ADR-0251](0251-the-almanac-is-thirty-two-names-behind-one-and-the-address-collapsed-while-the-buckets-did-not.md)
dec. 1 built it as a book of tables. The 53 lines are debt in the guard's ledger for a
reason that is an artefact of how its subject was named.

Status: accepted (2026-09-08). This is
[ADR-0126](0126-every-system-pass-audits-before-it-designs.md)'s **pass 2** for extraction
#6 — the audit that rules membership and destination before anything moves. It audits; it
moves no files. Reads
[ADR-0257](0257-a-debug-panel-is-not-a-member-and-the-order-that-counted-it-as-one-is-an-artefact.md)
decs. 2, 6, 7 and 8 for the membership it is handed,
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 5 for the four names that used to block this system,
[ADR-0211](0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) decs.
1/4/5 and
[ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md)
dec. 1 for the façade rule,
[ADR-0175](0175-a-port-answers-arm-1-and-not-arm-2-and-the-debug-residue-was-print-statements.md)
dec. 2 and
[ADR-0187](0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)
for the port shape, and
[ADR-0157](0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)
dec. 2 for what it means to name outbound debt and choose the system anyway.
**Supersedes nothing.** ADR-0257 stays accepted and every one of its ten decisions stands;
dec. 10 reserved this pass's four questions and this ADR answers them.

## Context

### The instrument that could not ask eight of the nine questions

`tools/arm7_membership.py` exists because `check_addon_portability.py` arm 7 reads
`score_goals.outbound_reaches`, which walks a real addon directory and so cannot be
pointed at a membership that does not exist yet. It closed
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
soft spot S1 for arm 7 and prints arms 2, 2b and 6 beside it under `--all`. Arms 1, 3, 4,
4b and 5 were never in its universe, and its own docstring says so.

`tools/membership_arms.py` (this pass) adds them. Three of the five are the guard's own
functions handed a `_FileSet` — an object whose `rglob` yields a file list — rather than a
second implementation of them, because two readings of one set drift
([ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)).
That was not a stylistic preference. The first cut of this file wrote its own push regex
for arm 4 and read **zero** on `exmateria_platform`, whose five pushes are spelled
`RenderingServer.global_shader_parameter_set(&"pixel_aspect", v)` — a StringName literal
the hand-rolled pattern did not admit. It was caught by the calibration test, not by
reading.

### The 35 that were never arm 2's subject

ADR-0257 dec. 7 prices `CharacterCatalog` at 35 host lines and rules the autoload design
work rather than disqualification. Re-taken here it is 34 host lines over 13 files, plus
161 lines across 20 test files. **None of them is a portability arm.** Every arm of
`check_addon_portability.py` scans files UNDER AN ADDON ROOT; a host line naming a host
autoload is not in any arm's universe and never was. What the move costs is an install
step — the host's `[autoload]` line has to point at the new path — and the corpus already
pays that step three times over. `project.godot` today autoloads
`res://addons/exmateria_platform/display_port/PSXDisplay.gd`,
`res://addons/exmateria_sound/runtime/audio_engine.gd` and
`res://addons/exmateria_sound/runtime/effect_sfx_engine.gd`.

The membership's own exposure is **two lines**, and the two are not the same kind of
thing. `src/characters/Character.gd:209` writes `CharacterCatalog.get_character(slug)` —
arm 2's predicate exactly. `src/scenarios/AllTemplatesSeeder.gd:184` writes
`catalog = CharacterCatalog`, a bare identifier with no dot, which is the same
standalone-parse break and which **no arm of the guard can see**: `autoload_reaches`
requires the dot, and its docstring gives the ground —

```
`Name.` and not a bare `Name`: an autoload is reached through its members, and
requiring the dot is what keeps a slug string or a prose word out of the count.
```

— while `autoload_route_reaches` (arm 2b) requires the name to be a string handed to
`get_node`. #648 found arm 2's subject in a third spelling; this is a fourth.

## Decision

**1. The membership is 10 files and 1,581 lines, and #1025's 1,530 is stale.** Re-taken
on `153baa0d8`, 19 commits past the tree the ticket was filed against and 41 past
ADR-0257's own measurement. The membership is ADR-0257 dec. 2 + dec. 8 verbatim:
`src/characters/*.gd` (8 files), `src/debug/RosterDebugView.gd`,
`src/scenarios/AllTemplatesSeeder.gd`. **Arm 7 is still 0 names / 0 lines**, which is more
than the selection could claim for itself. `--exclude-panels` drops zero files from this
membership and that is not the rule failing: `RosterDebugView.gd` is a helper, not a
subclass. The rule decided the BUCKET, not the filter.

**2. All nine arms, on this tree.** This closes #1025 item 5.

| arm | subject | reading |
|---|---|---:|
| 1 | reach into one of the eleven systems | **1** |
| 2 | host autoload named as `Name.` | 0 (+2 declared-inside, below) |
| 2b | host autoload named as a `/root/` string | 0 |
| 3 | `#include` leaving every addon root | 0 — the membership ships no shader |
| 4 | `[shader_globals]` name bound but not owned | 0 |
| 4b | `global uniform` declared by a system addon | 0 |
| 5 | sibling addon `class_name`, alias route resolved | **61** (6 free, 55 debt) |
| 6 | `res://` path leaving every addon root | **7** over 6 paths |
| 7 | `class_name` declared outside every addon root | **0 / 0** |

Arm 1 is one line and it is not zero: `src/characters/CharacterTemplateResolver.gd:38`
names `ExMateriaSpriteRig`, which `classify()` books to the `Sprite Rig` system. Arm 7
cannot see it — the declaring file is already inside an addon root, which is precisely
what arm 7 filters out — so the selection instrument was structurally blind to the only
cross-system reach the membership has. It is one line and it is an `ARM1_BURN_DOWN` entry
or a severance, owned by pass 3, on
[ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md) dec. 4's
shape.

**3. Arm 5 is 61 lines, not 12, and the 49-line gap is the alias route.** A `class_name`
token scan sees `const JobDatabase = ExMateriaAlmanac.JobDatabase` and stops. Arm 5 binds
the alias in a first pass and scores every bare `JobDatabase` in the file against the
resolved symbol, because that is what ADR-0211 dec. 4 bought when it chose aliasing over
`preload` — it keeps the use sites spelled the way they already were. Resolved, by root:

| target root | lines | verdict |
|---|---:|---|
| `exmateria_almanac` | 53 | debt |
| `exmateria_platform` | 6 | **free** — the platform port |
| `exmateria_sprite_rig` | 2 | debt |

Four distinct almanac names carry the 53: `UnitProgression` 32, `JobDatabase` 15,
`GambitList` 4, `SpriteDatabase` 2. They are **the same four names**
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 5 named as this system's blockers when it rejected it for extraction #5. They did not
go away; they moved into an addon, which is what took arm 7 to zero. **The shape scan is a
floor and every future selection ADR must read the resolved number.**

**4. `exmateria_almanac` is not a system, and `_system_of` says it is.** The guard's arm-5
free set is `system_of[home] is None`, and `_system_of` is a majority vote over
`classify()` buckets among an addon's own files. The almanac's 34 files vote `Battle` 14,
`content` 11, `UI` 5, `infrastructure` 2, `generated` 2 — so it reads `Battle`, and every
reach into it from anywhere is priced as a reach into the Battle system. That verdict is
an artefact twice over: `classify()` books by consumer (ADR-0243 dec. 3), so a table's
bucket is the name of whoever reads it, and ADR-0251 dec. 1 built the package as a book of
tables with no system of its own. The `Battle` system is `src/`-resident, 66 files and
24,783 lines, none of them in this addon.

This is recorded and NOT fixed here. Widening the free set is a change to an enforcing
guard's verdict on every addon in the tree, it would silently re-price three shipped
extractions, and a selection audit is the wrong pass to make it in. It is why decision 5
does not rest on the 53.

**5. Extraction #6 lands as its OWN addon, and the 55 lines of arm-5 debt are named and
accepted.** Not folded into `exmateria_almanac`. Four grounds, in order of weight:

- **Folding severs no edge; it stops the guard printing one.** The catalogue reaches four
  almanac names on 53 lines whether or not the two share a directory. A fold converts a
  printed dependency into an invisible one, which is the failure mode this corpus has
  named more than once. ADR-0157 dec. 2 is the precedent that matters: it enumerated
  `Battlefield`'s outbound debt line by line and chose the system anyway.
- **The almanac ships no `[autoload]` and should not start.** It is installed for its
  tables and is named from 13 host directories and 153 test lines. A consumer that wants
  `JobDatabase` would acquire a character registry singleton and its install step.
- **The dependency is one-way and folding widens it.** Nothing in `exmateria_almanac`
  names any of the ten members. Folding makes every consumer of any data table ship a
  480-line mutable runtime `Character` and its catalogue.
- **`_system_of` would misattribute the result.** Folded, the almanac still votes `Battle`
  (14 against the catalogue's 10), so the catalogue's arm-1 and arm-4b verdicts, and
  `--system` on every future run, would be booked to `Battle`. Decision 4's artefact stops
  being a pricing quirk and becomes a wrong answer on the extraction's own report card.

The accepted cost, stated so nobody re-sells the fold without answering it: **55 arm-5
lines of debt** (53 almanac + 2 sprite rig), which will be the corpus's FIRST sibling rows
targeting an addon that is neither the kernel nor the port — all 337 rows today target
`exmateria_schema` or `exmateria_platform`. They are DEBT and not RED, because
`package_project` returns `None` for an addon inside the host project and arm 5 takes arm
2's strictness rule verbatim.

**6. The autoload moves with the addon; the `[autoload]` line stays the host's and is
re-pointed.** `CharacterCatalog.gd` is 224 of the membership's 1,581 lines and is the
system's centre; leaving it behind inverts the extraction. The corpus already autoloads
three addon-resident scripts (Context above), and `autoload_route_reaches` is built for
exactly this case — it exempts a name whose `[autoload]` path starts with the addon's own
root, on the ground that the addon ships the script the line points at.

The two member lines are paid, and **the spelling decides which arm sees them**: arm 2b
exempts an own singleton, arm 2 has no such exemption, so a node-path soft-bind reads free
where a bare `CharacterCatalog.` reads as debt. That is `TunePort`'s shape (ADR-0175 dec.
2, built by ADR-0187) and `DisplayPort`'s, and here it needs **three verbs** —
`get_character`, `register`, `add_owned` — against `TunePort`'s six and `DisplayPort`'s
four. `AllTemplatesSeeder.seed(catalog = null)` already takes an injected catalogue, so
one of the two sites is a default rather than a reach and may not need the port at all.
Pass 3 picks between the port and the injection; this pass rules that the class moves and
that the exposure is two lines rather than thirty-five.

**7. The façade publishes NINE names, and `tests/` is why it is not seven.** One global
`class_name` in the folder-named file (ADR-0212 dec. 1) carrying one constant per
published member (ADR-0211 dec. 1). Counted over `src/` alone the answer is seven:
`UnitBirthdays` and `UnitNames` are reached from nowhere in the walk. They are named by
five test files, ADR-0211 dec. 5 rules a test-only host use a real host use, and `tests/`
is not one of `classify_blueprint.WALK_ROOTS` — so the instrument that selected this
membership is structurally unable to see two of the names its façade must publish. **The
surface is every `class_name` the membership declares.** Cost: 9 constants and **59 alias
lines**, one per consuming file per name, against #945's 32 names. `CharacterCatalog` is
reached in 63 files and needs no alias — it is the `[autoload]` line.

**8. The panels are FOUR and 643 lines, and one of them is dead.** #1025 item 4 says five
and 750. `classify()` books four `BaseDebugPanel` subclasses to `Character Catalogue`:
`ProgressionDebugPanel` 420, `BattleBindingDebugPanel` 92, `RosterUniverseDebugPanel` 70,
`RosterViewDebugPanel` 61. `StoryTimelineDebugPanel` (175) names `CharacterCatalog` on
three lines and books to `Campaign`, which is where the fifth came from. The raisers are
`src/scenarios/NavigatorMain.gd:483` and `:498` and `src/scenes/GPUArena.gd:851` — the
ticket's `src/scenes/GPUArena.gd:1201` is past the end of a 959-line file.
`RosterViewDebugPanel` is instantiated by **nothing**; `src/scenes/GPUArena.gd:896` says
so in a comment. They stay host under ADR-0257 dec. 1 and reach the addon through the
published `RosterDebugView` and the `[autoload]`, which is the same route
`src/debug/ProgressionDebugPanel.gd` uses today. Retiring the dead one is its own ticket
and not this one.

**9. Arm 6 is seven lines over six paths, and one of them cannot travel.** ADR-0251 dec. 2
rules that a payload travels beside its reader. Five of the six do — their only other
readers are `tests/` and the `tools/` scripts that GENERATE them
(`parse_unit_birthdays.py`, `build_unit_names.py`, `derive_template_jobs.py`), which are
producers, not consumers. **`assets/sprites/textures/`
(`src/scenarios/AllTemplatesSeeder.gd:50`) is shared** with
`addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd`, two sprite-rig `.tscn` files,
`src/core/AssetManifest.gd`, `src/effects/TrapEffect.gd`, `src/projectiles/Projectile3D.gd`
and `src/ui3/elements/NumberFont.gd`. It stays a host content root and the row survives
the move. The shape that pays it exists and is already in `project.godot` twice —
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md)'s host-injected
`content_root`, carried by `[exmateria_battlefield]` and `[exmateria_sprite_rig]`.

All seven rows are `const NAME := "res://…"` shaped, so for THIS membership arm 6 is exact
rather than a floor — `all_shapes` scans only the `preload`/`load`/`const` spellings while
`res_path_reaches` reads any quoted literal, and
`test_the_catalogue_has_no_row_outside_that_universe` is the control that says the gap
does not touch it. ADR-0251 dec. 2's warning stands unchanged for the five that DO travel:
a payload left behind raises no arm-6 row, because the path moved with the reader, and the
stranger rig is the only instrument that catches it.

**10. Two instruments ship, and neither is a guard.** `tools/membership_arms.py` (all nine
arms plus the inbound façade reading) and `tools/selection_sweep.py` (every system's
membership priced at once, the artefact that re-prices the extraction queue and which had
survived twice only as a file in `/tmp`). Both have no pass/fail and no burn-down, so
neither is a `tools/check_*.py` and `check_guard_registry.py` wants no row for either —
`arm7_membership.py`'s reasoning verbatim. `selection_sweep.py --calibrate` reproduces
`classify_blueprint.py`'s own FILES/LINES table, 19 buckets of 19 exact, and that is its
test. `tools/test_membership_arms.py` holds 26 for the other, every agreement test paired
with a liveness witness on a non-empty set — because goal #5 is enforcing, so a naive
comparison against a green guard is `0 == 0` and passes for a stub.

**11. What this does NOT decide.** The addon's name and directory layout; whether the two
member autoload lines are paid by a port or by injection; the `ARM1_BURN_DOWN` entry's
wording; what happens to the dead `RosterViewDebugPanel`; and whether arm 5's free set
should stop asking `_system_of` (decision 4). The `git mv` is pass 3 and has no ticket yet.

## Considered alternatives

**Fold into `exmateria_almanac`.** Removes 53 of the 55 debt lines — by a wide margin the
largest single number in this audit, and the reason this was not a formality. Rejected on
decision 5's four grounds, of which the first is the one that would survive alone: the
edges are not severed, only unprinted. ADR-0241 dec. 5 is often read as pointing the other
way, since the four names it called blockers now live in the almanac; but it named them as
a reason the catalogue could not be extracted THEN, and what changed is that they became
addon-resident, not that they became the catalogue's.

**Leave `CharacterCatalog.gd` in `src/` and mint a port for it.** This is what a literal
reading of `TunePort` suggests, and it is backwards. `Tune` is a host registry an addon
CONSUMES; `CharacterCatalog` is the catalogue's own centre with 34 host lines reading it.
A port over a class left behind would ship an addon missing 224 of its 1,581 lines and
would not remove a single arm row, since the host lines are in no arm's universe either
way.

**Report arm 5 as the shape scan reads it (12) and move on.** It is what the tooling
offered and what every previous selection would have quoted. Rejected because the number is
wrong by 5x on the one question the pass exists to answer, and because the direction of the
error is always the same — a membership that reaches a sibling through aliases reads
cheapest exactly where it is most coupled.

**Fix `_system_of` in this pass.** It is a real defect (decision 4) and fixing it would
retire 53 of the 55 debt lines by the front door. Rejected: it changes an enforcing guard's
verdict for every addon in the tree, and an audit that re-prices its own subject mid-pass
cannot be checked. Decision 5 is written so that it does not depend on the outcome.

## Consequences

- #1025's five open items are answered: 6 (autoload), 5 (destination), 7 (façade), 8
  (panels), 2 and 9 (the arms). Three of its stated numbers were stale and are corrected
  here — 1,530 lines, five panels at 750, and `GPUArena.gd:1201`.
- Pass 3 inherits a priced move: 9 published names, 59 alias lines, 1 arm-1 burn-down
  entry, 55 arm-5 debt lines, 2 autoload sites, 1 unmovable content root, 5 travelling
  payloads and 20 test files to re-point.
- The first arm-5 debt rows in the corpus that do not target the kernel or the port will
  appear the day the folder exists. A reviewer seeing them should read decision 5, not a
  regression.
- Every selection ADR that quoted a sibling-addon count quoted the shape scan.
  `tools/selection_sweep.py`'s A2/A6 columns are the same shape and carry the same floor;
  its output is an input to a re-take, not a re-take.

## Soft spots

- **S1. The 61 is measured on the membership IN `src/`, and the guard will run it on the
  membership in `addons/`.** Every alias line stays and every file-local resolution stays,
  so the number should not move — but it is an inference, and the first
  `check_addon_portability.py` run after the folder exists is the witness. It can only go
  up.
- **S2. Decision 4 names a defect and leaves it live.** As long as `_system_of` majority-
  votes over consumer-booked buckets, any content addon whose readers cluster in one
  system will read as that system, and arm 5's free set is computed from it. Nothing here
  stops the same artefact pricing extraction #7. Filed as
  [#1059](https://github.com/timbermania/fft-monorepo/issues/1059), which found two things
  this pass did not: the vote is a single line (`check_addon_portability.py:983`) whose own
  comment at `:1073` already states the tier-membership semantics it stands in for, and
  `plugin.cfg` already carries declared, measured, non-standard keys (`engine=`, ADR-0194
  dec. 7; `deps=`), so a declared tier has an established home rather than needing a new
  mechanism.
- **S3. The inbound reading is a `\b<name>\b` scan over stripped GDScript.** It cannot see
  a duck-typed reach, and it over-reads a name that is also an ordinary word. `Character`
  is the risk in this set; its 15 src lines were re-read after the first cut counted five
  shader `//` comments that `strip_noncode` does not strip.
- **S4. Nothing here has been run against a stranger rig.** ADR-0251 dec. 2 is explicit
  that a payload left behind is invisible to every static instrument in `tools/`, and five
  payloads travel in this move.
- **S5. Neither instrument is invoked by `tests/run_all_tests.sh`.** ADR-0257 shipped
  `tools/test_arm7_membership.py` without an invocation and its ADR-0257 dec. 3 pin has
  since drifted 17 to 18 unobserved; `tools/test_membership_arms.py` inherits the same
  gap. Wiring them in cannot happen before the pin is ruled — a red guard added to the
  pre-flight reds it on arrival, which is #770's failure and `check_guard_registry`'s
  three OWED notes verbatim. Both are filed as
  [#1055](https://github.com/timbermania/fft-monorepo/issues/1055).
