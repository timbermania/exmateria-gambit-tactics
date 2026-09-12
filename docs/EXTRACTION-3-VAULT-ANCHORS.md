# Extraction #3 — `Battlefield`'s vault anchors

Loop **pass 2** deliverable 1 of extraction #3
([#500](https://github.com/timbermania/fft-monorepo/issues/500)) — *"the one step
that cannot be deferred"* ([#310](https://github.com/timbermania/fft-monorepo/issues/310)).
Form set by ADR-0147 dec. 6, enforced by `tools/check_vault_anchors.py`. Written
at trunk **`778183181`**, 2026-08-24.

**Coverage is reported, never asserted** — adoption is per-extraction.

| | |
|---|---:|
| vault notes on `main` | 230 |
| notes whose `R:` citations reach a `Battlefield` file | **16** |
| anchors written | **32** |
| `Battlefield` files carrying an anchor | **17 of 49** (34.7%) |
| `check_vault_anchors.py` | green, exit 0 |

Before this pass the system carried **zero** anchors. The guard now reads
`Battlefield 32` alongside `Audio 7`, `Effects 4`, `Render 2` under `WALK_ROOTS`.

> **Amended 2026-08-25 by [ADR-0168](adr/0168-the-manifest-is-the-only-register-that-can-say-the-right-files-moved.md)
> (#565), re-measured at `cd9d6c88f`.** Every number in the table above has moved,
> and **nothing was lost** — the classifier changed under it. Today:
>
> | | pass 2 (`778183181`) | now (`cd9d6c88f`) |
> |---|---:|---:|
> | notes whose `R:` citations reach a `Battlefield` file | 16 | **15** |
> | anchors written | 32 | **31** |
> | `Battlefield` files carrying an anchor | 17 of 49 | **16 of 44** (36.4%) |
> | `src/debug/` files in the system | 7 | **2** |
>
> **The five `src/debug/` files left the system, not the repo.** ADR-0159 dec. 5
> rebooked `CameraFeelDebugPanel` / `CursorDebugPanel` / `MapRenderDebugPanel` /
> `SkirtDebugPanel` / `TilesDebugPanel` to `Debug`; none carried an anchor, so the
> anchor count is untouched by that half. The **one** anchor that moved is
> `[[Start Action Menu]]`: pass 4 (#551) split `CursorBob.gd` and the anchor rode
> into `src/ui3/GloveCursorBob.gd`, now booked `UI`. It travelled across a rename
> *and* a change of owning system with **zero authoring**, which is the property
> ADR-0111 dec. 7 claims for a comment and the empirical basis for ADR-0168 dec. 7.
>
> **The set is still exactly complete and exactly tight**, re-derived rather than
> assumed: the `R:` seed scan over all 230 notes against today's 44-file set finds
> **15 notes / 31 pairs, 0 gaps and 0 extras**, and the wider control scan again
> finds only `[[Unit Shadow Rendering]]`, still correctly excluded. So
> **extraction #3's marker-authoring debt is zero**, and the pass-6 criterion is
> survival rather than authoring — frozen as `docs/EXTRACTION-3-VAULT-EDGES.tsv`
> and enforced by `tools/check_move_manifest.py` arm 4, because
> `check_vault_anchors.py` is green through a note losing its last edge.
>
> The prose below still describes the 49-file set. It is left as pass 2 wrote it;
> where it says *"32 of the 49 files carry no anchor"*, read **28 of 44**.

## The seed, and the two traps

The seed is the vault's `R:` line — the reimplementation citation, which is the
half ADR-0111 dec. 7 says rots. Every `R:` line in every note on `main` was
scanned for a path or basename resolving to one of the 49 files
`classify_blueprint.py` books `Battlefield`. Both traps ADR-0147 paid for once at
extraction #1 were honoured and both still bite:

- **A citation can be a bare basename.** Handled by matching the basename against
  the system's file set as well as the full path.
- **`.gd` swallows `.gdshader` in a naive alternation.** The suffix group is
  ordered longest-first — `gdshaderinc|gdshader|glslinc|glsl|tscn|tres|gd` — so a
  `.gdshaderinc` citation cannot be truncated to a `.gd` one.

A wider scan was run as a control: every citation **anywhere** in a note, not
only on `R:` lines. It found exactly **one** note the `R:` scan missed, and it is
correctly excluded — `[[Unit Shadow Rendering]]` names `tile_overlay.gdshaderinc`
inside a claim *about* `shadow_blob.gdshader`, as the comparison case for a PAR
pattern. Its own `R:` cites `shadow_blob.gdshader`. A note that mentions a file is
not a note that implements it.

## The 16 notes, and where each anchor went

| note | `Battlefield` files anchored |
|---|---|
| `[[Background Opcode]]` | `assets/shaders/screen_background.gdshader` |
| `[[Color Screen Opcode]]` | `src/map/TileOverlayConfig.gd` |
| `[[Color Tint Luma Modes]]` | `assets/shaders/indexed_color.gdshader`, `src/map/MapComposer.gd` |
| `[[Combat Color Appliers]]` | `src/core/MapIlluminationDDA.gd` |
| `[[Display Space Blend Fold]]` | `cursor_fold.gdshaderinc`, `indexed_color.gdshader`, `tile_overlay.gdshaderinc`, `DynamicGeometryBuilder.gd`, `Tile.gd`, `TileCursor.gd` |
| `[[Event Opcode Catalog]]` | `src/map/MapComposer.gd` |
| `[[GTE World-to-Screen Transform]]` | `src/debug/MapGridOverlay.gd` |
| `[[Map Animation Systems]]` | `src/map/MapComposer.gd`, `src/map/MapTextureAnimator.gd` |
| `[[Map Darkness Opcode]]` | `MapComposer.gd`, `MapLightingConfig.gd`, `MapStateSelector.gd` |
| `[[Map State Selection]]` | `src/map/MapComposer.gd`, `src/map/MapStateSelector.gd` |
| `[[Map Tint]]` | `indexed_color.gdshader`, `MapIlluminationDDA.gd`, `DynamicGeometryBuilder.gd` |
| `[[Scenario Camera Framing]]` | `assets/shaders/indexed_color.gdshader`, `src/scenes/PlayerCamera.gd` |
| `[[Start Action Menu]]` | `src/scenes/CursorBob.gd` |
| `[[Terrain Render Pipeline]]` | `src/map/DynamicGeometryBuilder.gd` |
| `[[Tile Overlay]]` | `tile_overlay.gdshaderinc`, `Tile.gd`, `TileOverlayConfig.gd`, `TileCursor.gd` |
| `[[Walk To Opcode]]` | `src/scenarios/EventPathfinder.gd` |

Six of the sixteen are the whole of `[[Map Systems Index]]`'s note list —
`Map Animation Systems`, `Map State Selection`, `Terrain Render Pipeline`,
`Map Tint`, `Map Darkness Opcode`, `Tile Overlay`. The index note itself carries
no `R:` line and is not anchored, matching extraction #1, which anchored no index
note either.

**A note is anchored where its `R:` points, not where its subject belongs.** Ten
of the sixteen are nominally another system's — `Walk To Opcode` and
`Event Opcode Catalog` are `Cutscene`'s, `Start Action Menu` is `UI`'s,
`Combat Color Appliers` is `Effects`'. They are anchored in the `Battlefield`
file each cites because the anchor's job is to survive that file's move.
Extraction #1 set the precedent by anchoring `[[Scenario Camera Framing]]` into
`PSXDisplay.gd`.

## `[[Start Action Menu]]` in `CursorBob.gd` — the flag pass 3 asked for

ADR-0157 dec. 4 holds that `CursorBob` is not `Battlefield`'s, and where it goes
is pass 3's seam decision. Pass 2 anchors it where its vault note points, and the
note that points there is `[[Start Action Menu]]` — a `UI` note, naming the
**glove** half. That is the split showing up in the anchor set exactly as dec. 4
describes it: one `RefCounted`, two step tables, and its only vault note belongs
to the consumer that is not this system. **If pass 3 moves `CursorBob.gd`, this
anchor travels with it and needs no rewrite** — which is the property the anchor
exists for.

## What is not anchored, and why

**32 of the 49 files carry no anchor.** That is not a gap to be filled by
inventing anchors; it is the vault's coverage of this system, reported. The
unanchored set is dominated by the geometry builders and the debug panels —
`SkirtGeometryGenerator.gd` (786 lines), `DoodadLibrary.gd`,
`IndexedAtlasDilator.gd`, `PaletteTextureGenerator.gd`, `VisualGeometryIndex.gd`,
`DynamicTerrainBuilder.gd`, **six of the seven** `src/debug/` files, and **twelve
of the sixteen** shaders. No vault note cites any of them.

Two subject-scoped candidates were checked by hand and correctly have nothing to
anchor: `[[Selection Orb And Floor Spotlight]]`, whose three `R:` lines all read
*not present in godot-learning*, and `[[Camera Fusion Chain]]`, whose fourteen
`R:` lines all cite `src/scenarios/CameraChainSpline.gd` — `Cutscene`'s camera,
not this system's.

**This is a finding for pass 8, not a defect of pass 2.** By size, the top six
files run `PlayerCamera.gd` 788 / `SkirtGeometryGenerator.gd` 786 /
`MapComposer.gd` 721 / `DynamicGeometryBuilder.gd` 623 / `TileCursor.gd` 611 /
`MapTextureAnimator.gd` 351 — anchored 1, **0**, 5, 3, 2, 1. The one hole in the
top six is the largest geometry generator in the system, and `PlayerCamera.gd`'s
single anchor is `Cutscene`'s note rather than one of its own. When pass 8 asks
what the extraction dropped, the honest answer for those 32 files is that the
vault never held anything to drop.

## Reproduce

The anchor set is derivable from the vault and the classifier; nothing here is
hand-maintained state.

```
git archive main vault/ | tar -x -C <tmp> --strip-components=1   # the vault lives only on main
uv run python tools/check_vault_anchors.py --list                # what is anchored now
```

The `R:` seed scan is 30 lines over `classify_blueprint.walk()` and the extracted
vault; the suffix ordering above is the only subtle part.
