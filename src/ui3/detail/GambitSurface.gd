class_name GambitSurface
extends Node3D

## The GAMBIT SURFACE — where a unit's gambit list is read and edited, given a home on the ui3
## formation screen (#1007, ADR-0255).
##
## Reached as [constant FormationDetailTransition.State.GAMBIT] from the "Gambit" row of the
## adjustment action menu ([constant StartActionMenu.ROWS_ADJUST]), which the coordinator
## dispatches BY NAME. Its lifetime is the coordinator's; its writes are the player's edits.
##
## === THE ROW IS THE SENTENCE, READ ACROSS ===================================================
##
## ONE row per gambit slot, four parts side by side: **Enable · Do · To · If**. ↑/↓ pick the
## slot, ←/→ walk that row's parts, ○ opens the focused part's list UNDER ITS OWN COLUMN with
## the row still legible behind it, and L1/R1 raise and lower the slot.
##
## The `Do` list is TWO deep: its skillset rows drill into that skillset's ability names, in the
## same column and the same widget (see [method _skillset_rows]). Three levels of list, then —
## ROW, CHOICE, ABILITY — and [GambitSurfaceMenu] serves all of them, once in its column mode
## and twice as a plain list.
##
## ADR-0268 dec. 1 supersedes ADR-0255's SLOT → PART → CHOICE drill. A drill-down shows one
## gambit's one part at a time, and a gambit list is read by COMPARING rows: slot order **is**
## priority (rule A1), so "what does this unit do first, and when does it stop doing that" is a
## question about the list and not about a slot. The middle level is gone because it was a
## screen showing one slot's four parts — which is what the row now shows for four slots at once.
##
## === A PART IS EDITED, NOT A FIELD ==========================================================
##
## A [Gambit] is a struct of an `ActionKind`, an `ability_id` and two [TargetSelector]s each
## carrying a pool type, a team filter, a role filter and a resolution strategy. Exposing those
## as fields would be a five-dropdown form over a cross-product most of whose cells are
## nonsense — "Self, filtered to enemies, resolved by lowest stat" is reachable and means
## nothing. So each part offers a curated set of NAMED choices, and each choice is a whole
## value built by the domain's own constructors — ADR-0255 dec. 3, preserved verbatim by the
## row shape, because dec. 3's objection was to raw enum FIELDS and not to width.
##
## The catalogues live in [GambitOptions], not here, so the E1 round-trip gate (dec. 8) can ask
## for them without booting a screen. Every choice this surface offers encodes without a skip,
## and `GambitEncoderTest` is what says so.
##
## `Subject` IS a part (ADR-0283 dec. 1). It is a two-way switch — `My` / `Their` — and not the
## full pool selector ADR-0268 dec. 2 priced out at 68 px: the ally/foe and nearest/weakest axes
## are already on the `To` column one place left, so the switch adds an axis rather than a second
## spelling of one. `Their` is a COPY of the gambit's own aim, which is what makes
## `cond_target_type == action_target_type` and puts the kernel's rank walk in reach.
##
## The cost is that not every legal Gambit is reachable here, and that is the intended trade —
## the reachable set is the set a player can read back off the row. The mutation operators
## (#895) author into the same list without going through this screen, so the generator is not
## bounded by the choices offered here; a slot they gave more than one condition renders a `+N`
## and SAVES what it cannot show (dec. 3).
##
## === EDITS ARE EAGER ========================================================================
##
## Every choice writes into `Character.gambits` the instant it is picked, exactly as the Equip /
## Ability / Change-Job flows write straight through to the [Character] (ADR-0005, ADR-0252).
## The undo is the adjustment turn's pre-turn image, not a staged overlay here — staging would
## fork the formation screen, which #894 forbids.
##
## === THE LAST ROW IS THE SAFETY NET, AND IT IS NOT A SLOT EITHER ============================
##
## ADR-0048 injects one gambit per unit at the encoder boundary — an unconditional
## `Attack / Nearest Foe`, below everything the player authored — so a unit whose every slot
## misses still has a terminal candidate. The OBJECT carries one `ALWAYS` condition; the ROW
## reads `Attack / Nearest Foe / Their / —` (ADR-0283 dec. 7): blank IS the absence of a
## condition since that ADR's dec. 2 and `condition_label` reads either spelling back as blank,
## while the SUBJECT stays named — its dec. 3, amended, see `GambitOptions.subject_label` —
## because with no condition that field is the only thing gating the row, and on the net being
## gated on a foe existing is the entire mechanism.
##
## ADR-0048's own dec. 2 made the net invisible on purpose; ADR-0270 supersedes it: the net is
## the LAST row, rendered DIM, with a BLANK enable cell, and ←/→ refused on it.
##
## An editor whose four rows all read `---` is telling the player their unit does NOTHING, and
## the unit then attacks — which is the screen lying about the rule the unit is under. That is
## the same defect dec. 8 exists to prevent, arriving from the other direction: not a row that
## reads right and never fires, but a rule that fires and is on no row.
##
## The glove may rest there and it takes no press. It is not toggleable, editable or
## reorderable, because there is nothing on the other side of those verbs — the net is not in
## `Character.gambits` and never was (ADR-0048 dec. 3 keeps it a buffer concern), so an edit
## would have nowhere to land.
##
## === THE FIFTH ROW IS NOT A FIFTH SLOT ======================================================
##
## The slot level carries one row past the unit's four: the IMPERATIVE (#1006, design §5), a
## one-shot top-priority order that occupies no slot and self-removes when it is spent. It is a
## fourth LEVEL and not a new form, which is what [GambitSurfaceMenu] being generic buys — the
## level is a `_show_level` case and three strings. Its two questions are the sentence's own DO and
## TO; there is no When and no If, because an imperative is unconditional by construction (that is
## the whole of what "top priority" buys the player) and a condition on it would be a rule, which
## is what the four slots already are.
##
## === IT OPENS ONTO NOTHING, AND THAT IS CORRECT =============================================
##
## A scenario-booted cast has EMPTY gambit lists (#892: `UnitSpawn` mints a [GambitList] and
## nothing in the boot path authors into it), so on Gariland today every slot reads "---". That
## is the honest state of the unit, and this screen is the first thing in the tree that can
## change it — the seeded per-job playbook (design §7) is still fog, and hand-authoring a seed
## through this screen is one of the two ways it stops being fog.

const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const JobDatabase = ExMateriaAlmanac.JobDatabase
const Gambit = ExMateriaAlmanac.Gambit
const GambitCondition = ExMateriaAlmanac.GambitCondition
const GambitList = ExMateriaAlmanac.GambitList
const TargetSelector = ExMateriaAlmanac.TargetSelector

const AdjustmentTurn = preload("res://src/gpu/AdjustmentTurn.gd")
const UIMenuText = preload("res://src/ui3/UIMenuText.gd")
const ImperativeGambits = preload("res://src/gpu/ImperativeGambits.gd")

## Which level is showing. The stack never branches, so it is an enum and a slot/part index
## rather than a LIFO — a two-integer state a guard can read. IMPERATIVE is a sibling of CHOICE,
## not a level below it: both are reached from a ROW-level press and both fall back to it.
##
## ABILITY is the one level that IS below another: the `Do` list's skillset rows open it, and ✕
## on it returns to the `Do` list rather than to the row. It is a LEVEL and not a flag on CHOICE
## because `level()` is the guard seam this screen answers "where am I" with — a second list
## hiding inside CHOICE's answer would be a screen whose own report could not tell the player's
## two positions apart.
##
## There is no PART level any more. ADR-0268 dec. 1 supersedes ADR-0255 dec. 2's
## three-levels-of-one-list and dec. 4's "the part rows ARE the readout": the ROW is the readout
## and the editor at once, ←/→ walk its parts in place, and ○ opens the focused part's list.
## Two levels, not three, and the middle one is gone because it was a screen showing one slot's
## four parts — which is what the row now shows for FOUR slots at once.
enum Level { ROW, CHOICE, ABILITY, IMPERATIVE }

