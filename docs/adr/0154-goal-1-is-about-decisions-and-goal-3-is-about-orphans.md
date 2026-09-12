# Goal #1 is about decisions, goal #3 is about orphans

Two goals were unscorable for `Render` because each disagreed with an ADR. Both
disagreements dissolve on reading the sources: **the "analog, authored fresh"
rule is a claim with no source** — ADR-0112 does not contain it, and three later
ADRs plus the loop doc cite ADR-0112 for it — and **`declined` was already ruled
not-deadness** by ADR-0135 dec. 11. Neither goal is rewritten to fit the code;
both are read against what was actually decided, and both readings become
mechanical tests.

Status: accepted (2026-08-22). Closes
[#395](https://github.com/timbermania/fft-monorepo/issues/395). Corrects a
mis-citation in [ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md),
[ADR-0121](0121-systems-land-in-addons-src-only-shrinks.md) and
[ADR-0133](0133-a-wrong-cut-is-fixed-forward-and-the-reconnect-is-the-trigger.md).
Reads goal #3 against [ADR-0135](0135-the-root-set-is-eleven-scenes-and-its-assembler-is-the-script-nothing-calls.md)
dec. 11. Scored by [ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md).

Code at `e50d348f8`, classifier at `e50d348f8`.

## Context

`docs/GOALS.tsv` opened extraction #1's epilogue with five goals `open`. Three
were placement or design work and are settled by ADR-0150, ADR-0151 and
ADR-0152. The last two were **arguments about what the goal says**, which is the
class of blocker a scorecard is supposed to surface and cannot resolve.

## Decision

**1. "Analog, authored fresh" is not in ADR-0112, and goal #1 does not require
it.** Searched: ADR-0112 contains no *analog*, no *authored*, no *fresh*, no
*move*, no *lift*. Its six decisions are entirely about what dead code **is** — a
root set and its closure. The rule is asserted in three places that all cite it:

| site | what it says |
|---|---|
| ADR-0121 Context | *"ADR-0112 authors an **analog** rather than moving code"* |
| ADR-0111 dec. 7 / alternatives | *"the refactor writes analogs"* |
| ADR-0133 | *"**Extraction writes analogs, not moves** (ADR-0112)"* |
| `refactor-loop.md` | *"ADR-0112 makes each addon an **analog**, authored fresh"* |

So #395's framing — *"the two ADRs disagree with each other"* — is not what
happened. **Only one of them ever said anything**, and it is
[ADR-0110](0110-systems-extract-outward-into-addons.md) dec. 1: *"Extraction,
not transformation or reconstruction. Systems are lifted out of the host into
addons."* Extraction #1's 94–100% renames are that rule, followed. **The lift is
the rule; the four sites are amended, not the practice.**

**2. ADR-0121 decs. 3 and 4 survive as conditional, and are unexercised.** They
manage an overlap in which an original and its replacement coexist — the
original drops its `class_name` first, and dies by closure once the replacement
is reachable. A `git mv` never enters that state: one copy exists throughout and
no `class_name` collides. They remain the rule **for an extraction that genuinely
rewrites** — a system whose seam demands a different shape cannot be lifted
file-for-file — and after one extraction they have never run. Recorded so that
the first extraction that does need them knows it is the first.

**3. Goal #1 is bought at the DECISION level, and `Render` bought it.** The
goal's words are *"decisions made on their merits, not negotiated against what is
already there"* — a claim about how a choice was reached, not about how many
lines were retyped. The test is whether any decision went its way **because the
existing shape made it cheaper**, and extraction #1 has five that cost more:

- **475 lines re-booked OUT** of `Render` into `Effects`, eight files (ADR-0147
  dec. 1/3).
- **The shader library was refuted**, not inherited: `BLUEPRINT.md` §10 predicted
  the walk would hand `Render` one and all five entries book elsewhere (ADR-0147
  dec. 4).
- **`PSXDisplay`'s placement was re-argued from the blueprint** with a live
  option to halve the addon (ADR-0150).
- **65 lines were deleted rather than carried** (ADR-0151).
- **Four constants deleted and a compromise parameterised** (ADR-0152).

**4. The lift's real cost is unreviewed INTERNALS, and it belongs to the other
goals.** A `git mv` reviews *membership* and never *contents*. `PSXDisplay.gd`
crossed with four dead constants, a docstring calling one of them *"the canonical
constant"* while the running value contradicts it, and three more docstrings
naming panels that no longer exist. **Every one of those was found by a later
goal's pass forcing a read of the file** — #8's by ADR-0152, the panel citations
by ADR-0151. That is the mitigation working, and it is worth writing down
because the alternative reading (goal #1 failed) would prescribe a rewrite that
ADR-0110 dec. 1 forbids.

**5. `declined` is not goal #3's to remove.** `tools/residue.py`'s class list
already says it, in words of its own that it attributes to ADR-0135 dec. 11:
*"declined is not deleted. This is not deadness and never was."* **That sentence
is `residue.py`'s, not ADR-0135's** — dec. 11 reads *"The declaration is
ratified; the deletion is pass 5's. A declined scene stays classified until it is
actually removed."* The paraphrase is faithful and the schedule is the load-bearing
half; the distinction is noted because this ADR is about exactly that slippage,
and `tools/check_adr_quotes.py` flags this line.

A declined scene is a candidate root **deliberately not kept**, and its removal
is owned by the scene, not by whichever addon happens to hold one of the files it
reaches. `addons/exmateria_render/debug/depth_debug.gdshader` is preloaded by
exactly one file — `src/scenes/DepthDebugScene.gd`, itself `declined` — and both
are in the register. **Goal #3's mechanical test now fails on `orphan`,
`cluster`, `test` and `tool` and reports `declined`**, direction-tested: flipping
that one row's class to `orphan` turns the test red.

**6. The shader is not deleted here, and the drop it represents is already
recorded.** ADR-0135's Consequences carry it: *"`DepthMode.gd` documents its
sub-bucket nudges as 'tuned once in `DepthDebugScene`'. The constants survive;
the instrument that produced them does not. Re-tuning them later means rebuilding
the rig."* `depth_debug.gdshader` **is** that rig. Deleting it alone would break
a declined scene without removing it, which is the worst of both; deleting the
scene is `assembler`'s work and ADR-0135 dec. 11 reserves it.

## Considered alternatives

- **Delete `depth_debug.gdshader` now and score goal #3 clean.** Rejected by
  dec. 6. It buys a scorecard row by leaving a half-deleted scene behind, and it
  would let any extraction unilaterally delete another system's scheduled work
  because one file happened to land in its addon.
- **Delete `DepthDebugScene` and its shader together.** Coherent, and genuinely
  tempting since the decline is ratified and the drop recorded. Rejected as scope:
  the scene is `assembler`'s, one of 21 `declined` files across every system, and
  ADR-0135 dec. 11 assigns the deletion to pass 5. Extraction #1's epilogue is not
  pass 5.
- **Keep "analog, authored fresh" and declare extraction #1 non-compliant.**
  Rejected by dec. 1: the rule has no source ADR, and ADR-0110 dec. 1 — which
  does — says the opposite. Retrofitting a rewrite onto a landed extraction to
  satisfy a sentence nobody decided is the expensive version of this ticket.
- **Delete the four "analog" sentences outright.** Rejected: this repo records
  rather than rewrites. Each site gets an amendment block naming the correction,
  which is also what makes dec. 2 findable by the extraction that needs it.

## Consequences

- **`Render` scores 7 met, 2 n/a, 1 open** against an achievable 8. The single
  open goal is #8, and its remaining half is the known-drops register at epilogue
  E1 — blocked on the epilogue, not on `Render`.
- **Three of those seven were bought by reading the goal correctly rather than by
  changing code**, and that has to be said out loud or this is the unfalsifiable
  claim ADR-0149 exists to prevent: #7 on ADR-0117 row 10 (ADR-0150), #3 on
  ADR-0135 dec. 11 (here), #1 on ADR-0110 dec. 1 (here). **A goal whose reading
  moves can be moved again.** The defence is that each reading is now a
  mechanical test with a direction-tested failing arm, so the next person who
  wants to move it has to move a program.
- **A claim can propagate through four documents without a source.** Three ADRs
  and the loop doc assert "analog, authored fresh" and all four cite ADR-0112,
  which does not contain it.
  > **It is EIGHT sites, not four, and this bullet's own number was the reason
  > (recorded 2026-08-22 at extraction #2's pass 9).** Dec. 1's table has one row
  > per **document**, so amending a document's first occurrence read as amending
  > the document — and four more sites survived it: `check_vault_anchors.py`'s
  > docstring (#403), `docs/agents/refactor-loop.md:486` (~110 lines below its own
  > amendment), `godot-learning/CONTEXT.md:8015` — **the charter that defines goal
  > #1, never in the table at all, contradicting its own text ten lines above** —
  > and ADR-0147's alternatives. All are amended now, and a repo-wide grep for the
  > phrase is clean. **When you repair a phantom citation, grep for the PHRASE, not
  > for the documents you already know about; a per-document checklist under-counts
  > by construction.** Nothing checks that a citation supports what cites
  it — `check_adr_classification.py` verifies a link RESOLVES, never that the
  target says the thing. That is the ADR-shaped twin of extraction #2's finding
  that a blueprint sentence in the indicative is a measurement nobody
  instrumented.

  > **Partly solved after all, 2026-08-22: `tools/check_adr_quotes.py`.** A
  > citation records WHERE; for the **quotation-shaped subset** — `*"…"*` beside
  > an `ADR-NNNN` — WHAT is mechanically checkable, and both of the day's defects
  > are that shape. It reports 32 flags over 91 same-line cross-ADR quotations
  > and runs with `ENFORCE = False`, because a quote can be of another document
  > with an ADR link on the same line and the guard cannot tell.
  >
  > **Six sampled, six real**, and the third is about the sessions that wrote
  > this ADR:
  >
  > | citing | target | quoted, and absent |
  > |---|---|---|
  > | ADR-0124 | ADR-0117 | *"the calibrated example of a finished system"* |
  > | ADR-0127 | ADR-0122 | *"the effect channels"* |
  > | ADR-0147, 0148, 0149, `score_goals.py` | ADR-0146 | *"when two registers describe the same set, diff them"* |
  > | ADR-0144, ADR-0145 | ADR-0112 | its **title**, dropping *declared* |
  > | ADR-0151 | ADR-0121 | its **filename**, quoted as its title |
  >
  > The third is this ADR's own mechanism caught by a program: the phrase is
  > ADR-0147/0148's coinage and acquired an ADR-0146 attribution **purely by
  > repetition**, including twice by me. All four of my sites are corrected in
  > the same commit as the guard.
  >
  > **Extended to document targets after it missed one by construction.** A span
  > attributed to `BLUEPRINT.md` carries no ADR number on its line, so the first
  > cut never checked it — and that is exactly where extraction #2 found a defect
  > of its own with a recall-oriented throwaway. `docs/BLUEPRINT.md`, `CONTEXT.md`
  > and `refactor-loop.md` are now targets: 125 quotations checked, 42 flagged,
  > **ten sampled, ten real.** The sharpest of them is one phantom phrase, *"the
  > calibrated example of a finished system"*, quoted in ADR-0124 as ADR-0117's
  > and in ADR-0136 as `BLUEPRINT.md`'s. **It is in neither** — BLUEPRINT.md:434
  > reads *"The closest system to finished."* Three citing sites, two claimed
  > sources, one phrase that was never written.
  >
  > **Knowing the failure mode confers no immunity.** On the day this guard was
  > built, three misquotations were committed by the two sessions documenting the
  > problem — twice by the author of this ADR, and once by the session that
  > proposed the guard, into a paragraph it had just read. The error is invisible
  > from the citing side **by construction**. That, not a defect rate, is the
  > argument for `ENFORCE` eventually being True.
  >
  > **Why it catches what reading cannot — the argument a rate cannot make.** Two
  > of the ten are different animals. A **dropped word** (*"The closest system to
  > finished"* quoted as *"the closest to finished"*) is what a careful reader
  > with the source open catches. A **fusion** is not: `BLUEPRINT.md` 434-435
  > reads *"**The closest system to finished** — `Effects`' **calibration**
  > benchmark, and not the same thing as extracted"*, and the phantom takes
  > `calibration`, `finished` and `system` from **within two lines of each other**
  > and recombines them. Every content word in it is genuinely there, so nothing
  > reads as foreign. **A substring match does not care.** ADR-0124's second
  > fabrication, *"FFT music and SFX banks"* in the same sentence, is the same
  > shape — a real content shadow, two lines further on, in `BLUEPRINT.md` rather
  > than the ADR-0117 it is attributed to.
  >
  > **And a rate is not evidence.** This instrument was nearly discarded at "36%
  > cannot be a real defect rate". Six opened files said otherwise, six times out
  > of six; four more against the document targets made it ten. A rate is a
  > hypothesis about a population — opened files are evidence, and every flag
  > here is a filename and a line number.
  >
  > **It cannot catch a paraphrase**, which is the limit worth stating: *"the
  > sound driver"* rendered as *"sequencing, mixing, banks"* is caught only
  > because the invented words are absent. A close paraphrase would pass. The
  > mechanization is real and partial, and the only complete check remains a
  > second reader opening the target — which is how every one of these was
  > actually found.
- **The first extraction that must rewrite rather than lift owes ADR-0121
  decs. 3–4 their first run**, and should say so, because a decision that has
  never executed is a design, not a mechanism.
