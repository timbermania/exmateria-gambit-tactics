extends Node3D

## ADR-0088 migration guard: the Eqp/Ability lower panel group (frame chrome + column
## bands + title tabs + slot/ability icons + equipped-item column) is the registered
## element `detail.lower` (the old hand-rolled _lower_origin group).
##   1. IDENTITY — lower_element() returns the registered element (id "detail.lower"),
##      distinct from detail.stats.
##   2. ENGINE CLIP — shutting the windows (set_open_frame(-1)) lands the SHUT clip box
##      on EVERY lower payload material via the clip engine's subtree discovery (the
##      hand _lower_mats/_equip_item_mats clip pushes retire). The corner pager buttons
##      stay OUTSIDE the element (never box-open-clipped, §15.22).
##   3. MOUNT COVERAGE (the stale-clip kill) — rebuilding the equipped-item column while
##      SHUT (set_stats_view) leaves the fresh icon/name materials carrying the shut
##      aperture too.
##   4. SWEEP APERTURE — the settled aperture covers the drawn lower chrome AND the
##      full-width §15.17 sweep container (wider than the chrome; aperture_pad).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailLowerElementTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _EQ_A := [{"name": "Broad Sword", "palette": 0, "icon_graphic": -1}, {},
	{"name": "Leather Hat", "palette": 4, "icon_graphic": -1}, {}, {}]
const _EQ_B := [{"name": "Mythril Knife", "palette": 0, "icon_graphic": -1},
	{"name": "Escutcheon", "palette": 5, "icon_graphic": -1}, {}, {}, {}]

var _passed := 0
var _failed := 0


func _view(eq: Array) -> Dictionary:
	return {
		"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
		"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0, "equipment": eq,
	}


func _ready() -> void:
	for slug: String in ["detail.stats_frame_x", "detail.stats_frame_y", "detail.lower_frame_x",
			"detail.lower_frame_y", "detail.lower_frame_w", "detail.lower_frame_h"]:
		Tune.clear(slug)

	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_view(_EQ_A))
	await get_tree().process_frame
	await get_tree().process_frame

	# --- 1. identity -------------------------------------------------------------
	if not d.has_method("lower_element"):
		_expect(false, "lower_element() missing — lower panel not migrated to a registered element")
	else:
		var e: UI3Element = d.call("lower_element")
		_expect(e != null and is_instance_valid(e), "lower_element() returned null")
		if e != null:
			_expect(e.id() == "detail.lower", "element id %s != detail.lower" % e.id())
			_expect(e != d.stats_element(), "lower element must be distinct from detail.stats")

			# --- Amendment 4 §2: detail.lower DECLARES the UNION of all three mode
			# frames' drivers (LOWER_FRAME / _EQUIP / _ABILITY) — mode-dependent eval, but a
			# STABLE row set (beats a live-changing one). Was a bare Callable dead-end.
			var l_drivers := _rect_drivers(e)
			for base in ["detail.lower_frame", "detail.lower_frame_equip", "detail.lower_frame_ability"]:
				for c in ["x", "y", "w", "h"]:
					_expect(l_drivers.has("%s_%s" % [base, c]),
						"detail.lower must declare driver %s_%s, got %s" % [base, c, l_drivers])

			# --- 4. sweep aperture (settled) ---------------------------------------
			var ap := Rect2(e.aperture()).grow(1.0)
			_expect(ap.encloses(Rect2(DetailScene.LOWER_FRAME)),
				"settled aperture %s does not cover the lower chrome %s" % [ap, DetailScene.LOWER_FRAME])
			_expect(ap.size.x >= 249.0,
				"settled aperture width %.1f < the full-width §15.17 sweep (~250)" % ap.size.x)

			# --- 2. engine clip: shut → every payload material carries the shut box --
			var mats := e.payload_materials()
			_expect(mats.size() >= 15,
				"lower payload discovery found only %d materials (frame+bands+tabs+icons+items expected)"
				% mats.size())
			d.set_open_frame(-1)
			_expect(_all_shut(mats), "shut aperture did not reach every lower payload material")
			# The §15.22 pager buttons are NOT part of the box-open group — never shut.
			var pager: Array = d.debug_pager_button_materials()
			_expect(pager.size() > 0, "pager buttons missing (precondition)")
			for pm in pager:
				var cw = pm.get_shader_parameter("clip_world")
				_expect(cw == null or cw.x < 1e19, "pager button was box-open-clipped (must stay outside)")

			# --- 3. mount coverage: rebuild equip items while shut → fresh mats shut --
			d.set_stats_view(_view(_EQ_B))
			await get_tree().process_frame
			await get_tree().process_frame
			var fresh := e.payload_materials()
			_expect(fresh.size() >= 15, "rebuild dropped the lower payload (%d mats)" % fresh.size())
			_expect(_all_shut(fresh),
				"freshly mounted equip-item materials missed the SHUT aperture (stale-clip class)")

			# reopen fully — the settled aperture returns
			d.set_open_frame(1000)
			_expect(not _all_shut(e.payload_materials()), "settled reopen left the lower panel clipped shut")

	d.queue_free()
	print("\n=== DetailLowerElementTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailLowerElementTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailLowerElementTest: detail.lower registered element (engine clip + pager exempt + mount coverage + sweep aperture)")
		get_tree().quit(0)


## The declared driver slugs of an element's rect answer ([] when not derived).
func _rect_drivers(e: UI3Element) -> Array:
	for r: Dictionary in e.criteria():
		if String(r["field"]) == "rect":
			return r.get("drivers", [])
	return []


func _all_shut(mats: Array) -> bool:
	if mats.is_empty():
		return false
	for m in mats:
		var cw = m.get_shader_parameter("clip_world")
		if cw == null or cw.x < 1e19:
			return false
	return true


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[DetailLowerElementTest] " + msg)
		print("  [x] " + msg)
