# Battle state has one write path, and its presentation is a projection of it

Every change to battle state — an action's result, a scripted event, a scheduled
tick — enters through **one ordered, causally attributed effect log**. The
presentation is a **projection** of that log and never a second source of truth.

Status: accepted (2026-08-20).

## Context

[ADR-0031](0031-battle-state-is-gpu-authoritative.md) makes the GPU simulator
authoritative, and the CPU side displays it by **reading state back** each tick.
Reading state tells you *results*, never *events*: you cannot distinguish "took
30" from "took 10 then 20", only that health changed.

So presentation has to **infer** events from state, and inference races. The
missing melee hit-cloud in
[ADR-0083](0083-a-units-animation-clock-has-exactly-one-owner.md)'s context is
exactly that — the animation opcode ran ahead of the damage tick, `is_hit` read
stale data, and the trap cloud never spawned.

## Decision

**1. One write path.** `Action Resolution`, `Cutscene` and `Scheduling` all reach
battle state through the effect log and nothing else. A scripted damage is an
entry with `cause = script`; a poison tick is a declaration whose agent is the
clock. **There is no privileged door**, which is the whole content of
`Cutscene`'s boundary.

**2. Entries are ordered and causally attributed.** A hit is an entry at a known
index. Reading it late means playing it late — not missing it.

**3. Presentation is a projection.** Destroy all of it, rebuild from the log, and
no outcome changes. That is not decoration: it is what **bounds the save format**,
since persistence covers the authoritative side and nothing else.

**4. Exactly one thing crosses upward from presentation** — *this log's
performance is complete*. One bit. It may delay; it may never change what is
decided.

**5. Everything is scheduled against landmarks, never against each other.**
*Impact*, *cast*, *recoil*. Body, effects, audio and camera each schedule against
a named moment, which is what stops N-squared coupling between them. A landmark
is just another `Effects` channel whose events are moments rather than
instructions.

**6. The hybrid is the recommended emission shape.** State stays the sync path,
and the simulator emits a **small set of notable events** beside it — hit landed,
unit died, spell cast. Cheapest of the three, closest to what the attack and
spell stages are already positioned to do, and it stops presentation inferring
the events it actually needs.

## Considered alternatives

- **Presentation diffs state between ticks** to derive events. Rejected: the
  current inference problem with extra steps.
- **The simulator emits a full ordered append buffer.** Not rejected, but not
  required — atomics plus another readback, and ordering *within* a tick is
  almost never what matters. Ordering *between* ticks is.
- **Presentation as a separate system consuming the log.** Rejected by
  [ADR-0115](0115-a-system-is-a-bundle-that-ships.md): nobody would use it
  without the simulation, so it is not a separate release. Keeping them together
  makes this whole question internal rather than a contract across a package
  boundary.

## Consequences

- **Undo, replay and time-travel debugging come free**; log versioning and
  upcasting come as the bill, and land on persistence.
- The recorded tension stands: an event log wants order, and a GPU simulator
  naturally produces state computed in parallel where cross-workgroup ordering is
  not free. This decision does not dissolve it — it locates it **inside**
  `Battle`, where it is an implementation choice rather than a negotiation.
- **Two randomness sources look like one**, and this is the dangerous part:
  the authoritative source must be an explicit input, the presentation source is
  ambient, and reading the ambient one from the authoritative side breaks replay
  **silently** with nothing failing at the time.
- **Forkable battle state** is required by an AI that *searches*, and is dormant
  while the AI stays declarative — a gambit slot asks *does this condition pass*,
  not *what is the best move*. The requirement wakes the day anyone wants search,
  and it is brutal to retrofit.
- **Every declaration source must be able to yield.** A source producing no legal
  declaration has to pass and end the turn — true of the player (who can always
  Wait) and of the AI, and exactly gambit rule **B6**, *"the unit MUST NOT loop
  forever on this slot."*
