class_name TypewriterController
extends RefCounted

## Renderer-agnostic FFT dialogue typewriter.
##
## Walks the structured token list baked by `disasm_event.py --with-text`
## (`{type, …}` records — see `DialogueOverlay` / `tools/_fft_strings.py`)
## with a frame-discrete cursor and drives a thin **sink**. The sink is any
## object implementing:
##
##     func typewriter_append(text: String) -> void   # reveal more text
##     func typewriter_set_palette(palette: int) -> void  # CLUT swap
##
## This is the shared core for BOTH the 2D `DialogueOverlay` (Dialog=0x09
## prayer) and the 3D boxed `DialogueBox` (Dialog=0x1X/0x9X). It owns the
## token-walking + delay/glyph pacing; the sink owns rendering.
##
## Cadence is the ROM's **sticky-budget** model (BATTLE.BIN `event_dialogue_tick`
## @0x8012F6D4; see TYPEWRITER_TEXT_CADENCE.md §7.1). A per-glyph `budget`
## (`local_58`) starts at **1**; each `{Delay NN}` sets `budget = NN` and it is
## **sticky** — it persists across subsequent glyphs until the next `{Delay}`.
## Every glyph AND every delay costs `budget · (3 − throttle)` VBlanks
## (`throttle` = `DAT_80165F88`, default 1 → factor 2). So a `{Delay 19}`=25 makes
## the following run of glyphs type slowly at 25·2=50 VBlanks/glyph (scenario-8's
## "…little money…"), not a single pause then fast typing.
##
##   1. Drain control tokens (color/newline/macro) — free, no frame cost. A
##      `delay` token sets `_budget = NN` (sticky) and arms
##      `_delay_frames_left = _budget * factor` (the delay's own cost).
##   2. Pending delay: tick it down once per display frame.
##   3. Else type one glyph, then idle `_budget * factor - 1` frames before the
##      next glyph (the glyph's cost, at the current sticky budget).
##   4. End-of-tokens deactivates + emits `completed`.

signal completed

## Emitted once per revealed glyph (from `_type_one_glyph`), i.e. the same
## per-glyph tick the PSX drives the text-typing SFX off. Free control tokens
## (newline/color/macro/delay drained in `_drain_free_tokens`) do NOT emit it.
## The owning renderer connects this to play the "Text Typing" cue.
signal glyph_typed

## ROM text-speed throttle (`DAT_80165F88`). The per-glyph/per-delay frame cost
## is `budget · (3 − throttle)`. Default **1** → factor 2 (the faithful overlay
## cadence). The boxed consumer sets **2** → factor 1, reproducing the ROM's
## net boxed cadence (2 glyphs per sleep on real HW ≈ 1 glyph/VBlank; §7.1). The
## owning renderer copies its own value in before `start()`.
var throttle: int = 1

var _sink: Object = null
var _tokens: Array = []
var _token_idx: int = 0
var _text_idx: int = 0          # cursor within current text token
## Sticky per-glyph budget (`local_58`): init 1, set by each `{Delay NN}`, never
## reset per glyph. The current per-glyph/per-delay cost is `_budget * factor`.
var _budget: int = 1
var _delay_frames_left: int = 0
var _glyph_cooldown: int = 0    # frames to wait before typing the next glyph
var _active: bool = false


## Per-glyph / per-delay frame cost factor = `3 − throttle` (ROM emit loop
## `budget · (3 − throttle)` @0x8012FB84). Floored at 1 so the model keeps the old
## tunables' "≥1 frame per glyph" guarantee (the removed `maxi(1, …)` setters):
## `throttle = 3` would otherwise give factor 0 → every delay free and the whole
## message revealing with no cadence. `{75}` Set Text Speed isn't wired yet, so in
## play `throttle` is 1 (overlay) / 2 (boxed); the floor only guards a future/live
## `throttle = 3`.
func _factor() -> int:
	return frame_factor(throttle)


## The same `3 − throttle` factor as a pure function of the throttle, for the
## OTHER ROM consumer of `event_text_glyph_throttle @0x80165F88`: the boxed
## dialog's open/close tween holds each curve entry for `3 − throttle` frames
## (inner loop `0x80132cac..0x80132d88` — `jal event_fiber_yield` then re-apply
## the SAME entry, `s0` counting to `3 − throttle`). `DialogueBox` calls this so
## the arithmetic has one home; see `DialogueBox.tween_frames_per_entry()`.
static func frame_factor(text_throttle: int) -> int:
	return maxi(1, 3 - text_throttle)


## The rendered text for a `macro` token (ADR-0066). A **name-insert** macro
## (`{Ramza}`, baked as `{"type":"macro","name":"Ramza"}`) resolves to the
## Character's CURRENT name via the `CharacterCatalog` — no braces, and it
## tracks a runtime rename. Any other ("word") macro stays literal `{Name}`.
## Shared by every macro render site (drain, `flatten`, and the overlay's width
## measurement) so name-vs-word is decided in exactly one place.
static func macro_text(tok: Dictionary) -> String:
	var macro_name := str(tok.get("name", "?"))
	var slug := CharacterCatalog.name_macro_slug(macro_name)
	if slug != "":
		return CharacterCatalog.display_name(slug)
	return "{%s}" % macro_name


