# The reveal drain is an ordered pass, and the animation writes the bit

`Campaign.MASK_REVEAL` has been in the tree since the node script table was
decoded, and it has **zero callers**. `WorldMapProgress.set_node_known` and
`set_route_drawn` are called only from tests. So nothing in the port has ever
turned a reveal emit into a known node, and the map cannot open up: the opening
capture knows `{2 Igros, 6 Gariland, 24 Mandalia}` and draws routes `{1, 3}`, and
it stays that way forever.

The visible symptom is the spine stalling at story counter 4. Scenario 29 (*Family
Meeting*, the member of group root 28) writes `var[110] = 4`; at 4 the single live
`enter` is Sweegy Woods, node 26 — and node 26 is unknown, so `WorldMapCursor`
skips it and `WorldMapTravel` drops every route with an unknown endpoint. The
reveals that would have made node 26 known are four scripts on **Igros**, which is
where the marker is standing, and nobody runs them.

The obvious fix — loop `Campaign.query(marker, MASK_REVEAL)`, apply the emit,
re-query until it returns `{}` — **does not terminate**, and this ADR exists
because working out why re-shaped the whole thing.

Status: accepted (2026-09-04). Built on `feat/world-map-reveal-pass`. Consumes
**ADR-0179**'s single variable store and **ADR-0117 dec. 8**'s system split;
settles the Campaign↔map ownership question left open by **ADR-0172 dec. 1** and
**ADR-0176**; declines a constant on **ADR-0174**'s grounds.

## Context

### `MASK_REVEAL` selects five emit kinds, not two

`0xF80` is `0x080 | 0x100 | 0x200 | 0x400 | 0x800`. Against the shipped table that
is **107 of the 182 scripts**, not the 84 `reveal_route` + `reveal_node` the port
models:

| kind | mask | count |
|---|---|---|
| `reveal_route` | `0x080` | 43 |
| `pair100` | `0x100` | 4 |
| `here200` | `0x200` | 17 |
| `reveal_node` | `0x400` | 41 |
| `unary800` | `0x800` | 2 |

### The table is a choreography, not a set

Every reveal beat is a chain of triplets. Bethla Garrison at counter 47, in the
table's own order:

```
here200      [5]      | var[526]==0 AND var[110]==47
reveal_route [5,14]   | var[586]==0 AND var[110]==47
reveal_node  [14]     | var[526]==0 AND var[110]==47
here200      [14]     | var[554]==0 AND var[110]==47
reveal_route [14,42]  | var[587]==0 AND var[110]==47
reveal_node  [42]     | var[554]==0 AND var[110]==47
… four triplets, twelve scripts
```

Point the pen at a node, draw the road, light the town, move the pen. That is the
reveal animation everyone remembers, written down as data.

And it is why the re-query loop hangs. `here200` is **first** in the list, it is
guarded on `var[526]`, and the script that sets `var[526]` is `reveal_node [14]`
two scripts later. `Campaign.query` returns the first match. Apply it, re-query,
get `here200 [5]` again, forever. Nine nodes have this shape.

### The ROM was read, and it moved three answers from inferred to measured

`FUN_8006C894 @ 0x8006C894` — named by `WORLD_MAP_SCREEN.md`'s correction to §29.2
as the reveal runner rather than the ○ handler — is 90 instructions and does
**one emit per invocation**. It asks `FUN_80091238(*(0x8009F254), 0xF80)` about the
marker's node, returns immediately on 0, and otherwise dispatches on the result
word `*(0x800D4644)`:

| result bits | call |
|---|---|
| `& 0x180` | `FUN_8006DA88(OUT[0], OUT[1], (result & 0x100) != 0)` |
| `& 0xC00` | `FUN_8006DE50(OUT[0], (result & 0x800) != 0)` |
| `& 0x200` | `FUN_8006D7F4(OUT[0] == 0xFF ? marker : OUT[0])` |

Three facts fall out of that table and the functions under it:

- **`pair100` and `unary800` are not separate kinds. They are the erase
  direction.** `pair100` is `reveal_route` with the flag set; `unary800` is
  `reveal_node` with the flag set. One family, two directions, one animator each.
  The data agrees independently: every one of the six is guarded on the bit it
  must clear (`unary800 [30]` on `var[542] == 1`, and `542 = 512 + 30`).
- **The interpreter really is first-match, from script 0, every call.**
  `FUN_80091238` sets `s1 = 0` at `0x80091294` and walks from the top. There is no
  resume cursor anywhere in the ROM.
- **The emit does not write the variable — the animation does.** Op `0x22`'s
  handler at `0x80091D48` ORs `0x401` into the result word and stores the operand,
  and touches no game variable at all. The write is at **`0x8006DFA0`**, inside
  mode `0x36`'s tick, which is the node-reveal *animation page*:
  `FUN_800EF25C(node + 512, 1)` on the animation's first frame, paired with sound
  `0x77`; the erase arm branches past it and plays sound `2`.

And the runner is itself a page. `FUN_8006C894` has exactly two callers; one is
`0x8006C82C` inside `FUN_8006C7AC`, which the tick table at `0x8009E690` lists as
**mode `0x39`**. So the console's loop is: the drain page ticks, pushes one
animation page, that page sets the bit and pops, the next tick takes the next
script. Nothing gates the reveal runner — *being that page* is the gate.

### What is still unread, stated as such

`here200` writes no variable in any of the three functions read, and its guard is
the destination bit that a `reveal_node` three scripts later sets. On a strict
reading of "first-match every call" plus "only the animation writes", the console
would re-fire `here200` forever too. Something is unread — the `here200` page
chaining rather than popping, or another write. This does not block the port,
because decision 1 does not depend on it, but it is why decision 1 is **not**
described as a transcription.

## Decision

**1. The drain is an ordered pass over the node's script list, not a re-query
loop.** `CampaignRevealPass` holds a node index and a script cursor; each `step()`
scans forward from the cursor for the first script whose emit is in `0xF80` and
whose conditions pass **against the live store, right now**, applies its effect,
and returns a step descriptor. `{}` means the pass is finished.

The cursor is the whole difference. Conditions are re-evaluated live, exactly as
`FUN_80091238` does, so a triplet's `reveal_node` is what opens the next
`here200`; but a script is visited at most once, so a script that never clears its
own guard cannot be returned twice. Termination is by construction rather than by
a property of the data — which matters, because the property is **false**: 17 of
the 107 scripts do not clear their own guard.

This is deliberately not a transcription of the console's tick loop, for the
reason in the Context. It reaches the same end state by a mechanism we can prove
terminates, instead of by one we have only partly read.

**2. Campaign owns the table and the store; the map owns the presentation.**
`Campaign.reveal_pass(node_index) -> CampaignRevealPass` is the whole crossing.
The map never reads `events.json` — which is the rule `Campaign.gd`'s header
states as *Campaign asks the table, the map does not* — and Campaign never
animates, never draws and never touches a `WorldMapScene` node, which is the rule
ADR-0172 dec. 1 and ADR-0176 put on screen-owned visuals.

The doc conflict this settles was a false dilemma. `11-campaign-spine.md` said,
before this ADR's edit to it, that reveals are *drained by the map's own overlay
while it is open*; `Campaign.gd` says the map does not ask the table. Both survive: the map decides **when** and
paces the steps, Campaign decides **what** and writes the bits. It is the same
seam `node_entered → Campaign.enter_at()` already crosses, so this adds no new
one — port-list crossing C3 is where both live.

**3. A step applies the bit, because on the console the bit and the animation are
the same event.** `0x8006DFA0` is inside the animation page, not inside the emit
handler. Putting the write anywhere else — in the map, or in a batch after the
pass — would make the future animation a re-cut of this seam rather than a pacing
change. `step()` returns *after* writing, and what it returns is a description of
what just happened, for something to draw.

