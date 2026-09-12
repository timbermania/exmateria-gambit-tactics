extends BaseDebugPanel
## F3 readout for the GAMBIT LAB's live arm ([GambitLabScene], ADR-0275 dec. 13, issue #1128).
##
## Renders the kernel's per-slot VERDICT for the watched actor, beside the three unit fields
## the verdict cannot answer. That pairing is the point: the verdict says which slot committed
## and why the others declined, and it says NOTHING about what happened to `U_TARGET`
## afterwards. A target rewritten downstream of the decision — the shape the `:676` XFAIL
## suspects — is invisible to the verdict alone, so the two are read together or not at all.
##
## Pure VIEW, on ADR-0069's split: the host owns the battle, the corpus and the drive; this
## panel renders the dict the host hands it and calls back for the four verbs. It never
## reaches into the host's state.
##
## === WHAT IT REFUSES TO RENDER BLANK =======================================================
##
## `VERDICT_NONE == 0` is a real answer — *this call did not reach this slot* — and a readout
## that draws it as an empty cell says "no reason", which is the one failure mode dec. 18 says
## a debugging instrument must not have. [GambitVerdictReader] renders it `NONE(not walked)`
## and every slot is drawn, including the ones that never moved.
##
## A slot's verdict is also only as fresh as the last evaluation that WALKED it: `clear_verdict`
## is scoped to `max_slot` and the movement re-evaluation path passes `current_gambit`, so a
## unit mid-move deliberately keeps the executing slot's verdict. A panel polling every tick
## shows exactly that, and it is CORRECT.
##
## === THE SAFETY NET IS A ROW, DIM AND LABELLED =============================================
##
## dec. 19 / ADR-0270. The ADR-0048 net fires in the lab as it fires in a battle; suppressing
## it would make the lab debug a battle that does not exist. It is drawn dim with a
## `[safety net]` tag at slot index `MAX_USER_GAMBITS` — derived from the host, never a
## literal 5.
##
## Controls are Buttons and Labels only. ADR-0068's `TuneField` door is for value-holding
## fields, and this panel holds no value of its own: everything on it is either a verb
## belonging to the host or a number read off the GPU this tick.

var _host = null
var _status: Label = null
var _fixture: Label = null
var _units_box: VBoxContainer = null
var _legend: Label = null
var _xfail: Label = null
var _cell: Label = null
var _verdict = null

const VerdictPanelScript = preload("res://src/debug/GambitVerdictPanel.gd")

const DIM := Color(0.60, 0.60, 0.64)
const HOT := Color(1.0, 0.82, 0.35)
const COOL := Color(0.62, 0.80, 1.0)


func setup(host) -> void:
	_host = host
	panel_title = "Gambit Lab"
	panel_category = Category.SIMULATION
	_build_ui()


