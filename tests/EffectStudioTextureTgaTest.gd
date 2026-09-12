extends Node
## TDD guard for the studio-side TGA codec (#280, ADR-0096/0097).
##
## #280's round-trip format is an RGBA .tga matching
## `godot-learning/tools/extract_effect_texture.lua` EXACTLY. Godot can read TGA
## (`Image.load_tga_from_buffer`) but cannot write one, and the studio owns both
## directions, so the layout is hand-written here: an 18-byte header, image type
## 2 (uncompressed true-colour), 32 bpp, descriptor 0x28 (top-left origin, 8
## alpha bits), then BGRA texel bytes.
##
## The ORACLE is independent of this code: `res://assets/effects/E019/texture.tga`
## was produced by the Lua extractor, and `texture_palette.json` beside it holds
## the sheet's palette as [r, g, b, stp] rows. A decode that disagrees with
## either is wrong regardless of what the encoder does.
##
## Alpha carries the STP bit, never opacity (ADR-0096): STP=0 -> 255, STP=1 -> 128.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectStudioTextureTgaTest.tscn

const Tga = preload("res://src/effects/studio/TextureTga.gd")

const E019_TGA := "res://assets/effects/E019/texture.tga"
const E019_PALETTE := "res://assets/effects/E019/texture_palette.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_decodes_the_lua_extractors_own_output()
	_test_every_decoded_texel_is_a_palette_colour_with_stp_carried_in_alpha()
	_test_encode_reproduces_the_lua_extractors_bytes_exactly()
	_test_encode_writes_the_agreed_header_literals()
	_test_a_bottom_left_origin_file_is_flipped_not_read_upside_down()
	_test_a_24_bit_file_is_refused_with_a_reason()
	_test_an_rle_file_decodes_to_the_same_texels_as_its_uncompressed_twin()
	_test_rle_runs_cross_scanlines_and_a_trailing_footer_is_ignored()
	_test_a_bottom_left_origin_rle_file_is_also_flipped()

	print("\n=== EffectStudioTextureTgaTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] EffectStudioTextureTgaTest")
		get_tree().quit(1)
	else:
		print("[PASS] EffectStudioTextureTgaTest")
		get_tree().quit(0)


func _test_decodes_the_lua_extractors_own_output() -> void:
	var raw := _read(E019_TGA)
	var img: Dictionary = Tga.decode(raw)

	_assert_true(img.get("ok", false), "E019 texture.tga decodes")
	_assert_eq(img.get("width", 0), 128, "E019 width")
	_assert_eq(img.get("height", 0), 256, "E019 height")
	_assert_eq(img.get("pixels", PackedByteArray()).size(), 128 * 256 * 4,
		"one RGBA quad per texel")


func _test_every_decoded_texel_is_a_palette_colour_with_stp_carried_in_alpha() -> void:
	var img: Dictionary = Tga.decode(_read(E019_TGA))
	var pixels: PackedByteArray = img.get("pixels", PackedByteArray())

	# The palette is the independent oracle: [r, g, b, stp] rows straight off the
	# BIN, produced by parse_effect, not by this codec.
	#
	# Compared in 5-BIT space deliberately. parse_effect's `extract_palette`
	# expands a channel by bit replication ((v << 3) | (v >> 2), full 0-255)
	# while the TGA path truncates (v * 8, 0-248) — two different expansions of
	# the same bits, so an 8-bit comparison would fail on colour values that are
	# in fact identical. The 5 bits actually stored in the BIN are the truth.
	var palette: Array = JSON.parse_string(FileAccess.get_file_as_string(E019_PALETTE))
	var legal := {}
	for entry in palette:
		legal["%d,%d,%d,%d" % [int(entry[0]) >> 3, int(entry[1]) >> 3,
			int(entry[2]) >> 3, int(entry[3])]] = true

	var strays := 0
	for i in range(0, pixels.size(), 4):
		var stp: int = 1 if pixels[i + 3] < 255 else 0
		var key := "%d,%d,%d,%d" % [pixels[i] >> 3, pixels[i + 1] >> 3, pixels[i + 2] >> 3, stp]
		if not legal.has(key):
			strays += 1
	_assert_eq(strays, 0, "every texel is a palette colour with STP carried in alpha")


