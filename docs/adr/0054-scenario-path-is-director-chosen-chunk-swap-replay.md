# Scenario path is director-chosen chunk-swap replay, not byte concatenation

## Status

Accepted (2026-07-02); amended 2026-07-06 — the reset that reruns at each member
boundary splits into two classes, not one (see "Considered options" bullet 3 and
"Consequences").

To reach a mid-group scenario (e.g. Orbonne member 5) in the debug explorer, a
[Path](../context/10-scenario-branching.md) boots the [scenario
group](../context/10-scenario-branching.md) root **once** to load the world, then
walks members by forcing the minimal [Director state](../context/10-scenario-branching.md)
that advances the [Scenario director](../context/10-scenario-branching.md) to each
next member and swapping that member's event script onto the *same* live world
(`load_chunk_json` + `start`, units persisting). We deliberately do **not**
statically fuse the members' opcode bytes into one program.

## Considered options

- **Byte concatenation** (the obvious "it's just one long event" idea): glue the
  member chunks' opcodes into a single stream and run it. Rejected for three
  reasons: (1) members form a **branch graph**, not a line — Mandalia's
  `→17 Destroy-Corps` vs `→18 Save-Algus` are mutually-exclusive menu-choice
  timelines and `→20..23` are four different endings, so there is no single
  concatenation to build; *which* members follow is a per-branch decision only the
  director can make against state. (2) Event-script bytecode has **PC-indexed
  intra-chunk jumps/loops** (`IncrementLoop 0xFFD5`, labels — the same control flow
  click-to-rewind and the cinematic-walker fix depend on); fusing chunks shifts
  every jump target in the tail members and corrupts their control flow. (3)
  `ScenarioVM.start()` performs faithful **per-scenario execution resets**
  (event-var namespace clear, `{22}` track-toggle → 0, dialog/context state) at
  scenario boundaries that a single fused chunk would lose.

- **Director-chosen chunk-swap replay** (chosen): the director picks the next
  member per branch; the applier swaps chunks on a persistent world. Preserves the
  branch structure, keeps each member's jumps intact, and reruns the per-scenario
  *execution* resets while *carrying over* persistent scene overlays (see
  Consequences) — while still producing the "one concatenated opcode stream on one
  live world" the naive idea wanted.

## Consequences

What `start()` reruns at a member boundary splits into **two classes**, and
conflating them dropped the rain on a 4→6 walk (the applier swapped chunks and
`start()` tore down the live weather before the next member re-armed it, so the
rain visibly flickered off — which the ROM never does):

- **Per-scenario execution state resets** every member (faithful): the event-var
  namespace, `{22}` track-toggle → 0, dialog/context/gate state, and the per-unit
  cutscene reset (ADR-0064). The ROM zeroes these at each scenario init
  (`0x80144034`).
- **Persistent scene overlays carry across** the swap (also faithful): weather
  (`{3C}`), ambient BG sound (`{6B}`), dark screen (`{76}`), background gradient
  (`{2E}`). These live in **map-state the ROM does not reset at scenario init** —
  weather is var 0x23 ([ADR-0056](0056-map-state-is-one-arrangement-time-weather-row-selected-by-raw-weather-index.md)),
  so an earlier member's rain must still be falling when a later member loads.
  Mechanized as `ScenarioVM.start(fresh)`: `fresh=true` (standalone boot / replay /
  rewind, the default) tears the overlays down; the applier passes `fresh=false` on
  every member so they persist.

The **event-script-local** variables (`ScenarioVM._vars`, e.g. the var-87 frame
counter) reset per member, which is faithful — they are scenario-scoped. The
story-flow latches the director reads (`509`, `127/128`, `125/126/150`) are a
**separate namespace** supplied by the forced Director state, so they persist
across the swap as intended. Combat between members is **skipped** (the explorer
forces the guard's state rather than fighting); faithful mid-battle auto-firing off
live combat is a deferred RE task, not part of the path. A path stays **within one
scenario group** — inter-group `exit` (`GoToNextScenario` / `GoToWorldMap`) routing
is a separate, later concern.
