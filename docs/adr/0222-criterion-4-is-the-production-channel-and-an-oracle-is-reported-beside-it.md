# Criterion 4 is the production channel, and an oracle is reported beside it

- **Status:** Accepted
- **Date:** 2026-09-03
- **Constrains:** ADR-0164 dec. 4, ADR-0189 dec. 8, ADR-0194, ADR-0202 dec. 1, ADR-0205
  dec. 3 / dec. 7, ADR-0217

## Context

### Criterion 4 could not reach its own target, and the target was the point

`check_lattice_scene.py` scores ADR-0164 dec. 4 criterion 4: **no file outside
`addons/<subject>/` may name an `res://addons/<subject>/…` path, except at a declared
mount.** Target 0. For `exmateria_sprite_rig` it read **7 sites over 4 files** and had read
some non-zero number since #744 landed the move.

Six of those seven cannot be paid by any move available:

| file | rows | why it cannot move |
|---|---|---|
| `tests/UnitMaterialVariantTest.gd` | 4 | names `res://src/ui3/formation/FormationScene.gd`, `res://src/scenarios/ScenarioVM.gd`, `res://assets/materials/unit.tres` |
| `tests/ScenarioDeadUnitFadeTest.gd` | 2 | preloads `res://src/scenarios/ScenarioVM.gd` |

Both are **independent oracles**: they name a rig path as TEXT in order to measure the
seam. `UnitMaterialVariantTest` diffs the three unit shaders against each other, so all
three paths have to be named before the diff can be taken; naming two and deriving the
third is what would make the comparison pass by construction. `ScenarioDeadUnitFadeTest`
asserts the additive swap FROM one shader TO the other, so it has to name both. ADR-0189
dec. 8 already granted the second by hand, on the ground that routing the yardstick through
the module makes the guard compare the module to itself.

ADR-0194 takes a test into the addon it can run **without the game**. Both of these reach
`src/`, so a stranger rig — which has no host — cannot run either. Neither can move. The
seventh row, `assets/materials/unit.tres`, is a genuine production reach.

So the register summed two populations under one target, and the target was unreachable.

### This family already ruled what that is

`check_addon_install.py`'s arm 4 declines to score the compositor fork for exactly this
reason, in its own words:

> a register that scored its own target could never reach 0 and a burn-down that cannot
> reach 0 stops being read

A register that cannot reach its target is a defect in the **register**, not debt in the
tree. Two prior sessions filed the split and neither took it.

### The hazard the split creates

A channel that scores nothing is where debt goes to hide. The split's own failure mode is
**reclassification** — draining criterion 4 by parking a production reach in the reported
channel — and its second is ADR-0205 dec. 7's: after a change, a scanner blind to the old
spelling is indistinguishable from a correct one. Criterion 4 falls 7 → 1 the moment this
lands with **not one line of the tree moved**.

## Decision

**1. Criterion 4 splits into a SCORED production channel and a REPORTED oracle channel, on
ADR-0205 dec. 3's own ENFORCED/REPORTED shape.**

      SCENE_BURN_DOWN   PRODUCTION reaches. arm 1, ENFORCING, target 0. This is criterion 4.
      SCENE_ORACLES     TEST reaches that exist to MEASURE the seam. arm 3, REPORTED,
                        scores nothing toward criterion 4 — and still ENFORCED for hygiene.

The two registers are **disjoint** and `_check_registers()` raises on an overlap: splitting
one number into two is only honest while the halves stay addable. The check is scoped to
the two burn-downs and **not** to `DECLARED_MOUNTS` — a mount is an exemption subtracted
before either register is consulted, not a third channel, so a mounted row that also
carries a row is redundant rather than double-counted. Widening the check to the mounts was
tried and reverted the same hour: it raises on `all_live_sites_declared()`, the constructed
empty-register state the suite uses to keep an arm alive after a burn-down empties, and a
register check that forbids a legitimate constructed state is testing the test.

**2. Admission to the oracle channel is a reviewed literal gated by THREE machine
conditions, each re-checked every run.** The row is the human judgment; the conditions are
the machine's veto, and the point is that a row's argument can **expire** rather than
standing forever on the day it was written.

1. **The file is under `tests/`.** An oracle is a test. This is what refuses
   reclassification by name rather than by a reviewer noticing:
   `assets/materials/unit.tres` is not a test and can never be parked here.
2. **The file names a HOST path** — a `res://…` outside `addons/` and outside `tests/`.
   This is the MEASURED form of *ADR-0194 cannot take this test into the addon*: a stranger
   rig has no host, so a test naming host territory cannot move. The day a row's file stops
   naming one, arm 3 reds and the test must move or the row must be re-argued.
   `res://tests/…` is deliberately not a blocker — a test naming its own `.tscn` is
   self-reference, not a host dependency.
