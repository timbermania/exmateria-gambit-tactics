# The kernel publishes no names, so the vocabulary move is sixty-one alias declarations — and the rig needs a façade before it needs a seam

Loop **pass 4** of extraction #4 — *grill the design, and name it*. Status:
**accepted (2026-08-31)**.

Code at trunk `463d7bbd8`. This pass moves no code. It attacks
[ADR-0215](0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md)'s
twelve decisions, discharges or carries its six soft spots, settles the four
questions it left for pass 5, and fixes the vocabulary the extraction will
publish to readers who cannot ask.

**Pass 3 designed the seam against the rig's own crossings. It did not check the
design against the addon conventions the destination already enforces**, and
three of its decisions collide with them. `addons/exmateria_schema/` declares
**no global names** — ADR-0212 dec. 3 stripped all six and
`tools/check_addon_globals.py:136` pins the allowance at `set()` — so dec. 2's
enum move is not the zero-cost re-classification it is priced as, and **P3b is
falsified before pass 6 begins**. The same convention says the rig itself must
publish behind a folder-named façade, which pass 3 never mentions and which
changes what P1 is counting.

## Context

`../docs/agents/refactor-loop.md:356` asks pass 4 for two things: grill the
design, and settle the vocabulary. ADR-0215 dec. 12 wrote P1–P8 down *before*
the build so pass 9 can be wrong about them, and named two rows as already
fragile. Pass 4's job on the prediction is to make each row **falsifiable and
correctly stated**, not to revise it toward comfort — so where a row moves here,
this ADR says which and why the original was unfalsifiable.

The naming half has a stated hazard: `docs/context/18-sprite-layers.md:231`
already carries *"Three distinct 'palette' usages in this codebase, do not
conflate"*, and Sprite Rig's terms are spread over five clusters. A published
addon's terms are read by people who cannot ask.

## Decision

**1. The kernel publishes NO names, so dec. 2 costs sixty-one alias
declarations — and the number that breaks is P3b, not dec. 2.** ADR-0212 dec. 1
is *one global `class_name`, spelled `ExMateriaX`, in
`addons/exmateria_x/exmateria_x.gd`*, and `check_addon_globals.py`'s
`BURN_DOWN["exmateria_schema"]` is `set()` — empty, with both directions scored.
A moved enum therefore reaches as `ExMateriaSchema.<Member>.<Enum>`, or its
naming file adds `const X = ExMateriaSchema.X` (ADR-0211 dec. 4).

Measured: **61 files name one of the six enums by its qualified spelling — 24
production, 37 `tests/`.** Five are inside the rig's 29-file scope, 56 outside.

Dec. 2's headline — *"without re-pointing a single call"* — **survives on its
literal wording**: with the alias in place no call site changes, which is
precisely why the dec. 1 member scan remains a valid instrument for P1. What
does not survive is the accounting. Eight rig files use one of the six enums
(`AnimationClock`, `AnimationPlayback`, `AnimationResolutionMap`,
`AnimationStateController`, `DisplayActivity`, `SpriteLayerManager`,
`UnitDisplay`, `UnitMaterial`), so each takes one alias line **inside the
addon**. The worked precedent is already in the scope:
`src/effects/CrystalSpriteCompositor.gd:24-25` is two such lines, and **those two
lines ARE P3b's `ExMateriaSchema` 2**.

| | P3b as written | corrected |
|---|---:|---:|
| `Tune` | 2 | 2 |
| `PSXDisplay` | 2 | 2 |
| `ExMateriaSchema` | **2** | **2 + 8 = 10** |
| kernel/port `#include` | 5 | 5 |
| **total residual** | **11** | **19** |
| P3b's falsification ceiling | | **>13** |

**P3b was unfalsifiable as written, because its residual set omitted the lines
its own sibling decision creates.** It is restated in dec. 14, not retuned. This
is the eighth published number corrected under measurement across passes 2–4,
and dec. 15 is the answer that family is owed.

**2. `Sprite Rig` publishes behind `ExMateriaSpriteRig`, and this is an
invariant rather than a choice.** `check_addon_globals.py`'s `FACADES` dict is
the assertion, and its docstring is explicit that **a count of one was never the
invariant**: `exmateria_render` already declared exactly one global, `FoldSurface`,
and ADR-0212 killed it anyway because it was unbranded. The nine floor names of
ADR-0215 dec. 5 are published as `const X = preload(...)` on the façade, and the
addon declares nothing else. Scale is unremarkable — `exmateria_render` publishes
1, `exmateria_platform` 3, `exmateria_battlefield` 14.

**P1's name half is therefore not a prediction.** *"18 behaviour members over ≤9
names"* counts a quantity a guard already fixes at one. P1's falsification
criterion is on members and survives; its wording is corrected in dec. 14 to
**one global name publishing 9 constants over 18 behaviour members**.

**3. The scene publishes through a DECLARED MOUNT, not through the façade — and
`assets/scenes/Unit.tscn` already is one.** ADR-0215 dec. 3 rejects ADR-0204's
answer, correctly, for the **node-path** question, which is two `Cutscene` sites.
On the **scene-path** question it is already doing ADR-0204's thing and does not
say so. `Unit.tscn:7` names `res://src/animation/SpriteLayerManager.gd` by
`ext_resource`; **114 files reference `Unit.tscn`** (5 production, 109 `tests/`);
after the move `Unit.tscn` is the only file in the tree naming an addon path.
That is `check_lattice_scene.py`'s `DECLARED_MOUNTS` shape exactly — ADR-0204
dec. 1 collapsed 107 consumers to 1, this collapses **114 to 1** — and the 109
tests never learn the addon exists.

The façade does not also publish the scene. `const UnitRig =
preload("…/UnitRig.tscn")` would satisfy `_PUBLISHED_CONST` and resolve fine, and
would give the rig **two spellings of one publish** — a symbol channel and a path
channel naming the same thing, so pass 9 would have two numbers for one question.
ADR-0205 dec. 2 already forbids exactly that merge for the guards; this applies
the same rule to the publish.

**4. `check_lattice_scene.py` widens from one hardcoded addon to a dict, and the
register goes FIRST.** The file is `ADDON = "addons/exmateria_battlefield/"` — a
single string — so criterion 4 is today a Battlefield-only register, empty and
closed (ADR-0209). Without widening, the rig's scene publish is unscored and P4
covers only `res://assets/`, never `res://addons/`.

