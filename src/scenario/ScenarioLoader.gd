@tool
extends Node

## Applies a [scenario](../../docs/context/08-scenario.md): the runtime expression of
## "a scenario is the load entry point; the map is a field of it"
## (ADR-0029, ADR-0030).
##
## Given a scenario_id and the active map node, it resolves the record via
## [ScenarioDatabase] and drives the two effects of loading a scenario — set
## the map and play the battle music. Deliberately **thin**: map + music only,
## never unit spawning / conditionals / camera (each of those gets its own
## owner as scenarios grow). The map node is **passed in, never held**, so
## there is no stale-ref lifecycle across scene reloads.
##
## @tool (line 1) so that @tool debug scripts which may touch autoloads
## in-editor can reach it without silently failing.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const ScenarioDatabase = ExMateriaAlmanac.ScenarioDatabase



## Apply a scenario: set the map, then play its music. Graceful degradation —
## a missing map folder or absent music never crashes the load.
func apply_scenario(scenario_id: int, map_composer) -> void:
	var scenario = ScenarioDatabase.get_scenario(scenario_id)
	if scenario.is_empty():
		push_error("[ScenarioLoader] Unknown scenario_id %d" % scenario_id)
		return

	# --- Map ---
	# change_map already push_errors + returns false on a missing folder (only
	# map_id 0 and 53 today). Keep the current map and still apply music.
	var map_id: int = int(scenario.get("map_id", -1))
	if map_composer:
		var map_name := "MAP%03d" % map_id
		# Forward the scenario's weather/night so the map renders its matching
		# environment state (sky/lighting/palette), like it forwards map_id
		# (ADR-0056). Arrangement stays Primary — no Secondary selector yet.
		var weather_raw: int = int(scenario.get("weather_raw", 0))
		var is_night: int = 1 if bool(scenario.get("is_nighttime", false)) else 0
		if not map_composer.change_map(map_name, weather_raw, is_night, 0):
			push_error("[ScenarioLoader] Scenario %d: map %s unavailable; keeping current map" % [scenario_id, map_name])
	else:
		push_error("[ScenarioLoader] Scenario %d: no map node passed; skipping map load" % scenario_id)

	# --- Music ---
	# music_file_one_id == 0 means "the scenario sets no music" (the real track
	# comes from the deferred event-script {84} Play Song) — stay silent. Never
	# play_slot(0), which would load MUSIC_00.
	var music_id: int = int(scenario.get("music_file_one_id", 0))
	if music_id == 0:
		MusicPlayer.stop()
	else:
		MusicPlayer.play_slot(music_id)
