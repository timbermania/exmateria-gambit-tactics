#!/usr/bin/env python3
"""Assign every hand-written source file to one blueprint bucket, and report the rest.

Proof instrument for godot-learning/docs/BLUEPRINT-AUDIT.md. Deliberately has
NO catch-all: anything the rules do not name falls out as UNCLASSIFIED, which is
the finding. Run from the package root.

    python3 tools/classify_blueprint.py [--list-unclassified]

WHAT IT WALKS — ADR-0131 dec. 3 as extended by ADR-0146 dec. 5: hand-written
`.gd` **or shader source** under `src/`, `assets/` AND the addons this refactor
itself produces (`addons/exmateria_schema/` today; each extracted system as it
lands). `addons/exmateria_sound/` is NOT walked — it is a vendored copy and its
baseline row is read from the canonical package (ADR-0131 dec. 8).
Four shader extensions, not two: `.gdshader`,
`.gdshaderinc`, `.glsl` and `.glslinc`. ADR-0141 dec. 4's census globbed the
first two and so read 86 files / 6,290 lines; the compute half — ten `.glsl`
stages plus two `.glslinc` headers under `src/gpu/shaders/`, 6,081 lines — is
**48% of the shader body** and was invisible to it. Godot sidecars (`.uid`,
`.import`) are generated and are not source; they are not walked.

Exclusion happens at REPORT time, never at walk time (ADR-0131 dec. 4): a
generated file must be *recognised as generated*, so `generated`, `content` and
`tests` are still classified, still printed, and only then subtracted for the
baseline. `tests` is `addons/<name>/tests/` — an addon-owned test ships inside
the addon (ADR-0194 dec. 2) and is therefore inside a walk root, unlike the
host's `tests/`, which is outside the walk by construction.
"""
import sys, pathlib, collections

# ADR-0131 dec. 3. Sidecars (`*.uid`, `*.import`) are generated, not source.
SOURCE_SUFFIXES = (".gd", ".gdshader", ".gdshaderinc", ".glsl", ".glslinc")
SHADER_SUFFIXES = (".gdshader", ".gdshaderinc", ".glsl", ".glslinc")

SYSTEMS = ["Battlefield", "Battle", "Character Catalogue", "Sprite Rig",
           "Effects", "UI", "Audio", "Cutscene", "Campaign", "Render", "Debug"]
OTHER = ["assembler", "schema", "content", "generated", "infrastructure", "platform",
         "tests", "DELETE"]

