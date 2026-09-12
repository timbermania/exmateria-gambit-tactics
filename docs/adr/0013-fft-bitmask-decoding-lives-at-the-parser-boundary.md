# FFT bit-packed data decodes at the parser boundary into semantic structure

## Status

Accepted (2026-06-03). Amended 2026-07-04 (twice) — reconciled the two
never-landed deferrals (`anim_flags` / `rsm_flags` in `effects.json`). Both stay
raw `int` and a guard locks that state, but for different reasons: `anim_flags`
is deferred **pending reverse-engineering of the bit semantics** (not merely
label-sourcing); `rsm_flags` was subsequently RE'd and **renamed
`rsm_other_id`** — it is a passive-effect routine index, not flags, so raw `int`
is its faithful final shape (not a placeholder). Corrected the factual errors —
see "Deferred / resolved-raw sub-fields". The core decode-at-parse discipline
for the understood fields (elements, statuses, `weapon_flags`, `equipment_flags`,
`slot_flags`, `inflict_statuses`) is unchanged.

## Context (before this decision)

FFT encodes a great deal of per-job, per-item, per-ability, and per-effect
data as **bit-packed integers and MSB-first byte arrays**. The MSB-first
convention is FFTPatcher's, observable in
`PatcherLib.Utilities.ByteFromBooleans(msb, six, five, four, three, two,
one, lsb)` — the first parameter goes to bit 7. So `Fire = 0x80`
(`ElementFlags.cs`); `weapon_flags` packs `Striking` at bit 7 and
`Force2Hands` at bit 0; `equipment_flags` packs `Unused` at bit 7 of
byte 0 and `Rod` at bit 0. Two distinct semantic shapes recur:

- **Independent boolean properties** packed into one byte/word — each bit
  is a named, disjoint property. `slot_flags` (which slots an item fills),
  `weapon_flags` (`striking` / `lunging` / `direct` / `arc` / …),
  `equipment_flags` (which equipment categories a job can wear),
  `anim_flags` (an effect-animation flag byte; **its bit meanings are
  unknown** — see the corrected "Deferred sub-fields" note below, which
  retracts the original "bit 1 is `FLAG_PROJECTILE_TRIGGER`" claim as a
  name-collision with an unrelated runtime GPU field).
- **Set membership** packed into a byte (or several) — each bit asserts
  membership of a named element/status in the field's set. Element
  affinity (`absorb`, `cancel`, `half`, `weak`), the 40-status immunity
  table (`status_immunity`), the status-inflict field (`inflict_status`).

Today the codebase decodes only some of these. `tools/extract_items.py`
**already** demonstrates both target shapes: `slot_flags` and
`weapon_flags` come out as named-bool dicts (`{striking: bool, lunging:
bool, …}`); element affinity comes out as name arrays (`absorb_elements:
["Fire", "Holy"]`). The decoders + label tables (`ELEMENTS`,
`decode_elements`) live inline in the parser. So the precedent for the
discipline is established within items themselves.

The remaining bit-packed gaps are:

