# E154 Effect Investigation

## Effect Structure

E154 contains 6 emitters (indices 0-5) with a child particle chain:

| Emitter | Role | Anchor | Motion Type | velocity_inward | Radial Vel (raw) | Homing (raw) | Lifetime | Particles |
|---------|------|--------|-------------|-----------------|-------------------|--------------|----------|-----------|
| 0 | Homing projectile | TARGET | 98 (homing) | true | 2560 | 64400 | 8-16 | 6→1 |
| 1 | Relay / trigger | TARGET | 0 (static) | true | 0 | 0 | 3-16 | 2→1 |
| 2 | **Child of 1** | PARENT | 96 | true | -1057 to -1426 | 65488 | 11-16 | 10→1 |
| 3 | Chaotic spread | TARGET | 96 | false | -320 | 65494 | 16 | 2→1 |
| 4 | Homing projectile | TARGET | 98 (homing) | true | -641 to -625 | 64672 | 8-16 | 5→1 |
| 5 | Persistent bg | TARGET | 2 | true | 2 | 0 | -1 (anim) | 4→1 |

**Child chain:** Emitter 1 (`child_emitter_on_death: 2`, `child_death_enabled: true`) → spawns emitter 2 when its particles die. Emitter 1 particles live only 3 frames, so they die quickly, triggering a burst of 10 particles from emitter 2.

## Bug: Homing Strength Parsed as Unsigned

### Symptom
Emitter 2's child particles fly off screen at extreme speed.

### Root Cause
`tools/parse_effect.py` lines 499-502 read homing strength with `read_u16` (unsigned), but the PSX uses `lh` (signed halfword load).

**Parser (bug):**
```python
raw_homing_min_start = read_u16(data, offset + 0xB8)  # 0xFFD0 → 65488
```

**PSX disassembly (`emitter_control_routine`):**
```
801a7de4: lh $a0, 0xB8($s7)   # lh = signed → 0xFFD0 → -48
801a7de8: lh $a1, 0xBC($s7)   # signed
801a7dfc: lh $a0, 0xBA($s7)   # signed
801a7e00: lh $a1, 0xBE($s7)   # signed
```

### Impact on E154 Emitter 2

| | Unsigned (current bug) | Signed (correct) |
|---|---|---|
| Raw value | 65488 | -48 |
| Converted (÷114688) | **0.571** | **-0.000418** |
| Behavior | Massive acceleration toward target each frame | Essentially zero (homing disabled) |

With `homing_strength = 0.571` applied as acceleration every frame for 11 frames of lifetime, particles accumulate ~6.3 units/frame of velocity — they fly off screen. With the correct value ≤ 0, homing is disabled (`if particle.homing_strength <= 0.0: use drag`), and particles drift gently at their initial velocity.

### Fix
Change `read_u16` to `read_s16` for homing strength fields in `parse_effect.py`, then re-parse all effects.

## velocity_inward + Negative Radial Velocity

Emitter 2 uses `velocity_inward: true` with negative radial velocity (raw -1057 to -1426, converted -0.074 to -0.099).

**How our code handles this** (`EmitterManager._initialize_child_particle`):
```
direction = (base_pos - final_pos).normalized()   # toward center
velocity  = direction * radial_vel                 # radial_vel is negative → reversed to OUTWARD
```

**PSX behavior** (`emitter_control_routine` at `LAB_801a70d0`):
```
direction = normalize(center - particle_position)  # toward center
velocity  = direction * radial_vel >> 9             # signed multiply → same reversal
```

Both produce outward velocity when radial is negative. Our implementation matches the PSX here.

## Child Spawn: Single Shared Function

Both primary spawns (timeline-driven) and child spawns (parent death) call the **same** PSX function: `emitter_control_routine(effect_index, frame_counter, emitter_index, parent_particle)`.

The `velocity_inward` flag IS checked inside this function (confirmed at `801a6bc4`: `andi velocity_mode_flags, v1, 0x410` → branch on bit 4). So both spawn paths respect the child emitter's `velocity_inward` flag. Our implementation is correct on this point.

## Secondary Issue: Frame Counter Mismatch

**PSX** passes the effect-level frame counter to child spawns:
```
lh    a1, 0x20(s1)    # a1 = EffectState->frame_counter (effect-level)
lbu   a2, 0x53(s0)    # a2 = particle->child_emitter_on_death
jal   emitter_control_routine
```

**Our code** passes `particle.age`:
```gdscript
# EmitterManager._cleanup(), line 331:
child_spawn_requests.append({ "age": particle.age, ... })
# line 339:
_spawn_child_emitter(request.child_index, request.position, request.age, ...)
```

This affects interpolation `t = frame_counter / 160.0`. With `particle.age=3` (short-lived parent), t≈0.019. With the PSX's effect-level frame (~13+ when emitter 1 activates), t≈0.08+. Minor correctness issue — not the cause of flying off screen.

## Missing Feature: Homing Arrival Detection

The PSX checks whether particles have reached their homing target and transitions them to animation-driven death. This is in `op_update_all_particles` at `801a2f34`:

1. Extract threshold from particle flags: `andi v0, flags, 0x300` → `srl v0, v0, 4` → values 0, 16, 32, 48
2. If threshold is 0 → skip (no arrival check)
3. Check each axis: `|position_component - target_component| < threshold`
4. If ALL three axes within threshold → set particle lifetime to -1 (animation-driven death)

The particle doesn't die instantly — it plays out its animation until a terminal frame.

**E154:** All emitters have `homing_arrival_threshold: 0`, so this feature is irrelevant here. But it's missing from our implementation entirely (`ParticlePhysics.gd` has no arrival detection), which could affect other effects that use non-zero thresholds.

## Timeline Activation

From `timeline.json` (animate_tick context), emitters activate at:
- Tick 0: Emitter 0
- Tick 11: Emitter 0
- Tick 13: Emitters 1 + 0
- Tick 15: Emitter 5
- Tick 17+: Emitter 4

Emitter 2 is **never directly activated by the timeline** — it only spawns as a child of emitter 1.
