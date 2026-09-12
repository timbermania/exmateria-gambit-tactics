#!/usr/bin/env bash
# =============================================================================
# bootstrap_assets.sh — take a freshly-cloned checkout to a runnable
#                       state in one command.
#
# Usage:
#     bash tools/bootstrap_assets.sh [<path-to-fft-extract>]
#
#     The arg is optional. If provided, the script symlinks that directory
#     into project-assets/fft-extract/. If omitted, the script assumes you've
#     already populated project-assets/fft-extract/ yourself (e.g. by running
#     `fft-iso-patcher extract` into it).
#
# Cross-platform: Linux, macOS, WSL, and Git Bash on Windows.
#
# Idempotent: every step is safe to re-run. The script will:
#   - skip ROM-extract symlinks that already exist
#   - skip code patches that have already been applied
#   - re-parse assets (parsers no-op or use --force semantics)
#   - trigger a Godot re-import to pick up any new files
#
# See SETUP_FROM_SCRATCH.md (package root) for the full why-each-step.
# =============================================================================

set -euo pipefail

# ----- locate ourselves ------------------------------------------------------
SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_DIR="$(cd "$SCRIPT/.." && pwd)"
REPO_ROOT="$(cd "$GODOT_DIR/.." && pwd)"
FFT_EXTRACT_DIR="$REPO_ROOT/project-assets/fft-extract"

# ----- helpers ---------------------------------------------------------------
log()  { printf '\n\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
skip() { printf '\033[1;90m  ·\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing command: $1 (install it then re-run)"
}

# ----- 0. validate environment ------------------------------------------------
log "0/8 validating environment"
need_cmd godot
need_cmd uv
need_cmd python3
need_cmd ln
need_cmd grep
need_cmd sed
ok "godot, uv, python3, ln, grep, sed all present"

# Vulkan ICD check (informational on Linux; can't easily detect on Windows).
case "$(uname -s)" in
    Linux*)
        if [ -d /usr/share/vulkan/icd.d ] && \
           [ "$(ls /usr/share/vulkan/icd.d 2>/dev/null | wc -l)" -gt 0 ]; then
            ok "Vulkan ICD registered ($(ls /usr/share/vulkan/icd.d | head -1))"
        else
            warn "no Vulkan ICD found under /usr/share/vulkan/icd.d — install vulkan-<vendor>"
            warn "  (Arch: vulkan-intel / vulkan-radeon / nvidia-utils)"
        fi
        ;;
esac

# ----- 1. ROM extract --------------------------------------------------------
log "1/8 placing ROM extract at project-assets/fft-extract/"
mkdir -p "$FFT_EXTRACT_DIR"

