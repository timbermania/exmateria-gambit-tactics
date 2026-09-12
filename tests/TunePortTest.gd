extends Node

## Guard (#588, ADR-0175 dec. 2): the two PORT FAÇADES the battlefield addon names
## instead of the host's autoloads — `TunePort` and `DisplayPort`.
##
## The re-point itself is enforced statically: `check_addon_portability.py` arm 2
## loses its 78 standalone-parse rows and arm 5 gains them as a counted platform
## dependency, so re-adding a bare `Tune.` inside an addon moves both numbers. What
## no static guard can see is the half this file exists for — **what the façade does
## when the port is NOT THERE**, which is the only state the whole re-point was for
## and the one state no scene in this repo boots in.
##
## The absent case is manufactured by RENAMING the autoload node and dropping the
## façade's resolution cache (`_forget_port`). That is a truthful simulation of the
## thing being tested: `_resolve()` is a `get_node_or_null` against a name, and a
## consuming project without the `[autoload]` line differs from this one in exactly
## that lookup failing. Both façades are restored before the run ends.
##
## 🔴 Every fallback assertion uses a SENTINEL that the registry cannot produce, not
## the value the slug is actually bound to. Asserting `get_value(slug, X) == X` when
## the registry ALSO holds `X` is an arm that cannot fail — this pass shipped one of
## those before seeding caught it.
##
## Run: <GODOT> --path . --quit-after 5 res://tests/TunePortTest.tscn

## ADR-0212 dec. 1 — `addons/exmateria_platform` used to declare `DisplayPort`
## (the name of a hardware standard), `PsxNum` and `TunePort` as bare globals. It
## now declares only `ExMateriaPlatform`; aliasing them back keeps every use site
## below spelled the way it was (ADR-0211 dec. 4).
const DisplayPort = ExMateriaPlatform.DisplayPort
const TunePort = ExMateriaPlatform.TunePort
const EventPort = ExMateriaPlatform.EventPort

const SLUG := "tuneport.probe"
const BOUND := 3.0
## Deliberately unequal to BOUND, and to every value this file ever writes.
const SENTINEL := -77.25

var _failed := 0
var _passed := 0
var _applied: Array = []
var _hp_beats := 0
var _mp_beats := 0
var _par_beats := 0
var _saw_any_change := 0


func _ready() -> void:
	_test_present_bind_and_read()
	_test_present_push_verbs()
	_test_present_display_port_matches_the_autoload()

	_test_present_event_port()

	_test_absent_tune_port()
	_test_absent_display_port()
	_test_absent_event_port()

	_test_the_port_recovers_after_the_autoload_returns()
	_test_an_absent_bind_is_replayed_when_the_port_returns()
	_test_the_boot_pass_registered_the_addon_owners()

	Tune.clear(SLUG)

	print("\n=== TunePortTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] TunePortTest")
		get_tree().quit(1)
	else:
		print("[PASS] TunePortTest")
		get_tree().quit(0)


# --- port PRESENT -------------------------------------------------------------

## `bind` registers on the real singleton and returns the coalesced value; the
## matching `get_value` reads the REGISTRY and ignores the fallback it was handed.
func _test_present_bind_and_read() -> void:
	var returned = TunePort.bind(SLUG, BOUND)
	_assert_approx(returned, BOUND, "bind returns the coalesced value")
	_assert_true(Tune.is_registered(SLUG), "bind reached the singleton's registry")
	_assert_approx(TunePort.get_value(SLUG, SENTINEL), BOUND,
		"get_value reads the registry, not the fallback")

	TunePort.set_value(SLUG, 9.5)
	_assert_approx(TunePort.get_value(SLUG, SENTINEL), 9.5,
		"set_value lands an override the port reads back")
	_assert_approx(float(Tune.get_value(SLUG)), 9.5,
		"the override is on the singleton, not a façade-local copy")


