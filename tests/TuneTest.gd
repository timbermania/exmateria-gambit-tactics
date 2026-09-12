extends Node3D

## TDD guard for the Tune tunable registry (ADR-0068 pilot slice 1: the core
## spine — coalescing read, staging round-trip, bind lifecycle). See the
## CONTEXT.md "Debug tuning" cluster for the vocabulary.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/TuneTest.tscn

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	_test_bind_returns_code_default_when_no_override()
	_test_set_value_coalesces_over_default()
	_test_clear_reverts_to_code_default()
	_test_slugs_are_independent()
	_test_overrides_round_trip_through_file()
	_test_is_dirty_tracks_uncommitted_edits()
	_test_commit_creates_missing_dir_and_persists()
	_test_failed_commit_stays_dirty()
	_test_commit_slug_pins_only_that_slug()
	_test_commit_slug_after_reset_keeps_other_pins()
	_test_commit_slug_after_reset_unpins()
	_test_bind_applies_immediately()
	_test_bind_reapplies_on_change()
	_test_bind_drops_when_owner_leaves_tree()
	_test_bind_registers_slug_and_default()
	_test_registry_keeps_code_default_under_override()
	_test_bind_update_registers_slug_and_default()
	_test_registered_slugs_are_sorted()
	_test_reset_clears_the_registry()
	_test_reset_overrides_keeps_the_declarations()
	_test_bind_records_hint_metadata()
	_test_override_coerces_to_the_code_default_type()
	_test_bind_records_use_site_location()
	_test_bind_appends_a_distinct_use_site()
	_test_dump_registry_writes_type_persist_and_locations()
	_test_vector2_override_round_trips_and_coerces()
	_test_pure_bind_registers_and_coalesces_without_an_owner()
	_test_on_update_applies_now_and_on_change_after_bind()
	_test_on_update_coalesces_an_existing_override_on_apply()
	_test_on_update_drops_when_owner_leaves_tree()
	_test_on_update_skips_a_co_subscriber_freed_mid_emit()
	_test_on_update_skips_an_unbound_apply_whose_owner_died_mid_emit()
	_test_get_value_reads_coalesced_after_bind()
	_test_get_value_coerces_override_type()
	_test_guard_flags_scrubbed_slug_with_no_consumer()
	_test_guard_clears_when_on_update_subscriber_exists()
	_test_guard_clears_when_get_value_re_reads_after_scrub()
	_test_guard_respects_the_grace_window()
	_test_guard_reports_each_offender_once_until_re_scrubbed()
	_test_guard_reflags_after_last_subscriber_leaves_tree()
	_test_guard_state_clears_on_reset()
	_test_guard_counts_a_get_value_read_as_consumption()

	print("\n=== TuneTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TuneTest")
		get_tree().quit(1)
	else:
		print("[PASS] TuneTest")
		get_tree().quit(0)


## With nothing committed or scrubbed, bind() returns the code default verbatim — the
## code literal is the resting source of truth (ADR-0068 decision 3).
func _test_bind_returns_code_default_when_no_override() -> void:
	Tune.reset()
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 8.0,
		"bind() returns the code default when no override exists")


## Scrubbing a value (set_value) makes a re-bind return the override, coalescing
## over the code default (ADR-0068 decision 3: override ?? code_default).
func _test_set_value_coalesces_over_default() -> void:
	Tune.reset()
	Tune.set_value("unit.mesh_scale", 9.5)
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 9.5,
		"set_value override coalesces over the code default")


## clear() drops the override, so a read falls back to the code default again —
## the code literal is always the floor (ADR-0068 decision 3).
func _test_clear_reverts_to_code_default() -> void:
	Tune.reset()
	Tune.set_value("unit.mesh_scale", 9.5)
	Tune.clear("unit.mesh_scale")
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 8.0,
		"clear() reverts a read to the code default")


## Overrides are per-slug: touching one slug never bleeds into another.
func _test_slugs_are_independent() -> void:
	Tune.reset()
	Tune.set_value("a.one", 1.0)
	_assert_eq(Tune.bind("b.two", 2.0), 2.0,
		"an override on one slug does not affect a different slug")
	_assert_eq(Tune.bind("a.one", 9.0), 1.0, "the overridden slug still reads its override")


## Committed overrides survive a save/load round-trip through the staging file
## (ADR-0068 decision 4/5 — the file is loaded into memory at boot). Uses a
## temp path so the real staging file is never touched.
func _test_overrides_round_trip_through_file() -> void:
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 1.25)
	Tune.set_value("unit.mesh_scale", 9.5)
	var tmp := "user://tune_test_roundtrip.json"
	Tune.save_overrides(tmp)
	Tune.reset()
	_assert_eq(Tune.bind("render.pixel_aspect", 1.0), 1.0, "reset clears overrides before load")
	Tune.load_overrides(tmp)
	_assert_eq(Tune.bind("render.pixel_aspect", 1.0), 1.25,
		"override survives the save/load round-trip")
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 9.5, "a second override survives too")


