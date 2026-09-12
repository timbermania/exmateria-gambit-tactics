# Display and pixel aspect

How the PSX's non-square pixels are reproduced on a modern square-pixel
display, and what "applying PAR" means precisely for a piece of content.
The cluster exists to kill the framing trap of "is this thing PAR or not?"
— a trap that hides the prior question of what coordinate system the
thing's position is even expressed in. Resolve that first; PAR becomes
a per-content rendering detail.

**Display space**:
The single canonical screen-space coordinate system every subsystem
agrees on — square pixels, post-stretch, the dimensions the user
actually sees (1280×960 today). UI element positions, camera framing,
gambit cursors, debug overlays, layout-container step values all live
here. "Virtual" PSX pixels (256×240) **never escape an individual
element's renderer** — they're a source-art dimension internal to the
texture a UIChar / UIPortrait / unit sprite draws, and they're converted
to display units at that boundary. A position never carries a virtual
unit; a width returned for layout (`get_display_width`) never carries
one either.
_Avoid_: storing a UI position in "virtual pixels" because the source
art is in virtual pixels (the conversion lives at the renderer, not at
the placer); a global container that scales the whole frame to
reintroduce virtual-pixel positioning (the failed [PSXDisplay] mesh
approach); modeling the world in PSX virtual pixels and the UI in
display pixels separately (one canonical space; per-content opt-in is
the only knob).

**PAR** (pixel aspect ratio):
The 1.25× horizontal stretch a piece of PSX-authored pixel art needs to
reproduce its intended look on a square-pixel display — PSX renders at
256×240 (16:15) but displays at 4:3, so each PSX pixel is ~1.25 wide ×
1 tall. **A per-content rendering choice**, not a global mode: the
content's quad in [display space](28-display-and-pixel-aspect.md) is sized
`source_width * PAR × source_height`, anchored on its **left edge**
(the stretch grows rightward, so a top-left position remains correct
under any PAR value). Whether a given content type stretches is a
per-subsystem decision, not a global toggle — UI text and portraits
opt in; unit sprites, 3D map geometry, and particles each decide on
their own evidence. The constant `1.25` lives once at
`PSXDisplay.PAR`; subsystems that opt in multiply by it explicitly so
the dependency is visible at the call site.
**Implementation invariant**: for 3D meshes that opt in via the
vertex shader, PAR multiplies `clip_pos.x` **only** — after
`PROJECTION_MATRIX * MODELVIEW_MATRIX`, never on `CUSTOM0`, never on
`VERTEX` in object space, never on a centroid pre-projection. The
world is PAR-blind end to end; the only thing that ever multiplies by
1.25 is the final clip-X of a per-mesh opt-in shader. This is what
keeps the [GTE depth pipeline](25-rendering-depth.md) intact: depth is
`c.z / c.w` from the projected centroid, and PARing only `c.x`
touches neither term, so face depth, OT bucket assignment,
`Depth mode` biases, and layer-priority sorting all survive unchanged.
**One seam, enforced**: PAR is applied through exactly one shared
shader include (`addons/exmateria_platform/pixel_aspect/pixel_aspect.gdshaderinc`), the `POSITION`
analogue of `ot_depth` for the [depth axis](25-rendering-depth.md) — two
helpers, `pixel_aspect_full` (flat map-attached geometry, full clip-X
stretch) and `pixel_aspect_anchor` (anchor-tracking billboards, sprite
footprint scaled by the per-taxonomy width, ADR-0044). Every battle
shader that writes `POSITION` routes through it or is flagged by
`tools/check_par_shaders.py` (a `run_all_tests.sh` preflight);
fullscreen NDC passes opt out with `// pixel-aspect-exempt:`. This retires
the recurring "new mesh silently forgot PAR and drifted horizontally"
bug (unit shadow, dialogue box/tail). See ADR-0060.
_Avoid_: stretching the entire frame post-render to "apply PAR
globally" (the [PSXDisplay] approach, retired — broke camera math,
sprite filtering, and debug ergonomics); calling 1.25 a "stretch
factor" without saying which axis (always **horizontal**); applying
PAR to a layout step or a position (PAR stretches *visible content*;
positions are in display space and PAR-invariant by construction);
toggling PAR after positions have been authored by eye (everything
center- and right-aligned will shift — pick a PAR value, then author);
multiplying `CUSTOM0` / `VERTEX` / a world-space centroid by PAR (the
invariant is final-clip-X-only — anything earlier in the pipeline
leaks PAR into world space and re-creates the coordinate-disagreement
the per-content model exists to prevent).

