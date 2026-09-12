# Blueprint audit — what fits, what does not, and where assets go

The [blueprint](BLUEPRINT.md) was authored without reference to the code, per
[ADR-0111](adr/0111-the-research-vault-is-ballast-not-blueprint.md). This is the
check afterwards: every directory in `godot-learning/src/` and `assets/` placed
against the eleven systems, with the misfits recorded rather than forced.

**Measured 2026-08-20 on `docs/blueprint-306`.**

---

## Proof

The claim is not asserted — it is produced by
[`tools/classify_blueprint.py`](../tools/classify_blueprint.py), which assigns
every `.gd` file under `src/` to exactly one bucket and **has no catch-all**.
Anything the rules do not name falls out as `UNCLASSIFIED`, and the script
**exits non-zero** if any does. Re-run it after any change:

```
$ python3 tools/classify_blueprint.py --list-unclassified
```

| Bucket | Files | Lines | Share |
|---|---:|---:|---:|
| Battlefield | 26 | 6,585 | 4.6% |
| Battle | 72 | 16,881 | 11.9% |
| Character Catalogue | 9 | 1,219 | 0.9% |
| Sprite Rig | 21 | 3,760 | 2.7% |
| Effects | 68 | 17,145 | 12.1% |
| UI | 57 | 19,083 | 13.5% |
| Audio | 12 | 2,671 | 1.9% |
| Cutscene | 35 | 14,193 | 10.0% |
| Campaign | 7 | 2,037 | 1.4% |
| Render | 6 | 1,251 | 0.9% |
| Debug | 45 | 6,911 | 4.9% |
<!-- ADR-0140 dec. 1 (2026-08-21): `Debug` is **15 files / 2,884 lines / 2.0%**.
     A stale `"DebugPanel"` entry in the classifier's `DEBUG_HOST`, matched as a
     substring, held 30 per-system panels (4,027 lines) inside `Debug`. They book
     to Cutscene +9, Battlefield +5, UI +5, Battle +4, Character Catalogue +4,
     and one each to Audio/Campaign/Render. This snapshot's other rows are stale
     for unrelated reasons (see the `Render` and `assembler` rows). -->
| **assembler** | 100 | **28,805** | **20.3%** |
| generated | 1 | 19,411 | 13.7% |
| content | 5 | 872 | 0.6% |
| platform | 2 | 719 | 0.5% |
| infrastructure | 3 | 249 | 0.2% |
| DELETE | 1 | 39 | 0.0% |
| **UNCLASSIFIED** | **0** | **0** | **0.0%** |
| **TOTAL** | **470** | **141,831** | |

**In a system: 91,736 of 141,831 — 64.7%. Accounted for: 100%.**

### Three things the file-level pass found that the directory pass missed

**1 · `Campaign` is not missing — it was swallowed.** The first run reported
**zero files**. `NavigatorMain.gd` (1,115 lines) and six siblings live in
`src/scenarios/`, and a directory rule sent the whole folder to `Cutscene`.
**`src/scenarios/` holds two systems**, which is the vague-name pattern showing
up in the tree rather than in the model — the same shape as `src/core/` splitting
five ways.

**2 · Assemblers are the largest bucket after the systems** — 100 files, 28,805
lines, **20.3% of `src/`**. More than any single system. The Effect Studio is
most of it, with the viewers, repro scenes and game entry points making up the
rest. A category the model did not have two days ago now accounts for a fifth of
the package.

**3 · `Render` looks like the smallest system, and that is the measurement bug
made numeric.** Six files, 1,251 lines, 0.9%. *(2026-08-21: **5 files, 869 lines** — ADR-0138 books the shared kernel out of it. The point below only sharpens.)* But its actual deliverable is
**4,106 lines of shader** in `assets/shaders/`, counted nowhere — more than three
times its apparent size. `Battle` is understated the same way by **4,312 lines**
of compute shader under `src/gpu/`.

---

## Headline

**Two-thirds of `src/` is in a system; the rest is assemblers, generated content
and infrastructure.**
The remaining third was three things, and none was a boundary problem. `Debug`
became the eleventh system, the Effect Studio turned out to be an **assembler** —
a category the model was missing — and projectiles landed in `Battle`. All three are now
closed. What is left is two measurement findings that bias the refactor metric.

