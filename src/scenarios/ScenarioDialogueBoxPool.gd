class_name ScenarioDialogueBoxPool
extends RefCounted
## The scenario dialogue **box pool** — the RENDERING slice of the boxed-dialog
## subsystem, lifted out of [ScenarioVM] into a subsystem the interpreter drives.
##
## FFT keeps up to three portrait dialogue boxes on screen at once, each a
## cooperative-task slot; this module owns their Godot side: the 1-based slot pool
## built from the host-wired boxes, the align-nibble slot resolution, the per-frame
## screen-space placement (centred on the speaker, above/below, clamped to frame,
## with the mouth-triangle re-aim), the persist bit, the message-token index for
## `{51} Change Dialog` swaps, and the placement-anchor debug gizmos.
##
## Behaviour is byte-identical to the pre-extraction VM — a refactor, not a
## re-decode. It is a RENDERING-ONLY sibling of [ScenarioCameraDirector]: unlike the
## camera director (which owns a stateful cooperative task), this pool has **zero**
## scheduler knowledge. The boxed-dialog **advance gate** — which parks a
## `ScriptContext` so the interpreter waits for the player to advance — is scheduler
## state and stays in the VM; the VM's gate logic calls DOWN into this pool for
## rendering (`_foreground_box`, `_box_at`, `_slot_persists`, `_foreground_slot`),
## never the reverse. VM-wide context ([member ScenarioVM.units_by_id],
## `_active_camera`, `_resolve_unit_key`, `_insts`) is read live through a
## back-reference so it stays single-sourced on the VM.

## Back-reference to the owning interpreter — the pool reads VM-wide context
## (the unit table, the active camera, the operand-message index) through it.
var _vm: ScenarioVM = null


func _init(vm: ScenarioVM) -> void:
	_vm = vm


## Bind the boxed-dialogue placement knobs to their `dialbox.*` Tune slugs (ADR-0068).
## This pool OWNS the values, so a committed override coalesces onto the live box AND a
## scrub re-drives an already-open box in any scene — the dialogue-box debug panel is
## just a view (decision 12), and the tuning survives a scenario reload for free (the
## fresh pool re-reads the slugs). This pool is a RefCounted, so it can't be the bind
## owner itself — `owner` (the ScenarioVM Node) provides the tree_exited lifetime;
## the apply closures capture `self`, which lives exactly as long as that VM. Called
## from ScenarioVM._ready with the VM as owner. Defaults come from the resting property
## state so there is no rival literal. box_offset_px (a Vector2, no TuneField control)
## is split into two float slugs whose applies each drive one component.
func bind_tunables(owner: Node) -> void:
	Tune.on_update(owner, BOX_SIZE_SCALE_SLUG, func(v: float) -> void: box_size_scale = v)
	Tune.on_update(owner, BOX_GAP_ABOVE_SLUG, func(v: float) -> void: box_gap_above_px = v)
	Tune.on_update(owner, BOX_GAP_BELOW_SLUG, func(v: float) -> void: box_gap_below_px = v)
	Tune.on_update(owner, BOX_OFFSET_X_SLUG, func(v: float) -> void: box_offset_px.x = v)
	Tune.on_update(owner, BOX_OFFSET_Y_SLUG, func(v: float) -> void: box_offset_px.y = v)
	Tune.on_update(owner, TRI_AIM_BIAS_SLUG, func(v: float) -> void: tri_aim_bias_px = v)
	Tune.on_update(owner, TRI_AIM_SCALE_SLUG, func(v: float) -> void: tri_aim_scale = v)
	Tune.on_update(owner, ANCHOR_TO_BILLBOARD_SLUG, func(v: bool) -> void: anchor_to_billboard = v)
	Tune.on_update(owner, ANCHOR_QUAD_FRAC_Y_SLUG, func(v: float) -> void: anchor_quad_frac_y = v)
	Tune.on_update(owner, DEBUG_SHOW_BOX_ANCHORS_SLUG, func(v: bool) -> void: debug_show_box_anchors = v)
	Tune.on_update(owner, DEBUG_SHOW_TILE_ORB_SLUG, func(v: bool) -> void: debug_show_tile_orb = v)


## Register the dialbox.* slugs to their static-var homes + hints ONCE at class load (R2), so a
## committed override coalesces the instant ScenarioVM wires the box pool and the dashboard can
## enumerate the knobs before then. Split from bind_tunables (the per-owner on_update push) so
## it is this owner's named registration entry point — _static_init calls it at class load, and
## the ADR-0173 guards call it to read back which slugs this owner binds.
static func _static_init() -> void:
	if Engine.is_editor_hint():
		return
	register_tunables()


static func register_tunables() -> void:
	Tune.bind(BOX_SIZE_SCALE_SLUG, BOX_SIZE_SCALE_DEFAULT, BOX_SIZE_SCALE_HINT)
	Tune.bind(BOX_GAP_ABOVE_SLUG, BOX_GAP_ABOVE_DEFAULT, BOX_GAP_HINT)
	Tune.bind(BOX_GAP_BELOW_SLUG, BOX_GAP_BELOW_DEFAULT, BOX_GAP_HINT)
	Tune.bind(BOX_OFFSET_X_SLUG, BOX_OFFSET_X_DEFAULT, BOX_OFFSET_X_HINT)
	Tune.bind(BOX_OFFSET_Y_SLUG, BOX_OFFSET_Y_DEFAULT, BOX_OFFSET_Y_HINT)
	Tune.bind(TRI_AIM_BIAS_SLUG, TRI_AIM_BIAS_DEFAULT, TRI_AIM_BIAS_HINT)
	Tune.bind(TRI_AIM_SCALE_SLUG, TRI_AIM_SCALE_DEFAULT, TRI_AIM_SCALE_HINT)
	Tune.bind(ANCHOR_TO_BILLBOARD_SLUG, ANCHOR_TO_BILLBOARD_DEFAULT)
	Tune.bind(ANCHOR_QUAD_FRAC_Y_SLUG, ANCHOR_QUAD_FRAC_Y_DEFAULT, ANCHOR_QUAD_FRAC_Y_HINT)
	Tune.bind(DEBUG_SHOW_BOX_ANCHORS_SLUG, DEBUG_SHOW_BOX_ANCHORS_DEFAULT)
	Tune.bind(DEBUG_SHOW_TILE_ORB_SLUG, DEBUG_SHOW_TILE_ORB_DEFAULT)