## `on_update` applies now and again on change; `on_any_change` bridges the whole
## signal and reports that it connected.
func _test_present_push_verbs() -> void:
	_applied.clear()
	TunePort.on_update(self, SLUG, func(v): _applied.append(v))
	_assert_eq(_applied.size(), 1, "on_update applies once immediately")
	TunePort.set_value(SLUG, 4.25)
	_assert_eq(_applied.size(), 2, "on_update re-applies on change")
	_assert_approx(_applied[1], 4.25, "on_update carries the new value")

	_saw_any_change = 0
	var connected := TunePort.on_any_change(func(s: String, _v):
		if s == SLUG:
			_saw_any_change += 1)
	_assert_true(connected, "on_any_change reports the bridge landed")
	TunePort.set_value(SLUG, 5.5)
	_assert_eq(_saw_any_change, 1, "on_any_change sees the write")


## The display façade is a pass-through while its autoload is up — asserted against
## the autoload itself so a façade that quietly returned its own constant fails.
func _test_present_display_port_matches_the_autoload() -> void:
	_assert_approx(DisplayPort.live_fx_stretch(), PSXDisplay.live_fx_stretch,
		"live_fx_stretch forwards to the port")
	_assert_approx(DisplayPort.live_cursor_stretch(), PSXDisplay.live_cursor_stretch,
		"live_cursor_stretch forwards to the port")
	var before: int = PSXDisplay.live_camera_angle
	var probe: int = 0x321 if before != 0x321 else 0x123
	DisplayPort.set_camera_angle(probe)
	_assert_eq(PSXDisplay.live_camera_angle, probe,
		"set_camera_angle drives the port's mirror")
	# The READ half, added by #848 (ADR-0234). #590 put the PUSH on this port and
	# left its mirror reachable only as a property on the autoload, which no addon
	# can name — so the sprite rig went on naming `PSXDisplay` and did not parse in
	# a stranger project. Asserted against the autoload, like the two above, so a
	# façade that returned its own cached value fails.
	_assert_eq(DisplayPort.live_camera_angle(), PSXDisplay.live_camera_angle,
		"live_camera_angle forwards to the port")
	DisplayPort.set_camera_angle(before)

	# The UI PAR pair, added by #1263. The seven UI3 members that read
	# `PSXDisplay.live_ui_par` and subscribed to `live_ui_par_changed` could name no
	# autoload at all once they move into the addon (ADR-0308) — so the read AND the
	# subscription both had to come through here. Asserted against the autoload so a
	# port answering from its own cache fails.
	_assert_approx(DisplayPort.live_ui_par(), PSXDisplay.live_ui_par,
		"live_ui_par forwards to the port")
	var par_before: float = PSXDisplay.live_ui_par
	_par_beats = 0
	_assert_true(DisplayPort.connect_live_ui_par_changed(_on_probe_par),
		"bound: the PAR subscription reports it wired")
	PSXDisplay.live_ui_par = 1.6
	# The RETURN VALUE is not the claim — a port that answered `true` and wired
	# nothing would pass an arm that only read the boolean. The beat is the claim.
	_assert_eq(_par_beats, 1, "bound: the PAR subscription actually received the beat")
	_assert_approx(DisplayPort.live_ui_par(), 1.6,
		"bound: and the read half sees the new value")
	_par_beats = 0
	_assert_true(DisplayPort.connect_live_ui_par_changed(_on_probe_par),
		"bound: a second connect is idempotent, not an error")
	PSXDisplay.live_ui_par = 1.7
	_assert_eq(_par_beats, 1, "bound: and did NOT double-subscribe")
	PSXDisplay.live_ui_par = par_before
	Tune.clear("render.ui_pixel_aspect")


# --- port ABSENT --------------------------------------------------------------

