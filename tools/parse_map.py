#!/usr/bin/env python3
"""
FFT Map Parser - Single map orchestrator.

Parses a .GNS map file and outputs Godot-ready files to the maps folder.

Pipeline:
    MAP###.GNS → fft_exporter → preprocess_doodad → split_manifest → output

Usage:
    python tools/parse_map.py /path/to/MAP022.GNS
    python tools/parse_map.py /path/to/MAP022.GNS --output assets/maps/MAP022
"""

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path
from typing import List, Optional

# Disable bytecode caching to avoid stale .pyc files on WSL/Windows filesystem
sys.dont_write_bytecode = True

# Add tools directory to path for imports
TOOLS_DIR = Path(__file__).parent
sys.path.insert(0, str(TOOLS_DIR))

from fft_exporter.parsers.gns import load_map
from fft_exporter.parsers.palette import parse_palettes, parse_palette_animation_frames
from fft_exporter.parsers.mesh import parse_mesh
from fft_exporter.parsers.terrain import parse_terrain
from fft_exporter.parsers.lighting import parse_lighting
from fft_exporter.parsers.animation import parse_texture_animations, parse_texture_animation_slots
from fft_exporter.parsers.mesh_animation import parse_mesh_animation_set, parse_animated_meshes
from fft_exporter.exporters.texture import (
    export_textures,
    export_palettes_json,
    export_indexed_texture,
)
from fft_exporter.exporters.geometry import export_geometry
from fft_exporter.exporters.terrain import export_terrain
from fft_exporter.exporters.manifest import export_manifest
from fft_exporter.exporters.mesh_animation import (
    export_mesh_animation,
    export_animated_mesh_geometry,
    build_mesh_animation_manifest,
)
from fft_exporter.models.map_resource import (
    MapResource,
    MapArrangementState,
    MapTime,
    MapWeather,
)
from fft_exporter.map_states import (
    MapStateRef,
    build_states_index,
    enumerate_map_states,
    resolve_palette_sidecars,
    resolve_state_exports,
    resolve_texture_sidecars,
)
from preprocess_doodad import preprocess_doodad
from split_manifest import split_manifest


# Default output directory (relative to project root, not tools/)
DEFAULT_OUTPUT_BASE = TOOLS_DIR.parent / "assets" / "maps"


def find_texture_for_state(
    texture_resources: List[MapResource],
    arrangement: MapArrangementState,
    time: MapTime,
    weather: MapWeather,
) -> Optional[MapResource]:
    """Texture resource matching a state's (arrangement, time, weather).

    Most maps ship a single texture reused across every state, so this falls
    back to the first texture resource — matching the default-state idiom.
    """
    for r in texture_resources:
        if (r.arrangement == arrangement and
            r.time == time and
            r.weather == weather):
            return r
    return texture_resources[0] if texture_resources else None


def _state_texture_payload(
    state,
    default_tex: Optional[MapResource],
    texture_resources: List[MapResource],
) -> Optional[bytes]:
    """Raw texture-resource bytes a resolved state renders with (for dedup).

    The default state's payload is pinned to the root texture (``default_tex`` =
    the PRIMARY/DAY/NONE resource that ``texture_indexed.tga`` is baked from), so
    the sidecar dedup keys every other state against the exact root bytes. A
    non-default state resolves its own texture by (arrangement, time, weather),
    falling back to the first texture resource — the same rule the export uses.
    """
    if state.state.is_default:
        return default_tex.resource_data if default_tex else None
    st = state.state
    tex = find_texture_for_state(texture_resources, st.arrangement, st.time, st.weather)
    return tex.resource_data if tex else None


def mesh_geometry_signature(resource_data: bytes) -> Optional[str]:
    """Content hash of a mesh resource's primary-mesh geometry (System-C dedup).

    Returns None when the row carries no primary mesh (null 0x40 pointer ->
    zero polygons; a lighting/palette-only override). Two rows with the same
    signature swap in byte-identical geometry, so only one needs exporting —
    this is how MAP064's PRIMARY OVERRIDE collapses onto PRIMARY INITIAL.
    """
    polygons = parse_mesh(resource_data)
    if sum(len(v) for v in polygons.values()) == 0:
        return None
    h = hashlib.sha1()
    for ptype in sorted(polygons, key=lambda p: p.value):
        for poly in polygons[ptype]:
            h.update(repr(poly).encode())
    return h.hexdigest()


