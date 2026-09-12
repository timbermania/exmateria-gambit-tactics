extends Node
## Guards the unit-sprite VARIANT contract (ADR-0189).
##
## `Sprite Rig` draws every unit sprite with one compositor; a consumer that wants a
## different BLEND asks for a variant. Three entry shaders exist because `render_mode`
## must sit in the entry `.gdshader` and Godot has no runtime blend switch — the
## deliverable is not a file-count drop, it is that no `.gd` outside `Sprite Rig` names
## a unit shader path.
##
## What this pins, all pure (file reads + an enum lookup — no anim set, no scene, no GPU):
##
##   1. UNIFORM PARITY, opaque vs additive. `ScenarioVM._set_unit_fade_additive` swaps
##      `.shader` on a LIVE material mid-fade and relies on every already-pushed
##      parameter carrying over. Two shaders declaring different uniform names silently
##      drop the sprite's tiles on the swap frame. Nothing asserted this before ADR-0189,
##      and decision 1 rewrites both `vertex()`/`fragment()` bodies.
##   2. UNIFORM SUPERSET, flat over the shared body. `FormationScene` duplicates
##      `assets/materials/unit.tres` — authored against the battle shader — and mounts the
##      flat variant on it. Every uniform the .tres carries must still exist, or the
##      formation roster draws with defaults. The flat variant may add its own (the nine
##      change-job `cj_*` dissolve uniforms, ADR-0189 dec. 6) and only its own.
##
## The uniform regex is ARRAY-AWARE on purpose: `uniform vec2[10] type1_rects;` is the
## declaration form of the entire tile-compositing block, and a `\w+\s+\w+` scan misses
## all 27 of them — i.e. the naive parity check passes while blind to exactly the
## parameters FormationScene's comment says must stay valid.
##
## Run: <GODOT> --path . --quit-after 60 res://tests/UnitMaterialVariantTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const UnitMaterial = ExMateriaSpriteRig.UnitMaterial
const SpriteLayerManager = ExMateriaSpriteRig.SpriteLayerManager

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const UnitMaterialVariant = ExMateriaSchema.UnitMaterialVariant.Kind

## The three shader paths. This test is inside `Sprite Rig`'s own guard, so naming
## them here is the module's business, not a consumer reaching around the seam.
const OPAQUE_SHADER := "res://addons/exmateria_sprite_rig/render/unit.gdshader"
const ADDITIVE_SHADER := "res://addons/exmateria_sprite_rig/render/unit_additive.gdshader"
const FLAT_SHADER := "res://addons/exmateria_sprite_rig/render/unit_flat.gdshader"

## The flat variant's own per-pixel modulation block (ADR-0189 dec. 5/6) — the change-job
## commit dissolve. Deliberately NOT in the shared body: Godot surfaces every declared
## uniform on the ShaderMaterial parameter list, so hosting these there would hang nine
## dead, .tres-serialisable parameters off every battle unit.
## The PAR seam, which ONLY the two battle variants apply (ADR-0189 dec. 6). `pixel_aspect` comes
## from pixel_aspect.gdshaderinc and `unit_stretch` is the ADR-0044 billboard-width multiplier
## layered on it. The flat ortho roster stretches nothing, and a variant that included the seam
## while never calling it is exactly the state tools/check_par_shaders.py exists to prevent —
## so this list being EMPTY would be the regression, not the fix.
const BATTLE_ONLY_UNIFORMS := ["pixel_aspect", "unit_stretch"]

const FLAT_ONLY_UNIFORMS := [
	"cj_active", "cj_bbox_loc", "cj_dissolve", "cj_dissolve_sense", "cj_loc_bias",
	"cj_tint_bl", "cj_tint_br", "cj_tint_tl", "cj_tint_tr",
]

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


## Inline `#include "..."` directives. Mirrors GPUBatchSimulator._load_shader_with_includes.
func _load_with_includes(shader_path: String, visited: Dictionary = {}) -> String:
	if visited.has(shader_path):
		return ""
	visited[shader_path] = true
	var src := FileAccess.get_file_as_string(shader_path)
	if src.is_empty():
		return ""
	var include_re := RegEx.new()
	include_re.compile('^\\s*#include\\s+"([^"]+)"\\s*$')
	var base_dir := shader_path.get_base_dir()
	var out := PackedStringArray()
	for line in src.split("\n"):
		var m := include_re.search(line)
		if m == null:
			out.append(line)
			continue
		var inc := m.get_string(1)
		if not inc.begins_with("res://"):
			inc = base_dir.path_join(inc)
		out.append(_load_with_includes(inc, visited))
	return "\n".join(out)