## A slug is "dirty" when its live value differs from what is committed to the
## staging file — the {66} "dialed past the committed baseline" state
## (ADR-0068 decision 7). commit() bakes the live value in and clears dirt.
func _test_is_dirty_tracks_uncommitted_edits() -> void:
	Tune.reset()
	_assert_true(not Tune.is_dirty("render.pixel_aspect"), "an unset slug is not dirty")
	Tune.set_value("render.pixel_aspect", 1.25)
	_assert_true(Tune.is_dirty("render.pixel_aspect"), "a scrubbed-but-uncommitted slug is dirty")
	var tmp := "user://tune_test_dirty.json"
	Tune.commit(tmp)
	_assert_true(not Tune.is_dirty("render.pixel_aspect"), "a committed slug is clean")
	Tune.set_value("render.pixel_aspect", 1.5)
	_assert_true(Tune.is_dirty("render.pixel_aspect"),
		"editing past the committed value goes dirty again")


## commit() to a path whose parent dir does not exist must create the dir and
## actually persist — the real staging path is `res://config/…` and `config/`
## does not exist on a fresh checkout. A commit that silently no-ops the write
## while flipping is_dirty() clean loses the override on the next boot
## (ADR-0068 decision 4/7). Proven by reloading the file from disk.
func _test_commit_creates_missing_dir_and_persists() -> void:
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 1.25)
	var nested := "user://tune_test_missing_dir/nested/overrides.json"
	var ok: bool = Tune.commit(nested)
	_assert_true(ok, "commit into a missing dir reports success")
	_assert_true(FileAccess.file_exists(nested), "commit created the file on disk")
	_assert_true(not Tune.is_dirty("render.pixel_aspect"), "the committed slug is clean")
	Tune.reset()
	Tune.load_overrides(nested)
	_assert_eq(Tune.bind("render.pixel_aspect", 1.0), 1.25,
		"the committed override survives a reload from disk")


## When the write genuinely cannot happen (parent path is an existing FILE, so
## the dir can't be created), commit() must report failure and leave the slug
## dirty — never flip clean on a write that never hit disk (ADR-0068 decision 7).
func _test_failed_commit_stays_dirty() -> void:
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 1.25)
	# Make `blocker` a file so `blocker/sub/…` cannot be created as a directory.
	var blocker := "user://tune_test_blocker"
	var bf := FileAccess.open(blocker, FileAccess.WRITE)
	bf.store_string("x")
	bf.close()
	var ok: bool = Tune.commit(blocker + "/sub/overrides.json")
	_assert_true(not ok, "commit reports failure when the write cannot happen")
	_assert_true(Tune.is_dirty("render.pixel_aspect"),
		"a failed commit leaves the slug dirty (override not persisted)")


## Per-slug commit (the "pin" gesture, ADR-0068 decision 7): commit_slug() pins ONE
## slug's live value into the staging file and leaves every other dialed-but-unpinned
## slug out of it — so a session full of scratch nudges never gets blanket-saved.
## The pinned slug goes clean; an un-pinned dirty slug stays dirty AND is absent from
## the reloaded file.
func _test_commit_slug_pins_only_that_slug() -> void:
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 1.25)
	Tune.set_value("unit.mesh_scale", 9.5)  # dialed but NOT pinned
	var tmp := "user://tune_test_pin_one.json"
	var ok: bool = Tune.commit_slug("render.pixel_aspect", tmp)
	_assert_true(ok, "commit_slug reports success")
	_assert_true(not Tune.is_dirty("render.pixel_aspect"), "the pinned slug is clean")
	_assert_true(Tune.is_dirty("unit.mesh_scale"), "the un-pinned slug stays dirty")
	Tune.reset()
	Tune.load_overrides(tmp)
	_assert_eq(Tune.bind("render.pixel_aspect", 1.0), 1.25, "the pinned override persisted")
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 8.0,
		"the un-pinned override did NOT reach the file")


## #614: pinning ONE slug must not DELETE the file's other pins, even when the in-memory
## committed baseline has been cleared out from under it.
##
## `_committed` is meant to be a mirror of the staging file, and `commit_slug` builds the
## next file from "prior pins + this slug". `reset()` clears the mirror and deliberately
## does NOT touch the file, so in that window the mirror says "nothing is pinned" while the
## file holds everything — and seeding from the mirror wrote a file containing only the
## slug being pinned. Measured on the real tracked file: ten entries to one, including a
## deliberate `scenario.active_id` pick, with `git status` showing a modified file and
## nothing saying a test had done it.
##
## `TileOverlayConfigTuneTest` snapshots and restores the tracked file to contain its own
## blast radius, which is right for that test and does not fix this: any AUTOSAVE commit
## after a reset truncates, including a human pressing F3 in a scene that has no test seam
## to redirect. This is the arm for the root cause, so the containment there is belt and
## braces rather than the only thing standing between the repo and its own config.
func _test_commit_slug_after_reset_keeps_other_pins() -> void:
	var tmp := "user://tune_test_614_other_pins.json"
	# Three pins reach the file the ordinary way.
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 1.25)
	Tune.set_value("unit.mesh_scale", 9.5)
	Tune.set_value("cursor.height", 4.5)
	Tune.commit_slug("render.pixel_aspect", tmp)
	Tune.commit_slug("unit.mesh_scale", tmp)
	Tune.commit_slug("cursor.height", tmp)

	# THE WINDOW: the mirror is cleared, the file is not. Then one AUTOSAVE-shaped pin.
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 2.5)
	var ok: bool = Tune.commit_slug("render.pixel_aspect", tmp)
	_assert_true(ok, "the pin after a reset reports success")

	Tune.reset()
	Tune.load_overrides(tmp)
	_assert_eq(Tune.bind("render.pixel_aspect", 1.0), 2.5, "the pinned slug took its new value")
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 9.5,
		"a DIFFERENT slug's pin survived the pin-after-reset (#614)")
	_assert_eq(Tune.bind("cursor.height", 1.5), 4.5,
		"and so did the third one — pinning one slug deletes none")


