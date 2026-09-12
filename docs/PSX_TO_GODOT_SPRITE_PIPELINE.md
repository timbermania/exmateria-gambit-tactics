# PSX → Godot Unit-Sprite Pipeline Map (texture-UV → screen)

**What this is.** A function-by-function trace of the complete FFT (PSX) battle
path from *"a unit's animation state + its SHP/EVTCHR frame's per-piece texture
UVs"* → *"pixels on the display"*, with each ROM function given a cited address,
a semantic name, its utility, the exact data it reads/writes, and its **Godot
analog** (file:line / shader block). The point is granular systems-and-data gap
analysis: every stage is a named, comparable cell so a *visible* discrepancy
(the scenario-6 carry sprite) can be localised to a stage instead of hand-waved.

**Companions.** The PSX side's prose detail lives in
`research/working_documents/PSX_UNIT_SPRITE_RENDERING.md` (state machine, SEQ
interpreter opcode table, subframe assembly, GPU-submit — read it for the
*within-stage* depth this doc summarises). This doc adds: (a) verification of
every address against the decompilation, (b) the Godot analog for each stage
with file:line, (c) the coordinate-space crosswalk, and (d) the gap analysis.
Coordinate/depth model authorities: `docs/adr/0009` (OT depth = one model),
`docs/adr/0052` (PSX coords 180°-about-X at parse), `docs/adr/0036`/`0044`/`0060`
(PAR seam), `docs/adr/0022` (indexed-color body + runtime palette).

Verification pass: 2026-07-07. Addresses confirmed against
`project-assets/fft-rom/battle_decompilation.c` + `battle_disassembly.txt`
(post-2026-06-20 base fix — no +0x800 shift). GTE thunks in SCUS range
(`func_0x8001d578`, `func_0x80042b1c`) decoded by hand from machine words.

---

## 0. Two architectures: forward-scatter (PSX) vs inverse-gather (Godot)

This is the single most important framing, and the reason the mapping is
**many-to-one and inverted** rather than function-for-function.

**PSX — forward scatter, two GTE passes, N primitives into a global OT.**
1. The unit **anchor** (feet/world point) is projected world→screen **once** by
   an *orthographic* GTE **MVMVA** (`func_0x8001d578`, mx=0/sf=1), giving screen
   `(x,y)` at `unit+0x120/+0x122` and an OT depth bucket at `unit+0x128`.
2. Each sprite **piece**'s four corners are then placed in **2D screen space**
   around that anchor by a rotation+scale matrix and projected with GTE
   **RTPT** (3 corners) + **RTPS** (4th) (`poly_ft4_packet_builder`
   `0x8007af44`). Each piece becomes one textured `POLY_FT4` quad, UV/TPAGE/CLUT
   attached, linked into the ~383-bucket Ordering Table. The GPU rasterises the
   whole OT back-to-front. Depth is *per-piece* (each quad carries its own OT
   bucket, adjustable by camera pitch).

**Godot — inverse gather, one billboarded quad, per-fragment compositing.**
1. The unit is **one** `Node3D` (a 1×1 billboarded quad mesh) whose
   `global_position` is the anchor. The **Camera3D** (orthogonal) projects the
   quad; the vertex shader billboards it and applies the **PAR** anchor stretch
   (`unit.gdshader:625-654`). Depth is a **single flat** reversed-Z `DEPTH`
   computed once per object (`ot_depth(...,6)` UNIT mode).
2. The sprite pieces are composited **inside the fragment shader**
   (`unit.gdshader` `add_tile_paletted`, `unit.gdshader:455-553`): for **each
   mesh fragment**, the UV is transformed *backwards* through
   translate→rotate→flip for every piece, and if it lands inside a piece's atlas
   rect the atlas pixel is sampled (indexed→palette). PSX's forward per-corner
   transform is thus Godot's **inverse** per-fragment transform, and PSX's N
   quads collapse into 1 quad + an in-shader loop over N tiles.

**Consequence for gap analysis.** Stages 1–6 (state → SHP decode → sprite
buffer) map fairly cleanly, mostly at *parse* time. Stage 7 (per-piece geometry)
is where the architectures diverge hardest — PSX pivots/mirrors each piece about
the *screen anchor*; Godot mirrors the *whole assembled UV* about the mesh
center. Stages 8–12 (world projection, depth, raster) are structurally different
(GTE OT vs Camera3D + reversed-Z DEPTH) but numerically reconciled by ADR-0009 /
ADR-0036. See §5 for the suspect list this framing produces.

---

## 1. The spine (stage table)

Gap key: **≈** faithful/equivalent · **⇉** many-to-one (PSX N → Godot 1) ·
**⟂** divergent mechanism (numerically reconcilable) · **∅** missing in Godot.

