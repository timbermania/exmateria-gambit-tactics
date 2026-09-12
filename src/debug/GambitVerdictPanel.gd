extends BaseDebugPanel

## F3 readout for the kernel's per-slot VERDICT, over ANY battle (#1211).
##
## Renders one line per unit — the three fields a verdict cannot answer — and, for the WATCHED
## unit, every slot's decoded verdict beneath it. That pairing is the point: the verdict says
## which slot committed and why the others declined, and it says NOTHING about what happened to
## `U_TARGET` afterwards. A target rewritten downstream of the decision is invisible to the
## verdict alone, so the two are read together or not at all.
##
## === WHY IT IS ITS OWN PANEL ===============================================================
##
## Until #1211 this block lived inside [GambitLabPanel] and could therefore only be read in a
## scene with no deployment, no roster and no turn order. `GambitVerdictReader` had exactly two
## consumers in the tree and both were the lab. Hoisted, it renders a [GambitVerdictProbe]'s rows
## — so the lab reads its synthesized cell and [GambitBattle] reads the battle you are playing,
## through ONE renderer over ONE instrument.
##
## Pure VIEW on ADR-0069's split: the host owns the battle and answers [code]verdict_state()[/code]
## (`{rows, watched}`) plus the probe. This panel never reaches into the host.
##
## === WHAT IT REFUSES TO DRAW BLANK =========================================================
##
## `VERDICT_NONE == 0` is a real answer — *this call did not reach this slot* — and a readout
## that draws it as an empty cell says "no reason", which is the one failure mode ADR-0275
## dec. 18 says a debugging instrument must not have. Every slot is drawn, including the ones
## that never moved.
##
## A slot's verdict is also only as fresh as the last evaluation that WALKED it: `clear_verdict`
## is scoped to `max_slot` and the movement re-evaluation path passes `current_gambit`, so a unit
## mid-move deliberately keeps the executing slot's verdict. A panel polling every tick shows
## exactly that, and it is CORRECT.

const DIM := Color(0.60, 0.60, 0.64)
const COOL := Color(0.62, 0.80, 1.0)
const BRIGHT := Color(0.86, 0.86, 0.9)

var _host = null
var _box: VBoxContainer = null
var _head: Label = null


func setup(host, title: String = "Gambit verdict") -> void:
	_host = host
	panel_title = title
	panel_category = Category.SIMULATION
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 0)
	vbox.add_theme_constant_override("separation", 4)
	add_child(vbox)
	add_section_title(vbox, title)
	_head = Label.new()
	_head.add_theme_color_override("font_color", DIM)
	vbox.add_child(_head)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_box)


func _process(_delta: float) -> void:
	# POLLED, not pushed. A battle host ticks its own clock and has no "the readout should
	# refresh now" moment to emit — and an instrument that only updated when the host remembered
	# to tell it would go stale exactly when the battle got interesting. The lab pushes instead
	# (it is lockstep, so its ticks ARE the refresh), and `render` takes both.
	if _host != null and is_instance_valid(_host) and _host.has_method("verdict_state"):
		render(_host.verdict_state())


## Draw one frame from `{rows, watched, note}`.
func render(state: Dictionary) -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	var rows: Array = state.get("rows", [])
	_head.text = String(state.get("note", ""))
	if rows.is_empty():
		_box.add_child(_line("(no battle sampled yet)", DIM))
		return
	var probe: GambitVerdictProbe = state.get("probe", null)
	if probe == null:
		_box.add_child(_line("(no verdict probe bound — the layout failed to load)", DIM))
		return
	var watched: int = int(state.get("watched", 0))
	for r in rows:
		var is_watched: bool = int(r["unit"]) == watched
		_box.add_child(_line("%s%s  %s  target=%s  reason=%s  slot=%d  hp=%d  (%d,%d)" % [
			"> " if is_watched else "  ", r["name"],
			probe.state_name(int(r["state"])), probe.unit_name(int(r["target"])),
			probe.reason_name(int(r["reason"])), int(r["gambit"]), int(r["hp"]),
			int(r["x"]), int(r["z"])], COOL if is_watched else DIM))
		if not is_watched:
			continue
		var slots: Array = r["slots"]
		for s in range(slots.size()):
			# The ADR-0048 net renders as its own row, DIM and labelled, at slot index
			# `MAX_USER_GAMBITS` — derived, never a literal 5 (dec. 19 / ADR-0270). Suppressing
			# it would make the readout describe a battle that does not exist.
			var net: bool = probe.is_safety_net_slot(s)
			_box.add_child(_line("      slot %d%s  %s" % [
				s, "  [safety net]" if net else "", probe.reader.format(slots[s])],
				DIM if net else BRIGHT))


func _line(text: String, col: Color) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", 12)
	return l
