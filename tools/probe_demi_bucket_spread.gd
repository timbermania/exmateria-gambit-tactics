extends SceneTree
## DEMI 2 (E046) — BUCKET-WIDTH parity probe (research/working_documents/COMPOSITOR_OT_BUCKET_WIDTH_PARITY.md).
##
## Question: how many OTDepthPrimOrder buckets does the DEMI particle cloud occupy for US,
## and what is its world-Z depth extent (⇒ implied PSX bucket span = Δz / 0.19)? This measures
## how often the within-bucket AGE tie-break fires vs. how often real depth decides order.
##
## Method: boot EffectViewer, play E046, seek to overlap frames, and read the renderer's staged
## per-prim arrays (_prim_depths = DepthMode.ot_order_z = VIEW-SPACE Z in WORLD UNITS since #212;
## _prim_modes; _prim_ages). The depth span IS the world-Z extent directly now (no proj.z.z
## conversion — that was the reversed-Z NDC era). OUR-buckets = distinct round(z/0.19) buckets;
## post-#212 this is > 1 (the collapse is fixed). PSX span = Δz / 0.19.
## Two configs: ALL emitters, then KEEP=[1,3] (the black+white DEMI cloud the DEMI2 doc isolated).
##
## Run (NEVER headless), from the package root:  godot --path . -s res://tools/probe_demi_bucket_spread.gd

const OTDepthPrimOrder = preload("res://addons/exmateria_effects/render/OTDepthPrimOrder.gd")

## ADR-0212 dec. 1 — `addons/exmateria_schema` used to declare six bare globals,
## every one of them generic English (`Fold`, `DepthMode`, `ColorStack`,
## `ColorRecipe`, `CellMarking`, `TerrainCell`). It now declares only
## `ExMateriaSchema`, so these lines are what keep the use sites below spelled the
## way they were (ADR-0211 dec. 4).
const DepthMode = ExMateriaSchema.DepthMode

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 46
const SEEKS := [26, 34, 42, 45]
const ALL_EMITTERS := 5
const PSX_UNITS_PER_BUCKET := DepthMode.UNITS_PER_OT_BUCKET   # the PSX-calibrated OT bucket width

# (label, kept-emitter list or null=all)
var _configs := [["ALL", null], ["CLOUD[1,3]", [1, 3]]]

var _scene: Node
var _f := 0
var _played := false
var _ci := 0
var _si := -1
var _wait := 0
var _quit := false

func _initialize() -> void:
	_scene = load(VIEWER).instantiate()
	root.add_child(_scene)
	RenderingServer.frame_post_draw.connect(_on_post_draw)
	print("[spread] booting EffectViewer, E%03d — measuring bucket span vs world-Z" % EFFECT_ID)
	print("[spread] BUCKET_COUNT=%d  frustum-bucket-width≈1.38u  PSX-bucket-width=%.2fu" % [
		OTDepthPrimOrder.BUCKET_COUNT, PSX_UNITS_PER_BUCKET])

func _process(_dt: float) -> bool:
	if _quit:
		quit()
		return true
	return false

func _on_post_draw() -> void:
	_f += 1
	if not _played:
		var driver := _scene.get_node_or_null("CombatCompositeDriver")
		var ready: bool = _scene.get("_caster") != null and _scene.get("_target") != null and driver != null
		if ready and _f > 20:
			_scene.call("play_effect", EFFECT_ID, true)
			_played = true
			_ci = 0
			_si = 0
			_apply()
		elif _f > 300:
			print("[spread] FAIL — never settled")
			_quit = true
		return

	if _ci >= _configs.size():
		return
	_wait -= 1
	if _wait <= 0:
		_measure()
		_si += 1
		if _si >= SEEKS.size():
			_si = 0
			_ci += 1
			if _ci >= _configs.size():
				print("[spread] done")
				_quit = true
				return
		_apply()

func _apply() -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff != null and is_instance_valid(eff):
		var keep = _configs[_ci][1]
		var dis: Dictionary = {}
		if keep != null:
			for k in range(ALL_EMITTERS):
				if not keep.has(k):
					dis[k] = true
		eff.call("set_debug_emitter_filter", dis)
		eff.call("seek", SEEKS[_si])
	_wait = 4

func _measure() -> void:
	var eff: Node = _scene.get("_current_effect")
	if eff == null or not is_instance_valid(eff):
		return
	var r = eff.get("sprite_renderer")
	if r == null:
		print("[spread] no sprite_renderer")
		return
	# #6.2: staging moved into the shared UnifiedPrimStager (r._stager).
	var depths: PackedFloat32Array = r._stager.depths()
	var modes: PackedInt32Array = r._stager.modes()
	var ages: PackedFloat32Array = r._stager.ages()
	var n: int = depths.size()
	var label = _configs[_ci][0]
	var seekf = SEEKS[_si]
	if n == 0:
		print("[spread] %-11s f%-2d : 0 prims" % [label, seekf])
		return

	var counts: Dictionary = {}     # bucket -> prim count
	var dmin := INF
	var dmax := -INF
	for i in range(n):
		var d: float = depths[i]
		dmin = minf(dmin, d)
		dmax = maxf(dmax, d)
		var b: int = OTDepthPrimOrder._bucket_of(d)
		counts[b] = int(counts.get(b, 0)) + 1

	var distinct: int = counts.size()
	var bkeys := counts.keys()
	bkeys.sort()
	var max_per: int = 0
	var multi: int = 0     # buckets holding >1 prim (where age tie-break fires)
	var tied_prims: int = 0
	for b in bkeys:
		var c: int = counts[b]
		max_per = maxi(max_per, c)
		if c > 1:
			multi += 1
			tied_prims += c

	# #212: _prim_depths is view-space Z in WORLD UNITS, so the span IS the world-Z extent.
	var dz_world: float = dmax - dmin
	var psx_buckets: float = dz_world / PSX_UNITS_PER_BUCKET

	print("[spread] %-11s f%-2d : prims=%-3d  OUR-buckets=%-3d (min=%d max=%d)  max/bucket=%d  multi-buckets=%d (tied_prims=%d)" % [
		label, seekf, n, distinct, int(bkeys[0]), int(bkeys[-1]), max_per, multi, tied_prims])
	print("          viewZ[%.4f..%.4f]  Δz_world=%.3fu  ⇒ PSX-buckets≈%.1f  OUR-buckets=%d (ratio ×%.2f)" % [
		dmin, dmax, dz_world, psx_buckets, distinct, (psx_buckets / float(maxi(distinct, 1)))])
	# histogram: bucket:count
	var hist := ""
	for b in bkeys:
		hist += " %d:%d" % [int(b), int(counts[b])]
	print("          hist(bucket:prims)%s" % hist)
