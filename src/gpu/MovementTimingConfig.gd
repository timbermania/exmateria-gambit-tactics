class_name MovementTimingConfig
extends RefCounted

## Movement Timing Configuration
##
## Centralizes timing constants for GPU movement visualization.
## This ensures CPU visual interpolation matches GPU simulation timing.
##
## Key concepts:
## - TICKS_PER_SEQ_FRAME: How many GPU ticks per SEQ animation frame
## - Animation phases: JUMPING (wind-up), ARC (airborne movement), LANDING
## - Arc speed: How fast the unit moves through the air
## - Walk speed: How fast the unit walks on flat/ramp terrain
##
## Movement timing is synced to the MoveUp2 opcode in SEQ animation data.
## Animation 60 (JUMPING) fires MoveUp2 at frame 22, meaning:
## - Frames 0-21: Wind-up (unit stays at start position)
## - Frame 22+: Unit launches into air and moves to destination

# GPU tick rate (ticks per second at 60 FPS)
const GPU_TICKS_PER_SECOND: float = 60.0

# Global speed multiplier - change THIS ONE NUMBER to slow/speed everything
# 1.0 = normal, 2.0 = half speed, 0.5 = double speed
const GLOBAL_SPEED_DIVISOR: float = 1.0

# Animation frame timing
# Value of 2 means: 2 GPU ticks per SEQ animation frame = 30 FPS animation at 60 tick rate
# Higher values = slower animations
const TICKS_PER_SEQ_FRAME: int = 2

# MoveUp2 opcode position in animation 60 (JUMPING)
# This is the frame when the unit actually starts moving through the air
# Parsed from type1_seq.json: frames 0-21 are wind-up, MoveUp2 fires at frame 22
const JUMPING_MOVE_START_FRAME: int = 22

# Landing animation duration (in SEQ frame ticks, from type1_seq.json)
# Animation 64 (LAND_FROM_JUMP): sum of LoadFrameWait durations before PauseAnimation
const LANDING_SEQ_FRAMES: int = 18

# Movement speeds (units per second)
# Lower values = slower movement
const ARC_SPEED: float = 6.0
const WALK_SPEED: float = 2.0

# Activity SEQ speed multipliers (higher = faster)
# These scale both the timer duration AND the SEQ frame advancement rate
const HORIZONTAL_MOVE_SEQ_SPEED: int = 1   # Flat walking speed (feels good already)
const VERTICAL_MOVE_SEQ_SPEED: int = 2     # Cliff jump speed (2x faster)
const CHARGE_SEQ_SPEED: int = 1            # Spell charge speed
const ABILITY_SEQ_SPEED: int = 1           # Attack/cast animation speed


## Get number of GPU ticks for the JUMPING wind-up phase
## This is the time before MoveUp2 fires (unit stays at start position)
static func get_jumping_ticks() -> int:
	# Wind-up matches animation speed - don't apply global speed divisor
	return ceili(JUMPING_MOVE_START_FRAME * TICKS_PER_SEQ_FRAME)


## Get number of GPU ticks for the LANDING animation phase
static func get_landing_ticks() -> int:
	# Landing animation matches animation speed - don't apply global speed divisor
	return ceili(LANDING_SEQ_FRAMES * TICKS_PER_SEQ_FRAME)


## Get number of GPU ticks for arc movement phase
## Args:
##   arc_distance: Total path length along the arc in world units
static func get_arc_ticks(arc_distance: float) -> int:
	if arc_distance <= 0.0:
		return 1  # Minimum 1 tick
	return ceili(arc_distance / ARC_SPEED * GPU_TICKS_PER_SECOND * GLOBAL_SPEED_DIVISOR)


## Get total ticks for a flat/ramp move (scaled by HORIZONTAL_MOVE_SEQ_SPEED)
## Args:
##   distance: Distance to travel in world units
static func get_flat_move_ticks(distance: float) -> int:
	if distance <= 0.0:
		return 1  # Minimum 1 tick
	return ceili(distance / WALK_SPEED * GPU_TICKS_PER_SECOND * GLOBAL_SPEED_DIVISOR) / HORIZONTAL_MOVE_SEQ_SPEED


## Get scaled jumping ticks for cliff moves (divided by VERTICAL_MOVE_SEQ_SPEED)
static func get_cliff_jumping_ticks() -> int:
	return get_jumping_ticks() / VERTICAL_MOVE_SEQ_SPEED


## Get scaled landing ticks for cliff moves (divided by VERTICAL_MOVE_SEQ_SPEED)
static func get_cliff_landing_ticks() -> int:
	return get_landing_ticks() / VERTICAL_MOVE_SEQ_SPEED


## Get scaled arc ticks for cliff moves (divided by VERTICAL_MOVE_SEQ_SPEED)
static func get_cliff_arc_ticks(arc_distance: float) -> int:
	return get_arc_ticks(arc_distance) / VERTICAL_MOVE_SEQ_SPEED


