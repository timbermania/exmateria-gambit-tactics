class_name SimulationDebugPanel
extends BaseDebugPanel
## Simulation controls: time-scale toggle (pause/run/2x cycle), combat RNG
## seed input, and "Run with Seed" reload button. Reflects DebugConfig.
## time_scale, .combat_seed, .active_combat_seed.

const TuneField = preload("res://src/debug/TuneField.gd")

## Set by a host that MOUNTS a [TurnDirector] before it calls `setup()` — the between-turn
## playback row is shown only then. A scene running a bare [CombatLoop] has nothing for
## that rate to scale, and a knob that reaches nothing is worse than an absent one.
var show_playback_rate: bool = false

var _time_scale_button: Button
var _seed_input: LineEdit
var _active_seed_edit: LineEdit


func setup() -> void:
	panel_title = "Simulation"
	panel_category = Category.SIMULATION
	_build_ui()
	# Keep button text in sync when time_scale changes outside this panel
	# (Space key in GPUArena, CLI --time-scale arg, etc.).
	DebugConfig.time_scale_changed.connect(func(_v): _update_buttons())


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(220, 0)
	add_child(main_vbox)

	# === SPEED ===
	var speed_section = create_collapsible_section(main_vbox, "Speed", true)
	_time_scale_button = Button.new()
	_time_scale_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_scale_button.pressed.connect(_on_time_scale_pressed)
	speed_section.add_child(_time_scale_button)

	# === PACING ===
	# The two knobs that re-time FFT's turn-based balance for continuous combat.
	# Pure view (ADR-0068): the slugs are bound by GPUBatchSimulator, which is
	# also the only reader — it pull-reads them into the SimConfig buffer every
	# pass, so a scrub here lands on the next tick with no battle restart.
	var pacing_section = create_collapsible_section(main_vbox, "Pacing", true)
	_wrapped(pacing_section, "Travel time x. Higher = slower approach against a fixed action rate, which favours ranged.")
	TuneField.add(pacing_section, "Move time", GPUBatchSimulator.MOVE_TIME_SCALE_SLUG)
	_wrapped(pacing_section, "Damage AND healing x, so their ratio holds. Lower = more hits to kill, which is what buys room for more to happen.")
	TuneField.add(pacing_section, "Damage", GPUBatchSimulator.DAMAGE_SCALE_SLUG)

	# The third knob, and the only one of the three that changes NOTHING about the
	# sim — the stretch's length in ticks is fixed, so this is how long you spend
	# WATCHING it.
	#
	# Gated on a HOST FLAG, not on `Tune.is_registered`. That was the first shape and
	# it is a predicate that cannot fail: naming `TurnDirector.PLAYBACK_RATE_SLUG` in
	# this file class-loads TurnDirector, whose `_static_init` binds the slug — so the
	# registration test is true in every scene, including the ones with no director to
	# steer. The knob would render, scrub the static var, and reach NOTHING (an
	# ADR-0068 R8 dead scrub). Only the host knows whether it mounts a director, so the
	# host is what says so.
	if show_playback_rate:
		_wrapped(pacing_section, "Between-turn playback x. Pure viewing rate — the stretch is a fixed number of ticks, so this cannot change an outcome.")
		TuneField.add(pacing_section, "Playback", TurnDirector.PLAYBACK_RATE_SLUG)

	# === SEED ===
	var seed_section = create_collapsible_section(main_vbox, "Seed", true)

	var active_hbox = HBoxContainer.new()
	active_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_section.add_child(active_hbox)

	var active_label = Label.new()
	active_label.text = "Active:"
	active_hbox.add_child(active_label)

	# tune-exempt: read-only display of DebugConfig.active_combat_seed (the seed the current
	# battle actually used, set by GPUArena at startup) — a data-driven readout, not editable.
	_active_seed_edit = LineEdit.new()  # tune-exempt: read-only readout of DebugConfig.active_combat_seed
	_active_seed_edit.editable = false
	_active_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_active_seed_edit.text = str(DebugConfig.active_combat_seed) if DebugConfig.active_combat_seed >= 0 else "(none)"
	active_hbox.add_child(_active_seed_edit)

	var seed_hbox = HBoxContainer.new()
	seed_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_section.add_child(seed_hbox)

	var seed_label = Label.new()
	seed_label.text = "Seed:"
	seed_label.add_theme_color_override("font_color", TuneField.AUTOSAVE_ACCENT)
	seed_hbox.add_child(seed_label)

	# The combat seed auto-persists (green, ADR-0068) for reproducibility across launches.
	# DebugConfig OWNS the slug (reads it at boot into .combat_seed); this LineEdit is the
	# VIEW, so it's built control-only to keep the inline "Seed:" layout. Raw text ""=random.
	_seed_input = TuneField.build_control("simulation.combat_seed", "", {},
		Callable(), Tune.Persist.AUTOSAVE) as LineEdit
	_seed_input.placeholder_text = "0 = random"
	_seed_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_input.text_submitted.connect(_on_seed_submitted)
	seed_hbox.add_child(_seed_input)

	var run_button = Button.new()
	run_button.text = "Run with Seed"
	run_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	run_button.pressed.connect(func(): DebugConfig.request_run_with_seed())
	seed_section.add_child(run_button)

	_update_buttons()


func on_shown() -> void:
	_update_buttons()


func _on_time_scale_pressed() -> void:
	DebugConfig.cycle_time_scale()


func _on_seed_submitted(text: String) -> void:
	var value = text.strip_edges().to_int()
	DebugConfig.combat_seed = value
	_seed_input.release_focus()


func _update_buttons() -> void:
	if _time_scale_button:
		_time_scale_button.text = "PAUSED" if DebugConfig.time_scale == 0.0 else "RUNNING"


## A word-wrapped description label capped to the panel width.
func _wrapped(parent: Control, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(210, 0)
	label.add_theme_font_size_override("font_size", 10)
	parent.add_child(label)
	return label
