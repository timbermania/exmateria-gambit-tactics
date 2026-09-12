class_name TuneField
extends RefCounted
## The ONE builder for a tunable debug-panel row (ADR-0068). `add()` produces a
## complete row — label + type-inferred control + Tune wiring + right-click
## Pin/Reset menu + typographic markers — and is used by BOTH the generated
## Tunables dashboard AND bespoke debug panels, so there is a single
## implementation and no drift between them.
##
## Deep module: the whole surface a caller learns is `add()` (returns the control
## so it can be tweaked). Everything behind it — control inference, the `bind`
## register + coalesced read, the two-way control<->Tune binding (edit -> set_value;
## value_changed -> resync + marker refresh), the owner-scoped auto-drop, the menu,
## and the markers — is hidden. `add()` IS a Tune use-site: it `bind`s the slug
## (first-write-wins, idempotent for already-registered slugs) and coalesces.
##
## Markers are TYPOGRAPHIC, not icons (a deliberate anti-clutter choice): the label
## color IS the persistence class at a glance — cyan = tunable (Pin to keep), green =
## auto-persist (sticks on every edit), grey = ephemeral (declared session-only, never
## persisted). All three are Tune-backed; they differ only in disk-persistence policy.
## A " *" shows in a reserved trailing slot while a TUNABLE field's live value is dialed
## past the committed baseline (dirty); AUTOSAVE and EPHEMERAL never show it. The slot is
## ALWAYS reserved so toggling the marker never reflows the label or shifts the control.
##
## The persistence class is a property of the SLUG, not the widget (ADR-0068 decision
## 12): declared via the `persist` param on the registration use-site (Tune.bind /
## this add()), TUNABLE by default, and TuneField DERIVES the color + commit behavior
## from Tune.persist_of(slug). See Tune.Persist.

## Accent color for a tunable's label — the at-a-glance "Pin this to keep it" cue. A
## soft cyan; easy to change without touching any logic.
const TUNABLE_ACCENT := Color(0.55, 0.85, 0.95)

## Accent color for an auto-persist label — Catppuccin Mocha green (#a6e3a1): "already
## saved, no effort." Distinct from the cyan tunable accent because an AUTOSAVE slug
## commits every edit straight to the staging file (no Pin gesture, no dirty marker).
const AUTOSAVE_ACCENT := Color(0.651, 0.890, 0.631)

## Accent color for an ephemeral label — a muted grey/white: "session-only, not kept."
## An EPHEMERAL field is a DECLARED throwaway (command input, transient toggle), never
## persisted — the neutral color says so, distinct from a value worth pinning.
const EPHEMERAL_ACCENT := Color(0.78, 0.78, 0.78)

## Metadata key under which every built row carries its slug. Read by `PanelApplicability`
## to derive what a panel is a view onto; written by `_add_label_and_marker`.
const SLUG_META := "tune_slug"

## Per-field actions surfaced by right-clicking the control (kept off the row to
## avoid a button-per-action). Pin = commit_slug (persist just this one); Reset =
## clear the override back to the code default.
enum Action { PIN, RESET }