def _safe_signature(state: MapStateRef) -> Optional[str]:
    """Geometry signature for dedup, resilient to a malformed alternate row.

    The signature pre-pass parses *every* state's mesh up front, before the
    default export runs. A corrupt non-default row must not abort the whole map
    (the old single-state path only ever parsed the default mesh). On a parse
    failure we treat the row as carrying no own geometry: it falls back to
    reusing the default geometry and is still listed in states[].
    """
    try:
        return mesh_geometry_signature(state.resource.resource_data)
    except Exception as e:
        print(f"  WARNING: state {state.subdir} mesh unreadable ({e}); "
              f"treating as no own geometry")
        return None


def _safe_lighting(resource_data: Optional[bytes]):
    """Parse a state's lighting, tolerating a missing/malformed chunk (→ None).

    Mirrors _safe_signature: enumerating every state's env up front must never
    abort the map — a row without readable lighting simply falls back to the
    engine-default sky in the states[] index.
    """
    if not resource_data:
        return None
    try:
        return parse_lighting(resource_data)
    except Exception as e:
        print(f"  WARNING: state lighting unreadable ({e}); using default sky")
        return None


def _safe_palette_set(resource_data: Optional[bytes]):
    """Parse a state's 16 palettes, or None when the row carries no palette.

    An env-only weather/night row often patches only lighting (null palette
    pointer) — such rows reuse the root palettes.json (palette_file == null).
    """
    if not resource_data:
        return None
    try:
        palettes, has_palettes = parse_palettes(resource_data)
        return palettes if has_palettes else None
    except Exception as e:
        print(f"  WARNING: state palettes unreadable ({e}); reusing root palette")
        return None


def _safe_palette_frames(resource_data: Optional[bytes]):
    """Parse a state's palette-animation frames (offset 112), or [] if none.

    The frame table is the map's cycling-water/lava palette (#132). A state that
    overrides only its base CLUT (day-weather rows) carries a null frame pointer
    and inherits the DEFAULT state's frames — resolve_palette_sidecars applies
    that fallback; here we just report what this row itself carries.
    """
    if not resource_data:
        return []
    try:
        return parse_palette_animation_frames(resource_data)
    except Exception as e:
        print(f"  WARNING: state palette-animation frames unreadable ({e})")
        return []


def _prune_dangling_state_dirs(output_dir: Path) -> None:
    """Drop states[] entries whose geometry directory was never created.

    The states[] index is written into the root scene manifest *before* the
    alternate states are exported, and an alternate export can warn-and-continue
    on failure. If one failed, its states/<subdir> never materialised — remove
    any entry pointing at a missing directory (and any other state that
    deduplicated onto it) so the published manifest never advertises a state
    that isn't on disk. ``dir == "."`` (default / reuses-default geometry) is
    always kept.
    """
    manifest_path = output_dir / "scene_manifest.json"
    if not manifest_path.exists():
        return
    data = json.loads(manifest_path.read_text())
    states = data.get("states")
    if not states:
        return
    kept = [
        s for s in states
        if s.get("dir") == "." or (output_dir / s["dir"]).is_dir()
    ]
    if len(kept) != len(states):
        data["states"] = kept
        with manifest_path.open("w") as f:
            json.dump(data, f, indent=2)
        print(f"  Pruned {len(states) - len(kept)} dangling states[] entries "
              f"(alternate export failed)")


