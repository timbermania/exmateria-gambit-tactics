class_name CombatPanelCatalog
extends RefCounted

## The one mount for a COMBAT HOST's F3 panels — `GPUArena` and `GambitBattle`, the two
## production scenes that `extends CombatHost`.
##
## It exists because "which panels does this scene get" was answered per scene, by hand, and
## the two answers drifted to twenty versus one. `GambitBattle` printed "F3 - debug overlay"
## in its boot banner while registering nothing, so the `pacing.*` knobs were unreachable in
## the one mode that needs them (#1050 fixed that by adding a single panel; this replaces the
## per-scene list that made it possible). Both hosts own the same subjects — a
## `ProceduralMap`, a `PlayerCamera`, a `CursorRig`, both team arrays — so there was never a
## second answer to give, only a second list to forget to update.
##
## === Why this is a function and not a table ==================================
##
## 🔴 EVERY PANEL IS NAMED, ONE `var X = ClassName.new()` PAIRED WITH ONE
## `register_panel(X`. A `const PANELS := [preload(...)]` walked in a loop is tidier and
## **silently deletes every panel from `tools/check_debug_panel_tunables.py`**, which reads
## panel identity off exactly that pair (ADR-0151's widened marker); a loop variable
## satisfies neither half, so the guard goes green because it stopped looking. This is
## recorded twice already — `AudioHostAdapter.register_panels` and
## `MapDebugPanels.register_map_panels` both carry the same warning, the second of them
## written after the mistake had already shipped once. The repetition below is the cost of
## staying legible to the instrument that polices it.
##
## === What this file still owns ===============================================
##
## The four entries that need a subject only a combat host has — a `MapComposer`, a roster,
## a units accessor. The ten that need nothing moved to [UniversalDebugPanels], and the id
## STRINGS moved to [DebugPanelIds], because a combat-only file was the wrong home for a
## switchboard the whole game passes through: `NavigatorMain` never calls this mount, so
## every switch was a no-op there. The gate itself now lives at the seam
## ([DebugOverlay] `register_panel`); this file asks first only to avoid building what the
## seam would free.
##
## === What gates a mount ======================================================
##
## ONLY the ability to construct the panel — never "does it apply here". Four of the nine
## panels that take a subject never read it (`CursorDebugPanel.setup(_rig)`,
## `CameraFeelDebugPanel.setup(_camera)`, `UnitShaderDebugPanel.setup(_scene_root, _get)`,
## `ScenarioDebugPanel.setup(map = null)`), while `TilesDebugPanel.setup()` takes nothing and
## is a pure view onto the battlefield addon's `tile.*`. So the signature is evidence of
## nothing, and a gate keyed on it is a false-negative and false-positive machine at once.
## Applicability is derived per SLUG, after the fact, by [PanelApplicability] — and it is
## shown, never used to hide anything. The only reason a panel below is skipped is that
## mounting it would build a broken view (`ProgressionDebugPanel` over an empty roster).
##
## === Idempotent, and meant to be called twice =================================
##
## `GambitBattle` mounts at `_ready`, which is BEFORE deployment fills the team arrays, so
## the roster panel cannot be built yet — and waiting until the battle starts would put the
## pacing knobs out of reach for the whole of deployment, which is the defect this file is
## named after. So `mount()` skips what it cannot build, and the host calls it again once the
## battle starts; already-registered ids are left alone. The same property makes it safe on a
## reload, where the overlay (an autoload) outlives the scene.


## The ids this mount is responsible for, in mount order. The STRINGS live in
## [DebugPanelIds] now, with every other screen's, because a combat-only file was the wrong
## home for the game's switchboard — see that file's header for what moving them fixed.
## What stays here is the ORDER these four subject-bound entries are built in, which is a
## property of this mount and of nothing else.
const SUBJECT_IDS := ["map", "scenario", "progression", "unit_shader"]

