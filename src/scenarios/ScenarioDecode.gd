class_name ScenarioDecode
extends RefCounted
## Pure decode layer for the event-script interpreter: opcode operands → typed
## intent, with no nodes, no VM state, no side effects.
##
## Machine code fuses three things into one straight-line block: reading the
## operand bytes, computing what the opcode *means*, and mutating hardware. A
## transcription inherits that — so a handler like `_op_warp_unit` decoded the
## facing wheel and placement inline, then poked the `Unit` node, all in one body,
## reachable only by booting a scene. This module holds the first two — the
## reverse-engineered *decode* — behind a small, pure interface, so the RE knowledge
## (the point of the tedious debugging) is unit-testable on its own and the handlers
## shrink to "decode, then apply the intent to nodes."
##
## This generalises the shape ScenarioVM already used for `face_unit_look_at_12bit_psx`
## (a pure look-at computed from Δ-coords, tested against the octant table without a
## scene). Numeric conventions come from [PsxNum]; anything Godot-specific (the
## ADR-0052 depth-row flip against a live map, node lookup) stays in the apply
## handler, so decode has no dependency on map size or scene state.

# ---------------------------------------------------------------------------
# {24} Warp Unit — position + spawn facing
# ---------------------------------------------------------------------------

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const PsxNum = ExMateriaPlatform.PsxNum

## What a Warp Unit opcode asks for, decoded from its operands. `psx_x`/`psx_y`
## are the chunk's tile coords — Godot-native now that the chunk arrives
## pre-flipped from the parser (ADR-0057, #141), so the apply handler consumes
## them raw (no runtime mirror). `facing_12bit` is the spawn orientation
## direction (the raw clockwise facing angle; the "12-bit wheel" is just its
## encoding).
class WarpIntent extends RefCounted:
	var uid: int
	var psx_x: int
	var psx_y: int
	var facing_12bit: int


## Decode a Warp Unit opcode from its [EventInstructionArgs] reader. The `Facing`
## field is 2 bits (0..3) mapped to a cardinal by the ROM spawn writer (0x80087c1c,
## `<< 10`): 0=E, 1=S, 2=W, 3=N — see PsxNum.warp_facing_to_12bit.
static func warp_unit(a: EventInstructionArgs) -> WarpIntent:
	var intent := WarpIntent.new()
	intent.uid = a.raw("Unit")
	intent.psx_x = a.raw("X")
	intent.psx_y = a.raw("Y")
	intent.facing_12bit = PsxNum.warp_facing_to_12bit(a.raw("Facing") & 0x03)
	return intent


# ---------------------------------------------------------------------------
# {3B}/{6E} Sprite Move — straight-line position slide
# ---------------------------------------------------------------------------

## The Godot-space position offset a Sprite Move operand encodes, relative to the
## unit's home. The operand triple (+X, +Z, +Y in catalog axis order) is a signed
## PSX offset; the ADR-0052 180°-about-X map rotation negates the two flipped axes
## (the mirror's constant cancels for a relative delta):
##   opcode +X (lateral)        → world +X   (unchanged by the rotation)
##   opcode +Z (height, Y-down) → world −Y   (Y-down → Y-up)
##   opcode +Y (depth)          → world −Z   (ADR-0052 depth negation)
## `units_per_tile` is the operand-units-per-tile divisor (28 = one tile). The
## `+X`/`+Z`/`+Y` operands are 2-byte signed offsets — `a.signed` reads the width
## from the catalog and sign-extends via [PsxNum].
static func sprite_move_offset(a: EventInstructionArgs, units_per_tile: float) -> Vector3:
	return Vector3(
		 float(a.signed("+X")) / units_per_tile,
		-float(a.signed("+Z")) / units_per_tile,
		-float(a.signed("+Y")) / units_per_tile)


## What a Sprite Move opcode ({3B}/{6E}) asks for, decoded from its operands.
## `offset` is the Godot-space delta from the unit's home (see `sprite_move_offset`);
## `time_frames > 0` selects {3B} fixed-duration mode, otherwise `speed` drives the
## {6E} Beta cadence (`4·dist/speed`). `easing` (operand Type) picks the non-linear
## position curve and `weight` (operand Unknown) shapes it. `uid` is the raw operand
## id — apply resolves it to a live registry key (u16→u8 fallback).
class SpriteMoveIntent extends RefCounted:
	var uid: int
	var offset: Vector3
	var time_frames: int
	var speed: int
	var easing: int
	var weight: int


## Decode a Sprite Move opcode. The caller supplies the mode split — `time_frames`
## (max(1,Time) for {3B}, 0 for {6E}) and `speed` (0 for {3B}, max(1,Speed) for
## {6E}) — since which operand carries the cadence is per-opcode; everything else
## comes from the operands. `units_per_tile` is the offset divisor (28 = one tile).
static func sprite_move_intent(a: EventInstructionArgs, units_per_tile: float,
		time_frames: int, speed: int) -> SpriteMoveIntent:
	var intent := SpriteMoveIntent.new()
	intent.uid = a.raw("Unit")
	intent.offset = sprite_move_offset(a, units_per_tile)
	intent.time_frames = time_frames
	intent.speed = speed
	intent.easing = a.raw("Type") & 0xFF
	intent.weight = a.raw("Unknown", 1) & 0xFF
	return intent