## Build one tunable row under `parent`: a `label`-titled control (widget inferred
## from the value's type + optional `hint`, ADR-0068 decision 11), wired two-way to
## the Tune slug and carrying the tunable/dirty markers + right-click menu. Returns
## the control so callers can tweak it (null for a type with no widget yet).
##
## A panel is a VIEW, never an owner (decision 12 / R5): leave `default_value` unset and
## the row reads the slug's registered literal + hint + persist from the registry — the
## OWNER's `bind` supplies the value (PSXDisplay / Unit register at boot). Pass a
## `default_value` only when this call is the legitimate registrant: a debug-only
## AUTOSAVE/EPHEMERAL slug whose home IS the staging file (decision 10), or a panel not
## yet migrated off the old self-registering form.
static func add(parent: Control, label_text: String, slug: String,
		default_value: Variant = null, hint: Dictionary = {},
		persist: int = Tune.Persist.TUNABLE, path: String = "") -> Control:
	var row := HBoxContainer.new()
	parent.add_child(row)

	if default_value == null:
		# View row: the owner already bound this slug — read its registered literal + hint +
		# effective persistence class, and register nothing here.
		default_value = Tune.default_of(slug)
		if hint.is_empty():
			hint = Tune.meta_of(slug)
		persist = Tune.persist_of(slug)
		if default_value == null:
			# Still unregistered (the owner hasn't booted — e.g. an element whose binds
			# mint at construction): render a read-only placeholder and bind NOTHING.
			# Passing null on into build_control would register a PHANTOM null default
			# that first-write-wins then poisons the owner's later real bind.
			var label := _add_label_and_marker(row, label_text, slug)
			var placeholder := Label.new()
			placeholder.text = "(unregistered — owner not booted)"
			placeholder.add_theme_color_override("font_color", EPHEMERAL_ACCENT)
			row.add_child(placeholder)
			label.call()
			return null
	else:
		# Registrant row: register/upgrade the slug's mode up front so the label reflects the
		# EFFECTIVE persistence class (e.g. a code owner that already declared AUTOSAVE), not
		# merely what this call passed. The accent color IS that class at a glance.
		Tune.bind(slug, default_value, hint, persist)
	# The label + reserved dirty-marker slot are built by the shared helper so add() and
	# add_dropdown() render the same accent + never-reflowing marker contract.
	var refresh_marker := _add_label_and_marker(row, label_text, slug)
	# The control + its full two-way Tune wiring is built by the shared helper, so the
	# generated dashboard, a bespoke panel, and the registry page all bind identically.
	var control: Control = build_control(slug, default_value, hint, refresh_marker, persist, path)
	if control:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
	return control


## Build a tunable row whose control is a DYNAMIC dropdown — an OptionButton populated
## from a database at RUNTIME, so its label→value map isn't known upfront and the enum
## path (`hint.enum`) can't be used. Returns an EMPTY OptionButton the caller fills in
## (`add_item` + `set_item_metadata(i, <stable key>)`); the slug stores the SELECTED item's
## stable key as a STRING, so a selection sticks across reloads (AUTOSAVE) by key, not by
## row index. After populating, the caller calls `resync_dropdown` to re-select the
## persisted key (the items don't exist at build time — "late assignment"). Mirrors add()'s
## label + marker + accent + right-click menu; only the control and its binding differ.
static func add_dropdown(parent: Control, label_text: String, slug: String,
		default_key: Variant, persist: int = Tune.Persist.TUNABLE,
		path: String = "") -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)

	Tune.bind(slug, default_key, {}, persist)  # register/upgrade so the accent is the class
	var mode := Tune.persist_of(slug)
	var refresh_marker := _add_label_and_marker(row, label_text, slug)

	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.tooltip_text = "Right-click: Pin / Reset" if mode == Tune.Persist.TUNABLE else "Right-click: Reset"
	# Selecting an item writes its stable key (metadata as string, else the item text) to
	# the slug — AUTOSAVE commits in the same gesture, exactly like a typed control.
	ob.item_selected.connect(func(i: int) -> void:
		_write(slug, _dropdown_key_at(ob, i), mode, path))
	_attach_context_menu(ob, slug, refresh_marker, mode, path)
	row.add_child(ob)
	return ob


## Select the populated item whose stable key matches the persisted slug value — called by
## the caller AFTER it fills the dropdown (the items don't exist at add_dropdown time). This
## is display-only (no item_selected re-emit, so it never re-writes the slug); the caller
## runs its own load using the RETURNED key. When the persisted key isn't among the current
## items (the DB changed, or nothing persisted yet), the selection is left as-is.
##
## The slug was registered by the paired `add_dropdown`, so this PULL-reads the persisted key
## via get_value (ADR-0068 R5). `default_key` remains a defensive fallback for the off-contract
## case of a resync before its add_dropdown — matching the old `of`, which registered+returned
## the default rather than asserting, since a hard crash on a debug panel is the wrong failure.
static func resync_dropdown(ob: OptionButton, slug: String, default_key: Variant) -> Variant:
	# `peek`, not `get_value`: painting the dropdown must not stamp the R8 pull-read clock,
	# or every dropdown row reads back as a consumed slug (Tune.consumer_state).
	var key: Variant = Tune.peek(slug) if Tune.is_registered(slug) else default_key
	var want := str(key)
	for i in ob.item_count:
		if _dropdown_key_at(ob, i) == want:
			ob.select(i)
			break
	return key