| File | Field | Today | Target shape |
| --- | --- | --- | --- |
| `items.json` | `status_immunity` | `[5 raw bytes]` | name array |
| `jobs.json` | `absorb_element`/`cancel_element`/`half_element`/`weak_element` | `int` bitmask | name array |
| `jobs.json` | `status_immunity` | `[5 raw bytes]` | name array |
| `jobs.json` | `equipment_flags` | `int` | named-bool dict |
| `assets/abilities/effects.json` | `anim_flags` | `int` | *deferred — stays raw `int` (bits not RE'd)* |
| `assets/abilities/effects.json` | `rsm_flags` → `rsm_other_id` | `int` | *stays raw `int` — RE'd as a routine index, not flags* |
| `assets/abilities/effects.json` | `inflict_status` | `int` | name array |

`src/scenes/ProgressionTester.gd` is the only runtime decoder for any
of these; it re-implements the bit-loop, carries its own
`ELEMENT_NAMES` and `STATUS_NAMES_BYTE0..4`, and uses the MSB-first byte
convention CLAUDE.md flags as a known trap. `src/gpu/GPUConstants.gd`
also names `anim_flags` bit 1 (`FLAG_PROJECTILE_TRIGGER = 2`) — runtime
code that knows a bit position.

The sibling cluster — `SfxCatalog` + `assets/audio/sfx_banks/sfx_bank_names.json`
— does the opposite (wiki labels in a hand-edited runtime JSON resolved
by a small catalog class) because its underlying `.feds` blob is large
byte-reproducible binary that can't carry inline labels. Flat-JSON
committed artifacts have no such constraint, and the items parser has
demonstrated for years that decoded structure round-trips cleanly
through git.

## Decision

**FFT bit-packed data decodes at the parser boundary into semantic
structure.** Specifically:

1. **Two target shapes, chosen by the meaning of the bits — not by
   stylistic preference.**
   - *Named-bool dict* when the bits are independent boolean properties
     (`{striking: false, lunging: true, …}`). Used for: `slot_flags`,
     `weapon_flags` (existing), and now `equipment_flags`, `anim_flags`,
     `rsm_flags`.
   - *Name array* when the bits are set membership
     (`["Fire", "Holy"]`). Used for: `absorb_elements`, `cancel_elements`,
     `half_elements`, `weak_elements`, `strengthen_elements` (existing
     in items), and now the same four element fields on jobs, plus
     `status_immunity` (jobs + items) and `inflict_status` (effects).
2. **Committed extracted artifacts carry the decoded form; runtime code
   never sees a bitmask.** Schema changes per file are listed under
   *Consequences* below.
3. **The shared label tables + bit-loop helpers live in one module:
   `tools/_fft_decode.py`.** It exports the label tables (`ELEMENTS`,
   `STATUS_NAMES_BYTE0..4`, `EQUIPMENT_FLAG_NAMES`, `WEAPON_FLAG_NAMES`,
   `SLOT_FLAG_NAMES`, `ANIM_FLAG_NAMES`, `RSM_FLAG_NAMES`) and the two
   bit-loop primitives (`decode_set(byte_or_bytes, names) -> [names]`,
   `decode_flags(int, names) -> {name: bool}`). Every parser
   (`extract_items.py`, `extract_fft_data.py`, the abilities/effects
   parser path) imports from it; the wiki labels live in exactly one
   place.
4. **The MSB-first byte convention lives only in the parser.** The
   bit-loop primitive in `_fft_decode.py` is the single owner. No
   runtime code carries the convention; CLAUDE.md's "Wrong bit order"
   pitfall narrows to parser authors.
5. **The principle covers any future bit-packed field, by the same
   rule.** A new flag word added by a new parser (weapon attack type,
   action flags, ability category masks) decodes at the parser. The
   choice between named-bool dict and name array follows the meaning
   of the bits.

## Considered options

- **Decode-at-parse with two semantic shapes (chosen).** Mirrors what
  `extract_items.py` already does for `slot_flags` / `weapon_flags` /
  `elements`. Unifies the wiki labels into one importable Python
  module. Halts CLAUDE.md's MSB-first bit-order trap at the parser
  boundary — runtime never sees it again. The two shapes are not a
  stylistic split; they follow what the bits *mean* (property vs.
  set), so a reader picks the right one by inspecting the field's
  semantics, not by convention.
- **One uniform shape for everything (either all dicts or all arrays).**
  Rejected: forcing `absorb_elements` into a dict
  (`{Fire: false, Lightning: false, …}` per ability) or forcing
  `weapon_flags` into an array (`["striking", "throwable"]`) loses
  meaning. Element affinity *is* a set; `weapon_flags` *is* a set of
  named properties. The codebase already proves both shapes coexist
  cleanly (items.json carries both).
- **Runtime catalog mirroring `SfxCatalog`.** Keep all the committed
  JSON raw; add hand-edited label JSON files; resolve at runtime via
  catalog classes. Rejected — the SfxCatalog precedent exists *because*
  its underlying blob is byte-reproducible binary. Flat-JSON artifacts
  have no such constraint, and the parser already has the only place
  in the system that *has* the raw bits in the first place. Adding a
  runtime catalog buys nothing the parser cannot do, and disperses the
  bit-position knowledge across two languages.
- **Keep both raw and decoded forms side-by-side** (the `effects.json`
  `elements_raw` precedent, which keeps the int alongside the decoded
  `elements` array). Rejected as a *target*: a parallel raw form invites
  runtime code to reach for the bitmask, defeating the locality. (The
  one existing `elements_raw` in effects.json is a minor smell to clean
  up; see *Consequences*.)
- **Scope-limit to elements/status; chase `equipment_flags` and
  `anim_flags` / `rsm_flags` / `inflict_status` separately.**
  Rejected: the principle is one principle, and the shared
  `tools/_fft_decode.py` is the natural home for *all* the label
  tables, not a subset. Splitting the work would import the same module
  twice, with the second author re-deriving the discipline.
- **A third shape — enum-style fields (one bit-position selects one
  value-of-N).** No such field is in scope today; if one appears, the
  ADR is extended then. Not pre-modelled.

## Consequences

- **Per-artifact schema changes** (per the rule above):
  - `assets/jobs/jobs.json`
    - `absorb_element: <int>` → `absorb_elements: ["Fire", …]`
      (and likewise `cancel_elements` / `half_elements` /
      `weak_elements`).
    - `status_immunity: [5 raw bytes]` → `status_immunity: ["Petrify",
      "Sleep", …]`.
    - `equipment_flags: <int>` → `equipment_flags: {knife: bool,
      sword: bool, … }` (label names from FFTPatcher convention, sourced
      in `_fft_decode.py`).
  - `assets/items/items.json`
    - `status_immunity: [5 raw bytes]` → `status_immunity: ["Petrify",
      …]` (closes the same gap items left open while decoding elements
      and flags).
  - `assets/abilities/effects.json`
    - `anim_flags` / `rsm_other_id` (the latter renamed from `rsm_flags`) —
      **NOT landed as named-bool dicts**, for two *different* reasons. `anim_flags`
      is deferred: its bit semantics are not RE'd (nothing to name the keys), and
      the original aspiration (`anim_flags: {projectile_trigger: bool, …}`,
      "replaces `GPUConstants.FLAG_PROJECTILE_TRIGGER` with a typed read") was
      wrong — that mask names an unrelated same-named *runtime* GPU field, not
      this ROM byte. `rsm_other_id` is *resolved*: RE'd 2026-07-04 as a
      passive-effect routine index (FFTPatcher `OtherID`), not flags — raw `int`
      is its final shape. Both stay raw `int`. See "Deferred / resolved-raw
      sub-fields" below for the reasoning + guard.
    - `inflict_status: <int>` → `inflict_status: ["Sleep", "Don't Act",
      …]`.
    - `elements_raw: <int>` (the existing "kept alongside" smell) is
      *removed*; `elements: [names]` stays as the sole form.
- **Schema breaks are contained, even widened.** Runtime callers of the
  raw forms today: `src/scenes/ProgressionTester.gd` (jobs elements +
  status), `src/data/ItemDatabase.gd:287` (items.status_immunity),
  `src/gpu/GPUBatchSimulator.gd` and `src/gpu/GPUConstants.gd`
  (anim_flags bit reads). Each is one read site — one commit per
  artifact catches them.
- **CLAUDE.md's "Wrong bit order when parsing binary flags" pitfall
  narrows to parser authors.** It stays in CLAUDE.md as a warning to
  whoever edits `_fft_decode.py`, but runtime authors no longer need to
  know the MSB-first convention or any specific bit position. The
  convention now exists in exactly one file.
- **`tools/_fft_decode.py` is the home for any future bit-packed FFT
  field.** Adding a new flag word means adding the label table and one
  parser call site; the runtime sees decoded structure on the next
  bootstrap.
- **Locality of all the wiki-label data.** Element names, status names,
  weapon-flag names, slot-flag names, equipment-flag names,
  anim-flag/rsm-flag names — every hand-authored wiki label about
  FFT bit conventions sits in one Python module that no runtime imports.
- **Tests are unaffected by the parser change.** The GPU combat tests
  that author `weapon_flags: 1` as an int (`tests/Gpu*Test.gd`)
  continue to write that shape — those values come from in-test
  dictionaries, not the committed JSON, and the in-shader interpretation
  is `weapon_flags & 0x… `. The runtime decoded form is for *display*
  and *gameplay-config* code (e.g. JobDatabase reads), not for the
  packed GPU buffer, which keeps its own integer layout per ADR-0001
  /0003. (If the GPU side ever wants typed reads, that's a separate
  decoding step at the encode boundary, not a parser change.)
- **Not part of `bootstrap_assets.sh`.** The change is in the extractor
  source and the artifact shape it emits — running the extractors
  re-emits the new shapes; no separate step.
- **ADR-0001 (top-level) is the umbrella.** It names the *idempotency*
  and *host-agnostic* properties of ISO-derived assets; this ADR names
  the *decoded-at-parse* discipline and the *two semantic shapes*
  that follow.
- **`AbilityView` / `AbilityData` (ADR-0008) are unaffected as types.**
  Their schemas widen if `effects.json` adds/renames fields; the
  `generate_ability_database.py` regeneration picks up the new shapes
  automatically.

## Implementation status

Landed in three phases (2026-06-03):

- **Phase A** — `jobs.json` element + status decoding via
  `tools/_fft_decode.py` (`ELEMENTS`, `STATUS_NAMES_BY_BYTE`,
  `decode_set_msb`, `decode_set_msb_bytes`). `ProgressionTester` drops
  ~80 LoC of inline decoders.
- **Phase B** — `items.json` `status_immunity`/`permanent_statuses`/
  `starting_statuses` join the decoded-name shape; `ItemDatabase.gd`
  drops its duplicate `_decode_status_bytes` + `STATUS_NAMES`.
- **Phase C** — `equipment_flags` (jobs) decoded named-bool via
  `decode_flags_msb_multi_byte` (PSX 32-bit, `EQUIPMENT_FLAG_NAMES`
  from FFTPatcher `Job/Equipment.cs` `psxNames`); `effects.json`
  `elements_raw` removed (no consumers); `AbilityDatabase.gd` +
  `AbilityView.gd` regenerated.

**Two latent decoder bugs fixed during Phase C.** Both reflect-by-bit
inversions caused by reading FFTPatcher conventions wrong:

1. **Element / equipment / weapon / slot flag fields**: `extract_items.py`
   and the initial Phase A draft of `jobs.json` used `decode_*_lsb`
   against name lists authored MSB-first (`[Fire, …, Dark]`). FFT's
   convention is MSB-first per byte — verified against
   `FFTPatcher.PatcherLib.Utilities.ByteFromBooleans(msb, six, five,
   four, three, two, one, lsb)` (first param = bit 7) and
   `Datatypes/Elements.cs` (`ElementFlags.Fire = 0x80`). Result before
   fix: every element and flag emitted by `extract_items.py` was the
   reflection-by-bit of the truth — "Flame Rod" carried element `Dark`,
   "Ice Brand" carried `Water`, `weapon_flags.striking` was actually
   `Force2Hands`, Knight's `equipment_flags` showed `Rod`. The
   `decode_*_msb` family in `tools/_fft_decode.py` is now the only API.

2. **Status names** (`status_immunity`, `permanent_statuses`,
   `starting_statuses`): both `STATUS_NAMES_BY_BYTE` in `_fft_decode.py`
   (copied from `ProgressionTester.gd`) and the now-deleted
   `ItemDatabase.STATUS_NAMES` had their byte-internal name lists in
   the wrong order vs FFTPatcher `Datatypes/Status/Statuses.cs:187`'s
   `ByteFromBooleans(NoEffect, Crystal, Dead, Undead, Charging, Jump,
   Defending, Performing)`. With FFTPatcher-correct ordering, Angel
   Ring's `starting_statuses` now decodes to `["Reraise"]` (was
   `["Chicken"]` under the prior wrong table); Reflect Ring's
   `permanent_statuses` decodes to `["Reflect"]`; Setiemson's to
   `["Haste"]` + `Transparent` starting. The name lists themselves
   now use FFTPatcher's **C# field identifiers verbatim**
   (`NoEffect`, `BloodSuck`, `DarkEvilLooking`, `DontMove`, `DontAct`,
   `DeathSentence`); display strings ("Don't Move", "Death Sentence",
   "Cursed" for `DarkEvilLooking`, etc.) are a downstream presentation
   concern and live alongside the data, not in the parser source. The
   `---` placeholder skip in `decode_set_msb_bytes` is removed because
   FFTPatcher names every slot — byte 0 MSB is the real ROM slot
   `NoEffect`, not a placeholder to elide.

