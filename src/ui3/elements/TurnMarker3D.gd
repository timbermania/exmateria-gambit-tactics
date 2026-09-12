class_name TurnMarker3D
extends Node3D
## The ROM's "AT" active-turn marker — the bobbing gold letters over the acting unit.
##
## Spec: `research/working_documents/AT_MARKER_RENDERING.md` §8.3 (six numbered
## requirements) and its §0 table. In the ROM this is ONE opaque `POLY_FT4`: a fixed
## 14x12 screen-pixel quad cut from the RANGETILE status-icon strip at (114,176),
## anchored by its TOP-LEFT corner on the unit's projected position raised 40 FFT
## world units, and animated by exactly one bit of a free-running 60 Hz counter that
## swaps the atlas row (176 <-> 188) and lifts the quad 1 pixel at the same time.
##
## Mounted like [StatusBubble3D] — a camera-facing billboard parented to the unit, so
## it dies with the unit (ADR-0063 "over-unit ownership splits by lifetime") — and it
## shares that node's rendering seam: `combat_visuals` group (ADR-0037), CUSTOM0
## Ordering-Table depth (ADR-0009), the feedback-HUD sprite shader.
##
## NOT a [StatusBubble3D] icon index, and deliberately not a branch of
## [FeedbackHudManager]`._desired_icon`. Three reasons, all measured:
##   * `_desired_icon` returns ONE icon per unit — charge OR the first status, mutually
##     exclusive. The ROM's slot 21 ALTERNATES with a status every 16 frames (§4.1), so
##     modelling AT as another index would encode an exclusivity the ROM contradicts.
##   * `StatusBubble3D.set_icon` is explicitly idempotent so the manager can call it for
##     every unit every frame. This marker needs a per-frame phase, which is exactly the
##     property that idempotency exists to remove.
##   * `FeedbackHudManager` is mounted by `GPUArena`, which has no `TurnDirector` and so
##     has no acting unit; turns open in `GambitBattle`, which mounts no manager at all.
##     Reaching one from the other would drag the damage-number apparatus into the
##     gambit host for a marker that needs none of it.
##
## Observation-only: the host tells it which unit it is on and nothing else.

## ADR-0212 dec. 1 — the addon declares one global (`ExMateriaSchema`), so this line is what
## keeps the use site spelled the way the rest of the port spells it (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

const SHADER_PATH := "res://assets/shaders/feedback_hud_sprite.gdshader"
const ATLAS_SIZE := 256.0

## The marker is 14x12 NATIVE pixels and the ROM never scales it (hard-coded 0x1000 at both
## the element and the builder), so its world size is the SPRITE PIPELINE's native-px scale —
## the same one every other battlefield sprite is built at:
##
##   * the unit body — `UnitRig.tscn`'s `UnitMesh` is a 1x1 `QuadMesh` scaled 8 over a 256px
##     SHP sheet, so 8/256;
##   * the ROM tile cursor — `TileCursor.gd`'s mesh is "1 tall … then uniformly scaled by
##     cursor_scale", and `CURSOR_SCALE_DEFAULT = 0.75` draws a 24px-tall dagger, so 0.75/24.
##
## Both land on 0.03125, and the ROM's own ratio agrees: AT 12px / character 40px = 0.30, which
## 0.375 / 1.25 world units reproduces exactly.
##
## ⚠️ NOT `camera.size / DisplayPort.NATIVE_VIEWPORT_HEIGHT`, which this used to do. 240 is the
## right denominator for turning a screen-pixel CAMERA OFFSET into a world shift (`PlayerCamera`,
## `ScenarioCameraDirector`) but it is not a sprite-sizing constant: the combat camera is not at
## native zoom. At `size = 12.6` with sprites at 1/32 it shows 12.6*32 ~= 403 sprite-pixel rows in
## a 240-row native frame — deliberately zoomed out 1.68x from PSX framing — so sizing off it
## inflated the marker by exactly that factor, and by MORE as the player zoomed out further.
##
## The consequence is that the marker is WORLD-locked like every other sprite, not pixel-locked.
## The ROM has no zoom, so there is no fidelity case for screen-constant sizing.
const WORLD_PER_SPRITE_PX := 8.0 / 256.0

