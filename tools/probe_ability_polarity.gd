extends SceneTree
## Emit `ability_id \t name \t family \t is_ally_side` for every skillset-reachable
## ability, so the ROM's `ai_target_allies`/`ai_target_enemies` can be cross-tabbed
## against `AbilityFamily` (ADR-0278 / issue #1227) OFFLINE.
##
## The family is read from the REAL `AbilityFamily.of_view` rather than a Python
## re-implementation: an arm against a transcription only tests the transcription.
##
##   godot --path . --script tools/probe_ability_polarity.gd

const AbilityDatabase = preload("res://addons/exmateria_almanac/abilities/AbilityDatabase.gd")
const AbilityFamily = preload("res://addons/exmateria_almanac/abilities/AbilityFamily.gd")


func _init() -> void:
	# The same derivation `GambitEncoderTest._reachable_ability_ids` uses.
	var seen: Dictionary = {}
	var rows: Array[String] = []
	for sid in AbilityDatabase.SKILL_SETS.keys():
		for id in AbilityDatabase.get_skill_set_actions(int(sid)):
			var aid := int(id)
			if seen.has(aid):
				continue
			seen[aid] = true
			var v := AbilityDatabase.get_ability_view(aid)
			if v.is_empty() or v.name.is_empty():
				continue
			var fam := AbilityFamily.of_view(v)
			var ally := "-" if fam == AbilityFamily.UNKNOWN else str(int(AbilityFamily.is_ally_side(fam)))
			rows.append("%d\t%s\t%s\t%s" % [aid, v.name, fam, ally])
	print("POLARITY_ROWS\t%d" % rows.size())
	for r in rows:
		print("ROW\t%s" % r)
	print("POLARITY_DONE")
	quit()
