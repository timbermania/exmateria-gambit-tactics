class_name UI3RegistryView
extends VBoxContainer

## The debug dashboard's UI3 page (ADR-0088 §6; ADR-0035 dec. 8): a tree
## mirroring the live element hierarchy — screens at the root, elements nested as
## registered — each unfolding to its criteria rows. A PURE VIEW over the UI3Registry
## read surface + each element's criteria(): it never binds, never touches elements —
## every write goes through the TuneField control's Tune.set_value and lands via the
## element's own on_updates (decision 12). Built like TunablesRegistryView; reads the
## autoload directly, so no injection seam is needed. Rebuild on show and on
## register/unregister while visible.

const TuneField = preload("res://src/debug/TuneField.gd")
const OwnerColorMap = preload("res://src/debug/UI3OwnerColorMap.gd")
const _DIM := Color(0.6, 0.6, 0.65)

## Criterion-row tooltips (amendment §6 legibility): the clip row explains the modes;
## the transition row points at the verbs — the enum DECLARES, the buttons INVOKE.
const _CLIP_TIP := "Clip modes: PARENT_APERTURE = payload scissored by the nearest\n" \
	+ "OWN_APERTURE ancestor's aperture; OWN_APERTURE = this element carries its own\n" \
	+ "aperture (transition beats drive it; settled = rect + aperture_pad);\n" \
	+ "UNCLIPPED = never scissored (an explicit answer, e.g. the glove cursor)."
const _TRANSITION_TIP := "Declares WHAT plays (the beat). It does not play by itself —\n" \
	+ "the orchestrator (or this row's Open/Close buttons) INVOKES the verbs."

var _tree_box: VBoxContainer
# The element-row subtree (above the location section) — where an incrementally added ROOT
# element's box is appended.
var _elements_box: VBoxContainer
# The pinned chrome bar (never scrolls) + the scrolling body that holds the row tree —
# so the page-wide map/fold controls stay reachable however far the element list scrolls.
var _header_bar: HBoxContainer
var _body_scroll: ScrollContainer
# The rendered per-criterion rows, for guards + diagnostics:
# {element_id, field, source, slug, editable}.
var _rows: Array = []
# slug -> the bound TuneField control (AUTHORED rows only).
var _controls: Dictionary = {}
# element id -> {"open": Button, "close": Button} (the amendment-§6 verb buttons).
var _verbs: Dictionary = {}
# element id -> the AT_LOCATION row's re-home OptionButton (guard surface).
var _rehome_dropdowns: Dictionary = {}
# element id -> the reason its Open/Close verbs are inert ("" = they take effect) —
# the amendment-§5 honesty surface (guard + the annotation label's text).
var _verb_reasons: Dictionary = {}
# The location-registry section (Amendment 3 §6): every registered *.loc.* slug, and
# slug -> its bound control (a second view over the same shared binds the at-location
# rows edit — one place to tune a location, not an element-by-element hunt).
var _location_slugs: Array = []
## Slugs the owner-knob section rendered (see `_add_owner_knob_section`).
var _owner_knob_slugs: Array = []
var _location_controls: Dictionary = {}
# *.loc.* slug -> the class that DEFINES it (read-only, derived from the bind site) —
# so "which element rides which position, defined where" is legible end to end.
var _location_owners: Dictionary = {}
# "element_id/field" -> the row label's tooltip (guard surface).
var _row_tips: Dictionary = {}
# element id -> the element's rendered fold box (guard surface: tree-shape asserts).
var _element_boxes: Dictionary = {}
# Registry changes are batched to one deferred flush: elements register in BURSTS (opening one
# picker registers its window plus every child in the same frame) and each used to drive its own
# full rebuild.
var _pending_added: Array = []
var _pending_removed: Array = []
var _flush_queued: bool = false
# How many times rebuild() has actually run (guard surface: proves a burst does not rebuild
# the whole page once per element).
var _rebuild_count: int = 0
## How long one deferred flush may spend adding element rows before yielding to the next frame.
## Comfortably inside a 60 Hz frame, so a burst fills in over a few frames instead of stalling
## one. The budget is checked AFTER each element, so a single element always makes progress
## however long it takes — a stuck queue is worse than a long frame.
const FLUSH_BUDGET_MS := 8.0
# The ownership map (ADR-0088 Amendment 6): a debug-only mechanism the page DRIVES. It
# swaps live meshes' materials + toggles their visibility — NO debug state lands on the
# production UI3Registry (decision 12 pure-view invariant preserved). Owned by the view
# so it auto-clears when the page hides / the view tears down.
var _map: UI3OwnerColorMap = OwnerColorMap.new()
# Click-to-navigate (ownership-map follow-on). The dashboard is its own OS-level Window, so a
# click on the GAME cannot reach this page's input — the picker lives in the MAIN window's tree
# instead and reports back by signal. It exists only while the map is on: no map, no false-color
# buffer to read, and nothing should be listening for clicks on the game.
var _picker: UI3OwnerMapPicker = null
# Page-wide "Ownership map" toggle + "Clear all" (persistent chrome, not rebuilt rows).
var _map_toggle: Button
var _clear_btn: Button
# Fold-all / Unfold-all drive every element's fold toggle at once (handoff #3).
var _fold_all_btn: Button
var _unfold_all_btn: Button
# element id -> its per-element fold toggle (collected in _add_element; driven en masse
# by Fold all / Unfold all). Rebuilt with the tree.
var _fold_toggles: Dictionary = {}
# element id -> its owner-color swatch (ColorRect) — the legend (guard surface).
var _swatches: Dictionary = {}
# element id -> its per-row Mute toggle button (guard surface).
var _mute_buttons: Dictionary = {}