func _test_encode_reproduces_the_lua_extractors_bytes_exactly() -> void:
	var raw := _read(E019_TGA)
	var img: Dictionary = Tga.decode(raw)

	var out: PackedByteArray = Tga.encode(
		int(img["width"]), int(img["height"]), img["pixels"])

	_assert_eq(out.size(), raw.size(), "re-encoded size")
	var differing := 0
	for i in range(min(out.size(), raw.size())):
		if out[i] != raw[i]:
			differing += 1
	_assert_eq(differing, 0, "re-encode is byte-identical to the Lua extractor's file")


func _test_encode_writes_the_agreed_header_literals() -> void:
	var pixels := PackedByteArray()
	pixels.resize(2 * 3 * 4)
	var out: PackedByteArray = Tga.encode(2, 3, pixels)

	_assert_eq(out.size(), 18 + 2 * 3 * 4, "18-byte header then BGRA texels")
	_assert_eq(out[2], 2, "image type 2 (uncompressed true-colour)")
	_assert_eq(out[12] | (out[13] << 8), 2, "width little-endian")
	_assert_eq(out[14] | (out[15] << 8), 3, "height little-endian")
	_assert_eq(out[16], 32, "32 bits per pixel")
	_assert_eq(out[17], 0x28, "descriptor: top-left origin, 8 alpha bits")


func _test_a_bottom_left_origin_file_is_flipped_not_read_upside_down() -> void:
	# Bottom-left origin (descriptor bit 5 clear) is the TGA default in
	# Photoshop/GIMP/Aseprite, so an artist's save will routinely arrive that
	# way. Ignoring the bit reads the sheet upside down — silent corruption of
	# every texel's position. Two rows of one texel, distinguishable by red.
	var top_left := Tga.encode(1, 2, PackedByteArray([10, 0, 0, 255, 20, 0, 0, 255]))
	var bottom_up := top_left.duplicate()
	bottom_up[17] = 0x08                       # 8 alpha bits, origin bit CLEAR
	bottom_up[18] = 0                          # row 0 in the file is now the
	bottom_up[19] = 0                          # BOTTOM row: B,G,R,A = red 20
	bottom_up[20] = 20
	bottom_up[21] = 255
	bottom_up[22] = 0
	bottom_up[23] = 0
	bottom_up[24] = 10
	bottom_up[25] = 255

	var img: Dictionary = Tga.decode(bottom_up)

	_assert_true(img.get("ok", false), "bottom-left origin decodes")
	var px: PackedByteArray = img.get("pixels", PackedByteArray())
	_assert_eq(px[0], 10, "first row back in top-left order")
	_assert_eq(px[4], 20, "second row back in top-left order")


func _test_a_24_bit_file_is_refused_with_a_reason() -> void:
	# A 24-bit save carries no alpha, so every texel would silently claim STP=0
	# (ADR-0096). Refuse and say so rather than flattening the sheet's
	# semi-transparency.
	var raw := Tga.encode(1, 1, PackedByteArray([1, 2, 3, 255]))
	raw[16] = 24

	var img: Dictionary = Tga.decode(raw)

	_assert_true(not img.get("ok", true), "24-bit is refused")
	_assert_true(String(img.get("error", "")).contains("32-bit"),
		"the refusal names the required format")


func _test_an_rle_file_decodes_to_the_same_texels_as_its_uncompressed_twin() -> void:
	# Image type 10 is RLE true-colour — the DEFAULT in several editors' TGA export, so an
	# artist's re-save routinely arrives compressed (the real report: a 128x128 sheet that
	# came back 14,338 B instead of 65,554). It is lossless, so the only correct answer is
	# to decompress it, not to refuse it. The uncompressed twin is the oracle.
	var pixels := PackedByteArray()
	for i in range(8):
		pixels.append_array(PackedByteArray([i * 10, 0, 0, 255]))    # 8 distinct texels, RGBA
	var flat := Tga.encode(4, 2, pixels)

	# Re-packetise the flat file's OWN texel bytes, so the two files differ only in
	# framing. (Packets carry on-disk BGRA, which `encode` has already produced —
	# hand-writing RGBA here would test the fixture, not the decoder.)
	var body := flat.slice(18)
	var rle := _rle_header(4, 2, 0x28)
	rle.append_array(_raw_packet(body.slice(0, 4 * 4)))              # row 0: 4 literals
	rle.append_array(_raw_packet(body.slice(4 * 4, 8 * 4)))          # row 1: 4 literals

	var from_rle: Dictionary = Tga.decode(rle)
	var from_flat: Dictionary = Tga.decode(flat)
	_assert_true(from_rle.get("ok", false),
		"an RLE file decodes: %s" % from_rle.get("error", ""))
	_assert_eq(from_rle.get("width", 0), 4, "RLE width")
	_assert_eq(from_rle.get("height", 0), 2, "RLE height")
	_assert_eq(from_rle.get("pixels", PackedByteArray()),
		from_flat.get("pixels", PackedByteArray()),
		"RLE decodes to exactly the texels its uncompressed twin does")


