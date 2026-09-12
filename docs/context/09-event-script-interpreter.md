# Event-script interpreter

The runtime that plays the FFT **event script** (the cutscene-instruction
bytecode a [scenario](08-scenario.md)'s *own id* indexes in `TEST.EVT` — the link is
identity, not a field). Re-implemented
from PSX machine code opcode-by-opcode via emulator debugging, so its layering
deliberately separates the reverse-engineered *decode* (pure, PSX-faithful,
scene-free) from the Godot *apply* (node mutation) — machine code fused the two;
intentional software does not. The two extracted layers below are the seam.

**Event instruction**:
One unit of the [event script](08-scenario.md) — a named cutscene operation with typed
operands (`{2C} Face Unit 2`, `{6B} BG Sound`, `{10} Display Message`), identified
on disc by a single **opcode byte** and decoded into a name + parameter list. This
is the canonical term for the unit; the word **opcode** is reserved for the *raw
dispatch byte alone* (`0x2C`), never the instruction-with-operands. The repo's RE
write-ups already use it (`research/wiki_articles/event_instruction_NN_*.md`), and
it inherits the `event-script` qualifier's disambiguation.
_Avoid_: "opcode" for the whole instruction — "opcode" is monorepo-crowded (the SMD
sound driver's `addons/exmateria_sound/runtime/.../opcodes/` ships in this same Godot
project, plus BATTLE.BIN machine opcodes and effect-VM opcodes), so an unqualified
"opcode" is ambiguous inside the very package this lives in; "event command"
(FFTPatcher's upstream `EventCommands.xml` word — we diverge to match our own
incumbent "instruction"); "event" bare (that word already names [Game-event
SFX](14-audio.md) and the whole event script).

**EventInstruction** (generated enum):
The **semantic identity** of each [event instruction](09-event-script-interpreter.md)
and the interpreter's dispatch key — a generated GDScript enum
(`src/scenarios/EventInstruction.gd`) whose members (`FACE_UNIT_2`, `BG_SOUND`,
`DISPLAY_MESSAGE`, …) are slugged from the catalog's display names and whose
underlying int value **is the opcode byte**. Dispatch keys on it: `_handlers` is
keyed by `EventInstruction`, and the runtime lookup `_handlers.get(inst["opcode"])`
works because the enum value is the byte the chunk already carries. Generated from
the owned catalog by `gen_opcode_catalog.py` under the same `--check` pre-flight as
the activity taxonomy — the semantic transform happens at the **parser boundary**,
not at runtime (ADR-0013). The byte stays faithful to the PSX dispatcher as the
enum's *value*, but is never the "lead" identity in handler code — the enum is.
_Avoid_: keying dispatch on the raw byte (`0x2C`) or the display string
("Face Unit 2") — the byte is semantically bare and monorepo-crowded (ADR-0013),
the string is fragile (a catalog rename once silently unmatched a handler → the
bug this retires); hand-maintaining the enum (it regenerates from the catalog,
`--check`-guarded, like `LOGICAL_ACTIVITY_*` from `activity_taxonomy.yaml`).

**EventInstructionSet**:
The runtime home of the event-instruction catalog — a `class_name` module
(`src/scenarios/`) with the `XDatabase` lazy-static-cache shape that loads
`event_instructions.json` and hands back a descriptor (display name, typed param
list) by [EventInstruction](09-event-script-interpreter.md)/byte. The single source of
truth binding dispatch to the owned RE catalog: it backs the **coverage check**
(every `verified:true` instruction is `_bind`-ed to a handler or `_skip`-ed with a
reason — enforced by a test, warned at boot) and mints the typed
[EventInstructionArgs](09-event-script-interpreter.md) reader. Lives in `src/scenarios/`
beside the interpreter it defines, **not** `src/data/` with the content databases,
because it is the event-script *language definition* (an ISA), not game content
keyed by a gameplay id.
_Avoid_: filing it under `src/data/` with `JobDatabase`/`ScenarioDatabase` (those
are keyed content stores; this is the ISA); putting Godot handling-status into the
loaded JSON (the catalog is pure PSX RE — "intentionally unhandled" is a Godot
policy that lives in code as `_skip(enum, reason)`, so the coverage check reads
code → catalog).

