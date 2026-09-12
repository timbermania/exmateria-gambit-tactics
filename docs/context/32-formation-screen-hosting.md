# Formation screen hosting

The Formation screen is one screen with two **hosts**: the standalone roster
screen, and the live battlefield it re-hosts over. The vocabulary below names
what the two hosts share and the one place a unit stands in both. See ADR-0137.

**Breakout mark**:
The fixed display-px point where a unit stands once it has been singled out of
the roster. Both hosts land a unit on it by opposite means — the
[roster host](32-formation-screen-hosting.md) slides the unit there while its rowmates
exit the screen, the [map host](32-formation-screen-hosting.md) pans the camera until
the unit arrives on it — and since 2026-08-21 each host has **its own mark**,
because the question is not the same question:

- **Roster**: body centre `(178, 193)`, derived from the Equip/Ability settle plus
  half the 24×40 roster descriptor. Answers *"where does a unit go once it is no
  longer one of a grid"*.
- **Map**: feet `(167, 213)`, stated in FEET because a battlefield unit's position
  IS its feet. Answers *"where in the gap the sub-screen opens"* — between the
  narrowed lower panel and the list menu (Equip `x139..196`). The map sprite draws
  ~18×27 display px at the entry zoom, not 24×40, so the roster's descriptor was
  never the right feet offset either.

It is not Equip's: Ability uses the same mark. Change-Job does **not** derive from
it (its oval is screen-centred at `(128, 126)`).
_Avoid_: equip settle, settle px, spotlight settle, "the breakout"; one shared
mark for both hosts.

**Roster host**:
The Formation screen standing on its own — its own orthographic camera, the
stone floor behind it, the 4×2 roster grid answering "who is selected". The
out-of-battle path. **It is a screen with a LIFETIME** (ADR-0181): it raises itself
with a [screen-in](11-campaign-spine.md) and it ends by handing the display back. That
is the axis the two hosts differ on, and both the ramp and the
[hand-back](32-formation-screen-hosting.md) are gated on it.
_Avoid_: the formation scene (that is the node, not the role); "the dev harness" —
the standalone fixture is a SCENE (`FormationDev.tscn`), not a host, and a host mode
a navigator can use is a different thing from a way to drive the screen by hand.

**Hand-back**:
A screen saying *"I am finished; whoever mounted me may take the display back."*
Carried by `dismissed`, which is the whole game's word for it — the navigator awaits
it for the world map, for the debug formation view and for the world-map Formation,
and several tests IDENTIFY a screen by duck-typing that it has one. Distinct from
`settled(to)`, the Formation coordinator's WITHIN-screen seam, which fires at every
resting screen including the one you land on when you back out of a sub-screen: a
host awaiting *that* would tear the screen down under a player still browsing.
A hand-back is about a LIFETIME; `settled` is about an arrangement.
_Avoid_: "dismissed" bare when the surrounding text is about the roster grid — the
same signal name is the roster ELEMENT's cancel when something is hosting it, and
that one stops at its host.

**Map host**:
The same screen re-hosted over the live battlefield — mounted under the map's
camera, the map itself behind it, and the [tile cursor](29-battlefield-camera.md)
answering "who is selected". **It is PERSISTENT, not a screen with a lifetime**
(ADR-0181): built with the cursor rig at Deployment entry and freed with it, it never
"finishes", so it neither raises a [screen-in](11-campaign-spine.md) — a full-screen
subtractive quad would black out the battle it is mounted over — nor issues a
[hand-back](32-formation-screen-hosting.md), which there would be a claim that is false
rather than merely unheard. Has no grid, so every grid-shaped obligation
(roster chrome, the equip slide, redocking) degenerates to a no-op, and
"where is the selected unit" inverts: the [breakout mark](32-formation-screen-hosting.md)
is fixed and the camera moves to satisfy it. The exception is the docked
vitals+nameplate pair: that is not roster chrome but the **hover pair**, so it
still hides when the detail overlay's own cluster takes the same spot
(ADR-0137 Amendment 1 §2). At REST the map host draws nothing at all — no band,
pair parked off both screen edges.
_Avoid_: the map overlay, the battlefield formation screen.

