# Is "present generated options" the fix for a boring turn beat? — research

**Status:** research only, 2026-09-11. **Nothing decided, nothing built.** Companion to
[`GAMBIT-BATTLE-DESIGN.md`](GAMBIT-BATTLE-DESIGN.md) §4 (Adjustments) and §7 (the enemy AI)
and to [`TURN-OPEN-BEAT-DESIGN.md`](TURN-OPEN-BEAT-DESIGN.md).

Method: 5 search angles → 20 sources fetched → 95 candidate claims → 3-vote adversarial
verification (2-of-3 refutes kills a claim) → 25 survived to verification, **16 confirmed,
9 killed**. The kill list is in §6 and is load-bearing: several of the killed claims would
have been the most directly actionable items here.

---

## 0. The question

The turn beat in `GambitBattle` reads as admin, not play. Candidate fix: on a frozen turn,
surface N rollout-generated candidate gambit edits spread across impact/risk profiles or
intent clusters; player picks one, or drops into the full editor.

## 1. Headline: the evidence undercuts the fix *as specified*

The closest empirical analogue in existence was run and **it did not deliver the agency
benefit**. Choong, Cmentowski, Kukshinov, Tu & Nacke, *"Support Autonomy: Exploring Player
Perspectives on AI-Supported Onboarding in Video Games"*, CHI '25 Article 464
(doi 10.1145/3706598.3713576, CC-BY): a purpose-built two-player turn-based strategy game
on a chessboard, whose decision-tree AI evaluated all legal card-pair/square combinations
and surfaced **two** suggested options per turn as **non-mandatory** pulsing overlays **at
turn start**. n=20, within-participants.

> "providing a suggestion at the start of every turn did not increase freedom of choice.
> Players not only need the freedom to use suggestions how they want, but also to receive
> suggestions when they want. Providing an optional suggestion when the player does not want
> it cannot increase their freedom of choice because they did not choose to receive the
> suggestion in the first place."

- **15 participants** wanted guidance opt-in, naming two mechanisms themselves: a hint
  button, or a suggestion that appears only after a period of inactivity.
- **9** said the auto-appearing prompt gave them *less* freedom — it "did not give them the
  opportunity to think for themselves."
- Some reported that **even when they won, they did not feel they deserved it** if they had
  used the AI's pick.

Note what this is *not*: optionality DID buy agency against a forced tutorial. What
optionality alone failed to buy was freedom of choice when the **delivery timing** was not
the player's. Push is the failing variable, not suggestion.

**Confidence: medium.** Qualitative — two semi-structured interviews, reflexive thematic
analysis, **no quantitative autonomy measure**, so "did not increase freedom of choice" is
interview-derived, not a measured null. Scoped to *onboarding first-time players*, which
makes it conservative for us (unsolicited help is most defensible there and it still
failed) but also means transfer to an expert-facing tactics turn is our leap, not theirs.

## 2. There is no magic N. Any number you pick is your opinion.

Two meta-analyses, both primary, both verified verbatim against the PDFs:

- **Scheibehenne, Greifeneder & Todd 2010 (JCR)** — 63 conditions, 50 published+unpublished
  experiments, **N=5,036**. Mean choice-overload effect **d=0.02, 95% CI [-0.09, 0.12]**.
  Trim the 20% most extreme studies and it's **d=0.001**.
- **Chernev, Böckenholt & Goodman 2015 (JCP)** — written as a *rebuttal by overload
  proponents*, 99 observations, **N=7,202** — and it nonetheless replicates the unmoderated
  null: **t(20)=-.10, p=.48**, "consistent with the findings reported by prior research."
  It only gets a significant intercept once four theoretical moderators are entered.

Neither finds a linear or curvilinear relation between effect size and assortment size
(SGT quadratic fit R²=0.02; Chernev b=-.005 p=.13 linear, b=.002 p=.17 quadratic).

**Boundaries that must travel with this:**
1. Both report large unexplained heterogeneity (SGT I²=68%; Chernev χ²(78)=665.5, p<.001).
   Chernev's *own headline is pro-overload*. This kills "more options always harms"; it does
   **not** license "option count is irrelevant in my design."
2. **The corpus has essentially no data near 3–7.** Chernev's large assortments: median 24,
   mean 27.8, SD 3.7. The literature is *silent* about small sets, not supportive of them.
   The one inverted-U proposal (Reutskaja & Hogarth 2009) peaks around **10**, and is the
   hypothesis SGT tested and could not substantiate.
