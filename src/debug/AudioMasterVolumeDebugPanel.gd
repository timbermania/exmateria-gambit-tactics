class_name AudioMasterVolumeDebugPanel
extends BaseDebugPanel

## Whole-game volume — the Godot Master bus, in the AUDIO tab of the F3 overlay.
##
## THE HOST'S HALF of what used to be `SpuAudioDebugPanel` (ADR-0153 dec. 2/4, split at
## #409). Its subject is `MasterBus`: the Amplify-before-HardLimiter rack and the
## `UserSettings` persistence, neither of which ships with the sound package. A view
## splits where its subject splits, so the panel did too.
##
## It KEEPS `extends BaseDebugPanel`, and that is not an oversight: ADR-0151's rule binds
## files under an **addon** root, and a host panel inheriting a host base class is the
## published interface working as intended.
##
## A plain slider VIEW, not a `TuneField` row: live-apply on drag (no disk thrash), persist
## on drag_ended. A genuine per-machine user setting, so it is a slider, not a Tune slug.

var _volume_slider: HSlider
var _volume_label: Label


func setup() -> void:
	panel_title = "Whole-game volume"
	panel_category = Category.AUDIO
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	add_child(vbox)

	add_section_title(vbox, "Whole-game volume (Master bus)")
	add_label(vbox, "All music + SFX + UI re-sum here — the true global control.")

	var row := HBoxContainer.new()
	vbox.add_child(row)
	add_label(row, "Volume:", 90)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.custom_minimum_size.x = 160
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value = MasterBus.get_master_volume()
	row.add_child(_volume_slider)

	_volume_label = add_label(row, _volume_text(_volume_slider.value), 50)

	# Live-apply while dragging (persist=false), then commit to disk when the drag ends.
	_volume_slider.value_changed.connect(func(v: float) -> void:
		MasterBus.set_master_volume(v, false)
		_volume_label.text = _volume_text(v))
	_volume_slider.drag_ended.connect(func(_changed: bool) -> void:
		MasterBus.set_master_volume(_volume_slider.value, true))

	add_separator(vbox)
	add_print_values_button(vbox)


func _volume_text(v: float) -> String:
	return "%d%%" % int(round(v * 100.0))


func on_shown() -> void:
	# The value can change elsewhere (another surface, a boot-load); resync on show.
	if _volume_slider != null:
		_volume_slider.set_value_no_signal(MasterBus.get_master_volume())
		_volume_label.text = _volume_text(_volume_slider.value)


func _on_print_values() -> void:
	print("[AudioMasterVolumeDebugPanel] master_volume = %.2f (gain %.1f dB)"
		% [MasterBus.get_master_volume(), MasterBus.get_master_gain_db()])
