class_name ScenarioDirectorState
extends RefCounted

## Pluggable state source for the BattleConditionals director.
##
## The director never *writes* game state — every BattleConditional opcode except
## `Run Scenario` is a read-only requirement (a check against combat, variable, or
## party state). This base class is the query interface the interpreter calls; it
## returns an "empty world" (nothing present, everything zero, no victory) so an
## unwired director simply never advances. Concrete sources override the parts they
## can answer:
##   - a combat source backed by the GPU engine's unit state (HP / turn / presence
##     by ENTD unit id) — the eventual real wiring;
##   - a stub with hand-set values for tests;
##   - a debug/manual source that lets a human force a branch from the F3 picker.
##
## Unit ids are **byte 0 of the ENTD slot** -- `sprite_set` in `entd.json` --
## matching the `Unit=` operand in the bytecode. They are NOT slot indices:
## retail BC data addresses units up to 133 and a battle has 21 slots. Nor are
## they `unit_id`: the two agree on 374 of the 375 ENTD slots in the resolver's
## accepted range and differ at ENTD 462 slot 1. The ROM resolves the operand at
## `0x80142508`, which accepts ids 1..0x49 and scans the battle unit array for
## `b[0x00]`. (WITHIN_GROUP_MEMBER_TRANSITION.md 7.11.7; operands 128/133 take a
## different path and are still [OPEN].)
##
## Variable ids are the raw BattleConditional variable indices (e.g. 0x7d phase
## flag, 0x96 menu choice), also matching the operands.

## BattleConditional variable store: value of variable `id` (default 0).
func get_variable(_id: int) -> int:
	return 0

## Is the unit (ENTD id) on the field and not yet removed?
func unit_present(_unit_id: int) -> bool:
	return false

## Current HP of the unit (absolute). 0 when absent/dead.
func unit_hp(_unit_id: int) -> int:
	return 0

## Current HP of the unit as a percentage 0..100.
func unit_hp_percent(_unit_id: int) -> int:
	return 0

## Current MP of the unit (absolute).
func unit_mp(_unit_id: int) -> int:
	return 0

## Is it currently this unit's active turn?
func is_active_turn(_unit_id: int) -> bool:
	return false

## Has the battle reached its victory state (win condition met)?
##
## The ROM's contract, measured -- `0x80183374` tallies the standing units on each
## side of `unit.b[0x1BA] & 0x30`, and the `Victory` opcode is true exactly when it
## returns 0, which is: **at least one PLAYER unit standing and NO enemy standing**.
## `&0x30 == 0` is the player's side (it is the ENTD `team_color` shifted left 4).
## "Standing" excludes Crystal / Dead / Petrify / Invite / BloodSuck / Treasure.
## So this is not "the win condition is met" in general -- it is specifically
## *the enemy is wiped*, and it must be false while any enemy is still standing
## even if the map objective is otherwise complete.
## (WITHIN_GROUP_MEMBER_TRANSITION.md 7.11.4-5; poked both ways on a live battle.)
func is_victory() -> bool:
	return false

## Party gil.
func gil() -> int:
	return 0

## Number of casualties so far this battle.
func casualties() -> int:
	return 0

## Does the main character have `item_id` equipped?
func main_character_equipped(_item_id: int) -> bool:
	return false

## Current in-game date as [month, day]. Default is the epoch (0, 0).
func date() -> Array:
	return [0, 0]

## The unit's tile as [x, y, layer], or [] if the unit isn't placed.
## `layer` is the map's upper/lower-tile BIT (0 or 1), not an elevation: the ROM
## compares it against bit 15 of the halfword at unit+0x48, while x/y are the bytes
## at unit+0x47 and +0x48. See WITHIN_GROUP_MEMBER_TRANSITION.md §7.5.
func unit_location(_unit_id: int) -> Array:
	return []

## A team's reference tile as [x, y, layer], or [] if unknown. Same encoding as
## [method unit_location] — `layer` is a bit, not a height.
func team_location(_team_id: int) -> Array:
	return []