## Declared uniform NAMES, includes resolved. Array-aware: `uniform vec2[10] type1_rects;`
## and `global uniform float unit_stretch;` both count.
func _uniform_names(shader_path: String) -> Array:
	var src := _load_with_includes(shader_path)
	var names := {}
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*(?:global[ \\t]+)?uniform[ \\t]+\\w+(?:\\[\\d+\\])?[ \\t]+(\\w+)")
	for m in re.search_all(src):
		names[m.get_string(1)] = true
	var out: Array = names.keys()
	out.sort()
	return out


func _ready() -> void:
	var opaque := _uniform_names(OPAQUE_SHADER)
	var additive := _uniform_names(ADDITIVE_SHADER)
	var flat := _uniform_names(FLAT_SHADER)

	_check(opaque.size() > 40, "opaque variant resolves its includes (got %d uniforms)" % opaque.size())
	_check(flat.size() > 40, "flat variant readable (got %d uniforms)" % flat.size())

	# 1. Opaque/additive parity — ScenarioVM swaps .shader on a live material.
	var only_opaque := opaque.filter(func(n): return not (n in additive))
	var only_additive := additive.filter(func(n): return not (n in opaque))
	_check(only_opaque.is_empty() and only_additive.is_empty(),
		"opaque and additive declare identical uniforms (the live .shader swap carries every pushed parameter); opaque-only=%s additive-only=%s" % [str(only_opaque), str(only_additive)])

	# 2. Battle vs flat differ by a NAMED list in BOTH directions. Not "flat is a superset":
	# ADR-0189 dec. 6 moves the PAR seam out of the shared body into the two battle entry
	# shaders, so the flat variant legitimately declares FEWER uniforms than they do. A
	# one-directional check would have had to be relaxed to let that through, and a relaxed
	# check is where a real loss hides. Both lists are enumerated, so a uniform going missing
	# on either side is a failure rather than a smaller set (#424).
	var missing_from_flat := opaque.filter(func(n): return not (n in flat))
	missing_from_flat.sort()
	var expected_battle_only := BATTLE_ONLY_UNIFORMS.duplicate()
	expected_battle_only.sort()
	_check(missing_from_flat == expected_battle_only,
		"the only uniforms the flat variant lacks are the battle PAR block; got=%s expected=%s" % [str(missing_from_flat), str(expected_battle_only)])

	var extras := flat.filter(func(n): return not (n in opaque))
	extras.sort()
	var expected_extras := FLAT_ONLY_UNIFORMS.duplicate()
	expected_extras.sort()
	_check(extras == expected_extras,
		"the only uniforms the flat variant adds are the change-job modulation block; got=%s expected=%s" % [str(extras), str(expected_extras)])

	_check_variant_table()
	_check_consumers_ask_for_a_variant()
	_check_carried_contract(opaque, additive, flat)

	if _failed:
		print("[FAIL] UnitMaterialVariant test")
	else:
		print("[PASS] UnitMaterialVariant: for_variant table, consumers ask for a variant, carried contract on all 3 variants, opaque/additive uniform parity, two-way named variant difference")
	get_tree().quit()