func _test_rle_runs_cross_scanlines_and_a_trailing_footer_is_ignored() -> void:
	# Two things measured on the real file that a naive decoder gets wrong:
	#   1. Packets do NOT stop at row ends — its longest run was 128, a full row's width,
	#      with boundaries unaligned to rows. Decode into a FLAT texel buffer.
	#   2. It carries a 26-byte TGA 2.0 footer ("TRUEVISION-XFILE."). Stop after
	#      width*height texels; do not read to EOF.
	var rle := _rle_header(2, 2, 0x28)
	rle.append_array(_run_packet(PackedByteArray([0, 0, 7, 255]), 4))   # BGRA; ONE run spans both rows
	rle.append_array(PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0]))
	rle.append_array("TRUEVISION-XFILE.".to_ascii_buffer())
	rle.append(0)

	var img: Dictionary = Tga.decode(rle)

	_assert_true(img.get("ok", false),
		"a run spanning scanlines + a TGA 2.0 footer decodes: %s" % img.get("error", ""))
	var px: PackedByteArray = img.get("pixels", PackedByteArray())
	_assert_eq(px.size(), 2 * 2 * 4, "exactly width*height texels, footer not read as pixels")
	var all_seven := true
	for i in range(0, px.size(), 4):
		if px[i] != 7 or px[i + 3] != 255:
			all_seven = false
	_assert_true(all_seven, "every texel came from the one cross-row run")


func _test_a_bottom_left_origin_rle_file_is_also_flipped() -> void:
	# The two traits are independent: an editor that defaults to RLE usually defaults to
	# bottom-left too, so they arrive TOGETHER. Decompressing without flipping reads the
	# sheet upside down just as silently as before.
	var rle := _rle_header(1, 2, 0x08)                                  # origin bit CLEAR
	rle.append_array(_raw_packet(PackedByteArray([0, 0, 20, 255])))     # file row 0 = BOTTOM
	rle.append_array(_raw_packet(PackedByteArray([0, 0, 10, 255])))     # file row 1 = TOP

	var img: Dictionary = Tga.decode(rle)

	_assert_true(img.get("ok", false), "bottom-left RLE decodes")
	var px: PackedByteArray = img.get("pixels", PackedByteArray())
	_assert_eq(px[0], 10, "top row is the file's LAST row")
	_assert_eq(px[4], 20, "bottom row is the file's FIRST row")


# --- RLE fixture builders (BGRA in, matching the on-disk byte order) --------
func _rle_header(width: int, height: int, descriptor: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(18)
	for i in range(18):
		h[i] = 0
	h[2] = 10                                  # image type 10 = RLE true-colour
	h[12] = width & 0xFF
	h[13] = (width >> 8) & 0xFF
	h[14] = height & 0xFF
	h[15] = (height >> 8) & 0xFF
	h[16] = 32
	h[17] = descriptor
	return h


## A raw packet: header byte with bit 7 CLEAR, then `count` literal texels.
func _raw_packet(texels: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([(texels.size() / 4) - 1])
	out.append_array(texels)
	return out


## A run packet: header byte with bit 7 SET, then ONE texel to repeat `count` times.
func _run_packet(texel: PackedByteArray, count: int) -> PackedByteArray:
	var out := PackedByteArray([0x80 | (count - 1)])
	out.append_array(texel)
	return out


func _read(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)
