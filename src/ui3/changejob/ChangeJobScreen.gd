class_name ChangeJobScreen
extends Node3D
## The Change-Job screen's bottom-middle JOB-TITLE frame (FORMATION_SCREEN.md §15.24, RE round 28/29,
## beat 9) — a small FRAME.BIN 9-slice window holding the highlighted job's name, with the unit's job
## LEVEL as a cream label poking half above the frame top (§15.24 RE29 + user note 2026-08-07). The rest
## of the Change-Job screen is composed from REUSED pieces: the top chrome (vitals cluster LAYOUT_TOP +
## nameplate top-right + ◄L1/R1► pager) is the settled `DetailScene`; the job WHEEL (oval of generic
## bodies) is built by `FormationScene.build_changejob_wheel`. This overlay owns ONLY the title frame.
##
## ENTRY (§15.24 RE29, dynamic per-vsync `tmp/cj_ent/cj_29..32.png`): the plate BOX-OPENS — center-out,
## opaque, in place over ~2 vsync (NOT a slide, NOT a fade). Same mechanism as every FFT window —
## `BoxOpenAnimator` §15.17 center-out SCISSOR (`clip_world` aperture), as `StartActionMenu`/`DetailScene`.
##
## Faithfulness (as elsewhere): FFT visuals + layout, OUR data. The job NAME is the parsed `JobDatabase`
## name (ADR-0001); the ROM's job-name msgid lookup is unpinned (§15.24). Frame rect + the cream Lv label
## are dynamic-measured from the oracle (formation_changejob_dest + the RE29 ←/→ capture `n_18`).
##
## Screen→world uses the SAME shared-ortho-camera convention as StartActionMenu/DetailScene
## (`_screen_to_world(px,py) = (px·PPU, −py·PPU)`), so it drops straight into the transition host.
##
## Vault: [[Change Job Screen]]

const TunePort = ExMateriaPlatform.TunePort

## ADR-0088 migration (guard ChangeJobTitleElementTest): the plate is the registered
## window element `changejob.title` (MENU_TILE chrome via the frame criterion, the
## shared BOX_OPEN beat, OWN_APERTURE) with the cream "Lv. N" line as the UNCLIPPED
## child element `changejob.level` — its poke above the frame is a DECLARED answer,
## not a shader-default omission. The per-class box-open accumulator + the
## _clip_world/_screen_to_world/_z_for copies retired into UI3Element + the engines.

const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const BoxOpenAnimator = preload("res://src/ui3/detail/BoxOpenAnimator.gd")
const RangeTileAtlas = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const NumberFont = preload("res://src/ui3/elements/NumberFont.gd")
const VITALS_SHADER := "res://src/ui3/shaders/vitals_sprite.gdshader"

## The cream/tan HUD CLUT (0x7CBC family) shared with UIUnitInfoWindow's Lv/Exp/stat numbers: index1 =
## cream body, low indices = dark outline. The plate "Lv. N" renders THROUGH this (§15.24 RE30 / user
## note 2026-08-07: the level + number are TEXTURE-sampled HUD cells — RANGETILE "Lv." + FRAMEFONT digit
## — NOT the FONT.BIN glyphs the job NAME uses).
const MENU_CLUT: PackedColorArray = [
	Color8(0, 0, 0, 0), Color8(239, 239, 231), Color8(156, 156, 148),
	Color8(82, 82, 74), Color8(33, 24, 16), Color8(90, 82, 74),
	Color8(123, 123, 115), Color8(140, 132, 115), Color8(165, 156, 132),
	Color8(156, 148, 123), Color8(115, 107, 90), Color8(140, 123, 107),
	Color8(173, 165, 140), Color8(33, 24, 16), Color8(41, 41, 41), Color8(16, 16, 16),
]

## Bottom-middle title-frame rect (virtual px). §15.24 RE31 (2026-08-07): re-measured from the LIVE
## oracle framebuffer (pcsx :8080 settled + rotated ring) — the tan 9-slice body spans y[208,232],
## x[84,171]. The prior y=186 was ~21px TOO HIGH, which made the plate COLLIDE with the front ring
## member (sprite y[166,206]); the oracle plate sits BELOW that body (~1px gap). Centred on x=128.
const TITLE_FRAME := Rect2i(84, 207, 88, 27)
## The job-name text top-y inside the frame — oracle "Chemist" dark FONT.BIN glyphs top ≈ 217 (§15.24 RE31).
const TITLE_TEXT_TOP_Y := 216.0
## The cream "Lv. N" label top-y — it STRADDLES the frame's top edge (oracle "Lv. 8" cream cells span
## y[204,210], plate top = 208, so ~half above / half on the tan border). §15.24 RE31, user note 2026-08-07.
## static var (ADR-0088 Amendment 4 §2): the sole real knob of changejob.level — bound to
## `changejob.level_label_top_y` with write-back, so one edit moves the element rect (its driver)
## AND the "Lv" glyphs (payload riding the moved origin). §14.6.6-style feather X stays structural.
static var LEVEL_LABEL_TOP_Y := 204.0

