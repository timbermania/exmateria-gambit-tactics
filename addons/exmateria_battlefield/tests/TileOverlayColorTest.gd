extends Node
## Guards TileOverlayColor — the CPU barber-pole port that lets a flat_fill tile overlay route as a
## single-color vertex_flat quad (COMPOSITOR_INPUT_CONTRACT_GENERALIZATION.md §4a). Locks the pieces
## that must stay byte-identical to tile_overlay.gdshaderinc `tile_overlay_color`: the discrete
## 15-phase rotation `rot = ((idx-1+phase)%15)+1`, the phase clock, the palette lookup, and the
## gamma / mono / tint modulation. A drift here silently recolors every routed placement tile.
##
## Run: <GODOT> --path . --quit-after 4 res://addons/exmateria_battlefield/tests/TileOverlayColorTest.tscn

const Color2 = preload("res://addons/exmateria_battlefield/overlay/TileOverlayColor.gd")

# COUNTERS, not a bare bool — gained in the move commit, the ADR-0194 dec. 12 arm 2
# convention this ledger already applied to DepthModeTest and TileCursorCompositorTest.
# A `[PASS]` printed off `not _failed` is true of a run that asserted NOTHING, and a
# GDScript runtime error aborts only its ENCLOSING function while `_ready` carries on —
# so the verdict below pins the TOTAL, not just the absence of failures.
var _passed := 0
var _failed := 0


func _check(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
	else:
		print("[FAIL] %s" % msg)
		_failed += 1


func _ready() -> void:
	_test_phase_clock()
	_test_rotation_permutation()
	_test_lookup_raw_mono_tint()
	print("\n=== TileOverlayColorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _passed == 0:
		print("[FAIL] TileOverlayColorTest: ran zero assertions")
	elif _failed:
		print("[FAIL] TileOverlayColor test")
	else:
		print("[PASS] TileOverlayColor: phase clock, 15-phase rotation permutation, palette lookup + raw/mono/tint (no pow)")
	get_tree().quit()


## phase = manual when frozen (>=0, wrapped to 0..14), else int(mod(time*rate, 15)).
func _test_phase_clock() -> void:
	_check(Color2.phase_at(0.0, 15.0, 3) == 3, "manual_phase freezes at 3")
	_check(Color2.phase_at(999.0, 15.0, 17) == 2, "manual_phase wraps (17 % 15 == 2)")
	_check(Color2.phase_at(0.0, 15.0, -1) == 0, "t=0 -> phase 0")
	_check(Color2.phase_at(0.5, 15.0, -1) == 7, "t=0.5 * 15/s -> phase 7 (int(7.5))")
	_check(Color2.phase_at(1.0, 15.0, -1) == 0, "t=1.0 wraps a full 15-cycle back to 0")


## The barber-pole is a permutation of entries 1..15 (idx 0 pinned). rot = ((idx-1+phase)%15)+1.
## At phase 0 it's identity; each phase shifts by one; entries stay within 1..15; it's a bijection.
func _test_rotation_permutation() -> void:
	var pal := _ramp_palette()   # row 0 = a 0..15 grayscale ramp so rot is directly observable
	# phase 0 -> identity (rot == flat_index): the sampled gray == flat_index/15.
	for idx in range(1, 16):
		var c := Color2.flat_color(pal, 0, idx, 1, 0, false, Color.WHITE)
		_check(is_equal_approx(c.r, float(idx) / 15.0), "phase 0: idx %d maps to itself" % idx)
	# phase 1 -> each index shifts up by one within 1..15 (15 wraps to 1).
	_check(is_equal_approx(Color2.flat_color(pal, 0, 5, 1, 1, false, Color.WHITE).r, 6.0 / 15.0),
		"phase 1: idx 5 -> 6")
	_check(is_equal_approx(Color2.flat_color(pal, 0, 15, 1, 1, false, Color.WHITE).r, 1.0 / 15.0),
		"phase 1: idx 15 wraps -> 1")
	# The 15 phases of one index visit all of 1..15 exactly once (bijective cycle).
	var seen := {}
	for phase in range(15):
		var rot := int(round(Color2.flat_color(pal, 0, 3, 1, phase, false, Color.WHITE).r * 15.0))
		seen[rot] = true
	_check(seen.size() == 15, "one index visits all 15 entries across the 15 phases (bijection)")
	# anim_mode 0 = static (no rotation): rot == flat_index at every phase.
	_check(is_equal_approx(Color2.flat_color(pal, 0, 5, 0, 9, false, Color.WHITE).r, 5.0 / 15.0),
		"anim_mode 0: no rotation (idx 5 stays 5 regardless of phase)")


## Lookup + mono + tint. RAW display-space (ADR-0074 endgame): NO pow(gamma) — the routed tile adds
## the CLUT value straight (mirror formation_box_fold). Only mono value-collapse + tint remain.
func _test_lookup_raw_mono_tint() -> void:
	var pal := _known_palette()   # row 0, entry 4 ~= (0.5, 0.25, 0.0, 1.0) after 8-bit quantization
	var base := pal.get_pixel(4, 0)   # read the ACTUAL stored value (RGBA8 rounds 0.5 -> 128/255)
	# raw, no mono, white tint: each channel is the RAW CLUT value (no pow), alpha untouched.
	var g := Color2.flat_color(pal, 0, 4, 0, 0, false, Color.WHITE)
	_check(is_equal_approx(g.r, base.r) and is_equal_approx(g.b, base.b),
		"raw: each channel is the CLUT value, no pow(gamma)")
	_check(is_equal_approx(g.a, 1.0), "alpha = base.a * tint.a (coverage preserved)")
	# mono: all channels collapse to the max (raw, no gamma).
	var m := Color2.flat_color(pal, 0, 4, 0, 0, true, Color.WHITE)
	var mx: float = base.r   # r is the max channel here
	_check(is_equal_approx(m.r, mx) and is_equal_approx(m.g, mx) and is_equal_approx(m.b, mx),
		"mono: all channels collapse to the brightness (max)")
	# tint modulates rgb and alpha.
	var t := Color2.flat_color(pal, 0, 4, 0, 0, false, Color(0.5, 1.0, 1.0, 0.5))
	_check(is_equal_approx(t.r, base.r * 0.5) and is_equal_approx(t.a, base.a * 0.5),
		"tint modulates rgb and alpha")


# A 16x1 grayscale ramp on row 0: entry i = (i/15, i/15, i/15, 1). Makes rot directly observable.
func _ramp_palette() -> Image:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in range(16):
		var v := float(i) / 15.0
		img.set_pixel(i, 0, Color(v, v, v, 1.0))
	return img


# A 16x1 palette whose entry 4 is a known non-gray color for the gamma/mono/tint checks.
func _known_palette() -> Image:
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(4, 0, Color(0.5, 0.25, 0.0, 1.0))
	return img
