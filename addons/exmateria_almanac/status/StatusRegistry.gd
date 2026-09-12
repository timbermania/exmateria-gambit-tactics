extends RefCounted

## Single source of truth for FFT status effects (#67).
##
## Mirrors the `STATUS_*` bit constants in the host's
## `combat_common.glslinc`. The drift assertion that used to parse that shader
## from here lives in `tests/StatusRegistryTest.gd::_test_shader_parity`
## (ADR-0251 dec. 4): a table in a portable addon cannot hold a `res://` path
## into the game it was extracted from, and the test's copy is the stronger
## instrument anyway — it `_expect`s and FAILs, where this one could only
## `push_error` from a static initializer that fires at most once per boot.
##
## Used by [code]GambitEncoder._encode_gambit_condition[/code] (HAS_STATUS /
## MISSING_STATUS) and scenario authoring (status seeding via `bitmask(...)`).
## Single-bit-per-condition stays the contract — multi-status semantics compose
## via rule D5 AND-combine across multiple conditions on a slot.

# Hand-mirrored from combat_common.glslinc:219-250. Names match FFT canon
# (lowercase StringNames, hyphenless). `StatusRegistryTest::_test_shader_parity`
# catches any rename or renumber on the GLSL side.
const NAMES_TO_BITS: Dictionary = {
	&"dead": 0,
	&"undead": 1,
	&"charging": 2,
	&"jump": 3,
	&"defending": 4,
	&"performing": 5,
	&"petrify": 6,
	&"stop": 7,
	&"sleep": 8,
	&"immobilize": 9,
	&"disable": 10,
	&"blind": 11,
	&"berserk": 12,
	&"chicken": 13,
	&"frog": 14,
	&"poison": 15,
	&"regen": 16,
	&"protect": 17,
	&"shell": 18,
	&"haste": 19,
	&"slow": 20,
	&"float": 21,
	&"reraise": 22,
	&"transparent": 23,
	&"confusion": 24,
	&"silence": 25,
	&"blood_suck": 26,
	&"curse": 27,
	&"invite": 28,
	&"darkness": 29,
	&"oil": 30,
	&"faith": 31,
}

# The ROM's own default duration per status, in FFT CT units (#1116). Extracted
# from the status-attribute table in SCUS_942.21 — byte +0x00 of the record at
# 0x80065DE7 + 0x10*status — by `tools/extract_status_attributes.py`, which
# carries the three disassembly citations that fix the base, the stride and the
# meaning of the byte. `combat_common.glslinc::status_default_ct` mirrors this
# table and `tests/StatusRegistryTest.gd::_test_duration_parity` holds the two
# equal, the same way the bit numbers are held.
#
# 🔴 ABSENT MEANS PERMANENT, AND THAT IS A ROM ANSWER. FFT gives a countdown byte
# to sixteen of its forty statuses (`unit+0x5D + (status - 24)`); the rest have
# nowhere to count down, so Darkness, Silence, Oil, Frog, Confusion, Berserk,
# Petrify, Blood Suck, Float, Reraise and Transparent last until something cancels
# them. Writing a number for any of them would be invention, not a default.
#
# Five of the ROM's sixteen have no bit in this registry yet — Wall (24 CT),
# Innocent (32), Charm (32), Reflect (32) and Death Sentence (3) are the names
# `StatusEncoder.UNMAPPED_NAMES` skips (#99). Their countdown slots are reserved in
# `TIMER_SLOT` so adding them renumbers nothing.
const DEFAULT_CT: Dictionary = {
	&"poison": 36,
	&"regen": 36,
	&"protect": 32,
	&"shell": 32,
	&"haste": 32,
	&"slow": 24,
	&"stop": 20,
	&"faith": 32,
	&"sleep": 60,
	&"immobilize": 24,   # FFT "Don't Move"
	&"disable": 24,      # FFT "Don't Act"
}

# Which of the sixteen per-unit countdown slots a timed status owns. The indices
# are the ROM's own (`status - 24` in FFT's status order), so the gaps — 7 Wall,
# 9 Innocent, 10 Charm, 14 Reflect, 15 Death Sentence — are reservations and not
# holes. The kernel packs two 16-bit counters per `U_STATUS_TIMER_*` int, so the
# slot index is what addresses a countdown; a status absent here is never timed.
const TIMER_SLOT: Dictionary = {
	&"poison": 0,
	&"regen": 1,
	&"protect": 2,
	&"shell": 3,
	&"haste": 4,
	&"slow": 5,
	&"stop": 6,
	&"faith": 8,
	&"sleep": 11,
	&"immobilize": 12,
	&"disable": 13,
}

## How many of this kernel's ticks one FFT CLOCK TICK costs — the unit the ROM's
## durations are counted in. Mirrors `combat_common.glslinc::TICKS_PER_CLOCK_TICK`,
## which derives it from the turn meter (`TURN_METER_FULL / 100`, ADR-0236) rather
## than choosing it. Not the 30 an ability's charge CT is multiplied by: charge is
## speed-independent in this kernel and a status counter is not.
const TICKS_PER_CLOCK_TICK := 36


static func default_ct(status_name: StringName) -> int:
	"""The status's ROM default duration in CT units, or 0 when the ROM gives it
	no countdown (permanent until cancelled). Unknown names are a typo, not a
	permanent status, so they `push_error` through [method bit] first."""
	if bit(status_name) < 0:
		return 0
	return int(DEFAULT_CT.get(status_name, 0))


static func default_duration_ticks(status_name: StringName) -> int:
	"""The same duration in kernel ticks — what a seeded `status_timers` entry
	should carry to match what a battle would arm. 0 for a permanent status."""
	return default_ct(status_name) * TICKS_PER_CLOCK_TICK


static func timer_slot(status_name: StringName) -> int:
	"""The status's countdown slot (0..15), or -1 for a status the ROM never
	times."""
	if bit(status_name) < 0:
		return -1
	return int(TIMER_SLOT.get(status_name, -1))


static func timer_slot_for_bit(bit_index: int) -> int:
	"""[method timer_slot] keyed by bit number — what a packer holding a bit
	rather than a name needs. -1 for an untimed or unknown bit, without the
	`push_error` [method bit] emits: a caller walking all 32 bits is not making a
	typo."""
	var status_name := name_of(bit_index)
	if status_name == &"":
		return -1
	return int(TIMER_SLOT.get(status_name, -1))


static func bit(status_name: StringName) -> int:
	"""Return the bit index for [param status_name], or -1 if unknown.
	An unknown name emits [code]push_error[/code] — typos in scenario / gambit
	authoring fail loud rather than degenerating to STATUS_DEAD (bit 0)."""
	if not NAMES_TO_BITS.has(status_name):
		push_error("[StatusRegistry] Unknown status name: %s" % status_name)
		return -1
	return NAMES_TO_BITS[status_name]


static func bitmask(names: Array) -> int:
	"""OR-combine the bits for each name in [param names].
	Convenience for scenario authoring — e.g.
	[code]status_flags_lo: StatusRegistry.bitmask([&"silence", &"haste"])[/code]."""
	var mask := 0
	for n in names:
		var b := bit(n)
		if b >= 0:
			mask |= (1 << b)
	return mask


static func name_of(bit_index: int) -> StringName:
	"""Inverse lookup — bit index → canonical name, or [code]&""[/code] if
	[param bit_index] has no registered name."""
	for n in NAMES_TO_BITS:
		if NAMES_TO_BITS[n] == bit_index:
			return n
	return &""