Seeding order is not a detail. ADR-0205 dec. 7's own account is that **83% of the
opening rows were `MapComposer.gd`, and the only evidence separating "the reach
is gone" from "the scanner stopped seeing it" was watching 115 frozen rows go
STALE**. Sprite Rig has the same shape at 114 `Unit.tscn` referrers. The register
is seeded before the move or the move is ungraded — ADR-0192 dec. 1 a fourth
time.

**5. The CITE arm gains a third label, and that is ADR-0215 dec. 4's obligation
mechanized.** `arm_citations` requires every published constant to state a host
use and re-checks that the cited file still exists and still names the symbol.
That is nearly dec. 4's test — *"if it needs a member `Unit.gd` does not, that
member is published; if it needs a private, the interface is wrong"* — but
`_ADDON_CITE` flags an unlabelled citation only when it names a **different**
addon. A citation inside the same addon passes silently.

So a member published solely because the in-addon `SequenceViewer` wants it reads
**green**, which is precisely the failure dec. 4 raises and then leaves to a
prose ⚠️. A `Sprite Rig` façade constant whose citations are all inside
`exmateria_sprite_rig` must say so in the same words-based way `SIBLING NAMER`
works, and the count is reported. **That turns dec. 4's obligation into a number
pass 9 can read: a viewer-only count above zero means the interface shrank to
what one adapter wanted.** One branch beside the existing `unlabelled` check.

**6. The vocabulary is FIVE enums, not six, and `AnimationOpcodes` stays whole.**
Measured: `Op` has **zero** namers outside `src/animation/` — all 26 uses are the
rig's own, so ADR-0215 dec. 2 is exactly right that no outsider names it. And
`SideEffect`'s four outside lines are `CombatLoop.gd:1296` plus
`SequenceViewer.gd:440/453/468`, which move **inside** under dec. 4. **After dec. 4,
`SideEffect` crosses on exactly one line** — which P2's own arithmetic already
states.

The two enums share four member names with different integers
(`Op.QUEUE_SPRITE_ANIM` = 2, `SideEffect.QUEUE_SPRITE_ANIM` = 0). Splitting them
across a package boundary manufactures a conflation hazard in the pass that
exists to retire conflation hazards, and it does so to relocate a one-line
crossing. So: **neither moves.** `AnimationOpcodes` is published on the rig's own
façade and `CombatLoop.gd` takes one alias line. Dec. 2 becomes 213 of 489 uses,
**43.6%** instead of 44% — a change to nothing it claims.

**7. The names. Every one follows the kernel's own `DepthMode.Mode` /
`CellMarking.Kind` form: a subject noun, then the kind of thing it classifies.**

| today | crossing uses | published as |
|---|---:|---|
| `DisplayActivity.Activity` + `LOGICAL_ACTIVITY_*` | 64 | `ExMateriaSchema.UnitActivity.Display` / `.Logical` |
| `AnimationStateController.FacingDirection` | 52 | `ExMateriaSchema.Facing.Direction` |
| `SpriteLayerManager.Layer` | 50 | `ExMateriaSchema.SpriteLayer.Kind` |
| `AnimationClock.Owner` | 38 | `ExMateriaSchema.ClockOwner.Kind` |
| `UnitMaterial.Variant` | 9 | `ExMateriaSchema.UnitMaterialVariant.Kind` |
| `AnimationOpcodes.SideEffect` | 4 | `ExMateriaSpriteRig.AnimationOpcodes.SideEffect` (dec. 6) |

`SpriteLayer` rather than `Layer` and `ClockOwner` rather than `Owner` because
the bare words are ADR-0212's own examples of the hazard, and even behind a
façade `ExMateriaSchema.Layer` tells a stranger nothing. **The three
behaviour-bearing hosts keep their class names and their behaviour**
(`SpriteLayerManager` 888 lines, `AnimationStateController` 369,
`UnitMaterial` 57); only the enum moves, and each then names the kernel for its
own internal control flow, which ADR-0139 permits and ADR-0215 S3 correctly says
cannot be undone cheaply.

**8. The taxonomy is the unit of decision, not the display enum — because
`DisplayActivity` is not a file.** ADR-0213 selected this system on the finding
that its widest inbound name — 41 of 119 lines — is a *generated* enum, and pass
3 then planned the move as though the enum were a file. `src/animation/DisplayActivity.gd` is
generated. `tools/gen_activity_taxonomy.py` emits **five** artifacts from
`tools/activity_taxonomy.yaml`:

| target | bucket |
|---|---|
| `src/animation/DisplayActivity.gd` | **Sprite Rig** |
| `src/gpu/GPUConstants.gd` — `LOGICAL_ACTIVITY_*` | `Battle` |
| `src/gpu/shaders/combat_common.glslinc` — the same constants in GLSL | `Battle` |
| `src/gpu/ActivityTranslator.gd` — the dispatch shell | `Battle` |
| `docs/context/18-sprite-layers.md:392-412` | **this pass's own cluster** |

The display half and the logical half are generated from the **same YAML rows**
and exist only to be translated into each other. Moving one into the kernel and
leaving the other in `Battle` splits a single source of truth across a package
boundary; a value vocabulary two systems must agree on is the kernel's, which is
ADR-0196's argument for `CellMarking` applied unchanged. **So
`ExMateriaSchema.UnitActivity` publishes both halves**, generated into the addon
by the same script, with `Battle`'s GLSL and `GPUConstants.gd` emitted as before.

Two consequences pass 6 must hold. `ActivityTranslator.gd:350` and `:367` write
the literal string `DisplayActivity.Activity.<X>` into a host file, so the
**generator** carries the rename, not a `sed` over the tree. And the CONTEXT
region is machine-owned — dec. 13.

**9. The content port is seven SCALAR queries over FOUR key spaces, and "keyed by
FFT id" is the defect.** ADR-0215 dec. 6's shape claim holds — one port, all pure
queries — but two of its four rows are "id → dict" only because of how they are
spelled today: `AnimationResolutionMap.gd:377` calls `get_ability_view(ability_id)`
and reads one field, `SpritePaletteResolver.gd:68` calls `get_job(hex)` and reads
one key. **No content record crosses.**

