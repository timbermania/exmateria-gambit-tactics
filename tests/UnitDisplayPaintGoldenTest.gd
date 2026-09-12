extends Node
# test-kind: logic
# seeded-break: UnitDisplay._paint_body_variant's idle branch reads the pose-octant mirror bit as 0x04 instead of 0x02 (apply_reversion = (mirror_bit & 0x04) != 0) — inverts the idle reversion decision; 16 anim0 cells golden rev=1 mismatch (got rev=0), the other 176 cells (idle no-mirror-octants, walk/kneel/attack/react, both frame samples) stay green; GREEN unbroken on the reverted tree
## C4 — UnitDisplay paint unit test (issue #144). The payoff of the extraction.
##
## Born as the C0 characterization golden (scene-based safety net for C1→C3b);
## now that the painters are a pure function of `(intent, view)` behind the
## UnitDisplay seam, this drives `UnitDisplay` DIRECTLY — no live scene, no
## Camera3D, no `CameraRelativeRenderer`, no `PlayerCamera`, no
## `PSXDisplay.live_camera_angle` mirror. The exact same golden JSON is the
## oracle: keeping it byte-identical through the conversion proves the seam moved
## the painting complex without changing one resolved tuple.
##
## It pins the resolved paint output — the exact
## `(layer, frame_id, first, reversion, palette, v_offset)` tuples the painters
## push to `SpriteLayerManager.load_frame_by_id` — across a matrix of
## `(anim intent × facing × camera × anim_frame × react on/off)`.
##
## Mechanism (all scene-free):
##   * The fixture is a bare `Unit.new()` (the `_unit` back-ref UnitDisplay is
##     typed on) populated with ONLY what the painters read: a real
##     `animation_set` (pure `AnimationDatabase` lookup), the real unit shader
##     `material` (loaded + duplicated, no mesh/scene wiring), a recording
##     `SpyLayers` for `sprite_layers`, `_initialized = true`, and an equipped
##     progression so ATTACK has a real WEP1 secondary + weapon caches. No
##     `_ready`, no `AnimationStateController`, no camera nodes.
##   * A recording `SpyLayers` (extends SpriteLayerManager) is the unit's
##     `sprite_layers`. The painters read NOTHING back from the layer manager
##     (they compute the frame from the playback + animation_set), so a
##     record-only manager faithfully captures the resolution. The spy shares the
##     unit's real material, so `reversion` / `palette` read back as the shader
##     params the painter set immediately before each load.
##   * The view (facing + camera quadrant + PSX pose angle) is PUSHED IN per cell
##     via `display.set_view({...})` — the C2b interface — instead of derived
##     from a live camera. This is the extraction payoff: paint no longer reaches
##     for a camera or a global.
##   * `anim_frame` is set directly on each playback per cell (the painter reads
##     it), so each cell is a deterministic function of its inputs — no ticking,
##     no accumulation, no _process interleave (the sweep is fully synchronous).
##
## Run headful; reads stdout; auto-quits. Pass `-- --record` to (re)write the
## committed golden from current behavior.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const UnitDisplay = ExMateriaSpriteRig.UnitDisplay
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager
const AnimationResolutionMap = ExMateriaSpriteRig.AnimationResolutionMap

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

const GOLDEN_PATH := "res://tests/goldens/unit_display_paint_golden.json"
const UnitProgressionClass = ExMateriaAlmanac.UnitProgression

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase
const ReactionType = ExMateriaAlmanac.ReactionType

# Proven fixture (shared with UnitEffectCleanupOnStateChangeTest): female Chemist
# with a Blaze Gun, so the ATTACK intent has a real WEP1 secondary to paint.
const JOB := "4b"
const WEAPON := 74
const IS_FEMALE := true

# Pin the pose-octant calibration knob so the golden captures the PAINTER, not a
# live tuning value (mirrors ReferenceRenderDirectionTest).
const POSE_OCTANT_OFFSET := 0

# One realistic camera per quadrant: (expected quad, matching PSX 12-bit pose
# angle). The view is pushed straight in, so only the quadrant + PSX angle the
# painter consumes are needed (no live yaw). The angles are yaw mapped onto the
# 0x000..0xFFF wheel (yaw/360*4096) for yaw 315/225/135/45.
const CAMERAS := [
	{"quad": 0, "psx": 0xE00},
	{"quad": 1, "psx": 0xA00},
	{"quad": 2, "psx": 0x600},
	{"quad": 3, "psx": 0x200},
]