## The stable string key for row `i` of a dynamic dropdown: the item's metadata (stringified
## so an int id round-trips through JSON as a string) if one was stashed, else the item text.
static func _dropdown_key_at(ob: OptionButton, i: int) -> String:
	if i < 0 or i >= ob.item_count:
		return ""
	var md: Variant = ob.get_item_metadata(i)
	return str(md) if md != null else ob.get_item_text(i)


## Build the accent-colored `label_text` label plus the fixed-width dirty-marker slot for a
## row, returning a Callable that refreshes THIS row's marker. The marker lives in its OWN
## reserved slot (not appended to the label) so toggling " *" never reflows the label or
## shifts the control — the width is held whether or not the field is dirty. Shared by add()
## and add_dropdown() so both render the persistence-class accent + marker identically.
static func _add_label_and_marker(row: HBoxContainer, label_text: String, slug: String) -> Callable:
	# Stamp the slug on the row so a reader can walk a built panel and recover which slugs it
	# is a view onto (`PanelApplicability`). This is the ONE place every row shape passes
	# through — add(), add_dropdown(), and the unregistered-placeholder path — so a row that
	# renders is a row that is counted. Doing it at the three call sites instead would make
	# the placeholder path (the one that matters most, since it is the dead-row case) the
	# easiest to forget.
	row.set_meta(SLUG_META, slug)
	var accent := _accent_for(Tune.persist_of(slug))
	var label := Label.new()
	label.add_theme_color_override("font_color", accent)
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	var marker := Label.new()
	marker.add_theme_color_override("font_color", accent)
	marker.custom_minimum_size.x = 16
	row.add_child(marker)
	var refresh_marker := func() -> void: _refresh_marker(marker, slug)
	refresh_marker.call()
	return refresh_marker


## The label accent for a persistence class: grey for EPHEMERAL (session-only), green
## for AUTOSAVE (sticky), cyan for TUNABLE (Pin-to-keep). The single home for the
## color→class mapping.
static func _accent_for(mode: int) -> Color:
	match mode:
		Tune.Persist.EPHEMERAL: return EPHEMERAL_ACCENT
		Tune.Persist.AUTOSAVE: return AUTOSAVE_ACCENT
		_: return TUNABLE_ACCENT


## Build JUST the bound control for `slug` (no label/marker/row): the type-inferred
## widget + edit→set_value wiring + right-click Pin/Reset + the owner-scoped resync
## binding (auto-drops on tree-exit). This is the reusable core `add()` wraps with a
## label + marker; the registry page composes it into table columns. `on_change` (if
## valid) fires after every resync AND after a menu action, so a caller-owned marker
## can refresh. Returns null for a type with no widget yet.
static func build_control(slug: String, default_value: Variant, hint: Dictionary = {},
		on_change: Callable = Callable(), persist: int = Tune.Persist.TUNABLE,
		path: String = "") -> Control:
	var value: Variant = Tune.bind(slug, default_value, hint, persist)  # register/upgrade + coalesce
	var mode := Tune.persist_of(slug)  # EFFECTIVE mode (this call ⊔ any prior owner)
	var kind := _control_kind(default_value, hint)
	var control: Control = _make_control(kind, value, hint)
	if control == null:
		return null
	# Only a TUNABLE field has a Pin gesture; AUTOSAVE/EPHEMERAL are Reset-only.
	control.tooltip_text = "Right-click: Pin / Reset" if mode == Tune.Persist.TUNABLE else "Right-click: Reset"
	_connect_edit(control, slug, kind, mode, path)
	_attach_context_menu(control, slug, on_change, mode, path)
	# Resync the control (+ notify) whenever the slug changes anywhere — our own edit,
	# another panel, the registry, a boot-load. Owner-scoped to the control so the
	# binding auto-drops when it leaves the tree (Ctrl+R safe). Pass `persist` so this
	# bind never downgrades a slug the owner declared EPHEMERAL/AUTOSAVE.
	# as_view: TRUE. This subscription exists to repaint the widget, not to act on the value,
	# and counting it as a consumer would make every slug with a rendered control certify
	# itself as live — see Tune.consumer_state.
	Tune.bind_update(control, slug, default_value, func(v: Variant) -> void:
		_apply_to_control(control, v)
		if on_change.is_valid():
			on_change.call(), hint, persist, true)
	return control