def export_state(
    mesh_resource: MapResource,
    texture_resource: MapResource,
    map_name: str,
    output_dir: Path,
    verbose: bool = False,
    states_index: List[dict] = None,
    fallback_size_z_psx_units: int = 0,
) -> bool:
    """Export one GNS map state's files into output_dir.

    Writes texture/palettes, geometry, terrain, System-B mesh animation (if
    present), and the manifest for the given (mesh, texture) resource pair. The
    optional states_index (root state only) adds the System-C states[] index to
    the manifest.

    Returns True on success, False if the resources are missing.
    """
    if not mesh_resource or not texture_resource:
        print(f"  ERROR: Could not find mesh and texture resources")
        return False

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Export textures and palettes
    palettes, has_palettes = parse_palettes(mesh_resource.resource_data)
    if not has_palettes:
        palettes = []

    animation_frames = parse_palette_animation_frames(mesh_resource.resource_data)
    export_textures(
        texture_resource.resource_data,
        palettes,
        animation_frames,
        output_dir,
        verbose=verbose,
    )

    # Parse terrain first so we know size_z, which mesh export needs for
    # the parser-time Z-flip (ADR-0052). PSX uses 28 position-units per tile.
    # An alternate state that overrides only the primary mesh carries a null
    # terrain pointer and inherits the default state's terrain (see
    # _INHERITABLE_FILES). It must flip its geometry against that inherited
    # size_z (fallback_size_z_psx_units), NOT 0 — a 0 skips the flip and exports
    # the override geometry Z-mirrored relative to the tile grid it shares.
    terrain = parse_terrain(mesh_resource.resource_data)
    if terrain is not None:
        size_z_psx_units = terrain.size_z * 28
    else:
        size_z_psx_units = fallback_size_z_psx_units

    # Parse and export mesh
    polygons = parse_mesh(mesh_resource.resource_data)
    export_geometry(polygons, output_dir, size_z_psx_units, verbose=verbose)

    if terrain:
        export_terrain(terrain, output_dir, verbose=verbose)

    # Parse + export System-B mesh animation (moving geometry). Absent on
    # most maps — parse_mesh_animation_set returns None, leaving the ~108
    # static maps unchanged (no new files, no manifest block). The animated
    # meshes are only parsed when the 0x8C chunk is present, so static maps
    # pay nothing for this. Note: MAP053/MAP083 carry their 0x8C chunk only in
    # the SECONDARY arrangement, so the per-state export here picks it up for
    # those alternate states even though the default state has none.
    mesh_anim_set = parse_mesh_animation_set(mesh_resource.resource_data)
    mesh_animation_manifest = None
    if mesh_anim_set is not None:
        animated_meshes = parse_animated_meshes(mesh_resource.resource_data)
        export_mesh_animation(mesh_anim_set, animated_meshes, output_dir, verbose=verbose)
        export_animated_mesh_geometry(animated_meshes, output_dir, size_z_psx_units, verbose=verbose)
        mesh_animation_manifest = build_mesh_animation_manifest(mesh_anim_set, animated_meshes)

    # Parse lighting and animations, export manifest
    lighting = parse_lighting(mesh_resource.resource_data)
    uv_animations, palette_animations = parse_texture_animations(mesh_resource.resource_data)
    texture_animation_slots = parse_texture_animation_slots(mesh_resource.resource_data)

    export_manifest(
        map_name=map_name,
        arrangement=mesh_resource.arrangement.name.title(),
        time=mesh_resource.time.name.title(),
        weather=mesh_resource.weather.name.title(),
        lighting=lighting,
        uv_animations=uv_animations,
        palette_animations=palette_animations,
        polygons=polygons,
        palettes=palettes,
        output_dir=output_dir,
        verbose=verbose,
        texture_animation_slots=texture_animation_slots,
        mesh_animation_manifest=mesh_animation_manifest,
        states=states_index,
    )

    return True