# FacingDirection: NORTH, EAST, SOUTH, WEST.
const FACINGS := [0, 1, 2, 3]
const FACING_NAME := ["N", "E", "S", "W"]

# anim_frame samples: frame 0 (start) + a few in, to exercise opcode progression.
const FRAME_SAMPLES := [0, 2]

# Body anim-id intents fed through `display.play_body` (the ADR-0053 funnel).
# 0=idle pose-octant; 3=chapel at-ease tent; 15=walk; 37=kneel (CASE B). Each is
# skipped (recorded as "unarmed") if the fixture's SEQ table has no slot for it,
# so the golden is stable across sprites.
const BODY_ANIMS := [0, 3, 15, 37]


# --- recording spy -----------------------------------------------------------

## Records every resolved load_frame_by_id call plus the view-derived shader
## state (reversion / palette / v_offset) the painter set immediately before it.
## Shares the unit's real material so those read back as the exact params pushed.
class SpyLayers extends SpriteLayerManager:
	var calls: Array = []

	func load_frame_by_id(layer: SpriteLayer, frame_id: int, is_first_frame: bool = false) -> void:
		var d := {
			"layer": int(layer),
			"frame_id": int(frame_id),
			"first": 1 if is_first_frame else 0,
			"rev": 1 if _flag("global_reversion") else 0,
			"body_pal": _int("body_palette_row"),
		}
		if int(layer) == int(SpriteLayer.WEP1):
			d["wep_pal"] = _int("wep1_palette_row")
			d["wep_voff"] = int(wep1_v_offset_pixels)
		calls.append(d)

	func clear() -> void:
		calls.clear()

	func _flag(param: String) -> bool:
		return material != null and bool(material.get_shader_parameter(param))

	func _int(param: String) -> int:
		if material == null:
			return 0
		var v: Variant = material.get_shader_parameter(param)
		return int(v) if v != null else 0


# --- entry -------------------------------------------------------------------

func _ready() -> void:
	DebugConfig.iteration_debug_enabled = false
	if DebugConfig:
		DebugConfig.pose_octant_camera_offset_12bit = POSE_OCTANT_OFFSET

	var unit = _make_unit()
	if unit == null:
		print("[FAIL] UnitDisplayPaintGolden: fixture failed to initialize")
		get_tree().quit()
		return

	var spy: SpyLayers = unit.sprite_layers
	var observed := _sweep(unit, spy)
	spy.free()
	unit.free()

	if "--record" in OS.get_cmdline_user_args():
		_write_golden(observed)
		print("[PASS] recorded UnitDisplay paint golden (%d cells)" % observed["cells"].size())
		get_tree().quit()
		return

	_assert_against_golden(observed)


# --- fixture -----------------------------------------------------------------
#
# A bare `Unit.new()` (no `_ready`, no scene) holding ONLY the state the painters
# read. UnitDisplay is typed on `Unit`, so the back-ref host must be a Unit; we
# hand-run the pure init steps `_ready` would (animation set + material + weapon
# caches) and skip everything scene-bound (mesh, camera, state controller).

func _make_unit():
	var unit := Unit.new()
	unit.name = "PaintGoldenFixture"
	unit.body_sprite_id = JobDatabase.get_sprite_id(JOB, IS_FEMALE)

	# Real animation set — a pure AnimationDatabase lookup keyed off the sprite.
	if not unit._initialize_animation_set():
		return null

	# Real unit shader material (duplicated per-unit, as _initialize_materials
	# does) minus the mesh/sprite-layer wiring the painters don't touch. The spy
	# shares it so reversion/palette read back as the params the painter pushed.
	var mat := UnitAssets.base_material().duplicate()
	unit.material = mat

	# Record-only stand-in for SpriteLayerManager.
	var spy := SpyLayers.new()
	spy.material = mat
	unit.sprite_layers = spy

	unit._initialized = true

	# Equip the Blaze Gun so ATTACK resolves a real WEP1 secondary, and push the
	# weapon render caches (frame offset / palette row / v_offset) through the real
	# `update_weapon_sprite` → `display.set_weapon` path — same source of truth as
	# production, so the recorded wep_pal/wep_voff match byte-for-byte.
	var prog = UnitProgressionClass.new()
	prog.initialize(UnitProgressionClass.BaseStatType.FEMALE, JOB)
	prog.equipment[UnitProgressionClass.EquipSlot.RIGHT_HAND] = WEAPON
	unit.unit_progression = prog
	unit.update_weapon_sprite()

	# Mirror `_ready`'s final step (Unit.gd:335): resolve + arm the standing IDLE
	# animation. A combat unit (facing_angle == -1) boots into a NON-ZERO idle SEQ
	# slot, so the sweep's first `play_body(0)` is a real transition that arms the
	# idle pose-octant path — without this prime, play_body(0) is idempotent
	# against the default current_anim_id == 0 and anim0 never arms.
	unit.update_animation()

	if unit.animation_set == null or unit.material == null:
		return null
	return unit


