class_name FeedbackHudManager
extends Node3D
## Over-unit feedback-HUD driver (ADR-0063, issues #89 / #90).
##
## The observation-only consumer that turns the combat loop's GPU-authoritative
## signals into over-unit billboards. It reads ONLY [CombatLoop] signals, the
## unit's snapshot status ([UnitStatusManager]) and its world position — never
## FFT's `BattleUnitData`, and it writes no battle state (ADR-0063 / ADR-0031).
##
## It owns two billboard families:
##   * [DamageNumber3D] — a transient number spawned on `hp_changed`, parented to
##     THIS manager (map-anchored) so the killing blow's number outlives its
##     target's death-frame.
##   * [StatusBubble3D] — one persistent bubble per unit, parented to the unit
##     (dies with it), showing its charge state or an active status icon.
##
## [method mount] is the one way in — add it under the [CombatLoop] and wire it in a
## single call, at each of the three sites that build a loop. That is the shipped
## ADR-0265 shape (`TurnBeat.mount`, `StopBadge.mount`, `TurnQueueHud.mount`,
## `CursorRig.bind`), and it is per-host by hand for the reason those are: the mounts
## happen at different lifecycle points and no one place knows all three.
##
## 🔴 IT WAS MOUNTED BY `GPUArena` AND BY NOBODY ELSE, which is why the two battle hosts
## showed no damage numbers, no heal numbers and no status bubbles at all. The fact was
## even written down — [TurnMarker3D]'s docstring says *"`FeedbackHudManager` is mounted
## by `GPUArena`"* — and recorded is not the same as acted on. A static named `mount`
## makes the three sites one greppable census, which is the property the per-scene panel
## lists did not have when they drifted to twenty-versus-one.

## #1271 — `DebugConfig` is a host autoload, and an addon cannot ship
## `project.godot` entries (ADR-0262 dec. 6), so the identifier is undefined in a
## stranger project. The flags were already `Tune` slugs; `UIDebug` reads them
## through the platform port. ADR-0308.
const UIDebug = preload("res://src/ui3/UIDebug.gd")

const DamageNumber3DClass = preload("res://src/ui3/elements/DamageNumber3D.gd")
const StatusBubble3DClass = preload("res://src/ui3/elements/StatusBubble3D.gd")

## Height above the unit's origin where a damage number pops (world units).
const NUMBER_RAISE := Vector3(0.0, 1.5, 0.0)

## RANGETILE status-icon cells (0..19) for the bubble. The exact ROM
## `Status_Bubble_Icon` table → our-status mapping is UNRECOVERED — the atlas
## cells are unlabeled (spec §8, open item #1/#6), so these are stable
## PLACEHOLDER indices that keep the wiring faithful (charge shows one cell, a
## status another) pending that reconciliation. Refine when the table lands.
const CHARGE_ICON := 19               # last cell — the AT/charge bubble group
const DEFAULT_STATUS_ICON := 0        # generic bubble for an unmapped status
const STATUS_ICON := {
	&"poison": 1,
	&"stopped": 2,
	&"petrified": 3,
	&"hasted": 4,
	&"slowed": 5,
}

## Statuses that must NOT raise a bubble (death is shown by the DYING animation /
## unit removal, not an over-unit icon).
const HIDDEN_STATUSES: Array[StringName] = [&"dead"]

var _loop = null                      # CombatLoop (untyped: avoid a load cycle)
var _charging: Dictionary = {}        # unit_index -> bool (from SPELL_CHARGING)
var _bubbles: Dictionary = {}         # unit_index -> StatusBubble3D


## The node name, so [method mount] can recognise a hud this loop already carries.
const NODE_NAME := "FeedbackHud"


## Build (or find) this loop's feedback hud and wire it. Returns the manager, or null if
## there is no loop to hang it on.
##
## PARENTED UNDER THE LOOP, deliberately: its numbers are map-anchored, so they ride the
## same Node3D space and the same ADR-0037 `combat_visuals` freeze — and they die with the
## loop. That last part is what makes the idempotence guard a property of the LOOP rather
## than of a host member: `NavigatorMain` frees `_combat_loop` per battle, so a host that
## remembered its hud would remember a freed one. Ask the loop.
static func mount(combat_loop) -> FeedbackHudManager:
	if combat_loop == null or not is_instance_valid(combat_loop):
		return null
	var existing := combat_loop.get_node_or_null(NodePath(NODE_NAME)) as FeedbackHudManager
	if existing != null:
		return existing
	var hud := FeedbackHudManager.new()
	hud.name = NODE_NAME
	combat_loop.add_child(hud)
	hud.setup(combat_loop)
	return hud


## Wire to the combat loop's observation signals. Idempotent.
func setup(combat_loop) -> void:
	_loop = combat_loop
	if not _loop.hp_changed.is_connected(_on_hp_changed):
		_loop.hp_changed.connect(_on_hp_changed)
	if _loop.has_signal("state_changed") and not _loop.state_changed.is_connected(_on_state_changed):
		_loop.state_changed.connect(_on_state_changed)


func _on_hp_changed(unit_index: int, _prev_hp: int, new_hp: int, delta: int) -> void:
	# hp_changed only fires on a real change, so delta != 0 here; guard anyway.
	if delta == 0:
		return
	# Diagnostic feature gate (F3 Feedback HUD panel): skip the number entirely when off.
	if not UIDebug.feedback_numbers():
		return
	var unit = _unit(unit_index)
	if unit == null:
		return
	var number = DamageNumber3DClass.new()
	add_child(number)  # map-anchored under the manager, NOT the unit
	number.global_position = unit.global_position + NUMBER_RAISE
	var kind: int = DamageNumber3DClass.Kind.HEAL if delta > 0 else DamageNumber3DClass.Kind.DAMAGE
	number.setup(delta, kind, new_hp <= 0)


func _on_state_changed(unit_index: int, _prev_state: int, new_state: int) -> void:
	_charging[unit_index] = new_state == GPUConstants.LOGICAL_ACTIVITY_SPELL_CHARGING


func _process(_delta: float) -> void:
	if _loop == null:
		return
	for i in range(_loop.units.size()):
		_refresh_bubble(i)


func _refresh_bubble(i: int) -> void:
	var unit = _unit(i)
	if unit == null:
		_bubbles.erase(i)  # the bubble was a child of the freed unit
		return
	var icon := _desired_icon(unit, i)
	var bubble = _bubbles.get(i)
	if icon < 0:
		if bubble != null and is_instance_valid(bubble):
			bubble.clear()
		return
	if bubble == null or not is_instance_valid(bubble):
		bubble = StatusBubble3DClass.new()
		unit.add_child(bubble)  # unit-child: dies with the unit
		_bubbles[i] = bubble
	bubble.set_icon(icon)


## Pick the icon cell for a unit: charge takes the slot while casting, else the
## first non-hidden active status; -1 = no bubble. Observation-only reads.
func _desired_icon(unit: Node, i: int) -> int:
	# Diagnostic feature gate (F3 Feedback HUD panel): the charge "speech bubble" only.
	if _charging.get(i, false) and UIDebug.feedback_charge_bubble():
		return CHARGE_ICON
	var status_mgr := unit.get_node_or_null("UnitStatusManager")
	if status_mgr != null:
		for s in status_mgr.get_all_statuses():
			if s in HIDDEN_STATUSES:
				continue
			return STATUS_ICON.get(s, DEFAULT_STATUS_ICON)
	return -1


func _unit(i: int):
	if _loop == null or i < 0 or i >= _loop.units.size():
		return null
	var u = _loop.units[i]
	return u if is_instance_valid(u) else null