## The parts of the row, left to right — the sentence's reading order.
##
## ENABLE IS NOT A PART, and is not a button either (dec. 13 supersedes dec. 4). The leftmost
## column paints the SLOT NUMBER, which is not editable and so is not somewhere the cursor stops.
## `Gambit.enabled` stays in the domain and the kernel still honours it — the off-switch the
## player reaches is `---`, which empties the row.
##
## SUBJECT IS A PART AGAIN (ADR-0283 dec. 1 supersedes ADR-0268 dec. 2's fold). The row reads
## `Do · To · Subject · If` — `Heal / Nearest Ally / Their / HP<50%` — and the subject is a
## two-way switch (`My` / `Their`) rather than the full pool selector dec. 2 priced and
## rejected. Landing a subject writes `condition_target`; landing a condition writes
## `conditions[0]`, and each is now one field instead of two.
enum Part { DO, TO, SUBJ, IF }
const PART_COUNT := 4

## The TAIL of the `Do` list: empty this slot back to `GambitList`'s empty gambit.
##
## It used to be a fifth row on the PART level, which dec. 1 removed. It lives in the Do list
## rather than becoming a part of its own, because clearing IS choosing what the slot does, and
## because a destructive verb reachable by ←/→ alone is one press from the row a player is
## reading.
##
## `---` and not `--- (clear)` (ADR-0268 Amendment 3): the row it produces reads `--- / --- /
## ---`, so the list entry that produces it should read as that row and not as a sentence about
## it. The parenthetical was doing a second job — it was the only warning that this row is
## destructive — so the entry MOVED TO THE BOTTOM of the list in the same change. A destructive
## row at the head is one the cursor rests on the moment the list opens; at the tail it is one
## the player has to walk past every verb to reach.
const CLEAR_LABEL := "---"

## Where each part's CHOICE list hangs, mirroring [GambitSurfaceMenu]'s column table. Read from
## the menu rather than re-literalled, so a re-laid-out row cannot leave the lists behind.
const PART_COLUMN_X := {
	Part.DO: GambitSurfaceMenu.COL_DO_X,
	Part.TO: GambitSurfaceMenu.COL_TO_X,
	Part.SUBJ: GambitSurfaceMenu.COL_SUBJ_X,
	Part.IF: GambitSurfaceMenu.COL_IF_X,
}

## The imperative level's rows. DO and TO are the sentence's own parts, edited on the DRAFT rather
## than on a slot; ISSUE is the press that spends the charge, and it is a separate row precisely so
## that editing the order is free and only committing it costs.
enum Order { DO, TO, ISSUE }

## Emitted when a choice has landed in the character's gambit list. The host marks the
## adjustment turn TOUCHED on this — an opened-but-unedited surface must not pay for a commit
## push (ADR-0252: `reconfigure_unit` on an unedited unit is a proven no-op).
signal edited(slot: int)
## An imperative was issued (#1006) — a charge is spent and the order stands. Reported rather than
## acted on: the order is already in the ledger by the time this fires, and it crosses to the GPU
## at the turn's commit like every other edit on this screen.
signal imperative_issued(order)
## ✕ off the SLOT level — the surface is done and the coordinator may unwind it.
signal dismissed

## The character whose list this is editing. Set before add_child.
var character = null

## The battle's imperative ledger ([ImperativeGambits], #1006), or null off a battlefield — the
## roster host has no battle, so it has no charges and shows no fifth row. Set before add_child,
## like [member character].
var imperative = null
## Which unit index [member character] is, in the battle the ledger belongs to. `-1` off a
## battlefield. The ledger is keyed by unit index and not by Character, because charges are battle
## state and the Character is the durable representation that outlives the battle (ADR-0005).
var imperative_unit: int = -1
## The world's tick right now, for the watchdog deadline an issue stamps. Injected because a tick
## is a fact about the running loop and this screen holds no loop.
var imperative_now: Callable = Callable()

## The order being composed on the imperative level. Never `character.gambits` — an imperative is
## in no slot, and writing the draft into one would spend a rule the player still wants.
var _draft = null

## The ROW list (or the imperative's), which stays mounted for the whole visit.
var _menu: GambitSurfaceMenu = null
## The CHOICE list, mounted OVER the row list and freed when the choice lands or is left.
##
## A second window and not a re-used one, because dec. 1 asks for the list to open "under its
## own column as a formation box-open WITH THE ROW STILL LEGIBLE BEHIND IT". Tearing the row
## down to show the list is the drill-down this ADR supersedes, wearing a row's clothes.
var _choice_menu: GambitSurfaceMenu = null
var _level: int = Level.ROW
var _slot: int = 0
var _part: int = Part.DO
## Whether the CHOICE level currently showing was opened from the IMPERATIVE level. It is what
## sends the landing choice back to the order instead of to the sentence, and what makes
## [method _gambit] hand out the draft.
var _order_choice: bool = false
## The choices currently offered at the CHOICE level, parallel to the menu's rows. Each is
## `{"name": String, "apply": Callable}` — the apply writes the whole part, so no level below
## this one has to know which part it is serving. A `Do` entry may instead carry
## `{"name": String, "drill": int}`, which opens that skillset's abilities.
var _choices: Array = []
## Which skillset the ABILITY level is showing, or `-1` off it. A guard seam and the level's own
## subject: [method level] says WHICH list is up and this says WHOSE.
var _skillset: int = -1


func _ready() -> void:
	_ensure_list()
	_show_level(Level.ROW)


func _ensure_list() -> void:
	if character == null:
		return
	if character.gambits == null:
		character.gambits = GambitList.new()
	character.gambits.ensure_fixed_size()


# -----------------------------------------------------------------------------
# Level machinery — one menu at a time, rebuilt on every level change.
# -----------------------------------------------------------------------------
func _show_level(level: int) -> void:
	_level = level
	if level == Level.CHOICE or level == Level.ABILITY:
		_open_choice_list()
		return
	_order_choice = false
	_skillset = -1
	_free_choice()
	_free_menu()
	_menu = GambitSurfaceMenu.new()
	_menu.name = "GambitSurfaceMenu"
	_menu.title = _title_for(level)
	if level == Level.ROW:
		_menu.row_entries = row_entries()
		_menu.focused_part = _part
	else:
		_menu.entries = _entries_for(level)
	add_child(_menu)
	_menu.chosen.connect(_on_chosen)
	_menu.cancelled.connect(_on_cancelled)


