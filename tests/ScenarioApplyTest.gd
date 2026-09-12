extends Node
## Unit tests for ScenarioApply — the pure apply layer that turns a decoded intent
## into world mutation through [ScenarioWorld] verbs (ADR-0058). Each test drives an
## `ScenarioApply.apply_X(intent, world)` against a [FakeScenarioWorld] and asserts
## WHICH verbs the world received and with WHAT values — the external behavior, not
## a private VM field. No VM, no nodes, no scene: the whole point of the seam.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/ScenarioApplyTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const PsxNum = ExMateriaPlatform.PsxNum

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_warp_places_faces_and_clears_home()
	_test_warp_skips_missing_unit()
	_test_warp_bails_when_placement_fails()
	_test_add_unit_commits_graphic_and_reveals_per_draw()
	_test_draw_unit_shows_erase_unit_hides()
	_test_lifecycle_skips_missing_unit()
	_test_remove_unit_resolves_then_tears_down()
	_test_remove_unit_noops_when_absent()
	_test_add_ghost_unit_registers_under_control_id()
	_test_add_ghost_unit_visibility_follows_draw()
	_test_add_ghost_unit_decodes_facing()
	_test_add_ghost_unit_idempotent_readd()
	_test_sprite_move_fixed_arms_motion_from_home()
	_test_sprite_move_beta_duration()
	_test_sprite_move_clamped_by_playthrough()
	_test_sprite_move_skips_missing_or_immovable()
	_test_walk_to_arms_motion_faces_and_clears_home()
	_test_walk_to_bails_on_empty_plan()
	_test_walk_to_latches_the_seat_level()
	_test_walk_to_latches_the_plans_endpoint_not_the_operand()
	_test_unit_anim_plays_or_skips()
	_test_unit_anim_broadcasts_all()
	_test_march_releases_single_addressed()
	_test_march_broadcasts_team_set()
	_test_march_skips_empty_set()
	_test_unit_anim_rotate_snaps_then_animates()
	_test_rotate_unit_relative_target()
	_test_rotate_unit_broadcasts_player_team()
	_test_face_unit_single_and_mutual()
	_test_face_unit_guards()
	_test_face_unit_broadcasts_affected_team_set()
	_test_face_tile_rotates_affected_to_tile()
	_test_face_tile_guards()
	_test_face_tile_broadcasts_affected_team_set()
	_test_unit_shadow_toggles()
	_test_color_unit_pushes_and_conditionally_clears()
	_test_color_unit_skips_missing()
	_test_color_unit_broadcasts_team_set()
	_test_reset_palette_clears_and_pushes_identity()
	_test_mirror_sprite_latches_and_clears()
	_test_color_field_pushes_and_conditionally_clears()
	_test_map_darkness_sets_state()
	_test_weather_latch()
	_test_dark_screen_show_hide()
	_test_display_conditions()
	_test_show_graphic()
	_test_reveal_floors_time()
	_test_display_message_overlay_and_box()
	_test_display_message_skips()
	_test_change_dialog_close_and_swap()
	_test_load_evtchr()
	_test_use_field_object()
	_test_use_3d_object()
	_test_sound_effect_plays_by_id()
	_test_fade_sound_fades_music()

	print("\n=== ScenarioApplyTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] ScenarioApplyTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] ScenarioApplyTest")
		get_tree().quit(1)
	else:
		print("[PASS] ScenarioApplyTest")
		get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: expected true" % name)


func _near(got: float, want: float, name: String, eps: float = 1e-4) -> void:
	if absf(got - want) <= eps:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%f want=%f" % [name, got, want])


# --- {24} Warp Unit --------------------------------------------------------

func _warp_intent(uid: int, x: int, y: int, facing_12bit: int) -> ScenarioDecode.WarpIntent:
	var intent := ScenarioDecode.WarpIntent.new()
	intent.uid = uid
	intent.psx_x = x
	intent.psx_y = y
	intent.facing_12bit = facing_12bit
	return intent


func _unit_anim_intent(units: int, anim_id: int, flag: int, multi: int = 0) -> ScenarioDecode.UnitAnimIntent:
	var intent := ScenarioDecode.UnitAnimIntent.new()
	intent.units = units
	intent.multi = multi
	intent.anim_id = anim_id
	intent.flag = flag
	return intent


func _rotate_unit_intent(units: int, facing: int, direction: int, speed: int,
		delay: int, multi: int = 0) -> ScenarioDecode.RotateUnitIntent:
	var intent := ScenarioDecode.RotateUnitIntent.new()
	intent.units = units
	intent.multi = multi
	intent.facing = facing
	intent.direction = direction
	intent.speed = speed
	intent.delay = delay
	return intent


func _test_warp_places_faces_and_clears_home() -> void:
	# Female-knight ground truth: uid 0x84 to (7,3) facing NORTH (0xC00).
	var world := FakeScenarioWorld.new()
	ScenarioApply.warp(_warp_intent(0x84, 7, 3, 0xC00), world)

	var placed = world.only_call("place_unit_on_tile")
	_true(placed != null, "warp places the unit exactly once")
	_eq(placed["uid"], 0x84, "warp places the right uid")
	_eq(placed["psx_x"], 7, "warp places at psx_x")
	_eq(placed["psx_y"], 3, "warp places at psx_y (raw, parser pre-flipped)")

	var faced = world.only_call("set_unit_facing")
	_true(faced != null, "warp sets facing exactly once")
	_eq(faced["angle_12bit"], 0xC00, "warp faces NORTH (0xC00)")

	_true(world.only_call("clear_actor_home") != null, "warp clears the move-home")
	# Warp zeroes the +0x60 offset on hardware -> any in-flight Sprite-Move slide is
	# cancelled, else the stale motion drags the unit back to its pre-warp target
	# (scn6 Delita ride-off: pc302 slide survived the pc303 warp and walked him back
	# up the stairs). SCENARIO6_RIDE_OFF_CHOCOBO.md §Changelog 2026-07-05 s3.
	_true(world.only_call("disarm_motion") != null, "warp disarms the in-flight slide")
	_eq(world.only_call("disarm_motion")["uid"], 0x84, "warp disarms the right uid")
	# Order: place base, THEN disarm slide + clear home, THEN face (facing after placement).
	var verbs := world.calls.map(func(e): return e["verb"])
	_true(verbs.find("place_unit_on_tile") < verbs.find("disarm_motion"),
		"places before disarming the slide")
	_true(verbs.find("place_unit_on_tile") < verbs.find("clear_actor_home"),
		"places before clearing home")
	_true(verbs.find("clear_actor_home") < verbs.find("set_unit_facing"),
		"clears home before facing")


