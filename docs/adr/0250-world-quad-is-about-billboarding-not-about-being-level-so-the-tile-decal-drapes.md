# `world_quad` is about billboarding, not about being level — so the tile decal drapes

The routed tile highlights (the green deployment zone, the blue Move and red
Attack ranges) lay **flat** on sloped ground. On Gariland's deployment zone that
is visible in the middle of the screen: tiles `(5,2)` and `(6,2)` are a matched
`InclineEast` / `InclineWest` pair, and both highlights sat level while the
terrain under them tilted. The user reported it as *"the green tiles don't slope
to match the underlying geometry"*.

The cause is one expression in `TileOverlayCompositor._append_tile`, and it had a
comment defending it — *"slope dropped — a slope-conforming decal would be Path
2"* — plus a test asserting it: *"every baked vertex sits at the lifted centroid
Y (FLAT decal, slope dropped — not billboarded)"*. **There is no Path 2, and the
test was locking a conflation.**

## Status

accepted

## Decision

1. **The routed decal keeps each corner's own world Y**, lifted by `DECAL_LIFT`.
   It drapes over the terrain it marks. On a `Flat` tile the result is
   byte-identical to the old centroid bake, which is why nothing changes on level
   ground and everything changes on an incline.

2. **`geometry = world_quad` constrains how the verts are PRODUCED, not that they
   share a Y.** It means baked ground positions rather than a quad expanded about
   a centroid at draw time — which is what the engine fold was doing when the
   Move/Attack tiles vanished on Forward+ (ADR-0074 ④b, issue #229). A sloped quad
   of baked world positions satisfies that axis exactly. Flattening was the
   billboard fix over-applied, and ADR-0074 never asked for it: the word "flat"
   appears there about flat/gouraud *colour* and flat *UI scenes*, never about
   levelling a decal's corners.

3. **The DEPTH stays flat, and it is a DIFFERENT axis.** `CUSTOM0` remains the one
   shared lifted centroid, so `ot_depth` gives the whole quad a single depth — the
   PSX GTE's own AVSZ4 model for a face (ADR-0009). This is the change that would
   tempt a later edit to make `CUSTOM0` per-corner "for consistency", and that
   would be a real regression, so the guard now locks the two halves *against each
   other* rather than only asserting one.

4. **No new data and no new RE were needed, because the slope is already in the
   pipeline.** `terrain.json` ships four per-corner `vertices` per tile alongside
   the decoded `slope_type` / `slope_height`; `DynamicTerrainBuilder` stores them
   as `Tile.tile_vertices`; and the IN-SCENE highlight path (`Tile.gd`, the
   average/opaque blend modes) has always used them verbatim, lifting each vertex
   by `HIGHLIGHT_Y_OFFSET` and keeping its Y. The routed path was the only
   consumer that threw the Y away — so the in-scene and routed highlights
   disagreed with each other on the same tile, depending only on blend mode.

## The sources, and what each one settles

Checked because the shape of the fix depends on where the slope model lives. The
question worth asking of each is not "does it slope" but "is it a ROM
observation, an authoring convention, or our own reimplementation restating
itself" — three of the six below are the third kind.

**GaneshaDx** — `Resources/ContentDataTypes/Terrains/TerrainTile.cs`,
`SetRenderVertices()`. It builds the flat quad at `(Height + Depth) * 12`, then
lifts a **subset** of the four corners by `12 + (SlopeHeight - 1) * 12`, the
subset chosen by `SlopeType` from four membership lists (`vert0LiftTypes` …
`vert3LiftTypes`). `Common/CommonLists.cs` maps the raw byte to the name:
`0 Flat, 133 InclineNorth, 82 InclineEast, 37 InclineSouth, 88 InclineWest,
65/17/20/68 Convex*, 150/102/105/153 Concave*`. So GaneshaDx's own terrain
overlay — the exact analogue of our decal — is slope-conforming by construction.

**Our exporter agrees with it, numerically.** MAP001 `(0,0)` is `InclineSouth`
with `slope_height 2`, and its exported corner Ys are `3.38 / 2.90 / 2.90 / 3.38`
— two corners lifted by 0.48. GaneshaDx's lift for `slope_height 2` is
`12 + 12 = 24` FFT units, and one height unit (12 FFT units) exports as 0.24, so
24 units is 0.48. The two models agree to the digit.

**The vault holds the ROM-level root, and it is the strongest source here.**
`vault/Unit Shadow Rendering.md` carries an `[S·D·R] 3/3` point on the ROM's own
ground decal — the unit shadow — whose vertex builder `FUN_8007b9d0` @
`0x8007B9D0` (BATTLE.BIN) *"sets all four corner Ys to the terrain tile surface
… slopes drape per-corner via tile-shape byte `tile[+4]` when `tile[+3]&0x1f` ≠
0"*, with per-shape-code corner-Y math cited for slope codes `0x11 0x14 0x25 0x41
0x44 0x52 0x53 0x58 0x69`. **The ROM drapes a ground decal per corner.** That is
the static root this decision actually rests on; GaneshaDx and our exporter
corroborate it from the authoring side.

Eight of those nine codes (17, 20, 37, 65, 68, 82, 88, 105) also appear in
GaneshaDx's 13-entry `TerrainSlopeTypes` table — two independently derived lists
agreeing on the byte values. They are not identical: `0x53` (83) is absent from
GaneshaDx's table, and GaneshaDx's `133 / 150 / 102 / 153` are absent from the
shadow builder's list, so the builder's set is the codes it special-cases rather
than the full slope vocabulary. Corroboration, not identity.

⚠️ The first pass of this research searched `~/Obsidian Vault` and
`~/ObsidianVault`, found nothing, and recorded "the vault holds nothing on this".
Both of those are decoys — near-empty stubs. **The vault is `vault/` in the repo**
(254 documents, generated from `research/` by the `vault-sync` daemon). A zero
from the wrong directory reads exactly like a zero from the right one.

`RomTerrain.gd` documents the two terrain name tables with
`tools/check_rom_terrain_tables.py` mechanizing their agreement.

**The Blender addon is not the source for this.** `exmateria-map` carries
`slope_type` as the raw byte (`b4`) and `slope_height` as a bitfield slice, for
byte-exact round-trip; it never decodes either into geometry. It is a
faithful-bytes tool, not a renderer, so it has no opinion to borrow.

**Our own unit shadow already drapes.** `UnitShadow.gd` casts a ray for the
terrain Y and reads the collision normal — the vault's `R:` line notes "Godot
drapes corners on the terrain mesh instead". So the tile decal was out of step
with the ROM, with GaneshaDx, with the exporter's own data, with the in-scene
highlight path, *and* with the sibling ground decal in this very tree.

**`MapGridOverlay` is the in-repo precedent that settles the shape.** It is the
other baked world-space mesh in this addon, it goes through the *same* fold, and
it already does exactly what this decision adopts: `xform * v + Vector3(0, Y_LIFT,
0)` per corner, with one shared centroid in `CUSTOM0` for depth. The compositor
was the outlier, not the pattern.

## Rejected

**A "Path 2" — a separate slope-conforming decal path beside the flat one.** The
comment that named it implied the conforming version was a larger build. It is
one expression: the corners are already in hand as `world[i]`, and the flatten
was actively discarding `world[i].y` to substitute a centroid. There is nothing
for a second path to do.

**Making `CUSTOM0` per-corner too.** Decision 3. Consistent-looking and wrong: it
would give one face a depth gradient the PSX never had, and it is now a red arm.

**Leaving the guard asserting flatness and adding a new one beside it.** The old
assertion was not a weaker version of the truth, it was the defect written down.
Two guards would then disagree, and the suite would be green either way.

## Consequences

`TileOverlayCompositorTest` is **24 assertions**, up from 19, and the flatness
assertion is gone rather than relaxed. Two seeded defects were run and each
reddened only its own arm: reverting to the centroid flatten reds the two drape
arms; making `CUSTOM0` per-corner reds the two depth arms. Neither touches the
other, which is the property decision 3 wanted.

The guard now asks the drape **corner by corner** (`positions[i]` against
`corners[order[i]] + lift`, for the emitted order `0,1,2,0,2,3`) rather than
checking that the Ys merely differ. "The Ys differ" is also true of a decal draped
over the *wrong* corners, which a winding change would produce silently.

`LatticeCliffEdgeTest`, `TerrainFixtureTest`, `TileCursorCompositorTest`,
`TileHighlightsTest` and `TileOverlayColorTest` are unaffected and green.

**The in-scene and routed highlight paths now agree.** Before this, whether a
highlight followed the terrain depended on its blend mode — additive (1/2/3) went
through the compositor and flattened; average (0) and opaque (4) stayed in-scene
and draped. `PLACEMENT_UNAVAILABLE` (blend 0) and `CURSOR_ACTIVE` (blend 4) were
therefore *already* conforming on the very tiles where `PLACEMENT_PLAYER` (blend
1) was not, on the same screen at the same moment.

**Expected on screen at Gariland:** of the zone's eight tiles, exactly two —
`(5,2)` and `(6,2)`, the matched incline pair at the zone centre (`center_x 5,
center_y 2`) — change. They now tilt toward each other across a 0.24 rise instead
of both lying level. The other six are `Flat` and are pixel-identical.
