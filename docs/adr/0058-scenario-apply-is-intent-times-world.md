# Scenario apply is `apply(intent, world)`, not inline node-poking

## Status

Accepted (2026-07-02)

The event-script interpreter's behavioral opcodes get **one shape**: pure
`decode → Intent` ([ScenarioDecode](../context/09-event-script-interpreter.md)),
then `apply(intent, world)` — a free function on
[ScenarioApply](../context/09-event-script-interpreter.md) that performs the
world mutation **only** through *verbs* on an injected
[ScenarioWorld](../context/09-event-script-interpreter.md) facade
(`place_unit_on_tile`, `tint_unit`, `show_dialogue`, …), never by touching a node
directly. Production passes a real `ScenarioWorld` wrapping the live scene; a
`FakeScenarioWorld` records the verb calls, so an apply is unit-testable with **no
scene boot** (`ScenarioApplyTest`) on the same code path. This completes ADR-0055's
stated direction ("`position()` is pure, the `global_position` write is apply") for
the ~28 behavioral opcodes, and the apply bodies leave `ScenarioVM` — the god-Node
shrinkage the change buys.

## Considered options

- **Status quo — inline apply on the god-Node.** Each `_op_*` fused three jobs into
  one straight-line body: read operand bytes, compute the opcode's meaning, mutate
  live nodes (`units_by_id`, `map_composer`, the actor registry, materials/shaders,
  the dialogue box pool, screen overlays). The RE *decode* half was already split to
  `ScenarioDecode`/`PsxNum`, but the apply half stayed inline — so a bug in an apply
  (when to clear an actor's home, which dialog variant to route, how a tint composes)
  was reachable only through a full-scene boot, and `ScenarioVM.gd` kept growing.
  Rejected — this is the friction the change exists to remove.

- **A raw `{units, map, camera}` context bag passed to apply.** Give apply the live
  collaborators directly. Rejected: that is a *mirror* of the god-Node's getters, so
  the coupling just moves — apply still knows node shapes, and a fake has to
  reconstruct every node it might touch. It is a shallow interface, not a deep one.

- **Per-family narrow param structs (no shared world).** Pass each apply exactly the
  handful of refs it needs. Rejected: N bespoke interfaces means N fakes and no single
  place the "what the interpreter can do to the world" vocabulary lives; the verb
  surface would never consolidate.

- **One thin `ScenarioWorld` verb-facade, grown family-by-family (chosen).** A deep
  interface of *verbs* — the interpreter's capabilities, not the scene's structure.
  One `FakeScenarioWorld` serves every apply test. Verbs are added as opcodes migrate,
  so the surface stays exactly as wide as the ported behavior. Genuinely scene-coupled
  machinery (the pathfinder, the animation-playback + cinematic-walker machine, the
  look-at that reads two node positions, the lazy overlay creation, the field-object
  render) stays VM-side behind a verb that delegates — the verb is the seam, not a
  re-home of that machinery.

## Consequences

A behavioral handler collapses to `ScenarioApply.warp(ScenarioDecode.warp_unit(
_params_dict(inst)), _world)`. The three modules read as one symmetric pipeline —
`PsxNum` (numeric conventions) → `ScenarioDecode` (operands → typed intent) →
`ScenarioApply` (intent → world mutation) — plus the injected `ScenarioWorld`
capability object. Apply tests assert **external behavior** — which verb the world
received and with what values (placement tile, facing angle, tint vector, resolved
anim id, gate action) — never a private VM field.

Two boundaries a reader would otherwise trip on:

1. **Wait-arming stays on the VM.** For a handler that both mutates *and* arms a
   barrier (`display_message`, `dark_screen`, the motion/rotate/field-object waits),
   apply does the world mutation and the VM arms the wait separately — the seam is
   exactly "apply == touches the rendered world." `display_message` returns whether a
   boxed box was shown; `change_dialog` returns a gate *action* (`close_fg`/`close_bg`
   /`swap`/`noop`); the VM applies those to its own gate state. This also dissolves
   the review's Card 2 reach-in: box-pool access for these opcodes now routes through
   `ScenarioWorld` verbs, though the pool's own gate state is deliberately **not**
   re-homed (out of scope).

2. **Ramp/scheduler state stays VM-side.** The tint/oxide/reveal ramps tick *outside*
   the halt gate (ADR-0055's fault line) and remain VM fields; their apply drives them
   through a verb (`set_map_darkness`, `arm_reveal`, `push_field_tint_to_all`) rather
   than moving the tick loop.

`_world` is constructed in `_init` (not `_ready`) so handlers work on a bare
`ScenarioVM.new()` that was never added to the tree — the direct-construction test
harnesses (e.g. `ScenarioFaceUnitTest`) depend on it. `_vm` is held untyped on the
facade to avoid a cyclic `class_name` dependency, and the facade uses plain
fields + methods, never getter-only forwarding properties (the CLAUDE.md base-class
member-drop trap that `FakeScenarioWorld extends ScenarioWorld` would otherwise hit).

**Out of scope, intentionally:** the sound opcodes (deferred earlier), the camera
opcodes (already on `ScenarioCameraDirector`, still the sole cross-module reader of
`_params_dict`), and the wait/barrier/block-coroutine/event-variable opcodes (VM
scheduler state, not world mutation). This is a **pure refactor** — observable
scenario playback is identical, held by the scene-level `Scenario*Test` parity nets
through every commit.
