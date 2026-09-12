"""CLI entry point for FFT Map Exporter."""

import argparse
import sys
from pathlib import Path

from .parsers.gns import load_map
from .parsers.palette import parse_palettes, parse_palette_animation_frames
from .parsers.mesh import parse_mesh, get_polygon_counts
from .parsers.terrain import parse_terrain
from .parsers.lighting import parse_lighting
from .parsers.animation import parse_texture_animations, parse_texture_animation_slots
from .parsers.mesh_animation import parse_mesh_animation_set, parse_animated_meshes
from .exporters.texture import export_textures
from .exporters.geometry import export_geometry
from .exporters.terrain import export_terrain
from .exporters.manifest import export_manifest
from .exporters.mesh_animation import (
    export_mesh_animation,
    export_animated_mesh_geometry,
    build_mesh_animation_manifest,
)
from .models.map_resource import (
    ResourceType,
    MapArrangementState,
    MapTime,
    MapWeather,
)


def print_summary(all_resources, mesh_resources, texture_resources, map_name):
    """Print a summary of loaded resources."""
    print(f"Map: {map_name}")
    print(f"Total resources: {len(all_resources)}")
    print(f"  Mesh resources: {len(mesh_resources)}")
    print(f"  Texture resources: {len(texture_resources)}")
    print()

    # Group by type
    type_counts = {}
    for resource in all_resources:
        type_name = resource.resource_type.name
        type_counts[type_name] = type_counts.get(type_name, 0) + 1

    print("Resource types:")
    for type_name, count in sorted(type_counts.items()):
        print(f"  {type_name}: {count}")
    print()

    # Show details for each resource
    print("Resources:")
    for i, resource in enumerate(all_resources):
        res_type = "Mesh" if resource.is_mesh else "Texture"
        data_size = len(resource.resource_data) if resource.resource_data else 0
        print(
            f"  [{i}] {res_type} | "
            f"{resource.arrangement.name} | "
            f"{resource.time.name} | "
            f"{resource.weather.name} | "
            f"Sector {resource.file_sector} | "
            f"File .{resource.x_file} | "
            f"{data_size:,} bytes"
        )


