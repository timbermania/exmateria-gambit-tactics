extends Node3D

## #745 — EXERCISE THE TWO DIALOGUE-BOX CROSSING SITES WITH THE RIG NODE RENAMED.
##
## ADR-0217 dec. 18 renamed `UnitMesh` and observed that the lookup returns `null` with
## zero engine diagnostic. `tools/check_mount_node_paths.py`'s header goes one step
## further and says what the null COSTS: both `ScenarioDialogueBoxPool` sites carry an
## `if == null` fallback to `speaker.global_position`, so the box does not disappear —
## its anchor moves. The quoted size of that move is "~65-76 px". THAT NUMBER WAS NEVER
## MEASURED ON A RENAME: it is the size of two decode defects (§8.2's ~18 px PAR drift
## and §9.6's 76 px carry-pose stranding) that the twenty lines of comment around
## `_place_box_on_unit` exist to prevent. #745's criterion is that the mis-anchor be
## reproducible BEFORE the guard arm is trusted, so this probe measures it.
##
## Both crossings are exercised on a REAL `assets/scenes/Unit.tscn` instance — the
## declared mount — against a real `ScenarioVM`, its real box pool and a real
## `DialogueBox`, twice: once with the mount's node names intact and once with `UnitMesh`
## renamed at runtime. Nothing is replicated; the pool's own methods are called.
##
##   crossing A   ScenarioDialogueBoxPool.gd:728  `_sprite_billboard_anchor`
##   crossing B   ScenarioDialogueBoxPool.gd:517  inside `_place_box_on_unit`
##
## Run headful (NEVER --headless):
##     godot --path . --quit-after 20 res://tools/probe_box_anchor_rename.tscn
##
## Every line is prefixed `[anchor]`.

const VMClass := preload("res://src/scenarios/ScenarioVM.gd")
const BoxClass := preload("res://src/ui3/assemblies/DialogueBox.gd")
const CHUNK_JSON := "res://assets/scenarios/scenario_1_chunk.json"
const UNIT_SCENE := "res://assets/scenes/Unit.tscn"
const REF_ORTHO := 12.6          # DIALOG_BOX_REF_ORTHO, so box_scale == 1
const DIALOG_BYTE := 0x10        # a boxed dialog byte (align 0, portrait region)

var _cam: Camera3D
var _vm: Node
var _box: Node3D
var _unit: Node3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = REF_ORTHO
	_cam.position = Vector3(0.0, 8.0, 14.0)
	add_child(_cam)
	_cam.look_at(Vector3(2.0, 1.0, 3.0), Vector3.UP)
	_cam.current = true

	_vm = VMClass.new()
	add_child(_vm)
	var loaded: bool = _vm.load_chunk_json(CHUNK_JSON)
	print("[anchor] chunk loaded=%s  box_pool=%s" % [str(loaded), str(_vm.box_pool != null)])

	_box = BoxClass.new()
	_cam.add_child(_box)
	_vm.box_pool.dialogue_box = _box

	var packed: PackedScene = load(UNIT_SCENE) as PackedScene
	_unit = packed.instantiate() as Node3D
	add_child(_unit)
	_unit.global_position = Vector3(2.0, 0.0, 3.0)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

	var mesh: Node3D = _unit.get_node_or_null("UnitMesh") as Node3D
	print("[anchor] speaker=%s at %s   UnitMesh=%s at %s" % [
		_unit.name, str(_unit.global_position),
		"MISSING" if mesh == null else mesh.name,
		"-" if mesh == null else str(mesh.global_position)])
	var pool0: Object = _vm.box_pool
	print("[anchor] pool anchor_to_billboard=%s anchor_quad_frac_y=%s box_size_scale=%s" % [
		str(pool0.get("anchor_to_billboard")), str(pool0.get("anchor_quad_frac_y")),
		str(pool0.get("box_size_scale"))])
	if mesh != null:
		print("[anchor] mesh local pos=%s scale=%s   Tune render.unit_y_lift=%s" % [
			str(mesh.position), str(mesh.scale), str(Tune.get_value("render.unit_y_lift"))])

	var before := _measure("present")

	# ARM 2 — the same reading with the DRAWN SPRITE DISPLACED from the unit origin.
	# This is what the crossing exists for: `mesh.global_position` and
	# `speaker.global_position` are the same point on a resting unit, so a fallback to
	# the second is only wrong when the mesh has been moved off the origin. The
	# displacement is SYNTHETIC and labelled as such — 2.285 tiles is scenario_1 #273's
	# `-64u` carry-pose Sprite Move expressed in tiles (the 28-unit divisor), the same
	# number `ScenarioSpriteMoveTest` pins.
	if mesh != null:
		mesh.position = Vector3(-64.0 / 28.0, 0.5, 0.0)
	await get_tree().process_frame
	var displaced := _measure("displaced")
	# The rename. ADR-0217 dec. 18's experiment, done to the LIVE mount rather than to
	# the scene file, so the same instance answers both readings.
	var m: Node3D = _unit.get_node_or_null("UnitMesh") as Node3D
	if m != null:
		m.name = "UnitMeshRENAMED"
	print("[anchor] --- renamed UnitMesh -> UnitMeshRENAMED (no engine diagnostic above this line) ---")
	await get_tree().process_frame
	var after := _measure("renamed")

	print("[anchor] ===== RESTING SPRITE (mesh at the unit origin) =====")
	_report(before, after)
	print("[anchor] ===== DISPLACED SPRITE (mesh moved off the unit origin) =====")
	_report(displaced, after)
	print("[anchor] DONE")
	get_tree().quit()


