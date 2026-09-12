extends Node
## The bus layout is REAL — `D3` decision 6 (#376), `B3` task 2 (#385).
##
## Before this landed, the whole game entered Godot's mixer at the last inch: two
## `AudioStreamPlayer`s both hardcoded `bus = "Master"`, and **no `AudioBusLayout`
## existed anywhere in the repo**. A consumer had exactly one fader for everything.
##
## What this guards, and why each half is needed:
##
## - **The layout is declared, not built at runtime.** `audio/buses/default_bus_layout`
##   points at a committed `AudioBusLayout`, so the buses exist at engine boot, BEFORE
##   any autoload runs. `get_bus_index("Music") >= 0` alone would ALSO pass if some
##   `_ready` had called `AudioServer.add_bus()`, so this reads the resource back and
##   requires the live bus table to match it name-for-name and count-for-count. (Reading
##   the project setting is NOT enough on its own: the key has an engine-supplied default
##   of `res://default_bus_layout.tres`, so `get_setting` answers even when project.godot
##   says nothing — measured. The resource-exists + table-matches pair is what bites.)
## - **Routing is transparent, the RACK is the host's.** Music/SFX/Ambient each send to
##   Master at 0 dB with no mute/solo/bypass. The layout RESOURCE ships empty racks; the
##   host (MasterBus) installs exactly one HardLimiter on each at boot — #385 task 3 moved
##   `BusLimiter`'s job onto real buses, and Master-only would have ducked music by up to
##   12.6 dB under a 6-cast burst. Asserting BOTH halves is what keeps a layout that
##   shipped its own rack from silently doubling every limiter. The pre-change mix summed at Master;
##   inserting a unity pass-through bus in front of it must not change a sample. This is
##   the "costs no parity" clause made mechanical.
## - **The Master rack still hosts the Amplify -> HardLimiter.** `D3` dec. 6 keeps it on
##   Master exactly as `MasterBus.gd` builds it, so SFX + music still re-sum under the
##   -0.3 dB ceiling. A layout resource that shipped its OWN Master rack could silently
##   double it, or `MasterBus` could stop finding what it installs.
## - **Both players are off Master.** Read through `AudioStreamPlayer.bus`, whose GETTER
##   falls back to `&"Master"` when the named bus does not exist
##   (`audio_stream_player_internal.cpp:353-361`). So `bus == "Music"` cannot pass unless
##   the layout ACTUALLY loaded — the assignment alone is not enough to satisfy it.
##
## Run: <GODOT> --path . --quit-after 30 res://tests/AudioBusLayoutTest.tscn

const LAYOUT_SETTING := "audio/buses/default_bus_layout"
const MASTER := "Master"
## Master <- {Music, SFX, Ambient} — D3 decision 6's layout, named in the decision record.
## ROUTING only. Which of these carries a limiter is a separate question, and the answer
## is `MasterBus.LIMITED_BUSES` — read from production rather than restated here, because
## restating it is exactly how the two sets drifted apart (ADR-0163 dec. 2 names SFX and
## Ambient; `MasterBus.DOMAIN_BUSES` was looping all three).
const SENDING_BUSES := ["Music", "SFX", "Ambient"]

var _passed := 0
var _failed := 0


