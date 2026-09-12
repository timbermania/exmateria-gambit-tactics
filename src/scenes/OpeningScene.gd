@tool
class_name OpeningScene
extends Node3D
## Opening title screen.
##
## Renders OPNBK1 (the 320x240 main-menu background from FFT OPEN/OPNBK.BIN,
## decoded by tools/parse_opnbk.py) as a fullscreen quad centered on origin.
##
## PAR note: this bg defaults to pixel_aspect_ratio=1.0 even though UI3
## (UIText / UIFrame / UIPortrait) defaults to 1.25 (ADR-0036; PSXDisplay.PAR deleted, ADR-0152). OPNBK1
## was authored in PSX 320-mode, whose pixels are already square on a 4:3
## CRT (320÷4 = 240÷3 = 80 PPI) — the 1.25x CRT stretch only applied to
## 256-mode framebuffers. Forcing PAR=1.25 here would push the quad to
## 5:3 (16×9.6 world units) and overflow the 4:3 viewport's 12.8 width
## by ~32 source pixels per side. UI text we layer on top *does* stretch
## by PAR (it's authored in 256-internal); the visual mismatch between
## un-PAR'd bg and PAR'd text is the price of a CRT-faithful 320-mode bg.

const BACKGROUND_TEXTURE_PATH = "res://assets/ui/opnbk1.png"
const BACKGROUND_WIDTH = 320
const BACKGROUND_HEIGHT = 240

## World units per virtual pixel. Matches UIText / UIFrame default so any
## UI3 content layered into this scene sits at the same scale.
@export var pixels_per_unit: float = 0.04:
	set(value):
		if pixels_per_unit == value:
			return
		pixels_per_unit = value
		_rebuild()

## Pixel aspect ratio. Defaults to 1.0 — see the PAR note in the class doc:
## OPNBK1 is 320-mode native, so the CRT-faithful display has square pixels.
## Set to 1.25 only if you want to match the UI3 stretch (will overflow the
## 4:3 viewport).
@export var pixel_aspect_ratio: float = 1.0:
	set(value):
		if pixel_aspect_ratio == value:
			return
		pixel_aspect_ratio = value
		_rebuild()

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "BackgroundQuad"
		add_child(_mesh_instance)

	if _material == null:
		# psx-ot-depth-exempt: full-screen opening/title background quad, not a battle-OT mesh.
		_material = StandardMaterial3D.new()
		_material.albedo_texture = load(BACKGROUND_TEXTURE_PATH)
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh_instance.material_override = _material

	_rebuild()


func _rebuild() -> void:
	if _mesh_instance == null:
		return
	var w := BACKGROUND_WIDTH * pixel_aspect_ratio * pixels_per_unit
	var h := BACKGROUND_HEIGHT * pixels_per_unit
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	_mesh_instance.mesh = quad
	_mesh_instance.position = Vector3.ZERO
