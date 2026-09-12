class_name DialogueOverlay
extends CanvasLayer

## Screen-space typewriter overlay for FFT event-script `0x10 Display Message`
## (overlay variant — Dialog byte = 0x09; chapel prayer is the canonical hit).
##
## Token-driven: the bytecode bake (`tools/disasm_event.py --with-text`) emits
## `dialogue.tokens = [{type, …}]` per `0x10` record; this overlay walks those
## tokens with a frame-discrete cursor. The token taxonomy is documented in
## `tools/_fft_strings.py`:
##
##     {"type": "text",    "value": "..."}      # printable glyphs
##     {"type": "delay",   "frames": N}         # advance N display frames
##     {"type": "newline"}                      # newline / line break
##     {"type": "color",   "palette": N}        # current color palette
##     {"type": "macro",   "name": "Ramza"}     # macro stand-in
##
## Timing is frame-discrete, pumped by `ScenarioVM._tick_once` (the VM's 60 Hz
## logical tick — one call per console VBlank) via `advance_frames`, so the
## type-out is host-refresh-independent. Cadence is the ROM's sticky-budget model
## (a per-glyph budget set by each `{Delay NN}`, costing `budget · (3 − throttle)`
## VBlanks) — see `TypewriterController` and `TYPEWRITER_TEXT_CADENCE.md` §7.1.
##
## PSX coords: hypothesis is 320×224 top-left origin; `Y=0x3C` (=60) places
## the prayer ~27% down the frame. The overlay's `_psx_pixels_per_godot_unit`
## scaler maps PSX pixels to the current viewport width.
##
## Glyphs come from the PSX font atlas at `res://assets/fonts/font_atlas.tga`
## + `font_meta.json` (parsed by `godot-learning/tools/parse_fft_font.py`). Each
## glyph is rendered as a `TextureRect` child sampling a 10×14 cell from the
## atlas. Phase 0 round-4 grounding (2026-06-28) confirmed the same atlas is
## what BATTLE.BIN uploads to VRAM (0, 494) during dialog runs:
##   - char_height = 14 (matches `glyph_cell_height` in
##     `display_message_overlay_decode.md` C-table)
##   - char 0xFA (space) width = 0x0A (matches the per-char width table at
##     runtime RAM `0x801660FC` we dumped via `probe_dialog_font_atlas.py`)
##   - parser sources from BATTLE.BIN master font at file offset `0x000E7614`;
##     the runtime buffer at `0x800956E4` is the same data, post-decode.

const _PSX_WIDTH := 320.0
const _PSX_HEIGHT := 224.0
const _FONT_ATLAS_PATH := "res://assets/fonts/font_atlas.tga"
const _FONT_META_PATH := "res://assets/fonts/font_meta.json"

## Hard-coded space advance. The BATTLE.BIN per-char width table at
## `0x801661FC + char` returns 0x0A=10 for the space (char 0xFA), but the
## dialog renderer at `0x80132578..0x80132588` SPECIAL-CASES space and
## advances the X cursor by exactly 0x04 instead of consulting the width
## table. The 10 in the table is unreachable for spaces at runtime.
const _SPACE_PSX_WIDTH := 4.0

## Vertical placement model for box-type-0 messages (Dialog & 0x70 == 0), derived
## from PSX capture (display_message_overlay_decode.md Part Z §Z.3). The Dialog
## byte's low 2 bits are the valign:
const _VALIGN_TOP := 1     # prayer (Dialog 0x09) — first line at the authored `Y`
const _VALIGN_BOTTOM := 2  # not observed in ch.1/scn8; treated like Center for now
const _VALIGN_CENTER := 3  # scn8 narration (Dialog 0x0B) — per-page vertical centre