## Pinning a slug that was Reset (its live override cleared) persists the RESET —
## the slug drops out of the staging file, so a previously-committed value does not
## resurrect on the next boot. This is the "un-pin" half of the per-field gesture.
func _test_commit_slug_after_reset_unpins() -> void:
	Tune.reset()
	Tune.set_value("render.pixel_aspect", 1.25)
	var tmp := "user://tune_test_unpin.json"
	Tune.commit_slug("render.pixel_aspect", tmp)  # pinned into the file
	Tune.clear("render.pixel_aspect")             # Reset the field back to the default
	_assert_true(Tune.is_dirty("render.pixel_aspect"), "a reset-but-still-pinned slug is dirty")
	var ok: bool = Tune.commit_slug("render.pixel_aspect", tmp)  # pin the reset -> un-pin
	_assert_true(ok, "committing the reset reports success")
	_assert_true(not Tune.is_dirty("render.pixel_aspect"), "the un-pinned slug is clean")
	Tune.reset()
	Tune.load_overrides(tmp)
	_assert_eq(Tune.bind("render.pixel_aspect", 3.0), 3.0, "the slug dropped out of the file")


## bind() applies once on registration with the coalesced value — the default
## when nothing is overridden, the override when one already exists
## (ADR-0068 R3.5, the set-once form).
func _test_bind_applies_immediately() -> void:
	Tune.reset()
	var owner_a := Node.new()
	add_child(owner_a)
	var seen_a := [0.0]
	Tune.bind_update(owner_a, "cam.zoom_a", 3.0, func(v): seen_a[0] = v)
	_assert_eq(seen_a[0], 3.0, "bind applies the code default immediately when unset")
	remove_child(owner_a)
	owner_a.free()

	Tune.set_value("cam.zoom_b", 5.0)
	var owner_b := Node.new()
	add_child(owner_b)
	var seen_b := [0.0]
	Tune.bind_update(owner_b, "cam.zoom_b", 3.0, func(v): seen_b[0] = v)
	_assert_eq(seen_b[0], 5.0, "bind applies an existing override over the default")
	remove_child(owner_b)
	owner_b.free()


## A scrub (set_value) re-runs the bound callback with the new coalesced value,
## and clear() re-runs it with the code default — this is the live push into the
## game for set-once values.
func _test_bind_reapplies_on_change() -> void:
	Tune.reset()
	var owner := Node.new()
	add_child(owner)
	var seen := [0.0]
	Tune.bind_update(owner, "cam.pitch", 3.0, func(v): seen[0] = v)
	Tune.set_value("cam.pitch", 7.0)
	_assert_eq(seen[0], 7.0, "scrubbing re-applies through the bound callback")
	Tune.clear("cam.pitch")
	_assert_eq(seen[0], 3.0, "clearing re-applies the code default through the callback")
	remove_child(owner)
	owner.free()


## Once the owner leaves the tree, the binding is dropped: later scrubs no longer
## reach the callback (ADR-0068 decision 6 — Ctrl+R-safe, no ghost drives).
func _test_bind_drops_when_owner_leaves_tree() -> void:
	Tune.reset()
	var owner := Node.new()
	add_child(owner)
	var seen := [0.0]
	Tune.bind_update(owner, "cam.yaw", 3.0, func(v): seen[0] = v)
	remove_child(owner)  # fires tree_exited -> binding auto-drops
	owner.free()
	Tune.set_value("cam.yaw", 9.0)
	_assert_eq(seen[0], 3.0,
		"after the owner leaves the tree, a scrub no longer reaches the callback")


## The dashboard is generated FROM the registry (ADR-0068 decision 9): a slug is
## only knowable once its bind() use-site has run. bind() records the slug and
## its code default the first time it is read, so the auto-card can enumerate it.
func _test_bind_registers_slug_and_default() -> void:
	Tune.reset()
	_assert_true(not ("unit.mesh_scale" in Tune.registered_slugs()),
		"a never-read slug is not registered")
	Tune.bind("unit.mesh_scale", 8.0)
	_assert_true("unit.mesh_scale" in Tune.registered_slugs(), "bind() registers the slug")
	_assert_eq(Tune.default_of("unit.mesh_scale"), 8.0, "bind() records the code default")


## The registry stores the CODE default, not the live value — the dashboard shows
## "default vs current" and the reset target is the code literal, so an override
## must not overwrite the recorded default.
func _test_registry_keeps_code_default_under_override() -> void:
	Tune.reset()
	Tune.bind("unit.mesh_scale", 8.0)
	Tune.set_value("unit.mesh_scale", 12.0)
	_assert_eq(Tune.default_of("unit.mesh_scale"), 8.0,
		"the registry keeps the code default even when overridden")
	_assert_eq(Tune.bind("unit.mesh_scale", 8.0), 12.0, "bind() still coalesces the override")