# --- Box pool state ----------------------------------------------------------

## DialogueBox (ui3 screen-space assembly) for the BOXED `0x10 Display Message`
## variants (Dialog=0x1X/0x9X, and 0x7X→0x1X) — the 3-line portrait dialogue
## with speaker triangle + Cross-advance. See
## `research/working_documents/scenario_1_captures/boxed_dialog_decode.md`.
## Optional: when null, the boxed handler degrades to clear-overlay + skip-log
## (VM-only unit tests don't need the assembly). This is box slot 1 of the pool.
var dialogue_box: Node = null

## Extra DialogueBox nodes for concurrent-box slots 2..N (host-wired). FFT keeps
## up to THREE dialogue boxes on screen at once — the Orbonne opening puts two up
## together (top Gafgarion / bottom Agrias) and the 161-176 beat stacks three.
## PSX models each as a cooperative-task slot with a `kind`: a box opens kind-1
## (foreground, gated by `{E5} Task=1`) and is demoted to kind-0x33 (background,
## still rendered, ungated) when a newer box supersedes it; `{51} Change Dialog
## Target=N` closes box N by open-order slot. See
## `research/working_documents/scenario_1_captures/concurrent_dialogue_boxes_decode.md`.
## Together with `dialogue_box` these form the 1-based `_box_slots` pool. When the
## host wires fewer boxes than a scene opens concurrently, allocation degrades to
## reusing the foreground box (the old single-box overwrite) with a warning.
var extra_dialogue_boxes: Array = []
## The 1-based box pool, built lazily from `dialogue_box` + `extra_dialogue_boxes`
## on first use. `_box_slots[N-1]` is box N (matching `Change Dialog`'s 1-based
## `Target`). Nodes are host-owned; the pool array just orders them.
var _box_slots: Array = []
## Open-order slot (1-based) of the current FOREGROUND (kind-1) box — the one a
## `Wait For Instruction Task=1` gates on. 0 = no foreground box. Demoted
## (kind-0x33) boxes stay in their slots, visible, but aren't the foreground.
var _foreground_slot: int = 0
## Per-slot PERSIST bit = the box's Dialog byte bit 0x80. When SET (0x9x messages)
## the box stays rendered as a background box after it's advanced / superseded,
## and only closes on a `Change Dialog Target=N` (0xFFFF). When CLEAR (e.g. msg2
## Dialog=0x12) the box CLOSES the moment it stops being the foreground — matching
## PSX, where the Display Message handler stashes (Dialog & 0x80) per box
## (0x80130998) and the dialog fiber tears the slot down (LAB_80131a80 @0x80131a30)
## when the bit is clear. This is what keeps the first Orbonne event one-box-at-a-
## time (msg2 bottom closes before msg3 top opens) vs the 147-154 beat's two boxes
## (both 0x9x). Slot -> bool; absent = treat as persist (never close unexpectedly).
var _slot_persists: Dictionary = {}

