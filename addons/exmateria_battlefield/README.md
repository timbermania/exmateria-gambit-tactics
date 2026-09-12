# ExMateria Battlefield

The tactical lattice and what stands on it. **Extraction #3** of the
`godot-learning` refactor — 46 files, 10 directories, moved here at loop pass 6
([ADR-0184](../../docs/adr/0184-the-address-lands-and-arm-1s-debt-is-named-rather-than-hidden.md)).
The register that says the *right* files moved is
[`docs/EXTRACTION-3-MOVE-MANIFEST.tsv`](../../docs/EXTRACTION-3-MOVE-MANIFEST.tsv),
enforced by `tools/check_move_manifest.py` (ADR-0168).

| directory | files | what it is |
|---|---:|---|
| `cursor/` | 12 | the tile cursor: its scene, controller, bob, compositor and four shaders |
| `terrain/` | 7 | terrain and skirt geometry, the visible-angle cull, the geometry index |
| `overlay/` | 8 | the tile overlay — config, compositor, colour, the highlight publish, and the fold/opaque shader pair |
| `texturing/` | 5 | the indexed-colour atlas, palette generation, texture animation, the DDA illuminator |
| `camera/` | 4 | the isometric camera, its scene, the deadzone overlay, the screen background |
| `assembly/` | 4 | `MapComposer` and the state/lighting/scene-tree machinery it drives |
| `lattice/` | 4 | `Lattice` (the port), the unnameable `Tile` store behind it, `Tile`, `MapConstants` |
| `doodad/` | 2 | map props |
| `debug/` | 2 | the grid overlay and its shader |
| `pathfinding/` | 1 | the cutscene walk-to pathfinder |

## What it publishes

**30 `class_name`s and two scenes — and zero autoloads.**

⚠️ This line read **28** and was already stale by one before loop pass 6 measured
it at 29; the lattice seam below is net +1 (`Lattice` and `TileHighlights` in,
`TerrainIndex` out). 🔴 It then drifted to **31** in the tree while still reading 30,
and pass 12 ([ADR-0206](../../docs/adr/0206-the-cursor-ships-as-a-rig-and-two-implementation-names-lose-their-class-name.md))
made it correct BY ACCIDENT: `CursorRig` in, `TileCursor` and `CursorController` out,
net −1. Nothing enforces this number — `check_lattice_publish` deliberately does not
parse this sentence, because a source assertion that matches its own prose stays green
through the deletion of the line it guards — so treat it as a claim with a date on it
and re-count before citing it:
`grep -rh '^class_name' addons/exmateria_battlefield/ --include='*.gd' | wc -l`.

The zero is not an omission. `SkirtConfig`, `TileOverlayConfig` and `TileOverlayCompositor` were
host `project.godot` autoload entries until #564 ([ADR-0183](../../docs/adr/0183-the-published-autoloads-were-named-from-inside-and-that-half-was-uncounted.md))
re-pointed them onto `class_name`s, precisely because **an addon cannot register
an autoload** — that is a `project.godot` entry the host writes, and
`addons/exmateria_render/plugin.gd` states the rule and declines to work around
it. An addon whose public surface is autoloads is an addon nobody can install.

### The two host-beat flags (2026-09)

**`CursorRig.input_enabled` and `PlayerCamera.input_enabled`** were added for the
turn-open beat (`docs/TURN-OPEN-BEAT-DESIGN.md`), together with
**`CursorRig.move_to(cell)`**. They are written here because a published surface that
grows quietly is the failure the four registers exist to catch, and none of them can
see a new member — every one scores *couplings*, not *size*.

🔴 **The battlefield accepts device input on TWO surfaces, not one, and a host that
silences one has silenced half.** `camera_up/down/left/right` are
`TileCursor.CURSOR_ACTIONS` — they walk the CURSOR, and
`PlayerCamera._execute_translation` returns immediately unless the `camera.free_camera`
debug override is on, so they pan nothing in normal play. Q/E and F are
`PlayerCamera._input`'s alone. That is why there are two flags and not one, and why the
cursor rig cannot be given a member that covers both: the rig is handed its camera as an
untyped constructor argument and does not keep it.

