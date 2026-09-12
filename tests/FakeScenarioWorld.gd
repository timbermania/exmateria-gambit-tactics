class_name FakeScenarioWorld
extends ScenarioWorld
## Test double for [ScenarioWorld]: records every verb call instead of touching a
## live scene, so an [ScenarioApply] `apply_X(intent, world)` can be exercised with
## no VM boot (ADR-0058). One fake is reused across every apply test.
##
## It extends [ScenarioWorld] so it type-checks wherever a real world is expected;
## it overrides each verb to append a `{ "verb": name, ... }` record to `calls`
## rather than call `super`. Assertions read that record — they check WHAT verb the
## world received and with WHAT values (the external behavior), never a private VM
## field. Per the CLAUDE.md base-class member-drop trap, both classes carry plain
## fields, not getter-only forwarding properties.
##
## As the verb surface grows family-by-family, mirror each new [ScenarioWorld] verb
## here with a recording override; unrecorded verbs would silently fall through to
## the base (which dereferences a null `_vm` in a test) and surface as a crash.

## Addon classes are not bare globals — spell the schema type once (ADR-0211 dec. 4),
## the same way [ScenarioWorld] spells `ClockOwner`.
const TerrainCell = ExMateriaSchema.TerrainCell

## Ordered log of verb invocations. Each entry is a Dictionary with a `"verb"` key
## naming the verb plus one key per argument. Assertions scan/filter this.
var calls: Array = []

## uids the test declares NOT spawned — `has_unit` returns false for these so an
## apply's "no spawned unit; skip" guard can be exercised. Default: all present.
var missing_units: Dictionary = {}

## When true, `place_unit_on_tile` reports failure (no map / no tile) so an apply's
## place-failed bail can be exercised. Default: placement succeeds.
var place_fails: bool = false


func _init() -> void:
	# No VM in a test — the base holds a null `_vm`; every verb is overridden to
	# record rather than dereference it.
	super(null)


# --- Unit placement & facing ({24} Warp Unit) ------------------------------

func has_unit(uid: int) -> bool:
	_record("has_unit", {"uid": uid})
	return not missing_units.has(uid)


func place_unit_on_tile(uid: int, psx_x: int, psx_y: int) -> bool:
	_record("place_unit_on_tile", {"uid": uid, "psx_x": psx_x, "psx_y": psx_y})
	return not place_fails


func clear_actor_home(uid: int) -> void:
	_record("clear_actor_home", {"uid": uid})


func set_unit_facing(uid: int, angle_12bit: int) -> void:
	_record("set_unit_facing", {"uid": uid, "angle_12bit": angle_12bit})


# --- Unit lifecycle ({45}/{44}/{46}/{3D}) ----------------------------------

func commit_unit_graphic(uid: int) -> void:
	_record("commit_unit_graphic", {"uid": uid})


func set_unit_visible(uid: int, visible: bool) -> void:
	_record("set_unit_visible", {"uid": uid, "visible": visible})


func resolve_unit_key(chunk_unit_id: int) -> int:
	_record("resolve_unit_key", {"chunk_unit_id": chunk_unit_id})
	return -1 if missing_units.has(chunk_unit_id) else chunk_unit_id


## Canned broadcast roster for `resolve_unit_set` team-set tests: Array of
## `{key, team_color, alive}`. Default empty → broadcast modes (Multi≠0) resolve to
## nothing; a test sets it to the exec-BP truth-table membership. The single-unit
## path (Multi=0) ignores this and uses `resolve_unit_key`. `resolve_unit_set` itself
## is INHERITED from [ScenarioWorld] so tests exercise the real broadcast logic.
var roster: Array = []


func _unit_roster() -> Array:
	return roster


func release_to_combat_idle(uid: int) -> void:
	_record("release_to_combat_idle", {"uid": uid})


func remove_unit(uid: int) -> void:
	_record("remove_unit", {"uid": uid})


func revive_and_normalise(uid: int) -> void:
	_record("revive_and_normalise", {"uid": uid})


func inflict_poison_critical(uid: int) -> void:
	_record("inflict_poison_critical", {"uid": uid})


func inflict_crystal(uid: int) -> void:
	_record("inflict_crystal", {"uid": uid})


