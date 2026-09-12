# Gambit battle is a seek into the navigator, not a second combat host

`GambitBattle` boots a battle from one integer and skips the story around it. Three
things were wrong with the battle it produced: the camera opened on the corner of the
map, every unit stood frozen on IDLE frame 0 through the whole deployment, and the
authored cast faced the wrong way. The reported diagnosis was that gambit skips the
event script and needs to run it.

That is right about the camera and about the *shape* of the mistake — we treated a map
as usable without the event context that puts it in context — and it is wrong about the
mechanism for the other two. This ADR records what each defect actually is, and the
architectural answer that removes all three at once.

## What the three defects are

**The camera is an event-script defect.** `GambitBattle` sets no pose at all: its only
camera write is `cursor_rig.seed_from_map(map, Vector2i(0, 0))`, and
`CursorController.seed_from_map` hard-cuts the camera to that cell. Every battle's
entry framing is authored — it is the **terminal `{19}`** of the group's
[opener](../context/08-scenario.md). Gariland's (scn 10, PC 35) is
`Angle 302 / Map Rotation 5632 / Zoom 4096`, where `302` and `4096` are the ROM's
`camera_init` constants (`FUN_8008e468`) and the rotation is the map-dependent yaw.
All 72 battle groups have an opener; random encounters use the shared **Random Battle
Template** (scenarios 400/401/402), whose 401 carries five `{19}`s including the same
terminal settle. There is no battle anywhere that frames itself.

**The freeze is a clock defect, and `{80}` March does not fix it.** `ScenarioCast`
stamps every spawned unit `clock_owner = COMBAT`, which makes `Unit._process` no-op its
delta pump; `TurnDirector.open_deployment()` sets `combat_active = false`; and no GPU
simulator exists until commit. So during deployment **nothing ticks**. A `{80}` supplies
a pose, not a tick — running the opener would leave the units exactly as frozen.
`NavigatorMain` solves this a different way, and the way is the point: deployed units go
on `ScenarioVM.idle_only_units` and ride the VM's one 60 Hz tick (ADR-0065).

**The facing is a data defect no opcode can reach.** `ScenarioCast` hardcodes spawn
facing by team — `SOUTH` for enemies, `NORTH` for the player — and never reads the ENTD
slot's `facing_raw`, which we parse, commit and already lift correctly elsewhere
(`ScenarioPlayerScene.initial_spawn_facing_12bit`, the ROM's `angle = Facing << 10` at
`0x80087c1c`). For the player's squad it invents `_face_toward_enemies`, a nearest-enemy
heuristic, on top of a `unit_facing` nibble the deployment-zone table authored and
`DeploymentZoneDatabase` already serves. **The Gariland opener contains zero facing
instructions** — no `{2D}`, `{53}`, `{2C}`, `{69}` or `{8C}` — so running it would have
corrected the facing of nobody, while appearing to.

Two of these would have survived the fix that was proposed for them. That is the whole
reason this ADR exists.

## Decision

**"Play one battle" becomes a seek into `NavigatorMain`, and `GambitBattle` stops being
a `CombatHost`.**

The navigator is the spine — it *is* the game — and gambit's stated purpose is to play
the battle part of it in isolation. A thing that is a subset should be a **view** of the
superset, not a copy. Every one of the three defects is already solved in the spine, and
solved once:

| defect | the spine's answer |
|---|---|
| framing | `_settle_world_via_opener` fast-forwards the opener at 30× on a direct seek, then `settle_screen_effects()` |
| freeze | `_register_deployed_idle_pump` → `ScenarioVM.idle_only_units`, one 60 Hz tick (ADR-0065); `_hand_off_clocks_to_combat` at go-live (ADR-0083) |
| facing | `_deploy_owned_units` lifts the zone's `unit_facing` nibble; ENTD units spawn through `_spawn_unit_at(..., facing_raw)` |

So delegation **deletes** `ScenarioCast`'s hardcoded facing and `_face_toward_enemies`
rather than fixing them, and it inherits an invariant a second host would have had to
rediscover: the squad must be on the field **before the opener's first instruction**,
because 28 of 72 openers `Erase`/`Draw` the player's units and then `{1F}` Focus on
them. `NavigatorMain.play_beat` carries the scar of getting that ordering wrong — the
camera panned to empty terrain with Ramza's dialogue over it.

