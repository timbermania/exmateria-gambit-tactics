# Effect SFX and game-event SFX are separate audio paths

## Status

Accepted (2026-06-01)

The project plays sound for two reasons that look superficially similar
but have different state shapes: **effect SFX** is audio authored into a
spell/ability cast (FEDS pairs in `assets/effects/E###/sound_tracks.feds`,
fired by `TimelineController` → `ExMateriaEffectSfx.play_pair` with a per-cast
session token threading through pair callbacks), and **game-event SFX** is
one-shot or ambient audio bound to game state (unit death, UI navigation,
environment), played from the global FFT banks
(`assets/audio/sfx_banks/{system,env}.feds`) with no session lifecycle.

We keep these on separate front-ends — effect SFX through the
effects-system path, game-event SFX through a dedicated `SfxRouter`
autoload that owns a cue registry (`combat.unit_died` → bank slot) — and
share only the SPU backend (`ExMateriaEffectSfx.audition` for one-shots).
Unifying them would force the simpler path to carry the cast-session
plumbing it doesn't need, and would put bank IDs into every gameplay call
site instead of behind named cues.

## Consequences

- Adding a new game-event sound is *one row* in `SfxRouter._CUES` plus a
  subscription (or direct `play_cue`). It does **not** touch the effects
  system.
- Adding a new spell's audio stays an effects-system concern (its FEDS
  data + timeline), as before. `SfxRouter` plays no role.
- A future need for richer policy (polyphony caps, ducking, mixer buses)
  is added to `SfxRouter` per-cue when a real cue demands it, not
  speculatively on the registry shape.

## Addendum (2026-06-04): the audio chain vocabulary

This ADR established the path-level split. Below the path, both paths converge
on the **same playback chain** — sequencer → opcode VM → SPU. The vocabulary
for that chain was inconsistent until #31's audio sweep; the lexicon below is
now reflected in CONTEXT.md's Audio cluster and in code:

```
Keyframe ──→ SoundContainer ──→ FEDS pair ──→ Trackset ──→ Sequencer
                              (2 tracks)    (conductor + 2 tracks)
```

- **Channel** — keyframe lane in a sound subsystem's phase block (effect-cast
  path only; CONTEXT.md "Effect orchestration").
- **Keyframe** — `{duration_frames, sound_id}` entry in a channel.
- **SoundContainer** — per-effect `{mode, id_a, id_b, id_c, counter}` resolver
  entry; Wwise-style Random/Sequence Container. Replaces the misnamed
  "config_channel" int (which is now `sound_container_idx`).
- **EffectSoundResolver** — applies a container's mode to its counter and
  candidates; returns one resolved sound_id.
- **FEDS pair** — paired structural unit in a FEDS bank: exactly **2
  [Track]s**, side by side. The bank exposes `num_pairs` (groupings) and
  `num_tracks` (= `num_pairs * 2`, total opcode streams). A pair on disk has
  no conductor; one is added at wrap time.
- **Track** — one opcode stream. SMD songs and FEDS pairs both have tracks.
  *Distinct* from the retired effect-orchestration "track" (now Subsystem;
  see [ADR-0014](0014-effecttimeline-owns-time-modulation-tracks-self-deliver.md))
  and *distinct* from sound-subsystem Channel.
- **Conductor track** — track 0 of a Trackset by convention; tempo/global
  events in SMD songs, empty placeholder in FEDS-pair-derived Tracksets.
- **Trackset** — the runtime structure the sequencer plays. A conductor +
  N normal tracks. **Not an SMDFile.** `SMDFile.to_trackset()` and
  `FedsBank.pair_to_trackset(pair_idx)` are the two constructors;
  `Sequencer.load_trackset(...)` is the entry point. The pre-rename
  `make_synthetic_smd` is removed.
- **Opcode / NoteEvent / OpcodeEvent / EndBar (0x90) / Sequencer / SPU voice
  / WAVESET** — shared lower layer; same opcodes dispatched for FEDS, SMD,
  and the SFX banks.

Side-rename in the same sweep: the for-each phase's string value was kept
as the Ghidra label `"animate_tick"` for "ROM linkage." Per the team's
"ROM has no inherent names" directive, the value is now `"for_each"`. See
[ADR-0012](0012-effecttimeline-capstone.md).

This Addendum does not change ADR-0006's decision. The path-level split it
established is unchanged; the chain below it now has a consistent name at
every level, end-to-end across the exmateria-sound addon and the godot-learning
package.