**EventInstructionArgs**:
The typed operand reader for one [event instruction](09-event-script-interpreter.md) — a
lightweight `RefCounted` view minted by `EventInstructionSet.args(inst)` that zips the
runtime operand VALUES against the [EventInstructionSet](09-event-script-interpreter.md)
descriptor's `bytes`/`mode`/`type` METADATA by position, then delegates every numeric
convention to [PsxNum](09-event-script-interpreter.md). The named reads are **width-driven,
not width-named**: `a.raw("Sound")` returns the operand's as-assembled unsigned value
and `a.signed("X")` sign-extends it — `s8` for a byte, `s16` for a half-word — reading
the width **from the catalog**, so a handler never restates an operand's width and a
catalog re-widen re-reads correctly with zero handler churn. (This is why the surface
is `raw`/`signed` rather than the `u16`/`s16` an earlier forward-spec sketched: baking
`16` into the call site would re-import the hand-counted operand knowledge ADR-0059
exists to kill.) Positional siblings `a.nth(i)` (bounds-safe), `a.raw_at(i)`,
`a.signed_at(i)`, `a.name_at(i)`, `a.width_at(i)` read purely by operand index — the
reach `{6B}` BG Sound needs, whose operands share a byte layout across differing
catalog names. Replaces `_params_dict`'s `{name:int}` flattening, which dropped
`bytes`/`mode`/`type` and, fatally, **collapsed duplicate operand names** (the `{6A}`
two-`Unknown` case): `a.all("Unknown")`/`a.count("Unknown")` keep every same-named
operand distinct and in order, and `a.raw(name)` returns the FIRST match, so dup-name
opcodes are reached via `all`/positional rather than silently last-wins. `a.to_dict()`
is a transitional `{name:int}` bridge (byte-identical to the retired `_params_dict`,
last-wins) that feeds the still-name-keyed [ScenarioDecode](09-event-script-interpreter.md)
decoders, retired per-decoder as they migrate to the reader.
_Avoid_: re-implementing sign/width/wheel math here (it delegates to
[PsxNum](09-event-script-interpreter.md)); hand-counting operand byte offsets or restating an
operand's width inside an `_op_*` handler (the silent-contract fragility this retires);
`a.raw(name)` on a **duplicate-name** operand (it silently returns only the first — use
`a.all(name)` or positional access).

