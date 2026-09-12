# A wrong cut is fixed forward, and the reconnect is what catches it

There is no un-extraction. A boundary discovered to be wrong is repaired by
moving the responsibility, or by merging the two addons — never by reverting
the extraction that drew it. The signal is not a metric reading: it is the
**per-caller reconnect** inside the extraction itself, where each caller must be
expressed through a declared port or cannot be expressed at all.

Status: accepted (2026-08-20).

## Context

[`refactor-loop.md`](../../../docs/agents/refactor-loop.md) pass 3 names rollback
as a decision to take before it is needed: the loop runs ten to fifteen times
and *"predict here, verify there"* concedes that a boundary error will not
announce itself at the extraction that made it.

Three facts make the naive answer — `git revert` the extraction — worse than it
looks:

- **Extraction writes analogs, not moves** ([ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md)).
  Git sees delete-plus-add, so there is no rename to revert. The rewrite is the
  value and the boundary is the mistake; a revert discards both.
  > **Amended by [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md)
  > (2026-08-22): ADR-0112 does not say this, and this bullet is now the WEAKEST of the
  > three.** Under ADR-0110 dec. 1's lift there IS a rename to revert — extraction #1 reverts
  > cleanly. The other two facts are untouched and still make fix-forward right; this one no
  > longer carries weight for a lifted extraction, only for a rewritten one.
- **Later extractions bind the earlier interface**, and their tests migrated to
  bind it too (ADR-0112 dec. 5). Reverting extraction #1 at extraction #4
  un-boots #2 and #3, against [ADR-0110](0110-systems-extract-outward-into-addons.md)
  dec. 1's *the host remains bootable and playable at every commit*.
- **The three registers cannot be un-recorded.** A known drop was authorised by
  an ADR and is still dropped after any re-cut.

The industry position on all three questions is settled and worth naming rather
than re-deriving:

- **Direction is a hard gate, universally** — Go's `internal/` (a compiler
  error), Bazel `visibility`, JPMS `exports`, ArchUnit, `import-linter`,
  `dependency-cruiser`, Nx module boundaries. None of them ship this as advice.
- **Whether a given crossing is legitimate is not machine-decidable**, and every
  one of those tools concedes it the same way: *you declare the allowed edges and
  the machine enforces your declaration*. The gate is "on the list", never "zero".
- **The standing instrument for a wrong cut is change coupling** — files that
  keep changing in the same commit across a package boundary (Tornhill,
  *Software Design X-Rays*; CodeScene).
- **Merging a service back is normal and expected**, and treating boundaries as
  permanent is the actual error (Newman, *Monolith to Microservices*).

## Decision

**1. There is no un-extraction.** No revert path exists as policy, including for
the case where the system should not have existed. The addon stays extracted and
the repair is ordinary forward work.

**2. A wrong cut has exactly two repairs, and ADR-0115 dec. 3 chooses between
them.** Ask *would anyone use A without B?* If no, they were one system and the
addons **merge**. Otherwise the misplaced responsibility **moves** to its correct
system. Both are ordinary commits against a host that never stops booting.

**3. The repair stays cheap because promotion is deferred, and
[ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) dec. 7 already said
so.** A system lives in `godot-learning/addons/<system>/` until something
outside this repo consumes it. For the whole run of the loop a merge is a
same-repo refactor with no external consumer to break — ADR-0121's *"reversible
in the cheap direction"*, made explicit. **The expensive case begins at
promotion, not at extraction**, and promotion is triggered by an outside
consumer rather than by the loop.

**4. The primary trigger is the reconnect, not a measurement.** ADR-0121 dec. 4
drops the original's `class_name` first, which breaks every bare-name caller and
forces each to be re-pointed one at a time. That per-caller re-point is the
boundary's test: **a caller that cannot be expressed through the addon's declared
ports is the wrong-cut signal.** It fires inside the extraction that made the
mistake — earlier than pass 9, earlier than a later system's pass 3, and earlier
than any reading.

**5. The forced break is partial, and the policy says so.** Measured 2026-08-20
in `src/`: **337** `class_name` declarations, **371** `preload("res://…")`,
**30** literal `load("res://…")`, **26** autoloads. Dropping a `class_name`
breaks only the bare-name callers. The **401 path reaches and 26 autoload names
survive it silently**, still bound to the original file, and surface only at
ADR-0121 dec. 3's deletion-by-closure. So dec. 4 exposes roughly a third of the
caller set and the closure completes it; the reconnect trigger has a named blind
spot rather than an assumed completeness. (ADR-0112 records **124** path
preloads; the figure needs re-dating, whether the difference is method or
growth.)

