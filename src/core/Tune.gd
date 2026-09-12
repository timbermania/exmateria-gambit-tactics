extends Node

## The tunable registry (ADR-0068). A code value binds to a `slug`; a committed
## override coalesces over the code default (`override ?? default`). The code
## literal at the use-site is the resting source of truth. See the CONTEXT.md
## "Debug tuning" cluster for the vocabulary.

# The in-repo staging file (ADR-0068 decision 4). Sparse: only committed slugs appear.
# NOT user:// — it must travel with the repo. Untracked since 90e593900, so it is now
# MACHINE-scoped: the pins one developer dialed in the F3 panel, on one box.
const OVERRIDE_PATH := "res://config/tune_overrides.json"

# Where the no-argument persistence verbs actually read and write. Empty means THERE IS NO
# STAGING FILE IN THIS PROCESS: the in-memory committed baseline still advances (so the
# dirty marker, Pin and Reset behave exactly as in production), but nothing reaches disk.
# `_ready` empties it for a TEST process — see `_is_test_process`.
var _staging_path := OVERRIDE_PATH

# The GITIGNORED registry snapshot the materialize codemod reads (ADR-0068
# addendum M4) — a regenerated dev artifact (slug -> default/type/persist/
# locations), NOT a source of truth like OVERRIDE_PATH.
const REGISTRY_SNAPSHOT_PATH := "res://config/tune_registry.snapshot.json"

# Source files that are tunable FRAMEWORK, not a use-site: skipped when walking a
# captured stack so the recorded location is the CALLER's line, not ours (M2).
# TuneField.add() forwards to bind(), so it is framework too. UI3Element mints its
# auto-binds from _init/answer() (ADR-0088 §5) — skipping it lands the capture on
# the construction site's `new({...})` spec dict / the widget's `answer(...)` line.
const _FRAMEWORK_SUFFIXES := ["/Tune.gd", "/TuneField.gd", "/UI3Element.gd"]

## How a slug persists — a property of the SLUG (ADR-0068 decision 12), declared at
## its registration use-site (bind / TuneField.add) via an optional param. The three
## classes are ORDERED BY PERSISTENCE STRENGTH (weakest→strongest) so a slug touched by
## more than one use-site settles on the STRONGEST anyone asked for (never silently
## loses persistence someone wanted). TUNABLE is the resting default.
##   EPHEMERAL — never written to disk; the live value is session-only and resets to the
##     code default on reload. For throwaway panel state (command inputs, transient view
##     toggles, data-driven readouts) — white label, no Pin, no dirty marker.
##   TUNABLE   — an edit is a dirty override you Pin to keep (a value you're tuning).
##     Cyan label, Pin/Reset menu, " *" while dialed past the committed baseline.
##   AUTOSAVE  — an edit commits to the staging file in the same gesture, so the value
##     STICKS across reloads with no Pin. Green label, Reset-only menu. Sticky state.
enum Persist { EPHEMERAL, TUNABLE, AUTOSAVE }

# Sentinel for "the caller did not specify a persistence class" — distinct from an
# explicit TUNABLE so a plain bind() with no declared class never overrides a mode an owner declared
# (e.g. a stray read can't downgrade an AUTOSAVE slug, nor upgrade an EPHEMERAL one).
const _PERSIST_UNSPEC := -1

# slug -> live override value. Absent means "use the code default".
var _overrides: Dictionary = {}

# Snapshot of what is persisted in the staging file; a slug is "dirty" when its
# live override differs from this baseline. Kept in sync by commit/load.
var _committed: Dictionary = {}

# slug -> code default, accumulated as bind() use-sites run (ADR-0068
# decision 9). This is what makes the registry ENUMERABLE: a slug is knowable
# only once its use-site has executed, so the generated dashboard iterates this.
# slug -> { "default": <code literal>, "meta": <affordance hint> }. The default is
# the reset target + "vs default"; meta carries range/enum the type can't convey.
var _registry: Dictionary = {}

# R8 "scrub reached nothing" guard state (ADR-0068). A scrub that lands on a slug nothing
# consumes (no on_update subscriber AND no get_value re-read) is a mis-wired bind. We track,
# per slug: the frame of its last scrub, the frame of its last pull-read, and how many live
# on_update subscribers it has — then poll_unconsumed_scrubs() flags the offenders once.
var _last_scrub_frame: Dictionary = {}    # slug -> frame of last set_value
var _last_read_frame: Dictionary = {}     # slug -> frame of last get_value
var _subscriber_count: Dictionary = {}    # slug -> live on_update subscriber count
var _reported_unconsumed: Dictionary = {} # slug -> true once warned (re-armed by a fresh scrub)
# slug -> how many of `_subscriber_count`'s subscribers are DEBUG VIEWS, not consumers.
# `TuneField.build_control` subscribes every row it renders (that is how a control resyncs
# when another surface scrubs the same slug), so a slug with a panel row has a subscriber
# whether or not anything in the game reads it. Counting views separately is what lets
# `consumer_state` subtract them; R8's own `_subscriber_count` test is deliberately left
# alone, because tightening it would light up warnings across the tree (see consumer_state).
var _view_subscriber_count: Dictionary = {}

