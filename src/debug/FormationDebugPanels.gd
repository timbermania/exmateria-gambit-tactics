class_name FormationDebugPanels
extends RefCounted

## The formation screen's three F3 panels, mounted from the HOST side (#1267).
##
## `FormationScene` used to construct and register these itself, from its own
## `_setup_debug_panels()` — the same shape `MapComposer` carried before #555, and the
## same fix. Extraction #8 needs it gone for a harder reason than tidiness: `FormationScene`
## is moving into `addons/exmateria_ui/`, and a member that names `FormationDebugPanel`,
## `DetailScreenDebugPanel`, `VitalsLayoutDebugPanel` and the node path
## `/root/DebugOverlay` cannot ship. Those four reaches were the addon's whole scored debug
## residue.
##
## ADR-0304 dec. 2 states the rule the corpus was already obeying: an addon MAY ship
## diagnostics, it may NOT ship a panel that mounts on a host autoload. Measured across the
## nine shipped addons, `register_panel` is called **zero** times. So the panels stay
## `src/debug/` files, Debug owns their classes, and Debug now owns their mount too.
##
## === Why this is a function and not a table ==================================
##
## 🔴 EVERY PANEL IS NAMED, ONE `var X = ClassName.new()` PAIRED WITH ONE
## `register_panel(X`. A `const PANELS := [preload(...)]` walked in a loop is tidier and
## **silently deletes every panel from `tools/check_debug_panel_tunables.py`**, which reads
## panel identity off exactly that pair (ADR-0151's widened marker); a loop variable
## satisfies neither half, so the guard goes green because it stopped looking. This warning
## is carried by `CombatPanelCatalog`, `MapDebugPanels`, `UniversalDebugPanels` and
## `AudioHostAdapter.register_panels`; this is the fifth copy, and the repetition is the
## cost of staying legible to the instrument that polices it.
##
## === The rebind guard is not optional ========================================
##
## `DebugOverlay.register_panel` APPENDS (`DebugOverlay.gd:238`) — it does not de-duplicate.
## The formation screen mounts on SEVEN sites (see below) and is re-entered whenever the
## player leaves and returns, so a naive mount would stack three fresh panels every visit.
## `MapDebugPanels.register_map_panels` opens with the same scan for the same reason.
##
## An existing panel is re-pointed with `rebind()`, NOT by calling `setup()` again: `setup()`
## ends in `_build_ui()`, which `add_child`s a fresh root onto a panel that already has one.
## `SkirtDebugPanel.rebind` (#555) was the only such verb in the corpus; this pass added the
## matching two, each a bare re-point, because only the SEED values ever came off the subject.
##
## === Seven mount sites, and why a list would have been wrong ==================
##
## `FormationMapHost extends FormationScene`, so the deleted `_setup_debug_panels()` ran from
## `_ready()` on every path that puts either class in the tree. Enumerating them by hand gave
## FOUR; the test's discovery arm found SEVEN. `GPUArena`, `GambitLabScene` and
## `CombatUITestScene` mount the screen too, and wiring only the hand-picked four would have
## silently deleted the panels from those three. `DebugOverlay` has no discovery hook — no
## group, no `node_added` — so the guard against a missed EIGHTH is a test that rediscovers
## the sites from source, never a list maintained here.
##
## === The subject is passed in, not looked up =================================
##
## `FormationDebugPanel.setup()` takes a `Node`, so this file names no member type to mount
## it. The vitals window is read through the scene's own public accessors
## (`unit_info_cluster().vitals_panel()`), which is the same object the scene used to hand
## over as `_vitals_window`. A panel that hunted for its owner instead would trade a scored
## reach for a duck-typed one no instrument on this map can see (ADR-0164 dec. 4).


## Mount the formation panels for `scene`. Call it from the boot site, after the scene is in
## the tree and built — `_ready()` has to have run for the unit-info cluster to exist.
## Re-callable: the guard below re-points the two stateful panels instead of stacking them.
static func register_formation_panels(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return

	var existing_formation: FormationDebugPanel = null
	var existing_vitals: VitalsLayoutDebugPanel = null
	var has_detail := false
	for panel in DebugOverlay._panels.get(DebugOverlay.Category.DESIGNER, []):
		if not is_instance_valid(panel):
			continue
		if existing_formation == null and panel is FormationDebugPanel:
			existing_formation = panel
		if existing_vitals == null and panel is VitalsLayoutDebugPanel:
			existing_vitals = panel
		if panel is DetailScreenDebugPanel:
			has_detail = true

	# F3 → Designer tab: a VIEW onto the `formation.*` slugs the scene binds, grouped for live
	# body/shadow/box calibration (FORMATION_ELEMENT_PLACEMENT.md §7).
	if existing_formation != null:
		existing_formation.rebind(scene)
	else:
		var panel := FormationDebugPanel.new()
		panel.setup(scene)
		DebugOverlay.register_panel(panel, DebugOverlay.Category.DESIGNER)

	# F3 → Designer tab: live top-left-corner + size calibration for the unit-DETAIL /
	# Status screen's windows/apertures/tabs/bands. DetailScene owns the `detail.*` slugs
	# (it re-binds + rebuilds on each ○-press open); this VIEW seeds its rows from the class
	# static-var defaults, so it works whether or not a detail screen is currently open. The
	# roster is the persistent host, so the panel registers ONCE — and being a pure view with
	# no subject, there is nothing to re-point on a second visit.
	if not has_detail:
		var detail_panel := DetailScreenDebugPanel.new()
		detail_panel.setup()
		DebugOverlay.register_panel(detail_panel, DebugOverlay.Category.DESIGNER)

	# F3 → Designer tab: live layout-tuning surface for the bottom-left vitals window
	# (bar_pos / bar_full_width / num_divider_x / lv_pos / …), bound to the same `vitals.*`
	# slugs UIUnitInfoWindow owns. Dial the bars/values in by eye against the live scene,
	# then bake the number into the formation-specific override in _build_unit_info_cluster.
	# NOTE: these slugs are GLOBAL (shared with the battle HUD) — dial live here, but bake
	# formation-only values in code rather than committing the slug, or battle inherits them.
	var vitals_window = _vitals_window_of(scene)
	if vitals_window == null:
		return
	if existing_vitals != null:
		existing_vitals.rebind(vitals_window)
	else:
		var vitals_panel := VitalsLayoutDebugPanel.new()
		vitals_panel.setup(vitals_window)
		DebugOverlay.register_panel(vitals_panel, DebugOverlay.Category.DESIGNER)


## The scene's bottom-left vitals window, via its public accessors — the same object
## `FormationScene._vitals_window` held. Returns null before the cluster is built, which is
## the case the old `if _vitals_window != null` guard covered.
static func _vitals_window_of(scene: Node):
	if not scene.has_method("unit_info_cluster"):
		return null
	var cluster = scene.call("unit_info_cluster")
	if cluster == null or not is_instance_valid(cluster):
		return null
	if not cluster.has_method("vitals_panel"):
		return null
	return cluster.vitals_panel()