## Live-tunable dialogue-box placement fudge — dial in via the "Scenario Dialogue
## Box" F3 debug panel (or the inspector). Applied in `_place_box_on_unit`, which
## now re-runs EVERY FRAME while a box is open, so these take effect immediately
## on an already-open box (the box also tracks the speaker/camera live).
##
## NOTE (2026-07-02): placement moved to the faithful native-px [DialogueBoxPlacement]
## solver. `box_size_scale` (box on-screen size) and `box_offset_px` (final eyeball
## trim) still feed placement; `box_gap_above_px`/`box_gap_below_px` and
## `tri_aim_bias_px`/`tri_aim_scale` are **SUPERSEDED** — the solver owns the align
## vertical (0x28 above / 0 below) and the tail (local_b8). They remain as inert
## fields only so the debug-panel binding keeps working.
##   box_size_scale — multiplies the box's on-screen size. The default box is
##     sized to the CombatUI rig, which reads SMALLER than the PSX box relative
##     to the 256x240 native frame; bump this until it matches. (Faithful fix TBD:
##     derive size as box_native_px / 256 of the viewport width.)
##   box_gap_above_px / box_gap_below_px — the FIXED native-px distance between the
##     unit's projected feet-point P and the box's NEAR edge, per align. This is
##     the PSX model: align 1 (box above) → box bottom edge sits `box_gap_above_px`
##     px above P (PSX uses 0x28 = 40); align 2/0 (box below) → box top edge sits
##     `box_gap_below_px` px below P (PSX uses 0). Tune these to move the box
##     toward/away from the speaker vertically — they replace the old world-space
##     `gap` + `box_offset_px.y` hack, which mixed unit systems.
##   box_offset_px  — global fine-nudge of the final anchor in native 256x240 px
##     (applied AFTER the edge-clamp): X = right+, Y = down+. For small X trims;
##     vertical placement now lives in box_gap_*_px above.
# --- dialbox.* placement tunables (ADR-0068) --------------------------------
# Each slug's home lives HERE (not in ScenarioDialogueBoxDebugPanel): a static-var DEFAULT
# (materializable, R1 — not a const, not a bind_update-forwarded property) + a HINT const,
# bound in register_tunables(); the panel reads both back from the registry as a pure view.
# box_offset_px (a Vector2, no TuneField control) is split into two float-slug homes.
const BOX_SIZE_SCALE_SLUG := "dialbox.box_size_scale"
static var BOX_SIZE_SCALE_DEFAULT := 1.35
const BOX_SIZE_SCALE_HINT := {"min": 0.1, "max": 5.0, "step": 0.05}
const BOX_GAP_ABOVE_SLUG := "dialbox.box_gap_above_px"
static var BOX_GAP_ABOVE_DEFAULT := 37.0
const BOX_GAP_BELOW_SLUG := "dialbox.box_gap_below_px"
static var BOX_GAP_BELOW_DEFAULT := 5.0
const BOX_GAP_HINT := {"min": -240.0, "max": 240.0, "step": 1.0}  # shared above/below
const BOX_OFFSET_X_SLUG := "dialbox.box_offset_x"
static var BOX_OFFSET_X_DEFAULT := 0.0
const BOX_OFFSET_X_HINT := {"min": -256.0, "max": 256.0, "step": 1.0}
const BOX_OFFSET_Y_SLUG := "dialbox.box_offset_y"
static var BOX_OFFSET_Y_DEFAULT := 0.0
const BOX_OFFSET_Y_HINT := {"min": -240.0, "max": 240.0, "step": 1.0}
const TRI_AIM_BIAS_SLUG := "dialbox.tri_aim_bias_px"
static var TRI_AIM_BIAS_DEFAULT := 0.0
const TRI_AIM_BIAS_HINT := {"min": -128.0, "max": 128.0, "step": 1.0}
const TRI_AIM_SCALE_SLUG := "dialbox.tri_aim_scale"
static var TRI_AIM_SCALE_DEFAULT := 1.0
const TRI_AIM_SCALE_HINT := {"min": 0.0, "max": 4.0, "step": 0.01}
const ANCHOR_TO_BILLBOARD_SLUG := "dialbox.anchor_to_billboard"
static var ANCHOR_TO_BILLBOARD_DEFAULT := true  # bool → checkbox, no hint
const ANCHOR_QUAD_FRAC_Y_SLUG := "dialbox.anchor_quad_frac_y"
static var ANCHOR_QUAD_FRAC_Y_DEFAULT := 0.0
const ANCHOR_QUAD_FRAC_Y_HINT := {"min": -1.0, "max": 1.0, "step": 0.01}
const DEBUG_SHOW_BOX_ANCHORS_SLUG := "dialbox.debug_show_box_anchors"
static var DEBUG_SHOW_BOX_ANCHORS_DEFAULT := false  # bool → checkbox, no hint
const DEBUG_SHOW_TILE_ORB_SLUG := "dialbox.debug_show_tile_orb"
static var DEBUG_SHOW_TILE_ORB_DEFAULT := false  # bool → checkbox, no hint

var box_size_scale: float = BOX_SIZE_SCALE_DEFAULT  # user-calibrated vs PSX (was 1.0 = CombatUI rig)
var box_gap_above_px: float = BOX_GAP_ABOVE_DEFAULT  # feet-pivot→box-bottom-edge (align 1)
var box_gap_below_px: float = BOX_GAP_BELOW_DEFAULT   # feet-pivot→box-top-edge (align 2/0)
var box_offset_px: Vector2 = Vector2(BOX_OFFSET_X_DEFAULT, BOX_OFFSET_Y_DEFAULT)

## Draw debug gizmos while a box is open (toggle in the "Scenario Dialogue Box"
## panel): a RED dot at P (the unit anchor), a GREEN dot at the ACTUAL triangle
## node (its cell centre — the tip sits a few px off per the cell shape), and a
## YELLOW stem connecting them, so you can SEE the tail-vs-unit relationship and
## tune against it. (Green tracks the real triangle, not a separate estimate.)
var debug_show_box_anchors: bool = DEBUG_SHOW_BOX_ANCHORS_DEFAULT

## Draw a CYAN world-space orb at the speaker's actual logical position (its
## origin = global_position). Unlike the RED dot (which is the origin projected
## through the camera as a camera-child), this is a real 3D object in the world,
## so it renders wherever the camera genuinely projects that world point. Compare
## it against the red dot and the sprite's visible centre: if they don't line up,
## the billboarded sprite is being drawn off its logical position (a shader/
## billboard offset), not a dialog-anchor bug.
var debug_show_tile_orb: bool = DEBUG_SHOW_TILE_ORB_DEFAULT

## Anchor the dialog box + tail to a point on the sprite's BILLBOARDED quad rather
## than the raw origin, so it tracks where the sprite is actually DRAWN. The sprite
## is a camera-facing billboard: unit.gdshader's billboard() makes the quad's basis
## the camera axes (canceled by VIEW → identity in view space), so a local quad
## point (0, vy, 0) lands at origin_in_view + (0, vy*scale, 0) — a pure screen-space
## slide. We mirror that ONE point on the CPU (the GPU billboards all 4 verts for
## the draw; we only need the anchor). `anchor_quad_frac_y` is that point's local
## quad-Y in HALF-quad units: 0 = origin, negative = down toward the feet, -0.5 =
## the quad's bottom EDGE. CAUTION: the quad is ~8 world units tall with the
## character in a small central slice, so the bottom edge (-0.5) is ~460 px BELOW
## the visible feet — the feet sit only slightly below the origin, so this wants a
## SMALL negative value (dial it live). Turn OFF to fall back to the raw origin.
## NOTE: CPU mirror of the shader — if billboard()/the PAR math changes, update
## `_sprite_billboard_anchor` to match.
var anchor_to_billboard: bool = ANCHOR_TO_BILLBOARD_DEFAULT
var anchor_quad_frac_y: float = ANCHOR_QUAD_FRAC_Y_DEFAULT