# (matcher, bucket). First match wins; order matters. `dir/` = prefix, else exact stem.
RULES = [
    # --- ADR-0194 dec. 9: an addon-owned test is inside a walk root ----------
    # `tests/` is kept out of the line census *by construction* — it is simply
    # not a walk root. `addons/<name>/tests/` IS inside one, so a test moved
    # into the addon it guards would be walked and booked as production source:
    # +1,796 lines onto a 169,761-line baseline, read as the refactor adding
    # code it did not write. ADR-0131 dec. 3/4 forbids the obvious fix — a
    # walk-time skip — because a file must be *recognised* before it is
    # subtracted, so these rules book the tests to their own bucket and
    # `EXCLUDED` subtracts it at report time, exactly as `content` is handled.
    #
    # These four must stay AHEAD of their addon's own prefix rule below, or
    # they are dead and their tests book to `schema` / `Render` / `Battlefield`
    # / `platform` silently. `check_blueprint_walk.py` check 5 asserts the
    # ordering, and asserts one rule exists per addon walk root — the shadow
    # here is directory-over-directory, which check 2 does not see.
    #
    # They are PROVISIONED: on the day they land nothing matches them, which is
    # the point (dec. 9 — *"this lands before any test moves"*; move first and
    # the very first commit corrupts the frozen register). check 2 exempts them
    # from its DEAD DIRECTORY RULE arm for that reason and check 5 replaces it.
    ("addons/exmateria_schema/tests/", "tests"),
    ("addons/exmateria_render/tests/", "tests"),
    ("addons/exmateria_battlefield/tests/", "tests"),
    ("addons/exmateria_platform/tests/", "tests"),
    ("addons/exmateria_sprite_rig/tests/", "tests"),
    ("addons/exmateria_almanac/tests/", "tests"),
    ("addons/exmateria_catalogue/tests/", "tests"),

    # --- the shared kernel is one directory (ADR-0139 dec. 9, built in prologue
    # pass 6 / ADR-0146). Four hand-written path rules collapsed to this prefix,
    # so adding a file to the kernel now shows up in the classifier diff by
    # itself and dec. 3's admission gate is a line in a review, not a convention
    # someone has to remember.
    # ...but the addon's Godot scaffolding realises no schema, so by dec. 3's own
    # rule it is not a member and must not sit in the bucket that IS the
    # membership list. One exact rule ahead of the prefix keeps `schema` equal to
    # ADR-0139 dec. 11's table; every OTHER new file under the addon still trips
    # the prefix and shows up as a kernel admission in the diff. ADR-0146 dec. 6.
    ("addons/exmateria_schema/plugin.gd", "infrastructure"),
    ("addons/exmateria_schema/", "schema"),

    # --- extraction #1's output (ADR-0147). The same two-rule shape, for a
    # different reason: `schema`'s bucket IS its membership list, so scaffolding
    # must be kept out of it; `Render`'s is just a system. `plugin.gd` is booked
    # `infrastructure` anyway, because an addon's editor entry point is host
    # machinery in EVERY addon and not the system's 8th file — which keeps
    # `Render` equal to ADR-0147 dec. 1's table. The scaffolding's lines are
    # reported as `infrastructure`, not absorbed silently.
    ("addons/exmateria_render/plugin.gd", "infrastructure"),
    ("addons/exmateria_render/", "Render"),

    # --- extraction #3's output (ADR-0184), and the `platform` tier's address
    # (ADR-0169 dec. 1). Same two-rule shape again. The `Battlefield` pair is
    # #561 dec. 2's collapse arriving: ~27 hand-audited per-file rules and one
    # `src/map/` directory rule are GONE, replaced by this location assertion.
    # That trade is deliberate and it has a cost the manifest pays — after the
    # collapse the census RESTATES where files were put rather than measuring
    # what `Battlefield` is, so a file wrongly moved in reads as a win on two
    # instruments. `docs/EXTRACTION-3-MOVE-MANIFEST.tsv` plus
    # `tools/check_move_manifest.py` arm 3 are the register that says the RIGHT
    # files moved (ADR-0168); nothing in this file can.
    ("addons/exmateria_battlefield/plugin.gd", "infrastructure"),
    ("addons/exmateria_battlefield/", "Battlefield"),
    # `platform` is a TIER, not one of the eleven, so there is no membership list
    # for scaffolding to corrupt — but `plugin.gd` is booked `infrastructure`
    # here for the reason it is booked that everywhere: an addon's editor entry
    # point is host machinery in EVERY addon, and absorbing it would make the
    # tier's line count disagree with ADR-0169's table.
    ("addons/exmateria_platform/plugin.gd", "infrastructure"),
    ("addons/exmateria_platform/", "platform"),

    # Extraction #4's addon, seeded by #742 with the façade, `plugin.gd` and the
    # SEQ opcode vocabulary. 🔴 THE WALK ROOT LANDS WITH THE FOLDER, NOT WITH THE
    # POPULATION. `AnimationOpcodes.gd` booked `Sprite Rig` at
    # `src/animation/`, and an addon root outside `WALK_ROOTS` is not walked at
    # all — so without this the move would DELETE a file from the census rather
    # than relocate it, and the blueprint would read the extraction as progress
    # it had not made. Measured both ways before landing: the old path classifies
    # `Sprite Rig`, the new one classified `None`.
    ("addons/exmateria_sprite_rig/plugin.gd", "infrastructure"),
    # 🔴 A MOVE RELOCATES A FILE; IT DOES NOT RE-BOOK IT (#744, 2026-09-01). The
    # exerciser ships inside the addon (ADR-0217 dec. 4/10) but is still per-scene
    # wiring, which is what `assembler` books -- and `assembler` is not one of the
    # eleven, so no system's reach count moves for it. Under the prefix rule below
    # it would silently become `Sprite Rig`, and the viewer's own outbound reaches
    # would land on the rig it exercises. That is the same failure the walk-root
    # note below guards in the other direction: the census must measure the move,
    # not be moved BY it. This rule is ABOVE the prefix rule because first match wins.
    ("addons/exmateria_sprite_rig/viewer/SequenceViewer.gd", "assembler"),
    ("addons/exmateria_sprite_rig/", "Sprite Rig"),

    # Extraction #6's addon (ADR-0257 pass 1, ADR-0262 pass 2, pass 3 = the move).
    # 🔴 A MOVE RELOCATES A FILE; IT DOES NOT RE-BOOK IT (#744). All ten members
    # booked `Character Catalogue` before the move -- eight by the retired
    # `("src/characters/", ...)` prefix, `AllTemplatesSeeder.gd` by its own exact
    # row (ADR-0135 dec. 9), and `RosterDebugView.gd` through the `src/debug/`
    # branch's DEBUG_OWNER "Roster" fragment. The prefix row below reproduces all
    # ten, and both retired rows are deleted rather than left dead: a rule whose
    # subject has moved matches nothing and `check_blueprint_walk.py` cannot see
    # a dead RULES row the way it sees a dead DEBUG_OWNER one.
    #
    # DEBUG_OWNER's "Roster" fragment STAYS, and #1070 is where the stated reason
    # changed rather than the row. It used to read "`RosterViewDebugPanel.gd` is
    # still in `src/debug/`" (ADR-0262 dec. 8 -- dead code, ticket #1070). #1070
    # DELETED that file, and the fragment's remaining subject is
    # `RosterUniverseDebugPanel.gd`, which is booked `Character Catalogue` by this
    # fragment ALONE -- it is in no DEBUG_EXACT row.
    #
    # 🔴 #1070's own definition of done asked for this row to be RETIRED with the
    # file, on the reading that the panel was the fragment's only subject. It is
    # not, and both arms were run rather than argued: with the row, 742 files /
    # 0 unclassified / rc=0; without it, `check_blueprint_walk` reds UNCLASSIFIED
    # and the pre-flight aborts. A substring fragment names no subject, so the only
    # way to know how many it has is to count them.
    #
    # `plugin.gd` is `infrastructure` on the unanimous precedent of the other three
    # system-addons (battlefield:102, sprite_rig:120, almanac:184). The FAÇADE is
    # NOT: `exmateria_battlefield.gd` and `exmateria_sprite_rig.gd` both fall to
    # their addon's prefix rule and book into their system, and only
    # `exmateria_almanac.gd` is excepted. That exception's stated reason -- "it
    # realises no table and carries no behaviour" -- does not distinguish: all four
    # façades declare zero funcs. Measured 2026-09-08. Following the majority, and
    # the disagreement is written up as a soft spot rather than settled here.
    ("addons/exmateria_catalogue/plugin.gd", "infrastructure"),
    ("addons/exmateria_catalogue/", "Character Catalogue"),

    # --- split directories, by file ---
    ("src/core/Tune.gd", "platform"),
    # ADR-0177: the focus stack. `platform` on Tune.gd's precedent — its whole reason to exist
    # is a GODOT fact (set_process_*input gates DELIVERY, so a non-holder is never called), it
    # has no CPU/GPU counterpart to drift against, and every system's screens push onto it.
    ("src/core/Focus.gd", "platform"),
    # PSXDisplay.gd left src/core/ at extraction #1 (ADR-0147 dec. 1) and is now
    # matched by the addons/exmateria_render/ prefix at the head of this list.
    # ADR-0138: four files carry 43 of Render's 55 inbound edges and are depended
    # on from BOTH sides (FoldSurface/EngineFoldCompositor reach Fold.FOLD_LAYER
    # and DepthMode.render_layer_order_for exactly as the ten producers do).
    # They are ADR-0121 dec. 5's shared kernel, not Render's. Render keeps only
    # what nobody names (the renderer) plus its port. ColorStack, ColorRecipe and
    # DepthMode left src/core/ in prologue pass 6 (ADR-0146) — they are now
    # matched by the one addons/exmateria_schema/ prefix at the head of this list.
    ("src/core/UserSettings.gd", "infrastructure"),
    ("src/core/AssetManifest.gd", "infrastructure"),
    ("src/core/ValidationUtils.gd", "infrastructure"),
    ("src/core/EventBus.gd", "DELETE"),

    # --- the almanac (extraction #5, ADR-0251). THIRTY-TWO EXACT RULES FOR ONE
    # ADDON, WHICH IS NOT WHAT EVERY OTHER ADDON GETS, AND THE REASON IS
    # ADR-0144. These files were `src/data/` (plus `src/units/UnitProgression.gd`
    # and `src/units/AbilityLoadout.gd`); the ("src/data/", "Battle") catch-all
    # booked 24 files / 2,432 lines to `Battle`, including a file whose own header
    # says AUTO-GENERATED and nine hand-authored FFT tables, and ADR-0144 dec. 2
    # removed it — exact paths, no catch-all, the treatment ADR-0129 dec. 11 gave
    # src/effects/.
    #
    # 🔴 THE ADDRESS COLLAPSED; THE BUCKETS DID NOT (ADR-0251 dec. 7). #945 asked
    # for one directory rule on ADR-0184 dec. 3's precedent. Measured, it cannot
    # be had: `check_blueprint_walk.py` check 4 runs a TWO-WAY content <-> store
    # rule over this population, and its subjects are exactly the eleven files
    # booked `content` below — re-derived from source, not trusted. A prefix rule
    # booking all thirty `content` would need a twenty-name exemption set, which
    # is the blanket exemption that check's own comment refuses; a prefix rule
    # booking them anything else would re-book nineteen files that no consumer
    # stopped consuming, which is #744's rule one directory over. ADR-0243 dec. 3
    # is the same fact stated the other way: *a bucket is who consumes a file, it
    # was never a claim about where the seam is*. The seam moved. The consumers
    # did not.
    #
    # What the collapse was FOR is still had: there is no catch-all under this
    # root either, so a file added to the addon books `UNCLASSIFIED` and
    # `classify_blueprint.py` exits non-zero (check 1) until someone decides.
    #
    # The addon's own scaffolding is `infrastructure` and NOT one of the thirty-
    # two: `plugin.gd` for the reason it is that in every addon, and the façade
    # because it realises no table and carries no behaviour — it is ADR-0212
    # dec. 1's collision workaround. Keeping both out is what makes the four
    # buckets below equal ADR-0243 dec. 4's table exactly (Battle 14, content 11,
    # UI 5, generated 2 = 32).
    ("addons/exmateria_almanac/plugin.gd", "infrastructure"),
    ("addons/exmateria_almanac/exmateria_almanac.gd", "infrastructure"),
    #
    # `content` here is CONTEXT.md -> "Hand-authored data asset": the JobDatabase
    # shape — a class_name store with a static cache, a lazy `_ensure_loaded`, and
    # one `JsonAsset.load_dict("res://assets/**.json")`. That shape is mechanical,
    # and `check_blueprint_walk.py` re-derives it from source rather than trusting
    # this list. SpritePaletteResolver has the shape but is NOT a store: it
    # implements EVTCHR_CLUT_RESOLUTION.md's two-axis rule OVER a baked manifest,
    # which is behaviour, so it stays with its system (ADR-0135 dec. 9's shape).
    ("addons/exmateria_almanac/abilities/AbilityDatabase.gd", "generated"),
    ("addons/exmateria_almanac/abilities/AbilityView.gd", "generated"),     # header: "AUTO-GENERATED FILE - Do not edit manually"
    # `src/data/JsonAsset.gd` was `infrastructure` here until #809 moved it to
    # `addons/exmateria_platform/json/`, where the addon root classifies it and an
    # override would be a second answer to a settled question.

    # `src/data/AnimationNames.gd` was `content` here until #809 moved it to
    # `addons/exmateria_sprite_rig/sequence/`, for the same reason.
    ("addons/exmateria_almanac/progression/BaseStatsDatabase.gd", "content"),
    ("addons/exmateria_almanac/encounters/BattleConditionalDatabase.gd", "content"),
    ("addons/exmateria_almanac/encounters/DeploymentZoneDatabase.gd", "content"),   # BLUEPRINT.md "A ROM file is not a responsibility" names it content
    ("addons/exmateria_almanac/encounters/EntdPositionDatabase.gd", "content"),
    ("addons/exmateria_almanac/items/ItemDatabase.gd", "content"),
    ("addons/exmateria_almanac/jobs/JobDatabase.gd", "content"),
    ("addons/exmateria_almanac/jobs/JobLevelsDatabase.gd", "content"),
    ("addons/exmateria_almanac/encounters/ScenarioDatabase.gd", "content"),         # BLUEPRINT.md: "content for Campaign and Battle"
    ("addons/exmateria_almanac/items/ShopAvailabilityDatabase.gd", "content"),      # the JobDatabase store shape, re-derived by check_blueprint_walk
    ("addons/exmateria_almanac/sprites/SpriteDatabase.gd", "content"),
    ("addons/exmateria_almanac/sprites/WeaponGraphicData.gd", "content"),
    ("addons/exmateria_almanac/sprites/WeaponZeroFrames.gd", "content"),

    # #743 / ADR-0217 dec. 9: the HOST side of the rig's content port -- seven
    # forwards onto the four stores above, and no rig behaviour at all. Booked
    # `content` and deliberately NOT `Sprite Rig`: a severance whose fix lands in
    # the bucket it drains reads as no change (ADR-0167's own fix first read as
    # GROWTH for that reason, which is why BattlefieldWiring below is `assembler`).
    # It has none of the store shape check_blueprint_walk re-derives -- no cache,
    # no _ensure_loaded, no load_dict -- because it is a translation, not a table.
    ("src/data/SpriteRigContent.gd", "content"),

    # The picker-domain rules. Sole inbound caller of each is UI3 — four of the five
    # are FormationDetailTransition.gd — so they are booked where their edges land
    # (ADR-0140 dec. 1's method). Named soft spot: these are equip/learn RULES, and
    # `Character Catalogue`'s chunk may reclaim them.
    ("addons/exmateria_almanac/abilities/AbilityCandidates.gd", "UI"),
    ("addons/exmateria_almanac/jobs/JobCandidates.gd", "UI"),
    ("addons/exmateria_almanac/items/EquipCandidates.gd", "UI"),
    ("addons/exmateria_almanac/items/EquipStatDelta.gd", "UI"),
    ("addons/exmateria_almanac/abilities/LearnableAbility.gd", "UI"),
    # Same shape, one ADR later (ADR-0278): an ability RULE whose only inbound edge is
    # UI3 — `src/ui3/detail/GambitOptions.gd` seeds the gambit surface's `To` column
    # from it. Booked where the edge lands, not where the subject sounds like it lives.
    # ⚠ #1148 would give it a second caller in `src/gpu/CombatLoop.gd`, which is Battle;
    # re-read this row the day that lands rather than assuming it still holds.
    ("addons/exmateria_almanac/abilities/AbilityFamily.gd", "UI"),

    # The rest is Battle: gambit evaluation, the status/element bit encodings the
    # GPU packer writes, and the stat maths. StatusRegistry verifies itself against
    # src/gpu/shaders/combat_common.glslinc at load — it is Battle's bit layout,
    # not a table.
    ("addons/exmateria_almanac/abilities/AbilityData.gd", "Battle"),
    ("addons/exmateria_almanac/abilities/AbilityType.gd", "Battle"),
    ("addons/exmateria_almanac/status/ElementEncoder.gd", "Battle"),
    ("addons/exmateria_almanac/gambits/Gambit.gd", "Battle"),
    ("addons/exmateria_almanac/gambits/GambitCondition.gd", "Battle"),
    ("addons/exmateria_almanac/gambits/GambitList.gd", "Battle"),
    ("addons/exmateria_almanac/sprites/ReactionType.gd", "Battle"),
    ("addons/exmateria_almanac/progression/StatCalculator.gd", "Battle"),
    ("addons/exmateria_almanac/status/StatusEncoder.gd", "Battle"),
    ("addons/exmateria_almanac/status/StatusRegistry.gd", "Battle"),
    ("addons/exmateria_almanac/gambits/TargetSelector.gd", "Battle"),
    # ADR-0243 dec. 6/7 brought these two in from `src/units/`, where the
    # ("src/units/", "Battle") prefix booked them. An exact rule at the new
    # address is what keeps that TRUE rather than re-derived: the addon has no
    # prefix rule to fall through to.
    ("addons/exmateria_almanac/progression/UnitProgression.gd", "Battle"),
    ("addons/exmateria_almanac/abilities/AbilityLoadout.gd", "Battle"),
    # #1123 split the equipment-slot and ability-slot VOCABULARIES out of those two
    # so they would stay in the almanac when the `state` members leave for the
    # Character Catalogue. The survivor follows its origin's bucket for the reason
    # stated directly above: the addon has no prefix rule, so an exact rule at the
    # new address is what keeps the booking true rather than re-derived.
    #
    # `Battle` +1 here is the SPLIT, not growth. Nothing moved between buckets and no
    # behaviour arrived — an enum changed file. Read as a reach count it is the
    # failure ADR-0167 names one comment down, where a fix got booked to the bucket it
    # was draining; recorded here so the delta is attributable when someone diffs it.
    #
    # 🔴 `items/EquipSlot.gd` USED TO BE THE SECOND ROW HERE AND ITS RULE IS DELETED
    # RATHER THAN RE-POINTED. ADR-0294 dec. 2 admitted it to the shared kernel as
    # ADR-0118 dec. 1's twelfth schema row, and `addons/exmateria_schema/` HAS a
    # prefix rule (`"schema"` at the head of this list), so an exact rule at the new
    # address would state what the prefix already derives — the thing the comment
    # above says an exact rule exists to avoid needing. `Battle` therefore goes back
    # down by one and `schema` up by one, and that delta is this move and nothing
    # else. `abilities/AbilitySlot.gd` did NOT travel: measured, no file outside the
    # almanac and `tests/` names it, so it crosses no boundary and realises no row.
    ("addons/exmateria_almanac/abilities/AbilitySlot.gd", "Battle"),

    # #589: the wiring block for the three lines `Battlefield` used to push into
    # `Effects` and `Audio` itself. `assembler` for the same reason as the
    # `*Boot.gd` files below and CompositorAutopilot: its identity is per-scene
    # wiring, not a system's work. It is also what keeps the severance
    # ATTRIBUTABLE -- ADR-0167's own fix first read as GROWTH because the class
    # it was written in got booked to the bucket it was draining, and `assembler`
    # is not one of the eleven, so no system's reach count moves for it.
    ("src/scenes/BattlefieldWiring.gd", "assembler"),
    ("src/scenes/GPUArena.gd", "assembler"),
    # ADR-0242 — the second scenario-booting host. Same kind as `GPUArena`: its
    # identity is per-scene wiring (boot + deployment), and the combat work it
    # drives belongs to `CombatLoop` and `TurnDirector`, which are booked already.
    ("src/scenes/GambitBattle.gd", "assembler"),
    # ADR-0275 dec. 17/24 — the gambit lab's live arm and the scenario-boot step it
    # SHARES with `GambitScenarioRunner` (spawn, encode, battle spec). `assembler`
    # for the reason the block above gives: their identity is per-scene wiring, and
    # the combat work they drive belongs to `CombatLoop` and the kernel, which are
    # booked already. Booking either to `Battle` would read as the lab growing the
    # battle system, which is the mis-attribution ADR-0167 names.
    ("src/scenes/GambitLabScene.gd", "assembler"),
    ("src/scenes/GambitScenarioBoot.gd", "assembler"),
    ("src/scenes/EffectViewerScene.gd", "assembler"),
    ("src/scenes/ProgressionTester.gd", "assembler"),
    ("src/scenes/ProjectileTester.gd", "assembler"),
    ("src/scenes/FireCastReproScene.gd", "assembler"),
    ("src/scenes/OpeningMenu.gd", "UI"),

    # src/scenarios/ holds TWO systems — the script player and the spine
    # ADR-0144 dec. 4: NavigatorMain.gd is the `NavigatorMain.tscn` root's assembler
    # and nothing calls it (every `NavigatorMain` mention in src/ is prose or a
    # duck-typed executor slot). ADR-0134's rule applies unchanged: an addon cannot
    # ship a root scene, so 1,185 lines of boot leave `Campaign`.
    ("src/scenarios/NavigatorMain.gd", "assembler"),
    ("src/scenarios/GameNavigator.gd", "Campaign"),
    ("src/scenarios/NavigatorRunner.gd", "Campaign"),
    ("src/scenarios/GameState.gd", "Campaign"),
    ("src/scenarios/ScenarioDirector.gd", "Campaign"),
    ("src/scenarios/ScenarioDirectorState.gd", "Campaign"),
    ("src/scenarios/ForcedDirectorState.gd", "Campaign"),
    ("src/scenarios/ScenarioPlayerScene.gd", "assembler"),
    ("src/scenarios/ScenarioGroupDatabase.gd", "content"),
    ("src/scenarios/EntdBattle.gd", "content"),
    ("src/scenarios/BattleDeployment.gd", "Battle"),
    ("src/scenarios/BattleConditionalSet.gd", "Battle"),
    ("src/scenarios/BattleConditionalOpcode.gd", "Battle"),
    # ADR-0172: the cull-proof NDC-overlay-quad recipe. What it knows is a GODOT fact — an
    # NDC-rewritten quad falls outside its own AABB and the culler drops it — not a game one,
    # which is the same reason `pixel_aspect`/`psx_dither` are here (ADR-0147). It was booked
    # `Cutscene` only because the VM was its first caller; `FormationScreenIn` extending it
    # from `UI` is what made the misfiling visible.
    ("src/core/ScreenOverlayQuad.gd", "platform"),
    # `src/scenarios/PsxNum.gd` and `src/scenarios/EventPathfinder.gd` were rows here on
    # `main` until extraction #3's loop pass 6 moved both into addons — `PsxNum` to
    # `addons/exmateria_platform/fixed_point/` and `EventPathfinder` to
    # `addons/exmateria_battlefield/pathfinding/`. The prefix rules above book both, so
    # re-adding either row would name a path that no longer exists (ADR-0184).

    # remaining src/scenes/ — viewers and tools are assemblers, the cursor is not
    ("src/scenes/OpeningScene.gd", "assembler"),
    ("src/scenes/TrapViewerScene.gd", "assembler"),
    ("src/scenes/DepthDebugScene.gd", "assembler"),
    ("src/scenes/UnitAnimationViewerScene.gd", "assembler"),
    ("src/scenes/RangeTileAtlasViewer.gd", "assembler"),
    ("src/scenes/UnitInfoWindowViewer.gd", "assembler"),

    # --- src/effects/ is not one system (ADR-0129): the display-space fold is
    # Render's, and three other systems keep their own producers in here. The
    # directory rule booked 969 lines of it to Effects. FoldSurface.gd left this
    # directory for the addon at extraction #1 and EngineFoldCompositor.gd stayed
    # and changed bucket — it polls EffectMultiMeshPool by node NAME and reads a
    # ten-field Effects payload, so an addon holding it would depend on the game
    # that consumed it (ADR-0200 decs. 1/11, ADR-0147 dec. 1). It falls through to
    # the ("src/effects/", "Effects") rule below, which is the correct answer and
    # not a catch-all accident: the six carrier shaders it builds moved with it.
    # CompositorAutopilot is
    # SPLIT in the decision (~40 lines of Render probe/policy inside an autoload
    # whose identity is per-scene wiring); the classifier books whole files, so
    # it lands on its identity and the impurity is known, not hidden.
    ("src/effects/CompositorAutopilot.gd", "assembler"),

    ("src/effects/", "Effects"),

    # Extraction #7 (#1225, gl-ADR-0295 dec. 2). The 64 members left `src/effects/`
    # and `assets/shaders/` for `addons/exmateria_effects/` in one commit, and this
    # prefix is what keeps that a RELOCATION rather than a 14,456-line deletion —
    # the reading ADR-0146 dec. 5 built `WALK_ROOTS` for and the artefact ADR-0114
    # dec. 4 forbids. `ADR-0286 dec. 10` prices it: `Effects` does not shrink.
    # `plugin.gd` is `infrastructure` on `addons/exmateria_catalogue/plugin.gd`'s
    # precedent — an editor entry point is not the system — and the façade is NOT:
    # `exmateria_effects.gd` is the system's whole published surface, so it books to
    # the system it publishes (the catalogue's reading; `exmateria_almanac.gd` takes
    # the opposite one and the two are not reconciled here).
    # ADR-0194 dec. 9 — an addon-owned test lives INSIDE a walk root, so the `tests`
    # rule has to come first or the system's line count absorbs its own tests. The
    # directory does not exist yet; `check_blueprint_walk` probes the rule with a
    # synthetic path, which is what makes seeding it before the first test possible.
    ("addons/exmateria_effects/tests/", "tests"),
    ("addons/exmateria_effects/plugin.gd", "infrastructure"),
    ("addons/exmateria_effects/", "Effects"),

    # ADR-0135 dec. 10: three *Boot.gd wiring files the ("src/ui3/", "UI")
    # directory rule was booking into a system. An assembler that leaves with
    # its system at extraction is the ADR-0134 defect: an addon cannot ship a
    # root scene.
    ("src/ui3/detail/DetailSceneBoot.gd", "assembler"),
    ("src/ui3/detail/StartActionMenuBoot.gd", "assembler"),
    ("src/ui3/formation/AllTemplatesFormationBoot.gd", "assembler"),
    # ADR-0181: the mutating Formation harness, `FormationDev.tscn`'s root. Its sibling above
    # is the browsing one; both are boot scripts that wire a fixture to a screen, so the
    # relocation also takes `_unlock_every_job` out of the `UI` bucket along with the reset.
    ("src/ui3/formation/FormationDevBoot.gd", "assembler"),

    # --- src/world_map/ is not one system (ADR-0176, issue #580). It was the repo's
    # ENTIRE `UNCLASSIFIED` bucket — 15 files, 4,496 lines — and the rule that books it
    # is one BLUEPRINT already relies on elsewhere: §9 lists "world map" among Campaign's
    # MODES, but so does it list "formation", and `FormationScene.gd` is `UI`. Being a mode
    # the spine sequences has never meant the spine owns the code. The spine owns WHERE YOU
    # ARE; each mode's screen belongs to the system that screen is made of.
    #
    # The four exceptions are not judgement calls — three of them say what they are in
    # their own docstrings, citing `docs/WORLD_MAP_PORT_LIST.md`'s crossing table:
    # C3 "Campaign's payload, not the screen's" / "Campaign's save data", and A1
    # "owner Audio, edge map -> Audio". `WorldMapTravel` READS like the fourth and is not:
    # it walks the party marker between nodes (§27/§29.6), which is screen animation, and
    # it appears on no crossing.
    # `WorldMapScene.gd` is `assembler` for a second, independent reason trunk recorded
    # and check_root_set.py check 4 forces: WorldMap.tscn is a declared root, an addon
    # cannot ship a root scene (ADR-0134), and a root's script is booked `assembler`. Its
    # own docstring agrees — *"Assembles the three pieces and nothing else."*
    ("src/world_map/WorldMapScene.gd", "assembler"),
    ("src/world_map/WorldMapProgress.gd", "Campaign"),
    ("src/world_map/WorldMapVariables.gd", "Campaign"),
    ("src/world_map/WorldMapMusicPort.gd", "Audio"),

    # --- whole directories ---
    ("src/world_map/", "UI"),
    ("src/ui3/", "UI"),
    ("src/scenarios/", "Cutscene"),
    ("src/scenario/", "Cutscene"),
    ("src/gpu/", "Battle"),
    # 🔴 EXACT, NOT A PREFIX — and `src/balance/` holding exactly one file is the
    # reason, not an accident. The lever layer (ADR-0277) arrived with #1142 and
    # `LeverSet.gd` was the ENTIRE `UNCLASSIFIED` bucket on trunk: 1 file, 642
    # lines, `check_blueprint_walk` red, and `run_all_tests.sh` turns that into
    # `ABORT`, so the full suite could not run at all. `Battle` is re-derived from
    # consumers per ADR-0243 dec. 3 (*a bucket is who consumes a file*) rather
    # than from the directory name: every production consumer is `src/gpu/` —
    # `GPUAbilityLoader.build()`, `GPUCombatPacker`, `GPUBatchSimulator.report()`
    # — plus `tools/rollout_corpus.gd`, which is not a system. It is NOT `content`
    # under ADR-0156: that widening covers FFT-specific code with no original that
    # STAYS, and this is behaviour — validation, tier composition, rounding and the
    # capability floor — over a hand-authored asset, which is exactly
    # SpritePaletteResolver's ruling one comment up (has the store shape, is not a
    # store, stays with its system). A prefix rule here would instead PREDICT that
    # every future balance file is Battle-consumed; the exact row asserts only what
    # is measured, and the next file books `UNCLASSIFIED` until someone decides —
    # which is what the walk is for.
    ("src/balance/LeverSet.gd", "Battle"),
    # src/units/ holds at least Battle and Sprite Rig (ADR-0129); the crystal is a
    # substitute body rig, not the trigger that inflicts it.
    ("src/units/", "Battle"),
    ("src/strategy/", "Battle"),
    ("src/projectiles/", "Battle"),
    ("src/audio/", "Audio"),

    # --- ADR-0156: new code with no original is `content`, not a system --------
    # The world-map screen is the first genuinely NEW system-shaped code the loop
    # has met: no original to extract, no closure to kill, nothing to subtract
    # from the progress bar (#416). `docs/WORLD_MAP_PORT_LIST.md` §0 settles the
    # blueprint half — it is **a feature, not a system**, threading Campaign, UI,
    # Render, Audio and Cutscene, and it gets no addon — so BLUEPRINT.md's bucket
    # table sorts it **Content pack**, *"stays; this is what the host converges
    # to."*  `content` is EXCLUDED at report time, which is what stops a new FFT
    # screen reading as the host growing (ADR-0121 dec. 2).
    #
    # This WIDENS `content` and the widening is the decision, not an accident: it
    # meant CONTEXT.md's *Hand-authored data asset* — the JobDatabase shape — and
    # now also means FFT-specific code that stays. `check_blueprint_walk.py`
    # check 4 re-derives the store shape only under `src/data/`, so the two
    # senses do not collide; ADR-0156 dec. 3 is where they are held apart.
    #
    # --- shaders (ADR-0131 dec. 3) -------------------------------------------
    # Under `src/` the directory rules above already own them: `src/gpu/shaders/`
    # -> Battle (the ten compute stages + two `.glslinc` headers, 6,081 lines) and
    # `src/ui3/shaders/` -> UI. `assets/shaders/` splits by system exactly as
    # `src/effects/` did, so ADR-0129 dec. 11's treatment applies here too: exact
    # paths, no directory rule. Evidence per file is "which system's .gd names it",
    # with the include graph resolving the headers no .gd names directly.
    # (`Battlefield`'s sixteen shader rows left this list at extraction #3's
    # loop pass 6 — the files are under `addons/exmateria_battlefield/` and the
    # prefix rule at the head books them. They were the only shader rows here
    # whose system had extracted; the rest still split by exact path.)

    ("assets/shaders/projectile_sprite.gdshader", "Battle"),
    ("assets/shaders/projectile_vertex_color.gdshader", "Battle"),
    ("assets/shaders/shadow_blob.gdshader", "Battle"),
    ("assets/shaders/shadow_blob_fold.gdshader", "Battle"),
    ("assets/shaders/solid_ot.gdshader", "Battle"),

    # 🔴 RETURNED, not left behind — and this row could NOT go in a register-first
    # commit. `check_blueprint_walk` has a STALE RULE arm ("names a file the walk does not
    # see"), so a path-keyed classification row reds until the file is at that path:
    # measured, adding it one commit early cost 2 problems instead of 0. ADR-0192 dec. 1's
    # ordering assumes a THRESHOLD register, which can lead its population; a path-keyed
    # table is validated against the tree and must move WITH it.
    #
    # The row itself is verbatim the one extraction #3 pass 6 (285be3ff8) deleted when the
    # file moved into the addon. ADR-0209 measured that move as the bulk census acting by
    # DIRECTORY — no addon file uses this shader, its one consumer is a HOST viewer — and
    # put the file back, so the row comes back with it. Still `Battlefield`: the subject is
    # the tile cursor's CLUT, and booking a HOST path `Battlefield` is the residue register
    # saying the true thing — 24 lines of test-only Battlefield residue that did not extract.
    ("assets/shaders/cursor_clut_preview.gdshader", "Battlefield"),   # reached only from tests/CursorClutPreviewViewer.tscn

    ("assets/shaders/darkscreen_mosaic.gdshader", "Cutscene"),
    ("assets/shaders/darkscreen_mosaic.gdshaderinc", "Cutscene"),
    # The dim folds so {78}'s banner can sit ABOVE it — the fold resolves at
    # PRE_TRANSPARENT, so a folded banner under an in-scene dim gets the fog painted
    # over it. Cutscene's, with its in-scene twin.
    ("assets/shaders/darkscreen_mosaic_fold.gdshader", "Cutscene"),
    ("assets/shaders/psx_screen_blend.gdshaderinc", "Cutscene"),
    ("assets/shaders/screen_color_mode0.gdshader", "Cutscene"),
    ("assets/shaders/screen_color_mode1.gdshader", "Cutscene"),
    ("assets/shaders/screen_color_mode2.gdshader", "Cutscene"),
    ("assets/shaders/screen_color_mode3.gdshader", "Cutscene"),
    ("assets/shaders/show_graphic.gdshader", "Cutscene"),
    ("assets/shaders/show_graphic_reveal.gdshaderinc", "Cutscene"),
    ("assets/shaders/show_graphic_shadow.gdshader", "Cutscene"),
    ("assets/shaders/show_map_title.gdshader", "Cutscene"),
    ("assets/shaders/show_map_title_reveal.gdshaderinc", "Cutscene"),
    ("assets/shaders/show_map_title_shadow.gdshader", "Cutscene"),
    # {78} Display Conditions — the battle-intro banner and the results sequence,
    # a screen-space prim list over {76}'s dim. Cutscene's, like every other
    # scenario screen overlay above; ScenarioResultsScreen.gd is their only caller.
    ("assets/shaders/results_screen.gdshaderinc", "Cutscene"),
    ("assets/shaders/results_screen_add.gdshader", "Cutscene"),
    ("assets/shaders/results_screen_add_fold.gdshader", "Cutscene"),
    ("assets/shaders/results_screen_mix.gdshader", "Cutscene"),
    ("assets/shaders/results_screen_sub.gdshader", "Cutscene"),
    ("assets/shaders/results_screen_sub_fold.gdshader", "Cutscene"),
    # ADR-0189 dec. 3/7: the three unit variants are Sprite Rig's. `unit_additive` was
    # booked Cutscene under ADR-0129 dec. 4 ("a producer keeps its own shader") — but that
    # rule was written about producers into Render's fold taking Render's generic library,
    # and this is Cutscene taking Sprite Rig's WHOLE sprite compositor. Nothing outside
    # Sprite Rig names a unit shader path any more; the booking follows.
    # 🔴 THE TWELVE EFFECT SHADER ROWS THAT STOOD HERE ARE GONE, AND THE BUCKET IS
    # UNCHANGED. They were `assets/shaders/effect_*` exact rules — four particle
    # carriers, the STP and fold includes, `trap_charge_line` and the six
    # `EngineFoldCompositor` carriers — each booked `Effects` by its own argument.
    # Extraction #7 (#1225) moved all twelve into `addons/exmateria_effects/`, where
    # the prefix rule below claims them, and `check_blueprint_walk`'s SHADOWED RULE
    # arm reds an exact rule a prefix already covers. The arguments they carried are
    # kept in the two comments that follow rather than deleted with the rows.
    # 🔴 TRUNK'S DEBT, NOT #744's (booked 2026-09-01). `effect_particle_fold.gdshaderinc`
    # landed unbooked and `check_blueprint_walk` was red on `main` for it — an
    # EARLY-ABORTING pre-flight guard, so every guard behind it was going unrun. It is
    # the fold half of `effect_particle_*`, included by the particle shaders, and it
    # books `Effects` with them.

    # The six carriers EngineFoldCompositor builds. Booked `Render` until
    # extraction #1; they are Effects' producers into a fold Effects does not own,
    # which is ADR-0129 dec. 4's shape exactly (ADR-0200 dec. 11, ADR-0147 dec. 5).
    # After this the sixteen `compositor_layer` carriers read UI 7, Battlefield 4,
    # Effects 4, Sprite Rig 1, Render 0 — the system that owns the bracket produces
    # nothing into it.
    # depth_debug.gdshader and the two foldsurface .glsl stages left assets/shaders
    # for addons/exmateria_render/ at extraction #1; the prefix rule books them.

    ("assets/shaders/bitmap_char_3d.gdshader", "UI"),                 # font-atlas glyph; NO reader anywhere — a closure candidate
    ("assets/shaders/evtface_portrait_3d.gdshader", "UI"),
    ("assets/shaders/feedback_hud_sprite.gdshader", "UI"),
    ("assets/shaders/feedback_hud_sprite_additive.gdshader", "UI"),
    ("assets/shaders/feedback_hud_sprite_additive_fold.gdshader", "UI"),
    ("assets/shaders/nine_slice_3d.gdshader", "UI"),
    ("assets/shaders/nine_slice_3d_opaque.gdshader", "UI"),
    ("assets/shaders/ui3_owner_color.gdshader", "UI"),
    ("assets/shaders/ui_nearest.gdshader", "UI"),                     # named only by docs/SHADER_CONSOLIDATION_AUDIT.md — a closure candidate
    ("assets/shaders/turn_queue_team_underlay.gdshader", "UI"),       # ADR-0269
    ("assets/shaders/unit_portrait_3d.gdshader", "UI"),

    # color_stack and ot_depth are the kernel's two GPU halves and moved
    # into addons/exmateria_schema/ in prologue pass 6 (ADR-0146); the prefix rule
    # at the head of this list books them now.
    #
    # pixel_aspect and psx_dither reach FURTHER than either of those (pixel_aspect: 16
    # shaders across 6 buckets, with its own guard) and pass 6 still declined
    # them — ADR-0146 dec. 3. Reach is not the admission test (ADR-0139 dec. 2);
    # a codec is, and these two have no CPU counterpart to drift against. Their
    # CPU side is one `global uniform` pushed through a port (PSXDisplay._apply_par,
    # DebugConfig._apply_dither), not a second implementation of the same encoding.
    # They stay `platform` alongside PsxNum.gd, which ADR-0146 dec. 4 confirms
    # against ADR-0139 dec. 7's "the other three stay Render's".
    # Both moved to `addons/exmateria_platform/` at extraction #3's loop pass 6
    # (ADR-0169 dec. 2) and are booked by the prefix rule at the head of this
    # list. The paragraph above is why they are `platform` and not `schema`, and
    # it is unchanged by the address.

    # (ADR-0135 dec. 6's one .gd under assets/, TuneSandbox.gd, was deleted with its
    # declined scene — #459. There is no longer any .gd outside src/ to pin.)
]

