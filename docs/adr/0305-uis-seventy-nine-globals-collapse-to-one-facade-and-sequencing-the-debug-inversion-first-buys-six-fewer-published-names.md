# ADR-0305 — UI's 79 globals collapse to ONE façade, and sequencing the debug inversion first buys six fewer published names

- **Status:** accepted
- **Date:** 2026-09-11
- **Ticket:** #1266 (extraction #8, pass 5 — plan)
- **Pass:** 5 of 9 (`docs/agents/refactor-loop.md`)
- **Grills:** ADR-0304 dec. 4
- **Constrains:** ADR-0111, ADR-0126, ADR-0148, ADR-0159, ADR-0183, ADR-0211, ADR-0212, ADR-0257, ADR-0262, ADR-0303, ADR-0304

Pass 4 named a surface. Pass 5 found that it named it in the **wrong form**, that the
move's bill is an order of magnitude larger than any prior pass recorded, and that
**one ordering choice changes the addon's permanent public API by 35%.**

---

## §1 — ADR-0304 dec. 4 is wrong in form, and the destination already said so

ADR-0304 dec. 4 reads: *"The addon publishes 17 `class_name`s and no `[autoload]`
names."* The count is defensible. The **form** is not.

**ADR-0212 dec. 1**, quoted verbatim:

> Every addon declares exactly one global `class_name`; it is `ExMateriaX`; and it
> lives in `addons/exmateria_x/exmateria_x.gd`. Not a count, not merely a prefix.

Measured, not assumed — `class_name` declarations per addon root:

| addon | declarations |
|---|---:|
| almanac, battlefield, catalogue, effects, platform, render, schema, sprite_rig | **1 each** |

**8 of 8.** A published member is a `const` row on that one façade
(`ExMateriaEffects.EffectData`), and a consumer may alias it back to a bare local
name (ADR-0211 dec. 4), which is what leaves existing use sites spelled as they were.

So "publishes 17 `class_name`s" describes a thing the corpus does not build. The
addon publishes **one** global — `ExMateriaUI` in
`addons/exmateria_ui/exmateria_ui.gd` — carrying **17 const rows**.

This matters beyond wording. ADR-0304 said the other 63 names *"are internal and stay
internal."* They cannot stay: a `class_name` is engine-global, so every one an addon
declares lands in the consumer's project. They must be **de-declared**, which is
work — not the zero that "stays internal" implies.

> **Decision 1.** The addon declares one `class_name ExMateriaUI`. **62 of the 79
> member declarations are removed**, not merely unpublished. ADR-0304 dec. 4's count
> stands; its form is superseded.

This is extraction #4's pass-4 lesson — *the design was never checked against the
conventions the destination already enforces* — recurring at pass 4 of extraction #8.
ADR-0304 cites ADR-0212 nowhere. It should have.

### 1.1 79 is the largest collapse the corpus has attempted

`exmateria_effects` declared 42 on the day it moved; `exmateria_battlefield` was
seeded at 30. UI declares **79**. There is a shipped guard —
`check_addon_portability.py` arm_rot fails when `class_name {FACADE}` is absent from
the folder-named file — so pass 6 stays red until the façade file exists.

---

## §2 — The façade is 17, derived three times and corrected twice

A member is published when something **outside** the addon that is **not** a test or
tool names it. Instrument: every `.gd`/`.tscn`/`.gdshader`/`.gdshaderinc`/`.tres`
outside `addons/`, string literals blanked, `#` **and `//`** comments stripped.

Two corrections the first reading needed, both found by refusing a suspicious zero:

- **`//` comments are not `#` comments.** `UI3ClipEngine` scored as published on a
  single line: `assets/shaders/ui3_owner_color.gdshader:32`, a `//` comment naming it
  in prose. Shaders do not use `#`. Stripping only `#` published a name on the
  strength of a sentence about it.
- **`tests/` is a top-level directory.** The first bucketer tested `f.startswith('./tests')`
  against `rglob` output that yields bare `tests/…`, so **all 1,688 test files were
  booked as production** and the façade read 67. The tell was two zeros that could not
  both be true: `tests` = 0 files and `declined` = 0 names.

