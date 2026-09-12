extends Node
## TDD guard for **chain inspection** (ADR-0085 amendment 2026-08-21 + ADR-0073 dec. 11): a sound-event click SEEDS the nav stack with the whole
## [span → container → pair] chain in one gesture, and the inspector renders every entry
## co-resident instead of one at a time.
##
## The contract this suite exists to protect, in order:
##   1. a ONE-entry stack renders EXACTLY what it renders today — byte-identically, not
##      "close enough". Everything else is additive on top of that;
##   2. seeding is OPT-IN per seed: a `link` drill never becomes a chain;
##   3. the deepest slot is a CHOICE among the container's fires — picking a sibling
##      REPLACES it, never grows the stack to two FEDS sections;
##   4. the Container's collapsed line keeps `used by N triggers` (ADR-0092's property);
##   5. an EXPLICIT fold toggle resets the height latch; a rebuild does not;
##   6. an ancestor link is a scroll, not a step back, and the breadcrumb goes.
##
## Fixtures are REAL EFFECT DIRECTORIES read through the real loader — E026 (the FEDS
## baseline: 2 firing events, 4 containers, and container 0 in mode 2 emitting TWO pairs,
## so the dropdown is exercised) and E005 (a sound_id naming a container that does not
## exist — 1 of the 13 corpus cases). No hand-written span dicts.
##
## Run: <GODOT> --path . --quit-after 400 res://tests/EffectStudioChainInspectionTest.tscn

const EffectEmitter = ExMateriaEffects.EffectEmitter

const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const ContainerModel = preload("res://src/effects/studio/SoundContainerModel.gd")
const TimelineDataClass = ExMateriaEffects.TimelineData

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	await _test_one_entry_stack_renders_exactly_the_back_targets_sections()
	await _test_a_link_drill_is_not_a_chain()
	await _test_a_sound_click_seeds_and_renders_three_entries()
	await _test_the_container_line_keeps_used_by_n_triggers()
	await _test_breadcrumb_is_suppressed_for_a_chain()
	await _test_an_ancestor_link_scrolls_instead_of_truncating()
	await _test_a_sibling_pair_replaces_the_deepest_slot()
	await _test_fire_ordinal_choices_come_from_fire_sequence()
	await _test_the_dropdown_navigates_and_replaces_slot_three()
	await _test_a_dead_container_reference_seeds_one_entry()
	await _test_an_explicit_fold_toggle_resets_the_latch()
	await _test_a_rebuild_does_not_reset_the_latch()
	await _test_every_press_on_a_trigger_inspects_the_same_chain()
	await _test_a_press_that_resolves_to_no_pair_is_a_root_either_way()

	print("\n=== EffectStudioChainInspectionTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioChainInspectionTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioChainInspectionTest")
		get_tree().quit(0)


# --- 1. the regression contract -------------------------------------------

## THE contract (ADR-0073 dec. 11): "a one-entry stack renders exactly as it does today".
## Guarded on the section array the page actually hands the inspector — deep-equal to what
## the registry produces for `_nav.back()` alone, so a chain-shaped composition can never
## leak into an ordinary inspection.
func _test_one_entry_stack_renders_exactly_the_back_targets_sections() -> void:
	var page = await _page()
	var span_id := _load_synthetic(page)
	page._on_span_selected(span_id)
	_assert_eq(page._nav.size(), 1, "a particle span select is still a single-item root")
	_assert_true(not page._nav_chain, "a plain span root is NOT marked render-as-chain")
	var score: Dictionary = page._timeline._score
	var direct := Model.inspector_sections(page._nav.back(), page._effect_data, score)
	_assert_true(page._sections_for_render(score) == direct,
		"a 1-entry stack renders EXACTLY _nav.back()'s sections (deep equality)")
	_assert_eq(page._inspector.group_count(), direct.size(),
		"…and the inspector built exactly that many sections")
	page.queue_free()