**PsxNum**:
The pure home of the PSX numeric conventions the event-script opcodes encode
their operands with — two's-complement sign extension (`s8`/`s16`), little-endian
u16 reassembly from split param bytes (`u16_lohi`), the **12-bit clockwise facing
wheel** (0x000=E, 0x400=S, 0x800=W, 0xC00=N, one turn = 0x1000) with its per-opcode
lifts (`warp_facing_to_12bit`, `direction_to_12bit`, `facing_byte_to_12bit`,
`look_at_12bit`), and the ADR-0052 depth-row flip (`flip_depth_row(z, size_z)`,
pure — the VM owns the `size_z` source + "unset" warning). A `class_name` module
(`addons/exmateria_platform/fixed_point/PsxNum.gd`) of static functions, defined once and tested once
(`PsxNumTest`), so handlers read as intent instead of re-derived bit math. The
same drift-killer discipline ADR-0013 applies to bit-packed flag fields.
_Avoid_: re-deriving a wheel/sign/pack expression inline in a handler (the smell
this retires — `(facing << 10) & 0xfff` scattered across `_op_*`); putting map
state or calibration knobs on it (it is pure — `flip_depth_row` takes `size_z`
as an argument rather than reading the VM); an `FFT`-prefixed name (the
conventions are genuine PSX hardware conventions, so `Psx` is descriptive, not a
vanity prefix — the [generic-systems naming rule](#TBD) still holds).

**ScenarioDecode**:
The pure decode layer that turns an event-script opcode's operands (as
`_params_dict` produces) into **typed intent** — e.g. `warp_unit(params) →
WarpIntent{uid, psx_x, psx_y, facing_12bit}`, `sprite_move_offset(params,
units_per_tile) → Vector3`, `beta_duration_frames(dist, speed)`. A `class_name`
module (`src/scenarios/ScenarioDecode.gd`) generalising the shape `ScenarioVM`
already used for `face_unit_look_at_12bit_psx`: the reverse-engineered *meaning*
of an opcode, computed with no nodes / no VM state / no side effects, so the RE
knowledge is unit-testable without booting a scene (`ScenarioDecodeTest`) and the
`_op_*` handler shrinks to "decode, then apply the intent." Numeric conventions
come from [PsxNum]. **Godot-specific mapping stays in apply**: the ADR-0052
depth-row flip (needs the live map) and node placement are done by the handler,
not the decode, so decode has no map/scene dependency.
The candidate-A rollout is **complete** — every handler that fused
reverse-engineered numeric decode now routes through [PsxNum] / ScenarioDecode.
Rolled out: `warp_unit`, `sprite_move_offset` / `beta_duration_frames` ({6E} +
reused by {28} Walk To with `dist_units = dist_tiles·position_divisor`),
`heading_facing_dir` (walk faces its dominant travel axis), `unit_anim_params` /
`rotate_unit_params` (the split-u16 chunk_unit_id + operand decode),
`resolve_rotate_target_12bit` (the {2D} Facing-byte mode dispatch — pure, the
current/camera-yaw reads passed in), and `map_darkness(params, oxide_baseline) →
MapDarknessIntent{blend, target, duration_ticks, snap}` (oxide_baseline passed in
so decode stays scene-free, mirroring [PsxNum]'s `flip_depth_row(size_z)`). The
sound opcodes' numeric conventions went to [PsxNum] instead —
`track_volume_curve` ({22}) and `fade_ramp_ticks` ({60}). The VM's
`_decode_*_params` / `_resolve_rotate_target_12bit` are now thin delegates, so the
`ScenarioFacingAnimDecodeTest` / `ScenarioMapDarknessTest` parity nets are
untouched. (Color {32}/{33} were already thin — tint math lives in
`ScenarioColorTint`; the `pose_idx = (angle>>10)&3` in the debug-trace dump is the
one remaining un-pinned convention, diagnostic-only.)
_Avoid_: doing the depth-flip or node lookup inside a decode function (those are
apply — decode must stay scene-free); returning an untyped `Dictionary` where a
small intent class reads better (the [AbilityView](05-ability-data.md) lesson — though
the terse value-returning form is fine for a single scalar like a duration);
leaving new opcode decode fused inline in the `_op_*` body (the pattern to roll
out — decode + thin apply, following Warp Unit / Sprite Move).

**ScenarioApply**:
The pure **apply** layer — the third symmetric module completing the seam
(ADR-0058). A `class_name` module (`src/scenarios/ScenarioApply.gd`) of `static`
free functions `apply_X(intent, world)` that perform a behavioral opcode's world
mutation, but **only** through verbs on an injected [ScenarioWorld] — no node
lookups, no VM state, no scene. Where [ScenarioDecode] holds "what an opcode
means," this holds "how it changes the rendered world," lifted out of the inline
`_op_*` bodies. A behavioral handler collapses to
`ScenarioApply.warp(ScenarioDecode.warp_unit(_params_dict(inst)), _world)`. Because
production passes a real `ScenarioWorld` and tests pass a `FakeScenarioWorld` on the
**same** code path, every `apply_X` is unit-testable with no scene boot
(`ScenarioApplyTest`) and the apply bodies leave `ScenarioVM` (the god-Node
shrinkage). Covers the ~28 behavioral opcodes: warp; unit lifecycle
(add/draw/erase/remove); motion (sprite move / walk to); facing & animation
(unit anim / rotate / face); tint & palette ({32}/{33}/reset/map-darkness); screen
& overlay ({3C}/{76}/{77}/{78}/{7D}/reveal); dialogue ({10}/change — apply returns
whether/what to gate, the VM arms it); field objects & EVTCHR.
_Avoid_: reaching past the `world` param to a node or VM field inside an apply (the
whole point is the facade is the only capability); arming a **Wait barrier** in apply
(that stays VM scheduler state — apply does the world mutation, the VM arms the
wait); moving a ramp/scheduler tick loop here (ticks live on the VM, apply just
`arm_*`/`set_*` them through a verb).

**ScenarioWorld**:
The injected **capability object** the apply layer mutates (ADR-0058) — a thin
`class_name` facade (`src/scenarios/ScenarioWorld.gd`, `RefCounted`) of **verbs**
(`place_unit_on_tile`, `set_unit_facing`, `arm_motion`, `tint`/`push_unit_tint`,
`show_dialogue_box`, `set_weather`, …), each wrapping one live-scene mutation. It is
a **deep** interface — the interpreter's *capabilities*, deliberately not a mirror of
the god-Node's getters — grown family-by-family as opcodes migrate, so one
`FakeScenarioWorld` (records verb calls) serves every apply test. Genuinely
scene-coupled machinery (the event pathfinder, the animation-playback + cinematic
walker, the two-position look-at, lazy overlay creation, the field-object render)
stays VM-side behind a verb that **delegates** to a VM method (`_plan_walk_route`,
`_apply_unit_animation`, `_face_unit_look_at_12bit`, `_play_field_object_render`) —
the verb is the seam, not a re-home of that machinery. It reads the VM's collaborators
**live** (the host wires `units_by_id` / `map_composer` after `_ready`), so it holds
the VM ref (untyped, to dodge the cyclic `class_name` dep) rather than snapshotting;
`ScenarioVM` builds `_world` in `_init` (not `_ready`) so handlers work on a bare
`ScenarioVM.new()` never added to the tree.
_Avoid_: exposing a node getter instead of a verb (that reopens the coupling the
facade closes); forwarding another object's members through getter-only properties
(the CLAUDE.md base-class member-drop trap `FakeScenarioWorld extends ScenarioWorld`
would hit — use plain fields + methods); putting decode or scheduler state on it (it
is apply-time world access only).

**ScenarioCameraDirector**:
The **stateful-director** sibling of the pure layers above: it owns the whole
cinematic-camera slice the interpreter used to carry inline — the `{19}` Camera
and `{1d}`/`{1e}` Camera Fusion opcodes, the ~11 hand-calibrated `camera_*`
framing knobs (ortho, position/rotation offsets, back-rotate, floor-aim, F19
depth-flip, F20 vertical datum, crop), the screen-space→world pose transform
(`_compute_camera_godot_pose`), the per-frame lerp, and the fusion-chain
`CameraChainSpline`. A `class_name` module (`src/scenarios/ScenarioCameraDirector.gd`)
the VM creates in `_ready` and orchestrates: the Camera handlers are `Callable`s
bound to the director, `_advance_frame` calls `camera_director.tick(delta)`, and
the `{E5}` Wait-For-Instruction kind-4 barrier resolves through
`camera_director.is_idle()`. Where **PsxNum**/**ScenarioDecode** are *pure* (no
state, no nodes), a director *owns* its subsystem's state + apply — the opcode's
decode can still be pure, but the state machine and the `PlayerCamera` takeover
live here. It reads VM-wide context (`player_camera`, `map_composer`,
`map_size_z`, the play-through gate, `_params_dict`) live through a back-reference
so those stay single-sourced on the VM. Extraction was behaviour-neutral — the
camera parity net (`ScenarioCamera*Test`, `ScenarioChapelChain*Test`) is
unchanged.
_Avoid_: forwarding the director's knobs back through getter/setter properties on
`ScenarioVM` (the [base-class member-drop trap](#TBD) — callers poke
`vm.camera_director.<knob>` directly); the `Cinematic` prefix (this project
reserves "cinematic" for the in-combat spell spotlight — event-script camera work
is `Scenario`-prefixed); duplicating `_TICK_HZ` / `SCENARIO_POSITION_DIVISOR` (the
director references `ScenarioVM.<const>` so there is one definition).

**ScenarioDialogueBoxPool**:
The RENDERING slice of the boxed-dialog subsystem. FFT keeps up to three portrait
dialogue boxes on screen at once (each a cooperative-task slot); this module
(`src/scenarios/ScenarioDialogueBoxPool.gd`, `class_name`, RefCounted) owns their
Godot side: the 1-based slot pool built from the host-wired boxes, the align-nibble
slot resolution (`Dialog & 3`), the per-frame screen-space placement (centred on the
speaker, above/below, frame-clamped, mouth-triangle re-aim), the persist bit
(`Dialog & 0x80`), the message-token index for `{51} Change Dialog` swaps, and the
placement-anchor debug gizmos. Behaviour-neutral extraction. **Seam decision (Option
A):** unlike [ScenarioCameraDirector] (a stateful cooperative task the VM owns), this
pool has **zero scheduler knowledge**. The boxed-dialog **advance gate** — the state
that parks a `ScriptContext` so the interpreter waits for the player to advance
(read by the round-robin scheduler, `{E5}` Task=1, the `TASK_DIALOG` predicate, and
input) — is **scheduler state and stays in the VM**. The dependency flows one way:
the VM's gate logic calls DOWN into the pool for rendering (`_foreground_box`,
`_box_at`, `_slot_persists`, `_foreground_slot`); the pool never touches
`ScriptContext`. Output parity with PSX is unchanged (both this and the handoff's
"pool-owns-gate" alternative preserve behaviour); Option A was chosen as the cleaner
implementation — the gate is fundamentally *"which context runs,"* which is the
cooperative scheduler's job. `_op_display_message` (overlay + boxed dispatcher),
`_op_change_dialog`, and `_active_camera` stay on the VM; the pool reads VM context
(`units_by_id`, `_active_camera`, `_resolve_unit_key`, `_insts`) live via a `_vm`
back-reference.
_Avoid_: putting gate / `ScriptContext` / advance-input state on the pool (that is
scheduler-owned — the pool is render-only); the `DialogueBoxPool` bare name (match
the `Scenario`-prefixed siblings); confusing this pool with the `DialogueBox` **ui3
widget** (same-named `box_*` props — the widget is the on-screen node, the pool
orchestrates instances of it).

**Cutscene motion (ScenarioMotion)**:
The pure primitive for a scripted unit *slide* — the `{3B}`/`{6E}` Sprite Move
(a transient position offset that eases home→target) and `{28}` Walk To (a grid
relocation lerp). A `class_name ScenarioMotion` module
(`src/scenarios/ScenarioMotion.gd`, RefCounted) that is a **value object**:
`start`/`target`/`dur_s`/`elapsed_s`/`easing`/`weight` with
`advance(delta)`/`is_done()`/`snap_to_end()`/`position()` and the bit-exact ROM
curve as a pure static (`ScenarioMotion.curve`, the VM's former
`_sprite_move_curve`, verified per-frame against hardware). Like [PsxNum]/[ScenarioDecode] it holds **no node and no VM state**, so
it is unit-testable with no scene boot (`ScenarioMotionTest`) — `position()` is
the reverse-engineered lerp, and the `unit.global_position` write is **apply**
(the same decode/apply seam this cluster keeps). The VM owns a
`motions:{uid → ScenarioMotion}` registry; the one per-frame `_advance_motions`
loop resolves the node via [units_by_id](#TBD) and writes it. Sprite Move and
Walk To are the **same class** (Walk constructs with `easing = 0`); their
differences — facing (`heading_facing_dir`), the movement-walk anim, the event
pathfinder, the tile-home reset — stay in the `_op_*` apply handlers. **The wait
collapse:** `{6F}` Wait Sprite Move, `{29}` Wait Walk, and the `{64}`/`{65}` Wait
Rotate barriers all reduce to one predicate — `_arm_wait_until(ctx, () →
motion_done(uid))` — where `motion_done` is `motions[uid].is_done()` or, for a
unit not in the registry, the Unit-owned `_rotate_done(uid)`. **Rotate stays on
the Unit** (`scenario_rotate`/`_rotate_state`/`_tick_rotate`, mirroring PSX
`FUN_8013f20c`'s all-handles per-vsync consumer and driving `facing_direction`)
— it answers the *same* `is_done()` question without moving into the registry.
ScenarioMotion is the **first concrete instance** of a latent *self-ticking
scenario task* shape (`advance`/`is_done`/`snap_to_end`) that the effect timers
([ScenarioColorTint](#TBD)/`ScenarioBgSound`/`ScenarioDarkScreen`/
`ScenarioWeather`/`CinematicWalkState`) already approximate but stay separate
from (ADR-0055 — the halt-gate fault line).
_Avoid_: holding a node ref on the motion (breaks the pure/apply seam and the
scene-free test — the node lives on the VM via `units_by_id`); pulling Rotate's
notch stepper into the registry (it fights the PSX all-handles consumer and the
`facing_direction` render coupling — ADR-0055); adding a new per-type Wait opcode
for a new motion (they collapse to `motion_done` — a new motion is one
constructor call); folding the effect timers under this registry (they tick
*outside* the `_running` halt gate to finish during a dialog wall, motions tick
*inside* to gate contexts — merging reopens ADR-0011/0012/0014).

**Cutscene actor (ScenarioActor)**:
Everything one unit's cutscene *owns* — the home of the per-unit state that had
none. A `class_name ScenarioActor` module (`src/scenarios/ScenarioActor.gd`,
RefCounted) that is a **data bag**: `tint` ([ScenarioColorTint](#TBD)), `motion`
([Cutscene motion](09-event-script-interpreter.md)), `walker` (`CinematicWalkState`),
`atlas_y` offset, `home` anchor, and an `owner_iid: int` **node guard**. The VM
owns one `actors:{uid → ScenarioActor}` registry, single-keyed on the resolved
uid (matching [units_by_id](#TBD) and the four dicts it replaces — `_unit_tints`,
`motions`, `_cinematic_walkers`, `cinematic_unit_atlas_y_offset`). The former
instance-id key of `_unit_move_home` folds in as `owner_iid`: home-capture
re-captures when the live node's iid ≠ the stored one, preserving node-identity
safety without a second registry key. Like [ScenarioMotion](09-event-script-interpreter.md)
the actor holds **no owner node** — the VM resolves the node via `units_by_id`
and passes it *into* the methods that need it (`reset_all`, home-capture); the one
transitive node ref is `CinematicWalkState.unit`, intrinsic to how the walker
renders. **Four verbs** are the whole lifecycle: `actor(uid)` (get-or-create),
`peek_actor(uid)` (non-creating — distinguishes "unit forgotten" from "sub-state
cleared"), `forget(uid, node)` (erase the entry — behavior-identical to the former
`_forget_unit`), `reset_all(units_by_id)` (clear the registry **and** reset the
three [Unit](#TBD) cutscene fields via `Unit.reset_scenario_cutscene_state()`).
**The reset collapse:** `start()` and `set_rewind_target()` both reduce to
`reset_all` — the three previously-disagreeing reset paths (which cleared different
subsets, leaking stale tint/motion/walker/facing across a live-VM restart) become
one lifecycle, and the inconsistency bug becomes unrepresentable (ADR-0064). The
five dicts go **fully internal**; a sub-state clear (Reset Palette) nulls a field,
only `forget` erases the entry.
_Avoid_: a dual uid+instance-id key (re-smears what this consolidates — the iid
keying was a workaround for `start()` not clearing the four dicts; `owner_iid` is a
guard field, not a key); holding the owner `Unit` ref on the actor (couples its
lifetime to the scene tree and breaks the scene-free test — the node lives on the VM);
forwarding `vm.motions`/`vm._unit_tints` as getter-only properties (the member-drop
gotcha); the VM poking `Unit._rotate_state`/`current_anim_id` directly (reach rotate
to reset via the Unit method — ADR-0055/0056); folding the effect timers in
(Candidate 2's task-pump — a separate halt-gate axis, ADR-0055).

**Scenario screen overlay**:
A full-screen quad the event-script VM raises to tint, dim, or cover the frame
— `{3E}` Color Screen, `{76}` Dark Screen, `{7D}` Show Graphic, `{91}` Show
Map Title, sharing the `ScreenOverlayQuad` base (and its `CULL_AABB` with
`ScenarioWeather`). **The base is not this term** (ADR-0172): it is a `platform`
mechanism — the cull-proof NDC quad — and `FormationScreenIn` extends it from `UI`
without being a *scenario* overlay at all. What makes something one is the second
half below: its lifetime is the VM's. Defined by being **camera-independent**: its vertex shader
rewrites the corners straight to NDC, so it fills the screen at any zoom or
position; that moves them outside the mesh's local AABB, so it must carry an
oversized `custom_aabb` or the frustum culler drops it; and it opts out of the
ordering table (`depth_test_disabled` + `render_priority`, ADR-0009). Its
**lifetime is the VM's** — every overlay is a VM child, so freeing the VM frees
the family, and the VM's own `settle_screen_effects()` / restart sweeps already
enumerate them.
_Avoid_: calling any [screen-in](11-campaign-spine.md)'s quad one — `FormationScreenIn`
shares the mechanism and frees itself the vsync its ramp lands, so "the VM frees the
family" is not true of it; thinking of one as belonging to a *camera*, or as something a screen
can draw over. It belongs to the **world**: any camera mounted into that
`World3D` renders it full-screen, over everything, whatever else is in front.
A screen that mounts its own `Camera3D` into a world with a settled overlay
gets that overlay, and a `CanvasLayer` screen only escapes by drawing above all
3D. See ADR-0162.

**March-idle**:
The **combat** idle pose — a unit walking in place on the battlefield. It is the
battle engine's *spawn default*, re-asserted continuously from unit status, not
something an instruction switches on: the ENTD add-unit constructor
(`evtchr_unit_clut_writer @ 0x80087A28`) reaches the natural-anim selector
`FUN_80082eec` when the sprite object is built, and the refresh `FUN_80068d08`
re-derives the animation every frame. A cinematic pose persists only while the unit
is held under `{6D}` Set Unit Event Hold, which suppresses that refresh. Distinct
from the **cinematic idle** (the scenario/cutscene resting pose) — same unit, two
resting states, and which one you get is a question about who owns the unit's clock.
_Avoid_: "the march" bare — that names the **retired deployment march** (ADR-0258:
auto-fill onto spawn tiles then walk to a contested tile, no FFT equivalent), and
"march" also appears in this package as ray**march**ing
(`CinematicFacingResolver.MARCH_STEP`); "idle" bare (ambiguous between the two
resting states above).

**`{80}` March** (the instruction):
The event instruction that hands its addressed units **back** to
[march-idle](09-event-script-interpreter.md) — `Units, Multi, Time`. A *release*
verb, not a start verb: the units were already march-idling by spawn default until
an earlier instruction (typically `{11}` Unit Anim) posed them, and this returns
them. `Time` is the **per-unit stagger**, which is why the observable is units
starting to walk in place one after another; across the corpus 144 of 177 instances
are `Time = 0` (lockstep), the rest 2/4/6/8. Battle openers end on one — Gariland's
scn 10 poses at PC 8 and releases at PC 23 (`Units 0x80, Multi 0, Time 0`).
⚠️ A `{80}` supplies a **pose, not a tick**: a host whose units have no running
clock stays frozen after it, which is the second half of ADR-0264's defect.
_Avoid_: reading it as "start walking" (it restores a default); confusing it with
the retired deployment march (ADR-0258).
