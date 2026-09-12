extends Node
## Guard for TuneField — the ONE builder for a tunable debug-panel row (ADR-0068):
## label + type-inferred control + Tune wiring + right-click Pin/Reset menu +
## typographic markers, used by BOTH the generated dashboard AND bespoke panels so
## there is one implementation and no drift. Built in a bare tree (no masonry /
## DebugOverlay / roster) so it dodges the GPUArena native crash.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TuneFieldTest.tscn

const TuneField = preload("res://src/debug/TuneField.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_builds_and_returns_the_control()
	_test_tunable_label_carries_the_accent_color()
	_test_editing_the_control_reaches_tune()
	_test_external_change_resyncs_the_control()
	_test_dirty_marker_toggles_in_a_reserved_slot()
	_test_context_menu_offers_pin_and_reset()
	_test_context_pin_commits_only_the_slug_and_clears_the_marker()
	_test_context_reset_clears_the_override()
	_test_inference_covers_enum_bool_and_string()
	_test_autosave_label_carries_the_green_accent()
	_test_autosave_mode_is_a_slug_property_declared_at_registration()
	_test_autosave_edit_persists_immediately()
	_test_plain_edit_stays_dirty_until_pinned()
	_test_autosave_menu_drops_pin()
	_test_autosave_reset_unpersists_the_slug()
	_test_ephemeral_label_carries_the_grey_accent()
	_test_ephemeral_edit_is_session_only_never_on_disk()
	_test_ephemeral_never_shows_dirty_marker()
	_test_ephemeral_menu_is_reset_only()
	_test_strongest_declared_persistence_wins()
	_test_add_dropdown_builds_an_empty_option_button()
	_test_dropdown_selection_persists_the_key()
	_test_dropdown_resync_selects_the_persisted_key_after_populate()
	_test_dropdown_resync_leaves_selection_when_key_absent()
	_test_vector2_builds_editable_per_component_spinboxes()
	_test_vector_components_suppress_the_builtin_context_menu()
	_test_view_row_reads_the_registry_when_default_omitted()
	_test_view_row_inherits_the_registered_persistence_accent()

	print("\n=== TuneFieldTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TuneFieldTest")
		get_tree().quit(1)
	else:
		print("[PASS] TuneFieldTest")
		get_tree().quit(0)


## Tracer bullet: adding a float tunable builds a SpinBox parented under the host
## and hands it back so callers can tweak it.
func _test_builds_and_returns_the_control() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var control: Control = TuneField.add(host, "PSX PAR", "render.pixel_aspect", 1.25,
		{"min": 0.5, "max": 2.0, "step": 0.01})
	_assert_true(control is SpinBox, "a float tunable builds a SpinBox")
	_assert_true(control != null and host.is_ancestor_of(control),
		"the control is parented under the host")
	if control is SpinBox:
		_assert_approx(control.value, 1.25, "the spinbox shows the coalesced value")
	host.queue_free()


## A tunable's label is drawn in the accent color — the at-a-glance "pinnable"
## signal (typographic, not an icon).
func _test_tunable_label_carries_the_accent_color() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "PSX PAR", "render.pixel_aspect", 1.25, {})
	var label: Label = _first_of(host, "Label")
	_assert_true(label != null, "the row has a label")
	if label:
		_assert_true(label.get_theme_color("font_color") == TuneField.TUNABLE_ACCENT,
			"the tunable label carries the accent color")
	host.queue_free()


## The write path: moving the control pushes the value through to Tune, so the
## coalesced read reflects the scrub (the loop the field exists to drive).
func _test_editing_the_control_reaches_tune() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var sb: SpinBox = TuneField.add(host, "PSX PAR", "render.pixel_aspect", 1.25,
		{"min": 0.5, "max": 2.0, "step": 0.01})
	sb.value = 1.5  # emits value_changed -> the wired Tune.set_value
	_assert_approx(float(Tune.bind("render.pixel_aspect", 1.25)), 1.5,
		"scrubbing the control writes through to Tune")
	host.queue_free()


