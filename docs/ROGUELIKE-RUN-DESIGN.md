# The roguelike run — design

**Status:** design in progress, 2026-09-11. **Nothing built.** Supersedes
[`GAMBIT-BATTLE-DESIGN.md`](GAMBIT-BATTLE-DESIGN.md) §4 (see §9 below); everything else in
that document — the kernel, the CT turn model, the snapshot round-trip, the enemy rollouts —
stands unchanged.

Sections are marked **[DECIDED]** (the user said it) or **[PROPOSED]** (mine, awaiting a
call). Background research: [`TURN-BEAT-OPTIONS-RESEARCH.md`](TURN-BEAT-OPTIONS-RESEARCH.md).

---

## 1. Destination **[DECIDED]**

A roguelike run. You play a scenario, you are offered rewards, and you build a **team** the
way a deckbuilder builds a deck: units get stronger, and you recruit new people as you go.
Abilities are **not** learned with JP — they arrive as battle rewards.

## 2. The atom: a card is an ability **plus** its gambit **[DECIDED]**

A card ships coupled: *Cure — when an ally drops below 40%*. The player never authors a rule
from parts; they acquire a rule already written.

This is the whole reason the turn stops feeling like admin. Rule *authoring* is clerical;
rule *placement* is not.

## 3. Two layers, and the line between them **[DECIDED]**

| | Where | What you do |
|---|---|---|
| **Run layer** | Between scenarios | Build the deck: rewards, shop, recruits, equipment, jobs |
| **Battle layer** | In a scenario | Play it: draw a card, place it in a unit's priority stack |

**Build time and play time are separate.** Nothing is authored or configured during a battle.

## 4. The battle turn **[DECIDED, except 4.3–4.4]**

A unit's CT turn opens; the world freezes (unchanged — `TurnDirector`, `TurnBeat`). Then:

1. **Draw a card.**
2. **Place it in the priority stack** — position is the decision, and it is the only one.
3. Commit. The world resumes; the new row is live immediately.

**4.1 — Five slots, and displacement is the point.** `MAX_USER_GAMBITS = 5`
(`src/gpu/GPUConstants.gd:16`, ADR-0048 — 5 authored + 1 encoder-injected safety net). Once
full, playing a card means **cutting one**. That is a harder decision than the early-battle
ones, so the decision curve rises across a battle rather than flattening. **Do not raise
this number.**

**4.2 — Every card is a Power.** A placed card persists for the rest of the battle. There is
no discard-after-use; the stack is an engine you build mid-fight.

**4.3 — Deployment is the deck. [PROPOSED]** Draw from the **union of the deployed squad's**
learned cards, and **install on the unit whose turn it is.** Consequences:
- Bringing a unit brings their cards, so deployment *is* deckbuilding. The cap is already
  real: `max_squad_size` off the ATTACK.OUT zone record
  (`src/strategy/DeploymentAssignment.gd:90`, floored by available tiles).
- Recruiting is no longer free accumulation — it dilutes the draw. That is the deck-bloat
  tension, and it is what makes a recruit a decision.
- The turn constraint is the struggle: you drew a heal and it is the Knight's turn. This also
  makes the §6 turn-queue forecast a tension instrument.

**4.4 — Opening hand at deployment. [PROPOSED]** Deal each deployed unit 2–3 cards to place
*before* the first tick. Without it, units start with empty stacks and stand around for the
first several turns.

**4.5 — Skip/discard is the reroll economy. [PROPOSED]** Priced against the existing
imperative charges (`src/gpu/ImperativeGambits.gd`, finite per unit per battle from a `Tune`
constant) so one scarce resource has two uses.

## 5. Glimmer **[DECIDED; 5.1–5.3 PROPOSED]**

SaGa Frontier's spark. Mid-battle, a unit randomly learns a new card: lightbulb over the
head, and it fires immediately.

