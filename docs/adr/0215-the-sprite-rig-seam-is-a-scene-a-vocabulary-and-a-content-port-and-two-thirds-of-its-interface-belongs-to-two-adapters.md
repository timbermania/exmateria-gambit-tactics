# The `Sprite Rig` seam is a scene, a vocabulary and a content port — and two thirds of its interface belongs to two adapters

Loop **pass 3** of extraction #4 — *audit the crossings, design the seam, and
PREDICT the metric*. Status: **accepted (2026-08-31)**.

Code at trunk `69636feae`, classifier at `69636feae`. `tools/.touch_cache.json`
was checked against the tree before use rather than trusted: twelve cached
`(file, line)` pairs resolve, including the five shader `#include`s and the four
reaches ADR-0214 re-took. `tools/path_refs.py "Sprite Rig"` reproduces the
committed register **byte-identically** (`diff` of the sorted `.tsv` is empty).
Scope is 29 files / 5,383 lines, unchanged. ADR-0131's fourth amendment: *a
reading is only meaningful against a stated commit AND a stated classifier
revision.*

**The pass-1 and pass-2 instruments measured who names the rig. This pass
measures what they ask it for**, and that changes the answer. Counting names,
`Sprite Rig` publishes 18 global `class_name`s. Counting **members**, it
publishes **98**, used **489 times from 71 files** — and **66 of the 92
non-enum members are reached by exactly two files**. The seam is not a
negotiation with 71 callers. It is a scene, a vocabulary, and two adapters.

## Context

[ADR-0214](0214-sprite-rigs-scope-is-anchored-and-its-pass-1-numbers-were-taken-through-a-keyhole.md)
dec. 12 left pass 3 three things it *"could measure but not settle"* — the
content shadow, `assets/scenes/Unit.tscn`, and the §4 restatement — and five
soft spots. `docs/agents/refactor-loop.md:355` asks for three deliverables. All
of it lands here, and the prediction is the half that is easy to skip and is the
whole point of the pass.

### The instruments do not overlap, and that gap IS the seam's surface

`touch_matrix.py` reads typed symbols; `path_refs.py` reads `res://` literals.
Measured against each other at HEAD, on (file, line) identity:

| | `touch_matrix` | `path_refs` | **both** | **union** |
|---|---:|---:|---:|---:|
| outbound | 49 lines | 22 | **5** | **66** |
| inbound | 206 lines | 23 | **3** | **226** |

The overlap is exactly the path-shaped rows `touch_matrix` happens to record:
outbound, the five shader `#include`s; inbound, the three `preload`s
(`CombatLoop.gd:37`, `ScenarioVM.gd:4509`, `Unit.gd:15`). On inbound the two
instruments agree about **1%** of the surface. Neither is close to whole, and
ADR-0157's *"the fourth reading"* framing understates it: they are not a reading
and a check, they are two disjoint censuses.

**And there is a fourth spelling neither has.** `src/scenarios/ScenarioDialogueBoxPool.gd:517`
and `:728` do `speaker.get_node_or_null("UnitMesh")` — a `Cutscene` reach into the
node carrying this system's material, by **string**. (A third site,
`src/units/Unit.gd:490`, spells it the same way but is the adapter binding its
own child, so it does not cross.) Not a typed symbol, not a
`res://` path, invisible to both, and `get_node_or_null` returns `null` on a miss,
so a rename or a re-parent is silent. This is
[ADR-0191](0191-the-fold-predicate-is-the-kernels-and-a-producer-picks-between-two-shaders.md)'s
arm-2b subject — *an autoload named by node path* — one level down: a **scene
node** named by node path.

## Decision

**1. The interface is 98 members, not 18 names, and that is what makes it
shallow.** Scanned every `.gd` outside the system for `<SpriteRigType>.<member>`
and for `.<member>` on locals declared with a `Sprite Rig` type. Result: **98
distinct members, 489 uses, 71 referrer files** (23 production, 48 `tests/`).
Against 5,383 lines of implementation that is ~55 lines of behaviour per unit of
interface a caller must learn.

The distribution is what matters:

| | members | uses |
|---|---:|---:|
| the 6 vocabulary enums | 6 | **217 (44%)** |
| non-enum, reached ONLY by `src/units/Unit.gd` | 39 | |
| non-enum, reached ONLY by `src/scenes/SequenceViewer.gd` | 19 | |
| non-enum, reached only by those two together | **66** | |
| non-enum, reached only by `tests/` | 8 | |
| **non-enum, reached by anyone else** | **18** | |
| **total** | **98** | **489** |

