extends "res://src/scenes/GambitBattle.gd"

## The GAMBIT SURFACE, end to end on a real Gariland turn (#1007, ADR-0255) — the fourth
## adjustment type, driven through the real screen rather than around it.
##
## A subclass of the production host, like [GambitBattleTest] and [GambitDeploymentPickerTest]:
## what is under test is the HOST's wiring of the map-hosted Formation screen to a surface that
## edits [Character.gambits], so a harness that mounted its own coordinator would be testing the
## harness. [AdjustmentTurnTest] proves the turn contract in isolation and cannot see any of this.
##
##   1. **The menu carries a "Gambit" row, on the adjustment row set at its own home.** Four rows,
##      not the ROM's five: "Remove Unit" and "Order Unit" are roster verbs and there is no roster.
##   2. **The row is dispatched by NAME, not by index.** Row 3 is "Gambit" on
##      [constant StartActionMenu.ROWS_ADJUST] and "Remove Unit" on [constant StartActionMenu.ROWS],
##      so an index-keyed dispatch reaches a roster verb — ADR-0247's hazard, fired on purpose.
##   3. **It opens onto four EMPTY slots**, because a scenario-booted cast has empty gambit lists
##      (#892) and this screen is the first thing in the tree that can change that. Asserted, not
##      assumed: an editor that opened onto a seeded list would be reading somebody else's fixture.
##   4. **A press on a part lands an edit.** row 0's "Do" → "Attack" writes the Character's list,
##      and the row reads the new value back IN THE COLUMN it was picked for — the row IS the
##      readout, so a write that landed in a copy fails here. The row list stays standing behind
##      the open choice list (ADR-0268 dec. 1), which is asserted rather than assumed: a list
##      that tore the row down would be the superseded drill-down wearing a row's clothes.
##   5. **The edit crosses to the GPU on commit,** read back out of the gambit SSBO
##      (`snapshot_battle()["gambits"]`), not off the CPU object that was just written.
##   6. **Cancel takes it back on both sides,** including the battlefield [Unit]'s own
##      `gambit_list` — which binds at spawn and is never re-read from the Character (#894), so a
##      restore that minted a new list would leave the Unit holding the cancelled edit.
##   7. **✕ unwinds ONE level at a time** — choice → row → gone — rather than dropping the
##      player off the screen from a level in. TWO levels since ADR-0268 dec. 1 superseded
##      ADR-0255 dec. 2's three.
##  15. **Every part's list opens under its OWN column and its glyphs land inside its own
##      scissor** — asked of three parts in a row, because the FIRST list always drew and the
##      freeze only shows from the second on (#1081). The one arm here that is coordinates
##      rather than state; see its own docstring for why that distinction is the whole ticket.
##  14. **The row grammar**: ←/→ walk the parts and CLAMP at both ends, ○ on the leftmost part
##      TOGGLES `Gambit.enabled` instead of opening a list (dec. 4), and L1/R1 raise and lower
##      the focused slot (dec. 6) — a real verb, because slot order IS priority (rule A1).
##  16. **The safety net is the LAST row, and it is inert** (ADR-0270). ADR-0048 injects
##      `Attack / Nearest Foe / Always` below everything the player authored and used to hide it;
##      it is now a row, DIM under the glove, with a BLANK enable cell. ←/→ and L1/R1 are
##      REFUSED on it and ○ takes nothing, because there is no slot on the other side of those
##      verbs. Read against `GambitEncoder.safety_net_gambit()` rather than three literal
##      strings — a readout that restates a value in its own words is the drift this row exists
##      to close.
##  15. **The `Do` list is TWO deep.** No bare ability is offered at its top level: every ability
##      is behind the SKILLSET row that owns it, the ROM's own two-level action menu. ○ on a
##      skillset opens its abilities in the same column with the row still standing behind them,
##      ✕ from there returns to the `Do` list and not to the row, and the ability that lands
##      writes the Character's slot. The partition is asserted as a partition — every top-level
##      row is the clear, a verb, or a drill — because a list that offered BOTH shapes would pass
##      every "the drill works" assertion while still burying the abilities it duplicated.
##
## Arms 8-11 are the IMPERATIVE (#1006, design §5) — the one-shot top-priority order — and they are
## here rather than in a scene of their own because they need exactly this setup: a Gariland turn,
## the real coordinator, the real surface (test charter clause 13). [AdjustmentTurnTest] proves the
## ledger's arithmetic against no scene at all and is structurally unable to see any of the below.
##
##   8. **The slot level carries a fifth row that is NOT a slot.** Four slots plus one imperative
##      row reading the unit's charges. `slot_rows()` still returns four, because a fifth entry in
##      the LIST is not a fifth entry in the unit's `GambitList`.
##   9. **Composing an order is free, and it does not touch the unit's rules.** Picking a Do on the
##      imperative level moves the DRAFT and leaves slot 1 exactly as arm 4 left it — the
##      implementation that reused the slot cursor writes the player's rule instead, which every
##      other assertion on this screen would happily pass.
##  10. **Issuing spends exactly one charge**, arms the order, and the slot-level row reads it back
##      — so the cost and the consequence are both visible before the turn is committed.
##  11. **The order crosses as a LEAD entry, and the action takes it.** The gambit SSBO changes at
##      commit; driving the host's real `action_committed` handler puts it back to the buffer the
##      unit's own four slots encode to. Read off the SSBO, because "above the standing list" is a
##      claim about the buffer and about nothing else.
##  12. **Cancel refunds the charge** (design §4: "or cancel becomes a trap"), on the same second
##      turn arm 6 uses for the Character half of the same rule.
##
## Run: "$GODOT" --path . res://tests/GambitSurfaceTest.tscn   (timeout, not --quit-after)

# test-kind: gpu
# seeded-break: StartActionMenu.ROWS_ADJUST row 3 "Gambit" -> "Remove Unit" — assertion
#   "row 3 is the gambit door" reds with `got=Remove Unit want=Gambit`. MEASURED, not guessed:
#   baseline 45/0, seeded 44/1.
#
# ⚠️ THE BASELINE MOVED. ADR-0268's row reshape took this rig from 94/0 to 122/0 (arm 14 is new,
# and arms 3/4/7 grew assertions the drill-down had nowhere to put). The five seed measurements
# below were taken at 94 and their DELTAS still hold — each still reds only the arms named — but
# the totals are stale. Re-measure before quoting a total, not before trusting a delta.
#
# ⚠️ AND MOVED AGAIN: ADR-0268 dec. 9's two-level `Do` list took it from 122/0 to 146/0
# (arm 16 is new). One more seed, MEASURED against that 146:
#   delete the `Level.ABILITY` case from GambitSurface._on_cancelled       146 -> 138/6
#     — ✕ off the ability list then unwinds TWO levels for one press, dropping the player onto
#     the row. Only arm 16 reds, and it reds on the four assertions after the ✕ as well as on
#     the ✕ itself, because everything past it is asking about a list that is no longer up.
#
# ⚠️ AND AGAIN: ADR-0270's visible safety net took it from 146/0 to 164/0 (arm 17 is new, and
# arms 3/4 count two non-slot rows now instead of one). Its seed, MEASURED against that 164:
#   delete the `row == safety_net_row_index()` early return in GambitSurface._on_chosen
#                                                                        164 -> 134/15
#     — ○ on the net then falls into the imperative branch (`row >= VISIBLE_SLOTS`). Arm 17
#     reds FIRST and the count is 15 rather than its own 18 because the surface is left on a
#     level the arms after it do not expect: a cascade, not fifteen independent findings.
#
# ⚠️ AND ONCE MORE, at the merge: #1082's coordinates arm landed as arm 15 and the two arms above
# renumbered around it (Do-list 15 -> 16, safety net 16 -> 17), taking the rig from 164/0 to
# **189/0** — MEASURED on the merge, not added up. The three run ENABLE -> ENABLE -> Do -> Do, so
# each still enters on the cursor its own comment claims and arm 7 still starts on `Do`.
#
# Five more, measured against the #1006 arms at baseline 94/0, each reddening only its own arms:
#   `if _composing_order():` -> `if false:` in GambitSurface._gambit()      94 -> 89/5
#     — an imperative composed on the SELECTED SLOT; the assertion that names it is "and slot 1
#     is UNTOUCHED — an order is not a slot" (got=2 want=0), the ONLY arm that can see the
#     player's own rule being overwritten.
#   delete `_sweep_imperatives()` from GambitBattle._process                94 -> 93/1
#     — arm 13 alone, which is why it was worth writing: every other imperative arm calls a
#     handler directly, so a watchdog wired to nothing is green everywhere else.
#   `if spent > 0:` -> `if false:` in ImperativeGambits.cancel()  AdjustmentTurnTest 118 -> 114/4
#   lead appended last in GambitEncoder.encode_for_unit           AdjustmentTurnTest 118 -> 116/2
#   `dead_pool` -> `false` in ImperativeGambits.expire            AdjustmentTurnTest 118 -> 116/2
#
# ⚠️ THE FIRST SEED TRIED DID NOT RED — IT HUNG, and that is worth knowing before trusting a
# seed on this rig. Breaking the dispatch instead of the row set (`MENU_LABEL_STATE`'s "Gambit"
# key -> "Remove Unit", i.e. exactly the index-keyed dispatch item 2 above fires on purpose)
# leaves the menu offering a door that opens nothing, and the rig then spins its
# iteration-counted belt waiting for a state that never arrives. The suite scores that HUNG,
# not FAIL. A seed that hangs still proves the test CAN fail, but it proves it slowly and
# through a different channel, so the break named above is the row set — the one that reaches
# an assertion and prints it.

const StartActionMenuScript = preload("res://src/ui3/detail/StartActionMenu.gd")
## The coordinator's own script, for its State enum. NOT re-`preload`ed under
## `FormationDetailTransitionScript`: the parent already declares that name, and re-declaring it
## is a PARSE error that takes the whole rig down — which exits 0 with no verdict printed, so the
## suite reads it as a pass. Found by running it.
const FDT = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const GambitSurfaceScript = preload("res://src/ui3/detail/GambitSurface.gd")
const GambitSurfaceMenuScript = preload("res://src/ui3/detail/GambitSurfaceMenu.gd")
const GambitEncoderScript = preload("res://src/gpu/GambitEncoder.gd")
const ImperativeGambitsScript = preload("res://src/gpu/ImperativeGambits.gd")

const AbilityDatabase = ExMateriaAlmanac.AbilityDatabase
const Gambit = ExMateriaAlmanac.Gambit
const GambitList = ExMateriaAlmanac.GambitList
## `TargetSelector` is NOT re-declared here — `GambitBattle`, the parent, already carries it,
## and a second `const` of the same name is a PARSE error that takes the whole script down. The
## scene then boots the PARENT, which runs a battle and never reaches an assertion: no FAIL, no
## PASS, just a 4-minute hang. Reached for once already.
const GambitCondition = ExMateriaAlmanac.GambitCondition


## A bare holder for arm 2's `authored_gambits` probe. That function reads `unit.gambit_list` and
## nothing else, so the cheapest honest subject is an object that has one — a real [Unit] would
## need a battle, and the assertion is about a FILTER over an array.
class GambitProbeUnit:
	extends RefCounted
	var gambit_list = null


const SCENARIO := 9
const BATTLE_SEED := 424242
## Belt on every wait. Counted in ITERATIONS, not wall clock: a slow pass on a loaded box must not
## read as a hang, and a hang is a worse verdict than a failure because nothing names it.
const MAX_WAIT_FRAMES := 12000

## The "Gambit" row's index in [constant StartActionMenu.ROWS_ADJUST]. Named, not inlined, and
## deliberately the SAME index the ROM's five give to "Remove Unit" — see arm 2.
const GAMBIT_ROW := 3

var _passed: int = 0
var _failed: int = 0
## The turn this rig steers, held open for the length of the run.
var _taker: int = -1


func get_test_name() -> String:
	return "GambitSurfaceTest"