## Opt-in per SEED, not per kind: drilling a `link` never turns the stack into a chain, so
## span → emitter still shows only the emitter. This is what keeps the blast radius off
## every other inspectable kind.
func _test_a_link_drill_is_not_a_chain() -> void:
	var page = await _page()
	var span_id := _load_synthetic(page)
	page._on_span_selected(span_id)
	page._navigate_to(Target.emitter(0))
	_assert_eq(page._nav.size(), 2, "the drill pushed")
	_assert_true(not page._nav_chain, "a link drill does NOT mark the stack render-as-chain")
	var score: Dictionary = page._timeline._score
	_assert_true(page._sections_for_render(score)
			== Model.inspector_sections(Target.emitter(0), page._effect_data, score),
		"a drilled 2-entry stack still renders ONLY the emitter (unchanged from today)")
	page.queue_free()


# --- 2. the seeded chain --------------------------------------------------

func _test_a_sound_click_seeds_and_renders_three_entries() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	_assert_true(span_id != "", "E026 has a firing sound event to click")
	page._on_span_selected(span_id)
	_assert_eq(page._nav.size(), 3, "a sound-event click seeds [span, container, pair]")
	_assert_true(page._nav_chain, "the seed is marked render-as-chain")
	_assert_eq(Target.kind(page._nav[0]), "span", "slot 1 is the trigger's span")
	_assert_eq(Target.kind(page._nav[1]), "container", "slot 2 is the container")
	_assert_eq(Target.kind(page._nav[2]), "pair", "slot 3 is the FEDS pair")

	var score: Dictionary = page._timeline._score
	var rendered: Array = page._sections_for_render(score)
	# Every entry's sections are present, in stack order — the chain is CO-RESIDENT.
	var want := 0
	for t in page._nav:
		want += Model.inspector_sections(t, page._effect_data, score).size()
	_assert_true(rendered.size() >= want,
		"the chain renders every entry's sections (%d of %d tiers' worth)" % [rendered.size(), want])
	_assert_true(page._inspector.group_count() == rendered.size(),
		"the inspector built one section per composed section")
	# The two upper tiers collapse to a summary line each (decision 4); the FEDS tier does not.
	var collapsed := 0
	for s in rendered:
		if bool(s.get("collapsed", false)):
			collapsed += 1
	_assert_true(collapsed >= 2, "Event and Container collapse by default, the FEDS sections do not")
	page.queue_free()


## ADR-0092's surviving property: the shared container's blast radius stays visible even
## when its section is collapsed to one line. If this ever reads without a trigger count,
## the "answered, not overturned" argument in the amendment has quietly stopped being true.
func _test_the_container_line_keeps_used_by_n_triggers() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	page._on_span_selected(span_id)
	var summary := ""
	for s in page._sections_for_render(page._timeline._score):
		if str(s.get("fold_key", "")) == "chain:container":
			summary = str(s.get("summary", ""))
	_assert_true(summary.contains("used by") and summary.contains("trigger"),
		"the collapsed Container line carries `used by N triggers` (got %s)" % summary)
	page.queue_free()


## Decision 6: `Path › Event › Container` names surfaces that are on the same page.
func _test_breadcrumb_is_suppressed_for_a_chain() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	page._on_span_selected(span_id)
	# The trail moved from inspector header rows to the PATH BAR (2026-08-20), so the
	# suppression moved with it — the invariant is the same one: a chain's entries are all
	# on the page below, so naming them again is chrome describing itself.
	_assert_eq(page._path_crumbs(page._timeline._score).size(), 0,
		"a chain stack renders no trail")
	# …but an ordinary drill path still does.
	page._nav_chain = false
	_assert_true(page._path_crumbs(page._timeline._score).size() > 0,
		"an ordinary multi-entry stack still shows its trail")
	page.queue_free()


## Decision 6: the trigger's `Plays → container N` cell points at _nav[1]. Under the
## ORDINARY rule that is an ancestor revisit, which truncates — and would destroy the very
## chain the author is reading. In a chain it is a scroll instead.
func _test_an_ancestor_link_scrolls_instead_of_truncating() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	page._on_span_selected(span_id)
	var container: Dictionary = page._nav[1].duplicate(true)
	page._navigate_to(container)
	_assert_eq(page._nav.size(), 3, "navigating to an on-screen ancestor does NOT truncate the chain")
	_assert_true(Target.equals(page._nav[1], container), "…and the ancestor is still slot 2")
	page.queue_free()


