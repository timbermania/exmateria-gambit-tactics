extends Node3D

## PROTOTYPE DRIVER — THROWAWAY. See `tools/ProtoGambitRow.gd` for the question.
##
## Two modes, one scene:
##
##   LIVE (default) — a window opens, you drive it. ←/→ walk the parts of the focused row,
##   ↑/↓ change row, ○ opens the focused part's list (or toggles the enable flag), ✕ closes
##   the list / quits, Q and E (L1/R1) raise and lower the focused slot. Every press prints
##   the whole row state, so the transcript says what the screen said.
##
##     godot --path . res://tools/proto_gambit_row.tscn
##     godot --path . res://tools/proto_gambit_row.tscn -- --chevron   (the 10-px cursor)
##
##   FILMSTRIP — self-drives a fixed press sequence and saves one PNG per beat, so the layout
##   can be LOOKED AT rather than reasoned about:
##
##     godot --path . res://tools/proto_gambit_row.tscn -- --shots=/tmp/protorow
##
## The rows are seeded with the WORST-CASE real strings the shipped surface can produce
## (`GambitSurface._target_choices` / `_condition_choices`, plus the widest ability name in
## `assets/abilities/effects.json`), because a layout question answered against short strings
## is answered against a fixture.

const ProtoGambitRow = preload("res://tools/ProtoGambitRow.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")

## The real option vocabularies, lifted verbatim from the shipped surface.
const TARGETS := ["Self", "Them", "Nearest Foe", "Weakest Foe", "Nearest Ally", "Weakest Ally"]
## POST-GATE (ADR-0268 dec. 8). `In Melee Range` / `In Spell Range` are
## `GambitCondition.Type.TARGET_IN_RANGE`, which is in `GambitEncoder.UNSUPPORTED_CONDITION_TYPES`
## — the encoder skips a gambit carrying one, so the screen must not offer it. Dropping them
## takes the widest `If` string from 58 px to 48, and that 10 px is exactly what pays for the
## part chevron.
const CONDITIONS := ["Always", "HP < 25%", "HP < 50%", "HP > 50%", "MP < 50%"]
const ACTIONS := ["Attack", "Move", "Wait", "Cure", "Fire", "Secret Fist", "DragonPowerUp"]

var _row_menu: ProtoGambitRow
var _popup: Node3D
var _popup_entries: Array[String] = []
var _popup_row: int = 0
var _shots_dir: String = ""
var _frame: int = 0
var _beat: int = 0
var _script: Array = []
var _pending_shot: String = ""


func _ready() -> void:
	var chevron := false
	var glove := false
	for a in OS.get_cmdline_user_args():
		if a == "--chevron":
			chevron = true
		elif a == "--partglove":
			glove = true
		elif a.begins_with("--shots="):
			_shots_dir = a.substr("--shots=".length())

	_row_menu = ProtoGambitRow.new()
	_row_menu.name = "ProtoGambitRow"
	_row_menu.chevron_cursor = chevron
	_row_menu.part_glove = glove
	# Four slots as a player would actually author them, plus one carrying a second condition
	# the row cannot show — dec. 3's `+N` case, seeded so the affordance is looked at and not
	# imagined. Slot 3 is DISABLED, so the off state of the leftmost part is on screen too.
	_row_menu.rows = [
		{"enabled": true, "do": "DragonPowerUp", "to": "Weakest Foe", "iff": "HP < 25%", "extra": 0},
		{"enabled": true, "do": "Cure", "to": "Weakest Ally", "iff": "HP < 50%", "extra": 1},
		{"enabled": false, "do": "DeathSentence", "to": "Nearest Foe", "iff": "MP < 50%", "extra": 0},
		{"enabled": true, "do": "Attack", "to": "Nearest Foe", "iff": "Always", "extra": 0},
	]
	add_child(_row_menu)
	_row_menu.chosen.connect(_open_list)

	_report("boot")
	if _shots_dir != "":
		_script = [
			["", "01-open"],
			["right", "02-part-to"], ["right", "03-part-if"],
			["accept", "04-if-list-open"], ["down", "05-if-list-move"], ["accept", "06-if-landed"],
			["down", "07-row-2"], ["left", "08-part-to"], ["left", "09-part-do"],
			["left", "10-part-enable"], ["accept", "11-toggled-off"],
			["e", "12-lowered"], ["q", "13-raised"],
		]
		RenderingServer.frame_post_draw.connect(_on_post_draw)


