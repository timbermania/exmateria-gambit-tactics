class_name DamageNumber3D
extends Node3D
## Over-unit floating damage / heal number (ADR-0063, issue #89).
##
## A transient, camera-facing 3D billboard that pops above a unit when its HP
## changes and TRENDS the way FFT does: each digit grows along a ROM Q12 scale
## ramp (0.30 -> 1.5 overshoot -> 1.0) revealed right-to-left, holds, then fades
## by switching to additive blend and darkening the palette to black. The motion
## is phase-driven, NOT a wall-clock tween — one integer phase counter advancing
## +1 per rendered frame at 60 Hz (the same vblank divider as the cursor bob),
## indexing [NumberPopupTrend] which is loaded from the committed, byte-verified
## `number_popup_trend.json` (ADR-0001 / ADR-0046). See
## research/working_documents/DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md.
##
## It is the UI sibling of [Projectile3D]: a `combat_visuals`-group member (rides
## the ADR-0037 freeze / finishes after victory) drawn with CUSTOM0 Ordering-
## Table depth (ADR-0009) so it sorts against battlefield geometry.
##
## Observation-only (ADR-0063): the value comes from the GPU-authoritative
## `CombatLoop.hp_changed` signal (our data); only the digit SHAPES + the trend
## motion are faithful FFT — the `0123456789` cells of the RANGETILE system atlas
## (#88), sampled through [member RangeTileAtlas]. Damage is white, heal green,
## MP blue (a flat tint; the exact ROM cream menu-CLUT is a non-blocking cosmetic
## follow-up, spec §8).
##
## Map-anchored, NOT a unit child: the manager parents it at the unit's world
## position (like a projectile) so the killing blow's number survives the
## target's death-frame (ADR-0063 "over-unit ownership splits by lifetime").
##
## Geometry note: the number's RIGHT EDGE is the shared anchor at the node
## origin, and each digit is a MeshInstance3D whose cell is placed to the LEFT of
## that anchor; per phase we set each digit's `scale` so its offset AND size
## scale about the shared anchor (Round 5.2 — NOT each glyph's own centre). At
## scale 0 a digit collapses onto the anchor (its pre-reveal state). The single
## captured anchor point is a screen point; vertically we centre the cell on it
## (a faithful choice for the one-point anchor). The ROM's secondary position/
## skew transform blocks (bb8/bd8/c04) are not yet RE'd, so there is deliberately
## NO invented rise — the number trends in place.
##
## Vault: [[Damage Number Popup System]]

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

const SHADER_OPAQUE := "res://assets/shaders/feedback_hud_sprite.gdshader"
const SHADER_ADDITIVE := preload("res://assets/shaders/feedback_hud_sprite_additive.gdshader")
## The `compositor_layer` variant of the additive twin: worn by the digits during the fade band when
## the engine-fold compositor owns compositing (fork >= 4.8 + Forward+). Routing the fade phase into
## the fold clamps its additive contribution per-step in the display scratch, so a number still fading
## when a routed prim (e.g. Fire) lands on the same unit no longer flashes it (ADR-0074 / #229, #89
## follow-up). Off the fold path (stock/Mobile/test-runner) the plain in-scene twin is used unchanged.
const SHADER_ADDITIVE_FOLD := preload("res://assets/shaders/feedback_hud_sprite_additive_fold.gdshader")

## Kinds. HP damage/heal ride `hp_changed`'s delta sign; MP is here for when an
## MP-number consumer is wired (spec §5 type 3). DAMAGE renders faithfully through
## the ROM number CLUT (0x7d7c, from the atlas); HEAL/MP have no RE'd palette yet,
## so they stay on the flat-tint path below (a cosmetic follow-up, spec §8).
enum Kind { DAMAGE, HEAL, MP }

const TINT := {
	Kind.DAMAGE: Color(1.0, 1.0, 1.0),   # (unused for DAMAGE — it uses the CLUT)
	Kind.HEAL: Color(0.45, 1.0, 0.5),    # green heal (flat tint, unRE'd palette)
	Kind.MP: Color(0.55, 0.65, 1.0),     # blue MP (flat tint, unRE'd palette)
}

# World-space geometry. A digit is DIGIT_HEIGHT world units tall; width preserves
# the atlas cell aspect. PITCH_FACTOR is the ROM's 7px pitch on the 8px cell, so
# adjacent digits kern by 7/8 of a cell width (Round 5.2: "8x16 cell, 7px pitch").
const DIGIT_HEIGHT := 0.34
const PITCH_FACTOR := 7.0 / 8.0
const ATLAS_SIZE := 256.0