## {6E} Beta duration in frames: `4·dist / speed`. `dist_units` is this move's actual
## travel in opcode units; the ROM's `sqrt(Σ Δ²·0x10)` puts a ×4 over raw distance.
## Floored at 1 frame; speed floored at 1 to avoid divide-by-zero. NOTE: {28} Walk To
## does NOT reuse this — its cadence is an integer recurrence the ROM's own stepper
## runs (`ExMateriaBattlefield.RomWalkStepper`), and nothing predicts it. There used to
## be a `walk_to_duration_frames` here computing `224/Speed`; ADR-0225 deleted it —
## `vec3_normalize` returns 4095 and not 4096 for a cardinal axis and the launch gate
## re-quantises the position once per step, so 224/Speed is low by a frame a tile or
## more at every Speed, and a second approximate spelling beside the exact one is how
## the approximation comes back.
static func beta_duration_frames(dist_units: float, speed: int) -> float:
	return maxf(1.0, (4.0 * dist_units) / float(maxi(1, speed)))


## {28} Walk To Speed — ONE 16-bit little-endian operand at opcode+6, read as
## 8.8 FIXED POINT. The catalog splits it into two 1-byte operands (an anonymous
## `Unknown` and `Speed`) because the chunk exporter did; the ROM never does.
##
## Laid out by offset from the opcode: **`+7` is the integer byte and `+6` is
## the 1/256 fraction**; the ROM reads them as one little-endian half-word.
##
## `event_op_walk_to_setup @ 0x8013E5C0` computes `a0 = operand_base + 5`
## (@0x8013e5f0) and calls `event_bytecode_reader_c @ 0x80146078`, which is a
## little-endian half-word read — `v1 = lbu a0[1]; v0 = lbu a0[0]; v0 |= v1 << 8`
## — then sign-extends it and passes it as the FIFTH argument to
## `unit_movement_arm @ 0x8008C664` (@0x8013e628 `sw v0,0x10(sp)`). That callee
## reads it back (@0x8008c684 `lw s4,0x48(sp)`, sp having moved 0x38) and seeds
##   `unit+0x38 = s4 << 1`   (@0x8008c77c `sll v0,s4,0x1` / @0x8008c780).
## So the walk's velocity magnitude is `halfword << 1`, and the low byte is a
## 1/256 FRACTION of a Speed unit. When it is zero this collapses to the long-
## documented `unit+0x38 = Speed << 9` — that is the special case, not the rule.
##
## It matters for exactly six of the 282 `{28}` instructions in the exported
## corpus (the other 276 carry a zero fraction and decode bit-identically), and
## FIVE of those six are scenario 29: pc 19 Delita 0x044C = 4.297, pc 27 Ramza
## 0x049C = 4.609, pc 34 ALGUS 0x0380 = **3.5**, pc 152 0x05B4 = 5.703, pc 478
## 0x05B0 = 5.688; the sixth is scenario 117 pc 65 0x0492 = 4.570. Reading only
## the integer byte made Algus's walk 224/3 = 74.67 f/tile instead of 224/3.5 =
## 64.0, which is why his opening walk overran the script's `Wait 150` budget.
##
## Read POSITIONALLY (the fraction is the operand immediately before `Speed`)
## because both catalog neighbours are named `Unknown` and a name lookup cannot
## tell them apart. Returns Speed in whole units as a float; `default` is used
## when the opcode carries no `Speed` operand at all.
static func walk_to_speed(a: EventInstructionArgs, default: float = 8.0) -> float:
	var i := a.index_of("Speed")
	if i < 0:
		return default
	return float((a.raw_at(i) << 8) | (a.nth(i - 1, 0) & 0xFF)) / 256.0


## The FacingDirection a straight walk adopts from its (dx, dz) Godot-world heading —
## walks face their dominant travel axis. The world axes map to the FacingDirection
## enum as +X→NORTH(0), −X→SOUTH(2), +Z→EAST(1), −Z→WEST(3); a tie (|dx| == |dz|)
## resolves to the X axis, matching the handler's `>=` test.
static func heading_facing_dir(dx: float, dz: float) -> int:
	if absf(dx) >= absf(dz):
		return 0 if dx >= 0.0 else 2
	return 1 if dz >= 0.0 else 3


# ---------------------------------------------------------------------------
# Units/Multi — the multi-unit broadcast SELECTOR shared by every unit-target
# opcode: {2D} Rotate, {11} Unit Anim, {32} Color Unit, {53}/{2C} Face Unit,
# {69} Face Tile. The two adjacent operands are NOT a u16 unit id — the ROM
# (resolve_event_unit_handle @0x80147928) reads them as a target set: either one
# unit, or a broadcast to a team/faction group the handler loops over. Godot used
# to fuse them via PsxNum.u16_lohi and resolve a single (usually bogus) unit,
# silently dropping every Multi≠0 broadcast (the scn6 Ovelia carry-flip root
# cause). Full RE + exec-BP truth table: EVENT_UNIT_SET_RESOLUTION.md.
# ---------------------------------------------------------------------------

## The resolved target-set of a Units/Multi selector.
##   SINGLE       — Multi=0: `Units` is one unit id (ENTD slot; ≥0x80 = special).
##   PLAYER       — Multi=1,Units=0: player team (team_color 0 / blue).
##   PLAYER_ALIVE — Multi=1,Units=1: player team, incapacitated excluded.
##   ENEMY        — Multi=1,Units=2: enemy teams (team_color != 0).
##   ENEMY_ALIVE  — Multi=1,Units=3: enemy teams, incapacitated excluded.
##   ALL          — Multi=1,Units≥4, or Multi≥2: every present unit (the ROM
##                  iterator's default arm — `Multi=2` and out-of-range set
##                  indices alias here, EVENT_UNIT_SET §5.2).
enum UnitSetMode { SINGLE, PLAYER, PLAYER_ALIVE, ENEMY, ENEMY_ALIVE, ALL }


