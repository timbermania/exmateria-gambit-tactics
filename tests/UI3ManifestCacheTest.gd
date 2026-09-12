extends Node3D
## Guard: the IMMUTABLE asset manifests behind the UI3 text/atlas stack are parsed ONCE per
## process, not once per constructed instance.
##
## Why this exists (measured 2026-08-19, headful, warm caches). "Opening a UI3 picker lags the
## game" profiled to a purely SYNCHRONOUS build — `add_child` alone cost 44 ms (equip picker) /
## 33 ms (job + ability pickers). Nearly half of that was gone before a single quad existed:
##
##   RangeTileAtlas.new()  3.3 ms   — re-parses RANGETILE.json (43 KB)
##   UIMenuText.new()     16.2 ms   — of which UIFont.new() is 12.9 ms, and 12.7 ms of THAT
##                                    is one JSON.parse of font_meta.json (275 KB)
##
## Both manifests are read-only for the process's whole life, and both are constructed by many
## owners (UIMenuText, UIUnitNameplate, UIChar, ChangeJobScreen, all three detail pickers, ...),
## so every one of them paid the same re-parse. The fix is a class-level parse cache keyed by
## path; the constructors keep their signatures so no call site changed.
##
## The guard is deliberately COUNTER-based, not wall-clock: a parse counter goes red on the
## exact regression (someone drops the cache, or adds a fourth manifest owner that bypasses it)
## and is immune to machine jitter. The loose ms ceilings below are the secondary net — they are
## ~10x the post-fix cost, so they catch an unrelated blow-up without ever flaking.
##
## Content equality is asserted too: a shared parse must not let one instance's state leak into
## another's (the cache hands back the same parsed Dictionary, so a future mutation of it would
## corrupt every holder — these assertions are what makes that visible).
##
## Run: <GODOT> --path . --quit-after 20 res://tests/UI3ManifestCacheTest.tscn

const UIFontClass = preload("res://src/ui3/elements/UIFont.gd")
const NumberFontClass = preload("res://src/ui3/elements/NumberFont.gd")
const RangeTileAtlasClass = preload("res://src/ui3/elements/RangeTileAtlas.gd")
const UIMenuTextClass = preload("res://src/ui3/UIMenuText.gd")
const EquipPickerMenuClass = preload("res://src/ui3/detail/EquipPickerMenu.gd")
const JobPickerMenuClass = preload("res://src/ui3/detail/JobPickerMenu.gd")
const AbilityPickerMenuClass = preload("res://src/ui3/detail/AbilityPickerMenu.gd")

# ~10x the measured post-fix cost — a jitter-proof band, not a target.
const FONT_CEILING_MS := 3.0     # post-fix UIFont.new() ~0.2 ms (was 12.9 ms)
const ATLAS_CEILING_MS := 3.0    # post-fix RangeTileAtlas.new() ~0.3 ms (was 3.3 ms)
const MENUTEXT_CEILING_MS := 5.0 # post-fix UIMenuText.new() ~0.5 ms (was 16.2 ms)

var _passed := 0
var _failed := 0


func _ready() -> void:
	_test_font_manifest_parsed_once()
	_test_atlas_manifest_parsed_once()
	_test_cached_font_agrees_with_a_fresh_parse()
	_test_construction_cost_ceilings()
	await _test_a_picker_build_reparses_nothing()
	print("\n=== UI3ManifestCacheTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] UI3ManifestCacheTest")
		get_tree().quit(1)
	else:
		print("[PASS] UI3ManifestCacheTest")
		get_tree().quit(0)


## The headline: N UIFonts cost ONE parse of font_meta.json, not N.
func _test_font_manifest_parsed_once() -> void:
	var _warm := UIFontClass.new()     # whoever ran first may or may not have primed it
	var before: int = UIFontClass.manifest_parse_count()
	var fonts: Array = []
	for _i in range(8):
		fonts.append(UIFontClass.new())
	var parses: int = UIFontClass.manifest_parse_count() - before
	_expect(parses == 0,
		"8 UIFont.new() after a warm one must re-parse font_meta.json 0 times, parsed %d" % parses)
	_expect(fonts[7].characters.size() > 0, "a cache-hit UIFont must still be fully populated")
	_expect(fonts[7].atlas_texture != null, "a cache-hit UIFont must still carry its atlas texture")


## Same contract for RANGETILE.json — the other manifest every picker re-parsed.
func _test_atlas_manifest_parsed_once() -> void:
	var _warm := RangeTileAtlasClass.new()
	var before: int = RangeTileAtlasClass.manifest_parse_count()
	var atlases: Array = []
	for _i in range(8):
		atlases.append(RangeTileAtlasClass.new())
	var parses: int = RangeTileAtlasClass.manifest_parse_count() - before
	_expect(parses == 0,
		"8 RangeTileAtlas.new() after a warm one must re-parse RANGETILE.json 0 times, parsed %d" % parses)
	var a: RangeTileAtlas = atlases[7]
	_expect(a.texture != null, "a cache-hit RangeTileAtlas must still carry RANGETILE.tga")
	_expect(a.digit_glyphs().length() > 0, "a cache-hit RangeTileAtlas must still know its digits")
	_expect(a.stat_label_colors().size() == 16, "a cache-hit RangeTileAtlas must still carry its CLUTs")


