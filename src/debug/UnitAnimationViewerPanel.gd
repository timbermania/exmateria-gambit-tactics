class_name UnitAnimationViewerPanel
extends BaseDebugPanel

## Unit Animation Viewer debug panel — world-state knobs only
## (ADR-0021, ADR-0024).
##
## Unit state (job, gender, equipment) is reconfigured through the
## production CombatUI (UICombatManager) — that's the in-scene portrait,
## detail menus, and equipment popup wired by the viewer scene. This
## panel carries only the axes production has no UI for: what the unit
## is currently *doing* (DisplayActivity.Activity), where it's facing, the target
## elevation for ATTACKING, and the ability id for SPELL_CASTING /
## CHARGING. The "Resolution readout" surfaces `unit.last_resolution`
## with `atlas` / `miss` source coloring so the resolver can be
## hand-authored interactively.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const DisplayActivity = ExMateriaSpriteRig.DisplayActivity

# #809 — `AnimationNames` moved into the addon with the rest of the SEQ
# vocabulary; this keeps the three readout lines below spelled the way they were
# (ADR-0211 dec. 4).
const AnimationNames = ExMateriaSpriteRig.AnimationNames

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const ItemDatabase = ExMateriaAlmanac.ItemDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const UnitProgression = ExMateriaAlmanac.UnitProgression

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const FacingDirection = ExMateriaSchema.Facing.Direction

const TuneField = preload("res://src/debug/TuneField.gd")

const ACTIVITY_NAMES := [
	"IDLE", "IDLE_LOW_HEALTH", "WALKING", "JUMPING", "LANDING",
	"USING_ITEM", "DYING", "DEAD", "GETTING_UP",
	"ATTACKING", "SPELL_CHARGING", "SPELL_CASTING",
	"CELEBRATING", "AWAITING_IMPACT",
]

const FACING_LABELS := ["NORTH (+X)", "EAST (+Z)", "SOUTH (-X)", "WEST (-Z)"]
const VERTICAL_LABELS := ["HIGH (target above)", "MID (same height)", "LOW (target below)"]
const GENDER_LOCKED_MALE_JOBS := {"5b": true}    # Bard
const GENDER_LOCKED_FEMALE_JOBS := {"5c": true}  # Dancer

var _unit: Unit

# Unit identity overrides (debug-only; production CombatUI's UIJobPopup is
# correctly scoped to the limited player-pickable subset).
var _job_dropdown: OptionButton
var _gender_male_btn: CheckBox
var _gender_female_btn: CheckBox
var _gender_constraint_label: Label
var _job_ids: Array[String] = []

# World-state controls
var _activity_dropdown: OptionButton
var _facing_dropdown: OptionButton
var _vertical_dropdown: OptionButton
var _ability_spin: SpinBox
var _ability_name_label: Label
var _replay_btn: Button
var _auto_loop_toggle: CheckBox
var _readout: RichTextLabel


func setup(unit: Unit) -> void:
	_unit = unit
	panel_title = "Unit Animation Viewer"
	panel_category = Category.UNIT
	_build_ui()
	call_deferred("_sync_from_unit")


