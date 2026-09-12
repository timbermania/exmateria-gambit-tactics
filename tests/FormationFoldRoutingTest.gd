extends Node
# test-kind: logic
# seeded-break: strip `compositor_layer` from formation_box_fold.gdshader's render_mode - the exact ADR-0077 bug shape - 'box_add fold variant declares compositor_layer' REDed (1 assert + aggregate); every other prim, the fallback/exempt arms, the opaque-dual invariant, and the UIVitalsBand producer arm stayed green; GREEN unbroken on the reverted tree
## Guards the FORMATION scene's add/sub prims → compositor fold routing (ADR-0077).
##
## The formation / party-roster screen is a flat ortho UI whose six PSX display-space effects —
## the gold selection box (additive + subtractive emboss passes), the orb rim HALO, the per-unit
## drop SHADOW, the bottom vitals BAND, and the Change-Job commit CYLINDER — must join the engine-fold (ADR-0074) so the 4.8
## Forward+ Pass B blends them in the display-space scratch with the PSX per-step UNORM clamp,
## instead of the retired Mobile-era FormationDisplaySpaceComposite. Whether a live prim actually
## FOLDS (rather than drawing into the transparent color layer, where Pass C's coverage-discard
## clobbers it) is a runtime material contract the static tools/check_compositor_routing.py scan
## can only locate, not prove. This test locks that contract WITHOUT the fork/GPU by pinning the
## pure pieces the routing rests on, mirroring tests/CallbackFoldRoutingTest:
##   1. the routing DECISION (FormationScene.fold_shader_for + FOLD_PRIMS): fold variant when the engine-fold
##      owns compositing, the in-scene Mobile blend fallback otherwise;
##   2. every fold variant actually declares `compositor_layer` in its render_mode — i.e. it genuinely
##      routes through the compositor (the crux: a prim whose material lacks it never reaches the
##      scratch, so the halo/box silently vanish — exactly the ADR-0077 bug);
##   3. every in-scene fallback does NOT declare compositor_layer but IS `// compositor-exempt:`-marked,
##      so the Forward+ burn-down checker treats it as routed-elsewhere (the Mobile fallback), not a leak;
##   4. (the Fold.add decorator's own contract moved to tests/FoldTest.gd — ADR-0191 dec. 10.)
##   5. the BAND prim's real producer, UIVitalsBand, takes that same decision ITSELF (ADR-0191
##      Amendment 4) — both branches, including the off-fork half nothing exercised before.
##
## Pure GDScript + file reads, no GPU / no fork, so it runs in the headless suite.
##
## Run: <GODOT> --path . --quit-after 60 res://tests/FormationFoldRoutingTest.tscn

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaSpriteRig` a complete census of host->addon symbol coupling.
const UnitMaterial = ExMateriaSpriteRig.UnitMaterial

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode
const Fold = ExMateriaSchema.Fold

## ADR-0215 dec. 2 / ADR-0217 dec. 7 — the sprite rig's VALUE VOCABULARY is the
## kernel's; the behaviour-bearing hosts keep their class names and their behaviour.
## This line is what keeps the use sites below spelled the way they were
## (ADR-0211 dec. 4).
const UnitMaterialVariant = ExMateriaSchema.UnitMaterialVariant.Kind

const FormationSceneClass = preload("res://src/ui3/formation/FormationScene.gd")

# The reused vitals panel's two depth-writing sprite shaders (global-unify, clause 4b).
const SHADER_VITALS_SPRITE := "res://src/ui3/shaders/vitals_sprite.gdshader"
const SHADER_VITALS_BAR := "res://src/ui3/shaders/vitals_bar.gdshader"

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


## The MeshInstance3D UIVitalsBand.build put under its named holder.
func _band_mesh(parent: Node3D, holder_name: String) -> MeshInstance3D:
	var holder := parent.get_node_or_null(NodePath(holder_name)) as Node3D
	if holder == null:
		return null
	for c: Node in holder.get_children():
		if c is MeshInstance3D:
			return c as MeshInstance3D
	return null


func _ready() -> void:
	# Every add/sub prim ADR-0077 folds. Keys mirror FormationScene.FOLD_PRIMS.
	# `changejob_cylinder` is the 64-stripe commit cylinder (CHANGE_JOB_COMMIT.md §9) — a prim
	# that only lives for the 4-second beat, but a PSX display-space semi-transparent one all the
	# same, so it takes the identical routing decision as the five permanent prims.
	var prims := ["box_add", "box_sub", "orb_rim", "shadow", "band", "changejob_cylinder"]
	_check(FormationSceneClass.FOLD_PRIMS.size() == prims.size(),
		"FOLD_PRIMS covers exactly the six add/sub prims (%d)" % prims.size())

	for prim in prims:
		var entry: Dictionary = FormationSceneClass.FOLD_PRIMS[prim]
		var fold_path: String = entry["fold"].resource_path
		var scene_path: String = entry["scene"].resource_path

		# 1. Routing decision: folded -> the *_fold variant, un-folded -> the in-scene fallback. The
		# PICK is Fold.shader's and FoldTest asserts both its branches; what this pins is the half only
		# the producer can get wrong — that FOLD_PRIMS hands it the right two, in the right ORDER. A
		# swapped entry would fold the fallback and leave the fold variant in-scene, and every source
		# check below would still pass. The predicate is permanently true on the fork this runs on, so
		# the off-fork answer needs the cached snapshot overridden and restored (FoldTest's lever).
		_check(fold_path.ends_with("_fold.gdshader"),
			"%s folded decision -> a *_fold variant (%s)" % [prim, fold_path])
		_check(fold_path != scene_path,
			"%s fold and fallback are distinct shaders" % prim)
		var restore_owns: int = Fold._owns_cache
		Fold._owns_cache = 1
		_check(FormationSceneClass.fold_shader_for(prim) == entry["fold"],
			"%s folded -> FOLD_PRIMS' fold entry (%s)" % [prim, fold_path])
		Fold._owns_cache = 0
		_check(FormationSceneClass.fold_shader_for(prim) == entry["scene"],
			"%s un-folded -> FOLD_PRIMS' in-scene entry (%s)" % [prim, scene_path])
		Fold._owns_cache = restore_owns

		# 2. The fold variant genuinely routes through the compositor.
		var fold_src := FileAccess.get_file_as_string(fold_path)
		_check(not fold_src.is_empty(), "%s fold variant readable (%s)" % [prim, fold_path])
		_check(_declares_fold(fold_src),
			"%s fold variant declares compositor_layer (routes into the scratch — the ADR-0077 fix)" % prim)

		# 3. The in-scene fallback is NOT folded but IS exempt-marked (routed-elsewhere on Forward+).
		var scene_src := FileAccess.get_file_as_string(scene_path)
		_check(not scene_src.is_empty(), "%s fallback shader readable (%s)" % [prim, scene_path])
		_check(not _declares_fold(scene_src),
			"%s fallback does NOT declare compositor_layer (it's the Mobile in-scene path)" % prim)
		_check("compositor-exempt:" in scene_src,
			"%s fallback carries a // compositor-exempt: marker (burn-down treats it as routed)" % prim)

	# 4. The DUAL invariant (ADR-0077): the OPAQUE prims that seed the fold scratch + write depth must
	# actually BE opaque. This is the trap that caused the "gray box" regression — in Godot, ASSIGNING
	# `ALPHA` (even `= 1.0`) opts a spatial material into the TRANSPARENT pipeline, so it renders AFTER
	# the fold's PRE_TRANSPARENT seed and never reaches the scratch (folded prims then composite over the
	# gray clear-color) AND it stops writing depth (the folded box no longer occludes behind it). These
	# shaders must stay opaque via `discard` of transparent texels — never an ALPHA write, never a
	# depth-off render_mode. A human won't see this; the guard must.
	# The reused UIUnitInfoWindow vitals sprites join this SAME invariant (2026-08-02): once the panel
	# is on the depth ladder (ADR-0077), its sprites are ordinary opaque depth-writing prims — no more
	# "always on top" depth_test_disabled, no render_priority. They must be opaque (no ALPHA write) and
	# NOT carry depth_draw_never/depth_test_disabled, exactly like the floor/orb/body/sort-text above.
	var opaque_prims := {
		"floor (seeds the scratch)": FormationSceneClass._BG_SHADER,
		"orb core (seeds + depth)": FormationSceneClass._ORB_OPAQUE_SHADER.resource_path,
		# ADR-0189: the screen no longer names this file — it asks Sprite Rig for the FLAT
		# variant. So does this test, which is the point: there is one place that knows.
		"unit body (seeds + occludes the box)": UnitMaterial.shader_for(UnitMaterialVariant.FLAT).resource_path,
		"sort text (occludes the box)": FormationSceneClass._TEXT_OPAQUE_SHADER,
		"vitals sprite (labels/digits/bar-track)": SHADER_VITALS_SPRITE,
		"vitals bar fill": SHADER_VITALS_BAR,
	}
	var alpha_re := RegEx.new()
	alpha_re.compile("(?m)^[ \\t]*ALPHA[ \\t]*=")   # a fragment assignment to ALPHA (not a comment mention)
	var depth_off_re := RegEx.new()
	depth_off_re.compile("(?m)^[ \\t]*render_mode\\b[^;]*\\b(depth_draw_never|depth_test_disabled)\\b")
	for label in opaque_prims:
		var path: String = opaque_prims[label]
		var src := FileAccess.get_file_as_string(path)
		_check(not src.is_empty(), "opaque prim %s readable (%s)" % [label, path])
		_check(alpha_re.search(src) == null,
			"opaque prim %s does NOT assign ALPHA (an ALPHA write ⇒ transparent ⇒ drops out of the fold seed + depth — the gray-box trap)" % label)
		_check(depth_off_re.search(src) == null,
			"opaque prim %s writes depth (no depth_draw_never/depth_test_disabled — it must seed + occlude)" % label)

	# 5. The BAND prim's real producer is UIVitalsBand, and it must ASK the predicate itself.
	# FOLD_PRIMS["band"] is checked above like the other five, but nothing in production calls
	# fold_shader_for("band") — the bottom band, the detail stripe, the Eqp/Ability column bands and
	# the equip-picker left strip are all built by the SHARED UIVitalsBand element, which holds its
	# own preloaded pair. That producer was invisible to every ADR-0191 census because it never names
	# the predicate (Amendment 3), and until this arm nothing anywhere exercised its off-fork half.
	#
	# The two asks below are the same mutate-and-restore lever FoldTest uses, and they are what makes
	# the collapsed signature testable: with `folded` gone from build(), the fallback branch is
	# reachable ONLY through the cached snapshot, so this is now its only coverage.
	#
	# The OFF-FORK arms assert what the PRODUCER alone controls — `render_priority` (its in-scene
	# ordering fallback) and the holder's flat Z — not "the carrier is un-enrolled". Since Amendment
	# 4 §3 made Fold.add self-gate, un-enrolment off-fork is the KERNEL's guarantee and a producer
	# assert on it is a tautology: seeding `folded := true` here left it green. Measured, not assumed.
	var band_parent := Node3D.new()
	add_child(band_parent)
	var band_spec := {
		"name": "RoutingProbeBand",
		"x0": 0.0, "x1": 100.0,
		"y_top_out": 0.0, "y_top_in": 2.0, "y_bot_in": 18.0, "y_bot_out": 20.0,
		"full_sub": 48.0 / 255.0, "rung": 1,
	}
	var restore_band_owns: int = Fold._owns_cache

	Fold._owns_cache = 1
	var folded_mat := UIVitalsBand.build(band_parent, band_spec, 0.04, Vector2(320.0, 240.0))
	_check(folded_mat != null and folded_mat.shader == FormationSceneClass.FOLD_PRIMS["band"]["fold"],
		"UIVitalsBand folded -> the formation_band_fold variant (the same Shader FOLD_PRIMS names)")
	var folded_mi := _band_mesh(band_parent, "RoutingProbeBand")
	_check(folded_mi != null and folded_mi.render_layer != null,
		"UIVitalsBand folded -> the carrier is ENROLLED in the fold layer (Fold.add ran)")
	_check(folded_mat != null and folded_mat.render_priority == 0,
		"UIVitalsBand folded -> NO render_priority (depth is the fold order key, not the in-scene sort)")
	var folded_holder := band_parent.get_node_or_null("RoutingProbeBand") as Node3D
	_check(folded_holder != null and is_equal_approx(folded_holder.position.z, DepthMode.rung_z(1)),
		"UIVitalsBand folded -> the holder sits at the rung's real Z")

	Fold._owns_cache = 0
	band_spec["name"] = "RoutingProbeBandOffFork"
	var scene_mat := UIVitalsBand.build(band_parent, band_spec, 0.04, Vector2(320.0, 240.0))
	_check(scene_mat != null and scene_mat.shader == FormationSceneClass.FOLD_PRIMS["band"]["scene"],
		"UIVitalsBand un-folded -> the in-scene formation_band fallback")
	var scene_mi := _band_mesh(band_parent, "RoutingProbeBandOffFork")
	_check(scene_mi != null and scene_mi.render_layer == null,
		"UIVitalsBand un-folded -> the carrier is NOT enrolled (the kernel's guarantee since Amdt 4 §3)")
	# THESE are the producer's own off-fork work, which no kernel gate can do for it.
	_check(scene_mat != null and scene_mat.render_priority == 1,
		"UIVitalsBand un-folded -> render_priority carries the rung (the in-scene sort fallback)")
	var scene_holder := band_parent.get_node_or_null("RoutingProbeBandOffFork") as Node3D
	_check(scene_holder != null and is_zero_approx(scene_holder.position.z),
		"UIVitalsBand un-folded -> the holder sits FLAT at z=0 (no fold rung to materialise)")

	Fold._owns_cache = restore_band_owns
	band_parent.queue_free()

	# The Fold.add contract used to be re-asserted here, verbatim with CallbackFoldRoutingTest's copy.
	# It lives in tests/FoldTest.gd now (ADR-0191 dec. 10): this file's question is ROUTING — which
	# shaders declare compositor_layer and which are exempt — and the decorator's contract is not it.

	if _failed:
		print("[FAIL] FormationFoldRouting test")
	else:
		print("[PASS] FormationFoldRouting: 6 prims route (compositor_layer), fallbacks exempt")
	get_tree().quit()
