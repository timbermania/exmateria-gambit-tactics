class_name ScenarioVMDebugPanel
extends BaseDebugPanel

## Disassembly + state view for the scenario VM.
##
## Scrollable list of every opcode in the loaded chunk, with the current PC
## highlighted and auto-scrolled into view. Live state readout (running /
## halted, _wait_ticks, camera-lerp progress) at the top. Pause / Resume /
## Step buttons at the bottom for manual stepping through opcodes.

const TuneField = preload("res://src/debug/TuneField.gd")

var _vm  # ScenarioVM

var _status_label: Label
var _pc_label: Label
var _wait_label: Label
var _lerp_label: Label
var _list: ItemList
var _details_label: RichTextLabel
var _pause_btn: Button
var _step_btn: Button
var _step10_btn: Button
var _step100_btn: Button
var _play_through_cb: CheckBox
var _auto_advance_cb: CheckBox
var _rewind_root_cb: CheckBox
var _shot_path_edit: LineEdit

# Panel-side source of truth for the event-toggle disables — PC index -> true for
# every instruction the user has switched OFF (right-click a row / "Toggle sel").
# Survives scene reload via DebugOverlay + `rebind`, and is repushed into the
# freshly-booted VM by `_push_panel_values_into_vm` so a rewind replays with the
# same events removed. Cleared when the scenario changes (PCs become meaningless).
var _disabled_pcs: Dictionary = {}

# Refresh throttling — repopulating the ItemList every frame for 2k+ items
# is expensive. Re-render only when PC moves or paused/run state flips.
var _last_pc_rendered: int = -1
var _last_list_size: int = -1
# Tracks the row currently tinted as "the PC" so we can clear it cheaply
# when the PC moves on, without scanning every row.
var _highlighted_row: int = -1
# True when the user has manually selected a row in the list. Suppresses the
# step-mode auto-display of the current instruction in the details panel so
# the user's selection sticks until they click elsewhere or hit Resume.
var _user_pinned_details: bool = false

# PC to scroll the disassembly to once a double-click rewind has settled. Set in
# `_request_rewind` (before the scene reload) and survives the reload because the
# panel is owned by the DebugOverlay autoload. A rewind reloads the scene, then
# fast-forwards to the target PC over several `_process` frames; we wait until the
# VM is actually paused AT that PC (and the row exists) before scrolling, so the
# just-clicked instruction lands centred instead of the list snapping to the top.
# -1 = nothing pending.
var _pending_scroll_row: int = -1


func setup(vm) -> void:
	_vm = vm
	panel_title = "Scenario VM"
	panel_category = Category.SCENARIO_PLAYBACK
	_build_ui()
	# The AUTOSAVE toggles hold the persisted prefs (coalesced by TuneField at build);
	# drive the fresh VM FROM them so a remembered play-through/auto-advance applies on
	# first boot, exactly as rebind does after a reload.
	_push_panel_values_into_vm()
	_populate_list()


# Re-point the panel at a freshly-booted VM after a scene reload (Ctrl+R or
# click-to-rewind). The panel itself is owned by the DebugOverlay autoload
# and survives the reload — calling `rebind` instead of `setup` is what
# preserves scroll position, selected row, and every spinbox/checkbox
# value across the reload. The user-tuned panel values are pushed INTO the
# new VM (overriding its file defaults) so the live render reflects the
# tuning. Only state that's now stale (the disassembly row count +
# current-PC highlight) is invalidated so the next `_process` re-renders
# it against the new chunk.
func rebind(vm) -> void:
	_vm = vm
	_push_panel_values_into_vm()
	_last_list_size = -1   # force _populate_list to re-render against the new chunk
	_last_pc_rendered = -1 # force _highlight_current_pc to retint on the new VM's PC
	_user_pinned_details = false
	_populate_list()


# Push every panel-controlled value back into the new VM so the user's
# tuning survives the scene reload. The VM's file defaults are deliberately
# overridden by the panel's current values — the panel is the source of
# truth for these knobs once it's been touched.
func _push_panel_values_into_vm() -> void:
	if not _vm_alive():
		return
	_vm.play_through_skip_unknown = _play_through_cb.button_pressed
	if _auto_advance_cb != null:
		_vm.dialog_auto_advance = _auto_advance_cb.button_pressed
	# Event-toggle disables — repush the panel's set into the freshly-booted VM so a
	# rewind replays with the same events removed. (A path walk's applier holds these
	# aside for intermediate members; here we just hand the VM the full set.)
	_vm.disabled_pcs = _disabled_pcs.duplicate()


