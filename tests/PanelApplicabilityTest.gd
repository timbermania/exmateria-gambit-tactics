extends Node
## The panel-applicability discriminator can tell a CONSUMER from a debug ROW (ADR-0263).
##
## 🔴 THE DEFECT THIS IS WRITTEN AGAINST IS A SELF-CERTIFYING INSTRUMENT, and it is the
## reason the whole check exists rather than a refinement of it. `TuneField.build_control`
## subscribes every row it renders — that is how a control resyncs when another surface
## scrubs the same slug — and `Tune.on_update` bumps `_subscriber_count`. So "does anything
## consume this slug" answered with the raw subscriber count is TRUE for any slug that has a
## visible control, i.e. true for every row the catalogue page is asking about. A dashboard
## built on it would report every knob live, on every screen, forever, and look right.
##
## So the assertions below are DIRECTION tests, not smoke: each state is proved reachable AND
## proved distinguishable from its neighbour. A check that only asserted "a real consumer
## reads CONSUMED" would pass just as happily on the broken instrument that says CONSUMED for
## everything (`a-zero-from-a-blind-instrument`, inverted — a ONE from a jammed instrument).
##
## Run: <GODOT> --path . --quit-after 5 res://tests/PanelApplicabilityTest.tscn
# test-kind: logic
# seeded-break: pass `false` instead of `true` for as_view in TuneField.build_control's
# bind_update — the "only subscriber is its own debug row stays DECLARED" arm reds, and it is
# the ONLY arm that does (verified 2026-09-08: 20 passed, 1 failed).

var _passed: int = 0
var _failed: int = 0

## Fresh slugs per assertion. `Tune`'s registry is process-scoped and its declarations
## survive `reset_overrides()`, so reusing a name across arms would let one arm's bind
## decide the next arm's verdict.
const S_VIEW := "test.applicability.view_only"
const S_CONSUMER := "test.applicability.real_consumer"
const S_UNBOUND := "test.applicability.never_bound"
const S_PEEK := "test.applicability.peek_vs_get"
const S_PLACEHOLDER := "test.applicability.placeholder"


func _ready() -> void:
	_arm_states()
	_arm_row_walk()
	_arm_catalogue()
	_arm_honest_language()

	print("\n=== Panel applicability: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] %d of %d checks failed" % [_failed, _passed + _failed])
	else:
		print("[PASS] the discriminator separates a consumer from a debug row")
	# A FRAME, not a duration (charter C14): the only thing to wait for is stdout flushing
	# through one process frame, and a real-time sleep makes the verdict a bet about load.
	await get_tree().process_frame
	get_tree().quit(1 if _failed > 0 else 0)


## The three states, each proved reachable and proved DIFFERENT from the others.
func _arm_states() -> void:
	# UNDECLARED — no bind has run. The one confident state.
	_check(Tune.consumer_state(S_UNBOUND) == Tune.Consumer.UNDECLARED,
		"a never-bound slug is UNDECLARED")

	# DECLARED — bound, nothing consuming. The resting state of a knob whose owner has
	# class-loaded but which nothing on this screen reads.
	Tune.bind(S_VIEW, 1.0)
	_check(Tune.consumer_state(S_VIEW) == Tune.Consumer.DECLARED,
		"a bound slug with no consumer is DECLARED")

	# 🔴 THE ARM THAT MATTERS. Render a real TuneField row onto that slug — the row
	# subscribes — and the state must NOT move. Before `as_view` this read CONSUMED, and
	# every other assertion in this file passed anyway.
	var host := VBoxContainer.new()
	add_child(host)
	TuneField.add(host, "View row", S_VIEW, 1.0)
	_check(Tune.consumer_state(S_VIEW) == Tune.Consumer.DECLARED,
		"a slug whose ONLY subscriber is its own debug row stays DECLARED")

	# CONSUMED — a subscriber that is not a view. Same mechanism, different declaration,
	# so this pair is the direction test for the `as_view` flag itself.
	Tune.bind(S_CONSUMER, 1.0)
	var owner := Node.new()
	add_child(owner)
	Tune.on_update(owner, S_CONSUMER, func(_v: Variant) -> void: pass)
	_check(Tune.consumer_state(S_CONSUMER) == Tune.Consumer.CONSUMED,
		"a slug with a non-view push subscriber is CONSUMED")

	# The pull half: `peek` is the view's read and must not stamp the clock; `get_value` is
	# a consumer's read and must. Asserted in both directions on ONE slug, so a peek that
	# silently delegated to get_value cannot pass.
	Tune.bind(S_PEEK, 2.0)
	var peeked: Variant = Tune.peek(S_PEEK)
	_check(peeked != null and is_equal_approx(float(peeked), 2.0),
		"peek returns the coalesced value (%s)" % str(peeked))
	_check(Tune.consumer_state(S_PEEK) == Tune.Consumer.DECLARED,
		"peek does NOT mark the slug consumed")
	Tune.get_value(S_PEEK)
	_check(Tune.consumer_state(S_PEEK) == Tune.Consumer.CONSUMED,
		"get_value DOES mark the slug consumed")


