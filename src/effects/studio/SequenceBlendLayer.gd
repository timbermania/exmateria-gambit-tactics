extends Control
## ONE blend group's quads of one sequence cell, on a CanvasItem of its own (ADR-0103
## dec. 7).
##
## THIS NODE EXISTS BECAUSE OF ONE GODOT FACT: blending lives on `CanvasItemMaterial`,
## which is **per-CanvasItem, not per-draw-call**. A cell whose frames mix ADD and SUB
## cannot draw both on the host, so the sprite moves off the host and onto one child per
## distinct mode — while the host keeps its background, its border and its crosshair at
## normal blend, where they belong.
##
## Affordable only because of the corpus: **95.3% of cells need exactly one layer**, and of
## the 4.72% that mix, every common mix is a pair. Build the loop, cost it at one.
##
## Colour cannot ship without this. 93.5% of corpus frames are additive and 35.9% of
## colour-enabled emitters drive their resolved colour to ≤8/255 somewhere in the life —
## additive at `src → 0` is the particle VANISHING, and drawn flat-opaque the same moment
## is a black silhouette on grey. Tinting without blending would make the strip LESS
## truthful than the white it drew before, for more than a third of emitters.
##
## No `class_name` (ADR-0004).

const SpritePainter = preload("res://src/effects/studio/SequenceSpritePainter.gd")

var _key: int = SpritePainter.BLEND_ALL
var _entry: Dictionary = {}
var _framesets: Array = []
var _box := Rect2i()
var _texture: Texture2D = null
var _inset: float = 0.0
var _modulate := Color.WHITE
var _alpha: float = 1.0


func _init() -> void:
	# The host owns the click (a thumbnail click parks the player); a layer is paint only.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# NEAREST does NOT inherit usefully here — a layer is a child of a Control that sets
	# it, and PARENT_NODE is the default, but stating it keeps a reparented layer honest.
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Point this layer at one blend group. The material is SHARED across every layer on the
## same group (`SpritePainter.material_for`), so a 36-row strip holds five materials, not
## thirty-six.
func set_blend_key(key: int) -> void:
	if _key == key and material != null:
		return
	_key = key
	material = SpritePainter.material_for(key)
	_alpha = SpritePainter.blend_alpha(key)
	queue_redraw()


## The same state `SequenceSpritePainter.paint` takes, except for two deliberate
## differences. No CLIP: a sprite cannot escape its rect by construction (`box` is the
## union of every step's extent), so only the crosshair on the host needs one. And an
## INSET rather than a fit — the layer is `PRESET_FULL_RECT` over its host, so it derives
## the fit from its own live size, which is what keeps a resized host from needing to
## re-push state it has not changed.
func paint_state(entry: Dictionary, framesets: Array, box: Rect2i, texture: Texture2D,
		inset: float, modulate: Color) -> void:
	_entry = entry
	_framesets = framesets
	_box = box
	_texture = texture
	_inset = inset
	_modulate = modulate
	queue_redraw()


## The CUT's per-frame push. Separated from `paint_state` because the tint moves every
## game frame while the strip's loops run and the STRUCTURE moves only on a re-decode —
## re-syncing layers at 30Hz to change one colour is work for nothing.
func set_tint(modulate: Color) -> void:
	if _modulate == modulate:
		return
	_modulate = modulate
	queue_redraw()


func _draw() -> void:
	var fit: Dictionary = SpritePainter.fit(_box, Rect2(Vector2.ZERO, size).grow(-_inset))
	SpritePainter.paint_quads(self, _entry, _framesets, _box, _texture, fit,
		_alpha, _modulate, _key)


## Stand up exactly the layers `entry` needs under `host`, in blend order, and push the
## paint state into each. `layers` is the host's own list (it owns the lifetime); the
## updated list comes back.
##
## THE HOST'S LIST, not a scan of `get_children()`: a host has other children (the film
## strip's rows sit in a container, the player carries its chrome), and identifying layers
## by type would need a `class_name` this repo does not use. An explicit list is also the
## thing that makes "how many layers is this cell using" answerable from a test.
static func sync(host: Control, layers: Array, entry: Dictionary, framesets: Array,
		box: Rect2i, texture: Texture2D, inset: float, modulate: Color) -> Array:
	var keys: Array = SpritePainter.blend_keys(entry, framesets)
	while layers.size() > keys.size():
		var dead: Control = layers.pop_back()
		host.remove_child(dead)
		dead.queue_free()
	while layers.size() < keys.size():
		var fresh = (load("res://src/effects/studio/SequenceBlendLayer.gd") as Script).new()
		layers.append(fresh)
		host.add_child(fresh)
	for i in range(keys.size()):
		layers[i].set_blend_key(int(keys[i]))
		layers[i].paint_state(entry, framesets, box, texture, inset, modulate)
	return layers
