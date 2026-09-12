# Extraction #4 — `Sprite Rig`'s vault anchors

Loop **pass 2** deliverable 1 of extraction #4
([#310](https://github.com/timbermania/fft-monorepo/issues/310) — *"the one step
that cannot be deferred"*). Form set by ADR-0147 dec. 6, enforced by
`tools/check_vault_anchors.py`. Written at trunk **`571e4e3bd`**, 2026-08-31,
committed as `6fb4f0ad8`.

**Coverage is reported, never asserted** — adoption is per-extraction.

| | |
|---|---:|
| vault notes on `main` | 230 |
| notes whose `R:` citations reach a `Sprite Rig` file | **19** |
| notes added by the second seed (below) | **1** |
| **anchors written** | **40** |
| `Sprite Rig` files carrying an anchor | **14 of 29** (48.3%) |
| `check_vault_anchors.py` | green, exit 0 |

Before this pass the system carried **zero** anchors. The guard now reads
`Sprite Rig 40` at the head of the `WALK_ROOTS` table, ahead of `Battlefield 31`.

The commit is **comment-only** — 40 insertions, 0 deletions, 14 files, no line
of executable text touched. It is also the whole of the difference between
ADR-0213's census line count (**5,343**) and today's (**5,383**): 40 anchors,
40 lines. Any later reading of `Sprite Rig`'s size should subtract them before
comparing against pass 1.

## The seed, and the three traps

The seed is the vault's `R:` line — the reimplementation citation, which is the
half ADR-0111 dec. 7 says rots. Every `R:` line in every note on `main` was
scanned for a path or basename resolving to one of the 29 files
`classify_blueprint.py` books `Sprite Rig`. The rule is ADR-0147's, unchanged:

> **A note is anchored where its `R:` points, not where its subject belongs.**

Both traps extraction #1 paid for, and extraction #3 re-paid, bite again:

1. **A citation can be a bare basename.** `R: SpriteLayerManager.gd` with no
   directory is a real spelling in this vault and a path-only match drops it.
   Basenames are matched as well as paths.
2. **The suffix alternation must be longest-first.** `gd` written before
   `gdshader` in the regex makes `unit.gdshader` match as `unit.gd`, a file that
   does not exist, and the note reads as unanchored. The order is
   `gdshaderinc|gdshader|glslinc|glsl|tscn|tres|gd`.

And a **third**, found here:

3. **An `R: none` line can still NAME a file.** Four notes on `main` write their
   `R:` as an absence claim that goes on to name the file the absence is *about*
   — *"R: none — the frame table is read by `SpriteLayerManager.gd` but the
   opcode itself is not implemented"*. A scanner that reads the whole `R:` line
   for basenames books that as a live citation. It is the opposite of one: the
   note is saying the reimplementation does not exist.

   Of the four, exactly **one** pair was reachable by that route alone —
   `[[EVTCHR Script VM]]` → `src/animation/SpriteLayerManager.gd`. It is
   **excluded**. The other three already had a real citation elsewhere in the
   note and are unaffected.

## The second seed — the code's own `research/` citations

The `R:` scan is one direction: vault → code. The code cites back, and those
citations are **not** a subset. Six lines across four `Sprite Rig` files name a
`research/` document directly, and one of them resolves to a note the `R:` scan
never reached: `[[EVTCHR Frame Resolution]]`, cited from
`src/animation/SpriteLayerManager.gd`.

That pair is anchored, and it is the 20th note. The validation that it is not a
coincidence is `[[EVTCHR CLUT Resolution]]` — a sibling note about the same
format in the same file, which the `R:` seed found *independently*. The two seeds
agree where they overlap and the second one covers a gap the first has.

## The 20 notes, and where each anchor went

| note | anchors | files |
|---|---:|---|
| `[[Unit Sprite Render Pipeline]]` | 6 | `AnimationDatabase` `AnimationOpcodes` `AnimationPlayback` `AnimationStateController` `CinematicPoseLUT` `SpriteLayerManager` |
| `[[Display Space Blend Fold]]` | 4 | `unit.gdshader` `unit_additive.gdshader` `unit_sprite_body.gdshaderinc` `CrystalSprite3D` |
| `[[Unit Anim Opcode]]` | 4 | `AnimationResolutionMap` `AnimationStateController` `CinematicPoseLUT` `UnitDisplay` |
| `[[SEQ Movement Opcodes]]` | 3 | `AnimationOpcodes` `AnimationPlayback` `DistortMovementController` |
| `[[Cinematic Palette Pipeline]]` | 2 | `unit.gdshader` `SpriteLayerManager` |
| `[[EVTCHR CLUT Resolution]]` | 2 | `SpriteLayerManager` `SpritePaletteResolver` |
| `[[Scenario 6 Ride Off]]` | 2 | `AnimationResolutionMap` `UnitDisplay` |
| `[[Sprite Cardinal Pose Selection]]` | 2 | `AnimationResolutionMap` `AnimationStateController` |
| `[[Unit Sprite SEQ Opcodes]]` | 2 | `AnimationOpcodes` `AnimationPlayback` |
| `[[Walk To Opcode]]` | 2 | `AnimationStateController` `UnitDisplay` |
| `[[Weapon Animation System]]` | 2 | `AnimationDatabase` `UnitDisplay` |
| `[[Color Tint Luma Modes]]` | 1 | `unit.gdshader` |
| `[[Color Unit Opcode]]` | 1 | `unit.gdshader` |
| `[[Crystal Status Visual]]` | 1 | `CrystalSprite3D` |
| `[[Damage Number Popup System]]` | 1 | `SpriteLayerManager` |
| `[[EVTCHR Frame Resolution]]` † | 1 | `SpriteLayerManager` |
| `[[Inflict Status Opcode]]` | 1 | `AnimationStateController` |
| `[[Rotate Unit Interpolation]]` | 1 | `AnimationStateController` |
| `[[Scenario Camera Framing]]` | 1 | `unit.gdshader` |
| `[[TRAP Sprite Effect System]]` | 1 | `AnimationPlayback` |

† found by the second seed, not the `R:` scan.

Per file:

| file | anchors |
|---|---:|
| `src/animation/AnimationStateController.gd` | 6 |
| `assets/shaders/unit.gdshader` | 5 |
| `src/animation/SpriteLayerManager.gd` | 5 |
| `src/animation/AnimationPlayback.gd` | 4 |
| `src/animation/UnitDisplay.gd` | 4 |
| `addons/exmateria_sprite_rig/sequence/AnimationOpcodes.gd` | 3 |
| `src/animation/AnimationResolutionMap.gd` | 3 |
| `src/animation/AnimationDatabase.gd` | 2 |
| `src/animation/CinematicPoseLUT.gd` | 2 |
| `src/units/CrystalSprite3D.gd` | 2 |
| `assets/shaders/unit_additive.gdshader` | 1 |
| `assets/shaders/unit_sprite_body.gdshaderinc` | 1 |
| `src/animation/DistortMovementController.gd` | 1 |
| `src/data/SpritePaletteResolver.gd` | 1 |

**Where in the file an anchor goes.** ADR-0147 dec. 6 fixes the *form* and says
nothing about position, so the rule used here is stated rather than assumed: **the
anchor rides the file's own header doc block where there is one, and sits at the
top of the file where there is not.** That puts the two `.gdshader` anchors after
the header `/* … */` and *before* `shader_type` — legal, since only statements are
ordered — and `unit_sprite_body.gdshaderinc`'s at line 1, because that file has no
header block. The extraction-#3 precedent is the same rule with different inputs:
`tile_overlay.gdshaderinc` has a header and its anchors sit at the end of it;
`screen_background.gdshader` has none, so its anchor is at the top, which there
means after `render_mode`. A reader diffing the two extractions will see the
anchors in different-looking places for that reason and not another.

One placement inside a file is worth naming. `AnimationStateController.gd` opens
with two `##` doc blocks; the second is the `LOCKED_TRANSITIONS` table's. The anchors went into
the **first**, because the second documents a constant, and an anchor that rides
a constant's docstring is an anchor that dies when the constant is refactored —
which is exactly the rot ADR-0111 dec. 7 exists to avoid.

## What is not anchored, and why

**15 of the 29 files carry no anchor — 1,050 lines.** That is not a gap to be
filled by authoring; it is what the seed found, and the set was checked from both
ends before being called complete.

| unanchored file | lines |
|---|---:|
| `src/animation/WeaponAnimationSelector.gd` | 179 |
| `assets/shaders/unit_flat.gdshader` | 177 |
| `src/animation/CameraRelativeRenderer.gd` | 111 |
| `src/animation/AnimationFrameCalculator.gd` | 106 |
| `src/effects/CrystalSpriteCompositor.gd` | 88 |
| `src/animation/AnimationClock.gd` | 81 |
| `src/animation/UnitMaterial.gd` | 57 |
| `assets/shaders/crystal_fold.gdshader` | 56 |
| `src/animation/ResourceHotReload.gd` | 47 |
| `src/animation/PlaybackSet.gd` | 34 |
| `src/animation/UnitAnimationSet.gd` | 31 |
| the three `src/animation/resources/` rows — `ActivityRowResource` 17, `AnimationResolutionMapResource` 20, `SpriteTypeResource` 21 | 58 |
| `src/animation/DisplayActivity.gd` | 25 |

Two control arms were run rather than asserted:

- **A wide scan.** The `R:` matcher was re-run with the file filter removed —
  every basename in every `R:` line, matched against the whole repo — and then
  restricted to `Sprite Rig`. It returns the same **20 notes / 40 pairs**. There
  is no note the narrow scan dropped.
- **Subject-scoped candidates.** Fourteen notes whose *subject* is plainly this
  system (sprite, SEQ, SHP, pose, weapon-frame) but whose `R:` points elsewhere
  were checked one at a time. **None** cites a `Sprite Rig` file. Their `R:`
  lines name `fft-iso-patcher/`, `research/`, or a `tools/` extractor — which is
  ADR-0147's rule doing its job: a note about sprite data whose reimplementation
  is a Python extractor anchors in the extractor, not here.

`DisplayActivity.gd` deserves a sentence, because ADR-0213 built a decision on
it. It is 25 generated lines, one `enum Activity`, emitted from
`tools/activity_taxonomy.yaml`. Nothing in the vault cites it and nothing should:
an anchor in a generated file is deleted by the next generation.

## Reproduce

```sh
# from the package root
uv run python tools/check_vault_anchors.py --list     # exit 0; `Sprite Rig 40`
```

The seed scan itself is not a committed tool — it is a ~40-line read over
`git ls-tree -r main vault/` plus `classify_blueprint.walk()`. What it must do
to be correct is the three traps above; what it produced is the table above,
and the table is now the register. The anchors themselves are in the code and
are checked on every preflight, which is the point: **the marker survives the
move, the scan does not have to.**
