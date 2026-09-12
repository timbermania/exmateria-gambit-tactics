extends Node
## The world map's START-menu → Formation hand-off, RENDERED, on the route that plays
## the outgoing group's scene-out.
##
## Reported from play twice: *"the formation screen is just black."* The first fix lifted
## the inherited `_fade_rect` and was correct; the screen stayed black, because a THIRD
## cover was standing. Group 9's last member (scenario 12) ends on
## `{3E} Color Screen Mode 2, (0,0,0)->(255,255,255)` — a subtractive full-screen ramp
## whose settled colour is white, and `out = B - F` with F white is black. That quad is a
## [ScreenOverlayQuad]: NDC-rewritten corners, a ±4096 cull-proof AABB,
## `depth_test_disabled`, `render_priority 100`. It fills the screen of ANY camera in the
## world — including the orthographic one `Formation.tscn` brings with it. The map itself
## never noticed: it is a CanvasLayer at 100 and draws over all 3D. Formation is a Node3D.
## ADR-0162 frees the battle world at the map mount, taking the whole overlay family with
## it (they are VM children).
##
## [b]TWO things make this guard able to report that, and the route is the load-bearing
## one.[/b] `NavigatorWorldMapFormationTest` is 9/9 green through the entire defect: it
## asserts the two known covers are lifted and never samples a frame — but even a rendered
## assertion would not have caught it there, because that test seeks to the `world_map`
## ACTION, so scenario 12 never plays and no quad is ever raised. This one seeks to the
## VICTORY action instead, one step earlier, which is the whole difference. Do not
## "simplify" it back onto the world_map action: that makes it structurally blind.
##
## HEADFUL — run standalone:
##   godot --path . res://tests/NavigatorWorldMapFormationRenderTest.tscn

# ADR-0223 dec. 8 / ADR-0217 dec. 16 — `JsonAsset` is the PORT's, not the
# host's: it is a free-function loader with no host state, and leaving it in
# `src/` was goal #5 unmet on the TYPE axis for every addon that called it
# (#809). One alias line per file keeps this file's spelling (ADR-0211 dec. 4).
const JsonAsset = ExMateriaPlatform.JsonAsset

const TIMEOUT_MS := 240000
const WM_WINDOW_FORMATION := 7

## Formation fills the frame with a lit stone floor, unit bodies and two panels; measured
## on the fixed route it is ~89% non-black. A cover puts it at ~0.2% (the debug compass,
## a CanvasLayer at 50, is all that escapes). Anything in between is a new defect, not a
## tolerance — this bar sits far below the real value and far above a covered frame.
const MIN_NON_BLACK_FRACTION := 0.40

## Per-channel sum above which a sampled pixel counts as lit. Matches the probe that
## measured the numbers above.
const LIT_SUM := 0.06

## Mirrors `ScenarioPlayerScene.CHUNK_DIR` (that script has no `class_name`, so it cannot
## be referenced from here). Per-id chunks are keyed `scenario_%03d_chunk.json`.
const CHUNK_DIR := "res://assets/scenarios/chunks"

var _passed := 0
var _failed := 0
var _nav: Node = null
var _start_ms := 0

## The scenario id of the victory beat this run seeks to — the one whose tail must carry
## the `{3E}` that used to black the screen.
var _beat_scenario_id := -1


