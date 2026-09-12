extends RefCounted
## The ONE shared human-label map for the 11 PSX Color modes (ADR-0087) — codes 0-10 as
## reduced by ColorRecipe.from_mode (the ADR-0067 unified colour model). Both the screen
## Blend-mode row (ScreenTweenProjector) and the palette tint's blend-mode selector
## (PaletteTweenProjector) read this, so they cannot drift to different words for the same
## op (a consequence the ADR calls out explicitly).
##
## The SOURCE axis is IN the label. Every op is either additive/luma over the colour-so-far
## (modes 0/1/2/3) or over the committed BASE (modes 4/5/6/7/9 — the idempotent variants the
## #164 fix relies on, so repetition lands on base+delta not base+N·delta); the base-source
## ones carry an "over base" suffix. The two restores (8/10) ignore the Δ entirely and name
## the reset. Code 9 is a real byte semantically ≡ 4 (from_mode maps both to affine_base add).
##
## The strong/subtle split on the luma desaturate pair follows the div: mode 2/6 use div 6
## (a luminance-preserving greyscale — the STRONG desaturate) and mode 3/12 use div 12 (a
## half-luminance, dimmer wash — the SUBTLE one). No `class_name` (ADR-0004).

# code → human label. Keyed 0..10; the source distinction lives in the string.
const _LABELS := {
	0: "Add",
	1: "Dim ½ + Add",
	2: "Desaturate (strong)",
	3: "Desaturate (subtle)",
	4: "Add over base",
	5: "Dim ½ + Add over base",
	6: "Desaturate (strong) over base",
	7: "Desaturate (subtle) over base",
	8: "Reset to base",
	9: "Add over base",
	10: "Reset",
}

# The number of distinct mode codes (0..10 inclusive).
const COUNT := 11


## The human label for one mode code. An out-of-range code falls back to a raw tag so a
## malformed byte is still legible rather than silently blank.
static func label(code: int) -> String:
	return _LABELS.get(code, "Mode %d" % code)


## All 11 modes in code order as value-carrying enum choices ({value, label}) — the shape
## the `enum` editor consumes (item id == code). One source for both projectors' selectors.
static func choices() -> Array:
	var out: Array = []
	for code in range(COUNT):
		out.append({"value": code, "label": label(code)})
	return out
