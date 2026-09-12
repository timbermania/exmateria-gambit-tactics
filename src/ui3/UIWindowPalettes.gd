class_name UIWindowPalettes
extends RefCounted
## Pre-baked FFT "backgrounded window" palettes (§15.21, RE round 17): when a window is sent to
## the background (a menu/screen takes focus over it), each element's CLUT swaps foreground→background.
## Colours are the ROM CLUTs decoded with the port's BGR555 expansion (c<<3)|(c>>2). idx0 = transparent.
## Keyed by the FOREGROUND clut each is the bg twin of. Used by DetailScene + FormationScene.

# bg of 0x7C3C (window body / text / labels / dark icons / frames)
const BG_FOR_7C3C: Array[Color] = [Color8(0,0,0,0),Color8(41,49,57),Color8(57,66,74),Color8(82,90,99),Color8(99,107,115),Color8(66,74,90),Color8(74,82,90),Color8(90,99,107),Color8(107,115,123),Color8(74,49,66),Color8(82,74,82),Color8(90,90,99),Color8(115,123,132),Color8(24,24,41),Color8(57,74,107),Color8(132,140,148)]
# bg of 0x7CBC (active/hilite label + alt frame)
const BG_FOR_7CBC: Array[Color] = [Color8(0,0,0,0),Color8(189,189,189),Color8(115,115,115),Color8(49,49,49),Color8(8,8,8),Color8(82,66,57),Color8(115,107,99),Color8(132,115,99),Color8(173,165,140),Color8(115,41,16),Color8(132,82,66),Color8(148,132,115),Color8(181,173,148),Color8(16,82,132),Color8(82,107,115),Color8(140,140,132)]
# bg of 0x7D7C (menu/lit icons + L2/R2 button caption)
const BG_FOR_7D7C: Array[Color] = [Color8(0,0,0,0),Color8(41,41,33),Color8(140,148,165),Color8(66,74,82),Color8(74,90,99),Color8(90,107,115),Color8(107,123,140),Color8(148,49,33),Color8(148,49,33),Color8(181,66,41),Color8(231,90,41),Color8(41,41,33),Color8(57,66,57),Color8(82,90,90),Color8(107,115,115),Color8(132,140,148)]

# FRAME (pre-baked RGB) nearest-index remap: fg = 0x7C3C display-space, bg = 0x7D3C display-space (Vector3 /255)
const FRAME_FG_7C3C: Array = [Vector3(0,0,0),Vector3(0.192,0.161,0.129),Vector3(0.322,0.322,0.259),Vector3(0.518,0.482,0.420),Vector3(0.612,0.580,0.482),Vector3(0.388,0.353,0.290),Vector3(0.451,0.420,0.353),Vector3(0.549,0.518,0.451),Vector3(0.647,0.612,0.518),Vector3(0.420,0.161,0.063),Vector3(0.482,0.290,0.224),Vector3(0.549,0.482,0.420),Vector3(0.678,0.647,0.549),Vector3(0.129,0.094,0.063),Vector3(0.451,0.420,0.322),Vector3(0.839,0.808,0.678)]
const FRAME_BG_7D3C: Array = [Vector3(0,0,0),Vector3(0.161,0.192,0.224),Vector3(0.224,0.259,0.290),Vector3(0.322,0.353,0.388),Vector3(0.388,0.420,0.451),Vector3(0.259,0.290,0.353),Vector3(0.290,0.322,0.353),Vector3(0.353,0.388,0.420),Vector3(0.420,0.451,0.482),Vector3(0.290,0.192,0.259),Vector3(0.322,0.290,0.322),Vector3(0.353,0.353,0.388),Vector3(0.451,0.482,0.518),Vector3(0.094,0.094,0.161),Vector3(0.224,0.290,0.420),Vector3(0.518,0.533,0.580)]

static func texture(colors: Array) -> ImageTexture:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, colors[i] if i < colors.size() else Color(0,0,0,0))
	return ImageTexture.create_from_image(img)
