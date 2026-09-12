extends Node

## Routes game-event SFX (unit death, UI, environment, etc.) to the global
## FFT SFX banks at `assets/audio/sfx_banks/{system,env}.feds`. See the
## "Audio" cluster in CONTEXT.md and ADR-0006 for the split between this and
## the effect-cast audio path (`PhaseBlock` → `ExMateriaEffectSfx`).
##
## Two ways in:
##  - Subscribe to `EventBus` signals (game state) — `_ready` wires them up.
##  - Direct `play_cue(name)` for code that's allowed to know it's making a
##    sound (UI, environment).
##
## Cue names are namespaced: `combat.unit_died`, `ui.cursor_move`,
## `env.battlefield_wind`. Gameplay code never names a bank or slot.
##
## Vault: [[Battle Action SFX]]
## Vault: [[Dialogue Box SFX]]
## Vault: [[Event Sound OpCodes]]

## Emitted *before* the backend dispatch, so listeners (tests, debug overlays)
## see a cue even when the SPU backend can't actually play it.

# ADR-0211 dec. 4 — the addon's façade is its whole symbol surface. One alias
# line per file keeps every use site's spelling, and makes a grep for
# `ExMateriaAlmanac` a complete census of host->addon symbol coupling.
const UnitProgression = ExMateriaAlmanac.UnitProgression

signal cue_requested(name: String, bank: String, slot: int)

## Emitted on every {6B} BG Sound / {6A} Edit BG Sound state change so tests and
## debug overlays can observe the ambient channel without a live SPU backend.
## `action` ∈ {"play", "edit", "stop"}; `handle` is the audio token (0 pre-dispatch
## / on miss); `stacking` mirrors the opcode's op[3] (0 = tracked, ≠0 = overlay).
signal bg_sound_changed(action: String, sound_id: int, stacking: int, handle: int)


const BANKS_DIR := "res://assets/audio/sfx_banks"
const SfxCatalog = preload("res://src/audio/SfxCatalog.gd")

const _BANK_FILES := {
	"system": "system.feds",
	"env": "env.feds",
}

# Cue registry: cue name → {bank, slug}. Add a row to introduce a new cue.
# `slug` is a semantic label resolved against SfxCatalog (the bank's named
# slots), so cues never carry a magic slot id. A row may instead pin a raw
# `slot` int when a sound has no catalogued name. Optional per-row keys can be
# added when (and only when) a specific cue needs them — e.g. a `gain`
# override. Don't add speculative knobs.
#
# `combat.unit_died` is intentionally absent — it is handler-resolved (the
# slug depends on the dying unit's BaseStatType). See `_on_unit_died` and
# CONTEXT.md > SfxRouter.
const _CUES := {
	# TileCursor tile-step cue. Maps to FFT system bank slot 3 ("Move Cursor",
	# hex 0x03) — the canonical PSX cursor-move blip the original game played
	# on every battlefield-cursor advance.
	"ui.cursor_move": {"bank": "system", "slug": "move_cursor", "retrigger": true},
	# Dialogue typewriter cue, one blip per revealed glyph. Maps to FFT system
	# bank slot 115 ("Text Typing", hex 0x73). Fired by the DialogueBox /
	# DialogueOverlay renderers off TypewriterController's `glyph_typed` signal.
	# `retrigger` routes it to ExMateriaEffectSfx.play_click — a single reserved,
	# retriggered voice (cached bank, one channel) instead of a fire-and-forget
	# audition cast per glyph, matching the PSX and keeping the fast per-glyph
	# rate off the combat SFX pool.
	"ui.text_typing": {"bank": "system", "slug": "text_typing", "retrigger": true},
	# Multi-page boxed-dialogue page-turn blip. Maps to FFT system bank slot 45
	# ("Flip Page", hex 0x2d) — the one real *unimplemented* global dialogue
	# sound. Fired by DialogueBox.advance_page() on a real page turn (O/Circle),
	# NEVER on the final advance/close. A plain one-shot — NOT retriggered like
	# the per-glyph typewriter.
	"ui.dialogue_page_flip": {"bank": "system", "slug": "flip_page"},
}

# Handler-resolved slug map for combat.unit_died.
const _UNIT_DIED_SLUGS := {
	UnitProgression.BaseStatType.MALE: "male_death",
	UnitProgression.BaseStatType.FEMALE: "female_death",
	UnitProgression.BaseStatType.MONSTER: "monster_death",
}


func _ready() -> void:
	EventBus.unit_died.connect(_on_unit_died)


