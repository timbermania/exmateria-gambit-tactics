# The ten goals are scored per extraction, and three of them are not per-system

The refactor's charter is ten goals. They are cited by number in ten ADRs and in
`docs/agents/refactor-loop.md`, and **no loop pass checked one of them** — pass 9
measures lines and reaches (ADR-0131), which are two of goal #4's terms and none
of the other nine. So *"all goals passed"* was unfalsifiable. This gives five of
the ten a mechanical test, gives the other five a citation requirement, records
the result per extraction in `docs/GOALS.tsv`, and states which goals a single
system **cannot** be scored against at all.

Status: accepted (2026-08-22). Extends
[ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)
(the progress bar) and [ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)
(which names goals #3, #8 and #10). Instrument built on
[ADR-0148](0148-a-walk-that-does-not-follow-the-refactor-loses-coverage-silently.md)'s
`tools/_walk_roots.py`.

Code at `c85ba143d`, classifier at `c85ba143d`. Both named per ADR-0131's fourth
amendment.

## Context

The ten goals are `CONTEXT.md` → *Refactor projection → The ten goals*, recovered
onto the record on 2026-08-19 when the sweep found the list had never been
written down. Since then they have carried real weight: ADR-0112 turns goal #3
into the root-set closure, ADR-0113 exists to serve goal #5, ADR-0147 and
ADR-0148 both close by reporting against them.

Extraction #1 shipped and nobody could say what it scored. Deriving the scorecard
by hand at the end of extraction #1 took most of a session and produced a table
that lived in a handoff document rather than in the repo. Two of its ten rows —
*"not achievable"* — are not a state a system can be in; they are a statement
about the goal.

**The failure this ADR exists to prevent is not a low score. It is a score
nobody can dispute.** A goal that is met "because the extraction says so" cannot
be un-met by evidence, so it also cannot steer anything, and ten of those are a
charter that reads like an accomplishment at every point in the refactor.

## Decision

**1. Goals are scored per extraction, at pass 9, into `docs/GOALS.tsv`.** One row
per (extraction, system, goal), with `scope`, `state` and `evidence`. Pass 9
already runs the metric and already compares to the baseline; the score belongs
in the same reading and is worthless anywhere else, because the evidence is only
warm then (goal #4's own argument, applied to goal #4's own instrument).

States are `met`, `open`, `n/a` — and `n/a` needs a reason like any other.

> **Amended 2026-08-22 during extraction #1's epilogue: a fourth state,
> `unscorable`, and a `--root` argument.** Both came from the same defect, found
> by reviewing this instrument rather than by running it.
>
> `score_goals.py --root <path> --system <name>` scores a directory
> `WALK_ROOTS` does not own, because a system that extracts into a **published
> package** never enters the walk (`addons/exmateria_sound/` is excluded
> deliberately — see `tools/_walk_roots.py`) and would otherwise be reported on
> by nothing at all. Both arguments are explicit: the system is stated, not
> guessed from the directory name, because `exmateria_sound` does not contain the
> string "Audio".
>
> The first cut of that then scored `Audio` goal #3 **`met`**, on the grounds that
> an out-of-walk package has no rows in `docs/RESIDUE.tsv`. It has no rows because
> **the register never looked** — ADR-0148's defect reappearing inside the
> instrument written to catch it, one level up. So a mechanical test whose
> *evidence* does not cover the root now returns `unscorable` and says why.
> **`unscorable` is a finding, never a pass**, and the two-arm rule in dec. 4
> applies to it unchanged. Goal #3 is the only test with this property today;
> goals #5 and #7 read the addon's own files and are unaffected.
>
> **Superseded for the discovery half by [ADR-0155](0155-where-the-source-that-left-the-walk-went-is-declared-once.md)
> (2026-08-22).** `--root` is no longer the only way in: `_walk_roots.EXTRACTED`
> declares where each system that left the walk went and this scorecard reads it,
> so a package outside `WALK_ROOTS` is scored without anyone remembering to ask.
> `--root` remains for a package not yet declared. ADR-0155 dec. 6 adds the one
> new rule: **a system with NO rows is reported, never failed** — its extraction
> has not reached pass 9, so dec. 4's two arms have nothing to grip. The moment it
> has one row it owes all ten.

**2. Five goals get a mechanical test.** `tools/score_goals.py` runs them over
every addon in `_walk_roots.addon_roots()`, so a new extraction is scored the
moment its addon enters the walk and nothing has to remember to add it:

| goal | test |
|---|---|
| #2 translation table | `CONTEXT.md` carries `translation table (`<System>`)` |
| #3 remove dead code | no file under the addon has a row in `docs/RESIDUE.tsv` |
| #4 catch drift | the addon is a member of `classify_blueprint.WALK_ROOTS` |
| #5 portable systems | zero cross-system reach **lines** leave the addon |
| #7 no PSX/FFT jargon | zero jargon tokens in the addon's **code** |

#5 reads `tools/.touch_cache.json`, which `touch_matrix.py` writes, rather than
re-scanning, so there is one definition of "a reach" in the package rather than
two that can drift. (An earlier draft attributed *"when two registers describe
the same set, diff them"* to ADR-0146. **ADR-0146 does not contain that
sentence** — it is ADR-0147/0148's coinage, which acquired an ADR-0146
attribution by repetition. The principle is right and the citation was not;
see ADR-0154 and `tools/check_adr_quotes.py`.) A `platform` port and the `schema` kernel are not
systems and so do not appear, which is correct and is the whole content of
ADR-0140 dec. 9: a port is what a portable addon is *allowed* to reach.

**3. The other five carry a citation, and the citation has to resolve.** #1, #6,
#8, #9 and #10 have no mechanical test and the instrument does not invent one.
It requires the row's `evidence` to name an ADR that exists, an issue, or a path
in the tree, and reds when it does not. A row with no evidence prints `UNSCORED`,
which is the finding — the same deliberate absence of a catch-all that
`classify_blueprint.py` has.

**4. The ratchet has two arms.** The guard reds when the register and the
mechanical reading **disagree in either direction**: a row claiming `met` where
the test fails is a false claim; a row claiming `open` where the test now passes
is a stale register, and the moment the work lands is exactly when it should say
so. A register that honestly reads *"five open"* is **green**. There is
deliberately no threshold on the open count — a threshold is what makes a
register worth gaming, and agreement with the code cannot be gamed without
changing the code.

**5. Three goals are not per-system, and saying so is the point.**

- **#6 (assets as a superset) and #10 (authoring) are per-domain.** A system that
  owns no ROM-derived asset format cannot exercise #6, and a system that ships no
  root scene cannot exercise #10. `Render` is both. These score `n/a` **with a
  reason**, and `n/a` is a real state, not a soft failure. Without this every
  future extraction re-derives the same confusion, and every scorecard reads two
  points short of a target it was never able to reach.
- **#8 (PSX compromises divorced) splits.** The *code* half — a compromise
  becomes a policy the caller supplies rather than a constant in the bracket — is
  per-system and is not blocked. The *register* half is the known-drops register,
  which `refactor-loop.md` puts at epilogue E1. So #8's scope is `per-system +
  E1` and a system can hold at most half of it. Recording that stops E1 from
  being quietly treated as optional and stops a system from claiming #8 met.

**6. A system's realistic target is stated at pass 1, not discovered at pass 9.**
`Render`'s is **8**, because #6 and #10 are `n/a`. Publishing the achievable
number up front is what makes 8-of-8 a result rather than 8-of-10 a shortfall.

**7. The kernel is not scored.** `addons/exmateria_schema/` books to `schema` and
`infrastructure`, not to a system, and the ten goals are the charter for systems
(ADR-0139 dec. 9). The instrument prints that it is skipping it, with the buckets
it found — a future addon that lands unclassified must not vanish from the
scorecard silently, which is ADR-0148's whole lesson in a different costume.

## Considered alternatives

- **A prose scorecard per extraction, in the ADR that closes it.** Rejected: that
  is what extraction #1 did, and the result was a table in a handoff file that no
  later commit could contradict. ADR-0145 dec. 1 already found that a number in
  prose moves without the code moving.
- **Mechanize all ten.** Rejected on trying it. #1 (*decisions made on their
  merits*) and #9 (*improve the architecture as we go*) are judgements about how
  a decision was reached; any proxy — rename similarity, diff size — measures
  something else and would then be defended as if it were the goal.
- **Score the goals globally rather than per extraction.** Rejected: goal #5 is a
  property of one addon and averaging it across systems destroys the only reading
  that steers anything. Pass 9's *global* reading is about the metric, whose
  failure mode is local wins summing to a worse whole; the goals do not have that
  failure mode.
- **Fail the build on any `open` goal.** Rejected: `open` is the honest state for
  most goals for most of the refactor, and a red suite that is red on purpose
  teaches everyone to ignore it.

## Consequences

- **`Render` scores 3 met, 2 n/a, 5 open**, and this is now a command rather than
  a claim: `python3 tools/score_goals.py`. It reproduced the hand-derived
  scorecard exactly, which is the only evidence available that the tests are the
  ones the goals meant.
- **Goal #7 was being read at a quarter of its size.** The first cut of the
  instrument stripped string literals along with comments, because it borrowed
  `touch_matrix.strip_noncode` whole, and scored `Render` **3** jargon lines where
  issue #394 had counted `psx_par` ×15 by hand. A `Tune` slug lives in a string
  literal and is the most *public* vocabulary an addon has — it is what the F3
  dashboard prints. Read correctly it is **34**, and the distribution is the
  finding: 26 in `display_port/PSXDisplay.gd`, 5 in the two debug panels, 3 in the
  kernel's `psx_ot_depth` include. Every one of the 34 belongs to a placement
  question already open (#394, #393) or to another system. **There is no rename
  work in goal #7 for `Render` that is not first a placement decision.**
- **`RGB555` scores zero for goal #7 and is still a goal #8 defect.** It appears
  in `foldsurface_resolve.glsl` only in a comment; the quantize itself is an
  unnamed constant. Jargon and compromise are genuinely different goals and the
  instrument separates them without being told to.
- **Goal #3 is red for `Render` on one file**, and the redness is a real
  disagreement rather than a defect: `depth_debug.gdshader` is `declined` in
  `docs/RESIDUE.tsv` and kept deliberately (ADR-0142 dec. 8), while goal #3 says
  remove what the root set cannot reach and a declined scene is not a root. The
  instrument's job here is to refuse to let that sit unresolved, not to pick.
- **`docs/GOALS.tsv` is hand-authored**, unlike `docs/RESIDUE.tsv`. Five rows have
  no generator, so a generator would write half the file while implying it wrote
  all of it.
- Extraction #2 inherits a scorecard it must fill in at pass 9, and inherits the
  `n/a` vocabulary rather than re-deriving it. `Audio` is expected to score #6 and
  #10 differently from `Render` — it owns SMD/WAVESET formats and has an authoring
  surface — which is the first test of whether dec. 5's per-domain scoping is real
  or was written to excuse `Render`.