func _build_ui() -> void:
	custom_minimum_size = Vector2(380, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)

	# Identity overrides — production CombatUI's UIJobPopup only lists the
	# player-pickable jobs (0x4A-0x5D). This section exposes the full ~160
	# jobs.json universe (special characters, monsters, secret jobs) so the
	# viewer can author against any sprite. Driven through unit.change_job /
	# unit_progression.base_stat_type — same code path the production UI uses.
	add_section_title(vb, "Unit identity overrides")

	# The previewed job auto-persists (green, ADR-0068) so you resume on the same sprite next
	# launch. Dynamic (~160 jobs from JobDatabase), so it uses the string-keyed dropdown
	# affordance: the job id is the stable key; _sync_from_unit late-selects + APPLIES it.
	_job_dropdown = TuneField.add_dropdown(vb, "Job (full)", "anim_viewer.job", "",
		Tune.Persist.AUTOSAVE)
	_populate_job_dropdown()
	_job_dropdown.item_selected.connect(_on_job_picked)

	var gender_box := HBoxContainer.new()
	var gender_group := ButtonGroup.new()  # mutual-exclusion: only one selected at a time
	# Mirror of unit_progression.base_stat_type (owned by the unit), coupled to the job via
	# gender-locks + ButtonGroup mutual-exclusion — not a standalone pref.
	_gender_male_btn = CheckBox.new()  # tune-exempt: data-driven mirror of unit base_stat_type
	_gender_male_btn.text = "Male"
	_gender_male_btn.button_group = gender_group
	_gender_male_btn.toggled.connect(func(p): if p: _on_gender_picked(false))
	_gender_female_btn = CheckBox.new()  # tune-exempt: data-driven mirror of unit base_stat_type
	_gender_female_btn.text = "Female"
	_gender_female_btn.button_group = gender_group
	_gender_female_btn.toggled.connect(func(p): if p: _on_gender_picked(true))
	gender_box.add_child(_gender_male_btn)
	gender_box.add_child(_gender_female_btn)
	_row(vb, "Gender", gender_box)
	_gender_constraint_label = Label.new()
	_gender_constraint_label.add_theme_font_size_override("font_size", 10)
	_gender_constraint_label.text = ""
	vb.add_child(_gender_constraint_label)

	add_separator(vb)
	add_section_title(vb, "World state")

	# The previewed world state auto-persists (green, ADR-0068) so you resume the same
	# activity/facing/vertical/ability next launch; _sync_from_unit applies them on boot.
	# These are STATIC enums, so they use the enum path of the shared TuneField builder
	# (label→index map known upfront) rather than the dynamic dropdown affordance.
	_activity_dropdown = TuneField.add(vb, "Activity", "anim_viewer.activity", 0,
		{"enum": _index_enum(ACTIVITY_NAMES)}, Tune.Persist.AUTOSAVE) as OptionButton
	_activity_dropdown.item_selected.connect(func(_i): _apply_activity())

	# Replay button + Auto-loop toggle live on one row under the activity picker.
	# Useful for non-looping activities (ATTACKING, SPELL_CASTING, …) where
	# the user can't re-watch without toggling activity off and back on.
	var ctl_row := HBoxContainer.new()
	_replay_btn = Button.new()
	_replay_btn.text = "Replay"
	_replay_btn.pressed.connect(_apply_activity)
	_replay_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl_row.add_child(_replay_btn)
	# Auto-loop is a momentary playback convenience → EPHEMERAL (grey): a session that
	# auto-re-fires on next launch would surprise, not delight. Built control-only to keep
	# it inline with Replay; the grey text says "session-only".
	_auto_loop_toggle = TuneField.build_control("anim_viewer.auto_loop", false, {},
		Callable(), Tune.Persist.EPHEMERAL) as CheckBox
	_auto_loop_toggle.text = "Auto-loop"
	_auto_loop_toggle.add_theme_color_override("font_color", TuneField.EPHEMERAL_ACCENT)
	_auto_loop_toggle.toggled.connect(_on_auto_loop_toggled)
	ctl_row.add_child(_auto_loop_toggle)
	_row(vb, "", ctl_row)

	_facing_dropdown = TuneField.add(vb, "Facing", "anim_viewer.facing",
		FacingDirection.SOUTH, {"enum": _index_enum(FACING_LABELS)},
		Tune.Persist.AUTOSAVE) as OptionButton
	_facing_dropdown.item_selected.connect(_on_facing_picked)

	_vertical_dropdown = TuneField.add(vb, "Attack vertical", "anim_viewer.vertical", 1,
		{"enum": _index_enum(VERTICAL_LABELS)}, Tune.Persist.AUTOSAVE) as OptionButton
	_vertical_dropdown.item_selected.connect(func(_i): _apply_activity())

	_ability_spin = TuneField.add(vb, "Ability id", "anim_viewer.ability_id", 1,
		{"min": 0, "max": 511, "step": 1}, Tune.Persist.AUTOSAVE) as SpinBox
	_ability_spin.value_changed.connect(func(_v): _refresh_ability_label(); _apply_activity_if_ability_driven())
	_ability_name_label = Label.new()
	_ability_name_label.add_theme_font_size_override("font_size", 10)
	vb.add_child(_ability_name_label)

	add_separator(vb)
	add_section_title(vb, "Resolution readout")

	_readout = RichTextLabel.new()
	_readout.bbcode_enabled = true
	_readout.fit_content = true
	_readout.custom_minimum_size = Vector2(0, 260)
	_readout.scroll_active = false
	vb.add_child(_readout)