## Ghost control-ids already spawned this run — the {47} idempotency gate (PSX
## `FUN_8007a6e4(slot)==0`). `spawn_ghost_unit` records every call but reports a
## re-add of a live control-id as a no-op (returns false), so an apply test can
## drive two adds and assert the second didn't re-spawn.
var spawned_ghosts: Dictionary = {}


func spawn_ghost_unit(control_id: int, sprite_set: int, psx_x: int, psx_y: int,
		elevation: int, facing_12bit: int, visible: bool) -> bool:
	_record("spawn_ghost_unit", {"control_id": control_id, "sprite_set": sprite_set,
		"psx_x": psx_x, "psx_y": psx_y, "elevation": elevation,
		"facing_12bit": facing_12bit, "visible": visible})
	if spawned_ghosts.has(control_id):
		return false
	spawned_ghosts[control_id] = true
	return true


# --- Unit motion ({3B}/{6E} Sprite Move) -----------------------------------

## When false, `can_slide` reports the unit can't move (resolved-away / non-spatial).
var slide_ok: bool = true
## The position `unit_position` reports (motion start point).
var unit_pos: Vector3 = Vector3.ZERO
## The home `capture_unit_home` reports (motion anchor).
var unit_home: Vector3 = Vector3.ZERO


func can_slide(uid: int) -> bool:
	_record("can_slide", {"uid": uid})
	return slide_ok


func unit_position(uid: int) -> Vector3:
	_record("unit_position", {"uid": uid})
	return unit_pos


func capture_unit_home(uid: int) -> Vector3:
	_record("capture_unit_home", {"uid": uid})
	return unit_home


func arm_motion(uid: int, motion) -> void:
	_record("arm_motion", {"uid": uid, "motion": motion})


func disarm_motion(uid: int) -> void:
	_record("disarm_motion", {"uid": uid})


# --- Walk To ({28}) --------------------------------------------------------

## The canned route `plan_walk` returns. Empty (default) → apply bails (no map/tile).
var walk_plan: Dictionary = {}


func plan_walk(uid: int, tx: int, tz: int, level: int = 0,
		flat_cost: bool = false) -> Dictionary:
	# `level` is the {28} Walk To Z operand — the terrain LEVEL of the seat, not a
	# height (ADR-0219 dec. 7). `flat_cost` is the opcode's cost switch (ADR-0226).
	# Both recorded so a test can assert the byte reached the planner; the canned
	# route above is what comes back either way.
	_record("plan_walk", {"uid": uid, "tx": tx, "tz": tz, "level": level,
		"flat_cost": flat_cost})
	return walk_plan


## The last cell a walk latched onto a unit, or `TerrainCell.NONE` if none has.
## Level-bearing (ADR-0219 dec. 6) — the seat's level is the whole point of the verb.
var seated_cell: Vector3i = TerrainCell.NONE


func seat_unit_cell(uid: int, cell: Vector3i) -> void:
	seated_cell = cell
	_record("seat_unit_cell", {"uid": uid, "cell": cell})


func set_walking(uid: int, facing_12bit: int, anim_id: int) -> void:
	_record("set_walking", {"uid": uid, "facing_12bit": facing_12bit, "anim_id": anim_id})


func set_walk_facing(uid: int, facing_12bit: int) -> void:
	_record("set_walk_facing", {"uid": uid, "facing_12bit": facing_12bit})


# --- Facing & animation ({11}/{8C}/{2D}/{53}/{2C}) -------------------------

## When false, play_unit_anim reports the sprite pipeline isn't ready (skip).
var anim_ready: bool = true
## When false, has_valid_unit / can_face report an invalid node.
var node_ok: bool = true
## The baseline rotate_baseline_12bit returns.
var baseline_12bit: int = 0
## The angle face_look_at_12bit returns.
var look_at_12bit: int = 0


func has_valid_unit(uid: int) -> bool:
	_record("has_valid_unit", {"uid": uid})
	return node_ok


func can_face(uid: int) -> bool:
	_record("can_face", {"uid": uid})
	return node_ok


func play_unit_anim(uid: int, anim_id: int) -> bool:
	_record("play_unit_anim", {"uid": uid, "anim_id": anim_id})
	return anim_ready