# -----------------------------------------------------------------------------
# LIVE input. `rotate_camera_cw` / `_ccw` are reached AS ACTIONS (dec. 6) — the prototype
# proves the re-meaning works through the existing actions, which is the half of ADR-0268
# that decides whether any InputMap row is needed at all.
# -----------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	if _popup != null:
		if event.is_action_pressed("ui_up"):
			_popup_move(-1)
		elif event.is_action_pressed("ui_down"):
			_popup_move(1)
		elif event.is_action_pressed("ui_accept"):
			_popup_take()
		elif event.is_action_pressed("ui_cancel"):
			_popup_close("cancelled")
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_press("left")
	elif event.is_action_pressed("ui_right"):
		_press("right")
	elif event.is_action_pressed("ui_up"):
		_press("up")
	elif event.is_action_pressed("ui_down"):
		_press("down")
	elif event.is_action_pressed("ui_accept"):
		_press("accept")
	elif event.is_action_pressed("rotate_camera_ccw"):
		_press("e")
	elif event.is_action_pressed("rotate_camera_cw"):
		_press("q")
	elif event.is_action_pressed("ui_cancel"):
		print("[proto] ✕ — quitting")
		get_tree().quit()
	else:
		return
	get_viewport().set_input_as_handled()


func _press(what: String) -> void:
	match what:
		"left": _row_menu.move_part(-1)
		"right": _row_menu.move_part(1)
		"up": _row_menu.move_row(-1)
		"down": _row_menu.move_row(1)
		"accept": _row_menu.confirm()
		"q": _row_menu.reorder(-1)
		"e": _row_menu.reorder(1)
	_report(what)


# -----------------------------------------------------------------------------
# The part's own list, opened UNDER ITS OWN COLUMN (dec. 1) — which is the half of the
# grammar a static mock cannot show: whether a list hung off column x still reads as
# belonging to that part with the row legible behind it.
# -----------------------------------------------------------------------------
func _open_list(row: int, part: int) -> void:
	_popup_entries = []
	match part:
		ProtoGambitRow.Part.DO: _popup_entries.assign(ACTIONS)
		ProtoGambitRow.Part.TO: _popup_entries.assign(TARGETS)
		_: _popup_entries.assign(CONDITIONS)
	_popup_row = 0
	_popup = _build_popup(float(ProtoGambitRow.COL_X[part]))
	# IN THE TREE FIRST, THEN PAINTED. `UI3Element` adopts its spec in `_enter_tree`, so
	# `rel_world`/`z_for` off a detached element answer from an unadopted rect — which mounts
	# the glyphs somewhere that is not the box. The first cut did that and photographed an
	# EMPTY list with a perfectly drawn frame, which is the failure mode ADR-0244 says only a
	# screenshot can catch.
	add_child(_popup)
	var elem0: UI3Element = _popup.get_meta("elem")
	elem0.open()
	_repaint_popup()
	print("[proto] ○ opens the %s list under x=%.0f: %s"
		% [ProtoGambitRow.Part.keys()[part], float(ProtoGambitRow.COL_X[part]), str(_popup_entries)])


