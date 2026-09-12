class_name WorldMapMusicPort
extends RefCounted
## The world map's ONE audio crossing — docs/WORLD_MAP_PORT_LIST.md A1.
##
## [b]Payload[/b] "play the world-map track" · [b]owner[/b] Audio ·
## [b]edge[/b] map → Audio · [b]shape[/b] Command (ADR-0116 dec. 3's cheapest legal).
##
## `src/audio/` is mid-lift. Per #410 `MusicPlayer` is on the STAYING side, along with
## `SfxRouter`, `SfxCatalog`, `AttackSfxResolver` and `ExMateriaAudioEngine`'s bus half;
## `ExMateriaEffectSfx` moves whole and `ExMateriaAudioEngine` splits — so neither of those two is
## named anywhere in this file, and nothing here reaches by autoload name and
## `.call("…")`, which is the failure mode #316 documented as invisible to both the
## classifier and `touch_matrix.py`.
##
## The point of a port with exactly one method is that it can be [i]implemented[/i]
## now rather than stubbed, and re-pointed at the published addon in one place when
## #387 / B5 migrates the host.

## FFT's world-map theme — `SOUND/MUSIC_27.SMD`.
##
## [b]Measured, not guessed[/b] (which is why it sat at -1 rather than at a plausible
## number). A loaded SMD is resident verbatim in main RAM, so a savestate says which one
## a screen holds. Across all 38 savestates in `reference-assets/`:
##
## [codeblock]
## MUSIC_27 resident in  4/38  — and all four are the SETTLED world map
##                                ss1_settled_dialog_closed, ss0b_dialog_open,
##                                pre_scenario14_root13, walk_v306_midtraversal
##          absent from  34/38 — including the two world-map-ADJACENT captures,
##                                load_now_loading and ss0_scenario_end_prequicksave,
##                                where the map is not up yet
## [/codeblock]
##
## Residency alone only proves it is loaded, so: the four world-map captures are the same
## screen at four different moments, and MUSIC_27 is the ONLY resident sequence whose
## per-channel cursors move between them — 35 of 79 pointer slots differ, while
## MUSIC_12's 108 and MUSIC_45's 35 are frozen to the byte. A playing sequence advances
## its cursors; a preloaded one does not. (MUSIC_12 is resident in 26 of the 38 and is
## the one advancing in the Orbonne captures — it is a scenario track the world map keeps
## loaded, not its theme.)
##
## Both arms, then: it tracks the SCREEN, not the disc region.
const WORLD_MAP_SLOT := 27

var _player: Node


func _init(player: Node = null) -> void:
	_player = player


## Start the world-map theme. Returns false when the port is not wired or the slot
## is not confirmed — the screen runs silent rather than playing the wrong track.
func play() -> bool:
	if _player == null or WORLD_MAP_SLOT < 0:
		return false
	return _player.play_slot(WORLD_MAP_SLOT)


func stop() -> void:
	if _player != null:
		_player.stop()
