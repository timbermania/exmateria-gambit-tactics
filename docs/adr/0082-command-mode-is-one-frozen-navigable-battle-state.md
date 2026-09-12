# Command mode is one frozen-navigable battle state; Deployment and Pause are instances of it

## Status

accepted

## Context

Battles handed off from `NavigatorMain` dropped straight from a bare
"press Enter to start combat" breakpoint into a running fight — no way to look
at the battlefield before it started, and no way to stop and survey mid-fight.
We wanted both: a pre-battle **deployment** hold where units are placed but the
fight has not begun, and a mid-battle **pause**, each giving the player a map
cursor and a free camera.

The engine already had every piece: the `TileCursor` / `CursorController` /
`PlayerCamera` cursor-follow rig (ADRs 0041, and the "Battlefield camera"
glossary), and the `combat_active = false` freeze that halts the GPU sim and
combat visuals while leaving camera + UI alive (ADR-0037). ADR-0042 had already
established that the simulator can tick with `combat_active` false in a
non-combat phase.

## Decision

Model a single **command mode** — `combat_active = false` + live `TileCursor` +
free camera — and make **Deployment** (before the fight starts) and **Paused**
(mid-fight) two *instances* of it, not two features. From the player's seat they
are identical; in code they are the **literal same flag state**:

- The `CombatLoop` is built **up front** at Deployment entry with
  `combat_active = false` and units on **idle** gambits (placed and standing —
  the ADR-0042 deployment march is deliberately *not* invoked on this path).
  This is what makes Deployment and Paused the same state rather than two
  mechanisms ("no loop yet" vs "flag off").
- **Tab** is the sole **command-mode ⇄ Live** toggle. Deployment → Tab → Live
  ("start battle"); Live → Tab → Paused; Paused → Tab → Live ("continue
  battle"). Starting a fight is mechanically just *leaving Deployment* — there
  is no separate "start" key.
- **Enter** is reserved for a future cursor-**selection** extension; **ESC** for
  a future "abort battle → navigator". Both inert in the read-only scope.
- The tile cursor is visible and movable in **all** states (Deployment / Paused
  / Live); the only thing that changes is whether the sim ticks. Cinematic
  takeover still hides/returns the dagger, orthogonally.
- Scope at introduction is **read-only roam**: cursor + camera + active-tile
  highlight. No selection, repositioning, or info panels.

## Considered options

- **Two mechanisms, shared UX layer** — leave the `CombatLoop` lazily created on
  go-live (Deployment freeze = "loop not built yet", Pause freeze =
  `combat_active = false`). Less code up front, but "one command mode" would be
  true only in the UX, not the state, and the two paths would drift. Rejected in
  favor of unifying the flag.
- **Enter starts the battle, a separate key pauses** — the conventional
  "confirm to begin, dedicated pause toggle" split. Rejected because Enter is
  wanted for *select the unit under the cursor*; putting the phase toggle on Tab
  keeps the two off each other's key. Starting the fight is unified with
  un-pausing precisely because both are "leave command mode."

## Consequences

- A future reader sees the `CombatLoop` exist *before* the player "starts" the
  battle. That is intentional (this ADR + the "Command mode" glossary entry) —
  do not "fix" it back to lazy creation without reproducing the unified-flag
  model.
- **Command mode** (a combat-phase state: is the sim frozen?) is a different
  axis from `PlayerCamera`'s **Cursor mode** (is the camera cursor-driven or in
  takeover?). They coincide during command mode but must not be conflated.
- Deferred config work (unit selection, repositioning, info panels) has a home:
  it consumes the cursor's signals and lands on the reserved **Enter**, without
  touching the phase toggle.
- Realized on the roster-fed `NavigatorMain` path first; predetermined/ENTD
  battles can adopt command mode later unchanged — the cursor is indifferent to
  how units were placed.