# Frames a scrub is given to be consumed before it is flagged — a pull consumer (a getter)
# may not re-read on the very frame of the scrub, so a one-frame slack avoids false positives.
const _UNCONSUMED_GRACE_FRAMES := 2

signal value_changed(slug: String, value: Variant)


## Record a slug's code default + affordance hint the FIRST time its use-site runs
## (first-write-wins), so a repeated bind() pays the hint cost once. The default is
## stable per slug, and the hint lives at the use-site (ADR-0068 decision 11).
func _register(slug: String, default_value: Variant, meta: Dictionary = {},
		persist: int = _PERSIST_UNSPEC) -> void:
	if not _registry.has(slug):
		# A brand-new slug with no declared class rests at TUNABLE.
		_registry[slug] = {"default": default_value, "meta": meta,
			"persist": persist if persist != _PERSIST_UNSPEC else Persist.TUNABLE,
			"locations": []}
		# Capture the use-site ONCE, on first registration — the repeat registration
		# path never re-captures (M2). Additional bind() sites append below.
		_record_use_site(slug)
	elif persist != _PERSIST_UNSPEC and persist > _registry[slug].get("persist", Persist.TUNABLE):
		# Strongest-declared wins (persistence-strength order): the code owner's bind()
		# and the panel's TuneField.add() converge no matter which runs first. An unspecified
		# class never changes the mode; a weaker explicit class never downgrades a stronger one.
		_registry[slug]["persist"] = persist


## Append the caller's use-site (file+line) to `slug`'s location list, deduped by
## (file,line) so a repeat never bloats it (M3). Called once per slug from
## _register (first site) and from every bind() (rare — appends 2nd+ sites).
func _record_use_site(slug: String) -> void:
	var site := _capture_use_site()
	if site.is_empty():
		return
	var locs: Array = _registry[slug]["locations"]
	if not locs.has(site):
		locs.append(site)


## The first captured stack frame that is NOT tunable framework — the use-site
## whose default literal materialize rewrites (M2). Empty when get_stack() yields
## nothing (no script debugger, e.g. a release build; materialize is dev-only).
func _capture_use_site() -> Dictionary:
	for frame in get_stack():
		var src := String(frame.get("source", ""))
		if src == "" or _is_framework_source(src):
			continue
		return {"file": src, "line": int(frame.get("line", 0))}
	return {}


func _is_framework_source(src: String) -> bool:
	for suffix: String in _FRAMEWORK_SUFFIXES:
		if src.ends_with(suffix):
			return true
	return false


## The recorded use-site locations for `slug` ([] if none) — where its code
## default literal lives, for the materialize codemod.
func locations_of(slug: String) -> Array:
	var entry: Variant = _registry.get(slug)
	return entry["locations"] if entry != null else []


## Write the live registry to `path` as the materialize bridge (M4): per slug the
## JSON-persistable code default, its TYPE name (JSON collapses int/float/bool to
## one number type, so the codemod needs the type to format the baked literal),
## the persist class (AUTOSAVE slugs are skipped by materialize — decision 10),
## and every captured use-site location. Returns true only when the bytes land.
func dump_registry(path: String = REGISTRY_SNAPSHOT_PATH) -> bool:
	var out: Dictionary = {}
	for slug: String in _registry:
		var entry: Dictionary = _registry[slug]
		out[slug] = {
			"default": _persistable(entry["default"]),
			"type": _type_name(entry["default"]),
			"persist": entry.get("persist", Persist.TUNABLE),
			# The affordance hint travels too: materialize reverses an `enum:` hint's
			# map (+ its enum_tokens prefix) to format an int back to its named-const
			# token (ADR-0088 §5).
			"meta": entry.get("meta", {}),
			"locations": entry.get("locations", []),
		}
	return _write_dict(out, path)


