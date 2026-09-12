class_name UnitInfoCluster
extends UI3Element
## The composable "unit-info group" (FORMATION_SCREEN.md §15.5) — a registered ELEMENT
## root (ADR-0088 Amendment 5 §4) grouping a vitals panel + nameplate, owning the slide
## between their two layouts + an editable `<id>.origin` group-nudge.
##
## There are TWO independent instances, one per screen (`formation.unit_cluster` docked at
## the roster bottom, `detail.unit_cluster` settled at the Status-screen top) — NOT one
## shared pair that both reuse (the earlier docstring's claim was never true: FormationScene
## builds one, DetailScene another, and ○-press HIDES the formation one while the detail one
## slides up). FFT decodes the transition as the SAME sprites sliding, not two screens
## crossfading (§15.6): DOCKED (LAYOUT_DOCKED) rises 144 px to the top (LAYOUT_TOP) via the
## §15.1 keyframe table (see [VitalsSlideAnimator]). Each instance owns its own pair so the
## slide moves real sub-elements — independent reusable pieces arranged by a per-screen group.
##
## NOT in this group: the dark subtractive band (§15.6 — it is CUT at the formation
## bottom and REDRAWN at the top, never slid). Each screen keeps its own UIVitalsBand.
##
## Placement model: the vitals panel is a self-positioning widget (its `position` is
## its top-left). The nameplate builds its glyph tree at a CANONICAL origin, so we
## place it by TRANSLATING the node — cheap enough to drive every slide frame without
## a rebuild. `place_at()` snaps to a layout; `begin_slide()`/`set_slide_frame()` walk
## the keyframe curve between two layouts (lerping so both endpoints stay pixel-exact
## and the transient horizontal drift — 4 px on the nameplate — is unobservable).

# 🔴 NO `DepthMode` ALIAS HERE, AND THAT IS DELIBERATE. This script
# EXTENDS `UI3Element.gd`, which declares one, and GDScript refuses a
# member that already exists in the parent — a parse error that takes this
# whole file out. An alias is a per-CLASS declaration, not a per-file one;
# the inherited constant is what the use sites below read (ADR-0212 dec. 1).

const UIUnitInfoWindow = preload("res://src/ui3/UIUnitInfoWindow.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")

## The menu layouts this pair lives in (display 256×240 px, each piece's top-left).
## DOCKED = formation roster (§14.6/§14.7 bottom); TOP = Status/detail screen (§15.14).
const LAYOUT_DOCKED := {"vitals": Vector2(13, 177), "nameplate": Vector2(134, 176)}
const LAYOUT_TOP := {"vitals": Vector2(13, 32), "nameplate": Vector2(130, 32)}

## Panel widths, needed only to place the OFF layout fully off-screen. MEASURED from the built
## panels (the union AABB of what each actually draws, / PIXELS_PER_UNIT), not authored: the vitals
## panel read 110 here for as long as the OFF layout existed and is really **124**, so parking it at
## -110 left 14 px of readout stuck to the left edge at rest. `FormationMapHostTest` now measures
## both against a live build, because the guard that was here compared the constant against a
## layout DERIVED from the same constant and so could never fail (ADR-0137 Amendment 2).
const VITALS_W := 124.0
const NAMEPLATE_W := 114.0

## OFF — the third layout (ADR-0137), the map host's hover start/end. Each piece parked just past
## the edge it enters from: the vitals panel's RIGHT edge on display x=0, the nameplate's LEFT edge
## on x=256. Same Y as DOCKED, because the hover is a horizontal entrance from opposite edges, not
## the DOCKED→TOP rise. Derived from the docked layout + the panel widths so it stays "just off"
## if either panel is ever re-measured.
const LAYOUT_OFF := {
	"vitals": Vector2(-VITALS_W, 177),
	"nameplate": Vector2(256, 176),
}

## Near depth rung (ADR-0077): the opaque, depth-writing pair occludes the folded
## subtractive band beneath it (band shows in the readout gaps). Same rung both screens.
const RP_VITALS_PANEL := 12

var _ppu := 0.04
var _fold := false
var _vitals_rung := RP_VITALS_PANEL
var _vitals: UIUnitInfoWindow
var _nameplate: UIUnitNameplate
var _unit_view: Dictionary = {}
var _nameplate_view: Dictionary = {}

var _vitals_origin: Vector2 = LAYOUT_TOP["vitals"]
var _nameplate_origin: Vector2 = LAYOUT_TOP["nameplate"]

# Slide state
var _from: Dictionary = {}
var _to: Dictionary = {}
var _last_offset: int = 0


