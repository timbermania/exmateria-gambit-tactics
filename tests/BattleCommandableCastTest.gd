extends Node
# test-kind: logic
# seeded-break: in `BattleDeployment.control_count` return 0 unconditionally — the ENTD writer stops naming anybody and Orbonne (root 3) drops into the roster-fed arm, which it cannot satisfy (`has_zone` is false for a control>0 battle), so the census reds with root 3 named. A second, independent seed: add a root to `NAMED_EMPTY` that is NOT empty and the register's shrink-only arm reds — a stale exemption is itself the error, exactly as `charter_allowlist.tsv` treats one.
## EVERY SHIPPING BATTLE HANDS THE PLAYER SOMEBODY — the census ADR-0265 Amendment 1 asks
## for: *"An empty steerable set stays legal but must be named, and is guarded by one test
## over every shipping battle root — no combat needed, it asserts on the composed teams."*
##
## [b]Two writers, one fact[/b] (`docs/context/41-battle-mode-and-handback.md` →
## **Commandable**). A battle names a commandable cast through exactly one of them:
##
##   - the **ENTD** writer — a control-flagged slot, which `BattleDeployment.control_count`
##     reads and `is_predetermined` is defined as. Orbonne (ENTD 387) is the only battle in
##     the game that uses it, and it names three: Ramza, Delita and Algus.
##   - the **roster** writer — deployment onto the battle's own zone, which needs a zone
##     with tiles in it (`DeploymentZoneDatabase.has_zone`). Every other battle.
##
## A battle that satisfies NEITHER hands the player nobody, and that is the shape of the
## Orbonne defect one level up from where it bit: the host read the roster writer on a
## battle fed by the ENTD one.
##
## [b]This is the DATA half and it is not the whole guard.[/b] It proves the two writers
## can name a cast for every root; it cannot prove the host CONSULTS them, which is a
## different claim and a different process — [NavigatorOrbonneBattleModeTest] (the ENTD
## writer, live) and [NavigatorTurnStopTest] (the roster writer, live). A pure predicate
## tested alone proves the decision, not that anybody asks it.
##
## No world, no GPU, no combat: it reads the shipped tables through the production
## accessors and nothing else.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/BattleCommandableCastTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface; one alias line per
# file keeps the use sites spelled the way every other consumer spells them.
const DeploymentZoneDatabase = ExMateriaAlmanac.DeploymentZoneDatabase
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase

## Battle roots that legitimately name NO commandable cast. SHRINK-ONLY, and empty today:
## a row here is a battle the player cannot steer a single unit in, so it wants a ticket,
## not a habit. A stale row — a root listed here that CAN name a cast — is itself an error,
## the same rule `tests/charter_allowlist.tsv` runs on.
const NAMED_EMPTY: Array[int] = []

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var roots := _battle_roots()
	_true(roots.size() > 50,
		"the walk graph carries the game's battle groups — %d root(s)" % roots.size())

	var empty: Array[int] = []
	var by_entd := 0
	var by_roster := 0
	for root in roots:
		var writer := _writer_for(root)
		match writer:
			"entd": by_entd += 1
			"roster": by_roster += 1
			_: empty.append(root)

	# Every root is answered by exactly one of the two writers, or it is named below.
	_true(empty == NAMED_EMPTY,
		"every battle root names a commandable cast — unnamed empties: %s" % str(
			_difference(empty, NAMED_EMPTY)))
	# The register is shrink-only: a listed root that CAN name a cast is a stale exemption.
	_true(_difference(NAMED_EMPTY, empty).is_empty(),
		"no stale entry in NAMED_EMPTY — %s can name a cast now" % str(
			_difference(NAMED_EMPTY, empty)))

	# BOTH writers are exercised by the corpus, or one of the two arms above is vacuous.
	_true(by_entd > 0, "some battle is fed by the ENTD writer — %d of them" % by_entd)
	_true(by_roster > 0, "some battle is fed by the roster writer — %d of them" % by_roster)

	# THE ONE PREDETERMINED BATTLE, by name and by count. ADR-0265 Amendment 1 rests on
	# Orbonne being the single control>0 battle and on its cast being three units; both are
	# read off the ROM tables here rather than trusted.
	_eq(by_entd, 1, "exactly ONE battle in the game is ENTD-fed (Orbonne)")
	_eq(_writer_for(3), "entd", "Orbonne (root 3) is the ENTD-fed one")
	_eq(BattleDeployment.control_count(_entd_for(3)), 3,
		"Orbonne's ENTD names three control-flagged slots (Ramza, Delita, Algus)")
	_eq(_control_uids(_entd_for(3)), [0x01, 0x02, 0x04],
		"and they are event uids 0x01 / 0x02 / 0x04")

	print("\n=== BattleCommandableCastTest: %d passed, %d failed (%d roots: %d entd, %d roster) ==="
		% [_passed, _failed, roots.size(), by_entd, by_roster])
	if _passed == 0 and _failed == 0:
		print("[FAIL] BattleCommandableCastTest: ran zero assertions"); get_tree().quit(1); return
	if _failed > 0:
		print("[FAIL] BattleCommandableCastTest"); get_tree().quit(1)
	else:
		print("[PASS] BattleCommandableCastTest"); get_tree().quit(0)


## Every group root the walk graph calls a BATTLE, derived the way the walk derives it:
## `beats_for_group` builds a battle group's beats with `GameState.State.BATTLE` forced on
## them, and a cinematic group's from its members' own node kinds. Reading the state off
## the production beat rather than re-testing `kind == "battle"` here keeps this test from
## becoming a second, divergent copy of that rule.
func _battle_roots() -> Array[int]:
	var nav := GameNavigator.new()
	var out: Array[int] = []
	for group in ScenarioGroupDatabase.all_groups():
		var root := int(group.get("group_root_id", -1))
		if root < 0:
			continue
		var beats: Array = nav.beats_for_group(root)
		if beats.is_empty():
			continue
		if int(beats[0].get("state", -1)) == GameState.State.BATTLE:
			out.append(root)
	return out


## Which writer can name this battle's commandable cast: `"entd"`, `"roster"`, or `""` for
## neither. The ENTD is asked FIRST because `is_predetermined` is what decides the host's
## whole deployment path — a control>0 battle has nothing to deploy, so its zone is not
## consulted and must not be.
func _writer_for(root: int) -> String:
	if BattleDeployment.control_count(_entd_for(root)) > 0:
		return "entd"
	var scenario: Dictionary = ScenarioDatabase.get_scenario(root)
	return "roster" if DeploymentZoneDatabase.has_zone(
		int(scenario.get("first_squad_deployment_idx", 0))) else ""


func _entd_for(root: int):
	var scenario: Dictionary = ScenarioDatabase.get_scenario(root)
	return EntdBattle.record(str(int(scenario.get("entd_idx", 256))))


## The control-flagged slots' event uids, SORTED — the cast the ENTD writer hands the
## player. Sorted so the arm is about the SET and not about ENTD slot order, which is a
## different fact and not this test's.
func _control_uids(entd_record) -> Array:
	var out: Array = []
	if entd_record == null:
		return out
	for slot in entd_record.get("slots", []):
		var uid := int(slot.get("unit_id", 0xFF))
		if uid == 0xFF:
			continue
		if bool(slot.get("flags2_decoded", {}).get("control", false)):
			out.append(uid)
	out.sort()
	return out


func _difference(a: Array, b: Array) -> Array:
	var out: Array = []
	for v in a:
		if not b.has(v):
			out.append(v)
	return out


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(condition: bool, name: String) -> void:
	_eq(condition, true, name)
