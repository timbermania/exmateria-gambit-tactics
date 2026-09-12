class_name ScenarioWeatherDebugPanel
extends BaseDebugPanel

## F3 tuning panel for {3C} Weather (the map-wide rain particle system,
## `ScenarioWeather`). The RENDER MODEL is closed against live HW
## (WEATHER_OPCODE_3C_INVESTIGATION.md §15) — this panel does NOT re-derive it;
## it just dials the handful of Godot-mapping look knobs (additive intensity,
## pixel width/length, splat dimness/size).
##
## Every look knob is a shared TuneField bound to a `weather.*` slug (ADR-0068 move
## 2): ScenarioWeather OWNS these values (it binds each slug in _ready), so this panel
## is just a VIEW (decision 12). The weather node is LAZILY created by the VM on the
## first {3C} opcode (Orbonne PC-6), but that no longer matters to the knobs — the
## slug holds the value with or without a node, and the node coalesces it the instant
## it spawns. So a dialled-in look survives a click-to-rewind reload for free, and the
## panel no longer polls/pushes spinboxes. The "Force rain" controls (VM-specific)
## stay so the look can be spawned on demand before PC-6.
##
## No env vars (feedback_no_env_vars_for_scene_config) — every knob lives here.

const TuneField = preload("res://src/debug/TuneField.gd")

var _vm  # ScenarioVM — held only for the Force-rain buttons + status readout.
var _status: Label


func setup(vm) -> void:
	_vm = vm
	panel_title = "Scenario Weather"
	panel_category = Category.SCENARIO_LOOK
	_build_ui()
	_refresh_status()


## Survives a scene reload (owned by DebugOverlay); re-point at the fresh VM. The knob
## VALUES are owned by Tune now, so the freshly-spawned weather node coalesces them on
## its own _ready bind — nothing to push here.
func rebind(vm) -> void:
	_vm = vm
	_refresh_status()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	add_child(vbox)

	# Pure VIEW (ADR-0068 decision 12): slug only — ScenarioWeather owns every default + hint,
	# read back from the registry. No defaults/hints, no owner symbols.
	add_section_title(vbox, "Drops (screen-vertical streaks, §15.1/.2)")
	TuneField.add(vbox, "Additive intensity", "weather.drop_intensity")
	TuneField.add(vbox, "Width (PSX px)", "weather.drop_width_px")
	TuneField.add(vbox, "Length scale", "weather.drop_length_scale")

	add_separator(vbox)
	add_section_title(vbox, "Splats (dim diamond ring, §15.3/.4)")
	TuneField.add(vbox, "Additive intensity", "weather.splat_intensity")
	TuneField.add(vbox, "Size (tiles)", "weather.splat_size")
	TuneField.add(vbox, "Straddle gate (off = every landing splats)", "weather.splat_straddle_gate")

	add_separator(vbox)
	add_section_title(vbox, "Force rain (tune before PC-6)")
	var row := add_button_row(vbox)
	for s in [2, 3, 4]:
		var b := Button.new()
		b.text = "Str %d" % s
		b.pressed.connect(_on_force_strength.bind(s))
		row.add_child(b)
	var off := Button.new()
	off.text = "Off"
	off.pressed.connect(_on_force_off)
	row.add_child(off)

	add_separator(vbox)
	_status = add_label(vbox, "weather node: (none yet)")
	add_print_values_button(vbox, "Print Values (to bake as defaults)")


func on_shown() -> void:
	_refresh_status()


# --- node access ------------------------------------------------------------

func _node() -> ScenarioWeather:
	if not is_instance_valid(_vm):
		return null
	return _vm.get_weather_node()


## Update just the status readout (the knob rows are TuneField-owned and self-sync).
func _refresh_status() -> void:
	if _status == null:
		return
	var w := _node()
	if w == null:
		_status.text = "weather node: (none yet — Force rain to spawn)"
	else:
		_status.text = "weather node: LIVE (active=%s)" % str(w._active)


# --- force-rain affordance ---------------------------------------------------

func _on_force_strength(strength: int) -> void:
	if not is_instance_valid(_vm):
		return
	# The spawned node coalesces the current weather.* overrides on its own bind.
	_vm.debug_force_weather(true, strength)
	_refresh_status()

func _on_force_off() -> void:
	if is_instance_valid(_vm):
		_vm.debug_force_weather(false, 0)
	_refresh_status()


# --- override the base "Print Values" to dump the bake-ready knob set ---------

func _on_print_values() -> void:
	print("[ScenarioWeather] bake these as defaults:")
	print("  drop_intensity      = %.3f" % Tune.get_value("weather.drop_intensity"))
	print("  drop_width_px       = %.3f" % Tune.get_value("weather.drop_width_px"))
	print("  drop_length_scale   = %.3f" % Tune.get_value("weather.drop_length_scale"))
	print("  splat_intensity     = %.3f" % Tune.get_value("weather.splat_intensity"))
	print("  splat_size          = %.3f" % Tune.get_value("weather.splat_size"))
	print("  splat_straddle_gate = %s" % str(Tune.get_value("weather.splat_straddle_gate")))
