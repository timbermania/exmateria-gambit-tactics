# An asset belongs to the system that owns its format

An asset is filed by the system that owns its **encoding** — the system that
would have to change if the bytes' format changed — and **not** by the system
that calls `load()` on it. A reader that is not the format owner is a
**crossing**, named like any other crossing. Asset packets therefore stay
**entity-shaped and flat**; a system-named subdirectory appears only where two
format owners genuinely share one packet.

**Status:** accepted (2026-08-21). Resolves
[#323](https://github.com/timbermania/fft-monorepo/issues/323) on map
[#305](https://github.com/timbermania/fft-monorepo/issues/305) — goal #6,
*"assets as a superset, not a ROM transcription."* **Amends**
[ADR-0132](0132-assets-are-filed-by-consuming-system-not-by-provenance.md)
dec. 1 and corrects three figures in its Context. **Upholds**
[ADR-0072](0072-a-template-is-a-derived-folder-per-key-asset-packet-that-is-the-runtime-read-surface.md)
dec. 3 unchanged.

## Context

ADR-0132 dec. 1 says *"an asset is filed by the system that reads it."* ADR-0072
dec. 3 folders assets **per entity** — one folder per character — deliberately,
because *"replacing a file in a folder re-skins the unit."* #323 asked which
axis wins inside a packet, and owed one thing before deciding: a **third packet
class measured**. ADR-0132 had two (`characters/`, `effects/E###/`) and said so
itself — *"how often it splits a packet is an empirical question per class, and
so far one class of two."*

**All figures below measured at `377c8a569`, classifier `classify_blueprint.py`
at `34848f14f`, 2026-08-21.** Byte shares are **content bytes**: Godot `.import`
sidecars are excluded, and a file is booked to a system when a `.gd` file that
`classify_blueprint.py` puts in that system opens it.

### Three packet classes, and none of them splits

| packet class | packets | content bytes | owner | second **system** | **no reader** |
|---|---|---|---|---|---|
| `effects/E###/` | 401 + `trap/` | 208,845,247 | `Effects` **93.93%** | `Effects` + `Audio` co-read 3 files — **1.86%** | **4.22%** |
| `characters/templates/<key>/` | 165 | 91,726,944 | `Sprite Rig` **85.17%** | `UI` 1.07% · `Character Catalogue` 0.33% | **13.43%** |
| `maps/MAP###/` | 119 | 265,127,968 | `Battlefield` **86.23%** | **none** — the assembler co-reads `terrain.json`, 11.37% | **2.41%** |

The third class settles it: `maps/MAP###/` is read by `src/map/` end to end,
with one co-reader outside it — `ScenarioPlayerScene.gd`, an **assembler** root
scene, pulling `size_x`/`size_z` out of `terrain.json`. It has **no second
system at all**. So `effects/E###/` is the only mixed class of the three, and
the largest second system in any packet is **1.86%**. A uniform system axis
inside every packet would buy a boundary for under two per cent of bytes and
cost every packet a level of nesting.

### Read-ownership and format-ownership disagree, and the ADR already knew

ADR-0132's own Context books the portrait to `Sprite Rig` — *"`UI` owns the
frame, not the pixels"* — while `UI` is the only thing that reads it. Measured
here: `portrait.tga`'s single loader is `src/ui3/elements/UIPortrait.gd`, and
`src/animation/` contains the string `portrait` **zero times**. Under dec. 1 as
written, the portrait is `UI`'s. Under dec. 1 as *worked*, it is `Sprite Rig`'s.

The ADR resolves this itself by scoping the rule — *"dec. 1 sorts **stores**"* —
but nothing then supplied the file-level test, so #323 (and its first
resolution attempt) applied a store-level rule at file grain and got the
portrait wrong.

**The test that makes every case come out right is the format**, and it reaches
one case the ADR's narrower phrasing cannot:

| case | occasion supplied by | owner | why |
|---|---|---|---|
| the crystal ([ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)) | `Battle` | `Sprite Rig` | sprite-sheet pixels |
| EVTCHR cinematic poses | `Cutscene` | `Sprite Rig` | sprite-sheet pixels |
| the unit portrait | `UI` (which owns the frame) | `Sprite Rig` | sprite-sheet pixels |
| **`sound.json` · `sound_containers.json` · `feds.bin`** | **`Effects`** | **`Audio`** | **`Audio`'s sequence format** |

The fourth row runs the other way — `Effects` supplies the occasion and `Audio`
owns the bytes — which is [#307](https://github.com/timbermania/fft-monorepo/issues/307)'s
*"`Effects` holds `Audio`'s format"* restated as content. *"Anything made of
sprite pixels resolves to `Sprite Rig`"* cannot explain it; **format ownership**
explains all four, and it is the same rule ADR-0132 was reaching for with *"one
system supplies the occasion and `Sprite Rig` draws the pixels."*

Those three audio files are the measured mix: both `src/effects/EffectData.gd`
and the **already-departed** addon's
`addons/exmateria_sound/runtime/effect_json_loader.gd` open them by name out of
the effect directory. Two systems, one packet, one genuine split.

### The reader rule has no answer for 27.5 MB

**27,513,574 content bytes across the three classes are read by nothing** —
larger than the second system in every class:

| slice | bytes | note |
|---|---|---|
| `characters/…/events/chr/` + `events/face/` | 12,322,368 | the game's EVTCHR pixels come from the flat `assets/sprites/textures/evtchr/segment_NNN.tga` atlas, and its faces from `assets/scenarios/faces/` |
| `effects/E###/feds.json` | 4,712,232 | a decoded byproduct — `regen_feds_json.py` calls it exactly that; `feds.bin` is the truth |
| `effects/E###/texture_palette.json` + `texture_meta.json` | 4,088,873 | written by `parse_effect.py`, zero readers repo-wide |
| `maps/MAP###/mesh_animation.json` + `anim_meshes/` | 6,387,908 | `manifest.json` carries an `animations.mesh_animation` key; the three keys read are `palette_animations`, `uv_animations`, `texture_animations` |

A rule keyed on readership leaves all of it homeless. A rule keyed on format
does not: sprite pixels are `Sprite Rig`'s whether or not anything loads them.

### Three figures in ADR-0132's Context do not hold

1. The portrait is *"drawn through the same paletted indexed shader as the
   body."* **It is not.** The body is `unit.gdshader`, which
   `#include`s `unit_sprite_body.gdshaderinc`; the portrait is
   `unit_portrait_3d.gdshader`, 54 lines, **no include**. Two shader files, no
   shared code. They share the *format* — palette-indexed pixels against the
   sprite sheet's palette — which is the reason that actually holds, and is why
   the conclusion survives the correction intact.
2. *"So far one class of two."* It is now **one of three**.
3. *"`Sprite Rig`'s **78 files out of 78**."* **Not reproducible.** No template
   folder in the tree holds 78 files by any counting — with or without `.import`
   sidecars, the counts run 3, 5, 7 … 315. Assets are gitignored, so this is not
   a commit difference. The claim's *shape* is confirmed at packet scale
   (`Sprite Rig` 85.17% by bytes, and the whole residue is dead or
   `Sprite Rig`'s anyway); only the count is unsupported.

## Decision

1. **An asset belongs to the system that owns its format.** The test is: *if
   this asset's encoding changed, which system's code would have to change?*
   That system owns it. This **amends ADR-0132 dec. 1**, whose axis (system, not
   provenance) stands unchanged and whose worked examples all still come out the
   same — `MUSIC_00.SMD` is `Audio`'s under either reading. Only the *test*
   changes, and only where reader and format owner differ.

2. **A reader that is not the format owner is a crossing.** `UI` loading
   `portrait.tga` is `UI` reaching across into `Sprite Rig`; `Effects` loading
   `feds.bin` is `Effects` reaching across into `Audio`. These are named the way
   every other crossing is named, and they are what the packet's content schema
   (ADR-0132 dec. 6) has to state. A crossing is not evidence of ownership, and
   counting readers is not how an asset is filed.

3. **ADR-0072 dec. 3 is upheld, unchanged.** The packet stays **entity-shaped
   and flat**. One folder per character, per effect, per map.

4. **System subdirectories are exception-only, never uniform.** A system-named
   subdirectory appears inside a packet **only** where two format owners
   genuinely share it. A `sprite_rig/` subdirectory inside a folder that is
   entirely `Sprite Rig`'s is redundant and is not written. Rejecting the
   uniform form is deliberate: it was the leading candidate on #323 and the
   measurement does not support its cost.

5. **The default owner is declared per packet class, not carried in the path.**
   Because dec. 4 leaves most packets with no system marker, each packet class
   names its owning system in its content schema (ADR-0132 dec. 6) and in
   `BLUEPRINT.md`'s packet table. This is the answer to the *"unnamed default
   owner"* failure mode [#315](https://github.com/timbermania/fft-monorepo/issues/315)
   and [#316](https://github.com/timbermania/fft-monorepo/issues/316) both
   flagged: the default is named, just not in the directory name.

6. **`effects/E###/` is the one measured exception, and its audio slice takes
   the one subdirectory.** `sound.json`, `sound_containers.json`, `feds.bin` and
   `feds.json` move to `effects/E###/audio/`. Both readers change together —
   `src/effects/EffectData.gd` and the addon's `effect_json_loader.gd`. This is
   **execution**, and belongs to `Audio`'s extraction pass (#2 in ADR-0141's
   order), not to this map.

7. **The rule replaces its own special case.** *"Anything made of sprite pixels
   resolves to `Sprite Rig`, with the other system supplying the occasion"* is
   **retired as a standalone rule** and recorded as what it is: the three
   `Sprite Rig` rows of dec. 1's table. It was proposed on #323 for promotion to
   blueprint vocabulary on a fourth case; the fourth case arrived and runs the
   opposite direction, so the general rule is promoted instead. `Sprite Rig`
   holds three of the four rows because it owns the most widely-read format on
   the board, not because sprite pixels are special.

8. **An unread asset still has an owner.** The 27,513,574 bytes above are booked
   by format like everything else. **Whether they are deleted is not decided
   here**: ADR-0112 defines deadness as *what the root set cannot reach*, and
   that test has no asset arm. It has no mechanized arm at all: `tools/` holds
   21 `check_*.py` guards and none of them walks reachability from the declared
   roots, for `src/` or for `assets/`. Naming an owner is what this ADR
   owes; the deletion test is recorded as fog on #305.

## Considered and rejected

- **Nest both axes, entity-first — `characters/<key>/sprite_rig/…` (the leading
  candidate on #323).** Rejected on the measurement. It buys a path-carried
  boundary for at most 1.86% of any packet's bytes and costs every packet in
  three classes a level of nesting. Its stated benefit — *"a departing addon
  globs `characters/*/sprite_rig/`"* — does not materialise: the addon that
  **has already departed** reads `sound.json` out of the effect directory by
  name, alongside `Effects` reading the same file. A subdirectory renames the
  path; it does not unshare the file. The crossing still has to be named, which
  is dec. 2.
- **Keep dec. 1's readership test and follow it to its conclusion.** Rejected:
  it books the portrait to `UI` against ADR-0132's own worked example, has no
  answer for 27.5 MB with zero readers, and returns *two* answers for the
  34.0 MB with two readers. It is not a function.
- **Declare ownership in a per-packet manifest file.** Rejected on #323 already
  and again here: a manifest is a second place for the truth to rot, and the
  built precedent for a shared asset is a **port**, not a declaration —
  `CharacterTemplateResolver.read_template_json` documents itself as *"the ONE
  reader of the template metadata,"* and `UI`'s `FormationScene` calls through
  it rather than opening the file.
- **Delete the unread 27.5 MB as part of this decision.** Rejected as out of
  grain: it is a deadness question, and the deadness test for assets does not
  exist yet (dec. 8).

## Consequences

- **Nothing moves on trunk today.** Dec. 3 upholds the current layout and dec. 6
  is the only physical change, scheduled onto `Audio`'s pass.
- **`UIPortrait.gd` is now a named crossing, not a settled owner.** Its
  portrait-loading half reads `Sprite Rig`'s format from inside `UI`. Whether
  the pixel-reading code moves is `Sprite Rig`'s and `UI`'s pass work; this ADR
  only fixes which system the *asset* belongs to.
- **The asset instrument NOW EXISTS — `tools/asset_census.py`**, built by
  prologue pass 4
  ([ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)
  dec. 6), from the recipe below plus dec. 1's format-owner override. It
  reproduces all three packet-class totals **to the byte**, and reaches two
  classes measured here: `assets/scenarios/` (**77,853,620** bytes, `Cutscene`,
  43.4% with no reader in `src/`) and `assets/sprites/` (**120,583,297**,
  `Sprite Rig`, 68.4% with no reader). Both strengthen dec. 1 rather than test
  it: `assets/sprites/`'s largest *reader* is `infrastructure` — the asset
  manifest — over 120 MB whose format is plainly `Sprite Rig`'s. Every content
  byte under `assets/` now has a format owner. **Dec. 8's missing arm — whether
  the unread bytes are dead — is `tools/closure.py`, which reads 56.7 MB (7.4%)
  unreached, twice the 27.5 MB quoted here.** The paragraph below is kept as the
  record of what was owed.
- **The asset instrument did not exist when this was written.** Every figure here came from an ad-hoc
  census; there is no committed tool, deliberately — ADR-0131 puts instrument
  changes **before** the baseline and together, and this would be a third one
  landing alongside the `src/data/` catch-all and the shader walk. The recipe:

  ```python
  # from godot-learning/, per packet-class root
  import os, re, collections
  by = collections.Counter()
  for d in sorted(os.listdir(root)):
      if not os.path.isdir(os.path.join(root, d)): continue
      for dp, _, fs in os.walk(os.path.join(root, d)):
          rel = os.path.relpath(dp, os.path.join(root, d))
          for f in fs:
              k = re.sub(r'\d+', 'N', re.sub(r'[0-9a-f]{8,}', '<h>', f))
              by[k if rel == '.' else rel + '/' + k] += os.path.getsize(os.path.join(dp, f))
  ```
  Book each family by grepping `src/` for the quoted filename and running the
  hits through `classify_blueprint.py` — then **override by format** where the
  reader is a crossing, which is the whole point of dec. 1.
- **Goal #6's measurability (ADR-0132 dec. 5) is unaffected.** Whether a content
  tree can hold something the extract cannot produce is orthogonal to who owns
  the bytes.
