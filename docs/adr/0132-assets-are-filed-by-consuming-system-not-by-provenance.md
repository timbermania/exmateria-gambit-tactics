# Assets are filed by consuming system, not by provenance

An asset store is segregated by **the system that reads it**. Whether an asset
was extracted from the ROM or authored by hand is a *pipeline* property — it
decides what is gitignored — and never a directory-level distinction. The
package keeps **three** asset places, each with exactly one job: an **extract**
that is input only, a **content** tree that is the read surface, and an
**authoring workspace** that lives outside the project.

**Status:** accepted (2026-08-20). Resolves [#308](https://github.com/timbermania/fft-monorepo/issues/308) on map
[#305](https://github.com/timbermania/fft-monorepo/issues/305) — goal #6,
*"assets as a superset, not a ROM transcription."* Amends
[ADR-0072](0072-a-template-is-a-derived-folder-per-key-asset-packet-that-is-the-runtime-read-surface.md)
dec. 4 and supersedes the persistence target recorded on
[#254](https://github.com/timbermania/fft-monorepo/issues/254).

## Context

Goal #6 has one sentence behind it — ADR-0110's Context, *"assets rethought as a
superset rather than a ROM transcription (#6)"* — and no ADR gave it a unit.
This is the same shape [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
found in *"the host's size is the progress bar"*: a phrase promoted to a
decision without one.

**All figures below measured at `c1f1a56a8`, 2026-08-20.**

### The provenance line is already drawn, and it is not the interesting one

`godot-learning/assets/` holds **22,680 files / 805 MB**, of which **249 are
tracked** (1.1%). The split is clean and needs no decision: small JSON tables
are committed (`abilities` 9/9, `items` 2/2, `jobs` 2/2, `roster` 4/4, `stats`,
`audio`, `fonts`, `scenes` — all 100% tracked); bulk ROM-derived media is
gitignored and rebuilt by `tools/bootstrap_assets.sh` (`characters` 0/4717,
`maps` 0/1271, `music` 0/101).

### The interesting line is the consuming system, and nothing draws it

Counting distinct `src/` directories that reference each store (a **floor** —
`src/` directories are not blueprint systems 1:1, and this cannot see
duck-typed reaches, the same caveat `tools/touch_matrix.py` carries):

| store | distinct `src/` dirs that read it |
|---|---|
| `assets/sprites/` | **11** |
| `assets/effects/` | **5** (incl. `audio`, `gpu`) |
| `assets/scenarios/` | 3 |
| `jobs` / `audio` / `music` | 1 |

The stores are not one-to-one with systems because **the folder boundary is the
ROM's**. One `E###/` holds effect data *and* `Audio`'s FEDS bank — **4.1% of the
corpus by bytes** (8,590,914 of 209,055,500 across 401 effects), which is #307's
5,306-line finding stated as content. The ROM packed them together because they
ship as one file.

> **Three figures in the paragraph below are corrected by [ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md)
> (2026-08-21), measured at `377c8a569`.** (a) The portrait is **not** *"drawn
> through the same paletted indexed shader as the body"* — the body is
> `unit.gdshader`, which `#include`s `unit_sprite_body.gdshaderinc`; the portrait
> is `unit_portrait_3d.gdshader`, 54 lines, with **no include**. Two shader
> files, no shared code. What they share is the *format*, which is the reason
> that actually holds and is why the conclusion survives intact. (b) *"One class
> of two"* is now **one of three**: `maps/MAP###/` is `Battlefield` 86.23% by
> bytes with **no second system at all**. (c) **`78 files out of 78` is not
> reproducible** — no template folder in the tree holds 78 files by any counting,
> and assets are gitignored so this is not a commit difference. The shape holds
> at packet scale (`Sprite Rig` 85.17% by bytes); only the count is unsupported.

**A packet does not automatically split, though, and the obvious candidate does
not.** The character template was measured on the same day and is **`Sprite Rig`'s
78 files out of 78**: the body sheet, the 37 EVTCHR sprite pairs (drawn by
`src/animation/` — `UnitDisplay`, `SpriteLayerManager`, `AnimationResolutionMap`,
`SpritePaletteResolver`; `src/scenarios/` only *triggers* them), the portrait
(a region at **(80, 456)** inside the sprite sheet, stored **rotated 90° CW**,
drawn through the same paletted indexed shader as the body — `UI` owns the
frame, not the pixels), and `template.json`'s sprite-table scalars. The rule that
keeps surfacing is **one system supplies the occasion and `Sprite Rig` draws the
pixels** — the same shape ADR-0129 found for the crystal. So dec. 1 sorts
*stores*; how often it splits a *packet* is an empirical question per class, and
so far one class of two.

`BLUEPRINT.md` §*"A ROM file is not a responsibility"* already states the rule
and works `ATTACK.OUT` through it — encounter table, placement table and
title-card wipe going to three systems, *"nothing but the disc layout relates
them."* **The repo applied it at file level and stopped there:**
`deployment_zones.json`, `scenarios.json` and `map_titles/` are three separate
files, and all three sit under `assets/scenarios/` — `Battle`'s zones and
`UI`'s title cards filed under `Campaign`'s name.

### Authoring is write-only today, and the reason is structural

`src/effects/studio/` has **11 saver files**, every one writing to
`res://authored_effects/`. **Nothing reads that directory** — 0 non-`OUT_DIR`
references. Both live `EffectData.load_from_directory` callers read
`assets/effects/E###` (`EffectStudioPage` parses `"E317" -> 317` off the
dirname). The savers state the reason themselves: the source is the pristine ROM
extract and they must *"never clobber"* it, so Save writes a partial-patched
`E###.BIN` beside it and the only route back into the game is a human copying
that file into `project-assets/fft-extract/` and re-parsing. **The round trip
goes through the ROM file format**, so a field with no valid raw encoding — the
superset part, precisely — cannot survive it.

This means #254's recorded decision is **not what got built**. It specified
*"the existing per-effect JSON dir extended into a superset, runtime
`load_from_directory` UNCHANGED, no migration."* What exists is a third store,
`authored_effects/`, holding `E001.BIN` + `E001.screen.json`. The decision was
unimplementable as written because that JSON dir is derived and gitignored.

### The one extracted system already has the crossing, and names it wrong

`exmateria-sound/addons/exmateria_sound/` carries **zero content files** and has one
module — `runtime/asset_paths.gd` — whose entire job is locating content in the
host. That module *is* the content-pack crossing, already built, in the only
system that has actually left. Its resolution order is
`EXMATERIA_ASSETS_DIR` → `~/.local/share/exmateria/assets/` →
`project-assets/fft-extract/`: **outside the project first, repo last.**

Its defect is the address, not the mechanism:

```gdscript
return root.path_join("SOUND/MUSIC_%02d.SMD" % slot)
```

The disc directory and the ROM filename. The code is portable; the content
interface is not. Shipping that addon to another tactics RPG requires handing it
a folder called `SOUND/` containing files named `MUSIC_00.SMD`.

## Decision

**1. The axis is the consuming system, not provenance.** An asset is filed by
the system that reads it. Extracted-vs-authored decides gitignore and nothing
else; it is never a directory-level distinction. `MUSIC_00.SMD` is extracted and
belongs on the system side, because `Audio` is what reads it.

> **Amended by [ADR-0142](0142-an-asset-belongs-to-the-system-that-owns-its-format.md) dec. 1 (2026-08-21).**
> The **axis** stands — system, not provenance — and every worked example above
> is unchanged, `MUSIC_00.SMD` included. The **test** does not: an asset is filed
> by the system that owns its **format**, not the system that reads it. Where
> the two differ, readership gives the wrong answer, including against this
> ADR's own Context — `portrait.tga`'s only loader is `src/ui3/elements/UIPortrait.gd`,
> so readership books it to `UI` while the paragraph below books it to
> `Sprite Rig`. A reader that is not the format owner is a **crossing**.
> Measured at `377c8a569`: readership also has no answer for **27,513,574
> content bytes** with zero readers, and returns two answers for the 34.0 MB
> read by two systems.

**2. Three places, each with one job.**

| place | shape | job |
|---|---|---|
| **extract** | ROM-shaped, gitignored, regenerated | **input only — nobody's read surface** |
| **content** | segregated by system | **the** read surface; what an extracted addon resolves against |
| **workspace** | outside the project | where an authoring tool saves *and loads*; not in the game |

**3. The content tree is derived, and promotion into it is an explicit act.** A
rebuild must be able to regenerate it — 805 MB, 99% ROM-derived, uncommittable
for size and for provenance. An authored asset becomes part of the game by being
**placed** in the content tree. That is a deliberate step, not a side effect of
pressing Save.

**4. An authoring tool's save/load loop closes in the workspace, outside the
project.** This is what fixes the write-only defect: today Save writes into the
*game's* tree, which is why it can have no reader. A tool that saves and loads
its own documents in its own workspace closes its loop without the game being
involved at all — and matches how `asset_paths.gd` already resolves.

**5. The superset is what survives a checkout with no ROM.** Goal #6 is
satisfied for an asset class when its content tree can hold something the
extract cannot produce. This makes the goal **measurable**: a class is still a
transcription while everything in it is reproducible from the ROM.

**6. What crosses the content-pack boundary is a per-system content schema,
resolved through an asset-path port.** `asset_paths.gd` is the built precedent
and the shape to generalise. A content schema is addressed in **system
vocabulary**, never in ROM vocabulary — `SOUND/MUSIC_%02d.SMD` is the
counter-example to fix, not the pattern to copy.

**7. A ROM file's demux is not done until its shards sit under their consuming
systems.** Splitting `ATTACK.OUT` into three files was half the move; all three
still live under `assets/scenarios/`. Store-level demux completes it.

## Considered and rejected

- **An `authored/` tree beside `extracted/`.** The shape this ticket opened
  with, and the one the code drifted into (`authored_effects/`). Rejected on the
  author's own correction: provenance is not the distinction that matters, and
  filing by it puts `MUSIC_00.SMD` and a hand-made effect in different trees
  despite `Audio` and `Effects` reading them the same way. It also reproduces the
  write-only bug, because an `authored/` tree beside the extract is still not
  anybody's read surface.

- **The content tree as hand-owned source, seeded once from the ROM.** Rejected:
  805 MB of ROM-derived content cannot be committed, so the tree has to stay
  rebuildable regardless; and a store that can never be safely re-extracted
  freezes the parsers.

- **Extending the per-effect JSON dir in place (#254's recorded target).**
  Superseded rather than reversed — it was the right instinct (no migration,
  runtime loader unchanged) aimed at a derived directory. Decisions 2–4 give it
  the destination it lacked.

- **Forking the format per authored asset (`assets/effects/trap/`).** The one
  committed, ROM-less effect in the package — 10 tracked files, its own dialect
  (semantic `emitters.json` with named float vectors and no raw fields, beside a
  `palette.json` carrying Ghidra provenance), and its own **1,005-line**
  `TrapEffect.gd` loader. It proves a superset asset is possible and shows the
  price of getting there without one: a parallel loader per authored asset.

## Consequences

- **`asset_paths.gd` becomes a port with a schema behind it**, not a path
  helper. Its ROM-vocabulary addressing is the first thing that has to change,
  and it changes in `exmateria-sound/`, not here.

- **The Effect Studio gains a workspace and stops writing into the game tree.**
  Its 11 savers currently target `res://authored_effects/`; under dec. 4 that
  becomes an out-of-project document store the Studio also *loads*. This is a
  build, scheduled by the loop — not this map.

- **ADR-0072 dec. 4 is amended, not reversed.** *"The template folder is the
  runtime read surface"* is the intended end state and is **not** the built
  state: `src/` holds **2** references to `assets/characters/templates/` against
  **48** to the flat `assets/sprites/` store. The ADR's own Status line already
  says loaders (#203) are pending; `CONTEXT.md` stated it in the present tense
  without that caveat and is corrected here.

- **Goal #6 gets a per-class verdict rather than one global answer.** Under
  dec. 5 each asset class is measurable independently, and today every class
  except `assets/effects/trap/` is a transcription.

- **The entity-packet grain is left open, and it collides with ADR-0072.**
  Dec. 1 files by consuming system; ADR-0072 dec. 3 folders per character
  *deliberately*, because *"replacing a file in a folder re-skins the unit — this
  is what makes the layout moddable."* Those pull opposite ways for any packet
  whose files serve several systems — **`effects/E###/` is the one class known to
  do so** (`Audio`'s 4.1%), and the character packet, this ticket's motivating
  case, turned out **not** to split at all. **This ADR does not resolve it** — it
  decides the store's axis, not the packet's internal grain. Goal #5 and goal #10
  each have a stake, and it is filed as its own ticket, where the leading
  candidate is to nest both axes entity-first (`characters/<key>/sprite_rig/…`)
  so a departing addon globs its own slice and a modder keeps one folder per
  thing.

- **Nothing schedules the content schemas.** They are a second schema family
  beside ADR-0121 dec. 5's six published *payload* schemas, with the same
  problem: a prerequisite with no owner and no place in the extraction order.