| # | PSX addr | Semantic name | Utility (one line) | Godot analog (file:line) | Gap |
|---|----------|---------------|--------------------|--------------------------|-----|
| 1 | `0x80085c0c` | `anim_state_machine` | Per-unit/frame: start/advance anim, resolve facing→SEQ slot+flip, tick 3 WEP/EFF slots | `UnitDisplay._paint_body_variant` (UnitDisplay.gd:369-398) + `ScenarioVM._apply_unit_animation` (ScenarioVM.gd:3064-3101) | ⟂ |
| 2 | `0x80084818` | `type1_seq_interp` | TYPE1 SEQ bytecode → frame index + wait; opcode table 0xBE-0xFF | `AnimationFrameCalculator.get_frame_at` (AnimationFrameCalculator.gd:20-33); cinematic: `CinematicWalkState.advance` (ScenarioVM.gd:3504-3539) | ⟂ |
| 2b | `0x80085198` | `frame_index_resolve` | `displayed = *(u16)(anim_state+0x14) + script_byte` | folded into stage 2 (frame byte IS the index; +0x14 base = 0 in scn6) | ≈ |
| 3 | `0x80083f18` | `source_frame_ptr` | `frame_ptr = *(anim_res[+0x1c] + frame_idx*4)` | JSON lookup key: `_evtchr_frames_db[seg][fb]` / `shp_data[str(frame_id)]` (SpriteLayerManager.gd:406,615) | ⇉ |
| 4 | `0x80084214` | `subframe_assemble` | SHP frame → per-piece list; writes sprite buffer at `unit+0x204` | **parse time**: `parse_shp.parse_tile/parse_frame` (parse_shp.py:109-195); **runtime**: `SpriteLayerManager.load_frame_by_id` (362-459) / `load_cinematic_frame` (581-652) | ⇉ |
| 5 | `0x8007b4ec` | `buffer_write_piece` | Leaf: store ONE 7-byte piece `[sx][sy][w][h][U][V][flags]` at `buf+0x0E+i*7` | the append loop in `load_*_frame` → `type1_rects/rect_sizes/locs/…` arrays (SpriteLayerManager.gd:406-423, 626-634) | ⇉ |
| 6 | `0x80086640` | `render_dispatch` | Per-unit: mode(+0x130) select, 4-entry layer table `DAT_80094548+prio*0x10`, loop bound = `buf[+0x03]` | fragment `priority[4]` loop + `paint_type1/wep1/eff1` (unit.gdshader:851-914); mode-2 mount = Unit mount wiring | ⟂ |
| 7 | `0x8007af44` | `poly_ft4_packet_builder` | Per-piece: 2D rot+scale matrix, 4 corners about anchor, RTPT+RTPS, UV/TPAGE/CLUT, OT insert | `add_tile_paletted` inverse UV transform (unit.gdshader:455-553): `translate`→`rotation_around_point`→`revert/invert_within_rect`→`within_quad`→sample | ⟂ **(prime suspect)** |
| 8 | `0x8007b96c` | `world_vec_build` | Sum 3 int16 triples/axis → world VECTOR; `+0x64`→**Z**, `+0x62`→Y, `+0x60`→X | `global_position` from grid: `ScenarioVM.cinematic_place` (2970-2976) + Sprite-Move offsets; ADR-0052 depth flip | ≈ |
| 9 | `0x80042b1c` | `svector_pack` | Pack 3 world shorts at dst+0/+2/+4 | — (folded into Godot Vector3 / camera transform) | ⇉ |
| 10 | `0x8001d578` | `gte_ortho_mvmva` | GTE MVMVA sf=1 mx=0 (R=camera): world→(MAC1,MAC2,MAC3). **Orthographic, no divide** | `Camera3D` (Orthogonal) PROJECTION·VIEW; pose from `ScenarioCameraDirector._compute_camera_godot_pose` (708-789) | ⟂ |
| 11 | `0x80086b44` | `project_all_units` | Loop units: MVMVA → screen `+0x120/+0x122`, OT depth `+0x128 = MAC3>>2`; camera R@`0x80098A24` | `cam.unproject_position(anchor)`; DEPTH = `ot_depth(...,6)` (unit.gdshader:634-639,944) | ⟂ |
| 12 | GPU / OTC | `ot_raster` | POLY_FT4s DMA'd, rasterised back-to-front, textured+CLUT+semi-trans | Godot Forward+ rasteriser + reversed-Z DEPTH sort; `add_tile_paletted` sample+palette (unit.gdshader:531-551) | ⟂ |

---

## 2. Per-stage detail

