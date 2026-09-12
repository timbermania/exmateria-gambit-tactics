class_name BattleBindingDebugPanel
extends BaseDebugPanel

## F3 ROSTER panel: how the persistent catalogue (see [RosterUniverseDebugPanel]) maps
## onto the CURRENT battle's ENTD slots via [SlugBinding] (ADR-0201 dec.6/7). Each
## non-empty slot resolves to a catalogue Character (HIT) or falls back to the raw ENTD
## slot (a coverage gap). Read-only — it inspects the live navigator's binding without
## mutating it (uses `resolve_slug`, not `resolve_character`). Row logic in [RosterDebugView].
##
## Live data comes from the navigator's `debug_current_binding()` read-seam; the panel is
## rebound to the navigator across scene reloads.

const RosterDebugView = ExMateriaCatalogue.RosterDebugView
const _PANEL_WIDTH := 380

var _nav: Object   # NavigatorMain (duck-typed on debug_current_binding())
var _summary: Label
var _rows_vbox: VBoxContainer


func setup(navigator: Object) -> void:
	_nav = navigator
	panel_title = "Battle Binding"
	panel_category = Category.ROSTER
	_build_ui()


## Re-point at the live navigator after a scene reload (the panel outlives the scene).
func rebind(navigator: Object) -> void:
	_nav = navigator
	_refresh()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	add_child(vbox)

	add_section_title(vbox, "Roster → ENTD-slot binding (current battle)")
	var intro := add_label(vbox, "How the catalogue maps onto this battle's ENTD slots. "
		+ "HIT = a catalogue character flows in; FALLBACK = coverage gap (built from the "
		+ "raw ENTD slot).")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(_PANEL_WIDTH - 20, 0)
	add_separator(vbox)

	_summary = Label.new()
	vbox.add_child(_summary)
	add_separator(vbox)

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.add_theme_constant_override("separation", 0)
	vbox.add_child(_rows_vbox)
	_refresh()


func on_shown() -> void:
	_refresh()


func _refresh() -> void:
	if _rows_vbox == null or _summary == null:
		return
	for c in _rows_vbox.get_children():
		c.queue_free()

	var info: Dictionary = {}
	if _nav != null and is_instance_valid(_nav) and _nav.has_method("debug_current_binding"):
		info = _nav.debug_current_binding()
	if info.is_empty():
		_summary.text = "(no battle world booted — seek to a battle)"
		return

	var slots: Array = info.get("slots", [])
	var ctx := int(info.get("context", -1))
	var binding = info.get("binding")
	var cat = info.get("catalogue")
	var s: Dictionary = RosterDebugView.binding_summary(slots, ctx, binding, cat)
	_summary.text = "ENTD %d — %d slot(s):  %d bound, %d fallback" % [
		ctx, int(s["total"]), int(s["bound"]), int(s["fallback"])]

	for r in RosterDebugView.build_binding_rows(slots, ctx, binding, cat):
		var lbl := Label.new()
		var spot := "@(%d,%d)" % [int(r.get("x", -1)), int(r.get("y", -1))]
		if bool(r.get("bound", false)):
			lbl.text = "  uid %d [%s] %s → %s  (%s)" % [int(r["uid"]), r["team"], spot, r["name"], r["slug"]]
			lbl.add_theme_color_override("font_color", Color(0.7, 0.9, 0.72))
		else:
			lbl.text = "  uid %d [%s] %s → FALLBACK  (special_name %d)" % [
				int(r["uid"]), r["team"], spot, int(r.get("special_name", 255))]
			lbl.add_theme_color_override("font_color", Color(0.95, 0.82, 0.6))
		_rows_vbox.add_child(lbl)