| | |
|---|---|
| `.gd` files in `src/` | **470** |
| lines in `src/` | **141,831** |
| of which **generated** | **19,677** — 13.9% |
| hand-written | **122,154** |
| in one of the eleven systems | **91,736** — 64.7% |
| unclassified | **0** |

---

## The census, mapped

| Directory | Lines | Goes to |
|---|---|---|
| `effects/` *(less `studio/`)* | 16,176 | **Effects** |
| `effects/studio/` | **21,986** | **`Effects`** — ADR-0134 dec. 4. *(Was "an assembler, not a system"; the assembler is `EffectViewerScene.gd`, 1,321 lines.)* |
| `data/` | 22,674 | **19,411 is generated content**; the rest splits Battle / Character Catalogue |
| `ui3/` | 18,893 | **UI** |
| `scenarios/` | 17,915 | **Cutscene** + **Campaign** |
| `debug/` | **9,265** | splits — per-system panels, and **`Debug`** (system 11) |
| `scenes/` | 7,132 | splits — host, tools, Battlefield |
| `gpu/` | 6,907 | **Battle** |
| `map/` | 4,511 | **Battlefield** |
| `units/` | 3,811 | **Battle** — `Combatant` + `Body` |
| `animation/` | 3,660 | **Sprite Rig** |
| `audio/` | 2,671 | **Audio** |
| `core/` | 2,067 | splits five ways |
| `strategy/` | 1,270 | **Battle** — `Deployment` |
| `characters/` | 1,112 | **Character Catalogue** |
| `projectiles/` | 1,027 | **Battle** — the mesh flies on the shader's clock |
| `roster/` | 609 | **Battle** — the `roster` selection |
| `scenario/` | 51 | **Cutscene** |

Twelve of eighteen directories map to exactly one system with no argument
(77,680 lines). That is the calibration result: the blueprint was not derived
from this tree, and it fits most of it anyway.

---

## What did not fit

### 1 · `src/debug/` — 9,265 lines, split

Fifty-nine files of debug panels. The six-bucket accounting had no home for them
— not a system, not content, not residue, and not *authoring* either, since these
are diagnostic and goal #10 is about authoring as a product.

**Resolved: it splits, and the larger half becomes the eleventh system.**
Panels that know what a gambit slot *means* ship with their system, the way its
tests bind its interface. The **panel host, the field widgets, the override layer
and the discovery walk** are `Debug` — a system, genre-neutral, on the same
standing as `Render`: a substantial package you would install rather than write.

Systems **declare** their tunables;
[ADR-0113](adr/0113-tunables-invert-at-the-addon-boundary.md) already inverts the
arrow, so the declaration is simply the sixth published schema. Neither side
knows the other. *(2026-08-21: **seventh**, and it is the one schema with no
shared-kernel member — realised by a port's signature, `Tune.bind`, not by a
type. ADR-0139 dec. 12/14. The point above is unchanged.)*

**And this is the highest-leverage portability change in the package**, because
ADR-0113 measured `DebugConfig` at **69 of 321 `src/` files** — more than one in
five. A system that reads it cannot ship without dragging the harness along. *(2026-08-21: the leverage is real and the **target**
was wrong — `DebugConfig` is three things under one name. Of 324 references,
**73% are verbosity gates**, 15% launch control, and only **12% tunables**. The
gates go to the system that prints them as a `static var`, launch control goes to
the assembler, and only the last twelfth is the inversion ADR-0113 describes.
**There is no inter-system logging**; `GameLogger` is deleted, not promoted.
ADR-0140 dec. 4-6.)* *(That denominator is the **2026-07-12** census — see
[ADR-0131](adr/0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md).
Against today's 470 `src/` files the share is at most **one in seven**, and a
re-measure with comments and string literals stripped gives 61, or one in eight.
The leverage claim stands — `DebugConfig` is still the most-touched autoload in
the package by a wide margin — but it is not one file in five.)*

### 2 · `src/projectiles/` — `Battle`, because the shader owns the clock

**The mesh is pure presentation.** Damage is applied by the GPU:
[ADR-0032](adr/0032-ranged-damage-waits-in-state-awaiting-impact.md) puts the
flight tail in `LOGICAL_ACTIVITY_AWAITING_IMPACT` as a **GPU state**, counts
flight ticks in `U_TIMER`, and calls `apply_attack_damage()` from the shader at
the timer-zero edge. `ProjectileManager.update()` runs **post-GPU-step**, and its
`projectile_landed` signal drives the **hit cloud** — a visual, not a damage
write.