## Classify a Units/Multi selector into its [enum UnitSetMode] (pure). Mirrors the
## ROM's `V = Units|Multi<<8` resolver (`resolve_event_unit_handle @0x80147928` +
## membership `FUN_801479ac @0x801479AC`), shared by {11}/{2D}/{53}/{32}:
##   V == 0            → mode 1 = ALL existing units (no team filter) — the broadcast
##                       sentinel. You CANNOT single-target unit 0: id 0 → V=0 → all.
##   0 < V < 0x100     → single unit id V (Multi=0, Units≠0).
##   V ≥ 0x100 (Multi=1) → team set by Units: 0=player, 1=player-alive, 2=enemy,
##                       3=enemy-alive, ≥4=all (mode = V−0xFE in ROM space).
##   Multi≥2 / out-of-range set index → the iterator's default arm = all present.
## The V==0 → ALL case (not SINGLE) is the fix behind the scn8 sepia broadcast —
## see COLOR_TINT_LUMA_MODE_SEPIA.md §10.4.
static func unit_set_mode(units: int, multi: int) -> UnitSetMode:
	if (multi & 0xFF) == 0:
		# V = Units (high byte 0). V==0 is the all-units broadcast sentinel; any
		# other value is a single unit id.
		return UnitSetMode.ALL if (units & 0xFF) == 0 else UnitSetMode.SINGLE
	if (multi & 0xFF) == 1:
		match units & 0xFF:
			0: return UnitSetMode.PLAYER
			1: return UnitSetMode.PLAYER_ALIVE
			2: return UnitSetMode.ENEMY
			3: return UnitSetMode.ENEMY_ALIVE
			_: return UnitSetMode.ALL
	return UnitSetMode.ALL


## Is a candidate unit a member of broadcast `mode`? Pure — the caller supplies the
## unit's `team_color` (0 = blue/player, non-zero = enemy; the ROM's
## `structB[+0x5]&0x30` is exactly `team_color<<4`) and `alive` (present ∧ not
## incapacitated). SINGLE never reaches here (the world resolves it by unit id, to
## preserve the ≥0x80 special-id path). GAP (accepted, user-chosen 2026-07-07): the
## ROM's *_ALIVE modes additionally drop units by a runtime ALLIANCE overlap
## (structB+0x58 masked by [0x74,0xC1,0x01,0x00,0x00]) with no source in our ENTD
## pipeline, so PLAYER_ALIVE/ENEMY_ALIVE are their no-alliance supersets here —
## team+alive only. Cutscenes have no deaths, so `alive` ≈ present. EVENT_UNIT_SET §5.
static func unit_set_member(mode: UnitSetMode, team_color: int, alive: bool) -> bool:
	var is_player := team_color == 0
	match mode:
		UnitSetMode.PLAYER: return is_player
		UnitSetMode.PLAYER_ALIVE: return is_player and alive
		UnitSetMode.ENEMY: return not is_player
		UnitSetMode.ENEMY_ALIVE: return (not is_player) and alive
		UnitSetMode.ALL: return true
	return false


# ---------------------------------------------------------------------------
# {11} Unit Anim / {47} Unit Anim Rotate — animation dispatch operands
# ---------------------------------------------------------------------------

## What a {11} Unit Anim opcode asks for, decoded from its operands. `units`/`multi`
## are the raw target-selector operands (see `unit_set_mode` — NOT a u16 unit id);
## `anim_id` selects the animation (≥0x1F5 = EVTCHR branch, ≥0x258 → the cinematic
## SEQ table — an apply concern); `flag` is the with-flags byte.
class UnitAnimIntent extends RefCounted:
	var units: int
	var multi: int
	var anim_id: int
	var flag: int


## Decode a Unit Anim opcode's operands. `Units`/`Multi` are the shared target
## SELECTOR (`unit_set_mode`), not a split u16 — the apply broadcasts the anim to
## the resolved set (Multi=0 = one unit; Multi≠0 = a team-set, e.g. the scenario-1
## `Multi != 0` rows that mean "all present units").
static func unit_anim(a: EventInstructionArgs) -> UnitAnimIntent:
	var intent := UnitAnimIntent.new()
	intent.units = a.raw("Units")
	intent.multi = a.raw("Multi")
	intent.anim_id = a.raw("Animation")
	intent.flag = a.raw("Unknown")
	return intent


# ---------------------------------------------------------------------------
# {2D} Rotate Unit — facing-mode dispatch
# ---------------------------------------------------------------------------

## What a {2D} Rotate Unit opcode asks for. `units`/`multi` are the shared target
## selector (`unit_set_mode` — the apply broadcasts the rotate to the set, e.g. the
## scn6 `[Units=1,Multi=1]` = player-team rotate that turns Ovelia); `facing` is the
## mode/absolute byte fed to resolve_rotate_target_12bit; `direction`/`speed`/`delay`
## shape the stepper.
class RotateUnitIntent extends RefCounted:
	var units: int
	var multi: int
	var facing: int
	var direction: int
	var speed: int
	var delay: int


