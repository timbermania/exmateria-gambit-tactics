# The reveal animation is three pages on the vsync clock

ADR-0230 built the [reveal pass](../context/11-campaign-spine.md) and left one thing owed.
Its decision 4 says it in as many words: *"the pass is stepped, not run … `WorldMapScene`
calls `step()` in a loop today and everything lands in one frame. That is the caller's
choice and it is the only thing that has to change when the animation is built: pace the
calls, draw between them."*

So the map opened with every reveal already applied, and a beat that on the console is a
pen moving between towns while roads draw under it was a single frame in which the map
was suddenly bigger. This ADR is the pacing, and the picture.

Status: accepted (2026-09-05). Built on `feat/world-map-reveal-animation`. Consumes
**ADR-0230** whole — nothing in `CampaignRevealPass` moved — and **ADR-0161**'s rule that
the screen's animations run on the console's vsync clock and never on a `Tween`. Reuses
**ADR-0177**'s reading of what is and is not an input-focus question.

## Context

### The console runs three animation pages, and all three were read

ADR-0230 read `FUN_8006C894`, the reveal runner, and stopped at the dispatch table. Under
it are three page pushes, and the tick table at `0x8009E690` names each one's tick:

| step kind | push | page | tick | what it draws |
|---|---|---|---|---|
| `look_at` | `FUN_8006D7F4` | `0x32` | `FUN_8006D928` | a **camera pan** to the node |
| `reveal_route` / `unreveal_route` | `FUN_8006DA88` | `0x35` | `FUN_8006DBB8` | the ribbon, quad by quad |
| `reveal_node` / `unreveal_node` | `FUN_8006DE50` | `0x36` | `FUN_8006DF4C` | sixteen vsyncs, and nothing else |

**The node page is a beat and only a beat.** `FUN_8006DE50` stores `0x10` into the page
record's `+8` (`ori v1,zero,0x10` at `0x8006DE58`) and the whole body of
`FUN_8006DF4C`'s per-frame arm is to decrement it and OR §28.1's rebuild bit into
`0x8004D950`. The pin is already on screen — the bit landed on frame 1 — so the sixteen
frames are the pause between one triplet and the next.

**The ribbon page is a walk with a measured speed.** `FUN_8008D9A0` resolves the route by
unordered endpoint pair (the same bijection ADR-0230 dec. 7 asserts), copies its polyline
into `0x800D3BE8`, and computes a per-quad hold table into `0x800D3BC4`:
`isqrt(dx² + dy²) >> 5` between consecutive waypoint *pairs*, `sra v0,v0,5` at
`0x8008DBC0`. The tick advances a quad when the hold expires. **On the shipped table every
one of those holds is zero** — the longest segment in `model.json` is 31.1 px and the
shift needs 32 — so a route draws at one quad per vsync and lands in 3 to 10 frames.

**The look-at page has no picture the port can have.** `FUN_8006D7F4` hands the node's
`0x34` descriptor to `FUN_8008EC38`, which arms a camera pan (`dist >> 8`), and
`FUN_8006D928`'s first act is to test the pan enable at `0x800D0AF8 & 1` — with none armed
it pops on that same tick. §21.1 is that the port's view never scrolls and there is no pan
at all, so the port is permanently in the branch that pops immediately.

### The bit and the picture disagree at one end, and it is not always the same end

ADR-0230 dec. 3 has the step write the bit and return, and the spine doc's **Reveal step**
entry states the console's timing as *"the bit lands on the animation's first frame"*.
That is true of the node **reveal** and of nothing else. Read in full:

| | bit written | at |
|---|---|---|
| `reveal_node` | animation frame 1 | `0x8006DFA0` |
| `unreveal_node` | animation frame **16** | `0x8006E048` |
| `reveal_route` | animation's **last** frame | `0x8006DD04` |
| `unreveal_route` | animation frame 1 | `0x8006DC10` |

The rule underneath is one rule and it is simpler than any of the four: **the bit changes
on the frame the thing appears or disappears.** A road is not there until it is finished
drawing; a pin is gone the moment the erase starts drawing it away.

### `0x800D3BBC` is the ribbon, not a selected route

`WorldMapTravel`'s header carries §29.6's *"`0x800D3BBC` — round 10's 'selected route' —
is not the traversal and is not read"*. It is read now: it is the ribbon animation's own
state block. `+0` flags (bit 0 = a walk is in flight, bit 1 = the emit named the endpoints
reversed), `+2` the route, `+4` the quad count, `+6` the quad cursor, `0x800D3BC4` the
per-quad hold table, `0x800D3BE4` the hold counter, `0x800D3BE8` the copied polyline.

### The input latch belongs to the ○ handler, not to the reveal runner

