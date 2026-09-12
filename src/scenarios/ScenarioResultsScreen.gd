class_name ScenarioResultsScreen
extends ScreenOverlayQuad
## Event-script {78} "Display Conditions" — the battle **intro** banner
## ("Conditions for Winning" over that battle's objective, then "READY!") and the
## battle **outro** (CONGRATULATIONS! / This Battle Is Complete!, BONUS MONEY + the
## gil reel, and three screens that decide for themselves they have nothing to draw).
## Owned by ScenarioVM, ticked once per 60 Hz VM frame OUTSIDE the halt gate, so a
## screen plays in full while the VM parks on the {E5} Wait For Instruction(0x38)
## barrier that follows every {78}.
##
## [b]{78}'s first operand is a MODE, not a conditions id[/b]
## (research/working_documents/BATTLE_RESULTS_SCREEN.md §13 — the upward trace from
## `0x801CAFD4`, whose only caller in all of RAM is this opcode). The dispatcher
## hands each mode to its own screen body:
##
## | mode | screen | `Time` used? |
## |------|--------|--------------|
## | 0    | `READY!`                                      | yes — the hold |
## | 2    | CONGRATULATIONS! + This Battle Is Complete!   | no |
## | 3    | BONUS MONEY + the gil reel                    | no |
## | 4/5/6| WAR TROPHIES / WARNING / PARTING SHOT!!       | no |
## | 7    | the recruit flow                              | no |
## | >= 8 | the victory-condition banner, page `mode - 8` | yes — the hold |
##
## ⚠️ [b]`Time` reaches only mode 0 and modes >= 8.[/b] The dispatcher spawns modes
## 1-7 with all three params zero (`0x8014CA38(s1, 0, 0, 0)`); those bodies hard-code
## their own durations. A port that reads the operand for the victory text or the gil
## reel is reading a byte the ROM ignores.
##
## [b]The outro is a fixed six-step pipeline, not a set of conditional screens.[/b]
## A census of all 500 events (§13) finds modes 2,3,4,5,6,7 emitted unconditionally,
## in that order, in all 64 outro scripts — nothing upstream decides whether there are
## war trophies or a departing unit. Each body decides for itself, which is why
## modes 4-6 can be honest no-ops here (see `_MODES_WITH_NO_LAYOUT`).
##
## [b]Rendering.[/b] The PSX builds a real prim list, so this does too: an ArrayMesh
## per blend mode whose vertices are PSX framebuffer pixels, drawn by
## assets/shaders/results_screen_{mix,add,sub}.gdshader. Assets come from
## assets/scenarios/results/ (tools/parse_bonus.py, out of EVENT/BONUS.BIN and the
## overlay image EVENT/REQUIRE.OUT).

## The display-space fold, reached through the schema addon's facade — the addon names
## its own internals by path and publishes them here (ADR-0212 dec. 1), so a host binds
## the facade constant rather than the file.
const Fold = ExMateriaSchema.Fold
const DepthMode = ExMateriaSchema.DepthMode

## The banner's rungs in the fold's order ladder, ABOVE ScenarioDarkScreen's dim at
## rung 0 — the PSX draws the text at OT bucket 0 and the tint at bucket 1, so the text
## is on top (BATTLE_RESULTS_SCREEN.md §7). The two passes take DISTINCT rungs because
## coincident prims fold-tie: shadows first, then the additive text, which is the order
## AddPrim's prepend leaves the ordering table in (§13).
const FOLD_RUNG_BANNER_SUB := 1
const FOLD_RUNG_BANNER_ADD := 2

# The banner's two PSX display-space passes exist twice: a `compositor_layer` variant
# for a build whose engine fold owns compositing, and an in-scene `blend_add`/`blend_sub`
# fallback for one that does not. `Fold.shader` makes the pick (ADR-0191 dec. 2); the
# two differ only in the sRGB->linear conversion, because the fold's scratch already IS
# display space. The results text and the gil reel draw solid through `blend_mix`, which
# does not accumulate-saturate, so they have one shader and no routing obligation.
const _ADD_SHADER: Shader = preload("res://assets/shaders/results_screen_add.gdshader")
const _ADD_FOLD_SHADER: Shader = preload("res://assets/shaders/results_screen_add_fold.gdshader")
const _SUB_SHADER: Shader = preload("res://assets/shaders/results_screen_sub.gdshader")
const _SUB_FOLD_SHADER: Shader = preload("res://assets/shaders/results_screen_sub_fold.gdshader")
const _MIX_SHADER: Shader = preload("res://assets/shaders/results_screen_mix.gdshader")

## Where tools/parse_bonus.py puts the decoded sheets + tables.
const RESULTS_DIR := "res://assets/scenarios/results/"
const MANIFEST_PATH := RESULTS_DIR + "results.json"
## PSX framebuffer the whole prim list is laid out in.
const FB_W := 256.0
const FB_H := 240.0
## Every metric record's `dx`/`dy` are signed offsets from here (§4.1).
const SCREEN_CENTER := Vector2i(128, 120)

