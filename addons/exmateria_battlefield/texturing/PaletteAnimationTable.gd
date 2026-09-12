extends RefCounted

## Turn a map manifest's `animations.palette_animations` list into the PER-PALETTE-ID
## schedule that `indexed_color.gdshader` samples.
##
## A palette animation belongs to the CLUT, not to a surface: on PSX it runs on whatever
## polygons sample that palette. The shader therefore keys the schedule on the polygon's
## own palette id, and this class is the pure function that lays the manifest's entries
## out into the four 16-wide parallel arrays it reads.
##
## WHAT THIS REPLACES. `DynamicGeometryBuilder._get_palette_animation_config()` used to
## collapse every entry into ONE animation: `min(overridden_palette_id)` ..
## `max(overridden_palette_id)` as a contiguous RANGE, with `animation_start_index`,
## `frame_count` and `frame_duration` taken from `palette_animations[0]` alone, under the
## comment *"All entries typically share same animation_start_index, frame_count,
## frame_duration"*. That is false for 16 of the 18 multi-entry maps in the corpus.
## MAP009 (Citadel of Igros) is the worked example — three entries:
##
##     palette 2  start 0  3 frames  duration 15  ForwardAndReverseLooping
##     palette 5  start 3  4 frames  duration  9  ForwardLooping
##     palette 7  start 7  4 frames  duration  9  ForwardLooping
##
## The collapse yielded start=2 count=6, so palettes 3, 4 and 6 — which have no animation
## at all — animated, and 5 and 7 sampled palette 2's rows 16-18 instead of their own
## 19-22 and 23-26. Per palette, none of that arises.
##
## TRIGGER MODES DO NOT FREE-RUN. `ForwardLoopingOnTrigger` and `ForwardOnceOnTrigger`
## are played by an event, not by the clock, so they get `count = 0` here and the shader
## leaves them on their base palette row. Eight entries across the corpus are in that
## state; free-running them would be inventing motion the ROM does not show.

const PALETTE_COUNT: int = 16

## Row 16 of the 16x32 palette texture is animation_frame 0 (PaletteTextureGenerator).
const ANIM_ROW_BASE: int = 16

## `PaletteAnimationMode` (tools/fft_exporter/models/animation.py). The two clock-driven
## modes; the trigger modes are named here only so the table can exclude them by name.
const MODE_FORWARD_LOOPING: int = 3
const MODE_FORWARD_AND_REVERSE_LOOPING: int = 4
const FREE_RUNNING_MODES: Dictionary = {
	"ForwardLooping": MODE_FORWARD_LOOPING,
	"ForwardAndReverseLooping": MODE_FORWARD_AND_REVERSE_LOOPING,
}


## Build the shader's per-palette schedule.
##
## Args:
##     palette_anims: manifest.animations.palette_animations (Array of Dictionary)
##
## Returns a Dictionary of shader-ready uniform values:
##     any:      bool — does ANY palette free-run? (drives `enable_palette_animation`)
##     start:    PackedInt32Array[16]   — animation_frame row offset per palette id
##     count:    PackedInt32Array[16]   — frame count per palette id; 0 = does not animate
##     duration: PackedFloat32Array[16] — ticks per frame per palette id
##     mode:     PackedInt32Array[16]   — MODE_* per palette id
static func build(palette_anims: Array) -> Dictionary:
	var start := PackedInt32Array()
	var count := PackedInt32Array()
	var duration := PackedFloat32Array()
	var mode := PackedInt32Array()
	start.resize(PALETTE_COUNT)
	count.resize(PALETTE_COUNT)
	duration.resize(PALETTE_COUNT)
	mode.resize(PALETTE_COUNT)
	# resize() zero-fills; count 0 already means "does not animate", and duration is
	# clamped shader-side, so an untouched slot is inert without further work.
	for i in range(PALETTE_COUNT):
		mode[i] = MODE_FORWARD_LOOPING

	var any := false
	for anim in palette_anims:
		var palette_id: int = int(anim.get("overridden_palette_id", -1))
		if palette_id < 0 or palette_id >= PALETTE_COUNT:
			continue
		var frames: int = int(anim.get("frame_count", 0))
		if frames <= 0:
			continue
		var mode_name: String = str(anim.get("animation_mode", ""))
		if not FREE_RUNNING_MODES.has(mode_name):
			continue  # trigger-driven (or unknown): the clock must not play it

		# Two entries CAN name the same palette id (MAP018 names 10 twice, MAP033
		# names 13 twice). One CLUT can only show one schedule, so the last entry
		# wins — the same order the exporter emitted them in.
		start[palette_id] = int(anim.get("animation_start_index", 0))
		count[palette_id] = frames
		duration[palette_id] = float(anim.get("frame_duration", 0))
		mode[palette_id] = FREE_RUNNING_MODES[mode_name]
		any = true

	return {
		"any": any,
		"start": start,
		"count": count,
		"duration": duration,
		"mode": mode,
	}


## Push a built table onto a material. Kept beside `build` so the uniform NAMES have one
## home shared by the producer and every caller.
static func apply_to_material(material: ShaderMaterial, table: Dictionary) -> void:
	material.set_shader_parameter("enable_palette_animation", table["any"])
	material.set_shader_parameter("palette_anim_start", table["start"])
	material.set_shader_parameter("palette_anim_count", table["count"])
	material.set_shader_parameter("palette_anim_duration", table["duration"])
	material.set_shader_parameter("palette_anim_mode", table["mode"])