## Decode a Rotate Unit opcode's operands into a [RotateUnitIntent].
static func rotate_unit(a: EventInstructionArgs) -> RotateUnitIntent:
	var intent := RotateUnitIntent.new()
	intent.units = a.raw("Units")
	intent.multi = a.raw("Multi")
	intent.facing = a.raw("Facing")
	intent.direction = a.raw("Direction")
	intent.speed = a.raw("Speed")
	intent.delay = a.raw("Delay")
	return intent


## Resolve the Rotate Unit target angle on the 12-bit wheel from the `Facing`
## byte's mode dispatch (hacktics disasm 0x80148284). `current_12bit` and
## `camera_yaw_12bit` are apply-time reads the caller supplies — the function
## itself is pure:
##   0x10        → camera-relative: the camera yaw quantized to a cardinal
##   0x11..0x13  → relative: current + N·0x100 (N = low nibble)
##   0x14        → no change (face-target mode; resolved elsewhere)
##   else        → absolute: the wheel-step form (byte·0x100)
static func resolve_rotate_target_12bit(facing_byte: int,
		current_12bit: int, camera_yaw_12bit: int) -> int:
	var fb := facing_byte & 0xFF
	if fb == 0x10:
		return PsxNum.cardinal12(camera_yaw_12bit)
	if fb >= 0x11 and fb <= 0x13:
		return PsxNum.wrap12(current_12bit + (fb & 0xF) * 0x100)
	if fb == 0x14:
		return PsxNum.wrap12(current_12bit)
	return PsxNum.facing_byte_to_12bit(fb)


# ---------------------------------------------------------------------------
# {32} Color Unit / {33} Color Field — palette-space affine tint
# ---------------------------------------------------------------------------

## What a Color Unit opcode ({32}) asks for. `units`/`multi` are the shared target
## selector (`unit_set_mode` — the apply tints one unit or a broadcast set). `mode`
## is the Color operation byte; `red`/`green`/`blue` are RAW operand bytes
## (ScenarioColorTint sign-extends them internally, as the PSX applier does); `time`
## is the ramp duration in frames (0 = snap). The affine math lives in
## ScenarioColorTint — this only carries operands.
class ColorUnitIntent extends RefCounted:
	var units: int
	var multi: int
	var mode: int
	var red: int
	var green: int
	var blue: int
	var time: int


## Decode a Color Unit opcode from its [EventInstructionArgs] reader.
static func color_unit(a: EventInstructionArgs) -> ColorUnitIntent:
	var intent := ColorUnitIntent.new()
	intent.units = a.raw("Units")
	intent.multi = a.raw("Multi")
	intent.mode = a.raw("Color") & 0xFF
	intent.red = a.raw("Red")
	intent.green = a.raw("Green")
	intent.blue = a.raw("Blue")
	intent.time = a.raw("Time") & 0xFF
	return intent


## What a Color Field opcode ({33}) asks for — the broadcast sibling of {32}, the
## same affine applied to the whole field (every unit + the map palette) with no
## per-unit target. Same operand carriage as [ColorUnitIntent] minus `uid`.
class ColorFieldIntent extends RefCounted:
	var mode: int
	var red: int
	var green: int
	var blue: int
	var time: int


## Decode a Color Field opcode from its [EventInstructionArgs] reader.
static func color_field(a: EventInstructionArgs) -> ColorFieldIntent:
	var intent := ColorFieldIntent.new()
	intent.mode = a.raw("Color") & 0xFF
	intent.red = a.raw("Red")
	intent.green = a.raw("Green")
	intent.blue = a.raw("Blue")
	intent.time = a.raw("Time") & 0xFF
	return intent


# ---------------------------------------------------------------------------
# {3E} Color Screen — full-screen ABR-blended colour ramp (screen-space overlay)
# ---------------------------------------------------------------------------

## What a Color Screen opcode asks for, decoded from its 9-byte body
## `[Mode, R1,G1,B1, R2,G2,B2, Time(u16)]`. Start/End are ABSOLUTE 0..255 RGB
## (UNSIGNED — not the signed deltas of {32}/{33}); `mode` is the PSX
## semi-transparency (ABR) blend equation, verbatim into the GP0 E1h draw-mode:
## 0=½B+½F (mix), 1=B+F (additive), 2=B-F (subtractive), 3=B+¼F. Screen-space
## overlay, NOT a palette tint. Full RE: COLOR_SCREEN_OPCODE_3E.md.
class ColorScreenIntent extends RefCounted:
	var mode: int
	var start: Vector3    # (R,G,B) 0..255 — ramp origin
	var end: Vector3      # (R,G,B) 0..255 — ramp target
	var time: int         # ramp length in frames (u16)


## Decode a Color Screen opcode. Param names from the vendor catalog ("Mode",
## "Red (1)".."Blue (2)", "Time").
static func color_screen(a: EventInstructionArgs) -> ColorScreenIntent:
	var intent := ColorScreenIntent.new()
	intent.mode = a.raw("Mode") & 0xFF
	intent.start = Vector3(a.raw("Red (1)"), a.raw("Green (1)"), a.raw("Blue (1)"))
	intent.end = Vector3(a.raw("Red (2)"), a.raw("Green (2)"), a.raw("Blue (2)"))
	intent.time = a.raw("Time") & 0xFFFF
	return intent


# ---------------------------------------------------------------------------
# {1A} Map Darkness — the prayer-scene "oxide" screen tint
# ---------------------------------------------------------------------------

