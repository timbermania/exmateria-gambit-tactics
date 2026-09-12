class_name RangeTileAtlas
extends RefCounted
## Feedback-HUD sprite atlas (#88).
##
## Loads RANGETILE.json — the metadata tools/parse_range_tiles.py emits next to
## the RANGETILE.tga system atlas — and hands consumers the atlas texture plus
## per-cell rects: the damage/HP digit strip (0-9 and '/') and the 20
## status-bubble icons. Shared by the over-unit number/icon billboards (#89/#90)
## and the field-inspect info window (#91).
##
## Usage:
##   var atlas := RangeTileAtlas.new()
##   var tex := atlas.cell_atlas_texture(atlas.digit_rect("9"))
##
## Vault: [[Equip And Ability Panel]]
## Vault: [[Formation Screen Compositing]]
## Vault: [[Formation Sort Tab Header]]
## Vault: [[Formation Vitals And Nameplate]]
## Vault: [[Unit Pager Buttons]]

const DEFAULT_JSON := "res://assets/sprites/textures/RANGETILE.json"

## ADR-0212 dec. 1 — the addon declares one global (`ExMateriaAlmanac`), so this line is
## what keeps the use site spelled the way the rest of the port spells it (ADR-0211 dec. 4).
const SpriteDatabase = ExMateriaAlmanac.SpriteDatabase

## FFT world units per map tile (`ot_depth.gdshaderinc`: 1 tile = 1 Godot unit = 28 FFT
## units). The carousel's heights are signed bytes in FFT units, so they convert through here.
const FFT_UNITS_PER_TILE := 28.0

## Height in FFT units when a sprite's SHP type cannot be resolved — the ROM's human-scale
## row, which is what all but ~27 of the 159 sprite ids take anyway.
const OVERHEAD_RAISE_FFT_FALLBACK := -40.0

var texture: Texture2D = null            ## RANGETILE.tga (256x256 indexed-as-gray)
var palette_texture: Texture2D = null    ## RANGETILE.palette.tga (range-tile CLUTs)

var _digit_glyphs: String = ""
var _digit_cells: Array = []             ## parallel to _digit_glyphs
var _digit_colors: Array = []            ## the number CLUT (0x7d7c), 16 Color entries
var _zodiac_cells: Array = []            ## 13 zodiac-sign cells, index 0..12 (§14.3)
var _zodiac_colors: Array = []           ## the zodiac render CLUT, 16 Color entries
var _icon_cells: Array = []
var _active_turn_frames: Array = []      ## the "AT" marker's 2 cells, phase 0/1 (AT_MARKER_RENDERING.md)
var _active_turn_colors: Array = []      ## its CLUT (0x7887 == the 0x7d7c menu CLUT), 16 entries
var _active_turn_phase_frames: int = 0   ## video frames per phase (16 — bit 4 of the ROM's tick counter)
var _active_turn_bob_px: int = 0         ## screen-space lift on phase 1 (1 px)
var _active_turn_offsets: Dictionary = {} ## the per-sprite-type marker offset switch (§5.2)
var _ability_icon_cells: Array = []      ## 5 detail-screen Ability-window icons (§15.15)
var _ability_icon_colors: Array = []     ## the shared menu icon CLUT (0x7d7c), 16 entries
var _slot_icon_cells: Array = []         ## 5 Eqp slot-category icons [{lit:Rect2, dark:Rect2}] (§15.16)
var _slot_icon_2h_lit: Rect2 = Rect2()   ## two-handed collapse variant lit cell
var _slot_icon_lit_colors: Array = []    ## lit CLUT (0x7d7c), 16 entries
var _slot_icon_dark_colors: Array = []   ## dark backing CLUT (0x7c3c), 16 entries
var _weapon_icon_lit: Rect2 = Rect2()    ## Weap.Power weapon-legend lit cell (§15.18)
var _weapon_icon_dark: Rect2 = Rect2()   ## its dark backing cell (drawn under the lit)
var _weapon_icon_lit_colors: Array = []  ## lit CLUT (0x7d7c colourful), 16 entries
var _weapon_icon_dark_colors: Array = [] ## dark backing CLUT (0x7c3c), 16 entries
var _type_glyph_cells: Dictionary = {}   ## equip-picker class glyphs (§15.28): item class byte (int) -> Rect2
var _type_glyph_colors: Array = []       ## their idle CLUT (0x7c3c), 16 entries
var _menu_glove_lit: Rect2 = Rect2()     ## START-menu glove cursor lit cell (§15.20)
var _menu_glove_shadow: Rect2 = Rect2()  ## its shadow cell (drawn under, +2/+2)
var _menu_glove_lit_colors: Array = []   ## lit CLUT (0x7d7c), 16 entries
var _menu_glove_shadow_colors: Array = [] ## shadow CLUT (0x7dbc), 16 entries
var _stat_label_cells: Dictionary = {}   ## stats-band label ("Move"/"AT"/"C-"/...) -> Rect2 (§15.14)
var _stat_label_colors: Array = []       ## stats-band label CLUT (0x7c3c), 16 Color entries
var _delta_palette_colors: Array = []    ## equip stat-DELTA CLUT (0x7ffc = FRAME pal 15), 16 Color entries
var _label_cells: Dictionary = {}        ## label name ("Hp"/"Mp"/...) -> Rect2
var _window_tab_cells: Dictionary = {}   ## lower-window tab ("Eqp"/"Ability") -> Rect2 (§15.19)
var _window_tab_colors: Array = []       ## the active-label CLUT (0x7cbc), 16 Color entries
var _bar_swatch: Rect2 = Rect2()         ## shared HP/MP/CT bar swatch cell
var _bar_stats: Array = []               ## [{name, clut, colors: Array[Color]}]
var _header: Dictionary = {}             ## formation sort-tab header (§12.3.2):
                                         ## {cluts:{name->Array[Color]}, labels, buttons, box, tan_rect, colors}
