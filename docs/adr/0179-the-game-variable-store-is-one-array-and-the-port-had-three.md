# The game variable store is one array, and the port had three

FFT keeps **one** game-variable array. The world map's overlay, the event-script
interpreter's `0xB0`–`0xBE` writers and the battle director's
`event_set_script_variable` all address the same 684 bytes at `0x8005771C`. The port
had split it into three disjoint objects, one of them cleared on every scenario start
— and that split, not a missing feature, is why nothing in the port could ever advance
the story counter. **The port unifies them: a `Campaign` autoload owns one
`WorldMapVariables`, `ScenarioVM` takes it by injection, and it is no longer cleared
per scenario.**

Status: accepted (2026-08-24). Closes the "nothing ever writes progress" gap on the
world-map line. Sources: `research/working_documents/WORLD_MAP_SCREEN.md` §27.4, §29.3,
§32.2 and row 104; `research/wiki_articles/event_instruction_b0_be_variable_math.md` §1.
Consumed by `src/world_map/WorldMapProgress.gd`, `src/scenarios/ScenarioVM.gd` and the
new `src/scenarios/Campaign.gd`.

⚠ **Number collision, resolved.** `0155` and `0158` were each allocated twice across
live branches. Both of this line's ADRs were renumbered on 2026-08-26 — see the
*Renumbered* note below and in
`0178-the-town-picture-gets-an-address-of-its-own.md`. The other claimants
(`0155-where-the-source-that-left-the-walk-went-is-declared-once.md`,
`0158-the-suite-runs-in-parallel-and-the-lane-is-a-measurement.md`) were already on
`import-godot-game` and keep their numbers.

↺ **Renumbered.** Filed as `ADR-0158`; renamed to `0179` on 2026-08-26 because `0158`
was already taken on `import-godot-game` by `0158-the-suite-runs-in-parallel-and-the-lane-is-a-measurement.md`.
Commit messages up to `01f49f87d` cite the old number.

## Context

The world-map research closed how ○ hands off — a node's script emits
`(scenario_id, transition_mode)`, `var[0x27]` takes the id, the screen leaves. What it
never located, across 7,728 lines, was a writer for **`var[110]`**, the story counter
every one of the 46 spine emits is gated on. Every state the research examined was
either the game's own opening (`var[110] == 1`) or a Lua poke, both labelled as such.

The port had no writer either: `WorldMapProgress.set_story_counter` had zero call sites
outside its own fixtures. So the chain, once built, would loop forever on hop one —
Gariland → Balbanes's Death → back to the map, still at `var[110] == 1`, still offering
the same script.

**The writer is data, not code.** No MIPS anywhere loads the literal `110` into a call
argument (scanned: `BATTLE.BIN`, `WORLD.BIN`, `WLDCORE.BIN`, `SCUS_942.21` and all
fifteen `EVENT/*.OUT`). `TEST.EVT` holds **129 adjacent `ZERO(110); ADD(110, k)`
pairs** — FFT's event compiler has no single SET opcode, so it clears then adds. The
`k` values are `1`–`53` plus a twelvefold `99`; every value in `1..52` is present and
nothing falls in `54..98`. That is §29.4's story spine, written back by the scenarios
themselves.

Two of them close the first loop, and slot number equals scenario id:

| slot | scenario | writes | exit |
|---|---|---|---|
| 12 | *Gariland Fight (Ramza talking about honest lives)* | `var[110] = 1` | `GoToWorldMap` |
| 14 | *Balbanes's Death*, member of group root 13 | `var[110] = 2` | `GoToWorldMap` |

`var[110] = 2` is exactly what node 24 Mandalia Plains' `enter [15, 1]` is gated on.

**And it is already in our own decoded assets.** `assets/scenarios/chunks/
scenario_014_chunk.json`, offsets 1385–1436:

```
Zero var[110];  Add var[110], 2      the story counter
Zero var[49];   Add var[49], 6
Zero var[445];  Add var[445], 1      BIT region (128..863)
Zero var[963];  Add var[963], 1      NIBBLE region (864..1023)
Zero var[964];  Add var[964], 1
Zero var[965];  Add var[965], 1
Zero var[1008]; Add var[1008], 1
```

