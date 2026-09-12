extends Node

## MasterBus (Autoload Singleton)
## Accessed globally as: MasterBus
##
## The Godot **Master-bus rack** and the whole-game volume — the HOST half of what
## used to be one `ExMateriaAudioEngine` (ADR-0153 dec. 2, split at #409). The dividing line
## is stated once and both splitting files honour it: **the sound package owns the
## SPUs, the host owns the bus.** `AudioStream` + buses is map #373's tier (#385
## `B3`), and `UserSettings` is `infrastructure` the host keeps (ADR-0139 dec. 13),
## so neither belongs in a package that ships to another game.

# A Godot AudioEffectHardLimiter on the Master bus catches the SFX + music + UI
# sum at the TRUE device output (#122 / ADR-0050 follow-up). Music and SFX are
# separate AudioStreamPlayers, so they re-sum here and can exceed full-scale
# (measured 1.15–1.34 with SFX over battle music) -> device clip. This
# transparent-below-ceiling limiter prevents that final clip.
const MASTER_CEILING_DB := -0.3

# The DOMAIN buses get a limiter too, and this is the half that changed at #385
# task 3 (ADR-0163). Until then a hand-rolled GDScript limiter (`BusLimiter`) capped the SFX
# stream before Godot ever saw it. That is gone: `D3` dec. 4 retired it, because
# in GDScript it cost 2.3x the SPU render it protected and "its job is
# AudioEffectHardLimiter on a real bus".
#
# The job could not simply move to Master. Measured with SfxPopDiagTest firing N
# concurrent Fire (E016) casts — a MID-size effect, 0.69 peak alone, where
# ADR-0050 measured Shiva and Ifrit at 1.0 alone — the untamed SFX sum reaches:
#
#     1 cast 0.69 | 2 casts 1.42 | 3 casts 2.13 | 4 casts 2.84 | 6 casts 4.26
#
# Master-only limiting would hand all of that to a limiter sitting downstream of
# the SFX + MUSIC sum, ducking the whole mix — music included — by up to 12.6 dB
# during a combat burst. That is the pumping ADR-0050's two-limiter split existed
# to prevent, merely relocated onto the music bus, and it is a regression against
# what shipped. A limiter on each SUMMING domain bus bounds it BEFORE Master, so
# Master only ever sums three well-behaved sources. Music is the third and takes
# NO limiter: it is already bounded, by the SPU's own in-core clip rather than by
# a bus effect. See LIMITED_BUSES.
#
# The ceiling is 0 dB, not Master's -0.3, on purpose: it must reproduce
# BusLimiter's stated threshold — "it acts only on the SUM crossing the ceiling,
# never on a single source sitting at it". A lone full-scale summon sits exactly
# AT 0 dB and passes untouched; Master's -0.3 dB stays the device guard.
const DOMAIN_CEILING_DB := 0.0
## Master <- {Music, SFX, Ambient} (`D3` dec. 6, #385 task 2). This is the ROUTING
## list and ONLY the routing list: every domain bus sends to Master. Which of them
## carries a limiter is a different question with a different answer — LIMITED_BUSES.
## The two were one constant until #385's review; the docstring said routing and the
## sole consumer was the limiter installer, which is how Music acquired one.
const DOMAIN_BUSES := ["Music", "SFX", "Ambient"]

## The domain buses that get a DOMAIN_CEILING_DB HardLimiter — ADR-0163 dec. 2, which
## names these two and only these two. Ambient is here because a persistent bed needs
## headroom independent of combat (the decoupling `_bg_limiter` used to buy inside
## ExMateriaEffectSfx, now a property of the routing), and because deleting `_bg_limiter`
## outright would have been an UNMEASURED removal.
##
## Music is absent, and that is the decision rather than an oversight:
##  - it carries exactly ONE stream (`smd_player.gd`'s single AudioStreamPlayer on
##    `OUTPUT_BUS := &"Music"`), so nothing sums on it — the 4.26 peak that justifies
##    SFX's limiter is a SUM of concurrent casts and has no analogue here;
##  - every SPU frame leaves the core through `clip_pcm16` and is scaled by 1/32767
##    (`exmateria_psx_spu.cpp`), so the bus cannot exceed 0 dBFS and a 0 dB-ceiling
##    limiter on it is inert by construction;
##  - ADR-0050's whole pumping argument is that combat gain-reduction must not reach
##    the music, and a limiter on Music can only ever gain-reduce the music.
const LIMITED_BUSES := ["SFX", "Ambient"]

## Whole-game volume — the true global control. All audio (music via MusicPlayer, SFX via
## ExMateriaEffectSfx, UI blips) re-sums at the Godot Master bus (index 0), so a cut there is
## the one knob that scales everything. Sits fine UNDER the HardLimiter installed above; do
## not confuse with the per-domain trims (e.g. ExMateriaEffectSfx.set_bg_level, the ambient bed).
## UserSettings persists the value per-machine; this is its live-apply seam.
const MASTER_BUS := 0
const SILENT_FLOOR_DB := -80.0
# The whole-game volume BOOSTS, it doesn't just attenuate: the SPU source sits ~11 dB below
# full scale (a full-volume note peaks ~-11 dB at the Master bus), so plain unity (0 dB) at
# 100% was too quiet. The slider's top (v=1.0) maps to +MASTER_MAX_GAIN_DB, driving the source
# up toward the -0.3 dB HardLimiter ceiling; the limiter (installed above) catches any peaks so
# the boost never clips. +9 dB brings the quiet source to ~-2 dB (near the ceiling, clean) while
# leaving the louder multi-voice sums to the limiter. Unity lands at v≈0.36 on the curve.
const MASTER_MAX_GAIN_DB := 9.0
# The whole-game gain lives on a pre-limiter Amplify (NOT the bus fader, which Godot applies
# AFTER the effect rack — a boost there would land past the limiter and clip the device).
var _master_gain: AudioEffectAmplify = null