`NavigatorRunner.start_at(index)` is the seam; it already exists as the debug
"seek here" entry point, and the executor self-boots whatever world the seeked action
needs. Gambit seeks to the group's `pre_battle` beat by default (the opener
fast-forwards, ~1 s) with a flag to seek to `opener` and watch it play. Battle
addressing stays scenario-id-shaped: a battle group's root **is** its
[setup record](../context/08-scenario.md)'s id, so `--scenario=9` keeps meaning what it
already means.

The interactive deployment picker is **promoted into the spine** and replaces its
`DeploymentPlan.assign` call, because `DeploymentAssignment.auto_fill()` already
delegates to that same function — the spine does not lose auto-deploy, it gains a picker
with auto-deploy inside it, and `_autoplay_gate(SKIP_PRE_BATTLE_SLUG)` becomes
`auto_fill() + commit`.

## Considered and rejected

**Patch `GambitBattle` in place** — give it its own `ScenarioVM`, boot the group root,
fast-forward the opener, fix the clock and the facing. Rejected because it is a second
implementation of battle entry, and the three invariants above are precisely the kind
that drift apart in two copies. This ADR is the fourth time a placement/facing/framing
bug has been fixed in this repo; twice was in code that already existed correctly
elsewhere.

**Extract a shared battle-entry component** both hosts call. Rejected because the
invariants are entangled with the runner's action list — the "component" converges on
being most of `NavigatorMain`, at which point (b) is the honest version of it.

**Engine defaults instead of the opener** — make a scriptless battle correct on its own
and treat the opener as an override. Rejected on evidence: there is no scriptless
battle. The apparent control — 170 byte-identical 3-instruction event stubs — turned out
to be **setup records**, 155 of which are immediately followed by their group's non-stub
opener. The stub is half of a battle, not a battle.

**Implement `{1B} Map Light`.** It is `verified: false`, un-RE'd, and appears twice in
all 72 openers (both in group 291's, scn 292). It gets a documented `_skip` instead. The
last unverified lighting opcode we implemented on inference, `{1A}` Map Darkness, turned
out to be a phantom that changed zero rendered pixels and had to be removed (ADR-0051) —
and the overexposed-map bug it is often confused with was ADR-0056, a **map-data export**
defect, not a missing instruction.

## Consequences

- The fast-forward becomes load-bearing for 72 openers sized 24–679 instructions
  (mean 144), against `ScenarioPathApplier._MAX_FF_FRAMES = 2100` at `_FF_SPEED = 30`.
  That cap had never been exercised at this range, and a truncated fast-forward fails
  **silently** into exactly the bad framing this ADR is about. **Swept, and the cap is
  not close**: 72 of 72 reach `Event End`, worst case 169 frames (root 291, scn 292, 564
  instructions) — 8% of the budget. The longest opener is not the slowest: root 166's
  679-instruction scn 167 settles in 145, because the cost is the stream's *blocking*
  time, not its length. Tool + register: `tools/sweep_opener_fast_forward.py`,
  `docs/OPENER-FAST-FORWARD-SWEEP.tsv`. Two things came out of the sweep and stayed:
  the seek now reports its outcome and **fails loud** rather than silently on a
  fast-forward that did not reach `Event End`; and `ScenarioVM.is_main_context_finished()`
  answers the question the normal-speed walk asks, because the first take read 71/72 and
  the one failure was the instrument — scn 47 ends `{E3} Event End 2` at pc 131 with a
  `{DB} Event End` at 132 that is therefore never dispatched, so a fast-play watching only
  the PC sat out its whole stall budget on a scenario that had already finished.
- The host-vs-host differential test **expires on success**: once gambit *is* a seek,
  it compares the navigator to itself. It is written to be deleted with `GambitBattle`,
  and the deletion is a line in the retirement ticket rather than a thing to remember.
  The permanent guard is a launcher test asserting the authored values.
- `parse_placement.py`'s open question — `zone_facing` rotates the zone's tiles but is
  not folded into `unit_facing`, validated against one zone, *"revisit with a second
  live oracle if a future battle deploys facing wrong"* — gets its second oracle for
  free: the launcher test asserts Gariland's deployed facing against the raw nibble.
- `GambitBattle` is **not** deleted in the same change that replaces it. Its seven tests
  are the deployment picker's only behavioural coverage, and retiring the host while
  repointing them means a red suite cannot say whether the seek or the repoint is wrong.

## Status

accepted.

⚠️ **The number was claimed by scanning all worktrees (high-water 0263) *and*
`gh pr list` for numbers claimed by unmerged branches** — ADR-0258 records four
collisions caused by scanning only the filesystem, two of them to one branch in one
afternoon. The window between claiming and pushing is still open; this is a mitigation,
not a fix.
