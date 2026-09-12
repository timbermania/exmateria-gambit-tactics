extends Node

## Contract test (#743, ADR-0217 dec. 9): `ExMateriaSpriteRig.ContentPort` — the
## rig's ONE content port, seven scalar queries the HOST answers.
##
## The re-point itself is enforced statically: `touch_matrix.py` scores the rig's
## outbound `content`/`generated` lines and #743 drives them to 0, so re-adding a
## bare `JobDatabase.` inside the rig moves that number. What no static guard can
## see is the two halves this file exists for.
##
## **1. THE KEY SPACES ARE DISJOINT, AND ONLY A VALUE CAN SAY SO.** Four of the
## seven queries take an `int`, and three different int spaces reach them: a ROM
## **item** id, a weapon **type** id, and an **ability** id. Every one of them
## typechecks against every other. `SpriteLayerManager` has carried a standing
## warning about exactly this — the WEP1 table is keyed by ROM item id and *wrong
## key samples the wrong row* — so every assertion below is against a KNOWN ROW,
## by value. The load-bearing pair is `weapon_v_offset(3)` and
## `wep1_frame_offset(3)`: same literal, two spaces, two different right answers,
## so a port that routed one to the other fails on a number.
##
## **2. WHAT THE PORT DOES WHEN THE ADAPTER IS NOT THERE**, which is the state the
## whole injection was for and the one state no scene in this repo boots in. It is
## manufactured by RENAMING the autoload node and dropping the port's resolution
## cache (`_forget_adapter`) — a truthful simulation, because `_resolve()` is a
## `get_node_or_null` against a name and a consuming project with no `[autoload]`
## line differs from this one in exactly that lookup failing. The node is restored
## before the run ends.
##
## 🔴 Every present-case row below is DELIBERATELY NON-DEFAULT. Asserting a query
## returns 0 while the absent path also returns 0 is an arm that cannot fail; the
## rows were picked from the shipped data so that present and absent disagree.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/SpriteRigContentPortTest.tscn

## ADR-0212 dec. 1 / ADR-0211 dec. 4 — the addon declares one global name and this
## aliases the port back, the same way the four rig call sites do.
const ContentPort = ExMateriaSpriteRig.ContentPort

## The autoload the port resolves. Renaming it is how the absent arm is made.
const ADAPTER := ^"SpriteRigContent"

## Every arm this file runs. Asserted at the end, because a throw inside a test
## function ABORTS it: the arms after the throw never run, they are not counted as
## failures, and the verdict line reports a SMALLER green run rather than a red one.
## Seeding a record across the port during this ticket produced exactly that — one
## reported failure and five arms that silently vanished. Grow this with the arms.
const TOTAL_ARMS := 43

var _failed := 0
var _passed := 0


func _ready() -> void:
	_test_present_wep1_graphic_table()
	_test_present_zero_frame_tables()
	_test_present_the_two_int_key_spaces_disagree()
	_test_present_job_tables()
	_test_present_ability_table()
	_test_no_record_crosses()

	_test_absent_every_query()
	_test_the_port_recovers_after_the_adapter_returns()

	var ran := _passed + _failed
	_assert_eq(ran, TOTAL_ARMS, "every arm ran — a throw mid-test drops arms silently")

	print("\n=== SpriteRigContentPortTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SpriteRigContentPortTest")
		get_tree().quit(1)
	else:
		print("[PASS] SpriteRigContentPortTest")
		get_tree().quit(0)


# --- port PRESENT -------------------------------------------------------------

## `weapon_v_offset`, keyed by ROM ITEM id, against rows of
## `assets/sprites/weapon_graphic_data.json`.
func _test_present_wep1_graphic_table() -> void:
	_assert_eq(ContentPort.weapon_v_offset(2), 16, "weapon_v_offset(item 2) is the WEP1 row")
	_assert_eq(ContentPort.weapon_v_offset(3), 32, "weapon_v_offset(item 3) is the WEP1 row")
	_assert_eq(ContentPort.weapon_v_offset(4), 48, "weapon_v_offset(item 4) is the WEP1 row")
	_assert_eq(ContentPort.weapon_v_offset(9999), 0,
		"weapon_v_offset answers 0 for an item the table does not hold")


## The three zero-frame queries, keyed by weapon TYPE id, against
## `assets/sprites/wep_zero_frames.json`. All three take the SAME key and answer
## three different numbers — which is what makes a mis-wired forward visible.
func _test_present_zero_frame_tables() -> void:
	_assert_eq(ContentPort.wep1_frame_offset(6), 86, "wep1_frame_offset(type 6)")
	_assert_eq(ContentPort.wep2_frame_offset(6), 92, "wep2_frame_offset(type 6)")
	_assert_eq(ContentPort.eff1_frame_offset(6), 36, "eff1_frame_offset(type 6)")
	_assert_eq(ContentPort.wep1_frame_offset(2), 40, "wep1_frame_offset(type 2)")
	_assert_eq(ContentPort.wep2_frame_offset(2), 43, "wep2_frame_offset(type 2)")
	_assert_eq(ContentPort.eff1_frame_offset(2), 18, "eff1_frame_offset(type 2)")
	_assert_eq(ContentPort.wep1_frame_offset(9999), 0,
		"wep1_frame_offset answers 0 for a weapon type the sheet does not hold")


## 🔴 THE ARM THE TICKET IS ABOUT. The literal `3` is a valid key in BOTH int
## spaces and means two different things; the port's answers must differ.
func _test_present_the_two_int_key_spaces_disagree() -> void:
	var as_item := ContentPort.weapon_v_offset(3)
	var as_type := ContentPort.wep1_frame_offset(3)
	_assert_eq(as_item, 32, "3 as a ROM ITEM id is a WEP1 pixel offset")
	_assert_eq(as_type, 40, "3 as a weapon TYPE id is a WEP1 zero frame")
	_assert_true(as_item != as_type,
		"the two int key spaces are disjoint — swapping them changes the answer")