# True iff the VM ref is still pointing at a live instance. The panel can
# outlive its VM during a scene reload (DebugOverlay autoload survives, the
# scene-local ScenarioVM is freed), so every entry point that touches `_vm`
# must short-circuit on this — otherwise we crash with "previously freed"
# the first time `_process` fires on the orphan frame.
func _vm_alive() -> bool:
	return _vm != null and is_instance_valid(_vm)


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(380, 0)
	add_child(vbox)

	add_section_title(vbox, "State")
	_status_label = add_label(vbox, "")
	_pc_label = add_label(vbox, "")
	_wait_label = add_label(vbox, "")
	_lerp_label = add_label(vbox, "")

	# Primary playback controls up top so Pause/Step/Resume/Jump-to-PC are
	# reachable without scrolling past the tall disassembly list. (The event-
	# toggle + capture rows stay down by the list where they're contextual.)
	add_separator(vbox)
	var btn_row := add_button_row(vbox)
	_pause_btn = Button.new()
	_pause_btn.text = "Pause"
	_pause_btn.pressed.connect(_on_pause_pressed)
	btn_row.add_child(_pause_btn)

	_step_btn = Button.new()
	_step_btn.text = "Step"
	_step_btn.pressed.connect(_on_step_pressed)
	btn_row.add_child(_step_btn)

	_step10_btn = Button.new()
	_step10_btn.text = "Step 10"
	_step10_btn.pressed.connect(_on_step_n_pressed.bind(10))
	btn_row.add_child(_step10_btn)

	_step100_btn = Button.new()
	_step100_btn.text = "Step 100"
	_step100_btn.pressed.connect(_on_step_n_pressed.bind(100))
	btn_row.add_child(_step100_btn)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.pressed.connect(_on_resume_pressed)
	btn_row.add_child(resume_btn)

	var jump_btn := Button.new()
	jump_btn.text = "Jump-to-PC"
	jump_btn.pressed.connect(_on_jump_pressed)
	btn_row.add_child(jump_btn)

	# Scene selection lives in the "Scenario" cell — ScenarioPathDebugPanel (the
	# root picker + group flowchart). This panel is pure playback control.
	add_separator(vbox)

	# Playback toggles auto-persist (green TuneField, ADR-0068): a play-through / auto-
	# advance / rewind-through-root choice comes back next launch. This panel is the source
	# of truth for these knobs (pushed into a freshly-booted VM by _push_panel_values_into_vm,
	# also called at setup so a persisted pref drives the first boot too).
	_play_through_cb = TuneField.add(vbox, "Play-through (skip dialogues + unknown opcodes)",
		"scenario_vm.play_through", bool(_vm.play_through_skip_unknown) if _vm else false, {},
		Tune.Persist.AUTOSAVE) as CheckBox
	_play_through_cb.toggled.connect(_on_play_through_toggled)

	# Auto-advance: reveal each boxed Display Message in full and release after a
	# fixed dwell instead of blocking on Cross/confirm. ON by default (the chapel
	# plays start→end hands-free); turn OFF to step through dialogs by hand while
	# debugging. Mirrors `_vm.dialog_auto_advance`; pushed across scene reloads by
	# `_push_panel_values_into_vm`.
	_auto_advance_cb = TuneField.add(vbox, "Auto-advance dialogs (off = confirm to advance)",
		"scenario_vm.auto_advance", bool(_vm.dialog_auto_advance) if _vm else true, {},
		Tune.Persist.AUTOSAVE) as CheckBox
	_auto_advance_cb.toggled.connect(_on_auto_advance_toggled)

	add_separator(vbox)
	add_section_title(vbox, "Disassembly")

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 420)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_height = false
	_list.allow_reselect = true
	_list.item_selected.connect(_on_item_selected)
	# Double-click → rewind. ItemList fires `item_activated` on enter/double-click,
	# distinct from single-click selection. Phase-3 click-to-rewind wiring.
	_list.item_activated.connect(_on_item_activated)
	# Right-click a row → toggle that event ON/OFF (event-toggle debugging). Distinct
	# from left-click (select/pin) and double-click (rewind), so no gesture clash.
	_list.item_clicked.connect(_on_item_clicked)
	vbox.add_child(_list)

	# Decoded-param breakdown for the selected (or currently executing) row.
	# Populated by `_on_item_selected` and auto-refreshed in step mode.
	_details_label = RichTextLabel.new()
	_details_label.bbcode_enabled = true
	_details_label.fit_content = false
	_details_label.scroll_active = true
	_details_label.custom_minimum_size = Vector2(0, 110)
	_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details_label.text = "(select a row to see decoded params)"
	vbox.add_child(_details_label)

	add_separator(vbox)

	# Second button row — "Skip Halt" forces past an unhandled opcode (the
	# main use-case: VM has halted at Display Message and the user wants to
	# step manually past it, one opcode at a time, watching what happens).
	var btn_row2 := add_button_row(vbox)
	var skip_btn := Button.new()
	skip_btn.text = "Skip Halt (force step)"
	skip_btn.pressed.connect(_on_skip_halt_pressed)
	btn_row2.add_child(skip_btn)

	# Event-toggle controls. Right-click any disassembly row to switch that event
	# OFF (skipped like a no-op on the next play/rewind); these buttons toggle the
	# selected row and re-enable everything. Effect shows after a rewind (double-
	# click) replays the chunk without the disabled events.
	var toggle_btn := Button.new()
	toggle_btn.text = "Toggle sel on/off"
	toggle_btn.pressed.connect(_on_toggle_selected_pressed)
	btn_row2.add_child(toggle_btn)
	var enable_all_btn := Button.new()
	enable_all_btn.text = "Enable all events"
	enable_all_btn.pressed.connect(_on_enable_all_pressed)
	btn_row2.add_child(enable_all_btn)

	var toggle_hint := add_label(vbox,
		"Right-click a row (or Toggle sel) to disable an event; rewind to replay without it.")
	toggle_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Rewind-through-root: when the playing scenario is a NESTED group member,
	# double-click rewind replays from the group ROOT through every intermediate
	# member (fast) before rewinding this member's own chunk to the clicked PC, so
	# the world is built up as it would be reaching the member live. OFF = plain
	# single-chunk rewind of just this member. Default ON.
	_rewind_root_cb = TuneField.add(vbox, "Rewind through group root (nested members)",
		"scenario_vm.rewind_through_root", true, {}, Tune.Persist.AUTOSAVE) as CheckBox

	# Screenshot row — captures the viewport to a PNG so we can side-by-side
	# diff against a matching PCSX-Redux frame. Replaces the older env-var
	# trigger in ScenarioPlayerScene.gd (ADR-0051: scene config lives in
	# debug panels, not env vars).
	add_separator(vbox)
	add_section_title(vbox, "Side-by-side capture")
	# The capture path auto-persists (AUTOSAVE) so a chosen output PNG sticks across runs.
	_shot_path_edit = TuneField.add(vbox, "PNG path", "scenario_vm.shot_path",
		"/tmp/scenario_godot.png", {}, Tune.Persist.AUTOSAVE) as LineEdit
	var btn_row3 := add_button_row(vbox)
	var shot_btn := Button.new()
	shot_btn.text = "Screenshot"
	shot_btn.pressed.connect(_on_screenshot_pressed)
	btn_row3.add_child(shot_btn)
	var shot_pause_btn := Button.new()
	shot_pause_btn.text = "Pause + Screenshot"
	shot_pause_btn.pressed.connect(_on_pause_screenshot_pressed)
	btn_row3.add_child(shot_pause_btn)


