# The landmark lane — a code, a time, and a table anyone may read

Landmarks leave the particle keyframe and become their own lane, with their own
time grid and a **per-effect event table** resolving code → named event. The lane
is `Effects`' one open-ended extension point, which is what makes the rest of the
lane list safe to fix.

Status: accepted (2026-08-20).

## Context

In the ROM a landmark is not stored inside a particle keyframe. A particle
channel is a fixed 128-byte **structure of arrays** — `time[]`, `emitter_id[]`,
`action_flags[]` — all indexed by the same slot. `action_flags` is already a
parallel array. The entire coupling to the particle channel is the shared
`time[]`.

That coupling carries no meaning. `EffectInstance._on_action_flags_triggered`
takes `_channel_idx` and **discards it**, and fans the bits into three
independently-named signals before any consumer sees them. The particle channel
supplies timing and nothing else.

The two halves of `action_flags` already travel different code paths:

```
PhaseBlock._tick()             emitter_id != 0 → spawn request carries action_flags
                                               → ParticleSubsystem reads bits 0-2 as callback_slot
PhaseBlock._advance_keyframe()  action_flags != 0 → action_flags_triggered
                                               → EffectInstance reads bits 4/5/6 as landmarks
```

The callback half **requires** an emitter (`emitter_id 0 = skip`,
`PhaseBlock.gd:19`); the landmark half requires none.

Measured across 401 effects:

- **1,277** keyframes carry a non-zero `action_flags`: **317** callback-only,
  **935** landmark-only, **5** both (0.4%), 24 with undecoded bits.
- **937 of 946** landmark-bearing keyframes carry `emitter_id == 0` — the ROM
  already writes landmarks as standalone carriers.
- Slot pressure is negligible. Per context the budget is 5 channels x 24 usable
  slots = 120, and because `channel_index` is discarded a carrier may land on any
  channel in the context. The busiest effect in the corpus uses **76/120**
  (E473, phase1); `for_each` peaks at 57/120 and `phase2` at 7/120. Mean channel
  occupancy is **2.5 of 24**.

So an independent landmark grid always re-encodes, with at least 44 free slots on
the worst effect in 401. It is a **re-projection**, not a superset — it does not
pre-empt the asset-model question in
[#308](https://github.com/timbermania/fft-monorepo/issues/308).

**`reaction` is a span the ROM writes as two triggers.** `_on_refresh_tile` does
exactly one thing: `if target_unit.is_reacting: target_unit.end_reaction()`. Of
411 effect-contexts, **290** carry exactly one `ABILITY_REACT` and exactly one
`REFRESH_TILE`; react precedes refresh in **279**, is simultaneous in 11, and is
**inverted in none**. Of the unpaired remainder, the 61 bare refreshes are
already no-ops (the `is_reacting` guard) and the 60 unclosed reacts run to the
animation's natural end. The consumer is reconstructing an extent by hand —
exactly the tax [ADR-0122](0122-an-effect-lane-is-a-track-of-non-overlapping-typed-events.md)
predicts when an event with extent does not say so.

**The sound lane is the same kind of thing.** Its TIER-1 event carries
`sound_id` (u8) and `duration_frames`, and `sound_id` is not a sound: *"0/1 =
skip, N>=2 indexes SoundContainer[N-2]"*, which resolves through a mode to a FEDS
pair. The effect stores an **opaque index into a per-effect table**. Landmark and
sound are one shape — a code at a time, resolved by whoever listens — differing
only in that sound's codes are indirected through a table while landmark's are
welded to bit positions.

## Decision

**1. Landmarks become their own lane** with their own time grid. The importer
lifts `action_flags[]` off the shared grid; the exporter manufactures carriers
using the encoding the corpus already uses — `emitter_id = 0` plus the bits.

**2. The lane is phase-scoped — one lane per context.** `for_each` **repeats per
target**, so a `for_each` landmark fires once per target. A single absolute lane
would flatten that into one moment and apply a multi-target spell's damage once.
Phase scoping is correctness, not tidiness.

**3. The lane carries two event types**, per ADR-0122 dec. 2:

| event | extent | meaning |
|---|---|---|
| `reaction` | **span** | opens at what the ROM calls `ABILITY_REACT`, closes at `REFRESH_TILE` |
| `hit` | trigger | apply damage, show popups |

An unclosed `reaction` is **open-ended and ends with the consumer's own
animation** — declared once here so no consumer invents its own ending. A close
with no open is a no-op, which is what the code already does.

**4. `refresh_tile` does not survive.** The vocabulary is `reaction.begin`,
`reaction.end`, `hit`.

**5. The lane gets a per-effect event table**, the same indirection `sound`
already has through `SoundContainer`. A landmark event resolves through the table
to a named event rather than through a hardcoded bit position.

**6. `sound` and `landmark` stay two lanes of one kind.** They share an event
shape but have different clocks and different subscribers, and the lane is the
unit of subscription. Collapsing them would make every subscriber filter a shared
code space.

**7. The callback slot stays with the particle keyframe** and is renamed. Bits
0-2 are `callback_slot`, genuine particle machinery, load-bearing on
`emitter_idx`, `spawn_counter` and `channel_idx`. It was never a flag.

## Consequences

**This is what makes ADR-0122's fixed lane list safe.** Anything new — telling
the map to do something, telling a unit to react a different way — is a row in
the event table, not a new lane and not a schema version bump. Fixed list, one
open door.

**Landmarks are not addressed to any system.** The effect emits a code; whoever
subscribes decides what it means. `Cutscene` subscribing to an effect's `hit` to
time a dialogue box is a legitimate use and needs no new mechanism — but it
answers *when*, never *who owns the thing being done*.

**The 0.4% overlap and the 24 undecoded-bit keyframes need a disposition** when
the importer is written. They are named here so the importer does not discover
them: five keyframes carry both a callback slot and a landmark, and 24 carry bits
outside both fields (`0x8080` x11 and `0x6E6E` x3 look like unparsed bytes rather
than flags).