func _ready() -> void:
	DebugConfig.combat_seed = BATTLE_SEED
	DebugConfig.active_scenario_id = SCENARIO
	DebugConfig.combat_autostart = true

	await super._ready()

	if director == null or assignment == null or _formation_map_screen == null:
		print("[FAIL] GambitSurfaceTest: the host did not boot")
		get_tree().quit(1)
		return

	await _boot_to_a_steerable_turn()
	if _taker >= 0:
		await _arm_1_and_2_the_menu_carries_the_gambit_row()
		await _arm_3_it_opens_onto_four_empty_slots()
		await _arm_4_the_drill_lands_an_edit()
		await _arm_14_the_row_is_walked_and_reordered()
		await _arm_15_every_part_opens_under_its_own_column()
		await _arm_16_the_do_list_is_two_deep()
		await _arm_17_the_safety_net_is_the_last_row_and_is_inert()
		await _arm_7_cancel_unwinds_one_level_at_a_time()
		await _arm_8_and_9_composing_an_order_is_free()
		await _arm_10_issuing_spends_exactly_one_charge()
		_arm_5_the_edit_crosses_on_commit()
		await _arm_11_the_order_is_a_lead_entry_and_the_action_takes_it()
		_arm_13_the_watchdog_rides_the_frame()
		await _arm_6_and_12_cancel_takes_it_back_on_both_sides()

	print("\n=== GambitSurfaceTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0 and _failed == 0:
		print("[FAIL] GambitSurfaceTest: ran zero assertions")
		get_tree().quit(1)
		return
	if _failed > 0:
		print("[FAIL] GambitSurfaceTest")
		get_tree().quit(1)
	else:
		print("[PASS] GambitSurfaceTest: the gambit surface has a home, its ROW is walked with"
			+ " ←/→ and reordered with L1/R1 (ADR-0268), a part edited on it lands in the gambit"
			+ " SSBO at commit, and an imperative leads that buffer until it is spent")
		get_tree().quit(0)


# === Boot =====================================================================

## Deploy, start, and wait for a turn on a unit the player may steer. A commandable turn is NOT
## auto-passed by the host (`_on_turn_opened` defers `_pass_turn` only for the units that are not
## yours), so it stays open for as long as this rig needs it.
func _boot_to_a_steerable_turn() -> void:
	if not _deployed:
		_true(commit_deployment(), "the assignment committed and the battle started")
	var frames := 0
	while frames < MAX_WAIT_FRAMES and not (director.state() == TurnDirector.State.TURN_OPEN
			and _commandable.has(director.taker())):
		await get_tree().process_frame
		frames += 1
	var open := director.state() == TurnDirector.State.TURN_OPEN and _commandable.has(director.taker())
	_true(open, "a turn opened on a unit the player may steer, within %d frames" % frames)
	if not open:
		return
	_taker = director.taker()
	_true(adjustment.is_open() and adjustment.taker() == _taker,
		"the adjustment window opened on the taker")

	# THE TURN-OPEN BEAT OWNS THE FIRST ~18 FRAMES (`docs/TURN-OPEN-BEAT-DESIGN.md`), and every
	# arm below reaches the screen through a KEY. The camera travels to the taker and the cursor
	# is deaf for the duration — "there is no skip" is the design, not an oversight — so a rig
	# that presses △ six frames after the turn opens is simulating a player who cannot exist, and
	# its press is dropped. It is dropped ONCE and never re-sent, so the failure is not a slow
	# menu: it is `_wait_until` burning its whole 12,000-frame budget on a menu that will never
	# open, twice over, which the runner scores HUNG rather than FAIL.
	var frames_2 := 0
	while frames_2 < MAX_WAIT_FRAMES and _turn_beat_running():
		await get_tree().process_frame
		frames_2 += 1
	_true(not _turn_beat_running(),
		"the turn-open beat landed within %d frames, so a key press can reach the cursor" % frames_2)


# === Arms =====================================================================

func _arm_1_and_2_the_menu_carries_the_gambit_row() -> void:
	# The ROW SET question, asked before the screen is even open: it is the host's standing
	# configuration, not something a press produces.
	_eq(_formation_map_screen.action_rows, StartActionMenuScript.ROWS_ADJUST,
		"the host arms the adjustment row set")
	_eq(StartActionMenuScript.ROWS_ADJUST.size(), 4, "which is four rows, not the ROM's five")

	# ARM 2, and it is a one-line assertion about two constants because that is exactly the shape
	# of the hazard: the two row sets DISAGREE at this index, so an index-keyed dispatch that
	# happened to work on the ROM's five reaches a roster verb here.
	_eq(StartActionMenuScript.ROWS_ADJUST[GAMBIT_ROW], "Gambit", "row 3 is the gambit door")

	# THE EMPTY GAMBIT IS THE DEFAULT-CONSTRUCTED ONE, and it was not. `Gambit.is_empty` describes
	# "Always: Wait on Self"; `Gambit._init` set `action_target` to `triggering()`, which
	# `is_empty` rejects — so the constructor could not build the object its own predicate
	# describes, and `GambitList` carried a second, disagreeing definition to paper over it. One
	# definition now, and this is the assertion that says so.
	_true(Gambit.new().is_empty(),
		"a default-constructed Gambit IS the empty gambit — one definition of empty, in the"
		+ " constructor, with `GambitList._create_empty_gambit` deferring to it")

	# ==========================================================================================
	# `is_empty` IS DIRECTION-TESTED, and that is the whole point of this block (ADR-0283 dec. 2).
	#
	# `GambitEncoder.authored_gambits` filters on this predicate BEFORE encoding, so it decides
	# whether a slot reaches the GPU at all — and it fails two ways, not one:
	#
	#   too PERMISSIVE → a rule the player authored is dropped from the buffer. The row reads
	#                    back correctly and the unit is not under it.
	#   too STRICT     → a blank slot encodes as a real rule and occupies a priority (rule A1),
	#                    which the slots below it then never get.
	#
	# A guard that only asserted "the blank slot is empty" passes a predicate that returns true
	# for EVERYTHING, and a guard that only asserted "the authored slot is not" passes one that
	# returns false for everything. Both arms, over the same predicate, or neither is tested.
	# ==========================================================================================
	_eq(Gambit.new().conditions.size(), 0,
		"and its `conditions` array is EMPTY, not `[Always]` — one spelling of 'no condition'"
		+ " in the domain, because the screen stopped offering `Always` as a named choice")

	# THE `ALWAYS` SPELLING IS STILL EMPTY. #895's mutation operators write it and every save
	# from before ADR-0283 carries it; a predicate that rejected them would make those saves'
	# blank slots encode as rules.
	var legacy_blank := Gambit.create(TargetSelector.self_(), [GambitCondition.always()],
		Gambit.ActionKind.WAIT, -1, TargetSelector.self_())
	_true(legacy_blank.is_empty(),
		"`Wait / Self / [Always]` — the pre-ADR-0283 spelling — is STILL empty, or every old"
		+ " save's blank slots start occupying priority")

	# 🔴 THE ARM THAT MATTERS. `Attack / Nearest Foe` with NO condition is the player's own
	# sentence (ADR-0283's third worked example: *"Attack  nearest enemy  —  —"*). A predicate
	# rewritten as "blank conditions means blank slot" deletes it, silently, from the buffer —
	# and the row keeps reading `Attack / Nearest Foe / — / —` while the unit stands there.
	var unconditional := Gambit.create(GambitOptions.foe_pool(), [],
		Gambit.ActionKind.ATTACK, -1, GambitOptions.foe_pool())
	_true(not unconditional.is_empty(),
		"`Attack / Nearest Foe / — / —` is NOT empty — it is an unconditional RULE, and it is"
		+ " the row a blank-means-empty predicate drops from the buffer while the row still"
		+ " reads it back")

	# The other direction on the same axis: WAIT is the verb that makes a row say nothing, but
	# only with nothing else said either. `Wait when I am hurt` blocks every lower slot on
	# purpose.
	var conditional_wait := Gambit.create(TargetSelector.self_(),
		[GambitCondition.target_hp_below(50.0)],
		Gambit.ActionKind.WAIT, -1, TargetSelector.self_())
	_true(not conditional_wait.is_empty(),
		"`Wait / Self / My / HP<50%` is NOT empty either — the verb alone does not make a row"
		+ " blank, and this one deliberately blocks the slots beneath it")

	# AND THE FILTER AGREES WITH THE PREDICATE. Asserted through `authored_gambits` and not only
	# through `is_empty`, because that function is the one the encoder calls and a filter that
	# read the field directly would be a second definition of empty.
	var probe_list := GambitList.new()
	probe_list.ensure_fixed_size()
	probe_list.replace_at(0, unconditional)
	probe_list.replace_at(1, legacy_blank)
	var probe_unit := GambitProbeUnit.new()
	probe_unit.gambit_list = probe_list
	var kept: Array = GambitEncoderScript.authored_gambits(probe_unit)
	_eq(kept.size(), 1,
		"so `authored_gambits` keeps exactly the ONE authored rule out of a list holding it and"
		+ " three blanks — %d kept" % kept.size())
	if kept.size() == 1:
		_eq(kept[0].action_kind, Gambit.ActionKind.ATTACK,
			"and the one it kept is the Attack, not a blank that slipped the filter")
	_eq(StartActionMenuScript.ROWS[GAMBIT_ROW], "Remove Unit",
		"and row 3 of the ROM's five is a DIFFERENT verb — the index means nothing across sets")

	await _open_screen_on_taker()
	var menu = _formation_map_screen.action_menu()
	_true(menu != null, "○ on the taker opens the screen with its menu up")
	if menu == null:
		return
	_eq(menu.rows, StartActionMenuScript.ROWS_ADJUST, "the menu built on the adjustment rows")
	_eq(menu.row_count(), 4, "four rows")
	_true(menu.location == StartActionMenuScript.LOC_ADJUST_DETAIL
			or menu.location == StartActionMenuScript.LOC_ADJUST_LEFT
			or menu.location == StartActionMenuScript.LOC_ADJUST_RIGHT,
		"at a FOUR-row home (%s) — a four-row list in a five-row box leaves a dead row of frame"
			% menu.location)
	_true(not menu.is_row_disabled(GAMBIT_ROW),
		"and the Gambit row is live — it is this unit's turn")


func _arm_3_it_opens_onto_four_empty_slots() -> void:
	await _enter_gambit_row()
	var surface = _formation_map_screen.gambit_surface()
	_true(surface != null, "○ on the Gambit row opens the surface")
	if surface == null:
		return
	_eq(_formation_map_screen.current_state(), FDT.State.GAMBIT,
		"and the coordinator is on the GAMBIT screen")
	_eq(surface.level(), GambitSurfaceScript.Level.ROW, "showing the row level")
	var rows: Array = surface.slot_rows()
	_eq(rows.size(), GambitList.VISIBLE_SLOTS, "with one row per gambit slot")
	var empty := 0
	for r in rows:
		if String(r).ends_with("---"):
			empty += 1
	_eq(empty, GambitList.VISIBLE_SLOTS,
		"and every slot reads EMPTY — a scenario-booted cast has no authored gambits (#892)")

	# THE ROW IS FOUR PARTS, READ ACROSS (ADR-0268 dec. 1). Asserted on the dicts the surface
	# hands the widget, because that is where the sentence is assembled — the widget renders
	# what it is given and a guard reading pixels could not say which part was which.
	var built: Array = surface.row_entries()
	_eq(built.size(), GambitList.VISIBLE_SLOTS + 2,
		"four slot rows plus the imperative's and the safety net's — two rows that are not"
		+ " slots, and are the only two rows here in no `GambitList`")
	var first: Dictionary = built[0]
	for key in ["enable", "do", "to", "iff"]:
		_true(first.has(key), "an empty slot still carries its '%s' part — the parts are what" % key
			+ " ←/→ walk, and on a scenario-booted cast EVERY row is empty")
	_eq(String(first["enable"]), "1",
		"whose leftmost cell is the slot NUMBER, not an enable mark (ADR-0268 dec. 13) — slot"
		+ " order IS priority (rule A1), so the number is the thing L1/R1 change")
	_eq(String((built[GambitList.VISIBLE_SLOTS - 1] as Dictionary)["enable"]), "4",
		"and it counts to the last slot, 1-based as the player reads them")
	_eq(int(first.get("extra", 0)), 0, "with no `+N` — one condition, nothing hidden (dec. 3)")
	_true(built[GambitList.VISIBLE_SLOTS].has("text"),
		"the imperative's row is a PLAIN string — an order is not a four-part sentence")

	# ARM 8. The fifth row is the imperative's and it is NOT a slot: `slot_rows()` above still
	# answers four, because the unit's `GambitList` still has four. A row on the list and an entry
	# in the list are different things, and conflating them is what would make an imperative cost
	# the player a rule.
	_true(surface.offers_imperative(),
		"the battle host supplied the imperative ledger — a roster host supplies none")
	_eq(surface.imperative_unit, _taker, "aimed at the taker, by unit index")
	_eq(surface.imperative_row(), "! Imperative (%d)" % imperatives.allowance(),
		"and the fifth row offers the unit's full per-battle allowance")

	var menu = surface.menu()
	_true(menu != null, "the surface mounted its list")
	if menu != null:
		_eq(menu.row_count(), GambitList.VISIBLE_SLOTS + 2,
			"SIX rows: the four slots, the order, and ADR-0270's safety net")
		_eq(menu.visible_row_names().size(), GambitSurfaceMenuScript.VISIBLE_ROWS,
			"of which the window renders its five — the sixth is one ↓ away, which is the"
			+ " price of a 256-px frame whose bottom border is already at y=238")
		_eq(String(menu.visible_row_names()[GambitList.VISIBLE_SLOTS]), surface.imperative_row(),
			"with the order last")
		_true(menu.header_text_materials().is_empty(),
			"under NO title — the adjustment row that opened this window already said 'Gambit',"
			+ " and the 8-px band it was repeating that in is the row budget's"
			+ " (ADR-0255 Amendment 1)")
		# The §15.21 twins are CLUT reads, not colour choices: LIT is 0x7C3C indices 1/2/3 and
		# DIM the same clut's 5/6/7 (the blitter's `bVar1 += shade * 4` shade shift), so each
		# backgrounded twin must be `BG_FOR_7C3C` at the SAME index. Asserted rather than trusted
		# — a hand-typed palette that drifts one channel still renders, just wrongly.
		for pair in [[GambitSurfaceMenuScript.LIT_INKS_BG, GambitSurfaceMenuScript.LIT_CLUT_INDICES],
				[GambitSurfaceMenuScript.DIM_INKS_BG, GambitSurfaceMenuScript.DIM_CLUT_INDICES]]:
			var band: Array = pair[0]
			var idx: Array = pair[1]
			for k in idx.size():
				_eq(Color(band[k]), Color(UIWindowPalettes.BG_FOR_7C3C[int(idx[k])]),
					"backgrounded ink %d is BG_FOR_7C3C[%d]" % [k, int(idx[k])])
		_eq(menu.title_band(), 0.0,
			"so the title band collapses — the rows start at the frame's own inset, not 8 px"
			+ " below a band nothing occupies")
		_true(not menu.cursor_materials().is_empty(), "with the glove on it")


func _arm_4_the_drill_lands_an_edit() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null:
		_true(false, "arm 4 needs the surface open")
		return
	var character = FormationMapHost.character_for_unit(units[_taker])
	_true(character != null and character.gambits != null, "the taker has a gambit list to edit")
	if character == null or character.gambits == null:
		return

	# ○ on the focused PART of the focused ROW. There is no level between them any more
	# (ADR-0268 dec. 1 supersedes ADR-0255 dec. 2): the row IS the sentence, so the press that
	# used to open a slot's part list now opens the part's choice list directly.
	_eq(surface.part(), GambitSurfaceScript.Part.DO, "the row opens with the cursor on Do")
	await _press(KEY_ENTER)
	_eq(surface.level(), GambitSurfaceScript.Level.CHOICE, "○ on a part offers its choices")
	_eq(surface.slot(), 0, "for the slot the glove was on")

	# THE ROW IS STILL THERE (dec. 1: "with the row still legible behind it"). A list that tore
	# the row down would be the drill-down this ADR supersedes, wearing a row's clothes — and
	# every other assertion in this arm would pass exactly the same either way.
	_true(surface.row_menu() != null and is_instance_valid(surface.row_menu()),
		"and the ROW list is still standing behind it")
	_true(surface.menu() != surface.row_menu(),
		"— a SECOND window, which is what makes 'behind' possible at all")
	_true(surface.row_menu().row_count() == GambitList.VISIBLE_SLOTS + 2,
		"still showing all six rows")

	# ←/→ are REFUSED by an open list, and refused is not swallowed. A column has no horizontal
	# axis; `handle_action` answering false is what reaches the coordinator's `_refuse`.
	_true(not surface.handle_action(&"ui_left"),
		"← on an open choice list is REFUSED — a column has no horizontal axis")
	_true(not surface.handle_action(&"rotate_camera_cw"),
		"and so is L1: a choice is in no slot, so it has no priority to raise")

	var menu = surface.menu()
	_true(menu != null and menu.row_count() > 0, "the choice list is not empty")
	if menu == null:
		return
	_eq(String(menu.entries[menu.entries.size() - 1]), GambitSurfaceScript.CLEAR_LABEL,
		"whose LAST row is the clear — the destructive verb is NAMED, not reached by setting"
		+ " three parts back one at a time, and it TRAILS rather than leads because the head of"
		+ " an open list is where the cursor already rests (ADR-0268 Amendment 3)")
	await _choose_row_named("Attack")

	# THE WRITE. Read off the Character, which is the durable representation (ADR-0005) — not off
	# the surface, which would only prove the surface remembers what it was told.
	var g = character.gambits.get_at(0)
	_true(g != null, "slot 0 holds a gambit")
	if g == null:
		return
	_eq(g.action_kind, Gambit.ActionKind.ATTACK, "and its action is now ATTACK")
	_true(not g.is_empty(), "so the slot is no longer empty")

	# THE AIM CAME WITH THE VERB. `Attack` landed on an EMPTY slot used to leave `action_target`
	# at Self, so a fresh slot's first press produced `Attack / Self / Always` — a rule that reads
	# back correctly, encodes cleanly, and attacks the unit that owns it. The seeded aim is
	# `Nearest Foe`, the same aim ADR-0048's safety net carries, which is the sentence this very
	# screen is already showing one row below in dim as what the unit does anyway.
	#
	# Asserted through the ROW's own readout as well as the field, because the two can differ:
	# `_target_text` probes `GambitOptions.targets()` and falls back to "Self" for any selector
	# that catalogue cannot name, so an aim built from a second literal would store correctly and
	# render as the default that was just fixed.
	_eq(String((surface.row_entries()[0] as Dictionary)["to"]), "Foe",
		"and the slot came AIMED — `Attack` on an empty slot seeds the safety net's own aim."
		+ " `Foe` and not `Nearest Foe` since ADR-0285: the net's selector is NEAREST_FIRST,"
		+ " the pool the kernel retries at rank 1, 2, 3…, and the strict row is a DIFFERENT"
		+ " selector now that the column can tell them apart")
	var aim = g.action_target
	var want_aim = GambitOptions.foe_pool()
	_true(aim != null and aim.pool_type == want_aim.pool_type
			and aim.team_filter == want_aim.team_filter
			and aim.resolution == want_aim.resolution,
		"which is the SAME selector the `To` list's own `Foe` row builds")
	_eq(surface.level(), GambitSurfaceScript.Level.ROW,
		"landing a choice drops the list and leaves the row")
	_eq(String((surface.row_entries()[0] as Dictionary)["do"]), "Attack",
		"which now READS BACK the choice in the very column it was picked for")
	_true(not String(surface.slot_rows()[0]).ends_with("---"),
		"and the slot row no longer says empty")

	# 🔴 AND THE SUBJECT CAME WITH IT (ADR-0283 dec. 3). `Attack` was pressed on an EMPTY slot,
	# so `_seed_aim` re-aimed it — and `condition_target` had to travel with the aim, because a
	# BLANK condition leaves the subject MIRRORING it. Left at the constructor's SELF, this slot
	# would gate on the ACTOR existing (always true) and then fire at a foe pool it never
	# checked was there: `select_target` answers the caster, `candidate >= 0`, no
	# VERDICT_NO_CANDIDATE, and the action's own search fails instead.
	#
	# `_seed_aim` is the SECOND place `action_target` is written — the `To` apply is the first,
	# and it asks the same question. This arm is the one that reaches the second, because it is
	# the only one that presses a verb onto a slot with no aim of its own.
	var subj = g.condition_target
	_true(subj != null and subj.pool_type == want_aim.pool_type
			and subj.team_filter == want_aim.team_filter
			and subj.resolution == want_aim.resolution,
		"and `condition_target` MIRRORS that seeded aim — a blank condition does not clear the"
		+ " subject, it points it at the aim, or the slot gates on the actor and fires at a pool"
		+ " it never tested")
	# …AND THE COLUMN SAYS SO. It read BLANK here until ADR-0283 dec. 3 was amended, which made
	# this pair of assertions the defect in miniature: dec. 3's surviving half (above) pins the
	# field mirroring the aim *because otherwise the slot gates on the actor and fires at a pool
	# it never tested*, and this one used to pin the screen hiding that very field.
	_eq(String((surface.row_entries()[0] as Dictionary)["subj"]), GambitOptions.SUBJECT_THEIRS,
		"and the COLUMN reads it back — `Their`, the pool the blank-condition row is gated on,"
		+ " which is the field the assertion directly above just proved is load-bearing")
	_eq(String((surface.row_entries()[0] as Dictionary)["iff"]), GambitOptions.BLANK,
		"— `Attack / Nearest Foe / — / —`, which is ADR-0283's third worked example and the row"
		+ " a blank-means-empty `is_empty` would drop from the buffer (see arm 2)")

	# ==========================================================================================
	# RE-AIMING A `Their` ROW — THE SEQUENCE, driven through the REAL applies.
	#
	# ⚠️ THIS ARM USED TO RE-AIM TO `Them`, AND `Them` IS NO LONGER ON THE LIST. ADR-0283 kept
	# the row on the reasoning that the fourth column NAMES what `Them` forwards to, so the row
	# could stay and say so. That reasoning does not survive the press: landing `Them` re-mirrors
	# the subject, `mirror_of` refuses the cycle and falls back to the ACTOR, so what the player
	# gets is `Self` under a word that says otherwise — #1125's own opening complaint, produced
	# by the row that was kept to answer it. The grade says so now (`AIM_UNNAMED` for every
	# `Them` aim) and `targets_for` therefore withholds it; both halves are asserted just below,
	# and `GambitEncoderTest` owns the exhaustive version.
	#
	# What the arm still tests is the SEQUENCE, which is reachable through any aim change: two
	# presses, in order, and the order is the whole assertion — a build that asked
	# `_subject_mirrors_aim` AFTER the write cannot tell a mirrored subject from an unmirrored
	# one, because by then the old aim is gone. Driven by calling the part's own `apply` — the
	# same Callable ○ calls — rather than by re-implementing it, so this tests the behaviour and
	# not a transcription of it.
	_apply_choice(surface, GambitSurfaceScript.Part.IF, "HP<50%")
	_eq(String((surface.row_entries()[0] as Dictionary)["subj"]), GambitOptions.SUBJECT_THEIRS,
		"landing a test on a row aimed at a FOE seeds `Their` — the aim names somebody other"
		+ " than the actor, so that is who the question is most likely about (dec. 3)")
	# THE ROW IS GONE FROM THE LIST — asserted through the surface's OWN choice list, because
	# `GambitOptions.targets_for` being right is a different claim from this screen asking it.
	var to_names: Array = []
	for c in surface.choices_for(GambitSurfaceScript.Part.TO):
		to_names.append(String(c["name"]))
	_true(not to_names.has("Them"),
		"the `To` list must NOT offer `Them` — choosing it re-mirrors the subject onto a"
		+ " TRIGGERING aim, `mirror_of` refuses the cycle, and the player is left holding the"
		+ " `Self` row under a name that hides it")
	_true(to_names.has("Foe") and to_names.has("Nearest Foe") and to_names.size() >= 4,
		"…and the list is NOT empty while saying so — an absence read off a list nothing"
		+ " populated is the same string as an absence read off a working one (got %s)"
		% str(to_names))
	_eq(GambitOptions.aim_verdict(Gambit.ActionKind.ATTACK, -1, TargetSelector.triggering(),
			GambitOptions.foe_pool()), GambitOptions.AIM_UNNAMED,
		"…and the GRADE is what withholds it, not a special case in the list — the offer list"
		+ " and the grader stay one decision (ADR-0276)")
	# …and the CUT that made the row survivable is still in place, because a save, an imperative
	# or #895's operators can still hold a TRIGGERING aim even though nobody can author one.
	_true(GambitOptions.mirror_of(TargetSelector.triggering()).pool_type
			== TargetSelector.PoolType.SELF,
		"`mirror_of(Them)` must still fall back to the ACTOR — an unauthorable row is not an"
		+ " unreachable one, and a copied TRIGGERING subject encodes TARGET_THEM, which"
		+ " `select_target` answers -1 for on every tick forever")

	# THE SEQUENCE, on an aim change that IS reachable: `Foe` -> `Ally` must carry the mirrored
	# subject with it, which only works if `_subject_mirrors_aim` is asked BEFORE the write.
	_apply_choice(surface, GambitSurfaceScript.Part.TO, "Ally")
	var g2 = character.gambits.get_at(0)
	_eq(String((surface.row_entries()[0] as Dictionary)["subj"]), GambitOptions.SUBJECT_THEIRS,
		"re-aiming a mirrored row keeps the subject mirrored — it still reads `Their`")
	_true(g2 != null and g2.condition_target != null
			and g2.condition_target.team_filter == TargetSelector.TeamFilter.FRIENDLY,
		"read off the FIELD and not only the column: the subject FOLLOWED the aim onto the ally"
		+ " pool, so the row tests the pool it acts on. A build that asked `_subject_mirrors_aim`"
		+ " after the write would leave it on the FOE pool while the column still said `Their`")

	# RESTORE, so the arms after this one see the row they were written against — and the
	# restore is itself the blank round-trip: clearing the condition must blank the `If` column
	# and LEAVE THE SUBJECT READABLE.
	_apply_choice(surface, GambitSurfaceScript.Part.TO, "Foe")
	_apply_choice(surface, GambitSurfaceScript.Part.IF, GambitOptions.BLANK)
	var back: Dictionary = surface.row_entries()[0]
	_eq(String(back["to"]), "Foe", "restored: the aim reads Foe again")
	_eq(String(back["iff"]), GambitOptions.BLANK, "the condition is blank again")
	# 🔴 THE TWO DO NOT CLEAR TOGETHER, and this arm asserted that they did until the display
	# half of the left-to-right bug was fixed. Blanking the subject alongside the condition was
	# ADR-0283 dec. 3's rule on the grounds that it "would name a field the player cannot act
	# on" — but the field is the row's GATE with no condition attached (`select_target` on the
	# CONDITION target writes `VERDICT_NO_CANDIDATE` before `check_gambit_conditions` is
	# consulted at all), which is exactly why dec. 3's OTHER half — the line below — insists it
	# mirrors rather than clears. Printing blank over a live gate was the readout-that-lies shape.
	_eq(String(back["subj"]), GambitOptions.SUBJECT_THEIRS,
		"and the SUBJECT still reads `Their` — it is the pool this now-unconditional row is"
		+ " gated on, and a blank there would hide the gate the next assertion reads off the"
		+ " field")
	_true(character.gambits.get_at(0).condition_target.pool_type
			== TargetSelector.PoolType.TEAM_FILTER,
		"while the FIELD mirrors the aim rather than clearing to SELF, or the slot would gate on"
		+ " the actor existing and fire at a pool it never tested")

	# ==========================================================================================
	# AUTHORING IN READING ORDER — `Do`, `To`, `Subject`, `If` — AND THE SUBJECT SURVIVING IT.
	#
	# 🔴 THE REPORTED BUG: *"when I enter gambits left-to-right I can't choose 'my' or 'their'"*.
	# The `If` apply called `_seed_subject`, which re-derives the subject from the aim — so the
	# `Subject` press one column earlier was silently overwritten, and BOTH choices came out
	# `Their`. The column was INERT in the exact order the four-column layout asks the row to be
	# read, and it worked only if the player authored `If` BEFORE `Subject`.
	#
	# Invisible AS WELL AS discarded, and that half outlived the fix. `a8e001303` stopped the
	# `If` press overwriting the subject and closed the ticket; `GambitOptions.subject_label`
	# still returned BLANK while the condition was blank, so the press STILL showed no change to
	# confirm or deny and the same complaint came back:
	#
	#   *"I can't select 'my' or 'their' until AFTER I have selected a condition."*
	#
	# ⚠️ THE ARM BELOW COULD NOT CATCH THAT, and its shape is the reason: it reads `subj` only
	# AFTER the `If` press, so it grades the value the player ends up with and never that the
	# press was VISIBLE WHEN MADE. Left-to-right authoring needs the second thing. The assertion
	# that was missing is the one directly under this comment.
	for case in [["My", GambitOptions.SUBJECT_MINE], ["Their", GambitOptions.SUBJECT_THEIRS]]:
		_apply_choice(surface, GambitSurfaceScript.Part.DO, "Attack")
		_apply_choice(surface, GambitSurfaceScript.Part.TO, "Foe")
		_apply_choice(surface, GambitSurfaceScript.Part.IF, GambitOptions.BLANK)
		_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, String(case[0]))
		# 🔴 THE DISPLAY HALF — read BETWEEN the `Subject` press and the `If` press, with NO
		# condition on the row. This is the arm `a8e001303` did not write. A build that blanks
		# the subject while the condition is blank reds here and nowhere else, which is exactly
		# how the bug survived being fixed once.
		_eq(String((surface.row_entries()[0] as Dictionary)["subj"]), String(case[1]),
			"a `Subject = %s` press must be VISIBLE THE MOMENT IT IS MADE, on a row with no"
				% String(case[0])
			+ " condition yet — the player authors left to right and a column that shows no"
			+ " change cannot confirm or deny the press they just made")
		_apply_choice(surface, GambitSurfaceScript.Part.IF, "HP<50%")
		# THE ASSERTION IS THAT THE TWO CHOICES DIFFER. Pinning `My` alone would pass on a build
		# that hard-coded `My`, and pinning `Their` alone passes on the write-half defect — it
		# was always `Their`. The third row below is the DEFAULT, because a fix that made the
		# subject stick by no longer seeding it at all would break the row that never touches
		# the column.
		_eq(String((surface.row_entries()[0] as Dictionary)["subj"]), String(case[1]),
			"…and authored LEFT TO RIGHT, `Subject = %s` must then SURVIVE the `If` press that"
				% String(case[0])
			+ " follows it — the column is the third word of the sentence and the player reads"
			+ " the row in that order")
	# THE DEFAULT, unseeded: never touch the Subject column at all and the row still reads
	# `Their`, because a blank condition leaves `condition_target` mirroring the aim.
	_apply_choice(surface, GambitSurfaceScript.Part.DO, "Attack")
	_apply_choice(surface, GambitSurfaceScript.Part.TO, "Foe")
	_apply_choice(surface, GambitSurfaceScript.Part.IF, "HP<50%")
	_eq(String((surface.row_entries()[0] as Dictionary)["subj"]), GambitOptions.SUBJECT_THEIRS,
		"…and a row whose Subject was never pressed still lands `Their` — the fix removes a"
		+ " SEED, so the default it used to compute has to come from the mirror invariant"
		+ " instead, or this is a regression wearing a bug fix's clothes")

	# ==========================================================================================
	# `Always` IN THE SUBJECT COLUMN — THE ROW THAT SAYS IT HAS NO TEST, AND SPANS THE `If`.
	#
	# *"My or Their shouldn't be mandatory — we could have a gambit which only uses the first 2
	# items"*. Before this the player's only conditionless reading was `Attack / Foe / Their /
	# —`: a subject dangling off a question nobody asked, next to an em dash. `Always` is the
	# word for what that row DOES, and choosing it drops the `If` column rather than filling it
	# with an `N/A` — which would be one more glyph to explain and would re-create the pair.
	#
	# 🔴 THE COLUMN STAYS AND GOES DIM — it is not removed. A column that vanishes under the
	# player is the wrong answer to "not applicable": the eye loses the place it reads the fourth
	# word from, and a row with one fewer column reads as a different KIND of row.
	#
	# AND THE PREDICATE IS PARKED, NOT DESTROYED. *"if they flip it i don't want them to have to
	# repick it"* — so `HP<50%` moves to `Gambit.parked_condition`, the dim cell shows it, and
	# flipping back off `Always` restores it.
	_apply_choice(surface, GambitSurfaceScript.Part.DO, "Attack")
	_apply_choice(surface, GambitSurfaceScript.Part.TO, "Nearest Foe")
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_THEIRS)
	_apply_choice(surface, GambitSurfaceScript.Part.IF, "HP<50%")
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_ALWAYS)
	var always_row: Dictionary = surface.row_entries()[0]
	_eq(String(always_row["subj"]), GambitOptions.SUBJECT_ALWAYS,
		"the Subject column reads `Always` — the row's answer to 'what does it test', given in"
		+ " the column that asks WHETHER there is a test rather than what it is")
	_true(bool(always_row.get("if_disabled", false)),
		"and the `If` column is flagged DISABLED — which is what paints it in the dim band and"
		+ " widens SUBJECT to COL_SUBJ_DISABLED_CAP. `Always` measures 26 px against the 20 px"
		+ " switch cap, so a row that set the label without the flag would render it ELIDED")
	_eq(String(always_row["iff"]), "HP<50%",
		"…and the dim cell shows the PARKED predicate, not a placeholder — the row saying what"
		+ " is waiting to come back, which is the whole reason the park exists")

	var parked_g = character.gambits.get_at(0)
	_true(parked_g != null and parked_g.parked_condition != null
			and parked_g.parked_condition.type == GambitCondition.Type.TARGET_HP
			and is_equal_approx(parked_g.parked_condition.threshold, 50.0),
		"and the FIELD holds it — `Gambit.parked_condition`, which is where a flip back reads it"
		+ " from. A build that only changed the LABEL would pass the cell assertion above and"
		+ " lose the predicate the moment the player flipped")
	_true(parked_g.conditions.size() == 1
			and parked_g.conditions[0].type == GambitCondition.Type.ALWAYS,
		"…while `conditions` holds the lone `ALWAYS` and NOT `[ALWAYS, HP<50%]` — the kernel ANDs"
		+ " every entry, so parking the predicate in the array would leave the row reading"
		+ " `Always` and firing only below half HP")

	# THE FLIP BACK RESTORES IT. This is the assertion the ticket exists for.
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_THEIRS)
	var restored: Dictionary = surface.row_entries()[0]
	_eq(String(restored["iff"]), "HP<50%",
		"flipping off `Always` RESTORES the parked predicate — the player does not re-pick it")
	_true(not bool(restored.get("if_disabled", false)),
		"…and the column is live again, not dim")
	_true(character.gambits.get_at(0).parked_condition == null,
		"…and the park is CONSUMED, or a later `Always` would resurrect a predicate the player"
		+ " has since replaced")

	# RE-PRESSING `Always` ON AN ALREADY-`Always` ROW MUST NOT PARK THE `ALWAYS` ITSELF, which
	# would overwrite the predicate the player actually set with a no-op they cannot see.
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_ALWAYS)
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_ALWAYS)
	_eq(String((surface.row_entries()[0] as Dictionary)["iff"]), "HP<50%",
		"a second `Always` press leaves the park alone — it is idempotent, and a build that"
		+ " parked unconditionally would show `—` here and have eaten the predicate")

	# THE FIELD, not only the column. An explicit `ALWAYS` condition is the state — a zero-length
	# array is the row MID-AUTHORING and reads `My`/`Their` (the arms above), so a build that
	# wrote the label off an empty array would make every `Subject` press invisible again.
	var always_g = character.gambits.get_at(0)
	_true(always_g != null and always_g.conditions.size() == 1
			and always_g.conditions[0].type == GambitCondition.Type.ALWAYS,
		"and the write is an EXPLICIT `ALWAYS` condition, which is what distinguishes a row that"
		+ " declared it has no test from one the player has not finished authoring")
	_true(GambitOptions.is_unconditional(always_g),
		"…and the predicate the widget spans on agrees with the label, or the cell is drawn at"
		+ " the narrow cap with the wide word in it")

	# 🔴 THE CURSOR CANNOT STAND ON A DISABLED COLUMN, and that is also what PAYS for the word:
	# SUBJECT borrows the 13 px chevron gap in front of `If`, which is only free because no arrow
	# can ever be mounted there. `_move_part` clamped to `PART_COUNT - 1` unconditionally, so →
	# from the subject landed on `If` and ○ would open a condition list under a column this row
	# has just greyed out.
	surface._part = GambitSurfaceScript.Part.SUBJ
	_true(surface._move_part(1),
		"→ on an `Always` row is CONSUMED — the row owns the axis even at its ends, exactly as"
		+ " it does at `Do` (arm 14), so the coordinator must not be handed the press")
	_eq(surface.part(), GambitSurfaceScript.Part.SUBJ,
		"…and lands nowhere — Subject IS the last part on this row, because the `If` column it"
		+ " would walk onto is disabled")

	# AND THE WAY BACK IS VISIBLE THE MOMENT IT IS MADE, which is the reading-order rule above
	# applied to the new row: pressing `Their` on an `Always` row has to CHANGE something, or
	# this column is mute again in a new state. It drops the declaration, so the `If` column
	# wakes up — and wanting one is the only reason to name a subject at all.
	#
	# DRIVEN ON A ROW WITH NOTHING PARKED, which is the OTHER half of the restore: the block
	# above proved a park comes back, and this one proves the column still wakes up when there
	# is nothing to come back to. A build that woke the column only when it had a value to
	# restore would pass up there and strand the player down here.
	_apply_choice(surface, GambitSurfaceScript.Part.IF, GambitOptions.BLANK)
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_ALWAYS)
	_true(character.gambits.get_at(0).parked_condition == null,
		"the row under the way-back arm has NOTHING parked — `—` cannot be parked, so clearing"
		+ " the condition first is what makes this arm the no-park case rather than a repeat")
	_apply_choice(surface, GambitSurfaceScript.Part.SUBJ, GambitOptions.SUBJECT_THEIRS)
	var back_row: Dictionary = surface.row_entries()[0]
	_eq(String(back_row["subj"]), GambitOptions.SUBJECT_THEIRS,
		"pressing `Their` on an `Always` row must show `Their` — a press that left the row"
		+ " reading `Always` is #1255's reported bug re-opened in the state that fixed it")
	_true(not bool(back_row.get("if_disabled", false))
			and String(back_row["iff"]) == GambitOptions.BLANK,
		"…and the `If` column is LIVE again, reading `—` because this row had nothing parked:"
		+ " naming a subject is asking for a test, so the column the test goes in has to wake up")
	_eq(surface._move_part(1), true, "→ reaches `If` again on a row that has one")
	_eq(surface.part(), GambitSurfaceScript.Part.IF,
		"…and the cursor can stand on it — the clamp is read off the ROW, not latched")

	# RESTORE for the arms after this one.
	surface._part = GambitSurfaceScript.Part.DO
	_apply_choice(surface, GambitSurfaceScript.Part.TO, "Foe")
	_apply_choice(surface, GambitSurfaceScript.Part.IF, GambitOptions.BLANK)


