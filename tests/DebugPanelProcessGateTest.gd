extends Node
# test-kind: logic
# seeded-break: re-arm the gate at registration in src/debug/DebugDashboard.gd `add_panel` — add `panel.set_process(true)` right after the `on_registered()` call, which is the W13 defect restored through its surviving half; 'registering the bus mixer must NOT start it metering — the F3 window is closed' reds, 14 of 15 assertions still pass, and the hidden-direction arms stay green, which is the point the test's own header makes about why they are not sufficient | fold controls: comment out the `header_row.gui_input.connect(...)` in `_build_cell` and 'a left-click ANYWHERE on the header folds the cell' reds; drop the `not cell_panel.visible` half of `fold_all_categories`'s skip and 'Fold all skips EMPTY cells' reds with all 23 categories listed
## W13 (#955) — the F3 audio bus mixer must not meter the buses while the F3 window
## is closed.
##
## **The defect this pins is in the CALLER, not the panel.** `AudioBusMixerDebugPanel`
## already gated itself three times over (`_build_ui` → `set_process(false)`,
## `on_shown()` → `set_process(true)`, `on_hidden()` → `set_process(false)`), and it
## still ran every frame of every session: `DebugDashboard.add_panel()` calls
## `on_shown()` **unconditionally at registration**, whether or not the dashboard
## Window is visible, and `on_hidden()` had **no caller anywhere in the repo**. So the
## gate was armed ON at boot and nothing could ever switch it off. Measured at
## 0.064–0.103 ms/frame on both hosts — ~26 % of all non-`CombatLoop` script, and more
## than all 13 units' `_process` put together (GPU-ARENA-PERF.md → W5, W13).
##
## **Why the assertion is `is_processing()` and not a stopwatch.** The cost is 0.09 ms
## against a ~1.25 ms frame; no wall-clock rig on this box can resolve that (R29's own
## W14 A/B is the cautionary tale — arm A's two reps differed by 12 %). What regresses
## is *counted* work: a `_process` callback that is registered when nothing can see the
## panel. That is W8's standing ruling — assert counted work, not milliseconds.
##
## **The gate is `is_visible_in_tree()`, and that is strictly stronger than the hook
## pair was.** The panel sits inside a per-panel fold, inside a category cell that
## folds, inside a page that switches, inside the dashboard Window. `on_shown()` /
## `on_hidden()` can only ever see the Window; `is_visible_in_tree()` sees all four,
## and `visibility_changed` propagates down through every one of them
## (`CanvasItem::_handle_visibility_change` recurses into child canvas items;
## `CanvasItem::_window_visibility_changed` is what carries a Window's hide into them).
##
## Run: "$GODOT" --path . --quit-after 5 res://tests/DebugPanelProcessGateTest.tscn

