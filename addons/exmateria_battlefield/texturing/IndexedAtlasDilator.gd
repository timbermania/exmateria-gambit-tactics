extends RefCounted

## Edge-padding / texture dilation for the indexed terrain atlas.
##
## The map seam ("background sliver between polygons") is a covered fragment at a texture
## patch EDGE sampling a transparent index-0 texel that lives INSIDE its own patch (proven
## cyan by the indexed_color shader diagnostic). No UV nudge can fix it — there's no opaque
## pixel at that UV. So we fix the TEXTURE: bleed each patch's opaque palette indices
## outward into the transparent border texels, so the edge fragment samples an opaque index
## instead of a hole. This is the user's "impute the outer color as the nearest pixel
## WITHIN" — done in index space.
##
## EXACT indices are copied from the nearest opaque neighbor (never blended), so the crisp
## PSX nearest-neighbor look is untouched. Atlas encoding: R channel = palette index
## (shader reads `indexed.r * 15`); index 0 (R==0) is the transparent-black slot.

# 8-connected neighborhood, axis-first so a transparent texel prefers an edge neighbor
# (closer) over a diagonal one when both are opaque.
const _NEIGHBORS: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1),
	Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1),
]


## Return a dilated copy of `src`: each transparent (index-0) texel that touches an opaque
## neighbor takes that neighbor's exact pixel. `passes` widens the bleed by one texel each
## (0 = unchanged copy). Fully-surrounded transparent regions are left transparent.
static func dilate(src: Image, passes: int) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var out := Image.create(w, h, false, src.get_format())
	out.copy_from(src)
	if passes <= 0 or w == 0 or h == 0:
		return out

	for _p in range(passes):
		# Read from a snapshot so fills within one pass don't cascade (true simultaneous
		# dilation — one texel of growth per pass, deterministic regardless of scan order).
		var prev := Image.create(w, h, false, out.get_format())
		prev.copy_from(out)
		for y in range(h):
			for x in range(w):
				if not _is_transparent(prev, x, y):
					continue
				for offset in _NEIGHBORS:
					var nx := x + offset.x
					var ny := y + offset.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					if _is_transparent(prev, nx, ny):
						continue
					out.set_pixel(x, y, prev.get_pixel(nx, ny))
					break
	return out


## A texel is transparent iff its palette index is 0 (R channel == 0). Index 5, say, encodes
## as R = 5/15 -> r8 = 85, so only the transparent-black slot reads r8 == 0.
static func _is_transparent(img: Image, x: int, y: int) -> bool:
	return img.get_pixel(x, y).r8 == 0
