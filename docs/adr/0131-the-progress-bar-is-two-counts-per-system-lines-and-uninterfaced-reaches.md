# The progress bar is two counts per system: lines, and reaches without an interface

Refactor progress is read as **two counts per blueprint system, kept apart and
never divided**: hand-written **lines**, and **boundary reaches that do not go
through a declared interface**. Both are produced by one walk over one
denominator — every line of the package, classified. Extracted systems are
**reported, not vanished**.

Status: accepted (2026-08-20). Amends
[ADR-0110](0110-systems-extract-outward-into-addons.md),
[ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md) and
[ADR-0114](0114-refactor-progress-is-two-per-cluster-numbers.md).

## Context

Pass 6 of [`refactor-loop.md`](../../../docs/agents/refactor-loop.md) takes a
baseline, and the baseline opens a series that runs for months. A wrong first
measurement is the one error the series cannot correct — every later number is
read against it. Deciding *what to count* is therefore not gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299), even though
*taking* the measurement is.

**Two instruments had been fused into one.** `project(code_sha, vault_sha)`
(ADR-0111 dec. 5, built by pass 5) is the metric. `tools/classify_blueprint.py`
is not — its own docstring reads *"Proof instrument for
`docs/BLUEPRINT-AUDIT.md`. Deliberately has NO catch-all."* It proves every file
is placed and exits non-zero when one is not. It was never the baseline.

What the three findings below are all actually about is a **third** thing that
no ADR had ever defined a unit for: ADR-0110's closing Consequence, *"the host's
size is the progress bar."*

**1. It counts generated lines as work.** `src/data/AbilityDatabase.gd` is
**19,411 generated lines — 13.7% of all of `src/`**, and 16x the entire
`Character Catalogue` bucket (1,219).

**2. The census was five weeks stale, and the staleness had already produced a
wrong live figure.** ADR-0110 states *"321 `.gd` files and ~100k lines"*. That
is commit `f8f3041b3`, **2026-07-12**: 321 files, 100,701 lines — an exact
match. ADR-0110 was published 2026-08-19, when the tree measured **470 files,
141,831 lines**. The *same sentence* carries a current figure: 624 `.tscn` was
first reached 2026-08-14 (on 2026-07-12 it was 269). A third, `24 autoloads`,
matches neither date — 23 in July, 26 at publication. Only `17 top-level
directories` is invariant. The sentence splices censuses five weeks apart.

The consequence is not cosmetic. ADR-0111 dec. 7 claims *"95% adoption (306 of
321 `src/` files)"*. **306 is the current count** — re-measured on this branch,
306 of 470 files carry an `ADR-NNNN` citation. At the 2026-07-12 tree it was
**149** of 321. So a current numerator sits on a five-week-old denominator, and
the true adoption is **65.1%**, not 95%. Pass 2's backfill is sized off that
number.

The growth between the two dates is **+41,130 lines**, of which `src/effects/`
alone is **+26,258** (64%) — the Effect Studio landing via PRs #288 and #296,
the same body #299 is still adding ~34k to.

**3. The walk cannot see most of the package.** `classify_blueprint.py` globs
`src/**/*.gd` only. Measured on this branch:

| tree | files | lines | seen? |
|---|---:|---:|---|
| `src/**/*.gd` | 470 | 141,831 | yes |
| `tests/**/*.gd` | 601 | 114,022 | no |
| `tools/**/*.py` | 242 | 51,303 | no |
| shaders (`src/gpu`, `src/ui3`, `assets/shaders`) | 194 | 12,597 | no |
| `tools/**/*.gd` | 73 | 8,873 | no |
| `assets/**/*.json` | 77 | 1,114,028 | no |

`tests/` holds **more `.gd` files than `src/` does**. The shaders matter for a
different reason: BLUEPRINT §10 calls them `Render`'s deliverable, and `Render`
reads **1.2%** — the smallest bucket in the repo — because none of them are
counted.

