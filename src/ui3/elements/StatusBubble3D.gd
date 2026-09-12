class_name StatusBubble3D
extends Node3D
## Over-unit status / charge bubble (ADR-0063, issue #90).
##
## A persistent, camera-facing 3D billboard that floats above a unit to show its
## current status effect or its charging state. Unlike [DamageNumber3D] (a
## transient map-anchored pop), this belongs to the LIVING unit, so it is a
## unit-CHILD billboard — it despawns with its parent (ADR-0063 "over-unit
## ownership splits by lifetime").
##
## Same rendering seam as the damage number: CUSTOM0 Ordering-Table depth
## (ADR-0009), `combat_visuals` group (ADR-0037 freeze), drawn from one 14x12
## status-icon cell of the RANGETILE atlas (#88) via [RangeTileAtlas].
##
## Observation-only: the icon index is chosen from the unit's snapshot status /
## GPU charge state by [FeedbackHudManager]; this node just renders whichever
## cell it is handed.

const SHADER_PATH := "res://assets/shaders/feedback_hud_sprite.gdshader"

# Icon cells are 14x12 atlas px; ICON_SIZE world units tall, aspect preserved.
const ICON_SIZE := 0.30
const ATLAS_SIZE := 256.0
const TINT := Color(1.0, 1.0, 1.0)     # icons carry their own atlas shading

static var _atlas: RangeTileAtlas = null

var _material: ShaderMaterial = null
var _mesh_inst: MeshInstance3D = null
var _icon_index: int = -1


static func _shared_atlas() -> RangeTileAtlas:
	if _atlas == null:
		_atlas = RangeTileAtlas.new()
	return _atlas


func _ready() -> void:
	add_to_group("combat_visuals")
	position.y = raise_for_unit(get_parent())
	_build_quad()
	visible = false


## The bubble's local Y for the unit it hangs over — NOT a constant. It is the ROM's
## per-sprite-type carousel height (`unit[+0x2DF]`), resolved through
## [RangeTileAtlas.overhead_offset_for_sprite]. `unit_sprite_poly_builder` (`0x8007EEC0`)
## picks the cell for whichever carousel slot is current — the AT marker's slot 21 and
## these twenty status icons alike — and every one of those branches converges on
## `LAB_8007F088` before the height is read, with no slot test in between. So a Chocobo's
## bubble hangs at -50 and a KANZEN's at -120 where one constant put every unit at -40.
##
## Read ONCE, at mount: the ROM re-evaluates on each carousel advance, but the bubble is
## rebuilt whenever its unit is. Static and pure so a test can prove it DISCRIMINATES (a
## monster and a human must not agree) without mounting anything.
static func raise_for_unit(unit: Node) -> float:
	var sprite_id: int = unit.body_sprite_id if unit != null and "body_sprite_id" in unit else -1
	var off := _shared_atlas().overhead_offset_for_sprite(sprite_id)
	return RangeTileAtlas.overhead_raise_for_offset(off)


## Show the RANGETILE status-icon cell `index` (0..19). Idempotent: re-setting
## the same index is a no-op so the manager can call it every frame.
func set_icon(index: int) -> void:
	if index == _icon_index and visible:
		return
	_icon_index = index
	var atlas := _shared_atlas()
	if index < 0 or index >= atlas.status_icon_count():
		visible = false
		return
	var rect: Rect2 = atlas.status_icon_rect(index)
	if _material:
		_material.set_shader_parameter("cell",
				Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	visible = true


## Hide the bubble (no active status / charge).
func clear() -> void:
	_icon_index = -1
	visible = false


func current_icon() -> int:
	return _icon_index if visible else -1


func _build_quad() -> void:
	_mesh_inst = MeshInstance3D.new()
	add_child(_mesh_inst)

	# A unit quad (UV 0..1); the shader remaps it into the icon cell. Width keeps
	# the 14x12 aspect.
	var half_h := ICON_SIZE * 0.5
	var half_w := ICON_SIZE * (14.0 / 12.0) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-half_w, half_h, 0))
	st.set_uv(Vector2(0, 1)); st.add_vertex(Vector3(-half_w, -half_h, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(half_w, -half_h, 0))
	st.set_uv(Vector2(0, 0)); st.add_vertex(Vector3(-half_w, half_h, 0))
	st.set_uv(Vector2(1, 1)); st.add_vertex(Vector3(half_w, -half_h, 0))
	st.set_uv(Vector2(1, 0)); st.add_vertex(Vector3(half_w, half_h, 0))
	_mesh_inst.mesh = st.commit()

	var atlas := _shared_atlas()
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH)
	_material.set_shader_parameter("index_atlas", atlas.texture)
	_material.set_shader_parameter("cell", Vector4(0.0, 0.0, 14.0, 12.0))
	_material.set_shader_parameter("atlas_size", Vector2(ATLAS_SIZE, ATLAS_SIZE))
	_material.set_shader_parameter("tint", Vector3(TINT.r, TINT.g, TINT.b))
	_material.set_shader_parameter("fade", 1.0)
	_mesh_inst.material_override = _material