func _init() -> void:
	add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "UI3 elements"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	var hint := Label.new()
	hint.text = "Registered elements + their criteria (ADR-0088). Authored rows edit live; " \
		+ "inherited/derived rows are resolved read-only. Right-click a control: Pin / Reset."
	hint.add_theme_color_override("font_color", _DIM)
	hint.add_theme_font_size_override("font_size", 11)
	add_child(hint)

	# The pinned header bar (handoff #2/#3): the page-wide controls live here, ABOVE the
	# scrolling body, so they never scroll out of reach. The map toggle false-colors every
	# element's own payload by its swatch color (the page is the legend); Clear all drops
	# the map + every Mute; Fold all / Unfold all collapse or expand every element at once.
	_header_bar = HBoxContainer.new()
	_map_toggle = Button.new()
	_map_toggle.text = "Ownership map"
	_map_toggle.toggle_mode = true
	_map_toggle.focus_mode = Control.FOCUS_NONE
	_map_toggle.tooltip_text = "False-color each element's OWN payload by its owner color " \
		+ "(the swatch beside each row is the legend). Unowned payload → the alarm color."
	_map_toggle.toggled.connect(_on_map_toggled)
	_header_bar.add_child(_map_toggle)
	_clear_btn = Button.new()
	_clear_btn.text = "Clear all"
	_clear_btn.focus_mode = Control.FOCUS_NONE
	_clear_btn.tooltip_text = "Drop the map and every Mute — restore the live game exactly"
	_clear_btn.pressed.connect(_on_clear_all)
	_header_bar.add_child(_clear_btn)
	_unfold_all_btn = Button.new()
	_unfold_all_btn.text = "Unfold all"
	_unfold_all_btn.focus_mode = Control.FOCUS_NONE
	_unfold_all_btn.tooltip_text = "Expand every element's criteria + sub-elements"
	_unfold_all_btn.pressed.connect(_on_unfold_all)
	_header_bar.add_child(_unfold_all_btn)
	_fold_all_btn = Button.new()
	_fold_all_btn.text = "Fold all"
	_fold_all_btn.focus_mode = Control.FOCUS_NONE
	_fold_all_btn.tooltip_text = "Collapse every element (only the element headers remain)"
	_fold_all_btn.pressed.connect(_on_fold_all)
	_header_bar.add_child(_fold_all_btn)
	add_child(_header_bar)

	# The scrolling body owns the row tree; the header bar above it stays pinned. The view
	# expands vertically so the body scroll gets height (DebugDashboard mounts it directly).
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll = ScrollContainer.new()
	_body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(_body_scroll)
	_tree_box = VBoxContainer.new()
	_tree_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_scroll.add_child(_tree_box)
	# The element rows live in their OWN box above the location section, so a newly registered
	# root can be appended without landing underneath "Key locations".
	_elements_box = VBoxContainer.new()
	_elements_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tree_box.add_child(_elements_box)


func _ready() -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	if registry != null:
		registry.element_registered.connect(_on_registry_changed)
		registry.element_unregistered.connect(_on_registry_unregistered)
	# Auto-clear (§4): the live game must never be left altered by a debug view the user
	# navigated away from — page-hide (an ancestor toggled invisible) restores everything.
	visibility_changed.connect(_on_visibility_changed)


## Restore the live game the instant the page leaves the screen (the dashboard hides the
## UI3 scroll on a page switch, and the whole overlay hides on F3). The map + every Mute
## drop; the toggle resets so re-showing starts clean.
func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and (_map.is_active() or not _map.muted_ids().is_empty()):
		_map.clear_all()
		_detach_picker()      # the picker lives in the MAIN window — it must not outlive the map
		if _map_toggle != null:
			_map_toggle.set_pressed_no_signal(false)


## Scene teardown / view free: restore before the meshes and this view are gone, so a
## reload never inherits swapped materials or hidden payload.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_EXIT_TREE:
		if _map != null:
			_map.clear_all()
		# The picker is parented to the MAIN window's root, so it does NOT die with this view —
		# free it explicitly or it keeps eating ctrl-clicks against a dead map.
		_detach_picker()


## A registration is ADDITIVE, and must be treated that way. Rebuilding the whole page per
## registered element cost 1.6-2.0 SECONDS when a picker opened with this page on: four signals
## in one frame, four whole-page rebuilds at ~328 ms each, three of them discarded. One
## element's row group costs ~3.4 ms to build and attach instead.
##
## Two changes in one: the burst is COALESCED into a single deferred flush, and the flush then
## touches only what changed. A full rebuild remains the fallback for anything the incremental
## path cannot express (see _flush_registry_changes), so correctness never depends on the fast
## path covering every case. UI3RegistryPageIncrementalTest pins that the two agree.
func _on_registry_changed(e: UI3Element, removed: bool = false) -> void:
	if not is_visible_in_tree():
		return
	if removed:
		_pending_removed.append(e.id())
	else:
		_pending_added.append(e)
	if _flush_queued:
		return
	_flush_queued = true
	call_deferred("_flush_registry_changes")


func _on_registry_unregistered(e: UI3Element) -> void:
	_on_registry_changed(e, true)


## Apply a frame's worth of registry changes in one pass.
##
## Falls back to a full rebuild when the incremental path cannot honestly express the change —
## an added element whose parent has no row yet (registration order not guaranteed), or an id
## already on the page. The fallback is not a safety blanket over a fragile fast path: it is
## how the page stays correct for cases worth no extra machinery, since a full rebuild is only
## slow, never wrong.
func _flush_registry_changes() -> void:
	_flush_queued = false
	var added: Array = _pending_added
	var removed: Array = _pending_removed
	_pending_added = []
	_pending_removed = []
	if not is_visible_in_tree():
		return
	var registry := get_node_or_null("/root/UI3Registry")
	if registry == null:
		return

	for id: String in removed:
		_drop_element_rows(id)
	_prune_dead_rows()

	# Spread the work across frames under a budget. One element's row group costs ~15 ms on a
	# real page, so a burst of four is ~60 ms — no longer a freeze, but still several dropped
	# frames in one go. Adding elements is order-independent and each is self-contained, so the
	# batch can simply stop at the budget and resume next frame; the page fills in progressively
	# instead of stalling. (Same shape as the studio's chunked SoundRenderQueue.)
	var started := Time.get_ticks_usec()
	for i in added.size():
		var e = added[i]
		if e == null or not is_instance_valid(e):
			continue
		if _element_boxes.has(e.id()):
			continue                                  # already shown (a rebuild beat us to it)
		var into := _mount_point_for(registry, e)
		if into == null:
			rebuild()                                 # parent not on the page — start over
			_refresh_swatches(registry)
			return
		_add_element(registry, e, _depth_of(registry, e), into, false)
		# Always place at least one per flush, or a budget smaller than a single element would
		# never make progress.
		var spent := float(Time.get_ticks_usec() - started) / 1000.0
		if spent >= FLUSH_BUDGET_MS and i + 1 < added.size():
			# Put the remainder back at the FRONT: anything that arrives next frame queues
			# behind it, so elements still appear in registration order.
			var rest: Array = added.slice(i + 1)
			rest.append_array(_pending_added)
			_pending_added = rest
			if not _flush_queued:
				_flush_queued = true
				call_deferred("_flush_registry_changes")
			break

	# The owner ramp re-spreads whenever membership changes, so EVERY row's swatch moves even
	# though only one element was added. Repainting existing ColorRects is cheap; rebuilding the
	# page to achieve it is what this whole change exists to avoid.
	_refresh_swatches(registry)


