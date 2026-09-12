# Free-ness inside the `rules` tier is declared per member, because a package of tables is not all tables

[ADR-0271](0271-the-tier-is-declared-in-plugin-cfg-because-a-vote-over-consumers-cannot-see-a-fourth-tier.md)
gave every addon a declared `tier=` and left one question open on purpose: `rules` is a
fourth tier and it is not in `_walk_roots.PORTABLE_TIERS`, so `check_addon_portability.py`
arm 5 prints **every** sibling reach into `exmateria_almanac` — 53 lines, all
`exmateria_catalogue`'s. Dec. 5 priced the obvious fix and rejected it: of the almanac's
~700 consumed lines, **83% sit on members two or more of the eleven systems reach**, so a
wholesale free verdict would silence
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 6 over a real surface, and *"a
wrong bucket is a claim someone can falsify, and silence is not."*

This ADR takes the split ADR-0115 dec. 7 actually draws — *"the driver ships, the banks
are content"* — and makes it a **declaration on each member**, the way ADR-0271 made the
tier a declaration on each package. Arm 5 goes from **354 free / 53 debt** to **371 / 36**,
and the 36 that survive are exactly the members declared `state`.

Status: accepted (2026-09-09). This is **#1059 phase 2**; phase 3 is not decided here and
dec. 4 says why it cannot be. Reads
[ADR-0115](0115-a-system-is-a-bundle-that-ships.md) dec. 4 for the content shadow, dec. 6
for a feature threading systems and dec. 7 for the line this splits on,
[ADR-0212](0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md) dec. 1 for why the
façade's address is derivable rather than declared,
[ADR-0241](0241-unitprogression-is-the-catalogues-by-ownership-and-src-datas-by-address.md)
dec. 1 for `UnitProgression`'s ownership,
[ADR-0262](0262-the-alias-route-hid-forty-nine-lines-and-the-almanac-reads-as-a-system-only-because-classify-books-by-consumer.md)
dec. 5 for the accepted debt,
[ADR-0271](0271-the-tier-is-declared-in-plugin-cfg-because-a-vote-over-consumers-cannot-see-a-fourth-tier.md)
decs. 1, 3, 5, 6 and soft spot S4 for everything phase 1 landed, and
[ADR-0272](0272-the-palette-row-edge-is-paid-by-deleting-the-key-because-no-consumer-read-it.md)
for why the number is 53 and not 55.
**Supersedes nothing.** ADR-0271 stays accepted; its "Not decided" entry for phase 2 is
discharged by decisions 1 and 3, and dec. 5's rejected alternative is rejected again here
with a second reason.

## Context

Arm 5 asks one question — *may a sibling addon name this package's `class_name` for
free?* — and answered it with `free[home]`, a per-PACKAGE boolean read off the declared
tier. Four arms read that map, but arm 5 is the only one keyed on the reach's **target**
rather than its **subject**, and the only one holding a member name when it asks. That is
the seam this change lands on, and it is why nothing else moves.

The 53 lines it printed were never one thing. Split by the member they name:

| member | lines | declared kind |
|---|---:|---|
| `UnitProgression` | 32 | `state` |
| `JobDatabase` | 15 | `table` |
| `GambitList` | 4 | `state` |
| `SpriteDatabase` | 2 | `table` |

**Seventeen of the 53 are a system reading a ROM table**, which ADR-0115 dec. 4 says every
system is expected to do. The other 36 are per-playthrough state, and 32 of those are one
name that ADR-0241 dec. 1 **already ruled the Character Catalogue's by ownership**. Printing
all 53 under one heading said none of that.