## Speaker-triangle (mouth-pointer tail) aim tuning — dial in via the "Scenario
## Dialogue Box" panel. The tail points at the speaker's projected screen-X (the
## sprite's centre column); these two knobs correct where that lands:
##   tri_aim_bias_px  — constant native-px shift of the tail. Default −4 for
##     byte-parity with PSX, which computes the tail centre as `box_x − 4`,
##     i.e. it aims ~4 px LEFT of the exact sprite centre (the authentic
##     `box_x −4` term — see dialogue_box_triangle_aim_decode.md §3).
##   tri_aim_scale    — proportional gain on the aim offset (if the tail drifts
##     MORE the farther the speaker is from box centre → a PAR-type ratio error).
## NOTE: there is no mouth/head-height term. The PSX projects the unit's FEET
## SVECTOR (terrain floor), and a vertical world move is horizontally inert under
## both the GTE and the iso camera — so head height cannot shift the tail in X.
## The old `tri_mouth_height` knob was retired 2026-07-01 (non-faithful + inert).
var tri_aim_bias_px: float = TRI_AIM_BIAS_DEFAULT
var tri_aim_scale: float = TRI_AIM_SCALE_DEFAULT

# Speaker + Dialog byte of the currently-open boxed message. Retained so the box
# re-places live each frame (follows the unit + the camera, and picks up debug-
# panel tuning). Cleared when the box closes / on VM reset.
var _box_speaker: Node = null
var _box_dialog: int = 0
# Authored placement operands of the OPEN box (decode §1a), retained so the box
# re-places faithfully every frame. X58/Y5c = signed box offsets (msg+0x58/+0x5c),
# fineX60 = signed tail fine-X (msg+0x60, "Arrow X" param), arrow_byte = msg+0x64
# ("Open Type": low nibble open-tween, high nibble ±16px tail nudge/mirror gate),
# local_ac = portrait row − 1 (msg+0x0c; ≥8 resets the ▼ arrow's right bump).
var _box_x58: int = 0
var _box_y5c: int = 0
var _box_fine_x60: int = 0
var _box_arrow_byte: int = 0
var _box_local_ac: int = -1

# message_id -> baked tokens, indexed from the chunk's Display Message records
# so `Change Dialog` swaps (Message != 0xFFFF) can resolve their new text.
var _message_tokens: Dictionary = {}


# --- Message-token index -----------------------------------------------------

# Build message_id -> tokens from every Display Message record so a later
# `Change Dialog` swap (Message != 0xFFFF) can resolve its replacement text.
# (The disassembler bakes `dialogue.tokens` onto Display Message records but not
# onto Change Dialog; swaps whose message never appears as a Display Message
# can't be resolved here and degrade to keeping the current box.)
func _index_message_tokens() -> void:
	_message_tokens.clear()
	for inst in _vm._insts:
		if str(inst.get("name", "")) != "Display Message":
			continue
		var dlg: Dictionary = inst.get("dialogue", {})
		var mid: int = int(dlg.get("message_id", -1))
		var toks: Array = dlg.get("tokens", [])
		if mid >= 0 and not toks.is_empty():
			_message_tokens[mid] = toks


# --- Slot pool ---------------------------------------------------------------

## True when the Dialog byte selects a 3-line portrait box we render. The box
## type is the high nibble masked with 0x70: 0x10 covers 0x1X AND 0x9X (the
## `{51}`-close bit 0x80 doesn't change the box type), and 0x70 is the ROM's
## remap-to-0x10 case.
##
## The remap is real and load-bearing — 814 of our 3,745 live Display Messages are
## `Dialog = 0x70`. `0x80130930`: `(Dialog & 0x70) == 0x70` → `local_d2 =
## (Dialog & 0x1C) | 0x10` (`andi 0x1c` @`0x80130940`, `ori 0x10` @`0x80130944`) with
## the align OR-ed in from `dialog_auto_align_from_facing` @`0x80130950`; ONLY THEN is
## the class taken, `local_d0 = local_d2 & 0x70` @`0x80130980`. So those messages reach
## the tween gate @`0x8013132c` as class 0x10 and get the ordinary portrait-box grow +
## curve-4 close. Reading `local_d0` off the RAW byte makes them look like a second box
## family that should get `FUN_80132914`'s centre-out reveal and no close — it is not;
## guarded by `DialogueBoxTest._test_dialog_70_is_the_remap_to_class_10`.
func _is_boxed_dialog(dialog: int) -> bool:
	var box_type := dialog & 0x70
	return box_type == 0x10 or box_type == 0x70


## The 1-based box pool, built lazily from the host-wired `dialogue_box` (slot 1)
## + `extra_dialogue_boxes` (slots 2..N). `_box_slots[N-1]` is box N.
func _box_pool() -> Array:
	if _box_slots.is_empty():
		if dialogue_box != null:
			_box_slots.append(dialogue_box)
		for b in extra_dialogue_boxes:
			if b != null and not _box_slots.has(b):
				_box_slots.append(b)
	return _box_slots


## The DialogueBox at 1-based `slot`, or null if out of range.
func _box_at(slot: int) -> Node:
	var pool := _box_pool()
	if slot >= 1 and slot <= pool.size():
		return pool[slot - 1]
	return null


## The current foreground (kind-1) box, or null when none is up.
func _foreground_box() -> Node:
	return _box_at(_foreground_slot)


## Tear down every pooled box + clear the foreground pointer (on start / rewind
## replay so a fresh run has no residual boxes on screen).
func _close_all_boxes() -> void:
	_foreground_slot = 0
	_slot_persists.clear()
	_hide_box_anchor_gizmo()
	_hide_tile_orb()
	for box in _box_pool():
		if box != null and box.has_method("close") \
				and box.has_method("is_active") and box.is_active():
			box.close()


## The pool slot a Display Message opens into = its SCREEN POSITION = the align
## nibble `Dialog & 0x3` (1=top, 2=bottom; PSX's 0x80166084 slot array is indexed
## by this, and `Change Dialog`'s 1-based `Target` addresses the same index —
## `Target == align`, verified across the whole scenario-1 dialog script, not just
## the 147-154 window). So a new box REPLACES any box already at its position (two
## boxes never stack at the same align — the Orbonne beats keep exactly one top +
## one bottom), and no box leaks: every `Target=N` close lands on the box at that
## position. `align`-derived slot supersedes the naive "lowest free slot"
## (open-order) reading, which cascades into wrong-box closes once two same-align
## messages appear. Clamped to the wired pool size so a single-box host/test still
## renders every message (an align-2 message with only slot 1 wired → slot 1).
func _slot_for_dialog(dialog: int) -> int:
	var pool := _box_pool()
	if pool.is_empty():
		return 0
	var slot := dialog & 0x3
	if slot < 1 or slot > pool.size():
		slot = 1
	return slot