## What a Map Darkness opcode asks for, decoded from its operands. The PSX applier
## FUN_80090840 selects 1 of 11 `blend` modes; scenario 1 uses mode 4 ("byte-
## register add"): `target = oxide_baseline + signed(R,G,B)`, clamped to a byte,
## reached over `duration_ticks` frames (`Time << 3`). `snap` (Time ≤ 0) means jump
## straight to `target` with no fade. The rest baseline is a rendering constant the
## VM owns, passed in so decode stays scene-free (mirrors PsxNum.flip_depth_row's
## `size_z` argument).
class MapDarknessIntent extends RefCounted:
	var blend: int
	var target: Vector3
	var duration_ticks: int
	var snap: bool


## Decode a Map Darkness opcode. R/G/B are signed bytes (PsxNum.s8); `oxide_baseline`
## is the live-captured rest tint (20,4,0). Modes other than 4 are still returned with
## their computed byte-add target — the apply handler warns and animates them rather
## than halting (no scenario-1 scene uses another mode).
static func map_darkness(a: EventInstructionArgs, oxide_baseline: Vector3) -> MapDarknessIntent:
	var intent := MapDarknessIntent.new()
	intent.blend = a.raw("Blend")
	var r := a.signed("Red")
	var g := a.signed("Green")
	var b := a.signed("Blue")
	var time := a.raw("Time")
	intent.target = (oxide_baseline + Vector3(r, g, b)).clamp(
		Vector3.ZERO, Vector3(255, 255, 255))
	intent.snap = time <= 0
	intent.duration_ticks = 0 if intent.snap else time * 8
	return intent


# ---------------------------------------------------------------------------
# {3C} Weather — the map-wide rain/snow particle latch
# ---------------------------------------------------------------------------

## What a Weather opcode asks for, decoded from its two operand bytes. The PSX
## dispatcher (0x80144998) packs both into one global `DAT_80173f68 = Strength |
## (Unknown << 8)`; the per-frame consumer (0x801436b0) reads `& 0x0f00` (= the
## Unknown byte) as the **active gate** and `& 0x000f` (= Strength) as the
## intensity index. `Unknown=0` CANCELS weather (clears the global to −1);
## `Unknown!=0` runs it. `strength` 0/1 = clear, 2/3/4 = rain(or snow) intensity.
## Rain-vs-snow is a per-map flag (`DAT_800b6698 & 1`), NOT this opcode — so the
## intent carries strength only. Full RE:
## research/working_documents/WEATHER_OPCODE_3C_INVESTIGATION.md §0/§10/§12.
class WeatherIntent extends RefCounted:
	## True while weather runs (Unknown != 0). False cancels the particle system.
	var active: bool
	## Intensity index 0..4 (0/1 = clear, 2/3/4 = increasing storm power).
	var strength: int


## Decode a Weather opcode from its [EventInstructionArgs] reader.
static func weather(a: EventInstructionArgs) -> WeatherIntent:
	var intent := WeatherIntent.new()
	var strength := a.raw("Strength") & 0x0F
	var unknown := a.raw("Unknown") & 0xFF
	# The active gate is the Unknown byte; Strength 0/1 is also "clear" even when
	# Unknown is set (the consumer's intensity table starts real rain at index 2).
	intent.active = unknown != 0 and strength >= 2
	intent.strength = strength
	return intent


## The fall-velocity / vertical-scatter triple `(fa6a4, fa6a8, fa6ac)` the ROM
## feeds the rain spawner for a given Strength (WEATHER doc §0/§10 table). fa6a4 =
## base fall speed, fa6a8 = near-layer speed bonus + streak-length scatter, fa6ac =
## far-layer speed bonus. Returned in PSX sub-units (28 = one tile). Clear (0/1)
## returns the rain-2 triple defensively; callers gate on `WeatherIntent.active`.
static func weather_velocity_triple(strength: int) -> Vector3:
	match strength:
		4: return Vector3(5, 9, 18)
		3: return Vector3(5, 6, 9)
		_: return Vector3(3, 5, 8)  # strength 2 (and clear fallback)


## {76} Dark Screen — the pre-battle "Conditions for Winning" overlay: an
## expanding, semi-transparent diamond mosaic that dims the whole frame. Six
## operand bytes: [Unknown=00, Shape, ScreenExpansionSpeed, RotationSpeed(u16),
## SquareExpansionSpeed]. Live scenario-4 values were the wiki defaults
## `[00, 01, 0C, 0040, 04]` (DARKSCREEN_OPCODE_76_INVESTIGATION.md §0/§8 D3). The
## renderer draws AXIS-ALIGNED diamonds — no rotation is applied in scenario 4
## despite RotationSpeed=0x40 (§11.1), so `rotation_speed` is decoded for
## faithfulness but the port leaves it unused.
class DarkScreenIntent extends RefCounted:
	## Mosaic start point / expansion shape (0..3; live=1 = top-left origin).
	var shape: int
	## How fast the mosaic front spreads to fill the screen (12 = wiki default;
	## higher = faster). Scales the expansion duration.
	var screen_expansion_speed: int
	## Per-square rotation speed (0->45deg). NOT applied in scenario 4 (§11.1);
	## carried for completeness only.
	var rotation_speed: int
	## How fast each square grows point->full from spawn (4 = wiki default).
	var square_expansion_speed: int