func _test_warp_skips_missing_unit() -> void:
	var world := FakeScenarioWorld.new()
	world.missing_units[0x84] = true
	ScenarioApply.warp(_warp_intent(0x84, 7, 3, 0xC00), world)
	_eq(world.calls_to("place_unit_on_tile").size(), 0, "missing unit: no placement")
	_eq(world.calls_to("set_unit_facing").size(), 0, "missing unit: no facing")
	_eq(world.calls_to("clear_actor_home").size(), 0, "missing unit: no home clear")
	_eq(world.calls_to("disarm_motion").size(), 0, "missing unit: no slide disarm")


func _test_warp_bails_when_placement_fails() -> void:
	# No map composer -> place_unit_on_tile reports false; the home-reset + facing
	# must NOT run (they'd touch a unit that was never placed).
	var world := FakeScenarioWorld.new()
	world.place_fails = true
	ScenarioApply.warp(_warp_intent(0x84, 7, 3, 0xC00), world)
	_eq(world.calls_to("place_unit_on_tile").size(), 1, "placement was attempted")
	_eq(world.calls_to("clear_actor_home").size(), 0, "placement failed: no home clear")
	_eq(world.calls_to("disarm_motion").size(), 0, "placement failed: no slide disarm")
	_eq(world.calls_to("set_unit_facing").size(), 0, "placement failed: no facing")


# --- Unit lifecycle ({45}/{44}/{46}/{3D}) ----------------------------------

func _test_add_unit_commits_graphic_and_reveals_per_draw() -> void:
	# {45} Add Unit is the unit's INTRODUCTION into the scene: it commits the graphic
	# (marks present) AND sets +0xa from the (inverted) Draw byte — Draw=0 draws now,
	# Draw=1 holds it hidden. A not-yet-present unit is invisible until this fires, so
	# the reveal MUST live here, not only on {44} Draw (scn6 uid 1/4 at (0,4)/(0,3)
	# have a lone {45} Add Draw=0 near the end — no {44} Draw ever names them).
	var drawn := FakeScenarioWorld.new()
	ScenarioApply.add_unit(0x02, 0, drawn)
	_true(drawn.only_call("commit_unit_graphic") != null, "add Draw=0 commits graphic")
	var shown = drawn.only_call("set_unit_visible")
	_true(shown != null, "add Draw=0 sets visibility once")
	_eq(shown["visible"], true, "add Draw=0 → draw now (visible)")

	var held := FakeScenarioWorld.new()
	ScenarioApply.add_unit(0x02, 1, held)
	_true(held.only_call("commit_unit_graphic") != null, "add Draw=1 commits graphic")
	var hidden = held.only_call("set_unit_visible")
	_true(hidden != null, "add Draw=1 sets visibility once")
	_eq(hidden["visible"], false, "add Draw=1 → held (hidden)")


func _test_draw_unit_shows_erase_unit_hides() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.draw_unit(0x34, world)
	var shown = world.only_call("set_unit_visible")
	_true(shown != null, "draw sets visibility once")
	_eq(shown["visible"], true, "draw → visible true")

	world = FakeScenarioWorld.new()
	ScenarioApply.erase_unit(0x34, world)
	var hidden = world.only_call("set_unit_visible")
	_true(hidden != null, "erase sets visibility once")
	_eq(hidden["visible"], false, "erase → visible false")


func _test_lifecycle_skips_missing_unit() -> void:
	var world := FakeScenarioWorld.new()
	world.missing_units[0x99] = true
	ScenarioApply.add_unit(0x99, 1, world)
	ScenarioApply.draw_unit(0x99, world)
	ScenarioApply.erase_unit(0x99, world)
	_eq(world.calls_to("commit_unit_graphic").size(), 0, "missing: no graphic commit")
	_eq(world.calls_to("set_unit_visible").size(), 0, "missing: no visibility change")


func _test_remove_unit_resolves_then_tears_down() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.remove_unit(0x83, world)
	_true(world.only_call("resolve_unit_key") != null, "remove resolves the key first")
	var removed = world.only_call("remove_unit")
	_true(removed != null, "remove tears down once")
	_eq(removed["uid"], 0x83, "remove tears down the resolved key")
	# resolution precedes teardown.
	var verbs := world.calls.map(func(e): return e["verb"])
	_true(verbs.find("resolve_unit_key") < verbs.find("remove_unit"),
		"resolves before tearing down")


func _test_remove_unit_noops_when_absent() -> void:
	var world := FakeScenarioWorld.new()
	world.missing_units[0x83] = true
	ScenarioApply.remove_unit(0x83, world)
	_true(world.only_call("resolve_unit_key") != null, "remove still resolves (returns -1)")
	_eq(world.calls_to("remove_unit").size(), 0, "absent unit: no teardown")


# --- {47} Add Ghost Unit ---------------------------------------------------
# Body: xSP(sprite_set u16), x00, xID, X, Y, xEL(elevation), xFD(facing), xDR(draw).
# control-id = xID + 0x64; visible = (xDR == 0) (xDR inverted: 0=draw now, 1=held);
# facing_12bit = warp/spawn convention (PsxNum.warp_facing_to_12bit). Scenario 6's
# three ghosts: xSP 0x61/0x62/0x63, xID 0/1/2 → 0x64/0x65/0x66, X=Y=0, xDR=1.
# ADD_GHOST_UNIT_OPCODE_47.md §3.1/§6.

func _test_add_ghost_unit_registers_under_control_id() -> void:
	var world := FakeScenarioWorld.new()
	# scn6 ghost 1: xSP=0x61 xID=0 X=0 Y=0 xEL=0 xFD=0 xDR=1 (held).
	ScenarioApply.add_ghost_unit(0x61, 0, 0, 0, 0, 0, 1, world)
	var g = world.only_call("spawn_ghost_unit")
	_true(g != null, "ghost spawned once")
	_eq(g["control_id"], 0x64, "control-id = xID + 0x64")
	_eq(g["sprite_set"], 0x61, "sprite_set (xSP) passed through unchanged")
	_eq(g["psx_x"], 0, "X operand forwarded")
	_eq(g["psx_y"], 0, "Y operand forwarded")
	_eq(g["elevation"], 0, "xEL forwarded as elevation")


func _test_add_ghost_unit_visibility_follows_draw() -> void:
	# xDR inverted: 1 = held (hidden), 0 = draw now (visible).
	var held := FakeScenarioWorld.new()
	ScenarioApply.add_ghost_unit(0x62, 1, 0, 0, 0, 0, 1, held)
	_eq(held.only_call("spawn_ghost_unit")["visible"], false, "xDR=1 → held (hidden)")
	var drawn := FakeScenarioWorld.new()
	ScenarioApply.add_ghost_unit(0x62, 1, 0, 0, 0, 0, 0, drawn)
	_eq(drawn.only_call("spawn_ghost_unit")["visible"], true, "xDR=0 → drawn (visible)")


func _test_add_ghost_unit_decodes_facing() -> void:
	# xFD → 12-bit via the warp/spawn wheel: 0=E(0x000) 1=S(0x400) 2=W(0x800) 3=N(0xC00).
	var world := FakeScenarioWorld.new()
	ScenarioApply.add_ghost_unit(0x63, 2, 0, 0, 0, 1, 0, world)
	_eq(world.only_call("spawn_ghost_unit")["facing_12bit"],
		PsxNum.warp_facing_to_12bit(1), "xFD=1 decoded to 12-bit facing")