func _build_ui() -> void:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 0)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)

	add_section_title(vbox, "Gambit Lab — live arm")

	_fixture = Label.new()
	_fixture.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fixture.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_fixture)

	_status = Label.new()
	vbox.add_child(_status)

	var row = add_button_row(vbox)
	_verb(row, "Step", func(): _host.step_one())
	_verb(row, "Run/Pause", func(): _host.toggle_running())
	_verb(row, "Reboot", func(): _host.boot_index(_host.lab_state()["index"]))

	var row2 = add_button_row(vbox)
	_verb(row2, "< Prev", func(): _host.boot_index(_host.lab_state()["index"] - 1))
	_verb(row2, "Next >", func(): _host.boot_index(_host.lab_state()["index"] + 1))
	# ONE corpus, fixtures then synthesized cells, so the only extra verb the fold needs is a
	# jump: 84 presses of `N` is not a way to reach the cells (#1129, ADR-0275 decs. 1/2/8-12).
	_verb(row2, "Cells >", func(): _host.boot_index(_host.first_cell_index()))
	_verb(row2, "Gambit surface", func(): _host.open_surface())

	# THE SCRATCH CELL's verbs (#1210). Buttons as well as keys because the mouse is the one
	# input ADR-0137's wholesale pad claim leaves alone — with a screen up over the battlefield
	# these still work when the keys do not.
	var row3 = add_button_row(vbox)
	_verb(row3, "Fork → scratch", func(): _host.fork_into_scratch())
	_verb(row3, "Scratch", func(): _host.boot_index(_host.scratch_index()))
	_verb(row3, "+ Ally", func(): _host.scratch_add_unit(0))
	_verb(row3, "+ Foe", func(): _host.scratch_add_unit(1))
	_verb(row3, "Delete", func(): _host.scratch_delete_unit())
	_verb(row3, "Move watched", func(): _host.scratch_move_watched())
	_verb(row3, "Job", func(): _host.scratch_cycle_job())

	add_separator(vbox)

	# The CELL block — the axis it straddles, its refusal if it has one, and the score of its
	# prediction. Empty (and hidden) on a hand-authored fixture, which has none of the three.
	_cell = Label.new()
	_cell.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cell.custom_minimum_size = Vector2(520, 0)
	vbox.add_child(_cell)

	add_separator(vbox)

	_xfail = Label.new()
	_xfail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xfail.custom_minimum_size = Vector2(520, 0)
	_xfail.add_theme_color_override("font_color", HOT)
	vbox.add_child(_xfail)

	add_separator(vbox)

	_units_box = VBoxContainer.new()
	_units_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_units_box)

	add_separator(vbox)
	_legend = Label.new()
	_legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legend.custom_minimum_size = Vector2(520, 0)
	_legend.add_theme_color_override("font_color", DIM)
	_legend.text = ("range overlay: near tiles = weapon reach, far tiles = move reach."
		+ "  keys: SPACE step · ENTER run/pause · R reboot · N/B corpus entry · TAB watch"
		+ " · F fork into the scratch cell · 1/2 add ally/foe · X delete · M move · J job"
		+ " · V schematic/sprites · G gambit surface · BACKSPACE close it."
		+ "  While a screen is up the pad is the SCREEN's and the pump is paused (ADR-0137/0037)"
		+ " — F3 stays exempt, so this readout is what you read the list against.")
	vbox.add_child(_legend)


func _verb(row, text: String, fn: Callable) -> void:
	var b = Button.new()
	b.text = text
	b.pressed.connect(func():
		if _host:
			fn.call())
	row.add_child(b)


## Draw one frame of the host's state. Called on every tick the lab steps.
func render(state: Dictionary) -> void:
	if _fixture == null:
		return
	_fixture.text = "%s   [%d/%d %s]   map %s" % [
		state.get("scenario", "?"), int(state.get("index", 0)) + 1,
		int(state.get("count", 0)),
		_kind_of(state), state.get("map", "?")]
	_render_cell(state)
	_status.text = "tick %d   %s   view %s   watching %s%s" % [
		int(state.get("tick", 0)),
		"RUNNING" if state.get("running", false) else "paused",
		"schematic" if state.get("schematic", true) else "sprites",
		_watched_name(state),
		"   [surface open]" if state.get("surface_open", false) else ""]

	var xf: Array = state.get("xfail", [])
	if xf.is_empty():
		_xfail.text = ""
		_xfail.visible = false
	else:
		_xfail.visible = true
		_xfail.text = "XFAIL: %s\n%s" % [", ".join(PackedStringArray(xf)),
			state.get("xfail_reason", "")]

	_render_units(state)


## Which of the corpus's three populations this entry belongs to. SCRATCH is checked first: it
## sits past `fixture_count` like the cells do, so a plain "is it a cell" test would call it one.
func _kind_of(state: Dictionary) -> String:
	if state.get("is_scratch", false):
		return "SCRATCH — yours"
	return "cell" if state.get("is_cell", false) else "fixture"