# A label→index enum map for the shared TuneField enum path: each list entry maps to its
# own index, so the persisted value is the ordinal the panel's handlers already read via
# OptionButton.selected (insertion order preserves index == metadata).
func _index_enum(labels: Array) -> Dictionary:
	var out := {}
	for i in labels.size():
		out[String(labels[i])] = i
	return out


func _row(parent: VBoxContainer, label_text: String, control: Control) -> void:
	var hb := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	hb.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(control)
	parent.add_child(hb)


# -----------------------------------------------------------------------------
# Unit identity overrides — debug-only access to the full jobs.json universe
# -----------------------------------------------------------------------------

func _populate_job_dropdown() -> void:
	_job_dropdown.clear()
	_job_ids.clear()
	if not JobDatabase._loaded:
		JobDatabase._ensure_loaded()
	var keys: Array = JobDatabase._jobs.keys()
	keys.sort()
	for k in keys:
		var job_data: Dictionary = JobDatabase._jobs[k]
		var name: String = String(job_data.get("name", "?"))
		_job_dropdown.add_item("0x%s — %s" % [String(k).to_upper(), name])
		_job_ids.append(String(k))


func _on_job_picked(idx: int) -> void:
	if idx < 0 or idx >= _job_ids.size() or not is_instance_valid(_unit):
		return
	var job_id: String = _job_ids[idx]
	# If the new job is gender-locked, swap base_stat_type *before* change_job so
	# sprite_id resolves to the correct M/F variant on the first call.
	if GENDER_LOCKED_MALE_JOBS.has(job_id):
		_unit.unit_progression.base_stat_type = UnitProgression.BaseStatType.MALE
	elif GENDER_LOCKED_FEMALE_JOBS.has(job_id):
		_unit.unit_progression.base_stat_type = UnitProgression.BaseStatType.FEMALE
	_unit.change_job(job_id)
	_sync_gender_buttons_from_unit()
	_apply_activity()
	_render_readout()


func _on_gender_picked(is_female: bool) -> void:
	if not is_instance_valid(_unit) or not _unit.unit_progression:
		return
	var current_job: String = _unit.unit_progression.current_job_id
	if (is_female and GENDER_LOCKED_MALE_JOBS.has(current_job)) \
			or (not is_female and GENDER_LOCKED_FEMALE_JOBS.has(current_job)):
		_sync_gender_buttons_from_unit()
		return
	_unit.unit_progression.base_stat_type = (
		UnitProgression.BaseStatType.FEMALE if is_female else UnitProgression.BaseStatType.MALE
	)
	# Re-fire change_job(current) to recompute sprite_id under the new gender —
	# Unit.change_job now folds the sprite_id refresh; CombatUI listens to
	# unit_progression.job_changed so the portrait re-paints automatically.
	_unit.change_job(current_job)
	_apply_activity()
	_render_readout()


func _sync_gender_buttons_from_unit() -> void:
	if not is_instance_valid(_unit) or not _unit.unit_progression:
		return
	var is_female: bool = _unit.unit_progression.base_stat_type == UnitProgression.BaseStatType.FEMALE
	_gender_male_btn.set_pressed_no_signal(not is_female)
	_gender_female_btn.set_pressed_no_signal(is_female)
	var job_id: String = _unit.unit_progression.current_job_id
	var lock_male: bool = GENDER_LOCKED_MALE_JOBS.has(job_id)
	var lock_female: bool = GENDER_LOCKED_FEMALE_JOBS.has(job_id)
	_gender_male_btn.disabled = lock_female
	_gender_female_btn.disabled = lock_male
	if lock_male:
		_gender_constraint_label.text = "  Job is gender-locked to MALE"
	elif lock_female:
		_gender_constraint_label.text = "  Job is gender-locked to FEMALE"
	else:
		_gender_constraint_label.text = ""


# -----------------------------------------------------------------------------
# Panel-driven changes (route through Unit's semantic methods — ADR-0024)
# -----------------------------------------------------------------------------

func _on_facing_picked(idx: int) -> void:
	_unit.facing_direction = idx as FacingDirection
	_render_readout()


func _apply_activity_if_ability_driven() -> void:
	var name: String = ACTIVITY_NAMES[_activity_dropdown.selected]
	if name in ["SPELL_CASTING", "SPELL_CHARGING"]:
		_apply_activity()


