# Character catalog

The master identity layer above the battle roster: the durable, slug-keyed
record every unit is, the registry that owns them all, and the
human-authored key dialogue and scenario actors use to name one. **Prefactor
landed** (ADR-0066, issue #158): the `CharacterCatalog` autoload stores
`{slug: Character}`, and the `Character` identity type + `name provenance`
below are implemented and resolve dialogue name macros; Forms, Profiles, the
character-alignment transform, and template/instance materialization are still
design target. This cluster is the ubiquitous language for the whole concept
(a promotion of [UnitRosterData](03-unit-roster.md), not a from-scratch type). The guiding principle: *every* unit — protagonist,
special story character, generic recruit, throwaway cutscene extra — is one
uniform `Character`, functional attributes carrying imputed defaults so a
throwaway spins up minimal and is discarded.

**Character**:
The persistent catalog record for a unit: its durable *identity* (display
name, a canonical [slug] plus optional aliases) plus its *functional*
attributes (job,
equipment, abilities — held via the existing `UnitProgression`/`GambitList`
it already references). The thing a live `Unit` is **spawned from** and that
dialogue and scenario actors **point at** — never itself the in-scene node.
Supersedes `UnitRosterData` (which is already "identity + durable refs",
just battle-scoped and slug-less). Functional attributes have imputed
defaults, so a `Character` can be minted as "default", given only what its
role needs, and disposed. **Identity is unique within the active [Character
Catalog]** — one `"ramza"` — but a `Character` may **group one-or-more
[Form]s** (chapter/job incarnations); the Catalog resolves the *active*
Form. Job/appearance change over time is state, not a new `Character` (the
same rule the job system already applies to generics).
_Avoid_: conflating with `Unit` (the live in-scene fighter,
`src/units/Unit.gd`) or with `UnitProgression` (the durable stats
`Resource` a `Character` *holds*, not *is*); minting a second `Character`
for a character's later-chapter form (that's a new `Form`, same identity).

**name provenance**:
A per-`Character` flag — `Fixed` or `Player` — governing where its name comes
from and whether it is editable. `Fixed`: canonical, seeded from
`UnitNames.xml`, not player-editable (Agrias is always "Agrias"); a re-import
may overwrite it. `Player`: player-authored, editable, never clobbered by
re-import — generic recruits, and the **protagonist** (`Player` with the
canonical default "Ramza", which the name-entry flow may override — the one
story character you can rename). Drives the naming UI and re-import policy off
one field.

**Character Catalog**:
The master *runtime* registry of all currently-known `Character`s, keyed by
[slug]. The single source of truth for who exists. It holds **two
lifetimes** in one uniform lookup: **persistent** `Character`s (recruited /
story units, serialized to disk) and **transient** ones (throwaways minted
at scene-load from the [default Character prototype], registered under a
scene-scoped slug so dialogue resolves them, then dropped on unload — never
serialized). Persistence is a per-`Character` property, not a separate type;
`catalog[slug]` resolves both kinds identically. A [Roster](03-unit-roster.md) is
a **selection/view** over the Catalog (the units enlisted for a battle), not
the master list.
_Avoid_: treating the battle `Roster` as the master inventory (it is a
subset drawn from the Catalog); serializing transient throwaways.

**default Character prototype**:
The prototype a `Character`'s *data* is minted from — the "imputed defaults"
for every functional attribute (job, equipment, abilities). A throwaway is
instantiated from it, given only the minimum its role needs, and disposed;
a real recruit is the same mint with more overridden. Makes "instantiate
default → assign minimum → dispose" a single uniform path. **Not** an asset
[template] — this defaults a character's *data*; a `template` is its *visual*
packet. (Renamed from "default Character template" — ADR-0072 — to free the
word *template* for the asset packet.)

