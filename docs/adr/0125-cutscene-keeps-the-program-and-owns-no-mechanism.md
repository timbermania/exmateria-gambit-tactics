# `Cutscene` keeps the program; every mechanism leaves through a port

`Event VM` decomposes into **`Cutscene`** — the interpreter, the decode and the
apply — and **`Deployment`**, which is `Battle`'s. Everything the VM currently
*does* leaves through ports. [ADR-0058](0058-scenario-apply-is-intent-times-world.md)
already built the seam; this finishes it and splits the one facade into one port
per system.

Status: accepted (2026-08-20).

## Context

`ScenarioVM.gd` is 4,746 lines doing two different jobs. About 900 of them run
the script — contexts, `pc`, `_vars`, waits, branches, dispatch. The rest *do the
work*: a camera director (1,142 lines), a dialogue box pool (762), a dialogue
overlay (681), weather (516), colour tint (323), map title (306), show-graphic
(277), a typewriter (238), path motion (219), dark screen (184), colour screen
(157), background (100), bg sound (94), plus unit animation advancing at 60 Hz,
dead-unit fades, shader swaps, evtchr blocks and field objects.

[ADR-0111](0111-the-research-vault-is-ballast-not-blueprint.md) measured the
symptom — 60 opcode handlers in 925 of 4,383 lines, *"the other 79% is accreted
machinery no cluster predicted."* [ADR-0117](0117-the-blueprints-ten-systems.md)
names the cause: machinery accretes in a script host **precisely when the host
has private doors**.

Three of those mechanisms already go through a shared door, and they are the
model for the rest:

| | shared with | door |
|---|---|---|
| colour | `Effects` | `ColorStack` → the `owner_id` layer overlays. `ColorStack`'s own docs name both drivers: *"Drivers (ScenarioVM, EffectTimeline) are thin: they push layers and evaluate."* |
| camera | `Effects` (cinematics) | `PlayerCamera.request_takeover` / `apply_takeover(pos, rot, ortho)` |
| unit animation clock | `Battle` | [ADR-0083](0083-a-units-animation-clock-has-exactly-one-owner.md)'s explicit owner handoff |

All three were checked **in code, not from their ADR titles** — the failure mode
#306 recorded twice. `AnimationClock.Owner {SELF, SCENARIO, COMBAT}` exists and
`ScenarioVM` genuinely reads `clock_owner`, skips COMBAT-owned units and claims
`SELF -> SCENARIO`; `ColorStack`'s own docs name both drivers; `request_takeover`
is called by `CinematicManager` and `ScenarioCameraDirector` alike. The one thing
that did *not* survive the check was the assumption that camera therefore travels
the `ScenarioWorld` seam — see the port table below. It does not.

And ADR-0058 already built the general form: `ScenarioDecode` turns operands into
a pure **intent**; `ScenarioApply` turns an intent into world mutation **only by
calling verbs on `ScenarioWorld`**; `FakeScenarioWorld` records the verbs so an
apply is testable without booting a scene. Two implementations exist, so this is
a real seam and not a hypothetical one. `ScenarioWorld` describes itself as *"a
THIN verb surface grown family-by-family as opcodes migrate off the VM."*

So the decomposition is not a new design. It is finishing ADR-0058 and deciding
what the port's shape is when it is done.

## Decision

**1. `Cutscene` owns the program and nothing else** — contexts, `pc`, event
variables, waits, branches, the instruction set, decode, and apply. This is what
distinguishes it from `Effects`: an effect is a *timeline* (fixed length, no
branching, no variables); a cutscene is a *program*. A cutscene is not a long
effect.

**2. Every mechanism leaves, including the ones with one caller today.** The
usual objection — building an interface for a single caller — does not apply
here, because the second caller exists in the *game* even where it does not yet
exist in the code. A dialogue box is a battle message, a tutorial and shop text.
Weather happens in battles. If a mechanism is found that genuinely has one caller
forever, it stays; none has been found yet.

**3. `ScenarioWorld` splits into one port per system it reaches.** A single
facade covering units, map, actors, text, sound and overlays hides the crossings
inside itself, and naming the crossings is the point. One port per system makes
each one nameable with a payload, an owner and an edge
([ADR-0116](0116-a-crossing-needs-a-payload-an-owner-and-an-edge.md)):