## Two-way: a change to the slug from ELSEWHERE (another panel, a boot-load)
## resyncs this control's shown value without the caller doing anything.
func _test_external_change_resyncs_the_control() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var sb: SpinBox = TuneField.add(host, "PSX PAR", "render.pixel_aspect", 1.25,
		{"min": 0.5, "max": 2.0, "step": 0.01})
	Tune.set_value("render.pixel_aspect", 1.75)  # someone else scrubs the same slug
	_assert_approx(sb.value, 1.75, "the control resyncs to an external change")
	host.queue_free()


## The dirty cue lives in a RESERVED trailing slot (a fixed-width marker label),
## not the name label — so the name never changes and the reserved width means the
## control never shifts as the marker toggles.
func _test_dirty_marker_toggles_in_a_reserved_slot() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "PSX PAR", "render.pixel_aspect", 1.25,
		{"min": 0.5, "max": 2.0, "step": 0.01})
	var labels := _all_of(host, "Label")
	var name_label: Label = labels[0]
	var marker: Label = labels[1]
	_assert_eq(name_label.text, "PSX PAR", "the name label is constant (marker is a separate slot)")
	_assert_true(marker.custom_minimum_size.x > 0.0,
		"the marker slot reserves width so the control never shifts")
	_assert_eq(marker.text, "", "clean field shows no marker")
	Tune.set_value("render.pixel_aspect", 1.5)
	_assert_eq(marker.text, " *", "dirty field shows ' *' in the reserved slot")
	Tune.clear("render.pixel_aspect")
	_assert_eq(marker.text, "", "clearing the override drops the marker")
	host.queue_free()


## The right-click menu is the per-field affordance: Pin + Reset, with Pin disabled
## until the field is dirty (nothing to persist).
func _test_context_menu_offers_pin_and_reset() -> void:
	Tune.reset()
	Tune.bind("render.pixel_aspect", 1.25, {})
	var menu: PopupMenu = TuneField._build_context_menu("render.pixel_aspect")
	_assert_eq(menu.item_count, 2, "context menu offers Pin + Reset")
	_assert_true(menu.is_item_disabled(menu.get_item_index(TuneField.Action.PIN)),
		"Pin is disabled while the field is clean")
	Tune.set_value("render.pixel_aspect", 1.5)  # dirty
	var menu2: PopupMenu = TuneField._build_context_menu("render.pixel_aspect")
	_assert_true(not menu2.is_item_disabled(menu2.get_item_index(TuneField.Action.PIN)),
		"Pin enables once the field is dirty")
	menu.queue_free()
	menu2.queue_free()


## Pin commits just that slug (per-field, not blanket) and fires the on-changed hook
## so the row can drop its dirty marker. A temp path keeps the real staging file out.
func _test_context_pin_commits_only_the_slug_and_clears_the_marker() -> void:
	Tune.reset()
	Tune.bind("render.pixel_aspect", 1.25, {})
	Tune.set_value("render.pixel_aspect", 1.5)
	_assert_true(Tune.is_dirty("render.pixel_aspect"), "the scrubbed slug is dirty")
	var refreshed := [false]
	TuneField._context_action("render.pixel_aspect", TuneField.Action.PIN,
		func() -> void: refreshed[0] = true, "user://tune_field_pin.json")
	_assert_true(not Tune.is_dirty("render.pixel_aspect"), "pinning commits the slug")
	_assert_true(refreshed[0], "pinning fires the on-changed hook (marker refresh)")


## Reset clears the override back to the code default.
func _test_context_reset_clears_the_override() -> void:
	Tune.reset()
	Tune.bind("render.pixel_aspect", 1.25, {})
	Tune.set_value("render.pixel_aspect", 1.5)
	TuneField._context_action("render.pixel_aspect", TuneField.Action.RESET)
	_assert_approx(float(Tune.bind("render.pixel_aspect", 1.25)), 1.25,
		"reset clears the override back to the default")


