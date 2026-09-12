extends RefCounted

## The numeric equip stat-DELTA preview computation (research/working_documents/
## EQUIP_STAT_PREVIEW.md — RE'd + oracle-validated 2026-08-12).
##
## When the equip-picker cursor rests on an item, FFT shows how each stat would change:
## `Weap.Power +4 / +5` (blue) for a gain, `-1 / -` (red + dash) for a loss. The ROM
## computes this by dry-running the equip into a scratch pseudo-unit (unit 0x14, skipping
## the real stock/stat commit) and taking `preview − base` per field into a signed delta
## array (`0x8018AB40`). The port needs no dry-run: the delta is just
## `contribution(candidate) − contribution(base)` read straight from items.json (the same
## sub-tables `extract_items.py` already parses — ADR-0001 clean, no new extractor).
##
## Faithfulness rule: FFT's numbers, OUR data path. The sign→colour→dash RENDERING lives
## in the panel (DetailScene / the vitals window); THIS module only computes the signed
## numbers.
##
## SCOPE (MVP, the oracle-proven fields): weapon → `wp`/`wev` (the Weap.Power row's two
## numbers), armor/accessory → `hp`/`mp` (the vitals HP/MP numerators). A field the item
## type doesn't drive is 0, so the panel dashes it — and routing falls out for free: a
## weapon has hp/mp 0, a body-armor has wp/wev 0. The un-exercised rows (Move/Jump/Speed/
## AT/C-EV/S-EV/A-EV) are not mapped yet (see the doc's "Full coverage" option).
##
## DEFERRED — the two-hand edge case: a two-hand weapon clears the paired hand slot in the
## ROM dry-run, so its real delta also subtracts the removed off-hand's contribution. That
## is slot-/unit-state aware and lives above this pure two-item function; add it when the
## basic path is proven.

# ADR-0211 dec. 2 / ADR-0251 dec. 3 — this addon publishes ONE global name
# (`ExMateriaAlmanac`); its own members are reached BY PATH. A `preload` const
# is a full type: it annotates, `is`-checks and `.new()`s exactly as the
# deleted `class_name` did.
const ItemDatabase = preload("res://addons/exmateria_almanac/items/ItemDatabase.gd")


## Signed `preview − base` deltas for swapping `candidate_id` into a slot currently holding
## `base_id`. An EMPTY base slot is id -1 (or any id items.json doesn't know), contributing
## 0 — so equipping into an empty slot yields the item's full contribution as the delta.
## Returns { wp, wev, hp, mp, move, jump, speed, pa, s_ev, a_ev } — one signed int per field.
static func compute(candidate_id: int, base_id: int) -> Dictionary:
	# Every field is a pure two-item CONTRIBUTION delta — the item's own additive bonus, which the
	# model adds AFTER any job multiplier (get_effective_* add the raw bonus), so no unit state is
	# needed. Full band coverage: Move/Jump/Speed and PA (feeds the AT row) from the stat-bonus block,
	# S-EV from a shield's physical block, A-EV from an accessory's evade, plus the original weapon
	# (wp/wev) and vitals (hp/mp) fields. C-EV is job-only (never equipment-driven) → not emitted, so
	# the panel dashes it. A field the item type doesn't drive is 0 → the panel dashes it (routing
	# falls out: a shield has wp/hp/speed 0, a hat has s_ev/wp 0).
	var cand := ItemDatabase.get_stat_bonuses(candidate_id)
	var base := ItemDatabase.get_stat_bonuses(base_id)
	return {
		"wp": ItemDatabase.get_weapon_power(candidate_id) - ItemDatabase.get_weapon_power(base_id),
		"wev": ItemDatabase.get_weapon_evade(candidate_id) - ItemDatabase.get_weapon_evade(base_id),
		"hp": ItemDatabase.get_hp_bonus(candidate_id) - ItemDatabase.get_hp_bonus(base_id),
		"mp": ItemDatabase.get_mp_bonus(candidate_id) - ItemDatabase.get_mp_bonus(base_id),
		"move": int(cand.get("move", 0)) - int(base.get("move", 0)),
		"jump": int(cand.get("jump", 0)) - int(base.get("jump", 0)),
		"speed": int(cand.get("speed", 0)) - int(base.get("speed", 0)),
		"pa": int(cand.get("pa", 0)) - int(base.get("pa", 0)),
		"s_ev": ItemDatabase.get_physical_block(candidate_id) - ItemDatabase.get_physical_block(base_id),
		"a_ev": ItemDatabase.get_accessory_evade(candidate_id) - ItemDatabase.get_accessory_evade(base_id),
	}