var _detail_pager: Dictionary = {}       ## Status-screen ◄L1/R1► pager buttons (§15.22):
                                         ## {tpage, clut, clut_bg, left/right:{origin_x, y, pieces:[[dx,dy,u,v,w,h]]}}


# RANGETILE.json is READ-ONLY for the life of the process but every atlas owner constructs its
# own RangeTileAtlas, so each `new()` used to re-read+re-parse the 43 KB file (~1.6 ms). Cache
# the parsed Dictionary per path; the per-instance cell/CLUT tables below are still rebuilt from
# it, so only the file I/O + parse is shared. Treat the cached Dictionary as IMMUTABLE.
# See UI3ManifestCacheTest.
static var _manifest_cache: Dictionary = {}   # json_path -> parsed manifest Dictionary
static var _manifest_parse_count: int = 0     # real parses only — the cache guard's signal


func _init(json_path: String = DEFAULT_JSON) -> void:
	load_manifest(json_path)


## How many times a manifest has actually been read+parsed this process. A cache HIT does not
## increment it, so a guard can assert "N constructions, zero re-parses" without wall-clock.
static func manifest_parse_count() -> int:
	return _manifest_parse_count


## Drop the parse cache. Only for tooling that rewrites RANGETILE.json in place.
static func clear_manifest_cache() -> void:
	_manifest_cache.clear()


