# The turn queue strip is a row of framed cards on a band, up for the whole battle

[ADR-0244](0244-a-turn-queue-entry-is-a-turn-and-not-a-unit.md) built the turn-order
strip and got its hard question right: a queue entry is a TURN, so a unit fast enough
to act three times contributes three cards, and the pile of cards standing in front of
a slow unit is how its wait is shown. Nothing here touches that. What it did not
settle is how the strip should LOOK, and it said so — its own soft spots section flags
the readability calls as resting on one captured frame of Gariland.

The user reviewed it and named five things, in one sitting:

1. You cannot tell friendly from enemy.
2. It is always visible, and it is only relevant when a unit is taking a turn.
3. It looks high-res — the wrong resolution against the rest of the game.
4. It is unclear what it even IS to someone seeing it for the first time.
5. Nothing is framed, which is inconsistent with every other window on screen.

Four of the five are the same shape: the strip is the one thing on this screen that
is not a WINDOW. It has no chrome, no open and no close, and it is drawn out of a
UI2-era assembly ([UIPortraitFrame]) rather than out of UI3, so it inherits none of
the vocabulary — no aperture, no beat, no criteria — that every other window gets for
free. The fifth (the resolution) is arithmetic and is answered separately below,
because it is mostly NOT this widget's to fix.

**The user has since reviewed the answer twice more, and reversed five parts of it.**
Both reviews are folded into the decisions below rather than stacked beside them, so
this file states what should be true now:

- **Critique 2 is withdrawn** — the strip is up for the whole battle after all
  (dec. 8). The measurement behind the first answer was sound and the conclusion drawn
  from it was wrong: what a player wants BETWEEN the stops is who is coming, and a
  forecast that appears only once the answer has arrived is a forecast nobody consults.
- **Critique 4's answer is withdrawn** — the "Turn Order" title is gone (dec. 7). It
  cost a title band's height on every frame to answer a question that is asked once,
  by one player, on one screen, ever.
- **Critique 1's answer is halved** — the ROM's baked `Enemy` word cell is gone and
  the team-coloured underlay carries the side alone (dec. 2). Two markings where the
  review asked for one read as noise, which the first build recorded as a soft spot
  and this one settles.
- **The band goes ALL THE WAY ACROSS THE SCREEN** (dec. 7). Sized to the cards it
  stopped at the last portrait, and a backdrop with a visible right-hand end reads as
  a bug rather than as a layout. *"it looks bad. it should be the whole screen."*
- **A card no longer FADES: it apertures open and shut, and the strip WAITS for each
  verb to finish before starting the next** (dec. 3). The first build chose FADE on a
  mechanical ground that was true, and dec. 7's widening is what stopped it being
  true — the two asks resolve each other rather than trading off.

## Status

accepted — supersedes [ADR-0244](0244-a-turn-queue-entry-is-a-turn-and-not-a-unit.md)
decisions 6, 7 and 9; ADR-0244 decisions 1-5 and 8 stand unchanged. ADR-0244's
rejection of *emphasising the acting card* is **reopened, not settled** — see the
soft spot at the end.

## Decision

1. **Every part of the strip is a [UI3Element]: the bar and each card.**
   ADR-0244 dec. 6 built on `UIPortraitFrame` because `UIRosterBar` templates every
   frame at once and a queue interleaves the teams entry by entry. That argument was
   right about the ROSTER and wrong about the alternative: the third option is the one
   the whole screen is being moved onto. An element declares `transition`, `move`,
   `frame` and `clip` as criteria and gets the shared engines for free — which is
   exactly what decisions 3 through 8 below spend.

   This is also the user's standing preference for UI in this package, and it is the
   blocking step: none of the rest can be built on a `Node3D` that has no beat slot.

   The BAR element survives dec. 7 taking its frame away, and that is worth stating
   because "a frameless container" sounds like a node that could be deleted. It is the
   BAND's carrier: it owns the `OWN_APERTURE` and the `BOX_OPEN` beat that sweep the
   backdrop open, and its rect IS the band's extent (`_bar_rect`). The strip's root is
   a plain `Node3D`; moving the aperture there would take the beat with it. What it
   does NOT do is clip the cards — dec. 3 gave each card an aperture of its own, and a
   card is the bar's SIBLING under the strip root rather than its child.

   REJECTED: adding an ad-hoc tween to `UIPortraitFrame`. That is a fourth private
   animation accumulator in a package that spent [ADR-0088](0088-ui3-elements-register-a-criteria-spec-shared-engines-implement-it.md)
   and [ADR-0097](0097-transition-cadence-is-a-named-curve-per-verb.md)
   collapsing three of them into one engine.