func _populate_list() -> void:
	if not _vm_alive():
		return
	var insts: Array = _vm.get_instructions()
	if insts.size() == _last_list_size:
		return
	_last_list_size = insts.size()
	_list.clear()
	for i in range(insts.size()):
		_list.add_item(_build_row_text(i))
	# Re-apply the OFF tint for any rows disabled before this (re)populate — after a
	# rebind the row text already carries the OFF prefix via `_build_row_text`, but
	# the custom fg colour is per-item state that `clear()` dropped.
	for pc in _disabled_pcs.keys():
		_apply_disabled_style(int(pc))
	_highlighted_row = -1


# Resolve an instruction's display name LIVE from the authoritative catalog by its
# opcode byte — never the baked `inst["name"]`, which is denormalized into the
# gitignored per-scenario chunks at export time and can go stale relative to the
# committed catalog (that divergence made named opcodes read "Unknown"). This keeps
# the panel aligned with what the runtime VM already does for dispatch. A genuinely
# undecoded opcode still resolves to "Unknown", which is correct.
func _display_name(inst: Dictionary) -> String:
	return EventInstructionSet.name_of(int(inst.get("opcode", -1)))


# Build one disassembly row's text, prefixing "⊘ OFF" when the PC is toggled off so
# the disabled state reads at a glance. Shared by `_populate_list` and the live
# per-row refresh in `_toggle_disabled` so both stay in sync.
func _build_row_text(i: int) -> String:
	var insts: Array = _vm.get_instructions()
	var inst = insts[i]
	var nm := _display_name(inst)
	var off := int(inst.get("offset", 0))
	var params_str := _format_inline_params(inst)
	var prefix := "⊘ OFF  " if _disabled_pcs.has(i) else ""
	return "%spc=%4d  +0x%04X  %-22s  %s" % [prefix, i, off, nm, params_str]


