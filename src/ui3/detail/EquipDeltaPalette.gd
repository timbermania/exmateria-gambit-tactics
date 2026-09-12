class_name EquipDeltaPalette
extends RefCounted

## The equip stat-DELTA colour CLUTs (FORMATION_SCREEN.md §15.26 / EQUIP_STAT_PREVIEW.md §5).
##
## A signed stat-delta digit must read as the SAME glyph as its plain neighbour — the
## denominator (vitals) or the plain stat value (stats band) — with only its MIDDLE (the
## bright body) recoloured by sign. The user's verdict: "identical to the denominator text,
## just a different colour in the middle; the border is identical."
##
## The FRAMEFONT number glyph is a 5-index cell: 0 = the cell GUTTER (transparent), 1 = the
## saturated ink core, 2 = its bright anti-alias, 3 = a darker anti-alias, 4 = the glyph's
## BACKGROUND-MATCHING FILL / outline. A plain digit renders through its neighbour's OWN
## number CLUT (MENU_CLUT for the vitals numerator; the 0x7C3C stat-label CLUT for the stats
## band), which is what gives it its border and shading.
##
## So we DON'T invent a foreign palette. We copy the neighbour's base CLUT and overwrite ONLY
## the ink body (indices 1·2) with the sign colour — every other entry (gutter, anti-alias
## tail, border, fill) is preserved bit-for-bit. The delta digit becomes "the plain digit
## with a coloured middle," which is exactly the ask.
##
## (This replaces the earlier FRAME-pal-15 index-BIAS approach — `pal15[(i+bias)&0xF]` with
## index 0/4 forced transparent — which produced foreign greys and dropped the border/fill.
## See the doc §5 reconciliation and commit history.)
##
## Vault: [[Equip Stat Delta Preview]]

## The glyph indices that carry the ink body — the "middle" the sign colour paints. Verified
## empirically against the real FRAMEFONT small-digit cells (index 1 = stroke core, 2 = its
## bright edge); 3·4 are the border/fill and stay the plain digit's colour.
const INK_INDICES := [1, 2]

# --- oracle-validated sign colours -------------------------------------------------------
# Stats band: dark-ink digits on the tan 0x7C3C label frame. The ROM index-biases the delta
# into FRAME.BIN palette 15; the framebuffer-sampled primaries are [13] blue / [9] red. These
# read as coloured strokes on the tan ground.
const STATS_BLUE := Color8(16, 82, 132)    # FRAME pal 15 [13], positive delta
const STATS_RED := Color8(107, 41, 16)     # FRAME pal 15 [9],  negative delta
# Vitals numerator: bright-ink digits on the dark vitals frame. Positive is the ROM's sampled
# cyan (VRAM CLUT 0x774C). Negative isn't oracle-pinned — a bright red symmetric to the cyan,
# chosen for legibility on the dark frame (the dark FRAME-pal-15 red would vanish there).
const VITALS_CYAN := Color8(96, 208, 232)  # sampled 0x774C, positive delta
const VITALS_RED := Color8(232, 96, 96)    # bright red, negative delta (legibility, not oracle)


## Copy `base` (a 16-entry number CLUT — Array or PackedColorArray) and recolour the ink
## indices to `ink`, leaving every other entry untouched. The result is the plain digit's own
## palette with only its bright body repainted — same border, shading, fill, and gutter.
static func recolour(base, ink: Color, ink_indices: Array = INK_INDICES) -> Array:
	var out: Array = []
	for c in base:
		out.append(c)
	for idx in ink_indices:
		if idx >= 0 and idx < out.size():
			out[idx] = ink
	return out


## A 16×1 index→RGBA CLUT texture from 16 Colors — the shape UIMenuText.mount_number binds
## as `palette`. Entries past the source array (or a transparent source entry) render
## transparent, matching the font's transparent background.
static func texture(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)
