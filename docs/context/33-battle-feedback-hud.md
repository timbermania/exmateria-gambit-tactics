# Battle feedback HUD

The in-battle layer that **observes** battle state and shows it to the player —
as opposed to the [Window](31-combat-ui-windows.md) cluster, which is the UI the
player *operates*. Named apart because the two have opposite data direction: a
Window takes input and drives the game; the feedback HUD issues nothing and only
reflects what the GPU already decided. See ADR-0063 and
`docs/battle-hud-faithful-spec.md`.

**Feedback HUD**:
The set of in-battle elements that render GPU-authored combat state for the
player to read — over-unit **damage / heal / miss numbers**, over-unit **status
& charge/CT icons**, and the **field-inspect unit-info window** (point at a unit
on the battlefield → its info appears). It is an **apply-only consumer** of the
[combat loop](02-combat-buffer-layout.md)'s per-event signals (`hp_changed`,
`stat_changed`, the snapshot's status flags) — the UI sibling of a
[Combat-visual](02-combat-buffer-layout.md): it never writes battle state ([Battle-state
authority](02-combat-buffer-layout.md)) and reads the unit's *own* `UnitStats`, never
FFT's ROM struct. Reproduces FFT's feedback **visuals** (the `RANGETILE` digit /
status-icon sprites) while remapping nothing about its meaning — the
[take-the-visuals-remap-the-meaning](01-asset-extraction.md) rule. Distinct
from the **command HUD** (FFT's action menu + target-selection cursor), which
this game does **not** have today: issuing an order is a future *command gambit*
(a one-shot gambit action like move-to-tile), so there is no player-driven
command surface to mirror — only feedback.

**Presentation splits by placement** (ADR-0063), and is the only thing that
varies between feedback elements: *over-unit* elements (damage/heal/miss numbers,
status/charge bubbles) are **unit-anchored 3D billboards** with
[CUSTOM0 GTE depth](25-rendering-depth.md), enrolled in the `combat_visuals` group so
they ride the ADR-0037 freeze; *screen-space* elements (the field-inspect
**unit-info window**, any menu-like panel) are **ordinary screen-space `ui3`
HUD** at a fixed position, drawn like the rest of `ui3` — not billboards. The
observation-only nature is shared; the render mode is chosen per element.
_Avoid_: drawing an *over-unit* element as a 2D screen-space overlay (a
CanvasLayer number sorts wrong against the battlefield and sits outside the
ADR-0037 freeze); forcing a *screen-space* element (the info window, a panel)
into a unit-anchored billboard (it belongs in the `ui3` HUD, not floating on a
unit); reading FFT's `BattleUnitData` at runtime (the data is the unit's own
`UnitStats`; only the *layout/visuals* are faithful); a feedback element that
writes battle state or feeds input back to the sim (that is a Window / the future
command gambit, not feedback); calling the field-inspect window a
[modal window](31-combat-ui-windows.md) (it grabs no input and completes nothing —
it is read-only observation shown alongside the management windows).
