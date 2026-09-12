extends Node3D
# test-kind: logic
# seeded-break: FormationTransitionEngine.Player.advance drops the MAX_CATCHUP clamp (_accum += delta instead of minf(delta, MAX_CATCHUP)) — the 1 s spike the test feeds host._process now takes 30 menu ticks in one call, past the 16-tick SLIDE_DURATION, so 'one oversized delta finished the Equip slide in a single frame (the clamp is missing)' reds; the Item-starts-the-Equip-slide + no-formation/selection asserts stay green

## Host per-tick steppers survive a delta SPIKE (the teleport guard, companion to the DetailScene
## clamp in DetailEntrySlideTest). The Equip / Change-Job steppers in FormationDetailTransition._process
## accumulate `delta` into an UNBOUNDED while-loop at the menu-tick cadence — so a single oversized
## frame (a stall, or the Hyprland render_unfocused throttle dropping the window to ~1 fps) would run
## the loop enough times to reach the slide's settle in ONE visual frame (the "teleport"). Clamping the
## per-frame catch-up bounds each frame's advance so intermediate frames stay visible.
##
## Here: start the Equip roster slide (via the ○-press → START menu → Item path), then feed the host a
## single 1-second frame. With the clamp the slide advances only a bounded step and is STILL sliding;
## without it the slide collapses straight to its settled end.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")

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

	var form = host._formation
	_expect(form != null and form.selected_character() != null, "no formation/selection")
	if form == null:
		_finish()
		return

	# ○-press → START action menu → "Item" (row 0) starts the Equip roster slide.
	form._unhandled_input(_action("ui_accept"))
	host.open_action_menu()
	host.action_menu().confirm()
	_expect(host.is_equip_sliding(), "Item did not start the Equip slide")

	# One oversized frame (1 s). The engine Player's MAX_CATCHUP clamp bounds the catch-up, so the
	# slide advances only a bounded few ticks and is STILL sliding — it must NOT collapse to its
	# settled end in a single visual frame. is_equip_sliding() staying true IS the clamp: without it
	# the 1 s spike would run the whole SLIDE_DURATION beat and settle it (is_equip_sliding → false).
	host._process(1.0)
	_expect(host.is_equip_sliding(),
		"one oversized delta finished the Equip slide in a single frame (the clamp is missing)")

	_finish()


func _action(name: String) -> InputEvent:
	var ev := InputEventAction.new()
	ev.action = name
	ev.pressed = true
	return ev


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _finish() -> void:
	if _failed:
		print("[FAIL] FormationStepperClamp test")
	else:
		print("[PASS] FormationStepperClamp: a delta spike does not collapse the host Equip/Change-Job steppers (no teleport)")
	get_tree().quit()