# --- Cadence ----------------------------------------------------------------
## Vsyncs per frame-swap. `0x801C3BA4(n)` is "wait n frame-swaps" and each of the
## glyph builder's three phases does one swap per iteration, so a level step is two
## vsyncs — measured directly in §5.2 (a 20-frame ramp of 10 steps) and again in
## §9's 1-vsync-resolution re-measure. NOTE this is the *integer* 2 that {78}'s own
## beats measure at; ScenarioDarkScreen's sweep uses 2.1, which is what §17 measured
## for `{76}`'s 53-yield retract. Both are measurements of different loops.
const VSYNCS_PER_SWAP := 2

# --- The glyph-string builder `0x801C9FAC` (§10 Q3) --------------------------
## The fade is a colour SCALE, not alpha: `out = base × L >> 8` per channel, against
## a base table that holds the settled colours at L = 256 = 1.0 and never moves.
const FADE_SHIFT := 8
## Fade in: 10 loop iterations, `L += 16`, drawn at 96..240; the hold phase then
## draws 256. Eleven rendered levels over 20 vsyncs — it starts at 37.5 %, it never
## fades up from nothing.
const FADE_IN_START := 96
const FADE_IN_STEP := 16
const FADE_IN_ITERS := 10
const FADE_FULL := 256
## Fade out: `L -= 24` from 256 while `L >= 96`, so it steps
## 256, 232, 208, 184, 160, 136, 112 and then 88 fails the bound and the text is
## simply not submitted. [b]The last level ever drawn is 112.[/b] That terminal pop
## is a loop-bound artefact, not a flag — a port must not ramp to zero (§10 Q3).
const FADE_OUT_STEP := 24
const FADE_OUT_FLOOR := 96
const FADE_OUT_ITERS := 7

# --- Mode 2, the victory text (`0x801C3DF8`, §4B) ---------------------------
## Swaps between "CONGRATULATIONS!" and "This Battle Is Complete!" — `0x801C3BA4(0x1E)`.
const VICTORY_LINE2_DELAY_SWAPS := 30
## Swaps both lines hold before the driver commands them out — `0x801C3BA4(0xB4)`.
## 180 swaps = 360 vsyncs = the 5.7 s hold §9 measured to the vsync.
const VICTORY_HOLD_SWAPS := 180

# --- Mode 3, the gil reel (`0x801C7B78`, §8) --------------------------------
## `pos` is 1/256 px and a digit cell is 32 px, so a cell is 8192 units.
const REEL_CELL_UNITS := 8192
## Seeded from `0x801D0DAC` = 2560 — a 10 px/frame cruise, one `pos += vel` per vsync.
const REEL_CRUISE := 2560
## `vel = max(vel - 68, 256)` once the brake arms; the floor is 1 px/update.
const REEL_BRAKE := 68
const REEL_VEL_FLOOR := 256
## The brake arms when the target digit is 6 cells out, on a per-column gate
## `s7 > 32·i + 16·(ncols-1)` — which is what staggers the landings 32 vsyncs apart.
const REEL_LOOKAHEAD := 6
const REEL_GATE_STRIDE := 32
const REEL_GATE_SPREAD := 16
## The slot window: a GP0 `E3`/`E4` pair narrows the drawing area to screen y
## 128..150 for the reel and restores it after — 23 rows, exactly one digit cell.
const REEL_CLIP_TOP := 128
const REEL_CLIP_BOTTOM := 150
## Digit cells: 13 x 23 at sheet v = 50, `u = 13 × digit`, stacked on a 32 px pitch
## with the value DECREASING downward, so the cell 32 px above shows `digit + 1`.
const REEL_DIGIT_W := 13
const REEL_DIGIT_H := 23
const REEL_DIGIT_V := 50
const REEL_STACK_PITCH := 32
## Column `i` is only submitted once `16·i < pass`, so the columns appear
## right-to-left one every 16 passes (32 vsyncs) while all of them spin in lockstep.
const REEL_REVEAL_PASSES := 16
## The settled row measured in §8.5: x 76, 89, 100(comma), 110, 123, 136 and `Gil`
## at (153, 128). Columns are laid out right-to-left from the right edge on a 13 px
## pitch, with a comma cell widening the gap after every three digits.
const REEL_RIGHT_EDGE := 149
const REEL_COMMA_EXTRA := 8
const REEL_COMMA_LEAD := 11
## The comma is its own narrow cell, `uv (130, 64)`, 6 x 10.
const REEL_COMMA_UV := Vector2i(130, 64)
const REEL_COMMA_SIZE := Vector2i(6, 10)
## `Gil` — one 32 x 23 quad at screen (153, 128) from `uv (136, 50)`, settled from
## the reel's FIRST frame; it never spins.
const REEL_GIL_UV := Vector2i(136, 50)
const REEL_GIL_SIZE := Vector2i(32, 23)
const REEL_GIL_POS := Vector2i(153, 128)
## Vsyncs the settled row holds after the last column lands, before the fade-out —
## §9's 699 -> 826.
const REEL_SETTLED_HOLD := 127