## Where an element's row group belongs: its parent element's fold content, or the elements box
## for a root. Null when the parent is registered but has no row yet.
func _mount_point_for(registry: Node, e: UI3Element) -> Control:
	var parent := _parent_element_of(registry, e)
	if parent == null:
		return _elements_box
	var pbox: Control = _live(_element_boxes.get(parent.id()))
	if pbox == null:
		return null
	# _add_element builds `outer` as [head, content] — children mount into the content fold, so
	# collapsing the parent still hides its whole subtree.
	return pbox.get_child(1) as Control if pbox.get_child_count() > 1 else null


func _parent_element_of(registry: Node, e: UI3Element) -> UI3Element:
	for other: UI3Element in registry.elements():
		if other == e:
			continue
		for child: UI3Element in registry.children_of(other):
			if child == e:
				return other
	return null


func _depth_of(registry: Node, e: UI3Element) -> int:
	var d := 0
	var cur := e
	while true:
		var p := _parent_element_of(registry, cur)
		if p == null:
			return d
		d += 1
		cur = p
	return d


## Free an element's row group and forget it — including every DESCENDANT's bookkeeping, since
## freeing the box takes their controls with it and a stale entry would hand out a dangling row.
func _drop_element_rows(element_id: String) -> void:
	var box: Control = _live(_element_boxes.get(element_id))
	# Freeing this box also destroys the boxes of any element nested inside it. Rather than
	# predict which those are, sweep for bookkeeping whose Control no longer exists — that
	# catches them whatever the cause, and it is what keeps element_box() from handing out a
	# dangling row. (Nested elements normally unregister alongside their parent and get dropped
	# on their own; this is the backstop for when they do not.)
	var doomed: Array = [element_id]
	for id: String in _element_boxes.keys():
		var other: Variant = _element_boxes[id]
		if id != element_id and (other == null or not is_instance_valid(other)):
			doomed.append(id)
	for id: String in doomed:
		_element_boxes.erase(id)
		_swatches.erase(id)
		_mute_buttons.erase(id)
		_fold_toggles.erase(id)
		_verbs.erase(id)
		_verb_reasons.erase(id)
		_rehome_dropdowns.erase(id)
	var kept: Array = []
	for r: Dictionary in _rows:
		if not doomed.has(String(r.get("element_id", ""))):
			kept.append(r)
		else:
			_controls.erase(String(r.get("slug", "")))
	_rows = kept
	if box != null and is_instance_valid(box):
		box.get_parent().remove_child(box)
		box.free()   # synchronous: rows() reflects the removal immediately


## Drop bookkeeping for any element whose row Control has been freed. element_box() and friends
## are read by guards and by reveal_element; an entry pointing at a freed Control is worse than
## a missing one, because it answers "yes, here it is".
func _prune_dead_rows() -> void:
	var dead: Array = []
	for id: String in _element_boxes.keys():
		var b: Variant = _element_boxes[id]
		if b == null or not is_instance_valid(b):
			dead.append(id)
	for id: String in dead:
		_drop_element_rows(id)


## Repaint every rendered swatch from the (re-spread) owner ramp.
func _refresh_swatches(registry: Node) -> void:
	_map.assign_colors(registry)
	for id: String in _swatches.keys():
		var sw: Variant = _swatches[id]
		if sw != null and is_instance_valid(sw):
			(sw as ColorRect).color = _map.owner_color_for(id)


## How many times the whole page has been rebuilt (guard surface).
func rebuild_count() -> int:
	return _rebuild_count


## The page-wide map toggle: activate false-colors every owned mesh + alarms the
## unowned; deactivate restores. A verb, not a write — the page stays a pure view.
func _on_map_toggled(on: bool) -> void:
	var registry := get_node_or_null("/root/UI3Registry")
	if registry == null:
		return
	if on:
		_map.activate(registry, _sweep_roots(registry))
		_attach_picker()
	else:
		_map.deactivate()
		_detach_picker()


func _on_clear_all() -> void:
	_map.clear_all()
	_detach_picker()
	if _map_toggle != null:
		_map_toggle.set_pressed_no_signal(false)
	# Reflect the cleared mutes in the row buttons.
	for id in _mute_buttons:
		(_mute_buttons[id] as Button).set_pressed_no_signal(false)


## The screen mount subtrees to audit for unowned payload (§3): the parent of each root
## element (a screen's element sits directly under its UI mount, which holds only UI). By
## scoping to those subtrees the alarm sweep never wanders into battle meshes — a wrong
## alarm on a unit sprite would make the audit lie.
func _sweep_roots(registry: Node) -> Array:
	var out: Array = []
	for r: UI3Element in registry.roots():
		var p := r.get_parent()
		if p != null and not out.has(p):
			out.append(p)
	return out


## --- Ownership-map guard surfaces (Amendment 6 §7) ---
## The owner-color swatch (ColorRect) rendered on an element's row (null when not shown).
func owner_swatch(element_id: String) -> Control:
	return _live(_swatches.get(element_id))


## An element's per-row Mute toggle (null when not shown). Toggling it hides/restores
## that element's OWN payload via the map mechanism — a verb, the page stays pure.
func mute_button(element_id: String) -> Button:
	return _live(_mute_buttons.get(element_id)) as Button


## Whether the ownership map is currently active (guard + display).
func map_active() -> bool:
	return _map.is_active()


## The ids of every currently-muted element (guard surface).
func muted_ids() -> Array:
	return _map.muted_ids()


## The pinned header bar (guard surface): the page-wide controls that never scroll away.
func header_bar() -> Control:
	return _header_bar


## The Fold-all / Unfold-all buttons (guard surface). Each drives every element's fold
## toggle at once — collapse the tree to just its element headers, or expand it fully.
func fold_all_button() -> Button:
	return _fold_all_btn


func unfold_all_button() -> Button:
	return _unfold_all_btn


