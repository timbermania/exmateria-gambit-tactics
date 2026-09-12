class_name ChangeJobCommitCutscene
extends RefCounted

## The Change-Job COMMIT cutscene — the 240-frame beat FFT plays when you press ○ on an unlocked
## job. Reverse-engineered byte-exact in `research/working_documents/CHANGE_JOB_COMMIT.md`
## (rounds 50/51, every claim a `[static 0xADDR]` reading paired to a live measurement).
##
## **It is not a transition.** The ROM never leaves the Change-Job screen: it cuts the chrome,
## runs four concurrent mechanisms for 4.00 s, writes the job on the LAST frame, rebuilds the
## wheel's job list, restores the chrome, and leaves you on the wheel with the cursor where you
## left it (spec §11). That is why this lives beside the screen instead of inside the ADR-0084
## coordinator: it pushes nothing, pops nothing, and is irreversible — a `leave()` that replayed
## it backwards would have to un-commit a job, which the ROM has no notion of. ADR-0084's own
## Consequences already carve out "steady-state interaction stays out of the engine"; the
## amendment note there extends that to self-clocked in-place cutscenes like this one.
##
## Everything here is a pure function of the ROM's frame counter `DAT_8018c92e` ("c92e", 0..240),
## which is how the ROM computes it too — so the whole beat is testable without rendering a frame
## (`tests/ChangeJobCommitCutsceneTest.gd` pins every quantity against the oracle savestates).
## The only state is the clock, the skip latch, and the dissolve's consumed permutation.
##
## **Cadence is 60 Hz, one tick per vsync** — `[dynamic]` c92e advanced 124 ticks in 2.00 s wall
## clock. NOT the ≈30 Hz menu tick the entry/rotate/exit animators use. Both are correct; the ROM
## simply clocks this one per vsync (spec §12.1 "Cadence").
##
## The four mechanisms (spec §0):
##   1. chrome CUT      — vitals + nameplate + ◄L1/R1► stop being emitted on the press frame
##   2. band CLOSE      — a CONSEQUENCE of 1, not a second beat: the screen's own subtractive
##                        chrome bar steps 120 → 0 at −12/frame once the chrome flag clears (§6)
##   3. cylinder        — 64 semi-transparent gouraud LINES on an rcos/rsin ring (§9)
##   4. dissolve + tint — a random-order pixel DISSOLVE of the old job sprite into the new one
##                        (§8), under a four-hue gouraud tint ramp (§7)

## Total beat length, and the reason it is 240 and not a round number: the dissolve consumes
## 2 of the sprite's 480 cells per frame and the permutation is exhausted EXACTLY (§8).
const DURATION := 240
## Phase 2 ("relax") — the gouraud block walks back toward neutral, the cylinder flies out (§11).
const RELAX_START := 220

enum Phase { IDLE, MAIN, RELAX }

# --- the chrome band (§6) -----------------------------------------------------------------
## The band's subtractive strength at full — `DAT_8018aa70` runs 0..0x78.
const BAND_LEVEL_MAX := 120
## …stepped by 0xc per frame, so the close takes exactly 10 frames. NOT ~17, and NOT an alpha
## fade to black: a BRIGHTER tile colour means a DARKER band (ABR 2 = `B − F`), which is why the
## round-50 luminance measurement rises while the authored value falls (§6.2/§6.5).
const BAND_STEP := 12

# --- the gouraud tint ramp (§7) -----------------------------------------------------------
## Four RGB triples = the four gouraud corners of the two centre-unit quads. The commit trigger
## seeds all twelve bytes to 0x80 (PSX neutral 1.0×) at `0x801197A0`.
const GOURAUD_SEED := 0x80
## The corner channels that ramp UP: R of corner 0, G of corner 1, B of corner 2, R+G of corner 3
## — driving the corners to RED / GREEN / BLUE / YELLOW while the others crush toward 0. It is a
## prismatic shimmer across the sprite, not a uniform brighten.
const GOURAUD_UP_BYTES: Array[int] = [0, 4, 8, 9, 10]
## The up-bytes saturate at 0xFF here (0x80 + 127), which is where the tint peaks.
const TINT_PEAK := 127