`Unit.gd` alone is 128 uses over 57 members; `SequenceViewer.gd` is 122 over 32.
**Two files are 51% of all traffic.** The other 69 files average 3.5 uses each.

Decisions 2, 3 and 4 are that table, read three ways.

**2. The vocabulary is the KERNEL's, and moving it removes 44% of the crossing
traffic without re-pointing a single call.** Six enums:

| enum | uses | home today |
|---|---:|---|
| `DisplayActivity.Activity` | 64 | `src/animation/DisplayActivity.gd` (25 lines, enum + nothing else outside) |
| `AnimationStateController.FacingDirection` | 52 | nested in a 369-line Node |
| `SpriteLayerManager.Layer` | 50 | nested in an 888-line Node |
| `AnimationClock.Owner` | 38 | nested in an 81-line class |
| `UnitMaterial.Variant` | 9 | nested in a 57-line class |
| `AnimationOpcodes.SideEffect` | 4 | nested beside `Op`, which no outsider names |

A caller of one of these learns a **value set**, not a contract: no ordering, no
invariant, no error mode. ADR-0141 dec. 2 counts it as a cross-system reach and
has no term for the difference — [ADR-0213](0213-extraction-4-is-sprite-rig-and-its-widest-inbound-name-is-a-generated-enum.md)
dec. 4 said so, and ADR-0214 dec. 4 killed that decision's *coverage* while
leaving its *argument* standing. **This decision spends the argument.** The six
enums move to `addons/exmateria_schema/`, which
[ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md) dec. 9 and
dec. 12 already permit every addon and the host to name. 217 of 489 uses stop
being crossings **by re-classification, not by re-pointing** — no call site
changes meaning, and the enum question becomes a ruling instead of a standing
exception.

Cost, stated: three of the six (`FacingDirection`, `Layer`, `Variant`) are nested
in behaviour-bearing classes and need a file split. `DisplayActivity`,
`AnimationClock.Owner` and `AnimationOpcodes.SideEffect` are the cheap three —
and `DisplayActivity`, `AnimationClock` and `AnimationOpcodes` are reached from
outside for **nothing but** their enum, so all 106 of their inbound lines leave
the surface with them.

**3. The rig publishes as ONE SCENE, `src/units/Unit.gd` is its single host
adapter, and node paths are NOT part of the contract.** Read
`assets/scenes/Unit.tscn` in full (128 lines). Its root wears `Unit.gd`
(`Battle`), and inside it sits a contiguous rig: `UnitMesh` — a `MeshInstance3D`
whose `QuadMesh` carries a `ShaderMaterial` binding `assets/shaders/unit.gdshader`,
three ROM textures and **42 authored `shader_parameter/` keys** — plus three
`Sprite Rig` `Node` children, `SpriteLayerManager`, `AnimationStateController`
and `CameraRelativeRenderer`. Everything else in the scene is Battle's.

**That subtree is bound in exactly three lines in the entire tree**:
`Unit.gd:105`, `:108`, `:111`, one `@onready var x: T = $T` each — grep the whole
package for the three node names in a `$` or `get_node` position and those three
lines are the entire result. **114 files reference
`res://assets/scenes/Unit.tscn` — 5 under `src/`+`assets/` and 109 under
`tests/`** — and not one of them names a rig node. This is a seam in Feathers'
sense already — a place behaviour can be altered without editing there — and
nobody has used it as one.

The 109 is not a footnote. It says the rig's real test surface is already
*through* `Unit.tscn`, and it prices dec. 3's node-path ruling: a change to the
scene's shape would be visible in 109 places, which is why the guard arm is the
cheap half of this decision and the two-line edit is the trivial half.

So: publish the rig as one scene plus one script; `Unit.tscn` instances it;
`UnitDisplay`, `AnimationPlayback`, `AnimationClock`, `AnimationFrameCalculator`,
`PlaybackSet`, `AnimationDatabase`, `AnimationResolutionMap`,
`WeaponAnimationSelector`, `SpritePaletteResolver` and the three
`resources/` classes go **behind** it and stop being global `class_name`s.

