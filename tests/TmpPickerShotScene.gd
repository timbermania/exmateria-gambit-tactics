extends Node3D
## THROWAWAY visual-verify scene (delete after use): boots the FormationDetailTransition →
## Item → Equip → slot focus → ○ picker-preview state (same preamble as FormationEquipPickerTest)
## and saves a viewport screenshot to tmp/picker_preview_shot.png, then quits.

const FormationDetailTransition = preload("res://src/ui3/formation/FormationDetailTransition.gd")
const SpriteSlideAnimator = preload("res://src/ui3/detail/SpriteSlideAnimator.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")


func _ready() -> void:
	# #417: this scene asserts nothing, and until now it said so only in its
	# docstring — a place the verdict reader cannot score. On the channel now.
	print("[NOT_A_TEST] a throwaway visual-verify scene — it saves tmp/picker_preview_shot.png and quits")
	# ADR-0181: the host no longer seeds — it reads `CharacterCatalog.owned_units()`, so the
	# fixture this test was implicitly getting is now stated here. Same seeder, same units,
	# so every golden below is unmoved; what changed is that the input is written down.
	# It sits at the top of `_ready` rather than beside a `.new()` because a file can hold
	# more than one host factory, and whichever runs FIRST must already find a roster.
	CharacterCatalog.reset_to_new_game()
	PromotedRosterSeeder.seed()
	var host: FormationDetailTransition = FormationDetailTransition.new()
	host.name = "Host"
	add_child(host)
	for _i in 4:
		await get_tree().process_frame
	var form = host._formation
	if form == null:
		print("[SHOT-FAIL] no formation")
		get_tree().quit(1)
		return
	form._unhandled_input(_action("ui_accept"))
	host.open_action_menu()
	host.action_menu().confirm()
	for _s in VitalsSlideAnimator.settle_frame() + SpriteSlideAnimator.SLIDE_DURATION + 2:
		host.equip_step()
	host.action_menu().confirm()
	host._input(_action("ui_accept"))
	# Let the picker box-open + compare reveal settle fully before the shot.
	for _i in 40:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("/tmp/port_picker_shot.png")
	print("[SHOT-OK] saved /tmp/port_picker_shot.png")
	get_tree().quit(0)


func _action(nm: String) -> InputEventAction:
	var ev := InputEventAction.new()
	ev.action = nm
	ev.pressed = true
	return ev