## Collapse every element to just its header row (drive each fold toggle off).
func _on_fold_all() -> void:
	_set_all_folds(false)


## Expand every element — all criteria rows + nested sub-elements shown.
func _on_unfold_all() -> void:
	_set_all_folds(true)


## Drive every collected fold toggle to `open`. Setting button_pressed emits `toggled`,
## so each row's own refresh closure updates its content.visible — one code path, no
## separate "apply" that could drift from the per-row toggle behaviour.
## Every read here goes through _live: assigning a freed instance to a TYPED local is itself an
## error that aborts the loop, so `var t: Button = ...` followed by `is_instance_valid(t)` is a
## check that can never run. That exact ordering left UI3OwnerColorMap.deactivate restoring
## nothing once one payload mesh had been freed. This loop is now on the map-pick path (a pick
## folds everything before isolating its target), so it runs constantly.
func _set_all_folds(open: bool) -> void:
	for id in _fold_toggles:
		var t: Button = _live(_fold_toggles[id]) as Button
		if t != null:
			t.button_pressed = open


## The owner color assigned to an element id — the swatch color AND the on-screen color
## (one source, so the legend can't disagree with the pixels).
func owner_color(element_id: String) -> Color:
	return _map.owner_color_for(element_id)


## --- Click-to-navigate (ownership-map follow-on) ---

## How long the revealed row stays highlighted. Long enough to catch the eye after the scroll
## lands, short enough not to linger as if it were a selection — this navigates, it does not
## select, so nothing must look sticky afterwards.
const REVEAL_FLASH_SECONDS := 1.2

## The highlight color a revealed row wears. Deliberately not an owner color: the row is
## already wearing its owner color in its swatch, and a second one would read as a third owner.
const REVEAL_FLASH := Color(1.0, 1.0, 1.0, 0.28)

## The last element revealed by a map pick (guard + diagnostic surface).
var _last_revealed: String = ""
## The live flash overlay, so a second pick retargets instead of stacking overlays.
var _flash: ColorRect = null
var _flash_left: float = 0.0


## Jump to an element's row: unfold everything hiding it, scroll it into view, flash it.
##
## Ancestors matter — a nested element's box lives inside its parent's fold CONTENT, so a
## folded ancestor leaves the target with zero size and nothing to scroll to. Unfold the whole
## chain from the root down, then the target itself so its criteria rows are readable, which is
## the point of arriving.
##
## With `isolate`, everything folds shut first so ONLY the target's chain is left open — the
## map-click behaviour, where the page should end up showing the one element you pointed at
## rather than that element somewhere inside eighteen expanded ones. It is a view state: no row
## is removed, and Unfold-all brings the rest straight back.
##
## Returns false when the id has no rendered row (it registered after the last rebuild).
func reveal_element(element_id: String, isolate: bool = false) -> bool:
	var box: Control = _live(_element_boxes.get(element_id))
	if box == null:
		return false
	if isolate:
		# Fold everything FIRST, then re-open only the path down to the target. Unfolding the
		# chain alone would leave the row buried among every other element's expanded criteria,
		# which is the state the click was meant to cut through — clicking a colour means "show
		# me THIS one". Nothing is removed; the other rows are folded, not gone.
		_set_all_folds(false)
	for id: String in _ancestor_chain(element_id):
		var t: Button = _live(_fold_toggles.get(id)) as Button
		if t != null and not t.button_pressed:
			t.button_pressed = true          # emits `toggled` -> the row's own refresh runs
	var own: Button = _live(_fold_toggles.get(element_id)) as Button
	if own != null and not own.button_pressed:
		own.button_pressed = true
	_last_revealed = element_id
	_scroll_to(box)
	_flash_row(box)
	return true


## Put the picker in the MAIN window's tree (get_tree().root), not under this page: this page
## lives inside the dashboard Window, which never sees the game's clicks.
func _attach_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		return
	if get_tree() == null:
		return
	var root: Window = get_tree().root
	if root == null:
		return
	_picker = UI3OwnerMapPicker.new(_map)
	_picker.name = "UI3OwnerMapPicker"
	_picker.element_picked.connect(_on_map_element_picked)
	_picker.pick_missed.connect(_on_map_pick_missed)
	root.add_child(_picker)


func _detach_picker() -> void:
	if _picker != null and is_instance_valid(_picker):
		_picker.queue_free()
	_picker = null


## A pick landed on an element: reveal its row. The tree may have grown since the last render
## (elements register as screens boot), so rebuild once and retry rather than silently do
## nothing for a real element that simply has no row yet.
func _on_map_element_picked(element_id: String) -> void:
	if reveal_element(element_id, true):
		return
	rebuild()
	reveal_element(element_id, true)


## A pick landed on nothing. Not an error worth a dialog — but "unowned" is a genuine finding
## (real UI payload no registered element claims), so it is worth saying out loud.
func _on_map_pick_missed(color: Color, reason: String) -> void:
	if reason == "unowned":
		print("[ui3-map] clicked UNOWNED payload (alarm color) — no registered element claims it")
	elif reason == "ambiguous":
		print("[ui3-map] clicked color %s is within tolerance of more than one owner — not guessing"
			% color.to_html(false))


## Every ancestor id of `element_id`, root-first. Walked over the live registry rather than
## split out of the dotted id: ids look hierarchical but the TREE is what the folds mirror,
## and the two are free to disagree.
func _ancestor_chain(element_id: String) -> Array:
	var registry := get_node_or_null("/root/UI3Registry")
	if registry == null:
		return []
	for root: UI3Element in registry.roots():
		var path: Array = []
		if _find_path(registry, root, element_id, path):
			path.pop_back()                  # drop the target; callers unfold it separately
			return path
	return []


func _find_path(registry: Node, e: UI3Element, want: String, path: Array) -> bool:
	path.append(e.id())
	if e.id() == want:
		return true
	for child: UI3Element in registry.children_of(e):
		if _find_path(registry, child, want, path):
			return true
	path.pop_back()
	return false


## Scroll the body so `box` is visible. Layout has not run yet when a fold was just opened, so
## the position is only correct after a frame — set it now (right answer if layout was already
## settled) and again deferred (right answer if it was not). The same both-ways idiom the studio
## page uses for its own post-fold scrolls.
func _scroll_to(box: Control) -> void:
	if _body_scroll == null or not is_instance_valid(_body_scroll):
		return
	_body_scroll.ensure_control_visible(box)
	_body_scroll.call_deferred("ensure_control_visible", box)