# --- Modes >= 8, the victory-condition banner (`0x801C8F80`, §13) ------------
## `20 + Time + 10` yields: a fixed 20-iteration roll-up, `Time` held, a fixed
## 10-iteration roll-down, then one more yield and the task exits.
const BANNER_IN_ITERS := 20
const BANNER_OUT_ITERS := 10
## The wipe term advances 8 per yield and is clamped per record to `record.h` = 31,
## so a line unrolls in four yields.
const BANNER_WIPE_STEP := 8
## The lower line is gated on `iter >= 9`, which is the whole of the stagger.
const BANNER_LOWER_START := 9
## Every phase calls the fade multiplier with `a1 = 0x80` — [b]the banner never
## dims[/b]; its animation is purely geometric.
const BANNER_LEVEL := FADE_FULL
## The banner's `dx` is applied against a +128 draw offset (`x = dx + 256`), which
## lands at screen `dx + 128` — the same centre the glyph records use.
const BANNER_BOTTOM_ANCHOR := 120

## Modes whose string SELECTION is decoded but whose LAYOUT is not, plus the recruit
## flow. Keeping them as real pipeline steps that return immediately is what the ROM
## does on a battle like the one the RE captured: §17 drove `ss9` to the end of the
## event and measured modes 4, 5 and 6 at exactly two vsyncs each and mode 7 at less
## than one, because that battle dropped no loot, lost nobody and recruited nobody.
## They are no-ops HERE because nobody has ever seen them draw — unblocking them
## needs one artifact, a savestate from a battle that drops loot and recruits someone,
## and none of the 88 in `reference-assets/` is one. Filling one in later is a body
## swap, not a restructure.
const _MODES_WITH_NO_LAYOUT := [1, 4, 5, 6, 7]

# --- Tunables (ADR-0068) -----------------------------------------------------

## The reward the gil reel counts up to. §10 Q4 leaves the value's provenance
## explicitly out of scope — how the ROM computes it, and when it is known relative
## to the reel starting, was not read — so the MECHANISM is ported here and a battle
## reward model sets this when one exists. 0 spins a single column to `0`, which is
## what a battle with no reward should show.
static var bonus_gil: int = 0
## Page 1 of BONUS.BIN is the game-complete sheet: its line 2 reads "This Game Is
## Complete!". `0x801CA6C8` picks it on `0x8013B590(0x27) == 0x145`, the final-battle
## scenario check, and the same predicate stretches the victory hold to 300 swaps.
static var game_complete: bool = false

# --- Runtime state -----------------------------------------------------------

## The {78} mode in flight, or -1 when idle.
var _mode: int = -1
## `Time`, the second operand — only read for mode 0 and modes >= 8.
var _arg: int = 0
## Vsyncs since the screen started.
var _frame: int = 0
## True from run() until the screen's body has finished — the kind-56 {E5} barrier
## holds on this.
var _live: bool = false
## The glyph strings currently on screen, one per PSX prim pool line.
var _lines: Array[Dictionary] = []
## The reel's per-column integrator state, empty unless mode 3 is running.
var _reel: Dictionary = {}
## Which BONUS.BIN page the banner is showing (mode - 8).
var _page: int = 0
## True once the driver has written command word 2. A latch, not an `== frame` test:
## a `Time` of 0 would make the equality never fire and park the {E5} barrier forever.
var _commanded: bool = false

var _sheet_tex: Texture2D = null
var _digits_tex: Texture2D = null
var _banner_tex: Texture2D = null
var _mmi: Dictionary = {}          # pass name -> MeshInstance3D
var _mat: Dictionary = {}          # pass name -> ShaderMaterial

## Parsed manifest cache; {} when the asset tree is absent (the screens then time
## correctly and draw nothing, exactly like a mode with no layout).
static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false


func _ready() -> void:
	_load_manifest()
	_build_render()
	visible = false


# --- Public API --------------------------------------------------------------

## Run one {78} screen. `mode` is the first operand byte, `time` the second.
func run(mode: int, time: int) -> void:
	_mode = mode
	_arg = time
	_frame = 0
	_lines.clear()
	_reel.clear()
	_commanded = false
	_live = true
	if mode >= 8:
		_page = mode - 8
		_banner_tex = _load_banner(_page)
	elif mode == 0:
		_spawn_line(0, 0)          # string 0 = READY!
	elif mode == 2:
		_spawn_line(1, 0)          # string 1 = CONGRATULATIONS!
	elif mode == 3:
		_spawn_line(2, 0)          # string 2 = BONUS MONEY
		_reel = _reel_start(bonus_gil)
	if mode in _MODES_WITH_NO_LAYOUT:
		# A spawn, a check and an exit — the body finds nothing to draw.
		_live = false
	visible = _live
	_rebuild()


## True while a {78} screen is still on its own clock — the kind-56 ({E5}
## Wait For Instruction Task=0x38) barrier holds on exactly this.
func is_live() -> bool:
	return _live


## Advance one 60 Hz VM frame. No-op while idle.
func tick() -> void:
	if not _live:
		return
	_frame += 1
	if _mode >= 8:
		_tick_banner()
	elif _mode == 0:
		_tick_ready()
	elif _mode == 2:
		_tick_victory()
	elif _mode == 3:
		_tick_bonus()
	else:
		_live = false
	if not _live:
		visible = false
	_rebuild()


## Force the screen to its terminal state without spending frames — the fast-play
## settle guarantee a combat SEEK needs (ScenarioVM.settle_screen_effects). Lands
## the screen finished and cleared, which is where every {78} ends up.
func settle() -> void:
	_live = false
	_lines.clear()
	_reel.clear()
	visible = false
	_rebuild()


## The mode {78} last asked for, for the F3 panel / tests. -1 before the first one;
## it is NOT cleared on completion — `is_live()` is what says whether a screen is up.
func mode() -> int:
	return _mode


## How many vsyncs the screen has been running, for tests.
func elapsed() -> int:
	return _frame


## The reel's per-column scroll positions in 1/256 px, for tests. Empty off mode 3.
func reel_positions() -> PackedInt64Array:
	return _reel.get("pos", PackedInt64Array()) as PackedInt64Array


# --- The glyph-string builder, 0x801C9FAC ------------------------------------

## Spawn string `idx` into prim pool `line` (0 or 1) at the head of its fade-in.
func _spawn_line(idx: int, line: int) -> void:
	_lines.append({"string": idx, "line": line, "phase": "in", "iter": 0, "level": FADE_IN_START})


## Command every live line to fade out — `0x8014CA38(job, 0, 0, 2)`, the command
## word the driver writes to tear both lines down together.
func _command_fade_out() -> void:
	_commanded = true
	for l in _lines:
		if l["phase"] != "out":
			l["phase"] = "out"
			l["iter"] = 0
			l["level"] = FADE_FULL


## Advance every line one swap. Returns true once they are all gone.
func _advance_lines() -> bool:
	for l in _lines:
		match l["phase"]:
			"in":
				l["iter"] = int(l["iter"]) + 1
				var lv: int = FADE_IN_START + FADE_IN_STEP * int(l["iter"])
				if int(l["iter"]) >= FADE_IN_ITERS:
					l["phase"] = "hold"
					l["level"] = FADE_FULL
				else:
					l["level"] = lv
			"out":
				l["iter"] = int(l["iter"]) + 1
				var lo: int = FADE_FULL - FADE_OUT_STEP * int(l["iter"])
				# The bound, not a flag: 112 is the last level drawn and then the
				# packets simply stop being submitted.
				if lo < FADE_OUT_FLOOR:
					l["phase"] = "dead"
				else:
					l["level"] = lo
	_lines = _lines.filter(func(l): return l["phase"] != "dead")
	return _lines.is_empty()


## True on the vsyncs the builder rebuilds its prim buffer (one swap = two vsyncs).
func _on_swap() -> bool:
	return _frame % VSYNCS_PER_SWAP == 0


# --- Mode 0 — READY! ---------------------------------------------------------

## `0x801CAFD4`'s mode-0 arm: spawn the string FIRST, then hold `arg` swaps, then
## command 2. The operand is the hold after READY! is already on screen, not a delay
## before it.
func _tick_ready() -> void:
	if not _on_swap():
		return
	if not _commanded and _frame >= _arg * VSYNCS_PER_SWAP:
		_command_fade_out()
	if _advance_lines() and _commanded:
		_live = false


# --- Mode 2 — the victory text ----------------------------------------------

func _tick_victory() -> void:
	if not _on_swap():
		return
	if _frame == VICTORY_LINE2_DELAY_SWAPS * VSYNCS_PER_SWAP:
		_spawn_line(7, 1)          # string 7 = the pre-composed "This Battle Is Complete!"
	var out_at := (VICTORY_LINE2_DELAY_SWAPS + _victory_hold_swaps()) * VSYNCS_PER_SWAP
	if not _commanded and _frame >= out_at:
		_command_fade_out()
	if _advance_lines() and _commanded:
		_live = false


## On the final battle `0x8013B590(0x27) == 0x145` swaps the 180-swap hold for 300.
func _victory_hold_swaps() -> int:
	return 300 if game_complete else VICTORY_HOLD_SWAPS


# --- Mode 3 — BONUS MONEY + the gil reel ------------------------------------

func _tick_bonus() -> void:
	# The reel integrates once per vsync — the frame loop does two position updates
	# per build pass and a pass is two vsyncs.
	if not _reel.get("done", false):
		_reel_update(_reel)
	elif not _commanded and _on_swap() \
			and _frame >= int(_reel["done_frame"]) + REEL_SETTLED_HOLD:
		# §9's 699 -> 826: the settled row holds, then BONUS MONEY and the digits fade
		# out together on the one level the driver commands.
		_command_fade_out()
	if not _on_swap():
		return
	if _advance_lines() and _commanded:
		_live = false


## Split the reward into ones-first digits and seed every column at `digit << 13`.
func _reel_start(amount: int) -> Dictionary:
	var digits := PackedInt32Array()
	var n := maxi(0, amount)
	while true:
		digits.append(n % 10)
		n /= 10
		if n == 0:
			break
	var pos := PackedInt64Array()
	var vel := PackedInt64Array()
	var brake := PackedInt32Array()
	for d in digits:
		pos.append(d * REEL_CELL_UNITS)
		vel.append(REEL_CRUISE)
		brake.append(0)
	return {"digits": digits, "pos": pos, "vel": vel, "brake": brake,
			"update": 0, "done": false, "done_frame": 0}


## One position update of `0x801C7B78`'s frame loop, verbatim.
func _reel_update(r: Dictionary) -> void:
	var digits: PackedInt32Array = r["digits"]
	var pos: PackedInt64Array = r["pos"]
	var vel: PackedInt64Array = r["vel"]
	var brake: PackedInt32Array = r["brake"]
	var n := digits.size()
	var s7: int = r["update"]
	var moving := false
	for i in n:
		pos[i] += vel[i]
		if REEL_GATE_STRIDE * i + REEL_GATE_SPREAD * (n - 1) < s7:
			if ((pos[i] / REEL_CELL_UNITS) + REEL_LOOKAHEAD) % 10 == digits[i]:
				brake[i] = 1
		if brake[i] == 1:
			vel[i] = REEL_VEL_FLOOR if vel[i] < REEL_VEL_FLOOR + 1 else vel[i] - REEL_BRAKE
			if (pos[i] / REEL_CELL_UNITS) % 10 == digits[i] and (pos[i] / 256) % 32 == 0:
				vel[i] = 0
		if vel[i] != 0:
			moving = true
	r["pos"] = pos
	r["vel"] = vel
	r["brake"] = brake
	r["update"] = s7 + 1
	if not moving:
		r["done"] = true
		r["done_frame"] = _frame


# --- Modes >= 8 — the victory-condition banner ------------------------------

## The banner is a three-phase yield loop and it is NOT a colour fade: the quad's
## bottom edge is pinned and its top edge sweeps, with the source `v` tracking 1:1,
## so the content is stationary and the strip is a pure window-shade reveal.
func _tick_banner() -> void:
	if not _on_swap():
		return
	var iters := _frame / VSYNCS_PER_SWAP
	if iters > BANNER_IN_ITERS + _arg + BANNER_OUT_ITERS:
		_live = false


## The wipe height of the upper (`lower` false) or lower triple at this iteration.
func _banner_wipe(lower: bool, h: int) -> int:
	var iters := _frame / VSYNCS_PER_SWAP
	if iters <= BANNER_IN_ITERS:
		var i := iters - (BANNER_LOWER_START if lower else 0)
		return clampi(BANNER_WIPE_STEP * maxi(0, i), 0, h)
	if iters <= BANNER_IN_ITERS + _arg:
		return h
	# The out phase drives BOTH triples off one term — the stagger is in-phase only.
	return clampi(h - BANNER_WIPE_STEP * (iters - BANNER_IN_ITERS - _arg), 0, h)


# --- Prim-list construction --------------------------------------------------

## Rebuild the three ArrayMeshes from the current state. The PSX rebuilds its prim
## buffer every other frame; this does the same work on the same cadence.
func _rebuild() -> void:
	var text: Array = []
	var reel: Array = []
	var add: Array = []
	var sub: Array = []
	if _live and not _manifest.is_empty():
		if _mode >= 8:
			_build_banner(add, sub)
		else:
			for l in _lines:
				_build_string(text, int(l["string"]), int(l["level"]))
			if _mode == 3:
				_build_reel(reel)
	_set_mesh("sub", sub)
	_set_mesh("add", add)
	_set_mesh("text", text)
	_set_mesh("reel", reel)


## One glyph string: records `tab[n] .. tab[n+1]-1` of the metric table, each placed
## at `(128 + dx, 120 + dy)` and coloured by its own 20-byte colour record scaled to
## the line's current level.
func _build_string(out: Array, idx: int, level: int) -> void:
	var strings: Array = _manifest.get("strings", [])
	if idx < 0 or idx >= strings.size():
		return
	var s: Dictionary = strings[idx]
	var glyphs: Array = _manifest["glyphs"]
	var colors: Array = _manifest["glyph_colors"]
	for i in range(int(s["first"]), int(s["first"]) + int(s["count"])):
		var g: Array = glyphs[i]
		var c: Dictionary = colors[i]
		out.append({
			"pos": Vector2(SCREEN_CENTER.x + int(g[4]), SCREEN_CENTER.y + int(g[5])),
			"size": Vector2(int(g[2]), int(g[3])),
			"uv": Vector2(int(g[0]), int(g[1])),
			"uv_size": Vector2(int(g[2]), int(g[3])),
			"colors": _faded_corners(c["corners"], level),
			"tex": _sheet_tex,
		})