*(An earlier draft of this audit claimed the signal gated damage. It does not.
That was read off ADR-0038's title — "a freezing combat visual" — rather than off
the code, which is the failure this whole document exists to catch.)*

**It is `Battle` anyway, and for a firmer reason.** The shader computes the
flight duration as `damage_frame - anim_frame`, and the mesh must fly in lockstep
with it. Land the mesh at a different moment than the shader's timer-zero and the
cloud desynchronises from the damage — visibly but subtly, the same family as the
hit-cloud race in ADR-0083's context. **That is an agreement crossing**, and
agreement crossings live inside one system. The shader owns the timer, so the
mesh ships with it.

**Not `Battlefield`** — a projectile is not part of the place; it is a per-action
transient bound to a firer and a target. **Not `Effects`** either, despite being
pure presentation: an `Effects` play is free-running once triggered, and this one
stays locked to a clock it does not own.

### 3 · `src/core/EventBus.gd` — deleted in the refactor

Thirty-nine lines, six users. A **global event bus** is exactly what
[ADR-0118](adr/0118-payloads-are-schemas-services-are-ports.md) replaces: cross-
system events travel on **declared channels with a published schema**, not an
untyped global. **Decided: it goes.** Each of its six uses resolves to a channel
with a schema, a query, or a capability.

### And `src/core/` splits five ways