## Control inference (ADR-0068 decision 11) through the builder: an enum hint -> a
## dropdown, a bool -> a toggle, a String -> free text.
func _test_inference_covers_enum_bool_and_string() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var ob: Control = TuneField.add(host, "AI", "combat.ai_mode", 1,
		{"enum": {"Aggressive": 0, "Defensive": 1, "Passive": 2}})
	_assert_true(ob is OptionButton, "an enum tunable builds an OptionButton")
	if ob is OptionButton:
		_assert_eq(ob.get_item_metadata(ob.selected), 1, "the current enum value is selected")
	var cb: Control = TuneField.add(host, "Grid", "debug.show_grid", true, {})
	_assert_true(cb is CheckBox, "a bool tunable builds a CheckBox")
	var le: Control = TuneField.add(host, "Watch", "debug.watch_expr", "hp > 0", {})
	_assert_true(le is LineEdit, "a String tunable builds a LineEdit")
	host.queue_free()


## An auto-persist slug's label is drawn in the Catppuccin green accent — the third
## persistence class, visually distinct from a cyan tunable (Pin-to-keep) and white
## ephemera. The mode is declared right on the add() call.
func _test_autosave_label_carries_the_green_accent() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "Grid X", "effect_viewer.caster_x", 4, {}, Tune.Persist.AUTOSAVE)
	var label: Label = _first_of(host, "Label")
	_assert_true(label != null and label.get_theme_color("font_color") == TuneField.AUTOSAVE_ACCENT,
		"an auto-persist label carries the green accent")
	host.queue_free()


## The mode is a property of the SLUG (ADR-0068 decision 12), declared at any
## registration use-site and monotonic: a code owner declaring AUTOSAVE upgrades the
## slug even though the panel's later add() passes the default, so the two need not
## run in any fixed order and the panel still renders green.
func _test_autosave_mode_is_a_slug_property_declared_at_registration() -> void:
	Tune.reset()
	Tune.bind("effect_viewer.caster_x", 4, {}, Tune.Persist.AUTOSAVE)  # code owner declares
	_assert_eq(Tune.persist_of("effect_viewer.caster_x"), Tune.Persist.AUTOSAVE,
		"bind() records the slug's persistence mode")
	var host := VBoxContainer.new()
	add_child(host)
	# The panel omits the mode (default TUNABLE) — monotonic upgrade must keep AUTOSAVE.
	TuneField.add(host, "Grid X", "effect_viewer.caster_x", 4, {})
	var label: Label = _first_of(host, "Label")
	_assert_true(label != null and label.get_theme_color("font_color") == TuneField.AUTOSAVE_ACCENT,
		"the panel reflects the owner-declared mode regardless of call order")
	host.queue_free()


## The auto-persist contract: one edit both scrubs and commits to the staging file —
## no dirty state, no Pin. A reload from the file shows the edited value.
func _test_autosave_edit_persists_immediately() -> void:
	Tune.reset()
	var path := "user://tune_field_autosave.json"
	_rm(path)
	var host := VBoxContainer.new()
	add_child(host)
	var sb: SpinBox = TuneField.add(host, "Grid X", "effect_viewer.caster_x", 4,
		{"min": 0, "max": 20, "step": 1}, Tune.Persist.AUTOSAVE, path)
	sb.value = 9  # one gesture: set_value + commit_slug
	_assert_true(not Tune.is_dirty("effect_viewer.caster_x"),
		"an auto-persist edit commits immediately (never dirty)")
	Tune.reset()
	Tune.load_overrides(path)
	_assert_eq(int(Tune.bind("effect_viewer.caster_x", 4)), 9,
		"the auto-persisted value survives a reload from the staging file")
	host.queue_free()
	_rm(path)


## Contrast: a plain (tunable) edit does NOT auto-persist — it stays dirty until a
## deliberate Pin. This is exactly the behavior auto-persist departs from.
func _test_plain_edit_stays_dirty_until_pinned() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var sb: SpinBox = TuneField.add(host, "Grid X", "effect_viewer.caster_x", 4,
		{"min": 0, "max": 20, "step": 1})  # default = TUNABLE
	sb.value = 9
	_assert_true(Tune.is_dirty("effect_viewer.caster_x"),
		"a plain tunable edit stays dirty until pinned")
	host.queue_free()


