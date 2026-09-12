class_name SkirtDebugPanel
extends BaseDebugPanel

## Debug panel for experimenting with skirt parameters in real-time.
##
## Data-driven from SkirtConfig.PROPERTY_META: each parameter is a shared TuneField row
## bound to its `skirt.*` slug (ADR-0068 move 2). SkirtConfig OWNS the values (its
## getters coalesce Tune.of at read time), so this panel is just a VIEW (decision 12) —
## a committed override persists + applies at boot in any scene. "Rebuild Mesh" re-runs
## the generator so a scrub is reflected in the geometry.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaBattlefield` a complete census of host->addon symbol coupling.
const SkirtConfig = ExMateriaBattlefield.SkirtConfig


const TuneField = preload("res://src/debug/TuneField.gd")

var _map_composer: Node  # MapComposer reference


func setup(map_composer: Node) -> void:
	_map_composer = map_composer
	panel_title = "Skirts"
	panel_category = Category.GENERAL
	_build_ui()


## Re-point at a freshly-built composer without rebuilding the UI. The panel outlives a
## scene reload on the DebugOverlay autoload, so `MapDebugPanels.register_map_panels`
## rebinds it rather than stacking a second copy; the old composer is freed with its
## scene and "Rebuild Mesh" would call into a dead instance.
func rebind(map_composer: Node) -> void:
	_map_composer = map_composer


func _build_ui() -> void:
	var main_vbox = VBoxContainer.new()
	main_vbox.custom_minimum_size = Vector2(280, 0)
	add_child(main_vbox)

	var first := true
	for group in SkirtConfig.GROUP_ORDER:
		if not first:
			add_separator(main_vbox)
		first = false
		add_section_title(main_vbox, SkirtConfig.GROUP_TITLES[group])

		for prop_name in SkirtConfig.PROPERTY_META:
			var meta = SkirtConfig.PROPERTY_META[prop_name]
			if meta["group"] != group:
				continue
			var slug: String = "skirt." + str(prop_name)
			if meta["type"] == "bool":
				TuneField.add(main_vbox, meta["label"], slug, meta["default"])
			elif meta["type"] == "float":
				TuneField.add(main_vbox, meta["label"], slug, meta["default"],
					{"min": meta["min"], "max": meta["max"], "step": meta["step"]})

		# The land-skirt verbosity gate. Its home is SkirtGeometryGenerator's static
		# var (ADR-0140 dec. 5), not SkirtConfig.PROPERTY_META, so it is not in the
		# loop above — the row is a pure view over the slug either way, and this is
		# dec. 5's "the system's own debug panel reading it as a view".
		if group == "land":
			TuneField.add(main_vbox, "Debug Logging", "skirt.land_debug")

	add_separator(main_vbox)
	var btn_row = add_button_row(main_vbox)
	var rebuild_btn = Button.new()
	rebuild_btn.text = "Rebuild Mesh"
	rebuild_btn.pressed.connect(_on_rebuild_pressed)
	btn_row.add_child(rebuild_btn)


func _on_rebuild_pressed() -> void:
	if _map_composer and _map_composer.has_method("rebuild_map"):
		_map_composer.rebuild_map()
