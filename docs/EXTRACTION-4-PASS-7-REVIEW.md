# Extraction #4 — `Sprite Rig`, loop pass 7 (Review)

Loop **pass 7** deliverable of extraction #4. Two axes, per
`~/.agents/skills/code-review` — **Standards** (does the code follow this repo's
documented standards?) and **Spec** (does it implement what #735 asked for?).
Findings are reported per axis and **deliberately not reranked across axes**.

Run 2026-09-03 against trunk `3bd00771e`. Scope is **what pass 6 built**, not the
whole addon: the 13 PR merge commits `0cb79cedb` (#736) … `4b5547a0b` (#810),
diffed first-parent, = **250 files / ~8,700 insertions** (93 `addons/`, 57
`tests/`, 41 `tools/`, 38 `src/`, 15 `docs/`; 130 `.gd`, 46 `.uid`, 28 `.py`,
17 `.md`, 9 `.tscn`, 4 `.gdshader`).

`tests/run_all_tests.sh --preflight-only` is **green, rc 0**, every static guard
OK, zero `FAILED` lines. Every finding below is therefore invisible to the
instrument set, which is the point of running the pass at all.

---

## Standards — 8 findings

### Hard (documented-standard breaches)

**S1. `addons/exmateria_sprite_rig/README.md:87` contradicts the shipped
`plugin.cfg` on every clause.** README: *"`plugin.cfg` declares what this addon
needs — `engine="stock"` and no `deps`. Both are still true with the port in: it
touches no compositor primitive and reaches no sibling addon."* Tree:
`plugin.cfg:22` `engine="fork"`; `plugin.cfg:35`
`deps="exmateria_schema exmateria_platform"`;
`crystal/crystal_fold.gdshader:17` `render_mode … compositor_layer;`. The
`stock`→`fork` flip was **re-measured in #744** and the cfg's own comment says
so. The README also still opens (L5) with `> **🔴 THIS IS A SKELETON.**`, four
PRs after the 33-file population landed. Stale by four PRs, in the one document a
stranger installing the addon reads first.

**S2. The README's published table is 2 rows against a 20-`const` façade.**
`README.md:20-21` lists `AnimationOpcodes` and `ContentPort`;
`exmateria_sprite_rig.gd` declares **20** `const`s. 18 publishes are
undocumented, including the widest — `DisplayActivity`, which the façade's own
docstring measures at 60 reaches over 22 host files.

**S3. `install/SpriteRigContentRoot.gd`'s `push_error` cites a README section
that does not exist.** The once-per-run error ends `See the addon README,
"Content the host must supply".` The rig README's headings are *The one global
name / What YOU have to supply: the content port / What is deliberately NOT
published / Install / Design*. The cited heading exists only at
`addons/exmateria_battlefield/README.md:250`. A stranger who hits the error is
sent to a **different addon's** document.

**S4. The façade header docstring is stale in the tense that matters.**
`exmateria_sprite_rig.gd:17-20`: *"It reads **20** now … #746 drains the 20."*
#746 landed. `check_addon_globals.BURN_DOWN["exmateria_sprite_rig"]` is `set()`,
commented "DRAINED TO 0 ON 2026-09-02 BY #746". It reads **0**, and the drain is
past, not pending.

**S5. 48 vault `R:` citations across 19 notes name paths #744 moved — and the
guard is green by design.** `check_vault_anchors.py`'s own docstring states the
rule (*"a comment travels through any rename, move or rewrite; an `R:` path
citation in the vault does not"*) and its own pre-move census (*"81 of the
vault's 320 cited paths are already dead at trunk"*). #744 added **48** more, in
this extraction's own subject files — **14 of the 34 moved paths** are cited —
and nothing counted them, because the guard enforces the anchor direction
(`Vault: [[X]]` → `vault/X.md`) and explicitly *"does NOT enforce coverage"*.

Affected notes: `Cinematic Palette Pipeline`, `Color Tint Luma Modes`, `Color
Unit Opcode`, `Crystal Status Visual`, `Display Space Blend Fold`, `EVTCHR CLUT
Resolution`, `EVTCHR Script VM`, `Inflict Status Opcode`, `Rotate Unit
Interpolation`, `Scenario 6 Ride Off`, `Scenario Camera Framing`, `SEQ Movement
Opcodes`, `Sprite Cardinal Pose Selection`, `TRAP Sprite Effect System`, `Unit
Anim Opcode`, `Unit Sprite Render Pipeline`, `Unit Sprite SEQ Opcodes`, `Walk To
Opcode`, `Weapon Animation System`.

This is the extraction-#1 lesson recorded at `docs/agents/refactor-loop.md:472`
firing again in the one direction pass 6 did not sweep — *"a passing suite is not
evidence of coverage; the only thing that surfaces this is asking, per guard,
whether the thing that used to watch a moved file still does."*

### Judgement calls (Fowler smell baseline)

**S6. Duplicated Code — one activity taxonomy, two generated enums, both
published.** `addons/exmateria_sprite_rig/state/DisplayActivity.gd`'s
`enum Activity` and `addons/exmateria_schema/unit_vocabulary/UnitActivity.gd`'s
`enum Display` are the same 14 members in the same order, emitted from the same
`tools/activity_taxonomy.yaml` by the same generator, and **both published**
(`ExMateriaSpriteRig.DisplayActivity` / `ExMateriaSchema.UnitActivity`). 21 files
name the rig spelling; 1 (`src/gpu/ActivityTranslator.gd`) names the kernel one.
The kernel file concedes they *"agree by construction rather than by anyone
keeping them in step"*. ADR-0205 dec. 2's *never two spellings of one publish* is
the rule this extraction cites elsewhere. Relatedly, the rig façade at L242-244
asserts *"this one did not move"* — a kernel copy did land and is published.

**S7. Incomplete guard — `content/ContentPort.gd:_resolve()` validates 1 of 7
methods.** It accepts any node at `^"SpriteRigContent"` that answers
`has_method(&"job_is_monster")`. An adapter implementing six of seven passes the
guard and then fails at the call site, **outside** the documented absent-behaviour
table (six queries → `0`/`false`, `ability_effect_anim_id` → `-1`), because
`_resolve()` already returned non-null. A defined ABSENT behaviour is the port's
whole value; a partial adapter falls outside it with no diagnostic.

**S8. Duplicated Code — `_check_registers()` is written twice.**
`check_lattice_scene.py:536` and `check_addon_install.py:361` carry the same
subject-vs-register drift check with **verbatim-identical** error strings. The
install copy is a strict special case (one register vs three). Noted with a
caveat: `check_addon_globals.py` has no `_check_registers()` at all — its
equivalent lives in `test_check_addon_globals.py` as
`test_every_facade_has_a_burn_down_and_a_floor` +
`test_FACADES_is_EVERY_addon_this_package_owns`, which is genuinely the strongest
of the three. One obligation, three placements, across three sibling guards.

**Worst within this axis: S5** — it is a measurement the loop depends on, it
grew by 48 during pass 6, and no instrument can report it.

---

## Spec — 3 findings

Source: issue #735, **30 user stories, all 30 checked against the tree.**

### (a) Missing or partial

**P1. Story 16 landed in the wrong commit and at the wrong number.** Spec: *"I
want `BURN_DOWN["exmateria_sprite_rig"]` seeded at **24** in the commit that
creates the folder, so that the ratchet's both-direction scoring is armed from
the first commit rather than retrofitted."* `d43fd371b` (#742 — the commit that
creates the folder) seeds `"exmateria_sprite_rig": set()`. The real seed arrived
in **#744**, and at **23**, not 24 — the façade records why (*"`AnimationOpcodes`
was the 24th and #742 had already stripped it"*).

The empty seed is defended in-line and is arguably *better* arming than asked: an
empty burn-down makes `arm_rot` live rather than inert, which forces the façade
into commit one. But it is exactly the retrofitted shape the *so-that* clause was
written to prevent, and the spec was never amended to say so.

### (b) Scope creep

**None found.** Everything traced maps to a story or to the Implementation
Decisions. `install/SpriteRigContentRoot.gd` reads as unasked at first pass; it is
story 13 made real, and the seven surviving `res://assets/` occurrences inside the
addon are all in docstrings or `.tscn` `;` comment lines, none in code.

### (c) Implemented but looks wrong

**P2. Story 5 is 5-of-5 only if two publishes count as one.**
`ExMateriaSchema.UnitActivity.Display`/`.Logical` exist and are used, but
`DisplayActivity.Activity` was not retired and is still what 21 files name. The
move is complete in the kernel and incomplete in the tree. Story 5's *so-that*
(no colliding bare English word) holds; **story 21's** (*"one number for one
question"*) does not, for this one vocabulary. Same defect as S6, seen from the
spec side.

**P3. Story 30's number drifted by one.** ADR-0217:696 states the obligation
verbatim (*"Stated so pass 9 does not find a 37-file edit and call it a
surprise"*) — but **38** `tests/` files carry a rig alias today. Pass 9 should
quote 38.

### Confirmed clean, with the check that confirmed it

| story | check |
|---|---|
| 1 | per-addon `DECLARED_MOUNTS`/`SCENE_BURN_DOWN` + `_check_registers()` raising on **both** drift directions |
| 2 | `_INADDON_NAMER` third CITE label, per-addon count printed on the passing **and** failing paths |
| 3, 4 | the two early instrument changes are in `#736`/`#737`/`#738`, all before `2d2a89c0f` |
| 6, 7 | 186 alias lines over 135 files, **zero** files carrying a duplicate alias of the same name |
| 8, 10 | `gen_activity_taxonomy.py` emits all six targets; `LOGICAL_ACTIVITY_*` untouched |
| 9 | `docs/context/18-sprite-layers.md:462-482` `BEGIN/END GENERATED` region declared |
| 11 | all five `ext_resource` uids in `Unit.tscn` resolve; `uid://b6unitrig4444` is declared at `UnitRig.tscn:1` |
| 12 | `check_lattice_scene.py:124-132` records the corpus scan: 1091/1091 lines carry `path=`, 149 carry `uid=`, **2 dead, both fixed**; re-run with symlinks followed → 1108 / 151 / **0** |
| 13, 14 | one live `load()`, `src/units/UnitAssets.gd:47`; the second `BASE_MATERIAL` const is a test oracle reading the file as a string |
| 15 | exactly **one** `class_name` in the whole addon |
| 17 | `ExMateriaSpriteRig.AnimationOpcodes` + one alias at `src/gpu/CombatLoop.gd:32` |
| 18, 19 | seven scalar queries; all seven signatures carry the key kind (`item_id`, `weapon_type_id` ×3, `job_hex` ×2, `ability_id`) |
| 20 | `assets/scenes/Unit.tscn:32` is the sole consumer path; the only other two namers are the guards policing it |
| 22 | 23 `tools/` files name the addon; **zero** name a moved-away path |
| 23 | missing-file behaviour recorded per guard |
| 24 | `classify_blueprint.py:66,119,128,129,631` |
| 25 | burn-down `set()`, both arms |
| 26, 27 | `tools/probe_rig_removed.gd`, `tools/probe_rig_map_load.gd` |
| 28 | `check_mount_node_paths.py:116` carries the `ScenarioDialogueBoxPool.gd`/`UnitMesh` row, both sites recorded `SILENT` |
| 30 | ADR-0217:696 (see P3 for the count) |

**Worst within this axis: P1** — a requirement written specifically to be
un-retrofittable was retrofitted, without an amendment recording it.

---

## Two corrections to the predecessor handoff

- **ADR high-water is ≥0225**, not 0223. Scanned unscoped across refs and
  worktrees, per the standing rule that the number is not the reader's to assume.
- **Axis B's two open Class E rows are discharged.** `pixel_aspect` and
  `unit_stretch` were closed on trunk by ADR-0220 —
  `addons/exmateria_platform/plugin.gd:97-109` now lists them in
  `PROVIDED_GLOBALS`. All four `check_addon_install` arms read 0, and arm 3 got
  there **by a fix rather than by silence**. The handoff prices this as open work.

Trunk has also moved 53 commits past the handoff's `4b5547a0b` (now `3bd00771e`).

## What this pass does NOT do

Pass 7 reports; it does not fix. S1–S8 and P1–P3 are **findings, not tickets** —
none is filed, and none should be filed against a number this document assumes.
Pass 8 (residue attribution) and pass 9 (the ten goals, `docs/GOALS.tsv`, #809's
two rows) are untouched and remain in sequence.