**5.1 — A glimmer is not a decision.** The ability fires, and the card lands in that unit's
**deck** — not in the 5-slot stack. Whether to keep it is asked at the **reward screen**.
This keeps the moment a pure reward and never makes it a menu interrupt.

**5.2 — Do not freeze for it.** Slow-mo ~0.5 s, sound, lightbulb, sim keeps running.
Freezing the world for something the player does not decide is the worst of both worlds.

**5.3 — It must be aimable, not a lottery.** SaGa's spark is *conditional* — it fires off a
related technique against an enemy above a difficulty threshold, rate scaling with how much
stronger. That is why it read as a system rather than noise. Two rules follow:
- **Glimmers come from a tech family.** Using Cure often is what sparks the better heal, so
  a player who wants a thing can chase it. The randomness is *when*, not *whether*.
- **Rate scales with threat**, which makes the run map's harder branch worth taking. This is
  the run's risk/reward axis and it needs no other mechanism.

**5.4 — Keep the rate low.** Glimmer and the post-battle draft compete as card sources. If
glimmers are common the draft stops mattering. The draft is the main channel; glimmer is
the spice.

## 6. The run layer **[DECIDED; 6.2 PROPOSED]**

**6.1 — Rewards.** Win a scenario, get offered cards (dealt, not browsed) and sometimes a
recruit. This is where the full gambit editor lives, unhurried, competing with nothing.

**6.2 — The shop's headline item is removal, not new cards. [PROPOSED]** Deck thinning is
the strongest lever against the draw randomness, because a five-card deck draws its Cure
five times more reliably than a ten-card one. New cards are what you buy when you know what
you want; removal is what you buy when you know what you don't. It also closes the loop with
glimmer: **glimmer gives you a card free → keeping it dilutes your draw → the shop sells the
fix.** That makes the reward screen's "keep it?" a real question rather than a free yes.

**6.3 — Damage carries between battles. [DECIDED]** Units are not restored to full at the
next battle's start. This is what makes the map's risk/reward axis exist at all: without
persistent damage the hard branch is free and you always take it, and every town/battle fork
in §7 has nothing to trade against. Paired with FFT's crystal timer for permadeath, it is the
run's attrition curve.

## 7. The run map **[SEE §7.4 — restrict vs rebuild is OPEN]**

### 7.1 The finding

The ported world map is **not linear**. `assets/world_map/model.json`: 43 nodes, 48 routes,
mean degree 2.29, **15 nodes of degree >=3**, only 5 dead-ends, and 48 edges over 43 nodes =
**6 independent cycles**.

Oriented from node 14 to node 17 (the diameter, 12 hops) the rows are:

```
1 -> 2 -> 3 -> 2 -> 3 -> 2 -> 3 -> 4 -> 3 -> 3 -> 3 -> 3 -> 1
```

33 of 42 nodes participate and there are **60 distinct simple routes** across it. That is a
Slay the Spire act silhouette: one entrance, 2-4 branches per row, converging on one boss.

Node kinds are **15 towns / 28 battlefields** (`kind` 1 vs 2), close to StS's own
combat/non-combat ratio — and they **interleave on every row**, so the town-or-battle fork
exists the whole way down:

```
 0  1T     Zarghidas Trade City
 1  1T 1B  Zeltennia Castle * Germinas Peak
 2     3B  Nelveska Temple * Finath River * Poeskas Lake
 3  2T     Limberry Castle * Bervenia Free City
 4     3B  Bed Desert * Dolbodar Swamp * Doguola Pass
 5     2B  Bethla Garrison * Grog Hill
 6  2T 1B  Lesalia * Yardow Fort City * Zirekile Falls
 7  2T 2B  Goland * Zaland * Yuguo Woods * Araguay Woods
 8  2T 1B  Riovanes Castle * Dorter Trade City * Zeklaus Desert
 9     3B  Orbonne Monastery * Fovoham Plains * Sweegy Woods
10  1T 2B  Gariland Magic City * Fort Zeakden * Lenalia Plateau
11  1T 2B  Igros Castle * Murond Holy Place * Mandalia Plains
12     1B  Thieves Fort
```