func _test_add_ghost_unit_idempotent_readd() -> void:
	# Re-adding a live control-id is a no-op (PSX FUN_8007a6e4(slot)==0 gate).
	var world := FakeScenarioWorld.new()
	ScenarioApply.add_ghost_unit(0x61, 0, 0, 0, 0, 0, 1, world)
	ScenarioApply.add_ghost_unit(0x61, 0, 0, 0, 0, 0, 1, world)
	_eq(world.calls_to("spawn_ghost_unit").size(), 2, "both adds reach the verb")
	_eq(world.spawned_ghosts.size(), 1, "but only one control-id actually spawns")


# --- Unit motion ({3B}/{6E} Sprite Move) -----------------------------------

func _sprite_intent(uid: int, offset: Vector3, time_frames: int, speed: int) -> ScenarioDecode.SpriteMoveIntent:
	var i := ScenarioDecode.SpriteMoveIntent.new()
	i.uid = uid
	i.offset = offset
	i.time_frames = time_frames
	i.speed = speed
	i.easing = 2
	i.weight = 3
	return i


func _test_sprite_move_fixed_arms_motion_from_home() -> void:
	# {3B} fixed: 30 frames @ 60Hz = 0.5s; target = home + offset.
	var world := FakeScenarioWorld.new()
	world.unit_home = Vector3(5, 0, 5)
	world.unit_pos = Vector3(5, 0, 5)
	ScenarioApply.sprite_move(_sprite_intent(0x02, Vector3(1, 0, 0), 30, 0),
		world, 28.0, 60.0, INF, "Sprite Move")
	var armed = world.only_call("arm_motion")
	_true(armed != null, "sprite move arms one motion")
	var m: ScenarioMotion = armed["motion"]
	_eq(m.start, Vector3(5, 0, 5), "motion starts at current position")
	_eq(m.target, Vector3(6, 0, 5), "motion targets home + offset")
	_near(m.dur_s, 0.5, "fixed duration = time_frames / hz")
	_eq(m.easing, 2, "easing carried from intent")
	_eq(m.weight, 3, "weight carried from intent")


func _test_sprite_move_beta_duration() -> void:
	# {6E} beta: dist = |target-start|*divisor = 2*28 = 56 units; frames =
	# 4*56/10 = 22.4 -> /60 = 0.37333s.
	var world := FakeScenarioWorld.new()
	world.unit_home = Vector3.ZERO
	world.unit_pos = Vector3.ZERO
	ScenarioApply.sprite_move(_sprite_intent(0x02, Vector3(0, 0, -2), 0, 10),
		world, 28.0, 60.0, INF, "Sprite Move Beta")
	var m: ScenarioMotion = world.only_call("arm_motion")["motion"]
	_eq(m.target, Vector3(0, 0, -2), "beta targets home + offset")
	_near(m.dur_s, (4.0 * 56.0 / 10.0) / 60.0, "beta duration = 4*dist/speed / hz")


func _test_sprite_move_clamped_by_playthrough() -> void:
	# A 600-frame fixed move (10s) clamped to a 1s ceiling.
	var world := FakeScenarioWorld.new()
	ScenarioApply.sprite_move(_sprite_intent(0x02, Vector3(1, 0, 0), 600, 0),
		world, 28.0, 60.0, 1.0, "Sprite Move")
	var m: ScenarioMotion = world.only_call("arm_motion")["motion"]
	_near(m.dur_s, 1.0, "duration clamped to max_dur_s")


func _test_sprite_move_skips_missing_or_immovable() -> void:
	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x02] = true
	ScenarioApply.sprite_move(_sprite_intent(0x02, Vector3(1, 0, 0), 30, 0),
		missing, 28.0, 60.0, INF, "Sprite Move")
	_eq(missing.calls_to("arm_motion").size(), 0, "missing unit: no motion armed")

	var stuck := FakeScenarioWorld.new()
	stuck.slide_ok = false
	ScenarioApply.sprite_move(_sprite_intent(0x02, Vector3(1, 0, 0), 30, 0),
		stuck, 28.0, 60.0, INF, "Sprite Move")
	_eq(stuck.calls_to("arm_motion").size(), 0, "immovable unit: no motion armed")


# --- {28} Walk To ----------------------------------------------------------

# --- the ROM-shaped half of a `plan_walk` answer ---------------------------
#
# `ScenarioApply.walk_to` now hands `ScenarioPathMotion.configure_rom` the ROM's own
# route BYTES over the ROM's own tiles, so a canned plan has to carry them. The three
# fixtures below are still hand-written straight lines — this file tests the APPLY, not
# the planner (`EventPathfinderTest` does that against 18 live captures) — but they are
# in the shape the planner really emits, PSX coordinates and all.
#
# ⚠️ `psx_rows` is `size_z` and the Z axis MIRRORS about it (ADR-0052): Godot grid Z
# `gz` is PSX row `size_z - 1 - gz`. A fixture that skips the flip produces a walk of
# the right length running the wrong way down the map, and nothing here would say so.
const _RomWalkStepper = ExMateriaBattlefield.RomWalkStepper


static func _rom_plan(nx: int, ny: int, start_gz: int, route: Array,
		start_world: Vector3, target_world: Vector3, endpoint: Vector3i,
		waypoints: Array) -> Dictionary:
	var heights: Array = []
	for _lvl in 2:
		var rows: Array = []
		for _y in ny:
			var row: Array = []
			for _x in nx:
				row.append(0)
			rows.append(row)
		heights.append(rows)
	return {
		"start": start_world,
		"target": target_world,
		"endpoint": endpoint,
		"waypoints": waypoints,
		"terrain": _RomWalkStepper.terrain_flat(heights, nx, ny),
		"psx_start": Vector3i(int(start_world.x - 0.5), ny - 1 - start_gz,
			endpoint.z if waypoints.size() < 2 else 0),
		"route": route,
		"psx_rows": ny,
		"world_y_at_start": start_world.y,
		"grid_origin": Vector2i.ZERO,
	}


