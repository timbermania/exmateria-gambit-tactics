extends Node
# test-kind: logic
# seeded-break: set both branches of FormationScene.resolve_body_render's returned dict to ok:false; the 'every seeded unit resolves OK render inputs' invariant reds (all units not-ok)

## TDD guard for the formation all-templates RENDER PATH (ADR-0081, seam 4).
##
## `_build_cell_body` warns and early-returns when a unit has "no sprite" or "no animation
## set" — the failure modes that would leave a blank cell. This guard proves the whole
## seeded roster (every body-bearing template) resolves clean render inputs, so mounting it
## produces ZERO `[Formation]` warnings. It verifies the invariant AS DATA (the pure
## `resolve_body_render` seam over the whole variant roster), rather than scraping stderr —
## the same fact, deterministically. A separate headful run of the standalone scene confirms
## the real mount agrees (see the ADR / verify step).
##
## Render inputs come from the variant's dialect: a folder-routed unit (unique / appearance-
## type) reads `animation.seq/shp` from its `template.json`, so the sheet reachable by no job
## still animates (this is what fixes uniques rendering as their JOB sprite — they carry
## their real sheet + seq now); a job-routed monster variant reads its sprite's seq/shp.
##
## Run: <GODOT> --path . --quit-after 8 res://tests/FormationAllTemplatesMountTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const AnimationDatabase = ExMateriaSpriteRig.AnimationDatabase

const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const AllTemplatesSeeder = ExMateriaCatalogue.AllTemplatesSeeder

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	var roster: Array = AllTemplatesSeeder.build_roster()
	_assert_true(roster.size() > 100, "seeded roster is the full template set (%d)" % roster.size())

	var no_anim := 0
	var no_body := 0
	var not_ok := 0
	for c in roster:
		var r: Dictionary = FormationScene.resolve_body_render(c)
		if not r.get("ok", false):
			not_ok += 1
			if not_ok <= 5:
				print("  [detail] not ok: slug=%s r=%s" % [c.slug, r])
			continue
		# The animation set the mount will build must be non-empty (else "no animation set").
		var aset = AnimationDatabase.get_set(r.get("seq_type", ""), r.get("shp_type", ""))
		if aset == null or aset.type1_seq.is_empty():
			no_anim += 1
			if no_anim <= 5:
				print("  [detail] empty anim set: slug=%s seq=%s shp=%s" %
					[c.slug, r.get("seq_type"), r.get("shp_type")])
		# A body sheet must be loadable — the resolved folder's body.tga, or the flat fallback.
		var folder: String = r.get("template_folder", "")
		var flat: String = r.get("flat_texture_path", "")
		var has_body := (not folder.is_empty() and ResourceLoader.exists(folder + "body.tga")) \
			or (not flat.is_empty() and ResourceLoader.exists(flat))
		if not has_body:
			no_body += 1
			if no_body <= 5:
				print("  [detail] no body sheet: slug=%s folder=%s flat=%s" % [c.slug, folder, flat])

	_assert_eq(not_ok, 0, "every seeded unit resolves OK render inputs (no 'no sprite')")
	_assert_eq(no_anim, 0, "every seeded unit builds a non-empty animation set")
	_assert_eq(no_body, 0, "every seeded unit has a loadable body sheet")

	print("\n=== FormationAllTemplatesMountTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FormationAllTemplatesMountTest")
		get_tree().quit(1)
	else:
		print("[PASS] FormationAllTemplatesMountTest")
		get_tree().quit(0)


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
