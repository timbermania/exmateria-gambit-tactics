extends Node
# test-kind: logic
# seeded-break: vitals_view_from_character's out-of-battle `has_ct` flipped false -> true (the documented earlier battle-derived bug) — all three CT arms RED ('has_ct=false' flag, 'ct bar must be FULL frac 1.0' got 0.0, 'ct must be the dash row'); every HP/MP-full, identity/level/exp/brave/faith, and sprite/job-resolution arm stays green; GREEN unbroken on the reverted tree

## FormationScene vitals-view mapping test (#175) — pure GDScript, no GPU.
##
## Guards the roster-Character -> UIUnitInfoWindow view dict (the wiring #175 adds
## to reuse the already-solved battle vitals panel). The panel itself and its
## bar/fill maths are covered by UnitInfoPresenterTest; here we only assert the
## Formation screen feeds it the right roster values:
##   * roster units are OUT of battle -> full HP/MP (current == max == effective),
##   * no battle CT out of formation -> ct 0 (empty CT bar),
##   * identity/level/exp/brave/faith/sprite_id come straight off the Character.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const JobDatabase = ExMateriaAlmanac.JobDatabase


const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const Character = ExMateriaCatalogue.Character
func _ready() -> void:
	var failed := false

	# A default roster Squire (hex job id 4a), male.
	var c: Character = Character.create_default("Ramza", "4a", false)
	var prog = c.progression
	var view: Dictionary = FormationScene.vitals_view_from_character(c)

	# 1. HP/MP are FULL: current == max == the progression's effective stat.
	var eff_hp: int = prog.get_effective_hp()
	var eff_mp: int = prog.get_effective_mp()
	if view["current_hp"] != eff_hp or view["max_hp"] != eff_hp:
		print("[FAIL] hp not full: cur=%s max=%s eff=%d" %
			[view["current_hp"], view["max_hp"], eff_hp]); failed = true
	if view["current_mp"] != eff_mp or view["max_mp"] != eff_mp:
		print("[FAIL] mp not full: cur=%s max=%s eff=%d" %
			[view["current_mp"], view["max_mp"], eff_mp]); failed = true

	# 2. No battle CT for a roster unit -> has_ct false (-> "---/---" + FULL bar,
	#    matching the oracle §14.4; NOT ct 0 / empty, which was the earlier battle-derived bug).
	if bool(view.get("has_ct", true)):
		print("[FAIL] roster ct expected has_ct=false, got %s" % view.get("has_ct")); failed = true

	# 3. Identity + progression pass through.
	if view["name"] != "Ramza":
		print("[FAIL] name: %s" % view["name"]); failed = true
	if int(view["level"]) != prog.level or int(view["exp"]) != prog.experience:
		print("[FAIL] level/exp: %s/%s" % [view["level"], view["exp"]]); failed = true
	if int(view["brave"]) != prog.brave or int(view["faith"]) != prog.faith:
		print("[FAIL] brave/faith: %s/%s" % [view["brave"], view["faith"]]); failed = true

	# 4. Sprite id + job name resolve through the shared JobDatabase (same path the
	#    cell body uses), so the panel portrait/label agree with the grid.
	if int(view["sprite_id"]) != JobDatabase.get_sprite_id("4a", false):
		print("[FAIL] sprite_id: %s" % view["sprite_id"]); failed = true
	var job: Dictionary = JobDatabase.get_job("4a")
	if view["job"] != job.get("name", "4a"):
		print("[FAIL] job name: %s (want %s)" % [view["job"], job.get("name", "4a")]); failed = true

	# 5. The presenter consumes it without divide-by-zero, HP reads full, and CT is the
	#    out-of-battle DASH row: FULL bar + a "dashes" flag (renders "---/---" §14.4).
	var m: Dictionary = UnitInfoPresenter.build(view)
	if not is_equal_approx(m["hp"]["frac"], 1.0):
		print("[FAIL] hp frac not full: %s" % m["hp"]["frac"]); failed = true
	if not is_equal_approx(m["ct"]["frac"], 1.0):
		print("[FAIL] roster ct bar must be FULL (frac 1.0), got %s" % m["ct"]["frac"]); failed = true
	if not bool(m["ct"].get("dashes", false)):
		print("[FAIL] roster ct must be the dash row (dashes=true)"); failed = true

	if failed:
		print("[FAIL] FormationVitalsView test")
	else:
		print("[PASS] FormationVitalsView: full HP/MP, empty CT, identity/sprite/job passthrough")
	get_tree().quit()
