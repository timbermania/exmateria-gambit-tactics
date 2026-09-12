extends Node
## Guards the damage-number fade-band → compositor fold routing (the fire-on-a-fading-number artifact
## fix, ADR-0063 / #89 follow-up, ADR-0074 / #229).
##
## A DamageNumber3D lives two phases: opaque grow+steady (stays in-scene, feedback_hud_sprite.gdshader)
## and an additive fade band. The fade twin used to be a compositor-EXEMPT in-scene additive sprite —
## fine in isolation, but when a routed prim (Fire) lands on a unit that still has a fading number, the
## exempt sprite hardware-blends over the routed prim and flashes it. The fix routes the FADE phase
## through the engine fold like every other additive PSX prim. This test locks that routing contract
## WITHOUT needing the fork/GPU, mirroring CallbackFoldRoutingTest:
##   1. the routing DECISION (fade_shader): fold variant when the engine-fold owns compositing,
##      plain in-scene additive twin otherwise;
##   2. the fold variant actually declares `compositor_layer` (genuinely reaches the scratch) and is
##      NOT `// compositor-exempt:`-marked (it's routed, not routed-elsewhere);
##   3. the in-scene fallback still declares blend_add and carries the exempt marker (so the Forward+
##      burn-down checker treats it as routed-elsewhere on the fallback path, not a leak);
##   4. uniform PARITY between the two shaders — DamageNumber3D swaps only .shader and keeps each
##      digit's ShaderMaterial, so its persisted set_shader_parameter() values must hit the same names;
##   5. the fold variant drops the sRGB->linear pow(2.2) the in-scene twin applies (it blends in the
##      display-space scratch) — the crystal_fold contract, and the reason a folded number isn't dark.
##
## Pure GDScript + file reads, no GPU / no fork, so it runs in the headless suite.
##
## Run: <GODOT> --path . --quit-after 60 res://tests/FeedbackHudFoldRoutingTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
## `DepthMode` went with item 6 (#649) — the only use was the retired `Fold.add`
## rank arithmetic, and an alias nothing spells is an ADR-0211 dec. 4 claim with
## no use site behind it.
const Fold = ExMateriaSchema.Fold