A third correction went the other way. `RangeTileAtlas` and `StartActionMenu` are
reached only through a local `const X = preload("res://src/ui3/…")` alias, so I
demoted them to path rewrites. **ADR-0211 dec. 4 overturns that**: a host may alias a
published constant, but *may not* `preload` an addon path — that is a criterion-4 path
row `check_lattice_scene` already scores. Both must be published and aliased back.

| | count |
|---|---:|
| `class_name`s declared by the 125 members | **79** |
| **published** — a non-member production file names it | **17** |
| **declined** — only `tests/`/`tools/` name it | **43** |
| reached by nothing outside the addon | **21** |

17 + 43 + 21 = 79 ✓ (arithmetic control on one instrument).

> **Decision 2.** The published set measured against **today's** tree is **17** rows;
> §3 reduces it to **11** by ordering, and 11 is what gets written. The **43** declined names are not
> published and become declared criterion-4 debt, following extraction #7's precedent
> (it declined 15 on the same argument: a global name lands in a consumer's project
> whether or not that consumer runs our tests). This is a **decision, declared** — not
> a slip. ADR-0211 dec. 5 offers the other route (publish with a `test-only namer`
> label); UI declines it at 43, nearly 3× #7's 15, and because 118 test files are
> already path-coupled through channel A, so this adds no new *category* of debt.

---

## §3 — The ordering finding: the debug inversion is worth six published names

**6 of the 17 published rows exist only because debug tooling reaches in** —
`UI3Element`, `UIChar`, `UIUnitInfoWindow`, `FieldInspectController`, `UI3Beat`,
`DialogueBox`. Their only non-member production namers are under `src/debug/` or
`src/ui3/testing/`.

ADR-0303 dec. 6 already resolved to invert those constructions, and ADR-0304 §1.2 gave
that resolution its basis (nine addons, zero `register_panel` calls). Pass 5's addition
is that **when** it happens is not neutral:

| order | façade rows |
|---|---:|
| move first, invert later | **17** |
| **invert first, then move** | **11** |

A published name is permanent public API. Six of them can be avoided by doing a
host-side edit that is already decided, before the move rather than after.

> **Decision 3.** The debug inversion is a **pre-move** step, not cleanup. The façade
> is written with **11** rows.

---

## §4 — The bill is 181 files, not 15

ADR-0304 counted 118 inbound production lines in 15 files. That is channel B over
`src/` only. The move's actual bill, same instrument as §2:

| channel | size | unit | production | tests | tools |
|---|---|---|---:|---:|---:|
| **A** `res://` path bind | 278 lines / 142 files | per **LINE** — each literal is rewritten | 18 | 118 | 6 |
| **B** bare `class_name` | 83 files | per **FILE** — one alias line, uses below unchanged (ADR-0211 dec. 4) | 13 | 67 | 3 |
| **C** bare autoload identifier | — | **free** — the script moves, the `[autoload]` line stays the host's (ADR-0262 dec. 6) | | | |
| **union — the bill** | **181 files** | | **27** | **148** | **6** |

Plus **63 member files** that name another member's `class_name` and need an internal
alias line once the 62 declarations are removed (§1).

**The anchors are already paid.** Pass 2 wrote 52 vault anchors into 35 files. This is
the one item `docs/agents/refactor-loop.md` says cannot be recovered after the fact —
the note's `R:` path is the only note→file map and `git mv` destroys it (ADR-0111
dec. 7). Extraction #7's pass 5 found this outstanding at 48 notes; #8's was paid at
pass 2, on time.

---

## §5 — The ordered sequence

Green points named. Steps 1–2 are host-side edits that leave the tree green and
**shrink** the move; step 3 cannot be green in the middle and is one commit.