### Stage 1 — `anim_state_machine` `0x80085c0c`
**PSX.** Once per frame per active unit. Combines `work_rotation_y + unit.facing`
→ quadrant (SEQ slot front/back/side) + octant (flip flags OR'd into `unit+0x12`).
On `anim_command(unit+0x0C)==3` starts a new anim (clears WEP/EFF slots, zeroes
`+0x50..0x5C` offsets, calls stage 2 with first-frame=1); on `==0` continues
(re-resolve slot if facing changed, else decrement `wait_timer +0x1E2`, advance
on 0). Then ticks 3 sub-anim slots at `+0x208/+0x238/+0x268`. Full opcode table
in `PSX_UNIT_SPRITE_RENDERING.md` §3-4.

**Godot.** Two collaborators. **Combat/normal** path:
`UnitDisplay._paint_body_variant` (UnitDisplay.gd:369-398) dispatches on
`current_anim_id`: `==0` idle (pose-octant LUT), `<0x1f4` low-range SEQ
(`CinematicPoseLUT.resolve_low_range_seq_key`, sets `apply_reversion` = facing
mirror), `>=0x1f4` returns (hands the body to the scenario walker). **Scenario**
path: `ScenarioVM._apply_unit_animation` (ScenarioVM.gd:3064-3101) mirrors PSX
`+0x0C`: low-range writes `play_body(anim_id+1)` (so Unit's `(id-1)*2` slot math
= PSX `event_anim_id*2`); cinematic-range spawns the walker (stage 2).

**Gap ⟂.** PSX resolves facing→slot+flip *procedurally per frame* from the live
camera+facing angle; Godot precomputes it via `CinematicPoseLUT` and the
per-state resolution map (ADR-0021). The 3-slot WEP/EFF tick is Godot's separate
WEP1/EFF1 layers driven by `UnitDisplay` (UnitDisplay.gd:435-437).

### Stage 2 — `type1_seq_interp` `0x80084818` (+ `frame_index_resolve 0x80085198`)
**PSX.** Reads SEQ bytecode: a non-0xFF byte is a **frame delta**, `frame_index =
anim_state[0x14] + byte`; the next byte is the wait count. `0xFF`-prefixed bytes
are opcodes (movement `+0x50..0x5C`, flips, loops, `SetYRotation`, etc.). Slot
routing: `<500` TYPE1 (uses `anim_state[0x20]` ptr table), `500-599` WEP
(`0x8006a7d8`), `≥600` EFF (`0x8006ed3c`).

**Godot.** **Normal**: `AnimationFrameCalculator.get_frame_at(anim_id,
anim_frame, sequences)` (AnimationFrameCalculator.gd:20-33) walks
`LOAD_FRAME_WAIT` opcodes accumulating `duration` until `anim_frame < t+duration`
→ returns `op_code_param_0` (the frame). **Cinematic** (EVTCHR band ≥0x1f4):
`CinematicWalkState.advance` (ScenarioVM.gd:3504-3539) is the faithful bytecode
walker — `LoadFrameWait` sets `fb=param_0`, `ticks_left=max(wait,1)`;
`IncrementLoop`→`op_index=0`; `Pause/EndAnimation`→done. `_render(fb)` (3541-3563)
routes `fb>=0xD2`→`load_cinematic_frame`, else `load_frame_by_id`.

**Gap ⟂.** Same bytecode semantics; Godot has two implementations (a
duration-accumulator for looping SEQ anims driven by a per-unit clock, and a
tick-driven walker for cinematics). The `+0x14` frame base is 0 in scn6 so
`frame_index == script_byte`.

### Stage 3 — `source_frame_ptr` `0x80083f18`
**PSX.** `frame_ptr = *(u32*)(table + frame_idx*4)`, `table = anim_resource[+0x1c]`
(the SHP section-2 frame pointer array). Indirection from frame index → raw SHP
frame bytes.

**Godot ⇉.** No pointer arithmetic — the frame data is pre-extracted into JSON
keyed by string. Normal: `shp_data[str(frame_id)]` (SpriteLayerManager.gd:394).
Cinematic: `_evtchr_frames_db[str(seg)][str(fb)]` (SpriteLayerManager.gd:611-615).
The disc→runtime frame-byte `+7` shift is handled in `parse_evtchr_frames.py`.

### Stage 4 — `subframe_assemble` `0x80084214` — **the SHP decode**
**PSX.** Frame header: `piece_count=(frame[0]&7)+1`, `rotation_index=frame[0]>>3`
→ `buffer[+0x0C]=DAT_80094508[idx]` (26-entry angle table). Each 4-byte piece:
`shift_x=(s8)b0`, `shift_y=(s8)b1`, bitfield `b2..b3`: `U=(bits0-4)<<3`,
`V=v_offset+((bits5-9))<<3`, `size_index=bits10-13`, `flip_x=bit14`,
`flip_y=bit15`; `width=DAT_800946c8[size]`, `height=DAT_800946cc[size]`. Special
0xE 48×48 split for non-human. `v_offset` from `unit+0x7A`. Writes via stage 5.

**Godot ⇉ — split across parse + runtime.** The SHP decode itself happens at
**parse time**: `parse_shp.parse_tile` (parse_shp.py:109-144) is byte-identical
math — `x=s8(b0)`→`location_x`, `y=s8(b1)`→`location_y`, `tile_x=(flags&0x1F)*8`→
`rectangle_x`, `tile_y=((flags>>5)&0x1F)*8 + y_offset`→`rectangle_y`,
`size_index=(flags>>10)&0xF`→`SIZES[size_index]`, `reverse_x=flags&0x4000`→
`revert`, `reverse_y=flags&0x8000`→`invert`, `rotation=ROTATIONS_DEGREES[b0>>3]`.
`parse_frame` (147-195): `num=(byte0&7)+1`, `rot_idx=(byte0>>3)&0x1F`. At
**runtime** `load_frame_by_id`/`load_cinematic_frame` just read that JSON and
push it (stage 5). **`v_offset`/`unit+0x7A`** → `atlas_y_offset` param of
`load_cinematic_frame` (added to `rectangle_y`, SpriteLayerManager.gd:627) and
`wep1_v_offset_pixels` for WEP (SpriteLayerManager.gd:411).

> **Data crosswalk (critical).** Godot `location_x/y` **= PSX `shift_x/shift_y`
> verbatim** (the per-piece placement offset relative to the anchor), and
> `rectangle_x/y` = the PSX atlas `U/V`. Godot does **not** store a separate
> anchor+shift; the anchor centering is applied at draw via `shared_loc_offset`
> + `SPRITE_CENTER (100,100)`. So the *decode* is faithful; the *placement math*
> that consumes it (stage 7) is where divergence lives.

### Stage 5 — `buffer_write_piece` `0x8007b4ec`
**PSX.** Leaf store of one 7-byte piece `[shift_x][shift_y][w][h][U][V][flags]`
at `buffer+0x0E+piece*7`. `flags` bit0=semi-trans, bit1=flip_x, bit2=flip_y,
bit7=split marker.

**Godot ⇉.** The append loop in `load_frame_by_id` (SpriteLayerManager.gd:406-423)
/ `load_cinematic_frame` (626-634): appends to eight parallel arrays
(`rects,rect_sizes,locs,inversions,reversions,rotations,rot_points,loc_offsets`)
then one `set_shader_parameter` per array (426-433 / 636-643). `rot_points` and
`loc_offsets` are **uniformly** `SPRITE_CENTER_OFFSET=(100,100)` for every piece
(SpriteLayerManager.gd:28-29,421-422,633-634). No per-piece pivot data comes from
the SHP — see the stage-7 gap.

### Stage 6 — `render_dispatch` `0x80086640`
**PSX (verified).** `mode = *(char*)(unit+0x130)`: **0** = normal layer render,
**2** = composite/mount (pulls a second unit via `FUN_8007a6e4(unit+0x131)`),
**1 (and any other value) = no-op skip** to the tail. Layer group =
`(unit+0x14)*0x10` into `DAT_80094548`, 4 int entries: entry `0` → own
render_state `unit+0x204`; entry `n` → sub-sprite at `unit+(n-1)*0x30` (buffer
`+0x22C`, active gate `+0x208`). Piece count passed to stage 7 = `buffer[+0x03]`
(start 0). Global `sprite_scale_x/y/z` loaded here and passed to every stage-7
call.

**Godot ⟂.** The 4-entry layer table ↔ the fragment `priority[4]` loop
(unit.gdshader:898-914) painting `type1/wep1/eff1` back-to-front (painter's
algorithm inside one quad). Layer enable = `wep_enable/eff_enable`. Mode-2 mount
= Unit's mount/rider wiring (separate node), not a shader mode. **`sprite_scale`
is NOT wired to unit sprites in Godot** (documented gap — `PSX_UNIT_SPRITE_
RENDERING.md` §12).

### Stage 7 — `poly_ft4_packet_builder` `0x8007af44` — **PRIME SUSPECT**
**PSX (verified, with corrections to the seed).** Per piece `pcVar14 =
buffer+0x0E+i*7`:
- **Parent flip pivot** (`param_6` = caller/facing flags, bit1=H, bit2=V):
  `if H: left = -width - shift_x` else `left = shift_x`; symmetric
  `if V: top = -height - shift_y` else `top = shift_y`. *(The seed omitted the
  V arm.)*
- **Per-piece corner swap** via `uVar10 = piece_flip_byte ^ param_6`: H bit swaps
  which physical corner is left/right (mirror), V bit swaps top/bottom. Four
  corners packed `CONCAT22(y,x)`: V0=(xl,yt) V1=(xr,yt) V2=(xl,yb) V3=(xr,yb).
- **Matrix**: `angle = param_5 + buffer[6]`; `cos=func_0x8001bc28`,
  `sin=func_0x8001bb5c`; `DAT_80098dcc` MATRIX = `[cos·sX·bX, -sin·sY·bY;
  sin·sX·bX, cos·sY·bY]` (sX/sY = global scale `param_7`, bX/bY = buffer scale
  `buffer[4]/[5]`), TR `DAT_80098de0/de4 = screen_pos` (the anchor). Loaded via
  `SetRotMatrix`/`SetTransMatrix`.
- **Projection**: `copFunction(2, 0x280030)` = **RTPT** (3 corners) + `0x180001`
  = **RTPS** (4th). *(The seed guessed MVMVA — WRONG; per-piece corners go
  through RTPT/RTPS.)* Corners pivot/rotate about the **screen anchor (TR)**.
- **UV**: SXY0=(U,V), SXY1=(U+w,V), SXY2=(U,V+h), SXY3=(U+w,V+h). **No ±1 texel
  fudge.** `TPAGE = buffer[2] | (param_6 & 0x60)`, `CLUT = buffer[3]`.
- **OT insert** at `param_8`, with a camera-pitch-dependent bucket branch
  (`sprite_scale_z`).

**Godot ⟂ — the inverse.** `add_tile_paletted` (unit.gdshader:455-553), per
fragment, transforms the mesh UV *backwards*:
1. `translate(uv, loc_uv[0] - rect_uv[0])` — moves the atlas rect onto the draw
   `loc` (= `shift_x/shift_y`) (unit.gdshader:486-489).
2. `translate(uv, loc_offset)` where `loc_offset = SPRITE_CENTER(100,100) +
   shared_loc_offset(25,26)` (490-493) — the anchor centering.
3. `rotation_around_point(uv, rot_pt_mesh, deg_rot)` pivoting about
   `rot_pt = SPRITE_CENTER + shared_loc_offset` (494-506).
4. `revert_within_rect` (H) / `invert_within_rect` (V) per-tile flip (507-524).
5. `within_quad(rect)` test → sample indexed→palette (525-551). Whole-sprite
   facing flip = `global_reversion` (`uv.x = 1.0 - uv.x`, unit.gdshader:884).

**The divergence (why this is the prime suspect).**
- PSX **parent/facing flip** re-pivots *each piece* about the anchor
  (`-width-shift_x`); Godot mirrors the *entire composited UV* about the mesh
  center (`1-uv.x`). Equivalent **only** if every piece is symmetric about that
  center — a multi-piece carry pose (Delita 4 pieces, Ovelia 3) is not, so the H
  mirror can shift pieces relative to PSX.
- PSX rotates/pivots each piece about the **screen anchor (feet, TR)**; Godot
  pivots about the **fixed** `SPRITE_CENTER+shared_loc_offset` (100+25, 100+26)
  in atlas-pixel space. If that constant point ≠ the projected feet anchor, a
  nonzero `deg_rot` (rotation table) or a flip walks the piece off.
- PSX per-piece + global **scale** (`buffer[4/5]` × `sprite_scale`) has **no
  Godot analog** for units.
- PSX applies the rotation/scale via a real 2D matrix then RTPT (perspective
  divide by H); Godot's `rotation_around_point` is a pure 2D rotation in
  aspect-corrected UV space (no divide). For the near-ortho FFT camera these are
  close but not identical for large angles.

### Stages 8-11 — world→screen projection
**PSX (verified).** `project_all_units 0x80086b44` loads camera R@`0x80098A24` as
both rot and trans matrix, then per unit: `world_vec_build 0x8007b96c` sums three
int16 triples per axis — X=`+0x40+0x60+0x50`, Y=`+0x42+0x62+0x52+0x76`,
Z=`+0x44+0x64+0x54` (so `+0x64` is **world-Z**, not an OT index) — packs via
`svector_pack 0x80042b1c`, projects via `gte_ortho_mvmva 0x8001d578` (MVMVA sf=1
mx=0 — orthographic, no perspective divide; decoded from GTE cmd `0x0480012`).
Stores screen `+0x120 = MAC1(+flipΔ)`, `+0x122 = MAC2(+flipΔ)`, OT depth
`+0x128 = MAC3>>2`. **Screen origin offset is folded into the camera TR
translation (cv=0), NOT GTE OFX/OFY** — that seed claim was imprecise (OFX/OFY
belong to the RTPS path, not this MVMVA path).

**Godot ⟂.** The anchor `global_position` comes from grid coords:
`cinematic_place` (ScenarioVM.gd:2970-2976) = `Vector3(grid_x+0.5, tile.y,
grid_z+0.5)` (grid pre-flipped at parse per ADR-0052; `flip_depth_row = size_z-1-z`
in PsxNum.gd:126-127). Sprite-Move offsets (PSX `+0x60/+0x62/+0x64`) are applied
as world deltas (`SCENARIO_POSITION_DIVISOR=112`, `sprite_move_position_divisor=
112/4`, ScenarioVM.gd:499,507). The **Camera3D is Orthogonal**; its pose is built
by `_compute_camera_godot_pose` (ScenarioCameraDirector.gd:708-789): pos
`(x/112, -z/112, y/112)` with `flip_depth_continuous(y/112,size_z)=size_z-y` for
depth (735-736), ortho size `camera_ortho_at_1x_zoom*4096/zoom` (771), optional
exact GTE-rotation basis `B = D·R⁻¹·D`, D=diag(1,-1,-1) (760-765). Screen anchor
for probes = `cam.unproject_position(mesh.global_position)`.

**Depth (ADR-0009).** PSX `MAC3>>2` OT bucket ↔ Godot `ot_depth(depth_point,
PROJ, VIEW, 6)` (ot_depth.gdshaderinc:65-86), UNIT mode 6 → `base +
ot_unit_forward(0.1) * proj[2][2]` (reversed-Z). Sample point is the sprite
**center** (`MODEL_MATRIX[3] + (0, depth_center_height, 0)`, unit.gdshader:638),
`depth_center_height = 0.0625 - visible_center.y/32 + center_bias`
(SpriteLayerManager.gd:672-677) — DERIVED from the non-transparent pixel bbox
(`compute_body_center`, 699-755). Depth is **flat** across the billboard
(unit.gdshader:944) — one bucket per object, unlike PSX's per-piece buckets.

**PAR (ADR-0036/0044/0060).** No PSX analog (PSX pixels are non-square natively).
Godot restores the ~1.25× horizontal stretch via `pixel_aspect_anchor(vertex_clip,
anchor_clip, unit_stretch)` (pixel_aspect.gdshaderinc:66-69, called
unit.gdshader:651-653): the anchor's clip.x is PAR-stretched, the billboard offset
added at `unit_stretch` (1.0 = native art).

### Stage 12 — raster
**PSX.** OT DMA'd to GPU; each POLY_FT4 textured from VRAM via TPAGE, CLUT-paletted
(4bpp), semi-transparency by ABR bits, drawn back-to-front.

**Godot ⟂.** Forward+ rasteriser; the fragment shader gathers each tile
(`add_tile_paletted`), recovers the palette index `round(tex.r*15)`, treats
index 0 as transparent (FFT magic-0), samples `palette_tex[index, body_palette_
row]` (unit.gdshader:531-551, ADR-0022), applies scenario CLUT tint
(`unit_tint_scale/bias`), spell tint (`unit_tint`), ambient, sRGB→linear, writes
flat `DEPTH`.

---

## 3. Data-structure crosswalk

**`unit+0x204` sprite buffer (PSX) ↔ Godot shader uniforms + JSON.**

| PSX buffer | Meaning | Godot analog |
|---|---|---|
| `+0x00..02` | gouraud RGB tint | `unit_tint` / `unit_tint_scale/bias` |
| `+0x03` | piece_count | `type1_rects.length()` (non-zero-width entries) |
| `+0x04` | TPAGE | implicit (atlas is one texture) |
| `+0x06` | CLUT | `body_palette_row` (ADR-0022) |
| `+0x08/0A` | scale_x/y (4.12) | **∅ no unit-sprite analog** |
| `+0x0C` | rotation (angle) | `type1_rotations[i]` (degrees, `ROTATIONS_DEGREES`) |
| `+0x0E+i*7` piece | `[sx][sy][w][h][U][V][flags]` | `type1_locs[i]=(sx,sy)`, `type1_rect_sizes[i]=(w,h)`, `type1_rects[i]=(U,V)`, `type1_reversions[i]`=flip_x, `type1_inversions[i]`=flip_y |

**Anim state `unit+0x1D8`**: `+0x04` anim id ↔ `current_anim_id`; `+0x08` frame ↔
walker `op_index`/`AnimationClock`; `+0x14` frame base (0 in scn6); `+0x2c` =
`unit+0x204` buffer ptr. **Unit array** base `0x800B7308` stride `0x440`; scn6
Delita `0x800B8848`, Ovelia `0x800BA608`, chocobo `0x800B8C88`.

---

## 4. Coordinate-space crosswalk

| Space | PSX | Godot |
|---|---|---|
| Atlas texel | `U/V` pixels (piece `[4][5]`) | `rectangle_x/y` px → `/tex_size` → mesh-UV → tex-AR (`pxl_quad_to_mesh`+`mesh_quad_to_tex`) |
| Piece placement | `shift_x/shift_y` about screen anchor | `location_x/y` (=shift) → `translate(uv, loc-rect)` in mesh-UV |
| Anchor centering | screen anchor = GTE TR (feet) | `SPRITE_CENTER(100,100)+shared_loc_offset(25,26)` in atlas px |
| Rotation pivot | screen anchor (per piece, RTPT) | fixed `SPRITE_CENTER+shared` (per tile, 2D) |
| World anchor | `+0x40/42/44` (+move offsets), ÷ (GTE) | grid `(x+0.5, tile.y, z+0.5)`; offsets ÷112 |
| Screen | GTE MAC1/MAC2 (+TR), px | `cam.unproject_position`, px |
| Depth | `MAC3>>2` OT bucket, per-piece | flat reversed-Z `DEPTH`, per-object (mode 6) |
| Horizontal PAR | native non-square px | `pixel_aspect` clip-x stretch (anchor-only) |

---

## 5. Gap analysis — suspects for the visible scn6 carry sprite

Ranked by how directly stage 7's divergence bites the carry pose (multi-piece,
flipped, cinematic band). **§8 (2026-07-07) resolved this list against live RAM:
#1–#3 do not fire on the carry units, leaving #6 (camera framing) as the residual.**