## A brief highlight over the revealed row, so the eye can find where the scroll landed. Drawn
## as a mouse-transparent overlay child rather than by recoloring the row, so it cannot disturb
## the row's own controls or leave state behind when it expires.
func _flash_row(box: Control) -> void:
	if _flash != null and is_instance_valid(_flash):
		_flash.queue_free()
	_flash = ColorRect.new()
	_flash.color = REVEAL_FLASH
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_child(_flash)
	_flash_left = REVEAL_FLASH_SECONDS
	set_process(true)


func _process(delta: float) -> void:
	if _flash_left <= 0.0:
		return
	_flash_left -= delta
	if _flash_left <= 0.0:
		if _flash != null and is_instance_valid(_flash):
			_flash.queue_free()
		_flash = null
		set_process(false)
		return
	if _flash != null and is_instance_valid(_flash):
		# Fade out over the tail so it reads as a pulse, not a selection that stuck.
		var t: float = clampf(_flash_left / REVEAL_FLASH_SECONDS, 0.0, 1.0)
		_flash.color = Color(REVEAL_FLASH.r, REVEAL_FLASH.g, REVEAL_FLASH.b, REVEAL_FLASH.a * t)


## Null out a freed Control. Rows are freed by rebuilds, by unregistration, and by an ancestor
## going away, so any of these dictionaries can hold a corpse between a free and the next flush.
## Handing one back is worse than answering "none": callers check for null, not for validity.
## (`as Control` already yields null for a freed instance; the explicit check states the intent
## and keeps this correct if the accessors ever stop casting.)
static func _live(c: Variant) -> Control:
	return c as Control if c != null and is_instance_valid(c) else null


## The "nothing is registered yet" explainer, or null when elements are shown (guard surface).
## The page must never render a silent blank — registration happens when a migrated screen
## boots, so an empty page is a normal state that needs saying out loud.
func empty_state_label() -> Label:
	for c in _elements_box.get_children():
		if c is Label and String((c as Label).text).contains("no registered elements"):
			return c as Label
	return null


## An element's fold toggle (guard surface; null when it has no rendered row). The same
## buttons Fold-all / Unfold-all drive, and the ones reveal_element opens on the way in.
func fold_toggle(element_id: String) -> Button:
	return _live(_fold_toggles.get(element_id)) as Button


## The last element a map pick revealed (guard surface; "" before the first).
func last_revealed() -> String:
	return _last_revealed


## The live reveal-flash overlay, or null when none is showing (guard surface).
func reveal_flash() -> Control:
	return _flash


## The click-to-navigate picker, live only while the map is on (guard surface).
func map_picker() -> UI3OwnerMapPicker:
	return _picker


## The rendered row descriptors (guard/diagnostic surface; one per criterion row).
func rows() -> Array:
	return _rows


## The bound control for an AUTHORED row's slug (null when none was rendered).
func control_for(slug: String) -> Control:
	return _controls.get(slug)


## The Open/Close verb buttons rendered on an element's row ({} when not rendered).
## The buttons INVOKE elem.open()/close() — a verb is not a write; the page stays a
## pure view (amendment §6).
func verb_buttons(element_id: String) -> Dictionary:
	return _verbs.get(element_id, {})


## Why an element's Open/Close verbs are inert ("" = they take effect) — the
## amendment-§5 honesty surface: the page asks the DECLARED beat and reports NONE/
## RIDE_PARENT as inert-by-declaration, SLIDE as unbuilt, and an unmet beat
## precondition with the beat's own reason.
func verb_reason(element_id: String) -> String:
	return String(_verb_reasons.get(element_id, ""))


## Every *.loc.* slug rendered in the location-registry section (Amendment 3 §6) —
## guard surface.
func location_slugs() -> Array:
	return _location_slugs.duplicate()


## The location section's bound control for a *.loc.* slug (null when not rendered) —
## a second view over the same shared bind an at-location row edits.
func location_control_for(slug: String) -> Control:
	return _location_controls.get(slug)


## The class that DEFINES a location ("" if unresolved) — read-only, so it is clear
## which position goes with which owner. Derived from the location's Tune bind site
## (locations_of), NOT a namespace→class name transform: the honest source is where
## the literal + oracle citations actually live (Amendment 2 §2).
func location_owner(slug: String) -> String:
	if _location_owners.has(slug):
		return String(_location_owners[slug])
	return _owner_name(slug)


## The AT_LOCATION row's re-home OptionButton (null when the element has no
## at-location rect) — guard surface. Selecting an item invokes elem.place_at(slug):
## re-homes THIS element only, at runtime, NOT persisted (Amendment 3 §2b).
func rehome_dropdown(element_id: String) -> OptionButton:
	return _rehome_dropdowns.get(element_id)


## The tooltip rendered on a criterion row's label ("" when none) — guard surface.
func row_tooltip(element_id: String, field: String) -> String:
	return String(_row_tips.get(element_id + "/" + field, ""))


## An element's rendered fold box (null when not rendered) — guard surface. A nested
## element's box lives INSIDE its parent's fold content, mirroring the registry tree.
func element_box(element_id: String) -> Control:
	return _live(_element_boxes.get(element_id))


## Regenerate the whole tree from the live registry — the only way new elements
## enter the view, so callers rebuild on show (and the signals rebuild live).
func rebuild() -> void:
	_rebuild_count += 1
	for c in _tree_box.get_children():
		if c != _elements_box:
			c.free()   # synchronous: rows() reflects the fresh build immediately
	for c in _elements_box.get_children():
		c.free()
	_rows = []
	_controls = {}
	_verbs = {}
	_rehome_dropdowns = {}
	_verb_reasons = {}
	_location_slugs = []
	_owner_knob_slugs = []
	_location_controls = {}
	_location_owners = {}
	_row_tips = {}
	_element_boxes = {}
	_swatches = {}
	_mute_buttons = {}
	_fold_toggles = {}
	var registry := get_node_or_null("/root/UI3Registry")
	if registry == null:
		return
	# Assign each element its stable owner color BEFORE building rows, so a row's swatch is
	# the exact color the mesh will wear when the map is on (the page is the legend).
	_map.assign_colors(registry)
	var roots: Array = registry.roots()
	if roots.is_empty():
		# Empty state — the page is LIVE (it rebuilds the moment an element registers),
		# but registration happens when a migrated screen boots. Say so instead of
		# rendering a silent blank.
		var empty := Label.new()
		empty.text = "(no registered elements on screen — elements register when a migrated\n" \
			+ "screen opens; first migration: the equip picker, Status → Item → Eqp slot → ○)"
		empty.add_theme_color_override("font_color", _DIM)
		_elements_box.add_child(empty)
	else:
		for root: UI3Element in roots:
			_add_element(registry, root, 0, _elements_box)
	# The location registry is independent of which elements are on screen (a location
	# exists whether or not a live element rides it) — always surface it.
	_add_location_section()
	# ...and the knobs the OWNING CLASSES hold, which no element's criteria() can carry.
	_add_owner_knob_section(registry)


