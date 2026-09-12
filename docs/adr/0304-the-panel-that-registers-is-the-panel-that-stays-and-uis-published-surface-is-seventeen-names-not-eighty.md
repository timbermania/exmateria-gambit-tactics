# ADR-0304 — The panel that REGISTERS is the panel that stays, and UI's published surface is 17 names, not 80

- **Status:** accepted
- **Date:** 2026-09-11
- **Ticket:** #1265 (extraction #8, pass 4 — grill + name)
- **Pass:** 4 of 9 (`docs/agents/refactor-loop.md`)
- **Grills:** ADR-0303 (extraction #8 pass 3)
- **Constrains:** ADR-0126, ADR-0131, ADR-0148, ADR-0183, ADR-0223, ADR-0257, ADR-0262, ADR-0303

Pass 3 designed the seam. Pass 4's job is to attack that design, settle the one
conflict pass 3 left open, and give the addon a name and a published surface.
Three of pass 3's numbers moved. One of its headline claims was measured on the
wrong axis and is corrected here.

---

## §1 — The conflict pass 3 left open is settled by a discriminator, not by a directory

ADR-0303 §2 dec. 7 recorded a conflict it could not resolve.
`src/ui3/testing/CombatUIDebugPanel.gd` `extends BaseDebugPanel`, which makes it
a debug panel under ADR-0257 and therefore **not** a member — but it lives under
`src/ui3/`, which pass 2 ruled wholly in. Directory says in, base class says out.

### 1.1 I formed the wrong hypothesis first, and the code refuted it

My first reading was that this panel is the addon's *own* harness — the shape
`addons/exmateria_sprite_rig/install/RigDebug.gd` ships — and therefore travels
with the addon even though ADR-0257 drops the other eight. That hypothesis is
**false**, and the line that kills it is `src/ui3/testing/CombatUITestScene.gd:190`:

```gdscript
var panel = preload("res://src/ui3/testing/CombatUIDebugPanel.gd").new()
DebugOverlay.register_panel(panel, DebugOverlay.Category.DESIGNER)
```

It mounts on the host's global overlay. That is the same shape
`src/ui3/formation/FormationScene.gd:937` uses for the three panels ADR-0257
already dropped. A panel that registers on `/root/DebugOverlay` is a host panel
regardless of which directory holds its file.

### 1.2 The discriminator is `register_panel`, and it is an observed invariant

The rule that separates diagnostics an addon MAY ship from panels it may NOT is
not the filename, not the directory, and not the base class. It is whether the
file calls `DebugOverlay.register_panel`.

Measured across the whole tree:

| file | base class | calls `register_panel` | ships in an addon |
|---|---|---|---|
| `addons/exmateria_sprite_rig/install/RigDebug.gd` | `RefCounted` | no | **yes** |
| `addons/exmateria_catalogue/inspection/RosterDebugView.gd` | `RefCounted` | no | **yes** |
| `src/debug/FormationDebugPanel.gd` | `BaseDebugPanel` | via host | no |
| `src/debug/DetailScreenDebugPanel.gd` | `BaseDebugPanel` | via host | no |
| `src/debug/VitalsLayoutDebugPanel.gd` | `BaseDebugPanel` | via host | no |
| `src/debug/UIDisplayDebugPanel.gd` | `BaseDebugPanel` | via host | no |
| `src/ui3/testing/CombatUIDebugPanel.gd` | `BaseDebugPanel` | via host | **no — this ADR** |

**Positive control.** `grep -rln register_panel --include=*.gd src/ addons/`
returns 23 files and **not one of them is under `addons/`**. Across nine shipped
addons, zero register a panel. This is not a rule pass 4 is inventing; it is an
invariant every prior extraction already obeyed, stated for the first time.

The two addon-side diagnostics both `extends RefCounted` and read their state
through a port — `RigDebug.gd` reads "through the PLATFORM PORT instead of the
host's `Debug` system (#744)". So the addon is not barred from diagnostics. It is
barred from *mounting* them on a host autoload it cannot depend on (ADR-0262
dec. 6: an addon cannot ship `project.godot` entries, and `DebugOverlay` is one).

### 1.3 The same discriminator empties the rest of `src/ui3/testing/`

`src/ui3/testing/` holds exactly three scripts, and all three resolve host-side:

| file | why it stays in the host |
|---|---|
| `CombatUIDebugPanel.gd` | registers on `DebugOverlay` (§1.2) |
| `CombatUITestScene.gd` | a dev harness scene that *does* the registering, twice, and constructs the host's `UIDisplayDebugPanel` |
| `UICompileTest.gd` | `extends SceneTree`; a headless test, run via `godot --headless --script` |

**Test-placement precedent, measured.** Tests inside addon roots: battlefield 16,
schema 3, platform 1 — but effects **0**, sprite_rig **0**, almanac **0**,
catalogue **0**, render **0**. The most recent extraction (#7, Effects, 234
files) carried **zero** tests, and its viewer scene `src/scenes/EffectViewerScene.gd`
— which also calls `register_panel` — stayed host-side. UI follows the recent
precedent, not the old one.

> **Decision 1.** M5 is **125**, not 128. The three files in `src/ui3/testing/`
> stay in the host. Pass 2 ruled `src/ui3/` in *by directory*; that was the right
> default and this is the exception the grill pass exists to find.

> **Decision 2.** The member/non-member discriminator for debug is
> **`DebugOverlay.register_panel`**, not `extends BaseDebugPanel` and not the
> directory. This refines ADR-0257, whose stated base-class rule pass 1 already
> found falsified on 4 of its own 8 panels. An addon MAY ship diagnostics; it may
> NOT ship a panel that mounts on a host autoload.

---

## §2 — Pass 3's headline was measured on the wrong axis

ADR-0303 §1.5 states:

> "More than half of UI's public surface is sized by tooling that ADR-0257 says is
> not part of the system, while the system reaches back out to construct it."

The 56% behind that sentence is a count of inbound **lines**. "Public surface" is
not line-shaped — it is **name**-shaped. An addon's surface is the set of
`class_name`s a consumer must know, and one consumer file naming one class on 26
lines is one name, not 26 units of surface.

Both axes, re-measured on M5 = 125 so the two figures compare:

| axis | debug/testing share | total |
|---|---|---|
| inbound production **lines** | 71 (**60%**) | 118 lines in 15 files |
| published **names** | 5 (**29%**) | 17 façade names |

The line figure is real and got *larger* under the corrected membership (56% →
60%). The conclusion drawn from it does not follow: debug tooling supplies 60% of
the traffic across the seam but only 29% of its surface. Two files —
`src/debug/UI3RegistryView.gd` (26 lines) and `src/debug/FontDebugPanel.gd` (24)
— are half the debug traffic by themselves, and between them they name four
classes.

> **Decision 3.** ADR-0303 §1.5's inference is **withdrawn**. The measurement
> stands (60% of inbound lines); the claim about *surface* does not. Surface is
> counted in names.

This does not weaken ADR-0303 dec. 6 (invert the four panel constructions) — §1.2
gives that decision a principled basis it did not have. Pass 3 argued for the
inversion from a share-of-traffic figure, which is the weak form. The strong form
is the invariant: nine addons, zero `register_panel` calls.

---

## §3 — The published surface is 17 names

UI declares **80** `class_name`s. That is a declaration count, not an interface.

Measured: production `.gd` files outside M5 that use an M5 `class_name` as a bare
type (string literals blanked, trailing comments stripped, so an English word in
a string cannot score — the defect that cost ADR-0303 §1.3 its first reading):

| name | referrers | | name | referrers |
|---|---|---|---|---|
| `UIUnitInfoWindow` | 3 | | `FormationMapHost` | 2 |
| `FeedbackHudManager` | 3 | | `UIFont` | 2 |
| `UICombatManager` | 3 | | `UIChar` | 1 🔧 |
| `UI3Element` | 2 🔧 | | `UI3Beat` | 1 🔧 |
| `FieldInspectController` | 2 🔧 | | `StartActionMenu` | 1 |
| `TurnMarker3D` | 2 | | `RangeTileAtlas` | 1 |
| `TurnQueueHud` | 2 | | `DialogueBox` | 1 🔧 |
| `PauseScreen` | 2 | | `GloveCursorBob` | 1 |
| `StopBadge` | 2 | | | |

🔧 = named only by debug/testing files (5 of 17).

**63 of the 80 declared names are named by nothing outside the addon.** They are
internal and stay internal. For scale: extraction #7 published 21 names for 234
files; UI publishes **17 for 125**.

The façade grew by one against pass 3's count (16 → 17) purely as a consequence of
decision 1: `DialogueBox` is named only by `CombatUITestScene.gd`, which moved from
member to host. Moving files *out* of a membership can only grow a façade, never
shrink it — worth stating because it is the direction that surprises.

> **Decision 4.** The addon publishes **17** `class_name`s and no `[autoload]`
> names (ADR-0183 dec. 1). The other 63 declarations are internal.

### 3.1 A third obligation pass 3 did not count

20 M5 files are referenced by `res://` path from **7 host scenes** —
`CombatUI.tscn` 12, `CombatUITest.tscn` 3, and one each from
`AllTemplatesFormation.tscn`, `DetailScreen.tscn`, `Formation.tscn`,
`FormationDetailTransition.tscn`, `FormationDev.tscn`. These are
`ext_resource path=` + `uid=` entries. They are **not** façade names — exactly one
bare type use exists in any `.tscn` in the tree (`DialogueBox`) — but every one is
a path rewrite the move must perform. The move's work is therefore three lists,
not one: 17 names to keep stable, 20 scene paths to rewrite, 63 names free to move.

---

## §4 — Name and layout

The addon is **`exmateria_ui`** at `addons/exmateria_ui/`. This is not a free
choice: `tests/stranger/` already holds a directory per shipped addon and the
extraction's measure of done is `tests/stranger/exmateria_ui/run.sh` green.

Layout follows extraction #7, the most recent precedent — subsystem directories at
the addon root, `plugin.cfg`, `plugin.gd`, `README.md`:

```
addons/exmateria_ui/
  plugin.cfg          name / description / engine= / deps= / tier= (all MEASURED, per sprite_rig's precedent)
  plugin.gd
  README.md
  ui3/                the element/beat kernel
  elements/           UIFont, UIChar, UIButton, ...
  formation/          FormationScene and friends
  combat/             UICombatManager, TurnQueueHud, StopBadge, ...
  screens/            PauseScreen, StartActionMenu, DialogueBox, ...
  shaders/            ui_font_char.gdshader and the rest
```

`deps=` and `engine=` are **measurements pass 6 takes**, not guesses pass 4
records. Pass 3 already measured the `TunePort` half (107/107 lines, one port);
`DisplayPort` is two verbs short and that gap is ticket #1263.

> **Decision 5.** Directory subdivision above is provisional and owned by pass 5
> (plan). Pass 4 fixes the addon's *name*, its *published surface* (17), and its
> *membership* (125). It does not fix the internal tree.

---

## Decisions

**1. M5 is 125, not 128; the three files in `src/ui3/testing/` stay host-side.** Argued in §1.3.

**2. The member/non-member discriminator for debug is `DebugOverlay.register_panel`**, not
`extends BaseDebugPanel` and not the directory. An addon MAY ship diagnostics; it may NOT ship a
panel that mounts on a host autoload. Argued in §1.2; refines ADR-0257.

**3. ADR-0303 §1.5's "more than half the public surface is debug tooling" is withdrawn** as an
inference. The measurement stands (60% of inbound lines); surface is name-shaped and the name
figure is 29%. Argued in §2.

**4. The addon publishes 17 names and no `[autoload]` names** (ADR-0183 dec. 1); the other 63
declarations are not published. Argued in §3. ⚠️ **Superseded in form by ADR-0305 dec. 1** — the
corpus publishes one folder-named façade (ADR-0212 dec. 1), so the 63 are *removed*, not
"kept internal", and the count is carried as const rows rather than `class_name`s.

**5. Directory subdivision inside the addon is provisional and owned by pass 5.** Pass 4 fixes the
addon's name, its published surface and its membership only. Argued in §4.

---

## §5 — What this pass does not settle

- The `DisplayPort` gap (#1263) — `live_ui_par` / `live_ui_par_changed` are not
  published. ADR-0159 dec. 3 makes that **platform's** work, not UI's.
- The node-name string contract (#1264) — invisible to every portability arm.
- `deps=`, `engine=`, `tier=` for `plugin.cfg` — measured at pass 6.
- Where the 63 internal names land inside the addon tree — pass 5.
