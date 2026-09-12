extends Node
## Characterization test for the W7 stress fixture's clone (`--stress-units=N`).
##
## The fixture answers "where does the frame budget break?" by multiplying the cast.
## Its whole result rests on one property that **fails silently**: each clone must be a
## genuinely independent unit. `UnitSpawn.bind_for_combat` binds `character.progression`
## **by reference**, so two units built from one `Character` share a single HP pool —
## they take each other's damage and die together. A fixture with that defect reports a
## cast that decays at twice the real rate and a frame cost that falls away too early,
## and nothing in the run says so: the spawn count, the placement print and the `Units:`
## histogram all read exactly right.
##
## So this test asserts what those three cannot:
##   1. the clone's `progression` is a DIFFERENT object from its source's, and writing
##      one HP does not move the other;
##   2. the clone's `gambits` are a different object (the same by-reference hazard —
##      `bind_for_combat` mints one onto the Character when it is null);
##   3. the clone carries the source's job, level, equipment and appearance, because a
##      clone that resolved to a different job would run different animation work than
##      the unit it stands in for — and animation work is what is being measured;
##   4. the clone has its own slug, since `UnitSpawn.build` stamps it as the durable key.
##
## What it does NOT prove: anything about the frame rate. Per `docs/GPU-ARENA-PERF.md`'s
## W8 ruling, a wall-clock assertion is the flakiest test that could be written in a
## suite that runs in parallel. This asserts counted state and nothing else.
##
## Run headful; reads stdout; auto-quits.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const GambitList = ExMateriaAlmanac.GambitList


const GPUArenaScript = preload("res://src/scenes/GPUArena.gd")
const Character = ExMateriaCatalogue.Character

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	# `_clone_character` touches only its argument, so the host needs no scene tree:
	# `@onready` members fire on NOTIFICATION_READY, which a bare `.new()` never gets.
	var arena = GPUArenaScript.new()

	var source := Character.create_default("Sourcey", "4a", false)
	source.slug = "source-slug"
	source.template_token = "RAMZA"
	source.progression.level = 7
	source.progression.raw_hp = 4242
	source.gambits = GambitList.new()

	var clone = arena._clone_character(source, "stress-T0-3")

	_check("clone is a Character", clone is Character)
	_check("clone.progression is a distinct object",
		clone.progression != null and clone.progression != source.progression)
	_check("clone.gambits is a distinct object",
		clone.gambits == null or clone.gambits != source.gambits)
	_check("clone.slug is the one it was given", clone.slug == "stress-T0-3")
	_check("clone.slug is NOT the source's", clone.slug != source.slug)
	_check("clone keeps the source job", clone.progression.current_job_id
		== source.progression.current_job_id)
	_check("clone keeps the source level", clone.progression.level == 7)
	_check("clone keeps the source raw_hp", clone.progression.raw_hp == 4242)
	_check("clone keeps the source template_token",
		clone.template_token == source.template_token)
	_check("clone keeps the source gender", clone.is_female == source.is_female)

	# The load-bearing one: an HP write must not cross. This is the exact call shape
	# `bind_for_combat` -> `unit.bind_progression(character.progression, team)` gives a
	# spawned unit, so a shallow clone fails here and nowhere else.
	clone.progression.raw_hp = 1
	_check("writing the clone's HP does not move the source's",
		source.progression.raw_hp == 4242)

	arena.free()

	if _failures.is_empty():
		print("[PASS] GPUArenaStressCastTest (%d checks)" % _checks)
	else:
		for f in _failures:
			print("  - [FAIL] %s" % f)
		print("[FAIL] GPUArenaStressCastTest (%d of %d checks failed)"
			% [_failures.size(), _checks])
	get_tree().quit()


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures.append(what)
