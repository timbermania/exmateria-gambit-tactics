extends Node
## Pure-logic guard (no GPU/scene): EffectScoreModel.resolve_audibility — the Effect
## Studio Solo/Mute core. Turns the per-lane (muted, soloed) sets into the derived
## silence the preview enforces:
##   - `silenced_lanes`: the DAW rule — a lane is silenced if it's MUTED, or if any
##     solo is active and it is NOT soloed (solo composes with mute: the soloed lane
##     is audible unless separately muted; everything un-soloed goes quiet).
##   - `disabled_emitters`: the particle projection — every emitter_index a SILENCED
##     particle lane spawns (decision: mute a lane ⇒ drop every emitter it spawns,
##     even one it shares with an audible lane).
##
## Runs on a synthetic score (no effect load) so it tests the composition rule, not a
## particular effect's data.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectAudibilityTest.tscn

const Model = preload("res://src/effects/studio/EffectScoreModel.gd")

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _ready() -> void:
	_test_nothing_muted_nothing_silenced()
	_test_mute_particle_lane_disables_its_emitters()
	_test_mute_non_particle_lane_has_no_emitters()
	_test_solo_silences_every_other_lane()
	_test_solo_composes_with_mute()
	_test_mute_shared_emitter_still_disabled()
	_test_mute_one_color_lane_excludes_only_that_lane()
	_test_solo_excludes_every_folded_lane()
	_test_mute_cascades_to_pure_child_emitter()
	_test_mute_skips_child_with_its_own_lane()
	_test_camera_is_display_only()
	_test_mute_sound_lane_is_phase_scoped()
	_test_solo_sound_lane_does_not_mute_itself_via_cross_phase_twin()

	if _failed:
		print("[FAIL] EffectAudibility test")
	else:
		print("[PASS] EffectAudibility: Solo/Mute resolves to the right silence")
	get_tree().quit()


## A synthetic score: two particle lanes (one sharing emitter 5), a single screen lane,
## and TWO palette lanes (so the "disable a folded subsystem only when ALL its lanes are
## silenced" rule is exercised). Emitter 3 spawns a PURE child 7 (no lane of its own) so
## the child-closure cascade is exercisable.
func _score() -> Dictionary:
	return {
		"max_frame": 100,
		"lanes": [
			{"id": "particle:phase1:0", "kind": "particle",
				"spans": [{"emitter_index": 3}, {"emitter_index": 5}]},
			{"id": "particle:phase1:1", "kind": "particle",
				"spans": [{"emitter_index": 5}]},
			{"id": "screen:phase1", "kind": "screen", "spans": [{}]},
			{"id": "palette:phase1:caster", "kind": "palette", "spans": [{}]},
			{"id": "palette:phase1:target", "kind": "palette", "spans": [{}]},
			{"id": "camera:phase1:angle", "kind": "camera", "spans": [{}]},
		],
		"emitter_children": {3: [7]},
	}


## A score whose channel index 0 exists in ALL THREE sound phases — the real shape (E317:
## phase1/phase2/for_each each carry channels 0/1/2). Muting/soloing ONE of these lanes must
## not collide with its same-index twins in the other phases.
func _sound_score() -> Dictionary:
	return {
		"max_frame": 100,
		"lanes": [
			{"id": "sound:phase1:0", "kind": "sound", "channel_index": 0, "phase": "phase1", "spans": [{}]},
			{"id": "sound:phase2:0", "kind": "sound", "channel_index": 0, "phase": "phase2", "spans": [{}]},
			{"id": "sound:for_each:0", "kind": "sound", "channel_index": 0, "phase": "for_each", "spans": [{}]},
		],
	}


## Muting ONE sound lane must silence ONLY that lane — not the same channel index in the
## other phases. (Bug: muted_sound is keyed by bare channel_index, so muting for_each:0
## also silences phase1:0 / phase2:0.)
func _test_mute_sound_lane_is_phase_scoped() -> void:
	var res := Model.resolve_audibility(_sound_score(),
		{"sound:for_each:0": true}, {})
	_check(res["silenced_lanes"].has("sound:for_each:0"), "the muted sound lane is silenced")
	_check(not res["silenced_lanes"].has("sound:phase1:0"),
		"muting for_each:0 must NOT silence phase1:0 (a different lane)")
	# The gate the addon actually enforces must silence for_each:0 but leave phase1/phase2 ch0
	# audible — i.e. it can't be a bare channel-index set (which can't tell the phases apart).
	_check(not _sound_gate_silences(res, "phase1", 0),
		"the sound gate must leave phase1 ch0 audible when only for_each:0 is muted")
	_check(_sound_gate_silences(res, "for_each", 0),
		"the sound gate must silence for_each ch0")