## One element: an indented fold (roots open, nested start folded) containing its
## criteria rows, then its child elements as nested folds. The box mounts INTO the
## parent's fold content (`into`), so the header renders above its children and
## collapsing a parent hides its whole subtree — the list mirrors the registry tree.
## `recurse` is false on the incremental path: every element emits its own registration signal,
## so a picker's children are already queued behind their parent and will each be placed — and
## each as its own budgeted chunk. Recursing there would build the whole subtree inside one
## chunk, which is exactly what the budget exists to prevent (the job picker's window plus its
## three children is 62 ms in one indivisible go, versus ~15 ms each).
func _add_element(registry: Node, e: UI3Element, depth: int, into: Control, recurse: bool = true) -> void:
	var outer := VBoxContainer.new()
	var head := HBoxContainer.new()
	outer.add_child(head)
	# The owner-color swatch (Amendment 6 §1): the legend entry for this element — the
	# same color its own payload wears on screen while the map is active.
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 14)
	swatch.color = _map.owner_color_for(e.id())
	swatch.tooltip_text = "Owner color for %s (its own payload wears this on the map)" % e.id()
	head.add_child(swatch)
	_swatches[e.id()] = swatch
	var toggle := Button.new()
	toggle.toggle_mode = true
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(toggle)
	# The amendment-§6 VERB buttons: invoke the element's open()/close() — the
	# transition enum row DECLARES the beat, these INVOKE it. Not a write; the page
	# stays a pure view.
	var open_btn := Button.new()
	open_btn.text = "Open"
	open_btn.focus_mode = Control.FOCUS_NONE
	open_btn.tooltip_text = "Invoke elem.open() — plays the declared transition beat forward"
	open_btn.pressed.connect(func() -> void:
		if is_instance_valid(e):
			e.open())
	head.add_child(open_btn)
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.tooltip_text = "Invoke elem.close() — the same beat reversed, ends shut"
	close_btn.pressed.connect(func() -> void:
		if is_instance_valid(e):
			e.close())
	head.add_child(close_btn)
	_verbs[e.id()] = {"open": open_btn, "close": close_btn}
	# The per-row Mute toggle (Amendment 6 §4): blink this element's own payload out to
	# confirm "that strip was vitals_band." Pure visibility (needs none of the swap); prior
	# visibility is captured + restored exactly. Multi-mute stacks. A verb — pure view.
	var mute_btn := Button.new()
	mute_btn.text = "Mute"
	mute_btn.toggle_mode = true
	mute_btn.focus_mode = Control.FOCUS_NONE
	mute_btn.tooltip_text = "Hide this element's OWN payload (restores its prior visibility exactly)"
	mute_btn.set_pressed_no_signal(_map.is_muted(e.id()))   # keep state across a rebuild
	mute_btn.toggled.connect(func(on: bool) -> void:
		if is_instance_valid(e):
			_map.set_muted(e, on))
	head.add_child(mute_btn)
	_mute_buttons[e.id()] = mute_btn
	# Amendment §5 honesty: ask the DECLARED beat whether Open/Close will actually take
	# effect, and disable + annotate the verbs with the reason when they won't — so a
	# button never lies by sitting there doing nothing.
	_annotate_verbs(registry, e, head, open_btn, close_btn)
	var content := VBoxContainer.new()
	outer.add_child(content)
	var indent := "    ".repeat(depth)
	var refresh := func() -> void:
		toggle.text = indent + ("▾  " if toggle.button_pressed else "▸  ") + e.id()
		content.visible = toggle.button_pressed
	toggle.toggled.connect(func(_on: bool) -> void: refresh.call())
	toggle.set_pressed_no_signal(depth == 0)
	refresh.call()
	_fold_toggles[e.id()] = toggle   # collected for Fold all / Unfold all

	for row: Dictionary in e.criteria():
		_add_criterion_row(content, e, row, depth + 1)
	if recurse:
		for child: UI3Element in registry.children_of(e):
			_add_element(registry, child, depth + 1, content)
	into.add_child(outer)
	_element_boxes[e.id()] = outer


## The location-registry section (Amendment 3 §6): a flat, editable list of every
## registered `*.loc.*` slug + value, in one place — so tuning a key location is not
## an element-by-element hunt. A pure view over the owners' existing binds (registers
## nothing); the same slug an at-location row edits, surfaced here too.
func _add_location_section() -> void:
	var slugs: Array = []
	for s in Tune.registered_slugs():
		if String(s).contains(".loc."):
			slugs.append(String(s))
	if slugs.is_empty():
		return   # no locations bound yet (no migrated screen with key locations booted)
	var header := Label.new()
	header.text = "Key locations"
	header.add_theme_font_size_override("font_size", 14)
	_tree_box.add_child(header)
	var sub := Label.new()
	sub.text = "Every registered <ns>.loc.* position — editing one moves every element homed there."
	sub.add_theme_color_override("font_color", _DIM)
	sub.add_theme_font_size_override("font_size", 11)
	_tree_box.add_child(sub)
	for slug in slugs:
		var hbox := HBoxContainer.new()
		_tree_box.add_child(hbox)
		var label := Label.new()
		label.text = "    " + _location_name(slug) + "  (" + slug + ")"
		label.custom_minimum_size.x = 260
		label.add_theme_color_override("font_color", TuneField.TUNABLE_ACCENT)
		hbox.add_child(label)
		var control: Control = TuneField.build_control(slug, Tune.default_of(slug), Tune.meta_of(slug))
		if control != null:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(control)
			_location_controls[slug] = control
		var owner := _owner_name(slug)
		_location_owners[slug] = owner
		if owner != "":
			# Read-only: which class defines this position (its literal + oracle citations).
			var owner_lbl := Label.new()
			owner_lbl.text = "  ← " + owner
			owner_lbl.add_theme_color_override("font_color", _DIM)
			owner_lbl.add_theme_font_size_override("font_size", 11)
			hbox.add_child(owner_lbl)
		_location_slugs.append(slug)