## The synthesized cell's own three lines, or nothing at all on a fixture (ADR-0275 decs. 1/2/10).
##
## A REFUSED cell gets the refusal and nothing else — it booted no battle, so a score or an axis
## knob here would be describing an experiment that was never run. dec. 10's whole position is
## that the refusal IS the product, so it is drawn in the HOT colour rather than greyed away.
func _render_cell(state: Dictionary) -> void:
	if _cell == null:
		return
	if state.get("is_scratch", false):
		_cell.visible = true
		_cell.add_theme_color_override("font_color", COOL)
		_cell.text = ("THE SCRATCH CELL — edit it. Cursor to a tile, then: 1 add ally · "
			+ "2 add foe · X delete · M move the watched unit here · J cycle its job · "
			+ "G write its gambits. Every roster edit RE-BOOTS (the GPU sizes the battle's "
			+ "buffers at boot), so the cell restarts at tick 0. Nothing is saved — it dies "
			+ "with the process (ADR-0275 dec. 17).")
		return
	if not state.get("is_cell", false):
		_cell.text = ""
		_cell.visible = false
		return
	_cell.visible = true
	if state.get("cell_refused", false):
		_cell.add_theme_color_override("font_color", HOT)
		var notes: Array = state.get("cell_notes", [])
		_cell.text = "REFUSED, and never nudged (dec. 10):\n%s%s" % [
			state.get("cell_refusal", "?"),
			("\n| " + "\n| ".join(PackedStringArray(notes))) if not notes.is_empty() else ""]
		return
	var ax: Dictionary = state.get("cell_axis", {})
	var lines: Array = ["axis %s  ci=%s  knob %s=%s" % [
		ax.get("opcode_name", "?"), str(ax.get("condition_index", "-")),
		ax.get("knob", "-"), str(ax.get("knob_value", "-"))]]
	if String(ax.get("predicate", "")) != "":
		lines.append(String(ax.get("predicate", "")))
	if String(ax.get("measures", "")) != "":
		lines.append("int B measures: %s" % ax.get("measures", ""))
	for e in state.get("cell_expect", []):
		lines.append("predicts slot %s %s — %s" % [
			str(e.get("slot", "?")), str(e.get("p1", "?")), e.get("why", "")])
	var sc: Dictionary = state.get("cell_score", {})
	if sc.is_empty():
		lines.append("NOT SCORED YET — step until the actor is first evaluated.")
		_cell.add_theme_color_override("font_color", DIM)
	elif not bool(sc.get("scored", false)):
		lines.append("🔴 NO VERDICT — the actor has not been evaluated yet. A blind run, not a "
			+ "failed prediction.")
		_cell.add_theme_color_override("font_color", HOT)
	else:
		lines.append("scored at tick %d — %d predicted field-sets held, %d did not."
			% [int(sc.get("tick", -1)), int(sc.get("pass", 0)), int(sc.get("fail", 0))])
		_cell.add_theme_color_override("font_color",
			HOT if int(sc.get("fail", 0)) > 0 else COOL)
	_cell.text = "\n".join(PackedStringArray(lines))


func _watched_name(state: Dictionary) -> String:
	var rows: Array = state.get("rows", [])
	var w: int = int(state.get("watched", 0))
	for r in rows:
		if int(r["unit"]) == w:
			return String(r["name"])
	return "u%d" % w


## The per-unit verdict block. Rendered by [GambitVerdictPanel], NOT by this panel, since #1211:
## that renderer is shared with [GambitBattle], and two renderers of the same ints that could
## disagree about what they mean is the defect the hoist exists to make impossible. This panel
## still owns the corpus, the cell and the drive — the things only a LAB has.
func _render_units(state: Dictionary) -> void:
	if _verdict == null:
		_verdict = VerdictPanelScript.new()
		_verdict.setup(_host)
		# It is a CHILD here rather than a second F3 card: the lab reads the verdict against the
		# fixture and the drive state, and splitting them across two cards would put the two
		# halves of one reading in two places. `GambitBattle` registers it as its own card,
		# because there it IS the whole instrument.
		_verdict.set_process(false)   # the LAB pushes — it is lockstep, so its ticks are the refresh
		_units_box.add_child(_verdict)
	_verdict.render(state)


func _line(text: String, col: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 12)
	return l
