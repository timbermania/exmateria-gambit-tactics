class_name UniversalDebugPanels
extends RefCounted

## The F3 panels ANY host can mount — the ten [DebugPanelIds] `UNIVERSAL` entries.
##
## These were inside `CombatPanelCatalog.mount()`, reachable only from the two scenes that
## `extends CombatHost`, which is why a checked "Simulation" box did nothing on
## `NavigatorMain`: nothing there mounted it. Nothing about them is combat-specific —
## `SimulationDebugPanel.setup()`, `PerfDebugPanel.setup()`, `LoggingDebugPanel.setup()`
## and six others take no subject at all, and the two that take one never read it
## (`CursorDebugPanel.setup(_rig)`, `CameraFeelDebugPanel.setup(_camera)`, both pure `Tune`
## views since ADR-0068 dec. 12 that kept the old parameter). So the set moved to a file
## with no host in its name, and both lines — the combat catalogue and the scenario player
## — go through it.
##
## What a host still owns is everything with a real subject: its map, its roster, its units
## accessor. Those stay at the host, bound its own way, and are gated by the same ids at the
## seam ([DebugOverlay] `register_panel`).
##
## === Why this is a function and not a table ==================================
##
## 🔴 EVERY PANEL IS NAMED, ONE `var X = ClassName.new()` PAIRED WITH ONE
## `register_panel(X`. A `const PANELS := [preload(...)]` walked in a loop is tidier and
## **silently deletes every panel from `tools/check_debug_panel_tunables.py`**, which reads
## panel identity off exactly that pair (ADR-0151's widened marker); a loop variable
## satisfies neither half, so the guard goes green because it stopped looking. This warning
## is now written in four places — `CombatPanelCatalog`, `MapDebugPanels`,
## `AudioHostAdapter.register_panels`, and here — the third of them written after the
## mistake had already shipped once. The repetition below is the cost of staying legible to
## the instrument that polices it.
##
## === Idempotent, and meant to be called twice =================================
##
## `DebugOverlay.wants_panel()` is false for an id already mounted, so a host may call this
## at `_ready` and again later (combat hosts mount twice, once before deployment fills the
## roster; the scenario line re-enters on every `reload_current_scene`) without stacking a
## second copy. Turning an entry back on from the catalogue page re-enters through the
## host's remount hook and only the missing entries are built.


## Mount every universal panel the user has not switched off, appending each to `into` (the
## host's teardown list, when it keeps one). `host` is used only as the scene root the Font
## panel scans and as the node the camera hangs off; nothing here needs it to be a combat
## host. `opts` carries the one per-host difference that is not a subject:
##   `show_playback_rate` - the Simulation panel's between-turn rate row, which only a host
##                          that mounts a `TurnDirector` has anything to scale.
## Returns `into`.
static func mount(host: Node, into: Array = [], opts: Dictionary = {}) -> Array:
	if DebugOverlay.wants_panel("simulation"):
		var simulation_panel = SimulationDebugPanel.new()
		# BEFORE setup(), which is what builds the rows — a host that mounts a director has
		# a between-turn playback rate to scale, and one that does not must not show the row.
		simulation_panel.show_playback_rate = bool(opts.get("show_playback_rate", false))
		simulation_panel.setup()
		DebugOverlay.register_panel(simulation_panel, DebugOverlay.Category.SIMULATION, "simulation")
		into.append(simulation_panel)

	if DebugOverlay.wants_panel("logging"):
		var logging_panel = LoggingDebugPanel.new()
		logging_panel.setup()
		DebugOverlay.register_panel(logging_panel, DebugOverlay.Category.LOGGING, "logging")
		into.append(logging_panel)

	if DebugOverlay.wants_panel("perf"):
		var perf_panel = PerfDebugPanel.new()
		perf_panel.setup()
		DebugOverlay.register_panel(perf_panel, DebugOverlay.Category.PERFORMANCE, "perf")
		into.append(perf_panel)

	if DebugOverlay.wants_panel("tiles"):
		var tiles_panel = TilesDebugPanel.new()
		tiles_panel.setup()
		DebugOverlay.register_panel(tiles_panel, DebugOverlay.Category.TILES, "tiles")
		into.append(tiles_panel)

	if DebugOverlay.wants_panel("font"):
		var font_panel = FontDebugPanel.new()
		font_panel.setup(host)
		DebugOverlay.register_panel(font_panel, DebugOverlay.Category.FONT, "font")
		into.append(font_panel)

	if DebugOverlay.wants_panel("projectile"):
		var projectile_panel = ProjectileDebugPanel.new()
		projectile_panel.setup()
		DebugOverlay.register_panel(projectile_panel, DebugOverlay.Category.PROJECTILE, "projectile")
		into.append(projectile_panel)

	if DebugOverlay.wants_panel("feedback_hud"):
		var feedback_hud_panel = FeedbackHudDebugPanel.new()
		feedback_hud_panel.setup()
		DebugOverlay.register_panel(feedback_hud_panel, DebugOverlay.Category.UNIT, "feedback_hud")
		into.append(feedback_hud_panel)

	if DebugOverlay.wants_panel("cursor"):
		var cursor_panel = CursorDebugPanel.new()
		cursor_panel.setup(host.get("cursor_rig"))
		DebugOverlay.register_panel(cursor_panel, DebugOverlay.Category.CURSOR, "cursor")
		into.append(cursor_panel)

	if DebugOverlay.wants_panel("camera_feel"):
		var feel_panel = CameraFeelDebugPanel.new()
		feel_panel.setup(host.get_node_or_null("PlayerCamera"))
		DebugOverlay.register_panel(feel_panel, DebugOverlay.Category.CAMERA, "camera_feel")
		into.append(feel_panel)

	if DebugOverlay.wants_panel("ui_display"):
		var ui_display_panel = UIDisplayDebugPanel.new()
		ui_display_panel.setup()
		DebugOverlay.register_panel(ui_display_panel, DebugOverlay.Category.DISPLAY, "ui_display")
		into.append(ui_display_panel)

	return into