**Layout under PAR**:
The rule that makes top-left anchoring survive per-content PAR opt-in
and forces right-/center-aligned and composed layouts to stay correct.
Top-left placement is **PAR-invariant**: the left edge of a UIChar /
UIPortrait sits at its node origin regardless of `pixel_aspect_ratio`,
because the quad's centering offset (`mesh_width / 2.0`) already
includes the PAR factor. The non-trivial cases — right-alignment,
center-alignment, layout containers stepping `cursor.x += child_width`,
popups sized to the widest row — must consume the **post-PAR display
width** (`get_display_width`), never the source-pixel width. That's the
whole rule; the helper exists, the discipline is using it.
_Avoid_: a hand-computed `char_width * pixels_per_unit` at any layout
call site (drops PAR; use the helper); a `width_no_par` variant of any
public width helper (no caller wants pre-PAR width — every consumer is
in display space).

**PSXDisplay**:
The autoload that owns runtime PAR state, and **`Render`'s published port** —
`addons/exmateria_platform/display_port/PSXDisplay.gd`. It shipped inside
`addons/exmateria_render/` from extraction #1 until extraction #3's loop pass 6 moved it
to the `platform` tier — ADR-0171 dec. 1 rules it a **port**, not `Render`'s subject, and
[#583](https://github.com/timbermania/fft-monorepo/issues/583) still owes the
`DisplayCalibration` rename dec. 4 ordered.
The autoload NAME stays a `project.godot` entry the host writes: an addon cannot
ship one without being an enabled `EditorPlugin`, and this project enables neither
of its addons. The host registers the name; the addon owns the implementation. Three pieces: the `PAR := 1.25`
constant (the canonical PSX stretch factor), `live_par` (defaults to
`PAR`; its setter writes the project-wide `pixel_aspect` global shader
parameter declared in `project.godot` → `[shader_globals]`, which every
opt-in Pattern 1/2 world shader reads), and `live_ui_par` (defaults to
`PAR`; the parallel mesh-width multiplier UI3 elements read via
`source_width * pixel_aspect_ratio * pixels_per_unit`). Each emits a
`*_changed` signal; `DisplayDebugPanel` and `UIDisplayDebugPanel` host
parallel SpinBox scrubs that write the two values independently, so the
world can sit at 1.25 while a UI font tunes against 1.0 (or vice-versa).
The split is deliberate — there is no single "PAR knob" the project
agrees on; world and UI are independent surfaces with independent
evidence. UI3 elements (`UIChar`, `UIText`, `UIPortrait`, `UIFrame`)
guard the runtime sync with `if not Engine.is_editor_hint()` so the
editor preview keeps rendering against each element's `@export` default
while a play session reads the live scrub. An earlier shape wrapped the
main scene in a SubViewport scaled `(PAR, 1.0)` to stretch the whole
frame; that retired because it broke camera-pan symmetry, sprite
filtering at non-integer ratios, debug ergonomics, and scene-reload
routing, and it couldn't selectively skip units — per-content opt-in is
the only knob that can.
_Avoid_: reading `PAR` for a runtime stretch (read `live_par` or
`live_ui_par`, which start at `PAR` but are scrubbed); referencing a
single project-wide PAR toggle from a subsystem (each subsystem opts in
independently — there's no on/off); tuning `live_par` and `live_ui_par`
to the same value blindly (they're independent on purpose — UI fonts
may want a different stretch than the world); authoring positions
against a scrubbed `live_ui_par` value (the scrub is for *visual
evaluation*; saved positions should target the `@export` default).

**Sprite stretch** (ADR-0044):
The third PAR axis, distinct from [World PAR](28-display-and-pixel-aspect.md)
(`pixel_aspect`) and [UI PAR](28-display-and-pixel-aspect.md) (`live_ui_par`). A
**per-taxonomy horizontal multiplier on a Pattern-2 sprite's billboard
*width*** — the art's size around its anchor — layered on top of the
shared World-PAR anchor. The anchor still tracks the PAR-stretched map
(World PAR, unchanged); sprite stretch only widens the art *in place*,
so a stretched sprite never drifts off the tile it marks. Three buckets,
each its own `psx_*_stretch` global (and `PSXDisplay.live_*_stretch`
scrub), each defaulting to **1.0 = native art** (the ADR-0036 "sprites
don't stretch" default — opt in per bucket): **Cursor** (the tile
cursor), **Unit** (`unit.gdshader` bodies), **Effects** (everything
else — particles, projectiles, shadow blobs, callback meshes). They are
independent so the cursor can stretch while units stay native.
_Avoid_: conflating sprite stretch with World PAR (World PAR moves the
*anchor* and full-stretches Pattern-1 geometry; sprite stretch widens
Pattern-2 *art* only); a single shared sprite-stretch value (units must
be able to stay native while the cursor stretches — that's why the
buckets are split); applying stretch to the anchor (that's World PAR's
job and would re-introduce drift); a world/object-space mesh X-scale to
get the stretch (PAR stays a post-MVP `clip.x` multiply — never on
`VERTEX`).