## Soloing a sound lane must keep IT audible. (Bug: soloing for_each:0 silences phase1:0 /
## phase2:0 — same channel index — which set muted_sound[0], muting the soloed lane too.)
func _test_solo_sound_lane_does_not_mute_itself_via_cross_phase_twin() -> void:
	var res := Model.resolve_audibility(_sound_score(),
		{}, {"sound:for_each:0": true})
	_check(not res["silenced_lanes"].has("sound:for_each:0"), "the soloed lane is audible")
	_check(res["silenced_lanes"].has("sound:phase1:0"), "an un-soloed sibling is silenced")
	_check(not _sound_gate_silences(res, "for_each", 0),
		"the sound gate must NOT silence the soloed for_each ch0 via its cross-phase twins")


## Whether the sound gate the addon enforces (from resolve_audibility's sound filter) would
## drop a fire on (phase, channel_index). Phase-aware by construction — a bare channel-index
## set cannot answer this, which is exactly the bug under test.
func _sound_gate_silences(res: Dictionary, phase: String, ci: int) -> bool:
	var ms = res.get("muted_sound", {})
	return ms.has("%s:%d" % [phase, ci])


## Tracer: with nothing muted and nothing soloed, nothing is silenced.
func _test_nothing_muted_nothing_silenced() -> void:
	var res := Model.resolve_audibility(_score(), {}, {})
	_check(res["silenced_lanes"].is_empty(), "no mute/solo → no silenced lanes, got %s" % res["silenced_lanes"])
	_check(res["disabled_emitters"].is_empty(), "no mute/solo → no disabled emitters, got %s" % res["disabled_emitters"])


## Mute one particle lane → it is silenced and every emitter it spawns is disabled.
func _test_mute_particle_lane_disables_its_emitters() -> void:
	var res := Model.resolve_audibility(_score(), {"particle:phase1:0": true}, {})
	_check(res["silenced_lanes"].has("particle:phase1:0"), "muted lane is silenced")
	_check(res["silenced_lanes"].size() == 1, "only the muted lane is silenced, got %s" % res["silenced_lanes"])
	_check(res["disabled_emitters"].has(3) and res["disabled_emitters"].has(5),
		"muted particle lane's emitters (3,5) disabled, got %s" % res["disabled_emitters"])


## Mute a non-particle (screen) lane → silenced, contributes no emitter, and its phase
## lands in the screen exclusion filter (per-lane, not a whole-subsystem gate).
func _test_mute_non_particle_lane_has_no_emitters() -> void:
	var res := Model.resolve_audibility(_score(), {"screen:phase1": true}, {})
	_check(res["silenced_lanes"].has("screen:phase1"), "muted screen lane is silenced")
	_check(res["disabled_emitters"].is_empty(), "screen lane contributes no emitters, got %s" % res["disabled_emitters"])
	_check(res["muted_screen"].has("phase1"), "muting a screen lane excludes its phase, got %s" % res["muted_screen"])


## PER-LANE: muting ONE of two palette lanes excludes ONLY that lane's (phase/channel),
## leaving the other palette lane audible — no whole-subsystem gate, so a single M works.
func _test_mute_one_color_lane_excludes_only_that_lane() -> void:
	var res := Model.resolve_audibility(_score(), {"palette:phase1:caster": true}, {})
	_check(res["muted_palette"].has("phase1/caster"), "the muted palette lane is excluded")
	_check(not res["muted_palette"].has("phase1/target"), "the other palette lane stays audible")
	_check(res["muted_palette"].size() == 1, "only the one muted palette lane is excluded, got %s" % res["muted_palette"])


## Soloing a single (particle) lane excludes EVERY folded lane — none is soloed, so all
## their (phase[/channel]) keys land in the exclusion filters.
func _test_solo_excludes_every_folded_lane() -> void:
	var res := Model.resolve_audibility(_score(), {}, {"particle:phase1:0": true})
	_check(res["muted_screen"].has("phase1"), "solo excludes the screen lane")
	_check(res["muted_palette"].has("phase1/caster") and res["muted_palette"].has("phase1/target"),
		"solo excludes every palette lane, got %s" % res["muted_palette"])


