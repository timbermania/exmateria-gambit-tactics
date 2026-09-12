# The world map splits, because being a mode the spine sequences never meant the spine owns the code

`src/world_map/` was the repo's **entire** `UNCLASSIFIED` bucket — 15 files, 4,496 lines,
2.3%, and `classify_blueprint.py` returned `None` for every one of them and for nothing
else. It splits **four ways**: the screen is `UI` (11 files), the progression is `Campaign`
(2), the music port is `Audio` (1), and the `.tscn` root is `assembler` (1). The rule that
does it is one BLUEPRINT already relies on elsewhere.

Status: accepted (2026-08-25) — grilled with the user. Closes issue #580 and turns
`check_blueprint_walk` green (**0 unclassified**, 650 files walked). Deletes the
`NOT ASSEMBLER — src/world_map/WorldMapScene.gd` KNOWN entry ADR-0181 filed in
`tools/check_root_set.py`. Re-books ADRs 0178, 0161 and 0174 from `Campaign` to `UI`.

## Context

Two candidates each had a real claim and the two instruments disagreed. `classify_blueprint`
said `None`; `docs/adr/CLASSIFICATION.tsv` already booked 0178 / 0179 / 0161 / 0162 as
`Campaign`. Issue #580 framed it as *"BLUEPRINT §9 lists 'world map' under Campaign's modes;
§6's content shadow says the actual screens are compositions and they stay in `UI` — both
cannot be the whole answer."*

**They can, and the tie was already broken two days earlier.** §9's list reads *"Story scene,
formation, deployment, battle, results, world map."* **Formation is in that list, and
`FormationScene.gd` classifies `UI`** — ADR-0172 reaffirmed exactly that when it put
Formation's screen-in in `UI`. So appearing among Campaign's modes has never implied Campaign
owns the code; if it did, the classifier would have to move Formation, and nobody has
proposed that. §9 names the modes the spine *sequences*. §6 owns the screens. They were never
competing, and the apparent conflict was one document being read as an ownership list when it
is a transition list.

## Decision

### 1. The spine owns WHERE YOU ARE; each mode's screen belongs to the system it is made of

That is the rule, and it is not invented here — it is the already-load-bearing reason
Formation is `UI` despite being a §9 mode. Applied to `src/world_map/`, the fallback is `UI`
(the majority: it is a screen) with four exceptions.

### 2. The four exceptions are not judgement calls — three say what they are themselves

`docs/WORLD_MAP_PORT_LIST.md` has carried a crossing table the whole time, and the files cite
it in their own docstrings:

| file | bucket | its own words |
|---|---|---|
| `WorldMapProgress.gd` | `Campaign` | *"Campaign's payload, not the screen's"* (crossing C3) |
| `WorldMapVariables.gd` | `Campaign` | *"Campaign's save data, in the ROM's own encoding"* (C3) |
| `WorldMapMusicPort.gd` | `Audio` | *"owner Audio · edge map → Audio"* (A1) |
| `WorldMapScene.gd` | `assembler` | the `WorldMap.tscn` root |

**`WorldMapTravel.gd` reads like a fifth and is not.** "Travel" sounds like progression — the
grill provisionally booked it `Campaign` — but its docstring is *"walking the party marker
from one node to another"* (§27, §29.6), which is screen animation, and it appears on **no**
crossing. It is `UI`. That one file is the whole argument for reading the headers instead of
sorting fifteen names by how they sound.

### 3. `WorldMapScene.gd` is `assembler`, and that is a smell recorded rather than hidden

1,069 lines, holding the vsync clock, `advance()`, the screen-in quad and the contact-sheet
rig. That is not wiring. The precedent is exact, though: `NavigatorMain.gd` is 1,185 lines and
is `assembler` by ADR-0144 dec. 4, on ADR-0134's rule that an addon cannot ship a root scene.
Booking it honestly to that precedent beats inventing a bucket, but **the real answer is that
this file is two files**, and nothing here has done that work.

### 4. `psx_expand_555.gdshader` is `UI`, and the tempting `platform` is wrong for a stated reason

`psx_par` / `psx_dither` are `platform`, and this shader looks like their sibling. But the
classifier records that precedent's actual test: *"Reach is not the admission test (ADR-0139
dec. 2); a codec is, and these two have no CPU counterpart to drift against."* This one
**has** one — `WorldMapScreenIn.LEVEL_STEP` bakes `8 * v` on the CPU and this shader expands
`(v<<3)|(v>>2)` on the GPU. Two halves of one encoding that can drift is a codec by that
sentence. Whether a codec belongs in the schema kernel is ADR-0146's question, not this one,
so it stays with its consumer and the observation is on the record.

### 5. The ADR table moves with the code, except where the ADR is about the transition

0178 (the town picture) and 0161 (the screen-in) are screens → `UI`; **0174** (this line's own
fade measurement) likewise. **0179 stays `Campaign`** — the game-variable store is C3's
payload. **0162 stays `Campaign`**: it is about the mount tearing the battlefield down, which
is §9's *"the mode … and the transitions between them"*, not the screen.

## Alternatives rejected

- **All `Campaign`**, matching the four ADR rows. Campaign is 7 files / 1,250 lines; the world
  map is 15 / 4,496. This would not give Campaign the world map, it would make the world map
  **78% of Campaign** — and BLUEPRINT §9 already calls Campaign *"the weakest system on the
  list … the same shape as `Battle Presentation`, which did not survive."* Quadrupling the
  system most at risk of dissolution, with a screen, is the wrong direction.
- **All `UI`**, matching `FormationScene.gd`. Cheaper, and wrong about two files whose own
  docstrings name Campaign as their owner.
- **A twelfth system for the overworld.** `WORLD_MAP_PORT_LIST.md` lists edges into Render,
  UI, Campaign and Audio, which superficially reads as "its own thing." It is a framing
  artifact: a port list is written from the ported thing outward, and every screen reaches
  four systems. Nothing here needs a new bucket.
- **Leave it `UNCLASSIFIED` until the files are refactored.** The bucket is not a plan, it is
  a measurement, and 2.3% of the repo reading as unmeasured makes every census wrong.

## Consequences

- **`check_blueprint_walk` goes green** — 650 source files walked, 103 shaders, **0
  unclassified**. It was red before this branch and is not this branch's debt.
- **`check_baseline` stays green and stays MEANINGFUL.** It guards `BASELINE.tsv`'s freeze,
  schema and arithmetic, not a re-measurement, and no bucket was added or removed — so 1,143
  balanced reaches is untouched. But the next `--delta` run WILL move a long way: 4,496 lines
  leave `UNCLASSIFIED` for four buckets, and the cross-system edge count rises because edges
  that were invisible (nothing crosses into or out of `None`) are now real. That is a reading,
  not a regression, and it should be labelled as this ADR's when it lands.
- **`UI` grows to roughly 138 files / 43,000 lines**, and it was already the second-largest
  system. Booking a second full screen into it is correct by the rule and worth watching: if
  `UI` ever splits, "the toolkit" and "the screens" is where the seam is, and BLUEPRINT §6
  already names both halves in one row.
- **Not done here:** splitting `WorldMapScene.gd` (dec. 3), and deciding whether
  `psx_expand_555` should be promoted to the schema kernel as a codec (dec. 4). Both are
  filed by this ADR rather than by an issue, deliberately — they are consequences of a
  classification, and the classification is where a reader will meet them.