## The auto-persist menu drops Pin (every edit already persisted) and keeps Reset.
func _test_autosave_menu_drops_pin() -> void:
	Tune.reset()
	Tune.bind("effect_viewer.caster_x", 4, {}, Tune.Persist.AUTOSAVE)
	var menu: PopupMenu = TuneField._build_context_menu("effect_viewer.caster_x",
		Callable(), Tune.Persist.AUTOSAVE)
	_assert_eq(menu.item_count, 1, "an auto-persist menu offers only Reset (no Pin)")
	_assert_eq(menu.get_item_id(0), TuneField.Action.RESET, "the sole item is Reset")
	menu.queue_free()


## Reset on an auto-persist field also UN-persists: the slug drops out of the file. A
## sibling auto-persist slug proves the removal was WRITTEN, not just a missing file.
func _test_autosave_reset_unpersists_the_slug() -> void:
	Tune.reset()
	var path := "user://tune_field_autosave.json"
	_rm(path)
	Tune.bind("effect_viewer.caster_x", 4, {}, Tune.Persist.AUTOSAVE)
	Tune.bind("effect_viewer.caster_z", 6, {}, Tune.Persist.AUTOSAVE)
	TuneField._write("effect_viewer.caster_x", 9, Tune.Persist.AUTOSAVE, path)
	TuneField._write("effect_viewer.caster_z", 7, Tune.Persist.AUTOSAVE, path)
	TuneField._context_action("effect_viewer.caster_x", TuneField.Action.RESET,
		Callable(), path, Tune.Persist.AUTOSAVE)
	Tune.reset()
	Tune.load_overrides(path)
	_assert_eq(int(Tune.bind("effect_viewer.caster_x", 4)), 4,
		"reset un-persists the slug (drops from the file)")
	_assert_eq(int(Tune.bind("effect_viewer.caster_z", 6)), 7,
		"a sibling auto-persist slug is untouched")
	_rm(path)


## An ephemeral slug's label is drawn in the grey accent — the "declared session-only"
## class, distinct from cyan tunable and green auto-persist.
func _test_ephemeral_label_carries_the_grey_accent() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "Preview", "effect_viewer.preview_id", 5, {}, Tune.Persist.EPHEMERAL)
	var label: Label = _first_of(host, "Label")
	_assert_true(label != null and label.get_theme_color("font_color") == TuneField.EPHEMERAL_ACCENT,
		"an ephemeral label carries the grey accent")
	host.queue_free()


## The ephemeral contract: an edit is live for the session but NEVER reaches disk, so it
## resets to the code default on reload — even through a full save. An AUTOSAVE sibling
## built the same way proves the exclusion is per-class, not a broken write.
func _test_ephemeral_edit_is_session_only_never_on_disk() -> void:
	Tune.reset()
	var path := "user://tune_field_ephemeral.json"
	_rm(path)
	var host := VBoxContainer.new()
	add_child(host)
	var eph: SpinBox = TuneField.add(host, "Preview", "effect_viewer.preview_id", 5,
		{"min": 0, "max": 99, "step": 1}, Tune.Persist.EPHEMERAL, path)
	var keep: SpinBox = TuneField.add(host, "Grid X", "effect_viewer.caster_x", 4,
		{"min": 0, "max": 99, "step": 1}, Tune.Persist.AUTOSAVE, path)
	eph.value = 9   # session-only edit
	keep.value = 7  # auto-persisted edit
	_assert_eq(int(Tune.bind("effect_viewer.preview_id", 5)), 9,
		"an ephemeral edit is live for the session")
	Tune.save_overrides(path)  # persist everything eligible
	Tune.reset()
	Tune.load_overrides(path)
	_assert_eq(int(Tune.bind("effect_viewer.preview_id", 5)), 5,
		"an ephemeral value never reaches disk — resets to default on reload")
	_assert_eq(int(Tune.bind("effect_viewer.caster_x", 4)), 7,
		"an autosave sibling built the same way DOES persist")
	host.queue_free()
	_rm(path)


