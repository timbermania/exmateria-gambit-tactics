extends Node

## Guard for the birthday -> zodiac wiring (finding #2 of the formation review).
##
## FFT stores no zodiac byte — the sign is DERIVED from a unit's ENTD birthday
## (bytes 4/5). This pins that derivation and the two seams that consume it:
##   1. Zodiac.zodiac_from_birthday — the pure ROM function (this enum's
##      0-based order), validated against the ROM's own uniques + the calendar-wrap
##      edges (Capricorn spans Dec/Jan; the Aquarius/Pisces small-month case).
##   2. UnitBirthdays — the committed special_name -> birthday table serves the real
##      ROM zodiacs (Agrias=Cancer, Ramza=Capricorn, Delita=Pisces).
##   3. Character.from_entd_slot — a slot with a concrete birthday sets the zodiac; a
##      Random/None sentinel leaves the default.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/ZodiacFromBirthdayTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression

# ADR-0294 dec. 2 — `Zodiac` is the shared KERNEL's since #1180, ADR-0118 dec. 1's
# twelfth schema row. dec. 3 has `UnitProgression` re-export it, and `Z` below is
# deliberately still spelled through the almanac so this file asserts that the
# re-export resolves at a real use site.
#
# 🔴 THE FUNCTION IS NOT RE-EXPORTED AND CANNOT BE. dec. 3's idiom aliases a CONST
# and an ENUM; `zodiac_from_birthday` is a STATIC FUNCTION, and GDScript resolves a
# static call against the declaring script rather than through a const alias. So
# this one call site moved to the kernel spelling where every enum site did not.
# ADR-0294 dec. 3 records the limit.
const Zodiac = ExMateriaSchema.Zodiac


const Character = ExMateriaCatalogue.Character
const UnitBirthdays = ExMateriaCatalogue.UnitBirthdays
var _failed: int = 0
var _passed: int = 0

const Z = UnitProgression.Zodiac


func _ready() -> void:
	_test_boundaries()
	_test_calendar_wrap_edges()
	_test_sentinels_return_negative_one()
	_test_rom_unique_oracle_via_birthday_table()
	_test_from_entd_slot_sets_zodiac()
	_test_from_entd_slot_keeps_default_on_random()

	print("\n=== ZodiacFromBirthdayTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ZodiacFromBirthdayTest")
		get_tree().quit(1)
	else:
		print("[PASS] ZodiacFromBirthdayTest")
		get_tree().quit(0)


## One birthday inside each sign's span, plus each sign's FIRST day (the cutoff) and
## the day before it (the previous sign) — the full 12-way partition.
func _test_boundaries() -> void:
	var cases := [
		# [month, day, expected sign]
		[3, 21, Z.ARIES],   [4, 19, Z.ARIES],
		[4, 20, Z.TAURUS],  [5, 20, Z.TAURUS],   [5, 11, Z.TAURUS],   # Algus
		[5, 21, Z.GEMINI],  [6, 21, Z.GEMINI],
		[6, 22, Z.CANCER],  [7, 22, Z.CANCER],                        # Agrias 6/22
		[7, 23, Z.LEO],     [8, 22, Z.LEO],
		[8, 23, Z.VIRGO],   [9, 22, Z.VIRGO],
		[9, 23, Z.LIBRA],   [10, 22, Z.LIBRA],
		[10, 23, Z.SCORPIO],[11, 22, Z.SCORPIO],
		[11, 23, Z.SAGITTARIUS], [12, 21, Z.SAGITTARIUS],
		[12, 22, Z.CAPRICORN],   [1, 19, Z.CAPRICORN],  [12, 30, Z.CAPRICORN],  # Ramza
		[1, 20, Z.AQUARIUS],[2, 18, Z.AQUARIUS],
		[2, 19, Z.PISCES],  [3, 20, Z.PISCES],   [3, 18, Z.PISCES],   # Delita
	]
	for c in cases:
		var got := Zodiac.zodiac_from_birthday(c[0], c[1])
		_assert_eq(got, c[2], "%d/%d -> sign %d" % [c[0], c[1], c[2]])


## The two seams a naive month scan gets wrong: Capricorn straddles the year end,
## and Aquarius/Pisces sit in numerically-small months.
func _test_calendar_wrap_edges() -> void:
	_assert_eq(Zodiac.zodiac_from_birthday(1, 1), Z.CAPRICORN, "Jan 1 wraps to Capricorn")
	_assert_eq(Zodiac.zodiac_from_birthday(1, 19), Z.CAPRICORN, "Jan 19 is Capricorn")
	_assert_eq(Zodiac.zodiac_from_birthday(1, 20), Z.AQUARIUS, "Jan 20 flips to Aquarius")
	_assert_eq(Zodiac.zodiac_from_birthday(2, 1), Z.AQUARIUS, "Feb 1 is Aquarius (not a late sign)")


func _test_sentinels_return_negative_one() -> void:
	# ENTD sentinels: 0 unset, 254 Random, 255 None; plus any out-of-range value.
	for bad in [[0, 0], [254, 254], [255, 0], [13, 1], [6, 0], [6, 32]]:
		_assert_eq(Zodiac.zodiac_from_birthday(bad[0], bad[1]), -1,
			"sentinel/oob %d/%d -> -1" % [bad[0], bad[1]])


## The committed birthday table resolves the known ROM uniques to their real signs.
func _test_rom_unique_oracle_via_birthday_table() -> void:
	_assert_eq(UnitBirthdays.zodiac_of(52), Z.CANCER, "Agrias (special 52, 6/22) -> Cancer")
	_assert_eq(UnitBirthdays.zodiac_of(2), Z.CAPRICORN, "Ramza (special 2, 12/30) -> Capricorn")
	_assert_eq(UnitBirthdays.zodiac_of(19), Z.PISCES, "Delita (special 19, 3/18) -> Pisces")
	# A special_name with no concrete birthday in the table yields -1 (keep default).
	_assert_eq(UnitBirthdays.zodiac_of(9999), -1, "unknown special_name -> -1")


func _test_from_entd_slot_sets_zodiac() -> void:
	var c = Character.from_entd_slot({"special_name": 52, "job": 0x4a, "month": 6, "day": 22})
	_assert_eq(c.progression.zodiac, Z.CANCER, "from_entd_slot(6/22) -> Cancer")


func _test_from_entd_slot_keeps_default_on_random() -> void:
	# Random(254) birthday: the game rolls it at recruit; we keep the ARIES default.
	var c = Character.from_entd_slot({"special_name": 0, "job": 0x4a, "month": 254, "day": 254})
	_assert_eq(c.progression.zodiac, Z.ARIES, "Random birthday keeps the default zodiac")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