3. Dean, Ravindran & Stoye (arXiv 2212.03931) argue the paradigms are underpowered and find
   "strong evidence of choice overload" under a better test. Don't over-read the null either.
4. These are **retail product assortments**, not multi-line rule edits in a tactics UI.

## 3. The one moderator that matters here runs *against* the folk rule

> "decision makers with strong prior preferences or expertise benefit from having **more**
> options to choose from."

SGT meta-regression: **b=-.50, SE=.20, z=-2.49, p=.013** against an intercept of +.11 — the
predicted effect **flips sign**, a reversal, not an attenuation. Chernev confirms it
independently via "preference uncertainty": for unfamiliar consumers larger sets raise
deferral; "for expert consumers, the impact of assortment size is reversed." SGT could
identify only **necessary** preconditions for overload, never sufficient ones, and the chief
one is *lack of familiarity with or prior preferences over the items*.

**Read-across — this is the empirical basis for TIERING rather than REPLACING.** A player who
has not yet formed preferences over gambit space is the overload case. A player who has is
the case that *benefits from the full editor*. It also reframes the generated set's job:
**helping the player form preferences over gambit space is a learnability goal, not a
load-reduction goal.**

## 4. Autonomy is the biggest lever, and UI polish is not it

Ryan, Rigby & Przybylski (2006, Study 4), as tabulated in Przybylski, Rigby & Ryan 2010
(*Review of General Psychology*), **N=730**, simultaneous regression against competence,
relatedness and Yee's three motives:

| predictor | → enjoyment | → post-play well-being |
|---|---|---|
| **autonomy** | **β=.49** | **β=.36** |
| competence | .24 | .12 |
| relatedness | .12 | .03 (ns) |

Autonomy is the largest |β| of all six predictors in both models (model R²=.45).

And separately, across three studies, **"mastery of controls" predicted enjoyment as expected
but no longer accounted for unique variance once in-game need satisfaction was entered**;
2006 Study 1's mediation reduced intuitive controls to non-significance once autonomy and
competence entered, and Study 2 found controls predicted motivation *only in the preferred
game*. The authors' own line: "merely having a low 'price of admission' or ease of control is
not enough to motivate players."

**Directly: polishing the gambit editor's usability cannot by itself make the turn beat
motivating — and whatever replaces it must preserve felt volition or it trades the problem
for a worse one.**

**Qualifiers.** β is not a variance share — say "largest unique standardized coefficient."
Self-selected MMO forum sample, **679/730 male**, mean age 22.1, cross-sectional single
self-report instrument (common-method variance), data ~20 years old. The ordering of the
three needs varies by context in the wider literature: this is *this sample's* ordering, not
a law. Johnson, Gardner & Perry (2018, IJHCS 118:38-46) found PENS Competence and Intuitive
Controls load on a single factor, which makes the mediation close to tautological.

## 5. Two craft primaries that both point somewhere uncomfortable

### 5.1 Costikyan — the ingredient is *struggle*, not options

*I Have No Words & I Must Design* (2002, author-hosted PDF). He opens with "What makes a
thing into a game is the need to make decisions", **explicitly hedges it** ("Perhaps decision
making is too strong a concept"; in fast games "winning depends more on quick response and
interface mastery than careful planning"), and then **drops decisions entirely from his final
functional definition**: "an interactive structure of endogenous meaning that requires
players to struggle toward a goal."

His "Plucky Little England" counterexample speaks *directly* to a curated option set: a
dramatically framed A/B choice where you instantly win produces nothing — **"it was all too
easy, wasn't it? There wasn't any struggle."**

> **A rollout-ranked list where one option is visibly the solver's best pick reproduces
> Plucky Little England with extra steps.**

He also sets a two-sided bar our architecture is at direct risk of failing: the algorithms
must be *"both complex enough to pose difficult choices to the players, and simple enough
that the player will not be mystified by the game's behavior."* (Caveat: it sits in a closing
self-interrogation checklist phrased as a rhetorical question; and the Mindtrek 2022 paper on
illegible/opaque design — Dwarf Fortress, hidden-mechanic roguelikes — disputes whether the
legibility half is universally required. Treat mystification as **a risk to instrument, not
an absolute bar.**)