def copy_final_files(source_dir: Path, dest_dir: Path, verbose: bool = False) -> None:
    """
    Copy the final runtime files from source to destination.

    Files copied:
    - terrain.json
    - geometry_linked.json (NOT geometry.json)
    - palettes.json
    - manifest_doodad.json → manifest.json (renamed)
    - scene_manifest.json
    - texture_indexed.tga

    Args:
        source_dir: Directory containing processed files
        dest_dir: Destination directory
        verbose: Enable verbose logging
    """
    dest_dir.mkdir(parents=True, exist_ok=True)

    # Files to copy directly
    direct_copy = [
        "terrain.json",
        "geometry_linked.json",
        "palettes.json",
        "scene_manifest.json",
        "texture_indexed.tga",
    ]

    for filename in direct_copy:
        src = source_dir / filename
        dst = dest_dir / filename
        if src.exists():
            shutil.copy2(src, dst)
            if verbose:
                print(f"  Copied: {filename}")
        else:
            print(f"  WARNING: Missing file: {filename}")

    # Rename manifest_doodad.json → manifest.json
    doodad_manifest = source_dir / "manifest_doodad.json"
    if doodad_manifest.exists():
        shutil.copy2(doodad_manifest, dest_dir / "manifest.json")
        if verbose:
            print(f"  Copied: manifest_doodad.json → manifest.json")

    # System B (moving geometry) — present only for animated maps. Carry the
    # mesh-animation set + per-mesh geometry to the output dir.
    mesh_anim = source_dir / "mesh_animation.json"
    if mesh_anim.exists():
        shutil.copy2(mesh_anim, dest_dir / "mesh_animation.json")
        if verbose:
            print(f"  Copied: mesh_animation.json")
        anim_src = source_dir / "anim_meshes"
        if anim_src.is_dir():
            shutil.copytree(anim_src, dest_dir / "anim_meshes", dirs_exist_ok=True)
            if verbose:
                print(f"  Copied: anim_meshes/")


# Base file a partial-override state may omit (null terrain pointer), inheriting
# it from the default state instead. preprocess_doodad needs terrain.json to
# correlate triangles with tiles. (palettes.json / texture_indexed.tga are
# always re-written by export_state, so they are never actually inherited;
# per-state palette inheritance is #132's scope.)
_INHERITABLE_FILES = ("terrain.json",)


def _run_state_pipeline(
    mesh_resource: MapResource,
    texture_resource: MapResource,
    map_name: str,
    dest_dir: Path,
    verbose: bool,
    states_index: List[dict] = None,
    inherit_from: Path = None,
    fallback_size_z_psx_units: int = 0,
) -> bool:
    """Run the full export pipeline for one state into dest_dir.

    parse (export_state) → preprocess_doodad → split_manifest → copy_final_files,
    each step against a private temp dir so the runtime files (geometry_linked,
    doodad/scene manifests) match the root layout. states_index is forwarded to
    the manifest for the root state only.

    Alternate states often override only the primary mesh and carry null
    terrain/palette/texture pointers; inherit_from (the already-exported default
    state dir) supplies any such missing base file so geometry linking still
    succeeds against the shared tile grid.
    """
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)

        try:
            exported = export_state(
                mesh_resource, texture_resource, map_name, temp_path,
                verbose=verbose, states_index=states_index,
                fallback_size_z_psx_units=fallback_size_z_psx_units,
            )
        except Exception as e:
            # Old single-state path caught every parse error and returned False;
            # preserve that so a malformed mesh fails this state cleanly (the
            # caller decides whether that's fatal — default — or warn-and-skip).
            print(f"  ERROR exporting state: {e}")
            if verbose:
                import traceback
                traceback.print_exc()
            return False
        if not exported:
            return False

        if inherit_from is not None:
            for name in _INHERITABLE_FILES:
                target = temp_path / name
                source = inherit_from / name
                if not target.exists() and source.exists():
                    shutil.copy2(source, target)
                    if verbose:
                        print(f"  Inherited {name} from default state")

        try:
            preprocess_doodad(temp_path)
        except SystemExit:
            print(f"  ERROR: preprocess_doodad failed")
            return False

        try:
            split_manifest(temp_path)
        except SystemExit:
            print(f"  ERROR: split_manifest failed")
            return False

        copy_final_files(temp_path, dest_dir, verbose)

    return True


