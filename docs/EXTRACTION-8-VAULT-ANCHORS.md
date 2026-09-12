# Extraction #8 (UI) — pass 2: scope and vault anchors

> **Superseded in part by ADR-0304 dec. 1 (pass 4):** membership M5 is **125**, not 128 —
> the three files in `src/ui3/testing/` stay host-side. The rest of this document stands as
> pass 2's reading; it is not rewritten (ADR-0148).

Pass 2 of the nine-pass refactor loop (`docs/agents/refactor-loop.md`). It does two
things and only two: it **anchors the vault notes into the code** so the note→code edge
survives the move (ADR-0111 dec. 7), and it **settles membership** — the one scope
question ADR-0302 (pass 1) deliberately left open.

It designs nothing and predicts nothing. Pass 3 owes the numeric prediction.

Coverage below is **reported, never asserted**. `tools/check_vault_anchors.py` enforces
that every `Vault: [[X]]` names a real note and that `Vault:` appears in no other form.
It does not enforce a coverage floor, and this document does not add one.

---

## 1. Membership: M4 = 140 → **M5 = 128**

ADR-0302 dec. 2 set membership at **M4 = 140** files (the `classify()` UI bucket of 154,
minus 6 `exmateria_almanac` files, minus 8 debug panels / registry views). This pass
reproduced that 140 exactly as a control on the reconstruction, then made four changes.

| # | change | files | running |
|---|--------|------:|--------:|
| — | M4 (ADR-0302 dec. 2) | | 140 |
| 1 | **drop `src/world_map/`** | −13 | 127 |
| 2 | **drop the `ui3_owner` cluster** | −4 | 123 |
| 3 | **drop `src/scenes/OpeningMenu.gd`** | −1 | 122 |
| 4 | **add the six scenes / `*Boot.gd` roots** | +6 | **128** |

M5 is then exactly **all 118 files under `src/ui3/`** plus **10 `assets/shaders/*.gdshader`**.
The extraction boundary is a directory boundary plus ten shaders. Nothing else remains.

### 1.1 `src/world_map/` is not a member

ADR-0302 dec. 8 recorded that `src/world_map/` carries all of UI's Campaign + Cutscene
debt, and kept it in because dropping it is a *scope* decision. Measured here:

* **Outbound.** The whole directory names **four** non-`WorldMap*` `class_name`s in code:
  `UIFont` (×2), `GloveCursorBob` (×1), `CampaignRevealPass` (×1), `WorldMapDebugPanel` (×1).
  Its reach into UI is **three lines naming two symbols.**
* **`res://` reach into `src/ui3/` is zero.** Positive control: the same scan finds 12
  `res://src/ui3/shaders/vitals_sprite.gdshader`, 8 `menu_cursor_shadow.gdshader`, etc.
  inside `src/ui3/` itself, so the instrument is not blind — the zero is real.
* **Inbound.** Production consumers are `src/scenarios/Campaign.gd` (14),
  `src/scenarios/NavigatorMain.gd` (9), `src/scenarios/ScenarioVM.gd` (5),
  `src/scenarios/CampaignRevealPass.gd` (4) — **32 Cutscene/Campaign lines** against
  `src/ui3/formation/FormationScreenIn.gd`'s **6**.

World map is consumed by Campaign at 5× the rate UI consumes it. It is a neighbouring
system, not a member. Dropping it also takes the `WorldMap.tscn` → `WorldMapScene.gd`
`ROOT_SET.tsv` row out of the extraction — UI keeps 5 root rows, not 6.

### 1.2 The `ui3_owner` cluster follows the panels out

`src/debug/UI3OwnerColorMap.gd`, `UI3OwnerColors.gd`, `UI3OwnerMapPicker.gd` and
`assets/shaders/ui3_owner_color.gdshader` form a **closed four-file cluster**: they
reference each other, and their only external consumer is `src/debug/UI3RegistryView.gd`
— itself one of the 8 files ADR-0302 dec. 2 already dropped under ADR-0257.

`UI3OwnerColorMap.gd` does name two UI3 symbols (`UI3ClipEngine`, `UI3Element`). That
makes it a **consumer** of UI, which is the reason it is not a member.

### 1.3 `src/scenes/OpeningMenu.gd` is a classifier false positive

It names **zero** UI3 `class_name`s in code. Positive control on the same scan:
`FormationScene.gd` names 15, `DetailScene.gd` names 18. It draws through
`opntex_glyph.gdshader`, not a UI3 shader. Its docstring *cites* `vitals_sprite.gdshader`
and `[UIUnitInfoWindow]` in prose — `classify()` booked it to UI on the resemblance.
Seven production files outside UI consume it (`NavigatorMain.gd`, `BattlefieldWiring.gd`,
`GPUArena.gd`, `EffectViewerScene.gd`, `FireCastReproScene.gd`,
`addons/exmateria_battlefield/cursor/TileCursor.gd`, `assets/scenes/OpeningScene.tscn`).
Shipping it would have made all seven inbound arm-7 lines against the addon.