## One reading of BOTH crossings. Returns {"anchor": Vector3, "box": Vector3, ...}.
func _measure(label: String) -> Dictionary:
	var pool: Object = _vm.box_pool
	# crossing A — the pool's own method, called directly.
	var anchor: Vector3 = pool.call("_sprite_billboard_anchor", _cam, _unit)
	# crossing B — the whole placement, driven through the pool exactly as the VM does.
	pool.call("_place_box_on_unit", _cam, _unit, DIALOG_BYTE, _box)
	var box_pos: Vector3 = _box.position
	if _box.has_method("get_base_position"):
		box_pos = _box.get_base_position()
	print("[anchor] %-8s A anchor(cam-local)=%s   B box base=%s" % [
		label, str(anchor), str(box_pos)])
	return {"anchor": anchor, "box": box_pos}


## World -> native px, using the pool's own scales so the number is in the frame the
## placement solver works in (256x240).
func _report(before: Dictionary, after: Dictionary) -> void:
	var pool: Object = _vm.box_pool
	var par := 1.25
	if PSXDisplay != null:
		par = PSXDisplay.live_ui_par
	var ppu := 0.04
	if "pixels_per_unit" in _box:
		ppu = _box.pixels_per_unit
	var box_scale: float = (_cam.size / REF_ORTHO) * maxf(0.01, pool.get("box_size_scale"))
	var wpp_x: float = par * ppu * box_scale
	var wpp_y: float = ppu * box_scale
	print("[anchor] scales par=%.4f ppu=%.4f box_scale=%.4f  wpp_x=%.5f wpp_y=%.5f" % [
		par, ppu, box_scale, wpp_x, wpp_y])

	var da: Vector3 = (after["anchor"] as Vector3) - (before["anchor"] as Vector3)
	var db: Vector3 = (after["box"] as Vector3) - (before["box"] as Vector3)
	print("[anchor] crossing A  Δworld=%s  Δnative_px=(%.1f, %.1f)" % [
		str(da), da.x / wpp_x, -da.y / wpp_y])
	print("[anchor] crossing B  Δworld=%s  Δnative_px=(%.1f, %.1f)" % [
		str(db), db.x / wpp_x, -db.y / wpp_y])
	var moved: bool = db.length() > 0.0001
	print("[anchor] VERDICT the box %s when the mount node is renamed — total %.1f native px" % [
		"MOVED SILENTLY" if moved else "did not move",
		Vector2(db.x / wpp_x, db.y / wpp_y).length()])