2. **A team-coloured underlay backs every card, and beside the mirror it is the only
   side-marking.** The underlay works because of the portrait shader's own transparency
   key: FFT portraits are indexed with palette index 0 as the magic-0 transparent
   colour and `unit_portrait_3d.gdshader` discards it, so the space around a head is a
   real hole. Filling it tints the SILHOUETTE'S SURROUND, which both separates one card
   from the next and carries the side at a glance, before any word is read.

   ADR-0244 dec. 7 made the mirror the only side-marking. The mirror is a fine marking
   and it stays — but it is a COMPARATIVE one: it reads when two entries sit side by
   side facing each other, and a queue is precisely the structure that cannot promise
   a card a neighbour of the other side. Three allies in a row are three
   identically-facing portraits, and the strip goes silent exactly when the player
   most wants to know whose turns are coming.

   **The ROM's own `Enemy` word cell was built and then removed.** The first build
   drew FRAME.BIN's baked `Enemy` cell (`frame.tga` (229,176)-(254,185)) through the
   vitals panel's `MENU_CLUT`, tucked under the portrait and cropped along its bottom
   edge, on the argument that the sheet already carries the word and there was no
   reason to invent one. That argument is still true and it was not the question. The
   question is whether a card needs the marking TWICE, and seen on screen it does not:
   the red/blue underlay says which side at a glance and the word repeats it in
   six-pixel type. The first build recorded exactly this as a soft spot ("whether that
   is belt-and-braces or noise is a looking question rather than an arguing one") and
   the looking has now happened. The shader, its three tuck dials, the CLUT palette
   builder and four test assertions went with it.

   REJECTED: a per-card team-coloured frame CLUT. This has been asked twice and the
   second asking had a different premise: the first build rejected it because there
   were no per-card frames left to colour, and dec. 7 below has now given every card a
   frame. Asked again with the premise repaired, the answer is still the underlay — but
   on its own merits rather than by default. The underlay tints the space the player is
   already looking AT (the hole around the head); a coloured border tints the space
   between cards, where two adjacent enemies would merge into one red block. ⚠️ This is
   the decision on this page most likely to flip after one more capture, because the
   underlay was judged against a FRAMELESS card and every card has since grown a border.

   REJECTED: two lanes inside one frame, allies on top and enemies below. It is a
   strong read, and it costs the vertical space the strip cannot spare while destroying
   the left-to-right reading of turn ORDER that ADR-0244 dec. 1 rests on — a queue
   split into two rows is no longer a queue.

3. **A CARD ENTERS AND LEAVES BY ITS OWN APERTURE, and the three verbs are
   SERIALISED: the head card closes, THEN the survivors shuffle left, THEN the new
   tail opens.** This reverses the first build of this decision, which dissolved a
   card in and out and started the shuffle in the same pass as the dissolve.

   The reversed argument was mechanical and it was right on its own terms.
   `UI3BoxOpenBeat.precondition` reports itself inert on anything but a
   `clip = OWN_APERTURE` element, so driving a card's entrance through an aperture
   while the card was cropped by the BAR's would open a private scissor inside the
   scissor already cropping it. What changed is the PREMISE and not the mechanics: a
   card needs the strip to crop it only because it can be somewhere the strip is not,
   and it could be, only because it entered by sliding in from off the right edge.
   Take the slide away and there is nothing left to crop — a card is built AT its
   slot, opens its own box there, and never occupies a pixel outside the row. So a
   card declares `Clip.OWN_APERTURE` and becomes the strip root's child and the bar's
   SIBLING. Dec. 7's screen-wide band was blocked by the same fact and is unblocked by
   the same move; the two asks answer each other rather than trading off.

   **The order is a chain on the elements' own signals — not a recipe, and not a
   clock.** The transition engine has no barrier facility (`FormationDetailTransition`
   carries recipe machinery; the engine does not) and needs none: `UI3Element` emits
   `closed` and `moved`, `_retire_card` already chained on `closed` to free its node,
   and one more link is the whole sequence. A clock was never on the table — charter
   clause 14 forbids `create_timer` under `tests/`, and `TurnQueueHudTest` hand-steps
   every beat through `UI3Registry.transition_engine_step()` precisely so nothing in
   this widget can wait on one.

   **Only the PLAYS are serialised; the DIFF is not.** `_cards`, `shown_indices()` and
   `draws()` are all correct the instant `show_entries` returns. A card still waiting
   its turn is a real element standing at its real slot with a SHUT aperture, which
   draws nothing — so dec. 6's redraw gate and the pure-view seam keep meaning exactly
   what they meant, and a test can read the queue without stepping a beat.

   **A refresh landing mid-chain REPLACES the pending step rather than queueing behind
   it**, because the queue it was going to animate is not the queue any more. A
   generation stamp makes the superseded chain's in-flight callbacks inert, and the
   re-diff folds any still-shut survivor back into the new chain's entrants, so a
   cancellation cannot strand a card closed. `_leaving` — which existed already, so a
   second refresh could not re-adopt a card mid-close — is also the barrier the first
   stage waits on. The chain is ARMED before the retirements are requested, because
   `close()` can settle synchronously and a `closed` that fired while the pending lists
   still held the previous refresh's work would advance a chain whose queue is gone.

   **`Transition.FADE` keeps its enum member and keeps its registration, with no
   caller.** The member cannot be removed whatever happens (see the Consequences: the
   ints are authored as literals and persisted as Tune overrides, so a kind may only be
   APPENDED), and an enum answer that resolved to no registered beat would not error —
   it would SNAP, silently, which is worse than a facility with no consumer. So
   `UI3FadeBeat` stays registered against it, and `unit_portrait_3d.gdshader` keeps its
   `fade` uniform, now with no writer and its 1.0 default. Two arithmetic assertions in
   arm 9 are what is left guarding the beat.

   **The ROM's fade ramp is that beat's provenance and is kept here, because this ADR
   is what transcribed it.** The one observed ROM fade is the prayer-text dismiss
   (living doc Part A / §C.1, already transcribed in `DialogueOverlay`): the composed
   text primitive's Gouraud RGB ramps `0x80` to `0x38` in steps of `-8`, one step per
   60 Hz fiber yield — code constants, fiber loop `0x80131628`, writers
   `0x8013164c/74/9c`, floor test `s1 >= 0x31`. `UI3FadeBeat` walks that step, at that
   clock, over that domain.

   **The recorded divergence is the FLOOR, and it is forced.** The ROM stops at `0x38`
   and disappears the text by freeing its window handle; it never draws a fully-faded
   frame because it does not have to. A UI3 close has no handle to free —
   [ADR-0084](0084-formation-screen-transitions-are-reversible-beats-composed-into-recipes.md) invariant 1
   makes leave = the beat reversed — so a reverse that stopped at 0.44 would leave the
   element at half brightness forever. The same `-8` step therefore runs the full `0x80`
   to `0x00`. A second, smaller divergence: the ROM multiplies BRIGHTNESS, which on a
   black PSX background is indistinguishable from fading away, while our windows sit on
   lit frames where a brightness ramp fades content to BLACK against the fill. `fade`
   multiplies ALPHA. The STEP and the CLOCK carry the ROM's cadence; those are the parts
   that were worth taking.

   **There is deliberately no FAST cadence**, for exactly the reason `UI3MoveSlideBeat`
   has none: the ROM has one fade ramp and no stride flag over it. `DAT_8015326C` is
   read only by the two box-open scalers and never reaches this fiber. A doubled step
   is a curve the beat COULD walk, but naming it FAST would claim a ROM speed that
   does not exist, which is the mislabelling ADR-0097 §1 exists to stop.

4. **A computed home answers WHERE with `derived()`, and walks there with
   `move_to_answer()`.** `place_at` is the verb for a KEY LOCATION — an authored
   place, one of an element's legal homes, with a slug an F3 scrub can move. A queue
   slot is not that. Slot 4 of a strip is `pad + 4 * pitch`: a position that exists
   only because two other knobs have values.

   Giving each of the sixteen slots its own location slug would mint sixteen knobs
   that must never be scrubbed independently — a lying knob sixteen times over.
   Authoring the rect as a LITERAL is worse and not merely inelegant: a literal rect
   mints a `<id>.rect` bind whose default is first-write-wins, so the first card ever
   built at slot 3 would freeze that slot's rect, and a later scrub of the portrait
   scale would re-apply the stale default and strand every card at its old position.

   So a card answers WHERE with the answer form the system already has for a computed
   home. What was missing was only the VERB: `_subscribe_rect_driver` already
   re-evaluates a derived answer and SNAPS to it when a driver moves, and
   `move_to_answer` walks the same distance on the declared move beat instead. The
   rect answer is untouched, which is the whole difference from `place_at`.

   Scrubbability is not lost, it MOVES: a card's home is a pure function of the bar
   rect, the card pitch and the card size, and all of those are `Tune` binds on the
   owner. The rule the two verbs share is the one that matters — an element still never
   decides which home it occupies.

5. **BACK is a cadence on the slide beat, with its OWN overshoot, priced against the
   card pitch.** The user asked for the entrance every other window on this screen has:
   overshoot and pull back, like the dialogue box, the vitals panel and the nameplate.
   That curve exists — `FormationHoverAnimator.pair_fraction_at` walks the back-out
   ease `1 + (s+1)u³ + su²` — and it is already a recorded divergence from the ROM, so
   adding a second of the same class is not a new kind of debt.

   **What must NOT be inherited is the hover's `s = 0.7`.** Back-out at `s` peaks
   `4s³/27(s+1)²` past the mark, so `0.7` is +1.76%. On a turn-queue card shuffling one
   slot — a pitch of about 32 display px once dec. 7's border is counted — that is
   **0.6 px**. Sub-pixel: the cadence would be indistinguishable from NORMAL at the one
   place it was added for. The hover's `0.7` was bounded by a measured 4 px of slack on
   a much longer journey, and a number is not a curve. This beat's default is `s = 1.9`,
   peaking +12.1% — about 3.9 px on that pitch, visible against the card's own border
   and short of the neighbouring card, so a springing rank never reads as a collision.

   **That one-slot shuffle is now this cadence's whole job.** The first build also
   priced BACK against a card entering from off the strip's right edge, where the same
   12% scales into something much larger and the pull-back reads most clearly. Dec. 3
   deleted that entrance — a card apertures open in place — so the 3.9 px above is not
   the small end of BACK's range here, it is the only end, and it is the number any
   re-scrub of `s` has to be judged against.

   BACK also gets its own LENGTH (8 frames, against the §15.1 table's 6). At 6 the
   ease's peak lands at frame 3.4 and only two frames of pull-back remain, which is
   about 66 ms at this beat's ~30 Hz visual cadence: the motion happens and barely
   registers. Both knobs are `Tune` binds, because this is the part a player settles.

   REJECTED: reading `FormationHoverAnimator.PAIR_OVERSHOOT_DEFAULT`. It ties two
   unrelated widgets' feel to one number that was priced for one of them.

6. **The refresh DIFFS the queue: cards enter, move and leave.** This is what the
   other decisions are FOR. The previous build tore every card down and repainted
   whenever the order moved, and that is why nothing could animate — a card destroyed
   and recreated one slot to the left has no identity to carry a motion.

   The match is greedy and stable: for each new entry, the first unmatched existing
   card with the same `(index, team)`. That is exactly right for the only thing this
   widget ever does between two turns — the head takes its turn and drops off, everyone
   shuffles one slot left, one new turn appears at the tail — and it keeps both cards
   of a unit that appears twice in one round-robin, in order, which ADR-0244 dec. 1
   requires.

   ADR-0244 dec. 5's redraw gate is KEPT and is unchanged: an unchanged ORDER still
   repaints nothing, and `draws()` is still its only honest witness. The diff is what
   happens after the gate lets a change through, not a replacement for it.

7. **EVERY CARD WEARS A FRAME, THE STRIP WEARS NONE, AND THERE IS NO TITLE — the
   chrome is a [UIVitalsBand] behind the row, and it runs the WHOLE WIDTH OF THE
   SCREEN.** This is a THIRD position, and neither of the two ADRs before it held it.

   ADR-0244 set `show_frame = false` on every card AND gave the strip no frame at all,
   because eleven bordered cards shoulder to shoulder read as a row of empty boxes.
   The first build of this ADR went the other way: one frame around the whole strip
   with a title band, on the argument that one frame makes the strip a WINDOW, which
   is what every one of its neighbours is. The user has now seen both, and neither is
   what landed. What decided it is that the two arguments are about different things —
   ADR-0244's "row of empty boxes" is a complaint about eleven EMPTY borders, and a
   card with a face in it is not empty; "one frame makes it a window" is a claim about
   the strip's identity, and a dark band under a row of portraits establishes that
   identity without spending a border's worth of pixels on all four sides.

   So: a card carries `Frame.MENU_TILE`, the bar carries `Frame.NONE`, and the bar's
   payload is a subtractive band sized to the bar — which is the screen. The card's
   rect is GROWN by the
   9-slice's own margins (4/4/5/4, read off `UIFrame`'s constants and never restated)
   so the border draws around the face rather than over it, and the outer box is
   CEILED to whole display px — an un-rounded box gives a fractional pitch, the cards'
   left edges drift a third of a pixel each, and every third gap picks up a stray dark
   column while its neighbours have none. `spacing` came from 2 to **0**: the border
   IS the separation the gap was buying, and a gap on top of two adjacent borders reads
   as a dead channel rather than as a queue.

   **The title is gone.** "Turn Order" answered critique 4 — "it is unclear what it
   even IS" — and answering that question with three words costs a 16 px band on every
   frame of every battle, forever, to inform a player once. The band and the frames
   between them say "this is a readout" without saying anything; what it is a readout
   OF is learned in one turn by watching the head card leave. This also deletes the
   first build's soft spot about the title not being apertureable
   (`ui_font_char.gdshader` carries no `clip_world`, so the header declared
   `Clip.UNCLIPPED` and was hidden outright until the box finished opening) — the
   problem stops existing rather than being solved.

   **The band is the SHARED producer**, `UIVitalsBand` — the same element the vitals
   panel, the nameplate, the roster's bottom stripe and the map host's pick dim use, at
   the oracle's own `base_rgb` 120 body strength. Deliberately NOT the nameplate's cheap
   `Color(0, 0, 0, 0.55)` alpha quad, whose own comment calls itself "a dark contrast
   band (NOT a frame)": that quad is alpha-blended in scene space, and this band needs a
   blend mode and the engine fold, because it must subtract from a lit battlefield
   rather than paint a guessed grey over it.

   It is mounted as the BAR ELEMENT'S OWN PAYLOAD — a plain holder under the bar, which
   `UI3ClipEngine.payload_materials` collects — and not beside it. That is what makes it
   ride the box-open aperture: it receives `clip_world` and `clip_basis_inv` from the
   same pushes the cards get, so the backdrop opens WITH the strip, and this widget
   still has no `_process`. A band mounted as a sibling would have needed a per-frame
   uniform push to stay clipped, which is the cost the first build's "nothing per frame
   while it is settled" claim would have quietly lost.

   **IT RUNS THE WHOLE WIDTH OF THE SCREEN.** The first two builds sized the band to the
   bar and the bar to the cards, so the backdrop stopped at the last portrait — which is
   what the user's second review named, and on screen it read as a bug rather than as a
   layout. The band is this element's own payload, so widening the band means widening the
   BAR: `_bar_rect` is the screen's span, and its x0 is NEGATIVE, because the screen's left
   edge lies to the left of the strip's `screen_pos` anchor. The HEIGHT is unchanged and
   deliberately so — "all the way across" is a claim about the horizontal extent, and a band
   as tall as the screen is a dim, not a strip.

   That span is DERIVED and is deliberately not written down. Under an ortho host it is
   `REFERENCE_CAMERA_SIZE * aspect / ppu` — about 373 display px on the battle camera — and
   the camera SIZE cancels out: `UIWindowHost` counter-scales this whole host by
   `camera.size / 14.0`, so a zoom widens the frustum and shrinks the strip's pixels by
   exactly as much. What is left is the viewport's ASPECT. `_screen_span_px` measures it
   through the host's own frustum arithmetic whenever a camera exists — the cancellation is
   an ORTHO identity and a perspective host gets no counter-scale — and falls back to the
   ortho form when there is no camera at all, which is every UI3 unit rig. A literal 373
   would be a capture-rig constant masquerading as a layout.

   **Widening it cost the cards their parent, and that is the price.** A child element
   places itself at `rect.position - parent.authored_home()`, and `authored_home` is FROZEN
   at construction — so a bar whose rect moved to a negative x would put every card one
   screen-margin left of its slot. The cards are therefore the STRIP ROOT's children and
   the bar's siblings. Nothing else moved with them: their rects were already ABSOLUTE in
   the strip's space (which is also the space `clip_world` reads), their fold rungs resolve
   to the same root default the bar's do, and the one thing they used to get from the bar —
   the aperture — is exactly what dec. 3 took away from it.

   **The queue's LENGTH no longer reshapes the band**, so `_bar_slots` is gone and with it
   the two lines that re-aimed and reshaped the bar on every refresh. What is left is that
   the band's extent follows the VIEWPORT, and a viewport is not a `Tune` slug, so no rect
   driver re-evaluates on a resize: `TurnQueueHud._relayout` overrides the host's own poll
   for that edge and re-derives there. ⚠️ This is a DIFFERENT override from the one the
   consequences below record as deleted — that one re-pushed clip bases and was a half-fix,
   because relayout never fires on a pan. This one answers a question relayout is precisely
   the right door for.

   ⚠️ The band is reshaped, never rebuilt (`UIVitalsBand.update_extent`): freeing a member of
   the compositor's fold layer while that layer composites corrupts the engine heap on the
   4.8 fork. It runs on a knob scrub, a PAR change or a window resize now, rather than on
   most turns.

8. **The strip is up for the WHOLE BATTLE, and the only thing that takes it away is a
   screen standing over the battlefield.** This reverses the first build of this
   decision, which tied the strip to the open TURN.

   The reversed argument was: ADR-0244's "cheap, so always on" was written at
   `TURN_METER_FULL = 100` — 244 turns a battle, a stop every 0.11 s — and
   [ADR-0260](0260-the-turn-meter-is-a-dwell-clock-and-the-dwell-is-two-ability-cooldowns.md)
   then set the dwell to 600 ticks and MEASURED 8 stops per Gariland battle, between
   which the strip is furniture for about ten seconds at a time. The measurement is
   right. The inference from it was wrong, and seeing it on screen is what showed that:
   those ten seconds are when the player is deciding, and "who acts next" is the
   question a decision is made against. A forecast that appears only at the moment its
   answer arrives has nothing left to forecast.

   The edges:

   - **Open and close on the BATTLE.** `NavigatorRunner` already carries it —
     `GameState.State` has `PRE_BATTLE` and `BATTLE`, `_dispatch` sets both, and
     `NavigatorMain` already listens to `state_changed`. No signal is invented. The
     real edge is `PRE_BATTLE` → `BATTLE` and back out; this runner never sets
     `DEPLOYMENT`.
   - **[GambitBattle] says nothing, and that is the right answer.** It has no
     `NavigatorRunner` and no `GameState`; it is a battle-only harness, so the strip's
     default of LIVE is already correct there and it is up from the moment the queue
     has anything in it. Teaching it to report a phase it does not model would be
     inventing state to satisfy a subscriber.
   - **Hide while a screen covers the battlefield**, through each host's existing
     `pause_battle` hook. The map-hosted Formation/Status screen covers the map the
     strip annotates. ⚠️ NOT `FormationMapHost.unit_activated` plus the screen's
     `dismissed`, which is the obvious pair and is a HIDE WITH NO MATCHING SHOW: the
     map host is PERSISTENT and `FormationDetailTransition._on_dismissed` returns early
     on `Host.MAP` without emitting, so `dismissed` never fires there. The pause hook is
     the coordinator's `_take_claims` / `_release_claims` edge — held iff its screen
     stack is non-empty — which is the same fact in a form that fires both ways.
   - **The hide PLAYS THE BOX-OPEN BEAT**, both directions, rather than writing
     `visible`. A strip that blinks out is the one thing on this screen that does not
     open and close like a window, and the beat costs nothing while it is not playing.
     Every CARD plays it too, on the same edge: cards stopped riding the bar's aperture
     when dec. 3 gave them their own, so a strip whose chrome opened alone would show a
     full row of cards already standing there behind a band still sweeping out. The
     strip's own box-open now sweeps the ENTIRE SCREEN WIDTH, which is dec. 7's band
     doing what a band does.

   `turnqueue.show_only_on_turn` is DELETED rather than left as an escape hatch. It
   restored a lifecycle no code now implements, so it would be a knob that does
   nothing — which is worse than an absent knob, because it reads as an answer.

   The two director subscriptions (`turn_opened`, `resumed`) are KEPT and unchanged:
   they were never the strip's lifetime, they are the two edges on which its CONTENTS
   can have gone stale, and that is still exactly what they are used for.

   **Not visible during deployment.** There is a case for the other answer — turn order
   while placing units is real information — and it was put and declined. It belongs
   with the head-marking question in the soft spot below, because both are about what
   the strip should SAY, not about when it exists.

9. **Overflow is CAPPED at eight cards and simply not drawn; the portraits do not
   shrink.** Always-on is what makes the width a real constraint rather than a
   theoretical one — at `portrait_scale` 0.7292 and PAR 1.25 an eleven-card round-robin
   spans about 353 of the ~373 display px this frustum gives (dec. 7 DERIVES that width
   rather than quoting it), which is most of the screen for most of the battle.

   `turnqueue.max_cards` (default 8, live) is that cap, and it replaces ADR-0244
   dec. 9's `max_shown` 16 belt. Two things changed, not one: the NUMBER, and what kind
   of thing it is. ADR-0244's was a belt against an unreadable queue and reported itself
   with a warning when it bit, because a silently short strip reads as "the queue ends
   here". This one is MEANT to bite on an ordinary Gariland round-robin, so the warning
   goes: a line printed on every battle is a line nobody reads. It is a display policy
   and is labelled as one.

   REJECTED: `portrait_scale = 0.3646`. It is the other exact sampling ratio (see
   below) and a quarter of the area, and it is the size the user had already called
   unreadable before this ADR started. Making the strip fit by making it illegible
   answers the wrong complaint.

   No conflict with ADR-0244 dec. 1: "an entry is a TURN" says what an entry MEANS, not
   how many of them are on screen. A capped strip still never collapses a unit's two
   turns into one card — the cap trims the TAIL, which is the part furthest into a
   projection [TurnQueue] already documents as unreliable.

## Considered options

**Critique 3 is arithmetic, not taste, and it is now mostly answered.**
`UIWindowHost._relayout` counter-scales by `camera.size / 14.0`, which makes a UI virtual
pixel screen-CONSTANT at `0.04 * 960/14 = 2.743` screen px, independent of zoom. At
`portrait_scale = 0.45` a portrait texel lands on 1.23 screen px: some texels get one screen
pixel and some get two, under `filter_nearest`. It is undersampled UNEVENLY, which is what
reads as "wrong resolution" — it is not high-res.

So the default scale becomes **0.7292**, at which a portrait texel is exactly 2.0 screen px.
The cost is size, and dec. 9 is what pays it. 0.3646 is the other exact answer, at a quarter
of the area, and is rejected there. A transposed constant is fixed too; see below.

The third and largest lever, `pixels_per_unit = 0.04375` making a UI pixel exactly 3.0 screen
px for the whole of ui3, is NOT taken: it moves every window in the package and is its own
ticket.

**PAR is read, never written.** `PSXDisplay._ui_par_default` is 1.0 today, commented as
square UI PAR for alignment work, and `UIPortrait` subscribes to
`render.ui_pixel_aspect` and overwrites its authored 1.25 from it. That is four
elements' shared setting and the user's instruction is that the strip inherits whatever
portraits use everywhere else; 1.25 comes back through the debug scrub, not through
code here. This widget subscribes to the same signal so its LAYOUT follows.

**Every owner knob is reachable from the UI3 page, in one place.** `UI3RegistryView` is a
view over registered elements and each element's `criteria()`, so a class-owned slug like
`turnqueue.max_cards` has no row there and cannot get one — `criteria()` reports an
ELEMENT's fields and a card cap is not one. The two slugs that DRIVE a derived rect
(`turnqueue.spacing`, `turnqueue.portrait_scale`) were already reachable, but as a driver row
nested under each element's derived `rect`, i.e. once per element, ten times over, each inside
its own fold. The page grows an **owner-knob section**: one row per class-owned slug in the
namespaces its elements live in, plus `ui3` (the shared engines' knobs, which every element
rides), minus anything already editable as a criterion, a driver or a key location. Derived by
namespace and not from a hand-written list, because a list in a debug panel is schema living in
the view — the thing [ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md) moved
out — and it would go stale the first time an owner added a knob.

`turnqueue.screen_pos` joins it, and is the reason the section is not merely tidier: the
strip's corner was an `@export` on a host that is built in code, so nothing ever opened an
inspector on it and the one number deciding where the strip sits was the one number a player
could not move. It is deliberately NOT a `<ns>.loc.` KEY LOCATION: a key location is a home a
UI3Element occupies via `place_at`, and the page renders one with a re-home dropdown. This is a
`UIWindowHost` anchor in normalized screen coordinates that no element is homed at, so filing
it there would render an affordance that does nothing.

**REJECTED: a per-slot Tune location for each card** — see decision 4.

**REJECTED: keeping `UIPortraitFrame` and giving it a `fade` property.** It would have
been three lines and it would have put a private animation clock in a UI2 assembly that
two ADRs are trying to retire.

**REJECTED: doing anything about the strip overlapping the compass.** Asked and answered
by the user: it is fine.

**REJECTED: leaving the band on the bar and giving it its own full-screen element.** The
band could have become a second [UI3Element] sized to the screen, sibling to a bar still
sized to the cards, with its own `OWN_APERTURE` and its own box-open. It answers the
first ask without touching the second. It is rejected because it splits one thing in two:
the strip would then own an aperture that crops nothing (dec. 3 having given the cards
their own), a beat that drives nothing, and a rect whose only reader is a `_bar_slots`
count nothing else consults. Widening the bar deletes all three instead of parking them.

**REJECTED: keeping the cards under the bar and re-deriving its `authored_home`.** It
is the smaller diff — one field instead of a reparent. `authored_home` is FROZEN by
contract (`UI3Element._home`, "the frozen content anchor"), every `rel_world` offset in
the package is absolute against it, and making one element's mutable would make the
contract conditional for all of them. The cards owed the bar nothing but placement once
dec. 3 took the aperture away, so moving them is the cheaper answer where it counts.

**REJECTED: a Clip mode that intersects an element's own aperture with its parent's.**
It would let a card box-open *and* stay cropped by the strip, which would have made
dec. 3 possible without dec. 7's reparent. It is a new answer in a shared criterion's
vocabulary, bought for one widget that no longer has anything outside its own row to
crop. If a future strip ever stages a card off-screen again, this is the option to
re-open — not the fade.

## Consequences

**The `Transition` enum gained a member, appended.** `FADE` is 4. These ints are
authored as literals in construction-site specs AND persisted as Tune overrides for the
F3 criterion knobs, so a new kind may only ever go on the END — inserting one silently
re-points every stored answer at a different beat. That rule is now written on the enum,
and it is why dec. 3 keeps `FADE` after retiring its only caller: the member is
unremovable, and an unremovable member with no registered beat would SNAP rather than
error. `UI3FadeBeat` therefore ships registered and uncalled, which is a state worth
naming so the next census does not read it as dead code.

**`unit_portrait_3d.gdshader` gained `clip_world` and `clip_basis_inv` as well as
`fade`.** The clip pair is what makes a portrait mounted in any box-open window ride
that window's reveal, and under dec. 3 it is what the CARD's own aperture drives — so
what began as the crop on an entering slide is now the entrance itself. Both default to
unbounded, so every portrait outside UI3 is unchanged. `fade` is left in place with its
1.0 default and no writer; deleting it would be a second, unrelated change to a shader
four other classes draw through.

**FOUND: `PORTRAIT_BASE` had its two axes TRANSPOSED, and it is part of critique 3.**
The constant read `Vector2(48, 40)` and its comment said 48 wide by 40 tall. UIPortrait
computes `width = tex_height * PAR` and `height = tex_width` from a 48x32 cell, so the
footprint is `(32*PAR, 48)` — at PAR 1.25 that is 40 wide by 48 tall, the other way
round. The strip was laying an 18 px-wide portrait out on a 21.6 px pitch and centring
it in a box the wrong shape. The footprint is now DERIVED from UIPortrait's own
constants and the live PAR, so it cannot drift again. Dec. 7's card margins are read off
`UIFrame`'s own constants for the same reason: that crop has already moved once (the ROM
dark-outline column pushed left/top from 3/4 to 4/5).