## The GDScript type tag for a code default — how materialize formats the baked
## literal (int->`2`, float->`2.0`, bool->`true`, Color->`Color(...)`).
func _type_name(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL: return "bool"
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "String"
		TYPE_COLOR: return "Color"
		TYPE_VECTOR2: return "Vector2"
		TYPE_VECTOR3: return "Vector3"
		TYPE_VECTOR4: return "Vector4"
		TYPE_RECT2: return "Rect2"
	return "unknown"


## Boot-load the committed overrides into memory BEFORE the scene tree comes up
## (ADR-0068 decision 5). Tune is the first autoload, so every later consumer's
## bind() already sees its override. Missing file = clean slate.
##
## A TEST process gets no staging file at all (see [method _is_test_process]), so for it
## "clean slate" is not a property of the box — it is the boot condition.
func _ready() -> void:
	if _is_test_process():
		_staging_path = ""
	load_overrides()


## The staging file the no-argument verbs use — [constant OVERRIDE_PATH] in the game,
## EMPTY in a test process. Public so a test can assert which side of the seam it is on:
## a leak check that cannot say "the seam fired" is reporting a zero from a blind
## instrument.
func staging_path() -> String:
	return _staging_path


## Is this process running a test scene? Measured off the command line, because that is
## the one thing every invocation form shares: the sequential runner, the parallel runner,
## `scoped_tests.py` and a hand-typed `godot --path . res://tests/X.tscn` all name the
## scene as a positional argument. (Not an env var — ADR-0051 bans those for exactly this
## kind of invisible, shell-scoped configuration.)
##
## THE POINT (godot-learning ADR-0281 / #1149): `OVERRIDE_PATH` is machine state, and a
## test process must not touch it in EITHER direction.
##   * READ — every boot calls `load_overrides()`, so a pin a human dialed in the F3 panel
##     became a silent test input. Four Navigator tests carry a hand-written defence against
##     one slug each ("a session that ticked it in the F3 panel leaves it TRUE ... a walk
##     that stops on every turn does not fail here, it HANGS").
##   * WRITE — an AUTOSAVE TuneField commits on every edit (`TuneField._write`), so a test
##     driving a real debug panel rewrote the repo file MID-RUN and every test booting after
##     it inherited the poison. #1149 measured nine false reds from one such write, and they
##     were attributed to the branch under test, not to the run.
## One seam cuts both directions, which is why this is not a per-test snapshot/restore.
func _is_test_process() -> bool:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("res://tests/"):
			return true
	return false


## R8 guard driver (ADR-0068, dev-only): each frame, warn ONCE for any slug that was scrubbed
## but nothing consumed — a mis-wired `bind` (no `on_update`, and no `get_value` re-read). The
## detection lives in the tested `poll_unconsumed_scrubs`; this is the thin frame-clock driver.
## Gated to debug builds so a shipped game never pays the poll or emits developer warnings.
func _process(_delta: float) -> void:
	if not OS.is_debug_build():
		return
	for slug: String in poll_unconsumed_scrubs(Engine.get_process_frames()):
		push_warning(("[Tune] '%s' was scrubbed but nothing consumed it — no on_update " +
			"subscriber and no get_value re-read since the scrub. Likely a mis-wired bind " +
			"(ADR-0068 R8): wire an on_update, or read the slug via get_value.") % slug)


## Test seam: the total clean slate — forget the live overrides, the committed baseline, the R8
## scrub tracking AND the declarations (does not touch the staging file). Slugs re-register when
## their `bind` use-sites run again. This is what nearly every test calling it wants: registry
## ISOLATION, so one test's binds cannot leak into the next and `_register`'s first-write-wins
## cannot hand a later test an earlier one's default.
##
## ⚠️ It clears something only the OWNERS can rebuild, and for a class-load owner they cannot:
## `_static_init` fires once per class load per process. So a test that calls this and then
## instantiates a production node is asking that node to read an unregistered slug —
## `get_value` asserts on exactly that (R5), and an `on_update` applies a null. **That test wants
## `reset_overrides()` below.** Wanting this and having no way back is what used to force `Tune`
## to hold a list of its owners' script paths and `load()` them again (the deleted
## `register_all()`); see ADR-0173.
func reset() -> void:
	reset_overrides()
	_registry.clear()


## Test seam: forget every live override, the committed baseline and the R8 scrub tracking,
## leaving the DECLARATIONS standing. Everything `reset()` does except the one thing it cannot
## undo.
##
## This is the seam for a test that scrubs and then spawns a REAL production node — the seven
## that used to call `Tune.reset()` followed by `Tune.register_all()`. The replay existed only to
## put back what `reset()` had just cleared, and it could only do that by naming seventeen owner
## script paths across seven of the eleven systems: a `platform` authority enumerating its
## clients, the shape `BLUEPRINT.md` rejects (*"A handle is opaque, so it enumerates nothing"*).
## Not clearing the declarations in the first place makes the list unnecessary rather than
## generic (ADR-0173, #535).
##
## The two resources differ in exactly one way that matters: an OVERRIDE has any number of
## producers (`set_value`, one line, no owner involved), a DECLARATION has one — a `bind` at its
## use-site. So this verb clears the recoverable half and leaves the unrecoverable half alone.
##
## An override may legitimately precede its declaration: that is already the PRODUCTION boot
## order (`_ready` -> `load_overrides()` runs before any owner binds), and `bind` coalesces
## `_overrides.get(slug, literal)` whenever it does run. So scrubbing before the owner spawns
## needs no replay either.
func reset_overrides() -> void:
	_overrides.clear()
	_committed.clear()
	# R8 guard tracking is per-session too — a pre-reset scrub must not leak into the next run.
	_last_scrub_frame.clear()
	_last_read_frame.clear()
	_subscriber_count.clear()
	_view_subscriber_count.clear()
	_reported_unconsumed.clear()



## Coerce a numeric override back to the code default's type — JSON has one number
## type, so a persisted int/enum/bool reloads as a float. Non-numeric types and
## already-matching values pass through untouched.
func _coerce(value: Variant, default_value: Variant) -> Variant:
	match typeof(default_value):
		TYPE_INT:
			if value is float or value is int:
				return int(value)
		TYPE_BOOL:
			if value is bool:
				return value
			if value is float or value is int:
				return bool(value)
		TYPE_FLOAT:
			if value is int or value is float:
				return float(value)
		TYPE_COLOR:
			# A persisted Color reloads from JSON as an [r,g,b,a] array; rebuild it.
			# An already-live Color (set this session, before any save) passes through.
			if value is Color:
				return value
			if value is Array and value.size() >= 3:
				return Color(value[0], value[1], value[2], value[3] if value.size() >= 4 else 1.0)
		TYPE_VECTOR2:
			# A persisted Vector2 reloads from JSON as an [x,y] array; rebuild it. An
			# already-live Vector2 (set this session, before any save) passes through.
			if value is Vector2:
				return value
			if value is Array and value.size() >= 2:
				return Vector2(value[0], value[1])
		TYPE_VECTOR3:
			if value is Vector3:
				return value
			if value is Array and value.size() >= 3:
				return Vector3(value[0], value[1], value[2])
		TYPE_VECTOR4:
			if value is Vector4:
				return value
			if value is Array and value.size() >= 4:
				return Vector4(value[0], value[1], value[2], value[3])
		TYPE_RECT2:
			# A persisted Rect2 reloads from JSON as an [x,y,w,h] array; rebuild it.
			if value is Rect2:
				return value
			if value is Array and value.size() >= 4:
				return Rect2(value[0], value[1], value[2], value[3])
	return value


## The slugs whose use-sites have run this session, sorted for a stable dashboard.
func registered_slugs() -> Array:
	var slugs := _registry.keys()
	slugs.sort()
	return slugs


## Whether `slug` has been registered by a `bind` this session — a cheap O(1) predicate (no
## get_stack, no key sort, unlike `slug in registered_slugs()`). For a use-site that must
## register-once then `get_value` (a hot getter whose default lives at the call, so a boot bind
## list would duplicate it): guard the one-time `bind` with this so the get_stack cost is paid
## once, not per read.
func is_registered(slug: String) -> bool:
	return _registry.has(slug)


## The recorded code default for `slug` (null if the slug's use-site never ran).
## The dashboard's reset target and "vs default" comparison, independent of any
## live override.
func default_of(slug: String) -> Variant:
	var entry: Variant = _registry.get(slug)
	return entry["default"] if entry != null else null


## The recorded affordance hint for `slug` (empty when none was supplied) — the
## range/step/enum-options the dashboard uses to pick and configure the control.
func meta_of(slug: String) -> Dictionary:
	var entry: Variant = _registry.get(slug)
	return entry["meta"] if entry != null else {}


## The persistence mode for `slug` (TUNABLE if its use-site never ran). TuneField
## reads this to pick the label accent color and whether an edit commits immediately
## (AUTOSAVE) or becomes a dirty override to Pin (TUNABLE). See enum Persist.
func persist_of(slug: String) -> int:
	var entry: Variant = _registry.get(slug)
	return entry.get("persist", Persist.TUNABLE) if entry != null else Persist.TUNABLE


## How a slug's value reaches the game, as far as this session has been able to OBSERVE.
## Read-only and non-mutating — unlike `poll_unconsumed_scrubs`, which marks what it reports.
##
## 🔴 THE THREE STATES ARE NOT "yes / maybe / no". Only `UNDECLARED` and `CONSUMED` are
## claims; `DECLARED` is the absence of one. Read them as:
##   UNDECLARED - no `bind` for this slug has run in this PROCESS. The owner's class has
##                never loaded. Confident, and the one state a view can act on.
##   DECLARED   - a `bind` ran, but nothing has been seen to consume the value. This is
##                NOT proof the knob is dead: a pull consumer that reads once at build
##                time and never again is indistinguishable from one that never reads.
##   CONSUMED   - a non-view push subscriber exists, or `get_value` has been called at
##                least once. Monotone: once observed, it stays CONSUMED for the session.
##
## Two things make this weaker than it looks, and both are deliberate rather than fixable:
##
## 1. **It is process-scoped, not scene-scoped.** `_registry` survives a scene change and
##    `reset()` explicitly cannot rebuild a class-load owner's declarations (ADR-0173), so
##    visiting a battle leaves every battlefield slug DECLARED for the rest of the session.
##    A surface reporting this must say "declared", never "active here".
## 2. **It is retrospective.** A slug goes CONSUMED when someone reads it, which for a
##    build-time pull consumer may be long before you look.
##
## Why the R8 counter is not reused as-is: `_subscriber_count` counts the rows a debug panel
## renders (`TuneField.build_control` subscribes each one), so it is true for anything with a
## visible control — self-certifying, and useless as evidence. `_view_subscriber_count` is
## subtracted here. R8's own emptiness test is left counting BOTH on purpose: making it
## stricter would newly warn on every slug whose only subscriber is its panel row, which is a
## separate audit with its own fallout, not a side effect of adding a dashboard page.
enum Consumer { UNDECLARED, DECLARED, CONSUMED }

func consumer_state(slug: String) -> int:
	if not _registry.has(slug):
		return Consumer.UNDECLARED
	var subscribers := int(_subscriber_count.get(slug, 0)) - int(_view_subscriber_count.get(slug, 0))
	if subscribers > 0 or _last_read_frame.has(slug):
		return Consumer.CONSUMED
	return Consumer.DECLARED


## The coalesced value for `slug` WITHOUT stamping the R8 pull-read clock — the read a debug
## VIEW makes to paint itself. `get_value` deliberately records every read as evidence that a
## consumer exists (that is how R8 tells a scrub was picked up); a panel painting its own
## control is not that evidence, and using `get_value` there makes every slug it renders look
## consumed. Same coalescing, same coercion, no telemetry. Returns null for an unbound slug
## rather than asserting, because a view legitimately renders before its owner has booted.
func peek(slug: String) -> Variant:
	if not _registry.has(slug):
		return null
	var default_value: Variant = _registry[slug]["default"]
	return _coerce(_overrides.get(slug, default_value), default_value)


## Scrub a live override for `slug` — what a dashboard control writes. Stores the
## value in its JSON-persistable form (a Color becomes an [r,g,b,a] array) so the
## in-memory override set, the committed baseline, and the on-disk file are all the
## same representation — `is_dirty` compares like-for-like and `get_value` coerces back to
## the typed value on read. Emits value_changed so bound consumers re-apply.
func set_value(slug: String, value: Variant) -> void:
	_overrides[slug] = _persistable(value)
	# R8 guard: stamp this scrub and re-arm the warning so a fresh scrub can flag again.
	_last_scrub_frame[slug] = Engine.get_process_frames()
	_reported_unconsumed.erase(slug)
	value_changed.emit(slug, value)


## R8 guard poll (ADR-0068, dev-only): the slugs newly detected as "scrubbed but nothing
## consumed it" — scrubbed at least _UNCONSUMED_GRACE_FRAMES ago, with no live on_update
## subscriber AND no get_value re-read since the scrub. Each offender is returned ONCE (marked
## reported until re-scrubbed), so `_process` can warn without spamming. `current_frame` is
## injected (Engine.get_process_frames() in `_process`) so the detector is a pure function of
## the tracked state — the seam the guard tests drive with synthetic frames.
func poll_unconsumed_scrubs(current_frame: int) -> PackedStringArray:
	var offenders := PackedStringArray()
	for slug: String in _last_scrub_frame:
		var scrub_frame: int = _last_scrub_frame[slug]
		if current_frame - scrub_frame < _UNCONSUMED_GRACE_FRAMES:
			continue  # still within grace — a pull consumer may not have re-read yet
		if int(_subscriber_count.get(slug, 0)) > 0:
			continue  # a push consumer (on_update) exists
		if int(_last_read_frame.get(slug, -1)) >= scrub_frame:
			continue  # a pull consumer re-read the value at/after the scrub
		if _reported_unconsumed.has(slug):
			continue  # already warned; wait for a fresh scrub to re-arm
		_reported_unconsumed[slug] = true
		offenders.append(slug)
	return offenders


## Reduce a value to a JSON-native form for storage. Color and Vector2/3 have no JSON type,
## so they become plain number arrays ([r,g,b,a] / [x,y] / [x,y,z]); get_value/_coerce rebuild
## the typed value on read. Everything else is already serializable and passes through.
func _persistable(value: Variant) -> Variant:
	if value is Color:
		return [value.r, value.g, value.b, value.a]
	if value is Vector2:
		return [value.x, value.y]
	if value is Vector3:
		return [value.x, value.y, value.z]
	if value is Vector4:
		return [value.x, value.y, value.z, value.w]
	if value is Rect2 or value is Rect2i:
		return [value.position.x, value.position.y, value.size.x, value.size.y]
	return value


## Drop `slug`'s override so a read falls back to the code default. Emits
## value_changed(slug, null) so bound consumers can re-read the default.
func clear(slug: String) -> void:
	if _overrides.erase(slug):
		value_changed.emit(slug, null)


## Resolve a caller's `path` argument: an EMPTY argument means "the default", which is
## [member _staging_path] — itself empty in a test process, where the answer is "there is
## no staging file". An explicit path is always honoured, so the `TuneTest` / `TuneFieldTest`
## temp-file seam is untouched by the test-process redirect.
func _resolve_staging(path: String) -> String:
	return _staging_path if path.is_empty() else path


## Write the current overrides to `path` as JSON (default: the staging
## file). Keys are sorted so the git diff stays stable. Creates the parent
## directory if missing (the real staging path is `res://config/…` and `config/`
## does not exist on a fresh checkout). Returns true only when the bytes reach
## disk, so `commit()` can refuse to mark clean on a failed write.
func save_overrides(path: String = "") -> bool:
	return _write_dict(_persistable_overrides(), _resolve_staging(path))


## The overrides eligible to reach disk: everything EXCEPT EPHEMERAL slugs, whose live
## value is session-only by definition. The single filter the whole-set dump (commit /
## save_overrides) and the per-slug pin (commit_slug) share, so an ephemeral value can
## never leak to the staging file — not even via a "Pin all".
func _persistable_overrides() -> Dictionary:
	var out: Dictionary = {}
	for slug: String in _overrides:
		if persist_of(slug) != Persist.EPHEMERAL:
			out[slug] = _overrides[slug]
	return out


## Serialize `data` to `path` as sorted JSON, creating the parent dir if missing.
## The single write path shared by the whole-set dump (save_overrides / commit) and
## the per-slug pin (commit_slug). Returns true only when the bytes reach disk.
func _write_dict(data: Dictionary, path: String) -> bool:
	# No staging file in this process (a test) — the write SUCCEEDS having written nothing,
	# so the caller's in-memory baseline still advances and Pin/Reset/dirty are unchanged.
	if path.is_empty():
		return true
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		if DirAccess.make_dir_recursive_absolute(dir) != OK:
			push_warning("[Tune] cannot create override dir %s" % dir)
			return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("[Tune] cannot write overrides to %s" % path)
		return false
	f.store_string(JSON.stringify(data, "\t", true))
	f.close()
	return true


## Load overrides from `path`, replacing the live set. A missing file is a no-op
## (nothing committed yet).
func load_overrides(path: String = "") -> void:
	path = _resolve_staging(path)
	if path.is_empty() or not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_overrides = parsed
		_committed = _overrides.duplicate()  # loaded == the committed baseline
	else:
		push_warning("[Tune] override file %s is not a JSON object" % path)


## Read `path` as a slug->value dictionary WITHOUT touching live state — the read half of
## [method _write_dict], used by [method commit_slug] to seed "prior pins" from the file
## itself. Returns [param fallback] when the file is missing, unopenable, or not a JSON
## object, so a first-ever write and a corrupt file both behave as they did before #614.
func _read_dict(path: String, fallback: Dictionary) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return fallback.duplicate()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fallback.duplicate()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else fallback.duplicate()


## True when `slug`'s live value differs from what is committed to the staging
## file — dialed past the saved baseline, not yet re-committed.
func is_dirty(slug: String) -> bool:
	return _overrides.get(slug) != _committed.get(slug)


## Persist the current overrides to `path` and mark them the new clean baseline.
## Updates the committed baseline ONLY when the write succeeds, so a slug whose
## override never reached disk stays dirty (never a silent false "saved").
## Returns whether the commit persisted.
func commit(path: String = "") -> bool:
	if not save_overrides(_resolve_staging(path)):
		return false
	_committed = _persistable_overrides()  # the baseline is what actually reached disk
	return true


## Pin a SINGLE slug's live value into the staging file (the per-field "pin"
## gesture, ADR-0068 decision 7) — persisting the committed set (prior pins + this
## slug) and nothing else, so dialed-but-unpinned slugs are never blanket-saved.
## Pinning a slug that has no live override (e.g. right after Reset) un-pins it: the
## slug drops out of the file. The committed baseline advances ONLY on a successful
## write, so a failed write leaves the slug dirty — never a silent false "saved".
##
## [b]"Prior pins" is read from the FILE, not from [member _committed] (#614).[/b] The two
## are supposed to be the same thing, and `_committed`'s whole job is to be a mirror of what
## is on disk — but [method reset] clears the mirror and deliberately does NOT touch the
## file, so between a `reset()` and the next `load_overrides()` the mirror says "nothing is
## pinned" while the file holds everything. Seeding from the mirror there made pinning ONE
## slug delete every other pin in the file: `TileOverlayConfigTuneTest` drives a real
## `TilesDebugPanel`, whose `tile.selected_type` is AUTOSAVE, so the edit committed — and the
## tracked `config/tune_overrides.json` went from ten entries to one, taking a deliberate
## `scenario.active_id` pick with it. `git status` showed a modified file and nothing said a
## test had done it.
##
## Reading the file makes the repair independent of HOW the mirror went stale — a `reset()`,
## a hand edit, another process — and it is what "prior pins" literally means. The fallback
## when the file is absent or unparseable is the mirror, which is the old behaviour and is
## correct for a first-ever write.
##
## [method commit] is deliberately NOT changed. It is the whole-set dump ("Pin all"), so it
## writes exactly the live persistable set — that is what lets a Reset followed by a commit
## UN-pin a slug. Seeding it from disk would make removal impossible.
func commit_slug(slug: String, path: String = "") -> bool:
	# An EPHEMERAL slug is never persisted — pinning it is a no-op (nothing to save).
	if persist_of(slug) == Persist.EPHEMERAL:
		return true
	path = _resolve_staging(path)
	var next: Dictionary = _read_dict(path, _committed)
	if _overrides.has(slug):
		next[slug] = _overrides[slug]
	else:
		next.erase(slug)
	if not _write_dict(next, path):
		return false
	_committed = next
	return true


## Attach `slug` to exactly one `literal` — and nothing else (ADR-0068 R2). The
## registry entry + emitter: no owner, no callback. ONE slug ↔ one bound literal is the
## invariant that makes conflicts impossible and materialize unambiguous, and that keeps
## the panel/materialize surface PURE literals (they enumerate binds, never reason about
## behavior). A `bind` alone is INERT to scrubbing (R3): it makes a value enumerable +
## materializable, but a scrub reaches the screen only once a matching `update` exists.
## Returns the coalesced value as a convenience for a caller seeding a static-var home;
## registration is the job. The `literal` must be inline or a static-var reference, never
## a wrapper-forwarded parameter (M5) — that was the original materialize pain.
func bind(slug: String, literal: Variant, meta: Dictionary = {},
		persist: int = _PERSIST_UNSPEC) -> Variant:
	_register(slug, literal, meta, persist)
	# Record every distinct use-site (deduped by file+line) so a slug bound from more than
	# one site materializes each (M3). _register already recorded the first; this appends
	# a 2nd+ site and is a dedup no-op on the first.
	_record_use_site(slug)
	return _coerce(_overrides.get(slug, literal), literal)


## The PULL-read (ADR-0068 R5): the coalesced value (override ?? registered default) for a
## slug ALREADY registered by a `bind`, read cheaply on demand — NO use-site capture, NO
## registration (unlike the retired `of`, so it is safe in a hot getter / per-frame read).
## This is the read-in-place counterpart to `on_update`'s push: for consumers that re-read on
## their own (a computed `get:` property, a `_process` read, a one-shot `_ready` read), where a
## standing subscription would be pointless (they pick up the new value next time they run) or
## wrong (a one-shot read wants no permanent wire). Asserts the slug was bound — a read before
## its `bind` is a wiring bug (nothing declared the default), not a silent null.
func get_value(slug: String) -> Variant:
	assert(_registry.has(slug),
		"[Tune] get_value(%s) before its bind — a read requires a prior bind() (R5)" % slug)
	# R8 guard: stamp this pull-read so a scrub this consumer re-reads is counted as consumed.
	_last_read_frame[slug] = Engine.get_process_frames()
	var default_value: Variant = _registry[slug]["default"] if _registry.has(slug) else null
	return _coerce(_overrides.get(slug, default_value), default_value)


## Subscribe to `slug`: run `apply` with the coalesced value NOW and again on every change,
## owner-scoped so it auto-drops when `owner` leaves the tree (ADR-0068 R3 — the "local"
## that the old `bind_local` misnamed lives HERE, on the on_update, not the bind). The `on_`
## prefix marks it an event hook (the handler runs ON each change), not an imperative. Added
## as-needed for debugging: add one when you actually want a value to respond to live
## scrubbing. `slug` must already be registered by a `bind` — `on_update` carries no literal,
## it reads the registered default to coalesce. Two shapes: a WRITE-BACK (`func(v):
## Owner.some_static_var = v`) that lands a scrub on a static var's direct readers, and a
## RE-DERIVATION for any consumer that cached a derived value (R4 — recompute end-to-end
## from the tuned base). This is PUSH — for a passive sink that will not re-read on its own
## (a shader global, a built mesh); a consumer that re-reads itself uses `get_value` instead.
##
## The registered default is CAPTURED at subscribe-time into the handler closure (it is
## stable per slug — first-write-wins), so a live on_update keeps applying its own default
## even if the registry is later cleared AFTER this call (the `reset()` test seam). That
## immunity is one-directional and the ORDER is the whole of it: a clear that lands BEFORE
## the subscribe leaves nothing to capture, and this used to apply a null for it — silently,
## because unlike [method get_value] there was no assert. #585 is what that cost: tests
## called `Tune.reset()` without replaying [method register_all], so a `_static_init`
## owner's slugs were gone by spawn time; the typed `apply` lambda threw *"Cannot convert
## argument 1 from Nil to float"*, the write-back never landed, and the read-back returned
## the declared default. Six arms failed that way across `Cursor`, `ScenarioDialogueBox`
## and `ScenarioWeather` — three subsystems whose only shared component is this function.
##
## [b]The count is not the interesting part; the SILENCE is.[/b] Sweeping all 31 tests that
## call `reset()` with this assert in place turned up four MORE on the same defect that no
## verdict line had ever reported: `ScenarioCinematic` and `UnitForward` were failing arms
## the null had been hiding, and `CameraFeel` and `VitalsLayout` printed `[PASS]` while
## raising the `get_value` half of it — `CameraFeel` **5322 times in one run**. A test that
## passes through thousands of script errors is describing a tree nobody measured.
## `as_view` marks a subscription that exists only to REDRAW A DEBUG CONTROL — pass true
## from a panel/registry row, never from a consumer that acts on the value. It does not
## change the subscription's behaviour at all; it only keeps `consumer_state` from reading
## a rendered row as evidence that something consumes the slug.
func on_update(owner: Node, slug: String, apply: Callable, as_view: bool = false) -> void:
	assert(_registry.has(slug),
		"[Tune] on_update(%s) before its bind — a subscribe requires a prior bind() (R3). "
		% slug + "A test that reset() and then spawned this owner wants reset_overrides() (ADR-0173).")
	var default_value: Variant = _registry[slug]["default"] if _registry.has(slug) else null
	apply.call(_coerce(_overrides.get(slug, default_value), default_value))
	# The owner's ID and not the owner: a lambda that CAPTURED the node would log
	# "Lambda capture at index N was freed" on every post-free emit before its body could
	# decline the call — the check runs at call time, ahead of the first statement. An int
	# is invisible to it.
	var owner_id := owner.get_instance_id()
	var handler := func(changed_slug: String, _value: Variant) -> void:
		# The re-entrancy-during-emit ordering hazard: value_changed snapshots its connection
		# list before invoking handlers, so if an EARLIER handler frees THIS subscriber's owner
		# (a panel rebuild, a page swap), the owner's tree_exited disconnect cannot take this
		# handler out of the in-flight emit. Exactly one more apply runs against a dead owner —
		# the NEXT emit is already clean, which is why this reads as a one-shot mystery error.
		#
		# The live question is the OWNER's, and `apply.is_valid()` answers a DIFFERENT one:
		# it is false only for a Callable bound to a freed script instance. A lambda made in a
		# `static func` — every row `TuneField` builds — is bound to nothing at all, so it stays
		# valid forever while its captures are silently swapped for null, and the call lands
		# downstream as "on a base object of type 'Nil'" (the dirty-marker write in
		# `TuneField._refresh_marker`). Both gates stay: an apply bound to some object OTHER
		# than the owner can die while the owner lives.
		#
		# Skipping is safe either way: the owner is gone and its tree_exited already dropped the
		# subscription, so no future emit reaches it.
		if changed_slug == slug and is_instance_id_valid(owner_id) and apply.is_valid():
			apply.call(_coerce(_overrides.get(slug, default_value), default_value))
	value_changed.connect(handler)
	# R8 guard: this slug now has a live push consumer, so a scrub on it reaches game state.
	_subscriber_count[slug] = int(_subscriber_count.get(slug, 0)) + 1
	if as_view:
		_view_subscriber_count[slug] = int(_view_subscriber_count.get(slug, 0)) + 1
	owner.tree_exited.connect(func() -> void:
		if value_changed.is_connected(handler):
			value_changed.disconnect(handler)
			_subscriber_count[slug] = maxi(0, int(_subscriber_count.get(slug, 0)) - 1)
			if as_view:
				_view_subscriber_count[slug] = maxi(0, int(_view_subscriber_count.get(slug, 0)) - 1))


## Sugar = `bind` + one paired `on_update` (ADR-0068 R3.5): attach `slug` to
## its inline `literal` AND subscribe one owner-scoped `apply` that lands the coalesced
## value now and on every change, until `owner` leaves the tree. For the co-located
## single set-once consumer (the `mesh.scale = v` shape) — it states the slug ONCE. The
## `literal` must be inline at the call, never forwarded through a wrapper. Drop to
## separate `bind` + `on_update`(s) when the literal is a `static var` home (direct readers)
## or when updates are added as-needed later. The optional `meta` is the same affordance
## hint bind takes (decision 11); recorded before the first apply so the dashboard has it.
func bind_update(owner: Node, slug: String, literal: Variant, apply: Callable,
		meta: Dictionary = {}, persist: int = _PERSIST_UNSPEC, as_view: bool = false) -> void:
	bind(slug, literal, meta, persist)
	on_update(owner, slug, apply, as_view)