## The ROM's counter is `unit[+0x2E0] += 1` per video frame and is reset only by a status
## change — never at turn start — so the bob is free-running and unsynchronised to anything
## the player does (§6.1). A `static var` reproduces that: the phase survives hide/show, so a
## marker that reappears on the next turn does not restart its hop.
const TICKS_PER_SECOND := 60.0
static var _tick_clock: float = 0.0

static var _atlas: RangeTileAtlas = null

var _material: ShaderMaterial = null
var _mesh_inst: MeshInstance3D = null
var _phase: int = -1                                    ## -1 = nothing built yet
var _built_size := Vector2.ZERO                         ## the (w,h) world size the mesh was built at
var _nudge_px: int = 0                                  ## `unit[+0x2DE]`, SCREEN px, added to the anchor's X
var _built_nudge: int = 0                               ## the nudge the mesh was built at


static func _shared_atlas() -> RangeTileAtlas:
	if _atlas == null:
		_atlas = RangeTileAtlas.new()
	return _atlas


## The animation's one bit (§6.2): `phase = (tick >> 4) & 1` picks the atlas row AND the
## 1px lift, so they are the same bit and can never desynchronise. Static and pure, so a
## test can assert the period without a wall clock or a rendered frame.
static func phase_for_tick(tick: int) -> int:
	var per: int = _shared_atlas().active_turn_phase_frames()
	if per <= 0:
		return 0
	return int(tick / per) & 1


func _ready() -> void:
	add_to_group("combat_visuals")
	_apply_sprite_offsets()
	_build_material()
	_apply_phase(phase_for_tick(int(_tick_clock)))


## Read the marker's height and screen-X nudge for THIS unit's sprite type (§5.2), and
## plant the node at that height.
##
## The switch key is the SHP-type byte of BATTLE.BIN 0x2D748 — the same table
## `parse_sprite_types.py` already extracts — so the port needs nothing new to answer it:
## a Chocobo/monster hangs the marker at -50, an ARUTE at -70, a KANZEN at -120, and the
## OTHER family at -25, where a single constant put every one of them at -40.
##
## Read ONCE, at mount, not per frame. The ROM re-evaluates it on every carousel advance,
## which matters because the tile and the animation can change under a unit — but the
## marker only exists while a turn is open, and the unit is frozen for the whole of it.
## Cheap to revisit if the marker ever outlives a still unit.
## These offsets are the CAROUSEL's, not this marker's — the ROM's slot-21 cell and the
## twenty status-icon cells go through one builder that reads `unit[+0x2DE]`/`[+0x2DF]`
## after every cell-selection branch has converged. So the resolver lives on
## [RangeTileAtlas] and [StatusBubble3D] reads the same rows.
func _apply_sprite_offsets() -> void:
	var unit := get_parent()
	var sprite_id: int = unit.body_sprite_id if unit != null and "body_sprite_id" in unit else -1
	var off := _shared_atlas().overhead_offset_for_sprite(sprite_id)
	_nudge_px = off.x
	position.y = RangeTileAtlas.overhead_raise_for_offset(off)


func _process(delta: float) -> void:
	_tick_clock += delta * TICKS_PER_SECOND
	_apply_phase(phase_for_tick(int(_tick_clock)))


