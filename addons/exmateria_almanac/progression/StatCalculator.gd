extends RefCounted

## FFT-style stat calculation utilities
##
## Handles stat growth on level-up and effective stat calculation based on
## job multipliers. Uses FFT's fixed-point math (× 16384) for precision.
##
## Formula Reference:
##   Growth: raw_stat += raw_stat / (job_constant + level)
##   Effective: displayed = (raw_stat × job_multiplier / 100) / 16384

const FIXED_POINT_DIVISOR: int = 16384
const MAX_RAW_STAT: int = 0xFFFFFF  # 24-bit cap


static func grow_stat(current_raw: int, job_constant: int, level: int) -> int:
	"""Apply FFT growth formula to a raw stat.

	Args:
		current_raw: Current raw stat value (fixed-point × 16384)
		job_constant: Job's growth constant for this stat (higher = slower growth)
		level: Unit's current level before level-up

	Returns:
		New raw stat value after growth

	Example:
		# Knight (hp_constant=10) at level 5
		# If raw_hp = 507904 (31.0 display):
		# growth = 507904 / (10 + 5) = 33860
		# new_raw = 507904 + 33860 = 541764 (33.08 display)
	"""
	if job_constant + level <= 0:
		return current_raw  # Safety: prevent division by zero

	var growth = current_raw / (job_constant + level)
	return mini(current_raw + growth, MAX_RAW_STAT)


static func get_effective_stat(raw_stat: int, job_multiplier: int) -> int:
	"""Calculate displayed stat from raw value and job multiplier.

	Args:
		raw_stat: Raw stat value (fixed-point × 16384)
		job_multiplier: Job's multiplier for this stat (percentage, e.g., 120 = 120%)

	Returns:
		Integer stat value for display/combat calculations

	Example:
		# Knight with hp_multiplier=120, raw_hp=507904
		# result = (507904 × 120 / 100) / 16384 = 37.2 → 37
	"""
	var multiplied = (raw_stat * job_multiplier) / 100
	return multiplied / FIXED_POINT_DIVISOR


static func raw_to_display(raw_stat: int) -> float:
	"""Convert raw stat to display value (for debugging).

	Args:
		raw_stat: Raw stat value (fixed-point × 16384)

	Returns:
		Float display value
	"""
	return float(raw_stat) / float(FIXED_POINT_DIVISOR)