## Begin walking `tokens`, pushing reveals into `sink`. Resets all cursor +
## delay state. `throttle` should be set before calling (the renderer copies
## its own value in).
func start(tokens: Array, sink: Object) -> void:
	_tokens = tokens
	_sink = sink
	_token_idx = 0
	_text_idx = 0
	_budget = 1
	_delay_frames_left = 0
	_glyph_cooldown = 0
	_active = true


func is_active() -> bool:
	return _active


## Stop the walker and drop token state. Does not touch the sink (the renderer
## clears its own visible text).
func reset() -> void:
	_tokens = []
	_token_idx = 0
	_text_idx = 0
	_budget = 1
	_delay_frames_left = 0
	_glyph_cooldown = 0
	_active = false


## Advance the cursor by N display frames. Exposed for unit tests that drive
## the walker without a real clock; the live renderer calls it with the
## per-frame `Engine.get_frames_drawn()` delta.
func advance_frames(advance: int) -> void:
	while advance > 0 and _active:
		# Step 1 — drain free tokens until a text-with-glyph, an armed delay,
		# or the end of the list.
		_drain_free_tokens()
		if not _active:
			return
		# Step 2 — pending delay: spend one frame ticking it.
		if _delay_frames_left > 0:
			_delay_frames_left -= 1
			advance -= 1
			continue
		# Step 3 — type one glyph at the configured per-glyph cadence.
		if _glyph_cooldown > 0:
			_glyph_cooldown -= 1
			advance -= 1
			continue
		if not _type_one_glyph():
			# No glyph available (shouldn't happen after drain) — bail.
			return
		# Glyph cost = current sticky budget · factor (the just-typed glyph inherits
		# the budget set by the last {Delay}); −1 because this frame typed it.
		_glyph_cooldown = max(0, _budget * _factor() - 1)
		advance -= 1


# Drain color/newline/macro/empty-text tokens until we hit either a text token
# with characters remaining or a delay token (which we ALSO consume here to arm
# `_delay_frames_left`), or run out of tokens.
func _drain_free_tokens() -> void:
	while _active and _token_idx < _tokens.size():
		var tok: Dictionary = _tokens[_token_idx]
		var kind: String = tok.get("type", "")
		if kind == "text":
			var value: String = tok.get("value", "")
			if _text_idx < value.length():
				return
			# Exhausted — advance to next token.
			_token_idx += 1
			_text_idx = 0
			continue
		if kind == "delay":
			# Sticky: {Delay NN} sets the budget; it persists across the following
			# glyphs until the next {Delay}. The delay's own cost is budget·factor.
			_budget = int(tok.get("frames", 0))
			_delay_frames_left = _budget * _factor()
			_token_idx += 1
			return
		if kind == "newline":
			_sink.typewriter_append("\n")
			_token_idx += 1
			continue
		if kind == "color":
			_sink.typewriter_set_palette(int(tok.get("palette", 0)))
			_token_idx += 1
			continue
		if kind == "macro":
			_sink.typewriter_append(macro_text(tok))
			_token_idx += 1
			continue
		# Unknown — skip rather than stall.
		_token_idx += 1

	# Drained past the end.
	if _token_idx >= _tokens.size():
		_active = false
		emit_signal("completed")


# Type one character from the current text token. Returns true if a glyph was
# typed. Caller must have run `_drain_free_tokens` first.
func _type_one_glyph() -> bool:
	if _token_idx >= _tokens.size():
		return false
	var tok: Dictionary = _tokens[_token_idx]
	if tok.get("type", "") != "text":
		return false
	var value: String = tok.get("value", "")
	if _text_idx >= value.length():
		return false
	_sink.typewriter_append(value[_text_idx])
	_text_idx += 1
	emit_signal("glyph_typed")
	if _text_idx >= value.length():
		_token_idx += 1
		_text_idx = 0
	return true


## Pure helper: flatten a token list to its FINAL rendered text plus a
## per-character palette array (one entry per char in `text`, including the
## `\n` newline chars). Delays/colors contribute no text; colors set the
## palette for subsequently-appended chars. Used by renderers that pre-build
## the full string and reveal it via a visible-char count (e.g. `DialogueBox`
## over `UIText`) rather than accumulating incrementally.
static func flatten(tokens: Array) -> Dictionary:
	var text := ""
	var palettes := PackedInt32Array()
	var pal := 0
	for tok in tokens:
		if not (tok is Dictionary):
			continue
		var kind: String = tok.get("type", "")
		if kind == "text":
			var v: String = str(tok.get("value", ""))
			for i in range(v.length()):
				text += v[i]
				palettes.append(pal)
		elif kind == "macro":
			var lit := macro_text(tok)
			for i in range(lit.length()):
				text += lit[i]
				palettes.append(pal)
		elif kind == "newline":
			text += "\n"
			palettes.append(pal)
		elif kind == "color":
			pal = int(tok.get("palette", 0))
	return {"text": text, "palettes": palettes}