func _ready() -> void:
	# The autoloads mount before a scene's _ready, but ExMateriaEffectSfx builds its player
	# inside its own _ready and MusicPlayer adds the SMDPlayer in its; one frame makes the
	# ordering irrelevant rather than assumed.
	await get_tree().process_frame

	# --- The layout is a committed resource the ENGINE loads, not runtime add_bus() ---
	var layout_path := str(ProjectSettings.get_setting(LAYOUT_SETTING, ""))
	_assert_true(layout_path != "" and ResourceLoader.exists(layout_path),
		"%s resolves to a resource on disk (got '%s')" % [LAYOUT_SETTING, layout_path])
	var layout: AudioBusLayout = null
	if layout_path != "" and ResourceLoader.exists(layout_path):
		layout = load(layout_path) as AudioBusLayout
		_assert_true(layout != null, "%s loads as an AudioBusLayout" % layout_path)
	if layout != null:
		# The resource's own bus table, read back through AudioBusLayout's `bus/N/*`
		# properties, must BE the live table — same names, same order, same count. That is
		# what separates "the engine loaded a declared layout" from "something called
		# AudioServer.add_bus() at boot"; the latter would leave the live count higher than
		# the resource's, or the names in an order the resource never states.
		var declared: Array[String] = []
		var i := 0
		while true:
			var nm = layout.get("bus/%d/name" % i)
			if nm == null:
				break
			declared.append(str(nm))
			i += 1
		_assert_true(declared.size() == AudioServer.bus_count,
			"the live bus table is exactly the declared one (%d live vs %d in the resource)"
				% [AudioServer.bus_count, declared.size()])
		for j in range(mini(declared.size(), AudioServer.bus_count)):
			_assert_true(AudioServer.get_bus_name(j) == declared[j],
				"bus %d is '%s' as the resource declares (live: '%s')"
					% [j, declared[j], AudioServer.get_bus_name(j)])
		# The RESOURCE ships EMPTY racks on every bus. This is the half that makes the
		# runtime "exactly one HardLimiter" assertions below mean something: the
		# limiters on Master/Music/SFX/Ambient are the HOST's, installed by MasterBus
		# at boot, and a layout that shipped its own would silently double every one
		# of them. Read as `bus/N/effect/0/effect` — null when the rack is empty.
		for j in range(declared.size()):
			_assert_true(layout.get("bus/%d/effect/0/effect" % j) == null,
				"the layout RESOURCE ships bus %d ('%s') with an EMPTY rack — limiting is the host's"
					% [j, declared[j]])

	# --- The buses exist, Master is index 0, and each domain bus feeds Master ---
	_assert_true(AudioServer.get_bus_name(0) == MASTER, "bus 0 is Master")
	for bus_name in SENDING_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		_assert_true(idx > 0, "bus '%s' exists (index %d)" % [bus_name, idx])
		if idx <= 0:
			continue
		_assert_true(str(AudioServer.get_bus_send(idx)) == MASTER,
			"bus '%s' sends to Master (sends to '%s')" % [bus_name, AudioServer.get_bus_send(idx)])
		# Transparent ROUTING: unity gain, no mute/solo/bypass. The fader and the routing
		# add nothing — a domain bus carries the signal, it does not colour it.
		_assert_approx(AudioServer.get_bus_volume_db(idx), 0.0, "bus '%s' is at unity (0 dB)" % bus_name)
		_assert_true(not AudioServer.is_bus_mute(idx), "bus '%s' is not muted" % bus_name)
		_assert_true(not AudioServer.is_bus_solo(idx), "bus '%s' is not soloed" % bus_name)
		_assert_true(not AudioServer.is_bus_bypassing_effects(idx), "bus '%s' does not bypass effects" % bus_name)
		# --- Limiting is a SEPARATE question from routing, and the two sets differ. ---
		# A limited bus holds EXACTLY ONE HardLimiter and it is the HOST's (MasterBus
		# installs it at boot) — see the resource check below, which is what makes
		# "the host's" a claim this test can tell apart from "the layout's".
		#
		# An UNLIMITED domain bus must hold NOTHING, and that arm is not decoration: it
		# is the only thing that can catch a limiter reappearing on Music. ADR-0163 dec. 2
		# authorises SFX and Ambient and no others; Music is bounded already, by the SPU's
		# in-core `clip_pcm16` on a bus that carries exactly one stream, so a 0 dB-ceiling
		# limiter there would be inert AND unauthorised. Both halves loop the PRODUCTION
		# constant, so neither can drift from what MasterBus actually installs.
		var limited: bool = bus_name in MasterBus.LIMITED_BUSES
		var lims := 0
		for i in range(AudioServer.get_bus_effect_count(idx)):
			if AudioServer.get_bus_effect(idx, i) is AudioEffectHardLimiter:
				lims += 1
		if limited:
			_assert_true(lims == 1,
				"limited bus '%s' carries exactly one HardLimiter (got %d of %d effects)"
					% [bus_name, lims, AudioServer.get_bus_effect_count(idx)])
			_assert_true(AudioServer.get_bus_effect_count(idx) == 1,
				"limited bus '%s' carries NOTHING but that limiter (has %d effects)"
					% [bus_name, AudioServer.get_bus_effect_count(idx)])
		else:
			_assert_true(AudioServer.get_bus_effect_count(idx) == 0,
				"UNLIMITED bus '%s' carries no effect at all (has %d, %d of them HardLimiters) — ADR-0163 dec. 2 authorises a domain limiter on %s only"
					% [bus_name, AudioServer.get_bus_effect_count(idx), lims, str(MasterBus.LIMITED_BUSES)])
		# The CEILING is the load-bearing number, and it is 0 dB rather than Master's
		# -0.3. This is what carries ADR-0050's "faithful in isolation" clause across
		# the BusLimiter deletion: BusLimiter's threshold "sits at 0 dBFS: it acts
		# only on the SUM crossing the ceiling, never on a single source sitting at
		# it", and a lone full-scale summon (ADR-0050 measured Shiva and Ifrit at
		# exactly 1.0) sits AT 0 dB. A -0.3 dB ceiling here would attenuate it.
		for i in range(AudioServer.get_bus_effect_count(idx) if limited else 0):
			var fx = AudioServer.get_bus_effect(idx, i)
			if fx is AudioEffectHardLimiter:
				_assert_approx(fx.ceiling_db, MasterBus.DOMAIN_CEILING_DB,
					"bus '%s' limiter sits at the domain ceiling (%.2f dB), not Master's"
						% [bus_name, MasterBus.DOMAIN_CEILING_DB])
				_assert_true(MasterBus.DOMAIN_CEILING_DB == 0.0,
					"the domain ceiling is 0 dBFS — a lone full-scale source passes it untouched")

	# --- The Master rack is still MasterBus's: Amplify BEFORE HardLimiter, exactly one each ---
	var amps := 0
	var lims := 0
	var amp_idx := -1
	var lim_idx := -1
	for i in range(AudioServer.get_bus_effect_count(0)):
		var fx = AudioServer.get_bus_effect(0, i)
		if fx is AudioEffectAmplify:
			amps += 1
			if amp_idx < 0: amp_idx = i
		if fx is AudioEffectHardLimiter:
			lims += 1
			if lim_idx < 0: lim_idx = i
	_assert_true(amps == 1 and lims == 1,
		"Master holds exactly one Amplify and one HardLimiter (got %d/%d — a layout that shipped its own rack would double them)" % [amps, lims])
	_assert_true(amp_idx >= 0 and lim_idx >= 0 and amp_idx < lim_idx,
		"the whole-game gain (Amplify @%d) still sits BEFORE the HardLimiter (@%d)" % [amp_idx, lim_idx])

	# --- Both hand-fed players are OFF Master and on their domain bus ---
	# `.bus` reads through the engine getter, which returns &"Master" for a name that does
	# not resolve — so these two also prove the layout loaded, not merely that a string
	# was assigned.
	_assert_player_bus(_music_player(), "Music", "MusicPlayer/SMDPlayer (the .SMD music stream)")
	_assert_player_bus(_sfx_player(), "SFX", "ExMateriaEffectSfx (the battle-effect SPU stream)")

	print("\n=== AudioBusLayoutTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] AudioBusLayoutTest")
		get_tree().quit(1)
	else:
		print("[PASS] AudioBusLayoutTest")
		get_tree().quit(0)


func _music_player() -> AudioStreamPlayer:
	var smd := MusicPlayer.get_node_or_null("SMDPlayer")
	return _find_stream_player(smd) if smd else null


func _sfx_player() -> AudioStreamPlayer:
	return _find_stream_player(ExMateriaEffectSfx)


func _find_stream_player(root: Node) -> AudioStreamPlayer:
	for child in root.get_children():
		if child is AudioStreamPlayer:
			return child
	return null


func _assert_player_bus(player: AudioStreamPlayer, expected: String, label: String) -> void:
	# A missing player is reported as its own failure rather than skipped: "the node was
	# not there" and "the node is on the wrong bus" must not look the same from the log.
	if player == null:
		_failed += 1
		print("  [FAIL] %s — no AudioStreamPlayer found (engine not up? cannot judge its bus)" % label)
		return
	_assert_true(str(player.bus) == expected,
		"%s plays on '%s' (reads '%s')" % [label, expected, player.bus])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected true" % label)


func _assert_approx(actual: float, expected: float, label: String) -> void:
	if is_equal_approx(actual, expected) or absf(actual - expected) < 0.01:
		_passed += 1
	else:
		_failed += 1
		print("  [FAIL] %s — expected %.4f, got %.4f" % [label, expected, actual])