const MixerPanel = preload("res://src/debug/AudioBusMixerDebugPanel.gd")
const VMPanel = preload("res://src/debug/ScenarioVMDebugPanel.gd")
const SpriteOffsetPanel = preload("res://src/debug/ScenarioUnitSpriteOffsetDebugPanel.gd")
const Dashboard = preload("res://src/debug/DebugDashboard.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_registration_does_not_arm_the_gate()
	_test_visibility_drives_the_gate()
	_test_every_panel_inherits_the_gate()
	_test_a_panel_that_drives_the_game_opts_out()
	_test_the_hook_pair_is_gone()
	await _test_the_cell_fold_controls()
	_finish()


## The measured defect, through the real registration path: a fresh DebugDashboard is
## `visible = false` from its own `_init` ("Start hidden; DebugOverlay calls show() on
## F3"), and registering into it must not start the meter. Seeded against trunk this
## assertion fails — trunk's `on_shown()` ends with `set_process(true)` and add_panel
## calls it here.
func _test_registration_does_not_arm_the_gate() -> void:   # coroutine — awaits frames
	var dash: Window = Dashboard.new()
	add_child(dash)
	_true(not dash.visible, "a fresh DebugDashboard starts hidden (F3 closed)")

	var panel := MixerPanel.new()
	panel.setup()
	dash.add_panel(panel, Dashboard.Category.AUDIO)

	_true(not panel.is_visible_in_tree(),
		"a panel registered into a hidden dashboard is not visible in tree")
	_true(not panel.is_processing(),
		"registering the bus mixer must NOT start it metering — the F3 window is closed")

	# ...and the F3 press must bring it back. Asserted through the real Window because
	# the gate's whole claim rests on a link this test would otherwise never exercise:
	# only the TOPMOST CanvasItem under a Window connects to its `visibility_changed`
	# (`CanvasItem::_notification` ENTER_TREE → `window = cast_to<Window>(get_viewport())`),
	# and it reaches this panel by recursion. A break anywhere in that chain would leave
	# the panel gated OFF forever — a dead F3 mixer, which is a worse bug than the one
	# being fixed. The hidden-direction assertions above cannot see that.
	dash.show()
	await get_tree().process_frame
	_true(panel.is_visible_in_tree(), "showing the dashboard makes the panel visible in tree")
	_true(panel.is_processing(),
		"opening F3 RESUMES the meter — the Window's visibility reaches the panel")

	dash.hide()
	await get_tree().process_frame
	_true(not panel.is_processing(), "closing F3 stops it again")

	dash.remove_panel(panel, Dashboard.Category.AUDIO)
	panel.free()
	dash.queue_free()


## The other direction, and the reason the gate is visibility rather than a hook: a
## panel whose ancestor chain is visible DOES meter, and hiding any link in that chain
## stops it. A gate that only ever reads `false` would pass the test above and ship a
## dead panel.
func _test_visibility_drives_the_gate() -> void:
	var holder := Control.new()
	add_child(holder)
	var panel := MixerPanel.new()
	panel.setup()
	holder.add_child(panel)

	_true(panel.is_visible_in_tree(), "the stand-in host is visible in tree")
	_true(panel.is_processing(),
		"a VISIBLE bus mixer meters the buses — the panel is not dead, it is gated")

	holder.visible = false
	_true(not panel.is_processing(),
		"hiding an ANCESTOR stops the meter (the category fold / page switch case)")

	holder.visible = true
	_true(panel.is_processing(), "revealing the ancestor resumes the meter")

	holder.queue_free()


## The gate lives on BaseDebugPanel, so it is not a per-panel fix: the census that
## found the mixer only saw the panels the GPU arena instantiates, and
## `ScenarioVMDebugPanel` — which repopulates a whole disassembly list every frame —
## had no gate of its own at all. It never called `set_process`, so nothing but
## Godot's own NOTIFICATION_READY auto-arm was deciding when it ran.
func _test_every_panel_inherits_the_gate() -> void:
	var holder := Control.new()
	holder.visible = false
	add_child(holder)
	var panel := VMPanel.new()
	holder.add_child(panel)
	_true(not panel.is_processing(),
		"ScenarioVMDebugPanel inherits the gate — it defines _process and no set_process")
	holder.queue_free()


## The gate has one deliberate exception, and it must actually work: a panel whose
## `_process` DRIVES THE GAME keeps running while hidden.
## `ScenarioUnitSpriteOffsetDebugPanel` re-applies its `shared_loc_offset` overrides
## every frame because the sprite pipeline rewrites the offset per animation; gating
## it would silently drop a calibration the moment the panel folded away.
func _test_a_panel_that_drives_the_game_opts_out() -> void:
	var holder := Control.new()
	holder.visible = false
	add_child(holder)
	var panel := SpriteOffsetPanel.new()
	_true(panel.processes_while_hidden,
		"the sprite-offset rig declares processes_while_hidden")
	holder.add_child(panel)
	_true(panel.is_processing(),
		"an opted-out panel keeps processing while hidden — its work is not a repaint")
	holder.queue_free()


## `on_hidden()` was a hook with zero call sites and one implementor, and
## `BaseDebugPanel`'s docstring for it ("Override to pause updates when not visible")
## is what made the mixer look gated when it was not. Both are deleted; this asserts
## the API is gone so the next panel cannot be written against it.
func _test_the_hook_pair_is_gone() -> void:
	var panel := MixerPanel.new()
	_true(not panel.has_method("on_hidden"),
		"on_hidden() is gone — a hook with no caller is worse than no hook")
	_true(panel.has_method("on_shown"),
		"on_shown() stays: add_panel() still calls it, and 13 panels re-sync in it")
	panel.free()


## The category cell's fold, from the other end: this test's own header calls the fold
## one of the four links the gate sees ("inside a category cell that folds"), so the
## controls that DRIVE that fold share this setup and are asserted here rather than in
## a second 2.3 s process (test charter clause 13).
##
## Two ergonomics fixes are pinned:
##   1. **Fold all / Unfold all** on the dashboard header — folding 12 open cells used
##      to be 12 clicks. `fold_all_categories` must reach every VISIBLE cell, must
##      emit `category_collapsed_changed` for each (that signal is the only thing
##      DebugOverlay persists through), and must skip cells with no panel — folding
##      those would persist a collapse for a category the user never saw.
##   2. **The whole header strip is the hit target**, not the 16px ▼ at its end. The
##      strip must take mouse events (`MOUSE_FILTER_STOP`) while its Label lets them
##      through (`IGNORE`), or the click lands on nothing; and the ▼ Button must keep
##      consuming its own clicks (`STOP`), or a hit on the triangle would toggle the
##      row handler too and the cell would flip twice = not at all.
func _test_the_cell_fold_controls() -> void:   # coroutine — awaits frames
	var dash: Window = Dashboard.new()
	add_child(dash)
	await get_tree().process_frame

	var mixer := MixerPanel.new()
	mixer.setup()
	dash.add_panel(mixer, Dashboard.Category.AUDIO)
	var vm := VMPanel.new()
	dash.add_panel(vm, Dashboard.Category.SCENARIO)
	dash.show()
	await get_tree().process_frame

	_true(dash.fold_all_button() != null and dash.unfold_all_button() != null,
		"the dashboard header offers Fold all / Unfold all")

	# --- 1. Fold all reaches every cell that is on the page, and only those. ---
	var folded: Array = []
	dash.category_collapsed_changed.connect(
		func(cat: int, collapsed: bool) -> void:
			if collapsed:
				folded.append(cat))
	dash.fold_all_button().pressed.emit()
	await get_tree().process_frame
	_true(dash.is_category_collapsed(Dashboard.Category.AUDIO)
		and dash.is_category_collapsed(Dashboard.Category.SCENARIO),
		"Fold all collapses every cell with a registered panel")
	_true(folded.has(Dashboard.Category.AUDIO) and folded.has(Dashboard.Category.SCENARIO),
		"Fold all emits category_collapsed_changed per cell — the persistence channel")
	_true(not folded.has(Dashboard.Category.FONT),
		"Fold all skips EMPTY cells: %s" % [folded])
	_true(not mixer.is_processing(),
		"a folded-away mixer stops metering — the fold reaches the gate")

	dash.unfold_all_button().pressed.emit()
	await get_tree().process_frame
	_true(not dash.is_category_collapsed(Dashboard.Category.AUDIO)
		and not dash.is_category_collapsed(Dashboard.Category.SCENARIO),
		"Unfold all expands them again")
	_true(mixer.is_processing(), "...and the mixer resumes")

	# --- 2. The header strip is the hit target, and one click is one toggle. ---
	var header: Control = dash.category_header(Dashboard.Category.AUDIO)
	_true(header != null, "the AUDIO cell exposes its header strip")
	_true(header.mouse_filter != Control.MOUSE_FILTER_IGNORE,
		"the header strip takes mouse events, or clicking it does nothing")
	var label_ignores := true
	for c in header.get_children():
		if c is Label and (c as Label).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			label_ignores = false
	_true(label_ignores,
		"the header's Label must IGNORE the mouse, or its pixels swallow the click")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	header.gui_input.emit(click)
	await get_tree().process_frame
	_true(dash.is_category_collapsed(Dashboard.Category.AUDIO),
		"a left-click ANYWHERE on the header folds the cell")
	header.gui_input.emit(click)
	await get_tree().process_frame
	_true(not dash.is_category_collapsed(Dashboard.Category.AUDIO),
		"...and a second click unfolds it")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	header.gui_input.emit(release)
	_true(not dash.is_category_collapsed(Dashboard.Category.AUDIO),
		"the RELEASE half of the same click must not toggle it back")

	var triangle: Button = dash._collapse_buttons[Dashboard.Category.AUDIO]
	_true(triangle.mouse_filter == Control.MOUSE_FILTER_STOP,
		"the ▼ keeps consuming its own clicks — else a hit there toggles twice = never")

	dash.remove_panel(mixer, Dashboard.Category.AUDIO)
	dash.remove_panel(vm, Dashboard.Category.SCENARIO)
	mixer.free()
	vm.free()
	dash.queue_free()


func _true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL %s" % msg)


func _finish() -> void:
	if _passed == 0 and _failed == 0:
		print("[FAIL] DebugPanelProcessGateTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] DebugPanelProcessGateTest — %d/%d" % [_passed, _passed + _failed])
		get_tree().quit(1)
	else:
		print("[PASS] DebugPanelProcessGateTest — %d/%d" % [_passed, _passed])
		get_tree().quit(0)