**And the node-path question is ruled the way that does NOT contort the scene
graph.** Three sites in the package reach a rig node by literal path:
`ScenarioDialogueBoxPool.gd:517` and `:728` (`Cutscene`, outside the system) and
`src/units/Unit.gd:490` (`self.mesh_instance = get_node("UnitMesh")`, the host
adapter binding its own child, which moves with the adapter). Only the two
`Cutscene` sites cross. [ADR-0204](0204-the-mount-point-is-an-inherited-scene-because-the-addon-supplies-the-ui-to-a-hundred-and-seven.md)
faced this at 107 scenes and preserved the paths, because at that scale the edit
was 104 silent breakages. Here it is **two crossing sites in one file**, both
`get_node_or_null(...) as Node3D`. Preserving `Unit/UnitMesh` as a contract to
save two lines would buy the scene shape a permanent constraint at the price of
nothing. **Publish an
accessor, edit the two `Cutscene` sites, and add a node-path-string arm to
`check_addon_portability.py`** so the next such reach reds instead of returning
`null`. The scale difference is why this ADR reaches the opposite conclusion from
ADR-0204 on the same evidence, and saying so is the point.

**4. `src/scenes/SequenceViewer.gd` ships INSIDE the addon, and that is what
discharges ADR-0214's S3.** S3 says 87 lines of `assembler` traffic is either
wiring an extraction expects **or** 87 lines of unbudgeted re-pointing, and that
the measurement cannot tell. It can now, because the measurement was of the wrong
thing. `SequenceViewer.gd` is **66 of those 87 lines**, 122 of the 489 member-uses
and 32 of the 98 members, and it is neither of S3's two options: `docs/ROOT_SET.tsv:13`
already describes it as *"exercises the whole sprite rig"*, and its **only**
non-`Sprite Rig` typed reach in 575 lines is `AnimationNames` (`content`, 2 lines).
`assets/scenes/SequenceViewer.tscn` names its own script, this system's shader and
three ROM textures — nothing else.

It is the addon's dev viewer, filed under `src/scenes/`.
[ADR-0194](0194-a-test-belongs-to-the-addon-it-can-run-without-the-game.md) dec. 2 — *an
addon-owned test ships inside the addon* — is the argument, and
[ADR-0184](0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md)'s move of `PlayerCamera.tscn` and
`TileCursor.tscn` into `exmateria_battlefield` is the precedent. The remaining 21
assembler lines (`NavigatorMain`, `ScenarioPlayerScene`, `EffectViewerScene`,
`GPUArena`, `ProgressionTester`, `UnitAnimationViewerScene`) are real host wiring
and stay.

⚠️ **The obligation this creates, stated because it is how the move could go
wrong.** *One adapter is a hypothetical seam; two adapters is a real one.* Moving
the viewer inside removes the second **external** adapter, which would let the
published interface shrink to whatever `Unit.gd` happens to need and call that a
seam. So: **the viewer must drive the rig through the same published interface
`Unit.gd` uses.** If it needs a member `Unit.gd` does not, that member is
published; if it needs a private, the interface is wrong. That is a pass-6 test
with a yes/no answer, not a preference.

**Contrast, to show the rule has teeth.** `src/scenes/UnitAnimationViewerScene.gd`
looks like the same kind of file and **cannot** move: it reaches
`Character Catalogue`, four `Battle` names, `UI` and `Debug`. It stays host-side.

**5. The published-interface floor is 18 behaviour members over nine names.**
Reached by someone other than the two adapters and other than `tests/`:

| name | members |
|---|---|
| `AnimationStateController` | `angle_12bit_to_facing`, `angle_12bit_to_cardinal_bucket`, `get_camera_variant` |
| `SpriteLayerManager` | `new`, `shared_loc_offset`, (`.gd` by path) |
| `AnimationResolutionMap` | `resolve_for_activity`, `resolve_attack` |
| `SpritePaletteResolver` | `job_body_palette_row`, `resolve_body_palette_row` |
| `UnitMaterial` | `for_variant`, `shader_for` |
| `WeaponAnimationSelector` | `get_wep_frame_offset`, (`.gd` by path) |
| `ResourceHotReload` | `new`, `resource_reloaded` |
| `AnimationDatabase` | `get_set` |
| `AnimationFrameCalculator` | `get_frame_at` |

Eighteen members and six kernel enums against ninety-eight members: depth goes
from ~55 to ~299 lines of implementation per unit of interface, a **5.4×**
improvement, and **76% of the current published surface stops being public**.
This is the number decisions 2–4 exist to produce and the one pass 9 scores.