⚠️ Reverse this orientation in practice — as computed it runs Zarghidas -> Thieves Fort, which
puts Gariland, Igros and Orbonne at the *end*.

Reproduce: read `routes` as undirected edges, BFS for the diameter, layer by
distance-from-source, keep nodes with `d_source + d_sink <= diameter + 2`.

### 7.2 What is actually incompatible **[DECIDED]**

Not the geometry. Three rules:

1. **Travel is undirected and free** — `WorldMapTravel.route_path` BFS-pathfinds between any
   two known nodes, so you can always go back.
2. **Six cycles**, so backtracking is available geometrically too.
3. **Reveal is story-script-driven** — `NODE_KNOWN_BASE` is set by the plot, so the player is
   walked along a spine and never chooses.

Cycles + free travel = **nothing ever forecloses**, and foreclosure is the entire mechanism of
a Slay the Spire map.

### 7.3 Routing with foreclosure **[DECIDED]**

Towns are **nodes you route through at a cost**, not interstitials handed out after each
battle. Standing on a node you are offered the 2-4 nodes on the next row; **taking one closes
its siblings for this run.** Guaranteed battle->town->battle->town is rejected: a fixed
sequence is a rhythm, not a decision.

Three rule changes deliver it:

1. **Orientation** — pick a source/sink per act, keep only forward edges. Different pairs give
   differently-shaped acts over the same geography, so four chapters are four orientations.
2. **Forward-only travel** — replace BFS-to-any-known-node with "the nodes on the next row."
3. **Run-driven reveal** — drive `NODE_KNOWN_BASE` from run state, not the story script.

### 7.4 OPEN: restrict the ported map, or build a bespoke one?

**The user's position** (2026-09-11): *"we are going to need to alter the world map... this
linear world map doesn't feel compatible with a roguelike."*

**The argument against, from §7.1:** orienting *removes* edges and adds none, and that
distinction is the whole cost question. `WorldMapTravel` is a **port of a console
measurement** — waypoint-for-waypoint against `WLDCORE.BIN`; §29.6 drove real hardware for
2,709 vsyncs and `travel.py` reproduces it. Every edge carries hand-measured curved waypoints,
headings and frame-list ids. **Inventing edges is exactly what breaks that**; a bespoke map
means every path is a straight line or hand-authored. Restriction costs nothing and keeps the
renderer, the PSX shaders, the cels/frames/layout, the town page, the start menu, the reveal
animation and every waypoint.

**What a bespoke map would buy:** node identity is fixed in the ported map — Gariland is
always Gariland — so per-run freshness has to come from **contents** (which battle, which
services, which threat tier) rather than from geography.

**The known risk of restricting:** the rows in §7.1 are *graph* layers, not screen positions.
Nodes sit at real Ivalice coordinates, so a row will look scattered rather than lined up.
Mitigation is a UI affordance, not a redraw — **highlight the 2-4 reachable next nodes** on
the existing art. Unverified: nobody has looked at it on screen.

### 7.5 Town services **[PROPOSED]**

`WorldMapTownPage` already draws a **Bar / Shop / Soldier Office** list. Roll a **subset per
node per run** — if every town offers all three they are interchangeable and routing between
them is not a decision.

