extends Node

## Guard (#1272): `src/ui3/UIRoster.gd` — UI's four roster reads, reached without the
## `CharacterCatalog` autoload identifier.
##
## WHAT NO STATIC GUARD CAN SEE. `check_ui_autoload_reach.py` proves the six bare
## `CharacterCatalog.` reaches are gone. It cannot see what the door ANSWERS when no
## catalogue is installed — the state every stranger rig boots in (empty `[autoload]`
## block, ADR-0262 dec. 6) and the only state this severance exists for.
##
## 🔴 THE ABSENT ARM IS VACUOUS WITHOUT A SEEDED ROSTER. Three of the four fallbacks are
## empty (`[]`, `[]`, `null`) and a freshly booted test scene has an EMPTY catalogue, so
## `assert owned_units() == []` would pass whether the door answered its fallback,
## answered the live catalogue, or answered nothing at all. Arm 1 therefore registers a
## character and marks it owned, and asserts the verbs see it, BEFORE arm 2 takes the
## catalogue away. Same lesson as #1263's PAR fallback and #1271's flag defaults.
##
## Absence is manufactured by RENAMING the autoload node — truthful, because
## `CharacterCatalog.live()` is `get_node_or_null(^"CharacterCatalog")`. Note there is no
## `_forget_port()` here and none is needed: `live()` resolves at every call and caches
## nothing, so the rename bites immediately and the restore heals immediately. Arm 3
## asserts exactly that, because a door that cached would pass arms 1 and 2 and then
## answer stale forever in a host that mounts its catalogue late.

const UIRoster = preload("res://src/ui3/UIRoster.gd")
const CharacterClass = ExMateriaCatalogue.Character

const PROBE_SLUG := "uirosterdoortest_probe"

var _passed := 0
var _failed := 0


func _ready() -> void:
	var cat := get_tree().root.get_node_or_null(^"CharacterCatalog")
	if cat == null:
		_fail("the CharacterCatalog autoload is not in this tree — no arm can run")
		_report()
		return

	_seed(cat)
	_test_the_verbs_see_the_live_catalogue(cat)
	_test_absent_catalogue_answers_empty(cat)
	_test_live_is_resolved_per_call_not_cached(cat)
	cat.remove_owned(PROBE_SLUG)
	_report()


func _seed(cat: Node) -> void:
	var c = CharacterClass.create_default("UIRoster Probe", "4a")
	c.slug = PROBE_SLUG
	cat.register(c)
	cat.add_owned(PROBE_SLUG)


## ARM 1 — the door forwards to the autoload, and the seed is what lets arm 2 fail.
func _test_the_verbs_see_the_live_catalogue(cat: Node) -> void:
	_eq(UIRoster.is_owned(PROBE_SLUG), true,
		"is_owned sees the seeded character — the value arm 2 has to disagree with")
	_eq(UIRoster.owned_slugs().has(PROBE_SLUG), true,
		"owned_slugs contains the seeded slug")
	_eq(UIRoster.owned_units().is_empty(), false,
		"owned_units is NOT empty — without this, arm 2's `[]` proves nothing")
	_eq(UIRoster.get_character(PROBE_SLUG) != null, true,
		"get_character resolves the seeded slug")

	# Asserted against the autoload, not against the seed, so a door that answered from
	# its own cached copy of the roster fails.
	_eq(UIRoster.owned_slugs(), cat.owned_slugs(), "owned_slugs forwards to the catalogue")
	_eq(UIRoster.owned_units().size(), cat.owned_units().size(),
		"owned_units forwards to the catalogue")


## ARM 2 — no catalogue installed: every verb answers the EMPTY truth, none raises.
func _test_absent_catalogue_answers_empty(cat: Node) -> void:
	cat.name = "CharacterCatalog_absent_probe"

	_eq(UIRoster.owned_units(), [], "absent: owned_units answers [], not the seeded roster")
	_eq(UIRoster.owned_slugs(), [], "absent: owned_slugs answers []")
	_eq(UIRoster.is_owned(PROBE_SLUG), false,
		"absent: is_owned answers false — there is no overlay to be in")
	_eq(UIRoster.get_character(PROBE_SLUG), null, "absent: get_character answers null")

	cat.name = "CharacterCatalog"


## ARM 3 — `live()` resolves per call. A door that cached the node would survive arm 2
## by luck of ordering and then answer a stale catalogue for the rest of the session.
func _test_live_is_resolved_per_call_not_cached(cat: Node) -> void:
	_eq(UIRoster.is_owned(PROBE_SLUG), true,
		"the catalogue came back: no negative resolution was cached")
	cat.remove_owned(PROBE_SLUG)
	_eq(UIRoster.is_owned(PROBE_SLUG), false,
		"a live mutation is visible immediately: no POSITIVE resolution was cached either")
	cat.add_owned(PROBE_SLUG)


func _report() -> void:
	print("\n=== UIRosterDoorTest: %d passed, %d failed ===" % [_passed, _failed])
	print("[PASS] UIRosterDoorTest" if _failed == 0 else "[FAIL] UIRosterDoorTest")
	get_tree().quit(1 if _failed > 0 else 0)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if got == want:
		_passed += 1
		print("  [x] %s" % what)
	else:
		_failed += 1
		print("  [ ] %s (got %s, want %s)" % [what, got, want])


func _fail(what: String) -> void:
	_failed += 1
	print("  [ ] %s" % what)