## Rebuild the quad and re-point the atlas cell for `phase` (0 or 1). Cheap to call every
## frame: the mesh is only rebuilt when the phase flips (~every 16 frames) or the zoom moves.
func _apply_phase(phase: int) -> void:
	var atlas := _shared_atlas()
	if atlas.active_turn_frame_count() < 2:
		# A manifest predating the AT extraction. Draw nothing rather than a wrong cell —
		# RANGETILE.json is gitignored, so a checkout that has not re-run
		# tools/parse_range_tiles.py lands here.
		visible = false
		return
	var size := _pixel_size()
	if phase == _phase and size.is_equal_approx(_built_size) and _nudge_px == _built_nudge:
		return
	_phase = phase
	_built_size = size
	_built_nudge = _nudge_px
	var rect: Rect2 = atlas.active_turn_rect(phase)
	_material.set_shader_parameter("cell",
			Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	_build_quad(size, phase)
	visible = true


## The quad's world size: the atlas cell's 14x12 native pixels at the sprite pipeline's scale.
## Camera-independent — see WORLD_PER_SPRITE_PX for why reading `camera.size` here was wrong.
func _pixel_size() -> Vector2:
	return _shared_atlas().active_turn_rect(0).size * WORLD_PER_SPRITE_PX


## The quad, with the ROM's TOP-LEFT anchor and its 1px bob baked into the VERTICES.
##
## Both offsets have to live in the mesh rather than in a node transform: the billboard in
## `feedback_hud_sprite.gdshader` replaces the model basis with the inverse-view basis and
## keeps only the model TRANSLATION, so local vertex offsets come out as screen right/up
## while a node-position offset would move the marker through the world instead.
##
## Anchoring at the top-left is authentic and is why the glyph hangs about 7px right of the
## unit's centre-line — the ROM's sub-record carries dx,dy = 0 and the builder does not
## centre, so the quad occupies (sx,sy)..(sx+14,sy+12) from the projected point (§5.1).
func _build_quad(size: Vector2, phase: int) -> void:
	if _mesh_inst == null:
		_mesh_inst = MeshInstance3D.new()
		_mesh_inst.material_override = _material
		add_child(_mesh_inst)

	# World units per NATIVE pixel — the bob and the nudge are both screen-pixel
	# quantities, so both convert through it.
	var per_px := size.y / _shared_atlas().active_turn_rect(0).size.y
	var bob := 0.0
	if phase == 1:
		bob = float(_shared_atlas().active_turn_bob_px()) * per_px
	# `unit[+0x2DE]` — a post-projection SCREEN nudge (0, or -5 for two poses), so it is
	# a pixel shift of the whole quad, not a world offset. It rides in the vertices with
	# the anchor and the bob, for the same billboard reason. Always 0 until the anim ids
	# are decoded, but the field is applied rather than dropped so the day they are, the
	# only thing missing is the predicate.
	var x0 := float(_nudge_px) * per_px
	var x1 := x0 + size.x
	var y0 := bob               # top edge, at the anchor (lifted on phase 1)
	var y1 := bob - size.y      # bottom edge, `h` px BELOW it

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(x0, y0, 0))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(x0, y1, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(x1, y1, 0))
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(x0, y0, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(x1, y1, 0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(x1, y0, 0))
	_mesh_inst.mesh = st.commit()


func _build_material() -> void:
	var atlas := _shared_atlas()
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	_material.set_shader_parameter("index_atlas", atlas.texture)
	_material.set_shader_parameter("atlas_size", Vector2(ATLAS_SIZE, ATLAS_SIZE))
	_material.set_shader_parameter("fade", 1.0)
	_material.set_shader_parameter("brightness", 1.0)
	# CLUT mode, not the flat tint the status bubble uses: the ROM draws the marker with a
	# neutral (0x80,0x80,0x80) flat colour so the TEXEL passes through unmodulated, which is
	# a palette lookup and not a tint. The 16 entries come out of the extraction
	# (RANGETILE.json -> active_turn.colors, ROM CLUT 0x7887) — §8.3 point 4, root ADR-0001.
	_material.set_shader_parameter("use_palette", true)
	_material.set_shader_parameter("palette_tex", _palette_texture(atlas.active_turn_colors()))
	_material.set_shader_parameter("depth_mode", DepthMode.Mode.STANDARD)


func _palette_texture(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
