# Combat pause is domain-scoped via a `combat_visuals` process_mode group

Pausing combat halts the GPU sim **and** every CPU-only presentation node that has no
GPU representation (the [combat-visuals](../context/02-combat-buffer-layout.md)). It must
**not** halt the camera, menus, **future UI overlays**, or the camera-reactive render path
(sprite-quadrant resolution, shader-side billboarding). The mechanism is a
`combat_visuals` Godot group whose members' `process_mode` is written from a freeze
predicate `CombatLoop` owns; pause is otherwise implicit, because the engine skips
`_process` on disabled nodes. This is the CPU-side counterpart to
[ADR-0031](0031-battle-state-is-gpu-authoritative.md): ADR-0031 pins where battle state
lives (GPU only); this ADR pins how the CPU presentation riding atop battle state halts
when the sim halts.

## Status

Accepted. Verified 2026-08-28 — decisions 1–10 all built.

## Context

`CombatLoop.combat_active` is the battle-domain on/off bit, and `CombatLoop.tick`
early-returns past `gpu_simulator.step_tick`, the tick-based unit playbacks, projectile
updates and the visual bridge when it is false. That gate covers the *GPU-driven*
visuals. It does not cover visuals that drive themselves off `_process(delta)` —
`EffectInstance` pumping `effect_timeline.tick(delta)` (the 30 Hz accumulator behind
particles, sound, colour and camera subsystems, ADR-0012), and the three trap effects
advancing their own tick timers. All of those kept animating through pause.

Two adjacent properties must survive pause and already do, by construction rather than
by this ADR: particles stay correctly **billboarded** as the camera moves, because
`effect_particle_stp.gdshaderinc` rebuilds `MODELVIEW_MATRIX` from the live
`VIEW_MATRIX` per draw (same shape in `trap_charge_line.gdshader`,
`projectile_vertex_color.gdshader`, `shadow_blob.gdshader`), so a frozen CPU position
re-projects against the current view; and unit sprites keep resolving the correct
camera-quadrant variant, because `CameraRelativeRenderer` emits
`camera_quadrant_changed` and `Unit._on_camera_quadrant_changed` answers it —
signal-driven, outside the combat-domain gate.

What was missing is a domain-wide axis the CPU-only combat visuals observe in lock-step
with the combat domain's own state.

## Decision

`CombatLoop` owns a freeze predicate and writes each `combat_visuals` member's
`process_mode` from it. The decisions below are the rules; decisions 1–6 are the
original design and 7–10 were added as the predicate grew axes and carve-outs.

1. **Combat pause is combat-scoped, not engine-scoped.** Camera, menus, UI overlays —
   including ones this ADR could only call future, such as ADR-0137's formation screen —
   and the camera-reactive subset (`CameraRelativeRenderer`'s quadrant signal, shader-side
   billboarding) keep running. Nothing on the combat path writes `get_tree().paused`.

2. **One authority, no mirror.** `CombatLoop` owns the freeze. Every input to the
   predicate is either a `CombatLoop` field (`combat_active`, `deploy_active`,
   `victory_achieved`) or the owning manager's own read (`cinematic_manager.is_active()`,
   `active_caster_idx()`). There is no autoload, no second copy of the state, and no
   parallel pause flag. *(The original rule named `combat_active` as the single field;
   the predicate grew, the no-mirror rule is what governs.)*

3. **Mechanism: a `combat_visuals` Godot group, gated by `process_mode`.**
   `_refresh_combat_visuals_freeze()` walks `get_nodes_in_group("combat_visuals")` and
   writes `PROCESS_MODE_INHERIT` or `PROCESS_MODE_DISABLED` per member. It is the only
   writer, and it fires from every input's edge: the three field setters and both
   `CinematicManager` signal handlers. Adding a predicate input means adding a refresh
   at its edge, not a second mechanism.

4. **Membership is a one-line opt-in:** `add_to_group("combat_visuals")` in `_ready`.
   The population is whatever that grep returns — today eight production members plus one
   test double:

   | member | joined for |
   |---|---|
   | `EffectInstance` | this ADR (guarded by `not is_cinematic`, decision 7) |
   | `TrapEffect`, `TrapChargeLineEffect`, `TrapOrbitalEffect` | this ADR |
   | `Projectile3D` | ADR-0038 |
   | `DamageNumber3D`, `StatusBubble3D` | ADR-0063 |
   | `CrystalSprite3D` | freeze parity with the other over-unit billboards |
   | `_FakeVisual` | `CombatVisualsSpawnFreezeTest`'s double |

   Children with `PROCESS_MODE_INHERIT` cascade for free — per-effect subsystems do not
   enroll separately.

