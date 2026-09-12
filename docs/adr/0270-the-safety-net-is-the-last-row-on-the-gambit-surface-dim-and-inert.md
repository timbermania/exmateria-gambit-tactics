# The safety net is the last row on the gambit surface, dim and inert

[ADR-0048](0048-safety-net-gambit-is-encoder-injected-ui-invisible.md) injects one gambit per
unit at the encoder boundary — `Attack / Nearest Foe / Always`, below everything the player
authored — so a unit whose every slot misses still has a terminal candidate instead of standing
still. That decision is right and is not reopened here. Its **dec. 2** is: *"It is invisible in
the UI editor."*

Invisibility was free when there was no editor to be invisible in. `UIGambitEditor3` had been
dark since ADR-0137 Amendment 2, and ADR-0255 says so in as many words. There is one now, and
on a scenario-booted cast (#892: `UnitSpawn` mints a `GambitList` and nothing in the boot path
authors into it) it opens onto **four rows that all read `---`** — and then the unit attacks.

That is the screen lying about the rule the unit is under. It is the same defect
[ADR-0268](0268-the-gambit-row-is-a-sentence-read-across-the-screen-and-a-screen-that-owns-the-pad-re-means-the-action.md)
dec. 8 exists to prevent, arriving from the other direction: not a row that reads right and
never fires, but a rule that fires and is on no row. Dec. 8's own reasoning — *"the row reads
back correctly while the unit does something else"* is the worst shape a defect can take on an
authoring surface — does not care which side the discrepancy comes from.

## Status

accepted, and its dec. 1 readout string — `Attack / Nearest Foe / Always` —
STANDS.
[ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)
takes it away and gives it back: its dec. 2 first retired `Always` from the
screen, leaving `Attack / Nearest Foe / Their / —`, and the same dec. 2 now
offers the word in the SUBJECT column instead of the `If` one, where it answers
*whether* there is a test rather than what it is. The net carries one explicit
`ALWAYS` condition, which is exactly that state, so ADR-0283 dec. 7 arrives back
at this string through its general rule rather than by restating it.

The decision itself was never edited through either move. That is the property
this ADR is about: the row is DERIVED from `GambitEncoder.safety_net_gambit()`
through the same label function every other row uses, so its string changes when
the screen's vocabulary changes and cannot be made to disagree with the buffer.

Supersedes [ADR-0048](0048-safety-net-gambit-is-encoder-injected-ui-invisible.md) **dec. 2**,
and the second half of that ADR's title with it. ADR-0048 dec. 1, 3, 4, 5 and 6 stand
unchanged — the net is still one fixed shape, still injected at the encoder boundary, still
absent from the domain, still unhooked at runtime, and still composes with fall-through.

## Decision

1. **The safety net is the LAST row of the gambit surface.** After the four slots and after
   the imperative's row, reading `Attack · Nearest Foe · Always` with its `If` cell DIM and
   empty — a row that has declared it has no test keeps the column and disables it
   ([ADR-0283](0283-the-gambit-rows-subject-is-its-own-column-and-the-slot-number-shares-a-lane-to-pay-for-it.md)
   dec. 8), and the net has nothing parked there because nobody authored it.
   *(It read `Attack · Nearest Foe · — · —` in between, while ADR-0283 dec. 2 had the
   word out of the screen's vocabulary and dec. 1's new subject column had nothing to say on a
   conditionless row; then `Attack · Nearest Foe · Their · —` once the subject printed. The row
   was never edited through any of it — see Status.)* Slot order **is** priority
   (rule A1) and the net is evaluated last, so the bottom of the list is where it belongs and
   reading order stays priority order for the rows that are rules.

2. **It is DIM under the glove, its enable cell is BLANK, and every verb is refused on it.**
   ←/→, L1/R1 and ○ all decline; the glove may rest there and takes nothing. Three separate
   answers, and each says the same thing on its own channel — the shade band that ADR-0268
   dec. 1 gives the job of saying *which row*, the mark that says *enabled*, and the refusal
   itself.

   **`inert` beats focus in the shade band.** An inert row is one the glove can rest on and do
   nothing to, so lighting it would promise a press that is refused; DIM under the glove is the
   only shade that says both things at once. Likewise the ENABLE cell is **blank** and not `○`:
   ADR-0268 dec. 4 chose `×` over a blank for a disabled slot precisely because *an empty
   leftmost part reads as a rendering failure and an off flag has to read as a state* — here
   there is no state, because there is nothing to toggle.

3. **Nothing is editable, because there is nothing on the other side of the verbs.** The net is
   not in `Character.gambits` and never was: ADR-0048 dec. 3 keeps it a buffer concern, and
   this decision does not move it. An edit would have nowhere to land, so the refusals are
   structural rather than a policy that could be relaxed.

