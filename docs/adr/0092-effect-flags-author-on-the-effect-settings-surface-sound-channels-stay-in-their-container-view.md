# Effect Flags author on the Effect Settings surface; sound channels stay in their container view

Status: accepted (design settled via /grilling 2026-08-13; build via
[timbermania/fft-monorepo#272](https://github.com/timbermania/fft-monorepo/issues/272)
`/tdd` pending)

## Context

[#271](https://github.com/timbermania/fft-monorepo/issues/271) opened the effect-level
GLOBAL **Effect Settings** surface (a new `effect_settings` inspection target →
`EffectSettingsProjector`, whose `sections()` is an array so later small-byte clusters
append as pure additions — [ADR-0073](0073-effect-studio-inspection-is-target-kind-dispatched-through-a-projector-registry.md)).
Its first tenant was the three timeline-header phase durations. **Effect Flags**
(#272, gap 24 B) is the natural second tenant on that surface.

The 24-byte `effect_flags` section (header `0x18` → `effect_flags_ptr`, runtime global
`0x801BACC8`) is documented at
`research/wiki_articles/effect_flags_section.txt`. Its layout is **not** the uniform
"bitflags + int + 4 ids" the #262 board sketched — it decomposes into three parts with
**different owners and readiness**:

- **`flags_byte` @0x00** — only bits 3–6 are read by the engine (proven exhaustively
  at `0x801A1530`/`0x801A61E0`/`0x801A3BF8`/`0x801A4A5C`): bit3 `TERRAIN_HEIGHT_ADJUST`,
  bit4 `AUDIO_FADE`, bit5 `TIME_SCALE_3PHASE`, bit6 `TIME_SCALE_1PHASE`. Bits 0–2/7 are
  loaded but AND-masked away; effect files still set them (`0x01`, `0x03` are common).
  Surfaced **nowhere** today. This is the clean, unclaimed core of #272.
- **`spawn_delay_override` @0x04** — the byte the #257/D3 manifest note calls an editable
  `default_frame_delay` gap. It is in fact **dead code** (wiki §4): the override path at
  `0x801A1A28` only runs when `DAT_801bad0f != 0`, which is copied from unit field
  `0x19F`, and **`0x19F` is never written** anywhere in `BATTLE.BIN` (single `lbu` at
  `0x8007F68C`, zeroed at init). E001 stores `0x44` there and the engine never reads it.
  The live spawn delay is the timeline-header `0x06`, already editable via #271.
- **Sound channels @0x08–0x17** (4 × `{mode, id_a, id_b, reserved}`) — already parsed
  (`SoundContainerModel`) and projected **read-only** as the `container` inspection
  target (`SoundContainerProjector`), reached by navigating from a sound trigger, with
  "used by N triggers" reverse-links. They are the TIER-2 resolution target the built
  Sound-Timeline ([#268](https://github.com/timbermania/fft-monorepo/issues/268), ADR-0085)
  indexes into (`sound_id − 2`), and they already round-trip through `sound_containers.json`.

Two bits of the flags byte (5/6) are **also** already decoded in `time_scale.json`, and
the studio preview honours them: `EffectTimeline._update_time_scale` scales
`_time_scale_factor` from the pacing curve **only when** `flags.time_scale_pattern1/2`
is set (E019's `outer_phases` curve peaks at pacing 10 → strong slow-mo).

## Decision

**#272 makes the `flags_byte` editable on the Effect Settings surface, and nothing else
this ticket.**

1. **New "Flags" section** on `EffectSettingsProjector.sections()` — one F1 `bitflags`
   checkbox group over the flags byte, exposing **all four engine-read bits** (bit3
   terrain-adjust, bit4 audio-fade, bit5 time-scale-3phase, bit6 time-scale-1phase).
   The two time-scale enables ride here (they live in this byte) rather than waiting for
   the Time-Scale build ([#270](https://github.com/timbermania/fft-monorepo/issues/270)),
   which will add the curve editor and cross-link.
2. **Ignored bits (0–2, 7) are preserved verbatim.** The `bitflags` editor toggles only
   declared masks over the live raw word, so unlisted bits ride along untouched — but
   only if the word is seeded from the **actual raw byte** (E001's `0x03`, not just the
   four booleans). `effect_flags.json` therefore carries the raw `flags_byte`.
3. **`0x04` → `na`.** Reclassify the dead byte as ROM-fixed, not an editability gap.
   Correct the manifest's D3 note. The writer preserves its bytes verbatim.
4. **Sound channels stay deferred** (`display`, still an open gap). When edited, they will
   be flipped to `shape:"edit"` **in their existing `SoundContainerProjector`** (a
   `SoundContainerChannel` + writer), preserving the "used by N" shared-object safety —
   **not** re-projected as flat rows on the Effect Settings surface, which would duplicate
   the container view and lose the reverse-links. That is a separate sound-subsystem slice.
5. **Sourcing: a new `effect_flags.json`** emitted by `parse_effect.py` (raw `flags_byte`
   + the four decoded bools), parsed into `EffectData.flags`, so the projector reads a
   parsed model field the same way #271 reads `data.timeline` — convention-matching.
   Regenerate all 401 effect dirs. (The section is present in every effect, unlike the
   conditional `time_scale.json`, which is why the two time-scale bits can't be sourced
   from there.)
6. **Live re-render (`invalidates_sim=true`).** The flags channel writes the flags var and,
   for bits 5/6, **syncs `data.time_scale.flags.time_scale_pattern1/2`** so a re-fold makes
   the slow-mo enable/disable visible immediately. Bits 3/4 re-fold harmlessly (no
   visible change in the isolated, terrain-less preview; audio-fade is only audible at
   effect end) — accepted.

### The bounded recipe (mirrors #271, no architecture invention)

- `EffectFlagsChannel.gd` (carries a `class_name`, as every sibling write-channel does;
  projectors/target/registry/savers do not — match the file's neighbours) —
  `apply_raw` writes the flags var + syncs time-scale flags for bits 5/6;
  `invalidates_sim=true`; scalar undo (raw byte re-derives).
- `EffectEditSession._dispatch` case for channel `"effect_flags"`.
- `write_effect_flags.py` + `effect_writer_registry.serialize_effect_flags` —
  partial-patch **one byte** at `effect_flags_ptr + 0x00` from `header.json`, everything
  else verbatim. `EffectFlagsSaver` layered into `studio_save` after the timeline-header
  saver (disjoint bytes — flags at `effect_flags_ptr`, durations at `timeline_section_ptr`).
- Manifest: `flags_byte` → editable, `0x04` + padding → `na`, sound channels stay
  `display`; append a guard probe to `EffectEditabilityManifestTest`.

## Considered options

- **Flat sound-channel rows on Effect Settings** (the #262-board sketch) — rejected: it
  duplicates the `container` projection and drops the "used by N triggers" reverse-link
  safety an author needs before editing a shared object.
- **Surface `0x04` as an editable `int`** (honour the D3 note) — rejected: it is provably
  dead code; an authoring knob with zero runtime effect misleads, and the live spawn
  delay already has an editor (#271).
- **Read the flags byte straight from the base `.BIN`** at Effect-Settings-open (no
  regen) — rejected in favour of the convention-matching parsed-JSON model field, at the
  cost of a 401-dir regen.
- **Save-only (`invalidates_sim=false`)** — rejected: the preview genuinely honours the
  time-scale enables, so live feedback is real for bits 5/6.
- **Defer the two time-scale bits to #270** — rejected: they live in this byte and the
  `bitflags` editor handles them uniformly; toggling the existing slow-mo on/off is
  useful now.

## Consequences

- The `effect_flags` subsystem **partially closes**: the flags byte becomes editable, but
  the 16-byte sound-channel block stays an open `display` gap, so the subsystem's gap does
  **not** shrink to 0 this ticket. This is the honest representation under the manifest's
  conservative "over-count until a build ticket carves it" policy.
- `parse_effect.py` gains a new per-effect output and all 401 `assets/effects/E###/` dirs
  gain an `effect_flags.json` (a large but mechanical diff).
- Bits 5/6 now have **two** in-model representations (`data.flags` and
  `data.time_scale.flags`); the channel keeps them in sync on edit. On reload both are
  re-derived from the (patched) BIN, so they can't drift across sessions.
- The Effect Settings surface is proven as a **multi-section host** — Time-Scale (#270)
  remains a pure `sections()` addition on the same surface.

## Amendment 1 (2026-08-13, #270 design via `/grill-with-docs`) — the two time-scale bits relocate to Time Scale

When Time Scale becomes editable (#270), the two time-scale enable bits **move out** of the
Effect Flags `bitflags` group and into the **pop-up editor that opens from the Time Scale
band on the timeline** (ADR-0093), each rendered as a **single-bit checkbox colocated with the
curve it gates** ("Phase 1 pacing" = bit 5, "For-each pacing" = bit 6). Rationale (the user's
call): one control per concept, sitting next to its curve, so the enable and the pacing shape
are authored in the same place. This **reverses** this ADR's "the `bitflags` editor handles them
uniformly" framing — the Effect Flags group drops to the **two** remaining engine-read bits it
still owns (bit 3 terrain-adjust, bit 4 audio-fade). A future reader who expected "the four
engine-read bits" grouped here should read that as bits 3/4 only; bits 5/6 are surfaced on the
Time Scale timeline path (not on this Effect Settings surface at all).

**Unchanged under the hood:** bits 5/6 physically live in `flags_byte`; `time_scale.flags` is a
*mirror*. The relocated checkboxes still write through the existing `effect_flags` channel
(read-modify-write the byte, mirror follows), so this is a **UI relocation, not a second
writer** — the "two in-model representations kept in sync" consequence above still holds. The
byte-exact save path and the parsed-JSON model are untouched. See ADR-0093 for the pacing-curve
authoring model that the relocated enables sit beside.

## Cross-reference (2026-08-21) — the sound-channel ruling is *answered*, not overturned

The ADR-0085 amendment of this date puts the sound event, its container and its FEDS pair on
one page ("chain inspection"). That is **not** the rejected alternative above. The rejected
shape was *flat sound-channel rows re-projected onto the Effect Settings surface*, which would
duplicate the container view and drop the reverse-links. Chain inspection does neither: there
is still exactly one `SoundContainerProjector` — it *is* the section — and it still emits its
own `Used by N triggers` header, carried on the collapsed summary line.

The corpus is kinder to this ADR's concern than the design debate assumed: 1,001 of 1,002
pairs are reached from a single container, and 87.9% of referenced containers are used by
exactly one event. The asymmetry that actually needs handling runs the other way (85
containers emit 2–3 distinct pairs, covering 15.3% of events) and is handled there, not here.
All figures: `godot-learning/tools/measure_sound_fanout.py`.

The container decision itself has since been built editable in place, exactly as this ADR
specified — mode radio plus the three bank-entry pickers, in `SoundContainerProjector`,
lowering through `SoundContainerChannel`.

## Amendment 2 (2026-08-28) — every decision is built, but Amendment 1's *removal* half never landed, and a green test pins the four-bit group it forbids

*Audit pass, 2026-08-28 (ADR consolidation). The six Decision items above were unnumbered
prose; they are now `1.`–`6.` so `ADR-0092 dec. N` citations resolve. The heading above became
`Amendment 1` — no citation of it addressed the date, so no anchor moved. Nothing was deleted.
Graded against the tree, not against the tickets.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | New "Flags" section, one `bitflags` group over **all four** engine-read bits | **built — and contradicted by Amendment 1** | `EffectSettingsProjector._flags_section()` returns one row with masks `0x08/0x10/0x20/0x40`, tooltip "The four engine-read bits". Amendment 1 says the group drops to bits 3/4. |
| 2 | Ignored bits 0–2/7 preserved verbatim; word seeded from the **raw** byte | **holds** | `EffectFlagsChannel.apply_raw` writes the whole `word & 0xFF`; `EffectStudioEffectFlagsAcceptanceTest` seeds E019's raw `0x23` and asserts `& 0x03 == 0x03` after a toggle. |
| 3 | `0x04` → `na`, D3 note corrected | **holds** | `editability_manifest.json` → `effect_flags.fields.spawn_delay_override: "na"`, with the note calling the earlier D3 `default_frame_delay` reading WRONG. |
| 4 | Sound channels stay `display`, edited later in `SoundContainerProjector` | **holds, and has since been paid** | Manifest still says `sound_channels: "display"`; the container itself is now editable in place (mode radio + three FEDS-bank pickers, two `shape:"edit"` rows, `SoundContainerChannel`), exactly the shape this ADR named. The Cross-reference's closing claim grades accurate. |
| 5 | Sourcing: a new `effect_flags.json` from `parse_effect.py`, parsed into `EffectData.flags`; regenerate all 401 dirs | **reader half built; the 401-dir claim is not checkable in this worktree** | `EffectData.gd:218` loads `effect_flags.json` unconditionally per effect and fills `data.flags`. `assets/effects/` is gitignored ROM-derived content and is unpopulated in this checkout, so the regen itself is **unverified here, not refuted** — do not read a zero count off this tree. |
| 6 | `invalidates_sim=true`; bits 5/6 sync `time_scale.flags` | **holds** | `EffectFlagsChannel.apply_raw` mirrors bits 5/6 into `data.time_scale["flags"]` when the block exists and returns `"invalidates_sim": true` unconditionally. |
| recipe | channel / dispatch case / writer / saver / manifest probe | **all five exist** | `EffectFlagsChannel.gd`, `EffectEditSession.gd:776` case `"effect_flags"`, `tools/write_effect_flags.py` + `effect_writer_registry.serialize_effect_flags` (`:255`), `EffectFlagsSaver.gd`, and probes in `EffectEditabilityManifestTest`. |
| Amd 1 | bits 5/6 **move out**; "not on this Effect Settings surface at all" | **half-landed — the addition happened, the removal did not** | The pop-up path exists (`EffectStudioPage._pacing_enable_bit` maps `outer_phases`→`0x20`, `for_each`→`0x40`, labels "Phase 1 pacing"/"For-each pacing", writing `effect_flags/flags_byte` at `:6331`). The bitflags group still carries both bits too. |

### The Status line is four ADRs' worth of stale

Status still reads "build via #272 `/tdd` **pending**". #272 is built and load-bearing: the
channel, the dispatch case, the Python writer, the saver and the manifest note (`"#272 LANDED
(ADR-0092)"`) are all in the tree, and three test files exercise them. This is the fourth
consecutive audited ADR (0040, 0069, 0071, 0092) whose Status advertises unshipped work that
shipped — a corpus-level pattern, not a fact about this document.

### A green test asserts what Amendment 1 forbids

`tests/EffectSettingsProjectorTest.gd` (`_test_flags_row_declares_four_engine_bits`, `:183`–`:196`)
asserts `bits.size() == 4` and, by mask, that `0x20` "time-scale 3-phase" and `0x40`
"time-scale 1-phase" are checkboxes on the Effect Settings Flags row. Amendment 1 says those
two bits are "not on this Effect Settings surface at all". Both are green today because the
code sides with the Decision, not with the Amendment. ADR-0093 `:92` repeats the Amendment's
reading in a second document ("so those bits are surfaced **only** on the timeline path"), so
the divergence is written down twice and true in neither place.

The two surfaces are not two *writers* — Amendment 1's "UI relocation, not a second writer"
grades accurate: `EffectStudioPage.gd:6331` and `EffectSettingsProjector.gd:82` both address
`{"channel": "effect_flags", "field": "flags_byte"}`, so there is one choke point
(`EffectEditSession.apply_edit`) and one undo shape. What exists twice is the **control**.

### The recipe's `class_name` rule was already false when it was written

The bounded recipe justifies `EffectFlagsChannel`'s `class_name` as "every sibling
write-channel does; projectors/target/registry/**savers** do not". The prediction for the two
files it names came out right — `EffectFlagsChannel.gd` declares one, `EffectFlagsSaver.gd`
and `EffectSettingsProjector.gd` do not. The stated *reason* does not hold in either
direction: 5 of 16 `*Channel.gd` files carry no `class_name` (`CurveChannel`,
`EffectScriptChannel`, `SoundContainerChannel`, `SoundDefChannel`, `TextureChannel`), and 7 of
12 `*Saver.gd` files do carry one — three of them (`EffectCameraSaver` 2026-08-09,
`EffectPaletteSaver` 2026-08-10, `EffectSoundSaver` 2026-08-11) predate this ADR. "Match the
file's neighbours" was the operative instruction; the census offered as its evidence was not.

### Recorded question — which side of the bits 5/6 divergence is the defect?

Two readings, and the ADR cannot settle its own case because its Decision and its Amendment 1
say opposite things:

- **Reading A — the relocation is unfinished.** Amendment 1 is the later ruling and states the
  intent plainly ("one control per concept, sitting next to its curve"). Landing it means
  deleting masks `0x20`/`0x40` from `_flags_section()`, retitling the tooltip, and **deleting
  two assertions from a currently-green test** (`EffectSettingsProjectorTest:189`–`:196`)
  plus the acceptance test's bit-5 sync arm. Cost: a manifest note rewrite too (the
  `"#272 LANDED"` note also enumerates all four bits on this surface).
- **Reading B — the tree is right and Amendment 1 overstated.** Keeping the enables in both
  places costs nothing mechanically (one channel, one choke point, one undo) and gives the
  author the byte's full picture on the Effect Settings surface plus the enable beside the
  curve where they are shaping it. Landing this means editing Amendment 1's "not on this
  Effect Settings surface at all" and ADR-0093 `:92`'s "**only** on the timeline path".

This is a product call about one control's home, not a mechanical one. Not guessed here.

### On mechanizing this ADR

Decisions 2, 3, 4 and 6 are already mechanized by `EffectSettingsProjectorTest`,
`EffectStudioEffectFlagsAcceptanceTest`, `EffectFlagsChannelTest`, `EffectFlagsSaverTest` and
`EffectEditabilityManifestTest` — this ADR is among the better-guarded in the corpus. The one
arm that is **absent and cannot be written until the question above is answered** is a guard
over the bit-5/6 *home*: whichever reading wins, the assertion is "mask `0x20`/`0x40` appear on
exactly one of `_flags_section()` and the Time Scale pop-up", and today it would report **two**.
Writing it now would only pin whichever answer the author of the guard happened to prefer.