## THE ROW GRAMMAR (ADR-0268 dec. 1, 4 and 6; the fourth part is ADR-0283 dec. 1) — the three
## verbs the row added, each of which the drill-down had no way to express.
##
## Here rather than in a scene of its own because it needs exactly this setup: a Gariland turn,
## the real coordinator, the real surface, and slot 0 already carrying the gambit arm 4 wrote
## (test charter clause 13 — and clause 15: splitting these off would cost a whole Godot boot
## per assertion).
## Land the choice NAMED `want` on `part`, through the part's own `apply` — the same Callable ○
## calls. A test that rewrote the apply's body would be asserting its own copy of it.
##
## Reports a miss rather than failing silently, because a name the list does not offer is a
## finding either way: it may be ADR-0276's gate correctly withholding the row.
##
## DOES NOT MOVE THE CURSOR. `choices_for` takes the part as an argument and no apply reads
## `_part`, so setting it would only leave the row focused somewhere the arms after this one
## were not written against — which is how this helper first red arm 14's part walk.
func _apply_choice(surface, part: int, want: String) -> void:
	for entry in surface.choices_for(part):
		var row: Dictionary = entry
		if String(row.get("name", "")) == want and row.has("apply"):
			(row["apply"] as Callable).call()
			return
	_true(false, "the %s list offers no row named '%s' to land"
		% [GambitSurfaceScript.Part.keys()[part], want])