## Namespaces this page is a view of: the first `.`-segment of every registered element's id
## (`turnqueue.card.3` → `turnqueue`), plus `ui3` — the shared engines' own knobs, which every
## element on this page rides whether or not any of them is named `ui3.*`.
const _ENGINE_NAMESPACE := "ui3"


## The OWNER-KNOB section: the class-owned `Tune` slugs in the namespaces above that are not
## already on the page as a criterion, a driver or a key location.
##
## The gap it fills is a REACHABILITY one, not an existence one, and the difference matters
## because the honest version is smaller than "these knobs are invisible". A slug that DRIVES a
## derived rect (`turnqueue.spacing`, `turnqueue.card_scale`) is already reachable — as a
## driver row nested under each element's derived `rect`, i.e. once per element, ten times over,
## each inside its own fold. A slug that drives no rect at all (a team colour, a band strength,
## a card cap) has no row anywhere and cannot get one: `criteria()` reports an ELEMENT's fields,
## and none of these is one.
##
## So: one row per knob, in one place, for both kinds. Derived by NAMESPACE rather than from a
## hand-written list, because a list in a debug panel is schema living in the view — the thing
## ADR-0068 moved out — and it would go stale the first time an owner added a knob. A pure view:
## every control is a [TuneField] over a bind its owner already registered.
func _add_owner_knob_section(registry: Node) -> void:
	var namespaces := {_ENGINE_NAMESPACE: true}
	for e: UI3Element in registry.elements():
		var ns := String(e.id()).get_slice(".", 0)
		if ns != "":
			namespaces[ns] = true
	var slugs: Array = []
	for s in Tune.registered_slugs():
		var slug := String(s)
		if not namespaces.has(slug.get_slice(".", 0)):
			continue
		if slug.contains(".loc."):
			continue                        # the key-location section above owns these
		if _controls.has(slug) or _location_controls.has(slug):
			continue                        # already editable somewhere on this page
		slugs.append(slug)
	if slugs.is_empty():
		return
	slugs.sort()
	var header := Label.new()
	header.text = "Owner knobs"
	header.add_theme_font_size_override("font_size", 14)
	_tree_box.add_child(header)
	var sub := Label.new()
	sub.text = "Class-owned knobs in these screens' namespaces — the ones no element's criteria() can carry."
	sub.add_theme_color_override("font_color", _DIM)
	sub.add_theme_font_size_override("font_size", 11)
	_tree_box.add_child(sub)
	for slug in slugs:
		var hbox := HBoxContainer.new()
		_tree_box.add_child(hbox)
		var label := Label.new()
		label.text = "    " + slug
		label.custom_minimum_size.x = 260
		label.add_theme_color_override("font_color", TuneField.TUNABLE_ACCENT)
		hbox.add_child(label)
		var control: Control = TuneField.build_control(slug, Tune.default_of(slug), Tune.meta_of(slug))
		if control != null:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(control)
			_controls[slug] = control
			_owner_knob_slugs.append(slug)
		var owner := _owner_name(slug)
		if owner != "":
			var owner_lbl := Label.new()
			owner_lbl.text = "  ← " + owner
			owner_lbl.add_theme_color_override("font_color", _DIM)
			owner_lbl.add_theme_font_size_override("font_size", 11)
			hbox.add_child(owner_lbl)


## Every slug the owner-knob section rendered a control for, in display order. For tests and
## for the same reason `location_slugs()` exists: a section that renders nothing and a section
## that was never called look identical from outside.
func owner_knob_slugs() -> Array:
	return _owner_knob_slugs.duplicate()


## One driver of a derived placement (Amendment 3 §4): the driver's own slug as an
## editable control, indented under the read-only derived row. Registers nothing —
## the driver bind already exists (the derived element subscribed it); the page is a
## pure view over it. Skipped if the slug is not registered (a mis-declared driver).
func _add_driver_row(parent: Control, slug: String, depth: int) -> void:
	if not Tune.is_registered(slug):
		return
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)
	var label := Label.new()
	label.text = "    ".repeat(depth) + "↳ " + slug
	label.custom_minimum_size.x = 170
	label.add_theme_color_override("font_color", TuneField.TUNABLE_ACCENT)
	label.add_theme_font_size_override("font_size", 11)
	hbox.add_child(label)
	var control: Control = TuneField.build_control(slug, Tune.default_of(slug), Tune.meta_of(slug))
	if control != null:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(control)
		_controls[slug] = control


## The re-home dropdown (Amendment 3 §2b/§3): the element's legal locations = every
## registered slug sharing the current location's `<ns>.loc.` prefix (derived, not a
## declared candidate set — §3). Picking one invokes elem.place_at(slug), re-homing
## THIS element only, at runtime; it is NOT persisted (a reboot returns to the
## host-authored home), so the control is labelled as such.
func _add_rehome_dropdown(hbox: Control, e: UI3Element, slug: String) -> void:
	var marker := ".loc."
	var i := slug.rfind(marker)
	if i < 0:
		return
	var prefix := slug.substr(0, i + marker.length())
	var dd := OptionButton.new()
	dd.focus_mode = Control.FOCUS_NONE
	dd.tooltip_text = "Re-home this element to another key location (runtime only — NOT persisted)"
	var idx := 0
	for s in Tune.registered_slugs():
		var ss := String(s)
		if not ss.begins_with(prefix):
			continue
		dd.add_item(_location_name(ss))
		dd.set_item_metadata(dd.item_count - 1, ss)
		if ss == slug:
			dd.select(dd.item_count - 1)
		idx += 1
	dd.item_selected.connect(func(sel: int) -> void:
		if is_instance_valid(e):
			e.place_at(String(dd.get_item_metadata(sel))))
	hbox.add_child(dd)
	_rehome_dropdowns[e.id()] = dd


