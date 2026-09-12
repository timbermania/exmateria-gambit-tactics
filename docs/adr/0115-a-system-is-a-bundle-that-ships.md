# A system is a bundle that ships, and the ship test is two-sided

A **system** is the unit of extraction: a bundle someone could install
independently in another game. Two tests decide membership — *"would anyone use
this without that?"*, and *"would you install this, or write it?"*

Status: accepted (2026-08-20).

## Context

[ADR-0110](0110-systems-extract-outward-into-addons.md) makes a system the unit
of work — one branch, one code review — and `CONTEXT.md` defines it as *"a body
of behaviour that could ship to another tactics RPG with its interface intact."*
Neither says how to decide what is inside one.

Deciding by feel produced a model that changed shape seven times while
[#306](https://github.com/timbermania/fft-monorepo/issues/306) was being
authored. Every correction had the same cause: a name that covered two things,
or a part filed by association rather than by whether it would ship alone.

## Decision

**1. A system is what ships.** The industry principle is REP — *the granule of
reuse is the granule of release*. If two things always release together they are
one system, however distinct they are as concepts.

**2. What fails the ship test is content, and it stays in the host.** FFT data,
ROM parsers, the wiring that makes *this* game.

**2a. What distinguishes a system from a port is package versus port, and it has
nothing to do with genre.**

- **Port** — a tiny interface whose implementation is trivial and
  assembler-specific. You *write* it: `clock`, `focus`, `lattice`.
- **System** — a small interface with substantial behaviour behind it. You
  *install* it rather than writing it. `Render` and `Debug` are both
  genre-neutral and both systems.

**3. One-way uselessness settles packaging.** *Would anyone use this without
that? If no, it is not a separate system.* Both halves need not be useless
without each other — the asymmetry alone decides. `Battle` without its
presentation is useful; the presentation without `Battle` is nothing, so they
are one system and "headless" is a **mode**, not a package.

**4. Place a system by its capability, never by its content shadow.** Every
system casts a shadow of FFT-specific data that stays in the host. `UI` sat
three drafts too high because the Formation screen depends on the character
records — but the *screens* are content and the *toolkit* is the system.

**5. An assembler is not a system either.** An **assembler** is a composition
over systems that implements the ports and wires them together. The game is one;
each authoring tool is another. This is why
[ADR-0112](0112-dead-code-is-what-the-root-set-cannot-reach.md) declares **two
root sets** — not a special case for tools, but a consequence of there being two
assemblers.

**6. A feature is not a system.** Gambits thread through three systems; so does
equipment. Asking the ship question about a feature always returns an alarming
number. The test that applies to a feature is *can you get its useful core with
one import?*

**7. Being generic does not make something a system, and being specific does not
disqualify it.** `exmateria_sound` ships as an addon *and* is FFT-specific: the
driver ships, the banks are content. What makes a system is having an interface
someone would install against.

## Considered alternatives

- **A genre ceiling — "if it would ship equally well to a platformer, it is not a
  tactics-RPG system."** Rejected as needlessly restrictive. It exiles `Render`,
  which a platformer wanting the PSX look would take whole, and `Debug`, which
  any game would want — both substantial packages you would install rather than
  write. Genre-orthogonality is at most weak evidence that something might be a
  port; it decides nothing on its own.
- **Separate by the lifetime of owned state.** The first draft's rule. Good at
  finding *parts* inside a system; wrong for packaging, because it splits things
  that always release together and keeps things that never do.
- **Separate by language boundary (DDD bounded contexts).** Rejected as an
  equation: this repo already has `CONTEXT.md` and `CONTEXT-MAP.md` with fixed
  meanings, and redefining them silently is worse than borrowing a near-fit.
- **Separate by tier (authoritative vs presentation).** Rejected: tier is about
  authority *inside* code and is orthogonal to packaging. `Battlefield` holds
  both tiers and is correct.

## Consequences

- **Eleven systems**, listed in [ADR-0117](0117-the-blueprints-ten-systems.md).
- The count is stable against the two failure modes that moved it repeatedly:
  content shadows dragging systems up the graph, and features being mistaken for
  systems.
- **A name that will not come is evidence, not a difficulty.** `Battle
  Presentation` resisted naming through four drafts because it was not a thing;
  it dissolved into `Battle`. Treat the same symptom the same way next time.
- Method note, recorded because it recurred: **a vague name is where two
  unrelated things hide.** `Screens` was a toolkit plus its screens, `Unit` a
  combatant plus a body, the map a lattice plus its dressing, `Roster` a
  catalogue plus a per-battle selection. If you cannot say what something owns in
  one clause, it owns two things.