func _test_walk_to_arms_motion_faces_and_clears_home() -> void:
	# Per-tile route (0,0)->(1,0)->(2,0)->(3,0): 3 tile segments at speed 8.
	#
	# ⚠️ THE WAYPOINTS ARE TILE CENTRES, which is what `ScenarioVM._plan_walk_route`
	# actually emits — `Vector3(float(t.x) + 0.5, wy, float(t.y) + 0.5)`. This fixture
	# used to state tile CORNERS, which no planner has ever produced; it went unnoticed
	# because the motion this replaced lerped between arbitrary points and never asked
	# which TILE one was in. `ScenarioPathMotion` now hands the route to the ROM's own
	# stepper, which is tile-addressed, so a corner waypoint is read as the tile it
	# falls in and the walk runs centre to centre inside it.
	#
	# ⚠️ AND THE DURATION IS NOT `224/speed`. That is an approximation of an integer
	# recurrence, and the recurrence is now what runs: `vec3_normalize` returns 4095
	# and not 4096 for a cardinal axis, and `FUN_8006C94C` quantises the position
	# three quarters of the way across every tile, throwing the sub-unit remainder
	# away once per step. Speed 8 costs 30 frames a tile, not 28, plus one ARRIVAL
	# frame for the whole walk: 3x30 + 1 = 91. See ScenarioPathMotionTest's
	# FRAMES_PER_TILE, and RomWalkStepperTest for the 43 510/43 510 that says so.
	var world := FakeScenarioWorld.new()
	# Three `+X` steps: route byte `0x00` is dir 0, span 0, no bits. A CELL endpoint,
	# not a column (ADR-0219): `walk_to` compares it against `Vector3i(tx, tz, level)`.
	world.walk_plan = _rom_plan(5, 2, 0, [3, 0x00, 0x00, 0x00],
		Vector3(0.5, 0, 0.5), Vector3(3.5, 0, 0.5), Vector3i(3, 0, 0),
		[Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5),
			Vector3(2.5, 0, 0.5), Vector3(3.5, 0, 0.5)])
	ScenarioApply.walk_to(0x84, 3, 0, 8, world, 28.0, 60.0, INF, 15)

	var m: ScenarioPathMotion = world.only_call("arm_motion")["motion"]
	_eq(m.position(), Vector3(0.5, 0, 0.5), "walk motion starts at plan start")
	_eq(m.waypoints[m.waypoints.size() - 1], Vector3(3.5, 0, 0.5), "walk ends at the seat")
	_near(m.dur_s, (3.0 * 30.0 + 1.0) / 60.0, "walk duration = the ROM recurrence, 3x30 + 1 frames")

	var walking = world.only_call("set_walking")
	_true(walking != null, "walk sets the walking state once")
	_eq(walking["facing_12bit"], 0xC00, "walk orients to its heading (+X → NORTH 0xC00)")
	_eq(walking["anim_id"], 15, "walk drives the movement-walk anim id")

	_true(world.only_call("clear_actor_home") != null, "walk clears home (tile advanced)")


func _test_walk_to_bails_on_empty_plan() -> void:
	# No map / no tile -> plan_walk returns {} -> nothing armed.
	var world := FakeScenarioWorld.new()  # walk_plan defaults to {}
	ScenarioApply.walk_to(0x84, 3, 0, 8, world, 28.0, 60.0, INF, 15)
	_true(world.only_call("plan_walk") != null, "walk asked for a plan")
	_eq(world.calls_to("arm_motion").size(), 0, "empty plan: no motion armed")
	_eq(world.calls_to("set_walking").size(), 0, "empty plan: no walking state")
	_eq(world.calls_to("seat_unit_cell").size(), 0,
		"empty plan: no cell latched — a walk that never happened moved nobody")


# 🔴 A WALK LATCHES ITS SEAT'S LEVEL, and this is the assertion whose absence cost
# scenario 29 pc 164 a thirteen-tile detour. `plan_walk` is handed a `Z` operand and
# answers with a `Vector3i` endpoint, and until this verb existed BOTH ends of that
# were thrown away the moment the motion was armed: nothing in `src/scenarios/` wrote
# `MovementComponent.current_cell`, so `ScenarioVM._unit_cell` fell through to the
# column's ground for every actor in every scenario and the NEXT Walk To re-planned
# from level 0 no matter what the last one had been told.
#
# The shape here is scenario 29 pc 34 verbatim — `Walk To Unit=7 X=4 Y=11 Z=1`, the
# instruction that puts Algus on the Igros bridge deck. It is what pc 164 reads back,
# 130 instructions later, when it asks him to step one tile west. ADR-0219 dec. 6.
func _test_walk_to_latches_the_seat_level() -> void:
	var world := FakeScenarioWorld.new()
	# One step Godot +Z, which under the ADR-0052 mirror is PSX −Y — route dir 2,
	# byte `0x80` — plus bit 5, the LEVEL bit, because the step lands on the deck:
	# `0xA0`. That byte is the whole of the seat latch, on the wire.
	world.walk_plan = _rom_plan(6, 13, 10, [1, 0xA0],
		Vector3(4.5, 1.32, 10.5), Vector3(4.5, 3.04, 11.5), Vector3i(4, 11, 1),
		[Vector3(4.5, 1.32, 10.5), Vector3(4.5, 3.04, 11.5)])
	ScenarioApply.walk_to(0x07, 4, 11, 3, world, 28.0, 60.0, INF, 15, 1)

	_eq(world.only_call("plan_walk")["level"], 1, "seat latch: the Z operand reached the planner")
	var seat = world.only_call("seat_unit_cell")
	_true(seat != null, "seat latch: the walk latched a cell onto the unit")
	_eq(seat["cell"], Vector3i(4, 11, 1),
		"seat latch: and it is the seat CELL, level included (got %s)" % str(seat["cell"]))
	_eq(world.seated_cell.z, 1, "seat latch: the level survives the walk")


# The latch takes the PLAN'S ENDPOINT, not the operand — latching what was asked for
# would put a unit's logical cell somewhere its transform is not, and `_unit_cell`'s
# `(x, z)`-matches-the-transform guard would then silently discard it, reintroducing
# exactly the level loss this verb exists to fix.
#
# ⚠️ THE PREMISE THIS ARM WAS WRITTEN ON IS GONE. It used to say "a target sealed off
# by impassable terrain stops the route short, and the unit stands on where it
# STOPPED". `FUN_8017813C` has no nearest-tile fallback: an unreachable target is
# REFUSED and the walk does not happen (ADR-0226), which
# `_test_walk_to_bails_on_empty_plan` is now the arm for. So the endpoint and the
# operand agree on every real plan, and this pins the WIRING rather than a divergence:
# the fixture states an endpoint the operand does not name, and the latch must follow
# the plan.
func _test_walk_to_latches_the_plans_endpoint_not_the_operand() -> void:
	var world := FakeScenarioWorld.new()
	world.walk_plan = _rom_plan(4, 2, 0, [2, 0x00, 0x00],
		Vector3(0.5, 0, 0.5), Vector3(2.5, 0, 0.5), Vector3i(2, 0, 0),
		[Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 0.5), Vector3(2.5, 0, 0.5)])
	ScenarioApply.walk_to(0x84, 3, 0, 8, world, 28.0, 60.0, INF, 15, 1)

	_eq(world.only_call("seat_unit_cell")["cell"], Vector3i(2, 0, 0),
		"the latch follows the PLAN's endpoint, not the requested cell")


# --- {11} Unit Anim / {8C} Unit Anim Rotate --------------------------------