# --- the cylinder (§9) --------------------------------------------------------------------
const STRIPES := 64
## Full circle in the ROM's angular units; `rcos`/`rsin` return 1.12 fixed point.
const FULL_CIRCLE := 4096
## Angular step between stripes (0x1000 / 64) and the per-frame spin.
const STRIPE_STEP := 0x40
const SPIN_PER_FRAME := 4
## θ advances 4/4096 per frame → one true revolution per 1024 frames, but the stripes are 0x40
## apart, so the PATTERN repeats every 16 frames. That fast shimmer is what reads as "spinning".
const VISUAL_REPEAT := 16
const CYL_RADIUS_X := 20      # steady-state X radius
const CYL_RADIUS_Y := 10      # the rim's Y radius
const CYL_CENTRE_X := 128     # screen x (the packets carry +0x80 more as the draw-env bias)
const CYL_YBOT_BASE := 146
const CYL_HEIGHT := 64        # the magenta→black span, exact in the packets
const CYL_ENTRY_END := 20     # entry spans c92e 0..19
const CYL_EXIT_START := 221   # exit spans c92e 221..239, the entry's arithmetic mirror
const CYL_OFFSET_SHIFT := 3   # S = k << 3
## `DAT_8018c930` / `DAT_8018c933`, read live: black → magenta → black, top to bottom.
const STRIPE_BLACK := Color8(0, 0, 0)
const STRIPE_MAGENTA := Color8(255, 0, 255)

# --- the skip (§10) -----------------------------------------------------------------------
## ○ or × fast-forwards to the exit. The latch is one frame AHEAD of the jump, and a press
## BEFORE the window is remembered and fires the moment the clock reaches 40.
const SKIP_WINDOW_LO := 40
const SKIP_WINDOW_HI := 220

# --- the dissolve (§8) --------------------------------------------------------------------
## The sprite shadow is 480 BYTES at 4bpp = 960 px = 24×40. The ROM reveals whole BYTES, so the
## dissolve's grain is a horizontal PAIR of pixels — visibly granular at this size, which is
## exactly what the user described independently ("almost one-pixel-at-a-time in random order").
const CELLS := 480
const CELL_PX := 2
const SPRITE_W := 24
const SPRITE_H := 40
## Two bytes per frame; 2 × 240 = 480 exhausts the permutation exactly.
const REVEAL_PER_FRAME := 2
## The ROM builds the identity 479..0 then applies 300 `bios_rand` swaps — a PARTIALLY shuffled
## table (its first entries read `430,1,2,168,344,5,403,7`), not a uniform shuffle. Reproducing
## the swap COUNT keeps the same partially-ordered character.
const SHUFFLE_SWAPS := 300

var _frame := 0
var _phase: int = Phase.IDLE
var _shuffle := PackedInt32Array()
## One byte per cell: 0 = still showing the OLD job's pixels, 1 = revealed to the NEW job's.
var _reveal := PackedByteArray()
var _revealed := 0
var _skip_requested := false
var _skip_latched := false


# =========================================================================================
# The clock
# =========================================================================================

## Start the beat: seed the clock at 0 and build the dissolve permutation. `seed` makes the
## shuffle deterministic so a guard can pin an exact frame (the ROM uses `bios_rand`).
## Mirrors the ROM's once-only init block at `FUN_80119D60` `0x80119D64`–`0x80119ECC` (§8).
func begin(rng_seed: int) -> void:
	_frame = 0
	_phase = Phase.MAIN
	_skip_requested = false
	_skip_latched = false
	_revealed = 0
	_reveal = PackedByteArray()
	_reveal.resize(CELLS)
	_shuffle = _build_shuffle(rng_seed)


## Advance one vsync tick. Returns TRUE on the single step that lands on frame 240 — the APPLY
## frame, where the caller writes the job, rebuilds the wheel list and restores the chrome (§11).
##
## Order matches the ROM: the dissolve consumes `shuffle[c92e*2 + i]` FIRST (at `0x80119F88`,
## with the pre-increment counter), THEN the clock advances and the skip is evaluated
## (`0x8011A168`). That is why c92e 0..239 indexes cells 0..479 with nothing left over.
func step() -> bool:
	if _phase == Phase.IDLE:
		return false
	_consume_dissolve(_frame)
	_frame += 1
	# §10: latch on the press frame, jump on the NEXT one. Once latched, every frame re-tests
	# the window — which is what makes an early press fire the moment the clock reaches 40.
	if not _skip_latched:
		if _skip_requested:
			_skip_latched = true
	elif _frame >= SKIP_WINDOW_LO and _frame <= SKIP_WINDOW_HI:
		_frame = SKIP_WINDOW_HI
	if _frame >= DURATION:
		_frame = DURATION
		_phase = Phase.IDLE
		return true
	_phase = Phase.RELAX if _frame >= RELAX_START else Phase.MAIN
	return false


