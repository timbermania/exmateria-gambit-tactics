extends Node
## Integration guard: run the [RosterDebugView] against REAL data — the Gariland ENTD 388
## record + the live [CharacterCatalog] autoload — and smoke-instantiate both F3 ROSTER
## panels so a wiring break (bad preload, renamed accessor, panel crash) fails CI rather
## than only surfacing headful. Complements the pure-logic RosterDebugViewTest.
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/RosterBindingIntegrationTest.tscn

const RosterDebugView = ExMateriaCatalogue.RosterDebugView
const CatalogueReplay = ExMateriaCatalogue.CatalogueReplay
const SlugBinding = ExMateriaCatalogue.SlugBinding
const ENTD_JSON := "res://assets/scenarios/entd.json"

var _passed: int = 0
var _failed: int = 0


# Stand-in for NavigatorMain's debug read-seam, so the Battle Binding panel can render
# without booting the (1fps) navigator scene.
class FakeNav:
	extends Node
	var payload: Dictionary
	func debug_current_binding() -> Dictionary: return payload


func _ready() -> void:
	_test_binding_against_real_gariland_entd()
	_test_panels_instantiate()
	_test_orbonne_guests_bind_after_ch1_fold()

	print("\n=== RosterBindingIntegrationTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] RosterBindingIntegrationTest: ran zero assertions"); get_tree().quit(1); return
	if _failed > 0:
		print("[FAIL] RosterBindingIntegrationTest"); get_tree().quit(1)
	else:
		print("[PASS] RosterBindingIntegrationTest"); get_tree().quit(0)


func _eq(got, want, name: String) -> void:
	if got == want: _passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])

func _true(c: bool, name: String) -> void: _eq(c, true, name)


func _load_entd_slots(idx: int) -> Array:
	var f := FileAccess.open(ENTD_JSON, FileAccess.READ)
	if f == null: return []
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	var rec = parsed.get("records", {}).get(str(idx), null)
	return rec.get("slots", []) if rec != null else []


func _test_binding_against_real_gariland_entd() -> void:
	var slots := _load_entd_slots(388)
	_true(slots.size() > 0, "loaded real Gariland ENTD 388 slots")
	if slots.is_empty(): return

	var binding := SlugBinding.new()
	var rows: Array = RosterDebugView.build_binding_rows(slots, 388, binding, CharacterCatalog)
	var summary: Dictionary = RosterDebugView.binding_summary(slots, 388, binding, CharacterCatalog)

	# Every non-empty slot yields exactly one row, and the summary is internally consistent.
	var non_empty := 0
	for s in slots:
		if int(s.get("unit_id", 0xFF)) != 0xFF: non_empty += 1
	_eq(rows.size(), non_empty, "one binding row per non-empty ENTD slot")
	_eq(int(summary["total"]), non_empty, "summary total == non-empty slots")
	_eq(int(summary["bound"]) + int(summary["fallback"]), int(summary["total"]),
		"summary bound + fallback == total")
	# Read-only: inspecting the binding must not pollute its live coverage log.
	_eq(binding.fallback_count(), 0, "view does not mutate the live binding")


# End-to-end (ADR-0201/0216): the derived script's APPEARANCE deltas must register the
# Orbonne named guests so their ENTD-387 slots bind to catalogue Characters (HIT) instead
# of falling back to raw-ENTD construction. Those three carry no `join_after_event`
# anywhere, so the JOIN derivation reaches none of them — they come from the always-present
# named scan over the battle's own ENTD record, folded at the group's opener. Folds the
# real plan into the LIVE catalogue up to the pre-battle breakpoint, then restores state.
func _test_orbonne_guests_bind_after_ch1_fold() -> void:
	var slots := _load_entd_slots(387)
	_true(slots.size() > 0, "loaded real Orbonne ENTD 387 slots")
	if slots.is_empty(): return

	var actions := GameNavigator.new().plan_actions(1, 9, StoryMutationScript.build())
	# Fold everything up to (not including) the pre_battle action — so the Orbonne opener's
	# joins are applied, exactly as the runner leaves the catalogue at the config breakpoint.
	var upto := actions.size()
	for i in actions.size():
		if String(actions[i].get("kind", "")) == "pre_battle":
			upto = i
			break
	CatalogueReplay.fold(actions, upto, CharacterCatalog)

	var binding := SlugBinding.new()
	var rows: Array = RosterDebugView.build_binding_rows(slots, 387, binding, CharacterCatalog)
	var by_slug := {}
	for r in rows:
		by_slug[String(r["slug"])] = r

	_true(bool(by_slug.get("agrias", {}).get("bound", false)), "Agrias binds (HIT) after the fold")
	_true(bool(by_slug.get("gafgarion", {}).get("bound", false)), "Gafgarion binds (HIT) after the fold")
	_true(bool(by_slug.get("ovelia", {}).get("bound", false)), "Ovelia binds (HIT) after the fold")
	# The bound guests must carry their REAL job (not a Squire placeholder) — else a HIT
	# would fight WORSE than the raw-ENTD fallback (Agrias job 52 = 0x34, Gafgarion 23 = 0x17).
	var agrias = CharacterCatalog.get_character("agrias")
	_true(agrias != null and agrias.progression != null, "Agrias registered with a progression")
	if agrias != null and agrias.progression != null:
		_eq(agrias.progression.current_job_id, "34", "Agrias bound with her real ENTD job (not Squire)")

	# Restore shared autoload state (this test mutates the live CharacterCatalog).
	for slug in ["delita", "agrias", "gafgarion", "ovelia"]:
		CharacterCatalog.unregister(slug)


func _test_panels_instantiate() -> void:
	# Universe panel: renders the live CharacterCatalog (seeded with at least "ramza").
	var uni := RosterUniverseDebugPanel.new()
	add_child(uni)
	uni.setup()
	uni.on_shown()   # must not crash; catalogue has the seeded protagonist
	_true(is_instance_valid(uni), "Universe panel builds against the live catalogue")
	uni.queue_free()

	# Battle Binding panel: renders from the navigator's debug seam (faked here).
	var fake := FakeNav.new()
	fake.payload = {
		"context": 388,
		"slots": _load_entd_slots(388),
		"binding": SlugBinding.new(),
		"catalogue": CharacterCatalog,
	}
	add_child(fake)
	var bind_panel := BattleBindingDebugPanel.new()
	add_child(bind_panel)
	bind_panel.setup(fake)
	bind_panel.on_shown()  # must not crash; pulls the fake battle context
	_true(is_instance_valid(bind_panel), "Battle Binding panel builds from the navigator seam")
	bind_panel.queue_free()
	fake.queue_free()
