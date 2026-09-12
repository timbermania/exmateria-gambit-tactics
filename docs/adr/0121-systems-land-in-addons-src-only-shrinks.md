# Systems land in `addons/`; `src/` is never reorganised, only shrunk

Each extracted system becomes `godot-learning/addons/<system>/`. **`src/` is
never restructured into per-system folders** — it shrinks as systems leave and
converges on the FFT content pack plus its wiring. Old code is not deprecated; it
becomes unreachable and the closure deletes it.

Status: accepted (2026-08-20).

## Context

The intuitive move at the start of a large refactor is to reorganise `src/` into
one folder per system, then lift the folders out. It looks like progress and
produces a large, satisfying diff.

It is also precisely the shape
[ADR-0110](0110-systems-extract-outward-into-addons.md) rejects: *"never yields
the greenfield slate goal #1 asks for — every decision is negotiated against what
is already there."* A reorganisation commit moves every file, produces no addon,
and leaves the ambient autoloads exactly where they were.

Three practical questions have to be answered before the first extraction, and
none is answered by ADR-0110:

- **Where the schemas live.** They are the prerequisite
  ([ADR-0118](0118-payloads-are-schemas-services-are-ports.md)) and they cannot
  sit inside a system, because the point is that consumers depend on the schema
  and not on the producer.
- **How two implementations coexist.** ADR-0112 authors an **analog** rather than
  moving code, so during an extraction the original and its replacement are both
  present. `src/` declares **337 `class_name`s**, and Godot's `class_name`
  registry is global.
  > **Amended by [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md)
  > (2026-08-22): ADR-0112 does not say this**, and the coexistence it describes has never
  > occurred. ADR-0110 dec. 1 lifts; a `git mv` keeps one copy throughout and no
  > `class_name` collides. **Decisions 3 and 4 below therefore remain valid and are
  > UNEXERCISED** — they are the rule for an extraction that genuinely rewrites, which
  > extraction #1 was not. The first one that does owes them their first run and should say
  > so: a decision that has never executed is a design, not a mechanism.
- **Whether a system becomes its own package.** `exmateria_sound` lives in
  `exmateria-sound/`, which is a finished system's home rather than an extraction's.

## Decision

**1. `godot-learning/addons/<system>/`.** The precedent is already in the tree:
`godot-learning/addons/exmateria_sound/` is `Audio`, landed. Godot resolves it
natively, and the host stays bootable at every commit (ADR-0110 dec. 1).

**2. `src/` is never reorganised.** No per-system folders, no preparatory move
commits. It only ever gets smaller, which is what makes ADR-0110's *"the host's
size is the progress bar"* a real measurement rather than a slogan —
`tools/classify_blueprint.py` reports the remaining slice per system.

**3. Old code dies by closure, not by deprecation.** Nothing is marked
deprecated. When an analog is reachable from the root set and the original is
not, the original is dead by construction (ADR-0112) and is deleted. Mechanical
rather than a discipline, and it fails in the safe direction — being wrong leaves
a file lingering, not a feature missing.

**4. During an overlap, the original drops its `class_name` first.** Two
declarations of one `class_name` cannot coexist. The original becomes
preload-only and the analog takes the name. Renaming the *analog* instead is
rejected: a temporary name has to be un-renamed later, in the commit where
attention is lowest. Dropping the original's `class_name` also makes its
remaining callers visible, since each must switch to a preload to keep compiling.

**5. The six published schemas get one shared addon, built before any
extraction.** It is a **shared kernel**, so DDD's standing advice applies —
keep it smallest, and let nothing in that is not a payload crossing a boundary.
Ports are *not* in it: a port is declared by the system that requires it.

> **Completed by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
> (2026-08-21).** The addon is **`godot-learning/addons/exmateria_schema/`**,
> built in a **seventh prologue pass, immediately after the baseline** — not
> before it, or the largest relocation in the plan is invisible in the reading
> the whole loop is measured against. Six members, **1,063 lines**: the four
> `.gd` files ADR-0138 dec. 5 named, plus `psx_ot_depth.gdshaderinc` and
> `psx_color_stack.gdshaderinc`, which are their GPU halves (dec. 7). The
> admission test is **membership in a named schema on ADR-0118 dec. 1's table** —
> so adding a member means adding a schema first — backed by two mechanical
> vetoes: **zero outbound edges** into any system, and **never an autoload**. And
> the schemas are **seven**, not six (ADR-0139 dec. 14).

**6. Capability follows its system out of `assets/`.** `assets/shaders/` — 48
shaders, 4,106 lines — is `Render`'s deliverable, not a content shadow, and moves
into its addon. Content shadows stay. `src/` and `assets/` do not split along
capability and content, so neither directory is a proxy for either.

> **Amended by [ADR-0139](0139-the-shared-kernel-is-enumerated-by-the-schema-list.md)
> dec. 7 (2026-08-21): two of the 48 do not go to `Render`.**
> `psx_ot_depth.gdshaderinc` (90 lines) re-declares **every** `DepthMode`
> calibration constant as a uniform default and re-implements `ot_depth`;
> `psx_color_stack.gdshaderinc` (87) declares exactly the four uniform arrays
> `ColorStack` packs. Each is one encoding in two languages, so each moves into
> the shared kernel with its `.gd` half — splitting a codec across two addons
> makes drift invisible in the one place `ColorStackGpuParityTest` catches it.
> Their guards (`tools/check_depth_shaders.py`, `tools/check_color_shaders.py`)
> travel with them. The other 46, `psx_par` / `psx_dither` / `psx_screen_blend`
> included, are `Render`'s exactly as written here: shared implementation with no
> CPU counterpart is a technique, not a crossing.

**7. Promotion to its own package happens at release, not at extraction.** A
system stays in `godot-learning/addons/` until something outside this repo
consumes it, at which point it moves to its own package as `exmateria_sound`
did. Splitting packages earlier pays cross-package plumbing before there is a
consumer to justify it.

## Considered alternatives

- **Reorganise `src/` into per-system folders first.** Rejected: ADR-0110's
  in-place transformation with extra steps. Moves every file, produces no addon,
  dislodges no autoload, and buries the real extraction diffs under a rename
  storm.
- **Extract each system straight to its own top-level package.** Rejected for
  now under dec. 7 — correct eventually, expensive immediately, and reversible
  in the cheap direction.
- **Give each schema its own micro-addon.** Rejected: six addons whose combined
  contents are smaller than one system, and a version matrix between them.
- **Rename the analog during overlap** rather than the original. Rejected under
  dec. 4 — it defers work to the least attentive moment.
- **Mark superseded code `@deprecated`.** Rejected: a marker is a claim, and the
  closure is a proof. ADR-0112 already supplies the proof.

## Consequences

- **The first work is not an extraction.** It is the schema addon, because
  everything else is written against it (ADR-0118).
- Every extraction is a **small `src/` deletion plus a new addon**, never a move.
  Diffs stay readable and per-system code review (ADR-0110 dec. 2) stays viable.
- **`godot --path . --import` will be run constantly.** Every `class_name`
  change under dec. 4 invalidates the global class cache, and `godot-learning/CLAUDE.md`
  already records that `--editor --quit-after N` does not rebuild it.
- Nothing in `src/` needs to be tidy for extraction to start. Its shape is
  irrelevant to a process that only deletes from it.
