extends Node3D

## Standalone headful harness for the unit-detail / Status screen (§15).
##
## Mounts a [DetailScene] bound to a default Ramza (Squire), plays the §15.17
## box-open once, and settles. A thin iteration vehicle (NOT a test) — it wires a
## Character's vitals view into the screen so the composition can be eyeballed
## against the oracle.
##
## Run: <GODOT> --path . res://assets/scenes/DetailScreen.tscn

const DetailSceneClass = preload("res://src/ui3/detail/DetailScene.gd")
const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const Character = ExMateriaCatalogue.Character
# In-game the detail screen opens OVER the formation / world view, so the SUBTRACTIVE
# vitals band (§14.6.6) darkens that floor and shows it through (dark-transparent, not
# solid black). This standalone harness renders on a flat scene, so mount a cobble floor
# behind the UI to preview the band faithfully. (NOT part of DetailScene — the integrated
# screen already has the real world behind it.)
const _BG_SHADER := "res://src/ui3/shaders/formation_background.gdshader"
const _BG_ASSET_DIR := "res://assets/ui/formation/"


func _ready() -> void:
	_build_preview_backdrop()

	var c: Character = Character.create_default("Ramza", "4a", false)
	c.progression.brave = 70
	c.progression.faith = 70

	var detail: DetailScene = DetailSceneClass.new()
	detail.name = "DetailScreen"
	add_child(detail)
	detail.set_unit_view(FormationScene.vitals_view_from_character(c))
	detail.set_nameplate_view(UIUnitNameplate.view_from_character(c, 1))
	detail.set_stats_view(DetailSceneClass.stats_view_from_character(c))

	print("[DetailScreen] mounted for %s (%s); box-open playing" %
		[c.display_name, c.progression.current_job_id])


## Full-screen cobble floor behind the UI — the world the detail screen opens over. The
## SUBTRACTIVE vitals band = clamp(cobble − 120, 0), so its look is background-driven: the
## selected unit's formation spotlight sits on THAT unit, not on the top-left vitals HUD, so the
## cobble behind the vitals is UNLIT and the band crushes to black (oracle fb_ss9, the typical
## case). The preview reproduces that: spotlight down-right (a deployed unit), top-left dark.
func _build_preview_backdrop() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(256.0, 240.0) * 0.04
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(q.size.x * 0.5, -q.size.y * 0.5, 0.0)
	var mat := ShaderMaterial.new()
	mat.shader = load(_BG_SHADER)
	mat.set_shader_parameter("index_atlas", load(_BG_ASSET_DIR + "BACKGROUND.tga"))
	mat.set_shader_parameter("palette_tex", load(_BG_ASSET_DIR + "BACKGROUND.palette.tga"))
	mat.set_shader_parameter("tile_px", Vector2(128.0, 32.0))
	mat.set_shader_parameter("screen_px", Vector2(256.0, 240.0))
	# Spotlight on the deployed unit (down-right), NOT the vitals HUD — so the top-left cobble is
	# unlit (~0.46 floor) and the subtractive band reads black there, as in the game (fb_ss9).
	mat.set_shader_parameter("spot_center_px", Vector2(196.0, 190.0))
	mat.set_shader_parameter("spot_base", 1.6)
	mat.set_shader_parameter("spot_swing", 0.0068)
	mat.set_shader_parameter("spot_min", 0.46)
	mat.set_shader_parameter("spot_vfac", 4.0)
	mat.render_priority = -10
	mi.material_override = mat
	add_child(mi)