## Mount every catalogue panel this host can build and the user has not switched off,
## appending each to `into` (the host's teardown list). Returns `into`.
##
## `host` supplies the subjects by the names `CombatHost` already gives them — `map`,
## `cursor_rig`, `team0_units`, `team1_units`, `units`, and a `PlayerCamera` child. `opts`
## carries the two per-host differences that are not subjects:
##   `show_playback_rate` - the Simulation panel's between-turn rate row, which only a host
##                          that mounts a `TurnDirector` has anything to scale.
static func mount(host: Node, into: Array = [], opts: Dictionary = {}) -> Array:
	# Re-entry point for the catalogue page's checkboxes: turning an entry back on re-runs
	# this same mount against the same host, and idempotence does the rest.
	DebugOverlay.set_catalog_remount(func() -> void: mount(host, into, opts))

	# The ten entries any host can build — Simulation, Logging, Performance, Tiles, Font,
	# Projectile, Feedback HUD, Cursor, Camera Feel, PSX Display. They lived in this file
	# until the id space moved to the seam, and their being here was the reason a checked
	# "Simulation" box did nothing on a screen that is not a combat host: nothing outside
	# these two scenes could reach the mount. Nothing in the set is combat-specific.
	UniversalDebugPanels.mount(host, into, opts)

	# The map's Skirts + Map Render panels. Mounted host-side (#555, ADR-0068 R1: the
	# production owner must not instantiate its own view), and the only entry whose panels
	# this function does not own — `register_map_panels` holds its own rebind guard and its
	# panels are deliberately NOT appended to `into`, exactly as `GPUArena` had it.
	if _wanted("map", host) and host.get("map") != null:
		MapDebugPanels.register_map_panels(host.get("map"))

	if _wanted("scenario", host):
		var scenario_panel = ScenarioDebugPanel.new()
		scenario_panel.setup(host.get("map"))
		DebugOverlay.register_panel(scenario_panel, DebugOverlay.Category.SCENARIO, "scenario")
		into.append(scenario_panel)

	# The one entry with a REQUIRED live subject: its rows are per-unit, so building it over
	# an empty roster produces a permanently empty panel rather than a broken one — which is
	# worse, because it looks mounted. `GambitBattle` reaches this with both arrays empty at
	# `_ready` and satisfies it on the second call, once deployment has committed.
	if _wanted("progression", host) and not _roster_of(host).is_empty():
		var progression_panel = ProgressionDebugPanel.new()
		progression_panel.setup(host.get("team0_units"), host.get("team1_units"))
		DebugOverlay.register_panel(progression_panel, DebugOverlay.Category.ROSTER, "progression")
		into.append(progression_panel)

	if _wanted("unit_shader", host):
		var unit_shader_panel = UnitShaderDebugPanel.new()
		unit_shader_panel.setup(host, func(): return host.get("units"))
		DebugOverlay.register_panel(unit_shader_panel, DebugOverlay.Category.SHADERS, "unit_shader")
		into.append(unit_shader_panel)

	# The whole F3 AUDIO tab — SPU tuning, whole-game volume, the live bus mixer. Outside the
	# catalogue's id space on purpose: the adapter owns these panels' lifetime and holds its
	# own idempotence guard (ADR-0153 dec. 3, the one place a sound declaration meets a host
	# symbol), which is also why they are not appended to `into`.
	AudioHostAdapter.register_audio_tab()

	return into


## Should `id` be built on this call — i.e. the user has not switched it off AND it is not
## already mounted. The second half is what makes `mount()` re-callable: a host that mounts
## at `_ready` and again at battle start must not stack a second copy of everything.
##
## The switched-off half is now also enforced at the seam ([DebugOverlay] `register_panel`
## refuses a disabled id), which is what covers the 39 hand-written call sites this function
## was never on. Asking here as well is the cheap path: it skips CONSTRUCTING a panel the
## seam would only free.
static func _wanted(id: String, _host: Node) -> bool:
	return DebugOverlay.wants_panel(id)


## Both teams as one array — the roster `ProgressionDebugPanel` builds its rows from.
static func _roster_of(host: Node) -> Array:
	var t0: Variant = host.get("team0_units")
	var t1: Variant = host.get("team1_units")
	var out: Array = []
	if t0 is Array:
		out.append_array(t0)
	if t1 is Array:
		out.append_array(t1)
	return out
