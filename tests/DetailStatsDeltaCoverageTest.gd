extends Node3D

## Full-band-coverage equip stat-delta PREVIEW rendering (EQUIP_STAT_PREVIEW.md "full coverage").
## The picker preview must paint a signed delta on EVERY band field the equip changes — not just the
## Weap.Power row. Blocks: Move/Jump/Speed (block 1) and the AT row's AT · C-EV · S-EV · A-EV (block 3).
## A shield swap shows S-EV; a speed hat shows Speed; a PA hat feeds AT. Job-only C-EV always dashes.
##
## Seam: DetailScene.set_stats_preview_delta(delta, slot) + the render-readback
## stat_delta_preview_strings() -> {move,jump,speed,r_at,l_at,c_ev,s_ev,a_ev} (the exact strings painted:
## "+N"/"-N"/"-"). Drives DetailScene directly (no picker), like DetailStatsElementTest.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression


const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 16, "l_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0,
}

var _passed := 0
var _failed := 0


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [x] " + msg)


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- SHIELD into L.Hand: S-EV +19 shows; Move/Jump/Speed dash; C-EV always dashes. ---
	d.set_stats_preview_delta(_delta({"s_ev": 19}), UnitProgression.EquipSlot.LEFT_HAND)
	await get_tree().process_frame
	var s: Dictionary = d.stat_delta_preview_strings()
	_expect(s.get("s_ev") == "+19", "shield: S-EV should paint '+19', got %s" % s.get("s_ev"))
	_expect(s.get("c_ev") == "-", "C-EV is job-only → always '-', got %s" % s.get("c_ev"))
	_expect(s.get("move") == "-", "shield: Move unchanged → '-', got %s" % s.get("move"))
	_expect(s.get("speed") == "-", "shield: Speed unchanged → '-', got %s" % s.get("speed"))
	_expect(s.get("a_ev") == "-", "shield: A-EV unchanged → '-', got %s" % s.get("a_ev"))

	# --- SPEED hat into HEAD: Speed +2 shows; S-EV dashes. ---
	d.set_stats_preview_delta(_delta({"speed": 2}), UnitProgression.EquipSlot.HEAD)
	await get_tree().process_frame
	s = d.stat_delta_preview_strings()
	_expect(s.get("speed") == "+2", "speed hat: Speed should paint '+2', got %s" % s.get("speed"))
	_expect(s.get("s_ev") == "-", "speed hat: S-EV unchanged → '-', got %s" % s.get("s_ev"))

	# --- PA hat into HEAD: AT gains PA (+2) on the R row. ---
	d.set_stats_preview_delta(_delta({"pa": 2}), UnitProgression.EquipSlot.HEAD)
	await get_tree().process_frame
	s = d.stat_delta_preview_strings()
	_expect(s.get("r_at") == "+2", "PA hat: AT (R) should paint '+2', got %s" % s.get("r_at"))

	# --- WEAPON into R.Hand: AT DASHES (the Weap.Power row shows the +N; ROM dashes AT here, doc §6). ---
	d.set_stats_preview_delta(_delta({"wp": 4}), UnitProgression.EquipSlot.RIGHT_HAND)
	await get_tree().process_frame
	s = d.stat_delta_preview_strings()
	_expect(s.get("r_at") == "-", "weapon swap: AT column should dash (Weap.Power row covers it), got %s" % s.get("r_at"))

	# --- NEGATIVE: downgrading the shield → S-EV '-5' (red path uses the '-' sign string). ---
	d.set_stats_preview_delta(_delta({"s_ev": -5}), UnitProgression.EquipSlot.LEFT_HAND)
	await get_tree().process_frame
	s = d.stat_delta_preview_strings()
	_expect(s.get("s_ev") == "-5", "downgrade: S-EV should paint '-5', got %s" % s.get("s_ev"))

	# --- PLAIN dash preview (no delta values, e.g. remove-on-empty) still all dashes. ---
	d.set_stats_preview(true)
	await get_tree().process_frame
	s = d.stat_delta_preview_strings()
	_expect(s.get("s_ev") == "-" and s.get("speed") == "-" and s.get("r_at") == "-",
		"plain preview should dash every field, got %s" % s)

	d.queue_free()
	print("\n=== DetailStatsDeltaCoverageTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailStatsDeltaCoverageTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailStatsDeltaCoverageTest: full-band delta preview (S-EV/Speed/Move/AT), C-EV dashes")
		get_tree().quit(0)


## Build a full delta dict with the given overrides; unset fields are 0 (→ dashed).
func _delta(over: Dictionary) -> Dictionary:
	var base := {"wp": 0, "wev": 0, "hp": 0, "mp": 0, "move": 0, "jump": 0, "speed": 0, "pa": 0, "s_ev": 0, "a_ev": 0}
	for k in over:
		base[k] = over[k]
	return base
