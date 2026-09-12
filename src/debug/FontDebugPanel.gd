class_name FontDebugPanel
extends BaseDebugPanel
## Debug panel for font palette settings.
##
## Three independent palette sections (Menu, Stat, Disabled) that each only affect
## UIChars using that palette. Every row is a shared TuneField bound to a `font.*` slug
## (ADR-0068 move 2): UIChar OWNS these values — it reads them via Tune.of at its
## set_palette use-site — so a committed override coalesces onto every char in any scene
## (and after a reload), and this panel is just a VIEW (decision 12). The panel drives a
## live RE-APPLY on scrub via one Tune.value_changed listener (a view refresh of the
## already-drawn chars; the value itself is Tune-owned, not panel-owned). Defaults come
## from the UIChar.* statics (the single default home) — the panel never writes them.

const TuneField = preload("res://src/debug/TuneField.gd")

# slug-prefix → palette, so a font.* scrub re-applies the right palette to live chars.
const _PREFIX_TO_PALETTE := {
	"font.menu_": UIChar.FontPalette.MENU,
	"font.stat_": UIChar.FontPalette.STAT,
	"font.disabled_": UIChar.FontPalette.DISABLED,
}

var _scene_root: Node


func setup(scene_root: Node) -> void:
	_scene_root = scene_root
	panel_title = "Font"
	panel_category = Category.FONT
	_build_ui()
	# One listener refreshes the on-screen chars when any font.* slug is scrubbed —
	# the values are owned by UIChar/Tune; this only re-applies them to live nodes.
	Tune.value_changed.connect(_on_tune_changed)
	tree_exited.connect(func() -> void:
		if Tune.value_changed.is_connected(_on_tune_changed):
			Tune.value_changed.disconnect(_on_tune_changed))


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(280, 0)
	add_child(main_vbox)

	var menu_section = create_collapsible_section(main_vbox, "Menu Palette", false)
	TuneField.add(menu_section, "Use palette", "font.menu_use_palette", UIChar.MENU_USE_PALETTE)
	TuneField.add(menu_section, "Dark:", "font.menu_dark", UIChar.MENU_DARK)
	TuneField.add(menu_section, "Mid:", "font.menu_mid", UIChar.MENU_MID)
	TuneField.add(menu_section, "Light:", "font.menu_light", UIChar.MENU_LIGHT)
	TuneField.add(menu_section, "Stroke", "font.menu_stroke_enabled", UIChar.MENU_STROKE_ENABLED)
	TuneField.add(menu_section, "Stroke color:", "font.menu_stroke", UIChar.MENU_STROKE)
	_add_reset_button(menu_section, "font.menu_")

	add_separator(main_vbox)
	var stat_section = create_collapsible_section(main_vbox, "Stat Palette", true)
	TuneField.add(stat_section, "Dark:", "font.stat_dark", UIChar.STAT_DARK)
	TuneField.add(stat_section, "Mid:", "font.stat_mid", UIChar.STAT_MID)
	TuneField.add(stat_section, "Light:", "font.stat_light", UIChar.STAT_LIGHT)
	TuneField.add(stat_section, "Stroke", "font.stat_stroke_enabled", UIChar.STAT_STROKE_ENABLED)
	TuneField.add(stat_section, "Stroke color:", "font.stat_stroke", UIChar.STAT_STROKE)
	_add_reset_button(stat_section, "font.stat_")

	add_separator(main_vbox)
	var disabled_section = create_collapsible_section(main_vbox, "Disabled Palette", true)
	TuneField.add(disabled_section, "Dark:", "font.disabled_dark", UIChar.DISABLED_DARK)
	TuneField.add(disabled_section, "Mid:", "font.disabled_mid", UIChar.DISABLED_MID)
	TuneField.add(disabled_section, "Light:", "font.disabled_light", UIChar.DISABLED_LIGHT)
	TuneField.add(disabled_section, "Stroke", "font.disabled_stroke_enabled", UIChar.DISABLED_STROKE_ENABLED)
	TuneField.add(disabled_section, "Stroke color:", "font.disabled_stroke", UIChar.DISABLED_STROKE)
	_add_reset_button(disabled_section, "font.disabled_")

	add_separator(main_vbox)
	add_print_values_button(main_vbox)


## A per-section "Reset" that drops (Tune.clear) every override under `prefix`, so the
## code defaults re-apply everywhere — no rival literals, mirrors the alignment panel.
func _add_reset_button(section: Control, prefix: String) -> void:
	var btn_row = add_button_row(section)
	var reset = Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func() -> void:
		for slug in Tune.registered_slugs():
			if str(slug).begins_with(prefix):
				Tune.clear(slug))
	btn_row.add_child(reset)


## Re-apply the palette a scrubbed `font.*` slug belongs to, refreshing every live
## UIChar using it — the slug's value is already owned by Tune (UIChar reads it via
## Tune.of), this just re-drives the already-drawn chars.
func _on_tune_changed(slug: String, _value: Variant) -> void:
	for prefix in _PREFIX_TO_PALETTE:
		if slug.begins_with(prefix):
			_reapply_palette(_PREFIX_TO_PALETTE[prefix])
			return


func _reapply_palette(palette: UIChar.FontPalette) -> void:
	if not _scene_root:
		return
	for ui_char in _find_all_ui_chars(_scene_root):
		if ui_char.get("_current_palette") == palette:
			ui_char.set_palette(palette)


func _find_all_ui_chars(node: Node) -> Array[Node]:
	var result: Array[Node] = []
	if node is UIChar:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_ui_chars(child))
	return result


func on_shown() -> void:
	_reapply_palette(UIChar.FontPalette.MENU)
	_reapply_palette(UIChar.FontPalette.STAT)
	_reapply_palette(UIChar.FontPalette.DISABLED)


func _on_print_values() -> void:
	print("")
	print("=".repeat(50))
	print("# Font Palette Values (coalesced font.* slugs)")
	print("=".repeat(50))
	for section in [["Menu", "font.menu_"], ["Stat", "font.stat_"], ["Disabled", "font.disabled_"]]:
		print("\n# %s" % section[0])
		for slug in Tune.registered_slugs():
			if str(slug).begins_with(section[1]):
				print("  %s = %s" % [slug, Tune.get_value(slug)])
	print("=".repeat(50))
	print("")