## Raise the focused part's list OVER the row, hung off that part's own column (dec. 1).
##
## The row list underneath is left standing and left CONNECTED — it just stops being the thing
## the pad reaches, because [method handle_action] routes to the topmost menu. That is the whole
## mechanism: two windows, one reader.
func _open_choice_list() -> void:
	# ONE owner for the drill's subject: every list that is not the ability list is a list with
	# no skillset behind it, and saying so here means no caller has to remember to.
	if _level != Level.ABILITY:
		_skillset = -1
	_free_choice()
	_choice_menu = GambitSurfaceMenu.new()
	_choice_menu.name = "GambitChoiceMenu"
	# A DISTINCT id namespace per level, and the reason is `queue_free`: the list this one
	# replaces is freed at the END of the frame, so for the rest of this one BOTH are in the
	# tree and both register their UI3Element ids. Two windows answering to
	# `gambitsurface.choice.window` is one element reading the other's stored rect — which
	# renders as a perfectly drawn frame with no text in it (see [member
	# GambitSurfaceMenu.id_prefix], where that failure is photographed).
	_choice_menu.id_prefix = "gambitsurface.ability" if _level == Level.ABILITY \
		else "gambitsurface.choice"
	_choice_menu.title = _title_for(_level)
	# Aim the row's chevron at the part being edited before the list covers it. ←/→ already
	# repaint on every step, so this only matters for a list opened WITHOUT walking there — the
	# capture tool's path, and any future host that opens a part directly.
	if _menu != null and is_instance_valid(_menu) and not _order_choice:
		_menu.set_row_entries(row_entries(), _part)
	# §15.21 — the row window goes to the BACKGROUND and gives up its glove. Dec. 1 wants the row
	# still legible behind the list, and "legible" is not "still focused": before this, both
	# windows drew in the foreground tan with a live bobbing glove each, so the screen showed two
	# cursors and named neither as the one the pad was reaching. The ROM's answer is the discrete
	# fg→bg CLUT swap plus the removal of the backgrounded window's cursor, which is what every
	# other menu in this family already does ([method StartActionMenu.set_backgrounded], its
	# consumers in `FormationDetailTransition`).
	if _menu != null and is_instance_valid(_menu):
		_menu.set_backgrounded(true)
		_menu.set_cursor_visible(false)
	_choice_menu.entries = _entries_for(Level.CHOICE)
	if not _order_choice:
		_choice_menu.container_override = choice_container_for(_part)
	add_child(_choice_menu)
	_choice_menu.chosen.connect(_on_chosen)
	_choice_menu.cancelled.connect(_on_cancelled)


func _free_choice() -> void:
	if _choice_menu != null and is_instance_valid(_choice_menu):
		_choice_menu.queue_free()
	_choice_menu = null


## Where the CHOICE list lands for `part`: hung off that part's column and rising ABOVE the row
## window, which is the only direction it can go — the row window's own bottom is the screen's.
##
## Clamped into [0, 256] on both sides. The `If` column is the LAST one, so an unclamped list of
## its width would run off the right edge of the mask; that is the first thing this has to
## survive and the reason the clamp is here rather than asserted upstream.
func choice_container_for(part: int) -> Rect2:
	var text := UIMenuText.new()
	var widest := 0.0
	for c in _choices:
		widest = maxf(widest, text.measure(String(c.get("name", ""))))
	var w := ceilf(widest) + 24.0
	var rows := mini(_choices.size(), GambitSurfaceMenu.VISIBLE_ROWS)
	# `+ 16` is ADR-0247's container rule and the whole of it — a choice list wears NO title
	# (dec. 10), so it pays no title band. It used to read `+ 24`, the rule plus a band the list
	# did not have, which left 8 px of empty frame under the last row.
	var h := rows * float(StartActionMenu.ROW_PITCH) + 16.0
	var home := GambitSurfaceMenu.container()
	var col: float = PART_COLUMN_X.get(part, float(home.position.x) + 8.0)
	var x := clampf(float(col) - 8.0, 4.0, 252.0 - w)
	var y := maxf(4.0, float(home.position.y) - h - 2.0)
	return Rect2(x, y, w, h)


func _free_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = null


## The window title for `level`. ONLY the imperative wears one.
##
## A choice list opens under the very column whose part it edits (ADR-0268 dec. 1), and that
## column is already the part's name — the row reads `1 Attack  Nearest Foe  —  —` with the
## list hanging off `Attack`. Titling it "Do" spends the window's whole 8-px top band restating
## the thing the player is looking at, and does it twice over for the ABILITY level, where the
## honest title would be the skillset the player just picked and the column below it is already
## showing what it produced.
##
## THE ROW LEVEL wore "Gambit" and no longer does (ADR-0255 Amendment 1). The same argument
## retires it: this window is reached by taking the "Gambit" row of the adjustment menu, and it
## is the only thing on screen — a title restating the press that opened it buys nothing, and it
## was buying it at a price. The 8-px band it occupied is the row budget's, and the title itself
## inked INTO the frame's own top border. The class doc's case for a FONT.BIN title still stands
## for the IMPERATIVE level, which is the one level whose name is not written anywhere else.
func _title_for(level: int) -> String:
	match level:
		Level.IMPERATIVE:
			return "Imperative"
		_:
			return ""


func _entries_for(level: int) -> Array[String]:
	match level:
		Level.IMPERATIVE:
			return order_rows()
		_:
			var out: Array[String] = []
			for c in _choices:
				out.append(String(c.get("name", "")))
			return out


## The rows the surface hands the menu: one dict per gambit slot, plus the imperative's plain
## string when a battle host supplied a ledger.
##
## PUBLIC and pure-ish so a guard can assert what the screen says without booting the menu. The
## stringifying happens HERE and not in the widget, because "who is `Their`" is a domain question
## and [GambitSurfaceMenu] renders what it is handed (its class doc).
## The leftmost cell: the slot's PRIORITY, 1-based, because slot order IS priority (rule A1) and
## the row number is therefore not decoration — it is the thing L1/R1 change. It reads 1-4 where
## it used to read `○` / `×` (dec. 13 supersedes dec. 4).
##
## A digit is ~6 px against the `○`'s 10, which is where the `Do` column's cap recovers what
## ADR-0255 Amendment 1's margin fix cost it.
func _slot_number(i: int) -> String:
	return str(i + 1)


func row_entries() -> Array:
	var out: Array = []
	var list = character.gambits if character != null else null
	for i in range(GambitList.VISIBLE_SLOTS):
		var g = list.get_at(i) if list != null else null
		if g == null or g.is_empty():
			# An empty slot still shows its number and its columns, because the parts are what
			# ←/→ walk — a row rendered as one "---" would be a row the cursor cannot enter, and
			# on a scenario-booted cast (#892) that is EVERY row.
			out.append({"enable": _slot_number(i), "do": "---", "to": "---", "subj": "---",
				"iff": "---", "extra": 0})
			continue
		out.append({
			"enable": _slot_number(i),
			"do": _do_text(g),
			"to": _target_text(g.action_target),
			# `---` is "this row holds nothing"; `—` ([constant GambitOptions.BLANK]) is "this
			# column is deliberately unset on a row that holds something". Two marks because
			# they are two states, and a row that printed the same glyph for both would make an
			# unconditional rule look like an empty slot.
			"subj": GambitOptions.subject_label(g),
			"iff": GambitOptions.condition_label(g),
			# ADR-0268 dec. 3 — the screen edits condition index 0 and NEVER destroys the rest. A slot
			# carrying more says so, because a screen that silently drops data the player cannot
			# see is worse than a screen that cannot author it.
			"extra": maxi(0, g.conditions.size() - 1),
		})
	if offers_imperative():
		out.append({"text": imperative_row()})
	out.append(safety_net_row())
	return out