## ○ or × during the beat. Remembered even outside the [40,220] window (§10).
func request_skip() -> void:
	_skip_requested = true


func is_running() -> bool:
	return _phase != Phase.IDLE


func frame() -> int:
	return _frame


func phase() -> int:
	return _phase


func skip_latched() -> bool:
	return _skip_latched


# =========================================================================================
# Beat 2 — the band (§6). A CONSEQUENCE of the chrome cut, not a separate beat: the caller
# hides the chrome and steps this from the same clock. `FUN_80112C88`'s tail is the whole of it.
# =========================================================================================

## The band's subtractive strength at frame `f`: `max(0, 120 − 12·c92e)`, i.e. closed in 10 frames.
static func band_level(f: int) -> int:
	return maxi(0, BAND_LEVEL_MAX - BAND_STEP * f)


## Row `k` of the band's falloff (k = 0 is the solid centre block, 1..9 the soft edge rows on
## BOTH sides): `max(0, level − 12·k)`. `[dynamic]` ss1 reads 96,84,…,12,0,0 centre-outward.
static func band_row_level(level: int, k: int) -> int:
	return maxi(0, level - BAND_STEP * k)


## The same close expressed as the 0..1 factor the port's band shaders take
## (`DetailScene.set_vitals_band_factor` / `FormationScene.set_band_fade`).
static func band_factor(f: int) -> float:
	return float(band_level(f)) / float(BAND_LEVEL_MAX)


# =========================================================================================
# Beat 4a — the four-hue gouraud tint ramp (§7)
# =========================================================================================

