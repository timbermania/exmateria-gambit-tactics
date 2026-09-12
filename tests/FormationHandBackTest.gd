extends Node3D
# test-kind: logic
# seeded-break: replaced the at-rest hand-back `dismissed.emit()` in _on_dismissed with `pass` so the ROSTER host never takes the display back; the 'A: ✕ at rest emitted dismissed 1 times' assert reds (0 emissions -> the navigator's await formation.dismissed would HANG), the A-settle + B open-screen leave/unwind + C persistent-MAP-host asserts stay green

## The Formation COORDINATOR's hand-back — `dismissed` at rest — and the two cases where it
## must stay silent. ADR-0181.
##
## [b]Why this test exists at all: the failure it guards is a HANG, not a wrong value.[/b]
## `NavigatorMain._on_world_map_menu_row` mounts the screen and does `await formation.dismissed`.
## The coordinator CONSUMES `FormationScene.dismissed` for its own unwind (`_on_dismissed` →
## `leave()`), so before this change it re-emitted nothing: pointing the world map at the
## coordinator made that await never return, with no error, no push_error and nothing in the log.
## A test that merely mounted the screen was 100% green through that. Verified by hand on the
## live route before the fix, which is what made a seeded red arm worth writing.
##
## Three arms, and the second and third are the direction seeds:
##   A. ROSTER host, nothing open  → ✕ emits `dismissed` exactly once. The hand-back.
##   B. ROSTER host, Status open   → ✕ emits NOTHING; it LEAVES the screen instead. Without this
##      the navigator would tear the screen down under a player who was still browsing — which
##      is also precisely why `settled(to)` could not be the signal awaited: `_exit_settled`
##      emits `settled(State.IDLE)` on this very press.
##   C. MAP host, nothing open     → ✕ emits NOTHING. The map host is PERSISTENT (built at
##      Deployment entry, freed with the tile-cursor rig), so it never "finishes"; a hand-back
##      there would be a false claim that today happens to have no listener.
##
## Run: <GODOT> --path . --quit-after 90 res://tests/FormationHandBackTest.tscn

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	# ADR-0181: the host reads `CharacterCatalog.owned_units()` and seeds nothing, so the
	# fixture is stated here — same pair `FormationDevBoot` uses for the standalone scene.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()

	await _a_rest_hands_back()
	await _b_open_screen_does_not()
	await _c_map_host_does_not()

	print("\n=== FormationHandBackTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationHandBackTest")
	else:
		print("[PASS] FormationHandBackTest: ✕ at rest hands the display back; an open screen and the persistent MAP host do not (ADR-0181)")
	get_tree().quit()


func _a_rest_hands_back() -> void:
	var host := await _mount(FormationDetailTransition.Host.ROSTER)
	var seen := [0]
	host.dismissed.connect(func() -> void: seen[0] += 1)

	_expect(host.current_state() == FormationDetailTransition.State.IDLE,
			"A: host did not settle on the plain roster")
	host._formation._unhandled_input(_cancel())
	await get_tree().process_frame

	_expect(seen[0] == 1, "A: ✕ at rest emitted `dismissed` %d times, want 1" % seen[0])
	host.queue_free()
	await get_tree().process_frame


func _b_open_screen_does_not() -> void:
	var host := await _mount(FormationDetailTransition.Host.ROSTER)
	var seen := [0]
	host.dismissed.connect(func() -> void: seen[0] += 1)

	# Open the Status/detail screen the way ○ does, then wait for the entry to settle.
	var character = host._formation.selected_character()
	_expect(character != null, "B: no selected character to open a screen on")
	if character == null:
		host.queue_free()
		return
	host._on_unit_activated(character)
	for _i in 40:
		await get_tree().process_frame
		if host.current_state() != FormationDetailTransition.State.IDLE and not host.is_moving():
			break
	_expect(host.current_state() == FormationDetailTransition.State.DETAIL,
			"B: Status screen did not open (state %d)" % host.current_state())

	host._formation._unhandled_input(_cancel())
	for _i in 40:
		await get_tree().process_frame

	_expect(seen[0] == 0, ("B: ✕ over an OPEN screen handed the display back (%d times) — "
			+ "the navigator would tear the screen down under the player") % seen[0])
	_expect(host.current_state() == FormationDetailTransition.State.IDLE,
			"B: ✕ over the Status screen did not unwind it")
	host.queue_free()
	await get_tree().process_frame


func _c_map_host_does_not() -> void:
	var host := await _mount(FormationDetailTransition.Host.MAP)
	var seen := [0]
	host.dismissed.connect(func() -> void: seen[0] += 1)

	_expect(host.current_state() == FormationDetailTransition.State.IDLE,
			"C: map host did not settle")
	host._on_dismissed()
	await get_tree().process_frame

	_expect(seen[0] == 0, "C: the PERSISTENT map host claimed to be finished (%d times)" % seen[0])
	host.queue_free()
	await get_tree().process_frame


func _mount(host_mode: int) -> FormationDetailTransition:
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.host_mode = host_mode
	host.name = "Host"
	add_child(host)
	for _i in 8:
		await get_tree().process_frame
	return host


## A ✕ press as the InputMap actually binds it — Backspace, NOT Escape (Escape is `battle_pause`).
func _cancel() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_BACKSPACE
	e.pressed = true
	return e


func _expect(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s" % msg)