func _test_unit_anim_plays_or_skips() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.unit_anim(_unit_anim_intent(0x0C, 0x03, 0), world)
	var played = world.only_call("play_unit_anim")
	_true(played != null, "unit anim plays once")
	_eq(played["anim_id"], 0x03, "plays the decoded anim id")

	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x0C] = true
	ScenarioApply.unit_anim(_unit_anim_intent(0x0C, 0x03, 0), missing)
	_eq(missing.calls_to("play_unit_anim").size(), 0, "missing unit: no anim")


func _test_unit_anim_broadcasts_all() -> void:
	# Multi=2 -> ALL present units get the anim (the scenario-1 Multi!=0 rows).
	var world := FakeScenarioWorld.new()
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},
		{"key": 0x0C, "team_color": 0, "alive": true},
		{"key": 0x05, "team_color": 1, "alive": true},
	]
	ScenarioApply.unit_anim(_unit_anim_intent(0x2E, 0x25A, 0x80, 0x3C), world)
	_eq(world.calls_to("play_unit_anim").size(), 3, "Multi≥2: anim broadcast to all present")


## {80} March — RELEASE the addressed set back to combat-idle, honoring the selector.
## Gariland = SINGLE (Units=0x80, Multi=0) → releases ONLY unit 0x80 (the dialogue speaker
## frozen by its {11}); it must NOT touch the units that were never frozen. The pre-fix
## _op_march blanket-flipped every unit — this pins the selector-aware release.
## MARCH_OPCODE_80_SEMANTICS.md §2 / §5 (release-addressed-only, user-chosen 2026-08-01).
func _test_march_releases_single_addressed() -> void:
	var world := FakeScenarioWorld.new()
	# Roster has three present units, but SINGLE must ignore it and release only 0x80.
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},
		{"key": 0x80, "team_color": 0, "alive": true},
		{"key": 0x05, "team_color": 1, "alive": true},
	]
	ScenarioApply.march(0x80, 0x00, 0, world)
	var released := world.calls_to("release_to_combat_idle")
	_eq(released.size(), 1, "March SINGLE releases exactly one unit (not a blanket flip)")
	if released.size() == 1:
		_eq(released[0]["uid"], 0x80, "March SINGLE releases the addressed unit 0x80 (the speaker)")


func _test_march_broadcasts_team_set() -> void:
	# Multi=1, Units=2 -> ENEMY team set: every present non-player unit is released. Proves
	# the broadcast-march scenarios (17/18/31/34) resolve through the same selector, not a
	# hardcoded all-units flip.
	var world := FakeScenarioWorld.new()
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},  # player — excluded
		{"key": 0x05, "team_color": 1, "alive": true},  # enemy  — released
		{"key": 0x06, "team_color": 1, "alive": true},  # enemy  — released
	]
	ScenarioApply.march(0x02, 0x01, 0, world)
	var released := world.calls_to("release_to_combat_idle")
	_eq(released.size(), 2, "March ENEMY broadcast releases every present enemy unit")
	var uids := released.map(func(e): return e["uid"])
	_true(uids.has(0x05) and uids.has(0x06) and not uids.has(0x02),
		"March ENEMY broadcast releases the enemy team only (0x05,0x06; not player 0x02)")


func _test_march_skips_empty_set() -> void:
	# The addressed unit isn't spawned -> SINGLE resolves to empty -> no-op (no release).
	var world := FakeScenarioWorld.new()
	world.missing_units[0x80] = true
	ScenarioApply.march(0x80, 0x00, 0, world)
	_eq(world.calls_to("release_to_combat_idle").size(), 0,
		"March on an unspawned unit releases nothing (empty set no-op)")


func _test_unit_anim_rotate_snaps_then_animates() -> void:
	# Direction nibble 0xC (N) -> 0xC00; facing snaps before the anim plays.
	var world := FakeScenarioWorld.new()
	ScenarioApply.unit_anim_rotate(0x0C, 0xC, 0x02, world)
	var faced = world.only_call("set_unit_facing")
	_true(faced != null, "unit anim rotate snaps facing")
	_eq(faced["angle_12bit"], 0xC00, "direction 0xC -> 0xC00 (N)")
	_true(world.only_call("play_unit_anim") != null, "then plays the anim")
	var verbs := world.calls.map(func(e): return e["verb"])
	_true(verbs.find("set_unit_facing") < verbs.find("play_unit_anim"),
		"snaps facing before animating")


# --- {2D} Rotate Unit ------------------------------------------------------

func _test_rotate_unit_relative_target() -> void:
	# Relative mode 0x11: target = wrap12(baseline + 0x100). baseline 0x400 -> 0x500.
	var world := FakeScenarioWorld.new()
	world.baseline_12bit = 0x400
	ScenarioApply.rotate_unit(_rotate_unit_intent(0x0C, 0x11, 1, 8, 0), world)
	var armed = world.only_call("arm_rotate")
	_true(armed != null, "rotate arms the stepper once")
	_eq(armed["target_12bit"], 0x500, "relative 0x11 = baseline + 0x100")
	_eq(armed["direction"], 1, "direction carried")
	_eq(armed["speed"], 8, "speed carried")


func _test_rotate_unit_broadcasts_player_team() -> void:
	# scn6 motivating bug: {2D} Rotate [Units=1, Multi=1, Facing=8] = PLAYER_ALIVE.
	# Every alive team-0 unit (incl. Ovelia 0x0C) rotates to the absolute wheel step;
	# Delita (team 1) is excluded. Facing 0x08 = absolute -> 0x800.
	var world := FakeScenarioWorld.new()
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},   # blue
		{"key": 0x0C, "team_color": 0, "alive": true},   # Ovelia — blue
		{"key": 0x05, "team_color": 1, "alive": true},   # Delita — enemy
	]
	ScenarioApply.rotate_unit(_rotate_unit_intent(1, 0x08, 0, 4, 0, 1), world)
	var armed := world.calls_to("arm_rotate")
	_eq(armed.size(), 2, "PLAYER_ALIVE: both blue units rotate, Delita excluded")
	var rotated_keys := armed.map(func(e): return e["uid"])
	_true(0x0C in rotated_keys, "Ovelia (0x0C) is rotated — the carry-flip fix")
	_true(not (0x05 in rotated_keys), "Delita (0x05, enemy) is NOT rotated")
	_eq(armed[0]["target_12bit"], 0x800, "Facing 0x08 absolute -> 0x800")


# --- {53} Face Unit / {2C} Face Unit 2 -------------------------------------

