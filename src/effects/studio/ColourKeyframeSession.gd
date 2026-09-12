extends RefCounted
## The colour-keyframe EDIT SESSION (ADR-0089 colour-keyframe amendment, decisions 5/7/8).
## Owns the joint colour keyframes for one emitter. Keyframes are the authoring layer; the
## dense 160-sample curves stay the compiled artifact the renderer paints from.
##
##   • begin(effect_data, emitter_index[, gamut]) — resolve the emitter's representative texel
##     S (EmitterSpriteColor) and IMPORT keyframes fitted to the emitter's current curves
##     (ColourKeyframeFit), so entering keyframe mode causes no jump.
##   • place / move / delete — joint colour-at-a-frame edits, kept sorted; placed colours are
##     clamped into the UNIT CUBE, which is the whole of what a curve sample can hold.
##   • apply() — compile the keyframes down (linear lerp) into the emitter's three colour
##     curves, in place.
##   • renders_as(frame) — what the multiply actually produces there, `S ⊙ curve`. The picker
##     shows it beside the swatch; it is the only place S is still consulted.
##
## THE KEYFRAME COLOUR IS THE CURVE, NOT THE OUTPUT (2026-08-21, ADR-0089 decision 4 amended
## a second time). It used to be the muxed target `T = S ⊙ curve`, clamped into the reachable
## box, and the author picked in that space — which meant that for 97.5% of the 3213 corpus
## colour emitters no channel's byte slider could hold 255, so *"I am not able to reach every
## [0,0,0] to [255,255,255]"* was literally true of the control. S still bounds what RENDERS
## (a multiply can never add a channel the sprite lacks) and that has not changed and cannot;
## what changed is that the bound is now REPORTED (`renders_as`, `dead_channels`) instead of
## silently applied to the author's pick.
##
## It used to FORK first: on the first edit it appended three independent curves and repointed
## the emitter at them, so it would never mutate a curve another emitter referenced. That
## copy-on-write is dead under the ADR-0089 curve-ownership amendment — the explode at load has
## already given every use site its own private curve, unconditionally, so there is nothing
## left to fork and a fork here would only append a duplicate of a curve nobody else can see.
##
## Live-preview repaint is the host's job (studio_apply_edit → refresh_render_emitter_caches).
## The game-JSON persistence is ColourKeyframeSaver. The byte-exact BIN pack + dedup is the
## deferred compiler.
##
## No `class_name` (ADR-0004) — preloaded by path.

const EffectCurve = ExMateriaEffects.EffectCurve

const ColourMux = preload("res://src/effects/studio/ColourMux.gd")
const ColourKeyframeFit = preload("res://src/effects/studio/ColourKeyframeFit.gd")
const EmitterSpriteColor = preload("res://src/effects/studio/EmitterSpriteColor.gd")
const EffectCurveClass = ExMateriaEffects.EffectCurve
const CurveExplode = ExMateriaEffects.CurveExplode
const LifeWindow = preload("res://src/effects/studio/EmitterLifeWindow.gd")

## Sentinel gamut: "derive from the emitter's representative sprite texel" (the normal path).
## The gamut no longer clamps anything — it is what `renders_as` muxes with and what
## `dead_channels` reports.
const AUTO_GAMUT := Color(-1, -1, -1, -1)

var _effect_data = null
var _emitter_index: int = -1
var _gamut: Color = Color.WHITE
var _keyframes: Array = []  # [{frame:int, color:Color}] sorted ascending by frame


## Enter keyframe mode on `emitter_index`: resolve the gamut and import keyframes from the
## emitter's current colour curves.
func begin(effect_data, emitter_index: int, gamut: Color = AUTO_GAMUT) -> void:
	_effect_data = effect_data
	_emitter_index = emitter_index
	_gamut = gamut if gamut != AUTO_GAMUT else EmitterSpriteColor.representative(effect_data, emitter_index)
	_keyframes = _import_keyframes()


## The representative sprite texel S — the gamut the render is bounded by, NOT the authoring
## range. Test / UI seam.
func gamut() -> Color:
	return _gamut


func keyframe_count() -> int:
	return _keyframes.size()


## The keyframes as {frame, color}, sorted. The ribbon/sparkline scaffolding reads this.
func keyframes() -> Array:
	return _keyframes


## Place (or replace) a joint colour keyframe at `frame`. The colour IS the curve triple,
## clamped only into the unit cube — every value in it is a byte the packer can write, so
## nothing an author can express is refused here.
func place(frame: int, curve: Color) -> void:
	var c := ColourMux.clamp_unit(curve)
	for kf in _keyframes:
		if int(kf["frame"]) == frame:
			kf["color"] = c
			return
	_keyframes.append({"frame": frame, "color": c})
	_sort()