## Center-valign anchoring (PSX framebuffer rows; same units as the overlay's
## `psx_y`, since the prayer's `Y=60` maps 1:1). Each page's first line sits at
## `max(_TOP_MARGIN, _CENTER_ANCHOR − LINE_PITCH/2 · n_content_lines)` — centred
## about y≈116 but never rising above the y≈76 top margin (fits pages of 3/6/5
## content lines at measured tops 92/75/76). Line pitch is 16 on PSX (the glyph
## CELL is 14 tall; lines are spaced 16 apart).
const _CENTER_ANCHOR_PSX := 116.0
const _TOP_MARGIN_PSX := 76.0
const _LINE_PITCH_PSX := 16.0

## Page-break token: a `{Delay ≥ this}` (60-frame page-hold) that is followed by a
## newline + more text closes the current page and clears to a fresh one
## (§Z.6 #1). `{Delay 19}`=25 and shorter are ordinary mid-line pauses, never
## breaks; the prayer's trailing `{Delay 3C}` has no following text so it doesn't
## paginate. Message-derived; tunable if a scenario uses a different hold value.
const _PAGE_BREAK_MIN_DELAY := 0x3C

## Prayer text FADE-OUT (living doc Part A / §C.1). On dismiss the ROM does NOT
## pop the prayer off — it ramps the composed-text primitive's Gouraud RGB
## `0x80 → 0x38` in steps of `−8`, one step per 60 Hz fiber yield (~9-10 frames),
## THEN frees the window handle (text disappears). It is a BRIGHTNESS multiply
## (not alpha), uniform across the two prayer lines, so a single
## `_container.modulate` ramp is faithful. There is NO parsed asset for this —
## these are the ROM *code* constants (fiber loop `0x80131628`, writers
## `0x8013164c/74/9c`, floor test `s1 >= 0x31`), documented inline so nobody
## hunts for a missing fade table.
const _FADE_START_V := 0x80   # neutral brightness = 1.0 (0x80/0x80)
const _FADE_STEP_V := 8       # −8 per 60 Hz tick
const _FADE_FLOOR_V := 0x38   # last drawn value ≈ 0.4375, then handle-free removal

## ROM text-speed throttle (`DAT_80165F88`). Drives the shared
## `TypewriterController`'s sticky-budget cadence: per-glyph/per-delay cost =
## `budget · (3 − throttle)`, where `budget` starts at 1 and each `{Delay NN}`
## sets it (sticky). Default **1** → factor 2 = the faithful prayer cadence (a
## leading `{Delay 05}` → budget 5 → 10 VBlanks/glyph). There is no `{75}` Set
## Text Speed handler wired yet, so this is fixed at 1 in play.
## TODO: drive from `{75}` Set Text Speed when that opcode lands.
## Live-tunable via the F3 Scenario VM debug panel.
var throttle: int = 1

## Signed PSX-pixel offset added to the bytecode-provided X/Y. Use for live
## position tuning until B.4 locks down the coord convention. Live-tunable.
var psx_x_offset: int = 0
var psx_y_offset: int = 0

## Center-anchor mode for X. Round-5 (2026-06-29) corrected the PSX-derived
## model: the bytecode X is a signed CENTER offset around screen midline,
## but the text block itself is LEFT-ANCHORED within that centered span —
## glyphs blit rightward as typing progresses; the left edge never moves.
## The staging code at `0x80130bac` computes:
##
##   local_b4 = ANCHOR − (full_message_text_width >> 1) − 4
##
## ONCE before typing starts (`text_width` = the MAX line width across the
## entire message), then sets that as the fixed left edge. Subsequent
## glyphs blit at `(local_b4 + cursor_x, baseline_y)`; the cursor advances
## rightward as glyphs type in.
##
## With `auto_center_x = true` (default), we pre-measure the full block
## width in `show_overlay` and position the container at the left edge of
## the centered block: `(viewport/2 + (X − block_width/2) * scale, Y * scale)`.
## `_redraw_label` lays glyphs out from `x_cursor = 0` rightward, so the
## LEFTMOST glyph stays put as typing progresses. With `auto_center_x =
## false`, debug mode — container sits at raw `(X*scale, Y*scale)`.
var auto_center_x: bool = true