func _arm_14_the_row_is_walked_and_reordered() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null or surface.level() != GambitSurfaceScript.Level.ROW:
		_true(false, "arm 14 needs the row level")
		return
	var character = FormationMapHost.character_for_unit(units[_taker])

	# ←/→ WALK THE PARTS, and CLAMP at the ends. Wrapping from `If` back to the enable flag
	# would teleport the cursor across the row the layout asks the player to read left to right.
	await _press(KEY_RIGHT)
	_eq(surface.part(), GambitSurfaceScript.Part.TO, "→ walks Do -> To")
	await _press(KEY_RIGHT)
	_eq(surface.part(), GambitSurfaceScript.Part.SUBJ, "→ walks To -> Subject")
	await _press(KEY_RIGHT)
	_eq(surface.part(), GambitSurfaceScript.Part.IF, "→ walks Subject -> If")
	await _press(KEY_RIGHT)
	_eq(surface.part(), GambitSurfaceScript.Part.IF, "and CLAMPS at the last part, never wraps")
	await _press(KEY_LEFT)
	await _press(KEY_LEFT)
	await _press(KEY_LEFT)
	_eq(surface.part(), GambitSurfaceScript.Part.DO, "← walks back to Do")
	await _press(KEY_LEFT)
	_eq(surface.part(), GambitSurfaceScript.Part.DO,
		"which is the FIRST part, and clamps — the slot NUMBER to its left is a readout and the"
		+ " cursor does not stop on it (ADR-0268 dec. 13)")

	# ○ ON THE FIRST PART OPENS ITS LIST, because there is no toggle to its left any more.
	# `Gambit.enabled` stays in the domain and the kernel still honours it — the off-switch the
	# player reaches is `---`, which empties the row. What this asserts is the ABSENCE: a ○ at the
	# leftmost stop must open the `Do` list, not swallow itself into a flag.
	await _press(KEY_ENTER)
	_eq(surface.level(), GambitSurfaceScript.Level.CHOICE,
		"○ at the leftmost stop opens the `Do` list — the ENABLE part is gone, not merely unbound")
	_eq(surface.part(), GambitSurfaceScript.Part.DO, "and the part it is serving is Do")
	await _press(KEY_BACKSPACE)
	_eq(_gambit_level(), GambitSurfaceScript.Level.ROW, "✕ puts the row back")
	_eq(int(GambitSurfaceScript.PART_COUNT), 4,
		"FOUR parts — `Do`, `To`, `Subject`, `If` (ADR-0283 dec. 1). A FIFTH would be a stop"
		+ " with nothing to edit; a THIRD is the fold that made `nearest ally whose HP is below"
		+ " half` inexpressible")

	# THE WIDGET'S MIRROR. `GambitSurfaceMenu` aims the chevron by part index and MIRRORS the
	# enum rather than importing it, because it renders what it is handed and knows nothing about
	# gambits. A mirror that drifts aims the chevron one column off the part it names, on every
	# row, and renders perfectly while doing it — so the equality is asserted, not assumed.
	_eq(int(GambitSurfaceMenuScript.PART_DO), int(GambitSurfaceScript.Part.DO), "the widget mirrors Do")
	_eq(int(GambitSurfaceMenuScript.PART_TO), int(GambitSurfaceScript.Part.TO), "and To")
	_eq(int(GambitSurfaceMenuScript.PART_SUBJ), int(GambitSurfaceScript.Part.SUBJ),
		"and Subject — the part whose arrival renumbered `If`, which is exactly the drift this"
		+ " equality exists to catch")
	_eq(int(GambitSurfaceMenuScript.PART_IF), int(GambitSurfaceScript.Part.IF), "and If")
	_true(int(GambitSurfaceMenuScript.NOT_A_PART) < 0,
		"and its sentinel for the slot-number column is no part at all")

	# L1/R1 RAISE AND LOWER THE SLOT (dec. 6). A real verb, because slot order IS priority
	# (rule A1): the shader walks slots ascending and takes the first match, so moving a row up
	# is moving the rule up. Read off the CHARACTER, because the reorder has to be a write and
	# not a re-render of the same list in a different order.
	_eq(character.gambits.get_at(0).action_kind, Gambit.ActionKind.ATTACK,
		"arm 14 starts with the authored gambit in slot 0")
	await _press(KEY_E)                     # rotate_camera_ccw = lower
	_eq(character.gambits.get_at(1).action_kind, Gambit.ActionKind.ATTACK,
		"R1 LOWERED it into slot 1")
	_true(character.gambits.get_at(0).is_empty(),
		"and the empty slot it swapped with came up to slot 0")
	_eq(surface.slot(), 1, "the cursor followed the row it moved")
	await _press(KEY_Q)                     # rotate_camera_cw = raise
	_eq(character.gambits.get_at(0).action_kind, Gambit.ActionKind.ATTACK,
		"L1 RAISED it back to slot 0")
	_eq(surface.slot(), 0, "and the cursor followed it back")