| FFT furniture | Run-layer job |
|---|---|
| **Shop** | Buy cards, and **removal** (§6.2's headline item) |
| **Soldier Office** | Recruit — FFT's own hire-a-generic mechanic, the "new people" channel |
| **Bar** | Rumors and propositions — the `?` event node, and where you learn what is *ahead* |

The Bar is where "the sim informs you about the world, never about your choice" lives in
fiction: a rumor that the next battle is heavy on casters is what makes routing a real
decision.

### 7.6 Act and run-loss **[PROPOSED]**

An act is a chapter, ending at its story battle. The run ends when **Ramza falls** — the
ATTACK.OUT scenario table already carries the Ramza-mandatory flag.

## 8. Legibility: show which row is firing **[PROPOSED — and load-bearing]**

Position is the only decision in a turn, so a player must be able to see *why* slot 2 beats
slot 4. One readout fixes it: **highlight the gambit row each unit is currently firing,
live.** It teaches the priority model by demonstration instead of explanation.

Cost, checked: not free. The per-unit decision-history ring buffer exists and already flows
GPU→CPU every tick (`record_decision`, `src/gpu/shaders/stage_compute.glsl:440`; decoded in
`CombatLoop._process_thrash_detection`), but its `reason` field is 4 bits with **all 16 codes
assigned** (`combat_common.glslinc:573-591`) and none names the winning slot. Needs a new
unit field. The channel is built; the value is not.

**Without this I do not think the design is teachable.** Budget it as part of §4, not as
polish.

## 9. What this overturns

- **`GAMBIT-BATTLE-DESIGN.md` §4 ("all adjustment types legal" on a turn)** is reversed.
  There is no editing in battle at all — only drawing and placing. Equipment, job and ability
  changes move to the run layer. ⚠️ The keystone snapshot round-trip keeps its justification
  (enemy fork, undo-on-cancel, save/load) and is not affected.
- **JP.** FFT's progression is grind-shaped and a run is draft-shaped; you cannot farm a job
  tree in 90 minutes. Abilities come from the reward pool instead. This is a real redesign of
  a signature FFT system, made deliberately.

## 10. Open questions

1. **Per-unit decks or the deployed union (§4.3)?** The union is the proposal; it has not
   been tried.
2. **Two layers of acquisition RNG** — draw plus glimmer — may still read as arbitrary even
   with §5.3's conditioning. Instrument before adding a third.
3. **How much watching will a player tolerate?** This is the autobattler question and the
   research came back with **nothing** on the genre (TFT, Mechabellum, Super Auto Pets,
   Gladiabots were all uncovered). §5 is the proposed answer — glimmer makes the between-turn
   stretch anticipatory rather than merely informational — but it is untested.
4. **Restrict the ported map or build a bespoke one (§7.4)?** The only open question with a
   stated disagreement on it. Everything else in §7 holds either way.
5. **Do the graph rows read as rows on screen (§7.4)?** Nobody has looked. If highlighting the
   reachable set is not enough, this is what would force a redraw.

## 11. What already exists

| Thing | Where |
|---|---|
| 5 authored gambit slots | `src/gpu/GPUConstants.gd:16` (ADR-0048) |
| Deployment cap from ATTACK.OUT | `src/strategy/DeploymentAssignment.gd:90` |
| A unit's ability container (the draw pool) | `src/units/EquippedAbilities.gd` |
| Gambit → English | `src/ui3/GambitProse.gd` |
| Live per-unit gambit writes | `GPUBatchSimulator.set_unit_gambits`, `:1349` |
| Finite per-battle charges | `src/gpu/ImperativeGambits.gd` |
| Turn freeze + beat | `src/gpu/TurnDirector.gd`, `src/gpu/TurnBeat.gd` |
| World map: 43 nodes, 48 routes, town/battlefield kinds | `assets/world_map/model.json` |
| Town page (Bar/Shop/Soldier Office) | `src/world_map/WorldMapTownPage.gd` |
| Per-node reveal flags | `WorldMapProgress.NODE_KNOWN_BASE` |
| Measured travel waypoints | `src/world_map/WorldMapTravel.gd` |
| Campaign/roster scaffolding | `src/scenarios/Campaign.gd`, `RosterTimeline.gd`, `NavigatorRunner.gd` |
| 480 scenario records (threat signal for §5.3) | ATTACK.OUT `@0x10938` → `assets/scenarios/scenarios.json` |

**Not built:** the card atom, the deck, the draw, run-driven reveal and forward-only travel,
rewards, the shop, glimmer, persistent damage, and §8's firing-row readout.