**4. The pass is stepped, not run.** `WorldMapScene` calls `step()` in a loop
today and everything lands in one frame. That is the *caller's* choice and it is
the only thing that has to change when the animation is built: pace the calls,
draw between them. Nothing about `CampaignRevealPass` moves.

**5. Reveal and unreveal are one family with a direction.** `reveal_node` /
`unreveal_node`, `reveal_route` / `unreveal_route`. `pair100` and `unary800` are
retired as names. `WorldMapProgress.set_node_known(i, false)` and
`set_route_drawn(r, false)` already take the flag, so the port needed no new
accessor — only the recognition that the fourth and fifth emit kinds were the
second half of the first and second.

Shipping the erase arms now rather than deferring them is not scope creep: they
first fire at counter 18, where Zirekile Falls removes the node and route that
Dorter drew at counter 16. A drain that only ever adds is a map that is wrong from
Chapter 2 onward, and it is wrong *silently* — an extra place on the list, not a
crash.

**6. `here200` is `look_at`, and it is returned as a step that does nothing yet.**
Its handler at `0x80091DC8` writes the selected-place word `0x800D0BB4` and hands
the node's `0x34` descriptor to `FUN_8008ED00`; `0xFF` means the marker's own
node. It is which node the screen is regarding. It applies no bit and today draws
nothing, and it is still returned, because it is 17 of the 107 scripts and it is
the choreography — dropping it would make the animation re-derive the pen moves
later and would make the step sequence diverge from the script list the test
asserts against.

It is **not** called `focus`, which was the name this ADR was drafted with.
`check_context_index` refused it: the vocabulary already spends `focus` on the
input-focus stack, and a reveal's look-at grants no input right to anyone. The
guard caught a collision the drafting did not.

**7. `reveal_route(a, b)` resolves by unordered endpoint pair, and that is total.**
The emit names two nodes; the bit is `556 + route_index`. Over the shipped
`model.json` all **48** routes have a unique endpoint pair, and over the table all
**47** route emits have a guard var exactly equal to `556 + the route that pair
resolves to` — zero mismatches, zero unmatched pairs. The lookup is therefore a
bijection on the data it is asked about, and the test asserts that rather than
trusting it, because an unresolvable pair would otherwise be a silently skipped
reveal.

**8. The trigger is map-open and arrival, and nothing else.** `WorldMapScene`
runs a pass in `_ready` and in `_arrive_at`. Those are the only two moments the
marker's node changes, and the store only changes while the map is *not* up —
scenarios write `var[110]`, the map does not. A per-frame check would buy nothing
until something can change the store with the map open, which nothing does.

Arrival is not optional. Counter 31's reveals live on **Dorter**, and counter 30
binds no hand-off at all, so the marker is elsewhere when the counter reaches 31:
Goland Coal City becomes reachable only because the player *travels* to Dorter and
the pass runs on arrival. Two more beats — Zeltennia on `var[170]`, Warjilis on
`var[165]` — are not gated on the story counter at all and can only fire this way.

**9. The sound cues are declined, on ADR-0174's grounds.** `0x77` and `2` are
read and recorded here; they are not ported. They belong to the animation, and a
sound id shipped with nothing to play it against is a constant nobody can score.

**10. `_conditions_pass` is unchanged.** Its `party has job → false` was flagged
as a possible new trade-off for a general reveal drain. It is not one: **zero** of
the 107 reveal-mask scripts is roster-gated. All 214 of their conditions are
opcode `0x01`. The six roster-gated scripts are all `enter` or `multi`.

## Prediction

Written before the pass was built, and scored after:

1. **The counter-4 beat reveals `{26, 9}` and draws `{11, 12}` from the opening
   capture, in one pass, with the marker on Igros.** *Held.*
2. **Every one of the 19 reveal beats terminates and leaves no live reveal
   behind.** *Held* — this is the property the re-query loop fails, and it is
   asserted mechanically rather than argued.