⚠️ **The camera flag is reached BY NODE PATH, which is the install term** — the same
unscored channel `PlayerCamera` already sits in (`check_lattice_publish` reads 0 for it
while 107 `.tscn` files instance it by path). The cursor flag is reached through
`CursorRig`, which is a published `class_name` and IS scored. Two members of one feature,
on two different sides of the register — say which, the way ADR-0202 dec. 1 says to.

🔴 **A camera TAKEOVER is not a substitute for either flag**, and it looks like one:
`TileCursor._input_allowed()` is already false in TAKEOVER mode, so "put the camera in
takeover for the duration" reads as a free deafen. It is not — `PlayerCamera._process`
returns early in any non-CURSOR mode, which skips `_execute_cursor_follow`, so the camera
would not travel at all. A beat expressed that way silences the input and deletes the
animation it exists to show.

It also publishes **three signals and two replay accessors**, which is what
#589's inversion cost and bought: `TileCursor.cursor_stepped` (the PLAYER moved
the cursor — *not* `cursor_moved`, which also fires from `move_to`),
`MapComposer.map_material_created` + `map_materials()`, and
`MapComposer.map_gradient_resolved` + `map_gradient()`. Each map seam has BOTH a
replay and a signal because neither alone is correct: the geometry builder is
constructed inside `_build_map`, so nothing outside can subscribe before the
first materials exist, and materials are created lazily on every `rebuild_mesh`,
so a one-time drain goes stale (ADR-0186 dec. 6).

The published interface is narrower than the 30: ADR-0157 dec. 3 measured that
**`Tile` and `TerrainIndex` carry 92 of the 131 inbound lines**, all from
`Battle`, and that fifteen of `src/map/`'s eighteen files were named by nothing
across a system boundary at all.

### The lattice seam (loop pass 6)

Two of those names are now one port and one publish, and one name went away:

- **`Lattice`** — the terrain PORT, four members (`terrain_at` ·
  `world_position_at` · `is_cliff_edge` · `all_cells`), answering with
  `TerrainCell` VALUES so a `Tile` never crosses
  ([ADR-0164](../../docs/adr/0164-the-lattice-ships-as-one-port-and-one-publish-and-tile-never-crosses.md)
  dec. 1/2,
  [ADR-0192](../../docs/adr/0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md)).
  Take it as `var lattice: Lattice = map.lattice` — one untyped step at the seam,
  typed from there on, because criterion 1 forbids publishing `MapComposer` and
  `$ProceduralMap` infers `Node`.
- **`TileHighlights`** — the highlight PUBLISH, keyed by `Vector2i`
  ([ADR-0193](../../docs/adr/0193-the-highlight-is-a-publish-with-an-address-and-the-sentinel-belongs-to-the-schema.md)).
- 🔴 **`TerrainIndex` no longer has a `class_name`.** The store that holds the
  `Tile` nodes is `preload`ed by the three addon files that build, fill and wrap
  it and is **structurally unnameable** from outside — criterion 1 scans
  `class_name`s, so a door on a class nobody can name is not a door
  (ADR-0192 dec. 4).

Both objects are created once and REBOUND on every map load rather than
replaced, so a consumer that took its handle at boot keeps answering for the map
on screen (ADR-0193 dec. 4).

## Goal #5's three arms all read 0 — and that is not the same as "isolated"

