extends Node
## Guard (no GPU): the map terrain carries the PSX framebuffer snap — ordered dither +
## 15-bit quantize — and carries it in the one place that is correct.
##
## WHY THE MAP AT ALL. The real GPU dithers a primitive only when it clears two
## independent gates: it must be a GOURAUD primitive (sprites and flat-textured polys
## never reach the dither unit at all) and the texpage's DTD bit must be set. FFT's map
## terrain clears both, and that is measured rather than reasoned: on a live battle frame
## pulled off hardware-accurate emulation, every terrain sample carries the 4x4 dither
## signature while the flat-rect UI windows in the same frame carry none. The port did
## neither for the map until this snap landed — `screen_background.gdshader` was the only
## live caller of the shared include.
##
## WHY 256.0. One dither cell is one FRAMEBUFFER pixel, so the include divides screen
## coords down to PSX pixel density before indexing the matrix, and it has to be told what
## that density is. FFT's battle framebuffer measures 256x240 — the generic PSX 320 is the
## wrong number for this title, and at this project's 1024-wide viewport (a clean 4x of
## 256) it rounds the cell to 3 device px instead of 4, putting the pattern off the pixel
## grid. Both battlefield surfaces are the same screen, so both must pass the same width;
## that agreement is arm 5 and it is the one an unrelated edit is most likely to break.
##
## WHY ABOVE THE DEBUG BRANCH. `map_light_debug` 1..5 replace `final` wholesale with a
## diagnostic (normals as colour, lighting with no albedo). Quantizing those is noise on
## the readout, so the snap sits ABOVE the branch: the diagnostics overwrite it, and no
## extra condition is needed to say so. Move the call below the branch and the modes
## silently start reading through a 5-bit lattice — nothing else in the suite notices.
##
## This is a SOURCE guard on purpose. ShaderCompileTest already proves these files parse;
## what it cannot see is whether the snap is called, where, or with what. The pixel-level
## claim (that the output posterizes to a 5-bit ladder at a 4px cell) was verified by
## rendering the map with the snap on and off and correlating the difference against the
## dither matrix — a rig, not a test, because it needs a real map and a real GPU.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/MapDitherSnapTest.tscn

const INCLUDE_PATH := "res://addons/exmateria_platform/dither/psx_dither.gdshaderinc"
const MAP_SHADER := "res://addons/exmateria_battlefield/texturing/indexed_color.gdshader"
const BG_SHADER := "res://addons/exmateria_battlefield/camera/screen_background.gdshader"
const SPRITE_ADDON := "res://addons/exmateria_sprite_rig"
const CALL := "psx_dither_and_quantize("

## FFT's battle framebuffer width, measured off the emulator's display capture (256x240),
## not the generic PSX 320. Spelled here so a silent edit at either call site reds.
const NATIVE_WIDTH := "256.0"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	# Every arm below reads CODE, never prose: these files document themselves heavily and
	# the doc comments name `psx_dither_and_quantize()` too, which would make the call
	# count and the argument scrape read the comment instead. Only whole-line comments are
	# dropped — a blanket cut at the first `//` would eat every `res://` include path.
	var map_src := _code_only(_read(MAP_SHADER))
	var bg_src := _code_only(_read(BG_SHADER))
	var inc_src := _code_only(_read(INCLUDE_PATH))

	_test_map_includes_and_calls(map_src)
	_test_snap_precedes_debug_overrides(map_src)
	_test_native_width_agrees(map_src, bg_src)
	_test_include_takes_a_native_width(inc_src)
	_test_no_sprite_shader_dithers()
	_test_panel_emits_a_live_toggle()

	print("\n=== MapDitherSnapTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] MapDitherSnapTest")
		get_tree().quit(1)
	else:
		print("[PASS] MapDitherSnapTest")
		get_tree().quit(0)


## Arms 1-2. The map shader pulls the shared include and actually calls the snap, once.
## Two arms rather than one because an include with no call is exactly what a half-applied
## refactor leaves behind, and it compiles.
func _test_map_includes_and_calls(src: String) -> void:
	_check("indexed_color.gdshader includes the platform dither include",
		src.contains('#include "%s"' % INCLUDE_PATH), true)
	_check("indexed_color.gdshader calls the snap exactly once",
		src.count(CALL), 1)


## Arm 3. The call sits ABOVE the `map_light_debug` override chain, so the diagnostic
## modes are the un-snapped value. Compares source offsets: both must exist, and the
## snap's must come first.
func _test_snap_precedes_debug_overrides(src: String) -> void:
	var call_at := src.find(CALL)
	var debug_at := src.find("map_light_debug ==")
	if call_at < 0 or debug_at < 0:
		_check("both the snap call and the map_light_debug branch are present", false, true)
		return
	_check("the snap is applied above the map_light_debug overrides", call_at < debug_at, true)


