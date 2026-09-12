# `PSXDisplay` stays in `Render`, because `Render` IS the PlayStation look

[#394](https://github.com/timbermania/fft-monorepo/issues/394) asked whether
`PSXDisplay.gd` belongs in a portable engine addon, on the grounds that
[ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md) dec. 4 sent
`psx_par.gdshaderinc` to `platform` while extraction #1 put its writer into
`addons/exmateria_render/`. **It stays.** The blueprint already names *display
aspect* as `Render`'s and already says `Render` is *"about looking like a
PlayStation"*; goal #5 is a **genre** test, not a platform test; and the reading
of dec. 4 that would evict `PSXDisplay` also evicts the fold and empties the
addon. Goal #7's lexicon splits instead, and the split is mechanised.

Status: accepted (2026-08-22). Closes #394. Bounds
[ADR-0146](0146-the-kernel-is-built-and-a-codec-is-what-gets-in.md) dec. 4.
Makes [ADR-0117](0117-the-blueprints-ten-systems.md)'s recorded `Render` strain
operative. Amends goal #7 as scored by
[ADR-0149](0149-the-ten-goals-are-scored-per-extraction-and-three-of-them-are-not.md).

Code at `5a3708743`, classifier at `5a3708743`.

## Context

The inconsistency #394 names is real as stated: ADR-0146 dec. 3's own table
lists `PSXDisplay._apply_par` as `psx_par`'s CPU side, dec. 4 booked the include
`platform`, and ADR-0147 put the writer inside the extracting addon. Two halves
of one PSX display fact, two buckets.

The stakes were the reason to answer this before anything else in the epilogue.
If `PSXDisplay` moves, `Render` is the fold bracket alone — 365 of 699 lines —
extraction #1 is retroactively halved, ADR-0131 forces its census to be restated
in a commit of its own, and 26 of the addon's 34 goal-#7 jargon lines leave with
it. Renaming anything first would have hardened the current placement by making
it look deliberate.

## Decision

**1. `PSXDisplay.gd` stays in `addons/exmateria_render/display_port/`.** Four
reasons, in the order that decides it:

**2. The blueprint already assigned it.** ADR-0117 row 10 defines `Render` as
*"`Compositor` · the depth model · **colour modes** · shader templating · the
fold · **display aspect**"*. Every one of `PSXDisplay`'s four concerns is named
there: PAR and the three per-taxonomy sprite stretches are *display aspect*, the
sRGB gamma is *colour modes*. There is no part of this file the blueprint books
somewhere else. #394 asked a placement question the blueprint had answered
before the file moved.

**3. Goal #5 is a genre test, and #394's framing swapped it for a platform
test.** The goal's literal words are *"a system could ship to another **tactics
RPG** with its interface intact."* ADR-0117 dec. 6 answers that directly:
*"`Render` is **genre-orthogonal**. It is about looking like a PlayStation, not
about tactics."* Genre-orthogonal and platform-agnostic are different axes.
A PSX-look renderer that ships to another tactics RPG with its interface intact
satisfies goal #5 completely, and goal #5 says nothing whatever about the
platform. #394's *"a game-agnostic engine addon arguably should not contain any
of them"* is the substitution, and it is where the ticket goes wrong.

**4. Being reached is what a port is for.** #394 offers *"26 of 27 inbound system
lines land on it from four systems"* as a cost of leaving it. It is the opposite.
ADR-0147 dec. 2 named `PSXDisplay` the addon's published surface; ADR-0118 says
services are **ports**; ADR-0139 dec. 12 already blessed reaching one. Measured,
all 21 of `UI`'s lines are `PSXDisplay.live_ui_par` reads and
`live_ui_par_changed.connect` subscriptions — a value and a signal, which is a
port being used exactly as designed. `Render` after this ADR reaches **nothing**
and is reached through one symbol: a **sink**, which is the shape an extracted
addon is supposed to have. A high inbound count on a port is evidence the seam
was cut in the right place.

**5. ADR-0146 dec. 4 is bounded to shared implementation, and the maximal
reading is a reductio.** Dec. 4's subject is a **`#include`d GLSL source file**
and its stated harm is *"six buckets include [it]"* dragging `Render` behind all
six — ADR-0118 dec. 5's serialisation arriving through the back door. That harm
requires a dependency with **no interface**: the six shaders compile the
include's text. A port is the presence of an interface, so the harm does not
transfer.

Read maximally — *any PSX display fact cannot live inside `Render`* — dec. 4
also evicts `fold_bracket/foldsurface_resolve.glsl`, whose `quantize5()` is the
PSX RGB555 framebuffer. That is the other 365 lines. **The maximal reading
empties the addon**, which is a reductio on the reading, not on the addon.

Dec. 3's test is what actually sorted these two halves, and it sorted them
correctly on its own terms: *"a member has a counterpart, not a writer."*
`psx_par.gdshaderinc` is the shared half and went to `platform`;
`PSXDisplay._apply_par` is named there **as the writer** — the thing the test
explicitly distinguishes. #394 read the table as evidence the halves were split
wrongly. The table is the reason they are split.

**6. Goal #7's lexicon splits into PLATFORM and CONTENT, and only `Render` is
exempt, and only from PLATFORM.** ADR-0117's Consequences already record the
strain in as many words: *"goal #8 runs backwards inside `Render`, where a PSX
compromise is the product and a known drop is a regression."* Goal #7 has the
same inversion and nobody had written it down. Inside `Render`, `psx_par` is
accurate domain vocabulary; inside `Audio`, `SMD` is one ROM container wearing
the name of a job.

So `tools/score_goals.py` carries two lexicons — `PLATFORM_JARGON` (`psx`,
`rgb555`, `clut`, `tpage`, `vram`, `libgpu`, `gte`) and `CONTENT_JARGON` (`fft`,
`waveset`, `ivalice`, `smd`) — and a `PLATFORM_EXEMPT` **map**, not a flag, so a
second system cannot acquire the exemption without a diff that names it. **No
system is ever exempt from CONTENT**: content stays in the host (ADR-0117
dec. 12). The platform count is still **printed for an exempt system**, never
suppressed — reported, never asserted (ADR-0145 dec. 4).

> **Amended 2026-08-22, declining a proposal from extraction #2 (ADR-0153
> dec. 10) and taking its evidence.** The proposal: *a term is **jargon** when a
> better word exists and **vocabulary** when the thing has no other name* — on
> `Audio` that is 171 open versus ~68. The observation behind it is real and the
> rule is refused, for three reasons in the order that decides it.
>
> **It contradicts this decision on the case this decision already settled.**
> `pixel_aspect_ratio` is a better word for `psx_par`, and it is *already in the
> tree* (`src/ui3/elements/UIChar.gd:75`, the same quantity). So the rule marks
> `psx_par` jargon and flips `Render`'s goal #7 back to `open`. The exemption and
> the rule are not composable as stated, and only one of them can be the test.
>
> **It is not mechanizable, and a proxy for it is worse than nothing.** *"A
> better word exists"* is a judgement. Encoding it means a hand-maintained list
> of which terms have better words — an allowlist wearing a principle's clothes,
> and ADR-0149 dec. 3 refuses exactly this: the instrument does not invent a test
> for a goal that has none.
>
> **The finding it is reaching for belongs to a different goal.** A term naming a
> **ROM container or disc artifact** — `WAVESET.WD`, an `SMD` file — is
> **content**, and ADR-0117 dec. 12 keeps content in the host. A codec for a ROM
> container sitting inside a portable addon is a **membership** finding, not a
> rename one, and exempting it is the opposite of what should happen to it.
> ADR-0136 dec. 1 already draws the line better than the proposed rule does: the
> **opcode language** is engine, the **container** is content. That is also why
> extraction #2's own dec. 6 is right about `SMDOpcodes` — 103 of its 171, the
> language named after one of its two containers — without needing this rule at
> all.
>
> **What changes instead: a #7 count is a WORK LIST, not a verdict.** Every hit
> sorts into exactly one of three, and the register's `evidence` column is where
> that sorting is recorded and is already required to resolve:
>
> 1. **rename** — our own concept named after a platform or a container
>    (`SMDOpcodes`);
> 2. **membership** — a ROM container's name, because the content is in the addon
>    (a goal #6 question, ADR-0117 dec. 12);
> 3. **exempt** — the platform IS the system's subject, which is `Render` and, on
>    ADR-0117's row for `Audio` (**"the sound driver"** — a job, not a platform),
>    is not `Audio`.
>
> The count stays mechanical and ungameable; the sorting stays human and cited.
> **No system scores #7 `met` while holding hits of kind 1 or 2**, which is the
> property the proposal would have given away.

**7. `psx_par` is not renamed, and that is a decision rather than an omission.**
Even setting the exemption aside, the identifier is a global shader parameter
shared with `platform`'s `psx_par.gdshaderinc` and read by 16 shaders across six
buckets. Renaming it inside `Render` alone breaks the pairing; renaming it
everywhere is a six-bucket change bought for a goal that dec. 6 says does not
apply here.

**8. Extraction #1's census is unchanged, so ADR-0131's restatement rule does not
fire.** Nothing moves. `--delta` reports no rebooking. This is worth stating
because #394 anticipated the opposite and the constraint would have shaped the
commit sequence.

## Considered alternatives

- **Move `PSXDisplay` to `platform`, beside `PsxNum.gd`.** Rejected by dec. 2 and
  dec. 5. It is also not what `platform` holds: `PsxNum` and the two includes are
  *shared implementation with no interface*, and `PSXDisplay` is an autoload with
  five signals and a tunable schema — a service, which ADR-0118 says is a port,
  and a port belongs to a system.
- **Split it: the mechanism to `Render`, the constants (`PAR := 1.25`,
  `INTERNAL_WIDTH`) out.** Genuinely tempting, and it is the shape goal #8 wants.
  Rejected **here** and moved to goal #8's own work, because it is a *compromise*
  question and not a *placement* one — the numbers do not change bucket, they
  change from a hardcoded constant into a policy the host supplies. Answering it
  inside a placement ADR would have buried the one real design change #394
  surfaced.
- **Rename `psx_*` in place and leave the file where it is.** Rejected by dec. 7,
  and it is what #394 itself warned against.
- **Leave #394 open until the epilogue.** Rejected: it blocks goals #5, #7 and #8
  for `Render` simultaneously, and every one of those was waiting on a decision
  the blueprint had already made.

## Consequences

- **Goal #7 scores `met` for `Render`: 0 content-jargon lines**, with 34 platform
  lines reported and exempt. The instrument prints both numbers, so the exemption
  is visible in every run rather than inferred from a green.
- **All 34 platform lines are accounted for by other decisions**, which is what
  makes the exemption safe rather than convenient: 26 in `PSXDisplay.gd` (this
  ADR), 5 in the two debug panels (leaving under goal #5 / #393), 3 in the
  kernel's `psx_ot_depth` include, which is `platform`'s symbol and not
  `Render`'s. Under the pre-split lexicon goal #7 could not have reached zero for
  `Render` at any point in the refactor, which is the definition of a goal that
  cannot steer.
- **`Render`'s achievable score is still 8** and this ADR moves it from 3 met to
  4 met without moving a line of code, because the goal was mis-scored rather
  than unmet.
- **Goal #8 keeps the hard half.** `PAR := 1.25` and `quantize5`'s `31.0` are
  still hardcoded compromises, and the alternative rejected above is the design
  work that divorces them. That is now the only real code change left in
  extraction #1's epilogue.
- **ADR-0146 dec. 4 carries a bound it did not have.** Anyone applying it to a
  future extraction now has the test — *does the dependent compile this file's
  text, or call through an interface?* — instead of the phrase *"a PSX display
  fact"*, which is true of most of `Render`.
- **`Render` is the only system with a platform exemption, and extraction #2 is
  the first thing that could challenge it.** `Audio` reproduces a PSX SPU. If the
  same argument is made for `exmateria_sound`, it must be made against ADR-0117's
  row for `Audio` — **"the sound driver"**, a job and not a platform — and not by
  analogy to this ADR.

  > **Corrected 2026-08-22, and the correction matters more than the error.**
  > Both this bullet and dec. 6's list originally attributed *"sequencing, mixing,
  > banks"* to ADR-0117's row for `Audio`. **The row reads "the sound driver."**
  > "sound banks" appears once in that ADR, in dec. 12's content-shadow list;
  > "sequencing" and "mixing" appear nowhere in it. It was a paraphrase written as
  > a quotation. The conclusion is unaffected — a driver is a job, so `Audio` gets
  > no platform exemption — but the sentence a reader would have checked was not
  > the sentence in the source.
  >
  > This is [ADR-0154](0154-goal-1-is-about-decisions-and-goal-3-is-about-orphans.md)'s
  > finding, committed **by the session that wrote ADR-0154, one commit later**.
  > That is the useful part: *"analog, authored fresh"* was not a past lapse by
  > someone careless. Nothing in the toolchain resists this —
  > `check_adr_classification.py` proves a link RESOLVES, never that the target
  > says the thing citing it — and a plausible paraphrase of a real ADR is
  > indistinguishable from a quotation of it at every point after it is written.
  > **Caught by extraction #2 reading the row instead of the citation**, which is
  > the only mechanism that has ever caught one of these.
  >
  > A second, same commit: *"the opcode language is engine, the container is
  > content"* was attributed to [ADR-0136](0136-audio-is-one-opcode-language-in-two-containers.md)
  > dec. 1. Dec. 1's claim is about **format structure** — *"below the header they
  > are the same bytecode, dispatched from the same PSX jump table"* — and says
  > nothing about ownership. The ownership split is an **extension** of it, and a
  > sound one, but a membership finding that rests on it owes its own paragraph of
  > evidence rather than a citation.
