class_name StoryTimelineDebugPanel
extends BaseDebugPanel

## F3 STORY panel: read the DERIVED story timeline (ADR-0216) for any group root — the
## same two answers the navigator now takes from it, side by side with what the live
## catalogue actually holds.
##
## [b]Left question — "what must be true when I arrive here?"[/b] The world-map `enter`
## state [NavigatorMain._install_world_state] installs on a Seek, plus whether that state
## leaves this group's node ALONE live. A non-exclusive root is the warning case: the map
## may offer nothing (an unmodelled `party has job` gate) or more than one node.
##
## [b]Right question — "who is in the party?"[/b] `roster_before` (the fold of every
## recruit granted ahead of this group) and the joins this group grants at its own end.
##
## Read-only, and deliberately so: seeking is [NavigatorDebugPanel]'s job, one cell over.
## This is the panel you open when a Seek lands somewhere surprising and you want to know
## whether the DATA or the WALK is wrong. Refreshes on show.

const _PANEL_WIDTH := 380

## Rows the group list shows before it starts eliding — 155 groups will not fit a cell.
const _MAX_ROWS := 12

var _root_picker: OptionButton
var _body: VBoxContainer
var _roots: Array[int] = []


func setup() -> void:
	panel_title = "Story timeline"
	panel_category = Category.STORY
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(_PANEL_WIDTH, 0)
	add_child(vbox)

	add_section_title(vbox, "Derived from the ROM (ADR-0216)")
	var intro := add_label(vbox, "assets/scenarios/roster_timeline.json — regenerate it "
		+ "with tools/build_roster_timeline.py; never hand-edit it.")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(_PANEL_WIDTH - 20, 0)

	_root_picker = OptionButton.new()  # tune-exempt: read-only data browser; the selection is a view, nothing is set
	_root_picker.item_selected.connect(_on_root_selected)
	vbox.add_child(_root_picker)

	add_separator(vbox)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 0)
	vbox.add_child(_body)

	_fill_roots()
	_refresh()


func on_shown() -> void:
	_refresh()


## Every group root in STORY order — which is the ordering the whole artifact is about,
## so the picker must not re-sort it by id.
func _fill_roots() -> void:
	_roots = RosterTimeline.order()
	_root_picker.clear()
	for root in _roots:
		_root_picker.add_item("%3d. root %d — %s"
			% [RosterTimeline.position(root), root, _map_name(root)])
	if not _roots.is_empty():
		_root_picker.select(0)


func _on_root_selected(_idx: int) -> void:
	_refresh()


func _selected_root() -> int:
	var idx := _root_picker.selected if _root_picker != null else -1
	if idx < 0 or idx >= _roots.size():
		return -1
	return _roots[idx]


func _refresh() -> void:
	if _body == null:
		return
	for c in _body.get_children():
		c.queue_free()
	var root := _selected_root()
	if root < 0:
		_body.add_child(_dim("(the derived timeline is empty — is roster_timeline.json present?)"))
		return

	# --- the seek state (Ask C) ---
	_body.add_child(_head("World-map state a Seek installs"))
	if not RosterTimeline.has_enter(root):
		_body.add_child(_dim("  none — this group is only ever reached by CHAINING, so a "
			+ "Seek here cannot re-root the map"))
	else:
		var wanted := RosterTimeline.enter_vars(root)
		var parts: Array[String] = []
		for idx in wanted:
			parts.append("var[%d]=%d" % [int(idx), int(wanted[idx])])
		_body.add_child(_dim("  " + (", ".join(parts) if not parts.is_empty() else "(no conditions)")))
		if RosterTimeline.enter_is_exclusive(root):
			_body.add_child(_dim("  exclusive — this leaves exactly this group's node live"))
		else:
			_body.add_child(_dim("  NOT exclusive — the map may offer nothing (an unmodelled "
				+ "`party has job` gate) or more than one node"))

	# --- the roster (Ask D) ---
	var before := RosterTimeline.roster_before(root)
	_body.add_child(_head("Roster on arrival — %d unit(s)" % before.size()))
	_body.add_child(_dim("  " + _elide(before)))

	var joins := RosterTimeline.joins_for(root)
	_body.add_child(_head("Granted at this group's END — %d delta(s)" % joins.size()))
	if joins.is_empty():
		_body.add_child(_dim("  none"))
	for delta in joins:
		var kind := "recruit" if bool(delta.get("recruit", false)) else "repeat (not folded)"
		_body.add_child(_dim("  %s — %s — ENTD %d slot %d"
			% [String(delta.get("slug", "?")), kind,
				int(delta.get("entd_idx", -1)), int(delta.get("slot_index", -1))]))

	# --- what the LIVE catalogue holds, so a mismatch is visible rather than inferred ---
	_body.add_child(_head("Live catalogue right now"))
	if CharacterCatalog == null:
		_body.add_child(_dim("  (no CharacterCatalog autoload)"))
	else:
		var owned: Array = CharacterCatalog.owned_slugs()
		_body.add_child(_dim("  owned (%d): %s" % [owned.size(), _elide(owned)]))
		var missing: Array = []
		for slug in before:
			if not CharacterCatalog.has_slug(String(slug)):
				missing.append(slug)
		if missing.is_empty():
			_body.add_child(_dim("  every unit the timeline expects here is present"))
		else:
			_body.add_child(_dim("  MISSING vs the timeline (%d): %s"
				% [missing.size(), _elide(missing)]))


## The group's map name, straight off the derived artifact's own row.
func _map_name(root: int) -> String:
	return String(RosterTimeline.map_name(root))


func _elide(items: Array) -> String:
	if items.is_empty():
		return "(none)"
	var shown: Array = items.slice(0, _MAX_ROWS)
	var text: String = ", ".join(PackedStringArray(shown))
	if items.size() > shown.size():
		text += " … (+%d)" % (items.size() - shown.size())
	return text


func _head(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	return l


func _dim(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(_PANEL_WIDTH - 20, 0)
	l.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	return l
