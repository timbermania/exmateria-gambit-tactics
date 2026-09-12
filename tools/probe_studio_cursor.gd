extends Node
## Boot probe: stand up the real EffectViewer scene, let it settle, and print the
## definitive camera_mode + tile-cursor dagger visibility AT REST (no user input).
## Confirms the "no cursor at boot" fix: the Studio must boot in CURSOR mode with
## the dagger visible, NOT seize the camera because the default effect (E317) has
## a camera timeline.
##
## Run: <GODOT> --path . --quit-after 240 res://tools/probe_studio_cursor.tscn

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")


func _ready() -> void:
	var scene = EffectViewer.instantiate()
	add_child(scene)
	# Let EffectViewerScene._ready run its awaited map build / unit spawn / studio
	# page setup, then a few _process frames for the reconcile to settle.
	for _i in 40:
		await get_tree().process_frame

	var cam = scene.get_node_or_null("PlayerCamera")
	var cursor = scene.get_node_or_null("TileCursor")
	var mode_str := "??"
	if cam:
		mode_str = "CURSOR" if cam.camera_mode == cam.CameraMode.CURSOR else "TAKEOVER"
	var dagger := "??"
	if cursor:
		var hl = cursor.get_node_or_null("HighlightMesh")
		if hl:
			dagger = "VISIBLE" if hl.visible else "HIDDEN"

	print("[PROBE] boot-at-rest: camera_mode=%s  dagger=%s" % [mode_str, dagger])
	if mode_str == "CURSOR" and dagger == "VISIBLE":
		print("[PROBE] PASS — Studio boots with the tile cursor present (regression fixed)")
	else:
		print("[PROBE] FAIL — expected CURSOR + VISIBLE at boot")
	get_tree().quit()
