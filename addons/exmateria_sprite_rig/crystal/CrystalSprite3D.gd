extends Node3D
## The animated diamond a unit becomes on {92} Inflict Status SS=1 ("turn to
## crystal") — issue #154.
##
## A camera-facing billboard that REPLACES the unit's body sprite (the caller,
## [code]Unit.scenario_inflict_crystal[/code], hides the body mesh and parents
## this as a unit child so it despawns with the unit). Drawn from the ISO-derived
## 8-frame crystal sheet (BATTLE/OTHER.SPR, [code]tools/extract_crystal.py[/code]).
##
## ROUTED (2026-07-21; direct node 2026-07-28): the diamond no longer draws through
## an in-scene blend_add material — the WHOLE sprite (it has no opaque part) is
## folded by the display-space fold via [CrystalSpriteCompositor], now a DIRECT
## billboard node wearing the monomorphic `crystal_fold` material (ADR-0074 ④a).
## Each frame this advances the animation cell + re-stamps the carrier's fold order
## at the unit's world point; the fold blends it additively in display space (the
## in-scene [code]pow(2.2)[/code] sRGB->linear is dropped by design).
##
## Animation cadence RE'd live per-vblank (inflict_status_op92_decode.md §12.8):
## the crystal is a bespoke death/crystal VFX (FUN_8006d818 family), NOT
## OTHER.SEQ-driven — a forward loop 0→7 holding each frame 4 vblanks (period 32
## vblanks ≈ 0.533 s at 60 Hz), synchronized across crystals. We advance the frame
## off a real-time clock at the same 4/60 s cadence.
## Vault: [[Crystal Status Visual]]
## Vault: [[Display Space Blend Fold]]

# ADR-0212 dec. 1 — the class is INTERNAL to this addon: no global `class_name`,
# so an in-addon consumer preloads the file it wants.
const CrystalSpriteCompositor = preload("res://addons/exmateria_sprite_rig/crystal/CrystalSpriteCompositor.gd")

const ContentRoot = preload("res://addons/exmateria_sprite_rig/install/SpriteRigContentRoot.gd")

const FRAME_COUNT := 8
const FRAME_SECONDS := 4.0 / 60.0        # 4 vblanks/frame (RE'd, §12.8)
# The sheet frame is 16w x 22h; SIZE is the on-screen diamond HEIGHT in world
# units (tuned against the live PSX frame — ~0.6x a unit sprite).
const SIZE := 1.30
const ASPECT := 16.0 / 22.0

static var _sheet: Texture2D = null

var _producer: CrystalSpriteCompositor = null
var _elapsed: float = 0.0
var _frame: int = -1


static func _shared_sheet() -> Texture2D:
	if _sheet == null:
		_sheet = load(ContentRoot.resolve(ContentRoot.CRYSTAL_SHEET_SUBPATH))
	return _sheet


func _ready() -> void:
	# Freeze parity with the other over-unit billboards (ADR-0037): the cast
	# cinematic freezes `combat_visuals`, so _process halts and the last published
	# frame keeps folding — the crystal holds its frame (the unit is frozen too).
	add_to_group("combat_visuals")
	# Sit the diamond centred above the unit's ground origin (bottom near ground):
	# the publish origin is this node's world position, the billboard spans ±half.
	position.y = SIZE * 0.5
	_setup_producer()
	_frame = 0


## Build the direct billboard carrier for the routed diamond, sized to the frame's aspect-scaled
## footprint (width = SIZE*ASPECT, height = SIZE). The carrier folds only when the display-space fold
## owns compositing (fork + Forward+); on stock it renders nothing meaningful (the crystal is a
## fold-only VFX with no in-scene fallback — the whole sprite routes).
##
## "Renders nothing meaningful" is now TRUE, and it was not when this line was written: `_publish`
## runs unguarded every frame, and `Fold.add` off-fork used to THROW rather than draw nothing —
## `render_layer` is a fork-only property and assigning it on stock 4.7 raises (measured; ADR-0191
## Amendment 4 §3). `Fold.add` self-gates now, so this path is silent off-fork instead of noisy.
## The gate is the kernel's, not this file's — nothing here needs to ask the predicate.
func _setup_producer() -> void:
	_producer = CrystalSpriteCompositor.new()
	_producer.setup(self, _shared_sheet(), Vector2(SIZE * ASPECT, SIZE))


## Return the borrowed compositor slot when the crystal leaves the tree (unit despawn).
func _exit_tree() -> void:
	if _producer != null:
		_producer.release()
		_producer = null


func _process(delta: float) -> void:
	_elapsed += delta
	_frame = int(_elapsed / FRAME_SECONDS) % FRAME_COUNT
	_publish()


## Advance the diamond to the current frame + re-stamp its fold order. The carrier is a child at this
## node's world position (the diamond centre); its footprint is fixed at setup(). The UV rect selects
## the current frame's cell of the 8-frame horizontal sheet (full height).
func _publish() -> void:
	if _producer == null:
		return
	var cam: Camera3D = get_viewport().get_camera_3d()
	var view: Transform3D = cam.get_camera_transform().affine_inverse() if cam else Transform3D()
	# Vector4, NOT Color: set_shader_parameter sRGB-linearizes a Color's RGB into the `vec4 uv_rect`
	# uniform, crushing the cell WIDTH (0.125 -> ~0.014) so every column samples one texel (same class of
	# bug as the tile cursor's "black dagger"). A Vector4 is delivered verbatim.
	var uv_rect := Vector4(float(_frame) / float(FRAME_COUNT), 0.0, 1.0 / float(FRAME_COUNT), 1.0)
	_producer.publish_crystal(view, global_position, uv_rect)