# debug/: the harness itself vs per-system panels, matched on filename
# ADR-0140 dec. 1: these are FILENAMES, matched as substrings. "DebugPanel" was
# one of them and matched all 33 `*DebugPanel.gd` files, shadowing 19 of the 30
# DEBUG_OWNER rules below and inflating `Debug` to 45 files / 6,911 lines. It
# named no file, nor did "DebugWindow" or "DebugRoot"; all three are dropped.
# Keep every entry here matching an actual file, or the shadow returns.
DEBUG_HOST = ("DebugConfig", "TuneField", "BaseDebugPanel", "DebugOverlay",
              "PerfMonitor", "GameLogger", "PerfDebugPanel", "LoggingDebugPanel",
              "DebugDashboard", "DebugMasonryContainer", "TunablesRegistry",
              "PerfHUD", "FuncTracer")
# ADR-0144 dec. 3 pruned fourteen entries that could never fire: eleven matched
# no file at all (`Sfx`, `Music`, `Combat`, `Gambit`, `Gpu`, `Character`, `Ui`,
# `Palette`, `Depth`, `Fold`, `Psx`) and three were wholly shadowed by an earlier
# fragment (`Sprite` and `Cinematic` by `Scenario`, `Anim` by `Unit`). That is 34%
# of the table doing nothing while reading as intent — the exact condition ADR-0140
# dec. 1 asked to be kept out, one paragraph above where it accumulated.
# `check_blueprint_walk.py` now fails on a dead or shadowed entry, so this cannot
# silently regrow; and a NEW panel no fragment reaches lands in UNCLASSIFIED, which
# is the no-catch-all property working, not a hole.
#
# ADR-0147 / extraction #1 removed all three `Render` fragments, and the guard is
# what forced it. "Display" and "Shader" went dead the moment DisplayDebugPanel.gd
# and ShaderCalibrationPanel.gd left src/debug/ for the addon: the only stems either
# still matched were UIDisplayDebugPanel and UnitShaderDebugPanel, and "UI" and
# "Unit" both precede them, so each became a SHADOWED entry rather than a missing
# one. "Color" went with them for dec. 3's reason below. DEBUG_OWNER now books no
# file to `Render` at all, which is the right shape: `Render`'s two panels are in
# `Render`, and this table only ever spoke for panels living in the host.
DEBUG_OWNER = [
    ("Scenario", "Cutscene"), ("Effect", "Effects"), ("Audio", "Audio"),
    ("Unit", "Battle"),
    ("Progression", "Character Catalogue"), ("Roster", "Character Catalogue"),
    # "Camera" / "Tile" went dead when ADR-0159 dec. 5 rebooked CameraFeelDebugPanel
    # and TilesDebugPanel to DEBUG_EXACT. "Map" and "Deadzone" followed them at
    # extraction #3's loop pass 6 (ADR-0184): the two files they still spoke for,
    # MapGridOverlay.gd and DeadzoneBoxOverlay.gd, are manifest rows and now live
    # under `addons/exmateria_battlefield/`, so this table books no `Battlefield`
    # file at all. `check_blueprint_walk.py`'s DEAD DEBUG_OWNER arm is what said
    # so — a substring table cannot notice its own last subject leaving.
    ("UI", "UI"),
    ("Trap", "Effects"), ("FireCast", "Effects"),
    # ADR-0140 dec. 1: panels no fragment above reached. Each owner is the system
    # the panel's own outbound edges land in (touch_matrix.py, 2026-08-21).
    ("BattleBinding", "Character Catalogue"),
    ("FeedbackHud", "UI"), ("Font", "UI"), ("Formation", "UI"),
    ("Navigator", "Campaign"),
    # "Cursor" and "Skirt" went dead with dec. 5's rebooking, same as "Camera"/"Tile".
    ("Projectile", "Battle"), ("Simulation", "Battle"),
    ("Vitals", "UI"),
]

