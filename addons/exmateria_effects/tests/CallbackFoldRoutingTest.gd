extends Node
## Guards the callback → compositor fold routing (the E065 Shiva "spikes pierce the flash" fix).
##
## Callbacks (grids/rings/tubes) are scene MeshInstance3D nodes, NOT particle-pool prims — so the
## static tools/check_compositor_routing.py scan can only *locate* their shaders; whether a live
## callback actually FOLDS (rather than drawing into the transparent color layer where Pass C's
## coverage-discard clobbers it) is a runtime contract. This test locks that contract WITHOUT needing
## the fork/GPU by pinning the pure pieces the routing rests on:
##   1. the routing DECISION (blend_shader): fold variant when the engine-fold owns compositing,
##      plain additive fallback otherwise;
##   2. the fold variant actually declares `compositor_layer` — i.e. it genuinely routes through the
##      compositor (the crux of the bug: a callback whose material lacks it never reaches the scratch);
##   3. the in-scene fallback does NOT declare compositor_layer but IS `// compositor-exempt:`-marked
##      (so the Forward+ burn-down checker treats it as routed-elsewhere, not a leak);
##   4. uniform PARITY between the two shaders — the callback swaps only .shader and keeps its own
##      _material, so its per-frame set_shader_parameter() calls must hit the same uniform names;
##   5. every callback registered in CallbackRegistry is an EffectCallback subclass, so it inherits the
##      single _create_cb_mesh routing seam — a future callback that hand-rolls its own material would
##      bypass the fold, and this catches it.
##
## Pure GDScript + file reads, no GPU / no fork, so it runs in the headless suite.
##
## Run: <GODOT> --path . --quit-after 60 res://tests/CallbackFoldRoutingTest.tscn

const EffectCallback = preload("res://addons/exmateria_effects/callbacks/EffectCallback.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const Fold = ExMateriaSchema.Fold

const CallbackRegistryClass = preload("res://addons/exmateria_effects/callbacks/CallbackRegistry.gd")

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _declares_fold(src: String) -> bool:
	# compositor_layer in the RENDER_MODE (line-anchored) — not a mention in a comment/exempt marker.
	var re := RegEx.new()
	re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\bcompositor_layer\\b")
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
	var fold_path: String = EffectCallback.CB_SHADER_FOLD.resource_path
	var norm_path: String = EffectCallback.CB_SHADER_NORMAL.resource_path
	var fold_src := FileAccess.get_file_as_string(fold_path)
	var norm_src := FileAccess.get_file_as_string(norm_path)

	# 1. Routing decision. The PICK itself is Fold.shader's, and FoldTest asserts both of its
	# branches. What this pins is the half only the PRODUCER can get wrong: that it hands Fold.shader
	# the right two shaders in the right ORDER. A swapped pair would fold the fallback and leave the
	# fold variant drawing in-scene, and every source check below would still pass. The build predicate
	# is permanently true on the fork this runs on, so the off-fork answer needs the cached snapshot
	# overridden and restored (the same lever FoldTest uses).
	var restore_owns: int = Fold._owns_cache
	Fold._owns_cache = 1
	_check(EffectCallback.blend_shader() == EffectCallback.CB_SHADER_FOLD,
		"folded decision -> fold variant (%s)" % fold_path)
	Fold._owns_cache = 0
	_check(EffectCallback.blend_shader() == EffectCallback.CB_SHADER_NORMAL,
		"un-folded decision -> plain additive fallback (%s)" % norm_path)
	Fold._owns_cache = restore_owns

	# 2. The fold variant genuinely routes through the compositor.
	_check(not fold_src.is_empty(), "fold variant readable")
	_check(_declares_fold(fold_src),
		"fold variant declares compositor_layer (routes into the scratch — the Shiva fix)")

	# 3. The in-scene fallback is NOT folded but IS exempt-marked (routed-elsewhere on Forward+).
	_check(not norm_src.is_empty(), "fallback shader readable")
	_check(not _declares_fold(norm_src),
		"fallback does NOT declare compositor_layer in render_mode (it's the Mobile in-scene path)")
	_check("compositor-exempt:" in norm_src,
		"fallback carries a // compositor-exempt: marker (burn-down treats it as routed)")

	# 4. Uniform parity — the runtime .shader swap must preserve the callback's set_shader_parameter().
	var fu := _uniform_names(fold_src)
	var nu := _uniform_names(norm_src)
	_check(fu == nu,
		"fold/fallback declare identical uniforms (swap-safe): fold=%s fallback=%s" % [str(fu), str(nu)])

	# 5. Every registered callback inherits the shared _create_cb_mesh routing seam. Iterate the ids
	# CallbackRegistry.create() maps (mirrors the registry match as of 2026-07-27) so unmapped ids
	# don't spam "Unknown callback ID" warnings.
	var mapped_ids := [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
		26, 27, 30, 32, 36, 39, 56, 57, 91, 92]
	var bypass: Array = []
	for cb_id in mapped_ids:
		var cb = CallbackRegistryClass.create(cb_id)
		if cb == null:
			bypass.append(cb_id)   # a mapped id that no longer produces a callback
			continue
		if not (cb is EffectCallback):
			bypass.append(cb_id)
		cb.free()
	_check(bypass.is_empty(),
		"all registered callbacks are EffectCallback subclasses (inherit fold routing); bypassing ids=%s" % str(bypass))

	# The Fold.add contract used to be re-asserted here, verbatim with FormationFoldRoutingTest's copy.
	# It lives in tests/FoldTest.gd now (ADR-0191 dec. 10): this file's question is ROUTING — which
	# shaders declare compositor_layer and which are exempt — and the decorator's contract is not it.

	if _failed:
		print("[FAIL] CallbackFoldRouting test")
	else:
		print("[PASS] CallbackFoldRouting: decision, fold-variant routes (compositor_layer), fallback exempt, uniform parity, all callbacks inherit the seam")
	get_tree().quit()