func _test_face_unit_single_and_mutual() -> void:
	# {53}: only the affected unit rotates, to the computed look-at.
	var single := FakeScenarioWorld.new()
	single.look_at_12bit = 0x400
	ScenarioApply.face_unit(0x0C, 0x84, 0, 2, 4, 1, false, single, "Face Unit")
	_eq(single.calls_to("arm_rotate").size(), 1, "{53}: one rotation (affected only)")
	_eq(single.only_call("arm_rotate")["target_12bit"], 0x400, "affected faces look-at")
	_eq(single.calls_to("face_look_at_12bit").size(), 1, "{53}: one look-at computed")

	# {2C}: both units rotate to face each other.
	var mutual := FakeScenarioWorld.new()
	ScenarioApply.face_unit(0x0C, 0x84, 0, 2, 4, 1, true, mutual, "Face Unit 2")
	_eq(mutual.calls_to("arm_rotate").size(), 2, "{2C}: two rotations (mutual)")
	_eq(mutual.calls_to("face_look_at_12bit").size(), 2, "{2C}: two look-ats")


func _test_face_unit_guards() -> void:
	# affected == faced -> degenerate skip (ROM LAB_80148128).
	var same := FakeScenarioWorld.new()
	ScenarioApply.face_unit(0x0C, 0x0C, 0, 2, 4, 1, false, same, "Face Unit")
	_eq(same.calls_to("arm_rotate").size(), 0, "affected == faced: no rotation")

	# Empty affected set (Multi=0, unspawned unit) -> no rotation.
	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x0C] = true
	ScenarioApply.face_unit(0x0C, 0x84, 0, 2, 4, 1, false, missing, "Face Unit")
	_eq(missing.calls_to("arm_rotate").size(), 0, "missing affected: no rotation")


func _test_face_unit_broadcasts_affected_team_set() -> void:
	# Multi=1,Units=0 -> PLAYER set: every team-0 unit faces the faced unit; the
	# faced unit (if team-0) is skipped by the affected==faced guard. Roster: two
	# blue (0x02,0x0C) + one red (0x05); faced=0x05 (enemy, not in the set).
	var world := FakeScenarioWorld.new()
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},
		{"key": 0x0C, "team_color": 0, "alive": true},
		{"key": 0x05, "team_color": 1, "alive": true},
	]
	world.look_at_12bit = 0x400
	ScenarioApply.face_unit(0, 0x05, 1, 2, 4, 1, false, world, "Face Unit")
	_eq(world.calls_to("arm_rotate").size(), 2, "PLAYER set: both blue units rotate")
	_eq(world.calls_to("face_look_at_12bit").size(), 2, "one look-at per affected")
	# {2C} mutual back-face is suppressed for a multi-unit broadcast (ambiguous).
	var mutual := FakeScenarioWorld.new()
	mutual.roster = world.roster.duplicate(true)
	ScenarioApply.face_unit(0, 0x05, 1, 2, 4, 1, true, mutual, "Face Unit 2")
	_eq(mutual.calls_to("arm_rotate").size(), 2, "mutual broadcast: no extra faced back-face")


# --- {69} Face Tile --------------------------------------------------------

func _test_face_tile_rotates_affected_to_tile() -> void:
	# {69}: affected unit rotates to the tile look-at (Multi=0). scn6-shaped:
	# affected 0x02, tile (0,13), dir 0, speed 2, delay 0.
	var world := FakeScenarioWorld.new()
	world.look_at_12bit = 0x600
	ScenarioApply.face_tile(0x02, 0, 0, 13, 0, 2, 0, world)
	var looked = world.only_call("face_tile_look_at_12bit")
	_true(looked != null, "{69}: one tile look-at computed")
	_eq(looked["tile_x"], 0, "look-at uses operand tile X")
	_eq(looked["tile_y"], 13, "look-at uses operand tile Y")
	var armed = world.only_call("arm_rotate")
	_true(armed != null, "{69}: one rotation armed (affected only)")
	_eq(armed["target_12bit"], 0x600, "affected rotates to the tile look-at")
	_eq(armed["speed"], 2, "speed operand carried to the stepper")


func _test_face_tile_guards() -> void:
	# Missing / unspawned unit (Multi=0) -> empty set -> skip.
	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x02] = true
	ScenarioApply.face_tile(0x02, 0, 0, 13, 0, 2, 0, missing)
	_eq(missing.calls_to("arm_rotate").size(), 0, "missing unit: no rotation")
	_eq(missing.calls_to("face_tile_look_at_12bit").size(), 0, "missing unit: no look-at")


func _test_face_tile_broadcasts_affected_team_set() -> void:
	# Multi=1,Units=2 -> ENEMY set: every non-zero-team unit faces the tile.
	var world := FakeScenarioWorld.new()
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},   # blue — excluded
		{"key": 0x05, "team_color": 1, "alive": true},   # red  — included
		{"key": 0x06, "team_color": 1, "alive": true},   # red  — included
	]
	world.look_at_12bit = 0x600
	ScenarioApply.face_tile(2, 1, 0, 13, 0, 2, 0, world)
	_eq(world.calls_to("arm_rotate").size(), 2, "ENEMY set: both red units rotate to tile")
	_eq(world.calls_to("face_tile_look_at_12bit").size(), 2, "one tile look-at per affected")


# --- {4E} Unit Shadow ------------------------------------------------------

func _test_unit_shadow_toggles() -> void:
	# Disable operand inverts: set_unit_shadow(enabled = Disable == 0). ROM writes
	# sb 1/0 to unit+0x298 for enable/disable respectively.
	var off := FakeScenarioWorld.new()
	ScenarioApply.unit_shadow(0x8B, 1, off)  # scn6 pc384: chocobo 139 shadow OFF
	var s = off.only_call("set_unit_shadow")
	_true(s != null, "unit shadow toggled once")
	_eq(s["uid"], 0x8B, "toggles the resolved unit")
	_eq(s["enabled"], false, "Disable=1 -> shadow disabled")

	var on := FakeScenarioWorld.new()
	ScenarioApply.unit_shadow(0x0C, 0, on)
	_eq(on.only_call("set_unit_shadow")["enabled"], true, "Disable=0 -> shadow enabled")

	# Missing / unspawned unit -> skip.
	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x8B] = true
	ScenarioApply.unit_shadow(0x8B, 1, missing)
	_eq(missing.calls_to("set_unit_shadow").size(), 0, "missing unit: no toggle")


# --- {32} Color Unit / {33} Color Field / Reset Palette / {1A} Map Darkness -

func _color_unit_intent(uid: int, mode: int, multi: int = 0) -> ScenarioDecode.ColorUnitIntent:
	var i := ScenarioDecode.ColorUnitIntent.new()
	i.units = uid
	i.multi = multi
	i.mode = mode
	i.red = 0
	i.green = 0
	i.blue = 0
	i.time = 0  # snap
	return i


func _test_color_unit_pushes_and_conditionally_clears() -> void:
	# Mode 1 (darken to half) snap -> non-identity -> pushed, NOT cleared.
	var half := FakeScenarioWorld.new()
	ScenarioApply.color_unit(_color_unit_intent(0x0C, 1), half)
	_true(half.only_call("push_unit_tint") != null, "non-identity tint pushed")
	_eq(half.calls_to("clear_unit_tint").size(), 0, "non-identity tint kept")

	# Mode 8 (restore identity) snap -> identity -> pushed then cleared.
	var restore := FakeScenarioWorld.new()
	ScenarioApply.color_unit(_color_unit_intent(0x0C, 8), restore)
	_true(restore.only_call("push_unit_tint") != null, "identity tint still pushed")
	_true(restore.only_call("clear_unit_tint") != null, "identity tint dropped")


