# Battle mode and handback

The battlefield is a **mode**: something the game enters, holds four claims
during, and leaves. [Command mode](13-command-mode.md) names the *frozen* half of
what happens inside it; this cluster names the **edges** — entering, leaving, and
who is allowed to act while you are in there.

The vocabulary exists because four player-visible bugs (2026-09-08, Orbonne) were
one missing edge: the mode is entered and never left.

**Battle mode**:
The state entered when a battle goes live and left when it ends. It is a `Focus`
state (ADR-0177) — pushed on entry, popped on exit — and it carries three claims
that are not input: the tile cursor's existence, `PlayerCamera.camera_mode`, and
every combat unit's [clock owner](19-animation-playback.md).
_Avoid_: "the battle scene" (both hosts are scenes; the mode is a state on them),
"combat" (that is the sim ticking — a mode you are in with `combat_active = false`
is still battle mode).

**Handback**:
The edge that leaves battle mode: pop the focus state, free the cursor and the
map-hosted Formation screen, return the camera, and flip surviving units'
clocks back to `SCENARIO`. Named as one thing because every one of the four
reports was a different claim taken at `_go_live` and not returned.
_Avoid_: "teardown" (that frees the world; a handback runs on a world that
*survives* — the victory beat plays on the live battlefield), "cleanup".

**Commandable**:
A property of a **unit**: does it take your orders at all. Set from the ENTD slot's
`control` flag for a predetermined cast, and by roster deployment for a roster-fed
one — two writers, one fact. Distinct from
[Steerable](32-formation-screen-hosting.md), which asks whether *this* selection may
be edited *right now* and takes commandability as one of its two terms.
_Avoid_: deriving it from `_deployed_owned` (that is *provenance* — how the unit got
here, not whose it is; it reads empty on every predetermined battle, which is what
made Orbonne unplayable). "Controllable" is the ENTD's spelling of the flag and is
kept only when quoting it.

**Identity stamp**:
The `character` / `character_slug` metas a live battlefield unit carries — the one link
from a body on the field back to the catalogue Character it *is*. Written at the **bind**
seam (`UnitSpawn.bind_for_combat`), not the build seam, because the predetermined
population never passes through `UnitSpawn.build`: the scenario player mints those bodies
itself and the navigator only ever binds them. An unstamped unit resolves to null, and on
the map host a null is an empty tile — no vitals, no nameplate, and Tab refusing to open
the screen.
_Avoid_: "the slug" for the pair (the slug is the DURABLE half — what survives a save; the
reference is the one that resolves for a unit no catalogue holds), and stamping below a
progression guard: a Character that cannot fight is still a Character the screen has to
name.

**Guest**:
A unit on the player's side that is **not steerable** — Delita at Gariland.
_Avoid_: using it for "came from the ENTD rather than the roster". Orbonne's
Ramza, Delita and Algus are all ENTD-sourced and none of them is a guest; that
conflation is what made the one predetermined battle in the game unplayable.

**Tactical stop**:
Space, during a running battle: the sim halts, everything else stays live — the
cursor walks, the camera pans, ○ opens a unit's screen. Stop and look.
_Avoid_: calling it a pause. A [Pause](13-command-mode.md) is Esc, and on the
gambit host it raises a modal screen; the two are different stops ended by
different keys, which is the whole reason the [stop badge](13-command-mode.md)
exists.

**Space is one rule**: it governs whether time runs. Deployment commit, turn
commit and the tactical stop are that one rule reaching three states — not three
meanings. A host that lacks a state simply cannot reach that arm of it.
_Avoid_: "Space means something different on each host."