## Pure view refresh — every line below repaints this panel and touches nothing
## else, so BaseDebugPanel's visibility gate stops it when the panel is not on
## screen. Before that gate existed this ran a full disassembly repopulate every
## frame of every scenario with the F3 window closed (W13 / #955).
func _process(_delta: float) -> void:
	if not _vm_alive():
		return
	_populate_list()  # idempotent — repopulates only if chunk changes
	_maybe_scroll_to_rewind_target()
	_refresh_state()
	_highlight_current_pc()
	_refresh_step_mode_details()
	if _play_through_cb.button_pressed != _vm.play_through_skip_unknown:
		_play_through_cb.set_pressed_no_signal(_vm.play_through_skip_unknown)


# Build an inline `name=0xVAL` summary of an instruction's decoded params, for
# the disassembly list row. Hex throughout — FFT data is byte-aligned and the
# user reads it in hex. Caps the string at ~60 chars so list rows stay legible;
# the full breakdown is in the details panel.
func _format_inline_params(inst: Dictionary) -> String:
	var parts: Array[String] = []
	for p in inst.get("params", []):
		var pname := str(p.get("name", "?"))
		var pval := int(p.get("value", 0))
		parts.append("%s=0x%X" % [pname, pval])
	var joined := "  ".join(parts)
	if joined.length() > 60:
		joined = joined.substr(0, 58) + "…"
	return joined


# Full per-param breakdown for the details panel. Includes raw bytes per
# param so the user can correlate the chunk hex against the decoded fields.
func _format_details_text(pc: int, inst: Dictionary) -> String:
	var name := _display_name(inst)
	var opcode := int(inst.get("opcode", 0))
	var off := int(inst.get("offset", 0))
	var unknown: bool = bool(inst.get("unknown", false))

	var lines: Array[String] = []
	lines.append("[b]pc=%d  offset=0x%04X  opcode=0x%02X  %s[/b]" %
		[pc, off, opcode, name])
	var params: Array = inst.get("params", [])
	if params.is_empty():
		lines.append("  (no params)")
	else:
		for p in params:
			var pname := str(p.get("name", "?"))
			var pval := int(p.get("value", 0))
			var pbytes := str(p.get("bytes", ""))
			lines.append("  %-16s = 0x%-8X  bytes=%s" % [pname, pval, pbytes])
	lines.append("raw=%s  unknown=%s" % [str(inst.get("raw", "")), str(unknown)])
	return "\n".join(lines)


# In step mode the details panel auto-tracks the current PC so the user sees
# what just ran — unless they've manually pinned a different row by clicking,
# in which case `_user_pinned_details` keeps their selection sticky.
func _refresh_step_mode_details() -> void:
	if _user_pinned_details:
		return
	if not _vm_alive() or not _vm.paused:
		return
	var pc: int = _vm.get_pc()
	var insts: Array = _vm.get_instructions()
	if pc < 0 or pc >= insts.size():
		return
	_details_label.text = _format_details_text(pc, insts[pc])