# ADR-0144 dec. 3. A substring table is order-sensitive, and ADR-0140 dec. 1
# already had to delete three entries for shadowing 19 rules. The shadow came
# back at a smaller scale: "Map" precedes "Ui"/"UI", so the UI3 owner-map debug
# tool was booked `Battlefield`; "Cinematic" precedes nothing but means the
# COMBAT cinematic here, not `Cutscene`'s. Rather than reorder the table — which
# fixes these two and hides the next pair — an exact-stem table is consulted
# first, exactly as RULES consults exact paths before directory prefixes.
# Each entry states the outbound-edge evidence that placed it.
DEBUG_EXACT = {
    # 158 lines, and the walk's only UNCLASSIFIED at trunk: no fragment matched.
    # Its one non-harness edge is preload src/ui3/detail/DetailScene.gd.
    "DetailScreenDebugPanel": "UI",
    # all three outbound edges land in UI (UI3OwnerColors, UI3ClipEngine, UI3Element)
    "UI3OwnerColorMap": "UI",
    # its only edges are to UI3OwnerColorMap
    "UI3OwnerMapPicker": "UI",
    # constructed by src/gpu/CombatLoop.gd, read by src/units/Unit.gd; reads
    # battle_state/all_states/units and GPUConstants. The "cinematic" is the
    # combat spell cinematic, not a Cutscene.
    "CinematicDebugProbe": "Battle",
    # ADR-0147 dec. 3, landed at loop pass 6 with the code as ADR-0200 dec. 13
    # requires. ("Color", "Render") booked this file on its NAME — the third
    # instance of the shadowing failure ADR-0140 dec. 1 and ADR-0144 dec. 3 each
    # corrected once. It is a pure projection of an effect's colour keyframes; its
    # only consumer is EffectTimelineView (Effects) and both its outbound edges are
    # Effects (EffectPhase, ScreenData). Deferred out of ADR-0147 itself because a
    # booking fix must not ride with a decision that quotes the numbers it moves
    # (ADR-0141's src/data/ precedent). With it moved, Render's outbound into any
    # system is ZERO.
    "ColorTimelineModel": "Effects",
    # ADR-0156 dec. 4 — the FOURTH time ("Map", "Battlefield") has booked a file
    # on its name. 146 lines whose only subject is WorldMapScene, which sets this
    # panel itself; it has ZERO typed edges into Battlefield, or anywhere. Per
    # ADR-0140 dec. 1 the owner is the system its outbound edges land in.
    #
    # Trunk booked it `content` because the rule above booked all of `src/world_map/`
    # `content`. ADR-0176 replaced that rule — the world map is not one system, and its
    # SCREEN is `UI` — so the last link of that chain no longer holds and the booking
    # follows the edges to where they now land. NOT `Debug`: that rebooking is scoped to
    # extraction #3's five panels by the note below, deliberately, and widening it here
    # would be the instrument-changes-mid-series failure that note exists to prevent.
    "WorldMapDebugPanel": "UI",
    # --- ADR-0159 dec. 5, extraction #3 pass 4 (#551) -------------------------
    # ADR-0068 and the `tunable-compliance` loop already state the rule: the
    # PRODUCTION owner holds the tunable, the debug panel is a pure VIEW onto the
    # registry. These five were booked `Battlefield` by the DEBUG_OWNER fragments
    # "Camera" / "Cursor" / "Map" / "Skirt" / "Tile" — booked on their NAME, which
    # is the failure ADR-0140 dec. 1, ADR-0144 dec. 3 and ADR-0156 dec. 4 each
    # corrected once before. Measured over the whole host surface they carry 49
    # lines of `Debug` and `platform`, of which `TuneField` (Debug's widget) is 32
    # and `Tune` is 7; not one line of `Battlefield` behaviour.
    # ⚠️ SCOPED TO EXTRACTION #3. The same rule is unapplied to the other systems'
    # panels — applying it tree-wide would move dozens of files and rewrite every
    # system's numbers mid-extraction, which is the instrument-changes-mid-series
    # failure the blueprint baseline exists to avoid. Debt, not a decision.
    "CameraFeelDebugPanel": "Debug",
    "CursorDebugPanel": "Debug",
    "MapRenderDebugPanel": "Debug",
    "SkirtDebugPanel": "Debug",
    "TilesDebugPanel": "Debug",
    # --- #555, extraction #3 pass 5 ------------------------------------------
    # The FIFTH file ("Map", "Battlefield") has booked on its name, and this one
    # was written by the very ticket that removes Battlefield's DebugOverlay
    # residue: left booked `Battlefield`, the inversion READ AS GROWTH (42 -> 47,
    # `DebugOverlay` 2 lines -> 4) because the four lines it deletes reappeared in
    # a file the stem rule put back in the same bucket. Measured per ADR-0140
    # dec. 1: its outbound edges are DebugOverlay, SkirtDebugPanel and
    # MapRenderDebugPanel — three `Debug`, ZERO `Battlefield`. It takes the
    # composer as a bare `Node` precisely so it names no Battlefield type.
    "MapDebugPanels": "Debug",
    # #1267 / extraction #8 pass 6 step 1 — the SAME failure this table records for
    # `MapDebugPanels`, one extraction later: a file written to DRAIN a bucket gets
    # name-booked INTO it. `FormationDebugPanels.gd` exists to delete UI's five
    # `UI -> Debug` reach lines, and the stem rule reads "Formation" and books its 129
    # lines to `UI` — the bucket it just emptied. Its outbound edges are `DebugOverlay`,
    # `FormationDebugPanel`, `DetailScreenDebugPanel` and `VitalsLayoutDebugPanel`:
    # four `Debug`, ZERO `UI`. It takes the screen as a bare `Node` precisely so it
    # names no UI type, exactly as `MapDebugPanels` takes the composer.
    "FormationDebugPanels": "Debug",
    # --- trunk's debt, booked by #744 2026-09-01 ------------------------------
    # The other half of the unbooked pair that has had `check_blueprint_walk` red on
    # `main`. `Campaign` on the same evidence as `NavigatorDebugPanel.gd`, which
    # `classify()` already answers `Campaign` for: same installer
    # (`NavigatorMain.gd:361`), same F3 category (`DebugOverlay.Category.STORY`), and
    # its subject is the derived story timeline of ADR-0216. Named EXACTLY rather than
    # by a "Story" stem — a stem is the failure ADR-0140 dec. 1 corrected, and one
    # panel does not need one.
    "StoryTimelineDebugPanel": "Campaign",
    # --- the gambit host's auto-place toggle (F3 -> Simulation) ---------------
    # Booked by its outbound edges (ADR-0140 dec. 1), which are three and all
    # `Debug`: BaseDebugPanel, TuneField and DebugConfig's slug const. It names
    # no Battle type at all — the host it is registered by reaches IT, never the
    # other way round — so `Battle` would be a booking on the installer, which is
    # the same name-shaped reasoning DEBUG_EXACT exists to overrule. Exact rather
    # than a "Gambit"/"Deploy" stem: one panel does not need one.
    "GambitDeployDebugPanel": "Debug",
    # --- the gambit lab's verdict readout (ADR-0275 dec. 13, #1128) ----------
    # `Debug` on the same evidence as the two panels above, applied rather than
    # re-derived: booked by its OUTBOUND EDGES (ADR-0140 dec. 1), and it names ZERO
    # game classes. Everything it draws about the battle it gets duck-typed off the
    # host through `GambitLabScene.lab_state()` — `state_name`, `unit_name`,
    # `reason_name`, `verdict_reader`, `is_safety_net_slot` — exactly the
    # `debug_battle_state()` seam `StateDebugPanel` is booked `Debug` for. Booking it
    # `Battle` would be a booking on the INSTALLER, the reasoning DEBUG_EXACT exists
    # to overrule. Exact rather than a "Lab"/"Gambit" stem: one panel does not need one.
    "GambitLabPanel": "Debug",
    # --- the SHARED verdict readout, both combat hosts (ADR-0275 dec. 38/40, #1211) -
    # `Debug`, and the booking is DERIVED rather than inherited from the two panels
    # above: its outbound edges (ADR-0140 dec. 1) are `BaseDebugPanel`, that base's
    # `Category` enum, and Godot builtins — `VBoxContainer`, `Label`, `Color`. It
    # names ZERO game classes, and it does not even reach `DebugConfig` or
    # `TuneField`, so it is the thinnest renderer in this table.
    #
    # Everything it draws arrives through a duck-typed host seam — `setup(host, title)`
    # takes an UNTYPED host and `render(state: Dictionary)` takes a plain dict — which
    # is the same `debug_battle_state()` shape `StateDebugPanel` and `GambitLabPanel`
    # are booked `Debug` for. Both hosts reach IT (`GambitBattle.gd:461-463`,
    # `GambitLabScene`), never the other way round, so `Battle` would be a booking on
    # the INSTALLER, the reasoning DEBUG_EXACT exists to overrule.
    #
    # ⚠️ NOT `assembler` on the strength of being SHARED by two hosts. ADR-0275 dec. 40
    # keeps it deliberately OUT of `CombatPanelCatalog` — the mount booked `assembler`
    # above — precisely because it is not a thing both hosts get. `GPUArena` fields a
    # cast with no gambits and never installs it. Sharing a renderer between two hosts
    # is not per-scene wiring; the wiring is in the hosts.
    #
    # Exact rather than a "Verdict"/"Gambit" stem: one panel does not need one, and
    # line 618's census already records that a `Gambit` fragment matches no file.
    "GambitVerdictPanel": "Debug",
    # --- the F3 STATE census (ADR-0177 Amendment 3) --------------------------
    # `Debug` by ADR-0140 dec. 1's own rule and NOT by ADR-0159 dec. 5's scoped
    # exemption: this panel has no subject system to be booked away from. It names
    # ZERO game classes — deliberately, because `DebugOverlay` preloads it and a
    # `TurnDirector.` or `GameState.` spelling on it would drag the GPU packer and the
    # walk's enum into every scene's load closure. Its outbound edges are
    # BaseDebugPanel, DebugConfig and the `Focus` autoload; every battlefield fact it
    # shows is read duck-typed off the live tree or handed over by the host's
    # `debug_battle_state()` seam. Exact rather than a "State" stem: a stem that broad
    # would shadow half the table, which is the failure ADR-0140 dec. 1 corrected.
    "StateDebugPanel": "Debug",
    # --- the combat hosts' shared F3 mount and its applicability lens (#1050) -
    # `assembler`, and deliberately NOT `Debug`: this file is a MOUNT — the one
    # place `GPUArena` and `GambitBattle` say which F3 panels a combat host gets —
    # and its identity is per-scene wiring, exactly like `BattlefieldWiring.gd`
    # and the two hosts themselves, all three of which are booked `assembler`
    # above. Booking a mount `Debug` re-runs the ADR-0167 mis-attribution that
    # `BattlefieldWiring`'s rule records: the file written to DRAIN a bucket gets
    # name-booked INTO it, and the severance reads as growth. `assembler` is not
    # one of the eleven systems, so no system's reach count moves for it.
    "CombatPanelCatalog": "assembler",
    # `assembler` for the same reason and by the same argument: this is the OTHER
    # half of that mount, split out when the catalogue's gate moved to the seam.
    # It is the one place a host that is not a combat host — the scenario player,
    # and `NavigatorMain` through it — says which subject-free F3 panels it gets.
    # Per-scene wiring, not a debug subject; booking a mount `Debug` is the
    # ADR-0167 mis-attribution `BattlefieldWiring`'s rule records.
    "UniversalDebugPanels": "assembler",
    # `Debug`, and NOT `assembler` alongside the two mounts above, because it is
    # not a mount: it builds nothing, registers nothing and names no scene. It is
    # a const TABLE — the id space of the F3 catalogue, which is the persisted key
    # in `user_settings.json` and therefore vocabulary owned by `DebugOverlay`
    # (`Debug`) rather than by any host's wiring. Same shape as
    # `PanelApplicability` below: exact rather than a stem, because an "Ids" or
    # "Panel" fragment would shadow half this table.
    "DebugPanelIds": "Debug",
    # `Debug` by ADR-0140 dec. 1's own rule. Unlike the catalogue this is not a
    # mount but a PREDICATE — it builds nothing and registers nothing; it walks an
    # already-built panel for `TuneField.SLUG_META` and asks `Tune.consumer_state`
    # about each slug. Its outbound edges are TuneField and Tune, both `Debug`; it
    # names no game class at all. Exact rather than a "Panel"/"Applicability" stem:
    # a "Panel" fragment would shadow most of this table, which is the failure
    # ADR-0140 dec. 1 corrected.
    "PanelApplicability": "Debug",
}