**Clip basis**:
The transform that maps a fragment back into the SCREEN's own space before the
box-open aperture test. A UI3 aperture (`clip_world`) is an axis-aligned rect in
display px × ppu; the shaders read a fragment's position in GLOBAL space. Those
are the same space only while the screen root sits at the world origin — true of
every screen that owns its own camera, false for the [map host](32-formation-screen-hosting.md).
`UI3ClipEngine` therefore pushes `clip_basis_inv` beside every `clip_world`,
resolved as *the nearest ancestor that answers `screen_to_world`* — a real
criterion, since the aperture's numbers are exactly that function's image. The
failure it prevents is legible and misleading: every UNCLIPPED element renders
while every CLIPPED one discards every fragment, so a screen looks like it simply
never opened.
_Avoid_: clip transform, screen matrix.

**Screen stack**:
The map-hosted Formation screen's LIFO of levels (`FormationDetailTransition._stack`,
ADR-0084) — and, since ADR-0261, the answer to "what is on the display", not merely
"which transition is running". A [deployment pick](32-formation-screen-hosting.md) is a
level (`State.PICK`) rather than a host mode, so `IDLE` means the battlefield is
uncovered without exception; three call sites used to carry a private "…unless a pick
is open" clause because it did not.
_Avoid_: "the screen" for a level (a level is one of several the screen can be at once);
"the state machine" — the levels nest, and what the stack settles is DEPTH.

**Claims**:
What the map-hosted screen takes from the battlefield while it is up: the battle pause
and the **camera takeover**. Held iff the [screen stack](32-formation-screen-hosting.md)
is non-empty — taken by the push that makes it non-empty, released by the pop that
empties it (ADR-0261). The takeover is not decoration: `TileCursor._input_allowed()`
refuses every press unless the camera is in CURSOR mode, so **the takeover IS the tile
cursor's input gate**, and releasing it under a screen that is still up wakes the
battlefield cursor beneath it. `PlayerCamera` holds it as one flag with no depth, shared
with the cinematic manager, so it cannot be taken twice and released once.
_Avoid_: "the pause" alone (that is one of two, and the other is the one that locks the
player out); "pad ownership" as a third claim — that is DERIVED from the stack
(`map_input_owned()`) and excludes `PICK`, because there the grid reads the pad itself.

**Back grammar**:
How far ✕ unwinds out of each level, per host — one declared table
(`_UNWIND_ROSTER` / `_UNWIND_MAP`, ADR-0261) rather than a depth restated at each
teardown. The map host pops ONE everywhere, because the level underneath is a
destination there; the roster host keeps ADR-0084 RE25's full unwind to the roster for
the sub-screens. Change Job follows the map host's rule as of ADR-0261 — ADR-0137
Amendment 7 had exempted it on an argument about COMMITTING a job, applied to the press
where you did not.
_Avoid_: "the exit rule" (there are two hosts and they differ on purpose); reading a
depth off any one teardown.

**Steerable**:
May this selection be **edited right now** — the question the START menu's action
rows are lit by. A conjunction of two terms that are never the same term:
*ownership*, a permanent property of the unit (an enemy or an ENTD-blue guest gets
the same screen, read-only, ADR-0137), and *the moment*, which only the host knows —
during a [gambit battle](https://github.com/timbermania/fft-monorepo/issues/886)
that is "is it this unit's turn" (ADR-0252). The [map host](32-formation-screen-hosting.md)
answers with `selection_is_steerable()`; the [roster host](32-formation-screen-hosting.md)
answers "always", because out of battle there is no turn for an edit to belong to.
Gates the EDIT and never the LOOK: △ opens the screen on anybody at any time
(ADR-0137 Amendment 6), and a unit you may not steer gets the enemy's screen —
complete, readable, inert.
_Avoid_: "owned" for this question (ownership is one of its two terms, and a
selection can be owned and unsteerable in the same breath); "editable" bare;
"controllable" — that is `_commandable`, which asks whether the unit takes YOUR
orders at all, not whether it may be edited this instant.

**Adjustment turn**:
An open turn seen as an **editing window** — the design's "a turn is a
reconfiguration, not an action". Its state is the *pre-turn image*, which has two
halves that no single object owns: the GPU's three buffers (the director's
snapshot, ADR-0235) and the durable `Character` on the CPU, which is in no SSBO.
Edits are made **eagerly** on the Character and land on the GPU only at commit, so
what the turn holds is the **undo**, never the redo (ADR-0252).
_Avoid_: "the adjustment UI" for the contract (the UI is the Formation screen, which
this does not own); "the turn snapshot" — that names one half and hides the half
that made it necessary.