| # | step | files | green after? |
|---|---|---:|---|
| 1 | **Invert the debug panel constructions** (§3). `FormationScene.gd:937/945/955` soft-binds via `get_node_or_null("/root/DebugOverlay")`; `CombatUITestScene.gd:190/196` reaches the bare autoload — different arms (2b vs 2a), possibly different treatment. `CombatUITestScene.gd` is now a **host** file (ADR-0304 dec. 1), so check whether its two calls are in scope at all. | 5 | **yes** |
| 2 | **`Tune` → `TunePort`.** 107 lines / 14 files. Mechanical, zero design residue (ADR-0303 §1.1). | 14 | **yes** |
| 3 | **The move.** `git mv` 125 files; write `exmateria_ui.gd` with 11 rows; remove 62 `class_name` declarations; add alias lines in 63 member files + 13 production + 67 test files; rewrite 278 `res://` lines across 142 files. | 306 | **at the end** |
| 4 | **The stranger rig.** `tests/stranger/exmateria_ui/run.sh`, `known failures declared: 0`. | — | **yes** |

> **Decision 4.** **#1263 is not a blocker.** ADR-0212 dec. 2 rules that *"complete-close
> is a description of scope, never a precondition for a façade"* — `exmateria_sound`
> shipped one with 48 host preloads standing. A façade closes the **symbol** channel;
> whether the path channel is also empty is worth stating and is not a gate. The
> `DisplayPort` gap is platform's work under ADR-0159 dec. 3 and proceeds in parallel.

> **Decision 5.** **#1214 (extraction #7) is mid-flight and four of UI's inbound
> referrers are under `src/debug/`.** Step 1 touches `src/debug/` only if the
> inversion moves panel code there. Pass 6 checks #1214's branch before any
> `src/debug/` edit.

### 5.1 Pass 3's arm predictions, restated against M5 = 125

ADR-0303 §3 predicted against M5 = 128. Three files left. Measured directly:
`CombatUITestScene.gd` carries **5** arm-2a lines; the other two carry zero (positive
control: `FormationScene.gd` scores 11, so the matcher fires). Those 5 leave with a
host file and can no longer appear inside the addon.

| arm | ADR-0303 predicted | restated at M5 = 125 |
|---|---:|---:|
| 2a bare foreign autoload | 178 → 46 | 178 → **41** |
| 2b autoload by node-path | 10 | 10 |
| 7 `class_name` outside an addon root | 34 → 30 | **see §1** — 62 declarations leave `src/` |
| 6 `res://` leaving the addon root | 20 | 20 |

Arm 7's prediction was made before §1 established that 62 declarations are removed
rather than relocated. Pass 6 re-predicts arm 7 before it runs it, and does not read
§1's 62 as a prediction — it is a design decision, not a measurement of the guard.

---

## Decisions

**1. The addon declares one `class_name ExMateriaUI`; 62 of the 79 member declarations are
removed, not merely unpublished.** ADR-0304 dec. 4's count stands; its form is superseded.
Argued in §1.

**2. The façade publishes the derived set — 17 rows against today's tree, 11 after dec. 3.** The
43 declined names are not published and become declared criterion-4 debt, following extraction
#7's precedent. Argued in §2.

**3. The ADR-0303 dec. 6 debug inversion is a pre-move step, not cleanup.** ⚠️ **The stated
reason is WITHDRAWN — see the Correction block.** Sequencing does *not* change the façade
size; the six names are inbound and the inversion moves outbound constructions. The step
survives on ADR-0303 dec. 6's original basis. Superseded in its reasoning by decision 6.

**4. #1263 (the `DisplayPort` gap) is not a blocker.** ADR-0212 dec. 2 rules that complete-close
is never a precondition for a façade; a façade closes the symbol channel. Argued in §5.

**5. Pass 6 checks #1214's branch before any `src/debug/` edit.** Extraction #7 is mid-flight and
four of UI's inbound referrers live there. Argued in §5.

---

## ⚠️ Correction (pass 6, before any code was written on it) — §3 and decision 3 are WITHDRAWN

**The claim.** §3 said 6 of the 17 published rows exist only because debug tooling reaches
in, so sequencing the ADR-0303 dec. 6 inversion *before* the move would publish 11 instead
of 17. Decision 3 made that the plan's headline.