## Build the two pieces (vitals panel + nameplate) as children, configured the shared
## menu way (vitals via UIUnitInfoWindow.apply_menu_layout, band off; nameplate via
## UIUnitNameplate.apply_menu_layout at the canonical origin). `fold_owns` joins the
## pair to the ADR-0077 near rung so it occludes a folded band. Snaps to LAYOUT_TOP.
## `vitals_rung` sets the vitals panel's ADR-0077 near rung — 12 (RP_VITALS_PANEL,
## the Status screen) by default; the formation roster passes its RP_HEADER_LABEL (11)
## so its depth ordering stays byte-identical to the pre-cluster build.
## `rung_offset` lifts BOTH pieces on the ADR-0077 real-Z ladder by that many rungs — 0 on
## the formation roster (this pair IS the near content), a positive lift when the Status/detail
## screen overlays the roster so the whole pair (and the nameplate's folded orb bullet) sorts
## nearer than the formation grid AND nearer than the overlay's own subtractive stripe.
func build(ppu: float, fold_owns: bool, vitals_rung: int = RP_VITALS_PANEL, rung_offset: int = 0) -> void:
	_ppu = ppu
	_fold = fold_owns
	_vitals_rung = vitals_rung + rung_offset

	# The two pieces are ELEMENT sub-elements of this cluster (ADR-0088 Amendment 5 §4): the
	# vitals panel via the UIComponent base-swap, the nameplate via its bespoke UI3Element
	# re-base. Their rect defaults == the settled LAYOUT_TOP origins (own-origin knobs); the
	# cluster's group placement (place_layout / the slide) is authoritative for the live
	# position, so this stays a strict visual no-op. HP/MP/CT bars, portrait, and glyphs
	# inside each piece remain PAYLOAD.
	var eid := id()
	_vitals = UIUnitInfoWindow.new(_sub_spec(eid + ".vitals", LAYOUT_TOP["vitals"], Vector2(110, 46)))
	_vitals.name = "VitalsPanel"
	_vitals.pixels_per_unit = ppu
	_vitals.show_band = false                       # the screen's UIVitalsBand draws the backdrop
	UIUnitInfoWindow.apply_menu_layout(_vitals)     # the ONE corrected menu placement (bars/Lv/Exp)
	add_child(_vitals)
	if not _unit_view.is_empty():
		_vitals.set_unit_view(_unit_view)

	_nameplate = UIUnitNameplate.new(_sub_spec(eid + ".nameplate", LAYOUT_TOP["nameplate"], Vector2(114, 54)))
	_nameplate.name = "Nameplate"
	_nameplate.pixels_per_unit = ppu
	_nameplate.rung_offset = rung_offset            # thread the overlay lift into the nameplate's rungs
	# Build the glyph tree at a ZERO origin (relative offsets): the nameplate NODE's position
	# then places it, so its element rect is honest and its origin knob is a real write-back
	# (equivalent transform to the old _NP_BUILD_ORIGIN bake + node translate — same pixels).
	UIUnitNameplate.apply_menu_layout(_nameplate, Vector2.ZERO)
	add_child(_nameplate)
	if not _nameplate_view.is_empty():
		_nameplate.set_view(_nameplate_view)

	place_layout(LAYOUT_TOP)


## Build one sub-element spec (ELEMENT role, own-origin literal rect, no chrome/clip/beat) —
## the cluster's group placement drives the live position, so the rect default is just the
## settled LAYOUT_TOP anchor. Empty id (a PAYLOAD cluster with no id) leaves the piece PAYLOAD.
func _sub_spec(sub_id: String, origin: Vector2, size: Vector2) -> Dictionary:
	if id().is_empty():
		return {}   # un-identified cluster: the pieces ride the default PAYLOAD (no rows)
	return {
		"id": sub_id,
		"rect": Rect2(origin, size),
		"transition": UI3Element.Transition.NONE,
		"frame": UI3Element.Frame.NONE,
		"clip": UI3Element.Clip.UNCLIPPED,
	}


## Bind the vitals view (portrait + HP/MP/CT bars + Lv/Exp), built the roster way
## (FormationScene.vitals_view_from_character). Safe before build().
func set_unit_view(view: Dictionary) -> void:
	_unit_view = view
	if _vitals != null and is_instance_valid(_vitals):
		_vitals.set_unit_view(view)


## Bind the nameplate view ({number,name,job,brave,faith,zodiac}). Safe before build().
func set_nameplate_view(view: Dictionary) -> void:
	_nameplate_view = view
	if _nameplate != null and is_instance_valid(_nameplate):
		_nameplate.set_view(view)