func _ready() -> void:
	var nav_script: GDScript = load("res://src/scenarios/NavigatorMain.gd")
	var consts: Dictionary = nav_script.get_script_constant_map()
	var start_root := int(consts.get("START_ROOT", 1))
	var stop_root := int(consts.get("STOP_ROOT", 0))

	var plan := GameNavigator.new().plan_actions(start_root, stop_root,
			StoryMutationScript.build())
	# The LAST victory action: group 9's, whose beat is scenario 12 — the `{3E}` tail.
	var idx := -1
	for i in range(plan.size()):
		if String(plan[i].get("kind", "")) == "victory":
			idx = i
	if idx < 0:
		print("[FAIL] NavigatorWorldMapFormationRenderTest — no victory action in the plan")
		get_tree().quit(1)
		return
	_beat_scenario_id = int((plan[idx].get("beat", {}) as Dictionary).get("scenario_id", -1))
	ScenarioDebugSession.navigator_start_root = start_root
	ScenarioDebugSession.navigator_stop_root = stop_root
	ScenarioDebugSession.navigator_start_action = idx

	_start_ms = Time.get_ticks_msec()
	_nav = load("res://assets/scenes/NavigatorMain.tscn").instantiate()
	add_child(_nav)

	var view: Node = null
	while view == null and not _timed_out():
		await get_tree().process_frame
		view = _find_world_map()
	if view == null:
		print("[FAIL] NavigatorWorldMapFormationRenderTest — the world map never mounted")
		get_tree().quit(1)
		return
	while is_instance_valid(view) and view.screen_in_active() and not _timed_out():
		await get_tree().process_frame

	# THE ROUTE IS HALF THE GUARD. Assert the beat this test seeks to actually carries a
	# `{3E}`, read off its own chunk — not that the seek was consumed, which is true of any
	# route. Re-point this test at the `world_map` action and this fails, which is the
	# point: that route cannot raise a cover, so a green render there means nothing.
	_true("the seeked beat (scn %d) raises a {3E} Color Screen" % _beat_scenario_id,
			_beat_raises_color_screen())

	# ADR-0162: the battle world is gone by the time the map is up, and with it every
	# scenario screen overlay. Asserted structurally as well as rendered, so a failure
	# names its cause instead of only its symptom.
	_true("battle world torn down at the map mount", _nav._vm == null
			or not is_instance_valid(_nav._vm))
	_eq("_battle_world_root cleared", _nav._battle_world_root, -1)
	_eq("no ScreenOverlayQuad left in the tree", _count_screen_overlays(), 0)

	_nav._on_world_map_menu_row(view, WM_WINDOW_FORMATION)

	# ADR-0172, and it can only be measured HERE. `FormationScreenInTest` proves the ramp in
	# isolation; nothing in it proves the ramp is armed on the PLAYER's route, and a screen-in
	# that never fires is invisible to every assertion below — the settled frame is identical
	# either way. So sample a few frames in, while the subtractive quad should still be dark,
	# and again at rest. Deliberately a DIRECTION check (early < settled) and not a pinned
	# value: `RAMP_TICKS` is an analogy to `world_menu_open_curve`, not a measurement of this
	# screen, and a test that pinned it would entrench the guess — the same refusal
	# `WorldMapScreenInTest` makes about the map's 60.
	for i in range(6):
		await get_tree().process_frame
	var early := await _lit_fraction()

	for i in range(180):
		await get_tree().process_frame

	var form := _find_formation()
	_true("Formation mounted", form != null)
	if form == null:
		_verdict()
		return
	var grid := _grid_of(form)
	_true("the coordinator built its roster grid", grid != null)
	if grid == null:
		_verdict()
		return
	_eq("Formation is bound to the owned roster",
			grid._roster_characters().size(), CharacterCatalog.owned_units().size())
	_true("the two known covers are still lifted",
			_nav._fade_rect != null and _nav._fade_rect.color.a == 0.0)


	# RESTORED. This was retired as a record while the fix was blocked; it is the assertion
	# the reported bug fails.
	#
	# The docked vitals/nameplate pair was bound ONCE in `_ready`, and both navigator call
	# sites mount then inject a frame later — so `_build_unit_info_cluster` ran while
	# `_injected_characters` was still null, took the self-discovery fallback, and nothing
	# ever rebound it. `rebuild_cells` redrew the cells and left the panel behind: measured
	# on this route as a Squire at HP 031 selected under a panel reading "Marcus" at 081 —
	# a unit not on the grid. It self-healed on the first cursor move, which is why it
	# survived. `rebuild_cells` now rebinds (ADR-0180), and the cluster is built UNBOUND so
	# it exists to be rebound.
	#
	# WHICH change fixed it, on THIS route: the FALLBACK, not the rebind. Measured — with
	# `rebuild_cells`'s rebind commented out this still passes 10/10, because the navigator
	# has already folded the owned overlay by the time the screen mounts, so the
	# self-discovery branch answers with the right unit at build time. That IS ADR-0180's
	# claim ("both branches answer with the same population") holding on the route the bug
	# was reported on. The rebind is load-bearing on the OTHER route — the coordinator
	# mounts against an EMPTY overlay, and `FormationUnitClusterElementTest` went red with
	# "UnitInfoCluster missing" until the pair was built unbound and rebound here.
	#
	# Not vacuous: stubbing `_update_vitals_for_selection` to a bare `return` takes this to
	# 8/9 on the emptiness check below, before it ever reaches the name.
	var np_view: Dictionary = grid._cluster._nameplate_view as Dictionary
	_true("the docked pair is BOUND after the injection, not left for the first cursor move",
			not np_view.is_empty())
	var sel_idx: int = grid.selected_cell.y * grid.COLS + grid.selected_cell.x
	var shown: Array = grid._roster_characters()
	if not np_view.is_empty() and sel_idx >= 0 and sel_idx < shown.size():
		_eq("the vitals panel names the SELECTED owned unit, not a party-roster seed",
				String(np_view.get("name", "")), String(shown[sel_idx].display_name))


	# THE assertion. Everything above can be green on a black screen — that is the whole
	# history of this bug.
	var frac := await _lit_fraction()
	# Print it on GREEN too. A guard that only speaks when it fails cannot show drift, and
	# the number is the whole evidence here: ~89% is the screen, ~0.2% is the cover.
	print("  [render] Formation frame %.1f%% lit (bar %.0f%%)"
			% [frac * 100.0, MIN_NON_BLACK_FRACTION * 100.0])
	_true("Formation renders: %.1f%% of sampled pixels lit (bar %.0f%%)"
			% [frac * 100.0, MIN_NON_BLACK_FRACTION * 100.0],
			frac >= MIN_NON_BLACK_FRACTION)

	print("  [render] screen-in: %.1f%% lit early -> %.1f%% settled" % [early * 100.0, frac * 100.0])
	_true("the screen-in is ARMED on the player's route: %.1f%% lit early vs %.1f%% settled"
			% [early * 100.0, frac * 100.0],
			early < frac * 0.5)
	_verdict()


