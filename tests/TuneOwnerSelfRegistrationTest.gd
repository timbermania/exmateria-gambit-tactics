extends Node
## Guard for ADR-0173 (#535): every tunable owner registers ITSELF at its own boot path, and
## `Tune.reset()` leaves those declarations standing. This is the runtime half of the pair that
## replaced `Tune.register_all()`; the static half is
## `tools/check_tune_owner_self_registration.py`.
##
## THIS TEST NAMES NO OWNER AND NO SLUG, and that is the point. The thing it replaced —
## `tests/TuneRegisterAllTest.gd` — mirrored `register_all()`'s manifest row for row, which made
## it a SECOND hardcoded copy of the same seventeen paths (#551 found exactly that: the act of
## measuring had added to the thing measured). With the list deleted there is nothing to mirror,
## so the owner set is DISCOVERED: a walk for `static func register_tunables()` over `res://src`
## and `res://addons`, plus the autoloads `project.godot` declares. Each owner's slug set is then
## derived by CALLING its entry point on a cleared registry and reading back what appeared.
##
## Three phases, so no arm is vacuous:
##   1. BOOT. Load every discovered owner and snapshot the registry. This is what class load
##      alone (`_static_init`) and autoload `_ready` produced — no replay was called, because
##      there is no longer anything to call.
##   2. OWNERSHIP. Per owner: clear the registry, call its `register_tunables()`, read back the
##      slugs it binds — that is its slug set, as data. Assert it is non-empty (an owner that
##      binds nothing is a boot path that does nothing), and assert every one of those slugs was
##      already in phase 1's snapshot. That second assertion is the claim: the owner's OWN boot
##      path put them there.
##   3. CONTRACT. `Tune.reset_overrides()` must leave the declarations standing while clearing
##      the overrides, and the total `Tune.reset()` must take them away. That split is the whole
##      reason no central replay is needed (ADR-0173); if `reset_overrides()` ever starts
##      clearing declarations, `register_all()` has to come back, and this is the arm that says
##      so first.
##
## Reads `.gd` source at run time, so it runs from a source tree (which is where the suite runs),
## not from an exported PCK.
##
## Run: <GODOT> --path . --quit-after 6 res://tests/TuneOwnerSelfRegistrationTest.tscn

# Anti-vacuity floors. A discovery walk that silently finds nothing passes every per-owner
# assertion for free, so the count is asserted before the owners are. These are FLOORS, not a
# manifest — they say "the walk worked", not "these are the owners" (13 static + 4 autoload when
# ADR-0173 was written). A legitimate drop below them is a conversation, not a bump.
const _MIN_SCRIPT_OWNERS := 10
# 🔴 WAS 3, AND 3 WAS A CENSUS OF A TREE THAT MOVED. These floors exist to catch a discovery
# walk that finds NOTHING — a `_SCAN_ROOTS` typo, a renamed `_OWNER_DECL` — not to pin a
# population. Set at 3 when `SkirtConfig` and `TileOverlayConfig` were autoloads; #564
# (ADR-0183) turned both into `class_name`s precisely because an addon cannot publish an
# autoload, which took the real count to 2 and made this arm fail for being RIGHT. The
# discovery this test is built on names no owner; a floor that counts them re-introduces the
# hardcoded population it exists to avoid, so it is now the smallest number that still
# distinguishes "discovered some" from "discovered none".
const _MIN_AUTOLOAD_OWNERS := 1