const DamageNumber3DClass = preload("res://src/ui3/elements/DamageNumber3D.gd")
const StatusBubble3DClass = preload("res://src/ui3/elements/StatusBubble3D.gd")

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _declares_fold(src: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bcompositor_layer\\b")
	return re.search(src) != null


func _declares_add(src: String) -> bool:
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bblend_add\\b")
	return re.search(src) != null


func _declares_any_blend(src: String) -> bool:
	# Any non-opaque blend mode in the render_mode line (line-anchored so a mention in a comment is
	# not matched). Opaque materials declare none of these.
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\b(blend_mix|blend_add|blend_sub|blend_mul)\\b")
	return re.search(src) != null


func _uniform_names(src: String) -> Array:
	var names: Array = []
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*uniform\\s+\\w+\\s+(\\w+)")
	for m in re.search_all(src):
		names.append(m.get_string(1))
	names.sort()
	return names


func _ready() -> void:
	var fold_path: String = DamageNumber3DClass.SHADER_ADDITIVE_FOLD.resource_path
	var fallback_path: String = DamageNumber3DClass.SHADER_ADDITIVE.resource_path
	var fold_src := FileAccess.get_file_as_string(fold_path)
	var fallback_src := FileAccess.get_file_as_string(fallback_path)

	# 1. Routing decision. The PICK itself is Fold.shader's, and FoldTest asserts both of its
	# branches. What this pins is the half only the PRODUCER can get wrong: that it hands Fold.shader
	# the right two shaders in the right ORDER. A swapped pair would fold the fallback and leave the
	# fold variant drawing in-scene, and every source check below would still pass. The build predicate
	# is permanently true on the fork this runs on, so the off-fork answer needs the cached snapshot
	# overridden and restored (the same lever FoldTest uses).
	var restore_owns: int = Fold._owns_cache
	Fold._owns_cache = 1
	_check(DamageNumber3DClass.fade_shader() == DamageNumber3DClass.SHADER_ADDITIVE_FOLD,
		"folded decision -> fold variant (%s)" % fold_path)
	Fold._owns_cache = 0
	_check(DamageNumber3DClass.fade_shader() == DamageNumber3DClass.SHADER_ADDITIVE,
		"un-folded decision -> in-scene additive twin (%s)" % fallback_path)
	Fold._owns_cache = restore_owns

	# 2. The fold variant genuinely routes through the compositor and is NOT exempt-marked.
	_check(not fold_src.is_empty(), "fold variant readable")
	_check(_declares_fold(fold_src),
		"fold variant declares compositor_layer (routes into the scratch — the fire-on-number fix)")
	_check(not ("compositor-exempt:" in fold_src),
		"fold variant is NOT compositor-exempt-marked (it is routed, not routed-elsewhere)")

	# 3. The in-scene fallback still blends additively AND carries the exempt marker (routed-elsewhere).
	_check(not fallback_src.is_empty(), "fallback shader readable")
	_check(_declares_add(fallback_src) and not _declares_fold(fallback_src),
		"fallback is in-scene blend_add (no compositor_layer) — the Mobile/stock path")
	_check("compositor-exempt:" in fallback_src,
		"fallback carries a // compositor-exempt: marker (burn-down treats it as routed-elsewhere)")

	# 4. Uniform parity — the runtime .shader swap must preserve each digit's set_shader_parameter().
	var fu := _uniform_names(fold_src)
	var nu := _uniform_names(fallback_src)
	_check(fu == nu,
		"fold/fallback declare identical uniforms (swap-safe): fold=%s fallback=%s" % [str(fu), str(nu)])

	# 5. Display-space contract: the fold variant drops the pow(2.2) the in-scene twin applies (the fold
	# blends in display space; the seed already converts the scene to sRGB). A folded number that kept
	# the pow would fold darkened (double sRGB->linear), the crystal_fold regression class.
	_check("pow(" in fallback_src, "in-scene twin applies a sRGB->linear pow (sanity)")
	_check(not ("pow(" in fold_src),
		"fold variant drops the pow(2.2) — it emits display-space texels (crystal_fold contract)")

	# 6. (RETIRED — #649.) This item re-asserted the `Fold.add` contract: material_override,
	# FOLD_LAYER membership, and default-rank-0 order. That is the DECORATOR's contract, not this
	# scene's question, and ADR-0191 dec. 10 moved the same three assertions out of
	# CallbackFoldRoutingTest and FormationFoldRoutingTest for that reason — it just did not name
	# this third copy. `tests/FoldTest.gd` owns it and covers it strictly better: it asserts the
	# order key as a LITERAL (3074) rather than recomputing it the way `add()` does, so it can
	# actually disagree with the implementation. A routing test's question is which shaders declare
	# `compositor_layer`; the number stays 6 so items 7 and 8 keep the names they were reviewed under.

	# 7. THE core invariant (the Fire-on-a-charging-caster / fading-number artifact, #89): the shared
	# over-unit sprite shader used by BOTH the damage-number steady phase and the status/charge bubble
	# must be OPAQUE — no blend_mix/add/sub in its render_mode. The display-space compositor seeds its
	# scratch from the OPAQUE color buffer; an opaque prim is in that seed by default (the scratch is the
	# default, the fold is the opt-in). A non-opaque, non-folded over-unit prim (the old blend_mix — not
	# even a real PSX mode) draws in the transparent queue after the seed and is clobbered by Pass C
	# wherever a folded effect overlaps it. This guards against that mode ever coming back.
	var steady_path: String = DamageNumber3DClass.SHADER_OPAQUE
	var steady_src := FileAccess.get_file_as_string(steady_path)
	_check(not steady_src.is_empty(), "over-unit steady/bubble shader readable (%s)" % steady_path)
	_check(not _declares_any_blend(steady_src),
		"over-unit steady/bubble shader is OPAQUE (no blend_mix/add/sub) -> lands in the compositor seed, not clobbered")
	# The status/charge bubble shares that exact shader, so the invariant covers it too.
	_check(StatusBubble3DClass.SHADER_PATH == steady_path,
		"StatusBubble3D uses the same opaque over-unit shader (so the bubble is seeded, not clobbered)")

	if _failed:
		print("[FAIL] FeedbackHudFoldRouting test")
	else:
		print("[PASS] FeedbackHudFoldRouting: decision, fade variant routes (compositor_layer, not exempt), fallback exempt, uniform parity, display-space pow dropped")
	get_tree().quit()