**FOUND: tearing the cards down has to clear the redraw gate's memory.** The gate
compares the QUEUE, but the question it must answer is whether what it drew is still on
screen. Closing and re-opening over an unchanged queue hit `key == _shown` and returned
early — the strip opened onto no cards at all. The teardown now clears `_shown`, and arm
11 of the test is that seed. Always-on did not retire this: the close/re-open that
reaches it is now dec. 8's cover gate rather than the turn gate, and it fires every time
the player opens a unit's screen.

**FOUND: the bar has to boot SHUT.** A freshly-adopted element's settled aperture is
its full rect, so the very first `open()` rendered one frame of a fully-open box before
the beat's frame 0 snapped it back to 10% — a flash exactly one vsync long, on the
first thing the player sees in a battle. It is closed IMMEDIATE at build time, which
settles synchronously (ADR-0097 §3).

**FOUND: a camera-child host leaves every clip basis stale, and a stale basis discards
EVERYTHING.** `UI3ClipEngine.clip_basis_inv_for` snapshots the screen root's global transform
at push time, and identifies the screen root by `has_method("screen_to_world")` — the idiom
DetailScene and FormationScene carry. This host had two problems at once: its strip anchor was
a bare `Node3D`, so the walk fell through to IDENTITY, and the whole strip is BUILT in `_ready`
while that anchor still sits at the camera's origin, before the first `_relayout` moves it to
its screen position and scales it by the camera counter-scale. `clip_world` (display px * ppu,
in the anchor's space) was therefore compared against a GLOBAL vertex position, the two
disagreed by the whole placement, and the strip rendered NOTHING while the UNCLIPPED title
above it looked perfectly fine.

**That defect had a TAIL, and always-on is what exposed it.** `UIWindowHost._process` skipped
`_relayout` on camera TRANSLATION, and its comment was half right — a window's screen-local
POSITION is invariant under a pan, its GLOBAL TRANSFORM is not, because the host is a child of
the camera. So the strip vanished whenever the map cursor panned and came back full on any
close/re-open, which re-drove `_set_aperture` → `_push_clip` → a fresh basis. The turn gate had
been masking it by closing and re-opening every few seconds; taking the gate away made it a
blocker. MEASURED across a pan, printing the basis off each card's payload material: the live
origin moved `(6.869333, -6.579999)` → `(3.536, -7.691111)` while all three payload shaders
still carried the pre-pan value — exactly the camera translation divided by the host's own
`camera.size / 14.0` counter-scale. The fix is `refresh_clip_basis` on the camera's transform
changing — the engine's own cheap one-uniform re-push, built for exactly this under ADR-0137
Amendment 3 — and it lives in `UIWindowHost`, because the defect is a property of BEING a camera
child and it hits every camera-child host plus the map-hosted formation screens.
`TurnQueueHud`'s own `_relayout` override called `refresh_clip_basis` too and was the half-fix:
relayout never fires on a pan. It is gone; the base now covers both doors.
`UI3OwnerColorMap._debug_material` carried the same defect in its other half — it copied
`clip_world` off the payload and never `clip_basis_inv` — which is why the ownership map drew
no colour on those same screens. Both are guarded by MECHANISM assertions folded into
`UI3ClipEngineTest` and `UI3OwnershipMapTest`; the SYMPTOM is untestable twice over, because
no layout assertion can see an absent fragment.

**FOUND: an ordering claim needs step INDICES, not settled states.** "Close, then
shuffle, then open" is entirely about WHEN, and a build that plays all three at once
reaches the same settled positions, the same card identities and the same apertures — it
passes every endpoint assertion. Arm 8 therefore hand-cranks ONE walk and records the
first step at which each verb happens, then asserts the indices are ordered. Seeded four
ways (the band back to card width; the close barrier removed; the shuffle barrier
removed; a card back to `PARENT_APERTURE`), each seed reds its own arm and no other.

**FOUND: `close()` can settle SYNCHRONOUSLY, so a chain must be armed before it is
started.** An IMMEDIATE cadence, or an element that is already shut, emits `closed`
inside the `close()` call. `_reconcile` therefore stamps the generation and stores the
pending lists BEFORE it retires anything; the earlier ordering would have let a
synchronous `closed` advance a chain still holding the previous refresh's work.

**FOUND: landing a rect on a SHUT element re-opens its aperture.**
`UI3Element._apply_rect` re-derives the aperture from the live rect whenever the element
is `OWN_APERTURE` and `_settled` — and a settled CLOSE is settled. So the two places this
class lands a rect outside a beat (the PAR scrub and the new `_relayout`) re-close
IMMEDIATE afterwards for anything that was not open. Invisible today, because a shut
strip has `visible = false`; it would not stay invisible the first time a card is shut
while the strip is not.

**FOUND: an arm that tests a curve is blind to what declares it.** Arm 10 asserts the
BACK curve overshoots, lands and left NORMAL alone — and stayed green when the card's
spec was seeded from `BACK` to `NORMAL`, because a pure predicate proves the DECISION
and not that any consumer consults it. Arm 8 now watches the survivor's whole walk and
asserts it travels PAST slot 0 before settling on it; a monotone cadence never crosses
its destination.

**Measured, and LOOKED AT.** `TurnQueueHudTest` carries 11 arms with an assertion count and a
zero-assertion guard (test charter clause 9). Every animation is hand-stepped through the
transition engine's guard seam, so nothing waits on a clock (clause 14). Seeded defects each
redden only their own arms: removing the gate-memory reset (arm 11), neutralising the redraw
gate (arm 4, both directions), dropping the cover term from `_sync_open` (arm 11), setting the
card's frame criterion to NONE (arm 2), swapping the card's cadence to NORMAL (arm 8), sizing
the band back to the card row (arm 2), removing the close barrier and removing the shuffle
barrier (arm 8, one index each), and putting a card back on `PARENT_APERTURE` (arm 9).

`tests/TurnQueueHudShot.tscn` is the capture instrument, kept rather than thrown away, and it
is not in the runner's list — it emits no verdict. It writes a settled frame and TWO mid frames,
one per stage of dec. 8's open: the band's scissor part-way across the screen with every card
still shut, and the band settled with each card's own box part-way open. Between them they are
the only thing that can tell a working aperture from an absent one. Each shot PRINTS the two
apertures it caught as a percentage of their own rects — the settled shot reports
`band 100% of 373 px, head card 100% of 32 px`, the two mid shots 60%/0% and 100%/59% — because
the engine is driven from `_process`, so the render frames the rig must await to get a DRAWN
image are themselves beat frames, and a mid-open shot that quietly drifted to 100% looks exactly
like a strip with no aperture at all. All of this widget's invisible defects were found by
looking at it, including dec. 8's two-stage open, and none was findable by a test until it had
been seen once.

**And LOOKED AT ON A LIT BATTLEFIELD, which the capture rig cannot be.** `TurnQueueHudShot`
draws the strip on the viewport's flat grey, and dec. 7's band is SUBTRACTIVE — on a flat grey
it is indistinguishable from a painted near-black rectangle, so the rig cannot tell the shared
producer from the cheap alpha quad it was chosen over. Booted through `GambitBattle`
(`--combat-autostart`) over Gariland with a turn open, the strip's band subtracts from the SKY
and lands as the same dark navy the vitals band at the bottom of that same frame lands on —
one look, two bands, one producer, which is the read the decision is for. The eight framed
cards span about 72% of the width at the top-left, clear of the vitals panel and of the
nameplate, and the team underlay carries the side at a glance behind each head.

Looked at again once the band ran the full width: it subtracts across the whole sky, edge to
edge, with its feather visible at both long edges, and the card row still starts at the
`screen_pos` anchor rather than at the band's left edge — which is the half a merely-wider band
would have got wrong. ⚠️ There is now roughly three times as much band on screen and
`turnqueue.band_sub` has not been re-judged against that; the strength was settled over
Gariland's sky when the band stopped at the last portrait, and how dark a backdrop should be is
a looking question about how much of it there is. Recorded in `audit-notes/0269.md`.

**Soft spots, stated as such.**

⚠️ **ADR-0244's rejection of emphasising the acting card is REOPENED.** The first build of
dec. 8 settled it from the other side — the strip did not need to distinguish the acting card
because the strip was only on screen while there WAS one. Always-on deletes that argument
entirely, and the question goes back to open with nothing standing in its place: for most of a
battle the strip now shows a queue whose head is nobody's current turn. Marking the head is
deliberately NOT built here — it is a looking call that could not be made until always-on was
on screen — and it is the next ticket, along with dec. 8's declined "visible during deployment".
This paragraph exists because an ADR that silently drops a question it claimed to settle is the
"cited claim with no source" failure.

⚠️ **Dec. 2's underlay was judged against a frameless card** and every card now has a border.
The per-card team-colour CLUT rejected there is one capture away from being re-asked a third
time, and this time the premise is fully repaired.

Beyond those: `max_cards = 8` and `spacing = 0` are capture calls on one queue shape, and the
strip has never been seen at PAR 1.25 (the debug scrub's value; `PSXDisplay`'s default is 1.0,
so every capture behind this file is square-PAR). Each card slot mints about eight Tune binds from its
element id, so the F3 tree grows by roughly a hundred rows for a widget with one real layout
knob; they are bounded and stable, but they are noise. And the colour choice, the tint alpha,
the band's two dials and both BACK knobs are exactly the parts a player settles, which is why
every one of them is a live bind rather than a constant.

## Amendment 1 (2026-09-09) — the first dial after the split moved three of this ADR's numbers, and one of them trades away dec. 4's whole argument

Four `turnqueue.*` defaults were re-dialed on the live strip and materialized back into
`TurnQueueHud.gd` through `tools/materialize_tunables.py` ([ADR-0068](0068-tunables-bind-a-slug-to-a-code-default-with-a-coalescing-override-layer.md)
dec. 8), so the literals this ADR quotes are no longer what the code holds:

| slug | this ADR | now |
| --- | --- | --- |
| `portrait_scale` | 0.7292 | **0.85** |
| `portrait_offset` | (4, 5) = the frame's margins | **(2, 2)** |
| `spacing` | 0 | **3** |
| `screen_pos` | (0.04, 0.03) | **(0.015, 0.03)** |

**`portrait_scale` 0.85 abandons the exact-sampling argument, deliberately.** The
"so the default scale becomes 0.7292, at which a portrait texel is exactly 2.0 screen px"
reasoning is the one this ADR argued hardest, and 0.85 lands a texel on 2.33 — the same
uneven undersampling `0.45` was faulted for, at a different ratio. What changed is that the
card stopped being derived from the portrait: `card_scale` is a knob now (it was not when
this ADR was written) and STAYED at 0.7292, so `portrait_scale` no longer sizes the card and
"make the face fill the frame" became a value someone could dial. It was dialed by looking at
portraits on the strip, which is the same authority the 0.45 verdict had. 0.7292 and 0.3646
remain the two values that ANSWER the arithmetic if the resampling is ever judged worse than
the fill. `portrait_offset` (2, 2) is the same gesture — MEASURED, a 27.2x40.8 face in a
32x45 card is centred by a ~2 px inset, not by the frame's (4, 5) margins.

**`spacing` 3 closes the soft spot that named it.** The Consequences call `spacing = 0` a
capture call on one queue shape; it was, and looking overturned it. Dec. 4's prediction was
that a gap on top of two adjacent borders would read as a dead channel — what it actually
reads as is one thick divider between two cards rather than two cards, and 3 px re-separates
them without opening that channel.

**The PAR soft spot stands, and is now CONFIRMED rather than suspected.** "The strip has
never been seen at PAR 1.25 … every capture behind this file is square-PAR" was right:
`PSXDisplay.live_ui_par` is 1.0 at rest and nothing sets 1.25 (it is the ADR-0036 initial
value on the elements' `@export`, overwritten on the first PAR notify). So dec. 9's width
arithmetic is restated at the PAR the game runs: a card measures **32** display px wide, an
eleven-card round-robin spans `11*32 + 10*3 = 382` of the ~373 px this frustum gives and does
not fit, and eight spans `8*32 + 7*3 = 277` and does. **Dec. 9's cap of 8 survives its own
re-measurement** — the "about 353 at PAR 1.25" figure it quoted did not.