4. **The row is DERIVED from `GambitEncoder.safety_net_gambit()`,** which becomes public for
   it, and rendered through the surface's own `_do_text` / `_target_text` /
   `GambitOptions.condition_label`. Not three literal strings: a readout that restates a value
   in its own words is exactly the drift this row exists to close, and it would close it on the
   day it shipped and reopen it the first time the net's shape changed.

   `to` reads the **condition** target, not the action target — the net's `action_target` is
   `triggering()`, which renders as `Them` and names no pool. Same rule, same reason as the
   imperative row, which took this decision first: the aim is on the condition target, because
   the net acts on whoever it picked out.

5. **The four authored slots are NOT seeded to match it.** A player who wants
   `Attack / Nearest Foe / Always` as a rule can author it; the net is what happens when they
   have not. Seeding would make every unit's list look authored, which is a different lie from
   the one this ADR retires and a worse one — it would put a rule in a slot the player never
   wrote, and `GambitList.ensure_fixed_size` would then have to distinguish "seeded" from
   "authored" to know what to strip.

   The net stays reachable through a blank list because `GambitEncoder.authored_gambits` filters
   on `Gambit.is_empty()` before encoding, so `GambitList._create_empty_gambit`'s
   *"Always: Wait on Self"* pad never reaches the buffer to terminate the pass on it. ADR-0048
   Amendment 1 found and documented that invariant; this decision depends on it and does not
   change it.

## Considered options

**Leave it invisible and put the explanation somewhere else** — a help line, a debug panel, the
manual. Rejected: the screen is where the player forms the belief, so the screen is where the
belief has to be correctable. Every other place is a second source of truth for the same
question.

**Make it a fifth EDITABLE slot** — let the player change what the fallback does, which
ADR-0048's own "considered options" already floated as a per-unit `default_safety_net`.
Rejected here and not forever: it is a different feature (the net stops being invariant, the
encoder stops being able to cache one template, and `GambitList` gains a fifth element with a
different lifetime from the other four). Showing what the net does costs none of that, and
whether the player should be able to edit it is a question better asked once they can see it.

**Seed slots 1–4 with the net's shape on a fresh unit**, so there is nothing to explain.
Rejected on dec. 5 — see there.

**Render it in the same shade as the authored rows**, on the grounds that it is just as real a
rule. Rejected: it *is* just as real, and it is not just as editable, and the row's only job
here is to say the second thing. A row the glove lights and then refuses is worse than an
invisible one, because the player learns the refusal by pressing.

**Grow the window to six rows so the net never scrolls out of sight.** Rejected: it cannot fit.
`GambitSurfaceMenu.GAMBIT_CONTAINER` is `Rect2(12, 134, 232, 104)` and the virtual screen is
256×240 — 134 + 104 = 238, with two pixels left. A sixth row is 16 more and lands at 254.

## Consequences

**On a battle host the list is six rows and the window shows five, so the net is one ↓ away.**
That is the price of the frame, per the rejection above; on the roster host, which has no
imperative, the five rows fit exactly and the net is on screen from the moment the surface
opens — which is where the authoring happens.

**The imperative's row sits between the slots and the net, and reading order therefore does NOT
match priority for it.** An imperative is *top* priority and is drawn fourth-from-last. That
predates this decision (#1006 appended it after the slots and ADR-0268 did not rule on the
order) and is left alone here rather than fixed silently: moving it is a change to
`GambitSurface._on_chosen`'s row dispatch and to the arms that walk to it, and it deserves its
own decision.

**A pre-existing dec. 1 violation was found and fixed to make dec. 2 observable.**
`GambitSurfaceMenu._on_selection_moved` rebuilt its row meshes only when the window *scrolled*,
and the LIT/DIM shade is baked into those meshes — so ↑/↓ moved the glove and left the band on
the row the player had LEFT. ADR-0268 dec. 1 gives that band the job of saying which row, "with
the glove agreeing at its left edge"; they disagreed. ←/→ never showed it because
`set_row_entries` rebuilds anyway. Photographed, not reasoned: the glove on the last row with
the first row still lit and still carrying the chevron. Row mode now rebuilds on every move;
the plain-entries mode, which has no band and no chevron, keeps the old cost.

**`GambitEncoder._safety_net_gambit` becomes `safety_net_gambit`.** One caller inside the
encoder, one on the screen.

**`GambitSurfaceTest` arm 17 is the guard**, 146/0 → 164/0. Seeded break: deleting the
`row == safety_net_row_index()` early return from `_on_chosen` → 134/15 — ○ on the net then
falls into the imperative branch, and arm 17 reds first with the arms downstream of the level
it leaves.
