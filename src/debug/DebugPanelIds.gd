class_name DebugPanelIds
extends RefCounted

## The id space of the F3 panel catalogue — every switchable debug panel in the game, in
## one table, for every scene.
##
## It was `CombatPanelCatalog.IDS`, a const inside the mount function for the two scenes
## that `extends CombatHost`, and that location was the bug. `NavigatorMain extends
## ScenarioPlayerScene`, never calls that mount, and hand-registered its twelve-odd panels
## with no id at all — so its Skirts panel came up with `map` switched OFF (the switch had
## nothing to match) while its Simulation panel never came up with `simulation` switched ON
## (nothing there mounts it). Repo-wide, 39 `register_panel(` call sites passed an id from
## exactly one file.
##
## So the id moved to the seam every panel already passes through. [DebugOverlay]
## `register_panel` REFUSES a disabled id (see its 🔴 note), which is what makes a new
## panel structurally unable to escape the switchboard: the only way to mount without an
## id is to pass none, and that is now a deliberate, listed choice (see BESPOKE below).
##
## 🔴 THESE STRINGS ARE FROZEN. The id is the persisted key in `user_settings.json ->
## debug_window.disabled_panels`, so renaming one silently re-enables a panel somebody
## turned off — and the set persists the DISABLED ids precisely so an id ADDED here
## defaults ON rather than being invisible until someone finds the checkbox. Adding is
## free; renaming is a migration.
##
## === What is deliberately NOT in here ========================================
##
## Two kinds of panel carry no id, and the catalogue page LISTS both under "Mounted
## outside the catalogue" rather than hiding them — the complaint that produced that page
## was a panel that was not there:
##
##   1. The F3 AUDIO tab (`AudioHostAdapter.register_audio_tab`) — outside the id space on
##      purpose, ADR-0153 dec. 3, because the adapter owns those panels' lifetime.
##   2. A scene's OWN tool surface — `EffectViewerPanel` on the effect viewer,
##      `TrapViewerPanel` on the trap viewer, `WorldMapDebugPanel` (ADR-0051: the scene's
##      configuration IS the panel), `FormationScene`'s three designer panels,
##      `GambitDeployDebugPanel` (a view onto a question only a host with a deployment can
##      ask). Switching one of these off leaves a scene that exists to host it with
##      nothing in it, which is not a view preference — it is breaking the scene.
##
## Applicability — "is this panel a view onto anything that is live HERE" — is a separate
## question, DERIVED per slug by [PanelApplicability] and SHOWN, never used to hide
## anything (ADR-0263). This table is only about what the user chose to look at.


## Ids any host can mount: their panels take no subject, or take one they never read.
## [UniversalDebugPanels] mounts exactly this set, and both the combat catalogue and the
## scenario-player line go through it.
const UNIVERSAL := [
	"simulation", "logging", "perf", "tiles", "font", "projectile", "feedback_hud",
	"cursor", "camera_feel", "ui_display",
]

## Ids whose panel needs a subject the host supplies — a `MapComposer`, a roster, a units
## accessor. Each host mounts these itself, with its own binding; the id is shared because
## the PANEL is the same one, so one switch governs it on every screen.
const SUBJECT_BOUND := [
	"map", "scenario", "progression", "unit_shader", "state",
]

## The scenario player's event-debugging panels ([ScenarioPlayerScene]), inherited by
## [NavigatorMain]. `scenario_path` is the one the Navigator overrides away — it is the
## scenario player's rival launcher, and the override is a scene decision, not a switch.
const SCENARIO := [
	"scenario_path", "scenario_vm", "scenario_dialogue_box", "scenario_view",
	"scenario_weather", "scenario_cinematic", "scenario_unit_align",
	"scenario_sprite_offset",
]

## [NavigatorMain]'s own four: the story-walk launcher and the roster/timeline readouts.
const NAVIGATOR := [
	"navigator", "roster_universe", "story_timeline", "battle_binding",
]

## The whole id space, in catalogue-page order.
const IDS := [
	# UNIVERSAL
	"simulation", "logging", "perf", "tiles", "font", "projectile", "feedback_hud",
	"cursor", "camera_feel", "ui_display",
	# SUBJECT_BOUND
	"map", "scenario", "progression", "unit_shader", "state",
	# SCENARIO
	"scenario_path", "scenario_vm", "scenario_dialogue_box", "scenario_view",
	"scenario_weather", "scenario_cinematic", "scenario_unit_align",
	"scenario_sprite_offset",
	# NAVIGATOR
	"navigator", "roster_universe", "story_timeline", "battle_binding",
]

## Display names for the catalogue page. Needed for the entries that are NOT mounted on
## the current screen and so have no live panel to read a `panel_title` off — which, on
## any one screen, is most of them.
const TITLES := {
	"simulation": "Simulation", "logging": "Logging", "perf": "Performance",
	"tiles": "Tiles", "font": "Font", "projectile": "Projectile",
	"feedback_hud": "Feedback HUD", "cursor": "Cursor", "camera_feel": "Camera Feel",
	"ui_display": "PSX Display",
	"map": "Skirts + Map Render", "scenario": "Scenario", "progression": "Progression",
	"unit_shader": "Unit Shader", "state": "Engine State",
	"scenario_path": "Scenario Path (launcher)", "scenario_vm": "Scenario VM",
	"scenario_dialogue_box": "Scenario Dialogue Box", "scenario_view": "Scenario View",
	"scenario_weather": "Scenario Weather",
	"scenario_cinematic": "Scenario Cinematic (EVTCHR)",
	"scenario_unit_align": "Unit Alignment",
	"scenario_sprite_offset": "Unit Sprite Offset (per-unit)",
	"navigator": "Navigator", "roster_universe": "Roster Universe",
	"story_timeline": "Story Timeline", "battle_binding": "Battle Binding",
}

## The page's section headings, in order, each with the ids it holds — so the catalogue
## reads as four short lists instead of one 27-row wall.
const SECTIONS := [
	{"title": "Any screen", "ids": UNIVERSAL},
	{"title": "Needs a subject from the host", "ids": SUBJECT_BOUND},
	{"title": "Scenario player", "ids": SCENARIO},
	{"title": "Navigator (story walk)", "ids": NAVIGATOR},
]


## Display name for `id`, falling back to the id itself so a table gap is visible rather
## than blank.
static func title_of(id: String) -> String:
	return String(TITLES.get(id, id))