## bind_update() registers its slug + default too (set-once values must appear on the
## dashboard exactly like read-in-place ones — live_par is a bind_update()).
func _test_bind_update_registers_slug_and_default() -> void:
	Tune.reset()
	var owner := Node.new()
	add_child(owner)
	Tune.bind_update(owner, "cam.zoom", 3.0, func(_v): pass)
	_assert_true("cam.zoom" in Tune.registered_slugs(), "bind() registers the slug")
	_assert_eq(Tune.default_of("cam.zoom"), 3.0, "bind() records the code default")
	remove_child(owner)
	owner.free()


## registered_slugs() is sorted so the generated dashboard is stable frame to
## frame (and groups cleanly by dotted-namespace prefix).
func _test_registered_slugs_are_sorted() -> void:
	Tune.reset()
	Tune.bind("render.z_last", 1.0)
	Tune.bind("cam.a_first", 1.0)
	Tune.bind("render.a_mid", 1.0)
	_assert_eq(Tune.registered_slugs(), ["cam.a_first", "render.a_mid", "render.z_last"],
		"registered_slugs() is sorted")


## reset() is the TOTAL clean slate — overrides and declarations both — and stays that way.
## Registry ISOLATION is what nearly every caller wants: `_register` is first-write-wins, so a
## surviving declaration would hand a later test an earlier one's default.
func _test_reset_clears_the_registry() -> void:
	Tune.reset()
	Tune.bind("temp.slug", 1.0)
	_assert_true("temp.slug" in Tune.registered_slugs(), "slug registered before reset")
	Tune.reset()
	_assert_true(not ("temp.slug" in Tune.registered_slugs()), "reset() clears the registry")


## reset_overrides() is everything reset() does EXCEPT the one thing it cannot undo (#535,
## ADR-0173). A declaration's only producer is a `bind` at its use-site, and for a class-load
## owner that runs from `_static_init`, once per class load per process — so clearing it used to
## force `Tune` to hold a list of owner script paths and `load()` them back (`register_all()`).
## This is the verb the seven tests that spawn a real production node call instead.
func _test_reset_overrides_keeps_the_declarations() -> void:
	Tune.reset()
	Tune.bind("temp.slug", 1.0)
	Tune.set_value("temp.slug", 5.0)
	Tune.reset_overrides()
	_assert_true("temp.slug" in Tune.registered_slugs(),
		"reset_overrides() leaves the declaration standing (nothing needs to replay it)")
	_assert_eq(Tune.get_value("temp.slug"), 1.0, "reset_overrides() drops the override")


## A tunable's control is inferred from its type, but range/step and enum options
## can't be (ADR-0068 decision 11). They ride an OPTIONAL trailing hint dict on
## bind(), recorded in the registry so the dashboard can render a ranged
## spinbox / enum dropdown. No hint = an empty hint (inferred control, no range).
func _test_bind_records_hint_metadata() -> void:
	Tune.reset()
	Tune.bind("render.pixel_aspect", 1.25, {"min": 0.5, "max": 2.0, "step": 0.01})
	_assert_eq(Tune.meta_of("render.pixel_aspect"), {"min": 0.5, "max": 2.0, "step": 0.01},
		"bind() records the affordance hint")

	var owner := Node.new()
	add_child(owner)
	Tune.bind_update(owner, "combat.ai_mode", 0, func(_v): pass,
		{"enum": {"Aggressive": 0, "Defensive": 1}})
	_assert_eq(Tune.meta_of("combat.ai_mode"), {"enum": {"Aggressive": 0, "Defensive": 1}},
		"bind() records the affordance hint")
	remove_child(owner)
	owner.free()

	Tune.bind("unit.mesh_scale", 8.0)
	_assert_eq(Tune.meta_of("unit.mesh_scale"), {}, "a hintless slug has an empty hint")


## An int/bool tunable persisted to JSON reloads as a float (JSON has one number
## type). A read coerces a numeric override back to the code default's type, so an
## enum/int slug survives the commit→reload loop as an int, not a float (review
## finding #5 — it bites the moment the first non-float tunable lands, which is
## now: the enum template).
func _test_override_coerces_to_the_code_default_type() -> void:
	Tune.reset()
	# Simulate a reloaded-from-JSON override: the enum int came back as a float.
	Tune.set_value("combat.ai_mode", 2.0)
	var coalesced = Tune.bind("combat.ai_mode", 0)  # code default is an int
	_assert_true(typeof(coalesced) == TYPE_INT, "an int-default slug coalesces to an int")
	_assert_eq(coalesced, 2, "the coerced value keeps its magnitude")
	# A float-default slug is left alone.
	_assert_eq(Tune.bind("render.pixel_aspect", 1.0), 1.0, "a float-default slug stays float")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