5. **`Unit` is not a combat-visual.** It is in group `units` only. It owns
   camera-reactive work that must survive pause: sprite-quadrant resolution on
   `camera_quadrant_changed`, the GTE depth-centre marker, the dynamic shadow update.
   Unit animation instead rides a host-pumped clock, so no per-`_process` pause gate is
   needed on `Unit` at all. The machinery is **ADR-0083**'s: `AnimationClock.owner` names
   the host, `tick_based` is the derived read-only predicate `owner != Owner.SELF`, the
   host declares itself with `unit.clock_owner = AnimationClock.Owner.COMBAT`, and
   `Unit._process`'s delta pump no-ops whenever a host owns the clock. Cite this decision
   for the rule and ADR-0083 for the machinery.

6. **A new combat-visual joins the group in `_ready`** — necessary, and by decision 10
   not sufficient. A combat-visual-shaped `_process` living on `Unit` (or on any node
   that must survive pause) is the failure shape: extend a host-pumped playback, or move
   the work into a dedicated combat-visual child.

7. **Cinematic-active is an orthogonal second axis, and the spotlight subject is carved
   out.** `CinematicManager.is_active()` freezes the group so the strategy-view spectacle
   halts around a cast cinematic. It cannot be collapsed into `combat_active`, which also
   gates the GPU simulator's `step_tick` — flipping that false would halt the cinematic
   itself, and the cinematic needs the GPU running so its own caster index and timer
   advance. Two carve-outs keep the subject lit:
   - the cinematic `EffectInstance` opts out of the group entirely (`is_cinematic = true`,
     set by `EffectManager.spawn_cinematic_effect` **before** `add_child`), so it is never
     a member to freeze;
   - **any member descending from the caster `Unit` keeps running**, resolved by a
     parent-chain walk against `units[active_caster_idx()]`. This covers the caster's
     unit-owned [Charge VFX](../context/02-combat-buffer-layout.md) (parented under
     the `Unit` by
     `EffectManager._spawn_charge_*`), which would otherwise lock mid-`start_fade()`
     because the GPU exits `SPELL_CHARGING` one tick before the cinematic begins. It is
     the CPU mirror of the GPU's `U_PAUSED` exemption — `stage_spell.glsl` writes
     `paused = 1` to every non-caster unit, and `CombatLoop._get_unit_anim_speed` reads it
     to keep the caster's body pose animating; same intent, different mechanism, because
     Charge VFX has no GPU representation. If the caster index does not resolve to a
     live unit, nothing is carved out.

8. **Post-victory does not freeze: `victory_achieved` overrides every other axis.** The
   freeze exists to halt the spectacle around the cinematic spotlight or during user
   pause. Neither rationale survives the battle resolving — no spotlight, no
   perception-of-pause intent. Particles, fading Charge VFX, lingering `EffectInstance`
   playbacks and projectiles mid-flight finish their natural lifecycle so the dance-out
   frame is not littered with frozen mid-particles. *(This reverses the original
   Consequences, which called post-victory freezing a latent bug being closed. It was
   the opposite.)*