```
weapon_v_offset(item_id) -> int                # ROM ITEM id
wep1_frame_offset(weapon_type_id) -> int       # weapon TYPE id
wep2_frame_offset(weapon_type_id) -> int
eff1_frame_offset(weapon_type_id) -> int
job_body_palette_row(job_hex) -> int           # job id, hex STRING
job_is_monster(job_hex) -> bool
ability_effect_anim_id(ability_id) -> int
```

Published as **`ExMateriaSpriteRig.ContentPort`** — the façade already supplies
the subject, so `SpriteContentPort` would read as a port for sprite-content
rather than the rig's port for content.

⚠️ **Dec. 6 calls this "ONE port keyed by FFT id". It is keyed by four different
things**, and `SpriteLayerManager.gd:209`'s own comment is a standing warning
about exactly this collision: *"The table is keyed by ROM **item id**, NOT
items.json.graphic (which is the menu-icon index — a separate concept). Wrong key
samples the wrong row of WEP1.tga."* A published port whose signature says `id`
four times for four key spaces makes that hazard permanent and hands it to
readers who cannot ask. **The key kind is carried in every parameter name**, and
the port is not split in two — the parameter names make the distinction the type
names would only duplicate.

**10. Dec. 4 is SETTLED yes, and its obligation is promoted from a ⚠️ to a
numbered decision with a pass-6 test.** ADR-0215 S2 is right that P1 is
conditional on dec. 4 and does not say so — if dec. 4 were rejected,
`SequenceViewer`'s 19 exclusive members rejoin the surface and the floor is 37,
not 18, so reading them independently over-reports the win by a factor of two.
The evidence for dec. 4 is unrebutted: 575 lines, one non-rig typed reach
(`AnimationNames`, 2 lines), `docs/ROOT_SET.tsv:13` already calling it the rig's
exerciser, and a `.tscn` naming nothing else. It ships inside.

What needed promoting is not the yes. It is *"the viewer must drive the rig
through the same published interface `Unit.gd` uses"* — the only thing keeping
the published interface from shrinking to one adapter's needs — and dec. 5 is now
the machine that reads it.

**11. Dec. 11's REFUSAL stands and its ARGUMENT is replaced, because S5's missing
control now exists.** Scored per system with `score_goals`' own strippers, the
eight added terms:

| | OLD | +WIDE (substring) | +WIDE (token) |
|---|---:|---:|---:|
| **Sprite Rig** | 39 | **434** | 406 |
| Battle | 69 | 257 | 247 |
| Cutscene | 144 | 45 | 45 |
| **Effects** | 229 | **382** | **35** |
| Battlefield | 89 | 34 | 28 |
| Audio / Render | 33 / 3 | 4 / 0 | 4 / 0 |

Dec. 11's stated ground — *"it scores `Render`, `Audio` and `Battlefield` too"* —
is worth **0, 4 and 28** lines. The real ground is **`Battle` +247**: widening
would change the instrument under a system nobody is measuring, which is
ADR-0131's objection with the right subject.

🔴 **And the uncontrolled part is the MATCHER, not the list.**
`score_goals.jargon_hits` matches by naked substring (`if term in low`).
`Effects`' 382 is `_sequence_canvas` ×46, `_sequence_panel` ×24, `sequence` ×18 —
the Effect Studio's animation-sequence UI, not FFT's `.SEQ` format. **The single
term `seq` decides the entire cross-system control**: for `Sprite Rig` the two
readings differ by 28 lines, for `Effects` by 347. S5 says *"the list is the part
with no control"*; measured, the truer statement is that **adding a three-letter
token to a substring matcher is not the same operation as adding `evtchr`**.

P6's numbers survive unchanged — 434 substring / 406 token, both inside its
350–520 band. The matcher clause is filed for the epilogue's re-baseline
alongside the widening, not applied to `score_goals.py` now.

**12. `assets/materials/unit.tres` is HOST-INJECTED, so P4 stays 0.** ADR-0215
dec. 7 classes it A′ — *publish, do not move* — which leaves
`src/animation/UnitMaterial.gd:31` `const BASE_MATERIAL :=
"res://assets/materials/unit.tres"` addressing `res://assets/` **from inside the
addon**, while P4 predicts zero such addresses. The two contradict.

Dec. 7 yields. `UnitMaterial.for_variant()` already `duplicate()`s the base, so
taking it as a parameter is the same shape as the nine Class B injections and
removes the addon's last `res://assets/` address without paying dec. 7's
four-inbound cost. It also fixes something dec. 7 did not notice: `Unit.gd:628`
and three `tests/` each `load()` that path independently today, so injection
gives four call sites one source instead of four.

**13. Cluster 18 declares its machine-owned region, and the activity rename goes
through the YAML.** `docs/context/18-sprite-layers.md:392-412` is regenerated by
`gen_activity_taxonomy.py`. A hand edit there survives until the next
regeneration and then vanishes with no diagnostic — the same *green because the
instrument stopped looking* shape this family keeps hitting. The cluster is 482
lines and a reader has no way to know twenty of them are not editable, so it says
so.

**14. THE PREDICTION, restated. Four rows move; each says why the original was
unfalsifiable.**

