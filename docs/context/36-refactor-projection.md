# Refactor projection

The vocabulary of the outward-extraction refactor (ADR-0110) and of the
longitudinal measurement that keeps it from drifting (ADR-0111, ADR-0114).
Distinguishes the three references the refactor reasons against — the code
being changed, the research anchoring it, and the intended architecture — so
that none is mistaken for another.

#### The ten goals

The refactor's charter. ADRs and `docs/agents/refactor-loop.md` cite these by
number (`goal #6`), so **the numbering is an interface — append, never renumber.**

1. **A greenfield slate** — decisions made on their merits, not negotiated
   against what is already there.
2. **Renaming carries a translation table** — old term → new, where it helps a
   reader who knows the old vocabulary. The machine half of this is solved
   separately (ADR-0111 dec. 7: code cites its vault note in a comment, which
   survives any rename); this is the human half.
3. **Remove dead code** — what the declared root set cannot reach (ADR-0112).
4. **Catch drift cheaply and continuously**, while the context that produced it
   is still warm.
5. **Portable systems** — a system could ship to another tactics RPG with its
   interface intact.
6. **Assets as a superset**, not a ROM transcription.
7. **No PSX/FFT jargon** in engine vocabulary.
8. **PSX compromises divorced**, each recorded as a known drop with its reason
   and the ADR that authorised it (ADR-0112).
9. **Improve the architecture as we go** — the refactor is not only relocation.
10. **Eventual support for authoring content** — authoring is a product of this
    effort, not scaffolding (which is why the authoring tools are a root set,
    ADR-0112 dec. 3).

Goals 1, 4, 5, 6, 7, 8 and 10 are quoted from the ADRs that cite them; 2, 3 and
9 were recovered from the author on 2026-08-19, when the sweep found the list had
never been written down. **They are scored per extraction at loop pass 9
into `docs/GOALS.tsv`, by `tools/score_goals.py`** (ADR-0149) — five have a
mechanical test, five carry a citation that has to resolve, and the guard reds
when the register and the code disagree in either direction.

**Not every goal is per-system.** #6 and #10 are **per-domain**: a system that
owns no ROM-derived asset format cannot exercise #6, and one that ships no root
scene cannot exercise #10, so they score `n/a` *with a reason* rather than
failing. #8 **splits** — the code half is per-system, the register half is the
known-drops register at epilogue E1. So a system's achievable score is usually
less than ten and is stated at pass 1; `Render`'s is **8**.