**Why it is wrong.** It conflates two directions across the seam.

- The **inversion** moves *constructions*: `FormationScene.gd:935/943/953`, three
  `HostPanel.new()` + `register_panel` pairs. That is **outbound** — a member naming host
  classes.
- The **6 published names** are **inbound** — host debug panels naming member types in
  their own bodies, nowhere near a construction:

  | name | the line that publishes it |
  |---|---|
  | `UIUnitInfoWindow` | `src/debug/VitalsLayoutDebugPanel.gd:20` — `var _window: UIUnitInfoWindow` |
  | `FieldInspectController` | `src/debug/VitalsLayoutDebugPanel.gd:21` — `var _field_inspect: FieldInspectController` |
  | `UI3Element` | `src/debug/UI3OwnerColorMap.gd:58` — `for root: UI3Element in registry.roots()` |
  | `UIChar` | `src/debug/FontDebugPanel.gd:18` — `UIChar.FontPalette.MENU` |
  | `UI3Beat` | `src/debug/UI3RegistryView.gd:1099` — `var beat: UI3Beat = registry.beat_for(kind)` |
  | `DialogueBox` | `src/ui3/testing/CombatUITestScene.gd:15` — `@onready var _dialogue_box: DialogueBox` |

  Not one is a panel construction. Moving the three `.new()` lines out of `FormationScene`
  changes none of them.

**The façade is 17 rows whichever order is used.** Decision 2's derivation stands; decision
3's *lever* does not exist. Shrinking the façade would require the panels themselves to stop
naming member types — a different and much larger job, not an ordering choice.

**The inversion is still a pre-move step**, on ADR-0303 dec. 6's original basis and
ADR-0304 §1.2's invariant: a member must not construct host panels or name
`/root/DebugOverlay`, and that debt must be zero before the addon ships. It buys arm-1/2b
cleanliness, not API size.

### What pass 6 measured that pass 5 did not

The inversion's call topology is larger than "5 files":

1. **`FormationMapHost extends FormationScene`** (`FormationMapHost.gd:2`), so
   `_setup_debug_panels()` runs from `_ready()` for the subclass too.
2. **Four boot paths produce a live instance** — `Formation.tscn` via
   `NavigatorMain.gd:921`; `AllTemplatesFormationBoot.gd:19` via `.new()`;
   `FormationDevBoot.gd:54` via `FormationDetailTransition`; and `GambitBattle`'s map host.
   Removing `_setup_debug_panels()` and wiring only the first **silently deletes the panels
   from the other three** — a green run that stopped looking.
3. **`DebugOverlay` has no discovery hook.** No group, no `node_added`, no
   `get_nodes_in_group` anywhere in `DebugOverlay.gd` or `DebugDashboard.gd`. So the
   inversion must be call-site-driven, per `MapDebugPanels` (#555), and every site must be
   named.
4. **`register_panel` appends without de-duplicating** (`DebugOverlay.gd:238`). That is why
   `MapDebugPanels.register_map_panels` opens by scanning `DebugOverlay._panels` for an
   existing `SkirtDebugPanel`/`MapRenderDebugPanel`. **The formation installer owes its own
   rebind guard**, or a scene reload double-registers three panels.

> **Decision 6 (correcting decision 3).** The façade is written with **17** rows. The
> inversion stays a pre-move step on its original justification, and its call topology —
> four boot sites, one subclass, one rebind guard — is named here rather than discovered
> during the move.

---

## §6 — What this pass does not settle

- Where the 21 unreached and 43 declined names sit inside the addon tree. The §4
  layout in ADR-0304 remains provisional; pass 6 fixes it at the move.
- The exact alias text in 148 test files — mechanical, and pass 6's to write.
- `deps=`, `engine=`, `tier=` for `plugin.cfg` — measured at pass 6, per sprite_rig's
  precedent of measuring rather than assuming each.

**6. The façade is written with 17 rows, not 11**, and the inversion's call topology is four
boot sites, one subclass and one rebind guard. Corrects decision 3. Argued in the Correction
block.