**Gambit surface**:
The screen where a unit's gambit list is read and edited (ADR-0255). Named for
what it is rather than for the class that used to be it: the UI2-era
`UIGambitEditor3` was *a* gambit surface and is no longer *the* one, and
`GPUArena`'s teardown comment — "one thing goes dark with it and has no new home:
the gambit surface" — already used the word for the concept. It is three levels of
one list ([gambit slot](32-formation-screen-hosting.md) → [sentence
part](32-formation-screen-hosting.md) → choice), reached from the "Gambit" row of
the [adjustment row set](32-formation-screen-hosting.md).
_Avoid_: "the gambit editor" (that names a specific retired window, and the surface
is a readout as much as an editor); "the gambit screen" — it is not a screen in the
ADR-0084 sense on its own, it is a state of the Formation screen.

**Gambit slot**:
One of the four fixed positions in a unit's `GambitList`. A slot always exists —
`ensure_fixed_size` pads to four — and may hold the *empty gambit* ("Wait on Self"),
which is what a scenario-booted cast has in all four (#892). Distinct from a
**gambit**, which is the rule a slot holds: you edit a slot, and what changes is its
gambit.
_Avoid_: "gambit" for the position ("slot 2 is empty" and "gambit 2 is empty" say
different things); "row" — a row is what the surface renders, and it renders parts
and choices as rows too.

**Sentence part**:
One editable field of a gambit, read as the sentence the unit already speaks: **Do**,
**To**, **Subject**, **If** (ADR-0283 dec. 1; ADR-0255 called the fourth one *When*
and ADR-0268 dec. 2 folded it away entirely, so the count has been 4 → 3 → 4). The
parts are the editing vocabulary because the struct's own fields are not — a
`TargetSelector` is a pool type, a team filter, a role filter and a resolution
strategy whose cross-product is mostly meaningless. Each part offers NAMED whole
values ("Nearest Foe", "HP<50%"), so the set a player can author is the set they can
read back off the row.
_Avoid_: "field" (the parts are not the struct's fields, deliberately); "dropdown" —
that names the retired mouse editor's widget, not the concept; **"When"** for the
fourth part — that word named a full pool selector, and the part is a two-way switch
(see **Condition subject**).

**Condition subject**:
Who a gambit's condition is a question **about** — `Gambit.condition_target`,
rendered as the row's third column and offered as a two-way switch, **`My`** (the
actor) or **`Their`** (whoever the **To** column named).
⚠️ **Two words, not one, because the bare word is TAKEN**: `Subject` already names
the unit + equipment shown on a screen, in
[port-vs-oracle diffing](35-port-vs-oracle-diffing.md), and that domain neutralizes
its subject by masking. The COLUMN on screen is still headed by the player's own
word — this entry names the concept, not the label.
Distinct from
[target](07-ability-hit-policy.md), which stays scoped to the unit an ability
*centers on*: a rule can test one unit and act on another, and `Heal / Ally /
Their / HP<50%` is a sentence with a subject and a target that happen to coincide
while `Heal / Self / Their / …` is one where they do not.
`Their` is a **copy** of the aim rather than a pool of its own, which is what makes
`cond_target_type == action_target_type` — and that equality is what the kernel's
second pass requires before it will walk `find_nth_nearest` at rank 1, 2, 3. A
subject naming any other pool gets `VERDICT_NOT_RETRYABLE`, which is how the folded
`When` made "an ally whose HP is below half" unsayable. ⚠️ Since ADR-0285 the **To**
row that reaches the rank walk is `Ally`, not `Nearest Ally` — the latter is now
strict [aim depth](32-formation-screen-hosting.md) and is deliberately NOT retryable.
Blank (`—`) **whenever the condition is blank**, because with no question there is
nobody for it to be about — and the field is then MIRRORING the aim, not unset:
`cond_target_type` gates the slot whatever the conditions array holds.
_Avoid_: "the condition target" in player-facing prose (it is the field's name, not
the column's); a bare "subject" in writing that could touch a capture diff (see the
collision above); "when" (it names a time, and the column names a unit); "trigger" —
`TargetSelector.triggering()` is the **To** value called `Them`, a different thing
one column left.

**Aim depth**:
How MANY units a **To** value is willing to offer the condition — the second axis of
that column since ADR-0285, the first being the *pool*. `Ally` / `Foe` are the whole
team, and the condition **filters** it: the kernel walks rank 0, then rank 1, then
rank 2 (`find_nth_nearest`) until one passes. `Nearest Ally` / `Nearest Foe` and
`Weakest Ally` / `Weakest Foe` name **one** unit, and the condition **gates** it — if
that unit fails, the slot is done for the tick.
The two are the SAME search; they differ only in whether the encoded
`cond_target_type` appears in the kernel's Pass 2 retry list, which is why depth is a
`ResolutionStrategy` (`NEAREST_FIRST` vs `NEAREST_ONLY`) and needed no new field.
🔴 **`Nearest Ally` meant the POOL until ADR-0285** — the retry walked past rank 0 and
the label only ever described the first guess. A save written before then still holds
`NEAREST_FIRST`, reads back as `Ally`, and behaves exactly as it did.
_Avoid_: "nearest" for `NEAREST_FIRST` in any layer — that word is what was lying, and
the domain member is `NEAREST_FIRST` for the same reason; "target depth", which reads
as terrain height next to [rendering depth](25-rendering-depth.md); calling `Ally` a
"filter" (the *condition* filters, the pool is what it filters).

**Adjustment row set**:
The four action-menu rows an editing host shows: Item / Ability / Change Job /
Gambit (`StartActionMenu.ROWS_ADJUST`). Game-original, leaving the ROM's five
byte-untouched, and dropping the two roster verbs because mid-battle they name
nothing a turn can do. Its rows are dispatched **by label**, not by index — index 3
is "Gambit" here and "Remove Unit" in the ROM's five, which is exactly the collision
ADR-0247 named.
_Avoid_: calling it "the battle menu" (the same host shows the deploy row set during
a pick); reading a row by index across two row sets.

**Imperative**:
The one-shot, top-priority order a player issues on their own turn — design §5's
"lock-on", built by #1006 (ADR-0259). It sits **above** the unit's four
[gambit slots](32-formation-screen-hosting.md) for one action and is then gone:
removed when the unit commits an action, or by the [watchdog](32-formation-screen-hosting.md)
when it becomes uncompletable. It occupies no slot — in the encoded buffer it is a
[lead entry](32-formation-screen-hosting.md), which is what "top priority" means to a
shader that walks slots ascending. It locks onto a **rule** ("the weakest foe") and not
onto a named unit, because the GPU cannot encode a named one
(`SPECIFIC_UNITS` is unsupported).
_Avoid_: "the fifth slot" (a slot holds a rule and persists; an order is spent and
gone, and it is on no `GambitList`); "gambit" bare for it, which loses the one-shot;
"lock-on" in code — the design's word, kept in prose, but the class and the row say
imperative.

**Charge**:
One issue of an [imperative](32-formation-screen-hosting.md). Finite **per unit per
battle** (`ImperativeGambits`, a `Tune` default now and job-derived later), spent at
the moment the order is issued and refunded only by the turn's cancel — design §4's
"cancel must refund any imperative charge spent that turn, or cancel becomes a trap".
Neither removal edge refunds: a wasted lock-on is a real mistake. Charges are battle
state on the CPU, deliberately not on the durable `Character` (ADR-0005), which would
carry them into the next battle.
_Avoid_: "uses" or "cooldown" (there is no recharge — the battle is the budget);
"MP cost" — a charge is not a resource the kernel knows about.

**Lead entry**:
The gambit encoded at index 0 of a unit's GPU buffer, ahead of everything it authored.
The shader takes the first slot that matches (`evaluate_gambits_up_to`), so priority is
a POSITION and no flag encodes it. Today only an
[imperative](32-formation-screen-hosting.md) is ever a lead entry; the room for it
already existed, since `MAX_USER_GAMBITS` is 5 against four visible slots with
ADR-0048's safety net after both.
_Avoid_: "slot 0" (the unit's own first rule is slot 0 when nothing leads it, so the
number names different things on different frames); "override".

**Watchdog**:
The only thing besides the unit acting that removes a standing
[imperative](32-formation-screen-hosting.md): a deadline in **ticks** and a test that
the order's target pool still has somebody in it. Deliberately dumb — design §5 rules
out reachability, LOS and affordability by name, because each duplicates shader logic
on the CPU and the two copies will disagree. Ticks and not turns, because the world is
frozen for the whole of a turn. It runs on the host's frame, since the stretch an
unconsumed order is exposed for is the one BETWEEN turns.
_Avoid_: "timeout" alone (that hides the pool clause); "validity check" — it does not
decide whether an order is legal, only whether it can still be reached.
