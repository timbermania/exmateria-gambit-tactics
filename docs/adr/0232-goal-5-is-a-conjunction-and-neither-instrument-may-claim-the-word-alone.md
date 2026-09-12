# Goal #5 is a conjunction and neither instrument may claim the word alone

[ADR-0229](0229-the-sprite-rig-reads-isolated-on-every-static-instrument-and-does-not-compile.md)
built the fifth stranger rig and it printed **goal #5 UNMET** for `exmateria_sprite_rig`, naming
two files. On the same tree, on the same day, `docs/GOALS.tsv` scored **`Sprite Rig` goal #5
`met`**, evidence *"0 cross-system reach lines leave the addon"*. Both instruments run in the
suite. Both are green. **Nothing joins them**, and
[ADR-0228](0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md)'s
ratchet went on asserting `Sprite Rig 6 met, 4 open` with the addon uncompilable outside this game.

This is the two-registers-no-join shape ADR-0229 dec. 8 filed on the *other* pair — rigs versus
walk roots — reappearing on a pair that matters more, because this one decides a number in the
refactor's own scorecard.

Status: accepted (2026-09-05). Builds
[ADR-0229](0229-the-sprite-rig-reads-isolated-on-every-static-instrument-and-does-not-compile.md)
dec. 8, which filed the missing join deliberately rather than guessing at it.
[ADR-0202](0202-installable-is-the-fork-plus-the-kernel-and-the-port.md) dec. 1 is the
precedent for how this repo settles a word owned by two instruments. Reads
[ADR-0223](0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md) one
level up. Tickets: [#847](https://github.com/timbermania/fft-monorepo/issues/847) (paid here),
[#848](https://github.com/timbermania/fft-monorepo/issues/848) (paid at
[ADR-0234](0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md); the
*"ordered behind [#583](https://github.com/timbermania/fft-monorepo/issues/583)"* this line used to
carry was false — `ExMateriaPlatform.DisplayPort` absorbs the autoload's spelling at its own node
path inside `exmateria_platform`, so paying #848 first deleted the row rather than moving its
signature text).

## Context

### Neither number was wrong

`tools/score_goals.py` scored goal #5 as `cross_system(outbound_reaches(rel, system))` and got 0.
`tests/stranger/exmateria_sprite_rig/` staged the addon into a project that did nothing for it and
watched it fail to compile. Both readings are correct. They are answers to two different
questions, and the charter's sentence contains both:

> a system could ship to another tactics RPG with its interface intact

*Interface intact* is the reach count — does this addon **name** another system. *Could ship* is
the rig — does it **come up**. An addon can name nothing and still not start, which is exactly
what `exmateria_sprite_rig` did.

### The hypothesis in the handoff was right about the outcome and wrong about the mechanism

The handoff proposed that `src/core/Tune.gd` classifies as the `platform` **tier** rather than a
system, so the reach never reaches goal #5. Verified with the function rather than by reading
`record()`, and the answer is sharper than the guess:

```
Reach(rel='addons/exmateria_sprite_rig/layers/SpriteLayerManager.gd',
      kind='autoload', target='Tune', dst='platform',
      dst_path='src/core/Tune.gd', lines=[121, 811])
```

`outbound_reaches()` **does** return it — its own docstring said `Tune` "does not appear here",
and that sentence was false and has been corrected. It is `cross_system()` that drops the row,
because `platform` is not one of the eleven systems.

That distinction is load-bearing, and the old wording hid it. `cross_system()` defends its filter
with *reaching the port is exactly what a portable addon is ALLOWED to do* (ADR-0139 dec. 12,
ADR-0140 dec. 9). **That defence does not cover this row.** `src/core/Tune.gd` is a HOST file. The
bucket said port; the address said host. ADR-0223 found precisely this and fixed it for
`check_addon_portability` arm 7 — goal #5 was the reader it did not reach.

## Measurement

### The boundary question, tree-wide

`Reach.dst_path` against every addon root — *does this target resolve outside every addon root* —
measured over all seven roots, before and after #847 was paid:

| | rows | lines |
|---|---|---|
| before #847 | 1 (`SpriteLayerManager.gd` → `src/core/Tune.gd`) | 2 |
| after #847 | 0 | 0 |

Every other addon reads 0 in both states. So widening `check_addon_portability`'s `_ARM7_KINDS`
from `{"class_name"}` to include `autoload` would be a zero-cost ratchet today — and it **cannot**
catch #848, because `PSXDisplay.gd` lives inside `addons/exmateria_platform`, an addon root. The
boundary question is not the missing instrument; the rig is.

### The rigs and the roots are 1:1, and two of the rigs are not in this directory

| addon root | rig |
|---|---|
| `addons/exmateria_battlefield` | `tests/stranger/exmateria_battlefield/run.sh` |
| `addons/exmateria_platform` | `tests/stranger/exmateria_platform/run.sh` |
| `addons/exmateria_render` | `tests/stranger/exmateria_render/run.sh` |
| `addons/exmateria_schema` | `tests/stranger/exmateria_schema/run.sh` |
| `addons/exmateria_sprite_rig` | `tests/stranger/exmateria_sprite_rig/run.sh` |
| `../exmateria-sound/addons/exmateria_sound` | `../exmateria-sound/workspace/acceptance/stranger_sound/run.sh` |
| `../exmateria-sound/addons/exmateria_spu` | `../exmateria-sound/workspace/acceptance/stranger_spu/run.sh` |

Seven roots, seven rigs, no gaps — which is why nothing is `unscorable` for want of a rig today,
and why ADR-0229 dec. 8's "what does a rig-less addon mean" can be answered as a rule rather than
as a special case.

**`Audio` is scored twice** — once per extracted root — and neither of its rigs declares a
`known_failures.tsv`, so this change does not move `Audio`. That was checked before the code was
written, because a naive lookup that knew only about `tests/stranger/` would have flipped both
`Audio` rows from `met` to `unscorable` on a register gap rather than on a finding.

## Decision

1. **Goal #5 is a conjunction: a BUDGET half and an INSTALL half.** The budget half is the
   cross-system reach count, unchanged and still filtered by `cross_system()` — that filter is a
   burn-down whose numbers may not move for a scanner change (ADR-0205 dec. 7). The install half
   is the stranger rig's declared debt. `met` requires both; `open` needs either.

2. **`_walk_roots.RIGS` is the join, and it checks three directions.** A declared `run.sh` that
   does not exist raises (the `extracted_roots()` rule). An addon root with no row raises. A
   `tests/stranger/*/run.sh` that no row names raises — that last arm is the DIFF between this
   declaration and `_runner_tests.stranger_rigs()`' glob, and it is the arm that would have caught
   the fifth rig landing while `README.md` still said *"All four"*.

3. **A root with no rig scores `unscorable`, not `met`.** This closes ADR-0229 dec. 8 using the
   charter's existing sixth state rather than inventing one. A reach count of 0 on an addon nobody
   has tried to install is a budget reading; reading it as a clean bill is ADR-0148's defect —
   green because it no longer looks — in the one goal that is about leaving.

4. **The two `Audio` rigs are DECLARED where they live, not relocated.** `_walk_roots.EXTRACTED`
   is the precedent: when `Audio` left the walk this repo declared the second home with its reason
   instead of moving the source back. Measured reasons, all five of them live: those rigs require
   **stock Godot** and refuse to fall back to the game's 4.8 fork, because the claim they buy is
   the opposite one; they need `publish/publish.sh exmateria-sound stage` **and** a scons-built
   native library, and exit 2 without them, while the suite's final phase treats a non-zero rig as
   a FAIL; they compute their paths by walking up from their own location; they carry their own
   `shared/`, which is not `tests/stranger/shared/`'s four-arm contract; and `stranger_rigs()`
   keys a rig by **directory name = addon name**, which `stranger_sound`/`stranger_spu` are not.
   `exmateria-sound/` is also deliberately outside the walk — walking it turns
   `check_no_env_vars.py` red — and `run.sh` reads `GODOT_STOCK` from the environment.

5. **`Rig.in_suite` is reported, never assumed.** The two `Audio` rigs are not run by
   `run_tests_parallel.py`, so a reading that said "no declared debt" without saying "and nothing
   ran it here" would be reporting a file as though it were a run. The scorecard reads
   DECLARATIONS — that is true of every goal here — and it now says so where it is not also true
   that something ran.

6. **Neither instrument says `goal #5` alone any more.** `stranger_install.gd`,
   `stranger_burn_down.gd` and `rig.sh` say **goal #5's INSTALL half**, and each names
   `tools/score_goals.py` as the holder of the join. A rig claiming the whole word is the same
   defect from the other end. This is ADR-0202 dec. 1's shape applied to the goal that owns both
   terms rather than to one of them:

   > `isolated` and `installable` are different terms, and this ADR owns only the second. [...]
   > Neither term subsumes the other and neither may be reported as the other.

   Goal #5 is the row that reports both, so it is the row that must hold the conjunction — and
   until now it reported the first as though it were the pair.

7. **`Sprite Rig` goal #5 reads `open`,** and `docs/GOALS.tsv`'s evidence column carries both
   halves with the budget half's four-instrument reading preserved verbatim, so the row records
   what was already bought rather than erasing it.

8. **`outbound_reaches()`'s docstring is corrected.** It claimed `Tune` and the shared kernel "do
   not appear" in its output. They do; `cross_system()` drops them. A false sentence in the
   docstring of the function the goal is scored from is how the mechanism went unverified for two
   sessions — the handoff had to mark its own hypothesis UNVERIFIED because reading the source was
   the only instrument anyone had reached for.

## Consequences

- `Sprite Rig` scored **5 met / 5 open / 0 n/a** on the day this ADR landed, down from 6/4, and
  **returned to 6/4 the next day** when [#848](https://github.com/timbermania/fft-monorepo/issues/848)
  was paid and its `known_failures.tsv` row deleted —
  [ADR-0234](0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md). That
  is this ADR's join working rather than a number wobbling: the budget half read 0 throughout and
  the install half is what moved, in both directions, and `stranger_burn_down.gd` forces the second
  move because it reds when a listed file compiles. ADR-0228's dec. 1 count now states the whole
  trip in its own body; its measurement was correct for the instrument that existed when it was
  taken.
- `check_addon_portability` arm 2's *"there is no standalone project to parse against yet"* is now
  false — the rig is that project. ADR-0229 dec. 7 deliberately left the wording alone; that
  deferral is discharged separately, because arm 2 still exits 0 and rewording it is not this
  ADR's subject.
- **`tools/test_score_goals.py` had never run**, and this ADR is what found it. `run_all_tests.sh`
  names each `tools/test_*.py` explicitly with no discovery loop, and that file was not among the
  24 it named — so ADR-0228 dec. 5's 11 seeds had been inert since they landed. Registered here,
  which is the third firing of that script's own rule, *"A guard the suite does not list is a
  guard nobody runs"*, after ADR-0175's arms 3 and 4 and ADR-0003 dec. 7 before it. The census
  behind it — **64 of 88** `tools/test_*.py` invoked by nothing — is filed as
  [#876](https://github.com/timbermania/fft-monorepo/issues/876) rather than fixed here: most look
  ROM-gated, and the point of that issue is that the exclusion is an ABSENCE rather than a
  declaration.

## Considered alternatives

- **Move the two `Audio` rigs into `tests/stranger/`** — for locality, and a single uniform rig
  register. Rejected on the five measured couplings in dec. 4. The locality that was actually
  wanted is of the REGISTER, which dec. 2 delivers without moving a file; the physical move is a
  contract migration for those rigs, not a rename, and doing it as a side effect of this change
  would have put two rigs that need a staged publish and a native build into the suite's final
  phase, where they would exit 2 on any checkout that had not run both. Filed with all six
  couplings and the three decisions it needs as
  [#875](https://github.com/timbermania/fft-monorepo/issues/875) -- an improvement, not a debt,
  because dec. 2's register is two-directional either way.
- **Leave goal #5 as the reach count and give the rig its own scorecard row.** Rejected: the
  charter's sentence is a conjunction already, and an eleventh goal is a charter amendment. The
  numbering is an interface — append, never renumber — and appending here to avoid a definition is
  the expensive way to say the definition out loud.
- **A standalone guard that reds when a rig's `known_failures.tsv` is non-empty while that
  system's goal #5 reads `met`.** This was the shape the handoff proposed and the one first
  approved. Rejected during the build, on a collision found before writing it: such a guard is
  permanently RED until #848 lands, and a guard that is red on trunk aborts every branch's
  preflight — the exact pathology open as [#871](https://github.com/timbermania/fft-monorepo/issues/871)
  at the time of writing. Housing the join **inside** `mechanical(5)` buys the identical claim and
  lands green, because the scorecard's own two-armed ratchet already fails in both directions:
  `GOALS.tsv` may not read `met` when the code says `open`, and may not read `open` when the code
  says `met`.
- **Widen `check_addon_portability`'s `_ARM7_KINDS` to include `autoload`.** Kept as a possible
  future ratchet — it is zero-cost today — but rejected as an ANSWER, because it cannot see #848
  at all: `PSXDisplay.gd` is inside an addon root, so the boundary question returns nothing for it.