## Resolve the speaker portrait + screen offset and show the box in its POSITION
## slot (`Dialog & 3`); any box at a DIFFERENT position stays visible (the PSX
## kind-0x33 background state), a box already at THIS position is replaced. Make it
## the foreground, then arm the advance gate for the next `Wait For Instruction`.
func _show_dialog_box(tokens: Array, dialog: int, speaker_uid: int, portrait_row: int, open_type: int = 3, x58: int = 0, y5c: int = 0, fine_x60: int = 0) -> void:
	var slot := _slot_for_dialog(dialog)
	var box := _box_at(slot)
	if box == null:
		return
	_foreground_slot = slot
	_slot_persists[slot] = (dialog & 0x80) != 0

	# Portrait source routing (PORTRAIT_ROW_OPCODE_50_EVTFACE.md §2.6, §8; scn14
	# ground-truthed by the user). `portrait_row` here is the {10} Portrait byte (a
	# 1-based EVTFACE column, misnamed). Two sources, in priority order:
	#   1. EVTFACE OVERRIDE — a scripted event portrait, drawn iff (Dialog&0x70)==0x10
	#      AND the byte is in [1,8] AND a {50} row is active for the scene. scn14:
	#      only Balbanes (speaker 0x80, Portrait=1) takes this path.
	#   2. SPEAKER unit-SPR fallback — the box otherwise shows the SPEAKER's own
	#      portrait from its sprite sheet (the sons at the deathbed speak with
	#      Portrait=0; their faces come from their unit SPR, which is where PSX
	#      sources them). Suppressed only by the 0x09 "no portrait" sentinel.
	# (The Portrait byte is an EVTFACE-column OVERRIDE, not a global on/off — a 0 does
	# NOT blank the box, it just falls through to the speaker's own face.)
	var sprite_id := -1
	var evtface_tex: Texture2D = null
	var speaker: Node = null
	var key := _vm._resolve_unit_key(speaker_uid)
	if key != -1:
		speaker = _vm.units_by_id[key]
	# A unique speaker's OWNED portrait.tga fronts its unit-SPR fallback (#223): the
	# scenario spawn seam resolved `template_folder` onto the Unit (mirroring #205's
	# roster/info-window seam — the pool reads it, it does not call the resolver). ""
	# for generics/monsters keeps the flat sprite-sheet portrait. EVTFACE still wins.
	var template_folder := ""
	evtface_tex = _resolve_evtface(dialog, portrait_row)
	if evtface_tex == null and portrait_row != 0x09 and speaker != null \
			and "body_sprite_id" in speaker:
		sprite_id = int(speaker.body_sprite_id)
		if "template_folder" in speaker:
			template_folder = String(speaker.template_folder)

	# When the box is mounted under the (orthographic) scenario camera we can
	# centre it on the speaker in camera-local space — then the mouth triangle
	# sits at the box centre (offset 0). Otherwise (standalone/test) fall back
	# to a screen-projected triangle aim with no repositioning.
	var cam := _vm._active_camera()
	var can_place := cam != null and (speaker is Node3D) and (box is Node3D) \
		and box.get_parent() == cam
	var unit_offset := 0.0 if can_place else _speaker_screen_offset(speaker)

	if box.has_method("show_dialog"):
		box.show_dialog(tokens, dialog, sprite_id, unit_offset, open_type, evtface_tex, template_folder)
	if can_place:
		# Track this speaker + the authored operands so the FOREGROUND box re-places
		# live each frame (below). Set BEFORE _place_box_on_unit — it reads them.
		_box_speaker = speaker
		_box_dialog = dialog
		_box_x58 = x58
		_box_y5c = y5c
		_box_fine_x60 = fine_x60
		_box_arrow_byte = open_type
		_box_local_ac = ScenarioDecode.portrait_column(portrait_row)
		_place_box_on_unit(cam, speaker, dialog, box)
	else:
		_box_speaker = null


## Resolve the EVTFACE OVERRIDE texture for a box: the scripted event portrait
## `EVTFACE[{50} row, col = portrait_byte - 1]`, drawn IFF a {50} row is active AND
## (Dialog & 0x70) == 0x10 AND portrait_byte in [1,8] (§2.6). Returns null when the
## override doesn't apply (the caller falls back to the speaker's unit-SPR, or —
## on a {51} swap — leaves the current face untouched). Shared by the {10} show
## path and the {51} in-place swap so both route portraits identically (issue #165).
func _resolve_evtface(dialog: int, portrait_byte: int) -> Texture2D:
	if _vm._portrait_row >= 0 and ScenarioDecode.portrait_visible(dialog, portrait_byte):
		return EvtFaceCatalog.face_texture(_vm._portrait_row,
			ScenarioDecode.portrait_column(portrait_byte))
	return null


# --- Per-frame placement -----------------------------------------------------

# Re-place the currently-open box each frame so it tracks its speaker + the
# camera and picks up live debug-panel tuning. No-op once the box has closed
func _reposition_open_box() -> void:
	if _box_speaker == null:
		_hide_box_anchor_gizmo()
		_hide_tile_orb()
		return
	var box := _foreground_box()
	if not is_instance_valid(_box_speaker) or box == null:
		_box_speaker = null
		_hide_box_anchor_gizmo()
		_hide_tile_orb()
		return
	if box.has_method("is_open") and not box.is_open():
		_box_speaker = null
		_hide_box_anchor_gizmo()
		_hide_tile_orb()
		return
	var cam := _vm._active_camera()
	if cam != null and box is Node3D and box.get_parent() == cam:
		_place_box_on_unit(cam, _box_speaker, _box_dialog, box)


