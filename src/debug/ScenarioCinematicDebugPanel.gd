class_name ScenarioCinematicDebugPanel
extends BaseDebugPanel

## EVTCHR cinematic pose scrubber (issue #124). Overrides the segment / frame the
## cinematic Unit-Anim resolver would auto-pick, so we can scrub through a segment's
## ~40 poses until the right one shows up and side-by-side it against PCSX. Both
## default to -1 = auto (resolver picks). "Re-apply" re-fires the most recent
## cinematic Unit Anim with the current overrides without restarting the scenario.
##
## The two override rows are shared TuneField controls bound to `scenario.*` slugs
## (ADR-0068 move 2): ScenarioVM OWNS the overrides (it binds each slug in _ready and
## re-fires the last cinematic on a scrub), so this panel is just a VIEW (decision
## 12). The override now survives a scenario reload for free — the freshly-booted
## VM's bind re-reads the slug — so `rebind` only has to re-point the Re-apply button.

const TuneField = preload("res://src/debug/TuneField.gd")

var _vm  # ScenarioVM — held only so the Re-apply button targets the live VM.


func setup(vm) -> void:
	_vm = vm
	panel_title = "Scenario Cinematic (EVTCHR)"
	panel_category = Category.SCENARIO_LOOK
	_build_ui()


# Re-point the Re-apply button at a freshly-booted VM after a scene reload. The
# override VALUES are owned by Tune now, so the new VM coalesces them on its own
# _ready bind — nothing to re-push here.
func rebind(vm) -> void:
	_vm = vm


func _vm_alive() -> bool:
	return _vm != null and is_instance_valid(_vm)


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(360, 0)
	add_child(vbox)

	# Segment override (-1 = auto). Frame override (-1 = auto = first LoadFrameWait
	# from the cinematic bytecode; valid 0xD2..0xF9 = 210..249, the runtime
	# script-byte form parse_evtchr_frames.py keys on).
	add_section_title(vbox, "EVTCHR pose scrub (issue #124)")

	# Pure VIEW (ADR-0068 decision 12): slug only — ScenarioVM owns the default + hint, read
	# back from the registry. No default/hint, no owner symbols.
	TuneField.add(vbox, "Segment (-1=auto)", "scenario.cinematic_segment_override")
	TuneField.add(vbox, "Frame (-1=auto, 210..249)", "scenario.cinematic_frame_override")

	var cin_btn_row := add_button_row(vbox)
	var reapply_btn := Button.new()
	reapply_btn.text = "Re-apply last cinematic Unit Anim"
	reapply_btn.pressed.connect(_on_reapply_cinematic_pressed)
	cin_btn_row.add_child(reapply_btn)


func _on_reapply_cinematic_pressed() -> void:
	if not _vm_alive() or not _vm.reapply_last_cinematic():
		push_warning("[ScenarioCinematicDebugPanel] No cinematic Unit Anim to re-apply yet")
