extends Node3D
# test-kind: logic
# seeded-break: split the single concurrent EQUIP group into two sequential groups (Group.new([equip_chrome], ...forward, ...reverse), then Group.new([equip_slide])) — the pre-concurrent-merge shape where the roster un-slide waits for the chrome to finish instead of playing with it; the 'EQUIP should be 1 concurrent group {chrome, split}, got 2' and 'EQUIP group 0 should be the concurrent {chrome, split} (2 beats), got 1' asserts red, the table-exists / fully-reversible audit / id-presence / CHANGE_JOB 2-group structure asserts stay green

## ADR-0084 invariant 1 (reversibility is TOTAL) mechanized at the coordinator: the recipes the
## FormationDetailTransition coordinator can `enter` are all present in one table and every beat in
## them carries a reverse driver. A forgotten exit — a beat with no reverse — fails HERE (a boot-time
## audit), not at the user's first Esc. As screens are ported onto the engine this guard grows; today
## it pins the recipe table exists, audits clean, and holds the ported screens' recipes.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const TransitionEngine = preload("res://src/ui3/formation/FormationTransitionEngine.gd")

var _failed := false


func _ready() -> void:
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame

	var recipes: Array = host.recipe_table()
	_expect(not recipes.is_empty(), "coordinator exposes no recipe table")

	# Every recipe is fully reversible — no beat lacks a reverse driver (invariant 1).
	var errors: Array = TransitionEngine.audit(recipes)
	_expect(errors.is_empty(), "recipe table is NOT fully reversible: %s" % str(errors))

	# The ported screens' recipes are present by id.
	var ids: Array = []
	for r in recipes:
		ids.append(r.id)
	_expect(ids.has("EQUIP"), "EQUIP recipe missing from the table (ids=%s)" % str(ids))
	_expect(ids.has("CHANGE_JOB"), "CHANGE_JOB recipe missing from the table (ids=%s)" % str(ids))

	# CHANGE_JOB is `[{chrome, split}, [ring]]` — TWO groups now: the chrome raise/descend and the roster
	# split are ONE CONCURRENT group (they play together, user 2026-08-08), then the ring is its own group.
	# The ring beat's reverse (the spin-fling) is a DISTINCT driver with its own duration; the chrome beat
	# descends on reverse — the audit passes both (a reverse exists), which is the invariant. EQUIP is the
	# single concurrent group `[{chrome, split}]` — 1 group.
	for r in recipes:
		if r.id == "CHANGE_JOB":
			_expect(r.groups.size() == 2, "CHANGE_JOB should be 2 groups ({chrome,split}, ring), got %d" % r.groups.size())
			_expect(r.groups[0].beats.size() == 2,
				"CHANGE_JOB group 0 should be the concurrent {chrome, split} (2 beats), got %d" % r.groups[0].beats.size())
		if r.id == "EQUIP":
			_expect(r.groups.size() == 1, "EQUIP should be 1 concurrent group {chrome, split}, got %d" % r.groups.size())
			_expect(r.groups[0].beats.size() == 2,
				"EQUIP group 0 should be the concurrent {chrome, split} (2 beats), got %d" % r.groups[0].beats.size())

	if _failed:
		print("[FAIL] FormationRecipeAudit test")
	else:
		print("[PASS] FormationRecipeAudit: recipe table present, fully reversible (invariant 1), EQUIP recipe registered (ADR-0084)")
	host.queue_free()
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