if [ $# -ge 1 ]; then
    SRC="$1"
    [ -d "$SRC" ] || die "FFT extract path does not exist: $SRC"
    [ -e "$SRC/BATTLE.BIN" ] || die "$SRC does not look like an FFT extract (missing BATTLE.BIN)"
    # Symlink top-level entries from the source into project-assets/fft-extract.
    # Skip entries we already have (e.g. sfx_banks/ may pre-exist locally).
    for entry in "$SRC"/*; do
        name=$(basename "$entry")
        if [ -e "$FFT_EXTRACT_DIR/$name" ]; then
            skip "$name (already present)"
        else
            ln -s "$entry" "$FFT_EXTRACT_DIR/$name"
            ok   "$name"
        fi
    done
fi

# Verify the result has what we need.
for required in BATTLE BATTLE.BIN MAP EFFECT EVENT SOUND SCUS_942.21; do
    if [ ! -e "$FFT_EXTRACT_DIR/$required" ]; then
        die "missing $FFT_EXTRACT_DIR/$required — populate project-assets/fft-extract/ first (see SETUP.md)"
    fi
done
ok "ROM extract validated: BATTLE/, BATTLE.BIN, MAP/, EFFECT/, EVENT/, SOUND/, SCUS_942.21"

# parse_range_tiles.py reads texels straight from the RAW ISO (a texture LBA),
# not from the extract — verify it's present so the RANGETILE step below can't
# silently drop the cursor tile / HUD digits / vitals bars. FFT_ISO overrides.
FFT_ISO_PATH="${FFT_ISO:-$REPO_ROOT/project-assets/Final Fantasy Tactics.bin}"
[ -e "$FFT_ISO_PATH" ] || \
    die "missing raw ISO $FFT_ISO_PATH (needed for RANGETILE) — see SETUP.md, or set FFT_ISO"
ok "raw ISO found: $(basename "$FFT_ISO_PATH")"

# ----- 2. asset directories ---------------------------------------------------
log "2/8 creating asset output directories"
for d in \
    "$GODOT_DIR/assets/sprites/animations" \
    "$GODOT_DIR/assets/sprites/textures" \
    "$GODOT_DIR/assets/sprites/textures/evtchr" \
    "$GODOT_DIR/assets/ui" \
    "$GODOT_DIR/assets/fonts" \
    "$GODOT_DIR/assets/effects" \
    "$GODOT_DIR/assets/maps" \
    "$GODOT_DIR/assets/abilities" ; do
    mkdir -p "$d"
done
ok "asset directories ready"

# ----- 3. case-correctness guards --------------------------------------------
# Per docs/adr/0001: when code and disk disagree the *code* is fixed in git, not
# patched here. The former WEP/EFF-SEQ and UIPortrait %02x→%02X sed patches are
# gone — those fixes live in tracked source (parse_seq.py, UIPortrait.gd). This
# step only warns about legacy case-folding artifacts that should never reappear.
log "3/8 checking for legacy case-folding artifacts"

# Unit.tscn once lived as a case-sensitivity symlink workaround; it is now
# tracked as Unit.tscn (capital U). The lowercase unit.tscn must not come back.
if [ -e "$GODOT_DIR/assets/scenes/unit.tscn" ]; then
    warn "found legacy lowercase assets/scenes/unit.tscn — should be Unit.tscn (capital U)"
else
    ok "no legacy lowercase unit.tscn"
fi

# ----- 4. audio addon --------------------------------------------------------
log "4/8 syncing exmateria_sound addon"
if [ -f "$GODOT_DIR/tools/sync_exmateria_sound.sh" ]; then
    bash "$GODOT_DIR/tools/sync_exmateria_sound.sh"
    ok "addon synced"
else
    warn "sync_exmateria_sound.sh missing — audio will be disabled"
fi

# ----- 5. run parsers --------------------------------------------------------
# Every parser auto-resolves to project-assets/fft-extract via _repo_paths.py,
# so no path args are required.
log "5/8 running asset parsers"

cd "$GODOT_DIR/tools"

run_parser() {
    local label="$1"; shift
    printf '  → %-32s ' "$label"
    if "$@" >/dev/null 2>&1; then
        printf '\033[1;32mok\033[0m\n'
    else
        printf '\033[1;31mFAILED\033[0m — re-run for details: %s\n' "$*"
        return 1
    fi
}

run_parser "animation SEQ (10 files)"   uv run python parse_seq.py --all
run_parser "sprite shapes SHP (10)"     uv run python parse_shp.py --all
# ⚠️ ORDER MATTERS — extract_all_sprites.py READS assets/sprites/sprite_files.json;
# it is an input there, not an output. The mapping is derived from BATTLE.BIN's
# 159-record sprite table joined against the ISO9660 walk of /BATTLE/, so it needs
# the raw image, not just the extract. Delete the artifact and the sprite extract
# dies with FileNotFoundError — which is how this ordering was found.
run_parser "sprite_id -> SPR file map"  uv run python build_sprite_file_map.py --iso "$FFT_ISO_PATH"
run_parser "sprite textures (156 TGA)"  uv run python extract_all_sprites.py
run_parser "formation sprite atlas"     uv run python parse_unit.py
# The weapon/shield battle-graphic table (BATTLE.BIN 0x2d3e4, keyed by ITEM ID,
# not by items.json's menu-icon `graphic`) and the per-family SHP frame bases it
# pairs with. Together they are "which pixels to sample for this attack frame".
run_parser "weapon battle graphics"     uv run python parse_weapon_graphic_data.py
run_parser "weapon SHP zero frames"     uv run python parse_zero_frames.py
# reaction_id -> SEQ animation per unit type, off BATTLE/*.SEQ plus the authored
# labels in tools/data/animation_names.txt.
run_parser "reaction animations"        uv run python dump_reaction_animations.py
run_parser "layer priority"             uv run python parse_layer_priority.py
run_parser "sprite type table"           uv run python parse_sprite_types.py
# Dialogue-box OPEN/CLOSE grow/shrink tween curves (BATTLE.BIN 0x80167908).
# DialogueBox.gd loads assets/ui/dialogue_box_curves.json and MUST fail loudly
# if it's missing — without it the box open/close animation has no curve data.
run_parser "dialogue box curves"        uv run python parse_dialogue_box_curves.py
# Damage/status number-popup grow/reveal/fade trending (BATTLE.BIN 0x80067bb8).
# The Q12 scale ramp + reveal stagger the ROM ships (ADR-0001/ADR-0046) — parsed,
# not hardcoded. See DAMAGE_NUMBER_DISPLAY_INVESTIGATION.md Rounds 4–5.
run_parser "number-popup trending"      uv run python parse_number_popup.py
# parse_all_maps exits non-zero whenever MAP000 / MAP053 are missing-as-expected
# (they're empty placeholders), so we don't gate on its exit code — just on the
# fact that it produced output for the maps we DO expect.
printf '  → %-32s ' "maps (≈119 of 121)"
if uv run python parse_all_maps.py "$FFT_EXTRACT_DIR/MAP" --force \
   > /tmp/bootstrap_parse_maps.log 2>&1 \
   || grep -q "Success: 11[0-9]" /tmp/bootstrap_parse_maps.log ; then
    printf '\033[1;32mok\033[0m\n'
else
    printf '\033[1;31mFAILED\033[0m — see /tmp/bootstrap_parse_maps.log\n'
    return 1
fi
# ⚠️ ORDER MATTERS — the scenario table is read by FOUR later parsers, and each
# one degrades SILENTLY without it rather than failing:
#   parse_entd.py            entd_idx -> map_id -> terrain size_z. No map, no
#                            ADR-0052 chirality flip, and `y` stays un-flipped on
#                            835 slots with only a WARN. build_roster_timeline.py
#                            then inherits the wrong coordinates.
#   parse_placement.py       the same map lookup for deployment zones.
#   parse_shop_availability  writes "" for every unlock_scenario_name.
#   export_scenario_groups / export_battle_conditionals / the chunk export
# Its own inputs are the extract plus the three authored FFTPatcher label tables
# (scenario_names/map_names/music_names.json), so it can run this early.
run_parser "scenarios (480)"            uv run python parse_scenarios.py
# The three SCUS_942.21 stat/equipment tables. `extract_abilities.py` writes
# skill_sets.json, which generate_ability_database.py joins below, so it has to
# come first; extract_items.py writes the items.json parse_attack_sounds.py
# reads for a weapon `graphic`.
run_parser "job stat tables"            uv run python extract_fft_data.py
run_parser "item + equipment tables"    uv run python extract_items.py
# WHEN a thing can be bought: the SCUS tier byte, the WORLD.BIN shop-slot mask,
# and the var[0x6F] unlock timeline folded into one artifact.
run_parser "shop availability"          uv run python parse_shop_availability.py
# Item icons out of EVENT/ITEM.BIN (4bpp pixels + 16 BGR555 palettes).
run_parser "item icons"                 uv run python extract_item_sprites.py
run_parser "ability + skill-set tables" uv run python extract_abilities.py
# The status-effect attribute table StatusRegistry.gd reads.
run_parser "status attributes"          uv run python extract_status_attributes.py
# Three outputs: effects.json, fft_names.json and ability_attributes.json (the
# ADR-0049 hit policy + ADR-0291 aim policy flags). The last had no generator at
# all until it became a third output here — see the commit that added it.
run_parser "abilities + names"          uv run python parse_abilities.py
# The inflict-status-set decode as a standalone traceability artifact; the
# parsers above call the same `_fft_decode.extract_inflict_status_sets` in
# process, so this only refreshes tools/extracted/inflict_status_sets.json.
run_parser "inflict status sets"        uv run python extract_inflict_status_sets.py
# Human-readable "what does this ability DO" annotations, derived from the
# ability_attributes.json flags + the BATTLE.BIN formula dispatch table. Needs
# BOTH of the two lines above. Lived in research/effect-meta-data/scripts/ until
# the extraction work; its output is a package asset, so the generator is one too.
run_parser "ability semantics"          uv run python seed_ability_semantics.py
# AbilityDatabase.gd + AbilityView.gd — needs effects.json + ability_attributes.json
# (parse_abilities, above) AND skill_sets.json (extract_abilities, above).
run_parser "ability database (GDScript)" uv run python generate_ability_database.py
# ⚠️ ORDER MATTERS — parse_entd.py and parse_placement.py read
# assets/maps/*/terrain.json to apply the ADR-0052 chirality flip, and when it is
# absent they only WARN: the y coordinate silently stays un-flipped on 835 slots.
# They must stay AFTER the map parse above.
run_parser "ENTD deployment tables"     uv run python parse_entd.py
run_parser "deploy zones + positions"   uv run python parse_placement.py
# Scenario-branching artifacts, all derived from the parsed scenario table above.
# battle_conditionals.json + scenario_groups.json are committed (small), but the
# per-id chunk set is gitignored (~212 MiB) — regen it here so the F3 scenario
# picker can boot any scenario id, not just the default cinematic.
# ⚠️ ORDER MATTERS — export_battle_conditionals.py READS BOTH
# assets/scenarios/battle_conditional_opcodes.json (to name each opcode) and
# assets/scenarios/scenario_groups.json, so the catalog and the groups both have
# to exist first. Transcribed from the vendored FFTPatcher XMLs under
# tools/data/vendor/, not from the ROM, which is why it can run this early.
run_parser "event opcode catalogs"      uv run python gen_opcode_catalog.py
run_parser "scenario groups"            uv run python export_scenario_groups.py
run_parser "battle conditionals"        uv run python export_battle_conditionals.py
run_parser "scenario chunks (500)"      uv run python export_all_scenario_chunks.py
# Folds scenarios.json + battle_conditionals.json + scenario_groups.json into the
# story graph GameNavigator.gd loads. All three of those are written above.
run_parser "transition graph"           uv run python build_transition_graph.py
run_parser "visual effects (401)"       uv run python parse_all_effects_py.py --force
# Both scan assets/effects/E*/ — the tree the line above writes. Run without it
# they emit a near-empty file rather than failing, so they must stay after it.
run_parser "FEDS param stats"           uv run python generate_feds_param_stats.py
run_parser "FEDS opcode coverage"       uv run python generate_feds_opcode_coverage.py
# Per-instrument sustain/one-shot facts, scanned out of the WAVESET.WD ADPCM
# block-loop flags. Reads SOUND/, not the effect tree, but belongs with the other
# FEDS tables the studio surfaces.
run_parser "FEDS instrument meta"       uv run python generate_feds_instrument_meta.py
# The TRAP particle configs baked into BATTLE.BIN (hit clouds, charge shimmer,
# summon orbs) + the TRAP1/TRAP2 palettes out of BATTLE/WEP.SPR.
run_parser "TRAP particle effects"      uv run python parse_trap_effect.py
# The untextured Gouraud projectile meshes (arrow, stone, reflect shield) baked
# into BATTLE.BIN at 0x14F9DC onward.
run_parser "projectile models"          uv run python parse_projectile_models.py
# The two global SFX banks (SOUND/SYSTEM.SED, SOUND/ENV.SED) — the death cry,
# melee hits and menu blips, none of which belong to an E###.BIN.
run_parser "global SFX banks"           uv run python parse_sfx_banks.py
# The sprite -> sound-class -> swing/hit/block mapping. Reads the SYSTEM bank
# names from the hand-authored assets/audio/sfx_banks/sfx_bank_names.json (which
# no parser writes) and items.json from extract_items.py above.
run_parser "attack sound mapping"       uv run python parse_attack_sounds.py
run_parser "bitmap font atlas"          uv run python parse_fft_font.py "$FFT_EXTRACT_DIR/BATTLE.BIN" -o "$GODOT_DIR/assets/fonts"
run_parser "UI frame.tga"               uv run python parse_frame.py
run_parser "HUD number font"            uv run python parse_frame_font.py
# The world map screen: WLDTEX.TM2 replayed into a 1024x512 VRAM image, plus
# EVENT/FRAME.BIN's shared UI band and CLUT tail, plus the WLDCORE.BIN model
# (nodes, cels, frame lists, routes, the START menu and the Move place list).
# Both outputs are gitignored and regenerable; without this step WorldMapAssets
# fails with "vram.bin missing" and the world map does not render at all.
run_parser "world map (VRAM + model)"   uv run python parse_world_map.py
# The story roster timeline — who joins, at which group, in what order. Reads
# entd.json, scenario_groups.json and transition_graph.json (all above) plus
# assets/world_map/events.json, which is why it sits after the world-map parse
# rather than with the other scenario artifacts.
run_parser "roster timeline"            uv run python build_roster_timeline.py
# RANGETILE atlas (from the raw ISO) — the cursor highlight tile, HUD damage
# digits, and the HP/MP/CT vitals bars all sample it. Missing it blanks the
# active-cursor barber-pole tile (and the HUD) even though every other sprite
# is fine. Writes RANGETILE.tga/.palette.tga/.json.
run_parser "range tiles + HUD digits"   uv run python parse_range_tiles.py --iso "$FFT_ISO_PATH"
# The at-rest cursor bob tables (ADR-0046): FFT ships the vertical offsets, it
# does not synthesize them from a curve. GloveCursorBob.gd + RangeTileAtlas.gd.
run_parser "cursor bob tables"          uv run python parse_cursor_bob.py
# Formation-screen cobblestone background: a 128x32 tile + slot-14 CLUT from the
# SAME LBA 0xE68 FRAME/range sheet parse_range_tiles reads (ShiShi RANGEFILE.TGA).
run_parser "formation background tile"  uv run python parse_formation_background.py --iso "$FFT_ISO_PATH"
# Formation-screen glowing blue orb: a 12x12 sprite + slot-20 CLUT from the same
# LBA 0xE68 FRAME/range sheet. Drawn additive; selected cell pulses (FORMATION_SCREEN.md sec 10).
run_parser "formation orb sprite"       uv run python parse_formation_orb.py --iso "$FFT_ISO_PATH"
# Formation-screen gold selection BOX: the isometric diamond frame under the
# SELECTED unit (the battle tile-cursor reused on the roster), a ¼ texel + CLUT
# off the same LBA 0xE68 FRAME/range sheet. FormationScene.gd loads BOX.tga +
# BOX.palette.tga directly, so without this the selected cell loses its frame
# while every other formation asset looks fine (FORMATION_SCREEN.md sec 11).
run_parser "formation selection box"    uv run python parse_formation_box.py --iso "$FFT_ISO_PATH"
# Box-trail glide fade ramp (WORLD.BIN 0x8018C88C) — ROM-parsed, not transcribed (ADR-0046).
run_parser "formation data tables"      uv run python parse_formation_tables.py
# EVTCHR.BIN cinematic event sprites (Ovelia's nod, Ramza's kneel, etc.).
# THREE outputs, all required — missing any one blanks the cinematic anims:
#   bake_evtchr_textures.py → assets/sprites/textures/evtchr/segment_*.tga (+palette)  [the pixels]
#   parse_evtchr_frames.py  → assets/sprites/animations/evtchr_frames.json             [frame→block rects]
#   parse_cinematic_seq.py  → assets/sprites/animations/cinematic_seq.json             [the SEQ walker that
#                                                                                        sequences the frames]
# Without cinematic_seq.json, _play_cinematic_unit_anim aborts for every anim and
# NOTHING cinematic renders even though the textures exist.
# The bake must run BEFORE the step-6 Godot import so the new TGAs get imported.
run_parser "EVTCHR event textures (137)"  uv run python bake_evtchr_textures.py
run_parser "EVTCHR cinematic frames"      uv run python parse_evtchr_frames.py
run_parser "EVTCHR cinematic SEQ walker"  uv run python parse_cinematic_seq.py
# {7D} ShowGraphic textures: chapter title cards, ending stills, GAME OVER, and
# the 131 WLDBK world backgrounds (Shishi can't load WLDBK — it's a headerless
# raw-framebuffer container). Writes assets/scenarios/graphics/*.png + manifest.
run_parser "ShowGraphic textures (140)"   uv run python parse_show_graphics.py
# {91} ShowMapTitle textures: the 115 inked pre-battle location-name strips from
# EVENT/MAPTITLE.BIN (256x20 4bpp, 2560B stride, fixed grey CLUT). Writes
# assets/scenarios/map_titles/*.png + manifest (incl. the map_id_to_slot table,
# derived as map_id-1 per the ATTACK.OUT worker). show_map_title_op91_decode.md.
run_parser "ShowMapTitle textures (115)"  uv run python parse_map_titles.py
# {50} Portrait Row event-dialogue portraits: the 64-cell EVTFACE.BIN grid
# (8x8 of 32x48 4bpp, inline BGR555 CLUT). The message-box face for scripted
# cutscenes (Balbanes deathbed etc.); distinct from the in-battle unit-SPR path.
# Writes assets/scenarios/faces/face_r<R>_c<C>.png + evtface.json.
# PORTRAIT_ROW_OPCODE_50_EVTFACE.md.
run_parser "EVTFACE event portraits (64)" uv run python parse_evtface.py
# {78} DisplayConditions screens: the battle intro banner ("Conditions for
# Winning" / "READY!") and the whole outro (CONGRATULATIONS!, BONUS MONEY + the
# gil reel). Two disc files, no savestate — EVENT/BONUS.BIN (36 pages: font sheet
# + per-battle victory banner) and EVENT/REQUIRE.OUT (the overlay's own glyph and
# layout tables, load base 0x801BF000). Writes assets/scenarios/results/*.png +
# results.json. Without it ScenarioResultsScreen draws the overlay and nothing on
# top, warning only. BATTLE_RESULTS_SCREEN.md.
run_parser "results screens + gil reel"   uv run python parse_bonus.py
# Character template packets (wayfinder #201): slices a folder-per-key packet
# (body/portrait/template.json) out of the FLAT assets/sprites/textures/ store,
# per docs/TEMPLATE_JSON_SCHEMA.md + ADR-0072 dec.3. The catalogue addon reads
# this tree through CatalogueContent.TEMPLATES_SUBPATH.
# ⚠️ ORDER MATTERS — it is a post-pass over the flat extract, so it must stay
# AFTER extract_all_sprites.py and after the EVTCHR/EVTFACE atlases above (the
# #204 event derivation slices those; absent them it emits body/portrait only).
run_parser "character templates"          uv run python align_character_templates.py
ok "all parsers complete"

# ----- 6. Godot import -------------------------------------------------------
log "6/8 running Godot import"
# Force every .tga .import to lossless + no 3D auto-compression BEFORE importing,
# so the cache is rebuilt from the corrected settings. New .import files (fresh
# checkout) are seeded lossless by [importer_defaults] in project.godot; this
# repairs any that predate that default or were auto-flipped to VRAM (mode 2).
( cd "$GODOT_DIR" && uv run python tools/normalize_texture_imports.py ) || \
    warn "texture-import normalize reported an issue (continuing)"
if godot --import --path "$GODOT_DIR" > /tmp/bootstrap_godot_import.log 2>&1; then
    ok "import done (.godot/imported populated, class cache refreshed)"
else
    warn "import returned non-zero; see /tmp/bootstrap_godot_import.log"
fi

# ----- 7. summary ------------------------------------------------------------
log "7/8 summary"
echo "  sprite TGAs:        $(ls "$GODOT_DIR/assets/sprites/textures"/*.tga 2>/dev/null | wc -l)"
echo "  animation JSONs:    $(ls "$GODOT_DIR/assets/sprites/animations"/*.json 2>/dev/null | wc -l)"
echo "  EVTCHR seg TGAs:    $(ls "$GODOT_DIR/assets/sprites/textures/evtchr"/segment_*.tga 2>/dev/null | grep -vc palette)"
echo "  EVTCHR frames JSON: $([ -f "$GODOT_DIR/assets/sprites/animations/evtchr_frames.json" ] && echo present || echo MISSING)"
echo "  cinematic SEQ JSON: $([ -f "$GODOT_DIR/assets/sprites/animations/cinematic_seq.json" ] && echo present || echo MISSING)"

# Sanity-check: no uppercase .TGA artifacts. These shouldn't be produced by any
# parser; they accumulate as case-bridging symlinks + Godot import duplicates
# whose root cause has been fixed. Catch regressions early.
stray_tga=$(find "$GODOT_DIR/assets/sprites/textures" -maxdepth 1 \( -name "*.TGA" -o -name "*.TGA.import" -o -name "*.TGA.IMPORT" \) 2>/dev/null)
if [ -n "$stray_tga" ]; then
    warn "stray uppercase .TGA artifacts found — none of these are produced by parsers"
    echo "$stray_tga" | sed 's/^/    /'
    echo "  (clean with: find $GODOT_DIR/assets/sprites/textures -name '*.TGA*' -delete)"
fi
echo "  maps:               $(ls -d "$GODOT_DIR/assets/maps"/MAP* 2>/dev/null | wc -l)"
echo "  effects:            $(ls -d "$GODOT_DIR/assets/effects"/E* 2>/dev/null | wc -l)"
echo "  font atlas:         $([ -f "$GODOT_DIR/assets/fonts/font_atlas.tga" ] && echo present || echo MISSING)"
echo "  UI frame:           $([ -f "$GODOT_DIR/assets/ui/frame.tga" ] && echo present || echo MISSING)"
echo "  world map VRAM:     $([ -s "$GODOT_DIR/assets/world_map/vram.bin" ] && echo present || echo MISSING)"
echo "  world map model:    $([ -s "$GODOT_DIR/assets/world_map/model.json" ] && echo present || echo MISSING)"
echo "  dialogue box curves:$([ -f "$GODOT_DIR/assets/ui/dialogue_box_curves.json" ] && echo ' present' || echo ' MISSING')"
echo "  audio addon:        $([ -f "$GODOT_DIR/addons/exmateria_sound/plugin.cfg" ] && echo present || echo MISSING)"

log "8/8 done"
cat <<EOF

  Launch the game with:
    godot --path '$GODOT_DIR' res://assets/scenes/GPUArena.tscn

  Known cosmetic warnings on first launch (not blockers):
    - File not found: …/*_names.json
      (these are hand-authored; no parser regenerates them)
    - Parse Error: Identifier "WavesetParser"/"Spu"/"SMDPlayer" (audio)
      (autoload chain fails if libexmateria_spu.so isn't built; game still runs,
       just silent. Build it with `cd exmateria-sound && scons` then re-run sync.)
EOF
