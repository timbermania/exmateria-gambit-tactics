class_name UIWiring
extends RefCounted

## Extraction #8's assembler, for the five lines `UI` used to push itself (#1273,
## owed by ADR-0308's arm 2a). *"A composition that wires once and leaves."*
##
## `BattlefieldWiring` is the precedent and this is deliberately a SIBLING, not an
## addition to it: that file states in its own first line that it is ADR-0134's
## assembler for extraction #3's three lines. One assembler per extraction keeps
## `grep` able to answer "what does this addon still need a host for".
##
## UI publishes three events and names nobody who wants them:
##
##     DialogueBox.page_turned                      -> Audio.SfxRouter
##     DialogueBox.glyph_revealed                   -> Audio.SfxRouter
##     FormationDetailTransition.input_refused      -> Audio.SfxRouter
##
## Before this, each was a direct call from inside a UI member into a host autoload.
## An addon cannot ship `project.godot` entries (ADR-0262 dec. 6) and every stranger
## rig declares an EMPTY `[autoload]` block, so `SfxRouter` is not a degraded feature
## in a vendoring project — it is an undefined identifier and a PARSE-TIME break.
##
## 🔴 WHY INVERSION AND NOT A PORT. #1263, #1271 and #1272 all answered their
## identifier with a door (`DisplayPort`, `UIDebug`, `UIRoster`), and this one does
## not, because the question is different. Those three READ host state that UI needs
## in order to render correctly. This one only WRITES an effect UI does not consume,
## and the thing being written is a CUE NAME — host vocabulary, not UI's.
## `"ui.cursor_move"` is played by `OpeningMenu.gd` for a menu selection with no
## battlefield in sight; `"invalid"` is played by `GambitBattle.gd` from seven of its
## own sites. `BattlefieldWiring._play_cursor_cue` records that ruling for #3 and it
## holds here unchanged. ADR-0234 / #848 / #590: a push-only half is a signal.
##
## 🔴 THE SIGNALS ARE NARROW ON PURPOSE, AND THAT IS THE HARD-WON PART.
## `TileCursor` had to grow `cursor_stepped` rather than reuse `cursor_moved`,
## because `cursor_moved` also fires from `move_to` and the cue would have started
## sounding on every programmatic reposition — "a behaviour change wearing a
## refactor's clothes". The same trap is live here: `DialogueBox.advanced` already
## existed and fires when the box is DISMISSED, and folding the page-flip onto it
## would blip on every dismissal. `page_turned` sits after `advance_page`'s
## `has_more_pages` guard, which is exactly where the cue sat.


## Wire one `DialogueBox` to its two cues. Safe to call repeatedly on a pooled box —
## `ScenarioPlayerScene` builds three, and `CombatUITestScene` wires one it already owns.
##
## 🔴 WHAT THE `is_connected` GUARD ACTUALLY BUYS, MEASURED. It does NOT stop the cue
## from doubling: Godot already refuses a second connection of the SAME named Callable,
## so deleting the guard leaves the sound correct and emits two
## `Signal ... is already connected` ERRORs instead. The guard suppresses those.
##
## The doubling risk is real but it lives elsewhere — if these adapters were ever
## rewritten as inline lambdas, each call would build a FRESH Callable, the engine
## would accept every one, and the blip would play once per wire. That is what
## `UICueInversionTest`'s idempotence arm discriminates; a seeded deletion of this
## guard alone leaves that arm GREEN, and the arm says so in its own comment. Keep the
## adapters as named statics.
static func wire_dialogue_box(box: Node) -> void:
	if box == null or not is_instance_valid(box):
		return
	if not box.page_turned.is_connected(_play_page_flip_cue):
		box.page_turned.connect(_play_page_flip_cue)
	if not box.glyph_revealed.is_connected(_play_typing_cue):
		box.glyph_revealed.connect(_play_typing_cue)


## Wire one mounted formation screen to its refusal cue.
##
## The null check is not defensive noise: `FormationDetailTransition.mount_over_map`
## RETURNS NULL when the camera has no `FocusPoint/Camera`, and `GPUArena` already
## guards its own panel mount for that exact reason (#1267).
static func wire_formation_screen(screen: Node) -> void:
	if screen == null or not is_instance_valid(screen):
		return
	if not screen.input_refused.is_connected(_play_invalid_cue):
		screen.input_refused.connect(_play_invalid_cue)


## "Flip Page", PSX system SFX 0x2d/45.
static func _play_page_flip_cue() -> void:
	SfxRouter.play_cue("ui.dialogue_page_flip")


## "Text Typing", PSX system SFX 0x73. `DialogueOverlay._ensure_typewriter` wires the
## same cue onto its OWN `TypewriterController`, and that duplication is the evidence
## the cue is host vocabulary — two unrelated dialogue paths name the same sound.
static func _play_typing_cue() -> void:
	SfxRouter.play_cue("ui.text_typing")


## The system-bank refusal buzz. `play_system`, not `play_cue`: it is a raw bank slug
## with no row in `SfxRouter._CUES`, which is how the three call sites already spelled it.
static func _play_invalid_cue() -> void:
	SfxRouter.play_system("invalid")
