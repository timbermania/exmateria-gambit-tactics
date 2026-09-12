# Contested resources are capabilities, not flags

Where exactly one holder may have a thing, hand out an **unforgeable handle**
rather than guarding it with a flag. A flag *prevents* the bad state when you
remember to set it; a capability makes the bad state **unrepresentable**.

Status: accepted (2026-08-20).

## Context

[ADR-0083](0083-a-units-animation-clock-has-exactly-one-owner.md) reached this
once, for one resource, at the cost of two separately-patched bugs. Its
`battle_frozen` boolean was a global toggle standing in for per-unit ownership;
it was correct only because two registries happened to overlap totally, and it
could not express *"this NPC is a non-combatant, keep it breathing during live
combat."*

The blueprint found the same shape four more times, which is what promotes it
from one ADR's fix to a rule.

## Decision

**1. Four contested resources, one shape.**

| Claim | Holder | Handoff edge |
|---|---|---|
| **the pump** — advance one clocked thing | whichever host holds the handle | the mint; re-minting revokes |
| **the camera** — the right to frame | one claimant, with priority | claim / release |
| **focus** — the right to receive input | one holder **per channel** | grant / return |
| **the deployment cell** — the right to be *assigned* a destination | one combatant | claim / (never released) |
| **standing** — occupying a cell *right now* | one combatant | **derived from position; no handoff** |

> **Amended 2026-08-25 by [ADR-0166](0166-occupancy-is-battles-in-five-spellings-and-battlefields-sixth-is-inert.md)
> dec. 5 ([#554](https://github.com/timbermania/fft-monorepo/issues/554)) — the fourth row was
> ONE row and the code has TWO claims, so the table is five rows for four resources.**
>
> The original row read *"the cell — the right to stand somewhere | one combatant | move, deploy,
> removal"*, merging deployment and movement. Measured at `7e35dc423` they are two claims with two
> arbiters that never speak: `PlacementTileSet.claim_tile` decides **which unit is assigned which
> destination** (and `claimed_tiles` is never cleared and never read after `Phase.COMPLETE`), while
> the GPU mover's `is_tile_occupied()` decides **whether a step is legal right now**, derived from
> `U_POS_X` / `U_POS_Z` every call. They are not sequential — `_run_march_sequence` drives the
> mover, so both are live during the march.
>
> 🔴 **Neither is built as a capability, and dec. 2 is not owed on either — for opposite reasons.**
> The deployment claim already *is* claim-and-refuse at one choke point: `claim_tile` returns
> `false` if the cell is taken, and both callers gate on it. Standing is **derived, not stored** —
> occupancy is a function of positions held by the one authority that owns them, which is a
> stronger guarantee than a handle, not a weaker one.
>
> ⚠️ **This is the one place this ADR is bent rather than applied.** *"A membership test"* is a
> rejected alternative below, on the grounds that ownership then *"lives in a test one system must
> reach into another to perform, re-answered every frame instead of settled at the handoff."*
> Standing **is** a membership test, and the objection does not land on it: the scan reaches into
> nothing — it reads the unit buffer the same shader invocation already owns — and there is no
> handoff to settle it at, because position *is* the state. A CPU-side claim would need a per-tick
> GPU readback to stay true, i.e. a second authority for state the simulator already holds.
>
> What was actually broken was a **third** spelling in a third system: `Tile.reserved_by`, in
> `Battlefield`, written once at deployment and never released, read by no decision, guarding
> nothing. ADR-0166 dec. 2 deletes it.


**2. Holding the handle *is* the authority.** There is no separate permission to
check. You cannot double-pump because you cannot obtain two handles for one
thing — ADR-0083's stated aspiration, *"structurally impossible, not toggled off
but expressed away"*, carried further than it could go in place.

**3. The thing keeps a derived, read-only back-reference to its holder**, for
inspection only. This is ADR-0083's own move, by which `tick_based` collapsed
into a derived predicate rather than leaving two fields encoding one axis.

**4. `Clock` owns the rate and the mechanism; the host owns the claim.** The
generic *how* — accumulate, cross a threshold, emit — is the clock's. The *who*
is a handle. That is policy/mechanism separation, and it is what lets `Clock`
stay free of any knowledge of `SCENARIO` or `COMBAT`.

**5. Focus is a selector switch, not a router, a mask, or an on/off.** A router
keeps a table and inspects each frame — logic inside the port, which is the
**ledger** ADR-0084 warns against. A mask can have two bits set, and two
consumers hearing one press *is the bug*. Focus is a railway point: the train
goes where it is set, and the point never inspects the train.

**6. Channels are the mask; focus is the switch inside each lane.** `game` and
`debug` are genuinely simultaneous — which is how F3 opens the overlay while a
modal is up — with exactly one holder each.

## Considered alternatives

- **A global freeze flag** (`battle_frozen`). Rejected by ADR-0083 for a case it
  could not express, and again here: it is discipline, not structure.
- **A membership test** — have one host skip anything present in another's live
  set. Rejected: ownership lives in a test one system must reach into another to
  perform, re-answered every frame instead of settled at the handoff.
- **One central authority owning all the units.** ADR-0083 set this aside for
  blast radius; the better reason is that such an authority must enumerate its
  hosts, dragging battle concepts into what should be generic. A handle is
  opaque, so nothing is enumerated.
- **A permission bitmask for input.** Rejected: it makes the two-consumer state
  representable again.

## Consequences

- The invariant generalises past combat bodies: **a clocked thing has exactly one
  pump** now covers effect timelines, the scenario tick and UI animation.
- `Clock` can enforce it **at the mint**, which upgrades it from a discipline
  every system obeys to a guarantee.
- **Focus is a discipline, not a guarantee**, and this is the honest weakness:
  one system polling the device directly breaks the invariant for everyone,
  silently. That is exactly the platform-tier case in `CONTEXT.md` — *"violations
  do not surface as test failures"* — so **the focus ADR carries a mandatory code
  anchor**.
- Vocabulary: **the pump** is already the repo's word end to end (*"which host
  pumps it"*, *"double-pump"*, *"the VM pump"*), so goal #2's translation table
  for it is empty.
- The through-line, worth stating because it recurred five times: **every model
  that permits the bad state — flag, toggle, ledger, mask — relies on discipline
  to avoid it. Ownership, capability and switch make it unrepresentable.**