## The twelve gouraud bytes (4 RGB corner triples) at frame `f`. Pure: replayed from the seed,
## so a caller can scrub. Phase 1 ramps until `RELAX_START`, then all twelve walk back toward
## 0x80 by 1/frame — which is why the block does NOT return to neutral (it ends 0xEB / 0x73).
static func gouraud_at(f: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(12)
	for i in 12:
		b[i] = GOURAUD_SEED
	# 219 main steps then 20 relax steps — 239 ramp steps across 240 frames, because the frame
	# that flips the phase runs neither. Solved from the ss3/ss4 rows, which pin it exactly:
	# ss4 needs `0xFF − r = 0xEB` (r = 20) AND `m + r − 124 = 0x73` (m = 219) simultaneously.
	for _s in mini(f, RELAX_START - 1):
		_gouraud_step_main(b)
	for _s in clampi(f - RELAX_START, 0, DURATION - RELAX_START):
		_gouraud_step_relax(b)
	return b


## One phase-1 step. Each triple has ONE "up" byte that saturates at 0xFF; the other two step
## DOWN until it saturates and UP afterwards, which is the turnaround the ss3/ss4 rows pin.
static func _gouraud_step_main(b: PackedByteArray) -> void:
	# triple 0: R up, G+B follow;  triple 1: G up, R+B follow;  triple 2: B up, R+G follow
	_ramp_pair(b, 0, 1, 2)
	_ramp_pair(b, 4, 3, 5)
	_ramp_pair(b, 8, 6, 7)
	# triple 3: R AND G both up, only B follows — the YELLOW corner.
	b[9] = mini(b[9] + 1, 0xFF)
	b[10] = mini(b[10] + 1, 0xFF)
	b[11] = _bump(b[11], 1 if b[9] == 0xFF else -1)


static func _ramp_pair(b: PackedByteArray, up: int, a: int, c: int) -> void:
	b[up] = mini(b[up] + 1, 0xFF)
	var d := 1 if b[up] == 0xFF else -1
	b[a] = _bump(b[a], d)
	b[c] = _bump(b[c], d)


## One phase-2 step: every byte walks toward neutral — `+1` if below 0x80, `−1` if at/above.
static func _gouraud_step_relax(b: PackedByteArray) -> void:
	for i in 12:
		b[i] = _bump(b[i], 1 if b[i] < GOURAUD_SEED else -1)


static func _bump(v: int, d: int) -> int:
	return clampi(v + d, 0, 0xFF)


# =========================================================================================
# Beat 3 — the cylinder (§9)
# =========================================================================================

## The X radius at frame `f`: 0→19 over the entry, 20 steady, 19→1 over the exit.
static func cylinder_radius(f: int) -> int:
	if f < CYL_ENTRY_END:
		return f
	if f < CYL_EXIT_START:
		return CYL_RADIUS_X
	return DURATION - f


## The vertical offset `S` at frame `f`: 160→8 over the entry, 0 steady, 8→152 over the exit.
## The exit is the entry's arithmetic MIRROR in the ROM — not an authored second curve.
static func cylinder_offset(f: int) -> int:
	if f < CYL_ENTRY_END:
		return (CYL_ENTRY_END - f) << CYL_OFFSET_SHIFT
	if f < CYL_EXIT_START:
		return 0
	return (f - (CYL_EXIT_START - 1)) << CYL_OFFSET_SHIFT


## Stripe `k` (0..63) at frame `f`, in virtual screen px:
##   `{x, y_top, y_bot}` — the bar runs from the screen TOP (y 0) down to `y_bot`, peaking
##   magenta at `y_top`. Two gouraud lines: black→magenta over `[0, y_top]`, then
##   magenta→black over `[y_top + 1, y_bot]`.
static func stripe_at(k: int, f: int) -> Dictionary:
	var r := cylinder_radius(f)
	var s := cylinder_offset(f)
	var theta: int = (k * STRIPE_STEP + f * SPIN_PER_FRAME) & (FULL_CIRCLE - 1)
	var x: int = CYL_CENTRE_X + ((r * _rcos(theta)) >> 12)
	var y_bot: int = ((CYL_RADIUS_Y * _rsin(theta)) >> 12) + CYL_YBOT_BASE - s
	return {"x": x, "y_top": y_bot - CYL_HEIGHT - s, "y_bot": y_bot}


## PSX `rcos`/`rsin`: θ over a 4096-unit circle, result in 1.12 fixed point.
static func _rcos(theta: int) -> int:
	return int(round(cos(float(theta) / float(FULL_CIRCLE) * TAU) * 4096.0))


static func _rsin(theta: int) -> int:
	return int(round(sin(float(theta) / float(FULL_CIRCLE) * TAU) * 4096.0))


# =========================================================================================
# Beat 4b — the dissolve (§8)
# =========================================================================================

## The shuffled permutation of 0..479 the reveal walks. For the guard.
func shuffle() -> PackedInt32Array:
	return _shuffle


## One byte per cell: 0 = the OLD job's pixels still show there, 1 = the NEW job's do.
func reveal_mask() -> PackedByteArray:
	return _reveal


func revealed_count() -> int:
	return _revealed


## Reveal the two cells this frame owns. A SKIPPED beat leaves the cells between the jump
## and 220 unrevealed — faithful to the ROM, and invisible because the apply on frame 240
## replaces the sprite outright with the newly-resolved unit body.
func _consume_dissolve(f: int) -> void:
	for i in REVEAL_PER_FRAME:
		var slot: int = f * REVEAL_PER_FRAME + i
		if slot < 0 or slot >= _shuffle.size():
			continue
		var idx: int = _shuffle[slot]
		if _reveal[idx] == 0:
			_reveal[idx] = 1
			_revealed += 1


## The ROM's table: fill descending 479..0, then 300 `bios_rand` swaps (§8). Seeded so the
## port is reproducible; the ROM's is not, but nothing downstream depends on WHICH permutation.
static func _build_shuffle(rng_seed: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(CELLS)
	for i in CELLS:
		out[i] = CELLS - 1 - i
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	for _s in SHUFFLE_SWAPS:
		var a: int = rng.randi_range(0, CELLS - 1)
		var b: int = rng.randi_range(0, CELLS - 1)
		var t: int = out[a]
		out[a] = out[b]
		out[b] = t
	return out


## The (x, y) of dissolve cell `idx` inside the 24×40 sprite — the cell covers `CELL_PX`
## horizontal pixels starting there. Cells run row-major, 12 per row (24 px / 2).
static func cell_origin(idx: int) -> Vector2i:
	var per_row: int = SPRITE_W / CELL_PX
	return Vector2i((idx % per_row) * CELL_PX, idx / per_row)