## ADR-0048's injected fallback, as a row (ADR-0270). Read off
## [method GambitEncoder.safety_net_gambit] — the very object the encoder packs — so the row and
## the buffer cannot drift into two descriptions of one rule.
##
## `to` reads the CONDITION target and not the action target, exactly as [method imperative_row]
## does and for the same reason: the net's `action_target` is `triggering()`, which renders as
## "Them" and says nothing about the pool it aimed at. The aim is on the condition target,
## because the net acts on whoever it picked out.
##
## `inert` is what the widget reads to keep the row DIM under the glove; the ENABLE cell is
## BLANK rather than `○`, because the mark is a state the player can change and this one is not.
func safety_net_row() -> Dictionary:
	var g = GambitEncoder.safety_net_gambit()
	return {
		"enable": "",
		"do": _do_text(g),
		"to": _target_text(g.condition_target),
		# THE `If` COLUMN BLANK, THE SUBJECT NAMED, and it is the net's own object that says so
		# rather than this row choosing it: `safety_net_gambit` carries one `ALWAYS` condition,
		# which `GambitOptions.condition_label` reads back as blank. The subject no longer
		# blanks with it (ADR-0283 dec. 3, amended) — the row reads
		# `Attack / Nearest Foe / Their / —` where ADR-0270 dec. 1 stated
		# `Attack / Nearest Foe / Always`, and `Their` is the same `condition_target` the `to`
		# cell above is read off, so the two cannot drift into disagreeing about one field.
		"subj": GambitOptions.subject_label(g),
		"iff": GambitOptions.condition_label(g),
		"extra": 0,
		"inert": true,
	}


## Which row the safety net occupies: after the four slots and after the imperative's row when a
## battle host supplied one. ALWAYS present — the encoder injects the net on the roster path too
## (`encode_gambits` appends it whatever the list held), so a screen that showed it only in
## battle would be hiding it exactly where the player does their authoring.
func safety_net_row_index() -> int:
	return GambitList.VISIBLE_SLOTS + (1 if offers_imperative() else 0)


## Is the glove resting on the safety net right now? Read off the MENU and not off [member
## _slot], which only moves on ○ — walking onto an inert row never lands a press, so `_slot`
## would still be naming whatever the player last opened.
func _focused_row_is_net() -> bool:
	if _level != Level.ROW or _menu == null or not is_instance_valid(_menu):
		return false
	return _menu.selected_row() == safety_net_row_index()


## The four slot rows, as the player reads them: the gambit's own action line, or "---" for a
## slot still holding the empty gambit. PUBLIC and pure-ish so a guard can assert what the
## screen says without booting the menu.
func slot_rows() -> Array[String]:
	var out: Array[String] = []
	var list = character.gambits if character != null else null
	for i in range(GambitList.VISIBLE_SLOTS):
		var g = list.get_at(i) if list != null else null
		if g == null or g.is_empty():
			out.append("%d. ---" % (i + 1))
		else:
			out.append("%d. %s" % [i + 1, GambitProse.sentence_lines(g)[0]])
	return out


## Does this surface offer the imperative row at all? Only over a live battle: the ledger and the
## unit index are both injected by the battle host, and the roster host supplies neither, so the
## roster's gambit surface is exactly the four slots it was before #1006.
func offers_imperative() -> bool:
	return imperative != null and imperative_unit >= 0


## The imperative's SLOT-level row: what stands, or what it would cost.
##
## Prefixed "!" rather than numbered, because a number would read as a fifth slot and it is not
## one — it holds no rule, it holds an order that is spent and gone.
func imperative_row() -> String:
	if not offers_imperative():
		return ""
	if imperative.is_armed(imperative_unit):
		var standing = imperative.entry_for(imperative_unit)
		# Read back in the SAME two words that composed it ("Attack" -> "Foe"), and not
		# through `GambitProse.sentence_lines`: that renders the action line as "Attack Them",
		# which is true of the struct and says nothing about the pool the player actually aimed at
		# — the aim is on the condition target, because an order acts on whoever it picked out.
		return "! %s → %s" % [_do_text(standing), _target_text(standing.condition_target)]
	return "! Imperative (%d)" % imperative.charges_left(imperative_unit)


## The imperative level's three rows: the order's two parts, then the press that spends the charge.
##
## The charge count is ON the Issue row and not in the title, because the cost belongs next to the
## press that pays it — and a row that reads "no charges left" is a refusal the player can see
## before making it, which a silently inert row is not.
func order_rows() -> Array[String]:
	_ensure_draft()
	var out: Array[String] = []
	out.append("Do: %s" % _do_text(_draft))
	out.append("To: %s" % _target_text(_draft.condition_target if _draft != null else null))
	if not offers_imperative():
		out.append("Issue")
	elif imperative.can_issue(imperative_unit):
		out.append("Issue — %d left" % imperative.charges_left(imperative_unit))
	else:
		out.append("Issue — none left")
	return out


## The order the imperative level opens on. Seeded from whatever already stands so re-opening
## reads back the order the unit is under, and from [method ImperativeGambits.default_order]
## otherwise — a default that is issuable on the first press, because a default the player must
## edit before it means anything would make the charge feel like it bought a form.
func _ensure_draft() -> void:
	if _draft != null:
		return
	if offers_imperative() and imperative.is_armed(imperative_unit):
		_draft = ImperativeGambits.copy_of(imperative.entry_for(imperative_unit))
	else:
		_draft = ImperativeGambits.default_order()


## The gambit the current edit lands on: the DRAFT while an imperative is being composed, the
## selected slot's otherwise.
##
## One accessor and not two, so [method choices_for]'s applies are written once — the CHOICE level
## never learns whether it is serving a slot or an order, which is the same reason it never learns
## which part it is serving.
func _gambit():
	if _composing_order():
		return _draft
	if character == null or character.gambits == null:
		return null
	return character.gambits.get_at(_slot)


## Is the edit in flight an imperative's rather than a slot's? True on the imperative level and on
## a CHOICE level opened from it.
func _composing_order() -> bool:
	return _draft != null and (_level == Level.IMPERATIVE
		or ((_level == Level.CHOICE or _level == Level.ABILITY) and _order_choice))


# -----------------------------------------------------------------------------
# Part readouts.
# -----------------------------------------------------------------------------
func _do_text(g) -> String:
	if g == null:
		return "Wait"
	if g.action_kind == Gambit.ActionKind.ABILITY:
		var view := AbilityDatabase.get_ability_view(g.ability_id)
		return view.name if not view.name.is_empty() else "Ability?"
	return String(Gambit.KIND_TO_VERB.get(g.action_kind, "Wait"))


## Probes the UNGATED [method GambitOptions.targets] and not `_target_choices`, and the
## difference is load-bearing. Since ADR-0276 the offer list is a SUBSET — a slot the player
## aimed before changing the verb, or a gambit authored anywhere but here, can legitimately
## hold an aim the current verb would no longer offer. Naming it out of the offer list would
## miss, fall through to "Self", and print an aim the slot does not hold: the readout lie this
## column exists to prevent, arriving through the gate meant to prevent it.
func _target_text(ts) -> String:
	if ts == null:
		return "Self"
	for c in GambitOptions.targets():
		var probe = c["make"].call()
		if probe.pool_type == ts.pool_type and probe.team_filter == ts.team_filter \
				and probe.resolution == ts.resolution:
			return String(c["name"])
	return "Self"


## The `If` column's readout — [GambitOptions.condition_label], which probes the catalogue so
## the row can only print a string the list also offers. A BARE predicate since ADR-0283 dec. 2;
## the subject it used to carry is `GambitOptions.subject_label`'s column now.
func _condition_text(g) -> String:
	return GambitOptions.condition_label(g)


