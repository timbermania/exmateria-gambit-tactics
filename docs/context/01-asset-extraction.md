# Asset extraction

How ROM-derived game content gets from the FFT PSX disc into a runnable
Godot project, and the vocabulary that distinguishes source from output.

**ISO extract** (a.k.a. `fft-extract`):
The raw PSX disc contents extracted from a Final Fantasy Tactics ISO,
living under `project-assets/fft-extract/` (gitignored, local-only). The
upstream source for every other asset. The ISO file itself may be named
differently per machine; the extracted tree must not.
_Avoid_: ROM dump, game files.

**ISO-derived asset**:
Any file produced *purely* by running an extractor/parser over the ISO
extract — no hand-editing afterward. Reproducible: the same script over
the same disc yields byte-identical output (after host-specific noise is
removed). If a committed artifact does not reproduce, that is a bug to
fix, not a reason to hand-maintain it.
_Avoid_: generated file (too vague — distinguish tracked vs ignored below).

**Regenerable bulk**:
ISO-derived assets that are **gitignored** and rebuilt locally on every
checkout — sprite textures, animations, maps, most effects, fonts, sound
samples. Never a git-parity concern; each machine just rebuilds them.

**Committed extracted artifact**:
ISO-derived assets that are **git-tracked** — `abilities.json`,
`skill_sets.json`, `jobs.json`, `items.json`, `projectile_models.json`,
`effects/trap/`, `sfx_banks/`. Tracked for convenience, but still
pure-derived: they must reproduce from the ISO + extractor, and must not
embed host-specific data (e.g. absolute source paths). The extractor
source itself may carry hand-authored constants the ROM bytes can't name
(`ELEMENTS = [...]`, `STATUS_NAMES_BYTE0..4`, `EQUIPMENT_FLAG_NAMES`,
`WEAPON_FLAG_NAMES`, …); those are *part of the extractor*, so
reproduction is from {ISO bytes + extractor source}. **FFT bit-packed
data decodes at this boundary** into one of the two shapes below
(named-bool dict or name array); runtime code never carries the bit
conventions. See ADR-0013.
_Avoid_: a runtime `ELEMENT_NAMES` / `STATUS_NAMES_*` const + `_decode_*`
helper paired with raw-bitmask fields in the committed JSON — they will
drift from the parser. The contrast with the **SFX catalog** below is
deliberate: sound-bank labels live separately because the `.feds` blobs
are byte-reproducible binary that can't carry inline names; flat JSON
artifacts can and should.

**Bit-packed field, named-bool form**:
A committed-artifact field where each bit is an *independent boolean
property* — decoded by the extractor into a named-bool dict, never
emitted raw. `weapon_flags: {striking: bool, lunging: bool, direct: bool,
arc: bool, two_swords: bool, two_hands: bool, throwable: bool,
force_two_hands: bool}` and `slot_flags: {weapon: bool, shield: bool,
head: bool, body: bool, accessory: bool, …}` are the canonical examples
already in `items.json`; `equipment_flags` (jobs) also lands this shape
(see ADR-0013). The dict keys are the hand-authored wiki labels (FFTPatcher
convention), sourced in `tools/_fft_decode.py`. **Two effects fields —
`anim_flags` and `rsm_flags` — are the documented exception: they stay raw
`int`, deferred pending reverse-engineering of their bit meanings** (FFTPatcher
names them only `Bool1..Bool24`; there is nothing faithful to decode into yet).
Raw is the honest form for *unimplemented* ROM data — decode only when the bits
are understood. A guard (`tools/check_adr0013_deferred_flags.py`) locks the
deferral. Note the name-collision trap: the per-unit GPU runtime field
`anim_flags` (`U_ANIM_FLAGS`, shader-written animation latches) is unrelated to
the ROM ability byte of the same name.
_Avoid_: emitting the raw integer and decoding at the call site (the
[Committed extracted artifact](01-asset-extraction.md) rule); using a name
array for an independent-property field (the bits are not a set —
`weapon_flags = ["striking", "arc"]` loses the eight named properties
the dict carries).

**Bit-packed field, set form**:
A committed-artifact field where each bit asserts *set membership* of a
named element/status — decoded by the extractor into a name array, never
emitted raw. `absorb_elements: ["Fire", "Holy"]`,
`status_immunity: ["Petrify", "Sleep", …]`, and (per ADR-0013)
`inflict_status: [...]` are the canonical shapes. The label tables are
the hand-authored wiki names sourced in `tools/_fft_decode.py`. The
choice between this and the **named-bool form** follows the meaning of
the bits — element affinity is a set; weapon-flag properties are
independent booleans — and is not a stylistic decision.
_Avoid_: keeping a parallel raw-bitmask field alongside the decoded
array (the historical `elements_raw` in `effects.json` is a small smell,
slated for removal per ADR-0013); modelling set-form fields as
named-bool dicts (`{Fire: false, Lightning: false, …}` for every
ability/job loses the meaning of an *affinity set* and pollutes the dict
with `false`s).