## The owner class name for a location slug, from its Tune bind site: the first
## recorded use-site file's basename ("…/StartActionMenu.gd" → "StartActionMenu").
## Empty when no site was captured (release build / no script debugger) — the display
## then falls back to just the slug's namespace, which is still informative.
func _owner_name(slug: String) -> String:
	var locs: Array = Tune.locations_of(slug)
	if locs.is_empty():
		return ""
	return String(locs[0].get("file", "")).get_file().get_basename()


## The human location NAME from a `<ns>.loc.<name>` slug (the tail past `.loc.`) —
## "startmenu.loc.equip" → "equip". Falls back to the whole slug if it is not a
## location slug (defensive; AT_LOCATION rows always carry one).
func _location_name(slug: String) -> String:
	var marker := ".loc."
	var i := slug.rfind(marker)
	return slug.substr(i + marker.length()) if i >= 0 else slug


## Resolve WHY (if at all) an element's Open/Close verbs are inert, disable + annotate
## them with the reason, and record it (Amendment 3 §5). The page asks the declared
## beat, never hard-coding "BOX_OPEN needs OWN_APERTURE" here: NONE/RIDE_PARENT reveal
## with their parent (inert by declaration); SLIDE names a beat that isn't built yet;
## a built beat with an unmet precondition reports the beat's own human reason.
func _annotate_verbs(registry: Node, e: UI3Element, head: Control, open_btn: Button, close_btn: Button) -> void:
	var kind := e.transition_mode()
	var reason := ""
	if kind == UI3Element.Transition.NONE or kind == UI3Element.Transition.RIDE_PARENT:
		reason = "inert: reveals with its parent (no own transition)"
	else:
		var beat: UI3Beat = registry.beat_for(kind)
		if beat == null:
			reason = "unbuilt: no beat registered for this transition"
		else:
			reason = beat.precondition(e)
	_verb_reasons[e.id()] = reason
	if reason != "":
		open_btn.disabled = true
		close_btn.disabled = true
		open_btn.tooltip_text = reason
		close_btn.tooltip_text = reason
		var note := Label.new()
		note.text = "  ⃠ " + reason
		note.add_theme_color_override("font_color", _DIM)
		note.add_theme_font_size_override("font_size", 10)
		head.add_child(note)


func _add_criterion_row(parent: Control, e: UI3Element, row: Dictionary, depth: int) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)

	var label := Label.new()
	label.text = "    ".repeat(depth) + String(row["field"])
	label.custom_minimum_size.x = 170
	label.mouse_filter = Control.MOUSE_FILTER_STOP   # labels ignore the mouse by default — no hover, no tooltip
	match String(row["field"]):
		"clip":
			label.tooltip_text = _CLIP_TIP
		"transition":
			label.tooltip_text = _TRANSITION_TIP
	if label.tooltip_text != "":
		_row_tips[e.id() + "/" + String(row["field"])] = label.tooltip_text
	hbox.add_child(label)

	var slug := String(row["slug"])
	var is_at_loc: bool = row["source"] == UI3Element.Source.AT_LOCATION
	# The class that DEFINES this location (read-only) — carried on the row so the chain
	# element → location → owner is legible end to end.
	var owner: String = _owner_name(slug) if is_at_loc else ""
	# AT_LOCATION (Amendment 3 §2a) and AUTHORED both edit a real Tune bind. The
	# difference is ownership: an AT_LOCATION slug is a SHARED key-location owned by
	# another class, so the row is labelled with the location NAME (not the opaque
	# slug/Rect2) and editing it re-authors that location for every rider.
	var is_screen_anchored: bool = row["source"] == UI3Element.Source.SCREEN_ANCHORED
	var has_bind: bool = (row["source"] == UI3Element.Source.AUTHORED or is_at_loc or is_screen_anchored) \
		and slug != "" and Tune.is_registered(slug)
	var editable := false
	if is_screen_anchored:
		# Label the group-nudge honestly: the assembly has no per-piece rect, but its ONE
		# <id>.origin knob translates the WHOLE group (Amendment 4 §1, Option C).
		label.text += "  (screen-anchored — origin nudges the whole group)"
	if is_at_loc:
		# Name the shared location beside the field ("rect @ equip ← StartActionMenu") so
		# the row is not an opaque slug — its value-edit blast radius (every rider) is
		# stated below, and the owning class (where the position is defined) read-only.
		label.text += " @ " + _location_name(slug)
		if owner != "":
			label.text += " ← " + owner
	if has_bind:
		# View row over an existing bind: default/hint/persist come from the registry
		# (the owner registered it) — the page registers nothing.
		var control: Control = TuneField.build_control(slug, Tune.default_of(slug), Tune.meta_of(slug))
		if control != null:
			control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(control)
			_controls[slug] = control
			editable = true
			label.add_theme_color_override("font_color", TuneField.TUNABLE_ACCENT)
			if is_at_loc:
				var note := Label.new()
				note.text = "  (edits the shared location — moves every rider)"
				note.add_theme_color_override("font_color", _DIM)
				note.add_theme_font_size_override("font_size", 10)
				hbox.add_child(note)
	if is_at_loc:
		_add_rehome_dropdown(hbox, e, slug)
	if is_screen_anchored and not editable:
		# Defensive: the origin bind should always be registered (minted at construction);
		# if it somehow is not, still render the honest label rather than a lying value.
		var note := Label.new()
		note.text = "screen-anchored assembly — placement is per-child"
		note.add_theme_color_override("font_color", _DIM)
		hbox.add_child(note)
		label.add_theme_color_override("font_color", _DIM)
	elif not editable:
		var tag := "(inherited)" if row["source"] == UI3Element.Source.INHERITED else \
			("(derived)" if row["source"] == UI3Element.Source.DERIVED else "")
		var value := Label.new()
		value.text = "%s %s" % [str(row["value"]), tag]
		value.add_theme_color_override("font_color", _DIM)
		hbox.add_child(value)
		label.add_theme_color_override("font_color", _DIM)

	_rows.append({"element_id": e.id(), "field": row["field"], "source": row["source"],
		"slug": slug, "editable": editable, "owner": owner})

	# Slice 4 (Amendment 3 §4): a plain DERIVED row is not a dead end — its drivers are
	# ordinary pinnable binds, so expand each as an inline editable control UNDER the
	# read-only computed value. (At-location rows carry a single driver — the shared
	# location slug — surfaced above as the value edit + re-home, so they don't expand.)
	if row["source"] == UI3Element.Source.DERIVED:
		for driver in row.get("drivers", []):
			_add_driver_row(parent, String(driver), depth + 1)