## An ephemeral field never carries the dirty " *" — it has no "unsaved" state (it is
## never saved), so the marker slot stays blank even after an edit.
func _test_ephemeral_never_shows_dirty_marker() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "Preview", "effect_viewer.preview_id", 5,
		{"min": 0, "max": 99, "step": 1}, Tune.Persist.EPHEMERAL)
	var marker: Label = _all_of(host, "Label")[1]
	Tune.set_value("effect_viewer.preview_id", 9)  # would be "dirty" for a tunable
	_assert_eq(marker.text, "", "an ephemeral field never shows the dirty marker")
	host.queue_free()


## The ephemeral menu is Reset-only — nothing to Pin (it is never persisted).
func _test_ephemeral_menu_is_reset_only() -> void:
	Tune.reset()
	Tune.bind("effect_viewer.preview_id", 5, {}, Tune.Persist.EPHEMERAL)
	var menu: PopupMenu = TuneField._build_context_menu("effect_viewer.preview_id",
		Callable(), Tune.Persist.EPHEMERAL)
	_assert_eq(menu.item_count, 1, "an ephemeral menu offers only Reset (no Pin)")
	_assert_eq(menu.get_item_id(0), TuneField.Action.RESET, "the sole item is Reset")
	menu.queue_free()


## The persistence class is resolved by STRENGTH (EPHEMERAL < TUNABLE < AUTOSAVE), not
## call order: an undeclared slug rests at TUNABLE, a plain read never changes a declared
## class, a stronger class upgrades, and a weaker one never downgrades.
func _test_strongest_declared_persistence_wins() -> void:
	Tune.reset()
	Tune.bind("x.fresh", 1.0)
	_assert_eq(Tune.persist_of("x.fresh"), Tune.Persist.TUNABLE,
		"an undeclared slug rests at TUNABLE")
	Tune.bind("x.eph", 1.0, {}, Tune.Persist.EPHEMERAL)
	Tune.bind("x.eph", 1.0)  # plain read — no class
	_assert_eq(Tune.persist_of("x.eph"), Tune.Persist.EPHEMERAL,
		"a plain read never upgrades an ephemeral slug")
	Tune.bind("x.eph", 1.0, {}, Tune.Persist.AUTOSAVE)
	_assert_eq(Tune.persist_of("x.eph"), Tune.Persist.AUTOSAVE,
		"a stronger class (AUTOSAVE) upgrades the slug regardless of order")
	Tune.bind("x.eph", 1.0, {}, Tune.Persist.EPHEMERAL)
	_assert_eq(Tune.persist_of("x.eph"), Tune.Persist.AUTOSAVE,
		"a weaker class never downgrades a stronger one")


## A dynamic dropdown (DB-populated at runtime) can't use the enum path — its label→value
## map isn't known upfront. add_dropdown builds an EMPTY OptionButton the caller populates
## later, wired to a string-keyed slug. The tracer: it returns an empty OptionButton parented
## under the host, with the persistence-class accent on the label.
func _test_add_dropdown_builds_an_empty_option_button() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var ob: OptionButton = TuneField.add_dropdown(host, "Effect", "effect_viewer.effect",
		"", Tune.Persist.AUTOSAVE)
	_assert_true(ob is OptionButton and host.is_ancestor_of(ob),
		"add_dropdown returns an OptionButton parented under the host")
	_assert_eq(ob.item_count, 0, "the dropdown starts empty — the caller populates it later")
	var label: Label = _first_of(host, "Label")
	_assert_true(label != null and label.get_theme_color("font_color") == TuneField.AUTOSAVE_ACCENT,
		"the dropdown label carries the persistence-class accent")
	host.queue_free()


