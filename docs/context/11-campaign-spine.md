# Campaign spine

The vocabulary of *where the story is* — the world map's decision data and the one
variable array that carries it across a battle. Distinct from
[Scenario branching](10-scenario-branching.md), which routes *within* a group; this is
what picks the group. The word **event** is not used anywhere here: `CONTEXT.md`
already spends it twice ([Scenario](08-scenario.md)'s `_Avoid_` rule and the
[event script](09-event-script-interpreter.md) bytecode), and the world map's own
programs are a different language with a different interpreter.

**Game variable store**:
FFT's single game-variable array — 684 bytes at `*(0x80153280)`, three regions that
tile it exactly (words `0..127`, bits `128..863`, nibbles `864..1023`). It is
**one array**, not one per subsystem: the world map's overlay, the
[event script](09-event-script-interpreter.md) interpreter's `0xB0`–`0xBE` writers, and
the battle side's `event_set_script_variable` all address the same bytes. Its home
`0x8005771C` sits in SCUS's BSS, *below* the `0x80067000` overlay window, so it
survives the `BATTLE.BIN` load — that placement is what makes a campaign possible at
all. Modelled by `WorldMapVariables`, which owns the addressing; named indices live
on `WorldMapProgress`, which is the query surface.
_Avoid_: "event variable file" (the RE's word for the same array seen from the
battle side — it implies a scene-local scratchpad, and treating it as one is what
kept the [story counter](11-campaign-spine.md) from ever advancing); "save data" (the
store is live campaign state that happens to persist); one store per consumer.

**Node script**:
One program in the world map's per-node bytecode — a list of **conditions** followed
by exactly one [emit](11-campaign-spine.md), run by `FUN_80091238(node, mask)`. 182 of them
over 43 nodes. The interpreter takes a *mask* naming which emit kind the caller wants
and returns the first script that both passes its conditions and emits that kind, so
one node's list serves several unrelated questions.
_Avoid_: "event script" (that is the cutscene bytecode — see
[Event-script interpreter](09-event-script-interpreter.md)); "type-8 script" (names one
emit **mask**, `0x008`, not the language, and reads as a hand-off when most scripts
are not); "event table", "lookup" (a node does not *have* a scenario — it has a
program, and the answer depends on the [story counter](11-campaign-spine.md)).