## 3. The published seam (ADR-0189 dec. 3): `Sprite Rig` answers a VARIANT, and the
## answer is a configured duplicate of the base the HOST injects — never the shared
## resource, or one consumer's tile params would land on every other unit on screen.
##
## The base arrives as a parameter now (ADR-0217 dec. 12), so the arms below also pin that
## `for_variant` duplicates what it was HANDED rather than something it looked up: the
## `mesh_size` assertion reads an authored value that only `unit.tres` carries, and it is
## reached through `UnitAssets`, not through a path this test spells.
func _check_variant_table() -> void:
	var base := UnitAssets.base_material()
	_check(base != null, "UnitAssets.base_material() resolves the authored base")
	if base == null:
		return
	var want := {
		UnitMaterialVariant.OPAQUE: OPAQUE_SHADER,
		UnitMaterialVariant.ADDITIVE: ADDITIVE_SHADER,
		UnitMaterialVariant.FLAT: FLAT_SHADER,
	}
	for v in want:
		var mat := UnitMaterial.for_variant(v, base)
		_check(mat != null, "for_variant(%d) returns a material" % v)
		if mat == null:
			continue
		_check(mat.shader != null and mat.shader.resource_path == want[v],
			"for_variant(%d).shader is %s (got %s)" % [v, want[v], "null" if mat.shader == null else mat.shader.resource_path])

	# The narrow door and the wide one agree. `ScenarioVM` owns a live per-unit material and
	# changes only the blend, so it needs the shader alone; it must be the SAME shader a
	# freshly-built material of that variant would carry, or the two consumers drift again.
	for v in want:
		var s := UnitMaterial.shader_for(v)
		_check(s != null and s == UnitMaterial.for_variant(v, base).shader,
			"shader_for(%d) is exactly for_variant(%d).shader" % [v, v])

	# A duplicate per call — the caller owns what it gets back.
	var a := UnitMaterial.for_variant(UnitMaterialVariant.OPAQUE, base)
	var b := UnitMaterial.for_variant(UnitMaterialVariant.OPAQUE, base)
	_check(a != b, "for_variant returns a fresh duplicate per call (callers push per-unit tile params)")
	_check(a != base and b != base,
		"and never the injected base itself — the caller pushes per-unit params into it")

	# The injection is direction-tested: without a base there is no material and no silent
	# fallback to a path the module used to know. A `for_variant` that quietly loaded one
	# would pass every arm above and defeat the whole decision.
	_check(UnitMaterial.for_variant(UnitMaterialVariant.OPAQUE, null) == null,
		"for_variant with no base returns null rather than resolving one itself")
	_check(a.get_shader_parameter("mesh_size") == Vector2(1, 1),
		"the duplicate carries unit.tres's authored parameters (mesh_size), not shader defaults")


## The two foreign systems that went around the seam. `FormationScene` (UI) and
## `ScenarioVM` (Cutscene) both took `Sprite Rig`'s sprite compositor by overwriting a
## material's `.shader` with a path they named themselves — one `load()` call each, and
## one of them grew a 1,018-line fork of the compositor to have a path worth naming.
##
## This is the narrow arm: the two files that actually broke the seam. ADR-0189 dec. 8
## — a repo-wide guard over every `.gd` outside `Sprite Rig` — is a separate, OPEN
## question. Note for whoever answers it: a text scan is not enough. Ten more `.gd`
## files mention a unit shader path in a COMMENT (SpriteLayerManager, Unit,
## ScenarioDialogueBoxPool, UI3OwnerColorMap…), every one of them a legitimate
## cross-reference, so the guard has to strip comments or it fires on prose.
const CONSUMERS_OUTSIDE_SPRITE_RIG := [
	"res://src/ui3/formation/FormationScene.gd",
	"res://src/scenarios/ScenarioVM.gd",
]

## `//`-free by construction (GDScript), so a `#` to end-of-line strip is exact — except
## inside a string literal, and a `res://…` path IS a string literal, which is the thing
## being looked for. Strip whole comment LINES and trailing comments that start outside a
## quote; anything else would eat the evidence.
func _strip_comments(src: String) -> String:
	var out := PackedStringArray()
	for raw in src.split("\n"):
		var in_str := false
		var quote := ""
		var cut := -1
		for i in raw.length():
			var c := raw[i]
			if in_str:
				if c == quote and (i == 0 or raw[i - 1] != "\\"):
					in_str = false
			elif c == "\"" or c == "'":
				in_str = true
				quote = c
			elif c == "#":
				cut = i
				break
		out.append(raw if cut < 0 else raw.substr(0, cut))
	return "\n".join(out)


## 4. No consumer outside `Sprite Rig` names a unit shader path in CODE (ADR-0189 dec. 3).
func _check_consumers_ask_for_a_variant() -> void:
	var re := RegEx.new()
	# Deliberately anchored on the PATH BODY ("shaders/…unit….gdshader") rather than on a
	# literal `res://` prefix. tools/check_res_paths.py walks every quoted `res://` string in
	# the tree and demands it resolve; a regex that merely CONTAINS the scheme is indexed as a
	# reference to a file named `res://[\w/]*unit…` and reported unresolved. That is the guard
	# being right about a string it cannot tell apart from a path, and KNOWN_BREAKS is for
	# ticketed real breaks, not for laundering — so the fix belongs here.
	# `[^i]` after the extension keeps `.gdshaderinc` (the shared include) out of the match.
	re.compile("[\\w/]*shaders/[\\w]*unit[\\w]*\\.gdshader(?:[^i]|$)")
	for path in CONSUMERS_OUTSIDE_SPRITE_RIG:
		var src := FileAccess.get_file_as_string(path)
		_check(not src.is_empty(), "%s readable" % path)
		var hits: Array = []
		for m in re.search_all(_strip_comments(src)):
			hits.append(m.get_string())
		_check(hits.is_empty(),
			"%s asks UnitMaterial for a variant instead of naming a unit shader path; found=%s" % [path, str(hits)])