## A shared parse must not hand out DIFFERENT content than a cold one — the whole risk of a
## cache is that it goes stale or half-populated. Compare a cached instance field-by-field
## against one built from a bypassing parse of the same file.
func _test_cached_font_agrees_with_a_fresh_parse() -> void:
	var cached := UIFontClass.new()
	var json := JSON.new()
	var f := FileAccess.open("res://assets/fonts/font_meta.json", FileAccess.READ)
	if f == null or json.parse(f.get_as_text()) != OK:
		_fail("could not read font_meta.json for the differential check")
		return
	var raw: Dictionary = json.data
	_expect(cached.char_width == int(raw.get("char_width", -1)), "cached char_width drifted")
	_expect(cached.char_height == int(raw.get("char_height", -1)), "cached char_height drifted")
	_expect(cached.chars_per_row == int(raw.get("chars_per_row", -1)), "cached chars_per_row drifted")
	_expect(cached.characters.size() == (raw.get("characters", {}) as Dictionary).size(),
		"cached glyph table size drifted from the file")
	_expect(cached.char_to_index.size() == (raw.get("char_to_index", {}) as Dictionary).size(),
		"cached char_to_index size drifted from the file")
	_expect(cached.dialog_clut.size() == (raw.get("dialog_clut", []) as Array).size(),
		"cached dialog_clut size drifted from the file")
	_expect(cached.get_char_width("A") > 0, "a cached font must still measure a glyph")


## Secondary net: the constructors themselves stay cheap. Best-of-5 so a GC hiccup can't flake it.
func _test_construction_cost_ceilings() -> void:
	var _w1 := UIFontClass.new()
	var _w2 := RangeTileAtlasClass.new()
	var _w3 := UIMenuTextClass.new()
	_ceiling("UIFont.new()", FONT_CEILING_MS, func() -> void:
		var x := UIFontClass.new(); x = x)
	_ceiling("RangeTileAtlas.new()", ATLAS_CEILING_MS, func() -> void:
		var x := RangeTileAtlasClass.new(); x = x)
	_ceiling("UIMenuText.new()", MENUTEXT_CEILING_MS, func() -> void:
		var x := UIMenuTextClass.new(); x = x)


func _ceiling(label: String, ceiling_ms: float, c: Callable) -> void:
	var best := INF
	for _i in range(5):
		var t := Time.get_ticks_usec()
		c.call()
		best = minf(best, float(Time.get_ticks_usec() - t) / 1000.0)
	if best <= ceiling_ms:
		_passed += 1
		print("[ok] %s best-of-5 = %.2f ms (ceiling %.1f ms)" % [label, best, ceiling_ms])
	else:
		_failed += 1
		print("[FAIL] %s best-of-5 = %.2f ms EXCEEDS ceiling %.1f ms — the manifest parse cache is gone"
			% [label, best, ceiling_ms])


## The invariant the user actually feels: OPENING A PICKER RE-PARSES NOTHING. Each picker
## constructs its own RangeTileAtlas + UIMenuText in _ready, which is how ~20 ms of the ~44 ms
## build got there in the first place. This is the end-to-end form of the guard, and it is
## structural rather than wall-clock: a new picker (or a new element inside one) that reaches
## for an uncached manifest goes red here regardless of how fast the machine is.
func _test_a_picker_build_reparses_nothing() -> void:
	# Warm: the FIRST picker in a process legitimately pays for the parse.
	for maker: Callable in [_make_equip, _make_job, _make_ability]:
		var warm: Node3D = maker.call()
		add_child(warm)
		await get_tree().process_frame
		warm.free()
	await get_tree().process_frame

	for entry: Array in [["equip", _make_equip], ["job", _make_job], ["ability", _make_ability]]:
		var label: String = entry[0]
		var font_before: int = UIFontClass.manifest_parse_count()
		var atlas_before: int = RangeTileAtlasClass.manifest_parse_count()
		var m: Node3D = (entry[1] as Callable).call()
		add_child(m)
		await get_tree().process_frame
		var font_parses: int = UIFontClass.manifest_parse_count() - font_before
		var atlas_parses: int = RangeTileAtlasClass.manifest_parse_count() - atlas_before
		_expect(font_parses == 0,
			"building the %s picker re-parsed font_meta.json %d time(s) — 275 KB per open"
				% [label, font_parses])
		_expect(atlas_parses == 0,
			"building the %s picker re-parsed RANGETILE.json %d time(s)" % [label, atlas_parses])
		m.free()
		await get_tree().process_frame


func _make_equip() -> Node3D:
	var m := EquipPickerMenuClass.new()
	m.autoplay_open = false
	return m


func _make_job() -> Node3D:
	var m := JobPickerMenuClass.new()
	m.autoplay_open = false
	return m


func _make_ability() -> Node3D:
	var m := AbilityPickerMenuClass.new()
	m.autoplay_open = false
	return m


func _expect(ok: bool, msg: String) -> void:
	if ok:
		_passed += 1
	else:
		_fail(msg)


func _fail(msg: String) -> void:
	_failed += 1
	print("[FAIL] %s" % msg)