**Emit**:
The single terminating instruction of a [node script](11-campaign-spine.md), and the only
thing a script produces. Ten kinds are named — `enter`, `reveal_node`,
`reveal_route`, `unreveal_node`, `unreveal_route`, `look_at`, `triple20`, `multi`,
`unary10`, `setvar40` — each with its own mask bit, and a caller sees only the kinds
its mask selects. An emit does **not** write a game variable; it names what should
happen. See [reveal step](11-campaign-spine.md) for what does.
_Avoid_: "return value", "result" (the script's `result_word` is the mask machinery,
not the payload); "action" (reserved for the [navigator](10-scenario-branching.md)'s plan).

**Enter**:
The [emit](11-campaign-spine.md) that hands the world map off — mask `0x008`, two operands:
a [scenario](08-scenario.md) id and a [transition mode](11-campaign-spine.md). It is the *only*
emit that leaves the screen. 55 of them; the 46 gated on the
[story counter](11-campaign-spine.md) are the main story, one per value.
_Avoid_: "battle" (28 of 55 launch a cutscene, not a fight); "load", "warp".

**Hand-off precedence**:
Which node ○ asks about — the one the **marker** is standing on, *before* the cursor's
node is consulted at all. `FUN_8008E2BC` (§29.3) opens with
`if (FUN_80091238(*(u32*)0x8009F254, 0x08)) { ...hand off...; return 0; }`, and
`0x8009F254` is the marker's node, so **when the marker's node has a live
[enter](11-campaign-spine.md), ○ does the same thing wherever the cursor is** and the
pathfinder is never reached. That is not a special case — it is what stops the player
leaving a town whose story battle is unfought. It is also rare: 33 of 38 consecutive
story hops move the [enter](11-campaign-spine.md) to a *different* node and therefore walk,
and all 5 that fire on the spot are two consecutive beats at the same location, where a
walk would be nonsense. Ported at `WorldMapScene._enter_node`; pinned end to end, with a
real press and the cursor deliberately elsewhere, by `NavigatorWorldMapPressPrecedenceTest`.
_Avoid_: "○ enters the node under the cursor" (true only when the marker's node is inert);
"walk or enter" as a **data element** — there is none, the answer is derived from where
the marker is plus which node's [enter](11-campaign-spine.md) conditions pass right now;
"instant travel", "teleport" (nothing travels — the marker does not move at all).

**Reveal**:
The [emit](11-campaign-spine.md) family that opens and closes the map, and it has a
**direction**. `reveal_node(n)` / `unreveal_node(n)` carry the node-known bit `512 + n`;
`reveal_route(a, b)` / `unreveal_route(a, b)` carry the route-drawn bit `556 + r`, where
`r` is the route whose two endpoints are `a` and `b` in either order. The two directions
are one thing on the console — the same animator, called with a flag — which is why they
are named as a pair rather than as four kinds. Reveals are drained by the map while it is
open, one at a time, each animated, and *not* by the ○ handler or the arrival handler —
neither of those ever asks for a reveal mask.
_Avoid_: "unlock" bare (ambiguous with job/ability unlocks); treating a reveal as
something that fires on entering a node; treating the known set as **monotonic** — six
emits across three nodes take a place or a road back, the first at story counter 18;
`pair100` / `unary800` (the pre-ADR-0230 placeholder names for the erase direction).

**Reveal step**:
One [reveal](11-campaign-spine.md) applied — the unit of the drain. A step is what writes
the known/drawn bit, and on the console it is the *animation* that writes it, not the
[emit](11-campaign-spine.md): the emit only says which node or route. So the state change
and the picture are the same event, and a step is the smallest thing that can be both.
**Which frame of the animation writes it is the frame the thing appears or disappears** —
first for a node reveal (`0x8006DFA0`) and a route erase (`0x8006DC10`), last for a route
reveal (`0x8006DD04`) and a node erase (`0x8006E048`). The port writes it up front in all
four, and the [reveal animation](11-campaign-spine.md) holds the *frame* back for the two
that differ rather than moving the write.
_Avoid_: "the emit sets the bit" (it does not, and this is the reading a reader assumes);
"the bit lands on the animation's first frame" — this doc said that of all four directions
until ADR-0231 read the other two pages, and it is true of one; "apply the reveals" as a
batch (a batch has no step, so it has nothing to animate).

**Reveal pass**:
The ordered walk of one node's [node script](11-campaign-spine.md) list that drains its
live reveals — every [reveal step](11-campaign-spine.md) that node owes right now, in the
table's own order, each visited at most once. The order is the content: a beat is written
as [look-at](11-campaign-spine.md), draw the road, light the town, move the look-at, and
it reads as an animation because it is one. A pass belongs to a **node**, not to the map
and not to the story — the node the party marker is standing on.
_Avoid_: "reveal loop", "drain until empty" (a re-query cannot terminate here — some
scripts do not clear their own guard, and the ordering is what bounds the walk);
"reveal queue" (nothing is enqueued; the table is re-read live as the pass advances).

**Reveal animation**:
A [reveal pass](11-campaign-spine.md) paced onto the console's 60 Hz clock, and the picture
each of its [steps](11-campaign-spine.md) draws while it is on screen. Three shapes, one
per animation page in `WLDCORE`: a node holds for sixteen vsyncs and nothing moves (page
`0x36`); a road's ribbon grows one quad per vsync and shrinks the same way (page `0x35`);
a [look-at](11-campaign-spine.md) costs one vsync and leaves the name behind it (page
`0x32`). While one runs the screen takes no input — not because a flag says so, but because
the animation page sits above the input handler's in the console's page stack, and because
here the screen is mid-animation exactly as it is while the party marker walks. ADR-0231,
`WorldMapRevealAnimation`.
_Avoid_: "the reveal tween" (there is none — ADR-0161 removed the last one from this
screen, and a delta-driven ramp runs at the display's rate rather than the console's);
"the animation applies the reveal" (it draws; the [reveal step](11-campaign-spine.md)
writes the bit); "reveal cutscene" (nothing is played and no screen is handed over).

**Look-at**:
The [emit](11-campaign-spine.md) that says which node the screen is regarding — one node,
or the party marker's own when the operand is `0xFF`. It carries no state: it writes no
game variable and changes nothing a save can hold. It is the pen of a [reveal
pass](11-campaign-spine.md), and it is a third of that pass's scripts. What it draws is the
**location name**, over the node it names: the handler writes the selected-place word
`DAT_800D0BB4` and §19.1 draws that node's name cel at that node's own point. The player's
cursor is not involved — the runner *stills* it, zeroing both ramp accumulators before
every reveal page it pushes (`FUN_8006C844`).
_Avoid_: **"focus"** — that word is already spent on the input-focus stack
([Focus](37-the-blueprint.md)), and a reveal's look-at grants no input right to anyone;
"here200" (the placeholder name from before the handler was read); "move the marker",
"travel" (nothing moves — the party's position is unaffected); confusing it with the
player's cursor, which a look-at does not touch.

**Transition mode**:
An [enter](11-campaign-spine.md) emit's second operand, `1` or `2` — which screen
transition plays on the way out. `2` is light (or a bit, play a cue); anything else
is heavy (tear the GPU down first). Across the story spine it correlates 54/55 with
whether the launch deploys a squad, but that is a **correlation**, not the meaning:
the port derives deployment from `first_squad_deployment_idx` and the ENTD control
count, and `Nelveska Temple` (scenario 484) is the measured exception.
_Avoid_: "battle mode", "mode = battle" (the reading the RE explicitly refuses);
"heavy/light" as the primary name (those are the arms, not the operand).

**Story counter**:
`var[110]` in the [game variable store](11-campaign-spine.md) — the world map's position in
the main story, running `1`–`52`, one value per spine [enter](11-campaign-spine.md).
Written **only** by the scenarios themselves, via the
[event script](09-event-script-interpreter.md) codegen idiom `Zero(110); Add(110, k)`;
nothing in the world map's overlay writes it.
_Avoid_: "chapter" (FFT's chapters are 1–4 and are a different variable); "progress",
"progression" (the latter is reserved for `UnitProgression`); "story flag" (it is a
counter, and eight of its values bind no script at all).

**Next-scenario register**:
`var[0x27]` — the one word naming the scenario the game is about to run. Written from
exactly two places: an [enter](11-campaign-spine.md) emit on the world map, and the battle
side's BattleConditionals opcode `0x0019 Run Scenario N`.
_Avoid_: "current scenario" (it names the *next* one and is stale immediately after);
"scenario pointer".

**Place number**:
A world-map node in the **screen's** numbering — 1-based, with `0` meaning "none".
The ROM's own convention: `FUN_8006C350`'s hit test returns `i + 1`, and the arrival
handler writes `arrived_node + 1` to the HUD's selected-location word. This is what
`WorldMapScene.node_entered` carries and what `WorldMapProgress.party_node()` returns.
_Avoid_: "node id" bare (ambiguous with the storage space below).

**Successor**:
Which **source names the next scenario** once one ends — the `ATTACK.OUT` record's
`+0x14` byte. Four values: **`next-scenario`** (`0x81`, the record's own
`next_scenario_id`), **`world-map`** (`0x80`, a [node script](11-campaign-spine.md) will
choose), **`reset`** (`0x82`), and none (`0x00`, the scenario is not a group's last
member). At runtime it is not read from `ATTACK.OUT` at all: `FUN_80142B5C`
(`0x80142B5C`) indexes a packed `u16` per scenario in BSS at `0x8004E5D0` —
`next_id = (w & 0x0C00) >> 2 | (w & 0x00FF)`, `successor = (w & 0xF300) >> 8` — and
`FUN_80142D58` writes the [next-scenario register](11-campaign-spine.md).
In `transition_graph.json` the edge it produces is tagged `via: "successor"`, paired with
`via: "BC"` for the guarded BattleConditionals branches.
_Avoid_: **exit**, **sink**, **`GoTo…`** — all three claim the scene *goes* there. It
does not: the byte names a *source*, and it is structurally incapable of expressing
anything the scene does on its way out. That is not pedantry — it is why the
[scene-out](11-campaign-spine.md) save prompt went unmodelled while `transition_graph.json`
reported the edge as bare. Also avoid **`ATTACK`** as the edge tag — it named the *file*
the byte came from (`ATTACK.OUT`) and read as "a battle edge", when **162 of 162 such
edges leave a non-battle node** and `"ATTACK"` is separately taken by the combat gambit
vocabulary. And avoid "post-scenario step" (names the field's offset, not its meaning).

**Scene-out**:
What a scenario actually **does on its way out** — the fade, and any blocking screen it
raises before `Event End`. It lives in the **chunk**, not in the record, and is therefore
invisible to the [successor](11-campaign-spine.md) byte and to `transition_graph.json`. The
known one is the **save prompt**: `{43} 06` → `event_graphics_cmd_mailbox_post(0x0E)`,
which stops event tasks 2..14 and blocks until dismissed (24 scenarios, 20 of them
"(Victory)"). See `GAME_STATE_TRANSITIONS.md` §2.8.
_Avoid_: folding this into [successor](11-campaign-spine.md) or "the transition" (the whole
point of the term is that they are different things, decided in different files);
"outro" (taken by the sound-trigger work).

**Screen-in**:
What a screen does on its way **up** — the ramp it runs on **itself**, on **its own
clock**, before it accepts input. The counterpart to [scene-out](11-campaign-spine.md), and a
different word because the *owner* is different: a scene-out is authored per-scenario in
the **chunk**, so it varies beat by beat; a screen-in is **unconditional** and belongs to
the screen's own code. The world map's is `WLDCORE`'s (§24.1: its own BSS, emitted from
`FUN_80069810` inside `WLDCORE`'s render loop) — so the map fades *itself* in, and the
navigator only holds black around the mount.
**That difference is also an OWNERSHIP rule** (ADR-0172): a scene-out is an event-script
instruction, so it belongs to `Cutscene` — and the classifier agrees, booking
`ScenarioColorScreen` and all four `screen_color_mode*` shaders there. A screen-in belongs
to **the screen's own system**, which makes the Formation screen's `UI`'s — BLUEPRINT §6's
first charter row is the toolkit's open and close cadence.
Not `Render`: ADR-0129 gives `Render` the fold BRACKET and
ADR-0147 measured it producing **zero** of the sixteen `compositor_layer` shaders, so a
screen fade — a drawable somebody submits — can never be its. Three ramps, three owners, and
that is correct rather than duplication: they answer three different questions, only one of
which has been measured.
_Avoid_: "fade" bare — the implementation is a PSX **abr 2** subtractive quad (`B - F`),
not an alpha ramp over black (`B * (1-a)`), and the two look different: subtractive holds
black until the ramp drops below the brightest pixel, then emerges highlights-first.
Avoid confusing it with **transition mode**, which selects the way *out* of the map and
is still unported. And do not let the one-letter gap from **scene-out** go unnoticed in a
grep — they are deliberately near-identical names for deliberately paired things.

**Screen-out**:
What a screen does on its way **down** — the ramp it runs on **itself**, on **its own
clock**, as it hands off. The mirror of [screen-in](11-campaign-spine.md) in position and NOT in
arithmetic: ADR-0174 §2 read `FUN_80069400(kind, len)` as one routine with two arms and bit 1
of `kind` selecting direction, and the out arm is `counter*256/len + 32` ceiled at `0xFF` —
opening at **32** and landing on full black, where the in arm opens at 192 and lands clear.
Reversing the in arm is wrong at *both* endpoints, which is why `WorldMapScreenOut` restates
the formula instead of running `WorldMapScreenIn` backwards.
**The owner is the SCREEN** (ADR-0188 dec. 7), on ADR-0172 §1's rule and not as an
exception to it: that rule's discriminator is authorship, not direction — a scene-out is
authored per-scenario in the **chunk**, a screen-in and a screen-out are **unconditional**
and belong to the screen's own code. BLUEPRINT §6's first charter row is the toolkit's *open
and close* cadence, and the close is this. So the map's is `UI`'s, in `src/world_map/`
(booked `UI` by ADR-0176), exactly as its screen-in is.
**The CURVE is a fidelity claim and the FIRING is not.** ADR-0174 read only the map's
*entry* cue (`0x8006731C`, direction in, len 16); nothing establishes that the console fires
the out arm when the map hands off. `world_map.screen_out` is the seam between the two, which
is the whole reason a measured ramp sits behind a tunable.
_Avoid_: reading this as the [host cue](11-campaign-spine.md) — they are one word apart
and they are different things, which is what that entry's own `_Avoid_` is warning about; see
it for the distinction. And avoid "fade" bare, for the reason [screen-in](11-campaign-spine.md)
gives: the implementation is a PSX **abr 2** subtractive quad, not an alpha ramp.

**Host cue**:
What a **host** fires on each side of running another screen to completion — once as it
hands the display over, once as it takes it back — and **blocks on** until the cue reports
finished. The owner is the point: a [screen-in](11-campaign-spine.md) belongs to the screen's own
system (ADR-0172), and a host cue belongs to whatever mounted it. Measured on the world map's
Formation row, `FUN_80107238` — a nine-state machine with **one** call site,
`SUB_80069400(kind, 0x10)`, reached twice: `kind 0x12` from state 1, then state 2 blocks on
bit 3 of `0x8004D950` (the cue's own busy latch, §32.3); state 3 runs the Formation mainloop
`FUN_80113748(0,0)` to completion; `kind 0x24` from state 8, then state 9 blocks on the same
bit. Three sibling row coroutines call it the same way.
_Avoid_: calling THIS a **"screen-out"** — the host cue is not a
[screen-in](11-campaign-spine.md) reversed and it is not the screen's, which is the error that
framing produces. Note the warning is about **this referent**, not about the word: the map
really does run a [screen-out](11-campaign-spine.md) of its own on ADR-0174's measured out arm,
and that one *is* the screen's (ADR-0188). Two things, one word apart; the entry above is
the other one. **"fade"** or **"ramp"** —
`SUB_80069400`'s body is in the `WLDCORE` overlay, absent from every `world_disassembly*`
export, so whether the cue is visual or audio is **UNMEASURED**; `FUN_80106a28` is a
four-instruction setter and `FUN_80106998` a fixed display re-init, so neither of those is
the ramp either. Naming the two firings as a **reversible pair** (ADR-0172 dec. 3 declined a
beat for exactly that reason). And do not stretch it to cover the whole trip: the map also
gives up [focus](37-the-blueprint.md) and the pump, and those are ADR-0119 capability traffic that
moves instantaneously — a host cue is only the part with a **duration**.
Distinct from [hand-back](32-formation-screen-hosting.md), which is the SCREEN saying it is
finished; a host cue is what the host does around that.

**Node index**:
A world-map node in the **storage** numbering — 0-based, `0..42`. The space the
[node script](11-campaign-spine.md) table is indexed by (`by_node[i]`), the space
[reveal](11-campaign-spine.md) operands are written in, and the space the known/drawn bits
are addressed in (`512 + i`, `556 + r`). Convert once, at Campaign's edge:
`index = place - 1`.
_Avoid_: mixing the two silently — every store accessor takes an index and every
signal carries a place.
