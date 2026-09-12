class_name BattleDeployment
extends RefCounted

## The control-flag gate (GAME_STATE_TRANSITIONS.md §2.6). At a battle, two paths:
##   • PREDETERMINED cast — the ENTD bakes in player-controlled units → straight to combat,
##     no formation screen. Across FFT's 72 battles this is ONLY Orbonne (ENTD 387).
##   • roster-fed — the ENTD has no control units; the player deploys their formation into
##     the deployment zone (every other battle, e.g. Gariland ENTD 388).
##
## The single decisive bit is the slot `flags2` control flag (decoded as
## `flags2_decoded.control`). Pure over an ENTD record dict; unit-tested (BattleDeploymentTest).

const ENTD_EMPTY := 0xFF


## True when the battle's cast is fixed (any non-empty slot is player-controlled) — so it
## skips deployment. `entd_record` is a loaded ENTD record dict (or null → false).
static func is_predetermined(entd_record) -> bool:
	return control_count(entd_record) > 0


## Number of non-empty, player-controlled (control-flagged) slots in the ENTD record.
static func control_count(entd_record) -> int:
	if entd_record == null:
		return 0
	var n := 0
	for slot in entd_record.get("slots", []):
		if int(slot.get("unit_id", ENTD_EMPTY)) == ENTD_EMPTY:
			continue
		if slot_is_commandable(slot):
			n += 1
	return n


## COMMANDABLE, the ENTD writer (`docs/context/41-battle-mode-and-handback.md`): does the
## unit in this slot take the player's orders at all?
##
## ONE RULE, TWO READERS, and that is the whole reason it is a function. The flag decided
## `is_predetermined` — *"deploy nobody"* — and was then thrown away, so the bit meaning
## "the player controls this unit" was never read again to answer *"steer whom"*. Every
## turn on the one predetermined battle in the game was spent where it opened
## (ADR-0265 Amendment 1).
##
## The OTHER writer is roster deployment and it does not live here: a deployed unit is the
## player's because the player placed it, which is a fact about the deployment and not
## about any ENTD slot. Two writers, one fact on the unit.
##
## 🔴 A control-flagged slot is not automatically IN the battle. `EntdBattle.combatant_slots`
## drops `always_present == false` slots, and at Orbonne two of the three control slots are
## exactly that. This answers "would this unit be yours", not "is this unit here".
static func slot_is_commandable(slot) -> bool:
	return bool(slot.get("flags2_decoded", {}).get("control", false))
