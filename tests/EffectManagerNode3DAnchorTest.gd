extends Node
# test-kind: logic
# seeded-break: put `Unit` back on EffectManager.gd's three spawn signatures (lines 62,
#   146, 272) — the literal #1219 revert. MEASURED, not predicted: see the red note in
#   the header for the exact verdict that seed produces.

## #1219's LOAD-AND-ASSERT witness: `EffectManager`'s three spawn entry points take a
## plain `Node3D` anchor, and the effect they build actually lands on it.
##
## WHY THIS TEST EXISTS AT ALL, AND WHY IT IS A PROCESS RATHER THAN A GUARD.
## ADR-0288 dec. 3 widened `spawn_spell_effect` / `spawn_cinematic_effect` /
## `spawn_item_effect` from `caster: Unit, target: Unit` to `Node3D`, taking
## `check_addon_portability.py` arm 7 — the addon naming a `class_name` declared
## OUTSIDE every addon root — to **0**. But ADR-0288 S2 is explicit that a duck-typed
## reach is INVISIBLE to every static instrument in the pre-flight, and gl-ADR-0295
## dec. 7 rules this item *verified by loading and asserting, not by scanning*. A
## `static-guard` would only re-read the annotation this change wrote; it cannot
## answer *does the spawn path work on something that is not a `Unit`?* — which is
## the only question the widening actually makes a claim about. So this is the
## cheapest kind that CAN still fail (charter clause 2), and the 737th process is
## bought deliberately by #1219's acceptance criteria.
##
## 🔴 ADR-0157 SPIKE A IS THE REASON IT ASSERTS RATHER THAN OBSERVES. Godot exits 0
## through a script that failed to bind and through a node that mounted stripped, so
## `rc` does not report either and neither does watching a scene come up. Every arm
## below reads state back off a live object: the instance's parent, its
## `global_position`, the anchor markers' names, and the weakrefs the palette
## subsystem tints through. `tests/BattlefieldAddonAddressTest.gd` is that shape and
## this file follows it.
##
## 🔴 WHAT A NEGATIVE RESULT LOOKS LIKE — AND THE FIRST ANSWER WAS A GREEN.
## Seeding the revert (see `# seeded-break:` above) puts `Unit` back on the three
## signatures, so every anchor this file passes is a bare `Node3D` and the engine
## refuses the call:
##
##     SCRIPT ERROR: Invalid type in function 'spawn_spell_effect' in base
##     'RefCounted (EffectManager.gd)'. The Object-derived class of argument 1
##     (Node3D) is not a subclass of the expected argument class.
##
## **A refused call ABORTS THE CALLING FUNCTION.** It does not raise, it does not
## return a default, and it does not reach the next line — so the first cut of this
## file, whose arms were `_check(...)` then `if …: return`, printed
##
##     === EffectManagerNode3DAnchorTest: 2 passed, 0 failed ===
##     [PASS] EffectManagerNode3DAnchorTest
##
## against the seed. 31 assertions became 2 and NOT ONE of them failed, because all
## three arms died at their `mgr.spawn_*` line before asserting anything. The suite's
## reader still scored it `THREW` (`tests/lib/verdict.sh` rule 9 — a green does not
## get to throw), but that verdict is a function of the engine's error COUNT, not of
## anything this file claims: raise the declared error budget and the same seed is a
## clean pass.
##
## `_arms_completed` is the repair. Each arm appends its own name as its LAST
## statement, and the summary asserts the set of three — so an aborted arm is a named
## red instead of a smaller total. That is the only structure under which "the total
## quietly dropped" cannot read as success, and it is why this file does not lean on
## an assertion-count floor: a count is a magic number, a completion set says which
## arm died. Re-measured against the same seed, the repaired file reads
##
##     [FAIL] all three spawn arms ran to their last line — an aborted call is not
##            a pass — expected ["spell", "cinematic", "item"], got []
##     === EffectManagerNode3DAnchorTest: 2 passed, 1 failed ===
##     [FAIL] EffectManagerNode3DAnchorTest
##
## which `tests/lib/verdict.sh` scores **FAIL** on rule 3, off this file's own
## assertion, rather than THREW off an engine error count.
##
## The point of the seed is also that it distinguishes THIS test from one that would
## have passed before the change too: an arm that spawns with a real `Unit` proves
## nothing about the widening, because a `Unit` satisfies both spellings.
##
## 🔴 AND THE ANCHORS ARE DELIBERATELY NOT UNITS. `StubCombatLoop` is a `Node3D`
## with the three members the spawn path actually touches — `units`, `_rlog`,
## `add_child` — and `get_test_name()`, which only the verbose branches call. Using
## the real `CombatLoop` would drag in the GPU battle and prove nothing extra: what
## is under test is the TYPE of the parameter, and the smallest object that can
## satisfy `Node3D` is the strongest witness that `Unit` was never needed.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/EffectManagerNode3DAnchorTest.tscn