`ScenarioVM._op_var_zero` / `_op_var_add` already execute these. The mechanism was
never missing. The **wire** was.

### One array, triple-sourced

- §27.4 / line 421: the world-map store is `*(0x80153280)`, whose value in every
  capture is **`0x8005771C`** — SCUS's own BSS, *below* `0x80067000`, so it survives
  the `BATTLE.BIN` overlay load. That placement is deliberate and it is the whole
  reason a campaign can span a battle.
- `event_instruction_b0_be_variable_math.md` §1: the event variable file's base
  pointer is `*0x80165F9C`, live value **`0x8005771C`**.
- Row 104: `var[0x27]`'s home is `*(0x80165F9C) + 0x27*4` = `0x800577B8`
  = `0x8005771C + 0x9C`. ✓

### What the port had instead

| object | region coverage | lifetime |
|---|---|---|
| `WorldMapVariables` | all three (words / bits / nibbles) | persisted to `user://world_progress.json` |
| `ScenarioVM._vars` | **words `0..127` only** | `clear()`ed on every `start()` and `set_rewind_target()` |
| `ScenarioDirectorState` | read-only query interface | n/a — *"the director never writes game state"* |

So scenario 14's writes to `445`, `963`–`965` and `1008` are silently dropped today,
and its write to `110` evaporates at the next `start()`.

## Decision

1. **`Campaign` (autoload, `src/scenarios/`) owns one `WorldMapVariables`** plus its
   load/save. It lands in the directory `classify_blueprint.py` already buckets
   `Campaign`, so it needs no new classifier rule. `NavigatorMain.run_world_map` stops
   constructing a `WorldMapProgress` at the mount and hands Campaign's.
2. **`ScenarioVM` takes the store by injection.** An unowned or unit-test VM constructs
   its own, so its behaviour is unchanged; the navigator injects Campaign's. This also
   gives the VM the bit and nibble regions it never modelled.
3. **The store is not cleared on `start()` or `set_rewind_target()`.** The ROM never
   clears it, and `Zero(v); Add(v, k)` *is* the reset — the idiom exists precisely
   because there is no SET opcode and no per-scene wipe.

## Considered alternatives

- **Keep two stores, mirror a named set at group exit.** Rejected: the mirror list is
  the translation table `WorldMapVariables`' own docstring says not to build, and it
  cannot carry the bit/nibble writes `ScenarioVM._vars` has no representation for.
- **Decode the group's chunks offline and let Campaign apply the writes itself.**
  Rejected: re-implements the opcode semantics a second time and diverges the moment a
  script's writes sit behind a condition.
- **Invent a port-side progression rule** (e.g. "a group exiting `GoToWorldMap` bumps
  the counter"). Rejected once the real writer was located — and it would have been
  wrong: the counter jumps (`13 → 14 → 29 → 30`), it does not increment.

## Consequences

- **Replay determinism changes shape.** The old `_vars.clear()` was justified as
  letting a rewind re-derive `var 87`'s frame counter. Measured exposure across all 250
  decoded chunks: **85 of 1,411** variable reads/RMWs are not preceded by a `Zero` of
  the same id in the same chunk, in 10 chunks, on four ids — and three of the four
  argue *for* persistence:

  | var | uses | zeroed? | reading |
  |---|---|---|---|
  | 86 | 67× `Wait Value`, chunks 411–425 | never, anywhere | nothing in the port writes it either, so it reads 0 regardless |
  | 41 | `Zero`×22, `Add`×44, `OR`×25, `AND`×12 | yes — in **sibling members** | the clear-on-start *breaks* that cross-member idiom |
  | 101 | `Add(101, 1)`, chunk 093 | never | Deep Dungeon depth (§32.5) — an accumulator that must persist |
  | 44 | one `Subtract`, chunk 461 | never | isolated |

- **A save file now carries scenario writes.** `WorldMapProgress.save()` — never called
  in production before — becomes load-bearing.
- **`ScenarioDirectorState` is untouched.** It stays a read-only query interface; the
  one BattleConditional opcode that writes (`0x0019 Run Scenario N`) targets
  `var[0x27]`, which the unified store now holds.