def classify(rel: str):
    if rel.startswith("src/debug/"):
        stem = pathlib.Path(rel).stem
        if stem in DEBUG_EXACT:
            return DEBUG_EXACT[stem]
        if any(h in stem for h in DEBUG_HOST):
            return "Debug"
        for frag, owner in DEBUG_OWNER:
            if frag in stem:
                return owner
        return None
    for pat, bucket in RULES:
        if pat.endswith("/") and rel.startswith(pat):
            return bucket
        if rel == pat:
            return bucket
    return None

# ADR-0131 dec. 3 scoped the walk to `src/` and `assets/`, which was the whole of
# the host's hand-written source on the day it was written. Prologue pass 6 moved
# the shared kernel out of both and into an addon, and ADR-0145 dec. 5 had already
# named the hole that opens when source leaves the walk's roots: it is counted
# NOWHERE, so a relocation reads as a deletion. ADR-0146 dec. 5 fixes it for the
# kernel — the walk follows the refactor's own output.
#
# `addons/exmateria_sound/` is deliberately NOT here: it is a drifted copy of
# another package (issue #326), and ADR-0131 dec. 8 reads that row from the
# canonical `exmateria-sound/` package, not from the host. Walking it would
# double-count it against the baseline's `extracted` row. The test is authorship,
# not the `addons/` path: this repo's blueprint owns exmateria_schema, and each
# extracted system joins this tuple in its own pass. `exmateria_render` joined it
# at extraction #1 (ADR-0147 dec. 9); `exmateria_battlefield` and
# `exmateria_platform` joined at extraction #3's loop pass 6 (ADR-0184 — the
# address is ADR-0169 dec. 1). Each joined in the same commit that created the
# directory — a relocation that outruns the walk reads as a deletion.
# `exmateria_almanac` joined at extraction #5 (ADR-0251 dec. 1) with 32 files
# that were already walked at `src/data/` and `src/units/`, so this line is what
# keeps the move a RELOCATION: without it the census would read 24,111 lines
# deleted and the extraction would score as progress it did not make.
WALK_ROOTS = ("src", "assets", "addons/exmateria_schema", "addons/exmateria_render",
              "addons/exmateria_battlefield", "addons/exmateria_platform",
              "addons/exmateria_sprite_rig", "addons/exmateria_almanac",
              "addons/exmateria_catalogue", "addons/exmateria_effects")