## Arms 4-5. Both battlefield surfaces are the same 256-wide PSX screen, so both must ask
## for the same dither cell size. Arm 4 pins the value; arm 5 pins the agreement — a later
## edit that "fixes" one call site in isolation reds here rather than shipping a frame with
## two different cell sizes in it.
func _test_native_width_agrees(map_src: String, bg_src: String) -> void:
	var map_w := _last_argument(map_src)
	var bg_w := _last_argument(bg_src)
	_check("indexed_color passes FFT's measured framebuffer width", map_w, NATIVE_WIDTH)
	_check("screen_background passes the same width as indexed_color", bg_w, map_w)


## Arm 6. The width is a PARAMETER, not a constant welded back into the include. The
## include lives in the platform addon, which is generic-PSX: the moment the scale divisor
## is a literal again, the caller has no way to be right.
func _test_include_takes_a_native_width(src: String) -> void:
	_check("the include's snap takes a native_width parameter",
		src.contains("vec3 psx_dither_and_quantize(vec3 color, vec2 screen_pos,"
			+ " vec2 viewport_size, float native_width)"), true)
	_check("the scale divisor is the parameter, not a literal",
		src.contains("round(viewport_size.x / native_width)"), true)


## Arm 7. The include's own header says it is NOT for sprite shaders, because PSX sprites
## are VRAM copies that bypass the dither unit — an unenforced heading until now. Scans
## the sprite rig addon rather than trusting the sentence.
func _test_no_sprite_shader_dithers() -> void:
	var offenders: Array[String] = []
	for path in _shader_sources(SPRITE_ADDON):
		if _read(path).contains(INCLUDE_PATH):
			offenders.append(path)
	_check("no sprite-rig shader includes the dither (%s)" % str(offenders),
		offenders.is_empty(), true)


## Arm 8. The F3 row is a LIVE control, not a dead one. `TuneField.add` renders a view row
## by reading the slug's default back out of the Tune registry, and when the owner has not
## bound it yet it does NOT fail — it renders a read-only "(unregistered — owner not booted)"
## label and binds nothing. That is the shape this row is most exposed to: DebugConfig owns
## `render.psx_dither_enabled`, not MapComposer like every other slug on this panel, so the
## row lives or dies on an autoload having bound the slug before the panel builds. A source
## grep for `TuneField.add` passes against exactly that dead row, so this arm grades the
## panel by what it EMITS.
##
## SCOPED TO THIS ROW ON PURPOSE. In a bare test scene MapComposer never boots, so its six
## rows on this same panel render as placeholders legitimately — asserting "no placeholder
## anywhere" reds on a healthy panel. That the dither row is a live CheckBox in the very
## scene where the others are not is the point: it is the one whose owner is an autoload.
func _test_panel_emits_a_live_toggle() -> void:
	var panel := MapRenderDebugPanel.new()
	add_child(panel)
	panel.setup()
	var row := _row_labelled(panel, "PSX dither")
	if row == null:
		_check("the map panel builds a row labelled 'PSX dither...'", false, true)
		panel.queue_free()
		return
	var has_box := false
	var dead := false
	for child in row.get_children():
		if child is CheckBox:
			has_box = true
		elif child is Label and (child as Label).text.contains("unregistered"):
			dead = true
	_check("the snap row emits a bound CheckBox", has_box, true)
	_check("the snap row is not an unregistered placeholder", dead, false)
	panel.queue_free()


## The first row container under `n` holding a Label whose text starts with `prefix`.
## Rows are the HBoxContainer `TuneField.add` builds per slug.
func _row_labelled(n: Node, prefix: String) -> Node:
	if n is HBoxContainer:
		for child in n.get_children():
			if child is Label and (child as Label).text.begins_with(prefix):
				return n
	for c in n.get_children():
		var found := _row_labelled(c, prefix)
		if found != null:
			return found
	return null


## Every `.gdshader` / `.gdshaderinc` under `root`, recursively. Returns [] if the
## directory is missing, which is itself reported by arm 7 passing vacuously — acceptable
## here because the addon's absence would red a great many louder tests first.
func _shader_sources(root: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var path := root.path_join(name)
		if dir.current_is_dir():
			out.append_array(_shader_sources(path))
		elif name.ends_with(".gdshader") or name.ends_with(".gdshaderinc"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## The final argument of the first `psx_dither_and_quantize(...)` call in `src`, trimmed.
## Returns "" when there is no call, which reds the arm that asked rather than passing.
func _last_argument(src: String) -> String:
	var at := src.find(CALL)
	if at < 0:
		return ""
	var close := src.find(")", at)
	if close < 0:
		return ""
	var args := src.substr(at + CALL.length(), close - at - CALL.length()).split(",")
	return args[args.size() - 1].strip_edges()


## `src` with whole-line `//` comments removed. Deliberately not a strip at the first
## `//` anywhere in a line: `res://` is two slashes, and that cut deletes every include.
func _code_only(src: String) -> String:
	var kept := PackedStringArray()
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("//"):
			kept.append(line)
	return "\n".join(kept)


func _read(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	if src.is_empty():
		print("  [FAIL] could not read %s" % path)
		_failed += 1
	return src


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