1. **✗ struck — Facing/parent H-flip mechanism (stage 7).** PSX re-pivots each
   piece about the anchor (`-width-shift_x`); Godot mirrors the whole UV (`1-uv.x`)
   about the mesh center. Multi-piece asymmetric poses can shift — **but the carry
   poses are all `count=1` (§8), so the single symmetric piece makes whole-quad
   mirror ≡ per-piece pivot.** H-flip itself is faithful (§7: PSX `render_flags`
   bit1 ↔ Godot `global_reversion`).
2. **✗ struck — Rotation pivot mismatch (stage 7).** `buffer[+0x0C]` rotation is
   `0x0000` in *every* scn6 savestate, every unit (§8) — this stage never fires
   in the whole abduction.
3. **∅ Per-piece + global scale (stages 6/7).** `buffer[+0x08/0A]` × `sprite_
   scale` has no unit-sprite analog — a scaled carry pose would be wrong size.
4. **⟂ Flat vs per-piece depth (stage 11).** Godot sorts the whole billboard at
   one bucket; PSX sorts each piece. Intra-sprite overlap (arm over torso) could
   differ, though the carry pieces are near-coplanar.
5. **≈ but verify: `atlas_y_offset`/Vbase (stage 4).** `unit+0x7A` ↔
   `load_cinematic_frame`'s `y_offset` (from `actor.atlas_y`). A wrong row selects
   wrong atlas art. Byte-match was 28/28 for scn6 seg 1 (memory), so likely OK.