def parse_map(gns_path: Path, output_dir: Path = None, verbose: bool = False) -> bool:
    """
    Full pipeline: Parse .GNS file and output Godot-ready files for every state.

    A map's GNS index lists multiple mesh states (System C — arrangement / time /
    weather). The default PRIMARY/DAY/NONE state exports to the map root
    (unchanged); every distinct alternate baked geometry (e.g. the Bethla Sluice
    open gate) exports into states/<arrangement>_<time>_<weather>/. States that
    carry no own geometry, or whose geometry duplicates an already-exported
    state, are not re-exported but are still listed in the root manifest's
    states[] index.

    Args:
        gns_path: Path to the .GNS map file
        output_dir: Output directory (default: assets/maps/MAP###)
        verbose: Enable verbose logging

    Returns:
        True on success (default state exported), False on failure
    """
    # Extract map name from filename (e.g., MAP022.GNS → MAP022)
    map_name = gns_path.stem.upper()

    # Default output directory
    if output_dir is None:
        output_dir = DEFAULT_OUTPUT_BASE / map_name

    print(f"\n=== PARSING MAP: {map_name} ===\n")
    print(f"Source: {gns_path}")
    print(f"Output: {output_dir}")

    # Load the map once and enumerate its states.
    try:
        _all, mesh_resources, texture_resources, loaded_name = load_map(gns_path)
    except Exception as e:
        print(f"  ERROR loading {gns_path}: {e}")
        if verbose:
            import traceback
            traceback.print_exc()
        return False

    if not mesh_resources or not texture_resources:
        print(f"  ERROR: Could not find mesh and texture resources")
        return False

    states = enumerate_map_states(mesh_resources)
    signatures = [_safe_signature(s) for s in states]
    resolved = resolve_state_exports(states, signatures)

    # The default (root) export must reproduce the long-standing single-state
    # output byte-for-byte: its texture is the PRIMARY/DAY/NONE row (else the
    # first texture), independent of which mesh row _pick_default settled on when
    # no PRIMARY/DAY/NONE mesh exists. Computed up front because the texture
    # sidecar dedup below keys every state against this exact root payload.
    default_tex = find_texture_for_state(
        texture_resources,
        MapArrangementState.PRIMARY, MapTime.DAY, MapWeather.NONE,
    )

    # states[] is the "map states" index (ADR-0056): every arrangement/time/
    # weather row with its own environment (sky gradient + ambient + directional
    # lights), palette, and texture, so the runtime can select a weather/night
    # sky — not just alternate baked geometry. Emit it whenever the map ships more
    # than the single default row (single-state maps stay unchanged: no states[]).
    palette_sidecars: dict = {}
    texture_sidecars: dict = {}
    if len(resolved) > 1:
        lightings = [_safe_lighting(rs.state.resource.resource_data) for rs in resolved]
        palette_sets = [
            _safe_palette_set(rs.state.resource.resource_data) for rs in resolved
        ]
        frame_sets = [
            _safe_palette_frames(rs.state.resource.resource_data) for rs in resolved
        ]
        palette_files, palette_sidecars = resolve_palette_sidecars(
            resolved, palette_sets, frame_sets
        )
        # Per-state texture (orthogonal to palette): each state resolves its own
        # texture resource by (arrangement, time, weather); the default state's is
        # the root texture_indexed.tga (default_tex), so pin index 0 to it exactly.
        texture_payloads = [
            _state_texture_payload(rs, default_tex, texture_resources)
            for rs in resolved
        ]
        texture_files, texture_sidecars = resolve_texture_sidecars(
            resolved, texture_payloads
        )
        states_index = build_states_index(
            resolved, lightings, palette_files, texture_files
        )
    else:
        states_index = None

    # Drop any stale states/ subtree from a previous parse so removed/renamed
    # states don't linger (gitignored build artifact; safe to rebuild).
    stale_states = output_dir / "states"
    if stale_states.exists():
        shutil.rmtree(stale_states)

    # Drop stale root palette sidecars too: the sidecar filename is content-
    # hashed, so a re-parse (or a hash-scheme change, e.g. #132 folding the
    # animation frames into the key) renames them and would otherwise orphan the
    # old files. The ones we still want get rewritten below; the current
    # palettes.json is never matched by this glob.
    for stale_sidecar in output_dir.glob("palettes_*.json"):
        stale_sidecar.unlink()

    # Drop stale root texture sidecars for the same reason — content-hashed names
    # orphan on re-parse. The root texture_indexed.tga (and its .import) is NOT a
    # sidecar and must survive the glob, so skip anything named texture_indexed.*.
    for pattern in ("texture_*.tga", "texture_*.tga.import"):
        for stale_sidecar in output_dir.glob(pattern):
            if stale_sidecar.name.startswith("texture_indexed."):
                continue
            stale_sidecar.unlink()

    # Export the default (root) state first — its success gates the whole map.
    # enumerate_map_states always prepends the default, so it is resolved[0].
    default_rs = resolved[0]
    print(f"\n[default] PRIMARY/DAY/NONE → {output_dir}")
    if not _run_state_pipeline(
        default_rs.state.resource, default_tex, map_name, output_dir,
        verbose, states_index,
    ):
        return False

    # Write the deduped per-state palette sidecars into the map root, referenced
    # by each state's palette_file. Same schema as palettes.json so the runtime
    # palette loader is reused. Each sidecar carries its per-state palette-cycling
    # animation frames (#132) — its own offset-112 table when the state overrides
    # it (e.g. night water), else the default state's frames (day-weather rows
    # that only patch the base CLUT), so the shader animates the correct palette.
    for fname, (pset, frames) in palette_sidecars.items():
        export_palettes_json(pset, frames, output_dir / fname)
        if verbose:
            print(f"  Wrote palette sidecar: {fname} ({len(frames)} anim frames)")

    # Write the deduped per-state texture sidecars (texture_<hash>.tga) into the
    # map root, referenced by each state's texture_file. Same grayscale-indexed
    # format as the root texture_indexed.tga so the runtime texture loader is
    # reused; the shader samples them against whichever palette the state selects.
    # A fresh `godot --import` pass (bootstrap_assets.sh) generates each sidecar's
    # .import so the runtime load()s the imported resource, not the raw .tga.
    for fname, payload in texture_sidecars.items():
        export_indexed_texture(payload, output_dir / fname)
        if verbose:
            print(f"  Wrote texture sidecar: {fname}")

    # Alternate states that override only the primary mesh carry a null terrain
    # pointer and inherit the default's terrain; they must flip their geometry
    # against the default's size_z (ADR-0052), so capture it once here.
    default_terrain = parse_terrain(default_rs.state.resource.resource_data)
    default_size_z_psx_units = (
        default_terrain.size_z if default_terrain else 0
    ) * 28

    # Export each distinct alternate geometry into states/<subdir>/. A failure
    # here warns but does not fail the map — the default state is what callers
    # depend on today.
    exported_alts = 0
    for rs in resolved:
        if rs.state.is_default or not rs.export:
            continue
        st = rs.state
        dest = output_dir / "states" / st.subdir
        tex = find_texture_for_state(
            texture_resources, st.arrangement, st.time, st.weather
        )
        print(f"[state] {st.arrangement.name}/{st.time.name}/{st.weather.name} "
              f"({st.resource_type_label}) → {dest}")
        if _run_state_pipeline(st.resource, tex, map_name, dest, verbose,
                               inherit_from=output_dir,
                               fallback_size_z_psx_units=default_size_z_psx_units):
            exported_alts += 1
        else:
            print(f"  WARNING: state {st.subdir} failed to export (continuing)")

    # A warned-and-continued alternate failure above leaves its states[] entry
    # pointing at a states/<subdir> that was never created; drop such entries so
    # the manifest only advertises geometry that's actually on disk.
    if states_index is not None:
        _prune_dangling_state_dirs(output_dir)

    # Summary
    print(f"\n=== MAP PARSED SUCCESSFULLY ===")
    print(f"Output: {output_dir}")
    if exported_alts:
        print(f"Alternate geometry states exported: {exported_alts}")
    print(f"Files:")
    for f in sorted(output_dir.iterdir()):
        if f.is_dir():
            print(f"  {f.name}/ (dir)")
            continue
        size_kb = f.stat().st_size / 1024
        print(f"  {f.name}: {size_kb:.1f} KB")
    print()

    return True


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Parse FFT map file (.GNS) to Godot-ready format",
        prog="parse_map",
    )
    parser.add_argument(
        "gns_file",
        type=Path,
        help="Path to the .GNS map file",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=None,
        help="Output directory (default: assets/maps/MAP###)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output",
    )

    args = parser.parse_args()

    # Validate input file
    if not args.gns_file.exists():
        print(f"ERROR: File not found: {args.gns_file}")
        sys.exit(1)

    if args.gns_file.suffix.lower() != ".gns":
        print(f"ERROR: Expected .gns file, got {args.gns_file.suffix}")
        sys.exit(1)

    # Run pipeline
    success = parse_map(args.gns_file, args.output, args.verbose)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