# -----------------------------------------------------------------------------
# The choice catalogues. Each entry is a NAME and a maker; the apply wraps the maker so the
# CHOICE level never learns which part it is editing (see the class doc).
# -----------------------------------------------------------------------------
## The target presets, shared by "To" and "When" — [GambitOptions.targets], not a list of its
## own. The catalogue moved OFF this screen so `GambitEncoderTest` can round-trip every offered
## choice through [GambitEncoder] without booting a surface (ADR-0268 dec. 8); a second copy
## here would be a screen offering choices the gate never saw.
func _target_choices() -> Array:
	var g = _gambit()
	if g == null:
		return GambitOptions.targets()
	return GambitOptions.targets_for(g.action_kind, g.ability_id, g.condition_target)


## The condition presets for the "If" part — [GambitOptions.conditions], for the same reason.
## `In Melee Range` / `In Spell Range` are GONE from that list and the reason is written there:
## both are E1-UNSUPPORTED, so the rows they authored read back correctly and never fired.
func _condition_choices() -> Array:
	return GambitOptions.conditions()


## The "Do" choices: the three job-independent control verbs, then ONE ROW PER SKILLSET the
## unit can act out of — the unit's own two, primary then sub.
##
## === WHY THE ABILITIES ARE A LEVEL DOWN =====================================================
##
## They used to be here, all of them, in one flat id-sorted run under the three verbs. A unit
## with two full skillsets offers thirty-odd; the list shows five at a time, so the ability the
## player wants is somewhere behind six presses of ↓ through a run with no landmark in it — and
## the ROM's own answer to exactly this question is the two-level action menu every FFT player
## already knows ("White Magic" → "Cure"). A skillset row is the landmark, and it is the one the
## game itself uses.
##
## The unit's two skillsets are also the whole of what it can do: [method
## AdjustmentTurn.usable_ability_ids] is BUILT as the union of the primary's and the sub's
## actions, so grouping by skillset partitions that set rather than filtering it — no usable
## ability falls outside a row, and there is no "Other" bucket to keep honest.
func _do_choices() -> Array:
	var out: Array = GambitOptions.action_verbs()
	out.append_array(_skillset_rows())
	return out


## The skillset rows the `Do` list offers: the unit's primary job's, then its sub-job's, each
## `{name, skill_set}` — a DRILL and not a `make`, because a skillset is not a thing a gambit can
## hold. `choices_for` turns the pair into the entry the CHOICE level lands on.
##
## Three ways a row is dropped, and each one would otherwise be a row that opens onto nothing:
## a job with `skill_set_id == 0` (24 of the ROM's 160 jobs have no action skillset at all), a
## skillset the two jobs SHARE (deduped by id — the ROM's nine duplicate skillsets are one job's
## male and female halves, which cannot be primary and sub at once, but a monster's two can
## coincide), and a skillset whose every action this unit cannot use.
func _skillset_rows() -> Array:
	var out: Array = []
	if character == null or character.progression == null:
		return out
	var seen: Dictionary = {}
	for job_id in [character.progression.current_job_id, character.progression.sub_job_id]:
		var sid := _skill_set_id_for(job_id)
		if sid <= 0 or seen.has(sid):
			continue
		seen[sid] = true
		var ss: Dictionary = AbilityDatabase.get_skill_set(sid)
		var nm := String(ss.get("name", ""))
		if nm.is_empty() or _ability_choices(sid).is_empty():
			continue
		out.append({"name": nm, "skill_set": sid})
	return out


static func _skill_set_id_for(job_id) -> int:
	var jid := String(job_id) if job_id != null else ""
	if jid.is_empty():
		return 0
	var job: Dictionary = JobDatabase.get_job(jid)
	if job.is_empty():
		return 0
	return int(job.get("skill_set_id", 0))


## One skillset's ability choices, in the ROM's OWN table order — not id-sorted and not
## alphabetised. A skillset's `actions` array is the order the ROM's action menu lists them in,
## which is the order a player who has ever opened that menu already knows; re-sorting it here
## would make this list disagree with the one the same abilities appear in everywhere else.
##
## Filtered by [method AdjustmentTurn.usable_ability_ids] — the SAME predicate the job change
## prunes against (ADR-0252). Offering a wider set would let the player author a slot the very
## next job change deletes, and offering a narrower one (filtered by `learned_abilities`) would
## refuse the slot a player is working toward.
func _ability_choices(skill_set_id: int) -> Array:
	var out: Array = []
	var usable: Dictionary = AdjustmentTurn.usable_ability_ids(character)
	for id in AbilityDatabase.get_skill_set_actions(skill_set_id):
		var aid := int(id)
		if not usable.has(aid):
			continue
		var view := AbilityDatabase.get_ability_view(aid)
		if view.is_empty() or view.name.is_empty():
			continue
		out.append({"name": view.name, "apply": func() -> void:
			var g = _gambit()
			if g == null:
				return
			# Asked BEFORE the write, exactly as the verb list asks it — landing the ability is
			# what stops the slot being empty. This is the press the player reported: picking
			# `ThrowStone` on a fresh slot left the constructor's `Self` standing, and
			# ThrowStone's ROM record forbids the caster.
			var was_empty: bool = g.is_empty()
			g.action_kind = Gambit.ActionKind.ABILITY
			g.ability_id = aid
			_seed_aim(g, was_empty)})
	return out


## The pools an imperative may be aimed at. The same named whole selectors the sentence offers,
## MINUS "Them" — "the unit that triggered this" names nothing when there is no standing trigger,
## and offering a row that cannot resolve is the reachable-but-meaningless cell dec. 3 of ADR-0255
## exists to keep off this screen.
func _order_target_choices() -> Array:
	var g = _gambit()
	var out: Array = []
	for c in GambitOptions.targets():
		var probe = c["make"].call()
		if probe.pool_type == TargetSelector.PoolType.TRIGGERING:
			continue
		# ADR-0276's gate, asked in the shape an ORDER has. A slot's row is an AIM; an order's
		# row is the unit the order LOCKS ONTO, and `order_choices_for` lands it on
		# `condition_target` with `Them` on the action. The source is `GambitOptions.targets()`
		# rather than `_target_choices` — the slot gate would grade each row against the
		# DRAFT's current subject, which is the one field composing an order is about to
		# overwrite.
		#
		# 🔴 GRADED AS `(verb, ability, this-row)` AND NOT AS `(verb, ability, Them, this-row)`.
		# It used to be the latter, and that read broke the moment `aim_verdict` learned that a
		# `Them` AIM is always UNNAMED on a slot (choosing it moves the subject onto the
		# actor) — every row started grading UNNAMED and the order's `To` list went EMPTY.
		# The two questions were never the same one: a slot is asking *"may this verb be aimed
		# at a pool it forwards to"*, and an order is asking *"may this verb be aimed at this
		# pool"*, which is this call. The verb and ROM half is IDENTICAL either way, because
		# `aim_class(Them, row)` forwards to `aim_class(row)` — only the slot-specific tail
		# differed, and an order has no subject column for that tail to be about.
		#
		# The caster skip is that tail, restated where it belongs: an order that locked onto
		# the issuer is the `Self` row under the word "lock-on", and it is withheld for the
		# same reason the slot withholds `Them`.
		if g != null and GambitOptions.aim_class(probe) == &"caster":
			continue
		if g != null and GambitOptions.aim_verdict(g.action_kind, g.ability_id,
				probe) != GambitOptions.AIM_SENSIBLE:
			continue
		out.append(c)
	return out