func _on_auto_loop_toggled(pressed: bool) -> void:
	if not is_instance_valid(_unit):
		return
	# A unit's body animation ends in one of two ways:
	#   - activity_complete: true completion (no hold/pause opcode at end)
	#   - animation_paused:          PauseAnimation opcode hit (hold-forever pose,
	#                                what ATTACKING / most one-shots do)
	# Auto-loop has to react to BOTH, otherwise hold-pose animations never
	# re-fire. Looping activities (IDLE, WALKING) emit neither, so the toggle
	# is a no-op for those — exactly what you'd want.
	if pressed:
		if not _unit.activity_complete.is_connected(_on_unit_activity_complete):
			_unit.activity_complete.connect(_on_unit_activity_complete)
		if not _unit.animation_paused.is_connected(_on_unit_activity_paused):
			_unit.animation_paused.connect(_on_unit_activity_paused)
	else:
		if _unit.activity_complete.is_connected(_on_unit_activity_complete):
			_unit.activity_complete.disconnect(_on_unit_activity_complete)
		if _unit.animation_paused.is_connected(_on_unit_activity_paused):
			_unit.animation_paused.disconnect(_on_unit_activity_paused)


func _on_unit_activity_complete(_completed_state) -> void:
	if _auto_loop_toggle and _auto_loop_toggle.button_pressed:
		_apply_activity()


func _on_unit_activity_paused(_anim_id: String) -> void:
	if _auto_loop_toggle and _auto_loop_toggle.button_pressed:
		_apply_activity()


## Returns the "where do I edit this routing?" hint shown in the readout.
## state_animations rows live in map.tres (Inspector-editable). Weapon-driven
## attacks live in ROM-derived JSON. Ability-driven casts/charges live in
## AbilityDatabase (effect_anim_id field). React overlays aren't in the
## resolution map at all.
const _PARAMETERLESS_ACTIVITIES := [
	"IDLE", "IDLE_LOW_HEALTH", "WALKING", "JUMPING", "LANDING",
	"USING_ITEM", "DYING", "DEAD", "GETTING_UP",
	"CELEBRATING", "AWAITING_IMPACT",
]


func _authoring_address(activity_name: String, sprite_type: String) -> String:
	var st := sprite_type.to_lower()
	if activity_name in _PARAMETERLESS_ACTIVITIES:
		return "map.tres → %s → states[%s]" % [st, activity_name]
	if activity_name == "ATTACKING":
		return "weapon_animation_ids.json (ROM-derived; not Inspector-editable) — humanoid BODY base; WeaponAnimationSelector.gd code constants for WEP1 base"
	if activity_name in ["SPELL_CASTING", "SPELL_CHARGING"]:
		return "AbilityDatabase.effect_anim_id (per-ability lookup), falling back to map.tres → %s → states[%s]" % [st, activity_name]
	return "(unmapped activity)"


## Called by ResourceHotReload after it swaps in a freshly-loaded map.tres.
## Re-fires the current activity so the BODY layer repaints with the new
## routing rows, and re-renders the readout so the address line and source
## verdict reflect the new data.
func on_resource_reloaded() -> void:
	if not is_instance_valid(_unit):
		return
	_apply_activity()


func _apply_activity() -> void:
	if not is_instance_valid(_unit):
		return
	var name: String = ACTIVITY_NAMES[_activity_dropdown.selected]
	var ability_id: int = int(_ability_spin.value)
	var vertical: int = _vertical_dropdown.selected
	match name:
		"ATTACKING":
			_unit.attack(vertical)
		"SPELL_CASTING":
			_unit.cast_spell(ability_id)
		"SPELL_CHARGING":
			_unit.charge_ability(ability_id)
		_:
			_unit.last_resolution = null
			_unit.activity = DisplayActivity.Activity.get(name)
	_render_readout()


# -----------------------------------------------------------------------------
# Sync + readout
# -----------------------------------------------------------------------------