func _lit_fraction() -> float:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var lit := 0
	var total := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			total += 1
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > LIT_SUM:
				lit += 1
	return float(lit) / float(max(total, 1))


## Every live [ScreenOverlayQuad] anywhere under the navigator — the family this
## screen has to be clear of, counted by TYPE so a fifth overlay is covered on the day it
## is written rather than needing a new assertion.
func _count_screen_overlays() -> int:
	return _count_overlays_under(_nav)


func _count_overlays_under(node: Node) -> int:
	var n := 0
	if node is ScreenOverlayQuad:
		n += 1
	for child in node.get_children():
		n += _count_overlays_under(child)
	return n


## True if the beat this test seeks to carries a `{3E}` Color Screen, read off its own
## event chunk. This is what makes the route checkable instead of assumed: the cover under
## test only exists because that opcode ran, so a route whose beat has no `{3E}` cannot
## report this defect however green it comes out.
func _beat_raises_color_screen() -> bool:
	if _beat_scenario_id < 0:
		return false
	var path := "%s/scenario_%03d_chunk.json" % [CHUNK_DIR, _beat_scenario_id]
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		return false
	var chunk: Dictionary = JsonAsset.load_dict(path)
	for inst in chunk.get("instructions", []):
		if String((inst as Dictionary).get("name", "")) == "Color Screen":
			return true
	return false


func _timed_out() -> bool:
	return (Time.get_ticks_msec() - _start_ms) >= TIMEOUT_MS


func _find_world_map() -> Node:
	if _nav == null or not is_instance_valid(_nav):
		return null
	for child in _nav.get_children():
		if not (child is CanvasLayer):
			continue
		for gc in child.get_children():
			if gc.has_signal("dismissed") and "_standalone" in gc:
				return gc
	return null


## The mounted Formation SCREEN, and since ADR-0181 that is the ADR-0084 coordinator rather
## than the bare [FormationScene] — so the duck-type had to move off `set_owned_characters`,
## which is the roster grid's method and one the coordinator does not carry. `current_state()`
## is the coordinator's own seam; the `set_owned_characters` arm stays so this finder still
## answers on the view-only route (`FORMATION_VIEW_PATH`), which is still the bare scene.
func _find_formation() -> Node:
	if _nav == null or not is_instance_valid(_nav):
		return null
	for child in _nav.get_children():
		if child is Node3D and (child.has_method("current_state")
				or child.has_method("set_owned_characters")):
			return child
	return null


## The roster GRID inside whatever `_find_formation` returned. The coordinator owns a
## [FormationScene] as `_formation`; the bare scene IS one. Every assertion below about cells,
## selection and the docked pair is about the grid, not about the host.
func _grid_of(form: Node) -> Node:
	if form == null:
		return null
	return form._formation if "_formation" in form else form


func _verdict() -> void:
	if _failed > 0:
		print("[FAIL] NavigatorWorldMapFormationRenderTest — %d/%d"
				% [_passed, _passed + _failed])
		get_tree().quit(1)
		return
	print("[PASS] NavigatorWorldMapFormationRenderTest — %d/%d" % [_passed, _passed])
	get_tree().quit(0)


func _eq(what: String, got: Variant, want: Variant) -> void:
	if str(got) == str(want):
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s: got %s, want %s" % [what, got, want])


func _true(what: String, ok: bool) -> void:
	if ok:
		_passed += 1
		return
	_failed += 1
	print("  FAIL %s" % what)