## The imperative's "To" choices. Each lands a WHOLE aim — the pool it picks out AND the act on
## whoever it picked — because an imperative that matched on one unit and acted on another is not
## a lock-on. That is dec. 3's "named whole values" read at the level an order needs it: the whole
## value here spans two selectors, not one.
func order_choices_for(row: int) -> Array:
	if row != Order.TO:
		return choices_for(Part.DO) if row == Order.DO else []
	var out: Array = []
	for c in _order_target_choices():
		var make: Callable = c["make"]
		out.append({"name": c["name"], "apply": func() -> void:
			var g = _gambit()
			if g == null:
				return
			g.condition_target = make.call()
			g.action_target = TargetSelector.triggering()})
	return out


## Spend a charge and put the drafted order above the unit's standing list.
##
## Written EAGERLY into the ledger, exactly as every other choice on this screen is written into
## the Character (ADR-0255) — the undo is the adjustment turn's cancel, which refunds the charge
## (design §4), and not a staged overlay here. A COPY is stored so the draft the player keeps
## editing afterwards cannot rewrite an order already paid for.
func _issue() -> void:
	if not offers_imperative():
		return
	_ensure_draft()
	var now: int = int(imperative_now.call()) if imperative_now.is_valid() else 0
	if not imperative.issue(imperative_unit, ImperativeGambits.copy_of(_draft), now):
		return
	imperative_issued.emit(imperative.entry_for(imperative_unit))
	_show_level(Level.ROW)


## Re-aim a slot after a press that can change what its aim MEANS — a new verb, or a new
## subject (which re-points `Them`). ADR-0276 supersedes ADR-0268 dec. 12's version of this.
##
## It also RE-MIRRORS a mirrored subject, because it is one of the two places `action_target` is
## written (the other is the `To` apply, which asks the same question). See the comment at the
## write itself.
##
## Two cases, and the second is the one dec. 12 did not have:
##
## **An EMPTY slot always takes the seed.** It has no aim the player chose; it has the
## constructor's `Self` (`Gambit._init`). That is dec. 12, unchanged in shape and widened in
## reach: it used to seed for `Attack` alone, and now every verb gets the head of its own gated
## list — which for `Attack` is still `Nearest Foe`, by name, from
## [method GambitOptions.seed_aim_for].
##
## **A CONFIGURED slot is re-aimed only when its aim has become BROKEN.** dec. 12's restraint —
## "a slot the player has already aimed is one they have made a decision about" — is right and
## survives, but it never covered the case where the press invalidates the decision rather than
## disagreeing with it. Change `Cure / Self` to `ThrowStone` and the aim is not a choice the
## screen should defer to: ThrowStone's ROM record carries `dont_hit_caster`, so `Self` is an aim
## the ability may not take, the `To` list no longer offers it, and leaving it there strands the
## row on a value the player can see and can no longer re-pick. So a verdict of
## [constant GambitOptions.AIM_SENSIBLE] is left alone and anything else is re-seeded.
##
## The screen still never PREFERS. Everything here either removes an aim ADR-0049's hit policy
## or the kernel can be shown to reject, or takes the first row the gate left standing — see
## [method GambitOptions.aim_verdict] for why the ROM answers "may it" and not "should it".
func _seed_aim(g, was_empty: bool) -> void:
	# An IMPERATIVE is not seeded and must not be. Its aim is structurally `triggering()` —
	# `order_choices_for` lands the pool on `condition_target` and the aim on `Them` together,
	# because an order that matched on one unit and acted on another is not a lock-on. Re-seeding
	# would replace `Them` with a concrete pool and silently break that pair. The same question is
	# asked of an order in `_order_target_choices`, where the pool it offers is the subject.
	if _composing_order():
		return
	if not was_empty and GambitOptions.aim_verdict(
			g.action_kind, g.ability_id, g.action_target,
			g.condition_target) == GambitOptions.AIM_SENSIBLE:
		return
	# ASKED BEFORE THE WRITE, because after it the old aim is gone and the two fields can no
	# longer be compared. This is the same question the `To` apply asks, and it has to be asked
	# here too: this function is the OTHER place `action_target` is written, so a `Do` press that
	# re-seeds the aim would otherwise leave a mirrored subject naming the pool the seed moved
	# off — and on a BLANK-condition row that is ADR-0283 dec. 3's own defect, arriving through
	# the seed instead of through an edit. A fresh slot is the common case: its constructor pair
	# is SELF/SELF, which mirrors, and pressing `Attack` aims it at the nearest foe.
	var was_mirrored := _subject_mirrors_aim(g)
	var seeded = GambitOptions.seed_aim_for(g.action_kind, g.ability_id, g.condition_target)
	if seeded != null:
		g.action_target = seeded
		if was_mirrored:
			_mirror_subject_onto_aim(g)