## Gap (px) between the RANGETILE "Lv." label cell and the first FRAMEFONT digit.
const LEVEL_DIGIT_GAP := 2.0
## The FRAMEFONT small digit is 10px tall vs the 8px "Lv." label — nudge the digit UP 2px so the digit
## and the label baseline line up (oracle `Lv. 8`).
const LEVEL_DIGIT_DY := -2.0

## Render priorities — a small band above the reused top chrome; folded to world-Z like the menu.
const RP_BASE := 40
const RP_FRAME := 41
const RP_TEXT := 43
const RP_LEVEL := 45          # the cream Lv label — drawn ABOVE the name, UNCLIPPED (pokes above the frame)
const DEFAULT_RUNG := 30
@export var overlay_rung_offset: int = DEFAULT_RUNG
## Auto-play the box-open on _ready (headful/host use). A guard drives it by hand via set_open_frame.
@export var autoplay_open: bool = true

var _job_name: String = ""
var _job_level: int = 0
var _menu_text: UIMenuText
# The registered WINDOW element (ADR-0088): movable origin + MENU_TILE chrome (frame
# criterion) + the shared BOX_OPEN beat + OWN_APERTURE clip. The clip engine discovers
# the body payload (chrome + name glyphs); the hand _body_mats/_frame_mats arrays died.
var _window: UI3Element
# The cream "Lv. N" line's own element — UNCLIPPED as a DECLARED answer (§15.24 RE30:
# it straddles the frame top, outside the box-open scissor).
var _level_elem: UI3Element
var _name_root: Node3D          # holds the job-name glyphs (rebuilt on rotate); window payload

# HUD "Lv. N" rendering (RANGETILE "Lv." word-cell + FRAMEFONT digits through the vitals_sprite CLUT
# shader) — the SAME mechanism the top-panel Lv/Exp/stat numbers use; NOT FONT.BIN (§15.24 RE30).
var _hud_atlas: RangeTileAtlas
var _hud_font: NumberFont
var _menu_pal: ImageTexture
var _vitals_shader: Shader
var _digit_tex: Texture2D
var _digit_size := Vector2(99, 22)
var _atlas_size := Vector2(256, 256)

## Fast open (5-frame, curve step ×2) — the oracle plate opens in ~2 vsync (§15.24 RE29), the fast path.
@export var fast: bool = true


## The job to show: NAME (e.g. "Squire") + the unit's LEVEL in that job (the cream Lv label). Set BEFORE
## add_child so _ready builds with it; call update_job() after to re-render on a ←/→ rotation (§15.24 RE29).
func set_job(job_name: String, job_level: int) -> void:
	_job_name = job_name
	_job_level = job_level


## Back-compat: name only (level defaults 0 → no Lv line). Prefer set_job.
func set_job_title(job_name: String) -> void:
	_job_name = job_name


func _ready() -> void:
	_menu_text = UIMenuText.new()
	_init_hud_fonts()
	_build_elements()
	_build_title_text()
	_build_level_label()
	if autoplay_open:
		play_open()
	# else: the window element boots settled (aperture = the full plate rect).


