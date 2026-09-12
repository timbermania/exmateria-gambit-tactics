# `Effects` tells `Audio` a code and a time, and nothing else

The crossing from `Effects` to `Audio` is one opaque code and one frame. Every
sound format — the instrument bank, the sequence data, the decoder, the
instrument names, the parameter semantics and the authoring for all of it — is
`Audio`'s, wherever the ROM happens to store it.

Status: accepted (2026-08-20).

## Context

[ADR-0117](0117-the-blueprints-ten-systems.md) gives `Audio` one part — *"the
sound driver"* — and `BLUEPRINT.md` §7 calls it *"The closest system to
finished"* with a content shadow of an instrument bank and four bank families.
That is true of the **driver** and untested for the **content** — and the content
is where the boundary is actually broken.

> **Quotation corrected 2026-08-22 by
> [ADR-0153](0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md).**
> This paragraph opened with **two quotations attributed to ADR-0117 by name and
> link, and neither string is in it** — *"the calibrated example of a finished
> system"* (also quoted twice in
> [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md), there
> attributed to `BLUEPRINT.md`, and present in neither source) and *"FFT music
> and SFX banks"*. ADR-0117's row 7 reads `| 7 | **Audio** | the sound driver |`
> and its table carries no per-system content shadow at all. The argument is
> unaffected — driver true, content untested — but the sentence a reader would
> have checked was not the sentence in the source.

**What crosses today is already correct, and already tiny.** The TIER-1 sound
event carries `sound_id` (u8) and `duration_frames`. `sound_id` is not a sound:
*"0/1 = skip, N>=2 indexes SoundContainer[N-2]"* (TIER-2), which resolves through
a mode to a FEDS pair (TIER-3). The effect stores an opaque index into a table.
It has no idea what will be heard. That is the same shape as a landmark
([ADR-0123](0123-the-landmark-lane.md)) and it is the right crossing.

**What is wrong is everything on the other side of that index.** `E###.BIN`
carries the containers *and* the FEDS sequence blob, and the code followed the
file: **5,306 lines** of sound-format knowledge live in `src/effects/`.

| | |
|---|---|
| `studio/FedsPairLanePanel.gd` | 1,245 |
| `studio/SoundGhostProjector.gd` | 600 |
| `studio/FedsPairProjector.gd` | 547 |
| `studio/FedsParamSemantics.gd` | 340 |
| `studio/FedsInstrumentNames.gd` | 309 |
| `studio/SoundContainerModel.gd` | 285 |
| …plus `SoundChannel`, `FedsPairModel`, `FedsOpcodeVerdicts`, `FedsNoOpPrune`, `FedsInstrumentMeta`, `FedsNoteAudition`, `SoundGapMath`, `EffectSoundSaver`, `SoundDefChannel`, `SoundRenderQueue` | |

Instrument names. Parameter semantics. Parameter *statistics*. A no-op pruner. An
opcode-verdict table. `Effects` has grown a toolkit for a format it does not own,
and the decoder it defers to (`smd_opcodes.gd`) already lives in the addon —
`FedsPairModel` preloads it and calls it *"THE runtime decoder."* So ownership is
already right in one direction and wrong in the other.

**The obvious argument for moving it fails, and the real one is stronger.** FEDS
blobs are not a shared bank to be deduplicated: **389 distinct blobs across 401
effects**, only 6 reused, mean 242 bytes. Each effect really does carry its own
sequence. The argument is not size or duplication — it is that **`Audio` owns the
format**, and one of its sequence banks is being stored, parsed, named and edited
inside another system's package.

**`Audio` is one core, one instrument bank, and N sequence formats.**
> **Amended 2026-08-21 by [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md)
> dec. 1–2:** there are **two containers over one opcode language** (`smds`,
> `feds`), not three formats. The global SFX bank is a third `feds` **bank
> family**, byte-verified — `system.feds` / `env.feds` carry the `feds` magic and
> load through the same `FedsBank` and the same driver. Read "N sequence formats"
> below as "N sequence **banks**".

The
correction that makes this legible:

- **Synth core** — `spu`, `adsr`, `pitch_table`, `gauss_table`, `sequencer`,
  `note_handler`, `shared/dispatcher`, `shared/slot_state`.
- **Instrument bank** — `WAVESET.WD`. `WavesetParser` pre-decodes *each
  instrument's* ADPCM; its inner class is `Instrument`. It is referenced by
  `smd_player`, `feds_bank`, `play_sound`, `sequencer`, `trackset`,
  `music_channel_context` and the shared dispatcher. **Both containers play
  through it** — it is not the SFX bank's private source. *(Amended by ADR-0136
  dec. 1; was "all three formats".)*
- **Sequence formats** — SMD (music), FEDS (attached to an effect), and the
  global SFX bank (standalone). The addon's own `shared/` directory is evidence
  it already treats them as variants of one thing.

That is the shape of the content the blueprint's one-line shadow was missing:
**one instrument bank plus N sequence banks**, one of which is stored inside
`Effects`' file.

## Decision

**1. The crossing is a code and a time.** `Effects` publishes a `sound` trigger
carrying an opaque code and a frame. It never learns what plays. This is already
what the data does; it is recorded so nothing widens it.

**2. Every tier above the code is `Audio`'s** — the container table (TIER-2), the
FEDS blob (TIER-3), the decoder, the instrument names, the parameter semantics,
the opcode verdicts, the pruner and the authoring surface for all of them. A ROM
file that carries two systems' data does not make it one system's responsibility
([`BLUEPRINT.md`](../BLUEPRINT.md) → *A ROM file is not a responsibility*).

**3. `Audio`'s system boundary includes its content**, not only its driver: one
instrument bank and N sequence banks. Whether FEDS ships as 401 per-effect banks
or is repacked is a packaging question for the asset model
([#308](https://github.com/timbermania/fft-monorepo/issues/308)), not a boundary
question.

**4. The package name is not the system name.** `smd-player` (the directory's
name when this ADR was written) is named after one of the three formats it
handles. Renaming is deferred to the `Audio` scope ticket, but no ADR should
treat "SMD" as a synonym for `Audio`.
> **Discharged 2026-08-21 by [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md)
> dec. 4:** the directory is now `exmateria-sound/` (commit `55b7e4653`). Half the
> premise was wrong — **`exmateria_sound`, the addon, was never named after a
> format**; only the monorepo directory was. The role stays `Audio`; the shipped
> name is ExMateria-Sound.

## Consequences

**The FEDS move is real work and is not scheduled here.** Relocating 5,306 lines
is an extraction, and this map rules extractions out of scope — pass 6 gates them
all, and pass 6 is gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299), which is where
most of those lines currently sit unmerged. This ADR records the **boundary**;
the move belongs to the refactor loop.

**The disruption is now named, which is what #307 owed.** When `effects`
extracts, the studio's FEDS authoring breaks because it is reaching into a
format that is no longer local. That is the correct outcome and it is now
predictable rather than discovered.

**Two questions are pushed to the `Audio` scope ticket, not answered here.** How
the global SFX bank differs from SMD, and whether it carries container/config
slots the way FEDS does — the working hypothesis is that it is FEDS-shaped
without the effect attachment, but that is a hypothesis and is labelled as one.
> **Answered 2026-08-21 by [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md)
> dec. 2:** the hypothesis holds and was understated — the global bank is not
> *shaped like* FEDS, it **is** FEDS, differing only in packaging (a standalone
> disc file versus a section sliced out of `E###.BIN` at `header[0x20]`). It
> carries **no** container/config tier: `SoundContainer` selection is effect-side,
> so a global-bank cue addresses a pair directly.