## The choice list for `part`, each entry `{"name", "apply"}` — the apply is what lands.
func choices_for(part: int) -> Array:
	var out: Array = []
	match part:
		Part.DO:
			for c in _do_choices():
				# A SKILLSET row carries no `make`: it lands nothing and opens the ABILITY
				# level instead. The distinction is the `drill` key and not a name test,
				# because a skillset named "Item" and an ability named "Item" are one string
				# and two entirely different presses.
				if c.has("skill_set"):
					out.append({"name": c["name"], "drill": int(c["skill_set"])})
					continue
				var make: Callable = c["make"]
				out.append({"name": c["name"], "apply": func() -> void:
					var g = _gambit()
					if g == null:
						return
					# Asked BEFORE the write, because the write is what stops it being empty.
					var was_empty: bool = g.is_empty()
					var picked: Dictionary = make.call()
					g.action_kind = picked["kind"]
					g.ability_id = int(picked["ability_id"])
					_seed_aim(g, was_empty)})
			# CLEAR TRAILS the list — for a SLOT, and ONLY for a slot. It is the destructive
			# one, so it is NAMED rather than reachable only by setting three parts back one at
			# a time, and it is LAST rather than first because the head of a list is where the
			# cursor already is (ADR-0268 Amendment 3).
			#
			# An IMPERATIVE's Do list reuses this catalogue (`order_choices_for`), and an
			# imperative occupies no slot — so a clear offered there would empty whatever slot
			# the cursor last touched: the player's own rule, destroyed while composing an order
			# that is not one. That is arm 9's hazard exactly, reached through a door arm 9
			# cannot see, because it walks the choice list BY NAME.
			if not _composing_order():
				out.append({"name": CLEAR_LABEL, "apply": func() -> void: _clear_slot()})
		Part.TO:
			for c in _target_choices():
				var make: Callable = c["make"]
				out.append({"name": c["name"], "apply": func() -> void:
					var g = _gambit()
					if g == null:
						return
					# WAS the subject mirroring the aim? Asked BEFORE the write, because after
					# it the old aim is gone and the two fields can no longer be compared.
					# `Their` MEANS "whoever the To column names" (`GambitOptions.subjects`), so
					# re-aiming the row has to re-aim the subject with it — otherwise the row
					# keeps printing `Their` while the subject still names the pool the player
					# just moved off, and that is the readout-that-lies shape this whole ticket
					# is about. `My` is left alone: it names the actor, not the aim.
					var was_mirrored := _subject_mirrors_aim(g)
					g.action_target = make.call()
					if was_mirrored:
						_mirror_subject_onto_aim(g)})
		Part.SUBJ:
			# TWO ROWS, and the list is offered even on a row with no condition — the subject is
			# what MAKES the condition mean something, so refusing it until a test is set would
			# be a part the player has to author out of order.
			for c in GambitOptions.subjects():
				var make: Callable = c["make"]
				out.append({"name": c["name"], "apply": func() -> void:
					var g = _gambit()
					if g == null:
						return
					# `Their` is a COPY of the gambit's own aim, so the copy has to be taken
					# from the aim as it stands NOW and not from whatever it was when the list
					# opened. That is why `make` takes the aim rather than closing over it.
					g.condition_target = make.call(g.action_target)
					# A subject the aim forbids changes what `Them` resolves to (ADR-0276), so
					# the aim is re-gated against the subject that just landed.
					_seed_aim(g, false)})
		Part.IF:
			# BLANK HEADS THE LIST, and it is not a sixth condition — it is the absence of one
			# (ADR-0283 dec. 2). It heads rather than trails because it is the state a fresh
			# slot is already in, so the cursor opens resting on what the row already says; the
			# destructive entry that TRAILS its list is `Do`'s clear, which empties four fields
			# rather than one.
			out.append({"name": GambitOptions.BLANK, "apply": func() -> void:
				var g = _gambit()
				if g == null:
					return
				_clear_condition(g)})
			for c in _condition_choices():
				var make: Callable = c["make"]
				out.append({"name": c["name"], "apply": func() -> void:
					var g = _gambit()
					if g == null:
						return
					# dec. 3 — indices 1+ are PRESERVED. `conditions[0] = x` and not
					# `conditions = [x]`: the row shows a `+N` for what it cannot display, and a
					# save that dropped them would make that mark a lie about data already gone.
					if g.conditions.is_empty():
						var seed: Array[GambitCondition] = [make.call()]
						g.conditions = seed
					else:
						g.conditions[0] = make.call()
					# 🔴 THIS PRESS MUST NOT TOUCH THE SUBJECT, and it used to.
					#
					# It called `_seed_subject(g)`, which re-derives the subject from the aim —
					# so a player authoring the row in READING ORDER (`Do`, `To`, `Subject`,
					# `If`) had their `Subject` press silently overwritten one column later.
					# Both `My` and `Their` came out `Their`, which is the column being INERT
					# in the exact order the layout asks the row to be read. Reproduced through
					# this apply with `capture_gambit_surface --author='Attack|Foe|My|HP<50%'`,
					# which landed `Attack / Foe / Their / HP<50%`; the same choice made AFTER
					# the condition (`--then=Subject:My`) landed correctly, which is what named
					# the press rather than the value as the culprit.
					#
					# Nothing has to be seeded here, because the subject is ALREADY right by
					# the mirror invariant dec. 3 maintains everywhere else: a blank condition
					# leaves `condition_target` MIRRORING the aim (`_clear_condition`), the
					# `To` press re-mirrors when it was mirrored, and `_seed_aim` re-mirrors on
					# a verb press. So an untouched row arrives here already reading `Their`,
					# and a row whose `Subject` the player set to `My` arrives holding the
					# actor. Seeding could only ever overwrite one of those two — and only the
					# player's one, because the default is what seeding recomputes.
					_seed_aim(g, false)})
	return out


## Is `condition_target` currently a copy of `action_target` — i.e. is the subject column
## reading `Their` (or blank, which mirrors for the same reason)?
##
## Compared on the three fields `GambitEncoder._target_selector_to_gpu` actually reads — pool,
## team and resolution — and not by identity, because the two are deliberately separate objects
## (`GambitOptions.subjects`) and never the same reference. `include_ko` is out: the screen
## offers no KO-inclusive aim, so a difference there came from somewhere this surface does not
## author and is not ours to re-point.
func _subject_mirrors_aim(g) -> bool:
	var s = g.condition_target
	var a = g.action_target
	if s == null or a == null:
		return false
	return s.pool_type == a.pool_type and s.team_filter == a.team_filter \
		and s.resolution == a.resolution


## Put the condition column back to blank. THE SUBJECT COLUMN DOES NOT GO WITH IT.
##
## It used to (ADR-0283 dec. 3, since amended) on the grounds that a subject is who a QUESTION
## is about and the question is gone. The rest of this comment is why that was wrong, and it has
## said so all along: what `condition_target` holds after a clear is the AIM — mirrored, not
## cleared — because the field STILL GATES THE SLOT with no condition attached to it.
## `select_target` runs, and a `candidate < 0` writes `VERDICT_NO_CANDIDATE` and skips the slot.
## Cleared to SELF instead, an `Attack / Nearest Foe` row with no test would gate on the ACTOR
## existing, which is always true, and the row would fire at a pool it never checked was there.
##
## A field that decides that is a field the column has to print, so `GambitOptions.subject_label`
## now reads `Their` off exactly this state. Blanking it left the player's `Subject` press with
## nothing on screen to confirm it — the display half of the left-to-right authoring bug.
##
## Index 0 only. ADR-0268 dec. 3's promise — NOT ADR-0283's, which the paragraph above cites
## and which is a different rule about a different column — is that the screen never destroys
## `conditions[1..]`, and a row carrying them keeps its `+N` through a blank: the column reads
## what index 0 says.
func _clear_condition(g) -> void:
	if g.conditions.is_empty():
		_mirror_subject_onto_aim(g)
		return
	g.conditions.remove_at(0)
	_mirror_subject_onto_aim(g)


## `condition_target := action_target`, as a COPY. See [method _clear_condition] for why a blank
## condition mirrors rather than clears, and `GambitOptions.mirror_of` for the one aim that
## cannot be copied (`Them`, which would be a cycle the kernel answers with -1).
func _mirror_subject_onto_aim(g) -> void:
	g.condition_target = GambitOptions.mirror_of(g.action_target)


# -----------------------------------------------------------------------------
# Input — the coordinator routes the four formation actions here (it owns the pad).
# -----------------------------------------------------------------------------
## Handle one of the SIX actions the coordinator forwards. Returns true when the surface
## consumed it, so the coordinator can leave anything else to the screen underneath.
##
## `ui_left` / `ui_right` and the two camera-rotate actions are RE-MEANT here, not rebound
## (ADR-0268 dec. 5): while this screen is up it is the only reader of the pad, so there is no
## second action losing a race for the binding — which is the hazard ADR-0137 Amendment 4's
## one-intent-per-button rule was written against. The screen adds no action to do it.
func handle_action(action: StringName) -> bool:
	var top := _top_menu()
	if top == null:
		return false
	match String(action):
		"ui_up":
			top.move_up()
		"ui_down":
			top.move_down()
		"ui_left":
			return _move_part(-1)
		"ui_right":
			return _move_part(1)
		"rotate_camera_cw":
			return _reorder(-1)
		"rotate_camera_ccw":
			return _reorder(1)
		"ui_accept":
			top.confirm()
		"ui_cancel":
			top.cancel()
		_:
			return false
	return true


## The menu the pad reaches: the choice list when one is up, the row list otherwise. One
## reader, always — an open list owns ↑/↓/○/✕ and REFUSES ←/→ and the two rotates, because a
## column has no horizontal axis and a choice is in no slot.
func _top_menu() -> GambitSurfaceMenu:
	if _choice_menu != null and is_instance_valid(_choice_menu):
		return _choice_menu
	if _menu != null and is_instance_valid(_menu):
		return _menu
	return null