func load_manifest(json_path: String) -> bool:
	var data: Dictionary = _cached_manifest(json_path)
	if data.is_empty():
		return false
	var base := json_path.get_base_dir()

	var tex_name: String = data.get("texture", "")
	if tex_name != "" and ResourceLoader.exists(base + "/" + tex_name):
		texture = load(base + "/" + tex_name)
	var pal_name: String = data.get("palette", "")
	if pal_name != "" and ResourceLoader.exists(base + "/" + pal_name):
		palette_texture = load(base + "/" + pal_name)

	var digits: Dictionary = data.get("digits", {})
	_digit_glyphs = digits.get("glyphs", "")
	_digit_cells = _to_rects(digits.get("cells", []))
	_digit_colors.clear()
	for c in digits.get("colors", []):
		_digit_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	# The damage-number DAMAGE path lights EVERY glyph through this 16-entry number
	# CLUT (0x7d7c); an empty/short `colors` => an all-transparent palette => the
	# shader discards every fragment => numbers render INVISIBLE with no other
	# symptom. That is exactly what a STALE gitignored RANGETILE.json produces — one
	# generated before tools/parse_range_tiles.py learned to emit `digits.colors`.
	# The manifest is not tracked, so a `git merge` won't refresh it; warn loudly
	# with the fix instead of failing silently. (Only when the digit strip is present
	# at all — a manifest with no digits block is a legitimately different atlas.)
	if not _digit_glyphs.is_empty() and _digit_colors.size() != 16:
		push_warning(("RangeTileAtlas: %s has %d digit-CLUT colors (expected 16) — " +
			"damage numbers will render INVISIBLE. The manifest is stale; regenerate it: " +
			"`uv run python tools/parse_range_tiles.py` (or tools/bootstrap_assets.sh).") % [
			json_path, _digit_colors.size()])

	# Formation zodiac-sign glyphs (§14.3): 13 signs (Aries..Serpentarius) laid
	# out across two fixed-pitch atlas rows, one 24x20 cell per sign in reading
	# order. `colors` is the render CLUT (a documented default reused from the
	# number CLUT; the panel can override the tint like the digits).
	var zodiac: Dictionary = data.get("zodiac", {})
	_zodiac_cells = _to_rects(zodiac.get("cells", []))
	_zodiac_colors.clear()
	for c in zodiac.get("colors", []):
		_zodiac_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	var icons: Dictionary = data.get("status_icons", {})
	_icon_cells = _to_rects(icons.get("cells", []))

	# The "AT" active-turn marker (AT_MARKER_RENDERING.md): carousel slot 21, whose cell is a
	# CODE LITERAL in the ROM rather than a status-table entry, so it arrives as its own block
	# and NOT as `status_icons` cell 21. Two frames one 12px row apart plus the animation the
	# ROM drives them with — the period is extracted, not restated in GDScript (root ADR-0001).
	var at: Dictionary = data.get("active_turn", {})
	_active_turn_frames = _to_rects(at.get("frames", []))
	_active_turn_phase_frames = int(at.get("phase_frames", 0))
	_active_turn_offsets = at.get("offsets", {})
	_active_turn_bob_px = int(at.get("bob_px", 0))
	_active_turn_colors.clear()
	for c in at.get("colors", []):
		_active_turn_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	# Same trap as the digit CLUT above, and the same reason it needs a loud warning rather
	# than a silent fallback: RANGETILE.json is GITIGNORED, so merging the commit that added
	# this block does NOT bring the block with it, and a worktree whose textures dir is
	# SYMLINKED to the asset hub reads the hub's copy no matter what its own branch says.
	# Without the cells `TurnMarker3D` draws nothing at all — an invisible AT marker with no
	# other symptom. (Only when the manifest is otherwise a RANGETILE one; an atlas with no
	# status icons at all is legitimately a different sheet.)
	if not _icon_cells.is_empty() and _active_turn_frames.size() < 2:
		push_warning(("RangeTileAtlas: %s carries %d active-turn marker frames (expected 2) — " +
			"the AT marker will not render. The manifest is stale; regenerate it: " +
			"`uv run python tools/parse_range_tiles.py` (or tools/bootstrap_assets.sh).") % [
			json_path, _active_turn_frames.size()])

	# Unit-detail/Status-screen Ability-window icons (§15.15): five FIXED sprites
	# on this same sheet (block (136,0)-(168,32)), drawn through the shared menu
	# icon CLUT 0x7d7c. Per-slot baked constants — the icon does not vary per unit.
	var ability: Dictionary = data.get("ability_icons", {})
	_ability_icon_cells = _to_rects(ability.get("cells", []))
	_ability_icon_colors.clear()
	for c in ability.get("colors", []):
		_ability_icon_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	# Eqp slot-category icons (§15.16): five two-layer emboss rows (dark backing
	# 0x7c3c under a lit icon 0x7d7c) + a two-handed collapse variant lit cell.
	var slot: Dictionary = data.get("slot_icons", {})
	_slot_icon_cells.clear()
	for s in slot.get("slots", []):
		_slot_icon_cells.append({
			"lit": _rect_from_dict(s.get("lit", {})),
			"dark": _rect_from_dict(s.get("dark", {})),
		})
	_slot_icon_2h_lit = _rect_from_dict((slot.get("two_handed", {}) as Dictionary).get("lit", {}))
	_slot_icon_lit_colors.clear()
	for c in slot.get("lit_colors", []):
		_slot_icon_lit_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	_slot_icon_dark_colors.clear()
	for c in slot.get("dark_colors", []):
		_slot_icon_dark_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	# Weap.Power band weapon-type legend icon (§15.18): one FIXED two-layer emboss
	# (dark backing 0x7c3c under a colourful dagger/rod 0x7d7c) — NOT ITEM.BIN, does
	# not vary per unit. Same mechanism as the slot icons, one pair instead of five.
	var weapon: Dictionary = data.get("weapon_icons", {})
	_weapon_icon_lit = _rect_from_dict(weapon.get("lit", {}))
	_weapon_icon_dark = _rect_from_dict(weapon.get("dark", {}))
	_weapon_icon_lit_colors.clear()
	for c in weapon.get("lit_colors", []):
		_weapon_icon_lit_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	_weapon_icon_dark_colors.clear()
	for c in weapon.get("dark_colors", []):
		_weapon_icon_dark_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	# Equip-picker per-TYPE class glyphs (§15.28): the WORLD.BIN type→UV LUT
	# (0x8018D7FC; page v == tga y), 12×12 cells through the idle dark menu
	# CLUT 0x7C3C — one cell per item class byte (1=Knife, 3=Sword, …).
	var tglyphs: Dictionary = data.get("type_glyphs", {})
	_type_glyph_cells.clear()
	for t in (tglyphs.get("cells", {}) as Dictionary):
		var c: Dictionary = tglyphs["cells"][t]
		_type_glyph_cells[int(t)] = Rect2(
				c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0))
	_type_glyph_colors.clear()
	for c in tglyphs.get("colors", []):
		_type_glyph_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	# Formation START sub-menu glove cursor (§15.20): a two-layer 16×16 emboss (lit
	# swirl CLUT 0x7d7c over a shadow CLUT 0x7dbc, offset +2/+2) — the FIRST glove
	# consumer (gh #73). Same RANGETILE sheet + two-CLUT mechanism as the slot icons.
	var glove: Dictionary = data.get("menu_glove_cursor", {})
	_menu_glove_lit = _rect_from_dict(glove.get("lit", {}))
	_menu_glove_shadow = _rect_from_dict(glove.get("shadow", {}))
	_menu_glove_lit_colors.clear()
	for c in glove.get("lit_colors", []):
		_menu_glove_lit_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
	_menu_glove_shadow_colors.clear()
	for c in glove.get("shadow_colors", []):
		_menu_glove_shadow_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	# Stats-band text labels (§15.14 row 14): baked RANGETILE word/token cells
	# (Move/Jump/Speed/Weap.Power/AT/C-EV/S-EV/A-EV/R/L) drawn through the dark-ink-on-
	# tan menu label CLUT 0x7C3C — the faithful source, NOT FONT.BIN. "C-EV" == cell
	# "C-" (dash baked in) + shared cell "EV". Rendered exactly like the slot/ability
	# icons (one index->CLUT sprite), so it carries its own 16-entry 0x7C3C palette.
	_stat_label_cells.clear()
	var stat: Dictionary = data.get("stat_labels", {})
	for c in stat.get("labels", []):
		_stat_label_cells[str(c.get("name", ""))] = Rect2(
				c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0))
	_stat_label_colors.clear()
	for c in stat.get("colors", []):
		_stat_label_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	# Equip stat-DELTA colour palette (§15.26 / EQUIP_STAT_PREVIEW.md §5): FRAME.BIN palette
	# 15 = CLUT 0x7FFC, the ONE palette the compare panel index-biases to colour a signed
	# delta blue([13], positive) / red([9], negative) / tan([1], plain). Same asset tail as
	# the stat-label CLUT; the port builds the biased number CLUTs from these 16 entries.
	_delta_palette_colors.clear()
	var dp: Dictionary = data.get("delta_palette", {})
	for c in dp.get("colors", []):
		_delta_palette_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	_label_cells.clear()
	var labels: Dictionary = data.get("word_labels", {})
	for c in labels.get("labels", []):
		_label_cells[str(c.get("name", ""))] = Rect2(
				c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0))

	# Lower-window title tabs (§15.19): "Eqp"/"Ability" cream word cells drawn through
	# the active-label CLUT 0x7CBC — the tab bakes its own tan fill + dark outline, so
	# it renders exactly like a slot/ability/stat-label sprite (one index->CLUT cell).
	_window_tab_cells.clear()
	var tabs: Dictionary = data.get("window_tabs", {})
	for c in tabs.get("labels", []):
		_window_tab_cells[str(c.get("name", ""))] = Rect2(
				c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0))
	_window_tab_colors.clear()
	for c in tabs.get("colors", []):
		_window_tab_colors.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))

	_bar_stats.clear()
	var bars: Dictionary = data.get("bars", {})
	var sw: Dictionary = bars.get("swatch", {})
	_bar_swatch = Rect2(sw.get("x", 0), sw.get("y", 0), sw.get("w", 0), sw.get("h", 0))
	for s in bars.get("stats", []):
		var cols: Array = []
		for c in s.get("colors", []):
			cols.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
		_bar_stats.append({"name": str(s.get("name", "")),
				"clut": int(s.get("clut", 0)), "colors": cols})

	# Formation sort-tab header (#174 v2, §12.3.2): ROM CLUTs + textured button
	# cells + label layout. CLUT colour arrays parsed into Array[Color] like bars.
	_header.clear()
	var hdr: Dictionary = data.get("sort_header", {})
	if not hdr.is_empty():
		var cluts: Dictionary = {}
		for name in (hdr.get("cluts", {}) as Dictionary):
			var arr: Array = []
			for c in hdr["cluts"][name].get("colors", []):
				arr.append(Color8(int(c[0]), int(c[1]), int(c[2]), int(c[3])))
			cluts[name] = arr
		_header = {"cluts": cluts, "labels": hdr.get("labels", []),
				"buttons": hdr.get("buttons", {}), "box": hdr.get("box", {}),
				"tan_rect": hdr.get("tan_rect", {}), "colors": hdr.get("colors", {})}

	# Status/detail-screen ◄L1/R1► pager buttons (§15.22): stored verbatim (geometry only;
	# colours come from the shared header 'button' CLUT + UIWindowPalettes bg twin).
	_detail_pager = data.get("detail_pager", {})
	return true