## With no `Tune` in the tree: every read answers with the caller's fallback, every
## registration verb declines to register, and `bind_update` — the one verb that
## carries the literal at the call — still applies it once.
func _test_absent_tune_port() -> void:
	var node := get_tree().root.get_node_or_null(^"Tune")
	if node == null:
		_fail("the Tune autoload is not in this tree — the absent arm cannot run")
		return
	node.name = "Tune_absent_probe"
	TunePort._forget_port()

	_assert_approx(TunePort.get_value(SLUG, SENTINEL), SENTINEL,
		"absent: get_value answers with the fallback")

	var fresh := "tuneport.never_bound"
	_assert_approx(TunePort.bind(fresh, 12.0), 12.0,
		"absent: bind returns its literal")
	_assert_true(not Tune.is_registered(fresh),
		"absent: bind did NOT reach the registry")

	_applied.clear()
	TunePort.on_update(self, SLUG, func(v): _applied.append(v))
	_assert_eq(_applied.size(), 0,
		"absent: on_update is a no-op — it carries no literal to apply")

	TunePort.bind_update(self, fresh, 12.0, func(v): _applied.append(v))
	_assert_eq(_applied.size(), 1, "absent: bind_update applies its literal once")
	# Guarded: a failed size assertion must not turn the next line into a SCRIPT
	# ERROR — a throw inside a test is invisible to the verdict line and shows up
	# only in a `SCRIPT ERROR` grep over the whole run.
	_assert_approx(_applied[0] if not _applied.is_empty() else null, 12.0,
		"absent: and applies the literal itself")

	_saw_any_change = 0
	_assert_true(not TunePort.on_any_change(func(_s, _v): _saw_any_change += 1),
		"absent: on_any_change reports no bridge")

	TunePort.set_value(SLUG, 99.0)
	node.name = "Tune"
	TunePort._forget_port()
	_assert_approx(TunePort.get_value(SLUG, SENTINEL), 5.5,
		"absent: set_value wrote nothing — the pre-absence override still stands")


## Same shape for the display half. `live_fx_stretch` is 1.0 in this project's own
## `project.godot`, so the arm is only meaningful if the autoload is holding a
## DIFFERENT value while it is up — pushed here, and restored after.
func _test_absent_display_port() -> void:
	var node := get_tree().root.get_node_or_null(^"PSXDisplay")
	if node == null:
		_fail("the PSXDisplay autoload is not in this tree — the absent arm cannot run")
		return
	var boot: float = PSXDisplay.live_fx_stretch
	PSXDisplay.live_fx_stretch = 1.75
	_assert_approx(DisplayPort.live_fx_stretch(), 1.75,
		"the seed moved the value the absent arm has to disagree with")

	# `live_ui_par` RUNS AT 1.0, which is exactly `NO_STRETCH` — so asserting the
	# identity after the port goes away is VACUOUS unless the seed moves it first.
	# (#1263; the same trap this file's SENTINEL rule names for the Tune slugs.)
	var boot_par: float = PSXDisplay.live_ui_par
	PSXDisplay.live_ui_par = 1.9
	_assert_approx(DisplayPort.live_ui_par(), 1.9,
		"the seed moved the PAR the absent arm has to disagree with")

	var boot_angle: int = PSXDisplay.live_camera_angle
	DisplayPort.set_camera_angle(0x555)
	_assert_eq(DisplayPort.live_camera_angle(), 0x555,
		"the seed moved the angle the absent arm has to disagree with")

	node.name = "PSXDisplay_absent_probe"
	DisplayPort._forget_port()
	_assert_approx(DisplayPort.live_fx_stretch(), DisplayPort.NO_STRETCH,
		"absent: live_fx_stretch answers with the identity, not the last value")
	_assert_approx(DisplayPort.live_cursor_stretch(), DisplayPort.NO_STRETCH,
		"absent: live_cursor_stretch answers with the identity")
	_assert_approx(DisplayPort.live_ui_par(), DisplayPort.NO_STRETCH,
		"absent: live_ui_par answers with the identity, not the seeded 1.9")
	_assert_eq(DisplayPort.connect_live_ui_par_changed(_on_probe_par), false,
		"absent: connect_live_ui_par_changed reports NOT live rather than raising")
	var mirror: int = PSXDisplay.live_camera_angle
	DisplayPort.set_camera_angle(0x7FF)
	_assert_eq(PSXDisplay.live_camera_angle, mirror,
		"absent: set_camera_angle wrote nothing")
	# 0 is the autoload's own boot value for the mirror and the fallback
	# `CameraRelativeRenderer` already spelled before the verb existed — an absent
	# calibration puts every unit on the baseline pose octant (#848, ADR-0234).
	# The seed above is what makes this arm able to fail: without it the mirror
	# would already read 0 and the assertion would be vacuous.
	_assert_eq(DisplayPort.live_camera_angle(), 0,
		"absent: live_camera_angle answers 0, not the last value it held")

	node.name = "PSXDisplay"
	DisplayPort._forget_port()
	DisplayPort.set_camera_angle(boot_angle)
	PSXDisplay.live_fx_stretch = boot
	PSXDisplay.live_ui_par = boot_par
	Tune.clear("render.psx_fx_stretch")
	Tune.clear("render.ui_pixel_aspect")


