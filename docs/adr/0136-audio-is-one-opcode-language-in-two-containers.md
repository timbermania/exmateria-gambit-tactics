# `Audio` is one opcode language in two containers, and it is not as extracted as the blueprint says

`Audio` does not handle three sequence formats. It handles **one opcode
language in two containers** — `smds` and `feds` — over **four bank families**
and one instrument bank. The system boundary includes that content, the package
directory is renamed to match the name it has published under for months, and
the blueprint's claim that `Audio` is *"The closest system to finished"* is
amended: it was calibrated in one direction only, and misses a 1,261-line driver
and four autoloads still sitting in the host.

Status: accepted (2026-08-21). Ratifies and amends
[ADR-0124](0124-effects-tells-audio-a-code-and-a-time.md) dec. 3–4; amends
[`BLUEPRINT.md`](../BLUEPRINT.md) §7. Resolves
[#313](https://github.com/timbermania/fft-monorepo/issues/313).

## Context

ADR-0124 settled the `Effects` → `Audio` crossing (an opaque code and a frame)
and pushed three questions to this ticket: whether the boundary includes the
content, how the global SFX bank differs from SMD, and what the package is
called when it is not just SMD. All three were framed on a premise the ADR
inherited from #307 and labelled as established — **"three sequence formats —
SMD (music), FEDS (attached to an effect), and the global SFX bank
(standalone)."** That premise is wrong, and correcting it collapses two of the
three questions.

**Two dispatch tables, one ROM jump table.** The addon carries
`runtime/sequencer/opcodes/_table.gd` (music) and
`runtime/shared/opcodes/_table.gd` (effect sound). Both docstrings name the
*same* PSX routine: *"the analog of FFT's `smd_opcode_jumptable @ 0x80028B0C`."*
The tables were compared entry by entry (2026-08-21, `55b7e4653`):

| | |
|---|---|
| opcodes in the music table | **67** |
| opcodes in the effect-sound table | **62** |
| of the 62, also in the music table | **62** — a strict subset |
| music-side entries that **delegate** into `shared/` | **32** |
| the same byte implemented **twice**, two files, two bodies | **30** |
| music-only opcodes | **5** |

The five music-only opcodes are `0x97` TimeSignature, `0xA0` Tempo, `0xC3`
AdsrDecayRate, `0xC6` Adsr1LowNibbleSlide, `0xC8` AdsrAttackMode — and **two of
the five keep their handler file under `shared/`** (`tempo.gd`,
`time_signature.gd`), bound only from the music table. As *code*, the entire
SMD-vs-FEDS split is five opcodes and a header.

**The global SFX bank is not a format.** Read from the bytes, not the prose:

```
system.feds   magic='feds'  size=8490   entry_count=168  category=0x0000
env.feds      magic='feds'  size=2106   entry_count=27   category=0x0001
E000/feds.bin magic='feds'  size=225    field@0x08=3     field@0x0A=2
```

Same magic, same header shape, same `+0x0A` bank/resource selector. Both global
banks are lifted **verbatim** off the disc — `SOUND/SYSTEM.SED` and
`SOUND/ENV.SED` — by `tools/parse_sfx_banks.py`, whose own docstring cites the
PSX linked-list head at `DAT_80032a00`. `FedsBank.load_from_file` auto-detects
all three cases in one code path, and `SfxRouter` plays a global-bank slot
through `ExMateriaEffectSfx.audition(...)` — **the same driver the effect-cast path
uses**. ADR-0124's hypothesis (*"FEDS-shaped without the effect attachment"*)
is confirmed and was understated: it is not *shaped like* FEDS, it **is** FEDS.

**`CONTEXT.md` already carried the right model, and nobody had compared it to
the ADR.** Its *Shared lower layer* section says of a FEDS bank: *"Same opcode
language as SMD; different header"*, and of an opcode: *"Shared VM: FEDS effect
sound, SMD music, and the SFX banks all dispatch through the same handlers."*
That is dec. 1, and git dates it `2beb045cf`, **2026-06-04** — eleven weeks
*before* ADR-0124 wrote "three sequence formats" on 2026-08-20 (`3059b837b`). The
same failure mode as [ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
(`BLUEPRINT.md` contradicting itself) and [ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
(two lists, one declaration). `CONTEXT.md` overstates it in exactly one place —
*"the same handlers"* is true of 32 of the music table's 67 entries, not all of
them — and is corrected here rather than the other way round.

**The one thing the blueprint never measured is the host side.**
`BLUEPRINT.md` §7 calls `Audio` *"The closest system to finished"* —
*"`Effects`' calibration benchmark, and not the same thing as extracted"* —
evidenced by `exmateria_sound` referencing zero of the host's 24 autoloads. That
reading is correct — re-verified here, and the addon's mentions of
`ExMateriaAudioEngine`/`ExMateriaEffectSfx` are **four, all comments, zero in code** (two
more than ADR-0127 counted, both also comments: `pool.gd:22`,
`smd_player.gd:71`). It measures the wrong direction.

> **Quotation corrected 2026-08-22 by
> [ADR-0153](0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md),
> and it costs this ADR a little of its framing.** Both sites above quoted
> `BLUEPRINT.md` as calling `Audio` *"the calibrated example of a finished
> system"*. **That phrase is in neither `BLUEPRINT.md` nor
> [ADR-0117](0117-the-blueprints-ten-systems.md)**; it is a fusion of two adjacent
> real ones — *"The closest system to finished"* and *"`Effects`' calibration
> benchmark"* (`BLUEPRINT.md` §7). The same phantom is quoted a third time, as
> ADR-0117's, in [ADR-0124](0124-effects-tells-audio-a-code-and-a-time.md), which
> is corrected in the same commit: one phrase never written, three citing sites,
> two claimed sources.
>
> **Dec. 5's substance is untouched** — the 1,261-line driver in the host and the
> four autoloads are measurements, and they stand. What the correction costs is
> the framing: `BLUEPRINT.md` says *"and not the same thing as extracted"* on the
> same line, so it already carried the caveat dec. 5 presents itself as
> supplying. The blueprint was **less wrong than this ADR said**, and dec. 5's
> real contribution is the host-side measurement nobody had taken, not the
> correction of an overclaim nobody had made.

## Decision

**1. `Audio` is one opcode language in two containers, not three sequence
formats.** The containers are `smds` (a track set with tempo, time signature,
title and an associated waveset id) and `feds` (a stride-2 table of channel-pair
offsets). Below the header they are the same bytecode, dispatched from the same
PSX jump table. **ADR-0124's "N sequence formats" is amended to "two containers
over one opcode language"**, and its line *"all three formats play through
[`WAVESET.WD`]"* to *"both containers play through it."*

**2. The global SFX bank is a third `feds` bank family, not a third format.**
The only difference from a per-effect bank is **packaging** — a standalone disc
file versus a section sliced out of `E###.BIN` at `header[0x20]`. It carries no
container/config tier: `SoundContainer` selection (ADR-0124 TIER-2) is an
effect-side table, so a global-bank cue addresses a pair directly (`pair_idx =
sound_id - 1`). That is the whole of the asymmetry #313 asked about.

**3. `Audio` owns its content: one instrument bank and four bank families.**
Ratifies ADR-0124 dec. 3 with the count made concrete (measured 2026-08-21):

| Family | Count | Where it lives today |
|---|---|---|
| instrument bank | `WAVESET.WD`, 177 instruments (169 active) | `assets/music/` |
| SMD songs | 100 × `MUSIC_NN.SMD` | `assets/music/` |
| global `feds` banks | 2 — header entry counts 168 + 27; **190 decoded playable sounds** (167 system + 23 env) | `assets/audio/sfx_banks/` |
| per-effect `feds` banks | 401 (389 distinct, per ADR-0124) | `assets/effects/E###/` |

The fourth family sits in **`Effects`' asset directory** — the content-side
mirror of #307's finding that `Effects` holds 5,306 lines of `Audio`'s format.
By [ADR-0132](0132-assets-are-filed-by-consuming-system-not-by-provenance.md)
(filed by consuming system, provenance decides gitignore and nothing else) it
files under `Audio`. **Whether it ships as 401 banks or repacked stays #308's
packaging question**, unchanged by this.

**4. The directory is `exmateria-sound/`; the role is `Audio`; the shipped name
is ExMateria-Sound.** Discharges ADR-0124 dec. 4, which deferred the rename
here. The ticket's premise was half wrong and the correction is worth keeping:
**`exmateria_sound` was never named after a format.** The package has published
to `timbermania/ExMateria-Sound` under `publish/manifests/exmateria-sound.manifest`,
`CONTEXT-MAP.md` already called it ExMateria-Sound, and only the *monorepo
directory* still said SMD. This is the rule `BLUEPRINT.md` already states —
*"the blueprint names the role; the shipped addon gets its own name"* — applied
one level further out than anyone had applied it. Renamed in `55b7e4653`;
`smd_player.gd`, `SMDParser` and `SMDOpcodes` keep their names because they
genuinely name the SMD container.

> **Amended 2026-08-22 at extraction #2 loop pass 6 (#407): TWO of the three
> kept names survive the reason given for them, not three.** `smd_player.gd` and
> `SMDParser` do genuinely name the SMD container. `SMDOpcodes` did not, and the
> file it lived in said so in its own docstring — *"SMD opcode definitions and
> track decoder"* — while decoding **both** containers: `smd_parser.gd:97` and
> `feds_bank.gd:141`/`:170` all call `SoundOpcodes.decode_track`. It was the
> shared VM wearing one container's name, which is the same defect ADR-0136
> dec. 7 named in `shared/` one directory down and #406 has now fixed there too.
>
> Renamed to **`SoundOpcodes`** in `runtime/sound_opcodes.gd`. The blast radius
> was lopsided in the way ADR-0153 dec. 10 predicted and **the host half was
> under-counted by the ticket**: 106 addon references over 77 files all go
> through the global `class_name`, but the host binds the **preload path on 13
> lines across 13 files** — 8 in `src/`, 4 in `tests/`, 1 in `tools/` — not the
> two #407 states, plus `tools/test_feds_opcode_drift.py`, which builds the path
> as a string and would have broken silently. **So the FILE rename, not the
> symbol rename, is the part with teeth**, and it has six times the reach the
> ticket credited it with.
>
> `SMDFile` and the four string literals naming the on-disc format
> (`"SOUND/MUSIC_%02d.SMD"`, `"Invalid SMD magic"`, `"SMD too small"`,
> `"Cannot open SMD: "`) are untouched and must stay — they name the container
> and the disc, which is exactly the test this amendment applies.

**5. `Audio` is not finished, and the calibration measured the wrong
direction.** The addon reaches the host zero times in code — true, and it is a
statement about the addon, not about the system. Measured on trunk `b76311092`
(2026-08-21):

- **`Audio` *is* four of the host's 26 autoloads** — `ExMateriaAudioEngine`,
  `MusicPlayer`, `ExMateriaEffectSfx`, `SfxRouter` — reached from **79 sites in 21
  host `src/` files**, plus 37 more files under `tests/` and `tools/`. Every one
  is a hardcoded global name, which
  [ADR-0127](0127-effects-publishes-and-requires-two-ports.md) already rules can
  never be a crossing.
- **`EffectSfxEngine.gd` is 1,261 lines and it is *driver*** — SPU units, the
  24-voice budget and its FAITHFUL/UNLOCKED modes, the producer thread, the
  pool, per-unit reverb and idle-skip. It preloads five addon files and models
  the PSX SPU. It is `Audio`'s, and it is in the host.

**Half of this was already on the page and read as `Effects`' problem.**
ADR-0127 names `ExMateriaEffectSfx` in its list of five autoloads *"an addon cannot
be satisfied by"* — but it was counting what `Effects` reaches. Turned around,
`ExMateriaEffectSfx` is not a host service `Effects` depends on; it is **`Audio`'s
driver, parked in the host under a global name**. The same line of evidence
answers a different question depending on which system you are standing in, and
nobody had stood in `Audio`.

So the finished system is **15,953 addon lines plus a 1,261-line driver the host
still owns**, behind four autoload names. `Audio` is the *closest* system to
extracted, not an extracted one — and the gap is a driver split, not residue.

**6. `Audio`'s host figure is 2,034 live lines, not 2,671.** Five of its twelve
classified files — 637 lines, 24% — are entry-point scripts for scenes declined
by ADR-0112 dec. 2 / [ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
(`SfxStressTest` 213, `SfxBankTestScene` 131, `FEDSTestScene` 116,
`AttackSfxTestScene` 109, `SMDTestScene` 68). ADR-0135 dec. 11 keeps them
classified until pass 5 deletes them, so the instrument will keep reporting
12/2,671; **reason about `Audio` as 7 files / 2,034 lines.** Four of the five are
SFX-side harnesses, which is why the SMD/FEDS split has less host code behind it
than the census suggests. `EffectSfxEngine.gd` alone is **62%** of the live
figure.

> **Re-derived 2026-08-21 by [ADR-0141](0141-extraction-1-is-render-and-the-clean-five-is-retired.md)
> dec. 6: the live figure is now 8 files / 2,180 lines, and
> `EffectSfxEngine.gd` is 57.8% of it.** The 637 declined-scene lines excluded
> are unchanged; the difference is `SpuAudioDebugPanel.gd` (146), which
> [ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)'s classifier fix
> booked to `Audio`. The instrument now reports 13/2,817.

**7. `shared/` is the one name inside the addon that is wrong, and renaming it
is not this map's.** It reads as *"the tree both paths share"*; it is the
effect-sound dispatcher's tree, which the music table borrows from for 32 of its
67 entries while duplicating 30 others, and which hosts two music-only handlers.
The honest names are the two paths plus what is genuinely common. Recorded as a
defect for `Audio`'s extraction pass; **this ADR does not schedule it.**

## Consequences

**Two of #313's three questions dissolved rather than resolved, and that is the
result.** Question 2 (*how does the global SFX bank differ from SMD?*) has no
interesting answer once the format count is corrected — it differs from SMD
exactly as FEDS does, and from FEDS only in packaging. Question 3 was already
answered by the repo's own publish manifest; only the directory had not caught
up. The premise was the work.

**The rename is inert to the pass-6 baseline and was verified so.** After
`55b7e4653`, `classify_blueprint.py` still reads **470 files / 141,831 lines**
with `Audio` at 12/2,671, and `touch_matrix.py` still reads **358 cross-system
edges**. Every `.gd` change inside `godot-learning/` is a comment. Nothing
outside the repo referenced the old directory name — no URL, no published repo,
no external consumer — so this is the cheapest such rename will ever be.

**Decision 5 gives `Audio`'s extraction pass its actual shape, and it is not
what the extraction order assumed.** `Audio` was slotted as cheap validation
because the addon already exists. What is left is a **driver split**:
`EffectSfxEngine.gd` divides into the part that belongs in the addon (SPU units,
pool, producer thread, voice budget) and the ~20-line host adapter that
[ADR-0118](0118-payloads-are-schemas-services-are-ports.md) dec. 6 predicts,
and the four autoload names collapse to declared ports. That is the same shape
`Render` got from #316 and the Studio got from #324 — a system whose residue is
smaller than its host presence — but `Audio` is the first where the residue is a
*driver* rather than wiring.

**A measured discrepancy is raised and deliberately not settled here.** Of the
30 opcodes implemented in both trees, **24 cite the same PSX address** in their
docstrings and **6 do not** — `0x81`, `0x91`, `0x95`, `0x96`, `0x99`, `0x9A`
(e.g. music `0x91` cites `LAB_800158C4`, effect-sound `0x91` cites
`LAB_800159DC` and jump-table entry `0x80028B50`). Separately, five duplicated
pairs carry mismatched *filenames*, and four of the five are stale rather than
divergent — `sequencer/opcodes/adsr_decay.gd` says in its own docstring *"was
misidentified as 'decay' in the original music binding"* and implements the
`0xC9` ADSR2-high mode selector, matching its `shared/` twin exactly. **Whether
the six address citations are two ROM routines or one mis-citation cannot be
settled from the repo**; it needs the ROM, it belongs to the sound package rather
than the blueprint, and it is filed as such. It is recorded here because "one
opcode language" is the load-bearing claim of dec. 1 and this is the one piece of
evidence that could unseat it.

**The blueprint's benchmark keeps its value but loses its wording.**
`exmateria_sound`'s zero autoload reaches is still the calibration
[ADR-0133](0133-a-wrong-cut-is-fixed-forward-and-the-reconnect-is-the-trigger.md)
uses for a clean addon boundary, and it survived re-verification. What it cannot
be is evidence that `Audio` is finished — a departed addon reaching back is one
defect, and the host holding a system's driver behind global names is another.
**The reach metric only ever counted the first.** In `touch_matrix.py` the
`Audio` **row** is 4 edges out; the `Audio` **column** is 16 edges in, and those
16 file→system edges are the 79 call sites compressed. Neither number is the
benchmark BLUEPRINT §7 quoted, which was an addon-internal grep. A system can
reach nothing and still be held by its host through four global names.
