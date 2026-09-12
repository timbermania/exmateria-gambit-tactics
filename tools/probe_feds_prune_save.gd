extends Node
## OBSERVE (not read) what a prune-for-real + save actually does today
## (ADR-0085 amendment 2026-08-18b, §1 of the implementation handoff): the writer
## refuses a length change, so the claim is that a pruned (smaller) FEDS blob
## cannot be saved. This boots the studio, prunes the first pair that has
## anything prunable, then runs the real studio_save and prints the result.
##
## Run (NOT headless):
##   EFFECT=E001 godot --path . --quit-after 900 res://tools/probe_feds_prune_save.tscn

const EffectViewer := preload("res://assets/scenes/EffectViewer.tscn")


func _ready() -> void:
	var want: String = OS.get_environment("EFFECT")
	if want == "":
		want = "E001"

	var scn = load(EffectViewer.resource_path).instantiate()
	add_child(scn)
	await _frames(40)
	var page = scn._studio_page
	var dir := ""
	for d in page._effect_dirs:
		if String(d).ends_with(want):
			dir = d
	if dir == "":
		print("[prunesave] %s not in the picker" % want)
		get_tree().quit(1)
		return
	page._load_effect(dir)
	await _frames(30)

	var data = scn._current_effect.effect_data if scn._current_effect != null else null
	if data == null or data.feds_bank == null:
		print("[prunesave] %s has no live feds bank" % want)
		get_tree().quit(1)
		return
	var before: int = data.feds_bank.raw.size()
	print("[prunesave] %s feds blob is %d bytes before the prune" % [want, before])

	# A clean save FIRST, so a failure after the prune can only be the resize.
	var pre_save: Dictionary = scn.studio_save()
	print("[prunesave] save BEFORE prune: ok=%s error=%s"
			% [pre_save.get("ok", false), pre_save.get("error", "")])

	var pruned := -1
	for i in range(32):
		var res: Dictionary = scn.studio_prune_feds_noops(i)
		if not res.is_empty():
			pruned = i
			break
	if pruned < 0:
		print("[prunesave] %s has no prunable no-ops in pairs 0..31 — try another effect" % want)
		get_tree().quit(0)
		return
	await _frames(10)
	var after: int = scn._current_effect.effect_data.feds_bank.raw.size()
	print("[prunesave] pruned pair %d — feds blob is now %d bytes (delta %+d)"
			% [pruned, after, after - before])

	var post_save: Dictionary = scn.studio_save()
	print("[prunesave] save AFTER prune: ok=%s out=%s error=%s"
			% [post_save.get("ok", false), post_save.get("out_path", ""),
			post_save.get("error", "")])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame
