# Event-instruction dispatch keys a generated semantic enum, not the byte or the name

The event-script interpreter dispatches on a generated
**[EventInstruction](../context/09-event-script-interpreter.md)** enum whose
members (`FACE_UNIT_2`, `BG_SOUND`, …) are slugged from the owned catalog's
display names (disambiguated where those collide — see the slug sub-decision
below) and whose underlying int value **is the opcode byte**. The enum is
generated at the parser boundary (`gen_opcode_catalog.py`, `--check`-guarded like
`activity_taxonomy.yaml`) from the owned catalog, now
`assets/scenarios/event_instructions.json`. Handlers register through
`_bind(EventInstruction.X, callable)` / `_skip(EventInstruction.X, reason)`;
[EventInstructionSet](../context/09-event-script-interpreter.md) loads the catalog
descriptors and mints a typed
[EventInstructionArgs](../context/09-event-script-interpreter.md) reader that
replaces `_params_dict`. A coverage test asserts every `verified:true` instruction
is bound-or-skipped. The word **opcode** is narrowed to mean the raw dispatch byte
alone; one unit of the event script is an **event instruction**.

## Decision

Numbered 2026-08-28 so `ADR-0059 dec. N` resolves. Items 1–4 and 8 restate the
opening paragraph; 5–7 are the three sub-decisions stated further down. No prose
was removed or reworded.

1. **Dispatch keys a generated `EventInstruction` enum**, not the byte and not
   the display name. The member is the identity; its underlying int **is the
   opcode byte**, so it matches `inst["opcode"]` for free.
2. **The enum is generated at the parser boundary** by `gen_opcode_catalog.py`,
   `--check`-guarded like `activity_taxonomy.yaml`, from the owned catalog
   `assets/scenarios/event_instructions.json`.
3. **Handlers register through `_bind(EventInstruction.X, callable)` /
   `_skip(EventInstruction.X, reason)`**, and the three terminators fold into
   enum-keyed handlers — deleting the last name-string dispatch logic.
4. **`EventInstructionSet` loads the catalog descriptors and mints a typed
   `EventInstructionArgs` reader** that replaces `_params_dict`, reading operands
   by width/type and delegating numeric conventions to `PsxNum`.
5. **Slug disambiguation (Option A).** Slug to `UPPER_SNAKE`; use a unique slug
   verbatim; on collision append the opcode hex to every sharer; render the
   `Variable` comparison family through a symbol map (`<=`→`LE` … `>`→`GT`);
   re-assert uniqueness afterwards. Every catalog entry gets a member, so the
   unnamed ones can be auto-`_skip`ped rather than halting.
6. **"Intentionally unhandled" lives in code, not the catalog JSON** — as
   `_skip(enum, reason)` beside the bindings, so the coverage check reads
   code → catalog and the JSON never edits when a handler lands.
7. **Coverage is enforced by a test (hard) plus a boot `push_warning` (soft).**
   The test is the gate; the warning reminds without refusing to boot.
8. **The word "opcode" is narrowed** to mean the raw dispatch byte alone; one
   unit of the event script is an **event instruction**.

## Context (before this decision)

Dispatch was keyed by the opcode **name string** (`_handlers = { "Face Unit 2":
Callable(…) }`, 48 entries), and **nothing bound those strings to the owned RE
catalog** (`event_opcodes.json`, 176 instructions, authored here). A catalog rename
silently unmatched a handler → the VM halted mid-scene with no compile-time or boot
signal. `_params_dict(inst)` flattened operands to `{name:int}`, discarding the
catalog's `bytes`/`mode`/`type:"Unit"`, which forced `{6B}` BG Sound into
hand-counted **positional decode** (`op[0]=Sound, op[1]=StartVol…`) — a silent
contract that breaks if the disassembler reorders operands. The three terminators
(`Event End`/`Event End 2`/`Block End`) were special-cased by name-string comparison
*before* the dispatch lookup.

Two owned principles bear on the fix: **ADR-0013** (FFT data decodes at the parser
boundary into *semantic* structure — no raw bytes/hex as the lead in runtime code),
and the `activity_taxonomy.yaml → gen` precedent (a semantic enum generated from an
owned source-of-truth file, `--check`-guarded in `run_all_tests.sh`). And "opcode"
is monorepo-crowded: the SMD sound driver's `runtime/.../opcodes/` ships in this same
Godot project, alongside BATTLE.BIN machine opcodes and effect-VM opcodes — so an
unqualified "opcode" is ambiguous inside the very package this lives in.

## Considered options

- **Status quo — name-string keys, no catalog binding.** Rejected: this is the bug.
  A rename is a silent mid-scene halt; the catalog's owned param widths/types go
  unused; positional decode is fragile.

- **Byte-keyed dispatch (`_handlers[0x2C]`), name demoted to display.** Faithful to
  the PSX dispatcher and rename-proof, and cheap since the chunk already carries the
  byte. Rejected as the *lead* identity: a bare `0x2C` / `242` as the dispatch key is
  exactly the "raw bytes lying around in runtime code" that ADR-0013 transforms away.
  The byte is kept — as the enum's underlying *value* — but it is not what handler
  code reads.

- **Name-keyed dispatch + a boot coverage assert.** Keeps `{ "Face Unit 2": … }` and
  makes drift *loud* (boot error) instead of *silent*. Rejected: it only *detects*
  the failure class rather than eliminating it — names stay load-bearing, and a
  display-string is still doing an identity's job.

- **A generated `EventInstruction` enum as the dispatch key (chosen).** The semantic
  transform ADR-0013 mandates, produced at the parser boundary from the owned catalog.
  The enum member is a compile-time-checked identity (a typo is a *parse error*), its
  value is the byte (faithful, and it matches `inst["opcode"]` for free), and the
  display name becomes pure data used only for traces — so a rename cannot touch
  dispatch. Handler registration (`_bind`/`_skip`) and the coverage test hang off the
  enum. Terminators fold into enum-keyed handlers, deleting the last name-string
  dispatch logic.

Three sub-decisions:

- **Slug disambiguation (Option A).** A naive display-name slug is *not* unique
  against the live catalog: the 48 `Unknown` entries all slug to `UNKNOWN`, and
  the six `Variable <=/>=/==/!=/</>` ops (0xA0–0xA5) all slug to `VARIABLE`.
  Member *values* (opcode bytes) are unique, but member *names* would collide and
  fail to parse. So the generator: slugs to `UPPER_SNAKE` and uses a unique slug
  verbatim (`FACE_UNIT_2`); on collision appends the opcode hex to every sharer
  (`UNKNOWN_0X12`, `UNKNOWN_0X14`, …); renders the `Variable` comparison family
  through a symbol map (`<=`→`LE` … `>`→`GT` ⇒ `VARIABLE_LE` … `VARIABLE_GT`); and
  re-asserts uniqueness after disambiguation. Because every one of the 176 catalog
  entries gets a member, the 48 `Unknown` bytes can be auto-`_skip`ped — required
  for byte-keyed dispatch to clean-skip them instead of halting. Full rationale +
  the slug-rule unittest: issue #145.

- **"Intentionally unhandled" lives in code, not the catalog JSON.** The owned catalog
  is RE fact about the PSX ROM (name, param widths, the PSX `handler` cross-ref,
  `verified`). Whether *Godot* acts on an instruction is a downstream policy that
  changes as we build — it belongs beside the bindings as `_skip(enum, reason)`, so
  the coverage check reads code → catalog and the JSON never edits when a handler
  lands.

- **Coverage enforced by a test (hard) + boot `push_warning` (soft).** The test is the
  gate (same tier as the gen `--check` pre-flight); the warning reminds a dev running
  headful without refusing to boot mid-RE-iteration.

## Consequences

- A catalog rename can no longer unmatch a handler — the failure class is structurally
  gone, not merely detected. A catalog rename regenerates the enum member name; the
  `_bind` site fails to *parse* until updated, at author time.
- `EventInstructionArgs` reads operands by width/type from the catalog and delegates to
  `PsxNum`; BG Sound's positional decode is retired on its migration turn, which also
  unblocks Candidate 3 (sound verbs on `ScenarioWorld`).
- Rollout is two-phase and behavior-neutral against the 45 `Scenario*Test` nets +
  `ScenarioApplyTest`: **Phase 1** (atomic) lands the generated enum, `_bind`/`_skip`,
  the folded terminators, byte-lookup dispatch, and the coverage test — leaving
  `_params_dict` and every handler body untouched. **Phase 2** migrates handlers off
  `_params_dict` onto `EventInstructionArgs` family-by-family (ADR-0058's order),
  retiring `_params_dict` last.
- `EventInstructionSet` lives in `src/scenarios/` (the ISA of the interpreter), not
  `src/data/` (keyed content stores) — a deliberate departure from the `XDatabase`
  location convention, justified by kind: this is a language definition, not game
  content.
- The sibling `battle_conditional_opcodes.json` (the BattleConditionals mini-ISA) is
  **not** renamed here; it is a separate language and can adopt the same pattern on its
  own later.

## Status

Accepted (2026-07-03)

## Amendment (2026-08-28) — both phases landed and every mechanism is drift-proof; the only things that rotted are the counts written beside them, and one consequence's wording is contradicted by the code that implements it

*Audited 2026-08-28 against `src/scenarios/`, `tests/`, `tools/` and the shipped
catalog JSON. Decision items numbered the same day.*

### What is current, per decision

| Dec. | Rule as written | Holds? | What the tree says |
| --- | --- | --- | --- |
| 1 | enum key, value **is** the byte | **yes** | `EventInstruction.gd` has 176 members, 176 unique names, 176 unique values; `_handlers` is keyed by that int |
| 2 | generated, `--check`-guarded, from the owned catalog | **yes** | `tests/run_all_tests.sh:91` runs `gen_opcode_catalog.py --check`; `:110` runs the slug-rule unittest. `event_opcodes.json` is **gone**; `event_instructions.json` holds 176 |
| 3 | `_bind`/`_skip`, terminators folded | **yes** | 75 `_bind` + 5 explicit `_skip` sites; `BLOCK_END:828`, `EVENT_END:832`, `EVENT_END_2:833` are ordinary binds. No name-string dispatch remains |
| 4 | typed reader replaces `_params_dict` | **yes — Phase 2 is DONE** | `_params_dict` has **zero** definitions or call sites in `src/`; it survives only in docstrings describing what it used to do |
| 5 | slug rules, Option A | **yes, exactly** | `UNKNOWN_0X12`…, and precisely `VARIABLE_LE/GE/EQ/NE/LT/GT` for the six `Variable` ops |
| 6 | "intentionally unhandled" in code | **yes** | `_skip(EVTCHR_PALETTE, "…not modeled in Godot")` &c. sit in the registrar; the catalog carries no policy field |
| 7 | test hard, boot warning soft | **yes, both** | `ScenarioEventInstructionCoverageTest` asserts it; `ScenarioVM:966` `push_warning`s the same set at boot |
| 8 | "opcode" = the raw byte | **yes** | the catalog is `event_instructions.json`, its inner key is `opcodes`, and the enum is `EventInstruction` — the split is held |

### The failure class this ADR was written to kill is gone, structurally

The stated bug was that a catalog rename silently unmatched a handler and the VM
halted mid-scene with no compile-time or boot signal. Today a `_bind` site names
an enum member, so a rename that regenerates the member makes the call site fail
to **parse**. There is no name-string dispatch left to unmatch — the terminators
that were special-cased by string comparison ahead of the lookup are three
ordinary binds. Both phases of the stated rollout landed, including the one the
ADR scheduled last: **`_params_dict` is retired outright.**

### Three counts have drifted; none of the mechanisms did

| Written | Today | Why |
| --- | --- | --- |
| "the 48 `Unknown` entries" (dec. 5) | **40** | eight have been RE'd and named since |
| "45 `Scenario*Test` nets" | **83** | the net roughly doubled |
| catalog `verified:true` (implied by the gate) | **27** | RE progress, and the gate's assert tracks it |

The `Unknown` drift is the instructive one. `ScenarioVM.gd:925` carries the same
stale "48" in its comment — but the code beneath it is
`for _unknown_op in EventInstructionSet.unknown_opcodes(): _skip(...)`, a query
against the catalog. So the count is wrong in **two** places and load-bearing in
**neither**: naming an Unknown opcode moves it out of the sweep automatically,
which is exactly what happened eight times. The same pattern holds for the
coverage gate — its assert is a literal `27` and its docstring opens "The catalog
carries 25 verified:true instructions today" before a comment trail that adds up
to 27. The literal is right, the lead sentence is two behind its own arithmetic.

Dec. 5's *rules* meanwhile reproduce exactly against the shipped enum: 40
`UNKNOWN_0X**` members and precisely the six symbol-mapped `VARIABLE_*` members,
with names and values both unique across all 176.

### One consequence's wording is contradicted by the code that implements it

The ADR twice condemns positional decode — "`{6B}` BG Sound into hand-counted
**positional decode** (`op[0]=Sound, op[1]=StartVol…`) — a silent contract that
breaks if the disassembler reorders operands" — and promises "BG Sound's
positional decode is retired on its migration turn".

`ScenarioVM.gd:2016` says the opposite in its first line: "`{6B}`/`{6A}` operands
are read **POSITIONALLY** through the reader, not by name". And its reason is
sound and specific: the two opcodes share one byte layout while the catalog
misnames `op[1]` ("Echo", actually the ramp StartVol) and gives `{6A}` **two**
operands both named "Unknown" — which name-keyed `_params_dict` collapsed into
one, losing an operand outright. `EventInstructionArgs.nth` reads by position and
cannot collapse them.

So the migration turn happened and made things strictly better, but it did not do
what the consequence says it would.

### Recorded question — was BG Sound's positional decode "retired"?

Two readings, and this audit does not choose:

- **(a) Yes, in substance.** What the ADR objected to was *hand-counted* decode
  outside any typed contract. That is gone: reads go through
  `EventInstructionArgs`, widths and types come from the catalog, sign extension
  goes to `PsxNum`, and the dup-name data loss the old path caused is impossible.
  The word "positional" in the consequence is shorthand for the fragile pattern,
  not for indexing as such.
- **(b) No — the named harm survives for these two opcodes.** The ADR's stated
  failure mode is "breaks if the disassembler reorders operands", and reading by
  `nth` is exactly as reorder-fragile as `op[0]`. What changed is which layer does
  the counting. Under this reading the ADR is describing a migration that cannot
  complete while the catalog misnames `{6A}`/`{6B}`, and the honest fix is to
  correct the catalog names rather than to record the decode as retired.

### The deferred sibling adopted the pattern, and the deferral still holds

The last consequence says `battle_conditional_opcodes.json` "is **not** renamed
here; it is a separate language and can adopt the same pattern on its own later."
Both halves check out, and in opposite directions: the file is still named
`battle_conditional_opcodes.json` (not renamed), **and** the pattern has since
been adopted — `src/scenarios/BattleConditionalOpcode.gd` is generated by the same
`gen_opcode_catalog.py`, with `BattleConditionalSet` and `BattleConditionalSetTest`
beside it. A deferral that was taken up on its own terms, exactly as written.

`EventInstructionSet` is also still in `src/scenarios/`, the deliberate departure
from the `XDatabase` convention that consequence defends.

### On mechanizing this ADR

This is the best-mechanized ADR the audit has reached. Dec. 2 has a `--check`
pre-flight, dec. 5 has a dedicated slug-rule unittest
(`tools/test_gen_opcode_catalog.py`), dec. 7 has both of its own arms, and dec. 4
is covered by `EventInstructionArgsTest` including the `{6A}` duplicate-name case
by name. Two arms are absent and both are one grep:

- **Dec. 4 as a negative:** assert `_params_dict` has zero definitions in `src/`.
  Phase 2 is complete, and nothing stops a future handler from reintroducing the
  flattener; the retirement is currently guarded only by its own absence.
- **Dec. 3/8 as a negative:** assert no `_handlers` key is a `String`. The whole
  point of dec. 1 is that a display string can never again do an identity's job,
  and today that is true by convention rather than by check.

A third arm is *not* worth writing: a guard on the "48 Unknown" count would pin
a number that is supposed to fall as RE lands — the drift-proof mechanism
(`unknown_opcodes()`) is already the right answer, and the fix for the two stale
comments is to delete the number, not to assert it.