## Decode a Dark Screen opcode from its [EventInstructionArgs] reader. The param
## names come from the vendor EventCommands.xml ("Shape", "Screen Expansion
## Speed", "Rotation Speed", "Square Expansion Speed").
static func dark_screen(a: EventInstructionArgs) -> DarkScreenIntent:
	var intent := DarkScreenIntent.new()
	intent.shape = a.raw("Shape", 1) & 0xFF
	intent.screen_expansion_speed = maxi(1, a.raw("Screen Expansion Speed", 12))
	intent.rotation_speed = a.raw("Rotation Speed", 0x40)
	intent.square_expansion_speed = maxi(1, a.raw("Square Expansion Speed", 4))
	return intent


# ---------------------------------------------------------------------------
# {2E} Background — the full-screen Gouraud gradient backdrop + lightning flash
# ---------------------------------------------------------------------------

## What a Background opcode asks for, decoded from its 8 operand bytes
## `[Rt,Gt,Bt, Rb,Gb,Bb, Time, Unk]`. Top/Bottom are absolute 0..255 RGB corner
## colours for the vertical gradient quad; `time` ramps both over `Time*8` frames
## (`snap` when Time≤0). The `Unk` byte only selects the PSX setter path (it
## refreshes a secondary resting-gradient copy) — it does NOT change the visible
## gradient, so it is decoded but unused. Full RE:
## research/working_documents/LIGHTNING_FLASH_OPCODE_2E_BACKGROUND.md.
class BackgroundIntent extends RefCounted:
	var top: Vector3      # (R,G,B) 0..255 — the two top vertices
	var bottom: Vector3   # (R,G,B) 0..255 — the two bottom vertices
	var time: int         # ramp Time byte (0 == instant snap)
	var snap: bool


## Decode a Background opcode. Param names come from the vendor EventCommands.xml
## ("Red (Top)", "Green (Top)", … "Time", "Unknown").
static func background(a: EventInstructionArgs) -> BackgroundIntent:
	var intent := BackgroundIntent.new()
	intent.top = Vector3(
		a.raw("Red (Top)"), a.raw("Green (Top)"), a.raw("Blue (Top)"))
	intent.bottom = Vector3(
		a.raw("Red (Bottom)"), a.raw("Green (Bottom)"), a.raw("Blue (Bottom)"))
	intent.time = a.raw("Time") & 0xFF
	intent.snap = intent.time <= 0
	return intent


## {7D} Show Graphic — gradually fades a fullscreen graphic in, holds it, then
## fades it out; the very next opcode is {E5} Wait For Instruction(Task=61=0x3D)
## which blocks the scene until the graphic has fully faded away (chapter-intro
## card, ending still, GAME OVER, or a WLDBK world background). ONE operand byte:
## the Graphic ID. Formats + RE:
## research/working_documents/scenario_1_captures/show_graphic_op7d_decode.md.
class ShowGraphicIntent extends RefCounted:
	## The 1-byte Graphic ID (0x01-0x04 chapter, 0x07 game-over, 0x08-0x0C ending,
	## 0x10-0x91 WLDBK background). Resolved to a texture via the ShowGraphic
	## manifest (assets/scenarios/graphics/show_graphics.json).
	var graphic_id: int


## Decode a Show Graphic opcode from its [EventInstructionArgs] reader. The param
## name comes from the catalog ("Graphic").
static func show_graphic(a: EventInstructionArgs) -> ShowGraphicIntent:
	var intent := ShowGraphicIntent.new()
	intent.graphic_id = a.raw("Graphic") & 0xFF
	return intent


## {91} Show Map Title — reveals a pre-battle location-name strip with a L->R
## wipe, holds, then ERASES it with a second L->R wipe. BLOCKS the VM until the
## strip erases (the PSX built-in FUN_8014c9d0 wait, NOT a following {E5}). Three
## operand bytes X/Y/Speed; the image is selected by MAP context, not the operand
## (§3). RE:
## research/working_documents/scenario_1_captures/show_map_title_op91_decode.md.
class MapTitleIntent extends RefCounted:
	## On-screen X/Y offset of the strip (px in a 256x240 frame; 0 = anchored).
	var x: int
	var y: int
	## Wipe-rate multiplier for both the reveal and erase (opcode `Speed`).
	var speed: int


## Decode a Show Map Title opcode. Param names come from the catalog (X/Y/Speed).
static func show_map_title(a: EventInstructionArgs) -> MapTitleIntent:
	var intent := MapTitleIntent.new()
	intent.x = a.raw("X", 0)
	intent.y = a.raw("Y", 0)
	intent.speed = a.raw("Speed", 1)
	return intent


# ---------------------------------------------------------------------------
# {1F} Focus / {38} Focus Speed — camera-focus-on-unit(s)
# ---------------------------------------------------------------------------