**ADR-0114's denominator has a hole that widens.** Its two numbers are per
**ballast cluster**, and a cluster with thin ballast must *"report as
unobserved"*. ADR-0111's own Consequences price it: *"Roughly 30k of ~100k lines
sit in directories with ≤4 citations"*, and *"the blind spot grows as the
project succeeds. Every line written for the superset (#6) or for authoring
(#10) has no note to attach to."* `gpu` carries 2 citations for 6,907 lines;
`strategy` carries 0.

## Decision

**1. Two counts per system, kept apart, never divided.**

- **Lines** — hand-written lines owned by that system.
- **Uninterfaced reaches** — boundary crossings that do not pass through a
  declared interface.

Kept apart for ADR-0114 dec. 1's reason, which is unchanged: collapsed, a bad
reading says only that something got worse. They can also move in opposite
directions — every crossing can be cleaned with nothing extracted, and 20k lines
can move into an addon that still reaches back through five autoloads.

**No ratio.** *Uninterfaced reaches ÷ lines* would fall whenever a system grows
internally, reporting improvement where nothing about the coupling changed.

**2. The denominator is systems, not ballast clusters** — amending ADR-0114
dec. 1 and dec. 2. Every line lands in exactly one blueprint bucket by
construction, which `classify_blueprint.py` already guarantees (0 unclassified,
exit 0). Coverage is total on the day it is taken and does not decay as the
package grows, which is the property the cluster denominator cannot hold.
ADR-0114 dec. 2's *unobserved* rule survives for ballast-derived readings; it no
longer applies to the progress bar.

**3. A line is hand-written `.gd` or shader source under `src/` and `assets/`.**

Excluded, with reasons that are not interchangeable:

- **Generated** (`AbilityDatabase.gd`) — not work. Left in, it swamps small
  systems and moves when the extractor is re-run.
- **Content tables** (872 lines) — data, and per ADR-0110 it stays in the host
  by design, so it can never register as progress.
- **`tests/`** — tests migrate with their system (`refactor-loop.md` pass 6:
  *"a system's tests migrate to bind that addon's public interface"*), and that
  migration is verified at pass 7. Counting them adds 114k lines that move for
  free.
- **`tools/`** — the instrument measuring the subject is not the subject.

Shaders are **in**: a system whose deliverable is invisible to the instrument
cannot be measured. They carry the same file-level ownership problem `src/` had
— `assets/shaders/` splits by system exactly as `src/effects/` did
([ADR-0129](0129-the-fold-is-renders-and-a-producer-keeps-its-shader.md)
dec. 10) — so extending the walk requires the same exact-path rules ADR-0129
dec. 11 added, not a directory rule.

**4. Exclusion happens at report time, never at walk time.** Every file is still
classified, and the no-catch-all property with its non-zero exit is preserved. A
generated file must be *recognised as generated*; dropping it from the walk
turns it back into the blind spot this ADR exists to close.

**5. Uninterfaced reaches are counted per line, not per file-edge.**
`tools/touch_matrix.py` today records one edge per (file, target, kind) —
a file reaching `Battle` fifty times counts once. The baseline needs the line, so
the conversion is an **instrument change that lands before pass 6**, not after.

Its four shapes are unchanged: `class_name`, autoload, `preload`, `/root/`
lookup. An injected port is none of them, which is the property that makes the
count meaningful — as its docstring puts it, *"there are no ports in `src/`."*
**The baseline therefore opens at 354 uninterfaced reaches and 0 clean
crossings**, and can only improve.

**Amended by [ADR-0134](0134-the-studio-is-an-assembler-and-the-assembler-is-one-file.md)
(2026-08-20):** the opening reading is **360**, not 354. `touch_matrix.py` reuses
`classify_blueprint.py` as ground truth, and ADR-0134 dec. 3–4 rebooked
`src/effects/studio/` from `assembler` to `Effects`, exposing **+6** edges that
were previously inside an unclassified bucket. `Effects` reads **38,162** lines,
not 16,176. Measured both ways before the change landed — the instrument moved,
not the code.

**Amended again by [ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
(2026-08-21):** the opening reading is **358**, not 360. ADR-0135 dec. 9–10
rebooked `AllTemplatesSeeder.gd` out of `assembler` into `Character Catalogue`
and three `*Boot.gd` wiring files out of `UI` into `assembler`, netting **-2**
cross-system edges — `assembler` is not a system, so edges through it do not
count. Measured both ways: 360 on the pre-change classifier, 358 after. The
total stayed 470 files / 141,831 lines, as a pure rebooking must. **Third
amendment in three sessions: the baseline moves whenever a classifier rule
does, and pass 6 has still not read it.**

**Amended a fourth time by [ADR-0138](0138-a-publish-does-not-imply-an-assembler.md)
(2026-08-21):** the opening reading is **316**, not 358 — a **−42** step, and the
first one **downward**. ADR-0138 dec. 5 books `Fold.gd`, `DepthMode.gd`,
`ColorStack.gd` and `ColorRecipe.gd` out of `Render` into a new `schema` bucket
(ADR-0121 dec. 5's shared kernel), so 42 edges stop being system↔system and
become system→shared-kernel. `Render` reads **5 files / 869 lines**, not 9 /
1,755; `schema` reads 4 / 886; the total stayed **470 files / 141,837 lines**, as
a pure rebooking must. Measured both ways on trunk `1a435a142`.

**Amended a fifth time by [ADR-0144](0144-the-instruments-see-the-shaders-the-assets-and-the-closure.md)
(2026-08-21), which is prologue pass 4 — the pass this ADR schedules instrument
changes into, so this is the amendment that CLOSES the series.** The opening
reading is **1,143 uninterfaced reaches in LINES**, the unit dec. 5 asks for, over
**635 files / 190,408 lines**. In the old file-edge unit it is 350, and the change
decomposes: 400 published → **342** with only the classifier moved → 350 with the
instrument moved too.

Three things in this ADR were wrong and are corrected there. **Dec. 3's shader
scope was under-read by half** — "shader source" is four extensions, not two, and
the twelve `.glsl`/`.glslinc` files under `src/gpu/shaders/` are 6,081 lines that
neither this ADR's successor censuses nor ADR-0141 dec. 4 could see. (The *"194
files, 12,597 lines"* in the Context table above is the **right** body; the file
count included `.uid`/`.import` sidecars, and the later, narrower glob is what
drifted.) **Dec. 5's "four shapes are unchanged" becomes five**: `#include`, or
the newly-walked shader lines would contribute zero crossings. And **dec. 4's
report-time exclusion is now actually implemented** — `generated` and `content`
are classified, printed, and only then subtracted, on a `BASELINE` line.

**This is dec. 6's warning arriving in the worst form.** Three sessions were
told a *rising* count can mean an improving boundary; this is a **12% fall
produced by nobody touching any code**. A reading is only meaningful against a
**stated commit AND a stated classifier revision** — quote both or quote
neither. Fourth amendment in four sessions, and pass 6 has still not read it.

**6. The reach count is a FLOOR, and is reported as one.** `touch_matrix.py`
cannot see duck-typed reaches, which carry no type name — `EngineFoldCompositor`'s
`_pool.call("get_active_effect_buckets")` was invisible to it *and* to the
classifier (ADR-0129). A clean column is not proof of a clean boundary, and a
falling count is not automatically progress: it is also what a growing blind
spot looks like. Every report states the floor.

**7. Extracted systems are reported, not vanished.** Host lines and extracted
lines are both published, so the pair stays roughly constant across an
extraction. Under a host-only count, deleting 15k lines and extracting 15k lines
produce the identical reading, and the failure the metric most needs to catch —
a system "extracted" by deletion — is exactly the one it cannot see.

Today the set is one system: `exmateria_sound`, **15,953 lines** across 152
`.gd` files.

**8. Extracted lines are read from the canonical package, not from the host's
copy.** `exmateria-sound/addons/exmateria_sound/` is tracked and authoritative.
`godot-learning/addons/exmateria_sound/` is a gitignored **copy** (`.gitignore:3`),
not a symlink, and it has **drifted 24 lines behind** across `play_sound.gd`,
`effect_sound_controller.gd` and `smd_opcodes.gd`. Reading the host's copy would
feed copy drift into a longitudinal series.

**9. `project()` remains the metric; the progress bar is inventory.** ADR-0114
dec. 7 already holds the slot — *"Inventory is tracked alongside, not folded in.
Gaps, residue, autoload fan-in and ADR conformance are counts, not quality."* A
line count is a count. ADR-0110's *"the host's size is the progress bar"*
promoted an inventory number to the metric, and that is the error being
corrected.

## Considered alternatives

- **Leave ADR-0110's sentence as a figure of speech.** Rejected: three separate
  findings arrived independently as complaints about it, which is what a real
  instrument nobody specified looks like. An undefined number still gets quoted.

- **Make `classify_blueprint.py` the baseline instrument.** Rejected on its own
  docstring. Fusing the audit prover to the series would mean every future
  ownership correction — and ADR-0129 dec. 11 has already made eight — reads as
  a step change in the metric, which is the failure pass 2 exists to prevent.

- **Explain ADR-0110's `321 / ~100k` rather than amend it.** Rejected: it is not
  a scope difference. `src/` minus `src/effects/` gives 322 / 103,575, close
  enough to look like an exclusion — but the 2026-07-12 tree gives 321 / 100,701
  exactly, and the ADR-0111 per-directory figures (`gpu` 6,540, `debug` 8,569)
  match that same tree to the line while today's read 6,907 and 9,265. It is a
  date, not a scope.

- **Include `tests/`, on the grounds that a system leaving without its tests has
  not really left.** Rejected, but narrowly: the property is real and worth
  keeping, and it is kept — `refactor-loop.md` pass 6 requires the migration and
  pass 7 checks it. It is verified rather than measured.

- **A single "percent extracted" figure.** Rejected for ADR-0114 dec. 1's
  reason, and for a second one: the denominator would have to be the final size
  of a host nobody has measured yet, so the number would be re-based every time
  the estimate moved.

## Consequences

- **`tools/touch_matrix.py` must be converted to per-line before pass 6**, and
  the walk extended to shaders under `src/` and `assets/` with exact-path
  ownership rules. Both are instrument work belonging to pass 5, not to this
  map.

- **Pass 2's backfill is ~50% larger than ADR-0111 sized it.** Real adoption is
  65.1%, so 164 `src/` files lack a citation, not 15. `refactor-loop.md` sizes
  pass 2 at *"~359 files"* and that figure is stale in the same way.

- **The baseline's opening reading is fixed and unflattering**: 358 (was 360,
  was 354 — see the amendments above) uninterfaced
  reaches, 0 clean crossings, and a host of which 13.7% is one generated file.
  That is the point — a series that opens on a flattering number has nowhere
  honest to go.

- **Every census figure in an ADR now needs a date.** Two ADRs published the
  same day carried a five-week-old count, and one of them turned it into a live
  percentage. The convention: a measured figure states the commit or the date it
  was taken on.

- **`Render` stops reading as the smallest system.** Its 1.2% is an artifact of
  a walk that cannot see the thing BLUEPRINT §10 calls its deliverable. What it
  reads once shaders are counted is not predicted here; it is measured at pass 6.