# --- the sweep ---------------------------------------------------------------
#
# Fully synchronous — no `await`, no _process — so every cell is a pure function
# of its set inputs.

func _sweep(unit, spy: SpyLayers) -> Dictionary:
	var display = unit.display
	var cells := {}

	# Normal body anim-id intents (idle / at-ease / walk / kneel), via play_body.
	for anim in BODY_ANIMS:
		display._cancel_react_if_active()
		display.play_body(anim)
		var armed: bool = display.type1_playback != null and not display.type1_playback.anim_id.is_empty()
		var tag := "anim%d" % anim
		if not armed:
			cells[tag] = "unarmed"  # no SEQ slot for this anim on this sprite
			continue
		_record_body(unit, spy, cells, tag)

	# ATTACK intent — resolve a weapon swing (WEP1 secondary + body) and drive it
	# through the UnitDisplay seam (apply_resolution), the same call Unit.attack
	# makes. play_body idempotence means re-arming from idle needs a distinct id;
	# the resolution carries it.
	display._cancel_react_if_active()
	var sprite_type: String = unit.get_seq_type()
	var item_type_id: int = unit._equipped_item_type_id(UnitProgressionClass.EquipSlot.RIGHT_HAND)
	var attack_res = AnimationResolutionMap.resolve_attack(sprite_type, item_type_id, 1, false)  # vertical=1 (MID)
	display.apply_resolution(attack_res)
	if display.type1_playback != null and not display.type1_playback.anim_id.is_empty():
		_record_attack(unit, spy, cells, "attack")
	else:
		cells["attack"] = "unarmed"

	# REACT intent — the React set substitutes the body layer.
	display._cancel_react_if_active()
	display.play_body(0)
	var react_seq := _react_seq_id(unit)
	if react_seq >= 0:
		display.play_reaction_animation(react_seq)
	if display._react_active:
		_record_react(unit, spy, cells, "react")
	else:
		cells["react"] = "unarmed"
	display._cancel_react_if_active()

	return {"cells": cells}


func _record_body(unit, spy: SpyLayers, cells: Dictionary, tag: String) -> void:
	var display = unit.display
	for fs in FRAME_SAMPLES:
		display.type1_playback.anim_frame = fs
		_record_views(unit, spy, cells, "%s|f%d" % [tag, fs])


func _record_attack(unit, spy: SpyLayers, cells: Dictionary, tag: String) -> void:
	var display = unit.display
	for fs in FRAME_SAMPLES:
		display.type1_playback.anim_frame = fs
		if display.wep1_playback: display.wep1_playback.anim_frame = fs
		if display.eff1_playback: display.eff1_playback.anim_frame = fs
		_record_views(unit, spy, cells, "%s|f%d" % [tag, fs])


func _record_react(unit, spy: SpyLayers, cells: Dictionary, tag: String) -> void:
	var display = unit.display
	for fs in FRAME_SAMPLES:
		if display.react_playback: display.react_playback.anim_frame = fs
		_record_views(unit, spy, cells, "%s|f%d" % [tag, fs])