⚠️ Attribution: "the obvious move problem" is **not** Costikyan's term — his stated mechanism
is "too easy / no struggle". And do not call this a "pre-echo of Sid Meier": Meier's aphorism
dates to ~1989 GDC and its provenance is contested. Say "parallel to."

### 5.2 Chen — embed the choice in the verb; and P(victory) is blind

Jenova Chen's 2006 MFA thesis. On out-of-band choice prompts: the choices "have to appear in
a relatively high frequency… The easy solution that might come to mind is to implement a
monitor system to detect whether or not it is a good time to offer choices… However, monitor
systems are still not mature enough… **The only solution is to embed choices into the
gameplay.**" Conclusion: "Embed DDA choices into the core gameplay mechanics and let player
make their choices through play."

And his four structural failures of system-inferred adaptation include one that lands square
on our rollout scorer: **"Performance does not mirror Flow"** — his example is a player in
flow "just jumping around… but not finishing any level." **A player enjoying a losing line is
invisible to a win-probability objective.**

**Evidence grade: low.** 2006 MFA thesis; practitioner argument with illustrative anecdote —
no n, no instrument, no control arm. Two modality corrections: Chen wrote monitor systems
"are still **not yet** mature enough" — a contingent 2006 claim, not an in-principle
impossibility (the 2024 Springer DDA review and the affective-DDA line pursued exactly that
third option with partial success). And his scope is **difficulty adaptation**, not all
strategic choice, so transferring it to a frozen tactical turn is an analogy the source does
not license.

### 5.3 Into the Breach — full information is workable, but it is not a UI change

Subset Games, GDC 2019 postmortem (deck + 3,565s talk transcript both pulled). "Telegraphed
Attacks • All enemy attacks shown • No hit / miss chance • Completely deterministic (during
player turn)" was the **held constant everything else followed from**. Because a telegraphed
threat "shrinks to something incredibly small" and dodging becomes trivial, "managing the
threat no longer becomes part of the game… 90% of the tactics game was about managing the
threat, then that kind of breaks the game."

Their answer was a rebuild, not a tweak: relocate threat onto **defenceless objects**
(buildings "can't run away"), move the fail state to the power grid, the win state to a
per-battle turn limit, and the player verb from killing to manipulating — **"Killing enemies
isn't as fun as manipulating them."**

Two more things in that deck matter to us:
- Their *subjective constraints* list puts **"Readability • Limited menus • Low-Numbers •
  Streamlined • Minimize Wasted Time"** as **peers of** "Interesting Choices", not as
  subordinate to it.
- **"Playing with Turn Order • Complex rules, but not deep."** And the strategy layer
  failed because **"We ignored the constraints imposed by the combat."**
- When they later re-added randomness to the deterministic design (power-grid resist), the
  deck's own note is that it **"Annoyed players"** — i.e. the determinism decision is **not
  reversible piecemeal**.

**Grade: n=1 practitioner craft, retrospective self-report.** "Forces" describes one team's
derivation, not a law. Determinism is scoped to the **player's turn** only — spawns, the ~15%
grid resist and island generation resolve outside it. "Static enemy stats" was a *development*
constraint, not a property of the shipped bestiary.

## 6. Killed in verification — do not quietly reintroduce these

Nine claims were refuted. Several would have been the most actionable items in the report, so
their absence is load-bearing:

| Claim | Vote |
|---|---|
| Chen's Traffic Light prototype is primary evidence against a freeze-and-menu beat | **0-3** |
| Narrowing an AI suggester's **scope** to one subsystem restores agency | **0-3** |
| Unexplained suggestions were the top complaint; **rationale-transparency** is the fix | **0-3** |
| The CHI '25 quantitative arm was null except a suspicious audiovisual-appeal difference | **0-3** |
| A **dominant** option in the set reduces deferral while equipotent options increase it | **0-3** |
| Costikyan's "not a game unless it's a struggle toward a goal" as a checkable test on an edit screen | **0-3** |
| No monotonic option-count relation ⇒ *therefore* no optimal set size (the inference, not the stats) | **0-3** |
| Chernev's **four-moderator lever set** (task difficulty, set complexity, preference uncertainty, effort-minimizing goal) | **1-2** |
| Experimentally manipulated control complexity undermines competence and raises aggression | **1-2** |

