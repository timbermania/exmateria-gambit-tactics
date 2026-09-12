extends Node
## Slice 1 guard (issue #289 TIER-2): the shared, effect-global SoundContainers doc is a
## SINGLE SOURCE OF TRUTH on EffectData — mirroring `EffectData.sound`. A container edit
## must reach the resolver, the ghost projection, the container views, AND the writer
## through ONE mutable reference; that only works if EffectData itself carries the doc
## rather than each consumer re-parsing sound_containers.json off disk.
##
## The load-bearing property: `EffectData.load_from_directory(dir).sound_containers` equals
## the addon EffectJSONLoader's independent parse of the same effect (the two parse paths
## agree), and it is a live Dictionary the choke point can mutate in place.
##
## Run: <GODOT> --path . --quit-after 4 res://tests/EffectDataSoundContainersTest.tscn

const EffectDataClass = ExMateriaEffects.EffectData
const JSONLoader = preload("res://addons/exmateria_sound/runtime/effect_json_loader.gd")

const EFFECT_DIR := "res://assets/effects/E317"   # 4 DIRECT_A containers (id_a 1..4)

var _failed := false


func _check(cond: bool, msg: String) -> void:
	if not cond:
		print("[FAIL] %s" % msg)
		_failed = true


func _ready() -> void:
	_test_effect_data_loads_the_containers_doc()
	_test_matches_the_json_loader_parse()
	_test_doc_is_a_live_mutable_reference()

	if _failed:
		print("[FAIL] EffectDataSoundContainers test")
		get_tree().quit(1)
	else:
		print("[PASS] EffectDataSoundContainers: containers doc is a faithful single source of truth on EffectData")
		get_tree().quit(0)


## EffectData carries the parsed SoundContainers doc: a Dictionary with a "containers"
## array of 4 entries, each an {mode, id_a, id_b, id_c, index} record. Oracle = the known
## E317 fixture (4 DIRECT_A containers, id_a 1..4).
func _test_effect_data_loads_the_containers_doc() -> void:
	var data = EffectDataClass.load_from_directory(EFFECT_DIR)
	_check(data != null, "EffectData loaded")
	var doc = data.sound_containers
	_check(doc is Dictionary, "sound_containers is a Dictionary")
	var containers = doc.get("containers", [])
	_check(containers is Array and containers.size() == 4,
		"4 containers (got %s)" % [containers.size() if containers is Array else "non-array"])
	if containers is Array and containers.size() == 4:
		_check(int(containers[0].get("mode", -1)) == 0, "container 0 mode is DIRECT_A")
		_check(int(containers[0].get("id_a", -1)) == 1, "container 0 id_a is 1")
		_check(int(containers[3].get("id_a", -1)) == 4, "container 3 id_a is 4")


## The two parse paths agree: EffectData's doc equals the addon EffectJSONLoader's parse of
## the same effect. This is what lets the studio drop its redundant disk re-parse and read
## the containers straight off EffectData.
func _test_matches_the_json_loader_parse() -> void:
	var data = EffectDataClass.load_from_directory(EFFECT_DIR)
	var le = JSONLoader.load_dir(EFFECT_DIR)
	_check(le != null, "JSONLoader loaded the effect")
	if le != null:
		_check(data.sound_containers == le.sound_containers,
			"EffectData.sound_containers matches the JSONLoader parse")


## The doc is a LIVE Dictionary the choke point mutates in place — a mutation on the
## container entry is visible through the same reference (the property is not a per-read
## copy). This is the reference-sharing that fans a container edit out to every reader.
func _test_doc_is_a_live_mutable_reference() -> void:
	var data = EffectDataClass.load_from_directory(EFFECT_DIR)
	var doc = data.sound_containers
	var before := int(doc["containers"][0]["mode"])
	doc["containers"][0]["mode"] = 4
	_check(int(data.sound_containers["containers"][0]["mode"]) == 4,
		"mutation is visible through the EffectData property (shared reference)")
	doc["containers"][0]["mode"] = before   # restore (cache is shared across the session)