## Sweep facing × camera for the current (already-set) intent + anim_frame,
## capturing the spy's recorded calls per cell. The view is PUSHED IN — no live
## camera — so each repaint is a pure function of the pushed orientation.
func _record_views(unit, spy: SpyLayers, cells: Dictionary, prefix: String) -> void:
	var display = unit.display
	for fi in FACINGS.size():
		for c in CAMERAS:
			# facing_angle -1 = combat sentinel (fall back to the cardinal facing),
			# exactly what the scene-based golden's live units carried.
			display.set_view({
				"facing": FACINGS[fi],
				"facing_angle": -1,
				"camera_quadrant": c["quad"],
				"camera_angle_12bit": c["psx"],
			})
			spy.clear()
			display._render_camera_variant()
			cells["%s|%s|q%d" % [prefix, FACING_NAME[fi], c["quad"]]] = spy.calls.duplicate(true)


# Reaction SEQ slot to characterize the React body-substitution path. Prefer the
# sprite's real taking_damage lookup; fall back to the shared TYPE1 taking_damage
# slot (25 → front key "50") when the sprite type has no reaction table entry, so
# the React painter branch is exercised deterministically regardless of fixture.
const REACT_SEQ_FALLBACK := 25

func _react_seq_id(unit) -> int:
	var seq_id: int = ReactionType.get_seq_id(unit.get_seq_type(), "taking_damage")
	if seq_id >= 0 and unit.animation_set.type1_seq.has(str(seq_id * 2)):
		return seq_id
	if unit.animation_set.type1_seq.has(str(REACT_SEQ_FALLBACK * 2)):
		return REACT_SEQ_FALLBACK
	return -1


# --- assertion ---------------------------------------------------------------

func _assert_against_golden(observed: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		print("[FAIL] golden missing: %s (run with -- --record)" % GOLDEN_PATH)
		get_tree().quit()
		return

	var expected := _load_json(GOLDEN_PATH)
	var exp_cells: Dictionary = expected.get("cells", {})
	var obs_cells: Dictionary = observed["cells"]
	var failures: Array = []

	# Key-set parity (a dropped/added cell is a resolution change).
	for k in exp_cells:
		if not obs_cells.has(k):
			failures.append("cell absent from run: %s" % k)
	for k in obs_cells:
		if not exp_cells.has(k):
			failures.append("cell absent from golden: %s" % k)

	for k in obs_cells:
		if not exp_cells.has(k):
			continue
		var mism := _cell_mismatch(exp_cells[k], obs_cells[k])
		if mism != "":
			failures.append("%s: %s" % [k, mism])

	if failures.is_empty():
		print("[PASS] UnitDisplay paint golden green (%d cells)" % obs_cells.size())
	else:
		for f in failures:
			print("  MISMATCH: %s" % f)
		print("[FAIL] UnitDisplay paint golden: %d mismatch(es) — the painter's "
			% failures.size()
			+ "resolution changed. If intentional, re-record: "
			+ "godot --path . res://tests/UnitDisplayPaintGoldenTest.tscn -- --record")
	get_tree().quit()


func _cell_mismatch(exp: Variant, obs: Variant) -> String:
	# "unarmed" marker cells.
	if exp is String or obs is String:
		if str(exp) != str(obs):
			return "arm state %s != %s" % [exp, obs]
		return ""
	var ea: Array = exp
	var oa: Array = obs
	if ea.size() != oa.size():
		return "call count %d != %d" % [ea.size(), oa.size()]
	for i in ea.size():
		var e: Dictionary = ea[i]
		var o: Dictionary = oa[i]
		for key in e:
			if int(e[key]) != int(o.get(key, -0x7fffffff)):
				return "call[%d].%s %s != %s" % [i, key, e[key], o.get(key)]
		# guard against the run adding fields the golden lacks
		for key in o:
			if not e.has(key):
				return "call[%d] extra field %s" % [i, key]
	return ""


# --- io ----------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % path)
		return {}
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)


func _write_golden(observed: Dictionary) -> void:
	observed["_note"] = "C0 characterization golden for the UnitDisplay extraction " \
		+ "(issue #144); converted to the scene-free C4 UnitDisplay unit test. " \
		+ "Regenerate: godot --path . " \
		+ "res://tests/UnitDisplayPaintGoldenTest.tscn -- --record"
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % GOLDEN_PATH)
		return
	f.store_string(JSON.stringify(observed, "  ", true) + "\n")
	f.close()
	print("wrote %s" % GOLDEN_PATH)