## What a Focus opcode asks for, decoded from its operands. Focus is a BYTECODE
## PATCHER on PSX: the handler (FUN_80147584) resolves the two `Unit` refs to
## runtime units, reads each unit's world position, and overwrites the position
## operands of the *following* `{19}` Camera opcode with the pair's midpoint —
## `2·(pos1+pos2)` per axis = `4×midpoint`, and `4·(28-unit) = 112-unit`, i.e. the
## unit's tile position expressed in camera units. So the following Camera centres
## on the unit(s). `unit1`/`unit2` are the chunk unit ids (usually equal =
## single-unit focus).
##
## 🔴 `auto_map_rotation` (Unknown==0) PATCHES A FIFTH OPERAND, AND IT IS THE MAP
## ROTATION — not the zoom. This field was called `auto_zoom` until 2026-09-11 and
## the mis-name is why the gap was priced as "a zoom refinement on top of already-
## correct framing" and shelved. The store is unambiguous in `FUN_80147584`: after
## the three position writes `s1` points at operand slot 3, `addiu s1,s1,0x2` in the
## `bne s7,zero` delay slot (0x80147724/28) advances it to **slot 4 = Map Rotation**,
## and `FUN_80147318`'s return is stored there (0x80147740..48). `FUN_80147318`
## picks the nearest entry of the four-quadrant table `0x80169718 =
## {0xE00, 0xA00, 0x600, 0x200}` to the LIVE camera yaw, so the authored Map
## Rotation operand of the following Camera is DEAD on the 464 of 475 Focus ops in
## the corpus that carry Unknown==0. See [method
## ScenarioCameraDirector._focus_map_rotation] and
## research/working_documents/FOCUS_OPCODE_1F_INVESTIGATION.md §3/§8/§11.
class FocusIntent extends RefCounted:
	var unit1: int
	var unit2: int
	var auto_map_rotation: bool


## Decode a Focus opcode from its [EventInstructionArgs] reader. Vendor
## EventCommands.xml names: "Unit (1)" u16, "Unit (2)" u16, "Unknown" u8.
static func focus(a: EventInstructionArgs) -> FocusIntent:
	var intent := FocusIntent.new()
	intent.unit1 = a.raw("Unit (1)") & 0xFFFF
	intent.unit2 = a.raw("Unit (2)") & 0xFFFF
	intent.auto_map_rotation = a.raw("Unknown") == 0
	return intent


# ---------------------------------------------------------------------------
# {73} Camera Move (relative) — pre-patch the following {19} Camera
# ---------------------------------------------------------------------------

## The 7 signed s16 deltas a {73} opcode carries, in {19} Camera operand order
## `[X, Z, Y, Angle, Map Rotation, Camera Rotation, Zoom]`. On PSX {73} is a
## bytecode patcher (FUN_801474a4): it overwrites the FOLLOWING {19} Camera's
## first 7 operands with `live_camera_pose[f] + delta[f]` (Time is left alone;
## a delta of `0x2710` = 10000 is the "keep this field unchanged" sentinel,
## honored at patch time, not here). So {73} is a *relative* camera move keyed
## off the live pose — the sibling of {1F} Focus, which patches the same operands
## with a unit midpoint. Decoded positionally (all 7 operands are 2-byte signed)
## so the catalog's per-field names are not relied upon. Full byte-exact RE:
## research/working_documents/CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md §4.4.
static func camera_move_relative(a: EventInstructionArgs) -> Array:
	var deltas: Array = []
	for i in range(7):
		deltas.append(a.signed_at(i))
	return deltas


# ---------------------------------------------------------------------------
# {63} Camera Speed Curve — per-op ease shaping
# ---------------------------------------------------------------------------

## The nibble decode of a {63} Camera Speed Curve byte, matching the {19} task
## body's reader at 0x80146118. `intensity` (high nibble, 0..15) is the curvature
## weight: it linearly blends between pure-linear motion (0) and full symmetric
## quadratic ease-in-out (16) — see [method ScenarioCameraDirector._curve63].
## `accel_shape` (`byte & 0x3`, "A") selects the ease shape: 0 = linear,
## 1 = ease-in, 2/3 = symmetric ease-in-out (the FFHacktics "Delayed" group).
## `field_gate` (`(byte >> 2) & 0x3`, "B") gates which fields ease: 0 = position
## fields only (rotation/zoom stay linear), non-0 = all 7 fields. Full RE:
## CAMERA_ROTATION_OPCODES_63_73_19_INVESTIGATION.md §4.7/§4.8.
class SpeedCurveIntent extends RefCounted:
	var byte: int
	var intensity: int
	var accel_shape: int
	var field_gate: int


## Decode a {63} Camera Speed Curve byte into its nibbles.
static func camera_speed_curve(byte: int) -> SpeedCurveIntent:
	var intent := SpeedCurveIntent.new()
	intent.byte = byte & 0xFF
	intent.intensity = (intent.byte & 0xF0) >> 4
	intent.accel_shape = intent.byte & 0x03
	intent.field_gate = (intent.byte >> 2) & 0x03
	return intent


# ---------------------------------------------------------------------------
# {10} Display Message — overlay or boxed dialog
# ---------------------------------------------------------------------------

## What a Display Message opcode asks for, decoded from its operands (the message
## TOKENS are carried on the instruction's `dialogue` payload, not the params, so the
## apply takes them separately). `dialog` is the mode byte: 0x09 = the free overlay
## (prayer), 0x1X/0x9X = a boxed variant. `psx_x`/`psx_y` are the signed authored
## placement; `open_type` (Arrow operand) selects the box open curve + tail nudge;
## `fine_x60` (Arrow X) is the triangle tail fine-X (NOT the box X). `speaker_uid` /
## `portrait_row` pick the portrait.
class DisplayMessageIntent extends RefCounted:
	var dialog: int
	var msg_id: int
	var psx_x: int
	var psx_y: int
	var speaker_uid: int
	var portrait_row: int
	var open_type: int
	var fine_x60: int
	var is_overlay: bool


