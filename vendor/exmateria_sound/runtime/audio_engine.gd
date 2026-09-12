extends Node

## ExMateriaAudioEngine (Autoload Singleton)
## Accessed globally as: ExMateriaAudioEngine
##
## Owns the game's static audio assets, set up ONCE at boot and held for the
## game's lifetime (no per-play instrument reload):
##   - waveset:   one shared WavesetParser (the WAVESET.WD instrument bank)
##   - music_spu: the SPU that plays music (driven by MusicPlayer/SMDPlayer)
##   - sfx_spu:   the SPU that plays effect sounds (E###.BIN + global SFX banks,
##                driven by ExMateriaEffectSfx — the one always-on SFX driver)
##
## Two fixed SPUs = 48 voices total, each with its own reverb tank. They share
## the single instrument bank. The 24-voice cap is an internal detail of one
## native SPU unit, not a global limit — see project memory / the Spu class.
##
## THE SPU HALF ONLY (ADR-0153 dec. 2, split at #409). The Godot **Master-bus**
## rack that used to live here — the Amplify-before-HardLimiter chain, the +9 dB
## boost curve and the `UserSettings` persistence — is the HOST's and moved to
## `MasterBus`. The line is: this package owns the SPUs, the host owns the bus.
## Nothing in this file names a host symbol, which is what makes it liftable.
##
## Must autoload BEFORE MusicPlayer (which grabs music_spu in its _ready).

const _Spu = preload("res://addons/exmateria_spu/runtime/spu.gd")
const _WavesetParser = preload("res://addons/exmateria_sound/runtime/waveset_parser.gd")

const WAVESET_PATH := "res://assets/music/WAVESET.WD"

var waveset := _WavesetParser.new()
var music_spu: _Spu
var sfx_spu: _Spu
var ready_ok := false


func _ready() -> void:
	if not waveset.load_from_file(WAVESET_PATH):
		push_error("ExMateriaAudioEngine: failed to load waveset %s" % WAVESET_PATH)
		return
	music_spu = _Spu.new()
	sfx_spu = _Spu.new()
	if not music_spu.load_instruments(waveset.descriptors(), waveset.adpcm_data) \
			or not sfx_spu.load_instruments(waveset.descriptors(), waveset.adpcm_data):
		push_error("ExMateriaAudioEngine: failed to load instruments into SPUs")
		return
	ready_ok = true
	print("[ExMateriaAudioEngine] ready — shared waveset + music/sfx SPUs (48 voices)")