6. **Camera framing (director).** Not a sprite bug — prior sessions showed the
   scenario camera framing (ortho size/pan) accounts for much of the *apparent*
   gap (memory `scenario6-carry-visual-ab-camera-framing`). Keep camera matched
   before blaming stage 7.

---

## 6. Per-layer coordinate/position probes

Two paired probes read the coordinate/position state at every layer on both
engines, so a gap can be localised to a stage by diffing them. Same layer labels
(A/B/C/D) on each side.

- **PSX**: `tools/probe_pipeline_psx.lua` — loads
  `reference-assets/scenario6_carry_over_shoulder.sstate`, dumps for Delita(5) &
  Ovelia(12): anim id (`+0x1DC`), the `unit+0x204` buffer header + decoded 7-byte
  pieces, the world-vec triples (`+0x40/50/60`, `+0x76`), screen (`+0x120/122`),
  OT depth (`+0x128`), `render_flags +0x12`, `v_offset +0x7A`, `mount +0x130`,
  and camera R@`0x80098A24`. Run: pcsx paused on :8080, then
  `PcsxAgent.exec_file(".../probe_pipeline_psx.lua")` (or `dofile` in the Lua
  console). **Reads live RAM — do not trust hardcoded piece references** (the old
  `probe_carry_pieces.gd` hardcoded 3/4 pieces; the live settled carry is
  `count=1`).