**6. The four `content`/`generated` reaches are ONE PORT, not four dependencies,
and that is the honest §4 restatement.** ADR-0214 dec. 12 hands pass 3 six names
that make `BLUEPRINT.md` §4 false. Read at their call sites, four of them are the
same shape — *given an FFT id, what number does the rig need*:

| reach | sites | shape |
|---|---:|---|
| `AbilityDatabase.get_ability_view(ability_id)` | 1 | id → dict |
| `JobDatabase.get_job(hex)["body_palette_row"]`, `.is_monster(hex)` | 2 | id → int / bool |
| `WeaponZeroFrames.get_wep1/wep2/eff1_offset(item_type_id)` | 3 | id → int |
| `WeaponGraphicData.get_v_offset(item_id)` | 1 | id → int |

Seven call sites, four tables, all `content` or `generated`, every one a pure
query. **They collapse to one content port the host adapts** —
[ADR-0164](0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)'s
*one port* shape, `exmateria_platform`'s `TunePort` as the worked example
(ADR-0202 dec. 7), [ADR-0203](0203-an-addon-provides-the-names-it-can-and-injects-the-content-it-cannot.md)
dec. 2's *injects the content it cannot* as the rule.

The other two are `Battle` and are severable rather than portable.
`UnitDisplay` holds `var _unit: Unit` and `_init(unit: Unit)` and reads
`Unit._CARDINAL_TO_12BIT` — **a private static table of cardinal-to-12-bit angle
arithmetic**, which is `AnimationStateController`'s own subject (it already
publishes `angle_12bit_to_facing`). It moves into the rig; it was never Battle's.
`ReactionType` appears as a default argument value and a log formatter: it is
vocabulary, decision 2's class, not a dependency.

**So the restatement is: the rig does not know what a combatant IS. It asks a
content port for numbers keyed by FFT ids, and it owns the pixels.** ADR-0214
offered *"it does not know what a combatant is doing; it knows what one is"* and
called it a pass-3 question. Measured, the polarity is the other way round, and
the blueprint sentence is retired rather than annotated once the port lands.

**7. The content does not move, and the split is ADR-0202 dec. 5's.** Read all 17
`assets/` outbound rows in source. **Two are prose**: `SpriteLayerManager.gd:275`
is inside a `"""docstring"""` (`texture_path: Resource path like
"res://assets/sprites/02.png"`) and **`assets/sprites/02.png` does not exist** —
ADR-0214 dec. 8 cites it as *"an absolute sprite sheet"* and it is a stale example
in a comment; `AnimationResolutionMapResource.gd:12` is a `##` note. The same
correction ADR-0202's Context made for `DoodadLibrary.gd`.

**The live content shadow is 15 references in 8 files**, and every one is a
module-level `const` — not a single inline literal, which is the cheapest
possible shape to parameterise. Split by ADR-0202 dec. 5's test, which is
**tracked-ness, not authorship**:

| class | refs | disposition |
|---|---:|---|
| **A — tracked, shippable** | 4 | `map.tres` ×2, `weapon_animation_ids.json`, `weapon_wep1_anim_ids.json`, `populated_rows.json` → **move into the addon** |
| **A′ — tracked, but the host reads it too** | 2 | `assets/materials/unit.tres` → **publish, do not move**: `src/units/Unit.gd:628` `load()`s it and three tests name it, so a move creates a new host→addon path reference. The rig hands out the material and `Unit.gd:628` becomes a call. |
| **B — gitignored, un-shippable** | 9 | `sprites/animations/`, `layer_priority.json`, `evtchr_frames.json`, `WEP1.tga`, `WEP1.palette.tga`, `EFF1.tga`, `EFF1.palette.tga`, `textures/evtchr/`, `crystal/crystal_sheet.png` → **host-injected content root** |

`map.tres` is the clean Class A case: three `Sprite Rig` readers plus one
`tools/` migration script, no host consumer. That the register books its three
rows as *inbound* is decision 8.

