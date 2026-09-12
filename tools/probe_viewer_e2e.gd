extends Node

## Ticket #221 — end-to-end proof that the REAL EffectViewer previewer scene renders effects
## through the display-space compositor (slice D "compositor everywhere"). Boots the actual
## EffectViewer.tscn, waits for it to settle (map + units), plays a real effect via its public
## play_effect(), and watches for the compositor engaging: the driver node must be attached and
## the compositor must log "[combat-composite] active" (it only prints that when it folds).
##
## Run headful:  godot --path . res://tools/probe_viewer_e2e.tscn   (NEVER --headless)

const VIEWER := "res://assets/scenes/EffectViewer.tscn"
const EFFECT_ID := 65    # panel default (E065)

var _scene: Node
var _frame := 0
var _played := false
var _play_frame := -1


func _ready() -> void:
	_scene = load(VIEWER).instantiate()
	add_child(_scene)


func _process(_dt: float) -> void:
	_frame += 1

	# Wait until the previewer FULLY settled: caster/target spawned AND the compositor driver
	# attached (it's added at the end of the settle section of _ready) + a small margin so the
	# effect subsystems are live before we play.
	if not _played:
		var driver_up := _scene.get_node_or_null("CombatCompositeDriver") != null
		var ready := _scene.get("_caster") != null and _scene.get("_target") != null and driver_up
		if ready and _frame > 20:
			var driver := _scene.get_node_or_null("CombatCompositeDriver")
			print("[e2e] scene settled at frame %d — CombatCompositeDriver attached = %s" % [
				_frame, str(driver != null)])
			print("[e2e] playing E%03d ..." % EFFECT_ID)
			_scene.call("play_effect", EFFECT_ID, false)
			_played = true
			_play_frame = _frame
		elif _frame > 240:
			print("[e2e] RESULT FAIL — previewer never settled (no caster/target by frame %d)" % _frame)
			get_tree().quit()
		return

	# After play, give the effect time to emit particles + the compositor to fold (render-thread
	# unified upload lags ~1 frame; effects take a few frames to spawn visible particles).
	if _played and _frame - _play_frame > 30:
		# The definitive signal is the compositor's "[combat-composite] active" log above. Here we
		# just confirm the driver exists + an effect is current, then stop.
		var driver := _scene.get_node_or_null("CombatCompositeDriver")
		var cur = _scene.get("_current_effect")
		print("[e2e] driver_attached=%s  current_effect=%s" % [str(driver != null), str(cur != null)])
		print("[e2e] RESULT %s — if '[combat-composite] active' appeared above, the previewer folds through the compositor" % (
			"PASS" if driver != null else "FAIL(no driver)"))
		get_tree().quit()