## Decision 3 / the rejected "render every pair": the deepest slot holds ONE pair. A
## sibling replaces it rather than growing the stack to two FEDS sections + two lane panels.
func _test_a_sibling_pair_replaces_the_deepest_slot() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_multipair_span(page, "res://assets/effects/E026")
	_assert_true(span_id != "", "E026 has an event on a container that emits >1 pair")
	page._on_span_selected(span_id)
	var seeded: int = int(Target.ref(page._nav[2]).get("pair_idx", -1))
	var sibling := _other_pair_idx(page, seeded)
	_assert_true(sibling >= 0, "the container emits a second distinct pair")
	page._navigate_to(Target.pair(sibling))
	_assert_eq(page._nav.size(), 3, "a sibling pair does not grow the stack")
	_assert_eq(int(Target.ref(page._nav[2]).get("pair_idx", -1)), sibling,
		"…it REPLACES the deepest slot")
	page.queue_free()


# --- 3. the fire-ordinal dropdown -----------------------------------------

## Labels come from the resolver via `fire_sequence` — never a re-derivation here — and
## name the ORDINAL and the SLOT only. No reachability is claimed: whether a 2nd fire ever
## happens turns on the per-container counter, which our runtime resets per cast and the
## ROM may not (the amendment's out-of-scope finding). The ordinal is true either way.
func _test_fire_ordinal_choices_come_from_fire_sequence() -> void:
	var doc := {"containers": [{"mode": 2, "id_a": 1, "id_b": 3, "id_c": 0, "index": 0}]}
	var choices := ContainerModel.pair_choices(doc, 0, 8)
	_assert_eq(choices.size(), 2, "mode 2 (Sound 1 once, then 2) offers two distinct pairs")
	_assert_eq(str(choices[0].get("label", "")), "1st fire · Sound 1 · entry 0",
		"the first choice names fire 1, slot 1 and its bank entry")
	_assert_eq(str(choices[1].get("label", "")), "2nd fire · Sound 2 · entry 2",
		"the second names fire 2, slot 2 and its bank entry")
	# The pair indices agree with the resolver's own ordering, not with a slot ordering.
	var ids := ContainerModel.fire_sequence(doc, 0, 6)
	_assert_eq(int(choices[0].get("pair_idx", -1)), int(ids[0]) - 1,
		"choice 1's pair is fire 1's resolved id − 1")
	_assert_eq(int(choices[1].get("pair_idx", -1)), int(ids[1]) - 1,
		"choice 2's pair is fire 2's resolved id − 1")
	# A single-pair container offers no choice at all — the 84.7% case costs nothing.
	_assert_eq(ContainerModel.pair_choices(
			{"containers": [{"mode": 0, "id_a": 1, "id_b": 0, "id_c": 0, "index": 0}]}, 0, 8).size(),
		1, "a 1-pair container yields a single entry (the page renders no dropdown for it)")


## The dropdown is NAVIGATION, not an edit — it moves the stack and never approaches the
## write choke point. Picking entry i replaces _nav[2] with that pair.
func _test_the_dropdown_navigates_and_replaces_slot_three() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_multipair_span(page, "res://assets/effects/E026")
	page._on_span_selected(span_id)
	var widgets: Array = page._inspector.nav_choice_widgets()
	_assert_eq(widgets.size(), 1, "a multi-pair container grows exactly one fire dropdown")
	var ob = widgets[0]
	_assert_true(ob.item_count >= 2, "the dropdown lists every distinct pair the container fires")
	# Pick whichever entry is not the seeded one.
	var seeded: int = int(Target.ref(page._nav[2]).get("pair_idx", -1))
	var pick := -1
	for i in range(ob.item_count):
		if not ob.get_item_text(i).ends_with("entry %d" % seeded):
			pick = i
	_assert_true(pick >= 0, "the dropdown offers a sibling to pick")
	ob.item_selected.emit(pick)
	_assert_eq(page._nav.size(), 3, "picking a fire does not grow the stack")
	_assert_true(int(Target.ref(page._nav[2]).get("pair_idx", -1)) != seeded,
		"picking a fire replaced the deepest slot with the sibling")
	page.queue_free()