func play_cue(name: String) -> int:
	## Play a registered cue by name. Returns the audition token (0 on miss).
	var cue: Dictionary = _CUES.get(name, {})
	if cue.is_empty():
		push_warning("SfxRouter: unknown cue '%s'" % name)
		return 0
	var bank: String = cue["bank"]
	var slot: int = cue.get("slot", -1)
	if slot < 0:
		slot = SfxCatalog.slot_for(bank, cue.get("slug", ""))
	if slot < 0:
		push_warning("SfxRouter: cue '%s' has no resolvable slot (slug '%s' not in %s bank)" % [
			name, cue.get("slug", ""), bank])
		return 0
	cue_requested.emit(name, bank, slot)
	# Retrigger cues (dialogue typewriter) go to the lightweight cached +
	# reserved-voice click path instead of a fresh fire-and-forget cast.
	if cue.get("retrigger", false):
		return _play_click_slot(bank, slot)
	return _play_slot(bank, slot)


func play_system(slug: String) -> int:
	## Play a system-bank sound by its semantic slug (e.g. "gun_shot_loud_1").
	return _play_named("system", slug)


func play_system_by_id(slot: int) -> int:
	## Play a system-bank sound by raw FFT sound id (the numeric operand of the
	## event-script Sound Effect opcode {0x21}). Volume/pan are intrinsic to the
	## bank entry — no per-call mix params, mirroring the PSX dispatcher.
	if slot <= 0:
		push_warning("SfxRouter: play_system_by_id ignoring non-positive slot %d" % slot)
		return 0
	var name := SfxCatalog.name_for("system", slot)
	cue_requested.emit("system.%s" % (name if name != "" else "0x%02X" % slot), "system", slot)
	return _play_slot("system", slot)


func play_env(slug: String) -> int:
	## Play an env-bank sound by its semantic slug (e.g. "rain_1") as a one-shot
	## audition. For the full {6B} background channel (loop + volume ramp +
	## tracked/overlay stacking) use `play_bg` / `set_bg_volume` / `stop_bg_sound`.
	return _play_named("env", slug)


# --- {6B} BG Sound background-ambient channel ---------------------------------
#
# The event-script {6B}/{6A} opcodes play an env-bank ambient (handle 0x10000|id
# on PSX) as a looping/one-shot voice with a driver-side volume ramp. See
# research/working_documents/BGSOUND_OPCODE_6B_INVESTIGATION.md and ScenarioVM's
# `_op_bg_sound`. The ramp itself lives in ScenarioBgSound (ScenarioVM ticks it);
# this layer owns playback + the tracked-vs-overlay bookkeeping.

# env sound id -> live audio handle (last cast per sound; for same-sound stop).
var _bg_by_sound: Dictionary = {}
# The single tracked (Stacking=0) background handle — PSX caches one handle
# (DAT_8004599c) as "the current bg sound". 0 = none.
var _bg_tracked_handle: int = 0


func play_bg(sound_id: int, stacking: int) -> int:
	## {6B} BG Sound. Stops any currently-playing instance of the SAME env sound
	## (PSX FUN_800440f4), then (re)starts it — looping for looping ids, one-shot
	## otherwise. Stacking=0 records it as THE tracked background channel;
	## Stacking≠0 overlays on a separate voice. Returns the audio handle (0 on
	## miss) for `set_bg_volume` / `stop_bg_handle`.
	if sound_id <= 0:
		push_warning("SfxRouter: play_bg ignoring non-positive sound id %d" % sound_id)
		return 0
	# Stop any existing voices on this same sound before (re)triggering.
	stop_bg_sound(sound_id)
	# Observability fires pre-dispatch (like cue_requested) so listeners see the
	# cue even when the SPU backend can't actually play it.
	bg_sound_changed.emit("play", sound_id, stacking, 0)
	var feds_path := "%s/%s" % [BANKS_DIR, _BANK_FILES["env"]]
	# FFT sound_id N → FedsBank pair_idx N-1 (same stride as _play_slot).
	var handle: int = ExMateriaEffectSfx.begin_bg(feds_path, sound_id - 1, sound_id)
	if handle == 0:
		return 0
	_bg_by_sound[sound_id] = handle
	if stacking == 0:
		_bg_tracked_handle = handle
	return handle


func set_bg_volume(handle: int, vol: int) -> void:
	## Drive a bg cast's current volume (0..127). Called once per frame by the
	## ScenarioBgSound ramp; forwards to the per-voice SPU set-volume.
	if handle == 0:
		return
	ExMateriaEffectSfx.set_bg_gain(handle, vol)