9. **The strategy phase runs combat-visuals: `deploy_active` joins `combat_active` as a
   phase input.** The simulator ticks during deployment with `combat_active` still false —
   units walk to their tiles, combat intent is not live (ADR-0042). Deploy marches must
   animate, so the predicate's phase test is `combat_active or deploy_active`, with its
   own setter refresh. *(This too reverses the original Consequences' strategy-phase
   claim. ADR-0042 supplies the reason and owns the tick gate; the freeze axis is this
   ADR's, and is recorded here because it is stated in no other ADR.)*

10. **Correctness at spawn time is `CombatLoop`'s, not the member's.** `add_to_group`
    runs in `_ready`, which fires *after* `node_added`, so a member spawning while a
    freeze is in effect defaults to `PROCESS_MODE_INHERIT` and animates until the next
    transition-driven refresh. `CombatLoop` connects `SceneTree.node_added` to
    `_on_scene_node_added`, which defers `_apply_spawn_freeze` past `_ready` and applies
    the same per-node predicate to the one member. It is gated on
    `cinematic_manager.is_active()` — the only axis under which a fresh member appears
    amid a running battlefield — so it costs O(1) otherwise, and deliberately does not
    arm during the pre-combat phase where a tree-wide `node_added` reaction would churn
    over hundreds of unrelated nodes.

## Verification

- `tests/CombatVisualsSpawnFreezeTest.gd` drives a real `CombatLoop` with a stubbed
  `CinematicManager` over the actual `SceneTree.node_added` path, in three arms: a member
  spawned mid-cinematic freezes on spawn, a member spawned while running stays
  `INHERIT`, and a member spawned under the caster `Unit` keeps running. That covers
  decisions 7 and 10.
- `tests/FeedbackHudTest.gd` and `tools/check_feedback_hud.py` assert `combat_visuals`
  membership for the over-unit billboards, covering decision 4 for ADR-0063's two.
- Decisions 1, 2, 3, 5, 8 and 9 are verified by reading. Nothing exercises the
  group-wide refresh, the `victory_achieved` override, or the `deploy_active` phase
  input; a predicate table test over `_visuals_should_run` — the four axes crossed
  against member-under-caster — is the cheapest arm that would.

## Considered options

- **Godot tree pause (`get_tree().paused = true`) with `PROCESS_MODE_ALWAYS` opt-outs
  (rejected).** The first thing tried. Halts everything by default, so the camera, menus
  and every future overlay each need an opt-out. The inversion is wrong: combat is the
  minority of the running game, not the majority.
- **`CombatVisual` base class + `_process_combat` hook (rejected).** Equivalent
  discoverability to the group (an `extends` line vs. an `add_to_group` line) at the cost
  of an inheritance constraint on otherwise-independent `Node3D` subclasses, renaming
  `_process` across all of them, and reimplementing in GDScript what `process_mode`
  already does at engine level.
- **Per-`_process` flag check inside every combat-visual (rejected).** The discipline
  burden scales with every new member and the failure is silent. The group has the same
  failure-by-forgetting shape, but the opt-in is greppable — one grep enumerates the
  entire population — and the gate is the engine's, not hand-written code in N classes.
- **A `BattleClock` autoload mirroring the state (rejected).** A second source of truth
  that must be poked in sync with every write. The group plus `process_mode` already
  gives the "set it once, every visual reacts" property the autoload was reaching for.
- **`CombatLoop` pumps combat-visuals via a registry, removing their `_process`
  (rejected).** Pause would become implicit, but every spawn site takes a
  register/unregister responsibility, the visual's lifecycle couples to `CombatLoop`, and
  effect rate couples to GPU-tick rate rather than the 30 Hz accumulator the effect
  timeline owns by ADR-0012.
- **Subtree `process_mode` — reparent all combat-visuals under one node (rejected).**
  Requires reparenting effects added to the viewport and traps parented to target units.
  A scene restructure for the same per-node toggle, driven by inheritance instead of
  group iteration, and it would couple the pause mechanism to the parenting structure.
  Note that decision 7's carve-out reads the parenting structure deliberately, which is a
  different thing from depending on it for the freeze itself.

## Consequences

- Adding a new combat-visual is one line. Forgetting it is the failure shape, and it is
  greppable.
- `PROCESS_MODE_DISABLED` halts not just `_process` but `_physics_process`, `_input`,
  `_unhandled_input`, `_shortcut_input` and `_unhandled_key_input` on the node.
  Combat-visuals are presentation-only and use none of those; a future member that needs
  physics during pause changes shape (split the always-on part into a non-grouped child),
  not the group rule.
- `CrystalSprite3D` lives under `src/units/` and is a member. Decision 5 forbids
  combat-visual `_process` work **on `Unit`**, not on a node parented to one — and
  decision 7's carve-out depends on exactly that parenting.
- The predicate is what is pluggable; the group iteration is the mechanism. A future
  fifth axis repeats decision 3's shape: an input, and a refresh at its edge. Both
  reversals recorded in decisions 8 and 9 arrived this way, and the second one went
  unwritten in any ADR for a while — the bookkeeping is the part that does not happen
  by itself.
- A member needing cinematic behaviour other than decision 7's can be hand-special-cased
  in the predicate, the same shape as `_get_unit_anim_speed`'s per-unit branch.

## References

- [ADR-0012](0012-effecttimeline-capstone.md) — the effect timeline owns its 30 Hz
  accumulator (the reason decision 3 rejected the registry-pump option)
- [ADR-0031](0031-battle-state-is-gpu-authoritative.md) — battle state is GPU-authoritative;
  this ADR is the CPU-side counterpart
- [ADR-0042](0042-strategy-phase-is-a-non-combat-phase-of-the-gpu-simulator.md) — the
  strategy phase ticks the simulator with combat intent off (decision 9's reason)
- [ADR-0083](0083-a-units-animation-clock-has-exactly-one-owner.md) — the per-unit
  animation clock (decision 5's machinery)
- [ADR-0001](0001-gpu-combat-buffer-layout-is-shader-authoritative.md) — GPU combat buffer
  is shader-authoritative
- CONTEXT.md — [Combat-visual](../context/02-combat-buffer-layout.md)