| File | Goes to |
|---|---|
| `Tune.gd` (543) | platform — ADR-0068 |
| `ColorStack`, `ColorRecipe`, `DepthMode` (853) | **schema** — the shared kernel, ADR-0138 dec. 5 (2026-08-21). *(Was "Render"; they are depended on from both sides, so they are nobody's system.)* |
| `PSXDisplay` (254) | **Render** — and it is a **port**, not a schema (ADR-0138 dec. 2) |
| `MapIlluminationDDA` (129) | **Battlefield** — `Environment` |
| `UserSettings` (139) | infrastructure — persistence |
| `AssetManifest` (53) | infrastructure — residency |
| `EventBus` (39) | delete, per above |
| `ValidationUtils` (57) | generic |

A directory named `core` splitting five ways is the vague-name pattern the
blueprint already records, showing up in the tree rather than in the model.

---

## How assets fit

**823 MB, 22,777 files** — and overwhelmingly ROM-derived extracted artifacts:
**9,543 `.json`** and **5,912 `.tga`** account for two thirds of the file count.

| Directory | Size | Goes to |
|---|---|---|
| `maps/` | 258M | **Battlefield** — content shadow |
| `effects/` | 224M | **Effects** — content shadow |
| `sprites/` | 120M | **Sprite Rig** — content shadow |
| `characters/` | 119M | **Sprite Rig** — content shadow |
| `scenarios/` | 79M | **Cutscene** + **Campaign** — content shadow |
| `music/`, `audio/` | 2M | **Audio** — content shadow |
| `abilities/`, `items/`, `jobs/`, `stats/` | 1.9M | **Battle** + **Character Catalogue** — content |
| `roster/` | 40K | **Character Catalogue** — content |
| `ui/`, `fonts/` | 2.5M | **UI** — content shadow |
| **`shaders/`** | **600K, 48 shaders** | **Render — CAPABILITY, not content** |
| **`materials/`** | **24K** | **Render — capability** |
| **`scenes/`** | **140K, 29 `.tscn`** | **host wiring and the root sets** |

### The finding: `src/` and `assets/` do not split along capability and content

Two crossings run the wrong way, and they run in **opposite** directions:

- **`assets/shaders/` is capability living in `assets/`.** Forty-eight shaders
  are `Render`'s implementation — the deliverable itself, not a content shadow.
  *(2026-08-21: **forty-six**. `ot_depth.gdshaderinc` and
  `color_stack.gdshaderinc` — 177 lines — are the GPU halves of shared-kernel
  members and go to `addons/exmateria_schema/` instead, ADR-0139 dec. 7.)*
- **`src/data/AbilityDatabase.gd` is content living in `src/`.** 19,411
  auto-generated lines from `assets/abilities/*.json` — **13.7% of everything
  in `src/`**, and not code anyone wrote.

**Which means "the host's size is the progress bar"
([ADR-0110](adr/0110-systems-extract-outward-into-addons.md)) measures the wrong
thing if it counts `src/` lines.** Counting them today credits the host with
19.7k lines of generated content and omits `Render`'s actual implementation.

The fix is small: the metric counts **hand-written lines by bucket**, not lines
by directory.

**Settled by [ADR-0131](adr/0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md) (#320).** That is the decision, and it went
further: the progress bar is **two counts per system, kept apart and never
divided** — hand-written lines, and boundary reaches that do not go through a
declared interface. Shaders are in (a system whose deliverable is invisible
cannot be measured); generated, content, `tests/` and `tools/` are out, but
still classified — exclusion happens at report time so the no-catch-all property
survives. The blind spot was also bigger than this section knew: `tests/` holds
**601 `.gd` files, 114,022 lines** — more files than `src/`.

---

## Two things settled before the baseline

### The census disagreed with ADR-0110 by 46% — RESOLVED: it is stale, and dated

ADR-0110 states **321 `.gd` files and ~100k lines**. Measured on this branch:
**470 files and 141,831 lines**.

**It is a date, not a scope** ([ADR-0131](adr/0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md), #320). Commit `f8f3041b3`,
**2026-07-12**, measures 321 files / 100,701 lines — an exact match, five weeks
before ADR-0110 was published. `src/` minus `src/effects/` gives 322 / 103,575
and *looks* like a deliberate exclusion, but the July tree matches to the line,
and ADR-0111's per-directory figures (`gpu` 6,540, `debug` 8,569) match that
same tree while today's read 6,907 and 9,265.

The growth is **+41,130 lines**, of which `src/effects/` alone is **+26,258**
(64%) — the Effect Studio landing via PRs #288 and #296.

**The staleness had already produced wrong live figures**, because the same
denominator was reused under current numerators:

| claim | as published | actually |
|---|---|---|
| ADR-0111 dec. 7 — ADR-citation adoption | 95% (306 of 321) | **65.1%** (306 of 470) |
| ADR-0113 — files touching an autoload | 39% (126 of 321) | **27%** (126 of 470) |

Both numerators are current; only the denominator was old. Pass 2's backfill is
therefore ~50% larger than ADR-0111 sized it — **164** files lack a citation,
not 15.

### The Effect Studio is 15.5% of `src/` — and is an assembler

**21,986 lines.** Larger than `UI`. Larger than `Cutscene` and `Campaign`
together. Larger than `Effects` proper, which it authors.

**Resolved, and the answer was a third option: the Effect Studio is an
assembler.** A composition over systems that implements the ports and wires them
together — the same kind of thing the game is. Not a system, not host code.

**Corrected by [ADR-0134](adr/0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
(2026-08-20):** that is true of the *tool*, and it was wrongly extended to the
*directory*. The Effect Studio's assembler is `EffectViewerScene.gd` — **1,321
lines**, already classified separately — and these 21,986 lines are `Effects`,
which is what ADR-0115 dec. 3 requires: nobody uses the effect editor without
`Effects`, the game uses `Effects` with no editor, and the asymmetry alone
decides. So this heading's own observation — *larger than `Effects` proper,
which it authors* — was the clue: an editor and the thing it edits are one
system. `Effects` reads **38,162**, not 16,176.

That also explains what
[ADR-0112](adr/0112-dead-code-is-what-the-root-set-cannot-reach.md) dec. 3
asserts without justifying: two root sets, the ~12 game scenes *and* the
authoring tools. **Each assembler is a root set.** Not a special case for tools.

It remains goal #10's product and the subject of live map
[#262](https://github.com/timbermania/fft-monorepo/issues/262) — but it is no
longer an unplaced 22k lines.

---

## What the audit says about the blueprint

**It calibrates.** Twelve of eighteen directories land on exactly one system,
and the model was built without looking at any of them.

**Its gaps were real, narrow, and all three are now closed.** `Debug` became the
eleventh system, the Effect Studio became an **assembler** — a category the model
was missing — projectiles resolved to `Battle`, and `EventBus` is marked for
deletion. **No boundary had to move.**

**And the two measurement findings matter more than the classification ones.**
Generated content counted as code, and capability filed under assets, both bias
the metric that the whole refactor is steered by.