## The reel: `Gil` and the comma cells are settled furniture; each column is two
## quads 32 px apart, both trimmed to the 23-row slot window.
func _build_reel(out: Array) -> void:
	if _reel.is_empty():
		return
	var level: int = FADE_FULL
	if not _lines.is_empty():
		level = int(_lines[0]["level"])
	var flat := _faded_corners([[128, 128, 128], [128, 128, 128],
			[128, 128, 128], [128, 128, 128]], level)
	var digits: PackedInt32Array = _reel["digits"]
	var pos: PackedInt64Array = _reel["pos"]
	var n := digits.size()
	# `Gil` is present and settled from the reel's first frame; it never spins.
	_clipped(out, Vector2(REEL_GIL_POS.x, REEL_GIL_POS.y), Vector2(REEL_GIL_SIZE),
			Vector2(REEL_GIL_UV), flat, _digits_tex)
	# One comma per group of three digits. §8.5 gives its screen x (100, between the
	# 110 and 89 cells) but not its y; the static metric record 34 puts it at 142,
	# which the 23-row slot window would clip. Bottom-aligning it inside the window is
	# what ss9's frame shows — the comma sits on the digits' baseline, uncut.
	for k in range(1, (n + 2) / 3):
		var cx := _reel_column_x(3 * k) + REEL_COMMA_LEAD
		_clipped(out, Vector2(cx, REEL_CLIP_BOTTOM - REEL_COMMA_SIZE.y),
				Vector2(REEL_COMMA_SIZE), Vector2(REEL_COMMA_UV), flat, _digits_tex)
	# Column i is only submitted once `16·i < pass` — they appear right-to-left.
	var passes: int = int(_reel["update"]) / VSYNCS_PER_SWAP
	for i in n:
		if REEL_REVEAL_PASSES * i >= passes and not _reel.get("done", false):
			continue
		var x := _reel_column_x(i)
		var y := REEL_CLIP_TOP + int((pos[i] / 256) % REEL_STACK_PITCH)
		var d := int((pos[i] / REEL_CELL_UNITS) % 10)
		for step in 2:
			# The pair is what fills the 23-row window at every scroll offset: the
			# cell in the window and the next digit 32 px above it.
			var cell := (d + step) % 10
			_clipped(out, Vector2(x, y - REEL_STACK_PITCH * step),
					Vector2(REEL_DIGIT_W, REEL_DIGIT_H),
					Vector2(REEL_DIGIT_W * cell, REEL_DIGIT_V), flat, _digits_tex)


## Column `i`'s left edge, laid out right-to-left on a 13 px pitch with the comma
## cell widening the gap after every three digits (§8.5's measured 76/89/110/123/136).
func _reel_column_x(i: int) -> int:
	return REEL_RIGHT_EDGE - REEL_DIGIT_W * (i + 1) - REEL_COMMA_EXTRA * (i / 3)


## The banner's six records: three passes per line, shadows subtractive and the
## visible text additive, each wiped to its current height.
func _build_banner(add: Array, sub: Array) -> void:
	var recs: Array = _manifest.get("banner", [])
	for i in recs.size():
		var r: Dictionary = recs[i]
		var m: Array = r["metric"]
		var w := int(m[2])
		var h := int(m[3])
		var s := _banner_wipe(i >= 3, h)
		if s <= 0:
			continue
		var iters := _frame / VSYNCS_PER_SWAP
		# In: the BOTTOM edge is pinned at `dy + h + 120` and the top rises to meet the
		# visible height. Out: the bottom stays put and the top FALLS, so the strip
		# shrinks away from its own top edge.
		var top := int(m[5]) + h + BANNER_BOTTOM_ANCHOR - s
		if iters > BANNER_IN_ITERS + _arg:
			top = int(m[5]) + BANNER_BOTTOM_ANCHOR + (h - s)
		# 🔴 THE SOURCE `v` TRACKS THE TOP EDGE 1:1 IN BOTH PHASES, and that is the whole
		# point of the animation: substitute either phase's `top` and the source row for
		# a given screen row comes out as `(v - 128) + y - dy - 120`, independent of the
		# wipe. The content is therefore STATIONARY and the strip is a pure window-shade
		# reveal, not a slide. Writing the roll-down's `v` as a constant instead makes
		# the text crawl up out of its own baseline on the way out.
		var rows_hidden := top - int(m[5]) - BANNER_BOTTOM_ANCHOR
		var v_top := ((int(m[1]) - 128) & 0xFF) + rows_hidden
		# The gouraud is interpolated across the FULL quad, not the visible strip.
		var f0 := float(rows_hidden) / float(maxi(h - 1, 1))
		var f1 := f0 + float(s) / float(maxi(h - 1, 1))
		var cols := _faded_corners(_lerp_corners(r["corners"], f0, f1), BANNER_LEVEL)
		var tm := _banner_text_metric(i)
		var uv := Vector2(int(m[0]), v_top - 128)
		var quad := {
			"pos": Vector2(int(m[4]) + SCREEN_CENTER.x, top),
			"size": Vector2(w, s),
			"uv": uv,
			"uv_size": Vector2(w, s),
			# Where the ADDITIVE pass of this line samples the sheet for the same
			# screen pixel. The wipe shifts every record of a line by the same
			# amount, so the offset is just the two records' `dx`/`dy` difference —
			# (0,0) for the co-located shadow and (+1,+1) for the drop-shadow copy.
			"uv2": uv + Vector2(int(tm[4]) - int(m[4]), int(tm[5]) - int(m[5])),
			"colors": cols,
			"tex": _banner_tex,
		}
		if int(r["abr"]) == 1:
			add.append(quad)
		else:
			sub.append(quad)