## Read + parse the manifest once per path, then serve the same Dictionary forever. Returns an
## EMPTY Dictionary (and push_error's, as the inline code did) on failure; a failure is not
## cached, so a fixed-up file is picked up on the next construction.
static func _cached_manifest(json_path: String) -> Dictionary:
	if _manifest_cache.has(json_path):
		return _manifest_cache[json_path]

	if not FileAccess.file_exists(json_path):
		push_error("RangeTileAtlas: missing manifest %s" % json_path)
		return {}
	var file := FileAccess.open(json_path, FileAccess.READ)
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	_manifest_parse_count += 1
	if err != OK:
		push_error("RangeTileAtlas: JSON parse error in %s" % json_path)
		return {}

	var data: Dictionary = json.data
	_manifest_cache[json_path] = data
	return data


func _to_rects(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(Rect2(c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0)))
	return out


func _rect_from_dict(c: Dictionary) -> Rect2:
	return Rect2(c.get("x", 0), c.get("y", 0), c.get("w", 0), c.get("h", 0))


## --- digits -----------------------------------------------------------------

func digit_glyphs() -> String:
	return _digit_glyphs


func digit_rect(glyph: String) -> Rect2:
	"""The atlas cell for a single digit glyph ('0'..'9' or '/')."""
	var i := _digit_glyphs.find(glyph)
	if i < 0:
		push_error("RangeTileAtlas: no digit cell for '%s'" % glyph)
		return Rect2()
	return _digit_cells[i]