# Centre the top-left-anchored box horizontally on the speaker and place it
# above (align 1) or below (align 2/0) the unit, in the camera's local space
# (the box is a child of the orthographic camera, so its position IS cam-local).
# The box is clamped to stay inside the visible frame; the mouth triangle is
# then re-aimed at the speaker so it still points at them even when clamped.
func _place_box_on_unit(cam: Camera3D, speaker: Node, dialog: int, box: Node) -> void:
	var local: Vector3 = _sprite_billboard_anchor(cam, speaker as Node3D)

	# The box is a child of the cinematic camera, so it would scale with the
	# camera's zoom. Real FFT renders the box as a FIXED-size screen overlay, so
	# compensate: scale inversely with the camera's ortho size relative to the
	# ui3 design size (DIALOG_BOX_REF_ORTHO). This keeps a constant on-screen
	# size — the same one the box has under the CombatUITest ortho-12.6 rig.
	const DIALOG_BOX_REF_ORTHO := 12.6
	var box_scale := 1.0
	if cam.size > 0.0:
		box_scale = cam.size / DIALOG_BOX_REF_ORTHO
	# Live "box looks too small vs PSX" fudge (see box_size_scale docstring).
	box_scale *= maxf(0.01, box_size_scale)
	# Feed the zoom scale as the box's tween BASE (not the live node scale) so the
	# open/close grow-shrink tween composes on top of it (Part B); fall back to a
	# direct write for a box without the tween API.
	if box.has_method("set_zoom_scale"):
		box.set_zoom_scale(Vector3(box_scale, box_scale, 1.0))
	else:
		(box as Node3D).scale = Vector3(box_scale, box_scale, 1.0)

	# Native-px ↔ cam-local-world scales, taken from the BOX's own pixel model so
	# the placed rect and the rendered box are one coordinate system (the tail and
	# portrait then track exactly what's drawn). A native px is `par*ppu*box_scale`
	# world wide (PAR = non-square PSX px) and `ppu*box_scale` world tall. The box
	# renders `box_w_px` px, so its on-screen edges land exactly on the solved rect.
	var par := 1.25
	if PSXDisplay != null:
		par = PSXDisplay.live_ui_par
	var ppu := 0.04
	if "pixels_per_unit" in box:
		ppu = box.pixels_per_unit
	var wpp_x := par * ppu * box_scale       # world per native px (horizontal, PAR)
	var wpp_y := ppu * box_scale             # world per native px (vertical)
	if wpp_x <= 0.0 or wpp_y <= 0.0:
		return
	var size_world := Vector2.ZERO
	if box.has_method("get_box_size_world"):
		size_world = box.get_box_size_world()  # = (box_w_px*par*ppu, box_h_px*ppu)
	var box_w_px := int(round(size_world.x / (par * ppu)))
	var box_h_px := int(round(size_world.y / ppu))

	# Project the speaker into the PSX native 256x240 frame the SAME way the sprite
	# is DRAWN, so the box tracks the *visible* sprite column (ROOT B, decode §8.2).
	# The unit sprite billboards on its UnitMesh and the shader stretches screen-X by
	# the global PSX PAR (unit.gdshader); the box is a plain cam-child with no PAR
	# shader. The old `local.x / wpp_x` projected the anchor on the BOX's render
	# scale (wpp_x carries `box_size_scale`), leaving proj un-PAR-stretched — so an
	# off-centre unit's box drifted toward screen centre by a uniform 1/PAR≈0.78
	# (msg8 feet drawn at 77.7 but box centred ~96 → the ~18px right miss). Fix:
	# reproduce the sprite's own projection — unproject the mesh origin to native,
	# then PAR-stretch about native-x 128. This is byte-identical to the drawn-feet
	# projection (decode §8.2 `feet_D`), so proj == feet_D and the box centres on
	# the drawn sprite. Independent of wpp_x/box_scale (which cancel in the box's
	# on-screen size), so the golden solver + box sizes are untouched.
	var proj_x: int
	var proj_y: int
	var _anchor_world: Vector3 = (speaker as Node3D).global_position
	var _proj_mesh := (speaker as Node3D).get_node_or_null("UnitMesh") as Node3D
	if _proj_mesh != null:
		_anchor_world = _proj_mesh.global_position
	# ROOT-B (above) anchors on the DRAWN sprite column. §9.6/§9.7 corrects this for
	# POSE-DISPLACED speakers: PSX projects the unit's BASE SVECTOR (`unit+0x40` =
	# tile), NOT the sprite drawn at `base + 0x60`. Simon's carry pose (Sprite Move
	# offset −64) puts his sprite ~65px left of his tile; anchoring on the sprite AND
	# applying the authored `X58/fineX60` pose-compensation operands double-compensates
	# and strands the tail 76px left. So slide the anchor from the drawn-sprite (work)
	# column back to the base (tile) column by subtracting the current pose displacement
	# (work − base). This is ZERO for never-moved / non-displaced units, so their boxes
	# stay byte-identical to ROOT-B; only a Sprite-Moved speaker (Simon) shifts. The
	# base lives in the VM's `_unit_move_home` (captured on the unit's first move).
	if _vm != null and speaker is Node3D:
		var _base: Vector3 = _vm.sprite_move_base_position(speaker)
		_anchor_world -= ((speaker as Node3D).global_position - _base)
	var _proj_vp := cam.get_viewport().get_visible_rect().size
	if _proj_vp.x > 0.0 and _proj_vp.y > 0.0 and not cam.is_position_behind(_anchor_world):
		var _proj_s := cam.unproject_position(_anchor_world)
		var _proj_nx := _proj_s.x * (256.0 / _proj_vp.x)
		var _proj_ny := _proj_s.y * (240.0 / _proj_vp.y)
		proj_x = int(round(128.0 + (_proj_nx - 128.0) * par))  # PAR-stretch = drawn column
		proj_y = int(round(_proj_ny))
	else:
		# Fallback (behind camera / no viewport): the old cam-local projection.
		proj_x = int(round(128.0 + local.x / wpp_x))
		proj_y = int(round(120.0 - local.y / wpp_y))

	# Reverse-engineered placement (native px, exact integer clamps + shove): the
	# authored operands interact with the screen-edge clamps identically to PSX.
	# See src/scenarios/DialogueBoxPlacement.gd + dialogue_box_triangle_aim_decode.md.
	var pl := DialogueBoxPlacement.solve(
		proj_x, proj_y, box_w_px, box_h_px,
		dialog, _box_arrow_byte,
		_box_x58, _box_y5c, _box_fine_x60, _box_local_ac)

	# Map the solved top-left corner back to cam-local world.
	var box_left_px: float = float(pl["box_left"])
	var box_top_px: float = float(pl["box_top"])
	var left_x := (box_left_px - 128.0) * wpp_x
	var top_y := (120.0 - box_top_px) * wpp_y

	# Global fine-nudge (native px → world; X = right+, Y = down+). Superseded knobs
	# box_gap_*_px / tri_aim_* no longer feed placement (the solver owns vertical +
	# tail); box_offset_px stays as the one live eyeball trim.
	if box_offset_px != Vector2.ZERO:
		left_x += box_offset_px.x * wpp_x
		top_y += -box_offset_px.y * wpp_y

	var keep_z: float = (box as Node3D).position.z
	if box.has_method("get_base_position"):
		keep_z = box.get_base_position().z
	# Set the box's tween BASE position (the grow/shrink offsets compose on top).
	if box.has_method("set_base_position"):
		box.set_base_position(Vector3(left_x, top_y, keep_z))
	else:
		(box as Node3D).position = Vector3(left_x, top_y, keep_z)

	# Tail + portrait side both key on local_b8 (native px == the box's own px, so
	# it feeds `set_triangle_aim` directly — _layout_triangle computes the same
	# `tri_x = w/2 + local_b8 − 8`). Portrait docks on the sign of local_b8 (§7.1):
	# an edge-clamp shove OR an authored fine-X can flip it, arrow stays put (§7.2).
	var local_b8: int = pl["local_b8"]
	if box.has_method("set_triangle_aim"):
		box.set_triangle_aim(float(local_b8))
	if box.has_method("set_portrait_side"):
		box.set_portrait_side(not bool(pl["portrait_side_right"]))

	# Debug: draw the two anchors — RED at P (the unit anchor), GREEN at the ACTUAL
	# triangle node so the stem shows where the tail really sits vs the unit (not a
	# separately-computed guess). Falls back to the box near-edge if no Triangle.
	if debug_show_box_anchors:
		var align := dialog & 0x3
		var size_scaled := size_world * box_scale
		var green_local: Vector3
		var tri := (box as Node).get_node_or_null("Triangle")
		if tri != null and tri is Node3D:
			green_local = cam.to_local((tri as Node3D).global_position)
		else:
			var attach_y := (top_y - size_scaled.y) if align == 1 else top_y  # box edge facing P
			var attach_x: float = clampf(local.x, left_x, left_x + size_scaled.x)
			green_local = Vector3(attach_x, attach_y, keep_z)
		_update_box_anchor_gizmo(cam,
			Vector3(local.x, local.y, keep_z),        # P (unit anchor)
			green_local,                              # the actual triangle node
			wpp_y)
	else:
		_hide_box_anchor_gizmo()

	# Debug: world-space ground-0 orb at the speaker's logical tile centre.
	if debug_show_tile_orb:
		_update_tile_orb(speaker as Node3D)
	else:
		_hide_tile_orb()


