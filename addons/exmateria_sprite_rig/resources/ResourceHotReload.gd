extends Node

## File-mtime watcher for the animation resolution map (Q5 of the live-edit
## grilling). Scene-local: instantiated by UnitAnimationViewerScene._ready
## so it only runs in the authoring context — gameplay scenes don't poll.
##
## Polls `map.tres`'s modification time every POLL_INTERVAL seconds via
## a Timer (cheap; one stat call). When the mtime changes, reloads the
## Resource with CACHE_MODE_IGNORE (bypassing Godot's resource cache),
## calls `AnimationResolutionMap.set_resource(...)`, and emits
## `resource_reloaded` so the viewer panel can re-fire the current
## activity and repaint with the freshly-edited routing.

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const AnimationResolutionMap = preload("res://addons/exmateria_sprite_rig/layers/AnimationResolutionMap.gd")

## No longer a global `class_name` since #744; aliased back for the `is` check below.
const AnimationResolutionMapResource = preload("res://addons/exmateria_sprite_rig/resources/AnimationResolutionMapResource.gd")

const RESOURCE_PATH := "res://addons/exmateria_sprite_rig/resources/map.tres"
const POLL_INTERVAL := 0.5

signal resource_reloaded

var _last_mtime: int = 0
var _timer: Timer


func _ready() -> void:
	_last_mtime = FileAccess.get_modified_time(RESOURCE_PATH)
	_timer = Timer.new()
	_timer.wait_time = POLL_INTERVAL
	_timer.autostart = true
	_timer.timeout.connect(_check_file)
	add_child(_timer)


func _check_file() -> void:
	var mt := FileAccess.get_modified_time(RESOURCE_PATH)
	if mt == 0 or mt == _last_mtime:
		return
	_last_mtime = mt
	# CACHE_MODE_IGNORE forces Godot to re-read from disk rather than handing
	# back the cached Resource (which is what the running scene loaded at
	# startup). Without this we'd see the new mtime but stale data.
	var new_res = ResourceLoader.load(RESOURCE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if new_res is AnimationResolutionMapResource:
		AnimationResolutionMap.set_resource(new_res)
		resource_reloaded.emit()
		print("[ResourceHotReload] map.tres reloaded (mtime=%d)" % mt)
	else:
		push_warning("[ResourceHotReload] reload returned non-AnimationResolutionMapResource")
