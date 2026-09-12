extends Node3D
# test-kind: logic
# seeded-break: UnitInfoCluster.set_slide_fraction's lerp endpoints swapped (`_from.lerp(_to, frac)` -> `_to.lerp(_from, frac)`, the slide walks TOP->DOCKED) — the slide f0/docked-start, f2 mid-frame, and both settle-frame arms red (endpoints land swapped), composition/placement arms stay green; GREEN unbroken on the reverted tree

## UnitInfoCluster test (headful — builds the real vitals + nameplate widgets).
##
## The cluster is the composable "unit-info group" (FORMATION_SCREEN.md §15.5):
## the ONE vitals-panel + nameplate instance pair that both the formation roster
## (docked at the bottom) and the Status/detail screen (settled at the top) reuse,
## and that the ○-press transition SLIDES between those two layouts as a rigid group
## (§15.1/§15.6 — the band is NOT in this group). This guards:
##   1. composition — the cluster builds exactly the two pieces and forwards views;
##   2. placement — place_layout() lands each piece at a layout's display-px origin;
##   3. slide — set_slide_frame() walks the §15.1 keyframe curve from one layout to
##      the other, landing at top_y + offset (vertical), settling at the top layout.

const UnitInfoCluster = preload("res://src/ui3/UnitInfoCluster.gd")
const VitalsSlideAnimator = preload("res://src/ui3/detail/VitalsSlideAnimator.gd")
const FormationScene = preload("res://src/ui3/formation/FormationScene.gd")
const UIUnitNameplate = preload("res://src/ui3/UIUnitNameplate.gd")
const Character = ExMateriaCatalogue.Character
var _failed := false


func _ready() -> void:
	var c: Character = Character.create_default("Ramza", "4a", false)
	c.progression.brave = 70
	c.progression.faith = 70

	var cluster: UnitInfoCluster = UnitInfoCluster.new()
	add_child(cluster)                                   # in-tree before build add_childs pieces
	cluster.build(0.04, false)                           # ppu, fold_owns=false (no autoload dep)

	# --- 1. composition: the two sliding pieces exist, views forward -----------
	_expect(cluster.vitals_panel() != null, "vitals panel not built")
	_expect(cluster.nameplate() != null, "nameplate not built")
	cluster.set_unit_view(FormationScene.vitals_view_from_character(c))
	cluster.set_nameplate_view(UIUnitNameplate.view_from_character(c, 1))
	_expect(cluster.nameplate().get_child_count() >= 1, "nameplate empty after set_nameplate_view")

	# --- 2. placement: each layout lands the pieces at its display-px origins ---
	cluster.place_layout(UnitInfoCluster.LAYOUT_TOP)
	_expect(cluster.vitals_origin_px() == Vector2(13, 32),
		"top vitals origin = %s, want (13,32)" % cluster.vitals_origin_px())
	_expect(cluster.nameplate_origin_px() == Vector2(130, 32),
		"top nameplate origin = %s, want (130,32)" % cluster.nameplate_origin_px())

	cluster.place_layout(UnitInfoCluster.LAYOUT_DOCKED)
	_expect(cluster.vitals_origin_px() == Vector2(13, 177),
		"docked vitals origin = %s, want (13,177)" % cluster.vitals_origin_px())
	_expect(cluster.nameplate_origin_px() == Vector2(134, 176),
		"docked nameplate origin = %s, want (134,176)" % cluster.nameplate_origin_px())

	# The docked→top rise is the §15.1 144 px (vitals 177→32 = 145, within the 1 px
	# the two states were independently oracle-measured; nameplate 176→32 = 144 exact).
	_expect(abs((177 - 32) - VitalsSlideAnimator.SLIDE_CURVE[0]) <= 1,
		"docked→top vitals rise not ~144 px")

	# --- 3. slide: walk the keyframe curve DOCKED → TOP ------------------------
	cluster.begin_slide(UnitInfoCluster.LAYOUT_DOCKED, UnitInfoCluster.LAYOUT_TOP)

	# Frame 0 = the full offset (144) = docked start.
	cluster.set_slide_frame(0)
	_expect(cluster.nameplate_origin_px().is_equal_approx(Vector2(134, 176)),
		"slide f0 nameplate = %s, want docked (134,176)" % cluster.nameplate_origin_px())

	# A mid frame lands vertically at top_y + keyframe offset (the faithful §15.1 Y).
	# Frame 2 → offset 67 → vitals y = 32 + 67 = 99 (± the 1 px settle-measure slack).
	cluster.set_slide_frame(2)
	var mid_y := cluster.vitals_origin_px().y
	_expect(abs(mid_y - (32.0 + VitalsSlideAnimator.offset_at_frame(2))) <= 1.5,
		"slide f2 vitals y = %s, want ~%s (32+offset)" % [mid_y, 32 + VitalsSlideAnimator.offset_at_frame(2)])

	# The settle frame lands exactly on the TOP layout and reports settled.
	cluster.set_slide_frame(VitalsSlideAnimator.settle_frame())
	_expect(cluster.vitals_origin_px().is_equal_approx(Vector2(13, 32)),
		"slide settle vitals = %s, want top (13,32)" % cluster.vitals_origin_px())
	_expect(cluster.nameplate_origin_px().is_equal_approx(Vector2(130, 32)),
		"slide settle nameplate = %s, want top (130,32)" % cluster.nameplate_origin_px())
	_expect(cluster.slide_settled(), "slide not reported settled at settle_frame")

	if _failed:
		print("[FAIL] UnitInfoCluster test")
	else:
		print("[PASS] UnitInfoCluster: composes vitals+nameplate, places + slides (§15.1/§15.5)")
	get_tree().quit()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true