## EVERY part's list opens under ITS OWN column, whichever order the parts are opened in — and
## its glyphs land INSIDE its own scissor, which is the half no state assertion can see (#1081).
##
## === WHY THIS ARM IS COORDINATES AND NOT STATE ==============================================
##
## This file passed 123/0 while the shipped screen drew the SECOND list opened, and every one
## after it, as a perfectly empty box at the FIRST list's position. Every state question —
## level, row count, entries, what the pick wrote — was answered correctly the whole time,
## because the defect was never in the state. `GambitSurfaceMenu` is rebuilt per press under
## four CONSTANT ids, `UI3Element` minted a `<id>.rect` Tune knob for its literal rect, and
## `Tune` is first-write-wins — so the new window inherited the old one's geometry while its
## `authored_home` stayed its own, and `rel_world` carried the glyphs out past the window's
## `OWN_APERTURE` scissor. See [method UI3Element.host_derived].
##
## So the arm asks two questions a rendering can fail: WHERE is the box (against the surface's
## own `choice_container_for`, which the previous handoff measured and cleared), and are the
## GLYPHS inside it (in the ClipEngine's own basis, the space the clip shader tests them in).
##
## THE ORDER IS THE FIXTURE. One part proves nothing — the first list always drew. Opening
## three in a row under one setup is what makes the freeze reachable, and is also why this is an
## arm here rather than a scene of its own (charter clause 15: a split costs a whole Godot boot).
func _arm_15_every_part_opens_under_its_own_column() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null or surface.level() != GambitSurfaceScript.Level.ROW:
		_true(false, "arm 15 needs the row level")
		return
	# Arm 14 leaves the cursor on `Do`, the leftmost stop (dec. 13 retired the enable flag).
	# The names are LOCAL prose, not a production constant: ADR-0268 dec. 10 took the title off
	# every choice list, and `GambitSurface.PART_LABELS` went with it. These strings only make the
	# failure messages below readable, so reaching for a shared constant would be re-erecting the
	# thing that decision deleted just to have somewhere to read a word from.
	const PART_PROSE := {
		GambitSurfaceScript.Part.DO: "Do",
		GambitSurfaceScript.Part.TO: "To",
		GambitSurfaceScript.Part.SUBJ: "Subject",
		GambitSurfaceScript.Part.IF: "If",
	}
	# ALL FOUR, and `If` is no longer the last column whose box has to be clamped back inside the
	# 256-px mask — `Subject` is now the narrowest and `If` the rightmost, so the clamp and the
	# narrow case are two different iterations rather than one.
	var parts := [GambitSurfaceScript.Part.DO, GambitSurfaceScript.Part.TO,
		GambitSurfaceScript.Part.SUBJ, GambitSurfaceScript.Part.IF]
	for i in parts.size():
		var part: int = parts[i]
		var label: String = String(PART_PROSE[part])
		# NO press for the first part: arm 14 leaves the cursor on `Do`, which is the leftmost
		# stop there is now that the enable flag is a readout (ADR-0268 dec. 13). A → before it
		# would walk PAST the part this iteration then goes on to name, and every assertion below
		# would be made about the wrong column while reading perfectly.
		if i > 0:
			await _press(KEY_RIGHT)
		_eq(surface.part(), part, "the row's cursor is on the %s part" % label)
		await _press(KEY_ENTER)
		_eq(surface.level(), GambitSurfaceScript.Level.CHOICE, "○ opens the %s list" % label)
		var menu = surface.menu()
		if menu == null or menu.window() == null:
			_true(false, "the %s list built a window" % label)
			return
		# SETTLED first: BOX_OPEN drives the aperture, so a mid-beat read would be measuring the
		# reveal rather than the placement.
		await _wait_until(func() -> bool: return menu.window().is_settled())
		var want := Rect2(surface.choice_container_for(part))
		_eq(menu.container_now(), Rect2i(want),
			"the %s list's container is its OWN column's" % label)
		_eq(menu.window().rect(), want,
			"and so is the WINDOW's live rect — not the rect of a list opened before it")
		_eq(menu.window().aperture(), Rect2i(want),
			"and so is the scissor it reveals its rows through")
		var span := _glyph_x_span(_rows_element_of(menu))
		_true(not span.is_empty(), "the %s list mounted row glyphs at all" % label)
		if not span.is_empty():
			# HALF-OPEN on the right: a glyph quad is placed by its LEFT edge, so its origin is
			# inside a box whose right edge it touches.
			_true(span[0] >= want.position.x - 0.5 and span[1] < want.end.x,
				"and every one of them lands INSIDE that scissor — glyph span [%.1f, %.1f]"
				% [span[0], span[1]] + " against [%.1f, %.1f)" % [want.position.x, want.end.x])
		# §15.21 — the row window BEHIND the list gives up its colour and its glove. Dec. 1 wants
		# the row still legible, and legible is not focused: two foreground windows with a live
		# bobbing glove each is a screen showing two cursors and naming neither as the pad's.
		# Asked of `row_menu()` and not `menu()`, which by construction is the list on top.
		var row_menu = surface.row_menu()
		if row_menu != null:
			_true(row_menu.is_backgrounded(),
				"the row window is BACKGROUNDED under the %s list" % label)
			_true(not row_menu.cursor_visible(),
				"and its glove is REMOVED, so the %s list's is the only cursor on screen" % label)
		await _press(KEY_BACKSPACE)
		_eq(_gambit_level(), GambitSurfaceScript.Level.ROW,
			"✕ drops the %s list and leaves the row standing" % label)
		row_menu = surface.row_menu()
		if row_menu != null:
			_true(not row_menu.is_backgrounded(),
				"and the row window comes back to the FOREGROUND with the pad")
			_true(row_menu.cursor_visible(), "glove and all")
	# Hand arm 7 the cursor it documents starting from.
	for _i in parts.size():
		await _press(KEY_LEFT)
	_eq(surface.part(), GambitSurfaceScript.Part.DO,
		"and ← walks all the way back to `Do`, the leftmost stop there is")