# Phase pacing: +1 phase per rendered frame at 60 Hz (asset `pacing.hz`, the same
# vblanks-per-tick divider the cursor bob uses — ADR-0046).
const PHASE_HZ := 60.0

# Killing-blow numbers pop a touch bigger so the finishing hit reads. Applied to
# the whole node so it composes with the per-digit trend scale.
const KILL_SCALE := 1.25

static var _atlas: RangeTileAtlas = null
static var _trend: NumberPopupTrend = null
static var _palette_tex: ImageTexture = null

var _phase: int = 0
var _phase_accum: float = 0.0
var _digits: Array = []             # [{inst: MeshInstance3D, mat: ShaderMaterial, place: int}]
var _tint: Color = TINT[Kind.DAMAGE]
var _use_palette: bool = true       # DAMAGE lights digits through the ROM CLUT
var _in_fade: bool = false          # materials already swapped to the additive twin
var _folded: bool = false           # the fade routes through the engine fold (fork + Forward+)


static func _shared_atlas() -> RangeTileAtlas:
	if _atlas == null:
		_atlas = RangeTileAtlas.new()
	return _atlas


static func _shared_trend() -> NumberPopupTrend:
	if _trend == null:
		_trend = NumberPopupTrend.new()
	return _trend


static func _shared_palette() -> ImageTexture:
	if _palette_tex == null:
		_palette_tex = _shared_atlas().digit_palette_texture()
	return _palette_tex


## Build the number and start its trend. `value` is the raw HP delta from
## `hp_changed`; a heal is positive, damage negative — the magnitude is drawn.
## `kind` picks the tint; `killed` pops it slightly larger.
func setup(value: int, kind: int = Kind.DAMAGE, killed: bool = false) -> void:
	_tint = TINT.get(kind, TINT[Kind.DAMAGE])
	_use_palette = (kind == Kind.DAMAGE)   # only DAMAGE has a RE'd ROM CLUT
	_build_digits(str(absi(value)))
	if killed:
		scale = Vector3.ONE * KILL_SCALE
	_apply_phase()


func _ready() -> void:
	# Over-unit feedback is a combat-visual: it freezes with the battle on pause
	# / cinematic and finishes naturally post-victory (ADR-0037).
	add_to_group("combat_visuals")


func _process(delta: float) -> void:
	# Advance the integer phase counter at 60 Hz, exactly like the cursor bob's
	# frame counter — discrete phases, never a wall-clock interpolation.
	_phase_accum += delta * PHASE_HZ
	while _phase_accum >= 1.0:
		_phase_accum -= 1.0
		_phase += 1
	var trend := _shared_trend()
	if trend.is_done(_phase):
		queue_free()
		return
	_apply_phase()