- **Godot**: `tools/probe_pipeline_layers.gd` — parks scn6 at `PC=<pc>` and dumps
  the matching layers for U5/U12: `current_anim_id` + facing (A); `type1_*`
  per-piece arrays + `shared_loc_offset` + `global_reversion` +
  `depth_center_height` (B/E); `mesh.global_position` (C);
  `cam.unproject_position(anchor)` + horizontal px/world scale + ortho size (D).
  Run headful: `PC=219 godot --path . -s res://tools/probe_pipeline_layers.gd`.

## 7. Worked layer-diff — parked carry, PC 219 (2026-07-07)

The first end-to-end run of both probes at the settled carry. **Every layer
matches to the descriptor**, which is itself the finding: the residual *visible*
gap is not in stages 1–11's coordinate state at this beat.

| Layer | Delita(5) PSX → Godot | Ovelia(12) PSX → Godot | Verdict |
|---|---|---|---|
| A anim id | `0x207` → `0x207` | `0x1FF` → `0x1FF` | ✓ exact |
| B piece | `loc(-17,-35) UV(128,160) 32×40` → identical | `loc(-17,-35) UV(160,80) 32×40` → identical | ✓ exact |
| B flip/rot/scale | flipH=0, rot=0, scale=1.0 → `global_reversion=false`, rot=0 | **flipH=1**, rot=0, scale=1.0 → **`global_reversion=true`**, rot=0 | ✓ consistent |
| C world anchor | `(238,-132,338)` ÷28 → `(8.50, ·, 1.93)` | `(242,·,345)` ÷28 → `(8.643, ·, 1.68)` | ✓ exact (across ADR-0052 depth flip `size_z−z`) |
| D screen anchor | `(266,138)` | `(268,141)` | ✓ direction matches; abs px = cosmetic ortho zoom (cam.size 8.30) |