## Move the keyframe at `index` to `new_frame` (colour preserved). Merges onto an existing
## keyframe at the destination frame.
func move(index: int, new_frame: int) -> void:
	if index < 0 or index >= _keyframes.size():
		return
	var col: Color = _keyframes[index]["color"]
	_keyframes.remove_at(index)
	place(new_frame, col)


## Delete the keyframe at `index`.
func delete(index: int) -> void:
	if index < 0 or index >= _keyframes.size():
		return
	_keyframes.remove_at(index)


## The CURVE colour at `frame` — what a NEW keyframe inherits so adding one changes nothing
## until it is recoloured, and what the picker's swatch is seeded from.
func curve_at(frame: int) -> Color:
	return ColourKeyframeFit.curve_at(_keyframes, frame)


## What the particle actually RENDERS at `frame`: `S ⊙ curve`, the same multiply the shader and
## the ribbon do. The picker shows this beside the swatch, so the author sees both the value
## they are authoring and the colour the sprite can make of it — the pair the old design
## collapsed into one silently-clamped swatch.
func renders_as(frame: int) -> Color:
	return ColourMux.mux(curve_at(frame), _gamut)


## Which channels the sprite has no light in (S.k == 0) — no curve value can render there.
## Reported, never enforced: the curve is still authored and still saved, it simply multiplies
## by zero. 4.2% of corpus colour emitters have at least one.
func dead_channels() -> Dictionary:
	return {
		"r": 1 if _gamut.r <= 0.0 else 0,
		"g": 1 if _gamut.g <= 0.0 else 0,
		"b": 1 if _gamut.b <= 0.0 else 0,
	}


## Index of the keyframe at exactly `frame`, or -1.
func index_of_frame(frame: int) -> int:
	for i in range(_keyframes.size()):
		if int(_keyframes[i]["frame"]) == frame:
			return i
	return -1


## Add a keyframe at `frame` seeded with the colour already there (a visual no-op until
## recoloured). Returns its index; an existing keyframe at that frame is returned as-is.
func add(frame: int) -> int:
	var existing := index_of_frame(frame)
	if existing >= 0:
		return existing
	place(frame, curve_at(frame))
	return index_of_frame(frame)


## Compile the keyframes into the emitter's three colour curves. They are PRIVATE to this
## emitter (ADR-0089 curve-ownership amendment), so writing them in place moves nothing else.
func apply() -> void:
	if _effect_data == null or _emitter_index < 0:
		return
	var em = _effect_data.emitters[_emitter_index]
	var compiled: Dictionary = ColourKeyframeFit.compile_to_curves(_keyframes)
	for chan in ["r", "g", "b"]:
		# A channel with NO curve gains one here — the identity mint (decision 5), the same
		# one the picker uses. The fork this replaced always created three curves, so an
		# emitter whose colour channels were empty could still be authored; without the mint
		# the compile would silently write nowhere.
		_write_curve(CurveExplode.mint_identity(_effect_data, _emitter_index, chan, "colour"),
			compiled[chan])


# --- internals -------------------------------------------------------------

func _write_curve(idx: int, values) -> void:
	if idx < 0 or idx >= _effect_data.curves.size():
		return
	var out: Array[float] = []
	out.resize(values.size())
	for i in range(values.size()):
		out[i] = float(values[i])
	_effect_data.curves[idx].samples = out


func _import_keyframes() -> Array:
	var em = _effect_data.emitters[_emitter_index]
	var cr = _curve_of(int(em.color_curves.get("r", -1)))
	var cg = _curve_of(int(em.color_curves.get("g", -1)))
	var cb = _curve_of(int(em.color_curves.get("b", -1)))
	# THE LIFE SPLITS THE KEYFRAME BUDGET (2026-08-21). Every one of the 160 samples is still
	# fitted; `life_n` only stops the dead zone spending the budget the live window needs. It
	# belongs HERE rather than in the fit because this is the layer that has an emitter to
	# resolve a life from — `EmitterLifeWindow` is the ONE derivation of it (CONTEXT.md
	# *Colour dead zone*), and a second copy would decide the same emitter's axis twice.
	var life_n: int = int(LifeWindow.resolve(_effect_data, _emitter_index).get("n", -1))
	var fit: Dictionary = ColourKeyframeFit.import_from_curves(cr, cg, cb, life_n)
	return fit["keyframes"]


func _curve_of(idx: int) -> EffectCurve:
	if idx >= 0 and idx < _effect_data.curves.size():
		return _effect_data.curves[idx]
	return EffectCurveClass.from_array(_zeros(), idx)


func _sort() -> void:
	_keyframes.sort_custom(func(a, b): return int(a["frame"]) < int(b["frame"]))


func _zeros() -> Array:
	var a: Array = []
	a.resize(160)
	a.fill(0.0)
	return a