func rotate_baseline_12bit(uid: int) -> int:
	_record("rotate_baseline_12bit", {"uid": uid})
	return baseline_12bit


func arm_rotate(uid: int, target_12bit: int, direction: int, speed: int, delay: int) -> void:
	_record("arm_rotate", {"uid": uid, "target_12bit": target_12bit,
		"direction": direction, "speed": speed, "delay": delay})


func face_look_at_12bit(aff_uid: int, faced_uid: int) -> int:
	_record("face_look_at_12bit", {"aff_uid": aff_uid, "faced_uid": faced_uid})
	return look_at_12bit


func face_tile_look_at_12bit(aff_uid: int, tile_x: int, tile_y: int) -> int:
	_record("face_tile_look_at_12bit", {"aff_uid": aff_uid, "tile_x": tile_x, "tile_y": tile_y})
	return look_at_12bit


func set_unit_shadow(uid: int, enabled: bool) -> void:
	_record("set_unit_shadow", {"uid": uid, "enabled": enabled})


# --- Tint & palette ({32}/{33}/Reset Palette/{1A}) -------------------------

## Live per-unit tints, so a test can read the affine after the op folds into it.
var unit_tints: Dictionary = {}
## Live field tint (null until the first {33}).
var field_tint: ScenarioColorTint = null


func set_unit_mirror(uid: int, mirrored: bool) -> void:
	_record("set_unit_mirror", {"uid": uid, "mirrored": mirrored})


func get_or_create_unit_tint(uid: int) -> ScenarioColorTint:
	_record("get_or_create_unit_tint", {"uid": uid})
	if not unit_tints.has(uid):
		unit_tints[uid] = ScenarioColorTint.new()
	return unit_tints[uid]


func push_unit_tint(uid: int, tint: ScenarioColorTint) -> void:
	_record("push_unit_tint", {"uid": uid, "tint": tint})


func clear_unit_tint(uid: int) -> void:
	_record("clear_unit_tint", {"uid": uid})
	unit_tints.erase(uid)


func get_or_create_field_tint() -> ScenarioColorTint:
	_record("get_or_create_field_tint", {})
	if field_tint == null:
		field_tint = ScenarioColorTint.new()
	return field_tint


func push_field_tint_to_all() -> void:
	_record("push_field_tint_to_all", {})


func clear_field_tint() -> void:
	_record("clear_field_tint", {})
	field_tint = null


func set_map_darkness(intent: ScenarioDecode.MapDarknessIntent) -> void:
	_record("set_map_darkness", {"intent": intent})


# --- Screen & overlay effects ({3C}/{76}/{77}/{78}/{7D}/Reveal) ------------

func set_weather(active: bool, strength: int) -> void:
	_record("set_weather", {"active": active, "strength": strength})


func show_dark_screen(intent: ScenarioDecode.DarkScreenIntent) -> void:
	_record("show_dark_screen", {"intent": intent})


func hide_dark_screen() -> void:
	_record("hide_dark_screen", {})


func show_conditions(conditions: int, time: int) -> void:
	_record("show_conditions", {"conditions": conditions, "time": time})


func show_graphic(intent: ScenarioDecode.ShowGraphicIntent) -> void:
	_record("show_graphic", {"intent": intent})


func arm_reveal(ticks: int) -> void:
	_record("arm_reveal", {"ticks": ticks})


# --- Dialogue ({10} Display Message / Change Dialog) -----------------------

## When false, has_dialogue_overlay reports no overlay wired.
var overlay_wired: bool = true
## When false, is_boxed_dialog reports the dialog byte isn't a boxed variant.
var boxed_ok: bool = true
## When false, has_dialogue_box reports no box renderer wired.
var box_wired: bool = true
## The foreground slot show_dialogue_box reports after rendering.
var foreground_slot_after: int = 1
## The slot resolve_dialog_slot returns.
var resolved_slot: int = 1
## Whether close_dialog_slot reports it closed the FOREGROUND box.
var close_is_foreground: bool = true
## Baked tokens dialog_tokens_for returns (empty → no swap).
var tokens_for_msg: Array = ["tok"]
## Whether swap_dialog_text reports a box occupied the slot.
var swap_ok: bool = true