const EffectManagerClass = preload("res://addons/exmateria_effects/cast/EffectManager.gd")

## Three effect directories that exist in `assets/effects/` — one per spawn entry
## point, so no arm borrows another's payload. `E260` is the item family
## `spawn_item_effect`'s own docstring names.
const SPELL_EFFECT_ID := 5
const CINEMATIC_EFFECT_ID := 71
const ITEM_EFFECT_DIR := 260

var _passed: int = 0
var _failed: int = 0

## Which arms ran to their last line. See the third red note: a refused call aborts
## its caller silently, so "every arm finished" has to be asserted, never assumed.
var _arms_completed: Array[String] = []


## The one `_base` member with behaviour, kept so an arm can assert the spawn path
## reached it: `spawn_spell_effect` calls `_base._rlog.log_effect` UNCONDITIONALLY
## (`spawn_item_effect` too), which means a row here is evidence the body ran at all
## — the difference between "the effect is missing" and "the call never happened".
class RecordingLog extends RefCounted:
	var rows: Array = []

	func log_effect(caster_idx: int, target_idx: int, id_str: String) -> void:
		rows.append([caster_idx, target_idx, id_str])


## Everything `_base` is, as far as the three spawn functions are concerned.
##
## 🔴 THE MEMBER LIST WAS MEASURED, NOT GUESSED. The first run of this file carried
## `units` / `_rlog` / `get_test_name` and the engine named the two it was missing:
## `_base.EFFECT_INITIAL_WAIT_SEC` (`EffectManager.gd:427`, the cleanup poll's first
## sleep) and `_base.map` (`:189`, the cinematic camera's map-bounds read). Both are
## `CombatLoop`'s and neither is touched by the annotations under test, so they are
## here as the smallest thing that lets the spawn path run to completion. `map = null`
## is a REAL state, not a shortcut: `:189` reads `if _base.map and …`, so a null map
## takes the documented no-bounds branch rather than a stubbed-out one.
class StubCombatLoop extends Node3D:
	var units: Array = []
	var _rlog
	var map = null
	const EFFECT_INITIAL_WAIT_SEC: float = 0.5

	func get_test_name() -> String:
		return "EffectManagerNode3DAnchorTest"


