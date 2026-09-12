# The lever set is a strict partition baked at load, and a hollow lever is an error

[#1101](https://github.com/timbermania/fft-monorepo/issues/1101)'s destination is a
**balance instrument, not a balanced game** — a named lever set over the ROM tables,
a two-mode rig that referees it, and a measured target, such that *"is this
balanced?"* is a command you run. This ADR is that map's **keystone**: every balance
ticket downstream authors into whatever it decides.

Charting settled four things and left five open. This ADR keeps the four — three
tiers, immutable ROM tables underneath, a data file rather than the `Tune` registry
for the lower two tiers, `Tune` slugs for the global scalars — and answers the five,
plus three more the measurements forced. **It authors zero factors.** The first real
numbers belong to [#1107](https://github.com/timbermania/fft-monorepo/issues/1107)
and [#1108](https://github.com/timbermania/fft-monorepo/issues/1108), where the
evidence for them will exist; what lands here is the schema, the loader, the guard,
and a lever set that is empty on purpose.

Status: accepted (2026-09-10). Resolves
[#1106](https://github.com/timbermania/fft-monorepo/issues/1106) and unblocks
#1107, #1108, #1119 and #1122. Reads
[ADR-0003](0003-unit-encode-is-a-single-looped-schema.md) for the
schema-with-a-pure-validator shape both guards here copy,
[ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md) dec. 13 for
why the pacing pair is `static var` and not `const`,
[ADR-0235](0235-reconfigure-is-an-overlay-and-the-shader-write-set-classifies-the-fields.md) for
the `carry` / `recompute` split that dec. 11 turns on,
[ADR-0047](0047-real-time-ability-cooldown-is-a-per-ability-floor.md) for the
128-ability ceiling dec. 9 reports against.
⚠️ **The mode-is-not-a-tunable line dec. 3 draws again was drawn first by
`godot-learning` ADR-0274, which is NOT ON THIS TREE.** It exists only on
[PR #1124](https://github.com/timbermania/fft-monorepo/pull/1124), open at the time
of writing, so this ADR cites
[#1109](https://github.com/timbermania/fft-monorepo/issues/1109) by issue rather
than shipping a link that does not resolve — the *resolved-is-not-landed* gap
#1101's Notes warn about, hit for real.
**Supersedes nothing.**

## Context

Four measurements taken on this tree, not reasoned. Each one killed a premise the
ticket was written on.

**1. The config buffer is thirteen ints.** `_build_config_data`
(`GPUBatchSimulator.gd:1363`) resizes to 13 and fills scalars. The ticket asked
whether a per-category table should ride it "the way the pacing pair does"; the
pacing pair rides it because it is two ints. A ~30-row table was never going to fit
that shape, and the question is really *where else*.

**2. There is no weapon table on the GPU at all.** Abilities have one — 512 records
x 14 fields, built by `GPUAbilityLoader.build()`. Weapons do not: a weapon reaches
the kernel **flattened into per-unit fields at pack time** (`wp` from
`prog.get_weapon_power()`, plus `weapon_range` / `weapon_flags` / `weapon_type` /
evade — `GPUCombatPacker.gd:505`). So the two tier-2 categories have structurally
different homes, and "how does a factor reach the GPU" has two answers, not one.

**3. 🔴 The ticket's three ability partitions do not disagree — two of them nest and
the third is not a partition.** Measured over all 512:

| key | classes | coverage | verdict |
|---|---:|---|---|
| `ability_type` | 10 | all 512, but **367 in one bucket** (`Normal`) | too coarse to be a lever |
| `formula` | 83 | present on **exactly** the 368 `Normal` records, absent on all 144 others | the resolution balance wants |
| skill set | 176 (111 non-empty) | **224 of 355 covered abilities sit in more than one**; 157 sit in none | not a partition at all |

`formula` and `ability_type` have **zero overlap**, so they compose into one total
taxonomy rather than competing. Skill sets cannot be a category key, because a
category key must assign each record exactly one class.

**4. The `ability_type` half is mostly hollow, and the cooldown ceiling cuts across
the whole taxonomy.** `Support` (32) and `Movement` (24) are `live: false` in
`UNIT_CONFIG_SCHEMA` with no extractor — declared, never produced. `Reaction`
reaches the kernel through a hand-written seven-entry map
(`REACTION_ABILITY_TO_REACT`, `GPUCombatPacker.gd:450`), so **7 of 32** are live and
the other 25 fall through to `REACT_NONE` by design; and none of the six quantities
is consulted on that path anyway. Separately, `cooldown_pre_validate` skips
`ability_id >= 128`, and against the taxonomy above:

- **60 of the 91 category classes sit entirely above the ceiling.** A
  `cooldown_ticks` lever on any of them reaches nothing.
- **14 classes straddle it.** `formula 8` has 41 members of which 25 are below, so
  one lever would move 25 and silently not move 16.

The first is the bit-0 trap one layer up — a well-formed, correctly-spelled entry
that encodes cleanly and never fires. The second is a shape neither the bit-0 trap
nor a hollow-check covers, because the category **is** reachable, just not for all
its members.

**5. Nothing stamps provenance on a corpus row.** `_write_corpus` writes
`round, battle, tick, <features>, terminal_*` and no configuration identity at all
(`tools/rollout_corpus.gd:348`). Every number this map's rig will produce is
meaningful only against the lever set that produced it, and there was no way to say
which one that was.

## Decision

**1. The vocabulary, because four objects were being called one thing.**
The file is a **lever set**; one entry is a **lever**; the number it carries is its
**factor**; the tiers are **global** / **category** / **record**; the product of all
three for one quantity on one record is its **effective factor**; a value that has
been through the layer is **levered**. All of it is in
`docs/context/42-balance-levers.md`. The last word earns its place on its own: a
unit's `wp` is levered and the item's `wp` is not, and that difference now takes one
syllable instead of a paragraph.

**2. Tiers 2 and 3 are BAKED AT LOAD, into whichever buffer already owns the
quantity.** Ability quantities into `GPUAbilityLoader.build()`; weapon quantities
into the packer's `extract`. The property the ticket calls load-bearing — a rollout
battle forks with the same configuration as the live one — **survives more strictly
than it would on the config buffer**, because a rollout forks the battle buffer and
the unit rows, so a baked factor is already inside the thing that gets copied. What
is given up is live scrub, and dec. 11 says how that is bought back.

**3. The pacing pair is a SEPARATE LAYER and is not in the lever set.**
`pacing.move_time_scale` and `pacing.damage_scale` stay exactly what they are:
in-shader, on derived quantities (`scale_move_ticks` / `scale_hp_transfer`),
config-buffer, `Tune`-slugged, live-scrubbable. **Neither has a per-record form,
because no record has a `damage` field** — so the ticket's "same quantity at three
resolutions" model does not actually hold for the two levers that already exist, and
folding them in would put two unlike things under one word. Inside the lever set,
"global" means a `{"by": "all"}` row over a **record** quantity. Dec. 10's digest
covers both layers.

**4. The quantity enum is CLOSED, six entries, split by floor.**

| quantity | domain | kind | floor |
|---|---|---|---|
| `wp` | item | capability | 1, when the ROM value was >= 1 |
| `weapon_range` | item | capability | 1, when the ROM value was >= 1 |
| `w_ev` | item | cost | 0 |
| `cooldown_ticks` | ability | cost | 0 |
| `charge_time` | ability | cost | 0 |
| `mp_cost` | ability | cost | 0 |

Closed means adding a seventh is a decision, not an edit — an open key space is how
the file becomes 300 magic numbers, and it makes dec. 9's *"this names a quantity
that does not exist"* check impossible to write. Six and not eleven because these
are the ones #1107 and #1108 already need: an enum is only closed if adding to it
costs something, and shipping five nobody asked for spends that discipline on
nothing. A field naming an **identity** rather than a magnitude — `formula_id`,
`element`, `flags`, `effect_id`, `inflict_mask`, `inflict_mode`, `weapon_flags`,
`weapon_type` — is deliberately absent.

The **capability floor is not decoration**: `Nagrarock` is `wp 1`, and without it a
10% nerf disarms the unit. A lever may weaken a weapon and may never silently
delete one; deletion is not a balance operation and must not be reachable by typing
a small number, which is also why a factor is bounded to `[0.05, 20.0]`.

**5. Every lever names its namespace explicitly, and the tiers MULTIPLY.**
`{"by": "formula", "key": 8}` / `{"by": "ability_type", "key": "Support"}` /
`{"by": "item_type", "key": "Bow"}` / `{"by": "ability", "key": 442}` /
`{"by": "item", "key": 12}` / `{"by": "all"}`. A reader never has to infer which
space an integer is in. Composition is

    effective = rom x global x category x record

so 1.0 is the identity at every tier. **Replace-semantics was rejected** because it
makes the category tier decay as you use it: under replace, moving a whole category
silently fails to move any record carrying an override, so the more you author the
less tier 2 does — which is the reason the tiers exist. The cost is real and stated
rather than buried: to say *"this record is exactly 1.5x, category notwithstanding"*
you author the reciprocal by hand.

**6. Every lever carries a `why` AND an evidence class.**
`measured` / `rom-faithful` / `placeholder`. A `why` alone degenerates into
restating the number in words; the class is what makes the file auditable, because
the rig can then report *"N of M factors are still placeholders"* as a first-class
number and the tuning loop that follows this map gets a burn-down. `placeholder`
with a one-word reason is legal, so the friction while dialing is a word, not an
essay. An empty `why` is an **error**, not a warning: a factor is a claim that the
ROM number is wrong for this kernel, and an unexplained one is a magic number with a
category attached.

**7. 🔴 The category key is a TAGGED UNION over a STRICT PARTITION.**
`formula` where a record has one, `ability_type` where it does not, `item_type` for
items. Given context 3 the two ability halves have zero overlap, so this is total,
and each half is keyed by the field that is actually populated there. A record is in
**exactly one** category.

The case that follows and that someone would hit in week one:
`{"by": "ability_type", "key": "Normal"}` matches **nothing**, because all 367
`Normal` abilities carry a formula. It is a hollow lever, and dec. 9's zero-member
check is already the thing that catches it — same mechanism, no new rule. A matching
rule (a record matches every category it belongs to, all matches multiply) was
rejected: it undoes what the tagged key buys, because answering *"what factor does
ability 42 get?"* would mean scanning the whole file rather than one lookup, and two
authors could move the same record without either seeing the other.

**The escape hatch is named here so the first person who wants it does not conclude
the format cannot do it**: *"all `Normal` abilities x0.9"* is not one row, and it is
not 82 either — it is `{"by": "all"}` plus nine `ability_type` counter-rows, and
those counter-rows are self-documenting about what is being held fixed.

**8. Reachability is DERIVED, never listed.** `MAX_COOLDOWN_ABILITIES` is scanned
out of `combat_common.glslinc` with a regex, the way
`overlay_behaviour_problems()` derives its floor from shader source — so the day
#1108 raises or removes the ceiling, coverage moves with it and nobody has to
remember this file exists. **An empty scan is an error, not a pass**: an unread
ceiling must not read as *"everything is reachable"*. The unreachable ability types
come from the ROM's own `ability_type` (`Reaction` / `Support` / `Movement` /
`None`), and item reachability is `ItemDatabase.is_weapon` — `wp` / `weapon_range` /
`w_ev` are read off the right hand and nothing else.

**9. The guard: hollow is an ERROR, partial is a REPORTED NUMBER, and errors abort
the measuring tools while the game only warns.**

`LeverSet.problems()` is pure and shared by the boot check, `abort_if_invalid()` and
`LeverSetTest` — the `unit_config_schema_problems` shape. Errors: unknown quantity;
unknown `by`; a category from the wrong domain (`formula` x `wp`); a category tier
with no key; a factor outside the bounds; an empty `why`; an unknown evidence class;
a duplicate `(quantity, category)`; a **zero-member** category; a **zero-coverage**
category. Warnings: a lever applying to only part of its category.

Blocking a partial lever was rejected because #1108 exists to remove the ceiling
that makes most of them partial, so the check would have to be un-written the day it
lands. Ignoring it was rejected because that is how you measure a balance change
that moved 60% of what you thought it moved. So the guard prints
`formula 8 x cooldown_ticks: reaches 25 of 41`, and #1111 gets something honest to
say: *"this verdict was produced by a lever set with 78% coverage."*

The **asymmetry between the game and the rig is the decision**, not an
implementation detail. A silently-inert factor corrupts a measurement without
failing it, which is worse than not running — so `tools/rollout_corpus.gd` refuses
to play. A typo in a balance file should not stop somebody playing — so
`GPUBatchSimulator._validate_lever_set` pushes the error and continues.

Alongside it, **the guard reports the worst REALISED factor per lever**. Every
quantity lands in an int buffer, so an arbitrary factor is not representable:
`wp 3 x 0.9` rounds to 3, a realised 1.0, and 29 of the 127 weapons carry
`weapon_power <= 5`. Rounding **half away from zero** beats truncation outright at
these magnitudes (truncation gives 2 — a 33% cut from a 10% lever) but it does not
fix the resolution, it hides it. The report is what makes the distortion a number
instead of a surprise in the corpus.

**10. 🔴 The digest hashes the OUTPUT, per sample, and may change mid-file.**
A hash of the composed effective factors plus the pacing layer's live values, on
**every corpus row** — `lever_digest`, a column and not a sidecar, because a sidecar
separates from its data and a row that travels alone loses the one thing that says
what produced it.

*Output* and not input: an input hash moves when a key is reordered or a `why` is
reworded — changes that alter nothing — so people learn to ignore the column; and it
stays still when a loader change alters behaviour without touching the file. Hashing
the composed result means the digest moves exactly when the numbers the kernel sees
move.

*Per sample* and not per write: read once at write time the column would be constant
**by construction** and could never witness the mid-run scrub it exists to catch — a
guard that passes because there was nothing to check. The composed half is folded
once per instance (the lever set is immutable at run time, dec. 11) so this costs a
short hash per row.

*May change mid-file*: a run whose CSV carries two digests is telling the truth about
what happened, and the reader can split or reject it. Freezing it at start would make
the file claim a uniformity it does not have. The corpus summary prints the distinct
count and flags `THE CONFIGURATION MOVED MID-RUN`.

**11. The reload affordance is a separate ticket, and it REFUSES while a battle is
live.** Dec. 2 gave up live scrub and owes a reload; that reload is buildable work,
not a decision, and folding an implementation into a keystone design ADR is how a
keystone stops being reviewable.

What is decided here is its **one hard constraint**. Baking into the packer's
`extract` means each quantity inherits its row's ADR-0235 reconfigure behaviour, and
those disagree: `wp` is `BEHAVE_CARRY` (the shader writes it — Break Weapon zeroes
it, `combat_common.glslinc:254`) while `weapon_range` and `w_ev` are
`BEHAVE_RECOMPUTE`. So a reload under a unit already fighting would re-derive two of
its three weapon quantities and keep the third — **one unit, two lever sets**.
Forcing a re-pack was rejected: it would override the exact behaviour ADR-0235
established for a measured reason, and silently un-break a disarmed unit. Accepting
it was rejected because dec. 10's digest would then report one lever set while the
battle ran under two. Refusing is one guard clause and it keeps the digest honest.

**12. The lever set ships EMPTY, and the guard is direction-tested against it.**
This is the smallest thing that makes the decision testable rather than asserted.
`LeverSetTest` is one `logic` process carrying 59 assertions, and **each of its ten
guard arms seeds one defect, asserts the rejection, then re-asserts the corrected
lever goes clean** — so an arm cannot pass by rejecting everything, which is the
failure mode a validator test has. Two arms search the live tables for their subject
rather than naming one (the straddling formula class, the cooldown-reachable
ability) and **red if no subject exists**, because an arm with no subject passes
vacuously.

## Considered alternatives

- **A per-category table on the config buffer, "the way the pacing pair does it".**
  The ticket's framing, and context 1 kills it: the config buffer is 13 ints. It
  also would not buy what it appears to — the fork property it exists for is
  satisfied *more* strictly by baking, because a rollout copies the buffers a bake
  lands in.
- **A parallel `U_*_FACTOR_Q8` unit field the shader multiplies at use.** The
  honest alternative to baking `wp`, and it keeps the ROM number visible in the unit
  row, which matters for display and for oracle diffing. Rejected at one unit-struct
  field per levered quantity, against a cost that is one glossary word (`levered`)
  and one comment at the bake site. Recorded because it is the right answer if
  oracle diffing ever needs to see both numbers at once.
- **`ability_type` alone as the ability category.** One flat key, much easier to
  read than a tagged union — and it puts **367 of 512 abilities in one bucket**, so
  it is not a balance lever at all.
- **Skill set as the ability category.** Named in the ticket as one of three
  candidates. It is not a partition (context 3), so it cannot be a category key.
  ⚠️ A first pass of this investigation reported skill sets as *absent from the
  tree*; that was a `grep` run from the wrong directory, and
  `assets/abilities/skill_sets.json` has 176 of them. The measured objection is
  stronger than the mistaken one and is the one recorded.
- **A matching rule instead of a strict partition** — dec. 7.
- **Replace-semantics for the record tier** — dec. 5.
- **A dense file, every category present at 1.0.** ~126 rows of mostly identity
  before anyone has decided anything, and a file that is 90% no-op trains readers to
  skim it. Sparse instead, with dec. 6's evidence class buying back the distinction
  it costs: a deliberate no-op is a `1.0` entry tagged `measured`, and silence means
  untouched.
- **`config/levers.json`.** `config/` already holds one hand-authored committed
  policy file (`ui3_registration_allowlist.json`), so the precedent exists.
  Rejected because the rest of `config/` is machine-scoped — `tune_overrides.json`
  is rewritten by the F3 panel — and the lever set is content the shipped build
  reads: a teammate's checkout must see the same levers.
- **Blocking a partially-applying lever, or ignoring it** — dec. 9.
- **Hashing the lever file's bytes** — dec. 10.
- **Restricting the category key set to a hand-listed reachable subset.** Loudest
  of the three options for the hollow case, and it hard-codes a reachability table
  that goes stale the moment #1119 builds something. Derived instead — dec. 8.

## Consequences

- **A unit's `wp` is no longer necessarily the item's `wp`.** Display, inspection
  and oracle diffing all see the levered number with no marker on the value itself
  saying so. With an empty lever set the two are identical, so nothing observes this
  today; the day #1107 authors a `wp` factor, it becomes real. The glossary word
  `levered` exists to keep the distinction sayable.
- **A corrupted loader hashes its own corruption confidently.** The price of
  hashing the output. A digest attests that two runs saw the same composed numbers,
  not that those numbers were the right ones.
- **Scrubbing a per-category factor now needs a reload**, and the reload does not
  exist yet, and when it does it will refuse mid-battle. Until then a lever change
  is a restart. Tier 1's pacing pair is unaffected and stays scrubbable.
- **The guard's coverage output will change under #1108 without this ADR being
  touched**, by construction — dec. 8. That is the intent, and it means a coverage
  number quoted in a ticket is only true against the tree it was taken on.
- **Six quantities is a floor, not a ceiling**, and the seventh needs an ADR
  amendment rather than a file edit. `formula_y` / `formula_x` / `effect_area` /
  `range` / `vertical` are the obvious next candidates.

## Soft spots

- **S1. The lever set is empty, so every bake site is currently the identity.** The
  loader, the composition and the floors are all exercised by `LeverSetTest` against
  synthetic lever sets, but **no shipped code path has ever baked a factor other than
  1.0**. The first real lever is #1107's, and it is the first time the two bake sites
  are proved end-to-end rather than in a unit test.
- **S2. Dynamic coverage is decided and not built.** Dec. 9 splits coverage into
  static (the boot guard, built here) and dynamic (the rig's report, over a seated
  roster). The rig is #1110 and does not exist yet, so today the instrument can only
  report the half that cannot see #1121's 5,103 weaponless slots — which is exactly
  the half that would certify a lever set the game never touches.
- **S3. `w_ev` is levered by the right-hand weapon's record, and `_get_evade_breakdown`
  aggregates.** `prog.get_weapon_evade()` is the weapon's own evade today, so the
  keying is correct; if that accessor ever folds in a second slot, the lever's
  category would be naming one contributor to a number it scales whole.
- **S4. `LeverSet.PACING_SLUGS` is a COPY of `GPUBatchSimulator`'s two slug
  constants**, made to avoid a class-level cycle (the simulator consumes this class
  through `GPUAbilityLoader`). Arm 8 of `LeverSetTest` reconciles the two registers
  and reds on a third slug landing — but it is still two registers, which is the
  shape ADR-0271 dec. 1 refuses to create where it can be avoided.
- **S5. The realised-factor report has no positive control on the shipped tree.**
  With an empty lever set there are no coverage rows at all, so the arm that proves
  it (the `Rod` fixture, where `wp 3 x 0.9` realises as 1.0) is a test fixture and
  not a live number. The first authored `wp` lever is what turns it into one.