## Wire the control's edit gesture to write through to Tune. Each widget reports its
## edit differently; all funnel to the one _write, which persists in-line for AUTOSAVE.
static func _connect_edit(control: Control, slug: String, kind: String, mode: int, path: String) -> void:
	if kind == "vector2" or kind == "vector3" or kind == "vector4" or kind == "rect2":
		# Any component moving writes the WHOLE recomposed vector/rect — the slug holds
		# one Vector2/3/4/Rect2, not per-axis slugs, so a scrub is atomic.
		var sbs := _vector_spinboxes(control)
		for sb: SpinBox in sbs:
			sb.value_changed.connect(func(_v: float) -> void:
				_write(slug, _vector_from_spinboxes(sbs, kind), mode, path))
	elif control is SpinBox:
		var is_int: bool = kind == "int"
		control.value_changed.connect(func(v: float) -> void:
			_write(slug, int(v) if is_int else v, mode, path))
	elif control is OptionButton:
		control.item_selected.connect(func(i: int) -> void:
			_write(slug, control.get_item_metadata(i), mode, path))
	elif control is CheckBox:
		control.toggled.connect(func(on: bool) -> void: _write(slug, on, mode, path))
	elif control is ColorPickerButton:
		control.color_changed.connect(func(c: Color) -> void: _write(slug, c, mode, path))
	elif control is LineEdit:
		# Commit on Enter or focus loss, not per keystroke.
		control.text_submitted.connect(func(t: String) -> void: _write(slug, t, mode, path))
		control.focus_exited.connect(func() -> void: _write(slug, control.text, mode, path))


## Write an edit through to Tune. For an AUTOSAVE slug the SAME gesture also commits it
## to the staging file (`path`), so the value sticks across reloads with no Pin; a
## TUNABLE slug just becomes a dirty override until pinned. EMPTY `path` means "whatever
## Tune's staging file is" — the repo file in the game, and NOTHING in a test process, which
## is what stops a panel-driving test persisting machine state mid-run (ADR-0281 / #1149).
## An explicit `path` is still honoured, and is the temp-file seam `TuneFieldTest` uses.
static func _write(slug: String, value: Variant, mode: int, path: String = "") -> void:
	Tune.set_value(slug, value)
	if mode == Tune.Persist.AUTOSAVE:
		Tune.commit_slug(slug, path)


## Push a coalesced value onto the control WITHOUT re-emitting its edit signal, so
## an external change (or our own write echoed back) never loops.
static func _apply_to_control(control: Control, value: Variant) -> void:
	if control is HBoxContainer:
		# A Vector2/3 control: push each component onto its spinbox without re-emitting.
		var sbs := _vector_spinboxes(control)
		var comps := _vector_components(value)
		for i in mini(sbs.size(), comps.size()):
			sbs[i].set_value_no_signal(float(comps[i]))
	elif control is SpinBox:
		control.set_value_no_signal(float(value))
	elif control is CheckBox:
		control.set_pressed_no_signal(bool(value))
	elif control is OptionButton:
		_select_enum_item(control, value)
	elif control is ColorPickerButton:
		# Guard equality so an echoed resync never loops (ColorPickerButton has no
		# set_color_no_signal); setting an unchanged color is a no-op either way.
		if control.color != value:
			control.color = value
	elif control is LineEdit:
		control.text = str(value)


## Show " *" in the reserved marker slot while `slug` is dirty (its live value is
## past the committed baseline), else leave it blank. The slot keeps its width
## either way, so the control never shifts.
static func _refresh_marker(marker: Label, slug: String) -> void:
	# Only a TUNABLE field carries the dirty cue — AUTOSAVE commits on every edit and
	# EPHEMERAL is never persisted, so neither has a meaningful "unsaved" state.
	var dirty := Tune.persist_of(slug) == Tune.Persist.TUNABLE and Tune.is_dirty(slug)
	marker.text = " *" if dirty else ""