> **`Audio`'s achievable score is 9, and `n/a` is available for only one of the
> two per-domain goals** (recorded at extraction #2's pass 9). #10 is `n/a` on
> `Render`'s grounds — the package ships none of the eleven root scenes, and the
> FEDS/SFX authoring surface is `Effects`-booked in the host. **#6 is not.**
> `Render` scored it `n/a` because it *owns no ROM-derived format*; `Audio` owns
> three — SMD, FEDS and WAVESET (ADR-0142) — so the per-domain escape is closed
> and the goal has to be answered. It is `open`.
>
> **A sixth state exists and `Audio` is the first to use it: `unscorable`.** Goal
> #3's test reads `docs/RESIDUE.tsv`, which is derived over `WALK_ROOTS`, and this
> package is deliberately outside it (ADR-0153 dec. 1). An empty result means the
> register never looked. `unscorable` is the honest reading and is what the
> ratchet demands — scoring it `met` would have been the ADR-0148 defect written
> into the scorecard.

**Extraction #1's result: `Render` scores 7 met, 2 `n/a`, 1 open** — 7 of an
achievable 8. The one open is #8, whose remaining half is the known-drops
register at epilogue E1, so it is blocked on the epilogue rather than on
`Render`. Read it with `python3 tools/score_goals.py`; the register is
`docs/GOALS.tsv`.

**Extraction #2's result: `Audio` scores 4 met, 1 `n/a`, 4 open, 1
`unscorable`** — 4 of an achievable 9, and it is scored with
`python3 tools/score_goals.py --root ../exmateria-sound/addons/exmateria_sound
--system Audio`, because the package is outside the walk and the no-argument
form cannot see it.

> **Two of the four opens are the cost of leaving the walk, and they are the
> same cost twice.** #3 is `unscorable` and #4 is `open` for one reason:
> `docs/RESIDUE.tsv` and every `tools/check_*.py` are derived over `WALK_ROOTS`,
> which ADR-0153 dec. 1 keeps this package out of on three grounds. Three
> *readings* were built in compensation — [#402](https://github.com/timbermania/fft-monorepo/issues/402)'s
> `EXTRACTED` row, [#403](https://github.com/timbermania/fft-monorepo/issues/403)'s
> second anchor-scan root, [#405](https://github.com/timbermania/fft-monorepo/issues/405)'s
> blind-spot line — and **a reading is not a guard**. That is the price of the
> published-package shape, stated rather than scored away.
>
> The other two are real work with owners: #6 is map
> [#373](https://github.com/timbermania/fft-monorepo/issues/373)'s tier (does an
> FFT container codec belong in the addon at all), and #7's 122 lines all sort as
> **membership** of exactly that question — so #6 and #7 are one decision wearing
> two numbers. Zero sort as `rename`: `SMDOpcodes` was 103 of the original 171
> and [#407](https://github.com/timbermania/fft-monorepo/issues/407) retired it.
> **The package's CODE names zero PSX platform terms** — zero `psx`, `vram`,
> `clut`, `tpage`, `rgb555`, `libgpu` or `gte` on any code line of its 156 files,
> which model a PlayStation SPU. *Code line* is ADR-0149's rule as `score_goals.py`
> applies it: comments stripped, string literals kept. **Those same terms appear on
> 18 comment lines in 11 files** — `adsr.gd`'s *"PSX SPU ADSR envelope generator"*,
> `feds_bank.gd`'s *"SPU VRAM bank"*, `dispatcher.gd`'s *"PSX RCnt2"* and the rest —
> and that is the metric working, not a leak: goal #7 is about **vocabulary**, and a
> comment naming which PSX behaviour a line reproduces is documentation. The
> distinction is stated here because the unqualified sentence this replaces read as
> a claim about the text and was false as written.

**Extraction #3's result: `Battlefield` scores 6 met, 3 open, 1 `n/a`** — 6 of an
achievable 9, scored with the no-argument `python3 tools/score_goals.py` because
this system extracted **inside** the walk. It is the first extraction whose #4 is
`met`: `Audio`'s two opens were the price of leaving `WALK_ROOTS`, and this addon
never left, so all 52 `tools/check_*.py` still look at it.

> **Its #5 is `met` and that is worth reading with ADR-0202 rather than alone.**
> The mechanical test is `check_addon_portability.py`, which measures TYPE
> reaches — and **no arm of it reads a `res://` path out of a `.gd` body or a
> `.tscn` `ext_resource`**, so it was green through eleven code sites that made
> the addon un-installable. The compensating reading is
> `tools/check_addon_install.py`, built at pass 9 and now **0 on all four arms**.
> A `met` here means *no cross-system type reach*, which is narrower than
> *portable*, and the register is where the wider claim lives.
>
> **#6 is `open` on `Audio`'s grounds, not `Render`'s.** `Battlefield` owns
> ROM-derived formats — the GNS-linked mesh, the GNS map-state/weather enum, the
> indexed CLUT palettes — so the per-domain escape is closed and `n/a` is not
> available to it. #10 *is* `n/a`: the addon ships none of the thirteen root
> scenes, and its own two are components the host mounts.
>
> **#8 is `open` on BOTH halves, and the code half is the interesting one.** The
> register half is blocked on epilogue E1, the same blocker holding `Render` and
> `Audio`. The code half is not merely unstarted: this system's one
> PSX-compromise knob, `visible_angles_cull_mode`, went the *other* way at
> ADR-0190 dec. 1 — from a global uniform to a `const int` in the shader, which
> is precisely the shape ADR-0152 argues a PSX compromise should not take. That
> was the right call for ADR-0190's own question (a name with no writer does not
> earn a host entry) and it leaves #8's code half unbought.

> **Three of those seven were bought by reading the goal correctly rather than by
> changing code**, and ADR-0154 says so on the record rather than letting the
> number stand alone: #7 on ADR-0117 row 10 (`Render` IS the PlayStation look, so
> PSX platform terms are its vocabulary — ADR-0150), #3 on ADR-0135 dec. 11
> (`declined` is not deadness), #1 on ADR-0110 dec. 1 (the refactor lifts; the
> "analog, authored fresh" rule cited against it has no source ADR). A goal whose
> reading moves can be moved again — the defence is that each of the three is now
> a mechanical test with a direction-tested failing arm, so moving it again means
> moving a program.

**The research vault is deliberately not a goal** — it
is instrumentation, the ballast against which drift is measured (ADR-0111), not
an objective of the work.

**On #1 and the end state.** The greenfield slate is bought *per extraction* —
each addon is an **analog**, authored fresh rather than moved (ADR-0112) — not
by a final reassembly.

> **Corrected by ADR-0154 dec. 1 (recorded at extraction #2's pass 9): ADR-0112
> does not say this, and this paragraph contradicts the one ten lines above it.**
> The block on goal #1 already states that *"the 'analog, authored fresh' rule
> cited against it has no source ADR"*, and this sentence then asserts the rule
> with the citation — in the **charter that defines the goal**, which is the
> document a reader consults to find out what goal #1 means. ADR-0154 dec. 1's
> table listed four sites and this was not among them; it lists documents, and a
> document can say it twice. The rule that does have a source is **ADR-0110
> dec. 1** — *"Extraction, not transformation or reconstruction. Systems are
> lifted out of the host into addons."* Goal #1 is bought at the **decision**
> level (ADR-0154 dec. 3), which is why a lift can buy it at all; the rest of
> this paragraph — no reconnection event, the host is the running game throughout
> — is untouched.

ADR-0110 rejects the port-into-a-new-project shape
outright ("nothing playable until enough has crossed") and reaches the end state
"incrementally rather than by a big bang, ... the host's size is the progress
bar." There is no reconnection event; the host is the running game throughout,
converging on the FFT content pack plus its authoring tools. (ADR-0131 re-scopes
that quoted phrase: the host's size is an **inventory count**, not the metric —
see **Progress bar** below.)

**Ballast**:
The research vault's **note↔note wikilink graph plus index membership** — claims
about the domain that contain no reference to code, so refactoring cannot
perturb them. Pinned to **one** SHA, chosen when the single end-of-refactor
reading is taken — not per extraction, because there is no series (ADR-0111
dec. 1, amended by #310). It answers *directional* questions (is this more
scattered than before?) and never *positional* ones (should these be one module
or two?). It is **not** what tells you a reach is out of bounds — that is the
blueprint's job, via `classify_blueprint.py` and `touch_matrix.py`. The ballast's
unique finding is the opposite failure: behaviour **dropped**, which no
code-internal analysis can see. _Avoid_: blueprint (the opposite role —
see below), yardstick (fine informally, but ballast is the term), the vault
(that is the whole artifact, of which only this graph is ballast).

**Blueprint**:
The **game-agnostic tactics-RPG domain model** that defines what a
[system](36-refactor-projection.md) is and where its boundary falls, authored without
reference to FFT or to the current code, recorded as ADRs. The only reference
that is neither tautological (code-derived) nor ROM-shaped (vault-derived).
_Avoid_: the vault's domain clusters (those are filed ROM-shaped — `Effect
System` is one cluster because `E###.BIN` is one file format), target
architecture (too vague), the ADRs (those are where it is recorded, not what
it is).

**Projection**:
The function `project(code_sha, vault_sha) → graph`, mapping research notes onto
the code that implements them. **Two refs, because no single commit holds both
halves** — `vault/` lives only on `main`, the code only on the trunk
(`docs/adr/0002`; ADR-0111 dec. 5 wrote the one-argument form and is amended).
A **function, never a stored artifact**, so it stays re-derivable over any past
commit with any future metric — which is what lets it be **built at the end**:
it is read **once**, against **one** vault SHA chosen at that moment, as a
qualitative assessment rather than a series (ADR-0111 dec. 1, amended by #310).
There is no re-pin cadence and no owner of one. Its anchor is a **code-side comment** citing the
note, mirroring the ADR-citation convention, which stands at **65.1%** adoption
(306 of 470 `src/` files — ADR-0111 dec. 7's "95%" divided by a 2026-07-12
denominator; corrected by ADR-0131) — a comment travels with the code through
any rename. _Avoid_: vault 2 / vault 3 (they are
two evaluations of one function, not two artifacts), the R: lines (those seed
the anchors once; they are not the live projection).

**Progress bar**:
**Two counts per blueprint system, kept apart and never divided** (ADR-0131):
hand-written **lines**, and **uninterfaced reaches**. Both come from one walk
over one denominator — every line classified into exactly one system. They can
move in opposite directions, which is why they are never collapsed and never
divided into a ratio (a ratio falls whenever a system merely grows internally).
Distinct from the **metric**: `project()` supplies quality, the progress bar is
inventory under ADR-0114 dec. 7. _Avoid_: "the host's size" (ADR-0110's original
phrasing — it names only half, and one number cannot tell an extraction from a
deletion; extracted lines are reported beside host lines for exactly that
reason), percent complete (the final host size is unmeasured).

**Uninterfaced reach**:
A boundary crossing that does not pass through a declared interface — one of
four shapes `touch_matrix.py` can see: `class_name`, autoload, `preload`,
`/root/` lookup. An injected port is none of them, which is what makes the count
meaningful. **Always a floor**: duck-typed reaches carry no type name and are
invisible, so a falling count is also what a growing blind spot looks like.
Baseline: **354 reaches, 0 clean crossings**. _Avoid_: coupling (too broad),
violation (implies a rule was broken — there is no port to have used yet).

**Root set**:
The scenes the refactor commits to keeping, from which reachability is computed.
**A choice, not a measurement** — declaring it is the same act as deciding what
the game is. There are two: the ~12 game scenes, and the authoring tools.
_Avoid_: entry points (that is the candidate pool, not the chosen set), the
scene list, main scene (that is one root of many).

**Candidate root**:
A scene that runs on its own — nothing instances it. Running on its own makes a
scene *eligible*; being wanted makes it a [root set](36-refactor-projection.md)
member. `Unit.tscn`, `PlayerCamera.tscn` and `TileCursor.tscn` fail this: they
are reachable *from* roots, never roots. _Avoid_: standalone scene (ambiguous —
it also describes a scene with no dependencies).

**System**:
A unit of extraction — a body of behaviour that could ship to another tactics
RPG with its interface intact, lifted into one addon. `exmateria_sound` is the
calibrated example. One system extraction is one branch and one code review.
_Avoid_: module (reserve for the general deep-module sense), subsystem, cluster
(that is the research-side grouping, which a system need not match), component.

**Scatter**:
For one ballast cluster, the count of distinct modules holding code its notes
cite. Falls as a system consolidates into its addon. _Avoid_: spread, entropy,
fan-out (that is a per-symbol structural measure, not this).

**Crossing discipline**:
For one ballast cluster, the fraction of its code shared with other clusters
that sits on a **declared addon interface** rather than reaching into internals.
Reported beside [scatter](36-refactor-projection.md) and never collapsed with it.
_Avoid_: coupling score (implies one number), cohesion (that is closer to
scatter).

**Residue**:
Code **built but unclaimed** — reachable from no root set once extraction is
complete. The cruft register. _Avoid_: dead code (accurate but undifferentiated
— it hides the distinction from a gap), orphan.

**Gap**:
Research **recorded but never built** — a vault point whose `R:` reads `none`
(**516** such lines at `main` `dafcb81b3`, of 1,717 `R:` lines; the earlier
figure of 251 was measured before the vault doubled). The inverse of [residue](36-refactor-projection.md), and a
different register: conflating the two destroys both signals. _Avoid_: missing
feature, TODO, unimplemented (all lose the "we know it exists because the ROM
does it" specificity).

**Platform tier**:
The small set of ADRs that apply to every [system](36-refactor-projection.md) on
purpose — `PsxMagnitude` (ADR-0091), tunables (ADR-0068), the transform classes
(ADR-0057), the debug window (ADR-0035), parser-boundary decoding (ADR-0013).
An ADR spanning two systems is a question with three answers: split it, name it
an **interface ADR**, or promote it here. Platform-tier ADRs carry mandatory
code anchors, because their violations do not surface as test failures.
_Avoid_: cross-cutting concern (borrowed AOP jargon), global, core.