def main():
    parser = argparse.ArgumentParser(
        description="FFT Map Exporter - Extract FFT map data to various formats",
        prog="fft_exporter",
    )
    parser.add_argument(
        "map_file",
        type=Path,
        help="Path to the .GNS map file",
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("./export"),
        help="Output directory (default: ./export)",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print resource summary and exit (no export)",
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose output",
    )

    args = parser.parse_args()

    # Validate input file
    if not args.map_file.exists():
        print(f"Error: Map file not found: {args.map_file}", file=sys.stderr)
        sys.exit(1)

    if args.map_file.suffix.lower() != ".gns":
        print(f"Error: Expected .gns file, got {args.map_file.suffix}", file=sys.stderr)
        sys.exit(1)

    # Load map
    try:
        all_resources, mesh_resources, texture_resources, map_name = load_map(args.map_file)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if args.summary:
        print_summary(all_resources, mesh_resources, texture_resources, map_name)
        sys.exit(0)

    # Create output directory
    args.output.mkdir(parents=True, exist_ok=True)

    print(f"Loaded map: {map_name}")
    print(f"  {len(mesh_resources)} mesh resources")
    print(f"  {len(texture_resources)} texture resources")
    print()

    # Find the PRIMARY/DAY/NONE state resources (default state)
    target_arrangement = MapArrangementState.PRIMARY
    target_time = MapTime.DAY
    target_weather = MapWeather.NONE

    # Find matching mesh resource
    mesh_resource = None
    for r in mesh_resources:
        if (r.arrangement == target_arrangement and
            r.time == target_time and
            r.weather == target_weather):
            mesh_resource = r
            break

    if mesh_resource is None:
        # Fall back to first mesh resource
        mesh_resource = mesh_resources[0] if mesh_resources else None

    # Find matching texture resource
    texture_resource = None
    for r in texture_resources:
        if (r.arrangement == target_arrangement and
            r.time == target_time and
            r.weather == target_weather):
            texture_resource = r
            break

    if texture_resource is None:
        # Fall back to first texture resource
        texture_resource = texture_resources[0] if texture_resources else None

    if not mesh_resource or not texture_resource:
        print("Error: Could not find mesh and texture resources", file=sys.stderr)
        sys.exit(1)

    print(f"Export target: {args.output}")
    print()

    # Phase 2: Texture & Palette Export
    print("=== TEXTURE EXPORT ===")
    print()

    # Parse palettes from mesh resource
    palettes, has_palettes = parse_palettes(mesh_resource.resource_data)
    if not has_palettes:
        print("Warning: No palettes found in mesh resource")
        palettes = []

    # Parse animation frames
    animation_frames = parse_palette_animation_frames(mesh_resource.resource_data)

    # Export textures and palettes
    export_textures(
        texture_resource.resource_data,
        palettes,
        animation_frames,
        args.output,
        verbose=args.verbose,
    )

    # Phase 3: Mesh Parsing
    print()
    print("=== MESH PARSING ===")
    print()

    polygons = parse_mesh(mesh_resource.resource_data)
    counts = get_polygon_counts(polygons)

    if args.verbose:
        print("Polygon counts:")
        print(f"  Textured triangles: {counts['textured_triangles']}")
        print(f"  Textured quads: {counts['textured_quads']}")
        print(f"  Untextured triangles: {counts['untextured_triangles']}")
        print(f"  Untextured quads: {counts['untextured_quads']}")
        print(f"  Total: {counts['total']}")

    print(f"Parsed {counts['total']} polygons")

    # Parse terrain first — mesh/geometry export needs size_z for the
    # parser-time Z-flip (ADR-0052). PSX uses 28 position-units per tile.
    terrain = parse_terrain(mesh_resource.resource_data)
    size_z_psx_units = (terrain.size_z if terrain else 0) * 28

    # Phase 4: Geometry Export
    print()
    print("=== GEOMETRY EXPORT ===")
    print()

    export_geometry(polygons, args.output, size_z_psx_units, verbose=args.verbose)

    # Phase 5: Terrain Export
    print()
    print("=== TERRAIN EXPORT ===")
    print()

    if terrain:
        if args.verbose:
            print(f"Terrain dimensions: {terrain.size_x}x{terrain.size_z}")
            print(f"  Level 0 tiles: {sum(len(row) for row in terrain.level_0_tiles)}")
            print(f"  Level 1 tiles: {sum(len(row) for row in terrain.level_1_tiles)}")

        export_terrain(terrain, args.output, verbose=args.verbose)
    else:
        print("No terrain data found")

    # Phase 5b: System-B mesh animation (moving geometry). Absent on most maps.
    mesh_anim_set = parse_mesh_animation_set(mesh_resource.resource_data)
    mesh_animation_manifest = None
    if mesh_anim_set is not None:
        print()
        print("=== MESH ANIMATION EXPORT (System B) ===")
        print()
        animated_meshes = parse_animated_meshes(mesh_resource.resource_data)
        export_mesh_animation(mesh_anim_set, animated_meshes, args.output, verbose=args.verbose)
        export_animated_mesh_geometry(animated_meshes, args.output, size_z_psx_units, verbose=args.verbose)
        mesh_animation_manifest = build_mesh_animation_manifest(mesh_anim_set, animated_meshes)
        print(f"Exported {mesh_animation_manifest['active_set_count']} active sets, "
              f"{mesh_animation_manifest['animated_mesh_count']} animated meshes")

    # Phase 6: Manifest Export
    print()
    print("=== MANIFEST EXPORT ===")
    print()

    lighting = parse_lighting(mesh_resource.resource_data)
    uv_animations, palette_animations = parse_texture_animations(mesh_resource.resource_data)
    texture_animation_slots = parse_texture_animation_slots(mesh_resource.resource_data)

    if args.verbose:
        if lighting:
            print(f"Lighting: ambient=({lighting.ambient_r},{lighting.ambient_g},{lighting.ambient_b})")
            print(f"  Directional lights: {len(lighting.directional_lights)}")
        print(f"UV animations: {len(uv_animations)}")
        print(f"Palette animations: {len(palette_animations)}")

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
        output_dir=args.output,
        verbose=args.verbose,
        texture_animation_slots=texture_animation_slots,
        mesh_animation_manifest=mesh_animation_manifest,
    )

    print()
    print("Export complete!")


if __name__ == "__main__":
    main()