**Reads.**
- Both engines render **one** 32×40 piece here (`buffer[+0x03]=1`), no rotation,
  no scale — so stage-7 suspects **#2 (rotation pivot)** and **#3 (scale)** are
  **inactive at this beat**, and **#1 (H-flip)** is present but *faithful*
  (Ovelia's PSX `render_flags` bit1 ↔ Godot `global_reversion=true`; the single
  piece is symmetric enough that whole-quad mirror = per-piece pivot here).
- World anchors are **exact** once ÷28 and the ADR-0052 depth flip are applied
  (`238/28=8.5`, `242/28=8.643`, `345/28=12.32`→`14−12.32=1.68`).
- The only nonzero residual is the **screen anchor** ratio, which is the
  orthographic camera zoom (a similarity transform — cosmetic per §0/ADR;
  corroborates memory `scenario6-carry-visual-ab-camera-framing`: the gap the
  user sees is the scenario camera DIRECTOR framing, not the sprite pipeline).

**Where to look next** (multi-piece / rotated beats, where the stage-7 divergence
actually activates): re-run both probes at a beat with `count>1` and/or nonzero
`buffer[+0x0C]` rotation (e.g. the hoist/punch PCs 193–216), and diff layer B/E —
that is where PSX's per-piece-about-anchor mirror/pivot can part ways with
Godot's whole-quad `global_reversion` + fixed `SPRITE_CENTER` pivot.

## 8. Multi-piece / rotation sweep — the stage-7 suspects are inactive on the carry (2026-07-07)

Following §7's "where to look next," both stage-7 divergence triggers were swept
across the whole scn6 abduction (PSX side, all 7 `reference-assets/scenario6_*.sstate`
+ an all-slots scan at the settled beat; `/tmp/probe_scn6_multipiece_*.lua`,
`probe_scn6_allslots_pos.lua`).

**Rotation (`buffer[+0x0C]`) is `0x0000` in every scn6 savestate, every unit.**
Stage-7 suspect **#2 (rotation pivot)** is therefore **inactive scenario-wide** —
strike it from §5, not just "inactive at the settled beat."

**The carry poses are single-piece throughout.** Delita's and Ovelia's carry-band
anims (`0x1F4`–`0x208`) are all `count=1` at every sampled beat (punch/pickup
start `0x4`/`0x1F4`, settled `0x207`/`0x1FF`, ride-off `0x201`/`0x1FF`). So the
multi-piece divergence path **never renders the carry units** — suspect **#1's**
per-piece-vs-whole-quad mirror question is moot for the carry (one symmetric piece).

**`count>1` exists only on background/idle units playing normal SHP anims** — at
the settled beat, slot 2 (`anim 0x7`, count 3), slot 4 (`0x48`, count 2), slot 6
(`0x1C`, count 6). These composite through the **same** `type1_rects` shader arrays
as everything else (`SpriteLayerManager.load_frame_by_id` / `load_cinematic_frame`
share one path), i.e. the general renderer exercised game-wide — not a carry-
specific stage.

**Conclusion.** No coordinate/piece/anim stage (1–11) is the visible carry gap:
stages match byte-exact at the clean beat (§7), and the two stages that *could*
diverge (rotation, multi-piece) do not fire on the carry units at all. The
residual is the orthographic camera-director framing (cosmetic similarity
transform — memory `scenario6-carry-visual-ab-camera-framing`).

**PC 210 note (pre-exec park vs fixed savestate).** Parking Godot at 210 and
diffing against the *settled* savestate shows a **1-anim-frame phase offset**
(Godot `0x208`/`0x1FE` vs savestate `0x207`/`0x1FF`) with all structural layers
still matching — an artifact of comparing a pre-execution freeze to a fixed
settled frame (memory `scenario-park-freeze-and-preexec-pace`), not a bug. PC 219
is the aligned settled beat; use it, not 210, for the descriptor diff.

**Out-of-scope observation (flag, not carry-related).** At PC 219 Godot has only
6 units instantiated (uids 1,2,4,5,12,23) vs PSX's 12 populated slots; Godot's
1/4/23 sit at spawn-corner `X=0.5` with no PSX positional match, and uid 2 plays
`anim 0x3` where the X-matched PSX slot 2 plays `0x7`. That is a background-NPC
population/placement question (ghost/escort units, memory
`scenario6-abduct-three-bugs-rootcause` §0x47), independent of carry sprite fidelity.

## 9. The beat-210 "Ovelia wrong" gap = park-granularity off-by-one, NOT a pipeline bug (2026-07-07)