The "dominant option" kill is worth dwelling on: it means the corpus supports **neither**
"make the options equally attractive" **nor** "make one clearly best." That axis is open.

## 7. Coverage — what was NOT researched (treat as unknown, not as absent)

**This is the biggest caveat in the report.** Roughly four of six research questions got
partial coverage. **Nothing survived verification** on:

- MDA / LeBlanc's 8 kinds of fun, Lazzaro's 4 Keys, Koster's *Theory of Fun*, Burgun, Soren
  Johnson, Frank Lantz.
- **The entire indirect-control question** — FFXII gambits, FF7 Remake/Rebirth, Dragon Age
  tactics, Gladiabots, Screeps, Zachtronics, The Sims, RimWorld, Majesty, Mechabellum, TFT,
  Super Auto Pets. **The recurring failure modes of AI-configuration games (set-and-forget,
  one dominant config, edit-latency) are named in the brief but are NOT evidenced here.**
  For a game whose whole thesis is gambit configuration, this is the gap that most needs a
  second pass.
- **The entire drafting / curated-choice question** except CHI '25 — no Slay the Spire card
  rewards, no Hades boons, no autobattler shops, no Civ advisors, no BG3 recommended actions,
  no chess-engine hint-line effects on engagement.
- **The entire consequence-preview question** except Into the Breach — no XCOM hit-chance
  perception mismatch, no ghost/forecast preview patterns, no evidence on preview-induced
  solved optimization.

**Consequence: any recommendation about the FORM of outcome display — percentage, band,
ghost replay, distribution of rollout outcomes — is unsupported opinion.**

## 8. Recommendations, each labelled by what backs it

### R1 — Make the option set PULL, not PUSH. *(medium — direct empirical hook)*
Open the frozen turn on the unit and the board. Put the rollout suggestions behind an
explicit **consult** verb, and/or auto-surface only after a dwell threshold. These are the
two mechanisms CHI '25 participants asked for by name. Backing: §1 (push is the variable that
failed) + §4 (autonomy is the largest unique predictor, so trading autonomy for lower
cognitive load trades away the variable most associated with the outcome). The "undeserved
win" reports mean push is not merely neutral — it can **contaminate the competence payoff of
winning**. Transfer risk: onboarding study, n=20, expert-facing turn.

### R2 — Price the consult. *(designer opinion, zero evidential support)*
If consulting is a verb it can be a **scarce** verb — finite charges per unit per battle, or
a cost inside the freeze. That converts the suggestion from agency-removal into exactly the
kind of struggle Costikyan says an interesting decision requires. **Note for this codebase:
`src/gpu/ImperativeGambits.gd` already implements finite per-unit-per-battle charges from a
`Tune` constant (design §5), so consult-charges are a mirror of a mechanic that exists.**

### R3 — Keep the full editor, and tier it. *(medium — §3 is the real backing)*
The expertise reversal is the one moderator with a clear design consequence and it says
experts benefit from *more* options. Don't replace the editor; make the generated set the
on-ramp whose job is **helping the player form preferences over gambit space**. Design §4's
"all adjustment types legal" survives this untouched.

### R4 — Diversify by INTENT, not by a ranking. *(low — inference)*
Choose N from your **legibility budget** — how many options a player can hold the
*differences* between, given each is a multi-line rule edit, not an atomic pick — because the
literature has no N to give you (§2). Cluster by what the option is *trying to do* (turtle /
focus-fire / reposition / gamble) rather than by where it sits on a score, and **never show
the solver's confidence ordering as the primary presentation** — a ranked list of
near-equivalents is Plucky Little England. Honest tension I could not resolve: the claim that
a dominant option reduces deferral while equipotent options increase it was **killed 0-3**
(§6), so I cannot lean on it in either direction.

### R5 — Decide what the generator optimizes BEFORE building any preview. *(low — inference)*
P(victory) is provably blind to the player enjoying a losing line (§5.2). An option generator
tuned purely on win probability will systematically strip out the plays that are fun and
losing. Consider a second axis — outcome **variance**, **novelty** relative to the player's
current list, **edit distance**, or how legible the behaviour change will be on the board.
No source in this corpus offers a second objective; which of these produces a discriminable
set is untested anywhere I could verify.