## Extra scale applied on top of the PSX→viewport mapping. 1.0 = native PSX
## pixel density (the font atlas is authored at 10×14 PSX-px per glyph and
## scaled to match the viewport's PSX-width ratio). Live-tunable.
var font_pixel_size: int = 1:
	set(value):
		font_pixel_size = max(1, value)
		if _container != null and is_active():
			_redraw_label()

signal completed

var current_text: String = ""
var palette: int = 0

## The raw Dialog byte of the active message (low 2 bits = valign). Default 0x09
## = the prayer (Top), so callers/tests that omit it keep the old behaviour.
var dialog_byte: int = 0x09

## Pagination state. A long narration ({10} Dialog=0x0B) splits into pages at each
## `{Delay ≥ _PAGE_BREAK_MIN_DELAY}`-followed-by-text (§Z.6). Each page is a token
## sub-list; `_page_idx` walks them, re-placing + re-typing (with a clear between)
## so the barrier holds across the whole narration. Single-page messages (prayer)
## yield one page and behave exactly as before.
var _pages: Array = []
var _page_idx: int = 0
## Monotonic across pages so the VM's progress-aware watchdog (overlay_progress)
## keeps advancing over page clears (where current_text resets to "").
var _pages_completed_glyphs: int = 0
## Authored placement of the active message, re-applied per page (each page
## re-centres to its own line count).
var _msg_psx_x: int = 0
var _msg_psx_y: int = 0

var _container: Control = null
var _font_texture: Texture2D = null
var _font_meta: Dictionary = {}      # char_string → {atlas_x, atlas_y, width}
var _font_char_height: int = 14
var _font_default_char_width: int = 10
# Token-walking + pacing now live in the shared TypewriterController; this
# overlay is its 2D render sink (see typewriter_append/typewriter_set_palette).
var _typewriter: TypewriterController = null
# MAX line-width across all lines in the active message, in PSX pixels.
# Computed once per `show_overlay` and consumed by `_position_label` to
# pin the container at the block's left edge (round-5 Q10 fix).
var _full_block_width_psx: float = 0.0

# Fade-out ramp state (Part A). `_fading` is armed by `clear()` when there is
# visible prayer text; the ramp is pumped one step per `advance_frames` tick
# (the VM's 60 Hz `_tick_once`), and completes with a `_hide_now()` teardown.
var _fading: bool = false
var _fade_v: int = _FADE_START_V


func _ready() -> void:
	layer = 90  # Below FadeLayer (100) so a fade-to-black hides the dialog.
	_load_font()
	_ensure_typewriter()
	_container = Control.new()
	_container.name = "DialogueText"
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.modulate = Color(1, 1, 1, 1)
	add_child(_container)
	visible = false


# Lazily build the shared walker + wire its completion through to the overlay's
# own `completed` signal. Safe to call before _ready (tests drive show_overlay
# without a tree); idempotent.
func _ensure_typewriter() -> void:
	if _typewriter != null:
		return
	_typewriter = TypewriterController.new()
	# Per-PAGE completion drives page advance; the overall `completed` fires only
	# after the last page (see _on_page_complete).
	_typewriter.completed.connect(func() -> void: _on_page_complete())
	# One "Text Typing" blip per revealed glyph (PSX system SFX 0x73).
	_typewriter.glyph_typed.connect(func() -> void: SfxRouter.play_cue("ui.text_typing"))