func _sync_from_unit() -> void:
	if not is_instance_valid(_unit):
		return
	if _unit.unit_progression:
		# Apply-on-boot (ADR-0068): the AUTOSAVE job dropdown is populated at runtime, so
		# late-select the persisted job key and, if it's still a real job, APPLY it to the
		# unit (resume previewing that sprite) rather than only pre-selecting the name. No
		# persisted/stale key → fall back to mirroring the unit's own current job.
		var job_key: Variant = TuneField.resync_dropdown(_job_dropdown, "anim_viewer.job", "")
		var persisted_idx := _job_ids.find(str(job_key))
		if persisted_idx >= 0:
			_on_job_picked(persisted_idx)  # drives change_job + gender sync + readout
		else:
			var job_idx := _job_ids.find(_unit.unit_progression.current_job_id)
			if job_idx >= 0:
				_job_dropdown.selected = job_idx
			_sync_gender_buttons_from_unit()
	# Facing is AUTOSAVE too: drive the unit FROM the persisted dropdown (coalesced at
	# build), not the other way, so a remembered facing applies on boot.
	_on_facing_picked(_facing_dropdown.selected)
	_refresh_ability_label()
	_apply_activity()


func _refresh_ability_label() -> void:
	if not _ability_name_label:
		return
	var ab := AbilityDatabase.get_ability_view(int(_ability_spin.value))
	if ab.is_empty():
		_ability_name_label.text = "  (no ability at this id)"
		return
	_ability_name_label.text = "  %s   effect_anim_id=%d → slot %d" % [ab.name, ab.effect_anim_id, ab.effect_anim_id * 2]


func _render_readout() -> void:
	if not is_instance_valid(_unit) or not _readout:
		return
	var lines: Array[String] = []
	var prog := _unit.unit_progression
	var job_id: String = prog.current_job_id if prog else "?"
	var job_data: Dictionary = JobDatabase.get_job(job_id)
	var job_name: String = String(job_data.get("name", "?"))
	var is_female: bool = prog and prog.base_stat_type == UnitProgression.BaseStatType.FEMALE
	var sprite_id: int = _unit.body_sprite_id
	var sprite_name: String = JobDatabase.get_sprite_name(sprite_id)
	var r_id: int = prog.get_equipped_item(UnitProgression.EquipSlot.RIGHT_HAND) if prog else -1
	var l_id: int = prog.get_equipped_item(UnitProgression.EquipSlot.LEFT_HAND) if prog else -1
	var r_name: String = ItemDatabase.get_item_name(r_id) if r_id >= 0 else "(none)"
	var l_name: String = ItemDatabase.get_item_name(l_id) if l_id >= 0 else "(none)"

	# Unit-state mirror — read-only here; the production CombatUI is what changes these.
	lines.append("[b]Job[/b]:         0x%s — %s   (%s)" % [job_id.to_upper(), job_name, "FEMALE" if is_female else "MALE"])
	lines.append("[b]Sprite[/b]:      0x%02X (%s)   palette_row=%d" % [sprite_id, sprite_name, _unit.body_palette_row])
	lines.append("[b]Sprite type[/b]: %s (shp) / %s (seq)" % [_unit.get_shp_type(), _unit.get_seq_type()])
	lines.append("[b]R-Hand[/b]:      %s   L-Hand: %s" % [r_name, l_name])
	lines.append("[b]Facing[/b]:      %s" % FACING_LABELS[_unit.facing_direction])
	var activity_name: String = ACTIVITY_NAMES[_activity_dropdown.selected]
	lines.append("[b]Activity[/b]:    %s" % activity_name)
	lines.append("")

	var r = _unit.last_resolution
	if r == null:
		lines.append("[color=gray][i]No resolution recorded yet — pick an activity to drive one.[/i][/color]")
		_readout.text = "\n".join(lines)
		return

	var source_color := "lime" if r.source == "atlas" else "red"
	lines.append("[color=%s][b]Source: %s[/b][/color]" % [source_color, r.source.to_upper()])
	lines.append("[color=lightgray][b]Authoring[/b]: %s[/color]" % _authoring_address(activity_name, _unit.get_seq_type()))
	lines.append("[i]%s[/i]" % r.note)
	lines.append("")
	var body_type: String = _unit.get_seq_type()
	lines.append("[b]BODY slot[/b]: %s" % AnimationNames.format(body_type, r.body_slot))
	lines.append("[b]WEP1 slot[/b]: %s" % AnimationNames.format("wep1", r.wep1_slot))
	lines.append("[b]EFF1 slot[/b]: %s" % AnimationNames.format("eff1", r.eff1_slot))
	_readout.text = "\n".join(lines)
