class_name RosterUniverseDebugPanel
extends BaseDebugPanel

## F3 ROSTER panel: the persistent "universe" — every Character in [CharacterCatalog]
## as it stands at the current beat (ADR-0201's mutation script folds guests in as the
## walk advances). This is the pool the Battle Binding panel draws from; seeing it is the
## prerequisite for understanding any battle's roster→slot binding. Read-only; refreshes
## on show. Row logic lives in [RosterDebugView] (unit-tested).

const RosterDebugView = ExMateriaCatalogue.RosterDebugView
const _PANEL_WIDTH := 380

var _rows_vbox: VBoxContainer


func setup() -> void:
	panel_title = "Universe"
	panel_category = Category.ROSTER
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	add_child(vbox)

	add_section_title(vbox, "Character catalogue (the persistent universe)")
	var intro := add_label(vbox, "Everyone who exists right now — the catalogue the "
		+ "mutation script has folded up to the current beat. This is the pool the "
		+ "battle binding draws from.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(_PANEL_WIDTH - 20, 0)
	add_separator(vbox)

	_rows_vbox = VBoxContainer.new()
	_rows_vbox.add_theme_constant_override("separation", 0)
	vbox.add_child(_rows_vbox)
	_refresh()


func on_shown() -> void:
	_refresh()


func _refresh() -> void:
	if _rows_vbox == null:
		return
	for c in _rows_vbox.get_children():
		c.queue_free()
	if CharacterCatalog == null:
		_rows_vbox.add_child(_dim("(no CharacterCatalog autoload)"))
		return
	var rows: Array = RosterDebugView.build_universe_rows(CharacterCatalog.all_characters())
	_rows_vbox.add_child(_dim("%d character(s) — slug — name  [provenance] group  job:" % rows.size()))
	for r in rows:
		var lbl := Label.new()
		var job := ""
		if String(r.get("job", "")) != "":
			job = "  %s L%d" % [r["job"], int(r.get("level", 0))]
		var sex := "  ♀" if bool(r.get("female", false)) else ""
		lbl.text = "  %s — %s  [%s] %s%s%s" % [
			r["slug"], r["name"], r["provenance"], r["group"], job, sex]
		_rows_vbox.add_child(lbl)


func _dim(text: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.72))
	return lbl
