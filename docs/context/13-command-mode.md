# Command mode

The player-facing **battle state in which the simulation is frozen but the
field is fully navigable** — `combat_active = false`, the [Tile cursor](29-battlefield-camera.md)
is live, and the camera is free (`PlayerCamera` [Cursor mode](29-battlefield-camera.md)).
It is the umbrella term for two situations that are *identical* from the
player's seat and, per the freeze model below, the *literal same flag state* in
code. Introduced 2026-08-06; realized on the roster-fed `NavigatorMain` battle
path first.

**Command mode** (frozen sim + live cursor + free camera) has two **instances**:

- **Deployment**: command mode *before combat has ever started*. Entered
  automatically when a battle is handed off from the navigator — units are
  already snapped onto their [deployment-zone](12-strategy-phase.md) tiles and stand
  **idle** (idle gambits — nothing walks anywhere). The player roams the field, then
  commits to the fight.
- **Paused**: command mode *entered mid-battle*, freezing a fight already in
  progress so the player can look around, then resume.

**Live** is the complement — `combat_active = true`, the GPU sim ticking. The
tile cursor stays **visible and movable in all three** (Deployment / Paused /
Live); the *only* thing that changes across them is whether the sim ticks. (A
cinematic-spell [Takeover](29-battlefield-camera.md) still hides the dagger and
returns to it — orthogonal, untouched.)

**Toggle grammar** — one key per *kind* of transition (split from the single Tab
toggle by ADR-0137 Amendment 2, 2026-08-21):
- **Space** (`battle_start`) = Deployment → Live ("start battle"). **One-way**:
  starting a fight is just *leaving Deployment*, and once left there is nothing
  to leave, so a second press is an accepted no-op. It also arms the heartbeat
  and dumps unit state — one-time work a resume must not redo.
- **ESC** (`battle_pause`) = Live ⇄ Paused, the **repeatable** half. The bare
  flag flip, no arming.
- **Enter** (`cursor_confirm`) = **ACT** on the unit under the cursor.
- **Tab** (`unit_inspect`) = **INSPECT** it. Never gated by anything.

**Button model** (ADR-0137 Amendment 4, 2026-08-21) — the four PSX face buttons
keep their documented meanings (Teiyu Goto: ○/✕ are *correct*/*wrong*, △ is a
head — *viewpoint*, □ is a sheet of paper — *document*), and every key and pad
button carries **exactly one intent** (Amendments 4 and 6):

| PSX | intent | key | pad |
|---|---|---|---|
| ○ | confirm | Enter / KP Enter | 1 |
| ✕ | back | **Backspace** | 0 |
| △ | **go into the unit's menus** | Tab | 3 |
| □ | — *(unused)* | — | 2 |
| SELECT | pause | Esc | 4 |
| START | start battle | Space | 6 |

`ui_accept` and `ui_cancel` used to be Godot **defaults**, which is why they
were never audited: Space was accept *and* `battle_start`, Esc was cancel *and*
`battle_pause`, and Godot's pad defaults are Xbox-shaped (0 = accept), the exact
inverse of ○=yes. Both are now defined explicitly. **Esc is pause only** —
Backspace backs out of a screen.

△/Tab opens the unit's screen **with its menu already up** (Amendment 6) — it
means *"show me this unit's menus"*, so it lands on them; ✕ shuts the menu
leaving the Status readable, and △ reopens it. That is why □ has no job.

**✕ pops exactly one level** (Amendment 7, 2026-08-21) — on the map host, backing
out of Equip/Ability lands on the **Status screen with its menu up**, not out on
the battlefield. ADR-0084 RE25's *"a sub-screen back-out is a FULL unwind to the
roster"* still governs the [roster host](32-formation-screen-hosting.md), which has a
roster to unwind to; the map host's bottom is the battlefield, so unwinding there
skipped a floor. Change Job is exempt on both — a full-screen takeover, not a
detour. From Equip the full ladder out is `✕` (Status+menu) → `✕` (menu shuts) →
`✕` (battlefield), and the camera keeps its zoom until that last press: the
takeover belongs to the **unit**, taken once per visit and released once.
**WASD, the arrows and the d-pad all drive `ui_*`**, so direction means
direction on the map cursor, on a menu row and on the Learn tabs alike.

Three bindings are SHARED, each one intent at two depths: ○
(`ui_accept`/`cursor_confirm`), △ (`unit_inspect`/`formation_start_menu`), and
the directions (`ui_*`/`camera_*` — the latter misnamed, it moves the CURSOR).
None can contend, because a screen that is up owns the whole pad and marks
events handled before `TileCursor` sees them. Taking ○ as the example:
`ui_accept` and `cursor_confirm` are both ○. They are two *actions* for gating reasons (Amendment 2), not two
buttons, and they never contend because the cursor is frozen while a screen is
up. `FormationMapHostTest` mechanizes the whole table — it is the only thing
that catches a new action squatting on a key that already means something, which
is how the menu nearly shipped on Q (already `rotate_camera_cw`).

The split exists because the two are not the same kind of thing — one is a
one-way phase exit, the other a toggle — and fusing them onto Tab was what left
the map cursor with no key and made this host disagree with `GPUArena` (which
used Space). The one-flag *state* model is untouched; only the key split.
`command_mode_toggle` no longer exists. Godot's `ui_focus_next` / `ui_focus_prev`
are overridden to **empty** so Tab is actually reachable — the engine binds
focus traversal to Tab by default and the viewport GUI eats it before
`_unhandled_input`.

**Freeze model** — Deployment and Paused are the **same `combat_active = false`
state on a live `CombatLoop`**, not two mechanisms. The `CombatLoop` is built
**up front** at Deployment entry with `combat_active = false` (exactly as the
[strategy phase](12-strategy-phase.md) already ticks the simulator with combat intent
removed — ADR-0042); the Tab toggle merely flips `combat_active` and swaps
idle↔combat gambits on go-live. This is what lets "one command mode" be true in
code and not just in the UX.

**Scope at introduction** is **read-only roam**: cursor + camera + the active-
tile highlight (`CursorController` paints `CURSOR_ACTIVE` for free). No unit
selection, no repositioning, no info panels — those are the deferred "config"
work the cursor's signals will later feed. The cursor seeds on the **leader**
(first deployed owned unit) so the handoff never lands on world-origin.

_Avoid_: conflating **Command mode** (a *battle/combat-phase* state — is the sim
frozen?) with **[Cursor mode](29-battlefield-camera.md)** (a `PlayerCamera.CameraMode`
— is the camera cursor-driven or in takeover?); they are orthogonal axes that
merely coincide during command mode. Adding a separate "start battle" key (it is
just *leaving Deployment* — reuse the Tab toggle). Overloading **Enter** onto the
phase toggle (reserved for selection — the whole reason Tab carries the toggle).
Modelling Deployment's freeze as "no CombatLoop yet" (the loop exists up front —
see the freeze model). Calling either instance the
"[strategy phase](12-strategy-phase.md)" — that names the *placement* both battle
hosts do before `start_battle`, which this navigator path has already done for you.