func _refresh_state() -> void:
	var insts: Array = _vm.get_instructions()
	var pc: int = _vm.get_pc()
	var running: bool = _vm.is_running()
	var paused: bool = _vm.paused

	var status: String
	if not running:
		status = "HALTED"
	elif paused:
		status = "PAUSED"
	else:
		status = "RUNNING"
	_status_label.text = "Status: %s    (%d / %d opcodes)" % [status, pc, insts.size()]

	if pc >= 0 and pc < insts.size():
		var inst = insts[pc]
		_pc_label.text = "PC: %d  +0x%04X  %s" % [
			pc, int(inst.get("offset", 0)), _display_name(inst)]
	else:
		_pc_label.text = "PC: %d (out of range)" % pc

	_wait_label.text = "Wait ticks remaining: %d" % _vm.get_wait_ticks()

	var lp: float = _vm.camera_director.get_lerp_progress()
	if lp > 0.0 and lp < 1.0:
		_lerp_label.text = "Camera lerp: %.0f%%" % (lp * 100.0)
	else:
		_lerp_label.text = "Camera lerp: idle"


func _highlight_current_pc() -> void:
	var pc: int = _vm.get_pc()
	if pc == _last_pc_rendered:
		return
	_last_pc_rendered = pc
	if _highlighted_row >= 0 and _highlighted_row < _list.item_count:
		# Restore default by clearing the tint (transparent). Godot's ItemList
		# falls back to the theme bg colour when alpha == 0.
		_list.set_item_custom_bg_color(_highlighted_row, Color(0, 0, 0, 0))
	if pc < 0 or pc >= _list.item_count:
		_highlighted_row = -1
		return
	# Yellowish highlight — distinct from the selection-blue so the user can
	# tell "where the VM is" vs "what I clicked".
	_list.set_item_custom_bg_color(pc, Color(0.55, 0.45, 0.10, 0.55))
	_highlighted_row = pc
	# Deliberately do NOT scroll to follow the PC here. Auto-following yanks the
	# user's scroll position to the PC every time it advances, which fights any
	# manual scrolling during playback. Scrolling is now opt-in via Jump-to-PC.


# Scroll the disassembly list so `row` is centred in the viewport. `get_item_rect`
# is in content space (independent of the current scroll), and the vertical
# scrollbar's value uses the same units, so centring is a direct computation.
func _scroll_list_to_row(row: int) -> void:
	if row < 0 or row >= _list.item_count:
		return
	var vbar := _list.get_v_scroll_bar()
	if vbar == null:
		return
	var rect := _list.get_item_rect(row)
	var target := rect.position.y + rect.size.y * 0.5 - _list.size.y * 0.5
	vbar.value = clampf(target, vbar.min_value, max(vbar.min_value, vbar.max_value - vbar.page))


# After a double-click rewind reloads the scene, scroll the disassembly to the
# rewound-to PC once the VM has actually settled there. We wait for fast-forward
# to finish (`not is_fast_playing`) and the VM to be paused at its rewind endpoint
# — for a plain single-chunk rewind that's a few frames; for a through-root walk
# it's after the intermediate members have played out — and for the target row to
# exist in the repopulated list. Reuses the same proven scroll path as Jump-to-PC.
func _maybe_scroll_to_rewind_target() -> void:
	if _pending_scroll_row < 0:
		return
	if not _vm_alive() or _vm.is_fast_playing() or not _vm.paused:
		return
	if _pending_scroll_row >= _list.item_count:
		return  # chunk not (re)populated yet — wait
	_scroll_list_to_row(_pending_scroll_row)
	_pending_scroll_row = -1


func _on_item_selected(index: int) -> void:
	# Single-click → pin the details panel to this row. Double-click
	# (`item_activated`) is the rewind trigger.
	if not _vm_alive():
		return
	var insts: Array = _vm.get_instructions()
	if index < 0 or index >= insts.size():
		return
	_user_pinned_details = true
	_details_label.text = _format_details_text(index, insts[index])


func _on_item_activated(index: int) -> void:
	# Double-click → rewind. The scene reloads, then ScenarioPlayerScene reads
	# `ScenarioDebugSession.rewind_target_pc` and routes it into the freshly
	# booted VM's `set_rewind_target`.
	if not _vm_alive():
		return
	var insts: Array = _vm.get_instructions()
	if index < 0 or index >= insts.size():
		return
	_request_rewind(index)