> TL;DR (see §9a for the proof): at the "pc210" A/B, Godot shows Ovelia already
> *dropped* while PSX still shows her *lifted*. This is NOT a mesh/UV/decode error —
> pc210 is a `Unit Anim` and the drop is pc211's Sprite Move, which Godot decodes
> exactly right. Godot's beat-park just can't stop *inside* the non-blocking
> pc210→pc211 run, so it overshoots. Engines agree at wait-boundaries 209 & 212.

§7/§8 measured the *settled* beat (219) and the *settled savestate*, both of which
match. But the user's complaint is at the **transition beat 210**, and the settled
frame is the wrong reference for it. Re-run at a **true beat-210 read-BP park**
(NOT the settled savestate — see `research/working_documents/CAPTURE_SCENARIO_BEAT_HOWTO.md`).
The emulator was already frozen at true beat 210; live RAM read via
`/tmp/probe_live_beat.lua` (no savestate load), Godot via `probe_pipeline_layers.gd PC=210`.

**Frame is matched, anchor is not.** Both engines are on the same frame at 210
(Delita anim `520`, Ovelia anim `510` — exact). User's read: **Delita placed
correctly, Ovelia not.** Calibrating on Delita (the known-good, *unflipped* unit):

| | PSX true beat-210 | Godot | verdict |
|---|---|---|---|
| Ovelia piece (UV/size/shift) | `UV(128,80) 32×40 shift(-17,-35)` | identical | ✓ **UV/art faithful** |
| Ovelia H-flip | `render_flags` bit1 set | `global_reversion=true` | ✓ flip faithful |
| Ovelia **screen anchor** vs Delita | `(269,133)` vs `(266,138)` → **5 px HIGHER** (lifted onto shoulder) | both screen-Y `544.85` → **same height** | ✗ **anchor wrong** |
| Ovelia **world anchor** (Delita-calibrated) | should be `(8.357, 4.929, 1.929)` | actual `(8.357, 4.800, 1.786)` | ✗ Y −0.18 (no lift), Z −0.14 (spurious depth); X ✓ |

**FIRST-PASS verdict (WRONG — corrected below).** The table above reads like a
mesh-placement bug: Ovelia's anchor at "pc210" is missing the carry-lift and has
spurious depth while her UV/flip are faithful. That framing is *refuted* by the
trajectory test in the sub-section below — the anchor Godot shows at pc210 is the
*correct* anchor for pc211; the fault is which instruction the park froze on, not
how the anchor was computed.

### 9a. RESOLVED — it is a PARK-GRANULARITY off-by-one, NOT a placement/UV/decode bug

The instructions around the beat: **pc210 = `Unit Anim`** (no move), and Ovelia's
Sprite Moves sit at pc 204/205/208/209/**211**. So the "drop" move Godot shows at
pc210 is **pc211's** Sprite Move. Parking PSX per-opcode (read-BP, scenario-event-
debugger `scn_jump`) and reading Ovelia `unit+0x60/62/64` at each PC gives the
ground-truth trajectory — and the same beats on Godot (`probe_pipeline_layers.gd`):

| PC (pre-exec) | PSX off / world | Godot world | agree |
|---|---|---|---|
| 209 | `(−4,−5,16)` → lifted `(8.357, 4.98, 1.929)` | lifted `(8.357, 4.979, 1.929)` | ✓ |
| 210 (`Unit Anim`) | `(−4,−5,16)` → **lifted** | **dropped** `(8.357, 4.80, 1.786)` | ✗ |
| 211 (`Sprite Move`) | `(−4,−5,16)` → **lifted** (pc211 not yet run) | dropped | ✗ |
| 212 (`Wait`) | `(−4,0,20)` → dropped `(8.357, 4.80, 1.786)` | dropped `(8.357, 4.80, 1.786)` | ✓ |
| 214 | `(5,2,23)` → re-lifted | (re-lifts; settled state matches, §7) | ✓ |

**The engines agree at both wait-boundaries (209 lifted, 212 dropped) and disagree
ONLY on the two non-blocking opcodes between them (pc210 `Unit Anim`, pc211 the
drop-move).** PSX's read-BP stops per-opcode, so it can freeze *before* pc211;
Godot's beat-park cannot stop *inside* a run of non-blocking opcodes, so it executes
through pc211 and freezes on the post-drop state — which it labels "pc210."

**Corrected verdict: the carry sprite pipeline is FAITHFUL.** Ovelia's Sprite-Move
decode is byte-correct (Godot's pc211 result `(−4,0,20)`≡`(8.357,4.75,1.786)` equals
PSX's pc211 result exactly), her UV/flip/anchor are faithful, and PSX itself dips
her down at pc211–213 then re-lifts at pc214 (a real carry adjustment, not a Godot
artifact). The visible "Ovelia in the wrong place at beat 210" A/B mismatch is a
**park-granularity off-by-one in the Godot debug park**, not a rendering bug — it
appears only when a compared beat lands on a non-blocking opcode, and vanishes at
wait-boundary beats (209, 212).

**Methodological consequence:** any beat-park A/B in this investigation that landed
mid-non-blocking-run showed Godot 1–2 opcodes ahead of PSX. For a trustworthy diff,
compare at a *wait-boundary* PC, or make the Godot park stop per-opcode (like the
PSX read-BP) instead of per-wait-boundary — a debug-tooling fix, not a gameplay one.
To confirm no *live-play* difference, watch both engines free-run: the lift→drop→
lift dip (pc209→212→214) occurs at the same moment since the `{F1} Wait`s are matched
(memory `scenario6-pace-wait-offbyone`). Probes: `/tmp/probe_live_beat.lua`,
`/tmp/read_ovelia_off.lua` (per-PC PSX read via `scn_jump`), `probe_pipeline_layers.gd`.