func _test_color_unit_skips_missing() -> void:
	var world := FakeScenarioWorld.new()
	world.missing_units[0x0C] = true
	ScenarioApply.color_unit(_color_unit_intent(0x0C, 1), world)
	_eq(world.calls_to("get_or_create_unit_tint").size(), 0, "missing: no tint touched")
	_eq(world.calls_to("push_unit_tint").size(), 0, "missing: no push")


func _test_color_unit_broadcasts_team_set() -> void:
	# Multi=1,Units=0 -> PLAYER set: the tint is folded into every team-0 unit.
	var world := FakeScenarioWorld.new()
	world.roster = [
		{"key": 0x02, "team_color": 0, "alive": true},
		{"key": 0x0C, "team_color": 0, "alive": true},
		{"key": 0x05, "team_color": 1, "alive": true},   # enemy — excluded
	]
	ScenarioApply.color_unit(_color_unit_intent(0, 1, 1), world)  # mode 1, Multi=1
	var pushed := world.calls_to("push_unit_tint")
	_eq(pushed.size(), 2, "PLAYER set: tint pushed to both blue units")
	var tinted_keys := pushed.map(func(e): return e["uid"])
	_true(0x02 in tinted_keys and 0x0C in tinted_keys, "both blue units tinted")
	_true(not (0x05 in tinted_keys), "enemy unit not tinted")


func _test_reset_palette_clears_and_pushes_identity() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.reset_palette(0x0C, world)
	_true(world.only_call("clear_unit_tint") != null, "reset clears the tint")
	var pushed = world.only_call("push_unit_tint")
	_true(pushed != null, "reset pushes an identity tint")
	_true((pushed["tint"] as ScenarioColorTint).is_identity(), "pushed tint is identity")

	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x0C] = true
	ScenarioApply.reset_palette(0x0C, missing)
	_eq(missing.calls_to("push_unit_tint").size(), 0, "missing unit: reset no-op")


## {68} Mirror Sprite latches the per-unit flip XOR delta. `Mirror == 1` sets it;
## the ROM's `bne s0,1` means EVERY other value takes the clear path, so 0 (17 of
## the 62 corpus sites) must un-mirror. Single-unit: no Units/Multi broadcast.
func _test_mirror_sprite_latches_and_clears() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.mirror_sprite(0x30, 1, world)
	var set_call = world.only_call("set_unit_mirror")
	_true(set_call != null, "Mirror=1 reaches the world verb")
	_eq(set_call["uid"], 0x30, "mirror targets the resolved unit")
	_eq(set_call["mirrored"], true, "Mirror=1 latches the flip delta")

	var off := FakeScenarioWorld.new()
	ScenarioApply.mirror_sprite(0x30, 0, off)
	_eq(off.only_call("set_unit_mirror")["mirrored"], false, "Mirror=0 un-mirrors")

	var missing := FakeScenarioWorld.new()
	missing.missing_units[0x30] = true
	ScenarioApply.mirror_sprite(0x30, 1, missing)
	_eq(missing.calls_to("set_unit_mirror").size(), 0, "missing unit: mirror no-op")


func _test_color_field_pushes_and_conditionally_clears() -> void:
	var field := ScenarioDecode.ColorFieldIntent.new()
	field.mode = 1  # non-identity
	field.red = 0; field.green = 0; field.blue = 0; field.time = 0
	var world := FakeScenarioWorld.new()
	ScenarioApply.color_field(field, world)
	_true(world.only_call("push_field_tint_to_all") != null, "field tint broadcast")
	_eq(world.calls_to("clear_field_tint").size(), 0, "non-identity field kept")

	var restore := ScenarioDecode.ColorFieldIntent.new()
	restore.mode = 8; restore.red = 0; restore.green = 0; restore.blue = 0; restore.time = 0
	var world2 := FakeScenarioWorld.new()
	ScenarioApply.color_field(restore, world2)
	_true(world2.only_call("clear_field_tint") != null, "identity field dropped")


func _test_map_darkness_sets_state() -> void:
	var world := FakeScenarioWorld.new()
	var intent := ScenarioDecode.MapDarknessIntent.new()
	intent.blend = 4
	intent.target = Vector3(30, 10, 0)
	intent.snap = true
	intent.duration_ticks = 0
	ScenarioApply.map_darkness(intent, world)
	var set_call = world.only_call("set_map_darkness")
	_true(set_call != null, "map darkness sets the oxide state once")
	_eq((set_call["intent"] as ScenarioDecode.MapDarknessIntent).target, Vector3(30, 10, 0),
		"the decoded intent is forwarded to the state verb")


# --- Screen & overlay effects ({3C}/{76}/{77}/{78}/{7D}/Reveal) ------------

func _test_weather_latch() -> void:
	var on := FakeScenarioWorld.new()
	var active := ScenarioDecode.WeatherIntent.new()
	active.active = true
	active.strength = 3
	ScenarioApply.weather(active, on)
	var w = on.only_call("set_weather")
	_true(w != null, "weather latch fires once")
	_eq(w["active"], true, "active latch")
	_eq(w["strength"], 3, "strength forwarded")

	var off := FakeScenarioWorld.new()
	var cancel := ScenarioDecode.WeatherIntent.new()
	cancel.active = false
	cancel.strength = 0
	ScenarioApply.weather(cancel, off)
	_eq(off.only_call("set_weather")["active"], false, "cancel latch")


func _test_dark_screen_show_hide() -> void:
	var world := FakeScenarioWorld.new()
	var intent := ScenarioDecode.DarkScreenIntent.new()
	intent.shape = 1
	intent.screen_expansion_speed = 12
	intent.square_expansion_speed = 4
	intent.rotation_speed = 0x40
	ScenarioApply.dark_screen(intent, world)
	_true(world.only_call("show_dark_screen") != null, "dark screen shown")

	ScenarioApply.remove_dark_screen(world)
	_true(world.only_call("hide_dark_screen") != null, "dark screen hidden")


func _test_display_conditions() -> void:
	var world := FakeScenarioWorld.new()
	# 0x12 is a MODE, not a conditions id: modes >= 8 are the victory-condition
	# banner for BONUS.BIN page `mode - 8`, so 0x12 asks for page 10
	# (BATTLE_RESULTS_SCREEN.md §13).
	ScenarioApply.display_conditions(0x12, 30, world)
	var c = world.only_call("show_conditions")
	_true(c != null, "conditions screen run once")
	_eq(c["conditions"], 0x12, "mode forwarded")
	_eq(c["time"], 30, "Time forwarded")


