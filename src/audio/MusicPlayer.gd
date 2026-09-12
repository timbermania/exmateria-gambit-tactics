extends Node

## MusicPlayer (Autoload Singleton)
## Accessed globally as: MusicPlayer
##
## Plays Final Fantasy Tactics .SMD music through the ExMateria Sound addon
## (SMDPlayer). The waveset and song files are the synced copies under
## res://assets/music, populated by tools/sync_exmateria_sound.sh.
##
## Usage:
##   MusicPlayer.play_slot(31)   # play MUSIC_31.SMD
##   MusicPlayer.stop()
##
## Vault: [[Event Sound OpCodes]]

const MUSIC_DIR := "res://assets/music"
const WAVESET_PATH := MUSIC_DIR + "/WAVESET.WD"

var _player: ExMateriaSound.SMDPlayer
var _waveset_loaded := false

## Scene-local kill switch. While true, every play request is a silent no-op and
## anything currently playing is stopped. A scene that must run without background
## music (e.g. the Effect Studio previewer) raises this on enter and lowers it on
## exit, so even a scenario re-apply from an F3 panel stays quiet. Effect SFX runs
## on ExMateriaEffectSfx, a separate SPU, and is untouched.
var suppressed := false


## Raise/lower the scene-local music kill switch. Stops current playback when raised.
func set_suppressed(on: bool) -> void:
	suppressed = on
	if on:
		stop()


func _ready() -> void:
	_player = ExMateriaSound.SMDPlayer.new()
	_player.name = "SMDPlayer"
	add_child(_player)
	# Use the shared, boot-loaded music SPU + waveset (ExMateriaAudioEngine) instead of
	# the player's own self-built mixer, so the instrument bank is uploaded once.
	if ExMateriaAudioEngine.ready_ok:
		_player.attach_shared_engine(ExMateriaAudioEngine.music_spu, ExMateriaAudioEngine.waveset)
		_waveset_loaded = true


func play_slot(slot: int) -> bool:
	"""Load and play MUSIC_<slot>.SMD. Returns false if assets are missing."""
	return play_file("%s/MUSIC_%02d.SMD" % [MUSIC_DIR, slot])


func play_file(smd_path: String) -> bool:
	"""Load and play an .SMD file by path. Returns false on failure."""
	if suppressed:
		return false
	if _player == null:
		return false
	if not _ensure_waveset():
		return false
	if not _player.load_smd(smd_path):
		push_error("MusicPlayer: failed to load %s" % smd_path)
		return false
	_player.play_music()
	return true


func play_feds(feds_path: String, pair_idx: int = 0) -> bool:
	"""Load and play one FEDS effect-sound pair (from a feds.bin or E###.BIN)."""
	if suppressed:
		return false
	if _player == null:
		return false
	if not _ensure_waveset():
		return false
	if not _player.load_feds_pair(feds_path, pair_idx):
		push_error("MusicPlayer: failed to load feds %s pair %d" % [feds_path, pair_idx])
		return false
	_player.play_music()
	return true


func fade_out(ticks: int) -> bool:
	"""Fade the currently-playing music to silence over `ticks` sequencer ticks
	(event opc$PlayerCameraode {60} Fade Sound). `ticks <= 0` cuts immediately. No-op (returns
	false) if nothing is playing — matching FFT's `forcePlayedMUS == 0` gate.
	SFX and {6B} BGSound live on separate channels and are untouched."""
	if not is_playing() or _player == null or _player.seq == null:
		return false
	_player.seq.start_master_fade(0, ticks)  # target is always silence
	return true


func switch_track(slot: int, target_vol: int, ticks: int) -> bool:
	"""Event opcode {22} Switch Track: stop the current song, start MUSIC_<slot>
	from the top, then ramp master volume to `target_vol` (0..127) over `ticks`
	sequence$WorldEnvironmentr ticks (= Time*4; `ticks <= 0` sets it instantly). Mirrors the PSX
	chain stop (SUB_80043a38) → select preloaded slot + Reset_Mus (FUN_80043a90)
	→ Calc_Mus_VolChange ramp. Returns false if the song assets are missing."""
	if not play_slot(slot):
		return false
	if _player == null or _player.seq == null:
		return false
	# master_vol is the byte<<8 scale (0x7F00 = full), same as fade_out / {60}.
	_player.seq.start_master_fade(target_vol << 8, ticks)
	return true


func stop() -> void:
	"""Stop playback if anything is playing."""
	if _player:
		_player.stop_music()


func is_playing() -> bool:
	return _player != null and _player.is_playing()


func _ensure_waveset() -> bool:
	"""Load the instrument bank once and cache it across songs."""
	if _waveset_loaded:
		return true
	if not _player.load_waveset(WAVESET_PATH):
		push_error("MusicPlayer: failed to load waveset %s" % WAVESET_PATH)
		return false
	_waveset_loaded = true
	return true