### 1.4 `classify()` is blind to scenes and to scriptless roots

Six files under `src/ui3/` were absent from the 154-file bucket entirely:

    src/ui3/assemblies/DialogueBox.tscn
    src/ui3/detail/StartActionMenu.tscn
    src/ui3/detail/DetailSceneBoot.gd
    src/ui3/detail/StartActionMenuBoot.gd
    src/ui3/formation/AllTemplatesFormationBoot.gd
    src/ui3/formation/FormationDevBoot.gd

Every one is either a `.tscn` or a `*Boot.gd`. `classify()` books a file by its
`class_name`; a `.tscn` has none and a `*Boot.gd` is a bare `extends Node3D` harness.
Three of the six are named directly by `ROOT_SET.tsv` rows, so the root set was pointing
at files the membership figure did not contain. This is ADR-0302 S5 confirmed by
enumeration: **a walk that follows only scripts cannot see a screen's own root.**

---

## 2. Anchors: UI **1 → 53**

`tools/check_vault_anchors.py`, before and after, green both times:

| system | before | after |
|--------|-------:|------:|
| Effects | 137 | 137 |
| **UI** | **1** | **53** |
| Sprite Rig | 40 | 40 |
| Battlefield | 34 | 34 |
| Audio | 7 | 7 |
| platform | 5 | 5 |
| Render | 1 | 1 |
| **walked total** | 225 in 93 files / 77 notes | **277 in 128 files / 97 notes** |

**52 anchors written into 35 files, covering 24 notes.** The pre-existing anchor is
`src/ui3/GloveCursorBob.gd:27` → `[[Start Action Menu]]`. Four of the 52 land in
`src/world_map/` files, which §1.1 just ruled non-members; they are correct anchors and
they stay, and they are marked `NON-MEMBER` in the edges TSV so the move pass skips them.