`ScenarioWorld`'s **69 public verbs** already group cleanly, which is what makes
the split a re-projection rather than a redesign:

| port | verbs | crosses to | example |
|---|---|---|---|
| body | **21** | `Sprite Rig` / `Unit` | `place_unit_on_tile`, `set_unit_facing`, `play_unit_anim` |
| text | **13** | `UI` | `show_dialogue_box`, `swap_dialog_text`, `show_map_title` |
| colour | **13** | the layer overlays | `push_unit_tint`, `push_screen_background`, `set_map_darkness` |
| sound | **8** | `Audio` | `play_bg_sound`, `fade_music`, `switch_music_track` |
| **battle state** | **5** | **`Battle`** | `inflict_poison_critical`, `inflict_crystal`, `revive_and_normalise` |
| place | **4** | `Battlefield` | `can_slide`, `capture_unit_home`, `set_weather` |
| content | **3** | content / assets | `load_evtchr`, `play_field_object` |
| roster query | **2** | `Battle`'s roster | `resolve_unit_key`, `resolve_unit_set` — reads, not commands |

**The battle-state family is the one that must not be an ordinary port.**
`inflict_poison_critical`, `inflict_crystal`, `revive_and_normalise`,
`is_hp_restore_blocked` and `remove_unit` mutate battle state, and
[ADR-0120](0120-battle-state-has-one-write-path.md) says battle state has exactly
**one** write path. So these five do not get a private door of their own — they
reach the same write path any other caller uses, which is precisely the
blueprint's *"scripted damage is an effect-log entry with `cause = script`"*.

**Camera is not on this seam at all — zero of the 69 verbs.** `ScenarioVM` holds
`ScenarioCameraDirector`, which drives `PlayerCamera` directly and bypasses
decode/apply entirely. That is worth stating because it changes what "half-built"
means: the door exists for eight families and the camera **walks around it**. So
the camera work is not "finish the port", it is "route it through the seam in the
first place", and it is the one family where `Cutscene` and `Effects` already
contend for the same capability.

Ports are **required interfaces the assembler satisfies**, the same move ADR-0121
makes for the clock and focus ports. `Cutscene` depends on none of these systems;
it declares what it needs and the game wires it.

**4. `Deployment` is `Battle`'s.** `BattleDeployment`, `BattleConditionalSet` and
`BattleConditionalOpcode` already classify to `Battle`; the deployment-zone table
is content delivered through battle setup
([ADR-0043](0043-strategy-phase-placement-tiles-are-scenario-sourced.md)). The
prediction in `BLUEPRINT.md` holds.

**5. A `Scenario` remains a record, not a system**
([ADR-0029](0029-encounter-setup-is-a-scenario-not-an-event.md)). `Campaign`
picks a `Scenario`, which points at an event script, which `Cutscene` plays.

## Consequences

**The 79% is not deleted, it is relocated.** Dialogue, weather, map title,
show-graphic, path motion and field objects go to `UI`, `Battlefield`,
`Sprite Rig` and `Audio`. `Cutscene` converges on the interpreter plus
decode/apply.

**Subscribing does not substitute for a port.** `Cutscene` may subscribe to an
effect's `landmark` lane to time a scripted beat
([ADR-0123](0123-the-landmark-lane.md)), and to the effect log for mid-battle
triggers. Both answer *when*. Neither tells it who owns the dialogue box.

**`src/scenarios/` was already two systems, and the classifier already says so.**
`NavigatorMain`, `GameNavigator`, `NavigatorRunner`, `GameState`,
`ScenarioDirector` and `ForcedDirectorState` classify to `Campaign`;
`EventPathfinder` to `Battlefield`; `PsxNum` to `platform`; `ScenarioPlayerScene`
and `AllTemplatesSeeder` are assemblers. The folder is a storage fact, and
ADR-0121 forbids reorganising `src/` to match — the split lands as ports and
extractions, never as a move commit.

**Nothing here is extraction.** Pass 6 gates all of it, and pass 6 is gated on
[#299](https://github.com/timbermania/fft-monorepo/issues/299).