**6. Two backstops, because dec. 5 is partial and a wrong cut can still sit
quiet.**

- **A later system's pass 3** (human, design time). Designing system N's seam
  names code already living inside an extracted addon. Costs nothing — the audit
  was already scheduled.
- **Change coupling over git history** (machine, standing). Files that keep
  changing together across an addon boundary were separated wrongly. This is the
  only check that fires with nobody touching the code, which is the case dec. 4
  and pass 3 both miss. **It reads nothing useful until roughly three extractions
  have landed** — do not treat early silence as a pass.

**7. Declared ports are a hard gate, not a smell list.** A reach that does not go
through a declared port fails; declaring a new port is a deliberate edit that a
human reviews. This is the industry shape (dec. context) and the repo already has
the noun — [ADR-0118](0118-payloads-are-schemas-services-are-ports.md)'s port.
The gate is *on the list*, never *zero*: real crossings exist and the point is
that each one was declared on purpose.

**8. Direction is part of that gate.** Host → addon is ordinary. **Addon → host
is always a defect**, and addon → addon is legitimate only through a declared
port. The benchmark is measured, not assumed: `exmateria_sound` reaches into
`godot-learning` **zero** times in code (2026-08-20 — the seven files that name
it do so in comments about asset paths), while **21** of the host's 601 test
files preload the addon.

**9. A forward fix touches none of the three registers.** *Residue* (built but
unclaimed), *gap* (researched but unbuilt) and *known drop* (deliberately left
out, with its authorising ADR) are per-behaviour, not per-system. Moving code
between addons changes none of them; the only edit is re-pointing an entry whose
owning-system field names the old owner. **This is the decisive argument for
dec. 1** — a revert would have forced unwinding three registers across every
system built since.

**10. The reconnect is scored on reaches, not on size.** The reading that moves
is [ADR-0131](0131-the-progress-bar-is-two-counts-per-system-lines-and-uninterfaced-reaches.md)'s
second count — uninterfaced reaches, opening at **354** with **0** clean
crossings. A system extracted across a wrong boundary keeps needing what it
should not need, so **its reach count refuses to fall** while its line count
moves exactly as predicted. Host size cannot see this: moving a file from `src/`
to `addons/` changes neither line count, which is why ADR-0110's *"the host's
size is the progress bar"* was already corrected by ADR-0131.

## Considered alternatives

- **Revert the extraction.** Rejected under dec. 1 — discards an authored
  rewrite to fix a boundary, un-boots every system built on it, and forces the
  register unwinding dec. 9 describes.
- **Re-extraction: un-extract into the host, then extract again with the seam
  redrawn.** Rejected: it is the revert with an extra step, and it reopens the
  `class_name` overlap (ADR-0121 dec. 4) a second time for the same code.
- **A deprecation window on the old owner** — the old addon keeps a pass-through
  marked deprecated until the next major. Rejected: ADR-0121 dec. 3 already
  rejected `@deprecated` on the grounds that *a marker is a claim and the closure
  is a proof*, and dec. 3 above removes the external consumer that would have
  justified the window.
- **A metric regression as the trigger.** Rejected as the *primary* signal: a
  wrongly cut system still shrinks the host and its extra crossings look like
  ordinary crossings, so the reading is ambiguous exactly where it needs to be
  sharp. It survives as dec. 10's *reaches refusing to fall*, read against a
  pass-3 prediction rather than on its own.
- **A failing build or a pass 7 review verdict.** Rejected: both are downstream
  of a built extraction, which is the cost this ADR exists to avoid.
- **Addon-to-addon reaches must stay at zero.** Rejected under dec. 7 — it bans
  the legitimate crossing along with the accidental one, and no tool in the
  industry survey enforces zero either.

## Consequences

- **Rollback is not a mechanism, so nothing has to be built for it.** The
  deliverable of this ticket is a policy plus three triggers, two of which
  already exist in the loop.
- **The change-coupling check has an owner: loop pass 9.** It is a global read
  over the whole tree after every extraction, the same shape as the metric read
  already scheduled there. It is not this map's build — the map plans and hands
  off (ADR-0132 and ADR-0131 dispose of their builds the same way).
- **Dec. 5's blind spot is a standing cost of ADR-0121 dec. 4**, not of this
  decision, and re-dating ADR-0112's path-preload figure is now on someone's
  list.
- **Dec. 3 puts a boundary on this ADR's own validity.** Everything above holds
  while systems live in `addons/`. The first promotion to a top-level package
  makes a merge a breaking change, and this policy needs an amendment at that
  point rather than a silent extension.
