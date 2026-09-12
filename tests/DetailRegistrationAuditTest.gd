extends Node3D

## ADR-0088 §8 — the DetailScene registration audit, piggybacked per-screen: every
## rendering payload (MeshInstance3D + ShaderMaterial) under the booted Status screen
## must sit under a registered UI3Element, except the classes on the GUARD-LOCAL
## allowlist below (this screen's known-unmigrated widget world). The list may only
## SHRINK — the two-sided check fails a listed class with zero violations, so an entry
## cannot linger after its migration lands.
##
## NOTE: the tracked res://config/ui3_registration_allowlist.json stays EMPTY — its
## two-sided rule is evaluated per audit ROOT, so a file entry for the cluster classes
## would break the OTHER screens' audits ("remove X — zero violations under this
## root"). Until that per-root semantics is reworked, each screen guard carries its
## own local list.
##
## Run: <GODOT> --path . --quit-after 20 res://tests/DetailRegistrationAuditTest.tscn

const DetailScene = preload("res://src/ui3/detail/DetailScene.gd")

## The known-unmigrated classes under the Status screen. EMPTY: since ADR-0088 Amendment 5
## (slice 4) the vitals+nameplate cluster is a REGISTERED ELEMENT tree — detail.unit_cluster
## with .vitals + .nameplate sub-elements — so its payload sits under registered elements and
## is EXPECTED in the walk, not tolerated. Nothing needs allowlisting. SHRINK-ONLY if it ever
## grows (a code change reviewers see).
const ALLOW := []

## The no-empty-`DERIVED` audit seed (Amendment 4 §3): the detail-screen elements whose
## rect is still an empty-drivers DERIVED dead-end, awaiting their migration slice. SHRINK-
## ONLY — slice 2 converts stats/lower/compare to declared drivers, slice 4 converts
## vitals_band, and this list empties. slot_cursor + pager already converted (screen_anchored).
## EMPTY: all detail-screen elements now declare their drivers or are screen_anchored()
## (slices 1/2/4 landed). The seed emptied — the ratchet is complete for this screen.
const EMPTY_DERIVED_ALLOW := []

const _VIEW := {
	"move": 4, "jump": 3, "speed": 8, "r_power": 9, "r_wev": 5, "l_power": 0, "l_wev": 0,
	"r_at": 7, "c_ev": 12, "s_ev": 0, "a_ev": 0, "l_at": 0,
	"equipment": [{"name": "Broad Sword", "palette": 0, "icon_graphic": -1}, {}, {}, {}, {}],
}

var _passed := 0
var _failed := 0


func _ready() -> void:
	var d: DetailScene = DetailScene.new()
	d.autoplay_open = false
	add_child(d)
	d.set_stats_view(_VIEW)
	await get_tree().process_frame
	await get_tree().process_frame

	# --- full joint Status screen ------------------------------------------------
	var errors: Array = UI3RegistrationAudit.check(d, ALLOW)
	for e in errors:
		_expect(false, "status: %s" % e)
	_expect(errors.is_empty(), "status screen: %d registration-audit problems" % errors.size())

	# --- Item→Equip sub-screen + §15.25 slot focus (mounts the slot glove cursor) --
	d.enter_equip_mode()
	d.enter_slot_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	_expect(d.slot_cursor_mounted(), "slot glove cursor did not mount (precondition)")
	var errors2: Array = UI3RegistrationAudit.check(d, ALLOW)
	for e in errors2:
		_expect(false, "equip/slot-focus: %s" % e)
	_expect(errors2.is_empty(), "equip/slot-focus: %d registration-audit problems" % errors2.size())

	# --- no-empty-DERIVED audit (Amendment 4 §3): every registered rect must declare its
	# drivers or be screen_anchored(), except the seed of not-yet-migrated ids. slot_cursor
	# + pager are converted here (slice 1); an un-listed empty-DERIVED rect fails.
	var ed_errors: Array = UI3RegistrationAudit.check_empty_derived(d, EMPTY_DERIVED_ALLOW)
	for e in ed_errors:
		_expect(false, "empty-derived: %s" % e)
	_expect(ed_errors.is_empty(), "no-empty-DERIVED: %d problems" % ed_errors.size())

	d.queue_free()
	print("\n=== DetailRegistrationAuditTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] DetailRegistrationAuditTest")
		get_tree().quit(1)
	else:
		print("[PASS] DetailRegistrationAuditTest: every Status-screen payload housed (status + equip/slot-focus, empty allowlist)")
		get_tree().quit(0)


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[DetailRegistrationAuditTest] " + msg)
		print("  [x] " + msg)