CLAUDE.md's "Wrong bit order" pitfall note has been corrected to
MSB-first (it previously asserted LSB-first with an example that
contradicted FFTPatcher). FFTPatcher's C# source is the authority over
its XML resource files for both name-strings and bit-positions —
verified during this fix when the XML's display strings (e.g.
"Dark/Evil Looking") and the source's identifiers (`DarkEvilLooking`)
matched on bit positions but differed on presentation.

**Deferred / resolved-raw sub-fields (raw `int`, not label-sourcing).**
Amended 2026-07-04 — the original framing below was wrong about *why* these
were deferred, and about the fields themselves. `anim_flags` remains deferred
(bits not RE'd); `rsm_other_id` is now *resolved* (RE'd as a routine index, not
flags). Corrected:

- `assets/abilities/effects.json` `anim_flags` — **one byte** (8 bits), the
  3rd byte of each ability's 3-byte animation record (`parse_abilities.py`
  `parse_ability_animation`: `[charging_pose_id, effect_anim_id, flags]`; the
  first two are already decoded into named fields). *Not* "24 bits across 3
  bytes" — that was a miscount conflating the whole record with its flag byte.
  Data looks real (463/512 are `0`; the rest are clustered bit patterns).
- `rsm_other_id` (was `rsm_flags`) — **RE COMPLETE 2026-07-04; renamed.** One
  byte per R/S/M ability from the table at RAM `0x8006105C`. The extracted
  values are `0,1,2,…,87` sequential — and that is *correct, by-design* data,
  **not** a mis-addressed read. The byte is the ability's passive-effect
  *routine index*, named `OtherID` in FFTPatcher (`Ability.cs`) and `ID` in the
  FFHacktics disassembly. Multi-source verification this session:
  - **SCUS bytes** — the sub-tables are contiguous inline data, not a pointer
    block: Item `0x…1010` → Throw `…1020` → Jump `…102C` → Charge `…1044` →
    Math `…1054` (8 B) → **RSM `…105C`**. Each neighbor reads as real clustered
    data (item IDs, jump/charge pairs, Math bitmasks); the tables butt directly
    against each other, so `0x8006105C` is the correct contiguous RSM location.
  - **FFTPatcher C#** — `AllAbilities.cs` slices one inline byte at blob
    `0x246C` (= `0x8005EBF0 + 0x246C = 0x8006105C`) into `Ability.OtherID`, an
    opaque hex byte with **no bit-field decode**. Decoding FFTPatcher's own
    stock `Abilities.bin` reproduces `0,1,2,…,87` exactly.
  - **Meaning** — vanilla assigns the indices sequentially (Reaction 0–31,
    Support 32–63, Movement 64–87), so the value is redundant with the
    ability's ordinal. R/S/M passive behavior is hardcoded in BATTLE.BIN, keyed
    by this index; there are no data-driven flag bits to decode. An `int`
    routine-id is therefore the *faithful final representation*, not a
    placeholder. It stays raw and out of `INCLUDED_FIELDS` because a routine
    index has no gameplay/display consumer — not because RE is pending.
  - *Lead RESOLVED (2026-07-04):* the `AbilityEffects` table FFTPatcher cites at
    PSX RAM `0x1B63F0` is **the same table `parse_abilities.py` already reads** at
    BATTLE.BIN file offset `0x14F3F0` — `0x14F3F0 + 0x67000` (BATTLE overlay→RAM
    delta) `= 0x1B63F0` (`PsxIso.AbilityEffects = KnownPosition(BATTLE_BIN,
    0x14F3F0, 0x38C)`; loader `lui 0x801b`/`lh 0x63f0`). Not a distinct table. It
    covers offsets `0x000..0x1C5` (Normal…Reaction, 454 entries); Support/Movement
    have none. Each entry is a raw little-endian u16 graphic Effect index (`0xFFFF`
    = none) → stays a raw `int` in `effect_id` like `rsm_other_id`. 14/32 Reactions
    carry a real index (Regenerator→E008, DamageSplit→E341…); counter-type ones
    (Counter, Blade Grasp, Hamedo…) are genuine `0xFFFF` — they reuse the
    weapon-attack animation. Fixing the read exposed two FFTPatcher-documented
    decode bugs (0x0800 Item/Throw prefix mask; the 512→454 over-read) — see the
    parser and its commit.