## THE `Do` LIST IS TWO DEEP — skillset, then ability (ADR-0268 dec. 9, dec. 10).
##
## Here rather than in a scene of its own for the same reason as arm 14: it needs a Gariland turn,
## the real coordinator and the real surface, and a scene of its own would buy one more Godot boot
## for assertions this setup already affords (test charter clauses 13 and 15).
##
## Arm 15 hands back the cursor on slot 0's `Do` part — it opens three lists and drops each one,
## landing nothing, then walks ← back to the leftmost stop.
func _arm_16_the_do_list_is_two_deep() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null or surface.level() != GambitSurfaceScript.Level.ROW:
		_true(false, "arm 16 needs the row level")
		return
	var character = FormationMapHost.character_for_unit(units[_taker])
	if character == null or character.gambits == null:
		_true(false, "arm 16 needs a taker with a gambit list")
		return

	# THE PARTITION, read off the catalogue rather than off the open menu — `choices_for` is what
	# the menu is BUILT from, so asking it is asking the thing that decides. Every top-level row
	# is the clear, one of the three verbs, or a drill; a list that offered bare abilities TOO
	# would pass every other assertion in this arm while still burying them.
	var do_choices: Array = surface.choices_for(GambitSurfaceScript.Part.DO)
	_true(not do_choices.is_empty(), "the Do catalogue is not empty")
	# Read off `KIND_TO_VERB` rather than spelled out here. It was the literal
	# `["Attack", "Move", "Wait"]` until ADR-0301 put `Retreat` back on the enum, at
	# which point this arm reported the new verb as a bare ability buried in the
	# list — a false red that says nothing about the partition it is guarding. The
	# cross-check survives: the surface may only offer rows the DOMAIN names as
	# control verbs, and a verb the domain does not know is still a stray.
	var verbs: Array = Gambit.KIND_TO_VERB.values()
	var skillset_row: Dictionary = {}
	var strays: Array[String] = []
	for c in do_choices:
		var entry: Dictionary = c
		var nm := String(entry.get("name", ""))
		if entry.has("drill"):
			if skillset_row.is_empty():
				skillset_row = entry
			continue
		if nm == GambitSurfaceScript.CLEAR_LABEL or verbs.has(nm):
			continue
		strays.append(nm)
	_true(strays.is_empty(),
		"every top-level Do row is the clear, a verb or a SKILLSET — bare abilities offered"
		+ " alongside the drill would be the flat list wearing the drill's clothes; found %s"
		% str(strays))
	_true(not skillset_row.is_empty(),
		"and the taker's own job puts at least one skillset row there")
	if skillset_row.is_empty():
		return
	var sid := int(skillset_row["drill"])
	var skillset_name := String(skillset_row["name"])

	# ○ ON A SKILLSET OPENS ITS ABILITIES. Arm 15 hands the cursor back on `Do`, which is where
	# it already needs to be — no walk: dec. 13 retired the enable flag, so `Do` IS the leftmost
	# stop and a → here would land on `To`, whose list has no skillset row in it at all.
	_eq(surface.part(), GambitSurfaceScript.Part.DO, "the cursor is on Do")
	await _press(KEY_ENTER)
	_eq(surface.level(), GambitSurfaceScript.Level.CHOICE, "○ on Do offers the top-level list")
	await _choose_row_named(skillset_name)
	_eq(surface.level(), GambitSurfaceScript.Level.ABILITY,
		"○ on '%s' drills — it lands NOTHING, it opens that skillset" % skillset_name)
	_eq(surface.skillset(), sid, "and the level knows WHOSE abilities it is showing")
	_eq(character.gambits.get_at(0).action_kind, Gambit.ActionKind.ATTACK,
		"the slot is UNCHANGED by the drill — arm 14 left it holding Attack")

	# The ROW is still standing behind BOTH boxes (dec. 1). The ability list REPLACED the Do
	# list — one box per column, because both hang off `Do` and both rise from the row window's
	# top edge, so a second would land exactly on the first.
	_true(surface.row_menu() != null and is_instance_valid(surface.row_menu()),
		"with the ROW list still legible behind it, two boxes in")
	_true(surface.menu() != surface.row_menu(), "— and the pad on the ability list, not the row")
	_true(not surface.handle_action(&"ui_left"),
		"← is REFUSED here too: a column has no horizontal axis, however deep it is")

	# THE LIST IS THE SKILLSET'S OWN ACTIONS, IN THE ROM'S OWN ORDER. Read against the database
	# rather than against a literal: the taker is whichever unit the seed opened a turn on, so a
	# spelled-out list would be an assertion about the battle seed and not about this screen.
	var menu = surface.menu()
	var want: Array[String] = []
	for id in AbilityDatabase.get_skill_set_actions(sid):
		var view := AbilityDatabase.get_ability_view(int(id))
		if not view.is_empty() and not view.name.is_empty():
			want.append(view.name)
	var got: Array[String] = []
	for i in range(menu.row_count()):
		got.append(String(menu.entries[i]))
	_eq(str(got), str(want),
		"the ability list is '%s' exactly, in the ROM's table order — the order the player"
		% skillset_name + " already knows from the game's own action menu")
	if want.is_empty():
		return

	# ✕ RETURNS TO THE `Do` LIST, not to the row. The player spent a press to get here; ✕ owes
	# them ONE back, which is arm 7's rule read one level deeper.
	await _press(KEY_BACKSPACE)
	_eq(_gambit_level(), GambitSurfaceScript.Level.CHOICE,
		"✕ off the ability list returns to the Do list — ONE level, not two")
	_eq(surface.skillset(), -1, "and the drill has no subject any more")
	_true(_menu_has_row(skillset_name), "which offers '%s' again" % skillset_name)

	# AND THE ABILITY LANDS. Read off the Character (ADR-0005), then off the row, which is the
	# readout — a write that landed in a copy passes the first and fails the second.
	await _choose_row_named(skillset_name)
	await _choose_row_named(want[0])
	var g = character.gambits.get_at(0)
	_true(g != null, "slot 0 still holds a gambit")
	if g == null:
		return
	_eq(g.action_kind, Gambit.ActionKind.ABILITY, "whose action is now an ABILITY")
	_eq(String(AbilityDatabase.get_ability_view(g.ability_id).name), want[0],
		"and it is '%s', the ability picked two levels down" % want[0])
	_eq(_gambit_level(), GambitSurfaceScript.Level.ROW,
		"landing it drops BOTH lists and leaves the row — the ability level does not survive"
		+ " a choice that came out of it")
	_eq(String((surface.row_entries()[0] as Dictionary)["do"]), want[0],
		"which reads the ability back in the very column it was picked for")

	# ===== ADR-0276 — AND THE ABILITY BROUGHT AN AIM ==========================================
	#
	# Here rather than in a scene of its own because this is the only arm in the tree that has
	# the ABILITY level open on a real surface, with a real taker's real skillset (charter
	# clause 13). `GambitEncoderTest` grades every cell in the space and asserts every seed is
	# sensible — but that is a claim about a PREDICATE. Whether the press consults it is a
	# different claim, and `_ability_choices` landed an ability without seeding for as long as
	# the ability level has existed. That is the defect the player reported.
	#
	# DIRECTION-TESTED, MEASURED — AND RE-MEASURED UNDER ADR-0278, WHICH MOVED THE ANSWER.
	# Reverting `_ability_choices`'s `_seed_aim(g, was_empty)` call (line 693, NOT the second
	# call site in `choices_for`) now reds BOTH assertions below.
	#
	# It used to red exactly one — the `dont_hit_caster` one, on `Dash` — and NOT the
	# `seed_aim_for` comparison, because `want[0]` on this taker is `Accumulate`, whose record
	# permits the caster, so under ADR-0276 dec. 10 its seed WAS `Self` and the two arms agreed
	# with the constructor. ADR-0278 seeds `Accumulate`'s FAMILY pool instead — it is a `buff`,
	# so `Nearest Ally` — and the constructor's `Self` no longer matches it. The general arm can
	# now see the defect on this taker.
	#
	# Both stay, and the reason is the old measurement rather than the new one: the general
	# assertion only sees this because a family disagrees with the constructor, which is a
	# property of `Accumulate` and not a guarantee about whatever ability `want[0]` names on a
	# future taker. The named arm cannot generalise past the abilities carrying the flag, and the
	# general arm cannot be relied on to catch an ability whose family pool IS the constructor's
	# `Self`. Two arms, two blind spots, and they do not overlap.
	#
	# Cleared first, because the seed is an EMPTY-slot rule (ADR-0268 dec. 12, kept) and slot 0
	# is holding the ability arm 16 just landed.
	await _press(KEY_ENTER)
	await _choose_row_named(GambitSurfaceScript.CLEAR_LABEL)
	_true(character.gambits.get_at(0).is_empty(), "the clear emptied slot 0 for the seed arm")
	await _press(KEY_ENTER)
	await _choose_row_named(skillset_name)
	await _choose_row_named(want[0])
	var seeded_g = character.gambits.get_at(0)
	var want_seed = GambitOptions.seed_aim_for(seeded_g.action_kind, seeded_g.ability_id,
		seeded_g.condition_target)
	_true(want_seed != null and seeded_g.action_target != null
			and seeded_g.action_target.pool_type == want_seed.pool_type
			and seeded_g.action_target.team_filter == want_seed.team_filter
			and seeded_g.action_target.resolution == want_seed.resolution,
		"an ability landed on an EMPTY slot came AIMED — the same value"
		+ " `GambitOptions.seed_aim_for` names, so the press consults the rule rather than"
		+ " leaving the constructor's Self standing (ADR-0276 dec. 9)")
	_eq(GambitOptions.aim_verdict(seeded_g.action_kind, seeded_g.ability_id,
			seeded_g.action_target, seeded_g.condition_target), GambitOptions.AIM_SENSIBLE,
		"and the aim it came with is one nothing in the ROM record or the kernel can fault")

	# THE REPORTED PRESS, BY NAME. `ThrowStone / Self` was reachable because the ROM record
	# forbids the caster and the screen did not read that. Direction-tested rather than assumed:
	# if this taker's skillset holds no `dont_hit_caster` ability the arm SAYS SO instead of
	# reporting a silent pass, because "no forbidden aim was offered" and "nothing was examined"
	# look identical from the outside.
	var no_caster: String = ""
	for id in AbilityDatabase.get_skill_set_actions(sid):
		var v := AbilityDatabase.get_ability_view(int(id))
		if not v.is_empty() and not v.name.is_empty() and v.dont_hit_caster:
			no_caster = v.name
			break
	if no_caster.is_empty():
		print("[note] arm 16: '%s' holds no dont_hit_caster ability — the reported-press"
			% skillset_name + " assertion had no subject on this taker and did not run")
	else:
		await _press(KEY_ENTER)
		await _choose_row_named(GambitSurfaceScript.CLEAR_LABEL)
		await _press(KEY_ENTER)
		await _choose_row_named(skillset_name)
		await _choose_row_named(no_caster)
		_true(String((surface.row_entries()[0] as Dictionary)["to"]) != "Self",
			"'%s' carries `dont_hit_caster`, so landing it on an empty slot does NOT leave the"
			% no_caster + " row aimed at Self — the aim the ROM record forbids and the press"
			+ " the player reported")
		# …and the `To` list does not OFFER it either. An aim removed from the seed but still on
		# the list is one press from being authored again, and the row it would author reads
		# back correctly and lands on the one unit the record forbids.
		await _press(KEY_RIGHT)                    # Do -> To
		await _press(KEY_ENTER)
		_true(not _menu_has_row("Self"),
			"and the `To` list withholds Self for '%s' — the gate and the seed are one"
			% no_caster + " decision, not two (ADR-0276 dec. 8)")
		_true(_menu_has_row("Foe") and _menu_has_row("Nearest Foe"),
			"while still offering the pools the record permits — the gate removes what it can"
			+ " prove and nothing else. BOTH foe rows, because ADR-0285 made depth a separate"
			+ " choice from pool and a gate that kept one and dropped the other would be"
			+ " removing a row it cannot fault")
		await _press(KEY_BACKSPACE)                # close the list
		await _press(KEY_LEFT)                     # back onto Do, where arm 17 expects it