**Hand-authored data asset**:
A tracked JSON asset that is *not* produced by an extractor — it captures
wiki / reverse-engineering knowledge the ISO bytes can't carry on their
own. Lives in the same `assets/` tree as a [committed extracted
artifact](01-asset-extraction.md) but has no `tools/parse_*.py` counterpart;
the file itself is authored by hand. Loaded at runtime via the
`JobDatabase` shape (a `class_name` module with a static cache and a
lazy `_ensure_loaded`); never compiled into a generated GDScript
`const Dictionary` mirror. The `_ensure_loaded` open→parse→error
boilerplate is shared: every store calls
[`JsonAsset.load_dict(path, key)`](../../addons/exmateria_platform/json/JsonAsset.gd) (a free-function
helper, not a base class — GDScript per-subclass static state does not
inherit, so each store still keeps its own typed cache, accessors, and
`_loaded` flag; only the I/O body is factored out). A store that wants a
value that is not a top-level object (an `Array` under a key, a nested
path, or several sibling keys) calls `load_dict(path)` for the root dict
and plucks locally. Tables-of-records loaders live in `src/data/`
by convention (`SpriteDatabase`, `StateAnimationDatabase`); a
domain-specific loader (like `SfxCatalog`) can live alongside its
subsystem when the asset is part of that cluster's vocabulary. Two canonical examples: the [SFX
catalog](14-audio.md) (`sfx_bank_names.json`, slot → slug labels sourced from
the FFT wiki) and `assets/abilities/state_animations.json` (the
AnimationState → SEQ-frame-id mapping that `StateAnimationDatabase`
reads, sourced from reverse-engineering notes). The contrast with a
**Committed extracted artifact** is the origin (hand vs. extractor); the
contrast with a **Regenerable bulk** is git-tracking (yes vs. gitignored);
the contrast with a generated `const`-dict module is single source of
truth (JSON vs. JSON + a parallel checked-in mirror that can drift).
_Avoid_: emitting one through an extractor (the labels/mappings can't be
derived from ISO bytes — that's *why* they're hand-authored); duplicating
one into generated GDScript code (the JSON is the canonical source; a
generated `const Dictionary` mirror just gives the data two homes and an
opportunity to drift — the failure mode that retired the old
`SpriteDatabase.gd` and `StateAnimationDatabase.gd` const-dict files);
storing them under `assets/` without a corresponding loader that names
them in code (every hand-authored data asset has exactly one
`class_name` loader somewhere in `src/`; if it doesn't, the asset has no
live consumer and should be removed).

**Bootstrap**:
The single idempotent, OS-agnostic command that takes a fresh checkout to
a runnable state (`tools/bootstrap_assets.sh`): symlink the extract, run
every extractor, trigger a Godot import. Intended to be *comprehensive* of
all ISO-derived assets.
_Avoid_: setup script, install.

**Host-agnostic**:
Property required of every tracked file and every extractor: no absolute
paths, no `/mnt/c` / WSL / drive-letter assumptions, no reliance on
filename case folding. Paths resolve from the repo via `_repo_paths.py`.
Works identically on Linux, Windows, WSL, macOS.

**Canonical case**:
The filename case an extractor emits is authoritative — uppercase hex and
uppercase names, lowercase extension (`0A.tga`, `WEP1.tga`, not `0a.tga`
or `WEP1.TGA`). Code references must match this exactly; Linux is
case-sensitive and will not forgive a mismatch the way Windows does. When
code and disk disagree, the code is wrong.

**Battle range-overlay tile**:
The animated in-battle tile graphic FFT draws on the battlefield to mark
ranges. **In FFT the color carries a fixed meaning:** **blue** = where a
unit can *move*, **red** = where it can *attack*, **yellow** = what is
currently *selected* (the attack cursor sitting on a red tile). **None of
those meanings carry over.** In this project the look is **fully decoupled**
from purpose — there is no correspondence whatsoever between FFT's
move/attack/select and our placement roles. We take only the *visuals* (the
indexed texel bitmap, the four animated palettes, the barber-pole shimmer)
and re-map them freely onto the game's own `Tile` highlight types — Friendly
(`PLACEMENT_PLAYER`), Enemy (`PLACEMENT_ENEMY`), Contested
(`PLACEMENT_CONTESTED`), Available (`PLACEMENT_AVAILABLE`), Unavailable
(`PLACEMENT_UNAVAILABLE`) — each tunable per-type, where they were
previously flat dummy colors. So "the blue tile" names a **palette**, never
a meaning: a Friendly tile may be drawn blue, red, or yellow as art
direction dictates. Like every other ROM-derived graphic
it is an [ISO-derived asset](01-asset-extraction.md): produced by a
`tools/parse_*` extractor reading the ISO extract (BATTLE.BIN / a system
graphics blob), reproducible and host-agnostic — **never dumped from a
running emulator**. A PCSX-Redux save state is only the **discovery +
verification oracle**: it locates the texture/CLUT in VRAM, and the
texel/CLUT bytes read there are a
**signature to search for in the ISO extract** (find the same pattern in
the source → that is the parser's offset), plus a known-good reference
frame to verify against. It is **not** the asset source. **Resolved
(static analysis): it is a stored indexed bitmap + an animated CLUT, not
procedural.** The base palettes are static BGR555 rodata in BATTLE.BIN
(blue `0x80094ae4`, red `0x80094b04`, the yellow/target pair
`0x80094b44`+`0x80094be4` — which share their first 7 colors, confirming
the one-texture-two-palettes read); the shimmer is a **15-phase
barber-pole rotation** of the 16-color gradient (index 0 pinned
transparent, colors 1–15 cyclically shifted by phase) driven per-frame by
the range-tile cycle routine `FUN_80088eec` (`0x80088eec`). So what ships
is parsed from the ISO — the indexed texel bitmap + the rodata palettes —
and the *animation method* (the rotation) is reproduced in the Godot tile
shader as an animated palette LUT.
_Avoid_: importing the emulator's VRAM dump as the committed/regenerable
asset (host-specific, non-reproducible — the [ISO-derived asset](01-asset-extraction.md)
rule); carrying FFT's blue=move / red=attack / yellow=target meanings
into the Godot placement layer (semantics are re-mapped; only the look
transfers); calling it a "cursor" unqualified (the on-tile **range
panels** are a different graphic from the box selection cursor).
