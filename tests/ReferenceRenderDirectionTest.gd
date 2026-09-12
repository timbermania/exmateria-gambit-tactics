extends Node
## Phase-0 runtime render-direction oracle (issue #137, ADR-0057).
##
## The parser goldens (tools/test_reference_goldens.py) lock the *stored*
## Placement + Orientation. This locks the *Render* class: the runtime-only
## function that turns a unit's raw spawn facing (an orientation direction) plus
## the live camera into what the viewer sees (a render direction). It is the
## anti-regression oracle that Phase 1 (#138, one converter / derived views)
## must keep GREEN.
##
## For each render-reference scene it replays the exact runtime spawn->render
## pipeline on that scene's committed ENTD facings, per unique raw facing:
##
##     angle    = PsxNum.warp_facing_to_12bit(facing_raw)   # spawn seed
##     face_dir = AnimationStateController.angle_12bit_to_facing(angle)
##     variant  = asc.get_camera_variant(face_dir, quad)    # per camera quad
##     octant   = AnimationStateController.get_pose_octant(angle, cam_angle)
##
## and asserts the whole table byte-matches the committed expectation golden.
## No scenario is booted - the converters are pure functions of (facing, camera),
## so replaying them here is faithful AND deterministic (a booted cinematic
## re-orients its cast within the first instructions - spawn facing is transient
## there, which is exactly why chapel is orientation-blind).
##
## Roster (the three scenes the acceptance criterion names):
##   chapel  scn 1  facings {0,3} - ORIENTATION-BLIND regression guard, NEVER a
##                  facing-calibration reference (ADR-0057).
##   orbonne scn 4  facings {0,2} - the enemies-West / knights-East pair.
##   academy scn 8  facings {0,1,2,3} - the only scene exercising 1 and 3, the
##                  values the 0<->2 swap leaves untouched.
##
## The pose-octant tuning knob (DebugConfig.pose_octant_camera_offset_12bit,
## a live Render calibration) is pinned to a FIXED reference here so the golden
## captures the CONVERTER, not the knob - isolating exactly what #138 touches.
##
## Run headful; reads stdout; auto-quits. Pass `-- --record` to (re)write the
## committed expectation golden from current behavior.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationStateController = ExMateriaSpriteRig.AnimationStateController

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const PsxNum = ExMateriaPlatform.PsxNum

const Facing = ExMateriaSchema.Facing.Direction
const GOLDEN_PATH := "res://tests/goldens/reference_render_directions.json"

# The parser goldens are the single source of truth for each scene's ENTD.
const SCENE_GOLDENS := {
	"chapel": "res://tools/goldens/reference_scenes/chapel_scn0001.golden.json",
	"orbonne": "res://tools/goldens/reference_scenes/orbonne_scn0004.golden.json",
	"academy": "res://tools/goldens/reference_scenes/academy_scn0008.golden.json",
}

# Fixed pose-octant offset for a knob-independent snapshot (see class doc).
const POSE_OCTANT_OFFSET := 0

# The four cardinal PSX camera angles the octant is sampled at.
const CAM_ANGLES := [0x000, 0x400, 0x800, 0xC00]

const FACING_NAME := {
	Facing.NORTH: "NORTH", Facing.EAST: "EAST",
	Facing.SOUTH: "SOUTH", Facing.WEST: "WEST",
}


func _ready() -> void:
	# THE SCENE GOLDENS ARE THIS TEST'S WHOLE INPUT, and a standalone clone does not
	# ship them: they hold the `{19}` Camera operands byte-exact plus MAP062/004/008's
	# terrain grids, so `export_standalone.py` excludes them as Square Enix data
	# (register step 9, the user's "no square assets" ruling). Unlike the walk
	# fixtures they ARE regenerable from the reader's own ISO -- `uv run python
	# tools/gen_reference_goldens.py` -- so this is a bootstrap step a clone has not
	# run, and a skip says that where a red would not.
	#
	# CHECKED HERE, BEFORE `_observe`, because of how it would fail otherwise. There
	# is no fixture-free arm to preserve -- every scene comes out of these files --
	# and `_load_json` returns `{}` for an absent path, so `g["entd"]` would raise a
	# GDScript error, which ABORTS `_observe` and returns the type default. The test
	# would then score its empty observation against the committed expectation and
	# report a DIFF: a missing input arriving as a wrong answer, in the one test whose
	# job is to notice when directions change.
	var absent: Array = []
	for role in SCENE_GOLDENS:
		if not FileAccess.file_exists(SCENE_GOLDENS[role]):
			absent.append(role)
	if not absent.is_empty():
		print("[SKIP] ReferenceRenderDirectionTest — scene goldens absent (%s): "
			% ", ".join(absent)
			+ "excluded from the standalone repo as Square Enix data. Regenerate "
			+ "with tools/gen_reference_goldens.py.")
		get_tree().quit(0)
		return

	# Pin the live Render tuning knob so the golden captures the converter only.
	if DebugConfig:
		DebugConfig.pose_octant_camera_offset_12bit = POSE_OCTANT_OFFSET

	var asc := AnimationStateController.new()
	var observed := _observe(asc)
	asc.free()

	var record := "--record" in OS.get_cmdline_user_args()
	if record:
		_write_golden(observed)
		print("[PASS] recorded render-direction golden (%d scenes)" % observed["scenes"].size())
		get_tree().quit()
		return

	_assert_against_golden(observed)