## The driver that paints all three variants, and the authored base they all duplicate.
##
## 🔴 THIS LITERAL STAYS, and it is the one place in the tree that still spells it besides
## `UnitAssets` (ADR-0217 dec. 12). The arm below reads the file as TEXT to enumerate the
## `shader_parameter/` keys the three shaders must declare — it is the INDEPENDENT ORACLE
## for that block, and resolving it through `UnitAssets.BASE_MATERIAL` would let a repoint
## there move the oracle silently, so the guard would be comparing the injection to itself.
## Same argument ADR-0189 dec. 8 makes for `ScenarioDeadUnitFadeTest`. The `for_variant`
## arms above DO go through `UnitAssets`, because there the base is the subject, not the
## yardstick.
const DRIVER := "res://addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd"
const BASE_MATERIAL := "res://assets/materials/unit.tres"

## The three composited layers. `_write_layer_params` pushes eight arrays per layer by
## CONCATENATING this prefix onto a suffix, so the names never appear as literals in the
## driver's source and a literal scan is blind to all 24 of them. Named here, not derived
## by a filter, for the reason #424 paid for: a filter that stops matching leaves the
## required set silently.
const SPRITE_LAYERS := ["type1", "wep1", "eff1"]
const LAYER_PARAM_SUFFIXES := [
	"_rects", "_rect_sizes", "_locs", "_inversions",
	"_reversions", "_loc_offsets", "_rotations", "_rot_points",
]


## 5. THE CARRIED CONTRACT — the arm that survives the shader refactor.
##
## Arms 1 and 2 compare shaders to each other, which pins that they agree but says nothing
## about whether they agree on the RIGHT set. This one derives the required names from the
## two things that actually push them, neither of which is a shader:
##
##   A. every `shader_parameter/` key authored into `assets/materials/unit.tres` — the
##      resource all three variants duplicate. A key with no matching uniform is silently
##      dropped on load, so the battle unit renders with a shader default and nothing says.
##   B. every parameter `SpriteLayerManager` pushes per frame — the one driver behind all
##      three variants (five production call sites).
##
## Independent sources, so this cannot pass by construction the way a shader-to-shader
## diff can. ADR-0189 dec. 1 rewrites all three `vertex()`/`fragment()` bodies and dec. 6
## moves declarations BETWEEN files; this is what says the moves were lossless.
func _check_carried_contract(opaque: Array, additive: Array, flat: Array) -> void:
	var required := {}

	# A. The authored base.
	var tres := FileAccess.get_file_as_string(BASE_MATERIAL)
	_check(not tres.is_empty(), "%s readable" % BASE_MATERIAL)
	var tres_re := RegEx.new()
	tres_re.compile("(?m)^shader_parameter/(\\w+)")
	for m in tres_re.search_all(tres):
		required[m.get_string(1)] = "unit.tres"
	_check(required.size() > 30, "unit.tres authors a real parameter block (got %d)" % required.size())

	# B. The driver's per-frame pushes — literals...
	var drv := FileAccess.get_file_as_string(DRIVER)
	_check(not drv.is_empty(), "%s readable" % DRIVER)
	var drv_re := RegEx.new()
	drv_re.compile('set_shader_parameter\\(\\s*"(\\w+)"')
	var literals := 0
	for m in drv_re.search_all(drv):
		required[m.get_string(1)] = "SpriteLayerManager"
		literals += 1
	_check(literals > 15, "SpriteLayerManager's literal pushes are visible to the scan (got %d)" % literals)

	# ...and the concatenated per-layer block.
	for layer in SPRITE_LAYERS:
		for suffix in LAYER_PARAM_SUFFIXES:
			_check(('set_shader_parameter(layer_name + "%s"' % suffix) in drv,
				"SpriteLayerManager still pushes <layer>%s by concatenation (the named list is current)" % suffix)
			required[layer + suffix] = "SpriteLayerManager"

	var variants := {"opaque": opaque, "additive": additive, "flat": flat}
	for name in variants:
		var declared: Array = variants[name]
		var missing: Array = []
		for param in required:
			if not (param in declared):
				missing.append("%s (from %s)" % [param, required[param]])
		missing.sort()
		_check(missing.is_empty(),
			"the %s variant declares every carried parameter (%d required); missing=%s" % [name, required.size(), str(missing)])
