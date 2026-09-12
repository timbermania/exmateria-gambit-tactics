class_name FormationDebugPanel
extends BaseDebugPanel
## F3 → Designer tab: live placement calibration for the FORMATION / roster screen
## (FORMATION_ELEMENT_PLACEMENT.md §7). Dials in the per-cell body, drop-shadow and
## gold-box placement against the PSX oracle (t04.png) without a scene reload.
##
## A VIEW, not an owner (ADR-0068 decision 12): FormationScene binds every knob to a
## `formation.*` Tune slug in _ready (the apply writes the @export + rebuilds the
## cells), so these are real tunables — they persist (right-click → Pin), show in the
## generated Tunables dashboard, and a dialed value re-applies at boot. This panel
## just groups them into TuneField rows; it registers nothing itself (no default_value).
##
## The knobs (all cell-relative virtual px):
##   Body scale       — fixed holder scale (all minis one scale; job heights differ)
##   Feet target X/Y  — the standing point the visible feet land on (body centre-X,
##                      common baseline-Y)
##   Shadow off X/Y   — shadow CENTRE relative to the feet target ("shadow relative to
##                      the unit"): +Y moves it DOWN, −Y UP
##   Shadow size W/H  — on-screen shadow rect (ROM 20×10 = 2:1 squash of a 20×20 texel)
##   Shadow intensity — subtractive strength (1 = full; oracle floor is darker in-port)
##   Box centre X/Y   — gold selection-box meeting point (feet)
##   Floor spotlight  — base (centre brightness) / min (far-floor darkness) / swing
##                      (pool SIZE = per-px falloff) / vfac (oval H:V shape; 4 = 2:1 wide)
##   Unit/orb dim     — orb_falloff_scale: how fast a sprite darkens with distance from
##                      the selection (§16 body falloff; 0 = every unit full-bright)

const TuneField = preload("res://src/debug/TuneField.gd")

const _SCALE := {"min": 1.0, "max": 24.0, "step": 0.1}
const _POS := {"min": -64.0, "max": 128.0, "step": 0.25}
const _OFF := {"min": -32.0, "max": 32.0, "step": 0.25}
const _SIZE := {"min": 1.0, "max": 48.0, "step": 0.5}
const _UNIT := {"min": 0.0, "max": 1.0, "step": 0.02}
const _LEVEL := {"min": 0.0, "max": 2.5, "step": 0.01}
const _SWING := {"min": 0.0, "max": 0.02, "step": 0.0001}   # floor-spotlight px falloff
const _VFAC := {"min": 0.5, "max": 12.0, "step": 0.25}      # oval H:V aspect (4 = 2:1 wide)
const _DIM := {"min": 0.0, "max": 1.0, "step": 0.005}       # unit/orb per-px dim w/ distance

var _scene: Node   # FormationScene (source of the slug defaults)


func setup(scene: Node) -> void:
	panel_title = "Formation Placement"
	panel_category = Category.DESIGNER
	_scene = scene
	_build_ui()


## Re-point at a NEW scene without rebuilding the UI — the same shape as
## `SkirtDebugPanel.rebind` (#555), and for the same reason: the host's installer keeps one
## panel alive across scene reloads (#1267), so the rows must outlive the scene that seeded
## them. Only the SEED values came off `_scene`; every row's live value comes from the
## `formation.*` slug, so nothing on screen goes stale by not rebuilding.
func rebind(scene: Node) -> void:
	_scene = scene


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(320, 0)
	add_child(root)
	if _scene == null:
		add_label(root, "No FormationScene bound.")
		return

	add_section_title(root, "Body")
	_scalar(root, "scale", "body_scale", _SCALE)
	_vec2(root, "feet target", "feet_target_px", _POS)

	add_separator(root)
	add_section_title(root, "Drop shadow  (offset = centre rel. to feet; +Y=down)")
	_vec2(root, "offset", "shadow_feet_offset_px", _OFF)
	_vec2(root, "size", "shadow_size_px", _SIZE)
	_scalar(root, "intensity", "shadow_intensity", _UNIT)

	add_separator(root)
	add_section_title(root, "Gold box  (level <1 keeps the gradient / falloff)")
	_vec2(root, "centre", "box_center_px", _POS)
	_scalar(root, "add level", "box_add_level", _LEVEL)
	_scalar(root, "sub level", "box_sub_level", _LEVEL)
	_scalar(root, "emboss dy (shadow down)", "box_emboss_dy", _OFF)

	add_separator(root)
	add_section_title(root, "Floor spotlight  (oval pool on the selected unit — §14.6.3)")
	_scalar(root, "base (centre bright)", "floor_spot_base", _UNIT)
	_scalar(root, "min (far-floor dark)", "floor_spot_min", _UNIT)
	_scalar(root, "swing (size — per-px falloff)", "floor_spot_swing", _SWING)
	_scalar(root, "vfac (H:V shape — 4=2:1 wide)", "floor_spot_vfac", _VFAC)

	add_separator(root)
	add_section_title(root, "Unit / orb lighting  (far sprites dim — §16 body falloff)")
	_scalar(root, "dim (per-px falloff w/ distance)", "orb_falloff_scale", _DIM)


# --- TuneField rows (view onto the formation.* slugs the scene owns) -------------

func _scalar(parent: Control, label_text: String, prop: String, hint: Dictionary) -> void:
	TuneField.add(parent, label_text, "formation." + prop, _scene.get(prop), hint)


func _vec2(parent: Control, label_text: String, prop: String, hint: Dictionary) -> void:
	var v: Vector2 = _scene.get(prop)
	TuneField.add(parent, label_text + " X", "formation.%s_x" % prop, v.x, hint)
	TuneField.add(parent, label_text + " Y", "formation.%s_y" % prop, v.y, hint)