## THE SAFETY NET IS THE LAST ROW, AND IT IS INERT (ADR-0270, superseding ADR-0048 dec. 2).
##
## Here rather than in a scene of its own for arm 14's reason: it needs a Gariland turn, the real
## coordinator and the real surface (test charter clauses 13 and 15).
##
## Arm 16 left the cursor on slot 0's `Do`. This arm walks DOWN to the net, asserts it there, and
## walks back — arm 7 starts from where arm 16 left off.
func _arm_17_the_safety_net_is_the_last_row_and_is_inert() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null or surface.level() != GambitSurfaceScript.Level.ROW:
		_true(false, "arm 17 needs the row level")
		return
	var character = FormationMapHost.character_for_unit(units[_taker])
	if character == null or character.gambits == null:
		_true(false, "arm 17 needs a taker with a gambit list")
		return

	# THE ROW IS DERIVED FROM THE ENCODER'S OWN OBJECT, not from three strings. A readout that
	# restated the net in its own words is the drift this row exists to close, so the assertion
	# reads the same object the encoder packs and would red if either side moved alone.
	var net_index: int = surface.safety_net_row_index()
	_eq(net_index, GambitList.VISIBLE_SLOTS + 1,
		"the net is the LAST row — after the four slots AND after the imperative's")
	var rows: Array = surface.row_entries()
	_eq(rows.size(), GambitList.VISIBLE_SLOTS + 2, "so the list is six rows on a battle host")
	if net_index >= rows.size():
		return
	var net: Dictionary = rows[net_index]
	var injected = GambitEncoderScript.safety_net_gambit()
	_eq(String(net["do"]), "Attack", "which reads Attack…")
	_eq(String(net["to"]), "Foe",
		"…on a Foe — the CONDITION target, because the net's action target is `triggering()`"
		+ " and renders as 'Them', which names no pool. `Foe` and not `Nearest Foe` since"
		+ " ADR-0285: the net searches nearest-first and the kernel RETRIES it, which is the"
		+ " behaviour that makes it a net at all")
	# `Attack / Nearest Foe / Always` — ADR-0270 dec. 1's string, arrived at again and from the
	# OBJECT rather than from a literal: `safety_net_gambit` carries one explicit `ALWAYS`
	# condition, which is exactly the state the Subject column now names.
	#
	# It read `Attack / Nearest Foe / Their / —` in between. ADR-0283 dec. 2 had retired the word
	# `Always` from the screen on the grounds that the `If` column's job is to say what a rule
	# TESTS, and `Always` is not a test — which is true of that column and is why the word is
	# back in a DIFFERENT one: the Subject column answers whether there IS a test. `Their` was
	# honest about the gate and dangled off a question nobody had asked.
	#
	# ⚠️ THIS IS A VISIBLE CHANGE TO A ROW THE PLAYER DID NOT AUTHOR, and it is the assertion
	# rather than a side effect: the net is the one row whose reading is derived end-to-end from
	# the encoder's own object, so it is also the row that proves the new state is read off the
	# FIELD and not off a press the surface remembers.
	_true(bool(net.get("if_disabled", false)) and String(net["iff"]) == GambitOptions.BLANK,
		"the net's `If` column is DISABLED and reads `—` — nothing is parked there, because"
		+ " nobody authored the net. Dim-and-empty, not the live em dash that used to dangle"
		+ " beside a `Their` this row never asked for")
	_eq(String(net["subj"]), GambitOptions.SUBJECT_ALWAYS,
		"…because the column says `Always` instead: the net fires whenever a foe is there, which"
		+ " is what its one `ALWAYS` condition means and what ADR-0270 dec. 1 first wrote")
	_true(GambitOptions.is_unconditional(injected),
		"…read off the INJECTED object, so the row and the buffer cannot drift into two"
		+ " descriptions of one rule — a net that stopped carrying `ALWAYS` would red here"
		+ " rather than quietly render a subject")
	_eq(injected.action_kind, Gambit.ActionKind.ATTACK,
		"and that is the shape GambitEncoder actually injects (ADR-0048 dec. 1)")
	_eq(String(net["enable"]), "",
		"its enable cell is BLANK, not `○` — the mark is a state the player can change and"
		+ " this one is not")
	_true(bool(net.get("inert", false)),
		"and it is marked inert, which is what keeps it DIM under the glove")

	# WALK ONTO IT. Every verb the row grammar offers is refused here.
	for _i in range(net_index):
		await _press(KEY_DOWN)
	var menu = surface.menu()
	_eq(menu.selected_row(), net_index, "↓ walks the glove onto the net — it is reachable")
	_true(not surface.handle_action(&"ui_left"),
		"← on the net is REFUSED — it has no parts, so there is no axis to walk")
	_true(not surface.handle_action(&"ui_right"), "and so is →")
	_true(not surface.handle_action(&"rotate_camera_cw"),
		"and so is L1: the net is in no slot, so it has no priority to raise")
	_eq(surface.part(), GambitSurfaceScript.Part.DO,
		"— refused and not swallowed, so the part the player was on is where they left it")

	# ○ TAKES NOTHING. Read off the Character, which is where an edit would have to land.
	var slots_before: Array = surface.slot_rows().duplicate()
	var kind_before: int = character.gambits.get_at(0).action_kind
	await _press(KEY_ENTER)
	_eq(surface.level(), GambitSurfaceScript.Level.ROW, "○ on the net opens NO list")
	_eq(character.gambits.get_at(0).action_kind, kind_before,
		"and lands nothing — a press that fell through to a slot would edit the row the player"
		+ " was NOT on")
	_eq(str(surface.slot_rows()), str(slots_before), "the four slots are untouched")
	_eq(character.gambits.gambits.size(), GambitList.VISIBLE_SLOTS,
		"and the net is in NO slot — it is a buffer concern (ADR-0048 dec. 3), so the"
		+ " Character's list is the four it always was")

	# Walk back, so arm 7 starts where arm 16 left it.
	for _i in range(net_index):
		await _press(KEY_UP)
	_eq(surface.menu().selected_row(), 0, "and the glove walks back off it")


## ✕ unwinds ONE level at a time — choice → row → gone. TWO levels now, not three (ADR-0268
## dec. 1), so the walk down is one press shorter and the hazard is unchanged: a ✕ that unwound
## too far drops the player off a screen they were two presses into.
func _arm_7_cancel_unwinds_one_level_at_a_time() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null:
		_true(false, "arm 7 needs the surface open")
		return
	# Open a list to have something to unwind FROM. Arm 16 left the cursor on `Do`, so this
	# steps one right and unwinds the `To` list instead — a different part, same rule.
	await _press(KEY_RIGHT)
	await _press(KEY_ENTER)
	_eq(surface.level(), GambitSurfaceScript.Level.CHOICE, "arm 7 starts on an open choice list")
	await _press(KEY_BACKSPACE)
	# RE-FETCHED, never re-read off the captured handle. A ✕ that unwound too far frees the
	# surface, and `surface.level()` on the freed node CORE-DUMPS the rig — which is not a
	# verdict, it is the absence of one. Found by seeding exactly that defect.
	_eq(_gambit_level(), GambitSurfaceScript.Level.ROW,
		"✕ off a choice list returns to the row")
	_true(_formation_map_screen.gambit_surface() != null,
		"— it does NOT drop the player off the screen from a level in")
	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return _formation_map_screen.gambit_surface() == null)
	_eq(_formation_map_screen.gambit_surface(), null, "✕ off the row closes the surface")
	_true(_formation_map_screen.current_state() != FDT.State.GAMBIT,
		"and the coordinator left the GAMBIT screen")
	_true(_formation_map_screen.action_menu() != null,
		"putting the player back on the menu they came from")


## The edit crosses to the GPU when the TURN commits — read out of the gambit SSBO, not off the
## Character that was just written. `snapshot_battle` is the only reader of that buffer in the
## tree, and it is what a rollout candidate would be compared against.
func _arm_5_the_edit_crosses_on_commit() -> void:
	var sim = combat_loop.gpu_simulator if combat_loop != null else null
	if sim == null or director == null or director.state() != TurnDirector.State.TURN_OPEN:
		_true(false, "arm 5 needs an open turn on a live simulator")
		return
	var before: Array = _gambit_words()
	_true(not before.is_empty(), "the gambit SSBO reads back")
	var taker: int = director.taker()
	_true(director.commit(), "the turn committed")
	var after: Array = _gambit_words()
	_true(after != before,
		"the gambit SSBO CHANGED — the edited slot crossed at commit, not before and not never")
	# The window closes with THE TAKER'S turn, which is not the same claim as "no window is open".
	# `commit` DRAINS: two units can be ready at the same stop (TurnDirector.commit), so a
	# legitimate next turn re-opens the window on the NEXT taker inside the same call. A bare
	# `not is_open()` therefore asserts "nobody else was ready on this tick" — a property of the
	# battle seed, not of commit. It passed for two years on luck and ADR-0260's wider meter
	# re-rolled it: MEASURED, unit 1 committed at meter 3602 while unit 4 sat ready at 3601.
	_true(not adjustment.is_open() or adjustment.taker() != taker,
		"and the adjustment window closed with the taker's turn")


## Cancel restores BOTH holders. The battlefield [Unit] binds its `gambit_list` at spawn and never
## re-reads it from the Character (#894), so a restore that minted a fresh list would leave the
## Unit — the thing `GambitEncoder` actually reads at commit — holding the cancelled edit.
func _arm_6_and_12_cancel_takes_it_back_on_both_sides() -> void:
	var frames := 0
	while frames < MAX_WAIT_FRAMES and not (director.state() == TurnDirector.State.TURN_OPEN
			and _commandable.has(director.taker())):
		await get_tree().process_frame
		frames += 1
	if not (director.state() == TurnDirector.State.TURN_OPEN and _commandable.has(director.taker())):
		_true(false, "arm 6 needs a second steerable turn")
		return
	var taker: int = director.taker()
	var unit = units[taker]
	var character = FormationMapHost.character_for_unit(unit)
	if character == null or character.gambits == null:
		_true(false, "arm 6 needs a taker with a gambit list")
		return
	var before: int = character.gambits.get_at(1).action_kind

	adjustment.touch()
	character.gambits.get_at(1).action_kind = Gambit.ActionKind.MOVE

	# ARM 12, on the same turn and for the same rule. Design §4: "cancel must refund any imperative
	# charge spent that turn, or cancel becomes a trap". The charge is on neither half of the
	# pre-turn image the other two objects hold — it is in no SSBO for the director to restore and
	# on no Character for the adjustment turn to — so it is the ONE thing here that a cancel could
	# silently keep.
	var charges_before: int = imperatives.charges_left(taker)
	_true(imperatives.issue(taker, ImperativeGambitsScript.default_order(), _current_tick()),
		"an order is issued on this turn")
	_eq(imperatives.charges_left(taker), charges_before - 1, "which costs a charge")

	_true(director.cancel(), "the turn cancelled")
	_eq(character.gambits.get_at(1).action_kind, before,
		"cancel restored the Character's gambit list")
	_eq(imperatives.charges_left(taker), charges_before,
		"and refunded the charge the turn spent")
	_true(not imperatives.is_armed(taker),
		"taking the order with it — a refund that left the order standing would be a free one")
	_true(unit.gambit_list != null, "the battlefield Unit still holds a gambit list")
	if unit.gambit_list != null:
		_eq(unit.gambit_list, character.gambits,
			"and it is the SAME object the Character holds — the restore was IN PLACE")