- **`anim_flags`'s blocker is that its bit *semantics* are not
  reverse-engineered** — FFTPatcher's `Animation` class names them only
  generically (`Bool1..Bool24`). This is a *different* deferral from
  `weapon_flags`/elements, whose meanings FFTPatcher *does* name (there the
  only work was wiring a table). There is nothing faithful to decode it
  *into* yet, so it stays raw `int` — a faithful extraction of **unimplemented
  ROM data**, not a smell. It decodes when an RE session learns the bits;
  raw is the honest representation until then. (`rsm_other_id` above is *not*
  in this bucket — its RE is done; it is raw because it is an index, not flags.)
- **Name-collision warning.** The `FLAG_PROJECTILE_TRIGGER = 2` /
  "`anim_flags` bit 1" seed in `src/gpu/GPUConstants.gd` is **not** a label for
  this ROM byte. It masks an *unrelated, same-named* per-unit GPU runtime field
  `U_ANIM_FLAGS` — scratch state the compute shader writes at runtime
  (`stage_compute.glsl`: bit 0 = damage-triggered, bit 1 = projectile-triggered
  animation latches, zeroed at spawn, surfaced via `SNAPSHOT_FIELDS`). The ROM
  `effects.json.anim_flags` byte never flows into it (`GPUAbilityLoader` does
  not read it; it is absent from `INCLUDED_FIELDS` so it never reaches
  `AbilityView`). Do not seed an `ANIM_FLAG_NAMES` table from that bit.