## bind() captures its calling use-site (file+line) on first registration, so the
## materialize codemod knows where the default literal lives (ADR-0068
## M2). The recorded frame is the caller, NOT Tune.gd/TuneField.gd.
func _test_bind_records_use_site_location() -> void:
	Tune.reset()
	Tune.bind("loc.probe", 1.0)
	var locs: Array = Tune.locations_of("loc.probe")
	_assert_eq(locs.size(), 1, "bind() records exactly one use-site location")
	if locs.size() == 1:
		_assert_true(String(locs[0]["file"]).ends_with("TuneTest.gd"),
			"use-site file is the caller, not the tunable framework")
		_assert_true(int(locs[0]["line"]) > 0, "use-site line is captured")


## A slug touched from two distinct sites records BOTH locations (M3), so
## materialize rewrites every literal site instead of forking the truth. Deduped
## by (file,line) so a per-frame re-read never bloats the list.
func _test_bind_appends_a_distinct_use_site() -> void:
	Tune.reset()
	var owner := Node.new()
	add_child(owner)
	_bind_probe_site_a(owner)
	_bind_probe_site_b(owner)
	_assert_eq(Tune.locations_of("loc.multi").size(), 2,
		"two distinct bind sites are both recorded")
	owner.free()


func _bind_probe_site_a(owner: Node) -> void:
	Tune.bind_update(owner, "loc.multi", 1.0, func(_v: Variant) -> void: pass)


func _bind_probe_site_b(owner: Node) -> void:
	Tune.bind_update(owner, "loc.multi", 1.0, func(_v: Variant) -> void: pass)


## dump_registry writes the materialize bridge snapshot (M4): per slug the code
## default, its TYPE (JSON collapses int/float/bool), the persist class (AUTOSAVE
## is skipped by materialize), and the captured use-site locations.
func _test_dump_registry_writes_type_persist_and_locations() -> void:
	Tune.reset()
	Tune.bind("dump.count", 7, {}, Tune.Persist.AUTOSAVE)
	var path := "user://_tune_dump_test.json"
	_assert_true(Tune.dump_registry(path), "dump_registry writes the snapshot file")
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if f != null:
		f.close()
	var ok := parsed is Dictionary and (parsed as Dictionary).has("dump.count")
	_assert_true(ok, "snapshot contains the registered slug")
	if ok:
		var e: Dictionary = parsed["dump.count"]
		_assert_eq(e["type"], "int", "snapshot records the code-default TYPE")
		_assert_eq(int(e["persist"]), Tune.Persist.AUTOSAVE,
			"snapshot records the persist class")
		_assert_true((e["locations"] as Array).size() >= 1,
			"snapshot records at least one use-site location")


## A Vector2 override (the collapsed render.loc_offset slug, ADR-0068 R6) survives the
## save/load round-trip: JSON has no Vector2, so set_value stores it as an [x,y] array and
## get_value coerces it back to a Vector2 on read — same shape-reduction the Color path uses.
func _test_vector2_override_round_trips_and_coerces() -> void:
	Tune.reset()
	Tune.set_value("render.loc_offset", Vector2(27.0, 20.0))
	var tmp := "user://tune_test_vec2.json"
	Tune.save_overrides(tmp)
	Tune.reset()
	Tune.load_overrides(tmp)
	var got: Variant = Tune.bind("render.loc_offset", Vector2(27.0, 26.0))
	_assert_true(got is Vector2, "a Vector2 override reloads as a Vector2, not a raw array")
	if got is Vector2:
		_assert_approx_v(got, Vector2(27.0, 20.0), "the Vector2 override survives the round-trip")


func _assert_approx_v(actual: Vector2, expected: Vector2, label: String) -> void:
	if actual.is_equal_approx(expected):
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected ~%s, got %s" % [label, str(expected), str(actual)])


## Pure bind (ADR-0068 R2) attaches a slug to exactly one literal — NO owner, NO
## callback. It registers the slug (+ default + hint) so the panel/materialize can enumerate
## it, and returns the coalesced value as a convenience. A `bind` alone is inert to scrubbing
## (R3): with no `update`, a set_value reaches no consumer — it just changes what a later
## read coalesces. This is the two-arg call the old set-once bind could not express.
func _test_pure_bind_registers_and_coalesces_without_an_owner() -> void:
	Tune.reset()
	var got: Variant = Tune.bind("render.loc_offset", Vector2(27.0, 26.0), {"min": -128.0})
	_assert_eq(got, Vector2(27.0, 26.0), "pure bind returns the coalesced value (the literal when unset)")
	_assert_true("render.loc_offset" in Tune.registered_slugs(), "pure bind registers the slug")
	_assert_eq(Tune.default_of("render.loc_offset"), Vector2(27.0, 26.0), "pure bind records the literal as the default")
	_assert_eq(Tune.meta_of("render.loc_offset"), {"min": -128.0}, "pure bind records the affordance hint")
	# Inert: a scrub with no update changes only what the next read coalesces.
	Tune.set_value("render.loc_offset", Vector2(1.0, 2.0))
	_assert_eq(Tune.bind("render.loc_offset", Vector2(27.0, 26.0)), Vector2(1.0, 2.0),
		"a re-bind coalesces the existing override over the literal")