def walk():
    """Every hand-written source file under WALK_ROOTS, sorted."""
    out = []
    for top in WALK_ROOTS:
        for q in sorted(pathlib.Path(top).rglob("*")):
            if q.is_file() and q.suffix in SOURCE_SUFFIXES:
                out.append(q)
    return out


lines, files, shader_lines, shader_files, unk = (collections.Counter(), collections.Counter(),
                                                 collections.Counter(), collections.Counter(), [])
for p in walk():
    rel = p.as_posix()
    n = len(p.read_text(encoding="utf-8", errors="replace").splitlines())
    b = classify(rel)
    if b is None:
        unk.append((n, rel)); b = "UNCLASSIFIED"
    lines[b] += n; files[b] += 1
    if p.suffix in SHADER_SUFFIXES:
        shader_lines[b] += n; shader_files[b] += 1

total = sum(lines.values())


def row(b):
    sh = f"{shader_files[b]:>6}{shader_lines[b]:>9}" if shader_files[b] else f"{'.':>6}{'.':>9}"
    print(f"{b:<22}{files[b]:>7}{lines[b]:>10}{lines[b]/total*100:>7.1f}%{sh}")


print(f"{'BUCKET':<22}{'FILES':>7}{'LINES':>10}{'SHARE':>8}{'SH.F':>6}{'SH.LINES':>9}")
print("-" * 62)
for b in SYSTEMS:
    if files[b]:
        row(b)