`WORLD_MAP_SCREEN.md`'s line 306 and §29.2 attribute `0x800D3C8C & 3` to
*"`FUN_8006C894`'s own **cursor-move animation latch**, set four instructions after the
gate it guards"*.
Every access to that address in the overlay is: one write at `0x80067EF0` (the screen
initialiser, zeroing it), one pointer form at `0x8006CD0C`, and three reads at
`0x8006CAD0`, `0x8006D0A8` and `0x8006D304`. **`FUN_8006C894` does not write it.** The
write is `*(0x800D3C8C) = (v ^ 2) | 1` at `0x8006CDA0`, inside `FUN_8006C9FC`'s
`0x8006CD08` block — the ○ handler's own cursor auto-move, armed for `0x20` frames at
`0x800D3C94`. The attribution is §29.2's, from before §32.1 corrected the entry point from
`FUN_8006C894` to `FUN_8006C9FC`; the sentence moved with the gate and the writer did not.

It matters here because it means the reveal has **no** input latch. What stops the ○
handler running during a reveal is that the reveal's animation page is pushed above mode 0
in the page stack at `0x800BB4F0`, so `FUN_8006C9FC` is not ticked at all.

## Decision

**1. The pacing is a stepper on `advance()`, and it is a fourth of the same kind the
screen already has.** `WorldMapRevealAnimation` owns the pass, holds each step for its
page's length, and answers three questions about the frame. `WorldMapScene.advance` ticks
it once per vsync beside `_screen_in`, `_town.advance_open()` and `_advance_travel`. Not a
`Tween` and not `delta`: ADR-0161 removed exactly that, and a 143.9 Hz panel would run a
sixteen-frame beat in a third of the time.

**2. The holds are the console's, ported as constants rather than as feel.**
`NODE_VSYNCS = 16` is `0x10` at `0x8006DE58`. The ribbon's per-quad hold is
`isqrt(dx² + dy²) >> 5`, ported as the formula and not as the 1 it currently evaluates to
— the 1 is a fact about `model.json`, and a regenerated model with a longer route would
otherwise silently lose the slow arm. `LOOK_AT_VSYNCS = 1` is the port's, and it is the
one number here that is not a measurement: page `0x32` pops on its own first tick when no
camera pan is armed, and the port never arms one.

**3. The animation draws; it never writes a bit.** The write stays where ADR-0230 dec. 3
put it. Where the store and the console's timing disagree the animation *overrides the
frame* for the length of the page and the store is left alone: a revealing route is hidden
from `path_quads` and drawn as a partial ribbon instead, and an erasing node is drawn as a
ghost the store no longer knows. Two overrides, matching exactly the two rows of the table
in the Context where the console writes the bit at the far end of the page.

The alternative — move the write to the end of the page for those two — was rejected: it
would put the seam ADR-0230 dec. 3 argues for in two places, and it would make the pass's
own tests depend on how long a picture takes.

**4. A look-at's picture is the location NAME, over the node it names.** The console's
look-at is two things: the emit handler at `0x80091DC8` writing the selected-place word
`DAT_800D0BB4`, and a camera pan the port has no camera for. §19.1 is what that word
draws — the location-name cel, at the node's own projected point — so the half the port
*can* have is the whole of the visible half. `WorldMapPrimitives.main_list` takes a
`regarding` node that overrides the cursor's hit test as the name's source.

**It is not the player's cursor**, which is 11-campaign-spine.md's own `_Avoid_` line and
is now measured rather than assumed: `FUN_8006C844`, called before every one of the three
pushes, *zeroes* the cursor's four ramp words (`0x8009EF6C`, `0x8009EF7C`, `0x8009F184`,
`0x8009F194`). The runner stills the cursor; it does not steer it.

**5. The pen outlives its own page.** `regarding` is set by a look-at and stays until the
next one. That is why a one-vsync page is enough: on the console the look-at's content is
a *word*, and a word stays written. It is also the choreography reading correctly — the
name stands over the town being regarded while the road toward it draws.

**6. The arrival's ending waits for the animation.** `_arrive_at` ran the pass and then
fell straight into the town-page return or `node_entered.emit`. Both hand the screen away
— the emit can tear it down entirely — so paced, either one would land over a running
reveal. "Arrived" and "arrived and finished revealing" are two moments now, and the second
is a state (`_arrival_pending`) rather than the next statement.