## The two job queries, keyed by a lowercase hex STRING, against
## `addons/exmateria_almanac/jobs/jobs.json`.
func _test_present_job_tables() -> void:
	_assert_eq(ContentPort.job_body_palette_row("60"), 2,
		"job_body_palette_row(60) is Red Chocobo's variant row")
	_assert_true(ContentPort.job_is_monster("60"), "job_is_monster(60) — Red Chocobo")

	_assert_eq(ContentPort.job_body_palette_row("4a"), 0,
		"job_body_palette_row(4a) — a humanoid job's default row")
	_assert_true(not ContentPort.job_is_monster("4a"), "job_is_monster(4a) — Squire is not")

	# 🔴 The independence proof. Holy Dragon is `special`, not `monster`, and still
	# carries a real row. A port that derived either query from the other fails here.
	_assert_eq(ContentPort.job_body_palette_row("48"), 3,
		"job_body_palette_row(48) — Holy Dragon carries a non-zero row")
	_assert_true(not ContentPort.job_is_monster("48"),
		"job_is_monster(48) is FALSE — a non-zero row does not make a monster")

	_assert_eq(ContentPort.job_body_palette_row("zz"), 0,
		"job_body_palette_row answers 0 for a job the table does not hold")
	_assert_true(not ContentPort.job_is_monster("zz"),
		"job_is_monster answers false for a job the table does not hold")


## The ability query, and the `0` vs `-1` distinction the resolver depends on.
func _test_present_ability_table() -> void:
	_assert_eq(ContentPort.ability_effect_anim_id(185), 44,
		"ability_effect_anim_id(185) is the shared cast animation")
	_assert_eq(ContentPort.ability_effect_anim_id(255), 101,
		"ability_effect_anim_id(255) is its own")
	_assert_eq(ContentPort.ability_effect_anim_id(138), 0,
		"0 — HeadBreak EXISTS and has no cast animation")
	_assert_eq(ContentPort.ability_effect_anim_id(512), -1,
		"-1 — there is no such ability")
	_assert_eq(ContentPort.ability_effect_anim_id(-1), -1,
		"-1 — a negative id names no ability")


## Criterion: **no content record, view or dict crosses**. Asserted on the port's
## own return types, which is the only place the crossing could happen.
func _test_no_record_crosses() -> void:
	_assert_eq(typeof(ContentPort.weapon_v_offset(3)), TYPE_INT, "weapon_v_offset returns int")
	_assert_eq(typeof(ContentPort.wep1_frame_offset(6)), TYPE_INT, "wep1_frame_offset returns int")
	_assert_eq(typeof(ContentPort.wep2_frame_offset(6)), TYPE_INT, "wep2_frame_offset returns int")
	_assert_eq(typeof(ContentPort.eff1_frame_offset(6)), TYPE_INT, "eff1_frame_offset returns int")
	_assert_eq(typeof(ContentPort.job_body_palette_row("60")), TYPE_INT,
		"job_body_palette_row returns int, not the job record")
	_assert_eq(typeof(ContentPort.job_is_monster("60")), TYPE_BOOL, "job_is_monster returns bool")
	_assert_eq(typeof(ContentPort.ability_effect_anim_id(185)), TYPE_INT,
		"ability_effect_anim_id returns int, not an AbilityView")


# --- port ABSENT --------------------------------------------------------------

## With no `SpriteRigContent` in the tree: six queries answer what an EMPTY content
## set would, and `ability_effect_anim_id` answers `-1` because `0` is a real answer
## there. Every row is one the present case disagreed with above.
func _test_absent_every_query() -> void:
	var node := get_tree().root.get_node_or_null(ADAPTER)
	if node == null:
		_fail("the SpriteRigContent autoload is not in this tree — the absent arm cannot run")
		return
	node.name = "SpriteRigContent_absent_probe"
	ContentPort._forget_adapter()

	_assert_eq(ContentPort.weapon_v_offset(3), 0, "absent: weapon_v_offset is 0")
	_assert_eq(ContentPort.wep1_frame_offset(6), 0, "absent: wep1_frame_offset is 0")
	_assert_eq(ContentPort.wep2_frame_offset(6), 0, "absent: wep2_frame_offset is 0")
	_assert_eq(ContentPort.eff1_frame_offset(6), 0, "absent: eff1_frame_offset is 0")
	_assert_eq(ContentPort.job_body_palette_row("48"), 0, "absent: job_body_palette_row is 0")
	_assert_true(not ContentPort.job_is_monster("60"), "absent: job_is_monster is false")
	_assert_eq(ContentPort.ability_effect_anim_id(185), -1,
		"absent: ability_effect_anim_id is -1, NOT 0 — 0 is a real answer")

	node.name = "SpriteRigContent"
	ContentPort._forget_adapter()


## The cache never holds a NEGATIVE resolution: an adapter that appears after a
## failed lookup must be found. Without this, one call made before the autoload was
## up would poison every later call for the whole session.
func _test_the_port_recovers_after_the_adapter_returns() -> void:
	_assert_eq(ContentPort.weapon_v_offset(3), 32, "the port re-resolved after its node came back")
	_assert_eq(ContentPort.ability_effect_anim_id(185), 44, "and answers the ability table again")


# --- assertions ---------------------------------------------------------------

func _assert_true(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(what)


func _assert_eq(got, want, what: String) -> void:
	if got == want:
		_passed += 1
	else:
		_fail("%s (got %s, want %s)" % [what, got, want])


func _fail(what: String) -> void:
	_failed += 1
	print("  [x] %s" % what)