func _ready() -> void:
	_install_master_limiter()
	_install_domain_limiters()
	_apply_master_volume(UserSettings.master_volume)  # boot-apply the persisted whole-game volume


func get_master_volume() -> float:
	## The current whole-game linear volume (0..1). Source of truth is the persisted setting.
	return UserSettings.master_volume


func set_master_volume(x: float, persist: bool = true) -> void:
	## Set the whole-game volume (clamped 0..1) live on the Master bus and record it in
	## UserSettings. persist=false is the live-drag path (no disk write); persist=true (the
	## default) also saves user_settings.json so it survives a restart.
	var v := clampf(x, 0.0, 1.0)
	_apply_master_volume(v)
	UserSettings.set_master_volume(v, persist)


func _apply_master_volume(v: float) -> void:
	## Drive the whole-game gain: map linear 0..1 to dB, SHIFTED UP by MASTER_MAX_GAIN_DB so 100%
	## BOOSTS the quiet SPU source into the -0.3 dB limiter (see the const). Applied on the
	## PRE-limiter Amplify — NOT the bus fader, which Godot applies AFTER the rack, so a boost
	## there would bypass the limiter and clip. 0 -> a finite silent floor (not linear_to_db(0)=-inf).
	if _master_gain == null:
		_master_gain = _find_master_amplify()
	if _master_gain == null:
		return
	_master_gain.volume_db = SILENT_FLOOR_DB if v <= 0.0 else MASTER_MAX_GAIN_DB + linear_to_db(v)


## The current whole-game gain in dB (the pre-limiter Amplify's volume_db). For tests/diagnostics.
func get_master_gain_db() -> float:
	if _master_gain == null:
		_master_gain = _find_master_amplify()
	return _master_gain.volume_db if _master_gain else 0.0


func _find_master_amplify() -> AudioEffectAmplify:
	for i in range(AudioServer.get_bus_effect_count(MASTER_BUS)):
		var fx = AudioServer.get_bus_effect(MASTER_BUS, i)
		if fx is AudioEffectAmplify:
			return fx
	return null


func _install_master_limiter() -> void:
	## Master rack, IN ORDER: an Amplify (the whole-game gain) THEN a HardLimiter at
	## MASTER_CEILING_DB. The gain MUST precede the limiter — a >0 dB boost placed after it would
	## land past the ceiling and clip the device; before it, the limiter catches the boosted peaks.
	## Idempotent (won't stack on a tool/test re-init). Any lazily-appended Master taps (audio
	## monitor / stress tests) land after both, so they measure the true post-gain, post-limiter mix.
	AudioServer.set_bus_volume_db(MASTER_BUS, 0.0)   # the fader stays neutral — gain rides the Amplify
	if _find_master_amplify() == null:
		var amp := AudioEffectAmplify.new()
		amp.volume_db = 0.0
		AudioServer.add_bus_effect(MASTER_BUS, amp, 0)   # index 0 — ahead of the limiter
	_master_gain = _find_master_amplify()
	var have_lim := false
	for i in range(AudioServer.get_bus_effect_count(MASTER_BUS)):
		if AudioServer.get_bus_effect(MASTER_BUS, i) is AudioEffectHardLimiter:
			have_lim = true
			break
	if not have_lim:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = MASTER_CEILING_DB
		AudioServer.add_bus_effect(MASTER_BUS, lim)       # appended AFTER the amp


func _install_domain_limiters() -> void:
	## One AudioEffectHardLimiter at DOMAIN_CEILING_DB on each of LIMITED_BUSES
	## (SFX, Ambient) — ADR-0163 dec. 2. NOT on Music; see LIMITED_BUSES.
	##
	## Idempotent, and deliberately so: the shipped AudioBusLayout resource carries
	## EMPTY racks (the addon ships transparent routing — limiting is the consumer's
	## to place), so these are the HOST's, installed at boot. A layout that shipped
	## its own would otherwise double them, which is the failure AudioBusLayoutTest
	## guards against for the Master rack and now guards here too.
	##
	## A bus the host has not declared is skipped rather than warned about: this
	## runs before any scene, and a project mid-edit can legitimately lack one.
	for bus_name in LIMITED_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx <= 0:
			continue
		var have := false
		for i in range(AudioServer.get_bus_effect_count(idx)):
			if AudioServer.get_bus_effect(idx, i) is AudioEffectHardLimiter:
				have = true
				break
		if have:
			continue
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = DOMAIN_CEILING_DB
		AudioServer.add_bus_effect(idx, lim)
