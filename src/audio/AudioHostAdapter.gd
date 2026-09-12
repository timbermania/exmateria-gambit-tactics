extends Node

## The ONE host adapter for the ExMateria-Sound package (ADR-0153 dec. 3; ADR-0118 dec. 6
## predicted it at about twenty lines). Two walks and nothing else:
##
##   declared tunables -> `Tune`          (bind the slug, push the setter)
##   declared panels   -> `DebugOverlay`  (map the category string, mount, fill the rows)
##
## The package names neither `Tune` nor `DebugOverlay` nor `TuneField` — it publishes
## declarations and the host consumes them (ADR-0113's inversion). This file is the whole
## of what that inversion costs the host, and it is host code by construction: it is the
## only place where a sound-package declaration and a host symbol appear in the same line.

## The package declares its debug category as a STRING because `DebugOverlay.Category` is a
## closed enum of 22 the package cannot extend (ADR-0140); the mapping is here, and adding a
## 23rd member is NOT this pass's business.
const CATEGORIES := {"audio": DebugOverlay.Category.AUDIO}


func _ready() -> void:
	register_tunables()
	for t in ExMateriaEffectSfx.tunables():
		Tune.on_update(ExMateriaEffectSfx, t["slug"], t["setter"])
	ExMateriaEffectSfx.tunable_writer = Tune.set_value


## The bind half, split from the on_update push so it is this autoload's named registration
## entry point — `_ready` calls it at boot (the autoload's class-load equivalent, and the only
## thing that runs it), and the ADR-0173 guards call it to read back which slugs it binds. The
## same split every other tunable owner makes (ADR-0068 R1).
func register_tunables() -> void:
	for t in ExMateriaEffectSfx.tunables():
		Tune.bind(t["slug"], t["default"], t["hint"])


## Mount the package's declared panels: map each panel's declared category string, build a
## row for every declared tunable (a row is a `TuneField`, and `TuneField` is the host's),
## and hand the panel to the overlay. Called by whichever scene wants the AUDIO tab.
##
## THE PANEL CLASS IS NAMED AT THE MOUNT, DELIBERATELY. An earlier draft walked a
## `const PANELS := [preload(...)]` list and mounted `script.new()`, which is tidier and
## **silently deleted this panel from `check_debug_panel_tunables.py`**: that guard reads
## panel identity off `var X = ClassName.new()` paired with `register_panel(X` (ADR-0151's
## widened marker), and a loop variable satisfies neither half. The guard went GREEN because
## it had stopped looking — ADR-0148's defect for the third time, and in the very commit
## that retired the inheritance the widening was built to replace. Naming the class costs a
## line per panel and keeps the mount legible to the instrument that polices it.
static func register_panels() -> void:
	var panel := ExMateriaSound.SpuAudioDebugPanel.new()
	panel.setup()
	for t in ExMateriaEffectSfx.tunables():
		TuneField.add(panel.tunable_rows, t["label"], t["slug"])
	DebugOverlay.register_panel(panel, CATEGORIES[panel.PANEL_CATEGORY])


## Mount the WHOLE F3 AUDIO tab — the package's declared panels above plus the host's
## own `AudioMasterVolumeDebugPanel`, which is the other side of ADR-0153 dec. 2's
## SPU/bus split (the package owns the SPUs, the host owns the Godot Master bus).
##
## THE TAB HAS TWO HALVES AND EVERY SCENE WANTS BOTH, so every scene was writing both:
## ScenarioPlayerScene and EffectViewerScene held the same four lines, and only one of
## them held the idempotence guard. EffectViewerScene re-registered on every call. The
## guard belongs with the mount, not with one of its callers.
##
## Reaching `DebugOverlay._panels` is a host-private read, and it is here for the same
## reason everything else in this file is: this is the one place a sound declaration and
## a host symbol are allowed to meet. It was previously done from inside a scene.
static func register_audio_tab() -> void:
	for panel in DebugOverlay._panels.get(DebugOverlay.Category.AUDIO, []):
		if is_instance_valid(panel) and panel is ExMateriaSound.SpuAudioDebugPanel:
			return          # already mounted; stateless w.r.t. any VM, so no rebind
	register_panels()
	var volume_panel := AudioMasterVolumeDebugPanel.new()
	volume_panel.setup()
	DebugOverlay.register_panel(volume_panel, DebugOverlay.Category.AUDIO)
	# The live bus mixer (B3 task 2, #385). Host-side for the same reason the volume panel
	# is: its subject is the Godot bus graph, which is the host's half of ADR-0153 dec. 2.
	# Named class + register_panel pair, per the note above — a loop would hide it from
	# check_debug_panel_tunables.py.
	var mixer_panel := AudioBusMixerDebugPanel.new()
	mixer_panel.setup()
	DebugOverlay.register_panel(mixer_panel, DebugOverlay.Category.AUDIO)
