class_name PSXDitherCurves
extends RefCounted
## PSX-style dither curves for color interpolation
##
## FFT uses pre-computed lookup tables instead of division for smooth color transitions.
## Each curve is 32 signed byte deltas that sum to a specific total change.
## This creates the characteristic "stepped" PSX visual feel.
##
## Curve selection: curve_index = clamp(color_delta + 31, 0, 63)
## - Curve 0: Maximum decrease (-32 over 32 frames)
## - Curve 31: No change (neutral)
## - Curve 63: Maximum increase (+32 over 32 frames)

# Pre-computed dither curves (64 curves × 32 deltas each)
# Each curve distributes N deltas across 32 frames using dithering patterns
# Stored as Array[Array] of ints since Godot 4 doesn't have PackedInt8Array
static var _curves: Array = []
static var _initialized: bool = false


static func _init_curves() -> void:
	"""Generate the 64 dither curves based on PSX patterns"""
	if _initialized:
		return

	_curves.clear()

	for curve_idx in range(64):
		var curve: Array[int] = []
		curve.resize(32)
		for i in range(32):
			curve[i] = 0

		# Total delta for this curve: curve_idx - 31
		# Curve 0 = -31, Curve 31 = 0, Curve 63 = +32
		var total_delta: int = curve_idx - 31

		if total_delta == 0:
			# Neutral curve - already zeros
			pass
		elif total_delta > 0:
			# Increasing curves - distribute +1s using dithering
			_fill_dithered_curve(curve, total_delta, 1)
		else:
			# Decreasing curves - distribute -1s using dithering
			_fill_dithered_curve(curve, -total_delta, -1)

		_curves.append(curve)

	_initialized = true


static func _fill_dithered_curve(curve: Array[int], count: int, delta: int) -> void:
	"""Fill a curve with 'count' deltas distributed across 32 frames using dithering

	Uses Bresenham-style distribution for even spacing (same pattern as PSX).
	"""
	if count >= 32:
		# Maximum change - every frame gets a delta
		for i in range(32):
			curve[i] = delta
	elif count <= 0:
		# No change - already zeros
		pass
	else:
		# Distribute 'count' deltas across 32 frames using dithering
		# This creates the characteristic PSX stepped transitions
		var error: float = 0.0
		var step: float = float(count) / 32.0
		var placed: int = 0

		for i in range(32):
			error += step
			if error >= 0.5 and placed < count:
				curve[i] = delta
				error -= 1.0
				placed += 1
			else:
				curve[i] = 0


static func get_curve(curve_index: int) -> Array:
	"""Get a specific dither curve (0-63)"""
	if not _initialized:
		_init_curves()
	return _curves[clampi(curve_index, 0, 63)]


static func interpolate_channel(start: float, end: float, frame: int, duration: int) -> float:
	"""Interpolate a single color channel using PSX dither curves

	Args:
		start: Starting value (0.0 - 1.0)
		end: Ending value (0.0 - 1.0)
		frame: Current frame within the transition (0 to duration-1)
		duration: Total frames for this transition

	Returns:
		Interpolated value using PSX-style dithering
	"""
	if not _initialized:
		_init_curves()

	if duration <= 1:
		return end

	# Convert to 0-255 range for curve calculation (PSX uses 8-bit colors)
	var start_byte: int = int(start * 255.0)
	var end_byte: int = int(end * 255.0)
	var delta: int = end_byte - start_byte

	# Select curve based on delta (curve 31 = no change)
	var curve_index: int = clampi(delta + 31, 0, 63)
	var curve: Array = _curves[curve_index]

	# For durations != 32, we need to scale the curve application
	# PSX curves are designed for 32-frame transitions
	var current_value: int = start_byte

	if duration == 32:
		# Perfect match - just sum deltas up to current frame
		for i in range(mini(frame, 32)):
			current_value += curve[i]
	else:
		# Scale the curve to match our duration
		# Apply proportional amount of the curve based on progress
		var progress: float = float(frame) / float(duration)
		var curve_frame: int = int(progress * 32.0)

		for i in range(mini(curve_frame, 32)):
			current_value += curve[i]

		# For partial frames, interpolate the remainder
		if curve_frame < 32:
			var frac: float = (progress * 32.0) - float(curve_frame)
			current_value += int(float(curve[mini(curve_frame, 31)]) * frac)

	# Clamp to valid range and convert back to 0-1
	return clampf(float(current_value) / 255.0, 0.0, 1.0)


static func interpolate_color(start: Color, end: Color, frame: int, duration: int) -> Color:
	"""Interpolate a color using PSX dither curves

	Args:
		start: Starting color
		end: Ending color
		frame: Current frame within the transition
		duration: Total frames for this transition

	Returns:
		Interpolated color using PSX-style dithering per channel
	"""
	return Color(
		interpolate_channel(start.r, end.r, frame, duration),
		interpolate_channel(start.g, end.g, frame, duration),
		interpolate_channel(start.b, end.b, frame, duration),
		1.0
	)
