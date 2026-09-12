extends Node
## AbilityCandidates guard — the ability-picker full-CATALOG rules (ADR-0197, the
## testing scaffold that exercises the 5-row scroll pipeline). Pure, no GPU — the
## ability mirror of EquipCandidatesTest.
##
## build_catalog(slot) is unit-independent and honors NO progression gate:
##   - REACTION/SUPPORT/MOVEMENT: every ability of the slot's type
##     (AbilityDatabase.get_views_by_type), placeholder rows dropped.
##   - SECONDARY: one row per UNIQUE skillset name (many jobs share a skillset);
##     jobs whose skillset has no name (monster jobs point past the 176-entry
##     table) dropped. The row id is the skillset's REPRESENTATIVE job — the
##     GENERIC job (0x4A-0x5D) that owns it when one exists, else the lowest job id.
##   - PRIMARY (and any non-editable slot): not handled -> empty.
## Rows are {id, name}, name-sorted ascending with id as the stable tie-break.
## Placeholder = a blank/whitespace name OR the ROM pad name "(Nothing)".
##
## Expected counts/literals below are derived INDEPENDENTLY from the asset data
## (jobs.json + the AbilityDatabase records), not recomputed from build_catalog:
##   Reaction 32 records - 1 "(Nothing)" = 31; Support 32 - 3 = 29; Movement 24 - 1 = 23.
##   Secondary: the 112 non-placeholder jobs collapse to 51 unique skillset names.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/AbilityCandidatesTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityCandidates = ExMateriaAlmanac.AbilityCandidates
const AbilityLoadout = ExMateriaAlmanac.AbilityLoadout



var _passed := 0
var _failed := 0


func _ready() -> void:
	_check_rsm(AbilityLoadout.Slot.REACTION, 31, 436, "CounterTackle", "Reaction")
	_check_rsm(AbilityLoadout.Slot.SUPPORT, 29, 460, "EquipAxe", "Support")
	_check_rsm(AbilityLoadout.Slot.MOVEMENT, 23, 486, "Move+1", "Movement")
	_check_secondary()
	_check_primary_unhandled()

	if _failed > 0:
		print("[FAIL] AbilityCandidatesTest")
		get_tree().quit(1)
	else:
		print("[PASS] AbilityCandidatesTest: %d checks — R/S/M catalog + secondary catalog + sort/hygiene" % _passed)
		get_tree().quit(0)


func _check_rsm(slot: int, want_count: int, known_id: int, known_name: String, type_label: String) -> void:
	var rows := AbilityCandidates.build_catalog(slot)
	_expect(rows.size() == want_count,
		"%s catalog = %d rows, got %d" % [type_label, want_count, rows.size()])
	_expect_rows_well_formed(rows, type_label)
	_expect_sorted(rows, type_label)
	# The catalog CONTAINS a known real ability of this type (find-by-id, order-agnostic).
	var found := _find_by_id(rows, known_id)
	_expect(not found.is_empty() and String(found.get("name", "")) == known_name,
		"%s catalog must contain id %d named '%s', got %s" % [type_label, known_id, known_name, found])


func _check_secondary() -> void:
	var rows := AbilityCandidates.build_catalog(AbilityLoadout.Slot.SECONDARY)
	# The 112 non-placeholder jobs collapse to one row per unique skillset name.
	_expect(rows.size() == 51, "secondary catalog = 51 rows, got %d" % rows.size())
	_expect_rows_well_formed(rows, "secondary")
	_expect_sorted(rows, "secondary")
	# Deduped: no two rows share a skillset name (the whole point of the reversal).
	var seen := {}
	var dup := ""
	for r in rows:
		var n := String(r.get("name", ""))
		if seen.has(n):
			dup = n
		seen[n] = true
	_expect(dup == "", "secondary catalog must have no duplicate skillset names, got dup '%s'" % dup)
	# Representative-job rule: "Item" is owned by the GENERIC Chemist (0x4b), NOT the
	# lower-id non-generic job (0x35) that also maps to Item — prefer-generic wins.
	var item := _find_by_id(rows, 0x4b)
	_expect(not item.is_empty() and String(item.get("name", "")) == "Item",
		"secondary catalog must represent 'Item' by generic Chemist (0x4b), got %s" % [item])
	_expect(_find_by_id(rows, 0x35).is_empty(),
		"the non-generic Item job (0x35) must NOT be the 'Item' representative")
	# A skillset with NO generic (Holy Sword: Delita/Agrias/Wiegraf, all special jobs)
	# falls back to the lowest job id (0x05) for determinism.
	var holy := _find_by_id(rows, 0x05)
	_expect(not holy.is_empty() and String(holy.get("name", "")) == "Holy Sword",
		"generic-less 'Holy Sword' must fall back to lowest id (0x05), got %s" % [holy])


func _check_primary_unhandled() -> void:
	# The primary slot is job-fixed / not focus-reachable — the catalog does not handle it.
	_expect(AbilityCandidates.build_catalog(AbilityLoadout.Slot.PRIMARY).is_empty(),
		"PRIMARY slot must yield an empty catalog (not handled)")


func _expect_rows_well_formed(rows: Array, label: String) -> void:
	var ok := true
	for r in rows:
		if not (r is Dictionary and r.has("id") and r.has("name")):
			ok = false
			break
		var n := String(r["name"]).strip_edges()
		if n.is_empty() or n == "(Nothing)":
			ok = false
			break
	_expect(ok, "%s rows must all be {id,name} with no blank/'(Nothing)' names" % label)


func _expect_sorted(rows: Array, label: String) -> void:
	var ok := true
	for i in range(1, rows.size()):
		var pn := String(rows[i - 1]["name"])
		var cn := String(rows[i]["name"])
		if pn > cn:
			ok = false
			break
		if pn == cn and int(rows[i - 1]["id"]) >= int(rows[i]["id"]):
			ok = false
			break
	_expect(ok, "%s rows must be name-sorted ascending with id tie-break" % label)


func _find_by_id(rows: Array, id: int) -> Dictionary:
	for r in rows:
		if int(r.get("id", -1)) == id:
			return r
	return {}


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] " + msg)