**template**:
A `Character`'s **visual asset packet — and nothing statistical**. A
*derived*, one-folder-per-key "packet" (ADR-0072) that **owns** its 1:1
assets (body sprite sheet, embedded portrait, palette, and the **formation
sprite** — 1:1 with the sprite sheet, sliced from the shared `EVENT/UNIT.BIN`
atlas into the folder) and **references** the one genuinely-shared asset
(animation TYPE by name; plus `flying`/`height` and EVTCHR/EVTFACE pointers
where they exist) through a small `template.json`. Addressed by a
polymorphic [template key]. **It is the runtime read surface** — the game
loads a unit's visuals *from its template folder*, so replacing a file in the
folder re-skins the unit (this is what makes the layout moddable). *(Target, not
built state: measured at `c1f1a56a8` (2026-08-20), `src/` holds **2** references
to the template store against **48** to the flat `assets/sprites/` store —
ADR-0072's loaders (#203) are still pending. See
[ADR-0132](../adr/0132-assets-are-filed-by-consuming-system-not-by-provenance.md).)* Emitted by
the [character-alignment transform] from the flat extract plus a small
hand-authored residue (the unique↔asset / EVTCHR bridge); **derived and
regenerable, never hand-owned as source**. **Every** `Character` has a
template — generics included (their key is `(job, gender)`); this is the
"giant job listing" already in the assets, reorganized per-key.
_Avoid_: putting stats in a template (assets only — a unique's ROM base stats
seed the `Character`'s *data*, not its template); hand-editing a derived
template folder as if it were source (it regenerates); assuming only story
units have templates (generics do too).

**template key**:
The polymorphic address into the [template] store — its *shape* depends on
the `Character`'s category, and the [slug] (identity) is in **no** key for
either category (it is upstream binding, not an asset param): generic-human
`(job, gender)`, generic-monster `(job)` (no gender), unique `(special_name)`
— the single ROM token that packs identity **and** [Form] (`RAMZA`, `RAMZA2`,
`RAMZA3`), so no separate `character_id`/`version` pair is needed (#199). For a
**generic**, `job` does double duty — it is both non-template *data* and the
*router* into the template. For a **unique**, `job` is *only* data and never
routes; the template is chosen by `special_name` alone (that is why a unique's
sprite is job-invariant: Ramza-as-Monk == Ramza-as-Wizard). The [resolver]
computes this key from a `Character`'s materialized params and returns its template.
A **fifth** dialect exists for a sheet that is *neither* identity nor job — an
[appearance-type], keyed by a [template_token] (ADR-0081). Full set: unique
`(special_name)`, generic-human `(job, gender)`, generic-monster `(job)`,
cutscene-face `(slug)`, appearance-type `(template_token)`.
_Avoid_: treating `job` as a template-router for a unique — it isn't; putting
the [slug] in a template key — identity is bound upstream, never in the key
(the sole exception is a [cutscene-face identity], whose key **is** the slug).

**cutscene-face identity**:
A story identity that appears **only as an EVTFACE dialogue portrait** — it has
no ENTD unit, no combat body/SPR sheet, and **no ROM `special_name`**. Known
solely by the name its dialogue script gives it (the `{Color 08}` speaker
header — see `PORTRAIT_ROW_OPCODE_50_EVTFACE.md` §9.5). The first genuinely
**SPR-less** members: Balbanes, Besrodio, Gelwan, Kanbabrif, Flower Girl,
Blansh, Bolmna, Elidibs, Grevados(-as-Cid). It is a fourth **[template]
category** (`cutscene-face`) beside unique / generic-human / generic-monster,
and the **one case where the [slug] IS the [template key]** — there is no `job`
to route on and no `special_name` to key on. Its template is **portrait-only**:
`events/face` cells (the EVTFACE grid slot the [identity table] assigns it),
the face doubling as its portrait, and **no `body.tga`**. Homed by a bare-slug
folder (`templates/balbanes/`), collision-guarded like the generic slugs.
_Avoid_: minting a **synthetic `special_name`** to force it down the unique
path (special_name is invariantly the ROM ENTD byte 0–255; a cutscene face has
none — key it by slug, per ADR-0066); filing a cutscene face into the ENTD
speaker's folder (its identity is its `(row,col)` grid slot, not the speaker —
the bug ADR-0072 §addendum fixes); expecting a `body.tga` (portrait-only).

**identity table** (EVTFACE):
The `(row,col) → identity` authority for the global EVTFACE portrait grid,
derived from each `{10}` message's `{Color 08}` speaker name
(`evtface_identity.py` → `evtface_identities.json`). The grid is global +
fixed; this table is the missing character axis. Splits each shown cell into
a [template]-homed unique (path A, existing token) or an un-homed name (a
[cutscene-face identity] to mint, or a pure generic the global grid serves).
_Avoid_: keying a cell on the ENTD speaking `Unit` (scene-local — the cell's
identity is intrinsic to `(row,col)`).

**resolver** (template resolver):
The seam that maps a `Character` to its [template]:
`Character (identity + job) → [template key] → template folder → assets`.
The answer to "where does the asset lookup live" — **between** the `Character`
and the template, part of neither. Any consumer (formation screen, combat
spawn, cutscene) calls it; it is the single place the `key → folder` dispatch
lives (generic keys resolve through the existing job tables, unique keys
through the residue manifest, [appearance-type] keys directly through the
folder-named [template_token]).

**appearance-type**:
A sprite **sheet reused across many nameless instances, with no identity behind
any of them** — a *kind of extra* (`40_year_old_woman`, `funeral_priest`, Holy
Dragon), not a person. In the ROM these spawn only as `special_name = 0`
anonymous slots (`sprite_set < 0x80`, "the byte IS the SPR id"), and no playable
job's `body_sprite_id` reaches their sheet — so they are addressable by
**neither** [special_name] (they are not identities) **nor** `(job, gender)`
(they are not a job's body). They get a [template] folder like anyone else, keyed
by a [template_token]. The axis they clarify: **appearance is not identity** — a
sheet answers "what does it look like," a [slug] answers "which persistent
individual is this," and the 40-year-old woman in Gariland and the one in Lionel
share the sheet but are *not the same woman*.
The test is **data-derived job-reachability** — no job's `body_sprite_id_male`/
`_female` resolves to the sheet (ADR-0081 dec. 8) — the same shape as the
resolver's `_has_gender_axis`. Exactly **21** template folders pass it.
_Avoid_: giving an appearance-type a [slug] or a synthetic [special_name] (both
assert an identity it does not have — ADR-0081); calling it a "generic" without
qualification (a *job-routed* generic like a Male Knight resolves by `(job,
gender)`; an appearance-type is the job-less remainder); using
`template.json.category == "generic-human"` as the test — that field is a **SHP
body-shape** axis (is the skeleton humanoid), not an identity axis, and it admits
the 38 generic-wardrobe sheets whose whole point is that a job *does* reach them.

**template_token**:
The **semantic folder name** an [appearance-type] `Character` carries to reach
its [template] — `"40_year_old_woman"`, resolving `TEMPLATE_ROOT + token` → the
same `template_folder` every unit returns into `load_body_sprite`. It is the
*appearance* reference, a field **distinct from the [slug]** (identity): a unit
has both. The fifth [template key] dialect (ADR-0081), parallel to how a
[special_name] reaches a unique's folder via `ResidueManifest`. Produced at the
**parser boundary** (the [character-alignment transform] owns the
`sprite_id → token` table), so the runtime keys templates by name, never by a raw
sprite-id hex — the appearance-handle case of ADR-0013's decode-at-parse rule.
Carried by an [appearance-type] and **nothing else**: a sheet a job reaches routes
by that job instead. The population today is **39** — the 21 job-less sheets plus
the 18-sheet staged remainder ADR-0081 dec. 8 names (15 story bodies, 3 monster
sheets), which are fixed-look either way and are held by a one-way ratchet.
_Avoid_: keying a template by the raw sprite id (`0x4F`) in the game (the token is
the parsed handle — ADR-0081); conflating it with a [slug] (identity ≠ appearance,
and many instances share one token); putting a token on a **generic-wardrobe**
sheet (`male_knight`, `female_squire`) — that pins the unit to one sprite for life
and defeats ADR-0072 dec.1, whose whole content is that a generic's `job` routes.

**special_name** (ROM unique-character selector byte):
The one-byte ENTD-slot field FFTPatcher labels "Special Name" — a **misnomer**:
it is not a name but a **selector**. `0` = a **generic** (a nameless `(job,
gender)` unit — a Squire, an Archer, a Chocobo); **nonzero = a specific unique
story character**, the *value* indexing the unique table (`0x01` Ramza, `0x04`
Delita, `0x05` Algus…). `unit_names.json` (`UnitNames.xml`) is only the
byte→display-name lookup over that table — which is why the *field* got called
"name," though the byte itself is an ID. The byte packs **two axes at once**:
*who* (many bytes → one [slug]: `0x01/0x02/0x03 → ramza`) and *which [Form]*
(Ramza's three chapter incarnations get three distinct byte values) — so it
doubles as the unique [template key] (`template_residue.json`: `"1":"ramza_1"`),
which is what makes it load-bearing at the **data/ROM boundary** (the parsers,
the side-car JSONs, and the [resolver]). In *runtime/design* discourse, speak
**[Form]** — `special_name` is just the opaque ROM token a Form is 1:1 with.
_Avoid_: reading it as a "name" (it is an ID/selector); treating it as identity
(the [slug] is identity — a `special_name` is one character's *one Form*);
storing it as a durable field on a persistent `Character` (it is **materialized
at the [seeding seam]** from story context, so a later chapter re-stamps it —
see [Form]).

**Form** (a.k.a. a unique's *version*):
One chapter **incarnation** of a *unique* `Character` — **1:1 with a ROM
`special_name`** (Ramza's Ch1 `RAMZA`, Ch2–3 `RAMZA2`, Ch4 `RAMZA3`), which
**is** its unique [template key] (no separate `version` component; the token
packs it). A `Character` (one identity) has one-or-more Forms, **N:1 onto the
`Character`**. Selecting a Form selects which unique [template] renders. The
active Form is resolved from **story context** (chapter/phase) at the
**seeding seam**, where it is *materialized* as the `Character`'s `special_name`
— so the [resolver] stays a pure function of that stamped param, never reading
story context itself. Only *unique* `Character`s have Forms; a generic's
[template key] is `(job, gender)` with no version axis.
_Avoid_: promoting a Form to its own `Character` (it shares the identity);
baking the Form choice into the slug (the slug names the identity, not the
incarnation); calling a Form a "sprite+stat bundle" — a Form selects a
*[template]* (assets only); stats live on the `Character`.

**seeding seam**:
The single moment a `Character` is placed into a *specific battle* and its
**context-dependent** facts are materialized onto the live `Unit` — the
[Form]'s `special_name` (→ which unique sprite/portrait the [resolver] returns),
presence/team, the deploy tile, and the event-tag ([units_by_id] handle).
**Durable identity lives in the [Character Catalog], keyed by [slug]; everything
that depends on *this* battle is resolved here, not stored on the identity** —
Form (per chapter), tile (per map), node (per scene) are all the same *kind* of
per-context fact. One seam-*shape*, two implementations distinguished only by
*source*: **ENTD-spawned** units read the Form off the ROM ENTD slot
(`ScenarioPlayerScene._spawn_units`); **roster-deployed owned** units have no
live ENTD slot, so they read it from ROM-derived data carried on their Catalog
`Character` (its Form set, seeded at mint — ADR-0079) and stamp it at deploy
(`NavigatorMain._deploy_owned_units` → `_spawn_owned_unit`), one line before
`resolve()`. A **miss** (no Form on file) correctly job-routes — that is how a
generic stays generic: *"has a Form here" == "is a unique here."*
_Avoid_: stamping the Form as a fixed byte at author-time (it is per-context —
the same reason the tile and the node are not stored on the identity); making
the [resolver] read story context (it stays a pure function of the stamped
param — the seam stamps, the resolver reads).

**Character Profile** *(superseded — see [template])*:
The former name for a per-`Form` derived asset+stat artifact. Superseded by
[template] (ADR-0072), which corrects two things: (1) **generics have
templates too** (Profile wrongly said they had none), and (2) a template is
**assets only** (Profile wrongly bundled the stat block). Kept as a redirect
so older notes resolve.

**materialized instance** (template ↔ instance rule):
A `Character` in the active [Character Catalog] is a **live instance** = an
immutable [template] (its visual packet) **plus** its non-template data
(stats, equipment, brave/faith, name) **plus** any runtime asset override:
`instance = template + data (+ override)`, copy-on-write on the override. The
[template] store **never mutates** — it stays regenerable and reproducible;
all mutation is instance state. Runtime re-skinning (costume/palette/sprite
swap, mods) is a *permitted capability* of this shape, YAGNI-gated: the
override seam exists; the system is not built until a use case needs it.
(Because the [template] is the runtime read surface — once ADR-0072's loaders
land; see above — a *mod* re-skins by replacing files in the folder; an
*in-play* re-skin is the per-instance override.)
_Avoid_: mutating a template folder in place as if it were instance state;
putting stats in the template (they are instance data).

**character-alignment transform**:
The offline normalization tier *between the ROM-faithful parsers and the
game* — a data-transform / anti-corruption layer. Two jobs: (1) consume
scattered parser output plus a small slug/unique↔asset residue and emit the
per-key [template] folders (the visual packets, one per [template key]); (2)
**rewrite the scenario event instructions to be slug-addressed** — replacing
raw `ENTD`/`special_name`/asset keys with [slug]s. The target runtime is then
purely `instruction slug → active [Character Catalog] → the `Character` →
[resolver] → its [template] → assets`; the ugly `ENTD → asset store` coupling
that exists today is resolved *once, offline*, so the runtime does **no
ad-hoc asset assembly**. Parsers stay ROM-faithful and reproducible (the
[Committed extracted artifact] contract is unchanged); the [template] folders
are a *downstream, regenerable* derivation, not a change to the parsers.
Generalizes the existing per-asset bake tools (`bake_evtchr_*`,
`normalize_texture_imports`, `split_manifest`) into one character-keyed
seam; EVTCHR frame resolution (`research/working_documents/EVTCHR_FRAME_RESOLUTION.md`,
"bake per-(entry,anim) at parse time") is the pilot / existing beachhead.
_Avoid_: pushing character-awareness *into* the parsers (they must stay
faithful); assuming an EVTCHR entry maps 1:1 to a character — that
resolution is the transform's hard-won job to encode, not a given.

**slug**:
The stable, human-authored key that identifies a `Character` across systems
(`"ramza"`, `"agrias"`) — the dialogue-facing identity. A `Character` has
**one canonical slug** (required, globally unique — drives display and
serialization) plus an optional **alias** set: extra lookup keys resolving
to the same `Character` (`"protagonist"`, `"the_king"`). The canonical slug
answers "what is this character"; aliases are just additional handles into
the same record. Distinct from the
event-local ENTD `unit_id` (a per-battle handle the event script's `{Unit}`
opcode uses) and from the ROM `special_name` byte (imported PSX content maps
its `special_name` → a slug, **many-to-one**: `UnitNames.xml` `0x01/0x02/0x03`
all → `ramza`, collapsing onto one `Character` *identity* — though each byte
still selects a distinct [Form] (a chapter/job sprite+stat bundle) in the
asset store). Resolution is a dict-get: `catalog[slug] →
Character → .name`. Generalizes PSX's hardwired `0xE0`/`{Ramza}` name-insert
macro, which imports as the single slug `"ramza"` (see the dialogue
name-macro decision).
_Avoid_: using the event-local `unit_id`, the raw `special_name` byte, or the
**combat buffer-slot / GPU unit index** as a cross-system key — those are all
context-local *handles* (the buffer slot is a transient array position, not an
identity at all); the slug is the durable one.

**Name macro**:
A dialogue token that inserts a `Character`'s name by [slug], resolved
`catalog[slug].name` at render. A *first-class* token type, decided at parse
time — distinct from a **word macro** (`{Serpentarius}`, a fixed vocabulary
substitution) and from formatting tokens (`{Newline}`, `{Color}`). Authored
content targets a slug explicitly (`{Name agrias}`); imported PSX content is
the degenerate case — the byte `0xE0`/`{Ramza}`, hardwired to the
protagonist, imports as the single name macro `{Name ramza}`.
_Avoid_: deciding "is this a name?" at render time by testing whether a
generic macro collides with a catalog slug — the name/word distinction is
fixed at parse time, so a word macro never silently becomes a name.

**Owned roster**:
The player's deployable subset, and — since ADR-0180 — **the only player
population there is**. Held as `CharacterCatalog._owned_order`, an ordered list
of [slug]s (deploy order = list order), read through `owned_units()`. It is a
catalogue-internal overlay, **not** a field on `Character`, so owning a slug is
independent of the catalogue holding one. It is **seeded by the mutation fold
every boot** (`CatalogueReplay`, an `own: true` delta) and `reset_to_new_game`
clears it — player-authored save/load of this layer is deferred (ADR-0201 §8).
So it is **volatile**: it exists because this run's script re-established it,
not because anything persisted it. This is what the Formation screen is fed,
unconditionally.
_Avoid_: "the roster" (there is no other one to distinguish it from, and the
word carries the retired store's baggage); reading **volatile** as "temporary
until the real store arrives" — the real store *is* this overlay gaining
save/load.

**Roster** (retired):
`PartyRoster` / `EnemyRoster` / `BaseRoster` — autoload collections that held
`Character` objects, persisted to `user://{roster,enemy_roster}.json`, and at
boot **promoted themselves into** the catalogue under positional `party:N` /
`enemy:N` slugs. Deleted by ADR-0180; ADR-0066 dec. 1 had demoted them to
"a selection/view over the catalogue" and the code was the inverse. The word
survives only in this entry, so a reader meeting it in old commits, comments or
ADRs 0004/0066/0073/0078 knows what it named.
_Avoid_: reviving the term for any live collection; "the persistent roster"
(what that phrase wanted is **owned roster** *with* persistence, which is
ADR-0201 §8's deferred work, not a second store); a `party:N`/`enemy:N` slug
(identity = slot, ruled out by ADR-0066 dec. 4).

**Class** (of a unit, at a battle):
`player` / `guest` / `enemy`, **derived and never stored** —
`CharacterCatalog.classify(slug, team_color)` reads owned-membership from the
overlay and `team_color` from the ENTD slot. It is a per-*context* role: the
same identity is a guest at one battle and a party member at another. Delita is
the canonical case — catalogue-yes, owned-no, Blue → `guest`. A view-layer
label; the engine team split stays binary (`EntdBattle.team_of`).
_Avoid_: an `enemy_units()` query or any second overlay mirroring
**owned roster** — that stores class, gives `guest` no home, and turns "joins
the party later" into a move between lists (ADR-0078, restated by ADR-0180).
The enemy side's counterpart to `owned_units()` is **the ENTD**, not a list.

**mutation script**:
The beat-keyed table of `create`/`join`/`leave`/`die` deltas [Character Catalog]
membership is a **fold of** (ADR-0201): `MutationScript`, looked up by a stable
per-action key, folded by `CatalogueReplay` as the walk advances. Since ADR-0216
it is **derived, not authored** — `StoryMutationScript` builds it from
`RosterTimeline`, which reads the ROM's ENTD `join_after_event` flags. A group
grants its recruits at its **END**, because the runner applies an action's deltas
as it *leaves* that action. Membership is therefore a function of *where the walk
has got to*, and nothing else mints it — which is why **owned roster** is
volatile.
_Avoid_: "the roster table" (it is deltas over beats, not a snapshot);
hand-authoring one (the two that existed, `Ch1MutationScript` and
`GarilandMutationScript`, were measurably wrong — they seeded four invented
generics where the ROM grants none, and joined Delita a chapter early).

**roster_before** (of a group):
The units the player should already own on **arriving at** a group root — the
fold of every recruit granted by the groups before it in story order. The
derived answer to "who is in the party here?", materialized per group in
`roster_timeline.json` and the thing a **Seek** installs so a re-rooted walk does
not arrive with an empty cast. Its counterpart on the world-map axis is the
group's `enter` state.
_Avoid_: reading it as "the deployed squad" — the deployment zone's
`max_squad_size` clamps it (Gariland: 7 owned, 5 fielded), so the two differ by
design; expecting every member to be NAMED (`special_name` above 72 has no entry
in `unit_names.json`, so Worker 8 and four others are in the fold as generic
`entd<record>_<slot>` slugs — the one declared gap left, ADR-0216 dec.14).

**never-owned recruit** (`StoryMutationScript.NEVER_OWNED`):
The five units the ROM flags `join_after_event` that never enter the **owned
roster** — Delita, Algus, Ovelia, Gafgarion, Alma. Not a new concept: it is the
catalogue-yes / owned-no case ADR-0078 already rules, and Delita is that ADR's
own canonical example. The list is **authored** because the ROM cannot say it.
`flags2 control` is clear on all 34 join slots, and across the 72 battle groups
exactly ONE always-present slot sets it (Orbonne's baked-in Ramza, the game's
sole predetermined cast) — in every other battle the player's units come from
the roster and are not in the ENTD at all, so a Blue slot is a guest *at that
battle* by construction and the flag cannot say whether a unit is ever owned
(ADR-0216 dec.8/11). It decides `own` at fold time; **Class** then reads the
result, which is why these units classify `guest` and not something new.
_Avoid_: reading it as a third role beside **Class** (it is one of `classify`'s
two inputs, not a rival label — an earlier draft of this entry called it a
"story guest" and stood up exactly that rival, which is the mistake); assuming
`join_after_event` means "joins the party" (it is set on these five too, which
is the whole reason the list exists — owning Delita would deploy a second one
beside the blue unit Gariland's own ENTD spawns).

**appearance** (vs **recruitment**):
A named unit the battle's own ENTD spawns, entering the catalogue so its slot
binds to a real identity (a `SlugBinding` HIT) rather than falling back to
raw-ENTD construction. It grants nothing to **owned roster**. **Derived**
(ADR-0216 dec.12): every always-present, canonically-named slot of a battle
group's ENTD, folded at that group's `opener` — the one plan action that lands
before the fight, where a recruit lands at the group's *end*. 28 units across 23
battles, named ENEMIES included (the catalogue is the one population; `classify`
decides the role). Bound ONCE, at a slug's first battle, so a later re-bind can
never clobber a Character the player has been levelling.
_Avoid_: booking an appearance as a recruitment (Agrias appears at Orbonne in
Chapter 1 and is recruited at root 175, two chapters later); expecting one for a
generic (an unnamed slot has no prior identity to resolve to); expecting one from
a cinematic group (no cast-composition seam, and its `team_color` is noise —
Ramza reads Red in 17 cinematic records); assuming the fallback is broken — an
unbound slot still builds a unit, it just builds a *different object* each
battle, so nothing about it persists.

**recruited-and-Red** (a declared contradiction):
A unit the derivation says is already in the roster that the ENTD spawns on the
Red team at a later battle — it would be deployable AND an enemy in the same
fight. `roster_timeline.json`'s `_coverage.recruited_red_conflicts` registers all
three rows unfiltered by `own`; two are canon (Algus and Gafgarion turn on you
and were never owned), so exactly one is real: **Rafa**, a derived recruit at
story position 72 and Red at 107. ENTD 433 in fact spawns her TWICE, both
always-present — Blue at slot 0, Red at slot 1 — so which one the battle uses is
not an ENTD fact at all. Her true recruit point is a **guest-versus-join** call
the flags cannot make — she carries `join_after_event` again at 108, which the
generator now emits, but her first flagged occurrence is still 72 — so it is
declared rather than guessed around, and guarded as a burn-down of exactly 1.
It is *not* the Worker 8 gap: that one was a `team_color` filter and is closed
(ADR-0216 dec.14).
_Avoid_: reading "Red after recruit" as a general defect signal (Delita,
Gafgarion and Algus turning on you is the plot); narrowing the register inside
the generator (it asserts no `own` at all — the consumer holds that list).