**And the byte question, which no pass has asked.** `tools/asset_census.py` at
HEAD books **212,342,240 content bytes — 27.5% of the whole tree — to
`Sprite Rig`**, second only to `Battlefield`, across two packet classes
(`assets/sprites` 120,590,486 and `assets/characters/templates` 91,726,944).
Under [ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
dec. 1 that settles goal #6: this system **owns ROM-derived formats**, so `n/a`
is not available to it, exactly as for `Audio` and `Battlefield`. It also names a
crossing nobody has counted: `assets/characters/templates` is Sprite-Rig-format
and is read **21.9% by `UI` and 21.4% by `Character Catalogue`** — 43% of a
91.7 MB packet class, and ADR-0142 dec. 1 says a reader that is not the format
owner is a crossing like any other.

**8. Four of the 23 inbound path references are `Sprite Rig`'s OWN, and
production inbound is 8 references from 4 files.** The register's `?` bucket is
15 = eleven `tests/` rows plus **four from two resources that are this system's**:
`assets/animation_resolution/map.tres` (3 — it *is* an instance of three of this
system's resource classes) and `assets/materials/unit.tres` (1 → its own shader).
`asset_census.FORMAT_OWNER` books both to `Sprite Rig` at lines 78 and 99. They
read as inbound only because `classify_blueprint.walk()` takes no `.tres` and so
cannot book one.

| | ADR-0214 / the register | corrected |
|---|---:|---:|
| inbound, production | 12 refs / 7 files | **8 refs / 4 files** |
| inbound, total | 23 | 19 |

The four remaining production referrers are `Unit.tscn` (4), `Unit.gd` (1),
`CombatLoop.gd` (1), `ScenarioVM.gd` (1) and `SequenceViewer.tscn` (1). **Half
the production inbound path surface is one scene**, and after decision 4
`SequenceViewer.tscn` leaves with its script — so it is 7 from 3.

This does not change ADR-0214 dec. 8's conclusion; it sharpens it. The
`Battlefield` comparison is untouched because it is taken on the same instrument
with the same blindness on both sides.

**9. Goal #5's guard is NOT blind on the path axis, and two live documents still
say it is.** The handoff this pass started from, and `docs/GOALS.tsv`'s
`3 Battlefield 5` evidence row, both carry ADR-0202's sentence *"no arm of it
reads a `res://` path out of a `.gd` body or a `.tscn` `ext_resource`."* That was
true at `ebff57409`. **#658 built arm 6.** `tools/check_addon_portability.py:37`
and `:517-592`: **RES:// PATH, ENFORCING**, referrers `{.gd, .tscn, .tres, .cfg}`,
targets deliberately wider than the source suffixes (*"a `.tga`, a `.json` and a
bare `res://assets/maps/` directory are exactly as unshippable as a `.gd`"*),
per-suffix comment strippers, and a named burn-down. Run at HEAD it prints a
three-row burn-down for `exmateria_sound` and the sentence *"Not a pass: this is
goal #5 unmet on the PATH axis, on record"* — a guard reporting its own debt, not
a green one. All eleven `Battlefield` rows are gone, paid by ADR-0202/0204.

**So pass 3 widens nothing.** The `GOALS.tsv` row is corrected in this commit; the
handoff is not a tracked document. The lesson is the one this family keeps
relearning: **a quoted guard limitation is a claim about a tree, and it expires
when someone fixes the guard.**

⚠️ **But arm 1 has a DIFFERENT blindness, and it is the one that matters for
P3.** `main()` scores arm 1 only where `classify()` returns a **system**
(`check_addon_portability.py:549` — *"ARM 1 DOES NOT RUN ON THE KERNEL OR THE
PORT"*, correctly, since those are not systems). The tiers are not systems
either. Of this system's 49 outbound lines, **arm 1 can see 27** — `Debug` 21 and
`Battle` 6. The other **22** are `platform` 6, `content` 6, `schema` 5,
`infrastructure` 4 and `generated` 1, and arm 1 is silent on all of them by
construction. Eleven of those 22 are conformant (kernel and port). Eleven are
not, and the guard will not say so: seven are dec. 6's content port, and **four
are `src/data/JsonAsset.gd`, `infrastructure`, which no addon in this tree has
ever named.** That is why P3 is written as three rows against two instruments
rather than one row against arm 1 — a portability verdict taken from arm 1 alone
is [ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)'s
*green because it stopped looking* with a different subject.

**10. `tools/asset_census.py` was link-blind, and the fix lands HERE, before the
prediction.** `content_files()` walked with `os.walk(root)` and its default
`followlinks=False`. `tools/link_worktree_godot_assets.sh:52-58` symlinks
`assets/maps`, `assets/music`, `assets/sprites/textures`,
`assets/scenarios/chunks`, `assets/characters/templates` and `assets/effects/E000`
from a populated sibling. Seeded both arms on a scratch tree holding one `.tga`
behind a symlinked `assets/sprites/textures`: the old body yields `[]`, the new
one yields the file.

**199,175,800 of the 212,342,240 bytes this instrument books to `Sprite Rig` —
93.8% — sit behind two of those links.** The instrument that answers *does the
content move with the addon* was reading ~13 MB of a 212 MB question in the
worktrees the refactor loop actually runs in. Tree-wide the six link targets are
517,332,397 of 772,430,163 bytes, 67.0%. Routed through
`tools/_walk_roots.walk_files()`, which exists for this and which #731 used on
three ADR generators with the same defect. Output on this (rsync-form) checkout
is byte-identical, which is the correct no-op.

ADR-0131 lands instrument changes **before** the baseline, and decision 12's
prediction rests on the 212 MB figure, so this is not scope creep — it is the
precondition for predicting anything about goal #6.

**11. Goal #7 will score a FALSE GREEN, and pass 3 carries a criterion rather
than widening the word list.** Measured with `score_goals.jargon_hits`' own
strippers over the 29 files: **39 jargon CODE lines across 8 files, `psx` 38 and
`tpage` 1 — platform 39, content ZERO.** Against `Battlefield`'s 112 and
`Audio`'s 154 that reads like the best result any extraction has had.

It is an artifact of the word list. `score_goals.JARGON` is
`("psx","rgb555","clut","tpage","vram","libgpu","gte","fft","waveset","ivalice","smd")`
and has no term for this system's actual content vocabulary. The same scan with
`seq`, `shp`, `evtchr`, `wep1`, `eff1`, `type1`, `type2`, `palette_row` added
reads **437 CODE lines across 15 files** (`wep1` 127, `eff1` 96, `seq` 85,
`type1` 70, `evtchr` 23, `shp` 19, `palette_row` 12) — `UnitDisplay.gd` 141,
`SpriteLayerManager.gd` 118, `unit_sprite_body.gdshaderinc` 89. This is
ADR-0214 dec. 9's finding with the word list in place of the printout: **the
counterexample cannot be represented by the instrument's shape, not its data.**

**Widening `JARGON` is refused here.** It scores `Render`, `Audio` and
`Battlefield` too, and ADR-0131 forbids changing an instrument mid-series without
re-taking the baseline. So: the 437 is recorded as an explicit `Sprite Rig`
criterion in this ADR and in the `GOALS.tsv` evidence, and the widening is filed
for the epilogue, where a re-baseline is already scheduled. **Pass 9 must not
read `content 0` as met.**

**12. THE PREDICTION.** Written before pass 6 so pass 9 can be wrong about it.
Each row names the instrument and the command, because a prediction scored on a
different instrument is not scored.

| # | prediction | instrument | falsified if |
|---|---|---|---|
| **P1** | published interface **18 behaviour members over ≤9 names**, plus 6 vocabulary enums in the kernel — down from 98 members over 18 names | the decision-1 member scan, re-run with the addon root in place of the `Sprite Rig` scope | **>24** non-enum members reached from outside the addon |
| **P2** | inbound `touch_matrix` lines **84**, tolerance ±20 | `tools/touch_matrix.py` | outside **64–104** |
| **P3a** | outbound SYSTEM reaches **27 → 0** (`Debug` 21 = `DebugConfig` 17 + `GameLogger` 4; `Battle` 6 = `Unit` 3 + `ReactionType` 3) | `check_addon_portability.py` arm 1 | arm 1 non-zero |
| **P3b** | conformant residual **11 lines** — `Tune` 2, `PSXDisplay` 2, `ExMateriaSchema` 2, five `#include` lines over three kernel/port shaderincs — and nothing else | `tools/touch_matrix.py`, outbound | any residual outside the kernel/port set, or >13 lines |
| **P3c** | the 7 `content`+`generated` lines (`WeaponZeroFrames` 3, `JobDatabase` 2, `WeaponGraphicData` 1, `AbilityDatabase` 1) go to **0**, absorbed by dec. 6's port; `JsonAsset` 4 is the one line-item this pass does NOT dispose of | `tools/touch_matrix.py`, outbound | any `content`/`generated` line survives |
| **P4** | **0** `res://assets/` addresses in the addon: 4 Class A move, 2 publish, 9 injected | `check_addon_portability.py` arm 6 | any `assets/` row against the new addon root |
| **P5** | goals **6 met / 1 n/a / 3 open** — #6, #7, #8 open; the same shape `Battlefield` got | `tools/score_goals.py` | any other split |
| **P6** | goal #7 scores **`content 0`** and it is **wrong**; the true count is 437 lines / 15 files | dec. 11's widened scan, run alongside | the widened scan reads <350 or >520 |
| **P7** | the addon lands at **~6,000 lines / ~31 files** (5,383 + `SequenceViewer.gd` 575 + its `.tscn`), and it extracts **INSIDE** `WALK_ROOTS`, so goal #4 is met — unlike `Audio` | `classify_blueprint.py` | addon outside 5,600–6,400 lines, or not in `WALK_ROOTS` |
| **P8** | the largest single surprise will be **content, not code** — the 91.7 MB `assets/characters/templates` crossing (`UI` 21.9%, `Character Catalogue` 21.4%) forces a decision no pass has scoped | `tools/asset_census.py` | pass 9 finds it did not have to be decided |

**P2's arithmetic, so a miss is diagnosable rather than mysterious.** 206 today.
Decision 4 removes `SequenceViewer`'s 66. Decision 2 removes `DisplayActivity`
44, `AnimationClock` 11 and `AnimationOpcodes` 4 — the three names reached from
outside for nothing but their enum, 59 lines. **The two sets overlap by 3**:
`src/scenes/SequenceViewer.gd` names `AnimationOpcodes` on three lines, so
subtracting both terms would count those twice. 206 − 66 − 59 + 3 = **84**.
(The overlap is worth stating rather than absorbing into the tolerance: three of
`AnimationOpcodes`' four outside lines are the viewer's, so after dec. 4 that
name is reached from outside the addon on exactly ONE line.) The tolerance is
for `SpriteLayerManager`, `AnimationStateController` and `UnitMaterial`, whose
lines mix enum and method use and are counted per NAME, and for the façade name
the addon will publish and callers will then reach.

## Considered alternatives

**Preserve `Unit/UnitMesh` as a node-path contract, ADR-0204's answer.**
Rejected — dec. 3. ADR-0204 preserved paths because breaking them was 104 silent
failures across 107 scenes. Here it is two `get_node_or_null` sites in one file.
Buying a permanent scene-shape constraint to avoid a two-line edit inverts that
trade. The guard arm is what makes the two lines safe to change.

**Cut the seam at `src/units/Unit.gd`, the articulation point three instruments
land on.** Rejected. ADR-0214 dec. 11 already shows `Unit` is not a gate — 21 of
28 files survive its removal on three roots — and its `Unit`-free spread is a
monkey-patched static simulation that **S5 forbids reading as a runtime claim**.
This ADR does not use that table for anything. More decisively, `Unit.gd` is not
a boundary to cut at: dec. 1 shows it is the **adapter**, 57 of 98 members and
128 uses. A seam drawn at the adapter is a seam drawn at the widest point.

**Widen `score_goals.JARGON` now so goal #7 is honest at pass 9.** Rejected —
dec. 11. It re-scores three landed extractions mid-series against a frozen
baseline, which is the exact instrument-change ADR-0131 exists to prevent.
Carrying the number as a criterion costs a paragraph and loses nothing.

**Publish `SpriteLayerManager` as the interface, since it is the widest inbound
name (56 lines).** Rejected. Width of *name* is not width of *interface*: of its
17 reached members, 50 uses are the `Layer` enum (dec. 2) and 42 of the remaining
reaches are `SequenceViewer`'s (dec. 4). What survives both is **three members**.
Publishing an 888-line Node because a viewer drives it is how a shallow interface
gets ratified.

**Move `assets/materials/unit.tres` into the addon with the rest of Class A.**
Rejected — dec. 7. `src/units/Unit.gd:628` `load()`s it and three `tests/` name
it; the move trades one outbound reference for four inbound ones. It is a
publish.

**Leave `SequenceViewer.gd` in the host and count its 66 lines as the seam's
cost.** Rejected — dec. 4. That is S3's pessimistic reading, and it is refuted by
the file itself: 575 lines, one non-`Sprite Rig` typed reach, and a `ROOT_SET.tsv`
row that already calls it the rig's exerciser.

## Consequences

- **ADR-0214's S3 is DISCHARGED** by dec. 4 — the assembler ambiguity is resolved
  by relocating 66 of its 87 lines, not by choosing a reading of them.
- **S5 is honoured by NOT BEING USED.** No decision here rests on the `Unit`-free
  reach table. It carries to pass 5 intact.
- **S1, S2 and S4 carry.** S4 is *strengthened*: this pass adds three more
  corrections to two-day-old published numbers (dec. 7's prose rows, dec. 8's
  self-owned rows, dec. 9's stale guard sentence), all in the same family and
  none caused by carelessness. That is now seven corrections across two passes,
  and S4's question — *is the pass-1 method under-specified* — is owed an answer
  by the method's own ADR, not by another extraction's pass 3.
- **`docs/GOALS.tsv`'s `3 Battlefield 5` row is corrected** in this commit. It
  asserted a guard blindness that #658 removed.
- **`tools/asset_census.py` now reads the same universe in every install form.**
  Its committed output does not change on an rsync-form checkout; it changes by
  ~517 MB on a linked one, which is the defect.
- **Pass 5 inherits four build questions**, all named and none settled here: the
  content-port method list; **`src/data/JsonAsset.gd`** — `infrastructure`, four
  outbound lines, named by no existing addon, and neither kernel nor port, so it
  is vendor-it / port-it / drop-it and this pass does not choose; whether
  `AnimationOpcodes.Op` follows `SideEffect` into the kernel or stays private;
  and `src/animation/ResourceHotReload.gd`,
  still ADR-0214's deletion question and now also one of the nine floor names
  (`new`, `resource_reloaded`, from `UnitAnimationViewerScene.gd`) — it is reached
  by no *declared* root and by a real file, and those are not in conflict.
- **The census baseline does not move at this pass.** Nothing is relocated here;
  dec. 10 is an instrument fix with a null diff on this checkout.

## Soft spots

**S1. The member scan is a regex, and it under-counts duck-typed reaches by
construction.** It resolves `Type.member` and `.member` on locals declared
`var x: Type`. A rig object passed as `Node`, stored in a `Dictionary`, or
reached through `get_node("...")` and used untyped is invisible to it — and dec. 3
found a `Cutscene` reach of exactly that shape by hand, not by the scan. **98 is
a floor on the interface and 18 is a floor on the published floor.** Every
prediction in dec. 12 that quotes a member count inherits this.

**S2. The 18-member floor was computed by excluding two named files, and one of
them is about to move.** Dec. 5's floor is *"reached by neither adapter nor
`tests/`"*. If dec. 4 lands, `SequenceViewer` is inside the addon and its 19
exclusive members become internal — but if dec. 4 is *rejected* at pass 5, those
19 rejoin the published surface and the floor is 37, not 18. **P1 is conditional
on dec. 4 and does not say so in its own row.** Reading them independently
over-reports the win by a factor of two.

**S3. Dec. 2 moves three enums out of classes that keep their behaviour, and
nothing here checks the split is free.** `Layer` is nested in an 888-line Node
that uses it internally; `FacingDirection` in a 369-line one. The kernel gets the
enum and the addon keeps the class, so the addon then *names the kernel* for its
own internal control flow — which ADR-0139 permits, and which also means the
split cannot be undone cheaply. No arm was run to check the three classes still
parse standalone after the split, because the split does not exist yet.

**S4. Goal #6 is answered as a DISPOSITION and not as a decision.** Dec. 7 splits
15 references into move / publish / inject and settles what happens to the
*addresses*. It does not settle what happens to the **212 MB** — where
`assets/sprites/` and `assets/characters/templates` live, who ships them, and
what a consumer without a FFT ROM gets. `Audio` has carried that question open
since ADR-0153 and `Battlefield` since ADR-0203. This pass adds a third instance
and a byte count; it does not add an answer, and P8 predicts it will be the
surprise rather than pretending it is not.

**S5. Dec. 11 records 437 jargon lines from a word list I chose by eye.** Eight
terms, picked by reading this system's own sources. A ninth term nobody thought
of reads as zero, exactly the way `seq` and `evtchr` read as zero before this
pass. P6's ±ance is on the count, not on the list, and the list is the part with
no control.

**S6. Nothing here has been run in Godot.** Every number is static: a regex over
sources, two Python censuses and a cache. The claim that the rig is a severable
subtree rests on reading 128 lines of `.tscn` and three `@onready` lines — not on
booting a scene with the rig removed. `assets/scenes/Unit.tscn` is loaded by 26
files and a `.tscn` whose script fails to resolve still **mounts**, stripped,
failing at the first property touch (ADR-0157 Spike A). Pass 6 must boot before
it believes dec. 3.
