extends Node

## #745 / ADR-0217 S5 — BOOT THE TREE WITH THE SPRITE RIG REMOVED.
##
## ADR-0217 dec. 18 booted the rig PRESENT and proved two claims about it. S5 says what
## that boot did NOT do: dec. 3's severability claim rests on the tree standing up with
## the addon gone, and ADR-0157 Spike A warns that a `.tscn` whose script fails to
## resolve still MOUNTS, stripped, and fails at the first property touch. A boot that
## succeeds is therefore not by itself evidence of severability, and neither is a boot
## that fails — the question is WHICH failure mode, on WHICH channel.
##
## Run headful (NEVER --headless), once with the addon in the tree and once with it
## moved out, and diff the two reports:
##
##   godot --path . res://tools/probe_rig_removed.tscn -- \
##       --rig-root=res://addons/<the rig> --facade=<…>/<facade>.gd --rig-scene=<…>/UnitRig.tscn
##
## 🔴 THE ADDON'S PATHS COME IN ON THE COMMAND LINE AND ARE NOT WRITTEN HERE.
## `tools/` is inside `check_lattice_scene.py`'s corpus, so a literal
## `res://addons/<rig>/…` in this file — in code OR in a comment (ADR-0208 dec. 7) —
## would ADD criterion-4 sites to the very register this pass is scoring. The probe
## would move the number it exists to measure.
##
## Every line is prefixed `[s5]` so the two logs diff cleanly.

const HOST_NAMERS := [
	"res://src/units/Unit.gd",                      # the host adapter — 3 `$` reaches + a bare get_node
	"res://src/data/SpriteRigContent.gd",           # AUTOLOAD, and it names the façade
	"res://src/scenarios/ScenarioDialogueBoxPool.gd",  # the two SILENT crossings
	"res://src/gpu/CombatLoop.gd",
	"res://src/scenes/UnitAnimationViewerScene.gd",
]

var _args := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0].lstrip("-")] = kv[1]

	print("[s5] engine=%s  headless=%s" % [
		Engine.get_version_info()["string"], str(DisplayServer.get_name() == "headless")])
	print("[s5] argv rig-root=%s" % str(_args.get("rig-root", "<unset>")))

	_probe_disk()
	_probe_global_class()
	_probe_autoload()
	_probe_host_namers()
	_probe_mount()
	print("[s5] DONE")
	get_tree().quit()


func _probe_disk() -> void:
	## Is the addon on disk at all? The whole experiment's independent variable.
	for key in ["rig-root", "facade", "rig-scene"]:
		var p: String = _args.get(key, "")
		if p == "":
			continue
		var abs := ProjectSettings.globalize_path(p)
		print("[s5] disk  %-10s exists=%s  (%s)" % [
			key, str(DirAccess.dir_exists_absolute(abs) or FileAccess.file_exists(abs)), p])
		print("[s5] loader %-10s ResourceLoader.exists=%s" % [key, str(ResourceLoader.exists(p))])


func _probe_global_class() -> void:
	## The SYMBOL channel. `class_name` registration is what 53 host files' alias lines
	## resolve against; a `const X = ExMateriaSpriteRig.X` on a missing global is a PARSE
	## error, not a runtime null, which is the loud half of the answer.
	var found := ""
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")).begins_with("ExMateria"):
			found += " %s" % c["class"]
	print("[s5] global class_name registrations:%s" % (found if found != "" else " <none>"))


func _probe_autoload() -> void:
	## `SpriteRigContent` is an AUTOLOAD and it names the façade, so the symbol channel
	## is exercised before any scene loads. Godot instantiates a bare Node when an
	## autoload's script will not compile — the node is there and answers nothing.
	var n := get_node_or_null("/root/SpriteRigContent")
	if n == null:
		print("[s5] autoload SpriteRigContent: ABSENT from /root")
		return
	var s: Script = n.get_script()
	print("[s5] autoload SpriteRigContent: node=%s script=%s base='%s'" % [
		n.get_class(),
		"null" if s == null else str(s.resource_path),
		"" if s == null else str((s as GDScript).get_instance_base_type())])
	var live := n.has_method("weapon_v_offset")
	print("[s5] autoload has_method(weapon_v_offset)=%s" % str(live))
	if live:
		var v: Variant = n.call("weapon_v_offset", 0)
		print("[s5] autoload call weapon_v_offset(0) -> %s" % str(v))


func _probe_host_namers() -> void:
	## `load()` is NOT a compile witness — a parse-failed script still comes back as a
	## GDScript object. `get_instance_base_type()` is "" on one, and `can_instantiate()`
	## is false. That pair is the witness.
	for p in HOST_NAMERS:
		var s: Resource = load(p)
		if s == null:
			print("[s5] script %-48s load()=null" % p)
			continue
		var g: GDScript = s as GDScript
		print("[s5] script %-48s base='%s' can_instantiate=%s" % [
			p, str(g.get_instance_base_type()), str(g.can_instantiate())])


func _probe_mount() -> void:
	## The PATH channel. `assets/scenes/Unit.tscn` INHERITS the rig's scene, so with the
	## addon gone its base is missing — a different failure from a missing script, and
	## the one dec. 3's 114-to-1 collapse rests on. If it loads anyway, instantiate it
	## and touch a property: Spike A's stripped mount is exactly that shape.
	var path := "res://assets/scenes/Unit.tscn"
	print("[s5] mount  %s ResourceLoader.exists=%s" % [path, str(ResourceLoader.exists(path))])
	var ps: PackedScene = load(path) as PackedScene
	if ps == null:
		print("[s5] mount  load()=null — the inherited scene did not resolve")
		return
	print("[s5] mount  load()=%s can_instantiate=%s" % [ps.get_class(), str(ps.can_instantiate())])
	var inst: Node = ps.instantiate() if ps.can_instantiate() else null
	if inst == null:
		print("[s5] mount  instantiate()=null")
		return
	var names := []
	for c in inst.get_children():
		names.append("%s:%s" % [c.name, c.get_class()])
	print("[s5] mount  root=%s:%s children=%d %s" % [
		inst.name, inst.get_class(), names.size(), str(names)])
	for want in ["SpriteLayerManager", "AnimationStateController", "CameraRelativeRenderer", "UnitMesh"]:
		var c: Node = inst.get_node_or_null(want)
		print("[s5] mount  node %-26s %s" % [
			want, "MISSING" if c == null else "%s script=%s" % [
				c.get_class(), "null" if c.get_script() == null else "yes"]])
	# Spike A's first property touch, on whichever node survived.
	var slm: Node = inst.get_node_or_null("SpriteLayerManager")
	if slm != null:
		# Spike A's first property touch. With the mount stripped the node is still THERE,
		# as a plain Node with no script, so the read returns null instead of erroring.
		print("[s5] mount  touch SpriteLayerManager.apply_reversion -> %s  has_method(initialize)=%s" % [
			str(slm.get("apply_reversion")), str(slm.has_method("initialize"))])
	inst.queue_free()