## Selecting a dynamic-dropdown item writes its stable KEY (not the row index) to the slug,
## and an AUTOSAVE dropdown commits it in the same gesture, so the choice survives a reload.
func _test_dropdown_selection_persists_the_key() -> void:
	Tune.reset()
	var path := "user://tune_field_dropdown.json"
	_rm(path)
	var host := VBoxContainer.new()
	add_child(host)
	var ob: OptionButton = TuneField.add_dropdown(host, "Effect", "effect_viewer.effect",
		"", Tune.Persist.AUTOSAVE, path)
	# Caller populates at runtime, stashing a stable key per item (here an int effect id).
	ob.add_item("Fire")
	ob.set_item_metadata(0, 20)
	ob.add_item("Holy")
	ob.set_item_metadata(1, 15)
	ob.select(1)
	ob.item_selected.emit(1)  # the gesture the OptionButton fires on a user pick
	_assert_eq(str(Tune.bind("effect_viewer.effect", "")), "15",
		"selecting an item writes its stable key to the slug")
	Tune.reset()
	Tune.load_overrides(path)
	_assert_eq(str(Tune.bind("effect_viewer.effect", "")), "15",
		"an AUTOSAVE dropdown selection survives a reload from disk")
	host.queue_free()
	_rm(path)


## The items don't exist at build time (populated at runtime), so after populating the
## caller calls resync_dropdown to select the item whose key matches the persisted slug —
## the "late assignment". It also RETURNS the resolved key so the caller can run its own
## load side-effect for the restored selection.
func _test_dropdown_resync_selects_the_persisted_key_after_populate() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	Tune.set_value("effect_viewer.effect", "15")  # a previously-persisted selection
	var ob: OptionButton = TuneField.add_dropdown(host, "Effect", "effect_viewer.effect",
		"", Tune.Persist.AUTOSAVE)
	# Populate AFTER build (runtime DB), then late-assign the persisted selection.
	ob.add_item("Fire"); ob.set_item_metadata(0, 20)
	ob.add_item("Holy"); ob.set_item_metadata(1, 15)
	var key: Variant = TuneField.resync_dropdown(ob, "effect_viewer.effect", "")
	_assert_eq(ob.selected, 1, "resync selects the item whose key matches the persisted slug")
	_assert_eq(str(key), "15", "resync returns the resolved key for the caller's load side-effect")
	host.queue_free()


## Restore must be resilient: only re-select if the persisted key is still in the list (the
## user's rule — "only if it's in the list"). A stale key (the DB changed) leaves the caller's
## current selection untouched rather than blanking it, and still returns the persisted value.
func _test_dropdown_resync_leaves_selection_when_key_absent() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	Tune.set_value("effect_viewer.effect", "999")  # a key no longer in the DB
	var ob: OptionButton = TuneField.add_dropdown(host, "Effect", "effect_viewer.effect",
		"", Tune.Persist.AUTOSAVE)
	ob.add_item("Fire"); ob.set_item_metadata(0, 20)
	ob.add_item("Holy"); ob.set_item_metadata(1, 15)
	ob.select(1)  # caller's default pick
	var key: Variant = TuneField.resync_dropdown(ob, "effect_viewer.effect", "")
	_assert_eq(ob.selected, 1, "a stale persisted key leaves the current selection untouched")
	_assert_eq(str(key), "999", "resync still returns the persisted value even when absent")
	host.queue_free()


## Delete a test staging file if present (test isolation — never touch the real one).
func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A Vector2 tunable (the collapsed render.loc_offset, ADR-0068 R6 / decision 11) builds
## two per-component SpinBoxes: each shows its component of the coalesced value, editing one
## writes the whole Vector2 back to Tune, and an external Vector2 change resyncs both.
func _test_vector2_builds_editable_per_component_spinboxes() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var control: Control = TuneField.add(host, "loc_offset", "render.loc_offset",
		Vector2(27.0, 26.0), {"min": -128.0, "max": 128.0, "step": 1.0})
	var sbs := _all_of(control, "SpinBox") if control else []
	_assert_eq(sbs.size(), 2, "a Vector2 tunable builds two component spinboxes")
	if sbs.size() == 2:
		_assert_approx(sbs[0].value, 27.0, "the x spinbox shows the coalesced x")
		_assert_approx(sbs[1].value, 26.0, "the y spinbox shows the coalesced y")
		sbs[1].value = 30.0  # scrub the y component
		var got: Variant = Tune.bind("render.loc_offset", Vector2(27.0, 26.0))
		_assert_true(got is Vector2 and is_equal_approx(got.x, 27.0) and is_equal_approx(got.y, 30.0),
			"scrubbing the y component writes the whole Vector2(x, y) through to Tune")
		Tune.set_value("render.loc_offset", Vector2(5.0, 6.0))  # external change
		_assert_approx(sbs[0].value, 5.0, "the x spinbox resyncs to an external change")
		_assert_approx(sbs[1].value, 6.0, "the y spinbox resyncs to an external change")
	host.queue_free()