## Camera is DISPLAY-ONLY (framing, not content): it has no S/M and is never silenced, so
## even soloing another lane leaves the camera lane playing (not in silenced_lanes) and the
## result carries no camera filter.
func _test_camera_is_display_only() -> void:
	_check(not Model.has_mute_controls("camera"), "camera has no mute controls")
	var res := Model.resolve_audibility(_score(), {}, {"particle:phase1:0": true})
	_check(not res["silenced_lanes"].has("camera:phase1:angle"),
		"soloing a particle does NOT silence the camera lane")
	_check(not res.has("muted_camera"), "the result carries no camera filter")


## Muting a lane cascades to the PURE-child closure of its emitters: lane :0 spawns
## emitter 3, which spawns pure child 7 (no lane) — muting :0 must disable {3, 5, 7} so
## the child particles that keep spawning are hidden too (the reported E001 leak).
func _test_mute_cascades_to_pure_child_emitter() -> void:
	var res := Model.resolve_audibility(_score(), {"particle:phase1:0": true}, {})
	_check(res["disabled_emitters"].has(3) and res["disabled_emitters"].has(5),
		"the lane's own emitters are disabled")
	_check(res["disabled_emitters"].has(7),
		"the pure child emitter is disabled too (cascade), got %s" % res["disabled_emitters"])


## The cascade SKIPS a child that has its own lane: muting the parent leaves an
## independently-laned child audible (governed by its own lane, not the parent's mute).
## Here lane P spawns emitter 3 → child 7, and emitter 7 ALSO has its own (un-muted)
## lane C. Muting only P must NOT disable 7.
func _test_mute_skips_child_with_its_own_lane() -> void:
	var score := {
		"max_frame": 50,
		"lanes": [
			{"id": "particle:phase1:0", "kind": "particle", "spans": [{"emitter_index": 3}]},
			{"id": "particle:phase1:1", "kind": "particle", "spans": [{"emitter_index": 7}]},
		],
		"emitter_children": {3: [7]},
	}
	var res := Model.resolve_audibility(score, {"particle:phase1:0": true}, {})
	_check(res["disabled_emitters"].has(3), "the muted parent's own emitter is disabled")
	_check(not res["disabled_emitters"].has(7),
		"a child with its own audible lane is NOT hidden by muting the parent, got %s" % res["disabled_emitters"])
	# But muting BOTH lanes disables 7 (its own lane is now silenced).
	var both := Model.resolve_audibility(score,
		{"particle:phase1:0": true, "particle:phase1:1": true}, {})
	_check(both["disabled_emitters"].has(7), "muting the child's own lane disables it")


## Solo one lane → every OTHER lane is silenced (the soloed one is not).
func _test_solo_silences_every_other_lane() -> void:
	var res := Model.resolve_audibility(_score(), {}, {"particle:phase1:0": true})
	_check(not res["silenced_lanes"].has("particle:phase1:0"), "the soloed lane is audible")
	_check(res["silenced_lanes"].has("particle:phase1:1"), "an un-soloed lane is silenced")
	_check(res["silenced_lanes"].has("screen:phase1"), "an un-soloed screen lane is silenced")
	# particle:phase1:1 (emitter 5) is silenced → 5 disabled; the soloed lane keeps 3.
	_check(res["disabled_emitters"].has(5), "un-soloed particle lane's emitter (5) disabled")
	_check(not res["disabled_emitters"].has(3), "the soloed lane's emitter (3) stays enabled, got %s" % res["disabled_emitters"])


## Solo composes with mute: muting the SOLOED lane silences it anyway.
func _test_solo_composes_with_mute() -> void:
	var res := Model.resolve_audibility(_score(),
		{"particle:phase1:0": true}, {"particle:phase1:0": true})
	_check(res["silenced_lanes"].has("particle:phase1:0"),
		"a lane that is both soloed AND muted is silenced (mute wins)")


## Shared emitter: muting a lane disables its emitter even though an audible lane
## also spawns it (mute a lane ⇒ drop every emitter it spawns).
func _test_mute_shared_emitter_still_disabled() -> void:
	# Lane :1 (emitter 5) muted; lane :0 (emitters 3,5) audible — 5 is still disabled.
	var res := Model.resolve_audibility(_score(), {"particle:phase1:1": true}, {})
	_check(res["disabled_emitters"].has(5),
		"muting a lane disables its emitter even when an audible lane shares it, got %s" % res["disabled_emitters"])