func clear_dialogue_overlay() -> void:
	_record("clear_dialogue_overlay", {})


func has_dialogue_overlay() -> bool:
	return overlay_wired


func show_dialogue_overlay(tokens: Array, psx_x: int, psx_y: int, dialog: int = 0x09) -> void:
	_record("show_dialogue_overlay", {"tokens": tokens, "psx_x": psx_x, "psx_y": psx_y, "dialog": dialog})


func is_boxed_dialog(dialog: int) -> bool:
	return boxed_ok


func has_dialogue_box() -> bool:
	return box_wired


func show_dialogue_box(tokens: Array, dialog: int, speaker_uid: int, portrait_row: int,
		open_type: int, psx_x: int, psx_y: int, fine_x60: int) -> int:
	_record("show_dialogue_box", {"tokens": tokens, "dialog": dialog, "speaker_uid": speaker_uid})
	return foreground_slot_after


func resolve_dialog_slot(target: int) -> int:
	_record("resolve_dialog_slot", {"target": target})
	return resolved_slot


func close_dialog_slot(slot: int) -> bool:
	_record("close_dialog_slot", {"slot": slot})
	return close_is_foreground


func dialog_tokens_for(msg: int) -> Array:
	_record("dialog_tokens_for", {"msg": msg})
	return tokens_for_msg


func swap_dialog_text(slot: int, toks: Array, portrait_byte: int = 0) -> bool:
	_record("swap_dialog_text", {"slot": slot, "toks": toks, "portrait_byte": portrait_byte})
	return swap_ok


# --- Field objects & EVTCHR ({58}/{55}/{54}) -------------------------------

## Whether play_field_object reports a real render (vs the modeled fallback).
var field_object_rendered: bool = false


func load_evtchr(block: int, slot: int) -> void:
	_record("load_evtchr", {"block": block, "slot": slot})


func play_field_object(id: int, arg2: int) -> bool:
	_record("play_field_object", {"id": id, "arg2": arg2})
	return field_object_rendered


func play_3d_object(id: int, state: int) -> void:
	_record("play_3d_object", {"id": id, "state": state})


## Append a verb record. `args` maps each argument name to its value; the `"verb"`
## key is added here so a call site just passes its operands.
# --- Sound ({21}/{60}/{22}/{6B}/{6A}) --------------------------------------

## Backend handle `play_bg_sound` reports; a test sets it to 0 to exercise the
## "SPU miss → nothing to ramp" bail. Default: a non-zero handle.
var bg_sound_handle: int = 0x1234


func play_system_sound(sound_id: int) -> void:
	_record("play_system_sound", {"sound_id": sound_id})


func play_bg_sound(sound_id: int, stacking: int) -> int:
	_record("play_bg_sound", {"sound_id": sound_id, "stacking": stacking})
	return bg_sound_handle


func set_bg_sound_volume(handle: int, vol: int) -> void:
	_record("set_bg_sound_volume", {"handle": handle, "vol": vol})


func stop_bg_sound(handle: int) -> void:
	_record("stop_bg_sound", {"handle": handle})


func notify_bg_sound_changed(kind: String, sound_id: int, stacking: int, handle: int) -> void:
	_record("notify_bg_sound_changed",
		{"kind": kind, "sound_id": sound_id, "stacking": stacking, "handle": handle})


func fade_music(ticks: int) -> void:
	_record("fade_music", {"ticks": ticks})


func switch_music_track(song_id: int, target_vol: int, ticks: int) -> void:
	_record("switch_music_track", {"song_id": song_id, "target_vol": target_vol, "ticks": ticks})


func _record(verb: String, args: Dictionary = {}) -> void:
	var entry := {"verb": verb}
	entry.merge(args)
	calls.append(entry)


## All recorded calls to `verb`, in order — the common assertion helper.
func calls_to(verb: String) -> Array:
	return calls.filter(func(e): return e["verb"] == verb)


## The single recorded call to `verb`, or null if there wasn't exactly one — for
## the common "assert this verb fired once with these args" shape.
func only_call(verb: String):
	var matches := calls_to(verb)
	return matches[0] if matches.size() == 1 else null