## ←/→ across the parts of the focused row. CLAMPS rather than wraps: a sentence has a first
## word and a last word, and wrapping from `If` back to the enable flag would teleport the
## cursor across the row the layout asks the player to read left to right.
##
## Off the ROW level it is REFUSED (false), not swallowed — the choice list is a column and has
## no horizontal axis, so the coordinator's `_refuse()` gets to say so.
func _move_part(step: int) -> bool:
	if _level != Level.ROW:
		return false
	# REFUSED on the net (ADR-0270), not swallowed: the parts are what ←/→ walk, and this row
	# has none — every one of its cells is a fact about a gambit the player does not own. A
	# consumed press would leave the chevron sitting on a column that cannot be opened.
	if _focused_row_is_net():
		return false
	var next := clampi(_part + step, 0, PART_COUNT - 1)
	if next == _part:
		return true   # consumed: the row owns the axis even at its ends
	_part = next
	_menu.set_row_entries(row_entries(), _part)
	return true


## L1/R1 raise and lower the focused slot (dec. 6). A real verb, because slot order IS priority
## (rule A1) and the row number is therefore not decoration — the shader walks slots ascending
## and takes the first match, so moving a row up is moving the rule up.
##
## Refused on the imperative's row and on the choice list: an order is in no slot, so it has no
## priority to raise.
func _reorder(step: int) -> bool:
	if _level != Level.ROW or character == null or character.gambits == null:
		return false
	var from := _menu.selected_row()
	var to := from + step
	if from < 0 or from >= GambitList.VISIBLE_SLOTS \
			or to < 0 or to >= GambitList.VISIBLE_SLOTS:
		return false
	var list = character.gambits
	var moved = list.get_at(from)
	list.replace_at(from, list.get_at(to))
	list.replace_at(to, moved)
	_slot = to
	_menu.set_row_entries(row_entries(), _part)
	for _i in range(absi(step)):
		if step > 0:
			_menu.move_down()
		else:
			_menu.move_up()
	edited.emit(to)
	return true


func _on_chosen(row: int) -> void:
	match _level:
		Level.ROW:
			# The row PAST the four slots is the imperative's, and it is the only row on this
			# level that is not a slot — hence the bounds check below rather than a clamp that
			# would silently land a fifth press on slot 4.
			# The NET first, because it is the row past the imperative's and the bounds check
			# below would otherwise read it as one (ADR-0270). ○ on it does nothing: there is
			# no list to open and nothing in `Character.gambits` for a choice to land on.
			if row == safety_net_row_index():
				return
			if offers_imperative() and row >= GambitList.VISIBLE_SLOTS:
				_show_level(Level.IMPERATIVE)
				return
			_slot = clampi(row, 0, GambitList.VISIBLE_SLOTS - 1)
			_choices = choices_for(_part)
			if _choices.is_empty():
				return
			_show_level(Level.CHOICE)
		Level.IMPERATIVE:
			if row == Order.ISSUE:
				_issue()
				return
			_ensure_draft()
			_choices = order_choices_for(row)
			if _choices.is_empty():
				return
			_part = Part.DO if row == Order.DO else Part.TO
			_order_choice = true
			_show_level(Level.CHOICE)
		_:
			if row < 0 or row >= _choices.size():
				_close_choice_list()
				return
			var picked: Dictionary = _choices[row]
			# A SKILLSET row lands NOTHING. It replaces this list with that skillset's
			# abilities, in the same column — so ✕ from there owes the player the `Do` list
			# back and not the row (see [method _on_cancelled]).
			if picked.has("drill"):
				_open_ability_list(int(picked["drill"]))
				return
			var apply: Callable = picked["apply"]
			apply.call()
			edited.emit(_slot)
			# Landing a choice drops the list and leaves the row standing, which now reads the
			# choice back in the very column it was opened from — the player sees what they
			# picked where they picked it, which is the whole point of the row doubling as the
			# readout. The row list is REPAINTED, not rebuilt: rebuilding would reset the glove
			# to row 0 and cost a box-open the player did not ask for.
			_close_choice_list()


## Replace the `Do` list with one skillset's abilities, under the SAME column.
##
## REPLACED and not stacked. Both lists hang off the `Do` column and both rise from the row
## window's top edge (`choice_container_for`), so a second box would land exactly on the first —
## dec. 1's "under its own column" leaves one box per column and no room for two. What stays
## behind is the ROW, which is the thing dec. 1 asked to keep legible.
##
## An EMPTY skillset leaves the `Do` list up rather than opening an empty box. It cannot
## normally happen — [method _skillset_rows] drops a row whose abilities are all unusable — but
## the guard is here rather than there because this is the press that would show the hole.
func _open_ability_list(skill_set_id: int) -> void:
	var next := _ability_choices(skill_set_id)
	if next.is_empty():
		return
	_skillset = skill_set_id
	_choices = next
	_show_level(Level.ABILITY)


## Put the glove back on the slot the player left, after a level rebuild put it on row 0.
func _restore_row_cursor() -> void:
	if _level != Level.ROW or _menu == null or not is_instance_valid(_menu):
		return
	for _i in range(_slot):
		_menu.move_down()


func _clear_slot() -> void:
	var list = character.gambits if character != null else null
	if list == null:
		return
	var fresh := GambitList.new()
	fresh.ensure_fixed_size()
	list.replace_at(_slot, fresh.get_at(0))
	edited.emit(_slot)


## Drop the choice list and put the pad back on what raised it.
func _close_choice_list() -> void:
	_free_choice()
	if _order_choice:
		_order_choice = false
		_show_level(Level.IMPERATIVE)
		return
	_level = Level.ROW
	if _menu != null and is_instance_valid(_menu):
		# The row window has the pad again, so it takes its colour and its glove back.
		_menu.set_backgrounded(false)
		_menu.set_cursor_visible(true)
		_menu.set_row_entries(row_entries(), _part)


func _on_cancelled() -> void:
	match _level:
		Level.ROW:
			dismissed.emit()
		Level.IMPERATIVE:
			_show_level(Level.ROW)
			_restore_row_cursor()
		Level.ABILITY:
			# ONE level, like every other ✕ on this screen (arm 7). The player pressed ○ on a
			# skillset to get here, so what ✕ owes them back is the list that skillset was a row
			# of — dropping them onto the row would unwind two presses for one.
			_reopen_do_list()
		_:
			_close_choice_list()


## Put the `Do` list back up after ✕ on an ability. Rebuilt rather than remembered, because the
## slot may have been edited under it (the imperative level composes into the draft through the
## very same catalogue) and a remembered list would offer choices against a gambit that moved.
func _reopen_do_list() -> void:
	_choices = order_choices_for(Order.DO) if _composing_order() else choices_for(Part.DO)
	if _choices.is_empty():
		_close_choice_list()
		return
	_show_level(Level.CHOICE)


# -----------------------------------------------------------------------------
# Guard seams.
# -----------------------------------------------------------------------------
func level() -> int:
	return _level


func slot() -> int:
	return _slot


func part() -> int:
	return _part


## The skillset the ABILITY level is drilled into, or `-1` when no ability list is up.
func skillset() -> int:
	return _skillset


## The menu a guard should read: the choice list when one is up, the row list otherwise — the
## same answer [method handle_action] routes to, so a test cannot assert against a window the
## pad is not reaching.
func menu() -> GambitSurfaceMenu:
	return _top_menu()


## The ROW list specifically, even with a choice open — for the guard that has to prove the row
## is STILL THERE behind the list (dec. 1), which `menu()` by construction cannot answer.
func row_menu() -> GambitSurfaceMenu:
	return _menu


## The order being composed, or null before the imperative level has been opened. For guards.
func draft():
	return _draft
