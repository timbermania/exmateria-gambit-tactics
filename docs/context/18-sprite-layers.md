# Sprite layers

A unit's on-screen image is the composition of four ROM-defined **layers**
— `BODY`, `WEAPON`, `EFFECT`, `STATUS_TEXT` — stacked in an order picked
per-animation from the layer-priority table at BATTLE.BIN `0x80094548`
(parsed into `assets/sprites/layer_priority.json`). The cluster name comes
from the ROM; the runtime `ExMateriaSchema.SpriteLayer.Kind` enum is the same set.
This cluster keeps three things straight: **layer** (the render slot,
ROM-defined), **sprite type / template** (which SHP+SEQ tables fill that
slot, also ROM-defined), and the **asset format triple** the templates
live in on disc.

**The published spellings.** Extraction #4 moves this cluster's value
vocabulary into `exmateria_schema` — the kernel — and the rest of `Sprite Rig`
behind the `ExMateriaSpriteRig` façade. The kernel names follow its own
`DepthMode.Mode` / `CellMarking.Kind` form: a subject noun, then the kind of
thing it classifies. Settled by
[ADR-0217](../adr/0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md)
dec. 7; **the class names below do not change, only the enums move.**

| this cluster's term | spelled | state |
|---|---|---|
| [unit activity](18-sprite-layers.md) | `ExMateriaSchema.UnitActivity.Display` / `.Logical` | **landed, and it is the odd one out** — GENERATED, so it moved through `tools/gen_activity_taxonomy.py` and takes **no alias line**. `DisplayActivity.Activity` and `LOGICAL_ACTIVITY_*` are still emitted and still what the tree names; only the dispatch shell was repointed (#740) |
| [layer](18-sprite-layers.md) | `ExMateriaSchema.SpriteLayer.Kind` | landed |
| [unit material variant](18-sprite-layers.md) | `ExMateriaSchema.UnitMaterialVariant.Kind` | landed |
| [unit facing](22-sprite-variants.md) | `ExMateriaSchema.Facing.Direction` | landed |
| [animation clock](19-animation-playback.md) owner | `ExMateriaSchema.ClockOwner.Kind` | landed |

A naming file adds **one alias line per class** and the uses below keep their
spelling (ADR-0211 dec. 4) — the alias binds the **enum**, not the member script,
which is what makes it a repoint rather than a rewrite:

```gdscript
const FacingDirection = ExMateriaSchema.Facing.Direction   # FacingDirection.SOUTH still
```

_Avoid_: the bare kernel spellings `Layer`, `Owner` or `Variant` — each is a
word the engine or another cluster already owns (`Variant` is Godot's own type;
"[camera variant](22-sprite-variants.md)" is a different concept this same system
owns), which is why the subject noun is carried; **aliasing to the bare tail
`Variant`** in a naming file for the same reason — `FormationScene.gd` annotates
seven live values with the builtin and a local `const Variant` re-types them
silently, which is why that one alias is spelled `UnitMaterialVariant`; repeating
an alias in a child of a class that already declares it (GDScript refuses the
member and the parse error takes the whole child out).

#### Extraction #4 translation table (`Sprite Rig`)

Loop pass 4 of extraction #4 ([ADR-0217](../adr/0217-the-kernel-publishes-no-names-so-the-vocabulary-move-is-sixty-one-alias-declarations-and-the-rig-needs-a-facade-first.md),
[#740](https://github.com/timbermania/fft-monorepo/issues/740)), scored at pass 9
([ADR-0228](../adr/0228-the-rig-scores-six-of-nine-and-it-is-the-first-system-with-no-per-domain-escape.md)).
Old term → new, kept for a reader who knows the old vocabulary. Every row was
re-measured against the shipped addon at pass 9; where the tree and the plan
disagree the row says so rather than restating the plan.

| you may have read | say now | why |
|---|---|---|
| *`Sprite Rig` is `src/units/` plus `src/animation/` plus scattered files* | **`addons/exmateria_sprite_rig/`**, nine directories — `sequence` · `state` · `layers` · `render` · `crystal` · `content` · `install` · `resources` · `viewer` | [ADR-0215](../adr/0215-the-sprite-rig-seam-is-a-scene-a-vocabulary-and-a-content-port-and-two-thirds-of-its-interface-belongs-to-two-adapters.md), loop pass 6 ([#744](https://github.com/timbermania/fft-monorepo/issues/744)). The subdirectory names the FACT the file encodes, the same layout rule `addons/exmateria_platform/` follows. Measured at pass 9: **36 source files / 7,054 lines** in the addon (`git ls-files`), **6,435 lines** in the `Sprite Rig` BUCKET (`check_baseline.py --delta`, a different subject — `viewer/SequenceViewer.gd` ships inside the addon and books to `assembler`), outbound system reaches **29 → 0** and inbound **118 → 33** against the frozen baseline |
| `DisplayActivity.Activity` · `LOGICAL_ACTIVITY_*` | **`ExMateriaSchema.UnitActivity.Display` / `.Logical`** — *and the old spellings are still what the tree reads* | dec. 7/8. This is the one row of the five that takes **no alias line**: both halves are GENERATED from `tools/activity_taxonomy.yaml`, so the rename went through `tools/gen_activity_taxonomy.py` and only the dispatch shell was repointed. Pass 9 measured what that bought: **`ExMateriaSchema.UnitActivity.Display` has 4 readers** — all four in `src/gpu/ActivityTranslator.gd`, all four written by the generator — against **67** lines still spelling `DisplayActivity.Activity.` and **218** spelling `LOGICAL_ACTIVITY_*`. `UnitActivity.Logical` has **zero readers anywhere**: `Battle` reads the GPU's integer constants, not the enum. The kernel half is published and unread, which is dec. 8's ruling holding as a FILE and not as a use |
| `AnimationStateController.FacingDirection` | **`ExMateriaSchema.Facing.Direction`** (52 crossing uses) | dec. 7. The class keeps its name and its behaviour; only the enum moves. Verified at pass 9: **0** occurrences of the old spelling |
| `SpriteLayerManager.Layer` | **`ExMateriaSchema.SpriteLayer.Kind`** (50) | dec. 7; **0** occurrences of the old spelling. `SpriteLayerManager` keeps its 888 lines |
| `AnimationClock.Owner` | **`ExMateriaSchema.ClockOwner.Kind`** (38) | dec. 7; **0** occurrences of the old spelling. `AnimationClock` itself publishes NOTHING — it became an in-addon `preload` with no façade constant at all ([#746](https://github.com/timbermania/fft-monorepo/issues/746)) |
| `UnitMaterial.Variant` | **`ExMateriaSchema.UnitMaterialVariant.Kind`** (9) | dec. 7; **0** occurrences of the old spelling. The subject noun is carried because `Variant` is Godot's own builtin — the one alias in this family that may NOT be spelled with the bare tail |
| *the vocabulary is six enums* | **five** — `AnimationOpcodes.SideEffect` stays the rig's, as `ExMateriaSpriteRig.AnimationOpcodes.SideEffect` | dec. 6. The kernel holds a value vocabulary two systems must AGREE on. A SEQ opcode's side-effect flag is the rig's own implementation detail with 4 crossing uses, and moving it would put an implementation term in the shared dictionary |
| *the rig publishes twenty `class_name`s* | **one global name** — `ExMateriaSpriteRig`, carrying 21 façade constants | [ADR-0211](../adr/0211-nothing-preloads-in-so-the-class-name-set-is-the-whole-surface.md) dec. 2 / [ADR-0212](../adr/0212-a-count-of-one-was-never-the-invariant-the-addons-one-global-is-the-folder-named-facade.md), built at #746. 18 `class_name`s became façade constants, 2 (`AnimationClock`, `PlaybackSet`) became internal `preload`s with no publish. P1 predicted nine names over 18 behaviour members and pass 9 reads **30 non-enum members plus one enum over 18 names**; the interface was NOT tuned to the prediction |
| *a `class_name` is how a class is published* | **a façade constant is** — and a host ALIASES it back, so every use site keeps the spelling it had | ADR-0211 dec. 4. A host may alias a published constant; it may not `preload` an addon path. That is why the rename above costs one line per naming file and no line per use site, and why [ADR-0227](../adr/0227-a-facade-re-export-is-not-a-use-and-the-closure-could-not-tell.md) then had to teach `closure.py` that a façade's own `const X = preload(…)` line is **not a use** |
| *the rig publishes as a set of classes* | **as ONE SCENE** — `addons/exmateria_sprite_rig/UnitRig.tscn`, which `assets/scenes/Unit.tscn` INHERITS | ADR-0215 dec. 3 / ADR-0217 dec. 3. The scene publishes through a **declared mount** (`check_lattice_scene.py`'s `DECLARED_MOUNTS`), not through the façade — a mount is an exemption from criterion 4, not a third channel of it |
| `AnimationNames` in `src/data/` | **`ExMateriaSpriteRig.AnimationNames`**, at `sequence/AnimationNames.gd`, addressed by `SpriteRigContentRoot.ANIMATION_NAMES_SUBPATH` | [ADR-0223](../adr/0223-a-reach-has-a-bucket-and-an-address-and-goal-5-only-ever-read-the-bucket.md) dec. 9, built at [#809](https://github.com/timbermania/fft-monorepo/issues/809). It is the rig's own SEQ-slot vocabulary and it sat in the host's data folder; one host file aliases it back |
| `JsonAsset` in `src/data/` | **`ExMateriaPlatform.JsonAsset`** — the PORT, not the kernel | ADR-0223 dec. 8, built at #809. Its 32 namers span three packages and it encodes no shared value vocabulary, so the kernel is the wrong home even though ADR-0139 names it as its own counterexample. 23 `src/` + 4 `tests/` + 5 in-addon alias lines |
| *the rig owns its sprite content* | **the host INJECTS it** — one content root, eleven subpaths | ADR-0215 dec. 6/7, ADR-0217 dec. 9. The content does not move: `SpriteRigContentRoot` names `sprites/animations/`, `sprites/textures/`, `layer_priority.json`, the WEP1/EFF1 pairs, `evtchr/`, `crystal_sheet.png` and `animation_names.json` as subpaths under one injected root, and `ContentPort` answers **seven scalar queries over four key spaces**. Four reaches that read as four dependencies were one port |
| `src/scenes/SequenceViewer.gd` | **`addons/exmateria_sprite_rig/viewer/SequenceViewer.gd`** — and both halves ship INSIDE the addon | ADR-0215 dec. 4. It exercises the whole rig, so it moves with it. The consequence lands at pass 9: `docs/ROOT_SET.tsv` books `viewer/SequenceViewer.tscn` as an **authoring root**, which makes `Sprite Rig` the first extracted system for which goal #10's `n/a` is not available |
| *goal #5 is met when the reach count reads 0* | **a reach has a BUCKET and an ADDRESS, and the count only ever read the bucket** | ADR-0223. Four instruments deliberately disagree — `check_addon_portability.py` arm 1 (bucket), arm 7 (host `class_name`), arm 6 (`res://` path), and `check_lattice_scene.py` criterion 4. #809 emptied arm 7's burn-down to zero rows; all four now read 0 for this addon |
| *a `res://assets/` line in an addon is a path reference* | **criterion 4 has a scored PRODUCTION channel and a reported ORACLE channel, and the two are never summed** | [ADR-0222](../adr/0222-criterion-4-is-the-production-channel-and-an-oracle-is-reported-beside-it.md) dec. 1/3. An oracle literal is a test's independent statement of where a thing lives; scoring it would launder the guard into a tautology, and hiding it would lose the only line that can catch the guard agreeing with itself |
| `CameraRelativeRenderer.psx_camera_angle_changed` · `.last_psx_camera_angle` · `UnitDisplay._view["psx_angle"]` · `AnimationStateController.get_pose_octant(_, psx_camera_angle_12bit)` | **`camera_angle_changed`** · **`last_camera_angle_12bit`** · **`_view["camera_angle_12bit"]`** · **`get_pose_octant(_, camera_angle_12bit)`** | [ADR-0234](../adr/0234-a-port-half-is-not-shipped-until-both-directions-of-the-value-are-on-it.md), built at [#848](https://github.com/timbermania/fft-monorepo/issues/848). These twelve lines were the whole of this addon's rig-owned goal #7 debt and they all named ONE thing, the camera yaw. The row `docs/GOALS.tsv` used to carry said they were `#583`'s work, on the argument that renaming the consumer ahead of the port would spell a concept the port still spells `psx`. Measured: the port does **not** spell it `psx` — `PSXDisplay.live_camera_angle`, `DisplayPort.live_camera_angle()` and `DisplayPort.set_camera_angle()` are all prefix-free, and the `psx` was this addon's own local spelling echoing nothing. Two of the four are CONTRACTS with the host and moved in the same commit: the signal (`src/units/Unit.gd`'s connect and `_on_camera_angle_changed` handler) and the `_view` key (`Unit._build_view`, plus the two golden tests that hand-build the dict). `get_pose_octant`'s parameter has 12 call sites and all pass positionally, so that one is a name and not a signature |
| *`PSXDisplay.live_camera_angle if PSXDisplay else 0` degrades gracefully* | **it cannot fire, and the addon now reads `ExMateriaPlatform.DisplayPort.live_camera_angle()`** | ADR-0234 dec. 1/2, #848. A bare autoload identifier resolves at COMPILE time, so where the name is bound the ternary is dead weight and where it is not the file does not parse and the fallback is unreachable by construction. The intention was in the source and the source could not run it. `DisplayPort` is where it executes — a node-path soft-bind at call time with `0` as the defined absent value. The last copy of the idiom, `src/units/Unit.gd:975`, went with it |
| *a `[shader_globals]` entry is the host's to declare* | **the addon that DECLARES a `global uniform` PROVIDES it** | [ADR-0220](../adr/0220-the-addon-that-declares-a-global-uniform-provides-it.md) dec. 1/2. `exmateria_platform` provides all six; this addon declares none and consumes four through `#include`, which is why its shader half has no install obligation of its own |

**Layer**:
A render slot on a unit's billboard, drawn in the order chosen by an
animation's [layer priority](25-rendering-depth.md) entry. Four slots, all
ROM-defined: `BODY` (the character/monster), `WEAPON` (the held weapon),
`EFFECT` (a sprite-only overlay — a spark, a weapon gleam, a swing blur,
deliberately tiny), and `STATUS_TEXT` (damage numbers / status word
graphics). Every layer paints onto the **same** mesh today; the layer is a
shader/material concept, not a separate Node3D. **WEAPON and EFFECT are
populated only for `TYPE1` / `TYPE2` [sprite types](18-sprite-layers.md)**;
monsters, chocobos, and altima paint BODY (plus STATUS_TEXT) only —
the slots exist in the enum but the data tables don't. **Published as
`ExMateriaSchema.SpriteLayer.Kind`** — `SpriteLayerManager` keeps its name and
its 888 lines of behaviour; only the enum moves (ADR-0217 dec. 7).
_Avoid_: the word "Effect" without the "layer" qualifier when the sprite
layer is meant — the `EFFECT` *layer* is one tiny sprite slot, distinct
from the [effect cast](15-effect-orchestration.md) subsystem (the whole
ParticleSubsystem / EffectTimeline / ColorSubsystem cluster); the two share
the word and nothing else; calling the BODY layer "TYPE1" — `TYPE1` is a
[sprite type](18-sprite-layers.md), not a layer (the body layer's template
might equally be `TYPE2`, `MON`, `CYOKO`, …).

**Unit material variant**:
Which of `Sprite Rig`'s unit-sprite materials a caller is asking for — `OPAQUE`
(the battle body), `ADDITIVE` (the scenario-6 dead-unit fade) or `FLAT` (the
formation/roster screen's [flat orthographic UI scene](26-display-space-fold.md)).
Requested through `Sprite Rig`, never assembled by the caller: the variants differ
only in `render_mode`, which Godot requires in the entry `.gdshader`, so there is
one file per variant and **no file outside `Sprite Rig` names one**
(ADR-0189). All three drive the identical uniform block through the same
`SpriteLayerManager`; a variant is a blend and a depth policy, nothing more.
**Published as `ExMateriaSchema.UnitMaterialVariant.Kind`** — the subject noun is
carried because `Variant` alone is Godot's own type name *and* collides with
[camera variant](22-sprite-variants.md) (ADR-0217 dec. 7, S1). The base material
is **injected**, not addressed: `for_variant()` takes it as a parameter rather
than loading `res://assets/materials/unit.tres`, which is what keeps the addon
free of `res://assets/` addresses (ADR-0217 dec. 12).
_History_: `UI` and `Cutscene` used to obtain theirs by loading
`assets/materials/unit.tres` and overwriting its `.shader` — one line each — which
is how a 1,018-line hand-synced fork of the compositor came to exist in
`src/ui3/shaders/`.
_Avoid_: "the unit shader" unqualified (there are three); treating the variant as a
material the caller builds; adding a variant for a feature that is a `bool` branch
(that is [modulation](18-sprite-layers.md), not a variant).

**Sprite modulation**:
A per-pixel operation applied to a unit sprite **after** its layers are composed —
today the Change-Job commit's cell-noise dissolve and its bilinear gouraud corner
tint. `Sprite Rig`'s Part since ADR-0189, and booked there on **ordering** rather
than subject: the tint must modulate between the [colour stack](27-color-modes.md) fold
and the ambient term, where the PSX applies gouraud, and only the system that owns
that pipeline can hold that position. The calling screen owns *when* a modulation
runs and what it is parameterised with; `Sprite Rig` owns where in the sprite's
pipeline it lands.
_Avoid_: implementing one as an overlay quad (it composites after everything, so it
cannot reproduce the PSX ordering — the whole point); routing one through the
[colour stack](27-color-modes.md) when it varies across the surface (`ColorRecipe`'s
affine is uniform over the surface, and the wire format's affine-vs-luma
discriminator has no spare encoding for a third shape).

**Sprite compositor stages** (`unit_paint` / `unit_colour` / `unit_light`):
The four names `addons/exmateria_sprite_rig/render/unit_sprite_body.gdshaderinc` publishes — `billboard()`
plus these three — from which each of the three [unit material
variants](18-sprite-layers.md) writes its own `vertex()` and `fragment()`. The
include stopped owning those two stages at ADR-0189 dec. 1; `render_mode` has to sit in
the entry `.gdshader` (Godot has no runtime blend switch), so the entry files exist
anyway and each genuinely differs in both stages. Order is fixed: `unit_paint(uv, out
albedo, out alpha)` composites the tile layers and reports coverage; the entry discards
below `UNIT_ALPHA_CUTOFF`; `unit_colour` folds the [colour stack](27-color-modes.md) and
clamps; `unit_light` applies ambient and converts sRGB → linear.
**The gap between `unit_colour` and `unit_light` is the load-bearing part.** That is
where the PSX applies gouraud, so it is where a [sprite modulation](18-sprite-layers.md) has
to land. Publishing three stages rather than one shared `fragment()` is what makes that
position reachable from an entry shader — a two-name split would put a consumer that
needs it straight back to forking the compositor, which is the 1,018-line duplicate
ADR-0189 removed.
_Why the entry discards and not the include_: the flat variant has a SECOND discard (the
change-job dissolve) that must run after the coverage one and before anything writes
depth, so the first cannot be buried in shared code.
_Avoid_: adding a stage for something one variant needs (that is what the entry's own
`fragment()` is for); calling these "the unit shader" (there are three entries and one
include); moving a `#include` into the shared body for a seam only some variants apply —
`pixel_aspect` lives in the two battle entries precisely so the flat one does not reach it
while never using it (dec. 6).

**Body sprite ID** (a.k.a. `body_sprite_id`):
The numeric handle 0x01..0x9A naming which of FFT's 154 ROM-authored
character sprites a unit's [BODY layer](18-sprite-layers.md) paints.
Authority: BATTLE.BIN's sprite-LBA table at `0x2DCD4` (159 records ×
8 bytes — `(sector_u24, size_u32)` per slot) joined with the ISO9660
/BATTLE directory walk on sector. Parsed by
`tools/build_sprite_file_map.py` into `assets/sprites/sprite_files.json`
(154 entries; 5 ROM-faithful gaps are omitted — they have null sector
in the table). The runtime field on Unit is `body_sprite_id: int`
(default `0x01`, the first valid ID); the [extraction
pipeline](01-asset-extraction.md) emits one [texture](17-sprite-and-texture.md)
pair per ID — `NN.tga` + `NN.palette.tga` — under
`assets/sprites/textures/`.

The mapping is **N-to-1**: the same `.SPR` file can back multiple body
sprite IDs (`MINA_M.SPR` backs 8 humanoid-female slots that share
authoring data), so the SPR filename is *authoring provenance*, not a
runtime identifier. The only stable runtime handle is the numeric ID.

⚠️ AND THE FILENAME ACTIVELY MISLEADS, because the romanization reads like
a character and names a different one. `GARU.SPR` (0x16) sounds like
GAfgarion and is **Mustadio's** sheet; `AGURI.SPR` (0x34) sounds like
AGRIAS and is her **Form 2**. Both traps were sprung: the hand-authored
rows of `assets/scenarios/template_assets.json` gave sn 23 (Gafgarion)
0x16 and sn 30 (Agrias Form 1) 0x34, so the chapel painted Mustadio's
portrait on Gafgarion and nothing failed — the wrong id bakes into a
gitignored `templates/` folder that `UIPortrait.display_from_template`
PREFERS over the (correct) `body_sprite_id` on the spawned Unit. This
paragraph already said "not a runtime identifier" while both rows stood
wrong, which is why the rule is now MECHANIZED: the referee is the
`special_name → sprite_set` census over `entd.json`, and
`tools/check_template_assets_entd.py` runs it in the pre-flight.

**Hand-authored display labels** live separately in
`JobDatabase.SPRITE_NAMES` — e.g. `0x01 → "Ramza Ch1"`,
`0x60 → "Male Squire"` — sourced from FFTPatcher
`SpritesheetNames.xml`. **The two never mix at the extraction boundary**:
ROM-derived authoring names (`sprite_files.json`'s `RAMUZA`, `MINA_M`,
`ADORA`, …) and hand-curated semantic labels (`SPRITE_NAMES`'s "Ramza
Ch1", "Male Squire", …) are separate inputs that meet only at the
numeric body sprite ID. Mixing them was the long-standing extractor
smell ADR-0022-era refactors retired.

_Avoid_: treating an `.SPR` filename as a runtime identifier — it's
N-to-1, not stable, and meant for FFT-developer provenance only;
using `0x00` to mean "default" or "uninitialized" — it's not in the
ROM-faithful map, has no texture, and the runtime should fail loudly
on it (the silent-transparent rendering bug this term retires);
conflating `JobDatabase.SPRITE_NAMES` (hand-curated display strings,
FFTPatcher-sourced) with `sprite_files.json` (ROM-derived
provenance) — they answer different questions and must be sourced
independently; calling it `sprite_id` unqualified — `body_sprite_id`
is BODY-scoped; the WEAPON layer uses a different identifier scheme
(item-driven via `weapon_animation_ids.json`).

**Sprite type** (a.k.a. body template):
The schema a unit's [BODY layer](18-sprite-layers.md) conforms to — picked
per [body sprite ID](18-sprite-layers.md) from a fixed set of eight (`TYPE1`,
`TYPE2`, `CYOKO`, `MON`,
`OTHER`, `RUKA`, `ARUTE`, `KANZEN`). The sprite type also determines
which (if any) overlay templates the unit's WEAPON / EFFECT layers use.
The canonical table (authority: `assets/abilities/sprite_types.json`,
sourced from BATTLE.BIN `0x2D748` by `tools/parse_sprite_types.py`):

| Sprite type | Body SHP   | Body SEQ   | Weapon | Effect | Notes |
|-------------|------------|------------|--------|--------|-------|
| TYPE1       | TYPE1.SHP  | TYPE1.SEQ  | WEP1   | EFF1   | One humanoid shape (62 sprites in the roster) |
| TYPE2       | TYPE2.SHP  | **TYPE3.SEQ** | WEP2   | EFF1   | A second humanoid shape (66 sprites). Uses TYPE3.SEQ, not TYPE2.SEQ |
| CYOKO       | CYOKO.SHP  | CYOKO.SEQ  | —      | —      | Chocobo |
| MON         | MON.SHP    | MON.SEQ    | —      | —      | Generic monsters |
| OTHER       | OTHER.SHP  | OTHER.SEQ  | —      | —      | Misc. |
| RUKA        | MON.SHP    | RUKA.SEQ   | —      | —      | Lucavi demons (use MON.SHP) |
| ARUTE       | ARUTE.SHP  | ARUTE.SEQ  | —      | —      | Altima first form |
| KANZEN      | KANZEN.SHP | KANZEN.SEQ | —      | —      | Altima perfect form |

The `research/wiki_articles/target_reaction_animations.txt` reference labels
TYPE1 as "Human Male" and TYPE2 as "Human Female." The sprite_types data
contradicts that read directly — 62 TYPE1 and 66 TYPE2 sprites is far more
than FFT has gender-specific job slots, and Shishi's editor doesn't apply a
gender attribute at this level. Treat TYPE1 / TYPE2 as **two humanoid body
shapes**, not as gender buckets; many named-character sprites of either
gender land in either type.

**WEP1 vs WEP2 — same pixels, different SHP/SEQ definitions.** Shishi's
`AllSprites.cs` registers WEP1 and WEP2 at the **same KnownPosition** in
WEP.SPR — they alias the same byte range, so there is only one texture sheet.
What differs is the SHP/SEQ pair: TYPE1 sprites read `WEP1.SHP/WEP1.SEQ`,
TYPE2 sprites read `WEP2.SHP/WEP2.SEQ`. Both sample into the same texture.
The "WEP2" name in code (`uses_wep2`, `wep2_shp`) refers to the **SHP/SEQ
file selection**, not a separate pixel sheet.

(Separate observation about the texture layout itself: each weapon has two
adjacent angle/pose sprites within the shared WEP texture. That intra-sheet
two-angle layout is unrelated to the WEP1/WEP2 file-level distinction.)

Three things this table fixes that the historical naming hid: **(1)** SEQ
and SHP are picked independently — TYPE2 sprites use TYPE2.SHP but
**TYPE3.SEQ** (not TYPE2.SEQ); never assume `get_seq_type() ==
get_shp_type()`. **(2)** Only TYPE1 and TYPE2 have WEAPON or EFFECT
layers; monster / chocobo / altima sprites paint BODY (and
[STATUS_TEXT](18-sprite-layers.md)) only. The `WEP1` / `WEP2` / `EFF1` / `EFF2`
templates are *overlay* schemas, not selectable per [body sprite
ID](18-sprite-layers.md) — the body
type picks them. **(3)** `TYPE2.SEQ` and `TYPE4.SEQ` files exist on disc
(parsed into `type2_seq.json` / `type4_seq.json` in this repo) but are
**never loaded by the game** — they're orphans, not alternate paths.

The runtime mapping is in `SpriteDatabase` (`get_shp_type`,
`get_seq_type`), backed by the ROM table at BATTLE.BIN `0x2D748` parsed
by `tools/parse_sprite_types.py`. The parser's `SEQ_FILE_MAPPING`
(`TYPE2 → TYPE3`) bakes the TYPE2-uses-TYPE3.SEQ quirk in at parse time,
so the JSON's `seq` field is the actual file name to load, not the ROM
byte's logical name.
_Avoid_: conflating a sprite type with a [layer](18-sprite-layers.md) —
`Layer.TYPE1` is the historical naming smell this cluster retires; calling
the overlay templates (`WEP1` / `WEP2` / `EFF1` / `EFF2`) "sprite types"
unqualified — they're overlay templates selected by body sprite type,
not selectable per [body sprite ID](18-sprite-layers.md); assuming SEQ and
SHP match for a given
sprite (TYPE2 is the counter-example: `shp=TYPE2`, `seq=TYPE3`); treating
TYPE3 or TYPE4 as first-class sprite types — TYPE3 is the SEQ file
TYPE2 sprites use, and TYPE4 isn't loaded by anything; assuming every
unit has all four layers — monsters / chocobo / altima have no WEAPON
or EFFECT, only BODY (and STATUS_TEXT).

**SPR / SHP / SEQ**:
The asset-format triple a [sprite type](18-sprite-layers.md)'s data lives in
on disc — three sibling files per template: `.SPR` (raw paletted pixel
data — the texture), `.SHP` (per-frame *shape* composition: which
sub-rectangles of the SPR go where, with offsets and flips), `.SEQ`
(per-animation *sequence*: the ordered frame indices and opcodes that
drive playback). A frame is rendered by combining one SHP entry's
sub-rectangles read from the unit's SPR; a sequence advances through SHP
frame indices over time. The `assets/sprites/animations/*_shp.json` and
`*_seq.json` files in this repo are the parsed forms; `.SPR` becomes the
character `.tga` under `assets/sprites/textures/`.
_Avoid_: calling the body layer "SPR" — SPR is the texture file format,
not a render slot; treating `.SHP` and `.SEQ` as the same concept (they
serialize different things: shape vs. sequence); referencing a `.SPR`
without naming the sprite type whose templating it follows (an SPR is
indexable bytes; it's a SHP that gives them meaning as frames).

**Sprite palette**:
The PSX-native indexed-color table baked into a [SPR](18-sprite-layers.md) — 16
rows × 16 colors (256 entries), 4bpp indices stored per pixel. Unit color
variants (Yellow / Black / Red Chocobo, Goblin variants, Dragon variants,
future status effects) are **palette-row swaps on the same SPR** at runtime,
not separate sprites. The shader picks one row via a uniform; the BODY
layer's render pipeline (per ADR-0022) does the index → palette lookup at
fragment time. The palette table itself lives in `assets/sprites/textures/`
as `NN.palette.tga` (16×16 RGBA) alongside the per-sprite indexed
`NN.tga`. **Per-job source**: `jobs.json[job_id].body_palette_row`
(parsed from SCUS_942.21 byte 0x2E — what TacticsG calls
`monster_palette_id`). Most generic-humanoid jobs leave it at 0
(default); monster jobs set it from ROM data — e.g. job 0x5E Chocobo
→ row 0 (yellow), 0x5F Black Chocobo → row 1, 0x60 Red Chocobo → row 2.
**Three distinct "palette" usages in this codebase, do not conflate**:
this entry (sprite-level indexed-color tables); the
[PaletteSubsystem](15-effect-orchestration.md) (effects-system RGB tint applied
to a render target during a spell cast, ADR-0011 / ADR-0014); the UI font
palette (color rows for `UIText`, [Setter shapes](30-ui3-components.md)).
_Avoid_: "monster palette" as a standalone term — palette is a universal
sprite concern (humanoids use row 0 by default; monsters happen to be where
non-zero rows show up first); confusing this with the effects-system
palette (RGB tint, not indexed lookup); applying a sprite palette to the
WEAPON or EFFECT layers (ADR-0022 scopes paletting to BODY; WEAPON palette
is per-equipped-weapon and EFFECT palette is per-keyframe).

**Palette row**:
The integer 0-15 selecting which row of a [sprite palette](18-sprite-layers.md)
applies at runtime. Two uniforms feed it per Unit (per ADR-0022):
`body_palette_row` (default 0 humanoid, set from ROM for monster jobs;
drives the BODY shader's palette lookup) and `portrait_palette_row`
(default 8 preserving the humanoid extraction convention; drives the
portrait shader; no per-job override in v1 — monster portrait variants
deliberately known-broken pending v2 ROM research). Separate because
humanoid SPRs use row 0 for body pixels and row 8 for portrait pixels by
convention; forcing one row would break humanoid portraits to fix monster
bodies.
_Avoid_: storing a single shared `palette_row` on Unit (the body /
portrait split is intentional); reading the palette row from anywhere
other than `jobs.json[job_id].body_palette_row` for the body field (one
source per concern, per ADR-0021's discipline); per-unit `portrait_palette_row`
override (the v1 field is uniform across all units of a given sprite — if
we ever need per-job override, that's an ADR-0022 follow-up).

**SEQ slot label** (a.k.a. animation name):
The hand-authored wiki label for a single SEQ slot — e.g. `(type1, 128) →
"Swing High Front"`. Joins to the ROM-derived [SEQ](18-sprite-layers.md) data
at use time, giving the otherwise-opaque slot index its semantic meaning.
Lives in `assets/sprites/animation_names.json` (2206 rows covering every
named SEQ slot for all 14 sprite types/templates), borrowed from
TacticsEngineG via `tools/build_animation_names.py` and regenerable any
time their upstream labels update. A [hand-authored data
asset](01-asset-extraction.md) — not ROM-derived, not regenerated by
`bootstrap_assets.sh`; read at runtime by `AnimationNames`
(`get_label(sprite_type, slot)` / `format(sprite_type, slot)`). The
[animation atlas](../adr/0021-animation-resolution-is-per-state-one-atlas.md)
and the resolution viewer consume these labels to turn raw slot numbers
into reviewable verdicts.
_Avoid_: encoding labels inline in code or in `state_animations.json` /
`reaction_animations.json` — this file is the single source for label
meaning, separate from the per-state / per-react tables that use them;
treating absence of a label as a bug — many SEQ slots are unnamed in the
upstream wiki, and `AnimationNames.format` returns the raw slot number
unchanged when no label exists.

**Unit state**:
What a unit *is* — its durable identity. The fields: job (`current_job_id`),
gender (`is_female` / `base_stat_type`), and equipment (right-hand,
left-hand, head, body, accessory). Persists across [unit
activities](18-sprite-layers.md). Owned by `unit_progression` and modified
only through its mutators (`change_job`, `equip_item`, `unequip_item`),
which fan out via `equipment_changed` to refresh the sprite. One axis
of input to the [animation resolution map](18-sprite-layers.md); paired
with world state.
_Avoid_: treating [unit activity](18-sprite-layers.md) / facing / HP /
status as unit state — those are world state or transient runtime,
not identity; mutating unit state by writing
`unit_progression.equipment[slot] = …` directly (bypasses the change
signals the sprite update path listens on).

**World state**:
What's true *around* a unit right now — its situation. The axes that
feed the [animation resolution map](18-sprite-layers.md) alongside unit
state: the unit's current [activity](18-sprite-layers.md), facing, camera
quadrant, attack vertical (target tile above / equal / below), and
ability id being cast or charged. Some pieces live on the Unit object
physically (`facing_direction`, the activity it's playing) but
semantically they're what the unit is *doing*, not what it *is*.
_Avoid_: locating world state by storage location — facing lives on
the Unit but it's world state, not unit state; including durable
identity in world state (job / gender / equipment are unit state).

**Animation resolution map**:
The per-circumstance lookup that turns a unit's identity + situation into
the [SEQ slot](18-sprite-layers.md) triplet its [layers](18-sprite-layers.md) play:
`(unit state, world state) → (body_slot, wep1_slot, eff1_slot)`. Per-[unit
activity](18-sprite-layers.md) shape — each activity (IDLE, ATTACKING,
SPELL_CASTING, …) has its own resolver with its own parameter list,
because different activities need different inputs (ATTACKING needs
weapon + vertical; SPELL_CASTING needs ability id; IDLE needs neither).
Authority: ADR-0021 + ADR-0024. Runtime side: `AnimationResolutionMap`
(historical class name was `AnimationAtlas`, retired so "atlas" can mean
the on-disc [SPR](18-sprite-layers.md) / SHP sheets without ambiguity).
Data side:
`state_animations.json` + `weapon_animation_ids.json`. Each resolver
returns a `Resolution` whose `source` is `atlas` (real row hit),
`hardcode` (a transient migration shim still in code), or `miss` (no
row authored yet). Hand-authoring the map = filling in the rows.
_Avoid_: the bare word "atlas" — the SPR and SHP sheets are also
atlases, the resolution map is something else; calling the map's
inputs "state" without qualifier — the umbrella is split into
unit state (durable identity) and world state (situational); expecting
the map to pick the SEQ *file* — the job → [body sprite
ID](18-sprite-layers.md) → [sprite type](18-sprite-layers.md) chain picks the
file; the map picks the slot
inside it.

**Unit activity (Logical + Display)**:
What a unit is currently *doing*, modelled as two parallel projections
of one unified concept:

- **Logical activity** is what the *engine* thinks the unit is doing —
  the GPU compute shader's per-unit `U_STATE` field, with constants
  `LOGICAL_ACTIVITY_*`. Drives simulation decisions (can-attack,
  cast-on-arrival, victory freeze, opportunistic-attack gating).
- **Display activity** is what the *animation layer* should play —
  `DisplayActivity.Activity`, one input to the [animation resolution
  map](18-sprite-layers.md).

**Both halves are published together, as one kernel member** —
`ExMateriaSchema.UnitActivity.Display` and `.Logical`. They are generated from
the same YAML rows and exist only to be translated into each other, so a value
vocabulary two systems must agree on is the kernel's; splitting one half into an
addon and leaving the other in `Battle` would put one source of truth across a
package boundary (ADR-0217 dec. 8, following ADR-0196's argument for
`CellMarking`).

Both layers project the same unified concept (and share the same name
where there's no concept difference: `IDLE`, `WALKING`, `SPELL_CHARGING`,
`DYING`, `CELEBRATING`, `AWAITING_IMPACT`). Names stay distinct where the
*concept* differs:

- Logical splits movement three ways
  (`WALKING` / `WALKING_TO_CAST` / `APPROACHING`) for simulation reasons
  the animation layer doesn't care about — all three resolve to
  Display `WALKING`.
- Display splits acting two ways (`ATTACKING` / `SPELL_CASTING`) for
  animation reasons the engine doesn't care about — both come from
  Logical `ACTING`, with a `casting_ability_id > 0` predicate splitting
  the routing.

The mapping is declarative: `tools/activity_taxonomy.yaml` is the source
of truth, `tools/gen_activity_taxonomy.py` emits the GLSL constants, the
GDScript constants + DisplayActivity enum, the
`ActivityTranslator.translate(...)` dispatch shell, and the table below.
`CombatLoop._update_unit_animation` calls the translator with the
Logical value; the translator routes to the corresponding Display
authored event (direct activity assignment, semantic method call, no-op
delegated to a visualizer, etc.).
_Avoid_: calling either side a "state" — "state" is reserved for the
umbrella inputs (unit state durable identity vs. world state
situational); editing GLSL `LOGICAL_ACTIVITY_*` or
`GPUConstants.LOGICAL_ACTIVITY_*` directly — they regenerate from the
YAML; **editing `addons/exmateria_sprite_rig/state/DisplayActivity.gd`, the
`ActivityTranslator` dispatch, or the generated table below** — all five
artifacts regenerate from `tools/activity_taxonomy.yaml`, so a hand edit
survives until the next run and then vanishes with no diagnostic; conflating activity with [animation react](20-animation-react.md) —
react is a parallel-set rendering overlay sourced from the two
ROM-faithful trigger pathways (SEQ opcode 0xffde + effect keyframe
action_flags 0x40), entirely separate from any Logical activity. The
[PREEMPTIVE_COUNTER](21-combat-event-resolution.md) Logical state is the
one-tick Hamedo queued-counter-strike gateway, *not* a flinch-overlay
authority.

The diagnostic field `U_DBG_STATE_REASON` and its enum
`GPUConstants.REASON_*` (TIMER_EXPIRED, CAN_ATTACK, START_MOVING,
START_ATTACKING, etc.) record **why a unit's Logical activity
transitioned this tick**. They predate the activity-taxonomy rename and
still carry the legacy word "state" in their names — that is intentional
and not a renaming candidate: the `DBG_` prefix already scopes the field
to diagnostic / decision-recording use, the `REASON_*` constants are
self-scoped, and 73+ shader/GDScript reference sites mean the rename
cost dwarfs any clarity gain. Read "state" here as the Logical-activity
state machine; it does not conflict with the unit-state / world-state
umbrella split above.

🔴 **THE TABLE BELOW IS MACHINE-OWNED.** Everything between the two markers is
regenerated by `uv run python tools/gen_activity_taxonomy.py` from
`tools/activity_taxonomy.yaml` — it is one of **six** targets, alongside
`addons/exmateria_sprite_rig/state/DisplayActivity.gd`, `src/gpu/GPUConstants.gd`,
`src/gpu/shaders/combat_common.glslinc`, `src/gpu/ActivityTranslator.gd` and, since
#740, `addons/exmateria_schema/unit_vocabulary/UnitActivity.gd`.
**Edit the YAML.** A hand edit here is silently discarded on the next run.

That sixth target is why the ADR-0217 dec. 7 rename went through the generator and not
through a `sed`: the dispatch shell writes the qualified Display spelling into a host
file as a **literal string**, so the spelling is an output, not a call site. Two sites
in `gen_activity_taxonomy.py` produce four emitted lines, and they now read
`ExMateriaSchema.UnitActivity.Display.<X>` — **fully qualified, not through an alias**,
because a generated region that resolved through a hand-written `const` would break the
moment someone tidied that line away, with nothing red until the next regeneration
(ADR-0217 dec. 13).

<!-- === BEGIN GENERATED: activity-taxonomy (tools/gen_activity_taxonomy.py) === -->
| # | Unified | Logical | Display | Routing | Predicate | ADR | Notes |
|---|---|---|---|---|---|---|---|
| 1 | IDLE | IDLE | IDLE | resolver_variant | &mdash; | 0026 | Base IDLE. IDLE_LOW_HEALTH is Display-only (no Logical/GPU side): AnimationResolutionMap.resolve_for_activity dispatches to resolve_idle_low_health when the caller passes low_health=true, using the FFT-faithful threshold hp < max_hp / 4 (the AutoPotion trigger in stage_damage.glsl:187). Unit.update_animation precomputes the flag from unit_stats.current_hp / max_hp and passes it; the translator stays HP-agnostic. Explicit A.IDLE_LOW_HEALTH callers (animation viewer dropdown) still get the variant directly. |
| 2 | WALKING | WALKING | WALKING | visualizer | &mdash; | 0024 | Move visualizer drives the body activity from per-step writes; the translator is a no-op. |
| 3 | WALKING_TO_CAST | WALKING_TO_CAST | WALKING | visualizer | &mdash; | 0024 | Visualizer-driven, identical to WALKING; distinct logical so the engine can fire the cast on arrival. |
| 4 | APPROACHING | APPROACHING | WALKING | visualizer | &mdash; | 0024 | Unit-anchored MOVE; reposition without opportunistic attack. |
| 5 | RETREATING | RETREATING | WALKING | visualizer | &mdash; | 0301 | One tile directly away from the unit the retreat is aimed at, then a fresh gambit walk. Visualizer-driven like the other three moves; distinct logical because it must NOT re-arm on arrival (WALKING and APPROACHING both continue) and must NOT break off into an opportunistic attack (WALKING does). |
| 6 | USING_ITEM | ACTING | USING_ITEM | parameterized | `state.get('casting_ability_id', -1) >= 368 and state.get('casting_ability_id', -1) <= 381` | &mdash; | Item-use ACTING-split row. Item-ability ids live in [368, 381] (see combat_common.glslinc::is_item_ability). MUST appear before ATTACKING / SPELL_CASTING in the YAML so the generated if/elif ladder tests the item-range predicate FIRST; SPELL_CASTING's `> 0` predicate would otherwise also match item ids and shadow this row. Routing is parameterized: Unit.use_item(ability_id) sets active_ability_id and resolves the per-sprite-type USING_ITEM row from map.tres (TYPE1_ITEM_USE = 114 on humanoids). |
| 7 | ATTACKING | ACTING | ATTACKING | attack_handler | `state.get('casting_ability_id', -1) <= 0` | &mdash; | Weapon attack path (no active ability). Calls _start_attack_animation, which consults WeaponAnimationSelector. |
| 8 | SPELL_CASTING | ACTING | SPELL_CASTING | cast_deferred | `state.get('casting_ability_id', -1) > 0` | &mdash; | Cast path. Translator is a no-op; SPELL_CASTING is set later by CombatLoop._on_spell_cast_complete on the cast-complete signal so the cast animation can't be cut short by a state change. Predicate is intentionally strict greater-than: ability id 0 is the "(Nothing)" sentinel in effects.json, and the shader writes only -1 (cleared) or a real ability_id to U_CASTING_ABILITY_ID, so both 0 and -1 mean "no real cast" and must route to attack_handler. Preserve exactly. |
| 9 | SPELL_CHARGING | SPELL_CHARGING | SPELL_CHARGING | parameterized | &mdash; | 0024 | Parameterized activity; the resolver only fires through the semantic method, not via a bare activity write. |
| 10 | PREEMPTIVE_COUNTER | PREEMPTIVE_COUNTER | &mdash; | transient | &mdash; | 0033 | One-tick queued-counter-strike gateway. Today Hamedo (REACT_FIRST_STRIKE) is the only writer: stage_compute.glsl check_pre_damage_reactions sets U_STATE = PREEMPTIVE_COUNTER and U_TARGET = attacker when an IDLE defender with Hamedo is targeted. The next-tick state handler at stage_compute.glsl runs setup_attack_animation which writes U_STATE = ACTING, so the defender's counter-strike then plays as a normal ATTACKING animation under the existing attack_handler routing. Translator no-ops on this row; the defender shows the IDLE pose for the one gateway tick. No React overlay involvement -- the hit-flinch overlay lives on the two ROM-faithful trigger pathways (SEQ opcode 0xffde via CombatLoop._trigger_physical_reaction, effect keyframe action_flags 0x40 via CombatLoop._on_ability_react). Counter (REACT_COUNTER) does NOT use this state today (issue #49, faithfulness gap). See ADR-0033 and CONTEXT.md's Combat-event resolution cluster. |
| 11 | DYING | DYING | DYING | direct | &mdash; | &mdash; | Death animation playing. Display transitions to DEAD corpse via animation_lifecycle when the SEQ ends. |
| 12 | CELEBRATING | CELEBRATING | CELEBRATING | direct | &mdash; | 0026 | Terminal; OVERRIDES dead/cast latch in CombatLoop. The override guard stays at the CombatLoop call site - the translator only sees a normal direct routing. |
| 13 | AWAITING_IMPACT | AWAITING_IMPACT | AWAITING_IMPACT | direct | &mdash; | 0032 | Firer SEQ ended; projectile is in flight. Resolved through the map to the unit's IDLE SEQ pair. |
| 14 | IDLE_LOW_HEALTH | &mdash; | IDLE_LOW_HEALTH | none | &mdash; | &mdash; | Display-only, no Logical/GPU side. Auto-picked by AnimationResolutionMap as a variant of IDLE when unit_stats.current_hp < max_hp / 4 (see Unit.update_animation precomputing the low_health flag passed to resolve_for_activity). No translator entry; the IDLE row's resolver_variant routing is what produces this Display value. |
| 15 | DEAD_CORPSE | &mdash; | DEAD | animation_lifecycle | &mdash; | &mdash; | Terminal corpse. Reached from DYING when the death SEQ ends. |
| 16 | JUMPING | &mdash; | JUMPING | none | &mdash; | &mdash; | Cliff-hop air phase. NOT a separate Logical activity: cliff traversal stays under LOGICAL_ACTIVITY_WALKING end-to-end (see combat_common.glslinc::get_move_ticks branching on is_cliff_edge, with LANDING_TICKS folded into the total). Already wired: the move visualizer (GPUMovementVisualizer, driven by the WALKING / WALKING_TO_CAST / APPROACHING rows' visualizer routing in GPUVisualBridge._follow_visualizer) detects cliff vs flat in start_movement(), and get_activity(timer) returns JUMPING during both the wind-up and mid-arc phases. No GPU buffer change. |
| 17 | LANDING | &mdash; | LANDING | none | &mdash; | &mdash; | Cliff-hop touchdown phase. Sibling of JUMPING; same visualizer- driven Display choice during one continuous WALKING Logical state. LANDING_SEQ_FRAMES (18) is baked into the shader's cliff move-tick total via LANDING_TICKS (combat_common.glslinc); the visualizer derives the LANDING window from MovementTimingConfig.get_cliff_landing_ticks() and emits Display= LANDING in get_activity(timer) once `timer <= landing_ticks`. Already wired (see GPUKnightBreakTest log: `LANDING -> SPELL_CHARGING`). |
| 18 | GETTING_UP | &mdash; | GETTING_UP | none | &mdash; | &mdash; | Revival animation. Pure defer: Raise has no shader path today, so there is nothing to promote. Wiring lands with the Raise ability itself; reopen this row when that ability is implemented. |
<!-- === END GENERATED === -->

**Awaiting impact** (the activity and the state):
The firer's situation between the moment its attack SEQ ends and the
moment its projectile lands and damage applies. `LOGICAL_ACTIVITY_AWAITING_IMPACT`
is the GPU [Logical activity](18-sprite-layers.md) —
entered from `LOGICAL_ACTIVITY_ACTING` when SEQ playback ends with damage
still pending, exited on the timer-zero edge when the GPU writes the
damage and transitions to `LOGICAL_ACTIVITY_IDLE`.
`DisplayActivity.Activity.AWAITING_IMPACT` is the parallel parameterless
Display activity the firer performs during it; today every
sprite-type row in the [animation resolution map](18-sprite-layers.md) points
at the same SEQ pair as the unit's `IDLE` row, so the firer visually
returns to neutral while the bullet crosses. Covers ranged weapon
attacks and projectile spells (`projectile_frame >= 0`); melee, instant,
and adjacent-item paths fire damage inside `LOGICAL_ACTIVITY_ACTING` and
never enter the awaiting state. See ADR-0032.
_Avoid_: calling the situation "follow-through" — the firer isn't
following through, it's idle; the *projectile* is doing something. That
naming was retired in ADR-0032; pre-rolling the damage payload at fire
time and just "waiting it out" in `AWAITING_IMPACT` — damage is rolled at
landing so mid-flight buffs / debuffs on the target are honoured (the
semantic ADR-0032's "no pre-roll" line preserves); modelling the
projectile as a separate GPU entity (the B2 shape ADR-0032 rejected — FFT
can't multi-shoot per firer, so the firer's unit struct is enough to
carry the pending state); routing the damage write through a CPU
`projectile_landed` callback (the
[battle-state authority](02-combat-buffer-layout.md) violation that put
ADR-0028 into supersession).

**Celebrating / Victorious** (historical):
Pre-PR2 (issue #44) the codebase split this row as `STATE_VICTORIOUS`
(GPU) vs `CELEBRATING` (CPU) on the "thing vs doing" pun. With the
unified Logical/Display vocabulary the names collapse to `CELEBRATING`
on both layers — the asymmetry was historical drift, not a concept
difference. See the [activity taxonomy table](18-sprite-layers.md)
for the current shape.

**Unit Animation Viewer**:
The authoring scene that exercises the [animation resolution
map](18-sprite-layers.md). Loads a single fully-reconfigurable unit
(1-unit friendly roster, 0 enemies) and surfaces controls for both
unit state (job, gender, equipment) and world state ([unit
activity](18-sprite-layers.md), facing, attack vertical, camera quadrant,
ability id), then shows the resolved BODY / WEP1 / EFF1 slots in a
readout. Used to hand-author and visually verify resolution rows.
_Avoid_: treating it as a debug overlay over a real scene — it owns
its own scene and its own roster seed at `assets/roster/`; using it
to test playback timing — it tests resolution, not playback (the
[animation clock](19-animation-playback.md) is the playback authority).

**EVTCHR (event sprite sheets)**:
Cinematic full-body character poses, distinct from each unit's
TYPE1.SHP combat atlas. Source: `EVTCHR.BIN` (137 segments, each
28KB: 16 BGR555 palettes + 256×200 4bpp pixel page). Loaded into
VRAM by event-script opcodes `{58}` (disc→RAM) and `{59}` (RAM→VRAM);
see `research/working_documents/scenario_1_captures/evtchr_load_save_decode.md`.
Rendering: the per-unit `body_palette_row` (set from the ENTD slot's
`palette` byte, the same field combat uses per ADR-0022) selects
which SPR palette row the EVTCHR pixels sample. EVTCHR-embedded
palettes are authoring references, not the runtime source. The
`{7F} EVTCHRPalette` opcode is a per-unit override that swaps in an
EVTCHR-embedded palette row — used for special cases like bleeding
(Talcall, FFTHacktics); not modeled today. Walker:
`ScenarioVM.CinematicWalkState` walks an anim's bytecode (2-byte
entries per `FUN_80084818` script-VM), dispatching each emitted
`frame_byte` to TYPE1.SHP (`< 0xD2`) or EVTCHR (`>= 0xD2`) per
the 0xD2 split in `cinematic_frame_offset_decode.md`.
_Avoid_: treating EVTCHR-embedded palettes as the live render
source (V17 framing) — V14 (2026-06-27) settled this: the unit's
SPR palette stays bound throughout cinematics.
