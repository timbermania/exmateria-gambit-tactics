# Extraction #1 is `Render`, and the clean five is retired

The extraction order named by [ADR-0110](0110-systems-extract-outward-into-addons.md) —
*"the five vault clusters that map cleanly to systems"* — is **withdrawn**. Its
source is the one reference [ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md)
disqualifies, and four of its five members are not systems. Extraction order is
chosen by **measured isolation**, and the first extraction is **`Render`**.

Status: accepted (2026-08-21). Amends ADR-0110's Consequence and
`docs/agents/refactor-loop.md` → *Extraction order* and *Pass 5*.

## Context

**Measured at `cc19003e4`, `classify_blueprint.py` at `34848f14f`, 2026-08-21:**
470 files / 141,837 lines; 112,787 (79.5%) in a system; `touch_matrix.py` reads
**367 cross-system edges**.

### Where the clean five came from

ADR-0110's Consequence reads: *"The five **vault clusters** that map cleanly to
systems — `Ability Execution`, `Unit`, `Unit Deployment`, `Formation Screen`,
`SFX` — go first, as cheap validation of the model rather than its first hard
test."*

`vault/AI Research Index.md` (on `main`, the vault's root index) links **fifteen
topic clusters**. The five are five of those fifteen. **The extraction order is
the research vault's table of contents**, filtered by one judgement — *maps
cleanly to systems* — whose work is not shown anywhere, and which no document
has ever applied to the other ten.

### Three mechanical problems

**1. The source is disqualified, by an ADR in the same commit.** ADR-0111's
Considered alternatives: *"**Vault clusters as target module boundaries.**
Rejected: bakes the ROM's storage organisation into an engine intended to be
game-agnostic."* ADR-0110 and ADR-0111 were both added in **`447333b87`**
(2026-08-19). The same commit rejects the vault's clusters as boundaries and
adopts five of them as the order.

**2. There was no system roster to map *to*.** ADR-0110 is 2026-08-19;
[ADR-0117](0117-the-blueprints-ten-systems.md), the roster of eleven systems, is
2026-08-**20**. When the phrase *"map cleanly to systems"* was written, the set
on the right-hand side did not exist.

**3. Only one of the five is a system.** `BLUEPRINT.md` → *Calibration: the clean
five* already did this arithmetic, for a different purpose:

| Clean five | Resolves to | A system? |
|---|---|---|
| `Ability Execution` | `Action Resolution` | no — a part of `Battle` |
| `Unit` | `Combatant` + `Body` | no — two parts of `Battle` |
| `Unit Deployment` | `Deployment` | no — a part of `Battle` |
| `Formation Screen` | `UI` over `Character Catalogue` | no — spans two systems |
| `SFX` | `Audio` | **yes** |

ADR-0110 dec. 2 fixes the unit of work: *"One system extraction is one unit of
work."* Under that rule, *"the clean five first"* schedules
**`Battle` + `UI` + `Character Catalogue` + `Audio` = 41,406 lines, 29.2% of the
package** — the second and third largest systems included. That is the opposite
of cheap validation, and it is what the loop's Pass 5 currently instructs.

### What [#331](https://github.com/timbermania/fft-monorepo/issues/331) asked, and what it assumed

The ticket asked whether `Audio` is still first, on the premise that *"the
ordering was chosen from how finished a system looks from the addon side."*
**That premise is wrong.** The ordering was chosen from the vault, and only
`SFX` among the five has a shipped addon at all — the addon-side reading was
never even available for the other four. Its owed-item 2 (*was any other member
picked on the same evidence?*) resolves to: **all five were, and the evidence
was not addon-side.**

## Decision

**1. The clean five is retired as an extraction order.** It survives only where
`BLUEPRINT.md` already uses it — as a **calibration set**, five boundaries known
to be clean, against which the model was tested and which it refined twice. That
use is sound and untouched. Naming a *schedule* is a different act and this ADR
takes it back.

**2. Extraction order is chosen by measured isolation**, per ADR-0118 dec. 5
(*"extraction order is therefore free, chosen by risk and parallelism"*). The
three readings, all from `touch_matrix.py` and `classify_blueprint.py`:

- **size** — hand-written `.gd` lines plus the system's shader lines;
- **inbound concentration** — how many *distinct symbols* carry the inbound
  edges. One symbol is a port; twelve is a surface with no interface;
- **outbound reach into other systems** — edges to `platform`, `schema` and
  `Debug` do not count, being ports, published kernel, and the framework every
  system uses.

Read inbound **by symbol**, never by system count: a system reached 30 times
through one name is more extractable than one reached 11 times through nine.

**3. Extraction #1 is `Render`.** Measured:

| | `Render` | `Character Catalogue` | `Audio` |
|---|---|---|---|
| files / `.gd` lines | 6 / **905** | 14 / 2,046 | 13 / 2,817 (live 8 / 2,180) |
| shader lines | **139** | 0 | 0 |
| inbound edges from systems | 11 | 17 | 14 |
| **distinct inbound symbols** | **4** (10 of 11 are one) | 7 | — |
| outbound edges into systems | **2** | 13 | 3 |

`Render`'s complete boundary, both directions, all 29 edges:

- **In (16): `PSXDisplay` ×10**, plus `DisplayDebugPanel` ×4,
  `ColorTimelineModel` ×1, `ShaderCalibrationPanel` ×1 — the last six are debug
  panels registering with the framework, not an interface anyone calls. By
  source: `UI` 6, `assembler` 5, `Cutscene` 2, `Effects` 1, `Battlefield` 1,
  `Battle` 1.
- **Out (13):** `Tune` ×2 (the `platform` port, ADR-0140 dec. 8) · `TuneField`
  ×4 and `BaseDebugPanel` ×2 (`Debug`) · `Fold` ×2 and `DepthMode` ×1 (the
  shared kernel, ADR-0139) · **`EffectPhase` ×1 and `ScreenData` ×1 — the only
  two edges into another system.**

`FoldSurface.gd` (263) and `EngineFoldCompositor.gd` (208) — the compositor
itself, 471 of the 725 non-debug lines — are **reached by nothing across a
system boundary**. The system is one published name, `PSXDisplay`, over a
compositor nobody outside it touches.

**4. `Render` is not where the shaders land.** Attributing all **6,290** shader
lines under `src/` and `assets/` — **86 files: 70 `.gdshader` (4,304 lines, the
figure #311 raised) plus 16 `.gdshaderinc` (1,986)** — by *which system's `.gd`
files name the file*:

| | files | lines | share |
|---|---|---|---|
| `UI` | 28 | 2,593 | 41.2% |
| `Cutscene` | 14 | 1,346 | 21.4% |
| `Battlefield` | 10 | 589 | 9.4% |
| `Effects` | 6 | 461 | 7.3% |
| `Battle` | 4 | 258 | 4.1% |
| `schema` (the two kernel `.gdshaderinc`) | 2 | 177 | 2.8% |
| **`Render`** | **6** | **139** | **2.2%** |
| `Sprite Rig` | 2 | 121 | 1.9% |
| `assembler` | 1 | 19 | 0.3% |
| reached only from another shader (412) or from nothing (175) | 13 | 587 | 9.3% |

**Corrected 2026-08-21 by [ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)
(prologue pass 4): the 6,290 above is half the shader body.** The glob was
`.gdshader` + `.gdshaderinc`; ten `.glsl` compute stages and two `.glslinc`
headers under `src/gpu/shaders/` add **6,081 lines**, so the real figure is
**101 files / 12,627 lines** and the largest shader owner is **`Battle`** —
6,239 lines, 49.4% — ahead of `UI`'s 3,122 (24.7%). Under exact-path rules the
*"reaches no `.gd` file"* residue goes to zero.

**Dec. 4's conclusion survives its own correction, and it is the half that
mattered:** `Render` reads **258** shader lines, **2.0%** — so `Render`'s size is
still not hiding a shader problem, and the extraction order below is unaffected.
What does not survive is the ranking. Read the paragraph that follows as history.

This **refutes** the standing assumption — carried since #318 and repeated by
#333 and #334 — that the unallocated shader lines land *"mostly on `Render`"*
and that `Render`'s 905 badly understates it. They land mostly on `UI`, which is
already the second-largest system. **It does not settle the split**: the method
is a filename grep over `.gd` sources, it is a *floor* in exactly the way
ADR-0131 says the reach count is, and 587 lines (9.3%) reach no `.gd` file at
all. Pass 5's shader walk still has to do the exact-path ownership rules. What
it settles is that **`Render`'s size is not hiding a shader problem.**

**5. `Audio` goes second, and "cheap validation" is retired with the order it
justified.** [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md)
dec. 5 established that `Audio`'s pass is a **driver split**, not cheap
validation. That is still true and it is still worth doing early — an existing
addon plus a 1,261-line driver is the cleanest available test of the
*driver-split* shape, which `Render` does not exercise. But it validates
machinery, not the blueprint's boundary-drawing, and it should be scheduled as
that rather than as *"the easy one."* **No pass is cheap validation.** #331's
owed-item 3 resolves as: the category does not survive, and the blueprint's
first real test is extraction #1.

**6. `Audio`'s live host figure is 8 files / 2,180 lines**, superseding ADR-0136
dec. 6's 7 / 2,034. The five declined-scene entry points it excludes are
unchanged (`SfxStressTest` 213, `SfxBankTestScene` 131, `FEDSTestScene` 116,
`AttackSfxTestScene` 109, `SMDTestScene` 68 = 637); the difference is
`SpuAudioDebugPanel.gd` (146), booked to `Audio` by
[ADR-0140](0140-debug-is-a-system-and-a-system-logs-itself.md)'s classifier fix.
`EffectSfxEngine.gd` is **57.8%** of the live figure, not 62%.

## Considered alternatives

- **`Character Catalogue` first.** It publishes *character records*, one of the
  six schemas, so extracting it tests ADR-0118's load-bearing claim directly.
  Rejected as #1 on two measurements: its inbound is spread over **seven**
  symbols against `Render`'s effective one, and it reaches **into `Battle` 11
  times** — a store reaching the simulator is backwards, and settling that is a
  boundary question the pass would have to answer before it could start. Strong
  candidate for #3.
- **`Audio` first, as ADR-0110 had it.** Rejected per dec. 5: it is the
  driver-split test, and putting it first spends the calibration slot on a
  system whose addon boundary is already the benchmark everything else is
  measured against.
- **Keep the clean five and re-scope "cheap" to "cheapest available."** Rejected:
  it preserves a schedule that names four things that cannot be extracted, and
  the phrase would then describe `Battle`.
- **Order by size alone.** Rejected: `Effects` is 38,168 lines with only 7
  outbound and 16 inbound edges, and `Campaign` is 2,238 lines with 37 outbound.
  Size and entanglement disagree, and entanglement is what an extraction pays.

## Consequences

- **ADR-0110's Consequence and `refactor-loop.md`'s *Extraction order* and
  *Pass 5* are amended in place**, dated, pointing here. Pass 5's *"the clean
  five systems … go straight to `/to-spec`"* named four non-systems and is
  replaced by the isolation reading.
- **`BLUEPRINT.md` → *Calibration: the clean five* is untouched and stays.** It
  is the one use of the list that was always sound.
- **Nothing here unblocks an extraction.** Pass 6 gates every extraction and is
  gated on [#299](https://github.com/timbermania/fft-monorepo/issues/299); Pass 7
  moves the shared kernel, and `Render` reaches `Fold` and `DepthMode`, so the
  kernel still lands first. This ADR names the queue, it does not start it.
- **Three soft spots, stated rather than found later:**
  1. The shader attribution is a filename grep with a **673-line residue** and
     no exact-path rules. It refutes a claim; it does not replace pass 5's walk.
  2. `native_blend`'s partiality is a live `Render`-shaped defect with no owner
     — ADR-0137 dec. 10 decided its shape, not who does it. It will land on
     extraction #1 whether or not it is scheduled.
  3. `Render`'s six files include **three debug panels (180 lines)** booked to it
     by ADR-0140. They travel with the system, which is correct, but it means
     20% of extraction #1 is debug UI and the reading above should not be
     mistaken for 905 lines of compositor.
- **A defect found in passing and deliberately not fixed here:**
  `classify_blueprint.py` books `src/data/` to `Battle` by a **directory
  catch-all** (24 files / 2,432 lines). Of the ten `*Database.gd` loaders in that
  directory, **three are booked `content` by explicit name and six fall through
  to `Battle`** — the same rule shape whose failure ADR-0140 opens with, and
  `DeploymentZoneDatabase.gd` is booked `Battle` while `BLUEPRINT.md`'s own
  ROM-file table calls the deployment-zone table *content*. So **`Battle`'s
  17,171 is a floor with slack**, which if anything strengthens dec. 1's
  arithmetic. Recorded as fog on
  [#305](https://github.com/timbermania/fft-monorepo/issues/305); fixing it moves
  every number and should not ride in the same commit as a decision that quotes
  them.