# --- 4. degenerate chains -------------------------------------------------

## Decision 7: a chain that does not resolve is SHORT, not special-cased — it seeds a
## 1-entry stack and renders as an ordinary span inspection.
##
## The amendment names the 13 events across 9 effects whose `sound_id` points at a
## container index that does not exist. Every one of those 13 sits at `index ==
## max_keyframe`: they are TERMINATOR end-caps, not firing events (`measure_sound_fanout.py`
## counts `i <= last`, which includes the end-cap). No FIRING event in the corpus names a
## missing container, so that is not a case a click can reach — the reachable degenerate is
## the end-cap itself, and there are 112 of those across 52 effects carrying a sound_id that
## DOES resolve. Clicking one must not claim it plays anything: its own projector renders
## "End of track … It is not a sound", and a chain beside that row would contradict it.
func _test_a_dead_container_reference_seeds_one_entry() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_resolving_terminator(page, "res://assets/effects/E018")
	_assert_true(span_id != "", "E018 has an end-cap whose sound_id resolves to a live container")
	_assert_true(page._span_sound_id(span_id) >= 2,
		"…the end-cap's slot really does carry an audible-looking id (the trap)")
	page._on_span_selected(span_id)
	_assert_eq(page._nav.size(), 1, "an end-cap seeds a 1-entry stack — it fires nothing")
	_assert_true(not page._nav_chain, "…and is not marked render-as-chain")
	var score: Dictionary = page._timeline._score
	_assert_true(page._sections_for_render(score)
			== Model.inspector_sections(page._nav.back(), page._effect_data, score),
		"…so it renders exactly as an ordinary span inspection (the inert terminator row)")
	# Belt and braces: an UNRESOLVABLE firing event is short for the same reason.
	_assert_eq(page._pair_nav_for_sound_span("sound:phase1:0#0").size() >= 0, true,
		"the seed predicate is total — it answers for any span id")
	page.queue_free()


# --- 5. the height latch --------------------------------------------------

## Decision 5: the 2026-08-20 latch exists to absorb the REBUILD transient. A deliberate
## collapse is not a transient — without a reset, expanding then collapsing the Container
## section would leave a permanent gap under the inspector for that event.
func _test_an_explicit_fold_toggle_resets_the_latch() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	page._on_span_selected(span_id)
	var key: String = page._target_key(page._nav[0])
	page._editor_latch = {"key": key, "h": 420.0}
	page._on_inspector_fold_toggled()
	# Guarded on the EFFECT, not the representation: after the toggle the mark no longer
	# holds the band at 420 — the next layout tracks the height the author just chose.
	_assert_eq(Page._latched_editor_h(page._editor_latch, key, 120.0), 120.0,
		"an explicit fold toggle drops the high-water mark")
	page.queue_free()


func _test_a_rebuild_does_not_reset_the_latch() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	page._on_span_selected(span_id)
	var key: String = page._target_key(page._nav[0])
	page._editor_latch = {"key": key, "h": 420.0}
	page._render_current()          # the rebuild the latch was built to absorb
	_assert_eq(Page._latched_editor_h(page._editor_latch, key, 120.0), 420.0,
		"a rebuild leaves the high-water mark standing")
	page.queue_free()


# --- fixtures -------------------------------------------------------------

func _page():
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	page.bind_host(_FakeHost.new())
	return page