# Load the PSX font atlas + metadata once. Safe to call before _ready (used
# by both editor preview and runtime). Tests that only assert against
# `current_text` don't need the atlas to be present — the loader silently
# leaves `_font_texture` null and `_redraw_label` becomes a no-op for the
# missing-atlas case (the typewriter state still advances correctly).
func _load_font() -> void:
	if ResourceLoader.exists(_FONT_ATLAS_PATH):
		_font_texture = load(_FONT_ATLAS_PATH) as Texture2D
	if FileAccess.file_exists(_FONT_META_PATH):
		var f := FileAccess.open(_FONT_META_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_font_char_height = int(parsed.get("char_height", 14))
				_font_default_char_width = int(parsed.get("char_width", 10))
				var by_char := {}
				for entry in parsed.get("characters", {}).values():
					if entry is Dictionary and entry.has("char"):
						by_char[entry["char"]] = entry
				_font_meta = by_char


## Begin the typewriter at PSX-pixel position (`psx_x`, `psx_y`). `tokens` is
## the structured list baked by `disasm_event.py --with-text`. Caller is
## responsible for clearing the previous overlay before starting a new one;
## a fresh `show_overlay` resets the cursor + delay state.
func show_overlay(tokens: Array, psx_x: int, psx_y: int, color_palette: int = 0,
		dialog: int = 0x09) -> void:
	_ensure_typewriter()
	# A fresh message cancels any in-flight fade and restores full brightness
	# (clear() may have started one; show_overlay replaces the overlay outright).
	_cancel_fade()
	dialog_byte = dialog
	palette = color_palette
	current_text = ""
	_msg_psx_x = psx_x
	_msg_psx_y = psx_y
	# Copy the live-tunable throttle into the walker (tests set this on the
	# overlay before calling show_overlay).
	_typewriter.throttle = throttle
	# Split a long narration into pages (§Z.6). A single-page message (the prayer)
	# yields exactly one page → identical behaviour to before pagination.
	_pages = _split_pages(tokens)
	if _pages.is_empty():
		_pages = [tokens]
	_pages_completed_glyphs = 0
	visible = true
	_start_page(0)


## Begin typing page `i`: reset the visible text, re-centre for this page's line
## count, and start the walker on the page's token sub-list.
func _start_page(i: int) -> void:
	_page_idx = i
	current_text = ""
	var page_tokens: Array = _pages[i]
	_full_block_width_psx = _measure_full_block_width(page_tokens)
	_typewriter.start(page_tokens, self)
	_position_label(_msg_psx_x, _msg_psx_y)
	_redraw_label()


## A page's walker finished. Advance to the next page (clearing the screen), or —
## if this was the last page — signal the whole message complete. The lingering
## last-page text is left on screen (PSX leaves it up until the next message /
## Show Graphic clears it — the pc_38 park shows it still up at Color Field).
func _on_page_complete() -> void:
	if _page_idx + 1 < _pages.size():
		# Bank this page's glyphs only when we CLEAR to the next page (where
		# current_text resets), so overlay_progress = banked + current_text stays
		# monotonic. Banking on the LAST page would double-count its glyphs during
		# the dismiss fade (current_text isn't cleared until _hide_now).
		_pages_completed_glyphs += current_text.length()
		_start_page(_page_idx + 1)
	else:
		emit_signal("completed")
		# Box-type-0 overlays SELF-DISMISS when the message ends — no input, no
		# downstream opcode. The ROM composed-text primitive Gouraud-fades
		# 0x80→0x38 then the window frees, driven off the message's own terminator
		# (static: fade seed `s1=0x80` @0x80131624, ramp `−8` @0x801316A4, free at
		# the `0xFF` terminator; dynamic: the scn8 narration vanishes on its own
		# before the {7D} Show Graphic — captured 2026-07-10). This is the SAME path
		# as the chapel prayer — it just fires on completion instead of waiting for
		# the next Display Message's clear(). The fade keeps is_active() true, so the
		# Task=1 barrier holds until the text is actually gone (matching the PSX
		# dialog-task lifetime, where the task is live through the fade + teardown).
		_begin_auto_dismiss()


# Start the box-type-0 self-dismiss: fade the composed text out if any is showing,
# else hide immediately. Reuses the ROM fade ramp (Part A). No-op if already fading.
func _begin_auto_dismiss() -> void:
	if _fading:
		return
	clear()  # same fade-if-text-else-hide path as the external next-message dismiss


# --- TypewriterController sink ------------------------------------------------

## Sink hook: append revealed text (one glyph, a `\n`, or a macro literal).
func typewriter_append(text: String) -> void:
	current_text += text
	_redraw_label()


## Sink hook: a `{Color NN}` CLUT swap.
func typewriter_set_palette(new_palette: int) -> void:
	palette = new_palette


# Walk the full token list once and return the MAX line-width (in PSX
# pixels) across every line in the message. Used by `_position_label` to
# pin the container at `anchor − full_width / 2` (round-5 Q10 fix). Lines
# are split by `newline` tokens; only `text` token characters and macro
# names contribute to the line cursor.
func _measure_full_block_width(tokens: Array) -> float:
	var max_line: float = 0.0
	var cur_line: float = 0.0
	for tok in tokens:
		if not (tok is Dictionary):
			continue
		var kind: String = tok.get("type", "")
		if kind == "text":
			var value: String = tok.get("value", "")
			for i in range(value.length()):
				cur_line += _glyph_width(value[i])
		elif kind == "macro":
			# Macros render via the shared `TypewriterController.macro_text`
			# seam (name inserts → Character name, else literal `{Name}`), so
			# width must measure the SAME resolved string — see ADR-0066.
			var literal := TypewriterController.macro_text(tok)
			for i in range(literal.length()):
				cur_line += _glyph_width(literal[i])
		elif kind == "newline":
			if cur_line > max_line:
				max_line = cur_line
			cur_line = 0.0
	if cur_line > max_line:
		max_line = cur_line
	return max_line


func _glyph_width(ch: String) -> float:
	if ch == " ":
		return _SPACE_PSX_WIDTH
	var meta = _font_meta.get(ch, null)
	if meta is Dictionary:
		return float(meta.get("width", _font_default_char_width))
	return float(_font_default_char_width)


# --- Pagination (§Z.6) --------------------------------------------------------

## Split a token list into pages. A page ends at a `{Delay ≥ _PAGE_BREAK_MIN_DELAY}`
## that is followed by a `{Newline}` (i.e. more lines) — that newline is the page
## separator and is consumed. Leading/trailing blank lines are stripped from each
## page; all-blank pages are dropped. The prayer's trailing `{Delay 3C}` has no
## following newline, so it stays a single page. Verified against the scenario-8
## narration (3 pages) and the prayer (1 page).
func _split_pages(tokens: Array) -> Array:
	var pages: Array = []
	var cur: Array = []
	var saw_long := false
	for tok in tokens:
		if not (tok is Dictionary):
			continue
		var kind: String = tok.get("type", "")
		if kind == "delay" and int(tok.get("frames", 0)) >= _PAGE_BREAK_MIN_DELAY:
			saw_long = true
			cur.append(tok)
		elif kind == "newline" and saw_long:
			pages.append(_strip_blank_edges(cur))
			cur = []
			saw_long = false
		else:
			cur.append(tok)
	if not cur.is_empty():
		pages.append(_strip_blank_edges(cur))
	var out: Array = []
	for p in pages:
		if _count_content_lines(p) > 0:
			out.append(p)
	return out


## True for a token that forms (part of) a blank line at a page edge: a newline or
## a whitespace-only text run. Delays/colors/macros/real text are NOT blank.
func _is_blank_edge_token(tok) -> bool:
	if not (tok is Dictionary):
		return true
	var kind: String = tok.get("type", "")
	if kind == "newline":
		return true
	if kind == "text":
		return String(tok.get("value", "")).strip_edges() == ""
	return false


## Drop leading + trailing blank-line tokens so a page's first rendered line is its
## first line with real glyphs (matches PSX — leading blank `{Newline}` runs from a
## page break don't push the content down or count toward centering).
func _strip_blank_edges(tokens: Array) -> Array:
	var a := 0
	var b := tokens.size()
	while a < b and _is_blank_edge_token(tokens[a]):
		a += 1
	while b > a and _is_blank_edge_token(tokens[b - 1]):
		b -= 1
	return tokens.slice(a, b)


## Count the lines in a page that carry real glyphs (a line = text between newlines;
## whitespace-only lines don't count). Drives the per-page vertical centring.
func _count_content_lines(tokens: Array) -> int:
	var count := 0
	var line_has_content := false
	for tok in tokens:
		if not (tok is Dictionary):
			continue
		var kind: String = tok.get("type", "")
		if kind == "newline":
			if line_has_content:
				count += 1
			line_has_content = false
		elif kind == "text":
			if String(tok.get("value", "")).strip_edges() != "":
				line_has_content = true
		elif kind == "macro":
			line_has_content = true
	if line_has_content:
		count += 1
	return count


## First-line top for the ACTIVE page in PSX-`Y` units, honoring valign (§Z.3):
## Center → `max(top_margin, centre − 8·n_lines)` + authored Y; Top/other → Y.
func _first_line_psx_y(psx_y: int) -> float:
	var valign := dialog_byte & 0x3
	if valign == _VALIGN_CENTER or valign == _VALIGN_BOTTOM:
		var n := 1
		if _page_idx >= 0 and _page_idx < _pages.size():
			n = maxi(1, _count_content_lines(_pages[_page_idx]))
		var centered := _CENTER_ANCHOR_PSX - (_LINE_PITCH_PSX * 0.5) * float(n)
		return maxf(_TOP_MARGIN_PSX, centered) + float(psx_y)
	return float(psx_y)


## Dismiss the overlay. Faithful to the ROM (Part A / §C.1): if prayer text is
## on screen, ramp its brightness `0x80 → 0x38` over ~9 ticks and THEN free it
## (a fade-out, NOT an instant pop). With nothing visible, hide immediately.
## The ramp is pumped by `advance_frames` off the VM's 60 Hz `_tick_once`, and
## `is_active()` stays true through the fade so the VM keeps pumping it.
func clear() -> void:
	_ensure_typewriter()
	if not current_text.is_empty() and _container != null:
		_start_fade()
		return
	_hide_now()


# Immediate teardown (no fade): reset the walker, drop the text, hide.
func _hide_now() -> void:
	_ensure_typewriter()
	_cancel_fade()
	_typewriter.reset()
	current_text = ""
	_redraw_label()
	visible = false


# --- Prayer fade-out ramp (Part A) -------------------------------------------

func _start_fade() -> void:
	_fading = true
	_fade_v = _FADE_START_V
	_apply_fade_brightness()


func _cancel_fade() -> void:
	_fading = false
	if _container != null:
		_container.modulate = Color(1, 1, 1, 1)


func _apply_fade_brightness() -> void:
	if _container == null:
		return
	var b := float(_fade_v) / float(_FADE_START_V)   # 0x80 → 1.0
	_container.modulate = Color(b, b, b, 1.0)


# Ramp the brightness down one step per tick; when it drops below the 0x38 floor
# the ROM frees the window handle → the text pops off. Mirrors the fiber loop
# `0x80131628` (writers …164c/74/9c, `addiu s1,s1,-8`, `while s1 >= 0x31`).
func _advance_fade(frames: int) -> void:
	for _i in range(frames):
		if not _fading:
			return
		_fade_v -= _FADE_STEP_V
		if _fade_v < _FADE_FLOOR_V:
			_hide_now()
			return
		_apply_fade_brightness()


func is_active() -> bool:
	if _fading:
		return true
	if _typewriter != null and _typewriter.is_active():
		return true
	# Still active while pages remain to be typed (holds the Task=1 barrier across
	# the whole multi-page narration, including the instant between-page clear).
	return _page_idx + 1 < _pages.size()


## Monotonic-ish progress counter for the VM's Task=1 progress-aware watchdog
## (ScenarioVM._hold_wait_until). Changes whenever the overlay does visible work:
## a revealed glyph grows `current_text`, and the dismiss fade advances `_fade_v`.
## A long-but-advancing narration keeps this ticking so the barrier holds the full
## duration; a genuinely-stuck overlay leaves it constant so the deadlock backstop
## still fires. Value has no units — only *change* matters.
func overlay_progress() -> int:
	# Monotonic across page clears: completed-page glyphs + the current page's
	# revealed glyphs (so it keeps climbing even when current_text resets between
	# pages) + the fade term during the dismiss ramp + the page index.
	var fade_term := (_FADE_START_V - _fade_v) if _fading else 0
	return (_pages_completed_glyphs + current_text.length()) * 256 + fade_term + _page_idx


# Cached layout context — populated by `_position_label`, consumed by
# `_redraw_label` so per-glyph TextureRects use the same PSX→viewport scale
# the container was placed with.
var _layout_scale: float = 1.0
var _layout_psx_x: int = 0
var _layout_psx_y: int = 0


func _position_label(psx_x: int, psx_y: int) -> void:
	# Map PSX 320×224 to the current viewport. X-axis ratio drives both the
	# horizontal scale (font density matches PSX) and Y (no aspect-correction
	# — preserves PSX layout faithfully).
	if _container == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var scale := vp.x / _PSX_WIDTH
	_layout_scale = scale
	_layout_psx_x = psx_x + psx_x_offset
	# valign-aware first-line Y: Center pages centre by line count (clamped to the
	# top margin); Top (prayer) uses the authored Y. See _first_line_psx_y / §Z.3.
	_layout_psx_y = int(round(_first_line_psx_y(psx_y))) + psx_y_offset
	var y_px := float(_layout_psx_y) * scale
	if auto_center_x:
		# Round-5 ROM-derived: bytecode X is a signed center offset around the
		# screen midline; the text BLOCK is left-anchored within that span.
		# Container origin sits at the block's LEFT edge:
		#   left_edge_psx = X − full_block_width / 2
		# Glyphs blit rightward from x=0 (_redraw_label) so the leftmost glyph
		# is pinned and never drifts as typing progresses.
		var left_edge_psx := float(_layout_psx_x) - _full_block_width_psx * 0.5
		_container.position = Vector2(vp.x * 0.5 + left_edge_psx * scale, y_px)
	else:
		# Left-anchor fallback (debug only). Scaled-pixel position from the
		# raw bytecode X — useful for inspecting non-overlay variants where
		# X really is a literal left edge.
		var x_px := float(_layout_psx_x) * scale
		_container.position = Vector2(x_px, y_px)
	_container.size = Vector2(vp.x, vp.y)


## Advance the typewriter cursor by N display frames. The live reveal clock is
## driven by `ScenarioVM._tick_once` (the VM's 60 Hz logical tick, one call per
## console VBlank) rather than a per-node `_process` reading
## `Engine.get_frames_drawn()` — that made the type-out speed depend on the host
## refresh rate. Unit tests call this directly to drive the overlay without a
## real clock. Delegates to the shared `TypewriterController`, which pushes
## reveals back through this overlay's sink hooks (`typewriter_append` /
## `typewriter_set_palette`).
func advance_frames(advance: int) -> void:
	# During the dismiss fade the typewriter is done; spend the ticks on the
	# brightness ramp instead (Part A). Otherwise drive the type-out reveal.
	# Dispatch each frame to the fade OR the typewriter based on the CURRENT state.
	# A single batched call can cross typewriter-completion, which arms the
	# self-dismiss fade mid-batch (_on_page_complete → _begin_auto_dismiss); a plain
	# `_typewriter.advance_frames(advance)` would return with the remaining frames
	# unspent and the fade never advancing (overlay wedged "armed but not fading").
	# Stepping one frame at a time hands the leftover frames to the fade correctly.
	# Production pumps 1/frame, so this is a no-op cost there.
	for _i in range(advance):
		if _fading:
			_advance_fade(1)
		elif _typewriter != null:
			_typewriter.advance_frames(1)
		else:
			return


func _redraw_label() -> void:
	# Tear down and rebuild per-glyph TextureRect children. The current_text
	# is short (chapel prayer ~70 glyphs) so brute rebuild per typed glyph is
	# fine; profiled and not the bottleneck. Children inherit `_container`'s
	# modulate, so re-tint via `_container.modulate` instead of per-glyph.
	if _container == null:
		return
	for child in _container.get_children():
		child.queue_free()
	if current_text.is_empty():
		return
	# When the font atlas is missing (e.g. minimal test harness without the
	# .tga in res://), skip rendering. `current_text` still advances correctly
	# so unit tests assert against the typewriter contract.
	if _font_texture == null or _font_meta.is_empty():
		return

	var scale := _layout_scale * float(font_pixel_size)
	var ch_h := float(_font_char_height)

	# Pre-compute per-line glyph + width records. Width uses the same rule
	# as `_glyph_width` so the runtime cursor and the show_overlay
	# pre-measurement agree to the pixel — space gets the ROM-hardcoded
	# 4px advance, not the BATTLE.BIN width-table 10.
	var lines: Array = []   # array of {chars: [{char, meta, width}]}
	var cur_chars: Array = []
	for i in range(current_text.length()):
		var ch := current_text[i]
		if ch == "\n":
			lines.append({"chars": cur_chars})
			cur_chars = []
			continue
		var meta = _font_meta.get(ch, null)
		var w: float = _glyph_width(ch)
		cur_chars.append({"char": ch, "meta": meta, "width": w})
	lines.append({"chars": cur_chars})

	var y_cursor: float = 0.0
	for line in lines:
		var line_chars: Array = line["chars"]
		# Round-5 ROM-derived: glyphs blit rightward from the block's left
		# edge. `_position_label` already pinned the container at that left
		# edge (LEFT-anchored within the centered span), so x_cursor starts
		# at 0 regardless of line width — the leftmost glyph stays put as
		# typing progresses and shorter lines are ragged-right within the
		# MAX-line-width block.
		var x_cursor: float = 0.0
		for entry in line_chars:
			var meta = entry["meta"]
			var w: float = float(entry["width"])
			# Skip drawing the space cell — the FFT atlas at char ' ' has a
			# small visible marker baked in (parser artifact); spacing is
			# carried by the cursor advance below.
			if entry["char"] == " ":
				x_cursor += w * scale
				continue
			if meta is Dictionary:
				var ax: int = int(meta.get("atlas_x", 0))
				var ay: int = int(meta.get("atlas_y", 0))
				var rect := TextureRect.new()
				rect.texture = _font_texture
				rect.stretch_mode = TextureRect.STRETCH_SCALE
				rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
				# Nearest-neighbour: the atlas pixels are 1:1 PSX-px and we
				# scale them up integer multiples to PSX-pixel-grid the
				# viewport. Linear filtering blends with transparent atlas
				# borders and darkens the glyph body — saw cream (248,240,208)
				# rendering as olive (102,99,81) with the default filter.
				rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
				# Region: pull the 10×14 cell out of the atlas (TextureRect
				# uses an AtlasTexture wrapper for sub-region sampling).
				var at := AtlasTexture.new()
				at.atlas = _font_texture
				at.region = Rect2(ax, ay, _font_default_char_width, _font_char_height)
				rect.texture = at
				rect.position = Vector2(x_cursor, y_cursor)
				rect.size = Vector2(_font_default_char_width * scale, ch_h * scale)
				_container.add_child(rect)
			x_cursor += w * scale
		# PSX spaces text lines 16 px apart (the glyph CELL is 14 tall) — §Z.3.
		y_cursor += _LINE_PITCH_PSX * scale