func digit_palette_colors() -> Array:
	"""The 16 RGBA entries of the ROM number CLUT (0x7d7c) — idx0 transparent,
	idx1 dark outline, idx2 white fill, idx3/5/6 the cool-grey AA edges. The
	damage number samples these instead of a flat tint (one faithful pass)."""
	return _digit_colors


func digit_palette_texture() -> ImageTexture:
	"""The number CLUT as a 16x1 RGBA row, ready to bind as `palette_tex`."""
	var img := Image.create(16, 1, false, Image.FORMAT_RGBA8)
	for i in 16:
		img.set_pixel(i, 0, _digit_colors[i] if i < _digit_colors.size() else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(img)


## --- zodiac signs (§14.3) ---------------------------------------------------

func zodiac_count() -> int:
	return _zodiac_cells.size()


func zodiac_rect(sign: int) -> Rect2:
	"""The atlas cell for a zodiac sign (0=Aries .. 12=Serpentarius, reading
	order across the two atlas rows)."""
	if sign < 0 or sign >= _zodiac_cells.size():
		push_error("RangeTileAtlas: zodiac sign %d out of range" % sign)
		return Rect2()
	return _zodiac_cells[sign]


func zodiac_palette_colors() -> Array:
	"""The 16 RGBA entries of the zodiac render CLUT — a documented default reused
	from the number CLUT (0x7d7c); the info panel can override the tint, mirroring
	`digit_palette_colors`. The panel's true menu CLUT is not in the range palette."""
	return _zodiac_colors


## --- status icons -----------------------------------------------------------

func status_icon_count() -> int:
	return _icon_cells.size()


func status_icon_rect(i: int) -> Rect2:
	if i < 0 or i >= _icon_cells.size():
		push_error("RangeTileAtlas: status icon index %d out of range" % i)
		return Rect2()
	return _icon_cells[i]


## --- the "AT" active-turn marker (AT_MARKER_RENDERING.md) -------------------

func active_turn_frame_count() -> int:
	"""How many marker frames the manifest carries (2 in the ROM). 0 means a manifest
	predating the AT extraction — the caller should not draw a marker at all."""
	return _active_turn_frames.size()


func active_turn_rect(phase: int) -> Rect2:
	"""The atlas cell for marker phase 0 (row 176) or 1 (row 188). `phase` is
	`(frame_counter >> 4) & 1` — the same bit that drives the 1px bob."""
	if phase < 0 or phase >= _active_turn_frames.size():
		push_error("RangeTileAtlas: active-turn phase %d out of range" % phase)
		return Rect2()
	return _active_turn_frames[phase]


func active_turn_colors() -> Array:
	"""The 16 RGBA entries of the marker CLUT (ROM 0x7887, byte-identical to the
	0x7d7c menu/number CLUT — §3.3). idx0 is the transparent key."""
	return _active_turn_colors


func active_turn_phase_frames() -> int:
	"""Video frames per marker phase (16): the ROM flips on bit 4 of a free-running
	per-unit 60Hz counter, so the full period is twice this."""
	return _active_turn_phase_frames


func active_turn_bob_px() -> int:
	"""Screen-space pixels the marker lifts on phase 1 (1). The lift and the frame
	flip are THE SAME BIT, so they can never desynchronise."""
	return _active_turn_bob_px


## The marker's offset for a sprite's SHP type, as `[screen_x_px, world_y_fft_units]`
## (`unit[+0x2DE]` / `unit[+0x2DF]`). X is a post-projection SCREEN nudge, not a world
## offset; Y is negative because world -Y is up.
##
## ⚠️ Serves the `anim_else` branch ONLY, and that is the whole of what the port can
## answer. The ROM also keys on `unit[+0x1DC] >> 1` against three UNNAMED pose ids
## (0x1A/0x24/0x34) and, for human-scale sprites, on `tile[+3] & 0xE0`; our rig
## addresses animations by name, so no caller can say "is this unit in pose 0x1A".
## The full switch is in the manifest under `active_turn.offsets` — nothing is lost,
## it is just not reachable. Note the slope branch cannot move this answer either:
## human-scale is -40 raised AND flat once the anim is not special, so decoding the
## three ids is the single thing that unlocks the rest.
func active_turn_offset(shp_type: String) -> Vector2i:
	var rows: Dictionary = _active_turn_offsets.get("rows", {})
	if rows.is_empty():
		return Vector2i.ZERO
	var case_map: Dictionary = _active_turn_offsets.get("shp_case", {})
	var case_name: String = case_map.get(shp_type,
			str(_active_turn_offsets.get("fallback_case", "")))
	var row: Dictionary = rows.get(case_name, {})
	if row.is_empty():
		return Vector2i.ZERO
	# "flat" for the human row, "any" for every other — the branch the port can reach is
	# the same either way, so take whichever condition this row happens to carry.
	var branches: Dictionary = row.get("flat", row.get("any", {}))
	var v: Array = branches.get("anim_else", [])
	return Vector2i(int(v[0]), int(v[1])) if v.size() >= 2 else Vector2i.ZERO


## The over-head carousel offset for a SPRITE ID, resolved through its SHP-type byte —
## `[screen_x_px, world_y_fft_units]`, the `anim_else` branch of the §5.2 switch.
##
## These are the CAROUSEL's offsets, not the AT marker's. `unit_sprite_poly_builder`
## (`0x8007EEC0`) selects the atlas cell for whichever slot `unit[+0x2DD]` holds — the AT
## slot 21 by literal immediates, slots 0/20 through their own cell pair, slots 1..19 from
## the indexed tables — and EVERY one of those branches converges on `LAB_8007F088`, which
## then reads `unit[+0x2DF]` (`0x8007F0C4`) and `unit[+0x2DE]` (`0x8007F0EC`) with no slot
## test in between. So the status bubbles hang at the same per-sprite-type heights the
## marker does; a single constant for every unit is wrong in exactly the way `-40` was.
##
## Pure and instance-only-for-the-manifest, so a test can prove it DISCRIMINATES (a monster
## and a human must not agree) without mounting anything.
func overhead_offset_for_sprite(sprite_id: int) -> Vector2i:
	if sprite_id >= 0:
		var from_manifest := active_turn_offset(SpriteDatabase.get_shp_type(sprite_id))
		# A manifest predating the offsets serves (0,0); a real row never has y == 0 (every
		# one of the five is negative), so zero is unambiguously "absent".
		if from_manifest.y != 0:
			return from_manifest
	return Vector2i(0, int(OVERHEAD_RAISE_FFT_FALLBACK))


## The local Y an offset puts an over-head icon at. World -Y is up in FFT and +Y is up in
## Godot, so the ROM's negative height NEGATES.
static func overhead_raise_for_offset(off: Vector2i) -> float:
	return float(-off.y) / FFT_UNITS_PER_TILE



## --- detail/Status-screen ability-window icons (§15.15) ---------------------

func ability_icon_count() -> int:
	return _ability_icon_cells.size()


func ability_icon_rect(row: int) -> Rect2:
	"""The atlas cell for Ability-window row `row` (0..4: blade/blade/fist/diamond/
	boot). Fixed per-slot constants — the icon does not vary per unit (§15.15)."""
	if row < 0 or row >= _ability_icon_cells.size():
		push_error("RangeTileAtlas: ability icon row %d out of range" % row)
		return Rect2()
	return _ability_icon_cells[row]


func ability_icon_palette_colors() -> Array:
	"""The 16 RGBA entries of the shared menu icon CLUT (0x7d7c) the ability icons
	sample — same palette as the digit/number set."""
	return _ability_icon_colors


## --- detail/Status-screen Eqp slot-category icons (§15.16) ------------------

func slot_icon_count() -> int:
	return _slot_icon_cells.size()


func slot_icon_lit_rect(slot: int) -> Rect2:
	"""The lit-layer cell for Eqp slot `slot` (0=R.Hand..4=Accessory)."""
	if slot < 0 or slot >= _slot_icon_cells.size():
		push_error("RangeTileAtlas: slot icon %d out of range" % slot)
		return Rect2()
	return _slot_icon_cells[slot]["lit"]


func slot_icon_dark_rect(slot: int) -> Rect2:
	"""The dark backing-layer cell for Eqp slot `slot` (drawn under the lit layer)."""
	if slot < 0 or slot >= _slot_icon_cells.size():
		push_error("RangeTileAtlas: slot icon %d out of range" % slot)
		return Rect2()
	return _slot_icon_cells[slot]["dark"]


func slot_icon_2h_lit_rect() -> Rect2:
	"""The two-handed-weapon collapse variant lit cell (R/L.Hand merge; §15.16)."""
	return _slot_icon_2h_lit


func slot_icon_lit_colors() -> Array:
	"""The 16 RGBA entries of the lit slot-icon CLUT (0x7d7c)."""
	return _slot_icon_lit_colors


func slot_icon_dark_colors() -> Array:
	"""The 16 RGBA entries of the dark backing CLUT (0x7c3c = inactive_label)."""
	return _slot_icon_dark_colors


## --- detail/Status-screen Weap.Power weapon-legend icon (§15.18) -------------

func weapon_icon_lit_rect() -> Rect2:
	"""The lit-layer cell (dagger over rod) of the Weap.Power weapon-type legend icon."""
	return _weapon_icon_lit


func weapon_icon_dark_rect() -> Rect2:
	"""The dark backing-layer cell (drawn under the lit weapon-legend icon)."""
	return _weapon_icon_dark


func weapon_icon_lit_colors() -> Array:
	"""The 16 RGBA entries of the colourful lit weapon-icon CLUT (0x7d7c)."""
	return _weapon_icon_lit_colors


func weapon_icon_dark_colors() -> Array:
	"""The 16 RGBA entries of the dark backing CLUT (0x7c3c = inactive_label)."""
	return _weapon_icon_dark_colors


## --- equip-picker per-TYPE class glyphs (§15.28) -----------------------------

func has_type_glyph(item_type: int) -> bool:
	return _type_glyph_cells.has(item_type)


func type_glyph_rect(item_type: int) -> Rect2:
	"""The 12×12 class-glyph cell for an item class byte (1=Knife, 3=Sword, …) —
	the WORLD.BIN LUT 0x8018D7FC, page v == tga y (§15.28). Empty Rect2 if the
	type has no glyph (type 0 / unused slots)."""
	return _type_glyph_cells.get(item_type, Rect2())


func type_glyph_colors() -> Array:
	"""The 16 RGBA entries of the glyph idle CLUT (0x7c3c, FRAME.BIN tail +0x9000)."""
	return _type_glyph_colors


func delta_palette_colors() -> Array:
	"""The 16 RGBA entries of the equip stat-DELTA palette (0x7FFC = FRAME.BIN palette 15,
	asset tail +0x91E0). The compare panel index-biases these to colour a signed delta —
	[13]=blue (positive), [9]=red (negative), [1]=tan (plain). See EquipDeltaPalette."""
	return _delta_palette_colors


## --- Formation START sub-menu glove cursor (§15.20) --------------------------

func menu_glove_lit_rect() -> Rect2:
	"""The lit-layer cell (168,0 16×16) of the START-menu glove cursor (§15.20)."""
	return _menu_glove_lit


func menu_glove_shadow_rect() -> Rect2:
	"""The shadow-layer cell (184,0 16×16), drawn UNDER the lit layer at +2/+2."""
	return _menu_glove_shadow


func menu_glove_lit_colors() -> Array:
	"""The 16 RGBA entries of the glove lit CLUT (0x7d7c = the shared menu icon CLUT)."""
	return _menu_glove_lit_colors


func menu_glove_shadow_colors() -> Array:
	"""The 16 RGBA entries of the glove shadow CLUT (0x7dbc, semi-transparent emboss)."""
	return _menu_glove_shadow_colors


## --- detail/Status-screen stats-band labels (§15.14 row 14) ------------------

func has_stat_label(name: String) -> bool:
	return _stat_label_cells.has(name)


func stat_label_names() -> Array:
	return _stat_label_cells.keys()


func stat_label_rect(name: String) -> Rect2:
	"""The RANGETILE cell for a stats-band label token ('Move'/'AT'/'C-'/'EV'/'R'/...).
	The '-' in 'C-'/'S-'/'A-' is baked into the cell; 'C-EV' = 'C-' then 'EV'."""
	if not _stat_label_cells.has(name):
		push_error("RangeTileAtlas: no stat label cell for '%s'" % name)
		return Rect2()
	return _stat_label_cells[name]


func stat_label_colors() -> Array:
	"""The 16 RGBA entries of the stats-band label CLUT (0x7c3c = dark ink on tan)."""
	return _stat_label_colors


## --- word labels ------------------------------------------------------------

func has_label(name: String) -> bool:
	return _label_cells.has(name)


func label_names() -> Array:
	return _label_cells.keys()


func label_rect(name: String) -> Rect2:
	"""The atlas cell for an info-window word-label ('Hp'/'Mp'/'Ct'/'Exp.')."""
	if not _label_cells.has(name):
		push_error("RangeTileAtlas: no label cell for '%s'" % name)
		return Rect2()
	return _label_cells[name]


## --- lower-window title tabs (§15.19) ---------------------------------------

func has_window_tab(name: String) -> bool:
	return _window_tab_cells.has(name)


func window_tab_rect(name: String) -> Rect2:
	"""The atlas cell for a lower-window title tab ('Eqp'/'Ability') — a cream word
	cell drawn through the active-label CLUT 0x7cbc (§15.19)."""
	if not _window_tab_cells.has(name):
		push_error("RangeTileAtlas: no window-tab cell for '%s'" % name)
		return Rect2()
	return _window_tab_cells[name]


func window_tab_colors() -> Array:
	"""The 16 RGBA entries of the window-tab CLUT (0x7cbc = cream ink on dark fill)."""
	return _window_tab_colors


## --- HP/MP/CT bars -----------------------------------------------------------

func bar_swatch_rect() -> Rect2:
	"""The shared bar swatch cell in the atlas (a value/max-width SPRT samples it)."""
	return _bar_swatch


func bar_stat_count() -> int:
	return _bar_stats.size()


func bar_stat_name(i: int) -> String:
	if i < 0 or i >= _bar_stats.size():
		return ""
	return str(_bar_stats[i].get("name", ""))


func bar_stat_colors(i: int) -> Array:
	"""The 16-entry CLUT (Array[Color]) coloring stat `i`'s bar (idx1..3 = body)."""
	if i < 0 or i >= _bar_stats.size():
		return []
	return _bar_stats[i].get("colors", [])


## --- formation sort-tab header (§12.3.2) -------------------------------------

func has_header() -> bool:
	return not _header.is_empty()


func header_clut_colors(name: String) -> Array:
	"""One 16-entry header CLUT (Array[Color]) by name: 'inactive_label',
	'active_label', 'button', 'button_pressed'. ROM-authoritative (asset tail)."""
	return (_header.get("cluts", {}) as Dictionary).get(name, [])


func header_labels() -> Array:
	"""The six sort labels in header order: [{name, x, (x2_name, x2)}]."""
	return _header.get("labels", [])


func header_buttons() -> Dictionary:
	"""The two L2/R2 buttons: {left/right: {origin_x, y, pieces:[[dx,dy,u,v,w,h]]}}."""
	return _header.get("buttons", {})


func detail_pager() -> Dictionary:
	"""The Status-screen ◄L1/R1► unit-pager buttons (§15.22): {tpage, clut, clut_bg,
	left/right:{origin_x, y, pieces:[[dx,dy,u,v,w,h]]}}. Empty if the manifest predates it."""
	return _detail_pager


func header_box() -> Dictionary:
	"""The active-tab dark highlight box geometry {dx, y, w, h} (dx rel. active label x)."""
	return _header.get("box", {})


func header_tan_rect() -> Dictionary:
	"""The tan sort-bar window rect {x, y, w, h} (virtual px)."""
	return _header.get("tan_rect", {})


func header_color(name: String) -> Color:
	"""A framebuffer-measured header colour: 'tan_fill','tan_bevel','tan_edge','box_bg'."""
	var c: Array = (_header.get("colors", {}) as Dictionary).get(name, [])
	if c.size() >= 3:
		return Color8(int(c[0]), int(c[1]), int(c[2]), 255)
	return Color(0, 0, 0, 1)


## --- rendering helper -------------------------------------------------------

func cell_atlas_texture(rect: Rect2) -> AtlasTexture:
	"""An AtlasTexture clipped to `rect` over the shared atlas texture."""
	var at := AtlasTexture.new()
	at.atlas = texture
	at.region = rect
	return at