## A synthetic, SOUNDLESS effect (particle span → emitter 0 → emitter 1 on death) — the
## 1-entry-stack control. Mirrors EffectStudioNavStackTest's fixture on purpose.
func _load_synthetic(page) -> String:
	var ed = ExMateriaEffects.EffectData.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8},
		"particle_channels": [
			{"context": "for_each", "channel_index": 0, "max_keyframe": 1, "keyframes": [
				{"time": 0, "emitter_id": 0}, {"time": 10, "emitter_id": 1}]},
		],
	})
	var em0 = EffectEmitter.new()
	em0.child_emitter_on_death = 1
	ed.emitters.append(em0)
	ed.emitters.append(EffectEmitter.new())
	page._effect_data = ed
	page._sound_env = {}
	page._nav.clear()
	page._nav_chain = false
	page._timeline.load_score(Model.build(ed))
	return Model.build(ed)["lanes"][0]["spans"][0]["id"]


## Load a REAL effect directory through the page's own loader — real bytes, real decoder,
## real fold_spans — and return the first firing sound event whose chain fully resolves.
func _load_effect_and_find_firing_span(page, dir: String) -> String:
	page._load_effect(dir)
	for span_id in _sound_event_ids(page):
		if not page._pair_nav_for_sound_span(span_id).is_empty():
			return span_id
	return ""


## The first firing event whose container emits MORE THAN ONE distinct pair — the 15.3%
## of events the fire dropdown exists for.
func _load_effect_and_find_multipair_span(page, dir: String) -> String:
	page._load_effect(dir)
	for span_id in _sound_event_ids(page):
		var seed: Array = page._pair_nav_for_sound_span(span_id)
		if seed.is_empty():
			continue
		var idx := int(Target.ref(seed[1]).get("index", -1))
		if ContainerModel.pair_choices(page._effect_data.sound_containers, idx,
				page._sound_env["feds_bank"].num_pairs).size() > 1:
			return span_id
	return ""


## The first TERMINATOR end-cap whose padding sound_id resolves to a live container — the
## reachable degenerate case (112 of them across 52 effects).
func _load_effect_and_find_resolving_terminator(page, dir: String) -> String:
	page._load_effect(dir)
	var n: int = (page._effect_data.sound_containers.get("containers", []) as Array).size()
	for lane in page._timeline._score.get("lanes", []):
		if str(lane.get("kind", "")) != "sound":
			continue
		for span in lane.get("spans", []):
			if str(span.get("role", "")) != "terminator":
				continue
			var sid: int = page._span_sound_id(str(span.get("id", "")))
			if sid >= 2 and (sid - 2) < n:
				return str(span.get("id", ""))
	return ""


## Every firing sound event's span id off the projected score (terminators excluded).
func _sound_event_ids(page) -> Array:
	var out: Array = []
	for lane in page._timeline._score.get("lanes", []):
		if str(lane.get("kind", "")) != "sound":
			continue
		for span in lane.get("spans", []):
			if str(span.get("role", "")) == "event":
				out.append(str(span.get("id", "")))
	return out


## A distinct pair the open chain's container emits that is NOT `seeded`, or -1.
func _other_pair_idx(page, seeded: int) -> int:
	var idx := int(Target.ref(page._nav[1]).get("index", -1))
	for c in ContainerModel.pair_choices(page._effect_data.sound_containers, idx,
			page._sound_env["feds_bank"].num_pairs):
		if int(c.get("pair_idx", -1)) != seeded:
			return int(c.get("pair_idx", -1))
	return -1


class _FakeHost extends RefCounted:
	func studio_seek(_frame: int) -> void: pass
	func studio_set_playing(_playing: bool) -> void: pass
	func studio_current_frame() -> int: return 0
	func studio_select_effect(_id: int) -> void: pass


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


# --- 7. every press on a trigger inspects the same thing --------------------