## The walk that turns a built panel into slugs — including the dead-row path, which is the
## one that matters most and the easiest to leave unstamped.
func _arm_row_walk() -> void:
	var panel := VBoxContainer.new()
	add_child(panel)
	# A registrant row (slug gets bound) and a placeholder row (owner never booted). The
	# placeholder path returns null and binds nothing, so it is the path a stamping bug
	# would skip silently.
	TuneField.add(panel, "Bound", S_PEEK)
	TuneField.add(panel, "Unbooted", S_PLACEHOLDER)

	var slugs := PanelApplicability.slugs_of(panel)
	# POSITIVE CONTROL FIRST: an empty walk would pass every "contains" assertion below for
	# free, and pass the summary counts too.
	_check(slugs.size() == 2, "the walk finds both rows (%d)" % slugs.size())
	_check(slugs.has(S_PEEK), "the walk sees a bound row's slug")
	_check(slugs.has(S_PLACEHOLDER), "the walk sees an UNBOOTED row's slug")

	var summary := PanelApplicability.summary_of(panel)
	_check(int(summary["total"]) == 2, "summary totals both rows")
	_check(int(summary["undeclared"]) == 1, "summary counts the unbooted row as undeclared")
	_check(int(summary["consumed"]) == 1, "summary counts the consumed row as consumed")

	# A panel with no TuneField rows at all is its own state, not "nothing is live" — an
	# action-only panel must not read as a dead one.
	var actions := VBoxContainer.new()
	add_child(actions)
	actions.add_child(Button.new())
	_check(PanelApplicability.slugs_of(actions).is_empty(),
		"a panel with no tunable rows yields no slugs")
	_check(PanelApplicability.summarise(PanelApplicability.summary_of(actions))
		== "no tunable rows", "a row-less panel says so rather than reading as dead")


## The catalogue's id space is the persisted key, so a gap in it is a setting that silently
## reattaches to the wrong entry. The space is [DebugPanelIds] now, not the combat mount's
## own const — moving it is what let every scene's panels carry one.
func _arm_catalogue() -> void:
	_check(not DebugPanelIds.IDS.is_empty(), "the catalogue declares ids")
	var missing: Array = []
	for id: String in DebugPanelIds.IDS:
		if not DebugPanelIds.TITLES.has(id):
			missing.append(id)
	_check(missing.is_empty(), "every catalogue id has a display title (missing: %s)" % str(missing))
	# The reverse direction, or a renamed id leaves an orphan title nothing renders.
	var orphans: Array = []
	for id: Variant in DebugPanelIds.TITLES.keys():
		if not DebugPanelIds.IDS.has(String(id)):
			orphans.append(id)
	_check(orphans.is_empty(), "no title without an id (orphans: %s)" % str(orphans))
	# Ids are the persisted form precisely so they never move. Duplicates would make
	# `has_catalog_id` skip a real second entry.
	var seen := {}
	var dupes: Array = []
	for id: String in DebugPanelIds.IDS:
		if seen.has(id):
			dupes.append(id)
		seen[id] = true
	_check(dupes.is_empty(), "catalogue ids are unique (dupes: %s)" % str(dupes))

	# The sections ARE the page, so a section that names an id outside the space renders a
	# switch for nothing, and an id in no section is a panel with no switch on the page —
	# the exact "a panel that was not there" complaint, one indirection further in.
	var sectioned := {}
	var stray: Array = []
	for section: Dictionary in DebugPanelIds.SECTIONS:
		for id: String in section["ids"]:
			sectioned[id] = true
			if not DebugPanelIds.IDS.has(id):
				stray.append(id)
	_check(stray.is_empty(), "every sectioned id is in the space (stray: %s)" % str(stray))
	var unsectioned: Array = []
	for id: String in DebugPanelIds.IDS:
		if not sectioned.has(id):
			unsectioned.append(id)
	_check(unsectioned.is_empty(),
		"every id appears in a section (unsectioned: %s)" % str(unsectioned))

	# The combat mount's own four must still BE ids, or its `_wanted` gate keys on strings
	# no switch and no persisted setting can ever match.
	var unknown: Array = []
	for id: String in CombatPanelCatalog.SUBJECT_IDS:
		if not DebugPanelIds.IDS.has(id):
			unknown.append(id)
	_check(unknown.is_empty(),
		"the combat mount's subject-bound ids are in the space (unknown: %s)" % str(unknown))


## The honesty clause, mechanized. `DECLARED` is the ABSENCE of evidence, and a label that
## called it "dead" or "inactive" would turn a not-looking into a verdict — the one failure
## mode this page was built to stop reproducing.
func _arm_honest_language() -> void:
	var banned := ["dead", "inactive", "unused", "does nothing"]
	var labels := [
		PanelApplicability.state_label(Tune.Consumer.DECLARED),
		PanelApplicability.state_label(Tune.Consumer.UNDECLARED),
		PanelApplicability.state_label(Tune.Consumer.CONSUMED),
	]
	var offenders: Array = []
	for label: String in labels:
		for word: String in banned:
			if label.to_lower().contains(word):
				offenders.append("%s -> '%s'" % [word, label])
	_check(offenders.is_empty(), "no state label claims a verdict it cannot support (%s)" % str(offenders))
	# Positive control: the walk above must actually have inspected non-empty labels.
	_check(labels.all(func(l: String) -> bool: return l.length() > 0),
		"all three state labels are non-empty (%s)" % str(labels))


func _check(ok: bool, what: String) -> void:
	if ok:
		_passed += 1
		print("  [ok] %s" % what)
	else:
		_failed += 1
		print("  [FAILED] %s" % what)