`docs/EXTRACTION-8-VAULT-EDGES.tsv` carries all 52 rows as `note / src / dst`. The `dst`
column is `-`: the addon layout does not exist until pass 5, and extraction #7's edge
file was likewise written with the move manifest (#1216), not at pass 2.

### 2.1 Four mechanisms by which the `R:`-citation scan misses UI notes

Every prior extraction found its notes by scanning vault `R:` citation lines. On UI that
method reaches 18 notes. Six more are UI-topical with unambiguous implementations, and
each is missed for a **different structural reason** — this is the finding, not the six:

| # | mechanism | example | recovered target |
|---|-----------|---------|------------------|
| a | `R: none` on every point though the code exists | `[[Change Job Screen]]` | `src/ui3/changejob/ChangeJobScreen.gd`, `ChangeJobWheel.gd` (the ellipse, rX 100 / rY 60, at `ChangeJobWheel.gd:98`) |
| b | index notes carry no `R:` lines at all | `[[Formation Screen Index]]`, `[[World Map Index]]` | none — index notes name a domain, not code |
| c | `R:` cites a real file booked to **another** system | `[[Concurrent Dialogue Boxes]]`, `[[Dialogue Box SFX]]`, `[[Prayer Screen Tint]]` → `src/scenarios/*`, `src/audio/SfxRouter.gd` | left with Cutscene/Audio — the seam is real and correctly attributed |
| d | `R:` cites a **dead** path while the anchor rode the move | `[[Start Action Menu]]` → `src/scenes/CursorBob.gd`, dead since extraction #3 pass 4 | `src/ui3/detail/StartActionMenu.gd` |

Mechanism (d) is ADR-0111 dec. 7 demonstrated a second time from the other side: the
`R:` path citation died in the move and the `## Vault:` comment survived it.

The six recovered by hand, with the evidence that fixed each target:

* `[[Change Job Screen]]` → `ChangeJobScreen.gd`, `ChangeJobWheel.gd`
* `[[Gold Selection Box]]` → `formation_box.gdshader:2` (*"FORMATION-screen gold selection box — ADDITIVE pass"*), `formation_box_sub.gdshader`
* `[[Unit Pager Buttons]]` → `RangeTileAtlas.gd:69` (`_detail_pager`, §15.22), `DetailScene.gd:93` (`RP_PAGER_FRAME`)
* `[[Equip Sub Screen]]` → `EquipPickerMenu.gd`, `SpriteSlideAnimator.gd` (*"the Formation Item → Equip unit sprite-slide"*)
* `[[Equip Stat Delta Preview]]` → `EquipDeltaPalette.gd` (*"the equip stat-DELTA colour CLUTs"*)
* `[[Start Action Menu]]` → `StartActionMenu.gd`

---

## 3. The closure walk from the root set

Walked from the 5 UI rows of `ROOT_SET.tsv` — through `.tscn` **and** `.gd`, resolving
both `res://` paths and `class_name` references, per ADR-0302 S5.

A raw **transitive** closure reaches 325 files and is not a useful instrument: the
formation screen mounts real units, which pull the whole unit → sprite → effects stack.
The **direct** escape set — non-member files named by a member — is the addon's debt.

**29 direct escapes.** Five of them are not debt at all:

| addon facade | member files naming it |
|--------------|----------------------:|
| `ExMateriaAlmanac` | 17 |
| `ExMateriaSchema` | 15 |
| `ExMateriaCatalogue` | 2 |
| `ExMateriaBattlefield` | 2 |
| `ExMateriaSpriteRig` | 1 |

UI reaches the five already-extracted systems **only through their declared facades** —
there is not one direct reach into an addon's internals. That is the shape a new addon
is supposed to depend on, and it is already true before any work.

That leaves **24 host escapes**:

| dir | n | widest |
|-----|--:|--------|
| `src/gpu` | 6 | `TurnDirector.gd`, `CombatLoop.gd`, `GambitEncoder.gd`, `ImperativeGambits.gd`, `AdjustmentTurn.gd`, `GPUConstants.gd` |
| `src/debug` | 5 | `BaseDebugPanel.gd` + the 4 panels a member still names |
| `src/units` | 5 | **`Unit.gd` (5 member referrers)**, `UnitStatusManager.gd` (3), `UnitSpawn.gd` (2), `UnitAssets.gd`, `UnitStats.gd` |
| `src/scenarios` | 3 | `TypewriterController.gd`, `EntdBattle.gd`, `GarilandMutationScript.gd` |
| `src/core` | 1 | `ScreenOverlayQuad.gd` |
| `assets/shaders` | 1 | `screen_color_mode2.gdshader` |

### 3.1 Autoloads, which no file-ref walk can see

A closure walk follows file references; an autoload is a project setting. Members name
eight of them:

| autoload | member files | resolves to |
|----------|-------------:|-------------|
| **`Tune`** | **14** | `src/core/Tune.gd` |
| `PSXDisplay` | 7 | `addons/exmateria_platform/display_port/PSXDisplay.gd` |
| `DebugConfig` | 5 | `src/debug/DebugConfig.gd` |
| `CharacterCatalog` | 4 | `addons/exmateria_catalogue/registry/CharacterCatalog.gd` |
| `UI3Registry` | 3 | `src/ui3/UI3Registry.gd` |
| `EventBus` | 2 | `src/core/EventBus.gd` |
| `SfxRouter` | 2 | `src/audio/SfxRouter.gd` |
| `DebugOverlay` | 2 | `src/debug/DebugOverlay.gd` |

This confirms ADR-0302 dec. 7 by a second instrument: **the autoload question is `Tune`**,
named by 14 members, not `UI3Registry` at 3. `PSXDisplay` and `CharacterCatalog` already
live in addons and are ADR-0262 dec. 6's problem in their own right; `Tune`, `DebugConfig`,
`EventBus`, `SfxRouter` and `DebugOverlay` are host autoloads an addon cannot ship.

---

## 4. Instrument defects found and fixed in this pass

Recorded because each one produced a wrong number that looked right:

1. **The `res://` extractor's alternation order.** `res://…\.(?:gd|tscn|gdshader)` matches
   `gd` first, so every `.gdshader` truncated to a non-existent `.gd` path and was counted
   as an escape. It reported **59** escapes; the corrected pattern
   (`gdshaderinc|gdshader|tscn|gd`) reports **29**. 30 of the 59 were phantoms — real
   member shaders wearing a `.gd` extension.
2. **The vault-citation scan dropped `::method` suffixes**, so `DialogueBox.gd::_paginate`
   read as a dead path and lost its note→file edge.
3. **`classify()` is blind to `.tscn` and to scriptless `*Boot.gd`** — §1.4.

Per ADR-0148 no instrument was repaired mid-reading: each fix was followed by a full
re-run, and each re-run carries the positive control quoted beside its number above.

---

## 5. What pass 2 does not settle

* **No numeric prediction.** Pass 3 owes it. M5 = 128 is a membership figure, not a
  forecast of the arm-7 reading.
* **The 24 host escapes are enumerated, not dispositioned.** Which become addon-public,
  which get inverted, which follow UI out — pass 3/4.
* **`Tune`.** 14 members name a host autoload. ADR-0262 dec. 6 says an addon cannot ship
  a `project.godot` entry. Unresolved by design.
* **The `dst` column of the edges TSV** is filled at the move, not here.