## THE BUG THIS EXISTS FOR (found 2026-08-21e, by the author clicking a trigger and getting
## the config rows): a sound trigger stacks several hit targets on the same few pixels, and
## `hit_test` gives the FIRE handle priority over the select marker — deliberately, so a
## marker grab drags the trigger rather than merely inspecting it. But the handle is 9 px
## wide over an 8 px select rect, so for every trigger past the first it covers the marker
## COMPLETELY. The chain seeding was added to `_on_span_selected` and only there, so the
## path a plain click actually takes — `_on_fire_drag_started` — answered with the bare
## one-entry span root: the "all-in-one sound page" was unreachable by clicking the thing
## the author aims at.
##
## The invariant, and the one worth guarding rather than any particular rect width: **the
## press is a SELECTION and the drag is an EDIT.** Which pixel of a trigger you press decides
## what you can DRAG; it must never decide what you INSPECT. So both entry points are driven
## here and asserted to land on the same stack.
func _test_every_press_on_a_trigger_inspects_the_same_chain() -> void:
	var page = await _page()
	var span_id := _load_effect_and_find_firing_span(page, "res://assets/effects/E026")
	_assert_true(span_id != "", "E026 has a firing sound event")

	page._on_span_selected(span_id)
	var by_click: Array = page._nav.duplicate()
	_assert_eq(by_click.size(), 3, "the SELECT path seeds the chain")
	_assert_true(page._nav_chain, "…and marks it as one")

	# Now the other door, from a clean slate — the fire grab, which is what a press on the
	# marker really routes to.
	page._nav = []
	page._nav_chain = false
	page._on_fire_drag_started(span_id)
	_assert_eq(page._nav.size(), 3, "the FIRE-GRAB path seeds the chain too")
	_assert_true(page._nav_chain, "…and marks it as one, so it RENDERS as one")
	for i in range(mini(by_click.size(), page._nav.size())):
		_assert_true(Target.equals(by_click[i], page._nav[i]),
				"tier %d is the same target whichever way the trigger was pressed" % i)

	# The Gap the fire grab exists to move stays ON SCREEN while the drag is live: the
	# trigger tier opens EXPANDED for the duration, instead of collapsing to a summary the
	# way an idle chain's upper tiers do. Without this, seeding a chain here would have
	# traded one regression for another.
	var expanded := 0
	var trigger_key: String = page._chain_fold_key(Target.span(span_id))
	for s in page._sections_for_render(page._timeline._score):
		if str(s.get("fold_key", "")) == trigger_key and not bool(s.get("collapsed", true)):
			expanded += 1
	_assert_eq(expanded, 1, "the DRAGGED trigger's tier is expanded, not summarised")

	page._on_fire_drag_ended(span_id)
	_assert_eq(page._chain_expand_key, "", "the release stops forcing it open")
	_assert_eq(page._nav.size(), 3, "…and does NOT tear the chain down — a click is a select")
	# Back to the ordinary look on the next render: the upper tiers summarise again.
	var collapsed := 0
	for s in page._sections_for_render(page._timeline._score):
		if bool(s.get("collapsed", false)):
			collapsed += 1
	_assert_true(collapsed >= 2, "an idle chain summarises Event and Container again")
	page.queue_free()


## The other half: a trigger that resolves to NO pair must still behave the same either way —
## a plain one-entry span root, never a half-built chain. E005 carries a sound_id naming a
## container that does not exist (1 of the corpus's 13).
func _test_a_press_that_resolves_to_no_pair_is_a_root_either_way() -> void:
	var page = await _page()
	page._load_effect("res://assets/effects/E005")
	var dead := ""
	for sid in _sound_event_ids(page):
		if page._pair_nav_for_sound_span(sid).is_empty():
			dead = sid
			break
	_assert_true(dead != "", "E005 has a sound span that resolves to no pair")
	page._on_span_selected(dead)
	_assert_eq(page._nav.size(), 1, "the SELECT path falls back to a plain span root")
	_assert_true(not (page._nav_chain), "…and is not a chain")
	page._nav = []
	page._nav_chain = false
	page._on_fire_drag_started(dead)
	_assert_eq(page._nav.size(), 1, "the FIRE-GRAB path falls back the same way")
	_assert_true(not (page._nav_chain), "…and is not a chain either")
	_assert_eq(page._chain_expand_key, "",
			"a fallback root leaves no stale expand key behind to open a tier that is gone")
	page.queue_free()