func _test_show_graphic() -> void:
	var world := FakeScenarioWorld.new()
	var intent := ScenarioDecode.ShowGraphicIntent.new()
	intent.graphic_id = 0x03
	ScenarioApply.show_graphic(intent, world)
	var g = world.only_call("show_graphic")
	_true(g != null, "graphic shown once")
	_eq((g["intent"] as ScenarioDecode.ShowGraphicIntent).graphic_id, 0x03, "graphic id forwarded")


func _test_reveal_floors_time() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.reveal(20, world)
	_eq(world.only_call("arm_reveal")["ticks"], 20, "reveal arms the given ticks")

	var zero := FakeScenarioWorld.new()
	ScenarioApply.reveal(0, zero)
	_eq(zero.only_call("arm_reveal")["ticks"], 1, "reveal floors Time<=0 to 1 tick")


# --- Dialogue ({10} Display Message / Change Dialog) -----------------------

func _dm_intent(dialog: int) -> ScenarioDecode.DisplayMessageIntent:
	var i := ScenarioDecode.DisplayMessageIntent.new()
	i.dialog = dialog
	i.msg_id = 16
	i.psx_x = -31
	i.psx_y = -6
	i.speaker_uid = 0x84
	i.portrait_row = 0
	i.open_type = 3
	i.fine_x60 = -32
	i.is_overlay = dialog == 0x09
	return i


func _test_display_message_overlay_and_box() -> void:
	# Overlay (0x09): shows overlay, does NOT arm the gate.
	var ov := FakeScenarioWorld.new()
	var ov_armed := ScenarioApply.display_message(_dm_intent(0x09), ["hi"], ov)
	_true(ov.only_call("show_dialogue_overlay") != null, "overlay shown")
	_eq(ov_armed, false, "overlay does not arm the advance gate")
	_true(ov.only_call("clear_dialogue_overlay") != null, "prior overlay cleared first")

	# Boxed (0x11): shows box, ARMS the gate (return true).
	var bx := FakeScenarioWorld.new()
	var bx_armed := ScenarioApply.display_message(_dm_intent(0x11), ["hi"], bx)
	var shown = bx.only_call("show_dialogue_box")
	_true(shown != null, "box shown")
	_eq(shown["dialog"], 0x11, "box dialog byte forwarded")
	_eq(bx_armed, true, "boxed message arms the advance gate")


func _test_display_message_skips() -> void:
	# Empty tokens on overlay -> skip, no show, no gate.
	var empty := FakeScenarioWorld.new()
	_eq(ScenarioApply.display_message(_dm_intent(0x09), [], empty), false, "empty overlay: no gate")
	_eq(empty.calls_to("show_dialogue_overlay").size(), 0, "empty overlay: no show")

	# Unsupported dialog byte -> skip.
	var unsupported := FakeScenarioWorld.new()
	unsupported.boxed_ok = false
	_eq(ScenarioApply.display_message(_dm_intent(0x11), ["hi"], unsupported), false,
		"unsupported dialog: no gate")
	_eq(unsupported.calls_to("show_dialogue_box").size(), 0, "unsupported dialog: no box")

	# No box renderer wired -> skip.
	var no_box := FakeScenarioWorld.new()
	no_box.box_wired = false
	_eq(ScenarioApply.display_message(_dm_intent(0x11), ["hi"], no_box), false, "no box: no gate")
	_eq(no_box.calls_to("show_dialogue_box").size(), 0, "no box renderer: no show")


func _test_change_dialog_close_and_swap() -> void:
	# Close (0xFFFF) of the foreground box -> close_fg.
	var close_fg := FakeScenarioWorld.new()
	close_fg.close_is_foreground = true
	var rc = ScenarioApply.change_dialog(0xFFFF, 0, 0, close_fg)
	_true(close_fg.only_call("close_dialog_slot") != null, "close routed through the verb")
	_eq(rc["action"], "close_fg", "closing the foreground box tears down the gate")

	# Close of a demoted background box -> close_bg (gate untouched).
	var close_bg := FakeScenarioWorld.new()
	close_bg.close_is_foreground = false
	_eq(ScenarioApply.change_dialog(0xFFFF, 2, 0, close_bg)["action"], "close_bg",
		"closing a background box leaves the gate")

	# Swap to a new message -> swap (arm gate).
	var swap := FakeScenarioWorld.new()
	var rs = ScenarioApply.change_dialog(5, 1, 0, swap)
	_true(swap.only_call("swap_dialog_text") != null, "swap routed through the verb")
	_eq(rs["action"], "swap", "swapping text arms the gate")

	# The {51} Portrait Column is threaded to the swap verb (issue #165): a {51}
	# that re-picks a face must forward its column so the live box re-resolves it.
	var swap_pf := FakeScenarioWorld.new()
	ScenarioApply.change_dialog(5, 1, 2, swap_pf)
	_eq(swap_pf.only_call("swap_dialog_text")["portrait_byte"], 2,
		"swap forwards the {51} Portrait Column to the box verb")

	# Swap with no baked tokens -> noop (keep current box).
	var no_toks := FakeScenarioWorld.new()
	no_toks.tokens_for_msg = []
	_eq(ScenarioApply.change_dialog(5, 1, 0, no_toks)["action"], "noop", "no tokens: keep current box")
	_eq(no_toks.calls_to("swap_dialog_text").size(), 0, "no tokens: no swap")


# --- Field objects & EVTCHR ({58}/{55}/{54}) -------------------------------

func _test_load_evtchr() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.load_evtchr(2, 0x0100, world)
	var e = world.only_call("load_evtchr")
	_true(e != null, "EVTCHR mapped once")
	_eq(e["block"], 2, "block forwarded")
	_eq(e["slot"], 0x0100, "slot forwarded")


func _test_use_field_object() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.use_field_object(1, 0, world)
	var f = world.only_call("play_field_object")
	_true(f != null, "field object play requested once")
	_eq(f["id"], 1, "field object id forwarded")


func _test_use_3d_object() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.use_3d_object(3, 5, world)
	var o = world.only_call("play_3d_object")
	_true(o != null, "3d object play requested once")
	_eq(o["id"], 3, "3d object id forwarded")
	_eq(o["state"], 5, "3d object state forwarded")


# --- Sound ({21} Sound Effect / {60} Fade Sound) ---------------------------

func _test_sound_effect_plays_by_id() -> void:
	var world := FakeScenarioWorld.new()
	ScenarioApply.sound_effect(0x2A, world)
	var s = world.only_call("play_system_sound")
	_true(s != null, "system sound played once")
	_eq(s["sound_id"], 0x2A, "sound id forwarded to the SPU verb")


func _test_fade_sound_fades_music() -> void:
	var world := FakeScenarioWorld.new()
	var intent := ScenarioDecode.FadeSoundIntent.new()
	intent.ticks = 0x100
	ScenarioApply.fade_sound(intent, world)
	var f = world.only_call("fade_music")
	_true(f != null, "music fade requested once")
	_eq(f["ticks"], 0x100, "fade ticks forwarded to the music verb")