## A bare list in its own box. No glove and no box-open: the prototype is asking where the
## list LANDS, not what its cadence is, and the shipped [GambitSurfaceMenu] already owns both.
func _build_popup(col_x: float) -> Node3D:
	var text := UIMenuText.new()
	var w := 8.0
	for e in _popup_entries:
		w = maxf(w, text.measure(e))
	var width := w + 26.0
	# Clamp to the 256-px frame — a list hung off the LAST column would otherwise run off it,
	# which is the first thing this variant has to survive.
	var x := minf(col_x - 6.0, 252.0 - width)
	var h := _popup_entries.size() * 16.0 + 16.0
	var y := maxf(8.0, 132.0 - h)
	var elem := UI3Element.new({
		"id": "protogambitrow.list",
		"rect": Rect2(x, y, width, h),
		"authored_home": Vector2(x, y),
		"transition": UI3Element.Transition.BOX_OPEN,
		"frame": UI3Element.Frame.STRIPE,
		"frame_center_patch": Vector4(6, 7, 21, 17),
		"frame_rp": 56,
		"clip": UI3Element.Clip.OWN_APERTURE,
		"aperture_pad": Vector4(0, 0, 0, 0),
		"depth_rung": -7,
		"open_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
		"close_cadence": UI3BoxOpenBeat.Cadence.DEFAULT,
	})
	# The text goes into a CHILD element, never into the frame-bearing window itself: a repaint
	# frees its host's children, and the window's chrome IS one of them. Painted straight onto
	# the window, the second repaint deleted the frame and left the glyphs floating on the void
	# — again, only the screenshot said so.
	var rows_elem := UI3Element.new({
		"id": "protogambitrow.list.rows",
		"rect": Rect2(x, y + 8.0, width, h - 8.0),
		"authored_home": Vector2(x + 4.0, y + 10.0),
		"transition": UI3Element.Transition.RIDE_PARENT,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.PARENT_APERTURE,
	})
	elem.add_child(rows_elem)
	var holder := Node3D.new()
	holder.name = "ProtoChoiceList"
	holder.add_child(elem)
	holder.set_meta("elem", elem)
	holder.set_meta("rows", rows_elem)
	holder.set_meta("x", x)
	holder.set_meta("y", y)
	return holder


func _repaint_popup() -> void:
	var rows_elem: UI3Element = _popup.get_meta("rows")
	for c in rows_elem.get_children():
		c.free()
	var text := UIMenuText.new()
	var x := float(_popup.get_meta("x")) + 4.0
	var y := float(_popup.get_meta("y")) + 10.0
	for i in range(_popup_entries.size()):
		var marker := "→" if i == _popup_row else "  "
		var line: String = marker + _popup_entries[i]
		text.mount(rows_elem, line, rows_elem.rel_world(x, y + i * 16.0) + rows_elem.z_for(59),
			59, rows_elem.ppu(), null,
			ProtoGambitRow.LIT_INKS if i == _popup_row else ProtoGambitRow.DIM_INKS)


func _popup_move(step: int) -> void:
	_popup_row = (_popup_row + step + _popup_entries.size()) % _popup_entries.size()
	_repaint_popup()
	print("[proto]   list -> %s" % _popup_entries[_popup_row])


func _popup_take() -> void:
	_row_menu.set_value(_row_menu.row(), _row_menu.part(), _popup_entries[_popup_row])
	_popup_close("took '%s'" % _popup_entries[_popup_row])


func _popup_close(why: String) -> void:
	_popup.queue_free()
	_popup = null
	_report("list %s" % why)


# -----------------------------------------------------------------------------
# Reporting + the filmstrip.
# -----------------------------------------------------------------------------
func _report(why: String) -> void:
	var lines: Array[String] = []
	for i in range(_row_menu.rows.size()):
		var mark := ">" if i == _row_menu.row() else " "
		lines.append("%s %d. %s" % [mark, i + 1, _row_menu.row_text(i)])
	print("[proto] %s | focus row=%d part=%s | right edge %.0f px of 256"
		% [why, _row_menu.row() + 1, ProtoGambitRow.Part.keys()[_row_menu.part()],
			_row_menu.measured_right_edge])
	for l in lines:
		print("[proto]   " + l)


func _on_post_draw() -> void:
	_frame += 1
	# A beat is 16 frames: press on the first, photograph on the twelfth. Split rather than
	# awaited inside the callback, so the shot is of a SETTLED window (the box-open and the
	# glove's select-bob both run out inside the gap) and not of one mid-cadence.
	var phase := _frame % 16
	if phase == 1:
		if _beat >= _script.size():
			print("[proto] filmstrip done -> %s" % _shots_dir)
			get_tree().quit()
			return
		var step: Array = _script[_beat]
		_beat += 1
		var key := String(step[0])
		_pending_shot = String(step[1])
		if key == "":
			return
		if _popup != null:
			match key:
				"down": _popup_move(1)
				"up": _popup_move(-1)
				"accept": _popup_take()
				"cancel": _popup_close("cancelled")
		else:
			_press(key)
	elif phase == 12 and _pending_shot != "":
		var path := "%s/%s.png" % [_shots_dir, _pending_shot]
		get_viewport().get_texture().get_image().save_png(path)
		print("[proto] shot %s" % path)
		_pending_shot = ""