3. **The site is live.** A row whose file no longer names the path goes STALE and reds,
   same as arm 1. Stale is keyed on the scanned sites, **not** on the scored set: a row
   whose site is also a declared mount is redundant, not stale, and keying it the other way
   makes a mount strand an oracle row.

⚠️ **Condition 2 is necessary, not sufficient, and the ADR says so rather than implying
otherwise.** 593 of the 789 `tests/*.gd` files name a host path, so the predicate does not
by itself pick the oracles out. It is a veto, not an election.

**3. Both numbers are printed and NEVER summed.** The summary line reads
`<addon> <n> (+<m> oracle)`, criterion 4 is `n` alone, and the report states in the same
breath that a criterion 4 which FELL when this channel appeared fell because the register
split and not because the tree moved. That is ADR-0205 dec. 7 applied to this pass's own
change: printing the oracle term is what keeps the pre-split 7 recoverable from the
sentence a reader quotes, and it is the only thing that stops a split being a way to buy a
number. The verdict block gains a **third** sentence for criterion 4 at 0 over a non-empty
oracle channel — a real pass, but not the same claim as *no file in the tree names an addon
path*, and printing the existing zero sentence for both would make the split read as a
bigger win than it bought.

**4. `assets/materials/unit.tres` is a `DECLARED_MOUNTS` row, not a production reach —
and what makes it an exemption rather than a reclassification is a MEASUREMENT.** It was
criterion 4's whole remaining number for the rig, and the obvious drain was rejected before a
subtler one was measured and also rejected.

The obvious drain — the rig ships its own base material and the host injects only the textures
— is a design question ADR-0217 does not answer, at a cost this pass does not price. It moves
the authored file into the addon, which points three `res://assets/sprites/textures/`
`ext_resource` lines the other way, across the boundary the extraction exists to establish. It
is not payable by ADR-0202's Class B injection either: a `.tres` has no code, and the loader
resolves its `ext_resource` line before any of our code runs. `#741` made this file the single
source four `load()` call sites share (`UnitAssets.BASE_MATERIAL`), so it is load-bearing in
the other direction too. **That framing is untouched and still unpriced; this decision says the
reach stays, not that no design could remove it.**

The subtler shape — keep the file where it is, drop only its `shader =` line, and have
`UnitAssets.base_material()` inject the shader, the same injection `for_variant` already
performs on the base and the shape ADR-0215 classes B — **does not work, and was measured
rather than argued.** `unit.tres` authors 39 `shader_parameter/*` entries and Godot assigns
`[resource]` properties in file order, so `shader =` lands before all 39.
`tools/probe_unitres_shader_drain.gd`, run headful on the 4.8 fork, authors a shader-less copy
(dropping the `Shader` `ext_resource`, the `shader =` line and the `uid`), loads it, and reads
all 39 parameters back against the authored file as the control:

| half | reading |
|---|---|
| control — the authored file | shader set, **39 of 39** parameters read back |
| (a) load, **before** injecting | **39 of 39 null** |
| (a) load, **after** `mat.shader = load(…)` | **39 of 39 null** |
| (b) `get_property_list()` while shader-less | **0** `shader_parameter/` entries |
| (b) `ResourceSaver.save()` round trip | **0 of 39** lines written back, no error |

🔴 **The values do not survive to the injection.** `ShaderMaterial::_set` accepts a
`shader_parameter/x` assignment only while `shader.is_valid()`, so a `.tres` naming no shader
discards every parameter **at parse time**, and setting the shader afterwards has nothing to
re-bind. The `ext_resource` line is not one address among forty — it is the only thing that
makes the other thirty-nine loadable. Half (b) is sharper: `_get_property_list` enumerates the
*current* shader's uniforms, so a shader-less material lists no parameters at all and a save
writes an empty one back **silently**. Had (a) somehow passed, this shape would have shipped a
file that empties itself the next time anyone opens it in the editor.

So the row is arm 2 — REPORTED, scoring nothing — and it fits the mount shape rather than being
parked there: the file is host-owned and it is the only PRODUCTION namer of the target. The
exemption is load-bearing and tested as such: remove the row and the site is UNLISTED and the
guard exits 1.