## Build the scrub widget for the resolved `kind`. Unsupported types get a
## read-only value label (no guessed widget) — ADR-0068 open question. `value` is
## the coalesced live value to show; `hint` supplies range/enum. This is the single
## home for control construction, shared by add() and the Registry page.
static func _make_control(kind: String, value: Variant, hint: Dictionary) -> Control:
	var is_int: bool = kind == "int"
	match kind:
		"float", "int":
			return _make_scalar_spinbox(float(value), hint, is_int)
		"vector2", "vector3", "vector4", "rect2":
			# Per-component spinboxes (ADR-0068 decision 11): a Vector2/3/Rect2 has no
			# single widget, so lay its components out as clamped SpinBoxes sharing the
			# hint. Rect2 renders x,y,w,h in order — the ADR-0088 composite rect slug
			# (one slug ↔ one authored rect literal, R6/E1).
			var box := HBoxContainer.new()
			for c: float in _vector_components(value):
				var comp_sb := _make_scalar_spinbox(c, hint, false)
				comp_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				box.add_child(comp_sb)
			return box
		"enum":
			var ob := OptionButton.new()
			# hint.enum is label -> value; stash the value on each item so a
			# selection writes the underlying int, not the row index.
			for lbl: String in hint["enum"].keys():
				ob.add_item(lbl)
				ob.set_item_metadata(ob.item_count - 1, hint["enum"][lbl])
			_select_enum_item(ob, value)
			return ob
		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(value)
			return cb
		"color":
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(80, 24)
			cp.color = value
			return cp
		"string":
			var le := LineEdit.new()
			le.text = str(value)
			return le
		_:
			var lbl := Label.new()
			lbl.text = "%s (read-only)" % str(value)
			return lbl


## Resolve the control kind (ADR-0068 decision 11). An `enum` hint wins outright;
## otherwise inferred from the default's TYPE, free text reserved for String alone.
static func _control_kind(default_value: Variant, hint: Dictionary) -> String:
	if hint.has("enum"):
		return "enum"
	match typeof(default_value):
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "string"
		TYPE_COLOR: return "color"
		TYPE_VECTOR2: return "vector2"
		TYPE_VECTOR3: return "vector3"
		TYPE_VECTOR4: return "vector4"
		TYPE_RECT2: return "rect2"
		_: return "unsupported"


## Build one clamped SpinBox from a hint (ADR-0068 decision 11): range/step from the hint,
## permissive + un-clamped when the hint omits them so a generic tunable is never silently
## pinned. Shared by the scalar float/int control and each Vector2/3 component.
static func _make_scalar_spinbox(value: float, hint: Dictionary, is_int: bool) -> SpinBox:
	var sb := SpinBox.new()
	sb.step = float(hint.get("step", 1.0 if is_int else 0.01))
	if hint.has("min"):
		sb.min_value = float(hint["min"])
	else:
		sb.min_value = -1000000.0
		sb.allow_lesser = true
	if hint.has("max"):
		sb.max_value = float(hint["max"])
	else:
		sb.max_value = 1000000.0
		sb.allow_greater = true
	sb.value = value
	return sb


## The float components of a Vector2/3/4/Rect2 in order — the per-component
## spinbox values (Rect2 lays out x, y, w, h).
static func _vector_components(value: Variant) -> Array:
	if value is Rect2 or value is Rect2i:
		return [value.position.x, value.position.y, value.size.x, value.size.y]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is Vector3:
		return [value.x, value.y, value.z]
	var v: Vector2 = value
	return [v.x, v.y]


## Recompose a Vector2/3/4/Rect2 from its component spinboxes (the inverse of the
## layout). Four boxes is ambiguous — `kind` decides Vector4 vs the Rect2 x,y,w,h row.
static func _vector_from_spinboxes(sbs: Array, kind: String = "") -> Variant:
	if sbs.size() >= 4:
		if kind == "vector4":
			return Vector4(sbs[0].value, sbs[1].value, sbs[2].value, sbs[3].value)
		return Rect2(sbs[0].value, sbs[1].value, sbs[2].value, sbs[3].value)
	if sbs.size() >= 3:
		return Vector3(sbs[0].value, sbs[1].value, sbs[2].value)
	return Vector2(sbs[0].value, sbs[1].value)