## Decode a Display Message opcode from its [EventInstructionArgs] reader. `X`/`Y`/
## `Arrow X` are 2-byte signed operands — `a.signed` reads the catalog width.
static func display_message(a: EventInstructionArgs) -> DisplayMessageIntent:
	var intent := DisplayMessageIntent.new()
	intent.dialog = a.raw("Dialog") & 0xFF
	intent.msg_id = a.raw("Message")
	intent.psx_x = a.signed("X")
	intent.psx_y = a.signed("Y")
	intent.speaker_uid = a.raw("Unit")
	intent.portrait_row = a.raw("Portrait")
	intent.open_type = a.raw("Open Type", 3) & 0xFF
	intent.fine_x60 = a.signed("Arrow X")
	# Overlay (no-box) vs boxed is the box-type nibble `Dialog & 0x70`, NOT the
	# single value 0x09: boxed variants are 0x1X/0x7X/0x9X (box_type 0x10/0x70),
	# so box_type 0 (0x0X) is the free full-screen narration/overlay family. The
	# chapel prayer is 0x09; the chapter-opening narration ("Delita's name
	# appears…", scenario 8 PC 35) is 0x0B — same no-box path, held by the
	# following {E5} Wait For Instruction Task=1 (overlay-active predicate), NOT
	# a special value. Mirrors `ScenarioDialogueBoxPool._is_boxed_dialog`
	# (`Dialog & 0x70 in {0x10, 0x70}`), inverted. display_message_overlay_decode.md §20.
	intent.is_overlay = (intent.dialog & 0x70) == 0
	return intent


# ---------------------------------------------------------------------------
# {50} Portrait Row + the {10}/{51} portrait column/visibility rule
# ---------------------------------------------------------------------------

## {50} Portrait Row — the EVTFACE row-block index (0-based) to make resident.
## The following {10}/{51} Portrait byte picks the column into this row.
## PORTRAIT_ROW_OPCODE_50_EVTFACE.md §2.1/§3.1.
static func portrait_row(a: EventInstructionArgs) -> int:
	return a.raw("Row") & 0xFF


## The {10}/{51} Portrait byte is a 1-based column: col = byte - 1. `byte == 0`
## yields -1 (no portrait); the render short-circuits on col < 0. §2.2/§2.6.
static func portrait_column(portrait_byte: int) -> int:
	return (portrait_byte & 0xFF) - 1


## Is the EVTFACE portrait drawn for this box? True IFF the box is mode 0x10
## ((Dialog & 0x70) == 0x10) AND the column is valid (portrait_byte in [1,8], so
## col in [0,8)). Rejects byte 0 (none), byte 9 (col 8, the PSX `local_ac < 8`
## sentinel), and every non-0x10 box mode (overlay/positioned boxes carry no
## face). §2.6 — replaces the incomplete `portrait_row != 0x09` gate.
static func portrait_visible(dialog: int, portrait_byte: int) -> bool:
	if (dialog & 0x70) != 0x10:
		return false
	var col := portrait_column(portrait_byte)
	return col >= 0 and col < 8


# ---------------------------------------------------------------------------
# Sound — {21} Sound Effect / {60} Fade Sound / {22} Switch Track / {6B}/{6A}
# BG Sound. Pure operand decode; the audio backend calls + the {6B} ramp
# registry / {22} toggle live in the apply/VM layers.
# ---------------------------------------------------------------------------

## {21} Sound Effect — the system SFX catalog id to play.
static func sound_effect(a: EventInstructionArgs) -> int:
	return a.raw("Sound")


## {60} Fade Sound — the music fade-out duration in sequencer ticks. The PSX
## handler latches `Time << (16 + Shift)`; the flush extracts ramp ticks as
## `(word >> 14) & 0x3FFC` = `(Time << (Shift + 2)) & 0x3FFC` (PsxNum.fade_ramp_ticks).
class FadeSoundIntent extends RefCounted:
	var ticks: int


static func fade_sound(a: EventInstructionArgs) -> FadeSoundIntent:
	var intent := FadeSoundIntent.new()
	intent.ticks = PsxNum.fade_ramp_ticks(a.raw("Time"), a.raw("Shift Amount"))
	return intent


## {22} Switch Track — the resolved master `target_vol` (FFT `FUN_8012db90` curve:
## 0→0, ≥96→127, else Volume·127/96) and `ticks` (Time·4). Which of the two
## ATTACK.OUT songs plays is the VM's `_track_toggle` scheduler state, not decode.
class SwitchTrackIntent extends RefCounted:
	var target_vol: int
	var ticks: int


static func switch_track(a: EventInstructionArgs) -> SwitchTrackIntent:
	var intent := SwitchTrackIntent.new()
	intent.target_vol = PsxNum.track_volume_curve(a.raw("Volume"))
	intent.ticks = a.raw("Time") << 2  # Time*4 sequencer ticks
	return intent


## {6B}/{6A} BG Sound — the shared positional byte layout
## [Sound, StartVol, Volume, Stacking, Time]. Read by POSITION, not name: the two
## opcodes share this layout despite the catalog naming op[1] "Echo" (it's the ramp
## StartVol, doc §4) and giving {6A} two operands both named "Unknown" — a name-keyed
## read would collapse the dup, so `a.nth` reads by index (ADR-0059).
class BgSoundIntent extends RefCounted:
	var sound_id: int
	var start_vol: int
	var target_vol: int
	var stacking: int
	var time: int


static func bg_sound(a: EventInstructionArgs) -> BgSoundIntent:
	var intent := BgSoundIntent.new()
	intent.sound_id = a.nth(0)
	intent.start_vol = a.nth(1)
	intent.target_vol = a.nth(2)
	intent.stacking = a.nth(3)
	intent.time = a.nth(4)
	return intent