const _SCAN_ROOTS := ["res://src", "res://addons"]
# The class-load owner shape: static, zero-arg. An INSTANCE register_tunables is a scene-scoped
# owner that registers in its own _ready (EffectViewerScene), and an ARG-TAKING one is called with
# its owner Node (SequenceThumbnail) — neither is a class-load owner, and S4 of the static guard
# is what keeps the arg-taking one from being mechanically "fixed" into this shape.
const _OWNER_DECL := "static func register_tunables() -> void:"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	var script_paths := _discover_script_owners()
	var autoload_paths := _discover_autoload_owners()
	print("[discovery] %d class-load owner(s), %d autoload owner(s)"
		% [script_paths.size(), autoload_paths.size()])
	_assert_true(script_paths.size() >= _MIN_SCRIPT_OWNERS,
		"the walk found at least %d class-load owners (got %d)"
			% [_MIN_SCRIPT_OWNERS, script_paths.size()])
	_assert_true(autoload_paths.size() >= _MIN_AUTOLOAD_OWNERS,
		"project.godot declares at least %d autoload owners (got %d)"
			% [_MIN_AUTOLOAD_OWNERS, autoload_paths.size()])

	# --- Phase 1: BOOT ---------------------------------------------------------------------
	# Load every owner. A first class load runs _static_init; an already-loaded one is a no-op
	# and its slugs are in the snapshot anyway. Nothing replays, and no reset has run yet, so
	# what is in the registry after this is exactly what the owners' own boot paths put there.
	var scripts: Dictionary = {}
	for path: String in script_paths:
		var owner_script := load(path) as GDScript
		_assert_true(owner_script != null, "%s loads" % path)
		if owner_script != null:
			scripts[path] = owner_script
	var boot_slugs := {}
	for slug: String in Tune.registered_slugs():
		boot_slugs[slug] = true

	# --- Phase 2: OWNERSHIP ----------------------------------------------------------------
	var owned_by: Dictionary = {}
	for path: String in scripts:
		owned_by[path] = _slugs_bound_by(func() -> void: scripts[path].register_tunables())
	for node_path: String in autoload_paths:
		var node := get_node_or_null(node_path)
		_assert_true(node != null, "%s is up" % node_path)
		if node != null:
			owned_by[node_path] = _slugs_bound_by(func() -> void: node.register_tunables())

	for path: String in owned_by:
		var owned: Array = owned_by[path]
		_assert_true(owned.size() > 0, "%s binds at least one slug" % path)
		for slug: String in owned:
			_assert_true(boot_slugs.has(slug),
				"%s is registered by %s's OWN boot path, with no replay" % [slug, path])

	# --- Phase 3: CONTRACT -----------------------------------------------------------------
	# Rebuild a full registry by hand (phase 2 left only the last owner's slugs standing), then
	# hold reset_overrides() and reset() to their split.
	Tune.reset()
	for path: String in scripts:
		scripts[path].register_tunables()
	for node_path: String in autoload_paths:
		var node := get_node_or_null(node_path)
		if node != null:
			node.register_tunables()
	var declared := Tune.registered_slugs()
	_assert_true(declared.size() > 0, "the rebuilt registry is non-empty")

	# An override on a real slug, so the "reset() clears overrides" arm is not tested on a
	# slug nobody declared.
	var probe: String = declared[0]
	var probe_default: Variant = Tune.default_of(probe)
	Tune.set_value(probe, _some_other_value(probe_default))

	Tune.reset_overrides()
	_assert_eq(Tune.registered_slugs(), declared,
		"reset_overrides() leaves EVERY declaration standing (this is what deleted register_all())")
	_assert_eq(Tune.get_value(probe), probe_default, "reset_overrides() still clears the overrides")

	Tune.reset()
	_assert_eq(Tune.registered_slugs(), [], "the total reset() clears the declarations")

	print("\n=== TuneOwnerSelfRegistrationTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TuneOwnerSelfRegistrationTest")
		get_tree().quit(1)
	else:
		print("[PASS] TuneOwnerSelfRegistrationTest")
		get_tree().quit(0)


## The slugs `register` binds, read back off a cleared registry — an owner's slug set as DATA,
## so nothing here has to name one.
func _slugs_bound_by(register: Callable) -> Array:
	Tune.reset()
	register.call()
	return Tune.registered_slugs()


## Any value that differs from `v`, so `set_value` provably moves the read off the default.
func _some_other_value(v: Variant) -> Variant:
	match typeof(v):
		TYPE_BOOL: return not v
		TYPE_INT: return int(v) + 1
		TYPE_FLOAT: return float(v) + 1.0
		TYPE_STRING: return String(v) + "_x"
	return v


## Every `res://` script under the scan roots declaring the class-load owner shape.
func _discover_script_owners() -> Array:
	var out: Array = []
	for root: String in _SCAN_ROOTS:
		_walk(root, out)
	out.sort()
	return out


func _walk(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				_walk(full, out)
		elif name.ends_with(".gd"):
			if FileAccess.get_file_as_string(full).contains(_OWNER_DECL):
				out.append(full)
		name = d.get_next()
	d.list_dir_end()


## The autoloads `project.godot` declares whose live singleton exposes register_tunables(). Read
## off ProjectSettings rather than a list here, for the same reason as the script walk.
func _discover_autoload_owners() -> Array:
	var out: Array = []
	for prop: Dictionary in ProjectSettings.get_property_list():
		var key: String = String(prop.get("name", ""))
		if not key.begins_with("autoload/"):
			continue
		var node_path := "/root/" + key.substr("autoload/".length())
		var node := get_node_or_null(node_path)
		if node != null and node.has_method("register_tunables"):
			out.append(node_path)
	out.sort()
	return out


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])