## The cache never holds a NEGATIVE resolution: a port that appears after a failed
## lookup must be found. Without this, a `_static_init` that runs before the
## autoload is up would poison every later call for the whole session.
func _test_the_port_recovers_after_the_autoload_returns() -> void:
	_assert_approx(TunePort.get_value(SLUG, SENTINEL), 5.5,
		"the port re-resolved after its node came back")
	_assert_approx(DisplayPort.live_fx_stretch(), PSXDisplay.live_fx_stretch,
		"the display port re-resolved too")


# --- the boot order -----------------------------------------------------------

## A declaration that lands while the port is absent is REMEMBERED and replayed the
## moment the port resolves — the half of `bind`'s absent behaviour that no other arm
## in this file covers, and the one the boot depends on (see the arm below).
##
## The absent state is manufactured the same way as `_test_absent_tune_port`: rename
## the autoload, drop the resolution cache. Three things have to be true and only the
## middle one was before the queue existed — the call still answers with its literal,
## the dropped declaration is RECORDED (a swallowed drop and a recorded one both read
## as "not registered"), and it lands with its own literal and hint when the port is
## back.
func _test_an_absent_bind_is_replayed_when_the_port_returns() -> void:
	var node := get_tree().root.get_node_or_null(^"Tune")
	if node == null:
		_fail("the Tune autoload is not in this tree — the replay arm cannot run")
		return
	var slug := "tuneport.deferred_probe"
	_assert_true(not Tune.is_registered(slug), "the replay probe starts unregistered")

	node.name = "Tune_absent_probe"
	TunePort._forget_port()
	var before := TunePort.deferred_count()
	_assert_approx(TunePort.bind(slug, BOUND, {"min": 0.0, "max": 9.0}), BOUND,
		"absent: a deferred bind still answers with its literal")
	# Same slug, a literal it must NOT come back with: the registry's rule for a slug
	# bound twice is first-write-wins, so the queue has to hold one entry, not two.
	TunePort.bind(slug, SENTINEL)
	_assert_eq(TunePort.deferred_count(), before + 1,
		"absent: the dropped declaration was recorded ONCE")
	_assert_true(not Tune.is_registered(slug),
		"absent: and has not reached the registry yet")

	node.name = "Tune"
	TunePort._forget_port()
	# Any verb re-resolves, and re-resolving is what drains the queue.
	TunePort.get_value(SLUG, SENTINEL)
	_assert_true(Tune.is_registered(slug),
		"the declaration landed when the port came back")
	_assert_approx(Tune.default_of(slug), BOUND,
		"the replay carried the FIRST literal, not the second")
	_assert_eq(Tune.meta_of(slug), {"min": 0.0, "max": 9.0},
		"the replay carried the affordance hint with it")
	_assert_eq(TunePort.deferred_count(), 0, "the queue drained")


## The production consequence, and why the queue above exists. Godot builds every
## autoload in ONE pass and adds them to the tree in a SECOND (`main.cpp`: *"defer so
## references are all valid on _ready()"*), and loading an autoload's script loads
## everything its dependency chain names — here, `ExMateriaBattlefield` and the eight
## addon owners that register at class load (ADR-0068 R2). So every one of those
## `_static_init`s runs against a `/root` with NO CHILDREN. Before the replay queue,
## all 78 of their slugs were dropped: nothing could enumerate a `camera.*`, `tile.*`
## or `cursor.*` knob, a scrub reached nothing, and each owner's own `_ready` then
## tripped the R3/R5 asserts on its own slugs — `get_value(camera.free_camera_enabled)`
## 8,888 times in one 60-second `GambitBattle` run.
##
## 🔴 **NOTHING BELOW IS PRELOADED, AND THAT IS THE ARM.** Naming `PlayerCamera` from
## this file would load the class at SCENE load with the port already up, which passes
## with the defect fully in place. The only evidence that survives the defect is the
## BOOT's own class loads — one slug per owner, so the failure line names which one.
func _test_the_boot_pass_registered_the_addon_owners() -> void:
	for slug in ["camera.deadzone_width", "cursor.height", "tile.uv_offset_x",
			"map.water_waves", "skirt.land_skirt_enabled"]:
		_assert_true(Tune.is_registered(slug),
			"%s registered during the autoload pass, with nothing here naming its owner"
			% slug)


