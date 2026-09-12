"""System-B mesh-animation exporter (moving map geometry).

Serialises a parsed :class:`MeshAnimationSet` to ``mesh_animation.json`` and the
animated-mesh geometry chunks to ``anim_meshes/anim_mesh_<n>.json`` (reusing the
primary-mesh geometry JSON path so coordinates + ADR-0052 Z-flip line up).

Index-stable, mirroring System A's all-slot ``texture_animations`` table: all
128 keyframes and all 64 instruction sets are emitted so a runtime can address
them by the ``(meshType-1) + playingState*8`` formula. Active sets and sets
targeting a missing mesh are flagged for convenience. Tween/timing data is
emitted raw — interpolation is the runtime's job (#130 decision).
"""

import json
from pathlib import Path
from typing import Dict, List

from ..models.mesh_animation import (
    MeshAnimationSet,
    MeshAnimationTweenType,
)
from ..models.polygon import Polygon, PolygonType
from .geometry import _export_geometry_json

_TWEEN_NAMES = {t.value: t.name for t in MeshAnimationTweenType}


def anim_mesh_rel_path(n: int) -> str:
    """Output-relative path for animated mesh ``n``'s geometry JSON.

    Single source of truth for the anim-mesh filename scheme — the exporter,
    the manifest block, and the geometry writer all derive paths from here.
    """
    return f"anim_meshes/anim_mesh_{n}.json"


def build_mesh_animation_manifest(
    mesh_anim_set: MeshAnimationSet,
    animated_meshes: Dict[int, Dict[PolygonType, List[Polygon]]],
) -> dict:
    """Build the small ``animations.mesh_animation`` manifest block.

    A convenience pointer to mesh_animation.json + the per-mesh geometry files
    (the real data lives in those files). Shared by parse_map.py and the
    standalone ``python -m fft_exporter`` entrypoint so they never drift.
    """
    present = sorted(animated_meshes.keys())
    return {
        "file": "mesh_animation.json",
        "active_set_count": len(mesh_anim_set.active_set_indices()),
        "animated_mesh_count": len(present),
        "animated_mesh_files": [anim_mesh_rel_path(n) for n in present],
    }


def _tween_name(v: int) -> str:
    return _TWEEN_NAMES.get(v, f"Unknown({v})")


def _hx(values: List[int]) -> str:
    return " ".join(f"{x:02x}" for x in values)


def _keyframe_to_dict(index: int, kf) -> dict:
    return {
        "index": index,
        "is_empty": kf.is_empty,
        "rotation": [round(v, 4) for v in kf.rotation],
        "position": list(kf.position),
        "scale": [round(v, 4) for v in kf.scale],
        "rot_start_pct": [round(v, 4) for v in kf.rot_start_pct],
        "pos_start_pct": [round(v, 4) for v in kf.pos_start_pct],
        "scale_start_pct": [round(v, 4) for v in kf.scale_start_pct],
        "rot_end_pct": [round(v, 4) for v in kf.rot_end_pct],
        "pos_end_pct": [round(v, 4) for v in kf.pos_end_pct],
        "scale_end_pct": [round(v, 4) for v in kf.scale_end_pct],
        "rot_tween": [_tween_name(v) for v in kf.rot_tween],
        "pos_tween": [_tween_name(v) for v in kf.pos_tween],
        "scale_tween": [_tween_name(v) for v in kf.scale_tween],
        "raw_props": kf.props,
    }


def _instruction_to_dict(ins) -> dict:
    return {
        "frame_state_id": ins.frame_state_id,
        "next_frame_id": ins.next_frame_id,
        "duration": ins.duration,
        "duration_seconds": round(ins.duration / 60, 4),
    }


def export_mesh_animation(
    mesh_anim_set: MeshAnimationSet,
    animated_meshes: Dict[int, Dict[PolygonType, List[Polygon]]],
    output_dir: Path,
    verbose: bool = False,
) -> None:
    """Write ``mesh_animation.json`` for one map's `0x8C` chunk.

    Args:
        mesh_anim_set: Parsed mesh-animation set (all 128 keyframes / 64 sets).
        animated_meshes: Parsed animated-mesh geometry (keyed by 1-based mesh
            number); used to flag instruction sets that target a missing mesh.
        output_dir: Map output directory.
        verbose: Enable verbose output.
    """
    present_meshes = sorted(animated_meshes.keys())
    present = set(present_meshes)

    keyframes = [
        _keyframe_to_dict(i, kf) for i, kf in enumerate(mesh_anim_set.keyframes)
    ]

    instruction_sets = []
    for idx, iset in enumerate(mesh_anim_set.instruction_sets):
        # index = (meshType-1) + playingState*8
        mesh_type = (idx % 8) + 1
        playing_state = idx // 8
        prop = mesh_anim_set.properties[idx]
        active = iset.is_active
        instruction_sets.append({
            "index": idx,
            "playing_state": playing_state,
            "mesh_type": mesh_type,
            "active": active,
            "target_missing": active and mesh_type not in present,
            "linked_parent": prop.linked_parent,
            "instructions": [_instruction_to_dict(ins) for ins in iset.instructions],
        })

    mesh_properties = [
        {
            "index": i,
            "linked_parent": p.linked_parent,
            "unk1": p.unk1, "unk2": p.unk2, "unk3": p.unk3,
        }
        for i, p in enumerate(mesh_anim_set.properties)
    ]

    # banks view: active set indices grouped by playing-state (0..7)
    banks: Dict[str, List[int]] = {}
    for idx in mesh_anim_set.active_set_indices():
        banks.setdefault(str(idx // 8), []).append(idx)

    data = {
        "headers": {
            "keyframes": _hx(mesh_anim_set.keyframes_header),
            "instruction_sets": _hx(mesh_anim_set.instruction_sets_header),
            "properties": _hx(mesh_anim_set.properties_header),
            "trailing": _hx(mesh_anim_set.trailing),
        },
        "animated_meshes": {
            "count": len(present_meshes),
            "present": present_meshes,
            "files": [anim_mesh_rel_path(n) for n in present_meshes],
        },
        "banks": banks,
        "keyframes": keyframes,
        "instruction_sets": instruction_sets,
        "mesh_properties": mesh_properties,
    }

    output_path = output_dir / "mesh_animation.json"
    with open(output_path, "w") as f:
        json.dump(data, f, indent=2)

    if verbose:
        print(f"  Wrote: mesh_animation.json "
              f"({len(mesh_anim_set.active_set_indices())} active sets, "
              f"{len(present_meshes)} animated meshes)")


def export_animated_mesh_geometry(
    animated_meshes: Dict[int, Dict[PolygonType, List[Polygon]]],
    output_dir: Path,
    size_z_psx_units: int,
    verbose: bool = False,
) -> None:
    """Write ``anim_meshes/anim_mesh_<n>.json`` for each animated mesh.

    Reuses the primary-mesh geometry JSON path so coordinates, the ADR-0052
    Z-flip, and centroid handling match the static map exactly.
    """
    if not animated_meshes:
        return
    (output_dir / "anim_meshes").mkdir(parents=True, exist_ok=True)
    for n in sorted(animated_meshes.keys()):
        rel = anim_mesh_rel_path(n)
        _export_geometry_json(animated_meshes[n], output_dir / rel, size_z_psx_units, verbose)
        if verbose:
            print(f"  Wrote: {rel}")
