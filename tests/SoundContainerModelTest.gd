extends Node
## TDD guard for SoundContainerModel — the ADR-0085 TIER-2 "sound-selection logic"
## projection. A SoundContainer (mode + id_a/id_b/id_c + a stateful per-container
## fire counter) is what a timeline sound_id (container_idx = sound_id-2) resolves
## THROUGH before it reaches a FEDS pair. This model makes that shared, effect-global
## object LEGIBLE: the mode name, the DISTINCT set of concrete ids the container can
## fire across successive fires (parity/cycle vary per fire), each id's FEDS pair, and
## which triggers reference it ("used by N").
##
## The load-bearing property is that `emitted_ids` is enumerated by DRIVING the real
## EffectSoundResolver forward (fresh resolver, counts 0..3, collect distinct) — the
## resolver stays the single source of the 5-mode truth; the model only observes it.
## Pure logic: synthetic container docs / effect_sound, no scene / no SPU.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/SoundContainerModelTest.tscn

const Model = preload("res://src/effects/studio/SoundContainerModel.gd")
const FedsBankClass = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")
const InspectionTarget = preload("res://src/effects/studio/InspectionTarget.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_emitted_ids_direct_a_is_singleton()
	_test_emitted_ids_parity_a_alternates_a_b()
	_test_emitted_ids_direct_b_is_a_then_b()
	_test_emitted_ids_parity_b_covers_a_b_c()
	_test_emitted_ids_triple_cycle_covers_a_b_c()
	_test_emitted_ids_representative_is_first_fire()
	_test_mode_name_labels_each_mode()
	_test_mode_author_label_describes_the_sequence()
	_test_used_slots_names_which_ids_each_mode_reads()
	_test_fire_sequence_is_the_ordered_repeat()
	_test_sequence_for_mode_previews_without_mutating()
	_test_pattern_for_mode_names_slots()
	_test_mode_choices_cover_every_mode_with_what_if_sequences()
	_test_container_view_carries_legibility_fields()
	_test_container_view_projects_mode_ids_and_pairs()
	_test_used_by_counts_referencing_triggers()
	_test_used_by_and_provenance_honor_the_firing_window()
	_test_container_provenance_links_referencing_triggers()
	_test_container_views_covers_every_container()

	print("\n=== SoundContainerModelTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] SoundContainerModelTest")
		get_tree().quit(1)
	else:
		print("[PASS] SoundContainerModelTest")
		get_tree().quit(0)


# A one-container doc at index 0. sound_id that references it is index+2 = 2.
func _doc(mode: int, a: int, b: int, c: int) -> Dictionary:
	return {"containers": [{"mode": mode, "id_a": a, "id_b": b, "id_c": c, "index": 0}]}


## DIRECT_A (mode 0) always fires id_a — the emitted set is just {a}. Oracle from the
## resolver docstring: mode 0 → id_a for every count.
func _test_emitted_ids_direct_a_is_singleton() -> void:
	_assert_eq(Model.emitted_ids(_doc(0, 5, 9, 13), 0), [5],
		"DIRECT_A emits only id_a")


## PARITY_A (mode 1) alternates id_a (even fire) / id_b (odd fire) — distinct {a, b},
## in first-seen order a then b.
func _test_emitted_ids_parity_a_alternates_a_b() -> void:
	_assert_eq(Model.emitted_ids(_doc(1, 5, 9, 13), 0), [5, 9],
		"PARITY_A emits id_a then id_b")


## DIRECT_B (mode 2) fires id_a on the first fire, id_b thereafter — distinct {a, b}.
func _test_emitted_ids_direct_b_is_a_then_b() -> void:
	_assert_eq(Model.emitted_ids(_doc(2, 5, 9, 13), 0), [5, 9],
		"DIRECT_B emits id_a first then id_b")


## PARITY_B (mode 3): first fire id_a, then alternates id_c (odd) / id_b (even) — the
## three-fire distinct set is {a, c, b} in first-seen order (count 0→a, 1→c, 2→b).
func _test_emitted_ids_parity_b_covers_a_b_c() -> void:
	_assert_eq(Model.emitted_ids(_doc(3, 5, 9, 13), 0), [5, 13, 9],
		"PARITY_B emits id_a, id_c, id_b across its first three fires")


## TRIPLE_CYCLE (mode 4) cycles id_a/id_b/id_c — distinct {a, b, c} in order.
func _test_emitted_ids_triple_cycle_covers_a_b_c() -> void:
	_assert_eq(Model.emitted_ids(_doc(4, 5, 9, 13), 0), [5, 9, 13],
		"TRIPLE_CYCLE emits id_a, id_b, id_c")


## The FIRST element of emitted_ids is the count-0 representative — the honest
## first-fire id the ghost bar already draws (SoundGhostProjector.resolve_pair_idx).
func _test_emitted_ids_representative_is_first_fire() -> void:
	_assert_eq(Model.emitted_ids(_doc(4, 5, 9, 13), 0)[0], 5,
		"the representative (first) emitted id is the count-0 fire")


## The mode is labelled with the resolver's own vocabulary (docstring §modes). 5+ is
## the pass-through DEFAULT. Oracle = the resolver's documented mode names.
func _test_mode_name_labels_each_mode() -> void:
	_assert_eq(Model.mode_name(0), "DIRECT_A", "mode 0")
	_assert_eq(Model.mode_name(1), "PARITY_A", "mode 1")
	_assert_eq(Model.mode_name(2), "DIRECT_B", "mode 2")
	_assert_eq(Model.mode_name(3), "PARITY_B", "mode 3")
	_assert_eq(Model.mode_name(4), "TRIPLE_CYCLE", "mode 4")
	_assert_eq(Model.mode_name(5), "DEFAULT", "mode 5+ passes the timeline id through")
	_assert_eq(Model.mode_name(9), "DEFAULT", "any mode >=5 is DEFAULT")


## The AUTHOR-facing label describes what the container plays across successive fires —
## the RE mode_name (DIRECT_A/…) says nothing about the audible result. Oracle = the
## fire table: mode 0 is always A; 1 alternates A/B; 2 is A once then B; 3 is A once then
## alternates B/C; 4 cycles A/B/C. Mode 5+ passes the timeline id straight through.
func _test_mode_author_label_describes_the_sequence() -> void:
	_assert_eq(Model.mode_author_label(0), "Always Sound 1", "mode 0 author label")
	_assert_eq(Model.mode_author_label(1), "Alternate 1 / 2", "mode 1 author label")
	_assert_eq(Model.mode_author_label(2), "Sound 1 once, then 2", "mode 2 author label")
	_assert_eq(Model.mode_author_label(3), "1 once, then alternate 3 / 2", "mode 3 author label")
	_assert_eq(Model.mode_author_label(4), "Cycle 1 → 2 → 3", "mode 4 author label")
	_assert_eq(Model.mode_author_label(5), "Pass sound id through", "mode 5+ author label")


## Which of the three id slots a mode ever READS — so the inspector can flag the others
## as dead bytes for this mode (DIRECT_A never touches B or C). Oracle from the fire
## table: 0→{a}, 1→{a,b}, 2→{a,b}, 3→{a,b,c}, 4→{a,b,c}. Order is a,b,c.
func _test_used_slots_names_which_ids_each_mode_reads() -> void:
	_assert_eq(Model.used_slots(0), ["a"], "DIRECT_A reads only id_a")
	_assert_eq(Model.used_slots(1), ["a", "b"], "PARITY_A reads id_a and id_b")
	_assert_eq(Model.used_slots(2), ["a", "b"], "DIRECT_B reads id_a and id_b")
	_assert_eq(Model.used_slots(3), ["a", "b", "c"], "PARITY_B reads all three")
	_assert_eq(Model.used_slots(4), ["a", "b", "c"], "TRIPLE_CYCLE reads all three")


## The ORDERED fire sequence (NOT the distinct set) — what plays on fire 0,1,2,… so an
## author sees the repeat. Drives a fresh resolver forward n fires. Oracle by hand:
## PARITY_A [5,9] → 5,9,5,9,5,9; TRIPLE_CYCLE [5,9,13] → 5,9,13,5,9,13.
func _test_fire_sequence_is_the_ordered_repeat() -> void:
	_assert_eq(Model.fire_sequence(_doc(1, 5, 9, 13), 0, 6), [5, 9, 5, 9, 5, 9],
		"PARITY_A repeats a,b")
	_assert_eq(Model.fire_sequence(_doc(4, 5, 9, 13), 0, 6), [5, 9, 13, 5, 9, 13],
		"TRIPLE_CYCLE repeats a,b,c")
	_assert_eq(Model.fire_sequence(_doc(0, 5, 9, 13), 0, 4), [5, 5, 5, 5],
		"DIRECT_A repeats a")


## `sequence_for_mode` previews what a container WOULD fire under another mode, off its
## CURRENT ids, without touching the doc — the read-out behind the mode radio rows.
## Oracles worked by hand from the resolver fire table. A pass-through mode (5+) emits
## the referencing timeline id (index+2) unchanged.
func _test_sequence_for_mode_previews_without_mutating() -> void:
	var doc := _doc(0, 5, 9, 13)
	_assert_eq(Model.sequence_for_mode(doc, 0, 1, 6), [5, 9, 5, 9, 5, 9],
		"what-if PARITY_A alternates a/b off the current ids")
	_assert_eq(Model.sequence_for_mode(doc, 0, 4, 6), [5, 9, 13, 5, 9, 13],
		"what-if TRIPLE_CYCLE cycles a/b/c")
	_assert_eq(Model.sequence_for_mode(doc, 0, 7, 3), [2, 2, 2],
		"a what-if pass-through emits the referencing timeline id (index+2)")
	_assert_eq(int(doc["containers"][0]["mode"]), 0, "previewing never mutates the doc")


## The slot-number step patterns behind the radio rows: 1=id_a, 2=id_b, 3=id_c, straight
## off the resolver fire table (note mode 3 alternates STARTING on slot 3). Pass-through
## modes (5+) play no slot → empty pattern.
func _test_pattern_for_mode_names_slots() -> void:
	_assert_eq(Model.pattern_for_mode(0, 6), [1, 1, 1, 1, 1, 1], "mode 0 pattern")
	_assert_eq(Model.pattern_for_mode(1, 6), [1, 2, 1, 2, 1, 2], "mode 1 pattern")
	_assert_eq(Model.pattern_for_mode(2, 6), [1, 2, 2, 2, 2, 2], "mode 2 pattern")
	_assert_eq(Model.pattern_for_mode(3, 6), [1, 3, 2, 3, 2, 3], "mode 3 pattern (alternation starts on 3)")
	_assert_eq(Model.pattern_for_mode(4, 6), [1, 2, 3, 1, 2, 3], "mode 4 pattern")
	_assert_eq(Model.pattern_for_mode(7, 6), [], "a pass-through mode plays no slot")


## `mode_choices` lists EVERY authorable mode (0-4) with its author label, what-if
## sequence, and slot-number step pattern — the radio rows. A container currently on a
## 5+ pass-through mode keeps its real byte representable as an extra choice.
func _test_mode_choices_cover_every_mode_with_what_if_sequences() -> void:
	var choices: Array = Model.mode_choices(_doc(1, 1, 2, 0), 0)
	_assert_eq(choices.size(), 5, "the 5 authorable modes are all present")
	_assert_eq(str(choices[1].get("label", "")), "Alternate 1 / 2", "each choice carries its author label")
	_assert_eq(choices[1].get("seq", []), [1, 2, 1, 2, 1, 2], "each choice carries its what-if sequence")
	_assert_eq(choices[4].get("seq", []), [1, 2, 0, 1, 2, 0], "the cycle preview reads the current ids")
	_assert_eq(choices[4].get("pattern", []), [1, 2, 3, 1, 2, 3], "each choice carries its step pattern")
	var pass_through: Array = Model.mode_choices(_doc(7, 1, 2, 0), 0)
	_assert_eq(pass_through.size(), 6, "a 5+ current mode appends its own choice")
	_assert_eq(int(pass_through[5].get("value", -1)), 7, "the appended choice carries the raw byte")


## The view carries the legibility fields the projector renders WITHOUT re-deriving mode
## truth: the author label, the used slots, the ordered fire sequence, the mode radio
## choices, and the bank extent the slot pickers enumerate. PARITY_A [1,2,0] is the
## real-data shape (E001): reads a,b; C is dead; sequence 1,2,1,2,…
func _test_container_view_carries_legibility_fields() -> void:
	var view: Dictionary = Model.container_view(_doc(1, 1, 2, 0), _bank(10), {}, 0)
	_assert_eq(view.get("mode_author_label", ""), "Alternate 1 / 2", "view carries the author label")
	_assert_eq(view.get("used_slots", []), ["a", "b"], "view carries the used slots")
	_assert_eq(view.get("fire_sequence", []), [1, 2, 1, 2, 1, 2], "view carries the ordered fire sequence")
	_assert_eq((view.get("mode_choices", []) as Array).size(), 5, "view carries the mode radio choices")
	_assert_eq(int(view.get("bank_size", -1)), 10, "view carries the bank extent for the slot pickers")


# Two channels of the same phase: ch0 fires sid 2 (container 0), a skip, sid 3
# (container 1); ch1 fires sid 2 (container 0). max_keyframe covers every real kf.
func _used_by_sound() -> Dictionary:
	return {"for_each": [
		{"channel_index": 0, "max_keyframe": 3, "keyframes": [
			{"duration_frames": 4, "sound_id": 2},
			{"duration_frames": 4, "sound_id": 0},
			{"duration_frames": 4, "sound_id": 3}]},
		{"channel_index": 1, "max_keyframe": 1, "keyframes": [
			{"duration_frames": 4, "sound_id": 2}]},
	]}


# A FEDS bank with a known pair count (no track data needed — the view only reports a
# pair's index + whether it is in range).
func _bank(num_pairs: int):
	var fb = FedsBankClass.new()
	fb.pair_count_plus1 = num_pairs + 1
	return fb


## The composite view a projector renders: the container's index, mode + mode_name, its
## distinct emitted ids, and each id's FEDS pair (pair_idx = resolved-1) with in-range
## validity against the bank. TRIPLE_CYCLE ids 5/9/13 → pairs 4/8/12; with 10 pairs the
## last (12) is out of range. Oracle worked by hand from the resolve chain.
func _test_container_view_projects_mode_ids_and_pairs() -> void:
	var view: Dictionary = Model.container_view(_doc(4, 5, 9, 13), _bank(10), {}, 0)
	_assert_eq(view.get("index", -1), 0, "view carries its index")
	_assert_eq(view.get("mode", -1), 4, "view carries the raw mode")
	_assert_eq(view.get("mode_name", ""), "TRIPLE_CYCLE", "view carries the mode name")
	_assert_eq(view.get("emitted_ids", []), [5, 9, 13], "view carries the emitted set")
	var pairs: Array = view.get("pairs", [])
	_assert_eq(pairs.size(), 3, "one pair entry per emitted id")
	_assert_eq(pairs[0], {"id": 5, "pair_idx": 4, "valid": true}, "id 5 → pair 4 (in range)")
	_assert_eq(pairs[1], {"id": 9, "pair_idx": 8, "valid": true}, "id 9 → pair 8 (in range)")
	_assert_eq(pairs[2], {"id": 13, "pair_idx": 12, "valid": false}, "id 13 → pair 12 (out of range)")


## Because a container is SHARED, the view reports how many timeline triggers reference
## it (sound_id-2 == index) across every phase/channel — the ADR's "used by N" honesty.
func _test_used_by_counts_referencing_triggers() -> void:
	_assert_eq(Model.used_by(_used_by_sound(), 0), 2, "two triggers (sid 2) reference container 0")
	_assert_eq(Model.used_by(_used_by_sound(), 1), 1, "one trigger (sid 3) references container 1")
	_assert_eq(Model.used_by(_used_by_sound(), 2), 0, "no trigger references container 2")


## Only triggers WITHIN the firing window count/link: a keyframe at or past
## `max_keyframe` is a terminator, not a fired trigger (mirrors _sound_spans). Here a
## 4th kf (sid 2) sits past ch0's max_keyframe=3, so it must NOT inflate used_by(0).
func _test_used_by_and_provenance_honor_the_firing_window() -> void:
	var sound := {"for_each": [
		{"channel_index": 0, "max_keyframe": 3, "keyframes": [
			{"duration_frames": 4, "sound_id": 2},
			{"duration_frames": 4, "sound_id": 3},
			{"duration_frames": 4, "sound_id": 2},
			{"duration_frames": 4, "sound_id": 2}]},   # index 3 == max_keyframe → terminator
	]}
	_assert_eq(Model.used_by(sound, 0), 2, "the out-of-window 4th trigger does not count")
	_assert_eq(Model.container_provenance(sound, 0).size(), 2,
		"provenance links only the two in-window triggers")


## Provenance = clickable back-links (ADR-0073 reverse-nav) to every trigger span that
## references this SHARED container, so an author sees the blast radius. The link target
## is the trigger's own span (id "sound:<phase>:<ci>#<i>"). Oracle: the two sid-2
## triggers in _used_by_sound reference container 0.
func _test_container_provenance_links_referencing_triggers() -> void:
	var rows: Array = Model.container_provenance(_used_by_sound(), 0)
	_assert_eq(rows.size(), 2, "two back-links for container 0's two triggers")
	var targets: Array = []
	for row in rows:
		targets.append(row.get("link", {}).get("target", {}))
	_assert_true(targets.has(InspectionTarget.span("sound:for_each:0#0")),
		"one link targets the ch0 kf0 trigger span")
	_assert_true(targets.has(InspectionTarget.span("sound:for_each:1#0")),
		"one link targets the ch1 kf0 trigger span")


## The exhaustive list the score/browser consume: one view per container in the doc, in
## index order, each carrying its own index — so an orphan container (referenced by no
## trigger) is still present and reachable.
func _test_container_views_covers_every_container() -> void:
	var doc := {"containers": [
		{"mode": 0, "id_a": 3, "id_b": 0, "id_c": 0, "index": 0},
		{"mode": 4, "id_a": 5, "id_b": 6, "id_c": 7, "index": 1}]}
	var views: Array = Model.container_views(doc, _bank(10), {})
	_assert_eq(views.size(), 2, "one view per container")
	_assert_eq(views[0].get("index", -1), 0, "first view is container 0")
	_assert_eq(views[1].get("mode_name", ""), "TRIPLE_CYCLE", "second view keeps its mode")


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
