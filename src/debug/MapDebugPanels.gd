class_name MapDebugPanels
extends RefCounted

## The map's two F3 panels, mounted from the HOST side (#555).
##
## `MapComposer` used to construct and register these itself, from
## `_setup_debug_panels()`. That is an ADR-0068 R1 violation the pass-4 misbooking was
## hiding: while `src/debug/`'s five panels were miscounted as `Battlefield`'s, the two
## `.new()` + two `register_panel()` lines were internal and invisible; booked correctly
## (ADR-0159 dec. 5) they are a cross-system reach, and they are the ENTIRE `DebugOverlay`
## autoload residue inside `Battlefield` (`autoload_reach.py`: `DebugOverlay 2 lines /
## 1 files`, that one file being `MapComposer.gd`). The production owner owned the
## tunables AND instantiated the view — R1 honoured for the data, broken for the wiring.
##
## So the registration is inverted: these panels are `src/debug/` files, Debug owns their
## classes, and Debug now owns their mount too. `MapComposer` names neither them nor
## `DebugOverlay`, and `Battlefield → Debug` falls 42 → 38.
##
## THE COMPOSER IS PASSED IN, NOT LOOKED UP. `SkirtDebugPanel`'s "Rebuild Mesh" button
## needs the live composer, and a panel that hunts for its owner would trade a scored
## `class_name` reach for a duck-typed one no instrument on this map can see (ADR-0164
## dec. 4). Every caller already holds the node, so it hands it over.
##
## WHY A HOST-SIDE MOUNT AND NOT AN AUTOLOAD. `MapRenderDebugPanel`'s rows pass no
## default — they read default+hint back from the `Tune` registry (ADR-0068 decision 12,
## the pure-VIEW contract), and `SkirtDebugPanel`'s "Debug Logging" row does the same for
## `skirt.land_debug`, whose home is `SkirtGeometryGenerator`'s static var (ADR-0140
## dec. 5). A row built before its owner's class has loaded renders a dead
## "(unregistered — owner not booted)" placeholder for the rest of the session. Every
## call site below already runs AFTER its map is composed, which is exactly when
## `MapComposer._ensure_render_setup()` used to fire — so the mount order is unchanged.
##
## Shaped after `AudioHostAdapter.register_audio_tab()` (extraction #2's host adapter),
## including its lesson: the panel class is NAMED at the mount, because
## `check_debug_panel_tunables.py` reads panel identity off `var X = ClassName.new()`
## paired with `register_panel(X` (ADR-0151's widened marker) and a loop variable
## satisfies neither half.


## BOTH PANELS CARRY THE `map` CATALOGUE ID, and one switch governs the pair. They are one
## entry on the catalogue page because they are one answer to "show me the map's look
## knobs"; stamping the id on each is what lets `DebugOverlay.set_panel_enabled("map",
## false)` find and unregister them, which it could not do while they carried none — that
## silent no-op is why the Skirts panel came up on `NavigatorMain` with `map` switched off.
##
## Mount the Skirts + Map Render panels, or rebind the existing ones.
##
## The overlay outlives the scene, so on a reload (Ctrl+R, click-to-rewind) an existing
## `SkirtDebugPanel` is re-pointed at the freshly-built composer rather than replaced —
## the repo's standard rebind idiom (see `ScenarioPlayerScene._register_debug_panels`),
## which preserves the panel's UI state. `MapComposer`'s own `_render_setup_done` was a
## PER-INSTANCE guard and could not see the surviving panel, so a reload used to stack a
## second copy; the guard belongs with the mount, not with one of its callers.
static func register_map_panels(map_composer: Node) -> void:
	var existing_skirt: SkirtDebugPanel = null
	var has_render_panel := false
	for cat in [DebugOverlay.Category.SKIRTS, DebugOverlay.Category.SHADERS]:
		for panel in DebugOverlay._panels.get(cat, []):
			if not is_instance_valid(panel):
				continue
			if existing_skirt == null and panel is SkirtDebugPanel:
				existing_skirt = panel
			elif panel is MapRenderDebugPanel:
				has_render_panel = true

	if existing_skirt != null:
		existing_skirt.rebind(map_composer)
	else:
		var skirt_panel := SkirtDebugPanel.new()
		skirt_panel.setup(map_composer)
		DebugOverlay.register_panel(skirt_panel, DebugOverlay.Category.SKIRTS, "map")

	# Stateless w.r.t. the composer (a pure `Tune` view), so nothing to rebind.
	if not has_render_panel:
		var render_panel := MapRenderDebugPanel.new()
		render_panel.setup()
		DebugOverlay.register_panel(render_panel, DebugOverlay.Category.SHADERS, "map")