func _ready() -> void:
	var base := StubCombatLoop.new()
	base.name = "StubCombatLoop"
	base._rlog = RecordingLog.new()
	add_child(base)

	# Bare Node3Ds, at distinct positions so "the effect landed on the caster" is a
	# DISCRIMINATING read rather than one that Vector3.ZERO would satisfy by accident.
	var caster := _anchor(base, "CasterAnchor", Vector3(1.0, 0.0, 2.0))
	var target := _anchor(base, "TargetAnchor", Vector3(4.0, 0.0, 6.0))
	base.units = [caster, target]

	_check("the anchors are NOT Units — the whole premise of the widening",
		(caster is Unit) or (target is Unit), false)
	_check("they ARE Node3Ds", (caster is Node3D) and (target is Node3D), true)

	var mgr = EffectManagerClass.new(base)

	_spell_arm(base, mgr, caster, target)
	_cinematic_arm(base, mgr, caster, target)
	_item_arm(base, mgr, target)

	# THE ANTI-VACUITY ARM, and the one the seed is measured against.
	_check("all three spawn arms ran to their last line — an aborted call is not a pass",
		_arms_completed, ["spell", "cinematic", "item"] as Array[String])

	print("\n=== EffectManagerNode3DAnchorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0:
		print("[FAIL] EffectManagerNode3DAnchorTest asserted NOTHING")
		get_tree().quit(1)
	elif _failed > 0:
		print("[FAIL] EffectManagerNode3DAnchorTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectManagerNode3DAnchorTest")
		get_tree().quit(0)


## Arm 1 — `spawn_spell_effect`, the entry point with both parameters and the only
## one that calls `attach_anchors_to_units`.
func _spell_arm(base: Node3D, mgr, caster: Node3D, target: Node3D) -> void:
	var before := _effects_under(base).size()
	mgr.spawn_spell_effect(caster, target, -1, SPELL_EFFECT_ID)

	_check("spell: the body RAN (the unconditional _rlog row is there)",
		base._rlog.rows.size(), 1)
	if base._rlog.rows.size() == 1:
		var row: Array = base._rlog.rows[0]
		# find() over `units` is how the spawn path indexes the anchors; a Node3D
		# has to be findable in that Array for the log row to be right.
		_check("spell: _base.units.find() located the Node3D caster", row[0], 0)
		_check("spell: ...and the Node3D target", row[1], 1)
		_check("spell: the effect id string is the one asked for", row[2], "E005")

	var spawned := _effects_under(base)
	_check("spell: exactly one EffectInstance was parented to _base",
		spawned.size(), before + 1)
	if spawned.is_empty():
		return
	var effect: Node3D = spawned[spawned.size() - 1]

	_check("spell: the instance is IN the tree, not orphaned", effect.is_inside_tree(), true)
	_check("spell: its parent is _base, not the root viewport (#121)",
		effect.get_parent() == base, true)
	_check("spell: it landed on the CASTER's global_position",
		effect.global_position, caster.global_position)

	# The anchor markers are the acceptance criterion's "parented to the anchor".
	var origin := caster.get_node_or_null("EffectOriginAnchor")
	var tgt := target.get_node_or_null("EffectTargetAnchor")
	_check("spell: an origin marker is parented to the Node3D caster", origin != null, true)
	_check("spell: a target marker is parented to the Node3D target", tgt != null, true)
	if origin != null:
		_check("spell: the origin marker sits at the caster's origin",
			(origin as Node3D).global_position, caster.global_position)
	if tgt != null:
		_check("spell: the target marker sits at the target's origin",
			(tgt as Node3D).global_position, target.global_position)

	# set_unit_targets takes the anchors as the palette subsystem's tint subjects.
	# A weakref that resolves back to the bare Node3D is the read that shows the
	# spawn path never required a `Unit` anywhere downstream either.
	_check("spell: the caster weakref resolves to the Node3D we passed",
		effect.caster_unit != null and effect.caster_unit.get_ref() == caster, true)
	_check("spell: the target weakref resolves to the Node3D we passed",
		effect.target_unit != null and effect.target_unit.get_ref() == target, true)
	_arms_completed.append("spell")


## Arm 2 — `spawn_cinematic_effect`, the only one that RETURNS the instance.
func _cinematic_arm(base: Node3D, mgr, caster: Node3D, target: Node3D) -> void:
	var before := _effects_under(base).size()
	var effect = mgr.spawn_cinematic_effect(caster, target, -1, CINEMATIC_EFFECT_ID)

	_check("cinematic: the call returned an instance", effect != null, true)
	if effect == null:
		return
	_check("cinematic: one more EffectInstance under _base",
		_effects_under(base).size(), before + 1)
	_check("cinematic: the returned instance is the one in the tree",
		effect.get_parent() == base, true)
	_check("cinematic: it opted out of combat_visuals (ADR-0037 dec. 7)",
		effect.is_cinematic, true)
	_check("cinematic: it landed on the CASTER's global_position",
		effect.global_position, caster.global_position)
	_check("cinematic: an origin marker is parented to the Node3D caster",
		caster.get_node_or_null("EffectOriginAnchor") != null, true)
	_arms_completed.append("cinematic")


## Arm 3 — `spawn_item_effect`, the single-parameter one. It also reads `target.name`
## in its verbose branch, which is a `Node` member and so is covered by the widening.
func _item_arm(base: Node3D, mgr, target: Node3D) -> void:
	var before := _effects_under(base).size()
	var rows_before: int = base._rlog.rows.size()
	mgr.spawn_item_effect(target, ITEM_EFFECT_DIR)

	_check("item: the body RAN (one more _rlog row)",
		base._rlog.rows.size(), rows_before + 1)
	if base._rlog.rows.size() > rows_before:
		var row: Array = base._rlog.rows[base._rlog.rows.size() - 1]
		_check("item: the caster index is the documented -1", row[0], -1)
		_check("item: the Node3D target was found in _base.units", row[1], 1)
		_check("item: the effect id string is E260", row[2], "E260")

	var spawned := _effects_under(base)
	_check("item: one more EffectInstance under _base", spawned.size(), before + 1)
	if spawned.size() <= before:
		return
	var effect: Node3D = spawned[spawned.size() - 1]
	_check("item: its parent is _base", effect.get_parent() == base, true)
	_check("item: it landed on the TARGET's global_position",
		effect.global_position, target.global_position)
	# `set_unit_targets(null, target)` — the caster half is deliberately absent here,
	# which is the arm that shows the null branch still works after the widening.
	_check("item: there is no caster weakref", effect.caster_unit == null, true)
	_check("item: the target weakref resolves to the Node3D we passed",
		effect.target_unit != null and effect.target_unit.get_ref() == target, true)
	_arms_completed.append("item")


## A bare Node3D at a known place. Deliberately NOT a `Unit` — see the header.
func _anchor(parent: Node3D, node_name: String, where: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	parent.add_child(n)
	n.global_position = where
	return n


## Every EffectInstance currently parented to `base`, in child order. Identified by
## script path rather than by `class_name`: the addon publishes `EffectInstance`
## through its façade and does not declare it engine-globally (ADR-0212 dec. 1).
func _effects_under(base: Node3D) -> Array:
	var out: Array = []
	for child in base.get_children():
		var scr: Script = child.get_script()
		if scr != null and scr.resource_path.ends_with("/cast/EffectInstance.gd"):
			out.append(child)
	return out


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