- **Consumer status: zero, and that is fine.** Neither field is read by any
  runtime code (not the GPU encode path, not display/gameplay). A guard
  (`tools/check_adr0013_deferred_flags.py`, wired into `run_all_tests.sh`)
  locks both as raw `int` in effects.json and out of `INCLUDED_FIELDS`. For
  `anim_flags`, that failing on decode is the reminder to amend this ADR + the
  guard together when the bits are RE'd. For `rsm_other_id` the guard is now a
  *stability* lock (its RE is done — an index has no reason to become a dict or
  to reach `AbilityView`).
- `inflict_status` — **resolved** (was deferred as a foreign key into a
  separate inflict-status table). Now extracted as `inflict_statuses` (decoded
  name array) + `inflict_mode`, both in `INCLUDED_FIELDS`.
- The GPU-side `weapon_flags` audit landed **resolved-no-fix**.
  `GPUCombatPacker._extract_unit_config` re-packs `prog.
  get_weapon_flags()` (the now-correct semantic dict) into its own
  internal protocol where bit 0 = `striking`, bit 1 = `lunging`, etc.
  The shader (`combat_combat.glslinc:22`) reads the same protocol. So
  GPU `WEAPON_FLAGS` is a **distinct encoding** from the ROM
  `weapon_flags` byte — they share a name and a set of values, but
  bit-position layouts are independent (the CPU encoder is the
  translation layer). The encoder pulls semantic names from the dict,
  so it doesn't matter that the ROM convention is MSB-first and the
  GPU convention is LSB-first; the semantics round-trip correctly.
  Test fixtures using `"weapon_flags": 1` with `# STRIKING` are
  authoring the GPU integer directly and are also correct under this
  protocol. The comment at `GPUBatchSimulator.gd:124` now flags that
  this is the GPU-internal packing, not the ROM byte.