🔴 **AND THE ARGUMENT FOR PRINTING THEM PRICES A DIFFERENT REGISTER FROM THE ONE ARM 5
READS.** ADR-0271 dec. 5's 83% is measured over `src/` **plus** every sibling addon root.
Arm 5 scans addon→addon only. The four members dec. 5 names as the reason —
`GambitCondition` 76, `TargetSelector` 82, `Gambit` 57, `UnitRole` 24 — contribute **zero**
arm-5 rows today; all of that traffic is the host's, and the host consuming an addon is not
what this guard scores. Re-measured on this tree: 706 lines over 30 members, against dec.
2's 698 (the +8 is #1071 and the pass-3 addresses; a floor either way, ADR-0131 dec. 6).
That does **not** make dec. 5 wrong — the eleven systems are destined to become addons, and
the day Battle and UI are roots those lines become arm-5 rows — but it does mean dec.
5's cost is a **forward** cost, and the thing it was protecting was not being protected
today. (Those four members are 239 lines on this tree, against the 223 #1059's body quotes
for Battle-and-UI alone, taken before #1025 moved `src/characters/` out.) Recorded because a measurement quoted at the wrong register is
[ADR-0271](0271-the-tier-is-declared-in-plugin-cfg-because-a-vote-over-consumers-cannot-see-a-fourth-tier.md)
dec. 10's class of defect wearing a number instead of a citation.

## Decision

**1. Every member a `rules`-tier façade publishes DECLARES a kind, and nothing infers it.**
`const MEMBER_KINDS := { "Name": "kind", ... }` at the foot of the façade, one pair per
line. Three words, and the vocabulary is the decision:

| kind | what it is | arm 5 |
|---|---|---|
| `table` | a **bank**. Every answer it returns is STORED — a ROM table, a projection of one, or a fixed vocabulary. Reading it is ADR-0115 dec. 4's content shadow. | **free** |
| `rule` | a **driver**. It COMPUTES what the ROM computes rather than stores. `StatCalculator`'s own docstring says it verbatim — *"a rule over the table, not a table"*. | printed |
| `state` | a unit's own numbers, which is not a fact about the game at all. | printed |

`_walk_roots.MEMBER_FREE_KINDS` is `{"table"}` and is spelled once, beside `PORTABLE_TIERS`
and for its reason. `exmateria_almanac` reads **17 `table` / 11 `rule` / 3 `state`**.

**2. It goes in the FAÇADE, not in `plugin.cfg`, and the two homes are not inconsistent.**
ADR-0271 dec. 1 put `tier=` in `plugin.cfg` because a rig that *stages* the package reads
it with `sed` and a Python table in the host does not travel. Both arguments still hold and
neither selects `plugin.cfg` here: nothing stages a member, and the façade travels with the
addon just as `plugin.cfg` does. What decides it is the register ADR-0271 refused to create
twice — *"a declaration whose only job is to agree with a derivation is a register nobody
reconciles."* The façade is where each member is already named exactly once, so the kind
lands **beside the name it is about** rather than in a second list of thirty-one strings
that has to be kept in step by hand. It is also GDScript rather than an ini comment, so a
Godot-side consumer can read `ExMateriaAlmanac.MEMBER_KINDS` and check the claim.

**3. Arm 5 asks the free question of the MEMBER; arms 1, 2b and 4b are untouched.**
`member_free(home, name)` replaces `free[home]` in arm 5 only. A free TIER is still free
wholesale — every member of the kernel is shared vocabulary and every member of the port is
the platform seam, so there is nothing to split — and a `system` is still never free. `rules`
is the only tier where the package and the member give different answers. The other three
arms keep reading `free`, which is what keeps `Arm1HasALiveSubject`'s seeded witness live
across this change; verified by an A/B revert (dec. 7).

**4. `state` IS DECLARED, AND DECLARING IT DOES NOT SETTLE IT.** `UnitProgression`,
`GambitList` and `AbilityLoadout` are ADR-0271 soft spot S4's three — members that pass the
almanac README's purity predicate by its letter and fail it by its intent. The kind makes
the debt **36 lines and two names** instead of a paragraph. It does not move a file, and it
must not be read as ruling that state belongs in a `rules` package: ADR-0241 dec. 1 already
ruled `UnitProgression` the Character Catalogue's, and where the three live is **#1059 phase
3** and **#1060**. A behavioural change does not ride inside a declaration
([ADR-0167](0167-the-mount-inverts-to-the-host-and-the-fix-was-booked-into-the-bucket-it-drains.md)).

**5. 🔴 TIES GO TO `rule`, AND THE ASYMMETRY IS THE WHOLE TIE-BREAK.** A member wrongly
called `rule` costs a printed line somebody can falsify. One wrongly called `table` costs
silence. Three members are genuinely close — `StatusEncoder` and `ElementEncoder` are lookup
tables with a bitwise OR on top, and `UnitRole` is a classification derived from a stored
job type — and all three are declared `rule`. **The tie-break costs nothing on this tree and
is recorded anyway:** none of the three has an arm-5 row, so 371/36 is identical under
either reading, which is exactly when a rule is cheap to state and expensive to invent
later.

**6. FOUND WHILE VERIFYING THE CITATIONS: `ADR-0115 dec. 6` DOES NOT SAY "TWO".** Four
places in this tree paraphrase it as *"a feature threads two systems"*. Dec. 6 reads
*"A feature is not a system. **Gambits thread through three systems**; so does equipment."*
The general claim carries no number at all and the worked example carries three. This is the
**third** instance of ADR-0271 dec. 10's finding and the first that is a NUMBER rather than a
decision reference — which matters, because `check_adr_quotes.py` substring-matches a
`*"…"*` span against the ADR cited on the same line and a bare paraphrase carries no span to
match, so nothing could have caught it. Corrected in the two live-source sites this diff
already reads (`tools/_walk_roots.py`, `addons/exmateria_almanac/plugin.cfg`); ADR-0271's own
line 34 is an accepted ADR and is left, and ADR-0271 S5's sweep now has a third row.

**7. The register is proved by MUTATION, not by a green guard.** Every number above is read
off a guard that exits 0, and a green guard reads the same whether the register is consulted
or ignored. Two arms move one word and require the reds to land where predicted:
declaring `UnitProgression` a `table` must take the block **36 → 4** and the free block
**371 → 403**; declaring it a `rule` must move **nothing**, because `rule` and `state` are
different claims about a member and the same verdict for arm 5. An A/B revert of
`member_free` back to `free[home]` reddens exactly four arms — the three that read the
report's numbers and dec. 5's pricing arm — and nothing else.

**8. Both directions are reconciled BEFORE the first row is scored, and a mismatch RAISES.**
`declared_member_kinds()` cannot see `published_members()` and vice versa, so on its own
either is happy with a map naming thirty of thirty-one. The join runs once per `rules` root
at the top of the walk and raises with both lists in the message. A published member with no
row raises; a row naming an unpublished member raises too — that is #424's rule that a list
which may only shrink needs both arms, or it rots into a permanent exemption. A missing
entry is never a `.get(member, "table")`.

**9. The unresolved façade is not free.** `sibling_class_reaches` refuses to guess: a member
the façade does not publish resolves to the bare `ExMateriaAlmanac` rather than to itself.
That row names an INTERNAL of the package, which is a strictly worse dependency than naming a
published table, so it takes the printed branch and has its own arm.

## Considered alternatives

- **Adding `rules` to `_walk_roots.PORTABLE_TIERS`.** ADR-0271 dec. 5's rejected alternative,
  rejected again and now with a second reason. The first is dec. 5's: it silences 36 lines of
  per-playthrough state naming a package of rules, and ADR-0271 dec. 5's own sentence is that
  silence is not falsifiable. The second is that **it is not even a smaller number** — the
  total is 407 rows either way, because arm 5 prints its free block. The whole decision is
  which heading a row appears under, so choosing the wholesale branch buys nothing and pays
  the visibility. Its price is still a test rather than a paragraph
  (`test_freeing_the_rules_tier_takes_the_debt_block_to_ZERO`), re-priced to the new
  baseline. 🔴 **A handoff into this ticket read that test as phase 2's SPECIFICATION** — it
  is a tripwire on the rejected branch, and the two are indistinguishable from the assertion
  alone. The docstring now says which it is.
- **Inferring the kind from the member's name (`*Database`) or its subdirectory.** The
  cheapest possible reader and the exact defect #1059 exists to remove, one level down.
  ADR-0271 dec. 1's whole finding is that a proxy agrees with the intent right up until it
  does not, and both proxies are already wrong on the tree they would ship against.
  **By name:** nine members are spelled `*Database` and all nine are `table` — and there are
  **seventeen** tables, so the proxy misses `AbilityView`, `AbilityData`, `LearnableAbility`,
  `AbilityType`, `StatusRegistry`, `ReactionType`, `WeaponGraphicData` and `WeaponZeroFrames`.
  It under-counts by eight with a perfect record on the nine it sees, which is the shape of a
  proxy nobody re-checks. **By subdirectory:** six of the eight hold more than one kind —
  `abilities/` holds all three at once (five `table`, one `rule`, one `state`) and `jobs/`,
  `items/`, `status/`, `gambits/` and `progression/` each hold two. Only `encounters/` and
  `sprites/` are uniform.
- **Two kinds, `table` and `rule`, with no `state`.** Rejected by dec. 4. The free verdict
  is the same for both, so `state` buys nothing at the guard — and that is the argument for
  it: it costs nothing and it makes ADR-0271 S4's finding a **countable register** rather
  than a sentence in a soft spot. A vocabulary that could not say `state` would have had to
  call `UnitProgression` a rule about the game, which is the claim ADR-0241 dec. 1 already
  ruled false.
- **Splitting `exmateria_almanac` into a tables package and a behaviour package.** ADR-0271
  listed it and it is still out of scope for its reason: it is a membership change and it is
  #1060's subject. This ADR is what makes that ticket's price a number.
- **Declaring the kind in `plugin.cfg` beside `tier=`.** Dec. 2. Thirty-one names in an ini
  value is a second list of the façade's own contents, and ADR-0271 rejected a second
  unreconciled register for the system NAME on the same ground.
- **Freeing a member by counting its consumers — free where only one system reaches it.**
  Rejected outright: that is the majority-vote-over-consumers inference ADR-0271 dec. 1
  removed, rebuilt at the member level. It also inverts on contact with success — a member
  reached by one system today is free, and becomes debt the day a second system reaches it,
  which books a **new consumer** as a **new defect** in the package it consumes.

## Consequences

- **A member added to a `rules` façade without a `MEMBER_KINDS` row raises the whole guard.**
  Intended, and the same new way to stop the pre-flight that ADR-0271 introduced for `tier=`.
  The message names both lists and the fix.
- **`exmateria_catalogue`'s debt row is 36, not 53**, and its README, both `plugin.cfg`
  prose blocks and the almanac README now say which 17 moved and why. Those four sites also
  shipped **55** at phase 1, which #1071 had already made 53 on the same day; they are live
  source comments and are corrected here. ADR-0262 dec. 5 and ADR-0267's soft-spot note still
  read 55 and are accepted ADRs left unedited (ADR-0272's consequences carry that correction).
- **Only `exmateria_almanac` declares kinds today**, because it is the only `rules` package.
  The reader raises rather than defaulting, so the second one cannot join silently.
- The test register grows by 17 arms: the vocabulary and free set (1), the reader in both
  directions (7), the real tree's coverage and split (3), the end-to-end verdict (1), the
  three mutation and reconciliation arms (3), the unresolved-façade arm (1), plus the
  re-priced pricing arm.
- `docs/adr/AUDIT.md` and `INDEX.md` regenerate; `CLASSIFICATION.tsv` is hand-merged in
  landing order.
- 🔴 **FOUND WHILE WRITING THIS: `addons/exmateria_almanac/README.md` CARRIED FIVE BROKEN
  ADR LINKS, AND ONE OF THEM PROPAGATED INTO THIS ADR.** ADR-0212 is cited there as
  `0212-the-facade-is-folder-named-and-brand-prefixed.md`; the file is
  `0212-a-count-of-one-was-never-the-invariant-…`. The same README also mis-addressed
  ADR-0223, ADR-0184, ADR-0211 and ADR-0146 — every one of them a plausible slug that reads
  as a title rather than a path, which is exactly why none was ever clicked. All five are
  fixed here. **The instrument gap is the finding:** `check_adr_classification` resolves ADR
  links inside `docs/adr/` and caught this the moment the bad slug entered ADR-0273, but
  nothing resolves an ADR link from an addon README, so the same five sat green for as long
  as they have existed. This is dec. 6's shape one axis over — ADR-0271 dec. 10 found
  attributions nobody could check, and this is addresses nobody could follow. Worth a ticket;
  the check is `pathlib` over one regex and the corpus is nine READMEs.

## Soft spots

- **S1. The 17 freed lines are still printed, and "free" is a heading rather than a
  discharge.** Arm 5's free block exists precisely so the surviving install-time dependency
  is counted (ADR-0175 dec. 2), and `exmateria_catalogue` still does not parse where
  `exmateria_almanac` is absent. `deps=` already says so. What moved is the CLAIM about those
  lines, not their existence.
- **S2. `rule` reads ZERO on arm 5 today**, and a zero from an arm that has never printed a
  row reads the same as a zero from one that cannot. It is real — no sibling addon names a
  `rule` member — but the members that would produce those rows are consumed by `src/`, which
  arm 5 does not scan, so the arm has no positive control for the `rule` branch on this tree.
  The mutation arm in dec. 7 is the closest thing: declaring `UnitProgression` a `rule`
  exercises the printed branch through the vocabulary. A real control arrives when Battle or
  UI becomes an addon root.
- **S3. The kind is declared and its TRUTH is not checked**, which is ADR-0271 S4 one level
  in. Nothing tests that a member declared `table` only ever returns stored answers; that is
  phase 3's predicate applied per member rather than per package, and it is a harder guard
  than the purity one because "stored" is not a syntactic property. Until then `MEMBER_KINDS`
  is a claim about thirty-one members that only a reader can falsify.
- **S4. Dec. 5's tie-break has no live subject either.** All three close calls are members no
  sibling addon names, so the asymmetry it states has never actually decided a printed line.
  It is doctrine ahead of its first use, recorded so the first use does not get to invent it.
