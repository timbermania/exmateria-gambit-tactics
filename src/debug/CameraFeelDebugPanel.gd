class_name CameraFeelDebugPanel
extends BaseDebugPanel

## Camera-tab panel for the gameplay camera's framing and "feel" knobs: FFT's low
## vertical framing datum, the WASD-walk deadzone scroll box (overlay + width/height),
## the Q/E rotation-and-recenter feel (concurrent toggle + kickoff threshold), and the
## rotation / translation lerp speeds.
## Every row is a shared TuneField bound to a `camera.*` slug (ADR-0068
## move 2): PlayerCamera OWNS these values (it binds each slug in _ready), so this
## panel is just a VIEW (decision 12) — a scrub writes the slug, the camera
## re-applies it, and the knob moves in any scene / on the generated dashboard.
## No writes onto the PlayerCamera node.

const TuneField = preload("res://src/debug/TuneField.gd")

# Pure VIEW (ADR-0068 decision 12): every row passes the slug only — PlayerCamera owns each
# default + hint, read back from the registry. No defaults/hints, no owner symbols here.


## `camera` is unused now that PlayerCamera owns every value (it binds the slugs
## itself); the param stays for call-site compatibility (GPUArena passes it).
func setup(_camera) -> void:
	panel_title = "Camera Feel"
	panel_category = Category.CAMERA
	_build_ui()


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(260, 0)
	add_child(vbox)

	add_section_title(vbox, "Framing")
	_wrapped(vbox, "FFT frames its optical centre 40 native px BELOW the midpoint of the 240-line frame, not on it: the point the camera aims at projects to (128, 160). The anchor is at the subject's FEET, and the sprite, the damage numbers and the spell blooms all live above it — so a low aim buys headroom, keeps the up-slope the cursor is climbing in frame, and leaves the bottom strip to the AT list.")
	_wrapped(vbox, "This is the same datum the cinematic camera uses, so both rigs frame a tile on the same row. Set it to 0 for the A/B: the framed tile walks back to the viewport midpoint, which is how this camera shipped before.")
	TuneField.add(vbox, "Vertical datum (px)", "camera.vertical_datum_px")

	add_separator(vbox)
	add_section_title(vbox, "Cursor scroll box")
	_wrapped(vbox, "Camera holds still until the active tile leaves this box, then scrolls to keep it on the edge. The box is centred on the FRAMED row above, not on the middle of the screen, so the height is clamped to the room that leaves underneath — at datum 40 it stops mattering past ~0.66.")

	TuneField.add(vbox, "Show box overlay", "camera.show_deadzone_box")

	add_separator(vbox)
	TuneField.add(vbox, "Width (frac)", "camera.deadzone_width")
	TuneField.add(vbox, "Height (frac)", "camera.deadzone_height")

	add_separator(vbox)
	add_section_title(vbox, "Q/E rotation feel")
	_wrapped(vbox, "Off: FFT-style — yaw first, then body translates. On: yaw and body translate at the same time.")
	TuneField.add(vbox, "Concurrent rot+move", "camera.rotation_concurrent_translate")

	_wrapped(vbox, "Translation kickoff (sequential): start the pan when this much rotation remains. Higher = earlier, more overlap. 0 = wait for full settle.")
	TuneField.add(vbox, "Kickoff (deg)", "camera.rotation_kickoff_remaining_deg")

	add_separator(vbox)
	add_section_title(vbox, "Speeds")
	_wrapped(vbox, "Rotation speed — higher = snappier yaw.")
	TuneField.add(vbox, "Rotation speed", "camera.rot_speed")
	_wrapped(vbox, "Translation ease (frames @ 60Hz) — lower = snappier pan.")
	TuneField.add(vbox, "Translation ease", "camera.follow_ease_frames")
	_wrapped(vbox, "Battle-handoff ease (SECONDS) — the glide onto the first unit when a "
		+ "battle intro hands the camera over. Seconds, not frames, because it is armed "
		+ "right after a build hitch; ROM reference is the victory beat's {19} at Time=48 "
		+ "ticks = 0.80 s.")
	TuneField.add(vbox, "Handoff ease", "camera.handoff_ease_seconds")


## A word-wrapped description label capped to the panel width.
func _wrapped(parent: Control, text: String) -> Label:
	var l := add_label(parent, text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 250
	return l
