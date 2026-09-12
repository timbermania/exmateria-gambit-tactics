# Audio

The project has **two audio paths** that share an SPU backend but differ in
ownership, data shapes, and trigger models. Below the path-level split, both
paths converge on a **shared playback chain** (Trackset → Sequencer →
Opcodes → SPU voice). This cluster keeps each level straight.

#### Paths

**Effect SFX**:
The audio bound to a spell or ability cast — driven by the cast's [sound
subsystem](15-effect-orchestration.md), which advances [phase blocks](15-effect-orchestration.md)
of sound [channels](15-effect-orchestration.md) of [keyframes](15-effect-orchestration.md).
A keyframe fire walks the chain: keyframe → [SoundContainer](14-audio.md) →
resolver → [FEDS pair](14-audio.md) → [Trackset](14-audio.md) → [Sequencer](14-audio.md).
Per-effect FEDS data lives at `assets/effects/E###/feds.bin`. **Owned by the
effects system.** Adding a new spell adds its own FEDS data alongside the
cast's visual subsystems; no other audio surface touches it.
_Avoid_: calling per-effect sounds "SFX" without qualification — they
do not flow through the cue registry below; routing them through
`SfxRouter` (effect-cast state flows through the sound subsystem's
[PhaseBlock](15-effect-orchestration.md), which carries session tokens the
router doesn't model).

**Game-event SFX**:
The audio bound to *game state*, not to an effect cast — unit death, UI
navigation, ambient/environment, hit landed, status applied, etc. Plays from
the global FFT banks at `assets/audio/sfx_banks/{system,env}.feds`, routed
through `SfxRouter`. One-shot or looping; never carries a per-cast session.
_Avoid_: calling these "effect sounds" — they are not part of an effect's
authored data.

#### Effect-cast SFX chain

The chain a sound keyframe walks, from fire to SPU output:

```
Channel (in a sound PhaseBlock)
  └── Keyframe { duration_frames, sound_id }
       │
       ├── sound_container_idx = sound_id - 2
       │
       └── SoundContainer { mode, id_a, id_b, id_c, counter }
            └── EffectSoundResolver applies Mode → resolved sound_id
                 │
                 └── pair_idx = resolved_sound_id - 1
                      │
                      └── FEDS pair (2 tracks)
                           │
                           └── wrapped at playback time
                                │
                                └── Trackset (conductor track + 2 tracks)
                                     │
                                     └── Sequencer plays
                                          │
                                          └── Opcodes → NoteEvents → SPU voice
```

**SoundContainer**:
The per-effect "TIER-2" sound entry — `{mode, id_a, id_b, id_c, counter}`.
Industry-equivalent: Wwise Random/Sequence Container. Each container
**selects one [FEDS pair](14-audio.md) per fire** from up to three candidates
(`id_a` / `id_b` / `id_c`) using a [Mode](14-audio.md) and a stateful counter.
**Not** a mixer — every resolve returns a single id; over many fires the
same container yields different pairs (alternation, cycling). Lives in the
parser-emitted `sound_containers.json` (per-effect, array of containers).
Read at runtime by `EffectSoundResolver`.
_Avoid_: calling it a "channel" — that word is reserved for sound-subsystem
keyframe lanes (above); calling it "channel config" — it is not config *of* a
timeline channel, it is shared **sound-selection logic** keyed by `sound_id`,
effect-global and referenced by many triggers; reading "container" as a generic CS
word — here it specifically means a Wwise-style sound-variant container.

**Mode**:
A container's selection strategy. Five real modes plus a passthrough:
- `0 DIRECT_A` → always `id_a`
- `1 PARITY_A` → `id_a` / `id_b` alternating (counter parity)
- `2 DIRECT_B` → `id_a` once, then `id_b` forever
- `3 PARITY_B` → `id_a` once, then `id_b` / `id_c` alternating
- `4 TRIPLE_CYCLE` → `id_a` / `id_b` / `id_c` round-robin
- `5+ DEFAULT` → passthrough the timeline `sound_id` unchanged
The counter post-increments per call; this is FFT-faithful behaviour from
`lookup_sound_effect` (0x801A32E8).

**EffectSoundResolver**:
The runtime that applies a container's [Mode](14-audio.md) + counter to pick a
sound_id. One per cast; loaded from the cast's `sound_containers.json`.
Returns `-1` for `sound_id < 2` (FFT's "Sound ID 0/1 = Skip" rule).

**FEDS pair**:
The paired structural unit in a [FEDS bank](14-audio.md): **exactly 2 [tracks](14-audio.md)**,
side by side. The bank exposes both `num_pairs` (groupings) and `num_tracks`
(= `num_pairs * 2`, total opcode streams). `pair_idx` is the index used by
the resolver's output. A pair on disk has **no conductor track** — the
conductor is added at wrap time when the pair becomes a [Trackset](14-audio.md).
A pair may also exhibit byte-walker flow-through: stub tracks without an
`EndBar` opcode (`0x90`) flow into adjacent tracks (see
`feds_bank.gd::get_track_bytes_from`).
_Avoid_: equating a pair with a [Trackset](14-audio.md) — they're different
shapes; the trackset adds the conductor; conflating pair indexing
(`pair_idx`) with track indexing (`track_idx`, 0..`num_tracks`-1).

**Track** (audio sense):
One parallel **opcode stream**. Used by SMD songs *and* FEDS pairs — same
opcode language, same VM. Distinct from CONTEXT.md's retired
effect-orchestration "track" (that's now [Subsystem](15-effect-orchestration.md);
see ADR-0014); distinct from the [Channel](15-effect-orchestration.md)
(keyframe lane). One FEDS pair = 2 tracks; one SMD file = N tracks.
_Avoid_: confusing with a [Channel](15-effect-orchestration.md); calling
tracks "voices" (voices are SPU hardware, allocated dynamically).

**Conductor track**:
Track 0 of a [Trackset](14-audio.md) by convention — holds tempo / global events
in an SMD song; sits empty (a structural placeholder) in a FEDS-pair-wrap.
The sequencer expects it; the bank may not provide one.

**Trackset**:
The **runtime structure** the sequencer plays: a conductor track + N normal
tracks. Both `.SMD` music and effect-cast FEDS pairs become tracksets at
load time. **A Trackset is *not* an `SMDFile`** — they're different types:
an SMDFile is a parsed `.SMD` file on disc; a Trackset is the in-memory
structure derived from one source or another. `FedsBank.pair_to_trackset(pair_idx)`
and `SMDFile.to_trackset()` are the two constructors.
_Avoid_: passing an `SMDFile` to the sequencer (it takes a Trackset);
treating the synthesised-from-FEDS Trackset as an SMD-anything — they
just share the runtime shape.

**SMDFile**:
A parsed `.SMD` music file (FFT-format music data on disc). Source of one
flavour of [Trackset](14-audio.md); has nothing to do with FEDS structurally
even though the lower-level opcode VM is shared. Lives in the exmateria-sound
package; see `exmateria-sound/CLAUDE.md` for the wider music vocabulary.

**Stub** (track):
A [track](14-audio.md) with no `EndBar` (`0x90`) of its own, so its voice **runs on
into the following bytecode** instead of stopping. A stub authors no audible note
— but it is **not silent**: it sounds the notes it borrows, on its own voice, and
its own opcodes (a pitch bend, say) colour them, so the pair is heard twice over,
slightly apart. In practice a stub is always the **first** track of its
[pair](14-audio.md) and borrows from its partner. _Avoid_: calling it a *silent* stub
(the borrowed notes are audible); reading it as inert cruft; or as one half of a
stereo pair — the two [tracks](14-audio.md) of a [FEDS pair](14-audio.md) are two layered
**voices**, never left/right ears (pan is a separate per-voice opcode).

**Flow-through** / **borrowed** (sound):
The bytecode a [stub](14-audio.md) executes past the end of its own bytes, and the
notes it therefore plays. Those notes are **borrowed**: they are heard on the
stub's voice but **authored by another track**, which owns them — you change one
by editing it where its bytes live, not where it is heard. _Avoid_: treating a
borrowed note as belonging to the track that sounds it, or as a copy that can be
edited in place.

**Span** (sound):
The unit of **time** in a [track](14-audio.md): a run of ticks that is either one **note**
or a **rest**. Spans **tile** a track end to end — every tick belongs to exactly one,
and there is no empty space between them. A span longer than the note encoding can
express is written as a note followed by `0x81 Fermata` segments, and the **split
points are where voice opcodes fire inside the note** — which is why a span is
re-timed by editing it, never by re-spelling it. On the time lane a span is ONE bar
with up to three fills: blue for the note's own `delta_time`, amber for the sounding
time its Fermata segments add, grey for a rest. _Avoid_: reading `0x81 Fermata` as an
event in its own right (it is more of the note already sounding) or as free of duration
(it adds ticks like any other); reading a tie or a note-form rest as a form FFT writes
(neither occurs anywhere in the corpus, music or effects).

**Sounding time** / **silent time**:
The two kinds of tick a [span](14-audio.md) can be made of. `0x81 Fermata` and `0x80 Rest`
each add exactly their parameter to the clock; the difference is that Fermata's ticks
are sounding (a note keeps playing through them) and Rest's are silent. A Fermata with
no note playing is silent time — including one that follows a Rest, since a Rest ends
the note it follows (zero corpus occurrences: a guard, not a path). _Avoid_: calling `0x80` "the rest opcode" as if `0x81`
were its opposite in *length* — they are opposites in *sound*, and identical in length.

**Rest** (verb, authoring):
What deleting a [span](14-audio.md) does: its ticks stay, its sound goes — each of the
span's time-carrying bytes substituted in place by a `0x80 Rest` of identical tick
count, segment for segment, so the interior opcodes keep their firing ticks and the
event count never changes. Delete and "make it a rest" are the same act, so deleting a
rest is a no-op and is not offered.
_Avoid_: expecting a delete to shorten a track — nothing that tiles a fixed clock can;
only the [outro](14-audio.md) moves a track's end.

**Un-rest** (verb, authoring):
Delete's inverse, and the only way to remove silence: a rest [span](14-audio.md) is re-spelled
as ONE note of the same length, at the corpus's single velocity (96) and its most common
key (C). The clock does not move — the ticks were already there, they simply start
sounding. The pair is byte-exact **only** for the corpus's own note: a rest keeps ticks,
never a key, so a deleted D comes back a C and the key is then a one-click edit.
_Avoid_: reading it as "undo" (undo restores the key; the un-rest cannot), or expecting
it to hand a rest's ticks back to the note before it — that is a length edit, and the
un-rest always writes a note of its own.

**Paint** (verb, authoring):
Putting a note INSIDE a rest, splitting it: `rest(N)` becomes
`rest(a) · note(d) · rest(N-a-d)`, the pieces of zero length simply not written. The
only verb on the time lane that raises the event count, and the one that unblocks
authoring rather than editing — with [rest](14-audio.md) and [un-rest](14-audio.md) it retiles a
track's clock at any granularity. Addressed like its siblings by the span head's byte
offset, plus a **tick offset within the span**: the addressing collision that anchors an
insert to a byte boundary cannot arise here, because a rest is exactly one event with no
interior. _Avoid_: calling it "insert" — an insert adds an opcode at a boundary and adds
no time; a paint adds no time either, it re-spells silence that was already there.

**Currency and wall** (sound-lane drag):
Who pays for a drag. A **rest** is the currency — consumable, cascading through a run of
consecutive rests. A **note** is a wall, and so is any **zero-tick opcode**, because
rewriting a rest's tick count ahead of one changes *when it fires*. Hence the law: *a
drag may re-time silence; it may never move an authored event's firing tick.* ADR-0095's
colour-lane rule with one wall added. A rest consumed to zero is spliced out, so unlike
the colour lanes, adjacency is expressible here. The rule has a **deposit** half too: the
ticks a drag spends are absorbed by the rest already touching the note on the other side,
or — when the thing touching it is an opcode or the track edge — by a NEW rest written
byte-adjacent to the note, *ahead* of that opcode. `Instrument note(16)` moved right
becomes `Instrument rest(k) note(16)`, and the Instrument still fires at its own tick.
_Avoid_: reading a run of rests as currency without checking for an opcode between them —
that is the difference between re-timing silence and silently re-timing an instrument
change. _Avoid_: growing the nearest rest on the deposit side without checking the same
thing, which is the same bug facing the other way.

**Outro** (sound):
The silence between a [track](14-audio.md)'s last authored event and its `0x90 EndBar` — the
run of `0x80 Rest`s immediately in front of the terminator, and the ONE place in a track
where time can be added or taken away without re-timing anything. It is a number, not an
event: 1917 of the corpus's 1928 terminated tracks have none at all, and only 11 have one
FFT wrote (`E015` t2 has 36 ticks, `E481` t3 has 75, `E259` t0 has 120). Setting it is the
only verb on this lane that moves `end_tick` — every other verb substitutes inside a fixed
tick total. The run stops at the first non-[rest](14-audio.md), for the same reason the drag's
cascade does: 482 corpus tracks end on a zero-tick `Coda`, and silence written in front of
one would change when it fires.
_Avoid_: offering it on a [stub](14-audio.md) — a stub has no terminator, so its stream stops at
a byte edge and everything after is [borrowed](14-audio.md); silence written there pushes another
track's authored work later in ticks. Give it an `EndBar` first. _Avoid_: reading an outro as
a special kind of silence — once it exists it is an ordinary rest span, which is exactly why
[paint](14-audio.md) and the drag reach it with nothing new.

**Key roll** (authoring surface):
The **second reading** of the time lane: 12 fixed rows of a note's `relative_key`
(C..B, high notes at the top, the five accidentals striped darker so the rows read as a
keyboard) plus a 13th **Rest** row, on the pair's own axis fitted to the pair. Opt-in per
pair via a `[ Lanes | Roll ]` chip and defaulting to Lanes; only the time lane changes
shape, and the Opcodes / Structure / Flow lanes stay, re-projected. It is
**octave-agnostic on purpose** — octave is set by the `Octave` / `RaiseOctave` /
`LowerOctave` opcodes and read from the Opcodes lane, so putting it on Y would draw an
opcode's *effect* as note geometry. That is also what makes dragging a note to a new
pitch a single same-size byte patch of the note data byte's key field, with no octave
boundary to cross. Reach for it when a track is too dense to read on one line — the
median track has 2 notes and does not need it, but 46.0% carry more.
_Avoid_: calling it a piano roll and expecting absolute pitch on Y, or reading two notes
on the same row as the same pitch — they share a key, and the bar's octave digit and its
fill tint are what tell them apart. _Avoid_: expecting the roll's zoom or scroll to move
the editor band's — it has its own axis, which is the point.

**Null slot** (track):
An **unused** entry in a [FEDS bank](14-audio.md)'s track table — the pair has only one
voice. Distinct from a [stub](14-audio.md) in the way that matters: a stub has bytes
and no ending, a null slot has **no bytes at all**, so it neither sounds nor
borrows. _Avoid_: inferring "stub" from "no `EndBar`" alone — a slot with nothing
in it has no `EndBar` either, and reading one as a stub makes a reader walk the
bank's own header as if it were music.

**NoEnd phantom** (authoring surface):
How a [stub](14-audio.md)'s [borrowed](14-audio.md) span is drawn: a marker standing where
the missing `EndBar` would be, spanning the borrowed stretch, that **folds** — shut
by default, opened to reveal the borrowed notes in place. It is **phantom** because
no byte encodes it; the surface shows it apart from anything the composer wrote, so
a derived truth can never be mistaken for an authored one. _Avoid_: calling it an
opcode, or expecting to edit it.

**Time-carrying** vs **voice-write** (event classes):
The two kinds of thing in a [track](14-audio.md). A **time-carrying** event advances the
clock — notes, ties, rests (the language has two ways to write one), and the
fermata that lengthens the note before it. A **voice-write** sets state and takes
no time at all — instrument, octave, pitch bend, ADSR, reverb, dynamics — and it
applies from where it sits until something changes it. The distinction is the one
that matters when removing an event: deleting a voice-write moves nothing, while
deleting a time-carrying event pulls everything after it earlier. _Avoid_: sorting
events by how they are encoded rather than by which of these they are — the same
concept can be written two ways; grouping the two forms apart hides the only
property an author needs.

**Anchor** (authoring):
The event a new one is placed *after*. Position in a [track](14-audio.md) is a place in
an ordered list, not a moment in time — several voice-writes can share one instant,
so naming a time does not name a place. An anchor alone is still not an address when
the anchor is a multi-segment [span](14-audio.md): a note with a `Fermata` owns **two**
boundaries — one after its head note byte, *inside* the bar, where an opcode fires
once the note's own ticks are up; and one past its last segment, at the span's end
tick. Both are ordinary places FFT writes at (3151 interior opcodes across the corpus,
1534 spans with one immediately past the fermata), and the [fermata](14-audio.md) is drawn
as the bar's amber tail rather than as a chip, so neither boundary can be pointed at —
each has to be named. _Avoid_: a row that says "after `C4`" on a bar whose picture runs
to tick 60 while writing at tick 12; that is an anchor standing in for an address. _Avoid_: saying a voice-write is "attached
to" the note near it; it merely precedes it, and the note can be removed without
disturbing it (see [stub](14-audio.md) for the other case where position, not
ownership, decides what is heard).

**Cut** and **paste** (authoring):
The re-order. There is no move verb in this language and there cannot be a simple one:
placement is an [anchor](14-audio.md) plus a side, so moving an opcode is a delete and an insert
at two different byte boundaries. **Cut** is the delete that *remembers the bytes it
removed*; **paste** is the insert that writes those bytes back — offered on both sides of
the anchor, because "before `Oct3`" and "after `Oct3`" are two different addresses at the
same tick. What the pair buys is the opcode's **own parameters**: the Add menu re-inserts
the corpus mode, so a plain delete-then-add silently reset the value the composer had set.
Offered only on an opcode that can be re-inserted — the flow opcodes cannot, and a cut with
no lawful paste is a trap. _Avoid_: reading cut as a new kind of edit — it lowers to the
delete and insert that were already there, and only the clipboard is new. _Avoid_: offering
it on a [span](14-audio.md): a note is a velocity byte, not an opcode, and its time verbs are
[delete](14-audio.md) and the [paint](14-audio.md).

**Pre-arm** (opcode idiom):
A run of opcodes that **stage voice state before the first audible note** — e.g.
a silent instrument, then ADSR/pitch/portamento/LFO sets — so the note that
follows inherits that state. Deliberate authorship, not leftover; sounds like a
no-op only because nothing is audible *at that instant*.

**Opcode verdict**:
The authoring-honesty classification of a single opcode within a [track](14-audio.md),
one of: **Live** (its effect is heard), **Pre-arm** (staged before the first note —
see above), **Inert** (never observed — a true NOP, or a voice-write on a silent
stub that never sounds), **Structural** (flow/timing — `EndBar`/`Loop`/`Repeat`/
`Rest`, not voice state), **[Muted](14-audio.md)** (a note whose active instrument is
provably silent), **[Live-by-proxy](14-audio.md)** (makes no sound *here* but colours a
shared SPU register). Decided **statically** — by walking the stream and tracking two
per-voice facts, the **running instrument** (last `0xAC`) and whether **noise is
armed** (`0xB4`/`0xB6` on, `0xB7` off) — never from a render. A property of the opcode
*in context*, not of the byte alone. _Avoid_: conflating **Inert** with **Pre-arm**
(pre-arm is load-bearing); calling **Structural** opcodes no-ops; a **position-only**
verdict (it tags a silent track "Live"); a **per-track** muteness (44.3 % of tracks
switch instrument mid-stream, so muteness is per-event).

**Muted** (opcode verdict / note):
A **note** whose **running instrument** (the active `0xAC` at that event) is a
**trusted-empty** instrument, on a voice that is **not noise-armed** — so it provably
produces no sound. Two-level: a whole [track](14-audio.md) in which no `0xAC` ever resolves
to an audible instrument is **wholly Muted**; otherwise only individual notes are.
Only **notes** carry it — a voice-write under a silent instrument keeps its
`Pre-arm`/`Live` verdict, because it may stage state a later audible note inherits.
Rendered as a **45° diagonal hatch** over the chip. _Avoid_: Muting **voice-writes**;
hatching a note whose voice is **noise-armed** (`0xB4`/`0xB6` reroute it off its empty
sample onto the noise generator — audible); hatching a **gray-zone clip** note (faint
but nonzero — not provably silent → a softer "faint" `≈` tell, never a hatch).

**Live-by-proxy** (opcode verdict):
An opcode that produces **no sound in its own [track](14-audio.md)** but writes a **shared,
global SPU register**, so it is heard through **another** voice — confirmed today for
the noise clock (`0xB4 Noise_EnableAndClock`, `0xB5 Noise_ClockAdd`, which set the
single shared `SPUCNT` noise frequency). **Never hatched**, even inside a wholly-Muted
track. Unconfirmed opcodes default to **per-voice** (hatchable); completing the
per-opcode global/per-voice scope tag is deferred RE. _Avoid_: relying on the
[per-track energy](14-audio.md) band to catch a mis-tagged global opcode — the band renders
each track in isolation and is **blind** to cross-track effects.

**Per-track energy**:
The offline-SPU-rendered RMS envelope of **one [track](14-audio.md) rendered in
isolation** (the sibling track silenced), as opposed to the pair's mixed energy.
Normalized against the **pair's** peak so a [silent stub](14-audio.md) reads flat and
the carrying track reads tall. Serves as the empirical ground truth for an
[opcode verdict](14-audio.md): a flat region confirms *Inert*, a swell confirms *Live*.
_Avoid_: obtaining it by splitting the stereo L/R output — that is pan, not the
two voices.

**No-op prune A/B**:
The **active** corroboration of the [opcode verdict](14-audio.md) (the counterpart to the
passive [per-track energy](14-audio.md) band): render the [FEDS pair](14-audio.md) mixed, then
re-render it with **every no-op opcode pruned**, and diff. A no-op is any event the
verdict system tags **[Muted](14-audio.md)** (note → equal-duration `Rest`, preserving the
clock) or **Inert** (zero-tick → deleted); the **instrument** opcode (`0xAC`, running
state) and **Structural**/flow (loops, `EndBar`, `Rest`, `Hold`) are **never pruned**,
and **[Pre-arm](14-audio.md)** stays (it is not a no-op). Measured on the **mixed** render —
never a voice in isolation — so a pruned opcode that perturbs a **shared SPU register**
is caught (isolation is blind to it). Pruned **per track**, so each track's Δ is
attributable. Read from the **raw, un-normalized** envelope against the audibility
constants: Δ `< SILENCE_RMS` = **inert ✓**, `< ABSOLUTE_QUIET` = **faint ≈**, else
**changed ✗** (the classifier over-claimed). A deterministic render makes a genuinely
no-op prune **Δ = 0 exactly**. **Display/QA only** — the pruned bank is transient
(never saved) and the Δ **never** feeds the verdict or hatch. _Avoid_: pruning the
instrument or a `Pre-arm`; measuring in isolation (misses global effects); fitting the
threshold to a desired result (the constants are chosen *before* the render); folding in
the inverted **`Live-by-proxy`** allowlist check (a sibling experiment where green = the
other track *changed*).

#### Game-event SFX chain

**Cue**:
A namespaced string identifier for a *game-event SFX intent* —
`combat.unit_died`, `ui.cursor_move`, `env.battlefield_wind`. Gameplay code
emits cues (or emits an EventBus signal the router subscribes to); it never
names a bank or slot directly. The cue is the stable contract; the
underlying sample can be swapped without touching gameplay.
_Avoid_: hardcoding bank IDs at call sites, or inventing a free-form naming
scheme — every cue must follow `<namespace>.<verb_or_noun>`.

**SfxRouter**:
The autoload that owns the cue registry and dispatches one-shot / ambient
SFX. Two ingress paths: it subscribes to EventBus signals (`unit_died`,
etc.) for game-state changes, and exposes `play_cue(name)` for code that's
allowed to know it's making a sound (UI, environment). The registry maps
each cue to a global-bank sound by **semantic slug** (`{bank, slug}`,
resolved through the **SFX catalog** below) so a cue never carries a magic
slot id; a row may pin a raw `{bank, slot}` for an uncatalogued sound, plus
optional per-row overrides (e.g. `gain`) added only when a specific cue
demands them. It also exposes `play_system(slug)` / `play_env(slug)` for
playing a named bank sound directly. Most cues are **registry-resolved**
— one row, one slug — but a small number are **handler-resolved**: the
cue has no `_CUES` row, and its EventBus handler derives the slug from
the signal payload at dispatch time (e.g. `combat.unit_died` picks
`male_death` / `female_death` / `monster_death` from the dying unit's
`UnitProgression.base_stat_type`). Handler-resolved cues still emit
`cue_requested(cue_name, bank, slot)` with the *cue* name (not the
resolved slug) so the observability contract holds across both shapes.
**The only place gameplay code learns about bank IDs**; everywhere
else uses cue or slug names. **Dispatches through the same FEDS engine
the effects system uses** (`ExMateriaEffectSfx.audition` for one-shots) —
the engine is the shared SPU backend; only the front-end trigger model
differs.
_Avoid_: calling `ExMateriaEffectSfx.audition` directly from gameplay code
instead of registering a cue; adding speculative policy knobs (polyphony,
priority, exclusive) to the registry shape before a real cue needs one —
FFT pan and gain already live in the sample data; building a generic
"variant table" or resolver-Callable into the registry until a *second*
handler-resolved cue exists — the per-event branch in the handler is the
right shape while there's only one (the speculative-knob rule applied to
the cue shape itself).

**SFX catalog** (a.k.a. sound slug):
The hand-authored semantic labels for the two global banks — each bank
**slot** (FFT sound id) gets a stable `slug` and human name
(`0x45` → `female_death` "Female Death"; `0x5B` → `gun_shot_loud_1`).
Lives in `assets/audio/sfx_banks/sfx_bank_names.json`, read at runtime by
`SfxCatalog` (`slot_for` / `name_for` / `is_loop`). It gives the banks
meaning that the ISO-derived blobs can't: the slot→meaning mapping is
**wiki knowledge** (Event Instructions {21} Sound Effect / {6B} Background
Sound; full reference in `research/wiki_articles/event_instructions_sound.md`),
so it is a [Hand-authored data asset](01-asset-extraction.md), not a [committed
extracted artifact](01-asset-extraction.md) — it must not be regenerated from
the `.feds`/`.json` and is maintained by hand.
_Avoid_: putting these names into the extracted `system.json` /
`env.json` (those reproduce from the ISO; the labels do not); referencing
slots by magic id once a slug exists.

**Sound bank** (system / env):
A global FFT SFX [FEDS bank](14-audio.md) loaded from a standalone `feds` blob:
**system** (`SOUND/SYSTEM.SED` → `system.feds`, 167 sounds, the {21} list —
battle hits, menu blips, death cries) and **env** (`SOUND/ENV.SED` →
`env.feds`, the {6B} background list — rain, wind, thunder). The blob + its
decoded `*.json` are ISO-derived ([committed extracted
artifact](01-asset-extraction.md), via `tools/parse_sfx_banks.py`); their slot
names come from the **SFX catalog**, not the blob.
_Avoid_: conflating a **Sound bank** (global, game-event) with a per-effect
`E###/feds.bin` (effect-cast, *triggered* by the effects system). **Both are
`Audio`'s content** — the effect owns the trigger, not the format
([ADR-0124](../adr/0124-effects-tells-audio-a-code-and-a-time.md) dec. 2,
[ADR-0136](../adr/0136-audio-is-one-opcode-language-in-two-containers.md)
dec. 3).

#### Shared lower layer

**FEDS bank**:
A `feds` blob (per-effect `E###/feds.bin`, or global `system.feds` /
`env.feds`) holding a header + per-track byte-offset table + opcode bytes.
Same opcode language as SMD; different header. Exposes `num_pairs`,
`num_tracks` (= `num_pairs * 2`), `track_offsets[]`, `get_track_events(idx)`,
`get_pair_events(pair_idx)`, and the byte-walker variant
`get_track_bytes_from(idx)` for flow-through cases.

**Opcode**:
One byte-coded instruction in a [Track](14-audio.md)'s stream. **One opcode
language, two dispatch tables.** Both name the same PSX jump table
(`smd_opcode_jumptable @ 0x80028B0C`). Effect sound and the SFX banks run
`EffectSoundOpcodeTable` (62 opcodes); SMD music runs `SequencerOpcodeTable` (67 —
the same 62 plus five music-only: `0x97` TimeSignature, `0xA0` Tempo, `0xC3`
AdsrDecayRate, `0xC6` Adsr1LowNibbleSlide, `0xC8` AdsrAttackMode). Of the 62
in common the music table **delegates 32** into `shared/` and **re-implements
30** — so `shared/` is only half shared *as a dispatch table*
([ADR-0136](../adr/0136-audio-is-one-opcode-language-in-two-containers.md)
dec. 1). **As a directory the name is right and the membership is wrong**:
counted by file, 32 of the 84 `.gd` under `shared/` are bound by both tables, 31
by the effect-sound table only, 2 by the music table only, and 19 by neither
(walker, dispatcher, channel/slot state, note handler, LFO helpers, per-tick) —
so 61% of the tree really is common
([ADR-0153](../adr/0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md)
dec. 6, correcting ADR-0136 dec. 7).
_Avoid_: reading "shared" as "every file here is used by both paths" (31 are
not); calling the fix a rename (it is a 33-file move).

**NoteEvent**:
An opcode that emits a note (requests playback). Notes get allocated to SPU
voices at note-on time by the sequencer's voice allocator.

**OpcodeEvent**:
A non-note opcode — tempo, ADSR, LFO, control flow, EndBar, etc. Decoded
alongside NoteEvents by `SMDOpcodes.decode_track`.

**EndBar**:
Opcode `0x90` — the *only* thing that terminates a track. Tracks without
`EndBar` flow byte-walker-style into adjacent tracks (FFT advances byte-by-byte
through RAM without per-track boundaries; documented in
`feds_bank.gd::get_track_bytes_from`).

**Sequencer**:
The runtime that pumps a [Trackset](14-audio.md), dispatches opcodes, and emits
NoteEvents. Lives in the exmateria-sound package. Drives both effect-cast SFX
and SMD music — only the trackset source differs.

**SPU voice**:
PSX hardware voice — there are 24 on the chip. **Allocated** to NoteEvents
by the voice allocator at note-on time; voices are not bound 1:1 to tracks
or pairs. A pair's two tracks emit notes that compete for voices like any
other source.
_Avoid_: calling a [Track](14-audio.md) a "voice" — tracks are streams of
opcodes; voices are hardware. They have a many-to-many relationship
(notes from any track may take any voice).

**WAVESET**:
The ADPCM sample bank that voices reference. Shared between music and
effect SFX (one set, sampled differently). Loaded once at boot.

#### Extraction #2 translation table (`Audio`)

Loop pass 4 of extraction #2 ([ADR-0153](../adr/0153-audio-extracts-into-a-package-the-walk-reports-rather-than-enters.md)).
Old term → new, kept for a reader who knows the old vocabulary. Rows marked
**(predicted)** describe the seam as designed at loop pass 3; loop pass 6 builds
them and loop pass 9 checks them, so read them as a plan until then.

| you may have read | say now | why |
|---|---|---|
| *`shared/` is the effect-sound dispatcher's tree* | **`shared/` is the common tree with an effect-sound tree inlined into it** | ADR-0153 dec. 6, correcting ADR-0136 dec. 7 by measurement. 51 of 84 files belong under a name that means shared |
| *rename `shared/`* | **move 33 files out of it, renaming all 33** — 31 effect-sound-only handlers to `runtime/effect_sound/opcodes/` as `EffectSoundOp*`, 2 music-only (`tempo.gd`, `time_signature.gd`) to `runtime/sequencer/opcodes/` as `SequencerOpTempo` / `SequencerOpTimeSignature` | the 32/31/2 split reproduces exactly on `preload(` lines. `runtime/effect_sound/opcodes/` does **not** exist yet (ADR-0153 dec. 6's amendment corrects it; only the music destination does), and the tree's `<Tree>Op<Name>` convention makes the move 33 `class_name` renames, not zero. **(predicted)** |
| *`Audio` subscribes to `Effects`' sound channel* | **`Effects` calls `Audio`'s driver** — `Audio` → `Effects` is zero lines, `Effects` → `Audio` is 24 | ADR-0153's audit, ADR-0126 check 2. `BLUEPRINT.md` §7 and its *Subscription, not calls* paragraph are both amended. Retiring the call is `Effects`' pass, via ADR-0124's channel |
| *`Audio` is four autoloads in the host* | **`Audio` is one driver, one bus adapter and four host-side facades** | `ExMateriaEffectSfx` is the driver and moves; `SfxRouter`, `MusicPlayer`, `SfxCatalog`, `AttackSfxResolver` are game glue and stay; `ExMateriaAudioEngine` splits — the addon owns the SPUs, the host owns the Godot Master bus. **(predicted)** |
| *`Audio`'s seam is `Tune` / `UserSettings` / `DebugConfig`* | **it is 17 lines across six symbols** — those three plus `TuneField`/`BaseDebugPanel`, `JsonAsset` and `EventBus` | four of the six land in `other` buckets that ADR-0131 dec. 2 excludes from the reach count, so they are invisible in the cross-system column. A system's portability seam is not its cross-system column |
| *`ExMateriaEffectSfx` reads `DebugConfig`* | **the driver owns its own gate**, a `static var` on a slug in its own namespace | ADR-0140 dec. 5 — a system logs itself. `Audio` has exactly one gate, `audio_monitor_enabled`, and it moved with its slug: `debug.audio_monitor_enabled` → `audio.monitor_enabled`, because the old namespace was `Debug`'s. **BUILT** #408 |
| *the panel `extends BaseDebugPanel`* | **an addon panel is a plain `PanelContainer`** the system ships, satisfying `DebugOverlay.register_panel`'s duck-typed signature (untyped `panel`; it touches only `set("panel_category")` / `get("panel_title")`, and `DebugDashboard` guards every lifecycle call with `has_method`) | ADR-0140 dec. 8; the rule and its guard are ADR-0151's. Membership in the addon was never the defect — inheritance was. A **host** panel may keep inheriting: the rule binds files under an addon root |
| *the addon publishes `tunables()` and the host binds it* | **that is the inbound half only** — a declaration cannot WRITE. The package also needs an outbound **write port**: `static var tunable_writer: Callable`, filled by the host adapter, no-op when unfilled | ADR-0153 dec. 3's amendment. The panel's preset buttons scrubbed the slug through `Tune.set_value`; with `Tune` gone they had nothing to call. An inverted dependency needs both halves, and only the inbound one is obvious. **BUILT** #408 |
| *the host adapter walks declared panels* | **it MOUNTS them by name** — a `for script in PANELS: script.new()` loop makes the panel invisible to `check_debug_panel_tunables.py` | ADR-0151 dec. 6's widened marker reads identity off `var X = ClassName.new(` + `register_panel(X`; a loop variable satisfies neither. The guard went green because it stopped looking — ADR-0148's defect a third time. **BUILT** #408 |
| *a system's portability seam is what goal #5's guard forbids* | **they are two different sets, and the seam is the stricter** | `check_addon_portability.py` scans for symbols the classifier books to a **system**; `Tune`, `UserSettings` and `JsonAsset` are `platform`/`infrastructure` and never appear. Measured over the moving set: the seam is 17 lines, the guard sees **5**, and after #408 it sees 0 |
| *`SpuAudioDebugPanel` is one panel* | **it is two, and it splits where `ExMateriaAudioEngine` splits** — the click de-click knob, presets and live readout are the driver's (≈113 lines, addon); the whole-game **volume slider** drives the Master bus and stays host (≈33) | ADR-0153 dec. 2/4. Its live readout reaches `ExMateriaEffectSfx._click_units[0]["mixer"]`, addon-private; its slider reaches `ExMateriaAudioEngine.get/set_master_volume`, host. A view splits where its subject splits. **(predicted)** |
| *a debug panel un-inherits* | **first ask whether it is bespoke or only `TuneField` rows** — a purely declarative panel is DELETED, not un-inherited (ADR-0068 dec. 9: the registry generates those) | exactly **1 of `SpuAudioDebugPanel`'s 146 lines** is a `TuneField` row, so it is bespoke and un-inherits. `Render`'s two were pure declaration and the right answer there was delete |
| *`addons/exmateria_sound/` is where the addon lives* | **`exmateria-sound/addons/exmateria_sound/` is where it lives**; the host path is a gitignored deployment target | `.gitignore:3`, written by `tools/sync_exmateria_sound.sh`. ADR-0153 dec. 1 and dec. 7 |
| *`EffectSfxEngine.gd` lives in `src/audio/`* | **`exmateria-sound/addons/exmateria_sound/runtime/effect_sfx_engine.gd`** — with `bus_limiter.gd`, `audio_engine.gd` and `debug/spu_audio_debug_panel.gd` | the lift, #410. Renamed to the package's snake_case convention, as #406/#407 did. the autoload names were unchanged by the lift; only the paths moved. (They are `ExMateriaAudioEngine` / `ExMateriaEffectSfx` since `#383`; `#410` left them as `AudioEngine` / `EffectSfxEngine`.) **BUILT** |
| *inverting a dependency removes it from the census* | **it RELOCATES it into the adapter, which is booked to the same system** | `Audio → Debug` was predicted to fall 5 → 1 and fell 5 → **4**: `AudioHostAdapter.gd` is `src/audio/`, so its `DebugOverlay` ×2 and `TuneField` ×1 are fresh `Audio → Debug` lines. Goal #5's guard (what is inside the ADDON: 0) and the cross-system column (what the SYSTEM couples to, residue included) measure different things |
| *the UNCOUNTED register catches what leaves the walk* | **it catches what names an addon PATH**, which was 1 of the 24 edges the lift removed | 23 of the 24 named `ExMateriaEffectSfx.` / `ExMateriaAudioEngine.` as AUTOLOADS (`EffectStudioPage` 12, `EffectInstance` 11) and are now recorded nowhere. A compensating register only compensates for the shape it counts (#405, ADR-0148 dec. 1) |
| *the walk follows the refactor's output* | **it follows it inside the host package, and REPORTS it across a package boundary** | ADR-0153 dec. 1. Extraction #1's precedent narrowed, not extended; `WALK_ROOTS` gains no line at extraction #2 |
| *`play_pair(token, bank, pair_idx, sound_id)`* | unchanged, and it carries **two off-by-one conventions and a parsed `Audio` format object** | ADR-0126 check 4. `pair_idx = sound_id - 1` is done by the caller on both sides of the boundary; a third `+1` rule governs WAVESET indexing. ADR-0124 specified "a code and a time" |
| *`SMDOpcodes` names the SMD container* | **it is the shared VM's decoder and event vocabulary, and it becomes `SoundOpcodes`** in `runtime/sound_opcodes.gd` — 69 files under `shared/` + `effect_sound/` name it, 80 of the 83 references are `OpcodeEvent`/`NoteEvent`, and `feds_bank.gd` decodes through it. The host binds it by **preload path, not the global name** (`FedsOpcodeCatalog.gd` aliases it `SMD`), so the host cost is the file rename on 2 preload lines | ADR-0153 dec. 10, correcting ADR-0136 dec. 4 to two kept symbols, not three. `SMDParser`/`SMDPlayer`/`SMDFile` do genuinely name the container and stay. **(predicted)** |
| *`waveset` / `SMDParser` are jargon goal #7 purges* | **they are a MEMBERSHIP question, not a rename** — a ROM container's name in a portable addon asks whether the container codec belongs there at all | ADR-0150 as amended: a #7 count is a work list; every hit sorts to rename / membership / exempt. `Audio` takes no exempt (ADR-0117 row 7 is *"the sound driver"*, a job). The membership half is map #373's tier per #392 |
| *`smd_interpreter_*` names our jargon* | **they are RE citations** — PCSX-side routine names carried so the Godot trace and the emulator's diff row-for-row | `probe_emit.gd:41`. Renaming them breaks the parity diff. Same class as `fft-ghidra`'s address-citation rule |
| *`capture_mode` selects the offline engine* | **it does two things**: it discriminates a dedicated off-tree capture instance *and* parks the live autoload's producer | ADR-0153's audit. The demux above already exists (`init_as_capture` on a bare `.new()`); the second use defeats it. Recorded as a soft spot on the file pass 6 moves |

_Avoid_: quoting `Audio` at 2,671 or 2,034 lines (it is 13 files / 2,834 at
`78ab1fcd6`, of which five declined-scene harnesses are 637, so **8 / 2,197**
live); reading extraction #2's predicted 24-line fall in the cross-system total
as retired coupling (the targets leave the walk, the calls do not); calling
`exmateria_spu` a separate addon (the refactor models `Audio` as one system →
one addon; the two-addon split is map #373's).