print("-" * 62)
for b in OTHER:
    if files[b]:
        row(b)
print("-" * 62)
u = lines["UNCLASSIFIED"]
if files["UNCLASSIFIED"]:
    row("UNCLASSIFIED")
    print("-" * 62)
print(f"{'TOTAL':<22}{sum(files.values()):>7}{total:>10}{'':>7} {sum(shader_files.values()):>5}{sum(shader_lines.values()):>9}")
sys_lines = sum(lines[b] for b in SYSTEMS)
print(f"\nin a system: {sys_lines:,} of {total:,}  ({sys_lines/total*100:.1f}%)")
print(f"accounted for: {total-u:,} of {total:,}  ({(total-u)/total*100:.1f}%)")

# ADR-0131 dec. 3/4 — exclusion at REPORT time, never at walk time. The host's
# `tests/` and `tools/` are outside the walk by construction; `generated`,
# `content` and `tests` are classified above and subtracted only here.
# `tests` is `addons/<name>/tests/` and ONLY that (ADR-0194 dec. 9): an
# addon-owned test is inside a walk root, so it is walked, booked, printed as
# its own row, and then subtracted. It is never skipped.
EXCLUDED = ("generated", "content", "tests")
excl = sum(lines[b] for b in EXCLUDED)
print(f"\nBASELINE (ADR-0131 dec. 3 + ADR-0146 dec. 5) — hand-written .gd + shader under")
print(f"{', '.join(WALK_ROOTS)},")
print(f"less {' and '.join(EXCLUDED)}: {total - excl:,} lines in {sum(files.values()) - sum(files[b] for b in EXCLUDED)} files")
for b in EXCLUDED:
    print(f"   less {b:<14}{lines[b]:>8} lines ({files[b]} files)")

if unk and "--list-unclassified" in sys.argv:
    print(f"\nUNCLASSIFIED — {len(unk)} files, largest first:")
    for n, rel in sorted(unk, reverse=True):
        print(f"  {n:>6}  {rel}")
sys.exit(1 if unk else 0)