# Right-click a disassembly row → toggle that event ON/OFF. `item_clicked` carries
# the mouse button, so gate on RIGHT (left-click stays select/pin, double stays rewind).
func _on_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	if mouse_button_index != MOUSE_BUTTON_RIGHT:
		return
	_toggle_disabled(index)


# Flip the disabled state of the instruction at `index`, mirror it into the live VM
# (so the very next play/rewind honours it), and refresh just that row's text + tint.
func _toggle_disabled(index: int) -> void:
	if not _vm_alive():
		return
	var insts: Array = _vm.get_instructions()
	if index < 0 or index >= insts.size():
		return
	if _disabled_pcs.has(index):
		_disabled_pcs.erase(index)
	else:
		_disabled_pcs[index] = true
	_vm.disabled_pcs = _disabled_pcs.duplicate()
	_list.set_item_text(index, _build_row_text(index))
	_apply_disabled_style(index)
	print("[ScenarioVMDebugPanel] event pc=%d %s" %
		[index, "DISABLED" if _disabled_pcs.has(index) else "enabled"])


# Toggle the currently-selected row (button-driven twin of the right-click gesture).
func _on_toggle_selected_pressed() -> void:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		push_warning("[ScenarioVMDebugPanel] select a disassembly row first, then Toggle sel")
		return
	_toggle_disabled(sel[0])


# Re-enable every disabled event and repaint the affected rows.
func _on_enable_all_pressed() -> void:
	if _disabled_pcs.is_empty():
		return
	var was: Array = _disabled_pcs.keys()
	_disabled_pcs.clear()
	if _vm_alive():
		_vm.disabled_pcs = {}
	for pc in was:
		var i := int(pc)
		if i >= 0 and i < _list.item_count:
			_list.set_item_text(i, _build_row_text(i))
			_apply_disabled_style(i)
	print("[ScenarioVMDebugPanel] all %d disabled event(s) re-enabled" % was.size())


# Tint a row's text to read as disabled (dim red) or restore the default (white).
# fg colour is independent of the current-PC BG highlight, so the two compose.
func _apply_disabled_style(index: int) -> void:
	if index < 0 or index >= _list.item_count:
		return
	if _disabled_pcs.has(index):
		_list.set_item_custom_fg_color(index, Color(0.85, 0.42, 0.42, 0.9))
	else:
		_list.set_item_custom_fg_color(index, Color(1, 1, 1, 1))


# Stage a rewind: park the target PC in the persistent ScenarioDebugSession
# autoload, then hard-reload the scene. On boot, ScenarioPlayerScene reads
# the target PC and calls `_vm.set_rewind_target(N)` to fast-forward up to
# (but not past) the clicked instruction, then pauses. The panel itself
# survives the reload — DebugOverlay reuses it via `rebind` rather than
# recreating — so scroll position, selected row, and every spinbox/checkbox
# value persist across the reload.
func _request_rewind(target_pc: int) -> void:
	ScenarioDebugSession.rewind_target_pc = target_pc
	# Remember where to scroll once the reload + fast-forward settles. This panel
	# survives the reload (DebugOverlay autoload), so the field persists; the
	# actual scroll happens in `_maybe_scroll_to_rewind_target` when the VM has
	# fast-forwarded to and paused at this PC.
	_pending_scroll_row = target_pc
	# Rewind-through-root: if the playing scenario is a NESTED group member (not its
	# setup root), the toggle is on, AND the path planner can actually build a route
	# that reaches it, park a path-walk target so the scene replays from the group
	# root through the intermediate members before rewinding this member's chunk to
	# `target_pc`. Otherwise a plain single-chunk rewind of the member itself.
	var active: int = ScenarioDebugSession.active_scenario_id
	var root := ScenarioGroupDatabase.root_for_scenario(active)
	var through_root: bool = _rewind_root_cb == null or _rewind_root_cb.button_pressed
	if ScenarioDebugSession.navigator_resume_root > 0:
		# The scene on screen is a NAVIGATOR walk, not plain scenario playback, so park
		# nothing but the PC: `NavigatorMain._ready` resumes the walk from its own parked
		# position and consumes `rewind_target_pc` there. Both branches below are wrong
		# here — `path_target_scenario_id` would hand the next boot to `super._ready()` and
		# drop the walk entirely, and `selected_scenario_id` would fight the walk's own
		# `_boot_world_for`. Before this branch existed the walk had no way to say it was
		# live (`active_scenario_id` read -1 throughout), the fallback below ran, and the
		# reload booted the story start — the "rewind inside root 28, land at Orbonne" bug.
		print("[ScenarioVMDebugPanel] rewind → pc=%d inside the navigator walk (root %d, action %d, scene reload)"
			% [target_pc, ScenarioDebugSession.navigator_resume_root,
			ScenarioDebugSession.navigator_resume_action])
	elif through_root and active > 0 and root > 0 and active != root and _path_reaches(active):
		ScenarioDebugSession.path_target_scenario_id = active
		print("[ScenarioVMDebugPanel] rewind-from-root → member %d pc=%d (group root %d, scene reload)" %
			[active, target_pc, root])
	else:
		# Single-chunk rewind: pin the member itself as the booted scenario — a prior
		# through-root walk leaves `selected_scenario_id` on the ROOT, which would
		# otherwise boot the setup instead of the member we're debugging.
		if active > 0:
			ScenarioDebugSession.selected_scenario_id = active
		print("[ScenarioVMDebugPanel] rewind → pc=%d (scene reload)" % target_pc)
	get_tree().reload_current_scene()


