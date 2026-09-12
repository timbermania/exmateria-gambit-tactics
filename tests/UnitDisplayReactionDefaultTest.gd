extends Node
## The rig carries a duplicated number; this proves the two sides agree (#744).
##
## `UnitDisplay.play_reaction_animation`'s default used to be
## `ReactionType.Type.TAKING_DAMAGE` — a compile-time reach from the sprite rig into
## `Battle`, and one of ADR-0215 P3a's 27 outbound system reaches. The rig never
## branches on a reaction type: it takes the int, emits it back through
## `_unit.reaction_animation_played`, and prints it. So the reach bought a default,
## and #744 writes the default out as `UnitDisplay.REACTION_TAKING_DAMAGE`.
##
## 🔴 A WRITTEN-OUT ENUM VALUE IS A SILENT DIVERGENCE WAITING FOR A RENUMBER. Nothing
## in either file can see the other. This test is the seam that can: it names BOTH and
## fails if the host reorders `ReactionType.Type`. That is the shape a contract test
## has — the addon cannot check the host, and the host is where the check belongs.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/UnitDisplayReactionDefaultTest.tscn

const UnitDisplay = ExMateriaSpriteRig.UnitDisplay

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ReactionType = ExMateriaAlmanac.ReactionType

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_the_written_out_default_equals_the_hosts_enum()
	_test_the_rig_names_no_reaction_vocabulary()

	print("\n=== UnitDisplayReactionDefaultTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UnitDisplayReactionDefaultTest")
		get_tree().quit(1)
	else:
		print("[PASS] UnitDisplayReactionDefaultTest")
		get_tree().quit(0)


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s" % msg)


## The one arm that matters. Seeded red by changing either side.
func _test_the_written_out_default_equals_the_hosts_enum() -> void:
	_check(UnitDisplay.REACTION_TAKING_DAMAGE == ReactionType.Type.TAKING_DAMAGE,
		"UnitDisplay.REACTION_TAKING_DAMAGE is %d but ReactionType.Type.TAKING_DAMAGE is %d — "
		% [UnitDisplay.REACTION_TAKING_DAMAGE, ReactionType.Type.TAKING_DAMAGE]
		+ "the host renumbered the enum and the rig's written-out copy did not follow. "
		+ "Update addons/exmateria_sprite_rig/render/UnitDisplay.gd; do NOT re-introduce "
		+ "the reach, which is what #744 removed.")


## And the reason the number is written out at all: re-introducing the reach would make
## this file's other arm pass while failing goal #5, so the ABSENCE is asserted too.
func _test_the_rig_names_no_reaction_vocabulary() -> void:
	# The PATH comes from the façade const, not a literal: a host file spelling
	# `res://addons/exmateria_sprite_rig/…` is a criterion-4 site, and this test has
	# no reason to be one when the symbol it already holds knows its own address.
	# Not a tautology — the assertion below is about the file's CONTENT, and
	# `resource_path` cannot make a `ReactionType` line disappear.
	# Typed through `Script` on purpose: the const holds the CLASS, so a bare
	# `UnitDisplay.resource_path` is a parse error (`Cannot find member`) even though a
	# GDScript is a Resource at runtime. Caught by `--import`, not by `load()`.
	var unit_display: Script = UnitDisplay
	var src := FileAccess.get_file_as_string(unit_display.resource_path)
	_check(not src.is_empty(), "could not read UnitDisplay.gd as text")
	# 🔴 THIS ARM NEEDS THE SAME STRIPPER `check_addon_portability.py` USES, NOT A
	# STRICTER ONE. It cites that guard in its own failure text, so scoring a line the
	# guard does not score makes it red on a tree with nothing wrong with it. Two
	# comment channels carry the explanation and BOTH have to be skipped: the `##`
	# doc-comments above the method, and the `"""triple-quoted"""` Args block inside
	# it, which is this repo's function-docstring convention (CLAUDE.md) and to a
	# naive line scan looks like code. Skipping only the first scored 2 lines of prose
	# as a portability breach — measured, not hypothesised: `--quit-after 900` printed
	# `names ReactionType on 2 code line(s)` while the guard itself reported zero.
	var offending := 0
	var in_docstring := false
	for line in src.split("\n"):
		var t := line.strip_edges()
		var fences := t.count("\"\"\"")
		if in_docstring:
			if fences > 0:
				in_docstring = false
			continue  # the closing line is prose too, whatever follows the fence
		if fences == 1:
			in_docstring = true
			continue
		if fences >= 2:
			continue  # a one-line """docstring""" — prose start to end
		if t.begins_with("#") or t.begins_with("##"):
			continue  # the docstrings EXPLAIN the removal and must be allowed to say the name
		if t.contains("ReactionType"):
			offending += 1
	_check(offending == 0,
		"UnitDisplay.gd names `ReactionType` on %d code line(s). It is `Battle`'s "
		% offending
		+ "`class_name`, so the addon stops parsing in a project without it (goal #5) "
		+ "and `check_addon_portability.py` arm 1 goes red. The rig does not branch on a "
		+ "reaction type — take the int and let this test hold the number.")