**5. A mount's reason carries the MEASUREMENT, not an argument.** Dec. 2 condition 1 refuses
`assets/materials/unit.tres` from the oracle channel by name, and that refusal is worth
something only if the remaining channel is not a softer version of the same dodge. The mount's
note states the mechanism and the numbers, and
`test_the_EXEMPTIONS_reason_carries_the_MEASUREMENT_not_an_argument` fails if they leave it. An
exemption whose reason is a paraphrase is a filter with extra words (#424).

**6. The summary line carries THREE terms: `<addon> <n> (+<m> oracle, <k> mount)`.** This is
dec. 3's medicine applied to dec. 3's own blind spot. A mount is subtracted from the scored set
**before either channel is consulted**, so criterion 4 can fall to 0 because a row was exempted
rather than because a reach was removed — which is what happened to the rig. Battlefield had
read `0` over three mounts since ADR-0207 and the line never said so; that was tolerable while
no number turned on it and stopped being tolerable the moment one did. `report()` returns the
mount count for the same reason ADR-0205's note gives for it needing more than `rc`. The
verdict block carries the same clause one level down.

🔴 **The rig's criterion 4 has read 7, then 1, then 0, and NOT ONE LINE OF THE TREE MOVED FOR
ANY OF THE THREE.** All three are facts about the register. ADR-0205 dec. 7 is the rule against
letting a reader mistake that for a fact about the tree, and the three terms in the summary line
are what keep every step recoverable from the sentence a reader quotes.

## Prediction

Falsifiable, graded by the pass that took dec. 4 — **2026-09-03, one day later**, whose
measurement is folded into dec. 4 itself.

| | grade | |
|---|---|---|
| **P1** | 🔴 **FALSIFIED** | predicted that *draining* `unit.tres` takes the production channel to **0** with the oracle channel at **6**. The channel did reach 0 with the oracle channel at 6 — and **not by draining**. The drain was measured and is not available: a shader-less `ShaderMaterial` loses all 39 of its authored `shader_parameter/` values at parse time. The row is an **exemption**, and the summary now reads `0 (+6 oracle, 2 mount)`, not the `0 (+6 oracle)` this predicted. A prediction whose number lands and whose mechanism does not is the reason the number alone was never the criterion. |
| **P2** | ⚪ **held literally, and that is not the interesting half** | no row moved between the two burn-downs. One moved out of `SCENE_BURN_DOWN` into `DECLARED_MOUNTS`, which dec. 1 rules is an exemption and not a third channel — so P2 is silent about exactly the move that happened. What P2 was reaching for is what P1 records: the tree did not move. |
| **P3** | 🟢 **held** | the oracle channel is still 6, and no row arrived silently. |

## Consequences

- `check_lattice_scene.py` grows a third register and a third arm. `report()` returns
  `(rc, production, oracle)` — the caller needs both counts, for the same reason
  ADR-0205's own note gives for it needing more than `rc`.
- The rig's criterion 4 reads **1 (+6 oracle)**, down from **7**, and every report says in
  its own text that the drop is the scanner and not the tree.
- 🔴 **`tests/UnitMaterialVariantTest.gd` reads the seam as text DELIBERATELY.** It is the
  oracle, not debt. Its rows are now in a register whose name says so.
- Six rows leave a target-0 burn-down, so the burn-down becomes readable again — which is
  the whole benefit and is not itself a measurement of the tree.

## Alternatives considered

- **Leave the seven summed and file the split again.** Rejected: this is the third filing,
  and a burn-down that cannot reach 0 stops being read — the failure `check_addon_install`
  arm 4 names in its own words.
- **Admit oracle rows on the reviewer's word alone, with no machine condition.** Rejected:
  that is a filter with extra words, and #424 is the rule against exactly that. It would
  also let `unit.tres` be parked in the reported channel by anyone who found the number
  inconvenient.
- **Pick the oracles with a PREDICATE over the path instead of a named list.** Rejected on
  #424 for the opposite direction: a filter manufactures its own debt and cannot tell a
  triaged site from one that merely matches. Membership is the reviewed literal; the
  predicate only vetoes.
- **Drop the oracle term from the summary line once the split is understood.** Rejected:
  the term is what keeps the two numbers from being read as one, and the reader who needs
  it is the one who has not read this ADR.
- **Move both oracle tests into the addon and delete the rows.** Rejected as not available:
  ADR-0194 takes a test the addon can run without the game, and both reach `src/`. This is
  now measured every run rather than asserted here (dec. 2, condition 2).

## Built (2026-09-03)

Landed with the ADR, on `origin/main` at `59900b544`.

| reading | before | after |
|---|---|---|
| `check_lattice_scene` — `exmateria_sprite_rig` | **7** | **1 (+6 oracle)** |
| `check_lattice_scene` — `exmateria_battlefield` | 0 | 0 (+0 oracle) |
| `tools/test_check_lattice_scene.py` | 50 OK | **69 OK** |

🔴 **Not one line of the tree moved.** The 7 → 1 is this ADR's own change to the scanner
and nothing else, which is why dec. 3 puts the oracle term in the summary line rather than
in a footnote. `check_addon_install` (axis B) is **0 / 0** and untouched — reporting either
axis as the other is ADR-0202 dec. 1's named failure.

Green at the same commit: `test_check_addon_portability` 61 OK, `test_check_addon_install`
30 OK, and rc 0 from `check_addon_portability`, `check_addon_install`, `check_tool_paths`,
`check_lattice_publish`, `check_addon_globals`, `check_lattice_ports`, `check_lattice_doors`,
`check_mount_node_paths`, `check_adr_classification`, `check_adr_anchors`, `check_adr_shape`.

Each of arm 3's three conditions was seeded RED before it was trusted, and the control that
separates condition 2 from the seeding itself
(`test_the_SAME_seed_with_a_host_path_is_GREEN`) ships beside it. The third verdict sentence
— criterion 4 at 0 over a non-empty oracle channel, the state dec. 4's pass reaches — is
seeded too, so it is seen firing before it first appears in a real report.

## Amendment 2, 2026-09-05 — condition 2 reads a host REACH, not only a host PATH

Dec. 2 gave the oracle channel three admission conditions, and the second was written as a
veto: the file must name a HOST path, because that is the measured form of *`ADR-0194` cannot
take this test into the addon*. It was implemented as a search for `res://` literals outside
`addons/`. That implementation is narrower than the condition, and the gap cost trunk a red.

`tests/MapDitherSnapTest.gd` names two addon shader paths and no host path at all. It cannot
move into `exmateria_battlefield` regardless, because it constructs `MapRenderDebugPanel` —
a host class, reached by **bare class name**, which no `res://` scan can see. Filed as
[#871](https://github.com/timbermania/fft-monorepo/issues/871); the pre-flight aborted the
full suite on every branch for as long as it stood, and several sessions worked around it
with `--no-preflight` rather than pay it.

The ticket proposed booking the two rows on arm 3. Run against the instrument first, that
proposal **fails on arrival**: `oracle_blockers()` returned `[]` for the file, so the guard's
own ARGUMENT EXPIRED arm would have red the new rows the moment they landed. The judgement
was right and the predicate was wrong.

**A2.** Condition 2 is satisfied by a host **reach**, of which a host `res://` path and a
bare host `class_name` are two spellings. `oracle_blockers()` now reports both, tagged
`Name (declaring/path.gd)` so the report names the file the reach lands in. Host classes are
the `class_name` declarations under neither `addons/` nor `tests/` — 335 of them. Comments
are stripped from `.gd` sources first, and a class the file declares itself is not a reach.

Three things this does not do. It does not widen **criterion 4**, which still counts `res://`
production sites and still reads 0 for both addons — the burn-down number is unchanged and
this is deliberate, on dec. 7 of [ADR-0205](0205-a-path-reach-is-the-same-axis-as-a-type-reach.md)'s
grounds. It does not book the rows on the burn-down, which would have taken Battlefield's
criterion 4 off the 0 that
[ADR-0209](0209-one-ruling-over-three-rows-that-needed-three-and-a-file-can-be-ruled-back.md)
closed, for a **test** — the reclassification-in-reverse dec. 1 exists to refuse. And it does
not claim the two spellings are the whole of "cannot move": a duck-typed reach is still
invisible to both.

Cross-checked against `tools/closure.py`, which implements a bare-`ClassName` edge
independently and for a different purpose. Both produce identical host sets for all three
oracle files (`MapDitherSnapTest`, `ScenarioDeadUnitFadeTest`, `UnitMaterialVariantTest`).

### Built

| reading | before | after |
|---|---|---|
| `check_lattice_scene` rc on trunk | **1** | **0** |
| `exmateria_battlefield` | 0 (+0 oracle, 3 mount) | **0 (+2 oracle, 3 mount)** |
| `exmateria_sprite_rig` | 0 (+6 oracle, 2 mount) | 0 (+6 oracle, 2 mount) |
| `tools/test_check_lattice_scene.py` | 71 OK | **81 OK** |

Both rows carry owner `#871, 2026-09-05 — ARGUED PERMANENT`. Four of the ten new arms are a
class `TheBlindSpotThatCostATrunkRed`, which pins the finding itself rather than the fix: the
file holds no `res://` host path at all, it is blocked anyway, both rows sit on arm 3, and
criterion 4 did not move. Three more are seeded on a **constructed** host class — a class
reach with no path is green, the same name in prose only is red, and a class the addon
declares itself is not a blocker.

`test_battlefields_arm_1_still_reads_zero_over_three_declared_files` needed its literal
changed from `0 site(s) over 3 file(s)` to `over 4 file(s)`. That is the summary's file term
moving with the oracle rows while criterion 4 stays at zero — the distinction dec. 7 of
ADR-0205 draws, arriving in a test assertion. It is now asserted with the reason written down
beside it, and the arm additionally pins `2 oracle site(s) are reported by arm 3`.