## The additive text record of the line record `i` belongs to — records 0..2 are the
## upper line and 3..5 the lower, and the third of each triple is the visible text.
func _banner_text_metric(i: int) -> Array:
	var recs: Array = _manifest.get("banner", [])
	var text_i := 2 if i < 3 else 5
	if text_i >= recs.size():
		return (recs[i] as Dictionary)["metric"]
	return (recs[text_i] as Dictionary)["metric"]


## Append a quad trimmed to the reel's slot window. The PSX narrows the drawing area
## with a GP0 `E3`/`E4` pair; both the rect and its UV are axis-aligned, so trimming
## the geometry and the source rows by the same amount is the same picture.
func _clipped(out: Array, pos: Vector2, size: Vector2, uv: Vector2,
		cols: PackedColorArray, tex: Texture2D) -> void:
	var y0 := maxf(pos.y, float(REEL_CLIP_TOP))
	var y1 := minf(pos.y + size.y, float(REEL_CLIP_BOTTOM))
	if y1 <= y0:
		return
	out.append({
		"pos": Vector2(pos.x, y0),
		"size": Vector2(size.x, y1 - y0),
		"uv": Vector2(uv.x, uv.y + (y0 - pos.y)),
		"uv_size": Vector2(size.x, y1 - y0),
		"colors": cols,
		"tex": tex,
	})


## `out = base × L >> 8` per channel, the fade multiplier `0x801C8B94` — applied
## here so the mesh carries the value the PSX packet would.
func _faded_corners(corners: Array, level: int) -> PackedColorArray:
	var out := PackedColorArray()
	for c in corners:
		out.append(Color8(
			(int(c[0]) * level) >> FADE_SHIFT,
			(int(c[1]) * level) >> FADE_SHIFT,
			(int(c[2]) * level) >> FADE_SHIFT))
	return out


## The four corner colours of a vertical sub-range `[f0, f1]` of a gouraud quad.
func _lerp_corners(corners: Array, f0: float, f1: float) -> Array:
	var a := _lerp_row(corners, clampf(f0, 0.0, 1.0))
	var b := _lerp_row(corners, clampf(f1, 0.0, 1.0))
	return [a[0], a[1], b[0], b[1]]


## The left and right colours at vertical fraction `f` of a gouraud quad.
func _lerp_row(corners: Array, f: float) -> Array:
	var left := []
	var right := []
	for k in 3:
		left.append(int(round(lerpf(float(corners[0][k]), float(corners[2][k]), f))))
		right.append(int(round(lerpf(float(corners[1][k]), float(corners[3][k]), f))))
	return [left, right]


# --- Render plumbing ---------------------------------------------------------

func _set_mesh(pass_name: String, quads: Array) -> void:
	var mmi: MeshInstance3D = _mmi.get(pass_name)
	if mmi == null:
		return
	if quads.is_empty():
		mmi.visible = false
		return
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var tex: Texture2D = null
	for q in quads:
		var p: Vector2 = q["pos"]
		var sz: Vector2 = q["size"]
		var uv: Vector2 = q["uv"]
		var uvs_: Vector2 = q["uv_size"]
		var uv2: Vector2 = q.get("uv2", uv)
		var qc: PackedColorArray = q["colors"]
		tex = q["tex"]
		var ts := Vector2(1.0, 1.0)
		if tex != null:
			ts = Vector2(tex.get_width(), tex.get_height())
		var base := verts.size()
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
			verts.append(Vector3(p.x + sz.x * corner.x, p.y + sz.y * corner.y, 0.0))
			uvs.append(Vector2((uv.x + uvs_.x * corner.x) / ts.x,
					(uv.y + uvs_.y * corner.y) / ts.y))
			uv2s.append(Vector2((uv2.x + uvs_.x * corner.x) / ts.x,
					(uv2.y + uvs_.y * corner.y) / ts.y))
		cols.append_array(qc)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2,
				base + 2, base + 1, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mmi.mesh = mesh
	mmi.visible = true
	if tex != null:
		(_mat[pass_name] as ShaderMaterial).set_shader_parameter("sheet", tex)