## on_update() (ADR-0068 R3) subscribes an owner-scoped apply to a slug already registered by a
## bind: it applies the coalesced value NOW (the registered default when unset) and again on
## every change. This is the "as-needed" push apply, added separately from the bind.
func _test_on_update_applies_now_and_on_change_after_bind() -> void:
	Tune.reset()
	Tune.bind("cam.zoom", 3.0)
	var owner := Node.new()
	add_child(owner)
	var seen := [0.0]
	Tune.on_update(owner, "cam.zoom", func(v): seen[0] = v)
	_assert_eq(seen[0], 3.0, "on_update applies the registered default immediately")
	Tune.set_value("cam.zoom", 7.0)
	_assert_eq(seen[0], 7.0, "on_update re-applies on a scrub")
	Tune.clear("cam.zoom")
	_assert_eq(seen[0], 3.0, "on_update re-applies the default on clear")
	remove_child(owner)
	owner.free()


## An on_update subscribed AFTER an override already exists applies that override immediately —
## the coalescing read (override ?? registered default) governs the first apply too.
func _test_on_update_coalesces_an_existing_override_on_apply() -> void:
	Tune.reset()
	Tune.bind("cam.pitch", 3.0)
	Tune.set_value("cam.pitch", 5.0)
	var owner := Node.new()
	add_child(owner)
	var seen := [0.0]
	Tune.on_update(owner, "cam.pitch", func(v): seen[0] = v)
	_assert_eq(seen[0], 5.0, "on_update applies the existing override on first apply")
	remove_child(owner)
	owner.free()


## An on_update auto-drops when its owner leaves the tree (R3 — the owner-scope lives on the
## on_update, not the bind): a later scrub no longer reaches the callback. Ctrl+R-safe.
func _test_on_update_drops_when_owner_leaves_tree() -> void:
	Tune.reset()
	Tune.bind("cam.yaw", 3.0)
	var owner := Node.new()
	add_child(owner)
	var seen := [0.0]
	Tune.on_update(owner, "cam.yaw", func(v): seen[0] = v)
	remove_child(owner)  # fires tree_exited -> on_update auto-drops
	owner.free()
	Tune.set_value("cam.yaw", 9.0)
	_assert_eq(seen[0], 3.0, "after the owner leaves the tree, a scrub no longer reaches the on_update")


## Re-entrancy-during-emit hazard (the "call lambda on a null instance" error, and a heap-corrupt
## SIGSEGV on Godot 4.8.dev): value_changed SNAPSHOTS its connection list before invoking handlers,
## so if an earlier handler frees a co-subscriber's owner mid-emit (e.g. a rebuild that free()s the
## element it's replacing), the victim's tree_exited disconnect cannot pull it out of the in-flight
## emit — and its apply is now a Callable bound to a freed Object. on_update's `apply.is_valid()`
## guard must SKIP it rather than call into the freed instance. Here the victim's apply is bound to
## the victim node (UI3Element's `on_update(self, ...)` shape) and the survivor's handler frees it.
##
## NOTE this test exercises + documents the hazard path and the survivor contract; it is NOT
## self-failing on the CI engine, because a call on a freed Callable is a non-fatal GDScript error
## (it prints, execution continues, the survivor is still served) — so the assertions below hold
## with or without the guard. The guard's real payoff is on the user's 4.8.dev build, where the
## unguarded path can corrupt the accessibility_change_queue heap and crash. Watch stderr for a
## `Tune.gd` null-instance SCRIPT ERROR when the guard is absent.
func _test_on_update_skips_a_co_subscriber_freed_mid_emit() -> void:
	Tune.reset()
	Tune.bind("race.slug", 0.0)

	var victim := TuneFreedOwnerProbe.new()
	add_child(victim)

	# The FREER is connected first, so it runs first in the emit's snapshot and frees the victim
	# before the victim's own (now-stale) handler is reached. Gated to the scrub value (5.0) so the
	# immediate subscribe-time apply (0.0) does NOT free it during setup.
	var survivor_seen := [-1.0]
	var survivor := Node.new()
	add_child(survivor)
	Tune.on_update(survivor, "race.slug", func(v: float) -> void:
		survivor_seen[0] = v
		if v == 5.0 and is_instance_valid(victim):
			victim.free())

	# apply bound to the victim node — invalidated the instant the node is freed. Connected AFTER
	# the freer, so its handler is reached only after the victim is already gone.
	Tune.on_update(victim, "race.slug", Callable(victim, "on_value"))

	# The scrub that trips the race. Pre-guard this printed a null-instance SCRIPT ERROR (and on
	# Godot 4.8.dev could corrupt the heap); post-guard it completes cleanly.
	Tune.set_value("race.slug", 5.0)

	_assert_eq(survivor_seen[0], 5.0, "the survivor subscriber still applies through the racing emit")
	_assert_true(not is_instance_valid(victim), "the victim was freed mid-emit as set up")
	remove_child(survivor)
	survivor.free()