func stop_bg_handle(handle: int) -> void:
	## Stop a bg cast by its handle (key-off ring-out).
	if handle == 0:
		return
	ExMateriaEffectSfx.stop_bg(handle)
	if _bg_tracked_handle == handle:
		_bg_tracked_handle = 0
	for sid in _bg_by_sound.keys():
		if _bg_by_sound[sid] == handle:
			_bg_by_sound.erase(sid)


func stop_bg_sound(sound_id: int) -> void:
	## Stop the currently-playing instance of a specific env sound, if any.
	var handle: int = int(_bg_by_sound.get(sound_id, 0))
	if handle == 0:
		return
	ExMateriaEffectSfx.stop_bg(handle)
	_bg_by_sound.erase(sound_id)
	if _bg_tracked_handle == handle:
		_bg_tracked_handle = 0
	bg_sound_changed.emit("stop", sound_id, 0, handle)


func stop_all_event_sound() -> void:
	## {7C} End Sound. Stop EVERY background/event voice this router is tracking
	## and clear the tracked-handle cache — the Godot mirror of PSX SUB_800440cc
	## (zero the active-sound handle DAT_8004599c + 8-voice teardown FUN_80012860).
	## Emits a "stop" cue per torn-down sound for observability (pre-dispatch, so
	## listeners see it even with no SPU backend). Idempotent: no tracked voices
	## → nothing to do.
	for sid in _bg_by_sound.keys():
		var handle: int = int(_bg_by_sound[sid])
		if handle != 0:
			ExMateriaEffectSfx.stop_bg(handle)
		bg_sound_changed.emit("stop", sid, 0, handle)
	_bg_by_sound.clear()
	_bg_tracked_handle = 0


func _play_named(bank: String, slug: String) -> int:
	var slot: int = SfxCatalog.slot_for(bank, slug)
	if slot < 0:
		push_warning("SfxRouter: unknown %s sound '%s'" % [bank, slug])
		return 0
	cue_requested.emit("%s.%s" % [bank, slug], bank, slot)
	return _play_slot(bank, slot)


func _play_slot(bank: String, slot: int) -> int:
	## Every non-retrigger cue funnels through here — play_cue, play_system,
	## play_system_by_id, play_env and the combat.unit_died handler. NONE of them
	## keeps the token or ends the cast, so this declares that to the engine with
	## play_one_shot rather than audition: a one-shot session is reclaimed as soon
	## as it is provably silent instead of holding a whole SPU unit for the
	## multi-pair grace. Charging game-event blips that grace is what let a
	## repeated cue saturate the 8-unit pool.
	var bank_file: String = _BANK_FILES.get(bank, "")
	var feds_path := "%s/%s" % [BANKS_DIR, bank_file]
	# FFT sound_id N maps to FedsBank pair_idx N-1 (the bank's stride-2 offset
	# table starts at +0x18); pass the real sid for the chan+0x92 static seed.
	return ExMateriaEffectSfx.play_one_shot(feds_path, slot - 1, slot)


func _play_click_slot(bank: String, slot: int) -> int:
	# Retriggered, reserved-voice variant of _play_slot for the per-glyph
	# dialogue blip — same slot→pair mapping, but ExMateriaEffectSfx.play_click
	# caches the bank and keeps a single cut-and-retrigger voice off the pool.
	var bank_file: String = _BANK_FILES.get(bank, "")
	var feds_path := "%s/%s" % [BANKS_DIR, bank_file]
	return ExMateriaEffectSfx.play_click(feds_path, slot - 1, slot)


func _on_unit_died(unit: Node) -> void:
	## Handler-resolved cue: slug depends on the dying unit's BaseStatType.
	## Emits cue_requested with the cue name ("combat.unit_died"), not the
	## resolved slug, so observability speaks intent rather than sample.
	var prog: Resource = unit.unit_progression if unit else null
	if prog == null:
		push_warning("SfxRouter: unit_died with no unit_progression on %s" % unit)
		return
	var slug: String = _UNIT_DIED_SLUGS.get(prog.base_stat_type, "")
	if slug.is_empty():
		push_warning("SfxRouter: unit_died with unmapped base_stat_type %d" % prog.base_stat_type)
		return
	var slot: int = SfxCatalog.slot_for("system", slug)
	if slot < 0:
		push_warning("SfxRouter: cue 'combat.unit_died' slug '%s' not in system bank" % slug)
		return
	cue_requested.emit("combat.unit_died", "system", slot)
	_play_slot("system", slot)