3. **The marker is already on the right node for every beat.** *Falsified, and
   usefully.* 17 of 19 beats are hosted on the node whose hand-off fired at
   counter `k−1`, so the marker is there by construction. The two that are not —
   counter 1 (Gariland, the boot node) and counter 31 (Dorter, with no hand-off at
   counter 30) — are what forced decision 8's arrival trigger. Had the prediction
   held, open-only would have shipped and Chapter 3 would have stalled.

## Consequences

- **The spine advances past counter 4**, and the four reveals at Igros fire the
  first time the map opens after *Family Meeting*.
- **The map now loses places as well as gaining them.** Six emits across three
  nodes remove a node or a route. Anything that assumed the known set is
  monotonic is wrong from counter 18.
- **`Campaign.MASK_REVEAL` has a caller**, and `set_node_known` / `set_route_drawn`
  have a production caller for the first time.
- **A test that seeds known nodes in its fixture is blind to all of this.**
  `WorldMapPlaceListTest` calls `set_node_known` in a loop and would pass against
  the defect unchanged. `CampaignRevealPassTest` builds its store from
  `new_campaign()` and never seeds a bit it is about to assert.
- **Seven story counters still bind no `enter`** — 14, 29, 30, 34, 40, 46 and 49 —
  so `live_enter_nodes()` returns 0 and auto-advance stops there. Five of them
  bind a `multi` (`0x004`), which `WorldMapScene`'s own arrival comment identifies
  as the **errands** list built by `FUN_8008D3C0`, not a hand-off. That is a
  different subsystem and a different stall; it is
  [#849](https://github.com/timbermania/fft-monorepo/issues/849) rather than
  folded in here.
- **The animation is owed, and its shape is now fixed rather than open.** It is
  pacing `step()` and drawing what it returns. Built by **ADR-0231**, which also read the
  three animation pages under `FUN_8006C894`'s dispatch and found the bit's timing to be
  per-direction rather than always the animation's first frame.

## Alternatives considered

**Loop `query()` until it returns `{}`.** Rejected — it hangs. Nine nodes open
their beat with a `here200` guarded on a bit only a later script sets, and
`query()` is first-match. This was the proposed fix and it survived until the
table was counted.

**Keep `query()` and add a "scripts already applied this pass" set.** Rejected. It
is the ordered walk with the ordering thrown away and then reconstructed from a
side table, and it re-queries from script 0 on every step to find something it
already knows the position of.

**Compute the whole step sequence up front and hand the map an array.** Rejected.
It has to predict what the store will be mid-pass, which means simulating the
writes against a scratch copy — a second copy of the one array ADR-0179 exists to
prevent. Live re-evaluation against the real store is both simpler and what the
ROM does.

**Put the drain in `WorldMapScene`.** Rejected: the map would have to load
`events.json`, which is exactly what keeping the table out of `model.json` was
structured to prevent.

**Put the animation in `Campaign`.** Rejected for the mirror reason — it would put
a drawing loop in the spine's state object, and ADR-0161 and ADR-0188 place the
screen's visuals on the screen.

**Apply the bits in a batch after the pass finishes.** Rejected. The console
writes the bit inside the animation, so a batch would put the one event in two
places and make the animation work a re-cut of this seam.

**Skip `here200` inside the walk.** Rejected — decision 6.

**Defer the erase arms until they are seen on a console.** Rejected. Their
guard/emit relationship is read straight off the data (each is guarded on the bit
it must clear), and the flag argument in `FUN_8006DA88` / `FUN_8006DE50` is read
straight off the disassembly. Deferring means shipping a map that is knowably
wrong from Chapter 2 for no gained certainty.

**Chase `here200`'s console termination before building.** Deferred. The pass
terminates by construction and does not depend on the answer; the only thing the
answer changes is whether this may be called a transcription, and it is simpler
not to call it one.