## ARMS 8+9. Re-open the surface, walk into the imperative level, and compose an order. Every
## press here is free: nothing is spent until the Issue row, and — the arm that matters — nothing
## the player composes touches the rule they already authored in slot 1.
func _arm_8_and_9_composing_an_order_is_free() -> void:
	await _enter_gambit_row()
	var surface = _formation_map_screen.gambit_surface()
	if surface == null:
		_true(false, "arm 8 needs the surface re-opened")
		return
	var character = FormationMapHost.character_for_unit(units[_taker])
	var slot_before: int = character.gambits.get_at(0).action_kind
	var charges_before: int = imperatives.charges_left(_taker)

	# The fifth row, reached by walking PAST the four slots.
	for _i in range(GambitList.VISIBLE_SLOTS):
		await _press(KEY_DOWN)
	await _press(KEY_ENTER)
	_eq(surface.level(), GambitSurfaceScript.Level.IMPERATIVE,
		"○ on the fifth row opens the imperative, not slot 4")
	var order_rows: Array = surface.order_rows()
	_eq(order_rows.size(), 3, "which asks two questions and offers one press")
	_true(String(order_rows[0]).begins_with("Do:"), "row 0 is the order's Do")
	_true(String(order_rows[1]).begins_with("To:"), "row 1 is the order's To")
	_true(String(order_rows[2]).begins_with("Issue"), "row 2 is the press that spends the charge")
	_true(String(order_rows[2]).contains(str(charges_before)),
		"and it says what it costs against — the charge count is on the press that pays it")

	# Pick a Do that is NOT what slot 1 holds, so the two cannot be confused.
	await _press(KEY_ENTER)                       # row 0 = Do -> its choices
	_eq(surface.level(), GambitSurfaceScript.Level.CHOICE, "○ on the order's Do offers choices")
	_eq(surface.part(), GambitSurfaceScript.Part.DO, "titled as the part it is serving")
	await _choose_row_named("Move")
	_eq(surface.level(), GambitSurfaceScript.Level.IMPERATIVE,
		"landing a choice returns to the order, not to a slot's sentence")
	_true(surface.draft() != null, "the order is being composed on a draft")
	_eq(surface.draft().action_kind, Gambit.ActionKind.MOVE, "which took the choice")
	_true(String(surface.order_rows()[0]).begins_with("Do: Move"), "and reads it back")

	# THE ARM THAT SEPARATES THE DRAFT FROM THE SLOT. An imperative is in no slot; an
	# implementation that reused the slot cursor would have just overwritten the player's rule,
	# and every other assertion above would still be green.
	_eq(character.gambits.get_at(0).action_kind, slot_before,
		"and slot 1 is UNTOUCHED — an order is not a slot")
	_eq(imperatives.charges_left(_taker), charges_before,
		"composing costs nothing — only Issue does")
	_true(not imperatives.is_armed(_taker), "and nothing stands yet")


## ARM 10. Issue, and pay exactly once.
func _arm_10_issuing_spends_exactly_one_charge() -> void:
	var surface = _formation_map_screen.gambit_surface()
	if surface == null or surface.level() != GambitSurfaceScript.Level.IMPERATIVE:
		_true(false, "arm 10 needs the imperative level open")
		return
	var charges_before: int = imperatives.charges_left(_taker)

	# Aim it: Attack, at the weakest foe. Both through the real choice lists.
	await _press(KEY_ENTER)                       # row 0 = Do
	# ...whose list must NOT offer the clear. `order_choices_for` reuses the slot's Do
	# catalogue, and an imperative is in no slot — a clear here would empty whatever slot the
	# cursor last touched, which is the rule arm 9 above proves composing must not cost. Asserted
	# by NAME because that is the only channel that can see it: `_choose_row_named` walks to a
	# row it names, so an extra destructive row at the head sails past every other assertion.
	_true(not _menu_has_row(GambitSurfaceScript.CLEAR_LABEL),
		"the ORDER's Do list offers no clear — an imperative has no slot to empty")
	await _choose_row_named("Attack")
	await _press(KEY_DOWN)
	await _press(KEY_ENTER)                       # row 1 = To
	_true(_menu_has_row("Weakest Foe"), "the order's To offers the named pools")
	_true(not _menu_has_row("Them"),
		"and NOT 'Them' — there is no standing trigger for an order to have been triggered by")
	await _choose_row_named("Weakest Foe")
	_true(String(surface.order_rows()[1]).begins_with("To: Weakest Foe"),
		"the order reads its aim back")

	await _press(KEY_DOWN)
	await _press(KEY_DOWN)
	await _press(KEY_ENTER)                       # row 2 = Issue
	_eq(imperatives.charges_left(_taker), charges_before - 1, "issuing spent exactly one charge")
	_true(imperatives.is_armed(_taker), "and an order stands")
	var standing = imperatives.entry_for(_taker)
	_eq(standing.action_kind, Gambit.ActionKind.ATTACK, "which is the one that was composed")
	_eq(_gambit_level(), GambitSurfaceScript.Level.ROW,
		"and issuing returns to the slot level, where the order is now readable")
	_eq(_formation_map_screen.gambit_surface().imperative_row(), "! Attack → Weakest Foe",
		"the fifth row reads the standing order in the same two words that composed it")

	await _press(KEY_BACKSPACE)
	await _wait_until(func() -> bool: return _formation_map_screen.gambit_surface() == null)
	_true(imperatives.is_armed(_taker), "closing the surface does not disarm the order")


## ARM 11. The order is a LEAD entry in the gambit SSBO, and the unit acting takes it.
##
## Runs AFTER arm 5's commit, which is the crossing — so the buffer read here already carries it.
func _arm_11_the_order_is_a_lead_entry_and_the_action_takes_it() -> void:
	if not imperatives.is_armed(_taker):
		_true(false, "arm 11 needs the order to have survived the commit")
		return
	var led: Array = _gambit_words()
	_true(not led.is_empty(), "the gambit SSBO reads back")

	# The host's OWN removal handler, not a hand-rolled equivalent: design §5 puts the removal on
	# `CombatLoop.action_committed`, and this is the slot that signal lands in. Calling it directly
	# is deterministic where waiting for the unit to actually swing is not — so the EDGE itself is
	# asserted separately, because a handler nothing is connected to would pass every line below.
	_true(combat_loop.action_committed.is_connected(_on_action_committed),
		"the removal edge is wired to the loop's own signal, not merely implemented")
	_on_action_committed(_taker, -1, -1)
	_true(not imperatives.is_armed(_taker), "the unit acted, so the one-shot order is spent")
	_eq(imperatives.charges_left(_taker), imperatives.allowance() - 1,
		"and spending it refunds NOTHING — a used lock-on is used")
	await _wait_until(func() -> bool: return _gambit_words() != led)

	var bare: Array = _gambit_words()
	_true(bare != led,
		"the SSBO CHANGED when the order was taken — so the order was IN it, above the slots")
	# And what it fell back to is exactly the unit's own four slots, encoded with no lead. If the
	# push had dropped the standing rules along with the order, this would differ.
	_repush_gambits(_taker)
	await get_tree().process_frame
	_eq(_gambit_words(), bare,
		"and the buffer now equals the unit's own list — the removal took the order and"
			+ " nothing else")


## ARM 13. The watchdog is on the FRAME, and the host's `_process` is what runs it.
##
## Hand-cranks the host's own `_process` rather than awaiting real frames, for two reasons that
## are both about honesty rather than speed. The sweep only acts while the world is RUNNING, and a
## commandable turn opening mid-wait would freeze it for as long as this rig was willing to wait —
## a hang, which is worse than a failure because nothing names it. And `action_committed` is
## unhooked for the length of the arm, so the ONLY thing that can take the order is the watchdog:
## with it connected, the unit simply swinging would produce a green for the wrong reason.
##
## The loop is the host's own turn loop, cranked by hand: a commit lands the world back in
## TURN_OPEN whenever the next unit is already ready, and `tick` keeps its accumulator remainder
## across a gate break on purpose (ADR-0239), so a single frame is not guaranteed to find a
## running world.
func _arm_13_the_watchdog_rides_the_frame() -> void:
	combat_loop.action_committed.disconnect(_on_action_committed)
	var past: int = combat_loop.current_tick - imperatives.deadline_span() - 1
	_true(imperatives.issue(_taker, ImperativeGambitsScript.default_order(), past),
		"an order is issued with its deadline already behind it")
	_true(imperatives.is_armed(_taker), "and it stands")
	var charges_before: int = imperatives.charges_left(_taker)

	var steps := 0
	while steps < 64 and imperatives.is_armed(_taker):
		if director.state() == TurnDirector.State.TURN_OPEN:
			director.commit()
		_process(0.0)
		steps += 1
	_true(not imperatives.is_armed(_taker),
		"the host's own _process took it within %d frames — the watchdog rides the frame, because"
			% steps + " the stretch an unconsumed order is exposed for is BETWEEN turns")
	_eq(imperatives.charges_left(_taker), charges_before,
		"and expiry refunds nothing — design §5: a wasted lock-on is a real mistake")
	combat_loop.action_committed.connect(_on_action_committed)


# === Harness ==================================================================

## The open surface's level, or -1 when there is no surface. Asked through the coordinator so a
## surface freed by the press under test reads as "gone" rather than crashing the rig.
func _gambit_level() -> int:
	var surface = _formation_map_screen.gambit_surface()
	return surface.level() if surface != null and is_instance_valid(surface) else -1



## Walk the OPEN menu to the row spelled `name` and take it. Fails loudly rather than silently
## pressing ENTER on whatever happens to be under the glove — a choice list that stopped offering
## a row would otherwise land a DIFFERENT choice and read as a pass.
func _choose_row_named(name: String) -> void:
	var surface = _formation_map_screen.gambit_surface()
	var menu = surface.menu() if surface != null else null
	if menu == null:
		_true(false, "no menu to choose '%s' from" % name)
		return
	var row := -1
	for i in range(menu.row_count()):
		if String(menu.entries[i]) == name:
			row = i
			break
	_true(row >= 0, "'%s' is offered" % name)
	if row < 0:
		return
	for _i in range(row):
		await _press(KEY_DOWN)
	await _press(KEY_ENTER)


## The `.rows` element under a menu's window. Found by id rather than held as a reference,
## because the whole subject of arm 15 is that these elements are REBUILT and the handle from
## the previous list is a freed node.
func _rows_element_of(menu) -> UI3Element:
	for c in menu.window().get_children():
		if c is UI3Element and (c as UI3Element).id().ends_with(".rows"):
			return c
	return null


## The x span (display px) an element's payload glyphs actually occupy, measured in the space
## the clip shader tests them in — [method UI3ClipEngine.clip_basis_inv_for]'s basis. Empty when
## nothing is mounted, which is a different failure and is asserted separately.
func _glyph_x_span(elem: UI3Element) -> Array:
	if elem == null:
		return []
	var basis_inv := UI3ClipEngine.clip_basis_inv_for(elem)
	var ppu := elem.ppu()
	var lo := INF
	var hi := -INF
	for mi in elem.payload_meshes():
		var x: float = (basis_inv * (mi as Node3D).global_position).x / ppu
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return [] if lo == INF else [lo, hi]


func _menu_has_row(name: String) -> bool:
	var surface = _formation_map_screen.gambit_surface()
	var menu = surface.menu() if surface != null else null
	if menu == null:
		return false
	for i in range(menu.row_count()):
		if String(menu.entries[i]) == name:
			return true
	return false


## The taker's slice of the gambit SSBO, as the shader would read it.
func _gambit_words() -> Array:
	var snap: Dictionary = combat_loop.gpu_simulator.snapshot_battle(director.battle_id)
	return Array(snap.get("gambits", PackedInt32Array()))


## Put the cursor on the taker's tile and press △ FOR REAL, then wait for the menu.
##
## △/TAB, and NOT ○/Enter — that is the whole of a defect this rig found. Mid-battle on a
## commandable taker's turn `_cursor_confirm_is_mine()` is TRUE, so ○ belongs to the HOST and
## means "commit the turn" (ADR-0137 Amendment 2's dispatch). Pressing it here spent the turn and
## THEN opened the screen, so the menu came up with `director.taker() == -1` and every row
## correctly disabled — an assertion failure that read like a steerability bug and was a wrong
## keycode. △ is the screen's door, and Amendment 6 makes it `acting = true` from both, so the
## adjustment turn is still marked touched.
func _open_screen_on_taker() -> void:
	var unit = units[_taker]
	# `get_current_cell()` is the host's own answer (`_unit_at_grid` asks it) — a Vector3i whose
	# x/y are the COLUMN. A `Unit` has no grid_x/grid_z.
	var cell: Vector3i = unit.get_current_cell()
	tile_cursor.grid_pos = Vector2i(cell.x, cell.y)
	tile_cursor.cursor_moved.emit(tile_cursor.grid_pos)
	await get_tree().process_frame
	await _press(KEY_TAB)
	await _wait_until(func() -> bool: return _formation_map_screen.action_menu() != null)


## Walk the menu down to the Gambit row and take it.
func _enter_gambit_row() -> void:
	for _i in range(GAMBIT_ROW):
		await _press(KEY_DOWN)
	await _press(KEY_ENTER)
	await _wait_until(func() -> bool: return _formation_map_screen.gambit_surface() != null)


## One physical key press through the real InputMap — the action lookup, the coordinator's
## routing and the surface's own dispatch are all in the path. Setting the level directly would
## skip every one of them, and the routing is where "the key does nothing" lives.
func _press(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.keycode = keycode
	ev.pressed = true
	Input.parse_input_event(ev)
	for _i in 4:
		await get_tree().process_frame


func _wait_until(predicate: Callable) -> void:
	var frames := 0
	while frames < MAX_WAIT_FRAMES and not bool(predicate.call()):
		await get_tree().process_frame
		frames += 1
	if frames >= MAX_WAIT_FRAMES:
		_true(false, "waited %d frames and the condition never held" % MAX_WAIT_FRAMES)


func _eq(got, want, name: String) -> void:
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])


func _true(cond: bool, name: String) -> void:
	_eq(cond, true, name)