## The OTHER half of the same mid-emit race, and the half `apply.is_valid()` cannot see.
##
## `is_valid()` is false only for a Callable BOUND to a freed instance — the arm above. An
## apply that is a lambda from a `static func` is bound to nothing at all, so it stays valid
## forever no matter what happened to the owner; GDScript merely swaps its freed CAPTURES for
## null (logging "Lambda capture at index N was freed") and runs the body anyway. Every row
## `TuneField` builds has that shape, and the null then travels one more hop before it lands:
## `_apply_to_control(null, v)` matches none of its `is` branches and no-ops, and the very next
## statement writes the dirty marker — surfacing as *"Invalid assignment of property or key
## 'text' with value of type 'String' on a base object of type 'Nil'"* at `TuneField:306`, a
## file three frames away from the free that caused it, exactly once, on the next emit.
##
## Unlike the arm above this one IS self-failing: the guard's absence is observable as an extra
## element in the sink, not only as a printed error. The apply here is bound to the TEST (alive
## throughout) precisely so `is_valid()` stays true — the owner's liveness is the only thing
## that can decline the call.
func _test_on_update_skips_an_unbound_apply_whose_owner_died_mid_emit() -> void:
	Tune.reset()
	Tune.bind("race.unbound", 0.0)

	var owner := Node.new()
	add_child(owner)

	# Connected FIRST, so it runs first in the emit's snapshot and frees the owner before the
	# owner's own (now-stale) handler is reached. Gated to the scrub value so the subscribe-time
	# apply does not free it during setup.
	# The freer holds the owner in an ARRAY rather than capturing the node: a lambda that
	# captured it would itself log "Lambda capture at index 0 was freed" on the later emits
	# below, and a test that prints engine errors while passing is the shape this suite treats
	# as a failure it forgot to assert.
	var doomed: Array = [owner]
	var freer := Node.new()
	add_child(freer)
	Tune.on_update(freer, "race.unbound", func(v: float) -> void:
		if v == 5.0 and not doomed.is_empty():
			(doomed.pop_back() as Node).free())

	# The apply captures the SINK, never the owner — so nothing in this Callable is freed and
	# `is_valid()` cannot be what stops it.
	var sink: Array = []
	Tune.on_update(owner, "race.unbound", func(v: float) -> void: sink.append(v))
	_assert_eq(sink.size(), 1, "the subscribe-time apply landed before the race")

	Tune.set_value("race.unbound", 5.0)

	_assert_true(not is_instance_valid(owner), "the owner was freed mid-emit as set up")
	_assert_eq(sink.size(), 1, "the dead owner's apply is skipped in the emit that killed it")
	Tune.set_value("race.unbound", 6.0)
	_assert_eq(sink.size(), 1, "and stays dropped on every later emit")
	remove_child(freer)
	freer.free()


## get_value() (ADR-0068 R5) is the pull-read counterpart to on_update's push: it returns the
## coalesced value (override ?? registered default) for a slug ALREADY registered by a bind,
## cheaply — no use-site capture, no registration. For read-in-place consumers (computed
## getters, per-frame reads, one-shot setup reads) that re-read on their own.
func _test_get_value_reads_coalesced_after_bind() -> void:
	Tune.reset()
	Tune.bind("cam.zoom", 3.0)
	_assert_eq(Tune.get_value("cam.zoom"), 3.0, "get_value returns the registered default when unset")
	Tune.set_value("cam.zoom", 7.0)
	_assert_eq(Tune.get_value("cam.zoom"), 7.0, "get_value returns the override once scrubbed")
	Tune.clear("cam.zoom")
	_assert_eq(Tune.get_value("cam.zoom"), 3.0, "get_value falls back to the default on clear")


## get_value coerces a numeric override back to the code default's type — a JSON-round-tripped
## int slug reads as an int, not a float (same coercion get_value/on_update apply).
func _test_get_value_coerces_override_type() -> void:
	Tune.reset()
	Tune.bind("cam.steps", 2)  # int default
	Tune.set_value("cam.steps", 5.0)  # arrives as a float (JSON has one number type)
	var got: Variant = Tune.get_value("cam.steps")
	_assert_true(got is int, "get_value coerces the override back to the int default's type")
	_assert_eq(got, 5, "get_value returns the coerced int value")


## R8 guard (ADR-0068): a slug SCRUBBED with no on_update subscriber and never re-read via
## get_value is "unconsumed" — a likely mis-wired bind (bound but nothing wired to game
## state). poll_unconsumed_scrubs(frame) reports it once the grace window has elapsed, so a
## bound-but-dead tunable fails loudly the moment it is scrubbed during the sweep.
func _test_guard_flags_scrubbed_slug_with_no_consumer() -> void:
	Tune.reset()
	Tune.bind("guard.dead", 1.0)
	Tune.set_value("guard.dead", 2.0)
	var f := Engine.get_process_frames()
	var flagged := Tune.poll_unconsumed_scrubs(f + 5)  # well past the grace window
	_assert_true(flagged.has("guard.dead"),
		"a scrubbed slug with no on_update subscriber and no get_value re-read is flagged")


## A slug consumed by a PUSH subscriber (on_update) is never flagged, however long ago it was
## scrubbed — the subscriber lands the scrub on game state, so the wiring is live.
func _test_guard_clears_when_on_update_subscriber_exists() -> void:
	Tune.reset()
	Tune.bind("guard.pushed", 1.0)
	var owner := Node.new()
	add_child(owner)
	Tune.on_update(owner, "guard.pushed", func(_v): pass)
	Tune.set_value("guard.pushed", 2.0)
	var f := Engine.get_process_frames()
	var flagged := Tune.poll_unconsumed_scrubs(f + 5)
	_assert_true(not flagged.has("guard.pushed"),
		"a scrubbed slug with a live on_update subscriber is not flagged")
	remove_child(owner)
	owner.free()