## Place each digit's cell to the LEFT of the shared right-edge anchor (node
## origin). place 0 = ones (rightmost, its right edge at the anchor), place 1 =
## tens, etc. Each digit is its own MeshInstance3D at the origin so setting its
## `scale` scales offset+size about the shared anchor (Round 5.2).
func _build_digits(text: String) -> void:
	_clear_digits()
	var atlas := _shared_atlas()
	var tint_rgb := Vector3(_tint.r, _tint.g, _tint.b)  # raw sRGB; the shader applies the pow(2.2)
	var n := text.length()
	for i in n:
		var place := n - 1 - i               # leftmost char = highest place
		var glyph := text[i]
		var rect: Rect2 = atlas.digit_rect(glyph)
		var width := DIGIT_HEIGHT * (rect.size.x / rect.size.y)
		var pitch := width * PITCH_FACTOR
		# Cell corners relative to the shared right-edge anchor at x = 0.
		var x_right := -pitch * float(place)
		var x_left := x_right - width
		var y0 := -DIGIT_HEIGHT * 0.5
		var y1 := DIGIT_HEIGHT * 0.5
		var u0 := rect.position.x / ATLAS_SIZE
		var u1 := (rect.position.x + rect.size.x) / ATLAS_SIZE
		var v0 := rect.position.y / ATLAS_SIZE
		var v1 := (rect.position.y + rect.size.y) / ATLAS_SIZE

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_uv(Vector2(u0, v0)); st.add_vertex(Vector3(x_left, y1, 0))
		st.set_uv(Vector2(u0, v1)); st.add_vertex(Vector3(x_left, y0, 0))
		st.set_uv(Vector2(u1, v1)); st.add_vertex(Vector3(x_right, y0, 0))
		st.set_uv(Vector2(u0, v0)); st.add_vertex(Vector3(x_left, y1, 0))
		st.set_uv(Vector2(u1, v1)); st.add_vertex(Vector3(x_right, y0, 0))
		st.set_uv(Vector2(u1, v0)); st.add_vertex(Vector3(x_right, y1, 0))

		var inst := MeshInstance3D.new()
		inst.mesh = st.commit()
		var mat := ShaderMaterial.new()
		mat.shader = load(SHADER_OPAQUE)
		mat.set_shader_parameter("index_atlas", atlas.texture)
		mat.set_shader_parameter("cell", Vector4(0.0, 0.0, ATLAS_SIZE, ATLAS_SIZE))
		mat.set_shader_parameter("atlas_size", Vector2(ATLAS_SIZE, ATLAS_SIZE))
		mat.set_shader_parameter("fade", 1.0)
		mat.set_shader_parameter("brightness", 1.0)
		mat.set_shader_parameter("use_palette", _use_palette)
		if _use_palette:
			# DAMAGE: light the glyph through the ROM number CLUT (one faithful
			# pass — outline/fill/AA come from the palette, not a flat tint).
			mat.set_shader_parameter("palette_tex", _shared_palette())
		else:
			mat.set_shader_parameter("tint", tint_rgb)
		inst.material_override = mat
		inst.scale = Vector3.ZERO       # pre-reveal: collapsed onto the anchor
		add_child(inst)
		_digits.append({"inst": inst, "mat": mat, "place": place})


## Apply the current phase: scale each digit about the shared anchor, and once in
## the fade band swap to additive blend + ramp brightness toward black.
func _apply_phase() -> void:
	var trend := _shared_trend()
	var fading := trend.is_fading(_phase)
	if fading and not _in_fade:
		_enter_fade()
	var brightness := trend.fade_brightness(_phase) if fading else 1.0
	# During the fade band the number is additive; if it routes through the engine fold, re-stamp its
	# fold order every frame (depth tracks the unit) so the engine paints it in the right blend slot.
	var order_z := _fold_order_z() if (fading and _folded) else 0.0
	for d in _digits:
		var s := trend.scale_f(d["place"], _phase)
		d["inst"].scale = Vector3(s, s, 1.0)
		if fading:
			d["mat"].set_shader_parameter("brightness", brightness)
			if _folded:
				# Route the fade twin through the display-space fold (ADR-0074): the digit carries its
				# compositor_layer material + its OT fold-order. Idempotent — safe to call every frame.
				Fold.add(d["inst"], d["mat"], order_z)


## Swap every digit material onto the additive twin shader once, at the fade
## switch. Uniform values persist across the shader swap (same uniform names).
## On the fold path (fork + Forward+) the swap targets the `compositor_layer` variant so the additive
## fade folds into the display scratch instead of hardware-blending into the scene (the #89 fire-on-
## number fix); off it, the plain in-scene twin, unchanged.
func _enter_fade() -> void:
	_in_fade = true
	_folded = Fold.owns()
	var additive := fade_shader()
	for d in _digits:
		d["mat"].shader = additive


## The fade-band shader: the `compositor_layer` variant when the build folds, else the plain in-scene
## additive twin. The PICK is Fold.shader's (ADR-0191 dec. 2), tested on both branches in FoldTest;
## this pins which two shaders this producer hands it, and in which order. Mirrors
## EffectCallback.blend_shader.
static func fade_shader() -> Shader:
	return Fold.shader(SHADER_ADDITIVE_FOLD, SHADER_ADDITIVE)


## The number's representative OT fold-order key (view-space Z, DepthMode.ot_order_z): all digits share
## the node's world position, so one value orders the whole number. STANDARD mode matches the fold
## shader's ot_depth(..., 0). Returns 0.0 with no active camera (a bare unit test).
func _fold_order_z() -> float:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	if cam == null:
		return 0.0
	var view := cam.get_camera_transform().affine_inverse()
	return DepthMode.ot_order_z(global_position, view, DepthMode.Mode.STANDARD)


func _clear_digits() -> void:
	for d in _digits:
		if is_instance_valid(d["inst"]):
			d["inst"].queue_free()
	_digits.clear()