| # | status | prediction |
|---|---|---|
| **P1** | **FALSIFIED — measured 30 (#746)** | predicted **one** global name publishing **9 constants over 18 behaviour members**, falsified if **>24** non-enum members are reached from outside. The one global name is right and is a guard invariant. The interface is not: the census reads **18 published names carrying 30 non-enum members plus one enum, over 53 host files**. 30 > 24. The interface was NOT tuned to the floor — the ticket's own wording forbids that — and the amendment says why the prediction missed. |
| **P2** | **FALSIFIED — measured 44 (#745)** | inbound **84** lines, ±20. Scored on **`tools/.touch_cache.json`, all buckets**, not on `touch_matrix.py`'s printed matrix — the printout iterates `SYSTEMS` only and reads 119, and that exact gap caused five of ADR-0214's corrections. |
| **P3a** | **HOLDS at 0 (#745)** | outbound SYSTEM reaches 27 → 0, `check_addon_portability.py` arm 1. |
| **P3b** | **FALSIFIED — measured 23 (#745)** | conformant residual **19 lines** — `Tune` 2, `PSXDisplay` 2, `ExMateriaSchema` **10**, five `#include` — falsified outside **17–21**, or by any residual outside the kernel/port set. *The original omitted the eight in-addon alias lines dec. 2 itself creates.* |
| **P3c** | **moved 7 → 2, not met (#745)** | the 7 `content`+`generated` lines → 0 via dec. 9's port; `JsonAsset` 4 survives by design (dec. 16). |
| **P4** | **HOLDS at 0 (#745)** | **0** `res://assets/` addresses in the addon — 4 Class A move, **10 injected** (dec. 12 moves `unit.tres` from publish to inject), 1 published as a call. |
| **P5** | **UNSCOREABLE — no GOALS.tsv rows (#745)** | goals 6 met / 1 n/a / 3 open. |
| **P6** | **FALSIFIED — measured 651/579 (#745)** | goal #7 scores `content 0` and it is wrong; true count 437, band 350–520. |
| **P7** | **measured 6,913 / 35 (#745)** | ~6,000 lines / ~31 files, inside `WALK_ROOTS`. |
| **P8** | **byte count moved; verdict is pass 9's (#745)** | the largest surprise is content, not code — the 91.7 MB `assets/characters/templates` crossing. |
| **P9** | **FALSIFIED — measured 1 + 11 (#744)** | predicted criterion 4 for `exmateria_sprite_rig` seeds at **1** — `assets/scenes/Unit.tscn`, a `DECLARED_MOUNTS` entry — falsified by any second host file naming an addon path. There are eleven burn-down rows beside the mount. See the amendment. |

**15. A published number must name its instrument's BLIND SET, or a later pass
may not quote it.** ADR-0214 S4 asks whether five corrections to a two-day-old
ADR mean the pass-1 method is under-specified, and says the *method* ADR owes the
answer rather than another extraction's pass 3. It is now **eight** across three
passes, and every one has the same shape: **a number published from an instrument
whose blindness was known but not carried into the number.**

That is not carelessness and being careful will not fix it. P3c already does it
right — it names `JsonAsset` 4 as *"the one line-item this pass does NOT dispose
of"* — and P3b did not, which is exactly why P3b broke. **The rule lands in
`../docs/agents/refactor-loop.md`**, where it constrains passes 1–3 of every
future extraction rather than this one.

**16. `JsonAsset` is `platform`'s, and the deferral names its owner.** ADR-0215
leaves it as vendor-it / port-it / drop-it. Measured, none of the three is
available to this extraction:

- It is **not a 4-line file** — that is four *outbound touch lines*. It is 65
  lines with **~30 host namers** across `src/data`, `src/scenarios`,
  `src/characters`, `src/audio`, `src/animation`, `src/scenes` and `tests/`.
  Shipping it means 26 host files reaching into this addon.
- **Vendoring is self-refuting.** The file exists so *"a parse-handling fix lands
  once instead of ×18"*; a second copy re-creates the defect it was built to
  remove.
- **Injecting is wrong for Class A content.** `weapon_animation_ids.json` and
  `map.tres` move *into* the addon under dec. 7, so the addon must be able to
  read its own files.

The right home is `exmateria_platform`, whose README defines its tier as *"every
bucket needs some of them and none of them belongs to a system"* — and
`classify_blueprint` books `infrastructure` as four `plugin.gd` files plus
`AssetManifest`, `UserSettings`, `ValidationUtils` and `JsonAsset`: a residual
bucket with no address. But that is a tier reclassification mid-series plus a
30-file edit, paid to relocate four lines of this system's debt. **So: deferred,
owner named** — ADR-0196 dec. 5's rule that a deferral must name the pass that
owns the resolution. Sprite Rig carries 4 lines of declared debt into pass 9 and
P3c stands.

**17. `ResourceHotReload` moves IN, and the deletion question is filed
separately.** It hardcodes `res://assets/animation_resolution/map.tres`, which
dec. 7 Class A moves into the addon. Left host-side it names
`res://addons/exmateria_sprite_rig/…` — a criterion-4 row against the register
dec. 4 just decided to seed, on day one. So the path decides it: the watcher
follows its file or it becomes debt. It stays one of the nine published names
(`new`, `resource_reloaded`, from `UnitAnimationViewerScene.gd`, which dec. 4
correctly keeps host-side).

Whether live-edit should exist at all is ADR-0214's question and this pass has no
evidence for it. Deleting it would improve P1 to 16 members over 8 names, **which
is the reason not to decide it on a metric**.

**18. SOMETHING WAS RUN IN GODOT, and dec. 3 survives it.** ADR-0215 S6 is that
every pass-3 number is static. Taken on the 4.8 fork (`4.8.dev.custom_build`),
headful, instantiating `assets/scenes/Unit.tscn`:

- **Claim A holds.** All four rig nodes resolve off the scene root at runtime —
  `UnitMesh` (`MeshInstance3D`), `SpriteLayerManager`, `AnimationStateController`,
  `CameraRelativeRenderer` (`Node`). The contiguous-subtree reading was not an
  artifact of reading 128 lines of `.tscn`.
- **Claim B holds, and is worse than stated.** Renaming `UnitMesh` and re-running
  the `Cutscene` spelling returns `null` with **zero engine diagnostic**. And both
  crossing sites are *designed* to swallow it: `ScenarioDialogueBoxPool.gd:517-519`
  and `:728-730` each carry an explicit `if == null` fallback to
  `speaker.global_position`. So a rename does not remove the dialogue box — it
  **silently moves its anchor from the drawn sprite column to the unit's tile
  origin**, the ~65–76 px error the surrounding twenty lines of comment exist to
  prevent. Meanwhile `Unit.gd:490` uses bare `get_node("UnitMesh")` and **would**
  error. The host adapter fails loudly; the two crossings fail silently. That
  asymmetry is the case for dec. 3's guard arm, and it is stronger than *"returns
  null on a miss"*.

🔴 **And the witness found something no static pass could.** Booting emits two
warnings: `assets/scenes/Unit.tscn:6` and `assets/materials/unit.tres:4` both
carry `uid="uid://ccamm5qdra3tb"`, which **resolves to nothing** — `01.tga`'s
actual UID is `uid://coaet4wasli5v` — so Godot falls back to `path=`.
`check_lattice_scene.py`'s own blind-spot note reasons the other way: *"GODOT
RESOLVES BY UID AND IGNORES THE PATH… a fix here must swap `uid=` AND `path=` —
editing one is a no-op."* On these two rows the UID is already dead and the path
is what resolves, so a mover written to the register's stated model breaks them.
**They are the two files at the centre of dec. 3 and dec. 12.** Pass 6 fixes both
attributes and boots before it believes either.

## Amendment (2026-09-02) — #744, #746 and #745 built it, and FIVE of the nine predictions are falsified

Three tickets, one dated section, because `tools/check_adr_shape.py` caps an ADR
at one and the cap is the point: a reader gets the decision and one note, not a
chronology. #744 moved the population in; #746 drained the `class_name` channel to
zero; #745 booted the tree with the rig REMOVED and scored the whole P-table. Five
predictions are falsified — P1, P2, P3b, P6, P9 — and four of the five failed the
same way: a number scoped to a population its own instrument cannot see.

### #745 (2026-09-02) — S5 discharged: the removal is THREE outcomes, and the P-table is five-for-nine

**1. S5's question had one answer in the ticket and has three in the engine.**
`assets/scenes/Unit.tscn` was moved aside with the addon deleted and the tree
booted headful on the fork. It does not produce ADR-0157 Spike A's stripped
mount, and it does not produce a single verdict at all — the removal splits into
three channels that fail differently:

* **Scene path — HARD, LOUD.** Spike A is about a `.tscn` whose *script* fails to
  resolve. `Unit.tscn` **inherits** `UnitRig.tscn`, and a missing BASE scene is a
  different failure: `load()` returns `null`. 26 `[ext_resource] referenced
  non-existent resource` errors and 13 `[UnitSpawn] failed to load
  res://assets/scenes/Unit.tscn`. Nothing mounts, stripped or otherwise.
* **Symbol — LOUD, cascading.** 22 × `Could not find script for class
  "ExMateriaSpriteRig"`, then `"DisplayActivity" is a constant, so it can't be
  used as a type` and `Failed to compile depended scripts`. `Unit.gd`,
  `CombatLoop.gd` and `UnitAnimationViewerScene.gd` come back with `base=''
  can_instantiate=false`.
* **Content port — CLEAN DEGRADATION.** The `SpriteRigContent` autoload compiles
  and answers `weapon_v_offset(0) -> 0`, because it names the façade **only in a
  docstring**. That is dec. 9's port doing exactly what it was built to do, and
  it is the one channel that degrades instead of failing.

**And the game still boots.** With the addon gone the tree ran the full 45 s at
62 fps; the control run with the rig present has zero errors and zero
`[UnitSpawn]` lines. Severability is therefore true in the sense dec. 3 needs —
the host survives the rig's absence — and false in the sense the ticket assumed:
the failure is loud, immediate and total for anything that spawns a unit.

⚠️ `ProjectSettings.get_global_class_list()` still lists `ExMateriaSpriteRig`
after the addon is deleted. It reads the `.godot` cache, not the tree, so it is
NOT a witness for a removal probe. Corrected number: of PR #787's *"53 host files
naming the addon by symbol"*, **52 are code namers** — `src/data/SpriteRigContent.gd`
names it in a comment only.

**2. Criterion 2 — `resources/map.tres` loads with all three global names
stripped.** 10 sprite types, **132** state rows, scripts resolved by
`ext_resource` path with `get_global_name() == ''`. The dead `script_class=`
header attribute is not load-bearing, which is #744's probe result reconfirmed on
a tree where the names no longer exist anywhere. *The first run of this probe
returned a false "stripped mount" verdict because the probe read `activities`;
the exported member is `states`. The corrected reading is the one above.*

**3. Criterion 3 — the arm fires, and the harm it advertises is NOT
reproducible.** Both crossings were driven headful against the real `ScenarioVM`
/ `box_pool` / `DialogueBox`, first on a resting unit and then on
`assets/scenes/ScenarioPlayer.tscn` (scenario 1). All ten live units report
`UnitMesh.global_position - unit.global_position == (0, 0, 0)`, so with the node
renamed both crossings return **byte-identical** anchors: the error is **0.0 px**,
not 65–76. The cause is two defaults — `ANCHOR_QUAD_FRAC_Y_DEFAULT` is `0.0` and
`Tune`'s `render.unit_y_lift` binds `0.0`, while `Unit.gd` carries a literal
`0.05` in a third home that never runs. Displace the mesh synthetically and the
fallback does diverge, at **43.2 native px**, so the channel is live. The ~18 px
PAR drift and the 76 px carry-pose slide are decode facts of the SPRITE and
survive the fallback unchanged; a rename cannot re-open either.

The arm itself is sound — rc=1 on a seeded `UnitRig.tscn` rename, green on
revert — and `tools/check_mount_node_paths.py`'s header and red message are
corrected in this ticket. The lesson is the one dec. 18 was reaching for and
mis-stated: **a guard keyed on observable damage would score nothing here.** The
warrant is the silence, and the fact that the damage is zero only because a
tunable that is free to move happens to be zero.

**4. The P-table, scored on the instruments dec. 14 names.**

| # | predicted | measured | verdict | falsified by |
|---|---|---|---|---|
| **P1** | 1 global name / 9 constants / 18 members; falsified >24 non-enum | 1 global name; **20** published constants; **30 non-enum + 1 enum** | **FALSIFIED** (already, #746) | `746_members.py` |
| **P2** | inbound **84** lines ±20, all buckets | **44** all buckets — **36** net of the addon's own self-reach, **32** on the SYSTEMS-only reading | **FALSIFIED low** | `tools/.touch_cache.json` |
| **P3a** | outbound SYSTEM reaches 27 → **0** | **0** | **HOLDS** | `score_goals` goal #5 |
| **P3b** | residual **19** lines, band 17–21 | **23** — `Tune` 2, `PSXDisplay` 2, `ExMateriaSchema` 12 lines (10 alias rows), `#include` **7** not 5, plus 1 `ExMateriaPlatform.TunePort` line P3b never names | **FALSIFIED high** | touch cache + `check_addon_portability.py` |
| **P3c** | 7 `content`+`generated` → **0** | **2** (`SequenceViewer.gd:271,316` → `AnimationNames`); `JsonAsset` 4 by design | moved 7 → 2, not met | touch cache |
| **P4** | **0** `res://assets/` addresses in the addon | **0** code; 7 comment lines (4 `.gd`, 3 `.tscn` `;`) | **HOLDS** | `check_addon_portability.py` |
| **P5** | goals 6 met / 1 n/a / 3 open | **10 UNSCORED** — `docs/GOALS.tsv` has no `Sprite Rig` rows and the scorer defers them to pass 9 | **UNSCOREABLE** | `tools/score_goals.py` |
| **P6** | goal #7 scores content 0 and is wrong; true **437**, band 350–520 | content **0** ✓; widened with dec. 11's own eight terms: **651** substring / **579** token | **FALSIFIED high** | `score_goals.jargon_hits` |
| **P7** | ~6,000 lines / ~31 files | **6,913** lines / **35** source files (43 non-`.uid` tracked, 78 total) | holds within its tilde; no band was stated | `git ls-files` + `wc` |
| **P8** | content is the surprise — 91.7 MB `assets/characters/templates` | **96,278,494 bytes** through the symlink (was 91,726,944) | byte count moved +5.0%; the verdict is pass 9's | `du -sbL` |
| **P9** | criterion 4 seeds at exactly **1**, the mount | 1 declared mount + **11** burn-down rows | **FALSIFIED** (already, #744) | `check_lattice_scene.py` arm 1 |

**5. Two instrument blind spots, both found by scoring rather than by reading.**

* **`tests/` is not in `WALK_ROOTS`.** `classify('tests/…')` is `None` and the
  walk never opens those files, so the **37 host test files that name
  `ExMateriaSpriteRig`** contribute **0** to P2's inbound count. P2's instrument
  is structurally blind to the single largest population of host namers, which is
  dec. 15's rule with a name and a number attached.
* **`classify_blueprint` books `viewer/SequenceViewer.gd` — a file INSIDE the
  addon — to `assembler`.** Its seven internal `preload`s and its own façade
  reach therefore score as *inbound crossings to the addon from outside*, and its
  two `AnimationNames` lines and one `ExMateriaSchema` line escape the `Sprite
  Rig` outbound column. Eight of P2's 44 lines are the addon reaching itself.
  That same mis-booking is why P6 moved: `SequenceViewer.gd` alone is **156** of
  the 651 widened jargon lines, and it was outside the 29-file scope when 437 was
  measured, so dec. 10's own ruling that the viewer ships inside is what put P6
  out of its band.

Both are the shape this ADR keeps meeting: the number was fine, the **population
the instrument could see** was not.

**6. WHAT #745 DID NOT SETTLE.** P5 cannot be scored until pass 9 writes the
`Sprite Rig` rows into `docs/GOALS.tsv`; P8's verdict is likewise pass 9's, and
its byte count is a claim about the pinned asset hub's checkout, not about this
branch — `du -sb` without `-L` reads the symlink at **78 bytes**. `#745`'s own
probe files add one member to the census (32 rather than 31 printed); the
comparable figure to #746 is 30 non-enum + 1 enum, and the probes are named here
so a later pass does not read their reach as host coupling.

### #746 (2026-09-02) — the burn-down reads 0, and the published surface is 18 names / 30 members

`check_addon_globals.py` now prints *the global surface is 5 name(s), one per
addon*. The 20 `class_name`s #744 left owing are gone: 18 became façade constants
and host namers alias them back, 2 (`AnimationClock`, `PlaybackSet`) became
internal `preload`s with no publish at all.

**1. P1 IS FALSIFIED AT 30, AND THE INTERFACE WAS NOT TUNED TO HIDE IT.** Dec. 2
and dec. 14 said nine published names carrying 18 behaviour members, with the
other fifteen *"reached from NOWHERE outside this addon"* — the sentence the
façade itself carried. Measured on the merged tree, over `git ls-files`, with `#`
comments and `"""` docstrings stripped, `Name.gd` path strings excluded and
`ExMateriaSpriteRig.Name` façade accesses excluded: **18 names, 30 non-enum
members, one enum, 53 host files**. #746's acceptance criteria priced this exact
outcome in advance — *"report the number, do not tune the interface to hit it"* —
so the count is reported and the façade publishes what is reached.

**2. WHY IT MISSED IS THE SAME DEFECT AS P9's, ONE CHANNEL OVER.** The nine came
from `check_lattice_scene.py` arm 1, which scores `res://` PATH reaches — ten
`preload()` lines over three production files and seven tests. A host naming a
global `class_name` with no path anywhere is invisible to arm 1 **by design**;
`check_addon_globals.py`'s own SCOPE block says so about `#include`, and it is as
true of the symbol channel. Twelve of the eighteen lived there.
`AnimationStateController.angle_12bit_to_facing` alone is named on 18 lines across
13 files with no path reach to score, and `DisplayActivity.Activity` on 60 lines
across 22 files. **A prediction derived from one instrument cannot bound a
population that instrument is scoped away from** — which is P9's failure with the
channels swapped, and the pair of them is the finding, not either one alone.

**3. A GENERATED FILE'S `class_name` IS NOT IN THE FILE.** `DisplayActivity.gd` is
emitted by `tools/gen_activity_taxonomy.py`, and a hand-strip survives until the
next generator run — after which the pre-flight's `--check` arm reds on
*staleness*, days later, with the real cause gone. The line came out of
`emit_display_activity`. `tools/test_gen_activity_taxonomy.py` gained the mirror
of the kernel half's `test_the_kernel_member_declares_no_class_name`, and its
predicate is a **declaration**, not the substring: `assertNotIn("class_name",
text)` — the spelling the kernel half uses — fails on the emitter's own comment
explaining why there is no `class_name`. Proved red before it was trusted green.

**4. BOTH RATCHET ARMS WERE PROVED, NOT ASSUMED.** An entry naming a dead
`class_name` reds (`1 BURN_DOWN entr(ies) name no class_name any more`); a 21st
global beside the façade reds (`1 global class_name(s) beside the façade and
outside the burn-down`). Green again on revert, with a clean `git status` between.
An empty burn-down makes the ROT arm live rather than inert — the inverse of the
note that stood while names were owed.

**5. WHAT #746 DID NOT SETTLE.** `DisplayActivity.Activity` is the addon's widest
publish by use count and it is an ACTIVITY — game vocabulary by any reading of
dec. 2, which moved five sibling enums to `exmateria_schema` under #739/#740. This
one did not move. That is recorded, not decided: moving it changes the addon's
population, which is #744's territory, not this ticket's. S5 still stands — nothing
has yet booted the tree with the rig REMOVED, which is #745.

### #744 (2026-09-01) — the move, and P9

The move landed on `build/extraction-4-744-the-move`: 33 files into
`addons/exmateria_sprite_rig/`, `UnitRig.tscn` as the rig's own node tree with
`assets/scenes/Unit.tscn` inheriting it, and the dec. 3 mount live. Four things
the build measured that this ADR predicted differently, or did not predict.

**1. P9 is FALSIFIED — 1 declared mount + ELEVEN burn-down rows.** P9 said
criterion 4 for this addon *"seeds at 1 … and that one row is a `DECLARED_MOUNTS`
entry, not a burn-down row. Falsified by any second host file naming an addon
path."* There are eleven. Six are argued permanent — `assets/materials/unit.tres`
and five `tests/` sites that name a shader or a script *as data* — and four
belong to one dead file. Reported, with a dated owner on every row, rather than
absorbed; that is what the criterion asks for and it is what P9 was written to
make visible.

The prediction was not merely optimistic, it was **scoped to the wrong channel**.
P9 counted host files reaching the rig, and the mount does collapse those: 114
referencing files became 1, exactly as dec. 3 argued. What it did not count is a
`tests/` file naming a *shader path* to read it as text, or a `.tres` naming one
by `ext_resource` — reaches that are not "the host using the addon" at all and
that a scene mount cannot collapse because they do not go through a scene.

**2. Retiring a global name GROWS this register, which no decision here
anticipated.** Dec. 7's Class A move brings `resources/map.tres` in; its
`script_class=` header and three `ext_resource path=` rows name three resource
classes. Whether those could lose their global `class_name` and still load was
answered by BOOTING it, not by reasoning: a probe `SceneTree` printed
`entries=10  nested resources WITH a bound script=10` before and after, byte for
byte, because `script_class=` is a hint the loader does not need when the
`ext_resource` rows address the scripts by path. So the three came off and the
`class_name` burn-down went 23 → 20.

The cost lands on a different register. Three reaches inside the (dead) one-shot
`tools/migrate_state_animations_to_tres.gd` were BARE IDENTIFIERS, invisible to
a path-based guard; the strip turned them into three `preload()` paths, which
that guard scores. Criterion 4 went **8 → 11 as a direct consequence of a win**.
Two name channels are not interchangeable, and a pass that measures one while
moving the other will read its own progress backwards.

**3. Dec. 3's guard arm is built — `tools/check_mount_node_paths.py`.** Dec. 18's
runtime witness is the specification: renaming a node inside the mount scene
returns `null` with zero engine diagnostic, and `ScenarioDialogueBoxPool.gd:517`
and `:728` each swallow that null by design, substituting the unit's tile origin
for the mesh origin instead of removing the box. (The magnitude asserted here and
in the guard's own red message — ~65–76 px — is FALSIFIED by #745 below; the
silence is real, the number was not.) Five crossings are declared with their
measured failure mode (four LOUD, one SILENT covering both pool sites); three
arms — the name resolves, discovered equals declared, the mount itself parses —
each proved red on a seed before being trusted green. It is a pre-flight abort.

**4. `engine="stock"` was a true claim about the skeleton and is false about the
rig.** The skeleton's own `plugin.cfg` comment said to re-measure once the
population arrived. `crystal/crystal_fold.gdshader:17` is `render_mode …
compositor_layer` — the fork-only primitive — so the declaration is now
`engine="fork"`, and `deps="exmateria_schema exmateria_platform"` from the
measured 10 + 1 port reaches. `exmateria_render` is not a dep: the crystal
compositor's `EngineFoldCompositor` half is reached by the HOST, and zero `.gd`
lines in this addon name it.

**S5 stands.** Nothing here booted the rig *removed*, which is what dec. 3's
severability claim rests on; #745 is that boot.

## Considered alternatives

**Read P3b's blowout as evidence that six enums into one kernel is the wrong
shape.** Rejected — dec. 1. The design is right; the accounting was incomplete.
The alias is not overhead, it is the mechanism ADR-0211 dec. 4 built so use sites
keep their spelling, and it is what keeps the dec. 1 member scan valid as P1's
instrument. Nineteen residual lines against 98 members of published surface is
still the trade the extraction exists to make.

**Move `SideEffect` to the kernel with the other five, as dec. 2 has it.**
Rejected — dec. 6. One crossing line after dec. 4, bought by putting two enums
that share four member names at different integer values one package apart.

**Move `AnimationOpcodes.Op` across too, so the pair stays together in the
kernel.** Rejected — dec. 6. The kernel would gain a 34-member FFT SEQ opcode
table no second party names, which is the opposite of *"what two sides must agree
on"*.

**Publish the rig's scene as a façade constant as well as through the mount.**
Rejected — dec. 3. Two spellings of one publish, and pass 9 with two numbers for
one question. ADR-0205 dec. 2's rule.

**Move `JsonAsset` into `exmateria_platform` in this extraction.** Rejected —
dec. 16. Correct destination, wrong pass: a mid-series bucket reclassification
plus ~30 host edits to relocate four lines of Sprite Rig's debt.

**Delete `ResourceHotReload`, which no declared root reaches.** Rejected —
dec. 17. It would improve P1 from 18/9 to 16/8, and a behaviour deletion argued
for by the metric it improves is the one shape this loop must not adopt.

**Widen `score_goals.JARGON` now that the control shows `Battlefield` moves by
only 28 lines.** Rejected — dec. 11. `Battle` moves by 247, and `Battle` is not
an extraction, so the instrument would change under a system nobody is measuring.
The refusal survives its own control; only its stated reason was wrong.

**Split the content port in two — `WeaponContentPort` and `UnitContentPort` — so
the key spaces are distinguished by type.** Rejected — dec. 9. It gives up
dec. 6's one-port finding for a distinction the parameter names already make.

## Consequences

- **ADR-0215's S2 and S6 are DISCHARGED** — S2 by dec. 10 settling dec. 4 and
  P1 losing its conditionality, S6 by dec. 18's runtime witness.
- **S3 is discharged in the direction that matters and carries in the other.**
  Dec. 7 confirms the three behaviour-bearing classes keep their behaviour and
  name the kernel for their own control flow; nothing here has *run* the split,
  and pass 6 still must.
- **S5 is discharged by dec. 11's control, and replaced by a sharper one**: the
  matcher, not the list, is the uncontrolled part.
- **S1 and S4 carry.** S1's regex floor is untouched — every member count here
  inherits it. S4 is *answered* by dec. 15, in the method's own document.
- **P3b, P1 and P4 move; P9 is added.** Each says why the original was
  unfalsifiable rather than being retuned toward comfort.
- **Pass 5 inherits a smaller set than pass 3 handed it.** All four of ADR-0215's
  named build questions are settled (dec. 9 the port's methods, dec. 16
  `JsonAsset`, dec. 6 `AnimationOpcodes.Op`, dec. 17 `ResourceHotReload`). What
  it inherits instead is three instrument changes to sequence — the `FACADES`
  row, the criterion-4 dict, the CITE label — all of which must land **before**
  the move, per dec. 4. **Pass 5 measured that the `FACADES` row cannot**: the
  creep arm fails `no such addon folder` unconditionally on a missing directory,
  and `tools/test_check_addon_globals.py` asserts `BURN_DOWN[addon]` equals the
  live `class_name` set minus the façade for *every* `FACADES` key, plus a
  per-addon `MIN_GD_FILES` floor. The dict and the CITE label do land early — a
  `DECLARED_MOUNTS` row whose target does not exist yet prints `DEAD!` and scores
  nothing, and `arm_citations` returns early with no façade file. The `FACADES`
  row lands **with** the skeleton, burn-down seeded at **24**. See #735.
- **37 host `tests/` files take one alias line each, and no prediction scores
  them.** P1's scan excludes `tests/` and `touch_matrix` does not walk them.
  Stated so pass 9 does not find a 37-file edit and call it a surprise.
- **The five `docs/context/` clusters are edited in this commit**, and cluster 18
  declares its generated region.

## Soft spots

**S1. Dec. 7 names five kernel spellings and one of them is ugly.**
`UnitMaterialVariant.Kind` is long, and it is long because `Variant` alone
collides with Godot's own `Variant` and because cluster 22's *"camera variant"* is
a different concept the rig also owns. I did not find a better word; a reviewer
who has one should take it before pass 6 spells it into 61 files.

**S2. The 61 is a floor for the same reason 98 is.** It was taken by grepping the
six qualified spellings. A file that already aliases, reaches an enum
duck-typed, or names one from a `.tscn` in a form the grep does not match is
invisible to it — and ADR-0215 S1's `Cutscene` reach was found by hand, not by
scan. Dec. 1's alias-line arithmetic, and therefore P3b's 19, inherit this.

**ANSWERED by pass 5** ([#735](https://github.com/timbermania/fft-monorepo/issues/735)).
Probed four ways, three returned something. **12 of the 37 `tests/` files already
carry the alias line** for the facing enum, so pass 6 repoints rather than adds.
**Three `tools/` files** name a qualified spelling and are outside the 61. **No
enum crosses a `.tscn`/`.tres`** — the only scene-file hits are script paths.
**Zero inherited-alias reaches**: nothing uses a short spelling without also
naming a qualified one, so ADR-0211 dec. 4's hazard has no population here, and
dec. 1's arithmetic closes exactly — 5 in-scope namers plus the 3 *definers*
invisible to a qualified grep is its eight. Total alias lines **64**, of which 12
are repoints. And dec. 7 is confirmed by a collision that already exists:
`addons/exmateria_schema/colour_model/ColorStack.gd:38` declares `class Layer`,
so `ExMateriaSchema.Layer` would have collided **inside the destination addon**.

**S3. Dec. 5's third CITE label is designed but not built, and it is the only
mechanized half of dec. 4's obligation.** If pass 6 ships the façade without it,
the guard reads green over exactly the failure dec. 4 predicts, and nothing else
in the loop would notice. It belongs in the same commit as the `FACADES` row.

**S4. Dec. 8 widens dec. 2's scope on an argument, not a measurement.** Moving
the whole activity taxonomy into the kernel is right if the two halves really are
one vocabulary — which is read off the generator's shape and the YAML's own
"Vocabulary" header, not off a count of who names both. Nobody has measured how
many files name `LOGICAL_ACTIVITY_*` and would now name the kernel. Pass 5 should
take that number before it plans the generator change.

**ANSWERED by pass 5** (#735). **52 code files** name them — 44 `.gd`/`.py`, 8
GLSL. Every GDScript reach is spelled `GPUConstants.LOGICAL_ACTIVITY_*`, **227
lines**; the 39 occurrences without that prefix are comments, docstrings and
message strings, zero of them reaches. Because dec. 8 keeps `GPUConstants.gd` and
the GLSL *emitted as before*, **none of the 227 change** — the cost is one new
generator target and nothing else. Only **8 files name both halves**
(`ActivityTranslator`, `CombatLoop`, `CinematicDebugProbe`, four tests, and the
generator). So dec. 8's argument still rests on the generator's shape, as it says
it does; the measurement prices the change rather than moving it.

**S5. The runtime witness was one boot of one scene, and it proved the two
claims it was pointed at.** It did not boot the rig *removed*, which is what
dec. 3's severability claim actually rests on, and ADR-0157 Spike A's warning
stands: a `.tscn` whose script fails to resolve still mounts, stripped, failing
at the first property touch. Pass 6 must boot the extracted tree, not this one.

**S6. The stale-UID finding is two rows, and I did not scan the corpus for
more.** `check_lattice_scene.py` measured 1102 of 1102 `ext_resource` lines
carrying `path=` — it did not measure how many carry a `uid=` that *resolves*.
Two dead ones surfaced by accident, on the two files this design cares most
about, which is not evidence that there are only two.