# True iff [ScenarioPath] can plan a route to `target` (nested member) whose final
# step actually lands on it. Guards against groups whose battle-conditional yields
# no edges / can't reach the member — there we fall back to a single-chunk rewind
# rather than booting the root with a broken empty plan.
func _path_reaches(target: int) -> bool:
	var bc_id := ScenarioGroupDatabase.bc_id_for_scenario(target)
	if bc_id < 0:
		return false
	var plan: Array = ScenarioPath.new().plan(bc_id, target)
	if plan.is_empty():
		return false
	return int((plan[plan.size() - 1] as Dictionary).get("member_scenario_id", -1)) == target


func _on_pause_pressed() -> void:
	if _vm_alive():
		_vm.paused = true


func _on_resume_pressed() -> void:
	if _vm_alive():
		_vm.paused = false
		_user_pinned_details = false


func _on_step_pressed() -> void:
	if _vm_alive():
		_vm.step(1)
		_user_pinned_details = false


func _on_step_n_pressed(n: int) -> void:
	if _vm_alive():
		_vm.step(n)
		_user_pinned_details = false


func _on_jump_pressed() -> void:
	# Force the list to scroll back to the current PC after the user has
	# scrolled away to look at later opcodes. Resetting _last_pc_rendered makes
	# _highlight_current_pc re-run even when the PC hasn't moved (e.g. paused on
	# a wait), which re-tints the PC row. The scroll is explicit here (it is no
	# longer done automatically on every PC advance).
	if _vm_alive():
		_last_pc_rendered = -1
		_highlight_current_pc()
		_scroll_list_to_row(_vm.get_pc())


func _on_skip_halt_pressed() -> void:
	if _vm_alive():
		_vm.force_skip_current()


func _on_play_through_toggled(pressed: bool) -> void:
	if _vm_alive():
		_vm.play_through_skip_unknown = pressed


func _on_auto_advance_toggled(pressed: bool) -> void:
	if _vm_alive():
		_vm.dialog_auto_advance = pressed


func _on_screenshot_pressed() -> void:
	_save_screenshot()


func _on_pause_screenshot_pressed() -> void:
	if _vm_alive():
		_vm.paused = true
	# One process frame so the VM's pause state flushes before the grab; the
	# camera body itself doesn't move during a paused frame so this only
	# matters when the user wanted "stop on this exact opcode".
	await get_tree().process_frame
	_save_screenshot()


func _save_screenshot() -> void:
	var path := _shot_path_edit.text.strip_edges()
	if path == "":
		push_warning("[ScenarioVMDebugPanel] screenshot path empty")
		return
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		push_error("[ScenarioVMDebugPanel] screenshot save_png(%s) failed: %d" % [path, err])
		return
	# Bundle the camera + focal-tile state into the print so we can correlate
	# screenshots against the formula investigation in one log line.
	if _vm_alive() and _vm.camera_director != null:
		print("[ScenarioVMDebugPanel] screenshot -> %s  %s" % [path, _vm.camera_director.describe_last_camera_for_log()])
	else:
		print("[ScenarioVMDebugPanel] screenshot -> %s" % path)