**7. Input is refused for the length of the pass, as a game-state gate.** The same shape
`_travel` already has, in the same three places (`held_direction`, `_unhandled_input`,
`_enter_node`), and for the same reason: the screen still holds the input frame, it is
simply mid-animation. This is not a sixth answer to "who has input": the carve-out
`held_direction` already documents for `_travel` — *"it has no node and consumes no input.
The map still HOLDS focus while the marker walks, it is simply mid-animation"* — is this
case word for word. The console agrees structurally: its animation page sits above mode 0, so the ○
handler is not ticked (see the Context — the latch that looked like the mechanism is the ○
handler's own).

The gate in `_unhandled_input` sits **below** `_track_pad`, so a release that lands during
a reveal is still recorded. Dropping it would leave the cursor walking when the pass ended.

**8. The map opens, and then reveals — after the screen-in lands.** This is the visible
change: `_ready`'s pass no longer lands before the first frame. That is what the console
does (the drain is page mode `0x39`, ticking while the map is up), and the animation waits
for `screen_in_active()` to go false because CONTEXT.md defines a screen-in as the ramp
that runs *before the screen accepts input* — starting the beat under the fade would spend
it behind black.

**9. `settle()` is the old behaviour, kept as a verb.** The capture rig freezes the vsync
clock, so `_capture` settles the pass exactly as it settles the screen-in ramp; a host or
test that wants the landed frame calls `settle_reveal()`. Every caller that does not want
to watch has one call to make, and it is the pre-ADR-0231 behaviour to the bit.

**10. The erase direction ships with a picture, on the same grounds ADR-0230 shipped its
arms.** What was read for the erase is its *page*: sixteen vsyncs, and the bit at the far
end. What was not read is what `FUN_8006DA88` / `FUN_8006DE50`'s draw side puts on the
screen during it. The port draws the thing that is going away and then stops drawing it,
which is the only reading consistent with the bit's timing. Deferring would ship a map
where a place vanishes on the frame the pass reaches it — a dropped frame where the
console has an event.

**11. The sound cues stay declined, and one more is recorded.** ADR-0230 dec. 9 stands.
Its Context names `0x77` (node reveal) and `2` (node erase); the ribbon page plays
`FUN_80090D30(0x76)` on its first frame **in both directions** (`0x8006DC50` /
`0x8006DC54`) and the look-at page plays nothing. Three cues read, none ported —
`WorldMapMusicPort.gd` is still where one would cross.

## Prediction

Written before the build, scored after:

1. **The counter-4 beat is 43 vsyncs** — route 12's five quads, sixteen for Sweegy Woods,
   route 11's six, sixteen for Goland. *Held*, tick for tick.
2. **The two overrides are the only places the store and the frame disagree.** *Held* —
   the table in the Context has exactly two rows where the bit is written at the far end
   of the page, and they are the hidden route and the ghosted node.
3. **The `_unhandled_input` gate is redundant with the three game-state guards under it.**
   *Falsified, and usefully.* Three of the four inputs are stopped twice over — ○ by
   `_enter_node`, START by `_open_menu`, the pad by `held_direction`. ✕ is stopped by
   nothing else: `_leave` has only its own one-way latch. Without the gate, ✕ during a
   reveal strikes the screen. The arm that scores the gate had to be the ✕ one, and it is
   the seed that proved it.

## Consequences

- **The map's opening frame moved.** Every capture and screenshot rig that mounts the map
  on a store that owes reveals now sees the pre-pass picture unless it settles.
  `_capture` settles; `CampaignRevealPassTest`'s two hook arms call `settle_reveal()`,
  which is what dec. 8 was ever about — where the trigger is, not when it lands.
- **`WorldMapPrimitives` grew a partial ribbon and two frame overrides.** `path_quads`
  takes a route to skip, `ribbon_quads` is its per-route half and is public, and
  `main_list` takes `regarding` and `ghost_node`.
- **The spine doc's Reveal step entry was wrong about the console** in a way nothing could
  have caught until the other two pages were read: the bit lands on frame 1 for one of the
  four directions.
- **`here200`'s console termination is still open**, and the read narrows it rather than
  closing it. With no camera pan armed page `0x32` pops on its first tick and the drain
  page runs the same first-match again the next frame, so the loop the ADR-0230 Context
  describes would be tight rather than slow. The port still terminates by construction and
  still does not depend on the answer.

## Alternatives considered

**Drive the beat off `delta` or a `Tween`.** Rejected — ADR-0161 removed exactly that
shape from this screen, and the measured display here is 143.9 Hz.

**Move the bit to the end of the page for the route reveal and the node erase.** Rejected
— decision 3.

**Give the look-at a camera pan.** Rejected: §21.1 is that the view never scrolls, and the
port has no pan to aim. The name label is the half of the console's look-at that survives.

**Move the cursor to the looked-at node.** Rejected, and it was the first design. The
vocabulary refuses it (*"confusing it with the player's cursor, which a look-at does not
touch"*) and so does the ROM: the runner zeroes the cursor's accumulators before every
push.

**Let the arrival finish and animate underneath.** Rejected — the town page mounts over
the map and `node_entered` can free the whole screen, so the animation would be drawn over
or torn down mid-beat.

**Hold input off with a Focus push instead of a game-state gate.** Rejected: pushing a
state nobody holds to deafen the screen is the shape ADR-0177 deleted four bools to avoid
having, and the screen genuinely still holds the frame — it is mid-animation, not
outranked. `_travel` is the precedent and it is the same question.

**Settle the pass in `_ready` and animate only on arrival.** Rejected. Counter 4 is the
reported defect and it fires on map-open; settling there would mean the one beat everybody
looks at is the one beat with no animation.