## A slug consumed by a PULL read (get_value called at/after the scrub) is not flagged — the
## re-read is how a computed getter picks up the scrub, so no on_update is needed there.
func _test_guard_clears_when_get_value_re_reads_after_scrub() -> void:
	Tune.reset()
	Tune.bind("guard.pulled", 1.0)
	Tune.set_value("guard.pulled", 2.0)
	var got: Variant = Tune.get_value("guard.pulled")  # a getter re-reading after the scrub
	_assert_eq(got, 2.0, "get_value returns the scrubbed value")
	var f := Engine.get_process_frames()
	var flagged := Tune.poll_unconsumed_scrubs(f + 5)
	_assert_true(not flagged.has("guard.pulled"),
		"a scrubbed slug re-read via get_value after the scrub is not flagged")


## The grace window: a scrub is not flagged until _UNCONSUMED_GRACE_FRAMES have elapsed, so a
## pull consumer that re-reads a frame or two later is never a false positive.
func _test_guard_respects_the_grace_window() -> void:
	Tune.reset()
	Tune.bind("guard.slow", 1.0)
	Tune.set_value("guard.slow", 2.0)
	var f := Engine.get_process_frames()
	var within := Tune.poll_unconsumed_scrubs(f + 1)  # one frame later — still in grace
	_assert_true(not within.has("guard.slow"), "a scrub within the grace window is not flagged")
	var after := Tune.poll_unconsumed_scrubs(f + 2)  # grace elapsed
	_assert_true(after.has("guard.slow"), "the scrub is flagged once the grace window elapses")


## Warn-once: a flagged slug is reported on the poll that detects it and NOT on later polls
## (so `_process` warns once, not every frame) — until a fresh scrub re-arms it.
func _test_guard_reports_each_offender_once_until_re_scrubbed() -> void:
	Tune.reset()
	Tune.bind("guard.once", 1.0)
	Tune.set_value("guard.once", 2.0)
	var f := Engine.get_process_frames()
	var first := Tune.poll_unconsumed_scrubs(f + 5)
	_assert_true(first.has("guard.once"), "the offender is reported on the first poll past grace")
	var second := Tune.poll_unconsumed_scrubs(f + 6)
	_assert_true(not second.has("guard.once"), "the same offender is not reported again")
	Tune.set_value("guard.once", 3.0)  # a fresh scrub re-arms the warning
	var third := Tune.poll_unconsumed_scrubs(f + 7)
	_assert_true(third.has("guard.once"), "a re-scrub re-arms the offender so it reports again")


## When the last on_update subscriber leaves the tree, its slug loses its push consumer, so a
## still-live scrub on it becomes flaggable — the subscriber count is per-live-owner, not a
## one-way latch. Guards against a dead scrub hiding behind a since-freed subscriber.
func _test_guard_reflags_after_last_subscriber_leaves_tree() -> void:
	Tune.reset()
	Tune.bind("guard.orphan", 1.0)
	var owner := Node.new()
	add_child(owner)
	Tune.on_update(owner, "guard.orphan", func(_v): pass)
	Tune.set_value("guard.orphan", 2.0)
	var f := Engine.get_process_frames()
	_assert_true(not Tune.poll_unconsumed_scrubs(f + 5).has("guard.orphan"),
		"while the subscriber lives, the scrub is consumed")
	remove_child(owner)  # tree_exited -> subscriber count drops to 0
	owner.free()
	_assert_true(Tune.poll_unconsumed_scrubs(f + 6).has("guard.orphan"),
		"once the last subscriber leaves the tree, the still-live scrub is flagged")


## reset() (the test seam) clears the guard's tracking too, so a scrub recorded before a reset
## can never leak a phantom "unconsumed" report into the next test.
func _test_guard_state_clears_on_reset() -> void:
	Tune.reset()
	Tune.bind("guard.stale", 1.0)
	Tune.set_value("guard.stale", 2.0)
	Tune.reset()  # the subject: reset() must forget the scrub tracking, not just the overrides
	var f := Engine.get_process_frames()
	var flagged := Tune.poll_unconsumed_scrubs(f + 5)
	_assert_true(not flagged.has("guard.stale"),
		"reset clears guard scrub tracking so a pre-reset scrub is not flagged")


## A `get_value` pull-read is a genuine read-in-place consumer (R5): a scrubbed slug re-read via
## get_value is NOT flagged — the guard only catches truly dead binds (no on_update AND no pull
## re-read), never a slug a getter/`_process` re-reads on its own. (This replaced the old
## legacy-`of` consumption test when `of` was deleted; get_value now carries the read stamp.)
func _test_guard_counts_a_get_value_read_as_consumption() -> void:
	Tune.reset()
	Tune.bind("guard.pull", 1.0)  # get_value requires a prior bind
	Tune.set_value("guard.pull", 2.0)
	var got: Variant = Tune.get_value("guard.pull")  # pull-read after the scrub
	_assert_eq(got, 2.0, "get_value returns the scrubbed override")
	var f := Engine.get_process_frames()
	var flagged := Tune.poll_unconsumed_scrubs(f + 5)
	_assert_true(not flagged.has("guard.pull"),
		"a scrubbed slug re-read via get_value is treated as consumed, not flagged")