func vitals_panel() -> UIUnitInfoWindow:
	return _vitals


## §15.26 equip-picker preview: HP/MP numerators → "-" on the vitals window (bars/"/"/999 stay). Delegated.
func set_vitals_preview(on: bool) -> void:
	if _vitals != null and is_instance_valid(_vitals):
		_vitals.set_hpmp_preview(on)


## §15.26 numeric preview (EQUIP_STAT_PREVIEW.md §6): fill the HP/MP numerators with their signed
## armor/accessory delta ("+5"/"-5" coloured, or a dash for 0). Delegated to the vitals window.
func set_vitals_preview_delta(hp: int, mp: int) -> void:
	if _vitals != null and is_instance_valid(_vitals):
		_vitals.set_hpmp_delta(hp, mp)


func nameplate() -> UIUnitNameplate:
	return _nameplate


## The display-px top-left the vitals panel is currently placed at.
func vitals_origin_px() -> Vector2:
	return _vitals_origin


## The display-px top-left the nameplate is currently placed at.
func nameplate_origin_px() -> Vector2:
	return _nameplate_origin


## Snap the pair to a layout ({"vitals": Vector2, "nameplate": Vector2} display px). Named
## place_layout (not place_at) since the UI3Element base-swap — place_at(slug) is the element
## re-home verb.
func place_layout(layout: Dictionary) -> void:
	_place(layout["vitals"], layout["nameplate"])


## Arm a slide from `from` layout to `to` layout and snap to its first (docked) frame.
func begin_slide(from: Dictionary, to: Dictionary) -> void:
	arm_slide(from, to)
	set_slide_frame(0)


## Arm the endpoints WITHOUT placing the pair or touching `_last_offset`. For a caller driving its
## own cadence through [method set_slide_fraction] (ADR-0137's hover): `begin_slide` would walk the
## §15.1 ROM keyframe table to snap frame 0, which is the wrong curve for anyone else's motion and
## leaves `slide_settled()` reporting on a slide that is not running.
func arm_slide(from: Dictionary, to: Dictionary) -> void:
	_from = from
	_to = to


## Position the pair at slide animation frame `n` — the §15.1 keyframe offset walked
## from `_from` (frame 0, offset 144) to `_to` (settle, offset 0). Interpolated so both
## endpoints land pixel-exact on their layout and the vertical rise tracks top_y+offset.
func set_slide_frame(n: int) -> void:
	if _from.is_empty() or _to.is_empty():
		return
	_last_offset = VitalsSlideAnimator.offset_at_frame(n)
	var span := float(VitalsSlideAnimator.SLIDE_CURVE[0])   # 144 — the docked start offset
	set_slide_fraction(1.0 - (float(_last_offset) / span))  # 0 at docked, 1 at the top


## Position the pair at completion FRACTION `frac` between the armed layouts — 0 at `_from`, 1 at
## `_to`. Split out of [method set_slide_frame] so a caller can supply its OWN cadence instead of
## the §15.1 ROM keyframe table.
##
## `frac` above 1 is legal and meaningful: an OVERSHOOTING cadence (ADR-0137's hover — "opens a
## little too much, then settles") runs past the destination and comes back, and `lerp` extrapolates
## cleanly. `_last_offset` is left alone here, so `slide_settled()` stays the ROM slide's own query.
func set_slide_fraction(frac: float) -> void:
	if _from.is_empty() or _to.is_empty():
		return
	var vitals_o: Vector2 = (_from["vitals"] as Vector2).lerp(_to["vitals"], frac)
	var nameplate_o: Vector2 = (_from["nameplate"] as Vector2).lerp(_to["nameplate"], frac)
	_place(vitals_o, nameplate_o)


## True once the slide has reached the settled (offset 0) frame.
func slide_settled() -> bool:
	return _last_offset == 0


# -----------------------------------------------------------------------------
func _place(vitals_o: Vector2, nameplate_o: Vector2) -> void:
	_vitals_origin = vitals_o
	_nameplate_origin = nameplate_o
	if _vitals != null and is_instance_valid(_vitals):
		var z := DepthMode.rung_z(_vitals_rung) if _fold else 0.0
		_vitals.position = _px_to_world(vitals_o) + Vector3(0.0, 0.0, z)
	if _nameplate != null and is_instance_valid(_nameplate):
		# The glyph tree is baked at a ZERO origin, so the node position IS the top-left
		# (the children carry their own rung_z, so no extra Z here).
		_nameplate.position = _px_to_world(nameplate_o)


func _px_to_world(px: Vector2) -> Vector3:
	return Vector3(px.x * _ppu, -px.y * _ppu, 0.0)