# --- observation ------------------------------------------------------------

func _observe(asc: AnimationStateController) -> Dictionary:
	var scenes := {}
	for role in SCENE_GOLDENS:
		var g := _load_json(SCENE_GOLDENS[role])
		var facings := {}
		# unique raw facings, ascending, from this scene's committed ENTD units
		var seen := {}
		for unit in g["entd"]["units"]:
			seen[int(unit["spawn_facing"])] = true
		var keys := seen.keys()
		keys.sort()
		for raw in keys:
			facings[str(raw)] = _observe_facing(asc, int(raw))
		scenes[role] = {
			"scenario_id": int(g["scenario_id"]),
			"facings": facings,
		}
	return {
		"pose_octant_offset": POSE_OCTANT_OFFSET,
		"scenes": scenes,
	}


func _observe_facing(asc: AnimationStateController, facing_raw: int) -> Dictionary:
	var angle := PsxNum.warp_facing_to_12bit(facing_raw)
	var face_dir: int = AnimationStateController.angle_12bit_to_facing(angle)
	var variant_by_quad := []
	for quad in range(4):
		var v: Dictionary = AnimationStateController.get_camera_variant(face_dir, quad)
		variant_by_quad.append({
			"use_back": bool(v["use_back"]),
			"revert": bool(v["revert"]),
		})
	var octant_by_cam := {}
	for cam in CAM_ANGLES:
		octant_by_cam[str(cam)] = AnimationStateController.get_pose_octant(angle, cam)
	return {
		"angle": angle,
		"facing_dir": FACING_NAME[face_dir],
		"variant_by_quad": variant_by_quad,
		"octant_by_cam": octant_by_cam,
	}


# --- assertion --------------------------------------------------------------

func _assert_against_golden(observed: Dictionary) -> void:
	if not FileAccess.file_exists(GOLDEN_PATH):
		print("[FAIL] expectation golden missing: %s (run with -- --record)" % GOLDEN_PATH)
		get_tree().quit()
		return

	var expected := _load_json(GOLDEN_PATH)
	var failures: Array = []
	var checks := 0

	if int(expected.get("pose_octant_offset", -999)) != POSE_OCTANT_OFFSET:
		failures.append("pose_octant_offset drift: golden=%s test=%d"
			% [expected.get("pose_octant_offset"), POSE_OCTANT_OFFSET])

	for role in SCENE_GOLDENS:
		var exp_scene: Dictionary = expected["scenes"].get(role, {})
		var obs_scene: Dictionary = observed["scenes"][role]
		var exp_f: Dictionary = exp_scene.get("facings", {})
		var obs_f: Dictionary = obs_scene["facings"]
		if exp_f.keys().size() != obs_f.keys().size():
			failures.append("%s: facing-set changed golden=%s observed=%s"
				% [role, exp_f.keys(), obs_f.keys()])
		for raw in obs_f:
			checks += 1
			var e: Variant = exp_f.get(raw, null)
			if e == null:
				failures.append("%s facing %s: absent from golden" % [role, raw])
				continue
			var mism := _compare_facing(e, obs_f[raw])
			if mism != "":
				failures.append("%s facing %s: %s" % [role, raw, mism])

	if failures.is_empty():
		print("[PASS] render-direction oracle green (%d facing rows across %d scenes)"
			% [checks, SCENE_GOLDENS.size()])
	else:
		for f in failures:
			print("  MISMATCH: %s" % f)
		print("[FAIL] render-direction oracle: %d mismatch(es) — a Render-class "
			% failures.size()
			+ "transform changed. If intentional (e.g. #138), re-record: -- --record")
	get_tree().quit()


func _compare_facing(e: Dictionary, o: Dictionary) -> String:
	if int(e["angle"]) != int(o["angle"]):
		return "angle %s!=%s" % [e["angle"], o["angle"]]
	if str(e["facing_dir"]) != str(o["facing_dir"]):
		return "facing_dir %s!=%s" % [e["facing_dir"], o["facing_dir"]]
	var eq: Array = e["variant_by_quad"]
	var oq: Array = o["variant_by_quad"]
	for i in range(4):
		if bool(eq[i]["use_back"]) != bool(oq[i]["use_back"]) \
				or bool(eq[i]["revert"]) != bool(oq[i]["revert"]):
			return "variant@quad%d %s!=%s" % [i, eq[i], oq[i]]
	for cam in CAM_ANGLES:
		var k := str(cam)
		if int(e["octant_by_cam"][k]) != int(o["octant_by_cam"][k]):
			return "octant@cam%s %s!=%s" % [k, e["octant_by_cam"][k], o["octant_by_cam"][k]]
	return ""


# --- io ---------------------------------------------------------------------

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("cannot open %s" % path)
		return {}
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)


func _write_golden(observed: Dictionary) -> void:
	observed["_note"] = "Phase-0 render-direction oracle (#137, ADR-0057). " \
		+ "Regenerate: godot --path . res://tests/ReferenceRenderDirectionTest.tscn -- --record"
	var f := FileAccess.open(GOLDEN_PATH, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % GOLDEN_PATH)
		return
	f.store_string(JSON.stringify(observed, "  ", true) + "\n")
	f.close()
	print("wrote %s" % GOLDEN_PATH)
