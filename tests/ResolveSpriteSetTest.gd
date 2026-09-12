extends Node
# test-kind: logic
# seeded-break: ScenarioPlayerScene._resolve_sprite_set lets the monster flag also reroute < 0x80 slots through the job table — the confirmed ENTD records 402/474/475 regression class (a flag-gated resolver); '0x00 + monster=true stays 0x00 (not rerouted to job)' reds (got=150 want=0 — job 0x96's SPR); the 0x82/0x80/0x81 marker cases, the named-unit passthroughs, the gender-fallback and unknown-job-keeps-marker cases stay green
## Regression test for ScenarioPlayerScene._resolve_sprite_set.
##
## Pins the ENTD `sprite_set` -> SPR resolution rule. Spec + rationale:
## research/key_documents/SPRITE_SET_RESOLUTION.md. The discriminator is the
## `sprite_set` VALUE (< 0x80 = named/direct index; 0x80/0x81/0x82 = the
## Generic-Male/Generic-Female/Monster markers resolved from job) — NOT the
## `flags1_decoded.monster` bit, which is unreliable for monsters in real ENTD.
##
## `_resolve_sprite_set` is a static pure function, so we call it directly on
## the script with no scene instance.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/ResolveSpriteSetTest.tscn

const ScenarioPlayerScript := preload("res://src/scenarios/ScenarioPlayerScene.gd")

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	# uid, sprite_set, job, flags1{monster,female}, expected_spr, name
	var cases := [
		# Scenario-6 chocobo: 0x82 marker + Chocobo job -> SPR 0x86 (not raw 0x82).
		[0x82, 0x5E, {"monster": true, "female": false}, 0x86,
			"0x82 monster job 0x5E -> chocobo SPR 0x86"],
		# CONFIRMED regression (ENTD records 297/425): a 0x82 slot whose monster
		# bit is CLEAR (and female SET) must STILL resolve via job, because the
		# rule keys on the sprite_set value, not the flag. A flag-gated resolver
		# leaked these through as raw 0x82 = "Male Bard".
		[0x82, 0x5E, {"monster": false, "female": true}, 0x86,
			"0x82 with monster=false still -> chocobo SPR 0x86"],
		# Generic Male Knight: 0x80 + job 0x4C -> Male Knight SPR 0x64.
		[0x80, 0x4C, {"monster": false, "female": false}, 0x64,
			"0x80 male job 0x4C -> Male Knight SPR 0x64"],
		# Generic Female Knight: 0x81 + job 0x4C -> Female Knight SPR 0x65.
		[0x81, 0x4C, {"monster": false, "female": true}, 0x65,
			"0x81 female job 0x4C -> Female Knight SPR 0x65"],
		# Named unit (sprite_set < 0x80) returns the byte unchanged; job ignored.
		[0x34, 0x4C, {"monster": false, "female": false}, 0x34,
			"named 0x34 passthrough (job ignored)"],
		# Ovelia trap: named unit (0x0C) with a monster-range job (0x5E) stays a
		# direct index — the value is < 0x80, so the job never applies.
		[0x0C, 0x5E, {"monster": false, "female": false}, 0x0C,
			"named 0x0C + job 0x5E stays 0x0C"],
		# CONFIRMED regression (ENTD records 402/474/475): a < 0x80 slot with the
		# monster bit SET must NOT be rerouted through the job table. sprite_set
		# 0x00 "(None)" stays 0x00, not the job's SPR 0x96.
		[0x00, 0x96, {"monster": true, "female": false}, 0x00,
			"0x00 + monster=true stays 0x00 (not rerouted to job)"],
	]
	for c in cases:
		_check(c[0], c[1], c[2], c[3], c[4])

	# Gender falls back to the 0x81 marker when flags1 lacks a `female` key.
	_check_slot({"sprite_set": 0x81, "job": 0x4C, "flags1_decoded": {}}, 0x65,
		"0x81 with empty flags1 falls back to female SPR 0x65")
	# Marker slot whose job has no sprite keeps the marker rather than blanking.
	_check(0x82, 0xFF, {"monster": true, "female": false}, 0x82,
		"0x82 + unknown job 0xFF keeps marker 0x82")

	print("\n=== ResolveSpriteSetTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] ResolveSpriteSetTest")
		get_tree().quit(1)
	else:
		print("[PASS] ResolveSpriteSetTest")
		get_tree().quit(0)


func _check(sprite_set: int, job: int, flags1: Dictionary, want: int, name: String) -> void:
	_check_slot({"sprite_set": sprite_set, "job": job, "flags1_decoded": flags1},
		want, name)


func _check_slot(slot: Dictionary, want: int, name: String) -> void:
	var got: int = ScenarioPlayerScript._resolve_sprite_set(slot)
	if got == want:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s: got=%s want=%s" % [name, str(got), str(want)])