## The component SpinBoxes of a Vector control, in layout order.
static func _vector_spinboxes(control: Control) -> Array:
	var out: Array = []
	for child in control.get_children():
		if child is SpinBox:
			out.append(child)
	return out


## Wire right-click on the control to its per-field menu. SpinBox (and LineEdit)
## embed a LineEdit with its OWN right-click menu — disable it so ours wins, and
## listen on that inner LineEdit since it consumes the click before the SpinBox.
## A Vector2/3 is an HBox of component SpinBoxes (one slug, no monolithic widget),
## so wire each component: a right-click on any axis pops the same field menu, and
## each inner LineEdit's default menu is suppressed (else it leaks through).
## The gesture routing is not unit-testable headless (verify in the sandbox); the
## menu LOGIC is covered directly via _build_context_menu / _context_action.
static func _attach_context_menu(control: Control, slug: String, on_changed: Callable,
		mode: int = Tune.Persist.TUNABLE, path: String = "") -> void:
	var components := _vector_spinboxes(control)
	if not components.is_empty():
		for sb: SpinBox in components:
			_attach_context_menu(sb, slug, on_changed, mode, path)
		return
	var src: Control = control
	if control is SpinBox:
		src = control.get_line_edit()
	if src is LineEdit:
		src.context_menu_enabled = false
	src.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			src.accept_event()
			_popup_context_menu(control, slug, on_changed, mode, path))


## Build the per-field action menu for `slug`. ONLY a TUNABLE field offers Pin (disabled
## unless dirty) — an AUTOSAVE field already persisted every edit and an EPHEMERAL field
## is never persisted, so both are Reset-only. Reset is always available (a no-op clear
## is safe). `on_changed` (optional) fires after an action so the row can refresh its
## marker. Returned un-popped so it is unit-testable (see TuneFieldTest).
static func _build_context_menu(slug: String, on_changed: Callable = Callable(),
		mode: int = Tune.Persist.TUNABLE, path: String = "") -> PopupMenu:
	var menu := PopupMenu.new()
	if mode == Tune.Persist.TUNABLE:
		menu.add_item("Pin (commit this value)", Action.PIN)
		menu.set_item_disabled(menu.get_item_index(Action.PIN), not Tune.is_dirty(slug))
	menu.add_item("Reset to default", Action.RESET)
	menu.id_pressed.connect(func(id: int) -> void: _context_action(slug, id, on_changed, path, mode))
	return menu


## Pop the menu at the cursor. PopupMenu is a native OS window (project.godot
## embed_subwindows=false), so it positions in ABSOLUTE SCREEN coords —
## DisplayServer.mouse_get_position(), not a viewport-space global-mouse (which
## stretch/mode=viewport also scales), or the menu lands nowhere near the cursor.
static func _popup_context_menu(host: Control, slug: String, on_changed: Callable,
		mode: int = Tune.Persist.TUNABLE, path: String = "") -> void:
	var menu := _build_context_menu(slug, on_changed, mode, path)
	host.add_child(menu)
	menu.popup_hide.connect(menu.queue_free)
	menu.popup(Rect2i(DisplayServer.mouse_get_position(), Vector2i.ZERO))


## Apply a right-click action to `slug`. Pin persists just this slug (per-field
## commit); Reset clears its override. `path` is a test seam — production calls use
## the real staging file. Pin does not emit value_changed, so `on_changed` is the
## hook that refreshes the marker; Reset's value_changed already resyncs the row.
static func _context_action(slug: String, action: int, on_changed: Callable = Callable(),
		path: String = "", mode: int = Tune.Persist.TUNABLE) -> void:
	match action:
		Action.PIN:
			Tune.commit_slug(slug, path)
		Action.RESET:
			Tune.clear(slug)
			# An AUTOSAVE reset must also UN-persist, or the old value reloads next boot.
			if mode == Tune.Persist.AUTOSAVE:
				Tune.commit_slug(slug, path)
	if on_changed.is_valid():
		on_changed.call()


## Select the OptionButton row whose stashed value equals `value` (enum coalesces
## to its int, so match on the metadata).
static func _select_enum_item(ob: OptionButton, value: Variant) -> void:
	for i in ob.item_count:
		if ob.get_item_metadata(i) == value:
			ob.select(i)
			return