# --- Placement-anchor debug gizmos (P = feet, box near-edge attach point) ------
# Lazily built as children of the cinematic camera (cam-local space, matching the
# box), so the dots stay screen-locked. Toggled by `debug_show_box_anchors`.
var _box_anchor_root: Node3D = null
var _box_anchor_p: MeshInstance3D = null
var _box_anchor_attach: MeshInstance3D = null
var _box_anchor_stem: MeshInstance3D = null


func _make_anchor_marker(color: Color, priority: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	# psx-ot-depth-exempt: debug gizmo, no_depth_test, not a battle mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mat.render_priority = priority
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


func _ensure_box_anchor_gizmo(cam: Camera3D) -> void:
	if _box_anchor_root != null and is_instance_valid(_box_anchor_root):
		if _box_anchor_root.get_parent() != cam:
			_box_anchor_root.get_parent().remove_child(_box_anchor_root)
			cam.add_child(_box_anchor_root)
		return
	_box_anchor_root = Node3D.new()
	_box_anchor_root.name = "BoxAnchorGizmo"
	cam.add_child(_box_anchor_root)
	_box_anchor_stem = _make_anchor_marker(Color(1.0, 0.9, 0.1, 0.85), 3)  # yellow stem
	_box_anchor_p = _make_anchor_marker(Color(1.0, 0.15, 0.15, 1.0), 4)    # red P
	_box_anchor_attach = _make_anchor_marker(Color(0.2, 1.0, 0.3, 1.0), 4) # green attach
	_box_anchor_root.add_child(_box_anchor_stem)
	_box_anchor_root.add_child(_box_anchor_p)
	_box_anchor_root.add_child(_box_anchor_attach)


func _update_box_anchor_gizmo(cam: Camera3D, p_local: Vector3, attach_local: Vector3,
		world_per_px: float) -> void:
	_ensure_box_anchor_gizmo(cam)
	_box_anchor_root.visible = true
	var dot := 5.0 * world_per_px   # ~5 native-px dots
	(_box_anchor_p.mesh as QuadMesh).size = Vector2(dot, dot)
	(_box_anchor_attach.mesh as QuadMesh).size = Vector2(dot, dot)
	_box_anchor_p.position = p_local
	_box_anchor_attach.position = attach_local
	# Stem: a thin quad spanning P → attach (cam-local XY plane; z shared).
	var d := attach_local - p_local
	var length := Vector2(d.x, d.y).length()
	if length < 0.0001:
		_box_anchor_stem.visible = false
		return
	_box_anchor_stem.visible = true
	(_box_anchor_stem.mesh as QuadMesh).size = Vector2(length, 1.5 * world_per_px)
	_box_anchor_stem.position = (p_local + attach_local) * 0.5
	_box_anchor_stem.rotation = Vector3(0.0, 0.0, atan2(d.y, d.x))


func _hide_box_anchor_gizmo() -> void:
	if _box_anchor_root != null and is_instance_valid(_box_anchor_root):
		_box_anchor_root.visible = false


# --- Logical-tile ground orb (world-space; tests sprite-vs-logical position) ---
var _tile_orb: MeshInstance3D = null


func _update_tile_orb(speaker: Node3D) -> void:
	# Parent to the unit's CONTAINER, not the unit itself: the unit node rotates
	# for facing, so a child orb would swing around it as the camera re-orients.
	# The container is a stable world node, so the orb stays fixed in world space.
	var world_parent: Node = speaker.get_parent()
	if world_parent == null:
		world_parent = speaker
	if _tile_orb == null or not is_instance_valid(_tile_orb):
		_tile_orb = MeshInstance3D.new()
		_tile_orb.name = "TileLogicalOrb"
		var sph := SphereMesh.new()
		sph.radius = 0.2
		sph.height = 0.4
		_tile_orb.mesh = sph
		# psx-ot-depth-exempt: debug gizmo, no_depth_test, not a battle mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.1, 0.8, 1.0)  # cyan — distinct from red/green/yellow
		mat.no_depth_test = true
		mat.render_priority = 5
		_tile_orb.material_override = mat
		world_parent.add_child(_tile_orb)
	elif _tile_orb.get_parent() != world_parent:
		_tile_orb.get_parent().remove_child(_tile_orb)
		world_parent.add_child(_tile_orb)
	_tile_orb.visible = true
	# Real world point: the speaker's actual logical position (its origin) — same
	# X/Y/Z as the unit, so the orb sits AT the unit, not on the floor below it.
	_tile_orb.global_position = speaker.global_position


func _hide_tile_orb() -> void:
	if _tile_orb != null and is_instance_valid(_tile_orb):
		_tile_orb.visible = false


# Cam-local position of a point on the speaker's BILLBOARDED quad, mirroring
# unit.gdshader's billboard() + PAR so the anchor tracks where the sprite is
# actually DRAWN (the GPU billboards it screen-facing; we recompute the one point
# we need on the CPU). The billboard makes the quad's basis the camera axes, so in
# view space local quad-y maps straight to view-y (up), scaled by the mesh scale.
# Falls back to the raw origin when disabled or there's no UnitMesh.
func _sprite_billboard_anchor(cam: Camera3D, speaker: Node3D) -> Vector3:
	if not anchor_to_billboard:
		return cam.to_local(speaker.global_position)
	var mesh := speaker.get_node_or_null("UnitMesh") as Node3D
	if mesh == null:
		return cam.to_local(speaker.global_position)
	var o_view := cam.to_local(mesh.global_position)     # mesh origin in cam-local
	var scale_y := mesh.global_transform.basis.y.length()  # mesh world Y scale (~8)
	var v := o_view
	# Slide down the screen-aligned quad to the chosen fraction (feet at −0.5).
	v.y += anchor_quad_frac_y * scale_y
	# PAR (ADR-0036): the shader stretches the anchor's screen-x by the global
	# pixel_aspect; match it so the tail column lines up with the drawn sprite. The
	# billboard offset itself is PAR-neutral (bottom-CENTRE shares the anchor's x).
	#
	# Read the MIRROR, never RenderingServer.global_shader_parameter_get. That getter
	# is editor-only — `MaterialStorage::global_shader_parameter_get` opens with
	# `if (!Engine::is_editor_hint()) ERR_FAIL_V_MSG(..., "This function should never
	# be used outside the editor, it can severely damage performance.")` — so in the
	# shipped game it returned null on every call, the guard below it never fired,
	# and this correction had never once run outside the editor (W14 / #956). It also
	# printed the engine error plus a GDScript backtrace per open box per frame:
	# ~286 000 of a 150 s navigator walk log's 288 124 lines. PSXDisplay keeps
	# `live_par` for exactly this reason and its own comment names the trap.
	#
	# ⚠ At the committed default (`pixel_aspect = 1.0` in project.godot
	# [shader_globals], no `render.pixel_aspect` override) this multiply is by one,
	# so restoring it moves nothing on screen today. What it restores is the response
	# to a PAR scrub, which is what ADR-0036 asks of every opted-in surface.
	var par: float = PSXDisplay.live_par
	if par > 0.0:
		v.x = o_view.x * par
	return v


# Signed horizontal offset (virtual px) of the speaker's projected screen
# position from screen centre. Used as the triangle's mouth-aim. Returns 0 when
# no camera/speaker (arrow centred).
func _speaker_screen_offset(speaker: Node) -> float:
	if speaker == null or not (speaker is Node3D):
		return 0.0
	var cam := _vm._active_camera()
	if cam == null:
		return 0.0
	var world: Vector3 = (speaker as Node3D).global_position
	if cam.is_position_behind(world):
		return 0.0
	var screen: Vector2 = cam.unproject_position(world)
	var vp := cam.get_viewport().get_visible_rect().size
	# Convert pixel delta-from-centre into virtual PSX px (320-wide reference).
	var px_from_centre := screen.x - vp.x * 0.5
	if vp.x <= 0.0:
		return 0.0
	return px_from_centre * (320.0 / vp.x)