func _build_render() -> void:
	# Four passes, because the PSX prims differ in blend AND in which of the page's
	# two CLUTs they sample:
	#   sub  — the banner's two subtractive shadow records (abr 2), banner sheet
	#   add  — the banner's additive gouraud text record (abr 1), banner sheet
	#   text — the glyph strings, out of the LETTER palette (CLUT 0x3F9A)
	#   reel — the gil reel's cells, GP0 0x2C POLY_FT4, which is NOT the
	#          semi-transparent opcode (that would be 0x2E), so they draw solid, out
	#          of the DIGIT palette (CLUT 0x3F98). §7's prim-pool table.
	#
	# 🔴 THE GLYPH PASS DRAWS AT 1.0 EVEN THOUGH §4.2 DECODES ITS PACKETS AS GP0
	# 0x3E — POLY_GT4 *semi-transparent*. The capture is what decides it: in
	# battle_results_captures/ss4 and ss5 the letters are solid, and the hillside
	# behind "CONGRATULATIONS!" does not show through them; rendering them at the
	# abr-0 half blend visibly mutes them and lets the background read through.
	# PSX reconciles the two: on a TEXTURED primitive semi-transparency is gated per
	# texel by bit 15 (STP) of the CLUT entry, and exactly ONE of CLUT 0x3F9A's
	# sixteen entries carries it, so the overwhelming majority of the sheet draws
	# opaque. Modelling that per texel would also change the banner, whose two CLUT
	# palettes disagree about STP and for which no savestate exists — so the blend
	# stays per-primitive here and the banner keeps the abr the RE's own renderer
	# (battle_results_captures/banner_anim.py) uses.
	#
	# Priorities ascend in the order AddPrim's prepend leaves the PSX ordering table
	# in: shadows, then the additive text, then the results text (§13, §7).
	for spec in [["sub", Fold.shader(_SUB_FOLD_SHADER, _SUB_SHADER), 110, 1.0],
			["add", Fold.shader(_ADD_FOLD_SHADER, _ADD_SHADER), 111, 1.0],
			["text", _MIX_SHADER, 112, 1.0],
			["reel", _MIX_SHADER, 113, 1.0]]:
		var mat := ShaderMaterial.new()
		mat.shader = spec[1]
		mat.render_priority = int(spec[2])
		mat.set_shader_parameter("src_alpha", float(spec[3]))
		mat.set_shader_parameter("fb_size", Vector2(FB_W, FB_H))
		var mmi := MeshInstance3D.new()
		mmi.name = "Results" + String(spec[0]).capitalize()
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = CULL_AABB
		mmi.visible = false
		add_child(mmi)
		_mmi[String(spec[0])] = mmi
		_mat[String(spec[0])] = mat
		# The banner's add/sub passes are PSX display-space blends, so they join the
		# ENGINE FOLD when the build owns one: `Fold.add` stamps the held-out layer and
		# the ordering key, and `Fold.shader` above already picked the compositor_layer
		# variant. Off-fork `Fold.add` returns without touching the carrier and the
		# in-scene `render_priority` above is what orders them (ADR-0191 dec. 12).
		#
		# 🔴 THE RUNGS ARE LOAD-BEARING AND 0.0 WAS WRONG. Both passes took order_z 0,
		# which fold-ties them, and the dim was not in the fold at all — so the banner
		# resolved at PRE_TRANSPARENT and the in-scene dim then drew OVER it. Measured
		# with the dim driven opaque: the brightest pixel in the banner band was
		# (48,40,16), the fog colour — the text was gone. ScenarioDarkScreen now folds
		# too, at rung 0, and these sit above it.
		if String(spec[0]) == "sub":
			Fold.add(mmi, mat, DepthMode.rung_z(FOLD_RUNG_BANNER_SUB))
		elif String(spec[0]) == "add":
			Fold.add(mmi, mat, DepthMode.rung_z(FOLD_RUNG_BANNER_ADD))
	_sheet_tex = _load_tex(_sheet_name())
	_digits_tex = _load_tex(String(_manifest.get("digits_sheet", "")))


## Which of the two results-sheet variants: page 1's line 2 reads "This Game Is
## Complete!" and the overlay entry loads it only on the final battle.
func _sheet_name() -> String:
	var sheets: Array = _manifest.get("sheets", [])
	if sheets.is_empty():
		return ""
	return String(sheets[1 if game_complete and sheets.size() > 1 else 0])


func _load_banner(page: int) -> Texture2D:
	var pages: Array = _manifest.get("pages", [])
	if page < 0 or page >= pages.size():
		push_warning("[ScenarioResultsScreen] no BONUS.BIN page %d (have %d)"
				% [page, pages.size()])
		return null
	return _load_tex(String((pages[page] as Dictionary).get("banner", "")))


func _load_tex(name: String) -> Texture2D:
	if name.is_empty():
		return null
	return load(RESULTS_DIR + name) as Texture2D


static func _load_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	if not ResourceLoader.exists(MANIFEST_PATH) and not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("[ScenarioResultsScreen] %s missing — run tools/parse_bonus.py"
				% MANIFEST_PATH)
		return
	var txt := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed = JSON.parse_string(txt)
	if parsed is Dictionary:
		_manifest = parsed
	else:
		push_warning("[ScenarioResultsScreen] %s did not parse" % MANIFEST_PATH)