### R6 — Stress-test the DIAGNOSIS before building the fix. *(low — the one I'm least able to support and most inclined to make)*
The evidence's centre of gravity suggests the turn may read as admin **not because the
editor's UI is bad but because the interesting choice has been lifted out of the core verb
and parked in a separate configuration moment.** Chen says embed it in the verb; Subset's
strategy layer failed because "We ignored the constraints imposed by the combat" and their
verdict on system sophistication that doesn't reach the board was "Complex rules, but not
deep." The untested alternative the evidence gestures at: **gambit edits made DURING
continuous combat as a live verb with its own cast time or cooldown, with the CT turn opening
as a widened window rather than a modal editor.**

⚠️ **Be honest about this one.** The corpus does **not** contain a demonstration that a
freeze-and-menu beat breaks flow or agency — the claim that Chen's Traffic Light prototype
was exactly that demonstration was **killed 0-3**. Chen's embedding argument is scoped to
*high-frequency difficulty* choices, whereas a CT turn is low-frequency and strategically
loaded — the case his frequency argument least applies to. What survives is a **convergence
of framings, not a result.**

## 9. Instrument for these, and note that one costs nothing to run

- **(a) One dominant configuration** — measure **edit diversity across a cohort**, not win rate.
- **(b) Set-and-forget** — measure how many turns pass with zero edits, and whether the option
  set is merely accepted at rank 1.
- **(c) Undeserved-win contamination** — CHI '25 participants volunteered this unprompted, so
  **ask directly in playtest**; it will not show up in behaviour.
- **(d) Mystification — buildable today, no preview UI required.** Ask a player to **predict
  what their committed edit will do** before resuming, then score the prediction against what
  the sim actually does. A low score is Costikyan's bar failing, and it is **measurable right
  now against the existing tree.**

## 10. Open questions the research could not close

1. **Does PULL delivery actually recover the agency that PUSH failed to add?** The CHI '25
   participants *asked* for a hint button and an idle trigger, but neither was built or
   tested. Their preference is a stated want, not a measured outcome. **This is the cheapest
   thing you could A/B in your own playtest, and R1 — the pivot of the whole report — rests
   on it.**
2. **What should the generator optimize, given P(victory) is blind?** (§R5.)
3. **Is the diagnosis "the editor is boring" or "the choice left the core verb"?** Until you
   can distinguish these, an option-picker may be polishing the wrong surface.
4. **Where is the line between a preview that clears the non-mystification bar and one that
   turns the turn into a calculation?** Nothing in the verified corpus addresses
   preview-induced optimization, the XCOM perception mismatch, or whether a distribution of
   rollout outcomes reads as information or as an answer key.

---

## Sources (verified, primary unless noted)

- Costikyan, *I Have No Words & I Must Design* (2002) — `http://www.costik.com/nowords2002.pdf`
  ⚠️ failing TLS certificate.
- Przybylski, Rigby & Ryan (2010), *Review of General Psychology*, and Ryan, Rigby &
  Przybylski (2006) — selfdeterminationtheory.org PDFs.
- Chen, *Flow in Games* MFA thesis (2006) — `https://www.jenovachen.com/flowingames/Flow_in_games_final.pdf`
- Subset Games, *Into the Breach* GDC 2019 postmortem — deck at
  `https://media.gdcvault.com/gdc2019/presentations/Into%20the%20Breach%20Postmortem%20Final.pdf`
  (the `ubm-twvideo01` S3 URL now **403s**, and the only Wayback capture is truncated at
  exactly 1 MiB of 4.15 MB — cite media.gdcvault.com); talk `https://www.youtube.com/watch?v=s_I07Iq_2XM`.
- Scheibehenne, Greifeneder & Todd (2010), *JCR* — `https://scheibehenne.com/ScheibehenneGreifenederTodd2010.pdf`
- Chernev, Böckenholt & Goodman (2015), *JCP* — `https://chernev.com/wp-content/uploads/2017/02/ChoiceOverload_JCP_2015.pdf`
- Dean, Ravindran & Stoye — `https://arxiv.org/abs/2212.03931`
- Choong, Cmentowski, Kukshinov, Tu & Nacke, CHI '25 Art. 464 — doi 10.1145/3706598.3713576.
  ⚠️ dl.acm.org 403s to fetchers; CC-BY publisher PDF mirrored at
  `https://pure.tue.nl/ws/files/357846420/3706598.3713576.pdf`
