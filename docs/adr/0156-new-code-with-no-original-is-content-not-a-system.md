# New code with no original is `content`, not a system

Every refactor ADR defines the loop's unit of work as **extracting code that
already exists**. The world-map screen is the first thing the loop has met with
**no original to extract, no closure to kill, and nothing to subtract from the
progress bar** — and for want of a ruling its nine files sat in no bucket at all,
reding two guards at trunk's own tip for two days.

They are `content`. `BLUEPRINT.md`'s bucket table already sorted an FFT screen
that way; the classifier already excludes `content` from the published baseline.
The ruling is one rule, and what it costs is that **the progress bar now means
"un-extracted system code" rather than "host size"**.

Status: accepted (2026-08-23). Resolves
[#416](https://github.com/timbermania/fft-monorepo/issues/416) and both live arms
of [#444](https://github.com/timbermania/fft-monorepo/issues/444). Widens
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
dec. 3's exclusion and reads
[ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) dec. 2 narrowly.
Applies [ADR-0143](0143-the-root-set-is-ratified-and-the-formation-cluster-is-its-one-exception.md)
dec. 3 to a second scene and
[ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)
dec. 3 to a fourth file.

Code at `6bd492b4a`, classifier at `6bd492b4a`.

## Context

`#416` filed the gap rather than settling it, and named its own standing:
*"a decision for the refactor owner, not for the person building the screen."*
It stayed open while the screen was built, so the nine files landed in
`src/world_map/` with no classifier rule. That is not a neutral parking spot —
`classify_blueprint.py` has no catch-all by design, so it exits non-zero, and
through it `check_blueprint_walk.py` goes red. `assets/scenes/WorldMap.tscn`
reded `check_root_set.py` the same way. Trunk carried both into the extraction #2
merge, recorded as inherited rather than caused (#444).

**The blueprint half was already answered and it is not "which of the ten
systems".** `docs/WORLD_MAP_PORT_LIST.md` §0 reconciles the two passages that
read as if they disagree — `BLUEPRINT.md:635` lists the world map among the modes
`Campaign` sequences; `CONTEXT.md:8084` forbids *calling* `Campaign` the world
map — and concludes: **a feature, not a system**, threading `Campaign`, `UI`,
`Render`, `Audio` and `Cutscene`, **and it gets no addon**. BLUEPRINT's own bucket
table sorts an FFT screen **Content pack**, *"stays; this is what the host
converges to."*

What stopped that being the obvious answer is ADR-0121 dec. 2 — *`src/` "only
ever gets smaller, which is what makes ADR-0110's 'the host's size is the
progress bar' a real measurement rather than a slogan."* Converging on the
content pack makes `src/` bigger, so as written dec. 2 forbids the thing the host
is supposed to converge to. #416 read that correctly and could not resolve it,
because resolving it means saying what the progress bar measures.

## Decision

**1. Genuinely new, never-extracted code is `content`.** `("src/world_map/",
"content")` — nine files, 1,501 lines, the `.gdshader` included by the directory
rule exactly as `src/ui3/shaders/` is by `("src/ui3/", "UI")`. `content` is
excluded at **report** time (ADR-0131 dec. 3/4), so a new FFT screen no longer
reads as the host growing, and #416's option 4 is taken **through a mechanism
that already existed** rather than by adding an exemption beside it.

ADR-0121 dec. 2 is not overturned; it is read for what it aims at —
*reorganisation*, per-system folders and preparatory move commits. **The progress
bar measures un-extracted system code, not host size.** Say it that way from
here; the old phrasing was never true of `content` or `generated` either, which
have been excluded since ADR-0131.

**2. `assets/scenes/WorldMap.tscn` is a declared `root` of the `game` set, and
`WorldMapScene.gd` is its assembler.** `NavigatorMain.run_world_map()` loads it
through a `const` path, mounts it whole under a `CanvasLayer` and `queue_free()`s
it when the screen signals `dismissed`. That is ADR-0143 dec. 3's shape to the
letter — *a full-screen overlay, instantiated whole and freed on dismissal, is a
navigation transition, not composition* — so the site is pinned in
`check_root_set.py`'s `KNOWN` beside `Formation`'s, and the scene is a root
rather than a component.

`WorldMapScene.gd` is therefore the **one exception** to dec. 1: an addon cannot
ship a root scene (ADR-0134), a root's script is booked `assembler`, and
`check_root_set.py` check 4 enforces it. The file's own docstring agrees —
*"Assembles the three pieces and nothing else."* So the screen splits **332 lines
`assembler` / 1,169 `content`**, and the split is the same one every root already
pays.

**3. `content` widens, and the widening is the decision.** It meant CONTEXT.md's
*Hand-authored data asset* — the `JobDatabase` shape, a static cache plus a lazy
`_ensure_loaded` plus one `JsonAsset.load_dict`. It now **also** means
FFT-specific code that stays with the content pack. The two senses do not
collide, because the mechanical one is enforced **only where it was derived**:
`check_blueprint_walk.py` check 4 re-derives the store shape over
`src/data/*.gd` and nowhere else, and the two pre-existing `content` rows outside
`src/data/` (`ScenarioGroupDatabase.gd`, `EntdBattle.gd`) are already outside its
reach.

**This is a directory rule, which is the shape ADR-0144 dec. 2 removed for
`src/data/`** — and that is deliberate here rather than a relapse. `src/data/`'s
catch-all was hiding files of **several** kinds under one bucket; this one states
a property of the directory itself: everything in it is new screen code with no
original. The property that keeps it honest is unchanged — zero UNCLASSIFIED, no
catch-all above it, and check 2's dead/shadowed-rule test.

**4. `WorldMapDebugPanel` joins `DEBUG_EXACT`, booked `content`.**
`("Map", "Battlefield")` had booked it on its **name** — the fourth time that
fragment table has done so, after the three ADR-0140 dec. 1 and ADR-0144 dec. 3
each corrected once. Its 146 lines have **zero** typed edges into `Battlefield`
or anywhere else; its only subject is `WorldMapScene`, which registers the panel
itself. Per ADR-0140 dec. 1 the owner is the system its outbound edges land in,
and they land in `src/world_map/`.

**5. What this costs the series, stated rather than discovered at pass 9.**
Measured at `6bd492b4a`, before → after:

| reading | before | after |
|---|---:|---:|
| UNCLASSIFIED | 9 files / 1,501 lines | **0** |
| accounted for | 99.2% | **100.0%** |
| `Battlefield` | 8,393 | **8,247** |
| `assembler` | 8,431 | **8,763** |
| `content` | 1,424 (14 files) | **2,739 (23 files)** |
| in a system | 157,448 | **157,302** |
| BASELINE, less `generated` and `content` | 169,734 | **168,419** |

**The per-system series moves by exactly −146, and that −146 is a correction.**
`docs/BASELINE.tsv` froze `Battlefield` at **8,247** at `de055dc49`;
`check_baseline.py --delta` had been reporting `+146` ever since, and every line
of it was `WorldMapDebugPanel.gd`. After dec. 4 the row reads **Δ +0**. No
re-freeze is owed and none is taken.

The 1,315-line fall in the BASELINE headline is **not** a series break: those
lines were `UNCLASSIFIED` before, so they were never in a system and never in any
per-system row. What changed is that they are now *declared* excluded instead of
*unplaced*.

## Considered alternatives

- **Book it to a system — `Campaign` or `UI`** (#416 option 1). Rejected on the
  measurement: `Campaign` is 7 files / 1,180 lines, so this would grow it **127%**
  for a system nobody has touched, and it would do so during
  [#492](https://github.com/timbermania/fft-monorepo/issues/492), the pass-1
  selection query that reads `Campaign`'s size as one of its three inputs. It also
  contradicts the port list's own §0: a feature is not a system.
- **Born extracted — seed `addons/exmateria_campaign/`** (#416 option 2).
  Rejected: ADR-0126 says every system pass audits before it designs, and this
  creates a system's home *before* its audit, pre-committing the boundary the
  audit exists to find. No extraction has been run this way and this is not the
  case to try it on — the destination system has not even been selected.
- **A named `quarantine` bucket, placement deferred** (#416 option 3). Rejected
  as option 1 with extra steps, which #416 says of it itself: a quarantine nobody
  collects *is* the host. It also needs a nineteenth bucket, which
  `check_baseline.py`'s schema check turns into a baseline decision — paying the
  cost of dec. 1 without taking dec. 1's answer.
- **Leave it UNCLASSIFIED and pin the nine files as known.** Rejected: it is the
  status quo that reded trunk for two days, and it makes zero-UNCLASSIFIED — the
  classifier's own exit condition, ADR-0131 dec. 4 — a thing with exceptions.

## Consequences

- **`docs/agents/refactor-loop.md` gains a rule it did not have.** New
  system-shaped code with no original is `content` until its system extracts; at
  that point the placement is a `git mv` plus the crossings already declared in
  its port list. That last half is #416's own *"safe half"* and it has been
  honoured throughout — `docs/WORLD_MAP_PORT_LIST.md` is exactly ADR-0116's
  declared crossings, written before the scene.
- **A second screen built this way needs no new ruling**, and that is the point of
  making this an ADR rather than a rule comment.
- **`WorldMapProgress.gd` is a soft spot and is recorded, not decided.** Its own
  docstring says *"Campaign's payload, not the screen's … when Campaign lands,
  this class and its backing move together."* It is booked `content` here with
  the other eight. When `Campaign` extracts, `WorldMapProgress.gd` and
  `WorldMapVariables.gd` are the two files to re-read first — the port list calls
  their crossing **C3**, and it is a Query *into* `Campaign`, not out of it.
- **Do not read this as licence to widen `content` again.** Dec. 3's widening is
  bounded by dec. 1: FFT-specific code **that has no original to extract**. Code
  that already exists in the host is a system's, and extracting it is what the
  loop is for.