# --- assertions ---------------------------------------------------------------

func _on_probe_hp(_u: Node, _old: int, _new: int) -> void:
	_hp_beats += 1


func _on_probe_mp(_u: Node, _old: int, _new: int) -> void:
	_mp_beats += 1


func _on_probe_par(_v: float) -> void:
	_par_beats += 1


## The BOUND half. `connect_*` is asserted by the beat actually arriving, not by
## its own return value — a port that returned `true` and wired nothing would pass
## an arm that only read the boolean.
func _test_present_event_port() -> void:
	if get_tree().root.get_node_or_null(^"EventBus") == null:
		_fail("the EventBus autoload is not in this tree — the bound arm cannot run")
		return
	EventPort._forget_port()
	_assert_true(EventPort.connect_unit_hp_changed(_on_probe_hp),
		"bound: connect_unit_hp_changed reports the subscription is live")
	_assert_true(EventPort.connect_unit_mp_changed(_on_probe_mp),
		"bound: connect_unit_mp_changed reports the subscription is live")

	_hp_beats = 0
	_mp_beats = 0
	EventBus.emit_unit_hp_changed(self, 1, 2)
	EventBus.emit_unit_mp_changed(self, 3, 4)
	_assert_eq(_hp_beats, 1, "bound: the hp subscription actually received the beat")
	_assert_eq(_mp_beats, 1, "bound: the mp subscription actually received the beat")

	# Idempotent: `Signal.connect` RAISES on a duplicate, and a UI element removed
	# and re-added to the tree runs `_ready()` twice. A port that let the duplicate
	# through would either error or double every beat.
	_assert_true(EventPort.connect_unit_hp_changed(_on_probe_hp),
		"bound: a second connect with the same Callable still reports live")
	_hp_beats = 0
	EventBus.emit_unit_hp_changed(self, 5, 6)
	_assert_eq(_hp_beats, 1, "bound: and did NOT double-subscribe")


## The ABSENT half — the only arm that speaks to a consuming project, where there
## is no `[autoload]` line at all.
func _test_absent_event_port() -> void:
	var node := get_tree().root.get_node_or_null(^"EventBus")
	if node == null:
		_fail("the EventBus autoload is not in this tree — the absent arm cannot run")
		return
	node.name = "EventBus_absent_probe"
	EventPort._forget_port()

	_assert_eq(EventPort.connect_unit_hp_changed(_on_probe_hp), false,
		"absent: connect_unit_hp_changed reports NOT live rather than raising")
	_assert_eq(EventPort.connect_unit_mp_changed(_on_probe_mp), false,
		"absent: connect_unit_mp_changed reports NOT live")

	# Silence is the identity for a subscription: the element still builds, it just
	# never hears a change. The seed is the standing connection from the bound arm —
	# without disproving it we could not tell "absent" from "still wired".
	_hp_beats = 0
	node.emit_unit_hp_changed(self, 7, 8)
	_assert_eq(_hp_beats, 1,
		"absent: the connection made while BOUND still fires — absence blocks NEW " +
		"subscriptions, it does not silently tear down live ones")

	node.name = "EventBus"
	EventPort._forget_port()
	_assert_true(EventPort.connect_unit_hp_changed(_on_probe_hp),
		"the port recovers once the autoload is back under its name")


func _assert_true(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
	else:
		_fail(what)


func _assert_eq(got, want, what: String) -> void:
	if got == want:
		_passed += 1
	else:
		_fail("%s (got %s, want %s)" % [what, got, want])


func _assert_approx(got, want, what: String) -> void:
	if typeof(got) in [TYPE_FLOAT, TYPE_INT] and is_equal_approx(float(got), float(want)):
		_passed += 1
	else:
		_fail("%s (got %s, want %s)" % [what, got, want])


func _fail(what: String) -> void:
	_failed += 1
	print("  [x] %s" % what)