`tools/check_addon_portability.py` runs five arms over this directory and every
one of them is clean. **`ARM1_BURN_DOWN` (ADR-0184 dec. 4) is EMPTY**, which is
the first time since the addon was created; the six lines it carried are paid at
[#642](https://github.com/timbermania/fft-monorepo/issues/642).

| arm | fails because… | subject | state on `main` |
|---|---|---|---|
| 1 | the addon **reaches** one of the eleven systems | `.gd` | **0** — this change |
| 2 | one file does not **parse** — a host `[autoload]` name | `.gd` | **0** (ADR-0187) |
| 4 | a shader does not **compile** — a host `[shader_globals]` name | `.gdshaderinc` | **0 declare lines** (ADR-0190 / [#626](https://github.com/timbermania/fft-monorepo/issues/626)). The residual **6-name** block is provided by `addons/exmateria_platform/plugin.gd` at enable time (ADR-0220 dec. 1/2) and stated once, in `addons/exmateria_platform/README.md`; enforcing arms 4b and 4c hold the zero |

Both #642 legs were the same shape — a thing that looked like a dependency and
was not:

- `TileOverlayColor` was `Effects`' by its directory and by nothing else. It is
  the stateless CPU mirror of this addon's own `overlay/tile_overlay.gdshaderinc`,
  zero outbound edges, and its only two consumers were
  `overlay/TileOverlayCompositor.gd` and its own test. It now sits beside the
  shader it mirrors, at `overlay/TileOverlayColor.gd`.
- `lattice/Tile.gd`'s occupancy — `reserved_by`, `try_reserve`, `release`,
  `is_blocked`, `became_available` — was **deleted, not inverted and not
  retyped** (ADR-0166 dec. 2). Retyping was rejected *by name* in that ADR as the
  cheapest-looking move that every instrument on this map would have scored as
  the fix.

🔴 **Arm 1 at 0 does not close the lattice.** Arm 1 scores **outbound** reach and
nothing else — `score_goals.mechanical(goal=5)` has no inbound term at all
(ADR-0164 dec. 4's ⚠️). The inbound side is scored by four separate registers, and
as of ADR-0209 every one of them reads 0:

| criterion | register | reads |
|---|---|---|
| 1 — an addon `class_name` named from the host without being published | `tools/check_lattice_publish.py` | arm 1 **0 / 0**; arm 3 5 names over 44 sites, all named, none stale |
| 2 — a lattice call site whose receiver is not provably annotated `Lattice` | `tools/check_lattice_ports.py` | **CLEAR** |
| 3 — a `Tile` in a RETURN or SIGNAL-PAYLOAD position | `tools/check_lattice_doors.py` | **CLEAR** |
| 4 — a host file naming a path into this addon | `tools/check_lattice_scene.py` | **0 sites**, 3 declared mounts |

Everything this section used to list as owed is built: the `Lattice` port
(`lattice/Lattice.gd`), `TerrainCell` (in the kernel), occupancy holder 4 as
`MovementComponent.current_cell: Vector2i` (ADR-0166 dec. 3), and both registers —
the duck-typed-door one is criterion 2 above (ADR-0170 dec. 5, built by ADR-0192)
and the Tile-door one is criterion 3 (ADR-0166 dec. 4).

Those four are **axis A**. Axis B — installability — is `tools/check_addon_install.py`,
**CLEAR at 0 / 0**. Neither axis may be reported as the other (ADR-0202 dec. 1), so
say both numbers.

🔴 **Four zeroes are still four claims about TEXT.** Every register above scores what
a file *spells*. None can see inheritance, a duck-typed call whose annotation lies, or
a runtime reach into host content — and the last of those is not hypothetical: the
stranger rig has caught a defect that all five static instruments, and every passing
assertion in the test itself, called clean.

✅ **All three registers now exist.** `tools/check_lattice_ports.py`
(criterion 2, [ADR-0192](../../docs/adr/0192-the-register-goes-first-because-the-port-erases-its-own-baseline.md))
reads 0/0/0 across its three arms; `tools/check_lattice_doors.py` (criterion 3,
ADR-0166 dec. 4) reads **0 of a target 0** with an empty `DOOR_BURN_DOWN` —
nine rows, four closed by the pass-6 port and five by
[ADR-0195](../../docs/adr/0195-the-cursor-publishes-a-coordinate-and-criterion-3-closes.md),
which narrowed `TileCursor`'s four `cursor_*` payloads to `(grid_pos: Vector2i)`
and made `active_tile()` addon-internal. No host can hold a lattice node.
🔴 **Criterion 1 has a guard as of loop pass 8 and is the one still OPEN** —
`tools/check_lattice_publish.py`
([ADR-0196](../../docs/adr/0196-the-marking-belongs-to-the-schema-and-a-respelling-is-never-the-reason.md)),
built BEFORE the enum it grades moved, reading **31 sites over 14 rows** on its
first run and **21 over 12** now. `Tile`'s ten — every one a
`Tile.HighlightType.X` — closed in the same pass: the marking became
`CellMarking.Kind` in the shared schema, after ADR-0193 dec. 2 and ADR-0195
dec. 6 both declined the move and both priced a structural blocker as a
re-spelling count.

What is left is **`TileCursor` 13 and `CursorController` 8**, deferred by
ADR-0196 dec. 8 to the pass that closes criterion 1 — four host scenes call
`CursorController.new()`, which is a construction seam and an interface
question, not a rename. ⚠️ The register scores **type references**: it reads 0
for `PlayerCamera` while 107 `.tscn` files instance it by path. That is the
**install** term, printed and unscored, and no ADR rules on it.

⚠️ A raw `grep -rn '\bTile\b' src` prints **41**, and every prior handoff quoted
that as the debt. Ten were type references. The rest are prose, trailing
comments, `"""` docstring bodies and NodePath strings.

**`autoload_reach.py Battlefield` now reads `dec. 2 counts 0`** — the four rows
that were [ADR-0157](../../docs/adr/0157-extraction-3-is-battlefield-and-its-interface-is-two-names-one-system-reaches.md)
dec. 2's *scored* outbound debt, enumerated by file and line **before** this
system was chosen as extraction #3, are paid ([ADR-0186](../../docs/adr/0186-the-publish-already-existed-on-the-wrong-half.md)):

- **#590** — the `psx_camera_angle` mirror left `Debug` for
  `PSXDisplay.live_camera_angle`, beside the five globals that port already pushed.
- **#589** — the three push lines inverted. The addon publishes the values and
  `src/scenes/BattlefieldWiring.gd` (booked `assembler`, so no system's reach
  count moves for it) hands them to `Effects` and `Audio`.

`Tile` never crossing (ADR-0164 dec. 2 — the lattice answers with **values**)
and holder 4 becoming `current_cell: Vector2i` are still a real interface design
and still owed; they are the paragraph above, and no arm here scores them.

**It parses standalone now.** It did not at `6d63f6fbe`: 62 lines named a host
autoload, every one of them a *port* — `Tune` 59 and `PSXDisplay` 3. A port reach
is free on arm 1 and was still an arm-2 break, because the two arms ask different
questions: arm 1 is about the TIER a symbol belongs to, arm 2 is about who creates
the NAME, and only a `project.godot` `[autoload]` block creates an autoload name
(ADR-0175). [#588](https://github.com/timbermania/fft-monorepo/issues/588)
re-pointed all 62 onto the two port signatures in
`addons/exmateria_platform/` — `TunePort` and `DisplayPort`, soft-bound to their
singletons by node path, and published on `ExMateriaPlatform` since ADR-0212
dec. 1 (this addon aliases them back to their bare spellings, one line per file)
([ADR-0187](../../docs/adr/0187-the-port-is-two-signatures-and-sixteen-of-the-seventy-eight-were-already-inside-it.md)).
**Arm 2 now prints no rows at all.**

The cost is paid in the open rather than pocketed: arm 5 went 69 → 131 lines, and
the 62 new ones are this addon naming a sibling addon's published type. That is a
**hard dependency on `exmateria_platform` being installed** — an addon-presence
dependency, which is vendorable, in place of a host-project-configuration one,
which is an install step. It was already true of `PsxNum` and of both
`.gdshaderinc`.

**Its shaders compile standalone too, given the host block.** They did not until
[ADR-0190](../../docs/adr/0190-a-global-uniform-earns-its-host-entry-by-having-a-writer.md)
(#626): four `.gdshaderinc` lines here *declared* `[shader_globals]` names, and
declaring is not enough — the name must exist in the consuming project's
`[shader_globals]` block or the shader draws WRONG, silently. Outside the editor the
engine does not validate global uniforms at all, so there is no compile error to
catch it: the name reads its type's zero and warns only at draw time
(ADR-0238, correcting ADR-0169 dec. 4).

**This addon now declares zero**, and `check_addon_portability.py` **arm 4b**
enforces it: only a non-system addon may declare a `global uniform`. Three moved
to declaration seams in `addons/exmateria_platform/display_port/` — the port that
*pushes* them — and the fourth, `visible_angles_cull_mode`, turned out to have **no
CPU writer anywhere in the tree** and is a `const` now.

What remains is a six-name block, stated once in
[`addons/exmateria_platform/README.md`](../exmateria_platform/README.md). The
consuming project no longer declares it by hand: since
[ADR-0220](../../docs/adr/0220-the-addon-that-declares-a-global-uniform-provides-it.md)
dec. 1 the addon that DECLARES a `global uniform` provides it, so
`exmateria_platform/plugin.gd` writes all six at enable time and arm 4c enforces
that pairing. The dependency itself is still documented-and-accepted,
deliberately: `psx_camera_angle` changes every frame and is read by every map
surface.

⚠️ **This addon used to provide those five, and shedding them is the layering fix,
not a retreat.** They are declared in the port and were provided from here, so a
project installing fork + kernel + port and *not* this addon got the declarations
and none of the values — which is precisely what left `exmateria_sprite_rig`
uninstallable. This addon's own install debt does not move (`check_addon_install`
arm 3, still 0): the port is inside this subject's install target too.

**One remains: the six lattice reach lines.** Goal #5 fails three ways for a
directory — it does not PARSE, it REACHES a system, its shaders do not COMPILE —
and two of the three are now closed (ADR-0187, ADR-0190). Arm 1's burn-down is the
last, and it is a real interface design rather than a wiring change.

## Dependencies it is allowed to have

`addons/exmateria_schema/` (the kernel — `ExMateriaSchema.ColorStack`,
`.ColorRecipe`, `.DepthMode`, `.Fold`, all six published on one façade since
ADR-0212 dec. 1, which is why the files under `assembly/`, `cursor/`, `lattice/`
and `overlay/` alias them back to their bare spelling) and
`addons/exmateria_platform/` (the ports —
`PSXDisplay`, `pixel_aspect`, `psx_dither`). ADR-0139 dec. 9 and dec. 12 make those
two the set a portable addon may name; a **system** is not in it, which is what
arm 1 above is measuring.

## Content the host must supply

**This addon ships no ROM-derived content, and it never can.** The map tree, the
hand-crafted doodad tree and the `RANGETILE` cursor/overlay atlas are extracted from a
disc the repo does not redistribute; `assets/maps/` is gitignored outright. ADR-0202
dec. 5 calls this Class B and rules that the *hardcoding* was the defect while the
*dependency* is a legitimate contract — so the addon stopped naming `res://assets/` and
takes a search root from the host instead.

Declare it in the consuming project's `project.godot`:

```
[exmateria_battlefield]

content_root="res://assets/"
```

`BattlefieldContent` resolves every subpath against that root:

| subpath | what needs it |
|---|---|
| `maps/` | `MapComposer` (scene manifests, palette + texture sidecars), `DoodadLibrary` |
| `doodads/` | `DoodadLibrary` |
| `sprites/textures/RANGETILE.tga` | `Tile`, and the cursor's opaque material |
| `sprites/textures/RANGETILE.palette.tga` | `Tile`, `TileOverlayCompositor`, the cursor material |
| `sprites/textures/RANGETILE.json` | `TileOverlayConfig` (seeds the tile UV crop) |

**A project that omits the key gets one `push_error` naming it**, not a silent empty
load — that legibility is dec. 5's stated goal, and it is why the setting's default is
empty rather than `res://assets/`. A default pointing at the host's own layout would
also have left the literal inside an addon file, where the install register still scores
it.

⚠️ **`range_tex` / `range_palette` are bound at runtime, not in the `.tres`.**
`cursor/tile_cursor_opaque.tres` deliberately carries no `[ext_resource]` for either.
An `ext_resource` resolves at **load** time, before any code runs, so no setting can
reach one — re-adding either re-opens the install register's Class B rows *and* the
stranger rig's `known_failures.tsv`. `TileCursor._bind_range_textures()` supplies them.

## What enabling the plugin installs

Everything above is content the host must **supply**. This section is the other half: the
eight `project.godot` names the addon **provides for itself** when you enable it in
*Project → Project Settings → Plugins*. ADR-0203 dec. 1 draws the line — an addon provides
what it can author (a name and a default) and injects what it cannot (ROM-derived content).

⚠️ **It was thirteen.** The five `shader_globals/` entries moved to
`addons/exmateria_platform/plugin.gd` at ADR-0220 dec. 2, because that is the addon whose
`.gdshaderinc` files DECLARE them. Enable that plugin too — the port is in this addon's
install target, so nothing here regressed, and a project that installs the port without
this addon now gets its globals as well.

`plugin.gd` writes, at enable time, only the names the project does not already hold:

| channel | names |
|---|---|
| `input/` | `camera_up`, `camera_down`, `camera_left`, `camera_right`, `rotate_camera_cw`, `rotate_camera_ccw`, `unit_inspect`, `cursor_confirm` |

The `shader_globals/` row is deliberately absent: this addon declares no `global uniform`
and therefore provides none (ADR-0220 dec. 1). The six live in the port's README.

The input defaults reproduce this repo's bindings exactly — WASD + arrows + D-pad for the
four pan steps, Q/E for the two yaw steps, Tab for inspect, Enter/KP-Enter/pad ○ for
confirm. `cursor_confirm` is **not** `ui_accept`: Godot's default binds Space, and on the
battlefield Space starts the battle.

Disabling the plugin removes exactly the names it added, and nothing a project declared on
its own.

### Install order matters, and the first enable is noisy

Godot imports and **compiles this addon's shaders when the project opens**; the plugin is
enabled afterwards. So the very first enable in a bare project logs shader compile errors
for the six `global uniform`s that did not exist yet. They are real and they are transient:

    copy the three addons in  →  open the project  →  enable the plugins  →  reload

⚠️ *Plugins*, plural, since ADR-0220 dec. 2: the shader globals come from
`exmateria_platform`'s plugin and the input actions from this one.

After the reload the globals are declared and the shaders compile. ADR-0203 dec. 6
documents this rather than fixing it — the fix would be an addon that writes settings
before it is installed.

⚠️ **This repo does not exercise any of it.** `godot-learning/project.godot` has no
`[editor_plugins]` section, so no `plugin.gd` in this package has ever had `_enter_tree`
called, and the host keeps declaring all of these names itself. Booting the game therefore
verifies nothing about the provide. The oracle is
`tests/BattlefieldProvidesTest.gd`, which calls `plugin.gd`'s `provide_into()` directly
against an inspectable settings surface and asserts every name lands with its real
bindings (ADR-0203 dec. 4). `addons/exmateria_platform/tests/PlatformProvidesTest.gd` is
the same oracle for the six shader globals (ADR-0220 dec. 5).