## Each component of a Vector2 gets our Pin/Reset menu wired — the fix for the bug where
## right-clicking loc_offset(x,y) popped Godot's built-in LineEdit menu instead. The gesture
## itself isn't headless-testable, but the tell-tale is structural: _attach_context_menu must
## reach INTO the HBox and suppress each component LineEdit's default menu (else it leaks
## through and consumes the click before ours). A scalar's lone menu stays suppressed too.
func _test_vector_components_suppress_the_builtin_context_menu() -> void:
	Tune.reset()
	var host := VBoxContainer.new()
	add_child(host)
	var control: Control = TuneField.add(host, "loc_offset", "render.loc_offset",
		Vector2(27.0, 26.0), {"min": -128.0, "max": 128.0, "step": 1.0})
	var sbs := _all_of(control, "SpinBox") if control else []
	_assert_eq(sbs.size(), 2, "a Vector2 tunable builds two component spinboxes")
	for sb: SpinBox in sbs:
		_assert_true(not sb.get_line_edit().context_menu_enabled,
			"each vector component's built-in LineEdit menu is suppressed so ours wins")
	host.queue_free()


## A panel is a VIEW (ADR-0068 decision 12 / R5): with the default omitted, the row reads
## the slug's registered literal + hint from the registry (the OWNER's bind supplies them),
## so it builds the right control without the panel carrying a rival copy of the value.
func _test_view_row_reads_the_registry_when_default_omitted() -> void:
	Tune.reset()
	# The owner registers the slug (pure bind = literal + hint), as Unit/PSXDisplay do at boot.
	Tune.bind("render.loc_offset", Vector2(27.0, 26.0), {"min": -128.0, "max": 128.0, "step": 1.0})
	var host := VBoxContainer.new()
	add_child(host)
	var control: Control = TuneField.add(host, "loc_offset", "render.loc_offset")  # no default
	var sbs := _all_of(control, "SpinBox") if control else []
	_assert_eq(sbs.size(), 2, "a view row infers the Vector2 control from the registered literal")
	if sbs.size() == 2:
		_assert_approx(sbs[0].value, 27.0, "the view row shows the registered x")
		_assert_approx(sbs[1].value, 26.0, "the view row shows the registered y")
	host.queue_free()


## A view row derives its persistence accent from the registry too, so a slug the owner
## declared AUTOSAVE shows green even though the panel passed no persist class.
func _test_view_row_inherits_the_registered_persistence_accent() -> void:
	Tune.reset()
	Tune.bind("dbg.flag", false, {}, Tune.Persist.AUTOSAVE)  # owner declares AUTOSAVE
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "flag", "dbg.flag")  # view row, no default/persist
	var label: Label = _first_of(host, "Label")
	_assert_true(label != null and label.get_theme_color("font_color") == TuneField.AUTOSAVE_ACCENT,
		"a view row's label carries the registered persistence accent, not a forced TUNABLE")
	host.queue_free()


func _first_of(root: Node, cls: String) -> Node:
	for child in root.get_children():
		if child.is_class(cls):
			return child
		var found := _first_of(child, cls)
		if found:
			return found
	return null


## Every descendant whose class is `cls` (depth-first order).
func _all_of(root: Node, cls: String) -> Array:
	var out: Array = []
	for child in root.get_children():
		if child.is_class(cls):
			out.append(child)
		out.append_array(_all_of(child, cls))
	return out


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%.4f, got %.4f" % [label, expected, actual])