## Build the registered elements once (ADR-0088). The window's MENU_TILE chrome is
## built BY THE ELEMENT from its frame criterion (the hand _build_frame died); the
## Lv line is its own UNCLIPPED child element.
func _build_elements() -> void:
	_window = UI3Element.new({
		"id": "changejob.title",
		"rect": Rect2(TITLE_FRAME),   # the §15.24 RE31 oracle plate box — the composite live knob
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.MENU_TILE,
		"frame_rp": RP_FRAME,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"depth_rung": DEFAULT_RUNG - RP_BASE,
		# ADR-0097 §2: one cadence per VERB — the Change-Job plate opens on the fast curve.
		"open_cadence": UI3BoxOpenBeat.Cadence.FAST,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	add_child(_window)
	# per-instance export override — the OPEN only (ADR-0097 §2)
	_window.spec()["open_cadence"] = UI3BoxOpenBeat.Cadence.FAST if fast else UI3BoxOpenBeat.Cadence.DEFAULT
	if overlay_rung_offset != DEFAULT_RUNG:
		_window.spec()["depth_rung"] = overlay_rung_offset - RP_BASE
	_name_root = Node3D.new()
	_window.add_child(_name_root)
	# ADR-0068 write-back home for the level line's one real knob (bound BEFORE the element so
	# the static var is updated before the element's rect re-evaluates it): a scrub lands on the
	# static var and re-places the element origin; the "Lv" glyph payload rides it. Order-safe.
	TunePort.bind_update(self, "changejob.level_label_top_y", LEVEL_LABEL_TOP_Y,
		func(v: float) -> void:
			LEVEL_LABEL_TOP_Y = v
			if _level_elem != null and is_instance_valid(_level_elem):
				_level_elem.refresh_payload(),
		{"step": 1.0})
	_level_elem = UI3Element.new({
		"id": "changejob.level",
		# Case-3 driver (ADR-0088 Amendment 4 §2): the ONE genuinely-tunable const drives the
		# rect; the structural parts (TITLE_FRAME x/w coupling, fixed 10px height) stay literals.
		"rect": UI3Element.derived(["changejob.level_label_top_y"], func() -> Rect2:
			return Rect2(TITLE_FRAME.position.x, LEVEL_LABEL_TOP_Y, TITLE_FRAME.size.x, 10.0)),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	})
	_window.add_child(_level_elem)


## Re-render the plate for a newly-highlighted job (←/→ rotation, §15.24 RE29): swap the job name + Lv
## in place, keeping the frame + box-open state. The box-open is not replayed (the plate is already open).
## Old glyphs are freed SYNCHRONOUSLY (the DEFECT #8 idiom) so the engine's fresh discovery never sees
## them; the fresh glyphs receive the element's CURRENT aperture via the synchronous re-push.
func update_job(job_name: String, job_level: int) -> void:
	_job_name = job_name
	_job_level = job_level
	for c in _name_root.get_children():
		c.free()
	for c in _level_elem.get_children():
		c.free()
	_build_title_text()
	_build_level_label()
	_window._set_aperture(_window.aperture())   # idempotent re-push onto the fresh payload


func _build_title_text() -> void:
	if _job_name.is_empty():
		return
	# Centre the job name horizontally within the frame (home coordinates — the live rect
	# scrub moves the element origin and the glyphs ride).
	var w := _menu_text.measure(_job_name)
	var x := TITLE_FRAME.position.x + (TITLE_FRAME.size.x - w) * 0.5
	# No mats_out: the clip engine discovers the glyph materials (ADR-0088 §3).
	_menu_text.mount(_name_root, _job_name,
		_window.rel_world(x, TITLE_TEXT_TOP_Y) + _window.z_for(RP_TEXT),
		RP_TEXT, _window.ppu())


## Init the shared HUD atlases + cream palette used to render the "Lv. N" line as TEXTURE cells.
func _init_hud_fonts() -> void:
	_vitals_shader = load(VITALS_SHADER)
	_menu_pal = _make_palette(MENU_CLUT)
	_hud_atlas = RangeTileAtlas.new()
	if _hud_atlas.texture:
		_atlas_size = Vector2(_hud_atlas.texture.get_width(), _hud_atlas.texture.get_height())
	_hud_font = NumberFont.new()
	if _hud_font.texture:
		_digit_tex = _hud_font.texture
		_digit_size = Vector2(_digit_tex.get_width(), _digit_tex.get_height())


func _build_level_label() -> void:
	if _job_level <= 0 or _hud_atlas == null:
		return   # the CURRENT job shows NO Lv line (host passes 0); only prospective jobs do (§15.24 RE30)
	# "Lv. N" poking half above the frame top — the RANGETILE "Lv." word-cell + FRAMEFONT digit(s), through
	# the cream MENU_CLUT (§15.24 RE30 / user note: level+number are TEXTURE-sampled HUD cells, NOT FONT.BIN
	# like the job NAME). UNCLIPPED (the vitals_sprite clip_world defaults unbounded), so it pokes above the
	# frame like the oracle `Lv. 8`. Centred on the frame midline.
	var digits := str(_job_level)
	var label_rect: Rect2 = _hud_atlas.label_rect("Lv.")
	var digit_pitch := _hud_font.advance_for(NumberFont.SMALL)
	var total_w := label_rect.size.x + LEVEL_DIGIT_GAP + float(digits.length()) * digit_pitch
	var x := TITLE_FRAME.position.x + (TITLE_FRAME.size.x - total_w) * 0.5
	# Anchor the glyphs at the element's FROZEN home y (== LEVEL_LABEL_TOP_Y at construction) so
	# they are pure payload at local 0 — a level scrub moves the element ORIGIN and they ride it
	# (movable-origin model), and a rebuild after a scrub never double-counts the offset.
	var top_y: float = _level_elem.authored_home().y if _level_elem != null and is_instance_valid(_level_elem) else LEVEL_LABEL_TOP_Y
	_mount_hud_cell(_hud_atlas.texture, _atlas_size, label_rect, x, top_y)
	var digit_x := x + label_rect.size.x + LEVEL_DIGIT_GAP
	for g in _hud_font.place_number(digits, digit_x, top_y + LEVEL_DIGIT_DY, NumberFont.SMALL):
		var cell: Rect2 = g["cell"]
		_mount_hud_cell(_digit_tex, _digit_size, cell, g["pos"].x, g["pos"].y)


## Mount ONE indexed atlas cell (a RANGETILE label or a FRAMEFONT digit) as a textured quad through the
## shared vitals_sprite CLUT shader + cream MENU_CLUT — the same path the top-panel HUD numbers use.
## Added under the UNCLIPPED level ELEMENT (its declared clip answer keeps it out of the box-open
## scissor; the engine pushes the explicit unbounded sentinel).
func _mount_hud_cell(tex: Texture2D, tex_size: Vector2, cell: Rect2, x: float, y: float) -> void:
	if tex == null or _level_elem == null:
		return
	var ppu := _level_elem.ppu()
	var w := cell.size.x * ppu
	var h := cell.size.y * ppu
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	mi.mesh = quad
	var mat := ShaderMaterial.new()
	mat.shader = _vitals_shader
	mat.set_shader_parameter("index_atlas", tex)
	mat.set_shader_parameter("atlas_size", tex_size)
	mat.set_shader_parameter("cell", Vector4(cell.position.x, cell.position.y, cell.size.x, cell.size.y))
	mat.set_shader_parameter("palette_tex", _menu_pal)
	mat.set_shader_parameter("brightness", 1.0)
	mat.render_priority = RP_LEVEL
	mi.material_override = mat
	# Top-left anchor at (x,y): the QuadMesh centres on its origin, so offset +half right / −half down.
	mi.position = _level_elem.rel_world(x, y) + _level_elem.z_for(RP_LEVEL) + Vector3(w * 0.5, -h * 0.5, 0.0)
	_level_elem.add_child(mi)


func _make_palette(colors: PackedColorArray) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


# -----------------------------------------------------------------------------
# Box-open (§15.17 center-out scissor) — played by the shared TransitionEngine's
# BOX_OPEN beat on the window element (ADR-0088; the per-class accumulator died).
# -----------------------------------------------------------------------------
## `cadence` is the one-invocation override (ADR-0097 §4) — pass a UI3BoxOpenBeat.Cadence to
## make THIS play snap or slow without changing what the element is authored to do.
func play_open(cadence: int = UI3Element.NO_CADENCE_OVERRIDE) -> void:
	_window.open(cadence)


## The center-out aperture rect (display px) at animation frame `n` (n<0 ⇒ closed point at centre).
func aperture_at_frame(n: int) -> Rect2i:
	var full := Rect2i(_window.rect())
	if n < 0:
		return Rect2i(full.get_center(), Vector2i.ZERO)
	return UI3BoxOpenBeat.rect_for(full, n,
		UI3BoxOpenBeat.resolve(_window.cadence_for(UI3Element.OPEN_CADENCE), true))


## Park the box-open at frame `n`: drive the window element's aperture directly (the
## guard/host hand-drive; the clip engine pushes it onto the body payload).
func set_open_frame(n: int) -> void:
	_window._set_aperture(aperture_at_frame(n))


func aperture() -> Rect2i:
	return _window.aperture()


## The registered window element — the movable origin + chrome + aperture + beat carrier.
func window() -> UI3Element:
	return _window


## The Lv line's UNCLIPPED element (its poke above the frame is the declared clip answer).
func level_element() -> UI3Element:
	return _level_elem


## True once the plate box-open has fully settled (aperture == the full plate rect).
func is_open_settled() -> bool:
	return _window.is_settled() and Rect2i(_window.aperture()).size == Rect2i(_window.rect()).size


## The rendered job title (for the guard).
func job_title() -> String:
	return _job_name


## The rendered job level (for the guard: the cream Lv label).
func job_level() -> int:
	return _job_level


## How many HUD cells the "Lv. N" line mounted (RANGETILE "Lv." + one FRAMEFONT digit per digit) — 0 when
## the current job hides the line. For the guard that the level is TEXTURE-sampled, not FONT.BIN glyphs.
func level_cell_count() -> int:
	return _level_elem.get_child_count() if _level_elem != null else 0


## The title-frame materials (for the guard: the frame exists) — the element-built chrome.
func frame_materials() -> Array:
	var mat := _window.chrome_material() if _window != null else null
	return [mat] if mat != null else []


## The body materials (frame + job name) the box-open scissor reveals — the clip engine's
## fresh discovery over the window element (the UNCLIPPED level element excluded).
func body_materials() -> Array:
	return _window.payload_materials() if _window != null else []
