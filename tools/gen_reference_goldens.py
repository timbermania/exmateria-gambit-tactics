"""Generate the Phase-0 reference-scene parser goldens (issue #137, ADR-0057).

These goldens are the *anti-regression oracle* for the PSX->Godot spatial-
transform consolidation (epic #136). They snapshot, per reference scene, the
four parser-side layers that a shifted coordinate or flipped facing would
perturb:

  - entd        - ENTD spawn tiles + raw facings (Placement + Orientation)
  - terrain     - level_0 height/impassable grids + a content hash (Placement)
  - mesh_bounds - the map mesh AABB + vertex count (Placement)
  - camera      - the {19} Camera opcode operands, byte-exact (Orientation, and
                  the cinematic-camera Placement) - only for scenes that carry a
                  committed event-script chunk
  - cull        - the visible-angles table digest (Render input; #135 oracle) -
                  captured for the strong-cull scene

Phase 0 *locks current behavior*: it introduces no new transform and takes no
position on whether any value is "right". It records exactly what the current
tree produces so a later Placement/Orientation/Render refactor fails loudly.
See ADR-0057 and CONTEXT.md -> "Spatial convention (Placement / Orientation /
Render)".

The roster (each scene earns its place by exercising a distinct failure mode):

  chapel        scn 1  MAP062  - breadth/regression anchor. ORIENTATION-BLIND:
                                  its active ENTD slots only carry raw facings
                                  {0,3}, so it is a *regression* guard, NEVER a
                                  facing-calibration reference (ADR-0057).
  orbonne       scn 4  MAP056  - raw facings {0,2} -> world EAST/WEST (the
                                  enemies-West / knights-East pair; the 0<->2
                                  swap category error, ADR-0052 dec. 10).
  academy       scn 8  MAP024  - raw facings {0,1,2,3}: the ONLY roster scene
                                  that exercises facing 1 and 3, the values the
                                  0<->2 swap leaves untouched.
  frog          scn 269 MAP026 - a 4x18 map (the most non-symmetric parsed map):
                                  a depth-flip off-by-one cannot hide behind
                                  size_x == size_z symmetry here.
  monastery     scn 232 MAP057 - ~95% of polygons carry visible-angles cull
                                  bits: the oracle a cull-table remap (#135) is
                                  later checked against, under a camera orbit.

Regenerate (writes the committed goldens):
    uv run python tools/gen_reference_goldens.py

Verify committed goldens match the current assets (CI / pre-flight):
    uv run python tools/gen_reference_goldens.py --check

Both require the locally-generated, ROM-derived map assets
(assets/maps/MAP*/{terrain,geometry_linked}.json, gitignored). When they are
absent the corresponding layer is recorded as null and the test skips, exactly
like tools/test_parse_placement.py.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import _repo_paths as rp

# --- roster -----------------------------------------------------------------
# (role, scenario_id). Ordered chapel-first so the regression anchor leads.
ROSTER: list[tuple[str, int]] = [
    ("chapel", 1),
    ("orbonne", 4),
    ("academy", 8),
    ("frog", 269),
    ("monastery", 232),
]

# The strong-cull scene whose visible-angles table we digest for #135.
CULL_ROLE = "monastery"

# ENTD slot sentinel for "empty" - mirrors ScenarioPlayerScene.ENTD_EMPTY_UID.
ENTD_EMPTY_UID = 0xFF

GOLDEN_DIR = Path(__file__).resolve().parent / "goldens" / "reference_scenes"


def _scenarios() -> dict:
    p = rp.almanac_dir("encounters/scenarios.json")   # ADR-0251 dec. 2
    return json.loads(p.read_text())["scenarios"]


def _entd_records() -> dict:
    p = rp.assets_dir("scenarios/entd.json")
    return json.loads(p.read_text())["records"]


def _canonical_hash(obj) -> str:
    blob = json.dumps(obj, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(blob).hexdigest()


def _entd_layer(entd_idx: int, records: dict) -> dict:
    """Active-unit spawns, filtered exactly as the runtime spawns them
    (unit_id != 0xFF). facing_raw is the byte the runtime seeds spawn facing
    from; facing/facing_name are the parser's decoded labels (kept so a swap
    of either surface fails). This is a Placement (tile) + Orientation (facing)
    snapshot - no transform is applied here beyond what the parser committed."""
    rec = records.get(str(entd_idx))
    if rec is None:
        return {"entd_idx": entd_idx, "units": [], "facings_present": []}
    units = []
    facings = set()
    for i, s in enumerate(rec["slots"]):
        if int(s.get("unit_id", ENTD_EMPTY_UID)) == ENTD_EMPTY_UID:
            continue
        facing_raw = int(s.get("facing_raw", 0))
        # The runtime seeds spawn facing from the raw flags3 byte via
        # PsxNum.warp_facing_to_12bit(facing_raw) = (facing_raw & 3) << 10, so
        # the 2-bit `& 3` is the Orientation the game actually consumes; the
        # upper bits (0x80 = upper_level) ride along in facing_raw.
        spawn_facing = facing_raw & 0x3
        units.append({
            "slot": i,
            "sprite_set": int(s.get("sprite_set", 0)),
            "unit_id": int(s.get("unit_id", ENTD_EMPTY_UID)),
            "x": int(s.get("x", 0)),
            "y": int(s.get("y", 0)),
            "facing_raw": facing_raw,
            "spawn_facing": spawn_facing,
            "facing": int(s.get("facing", 0)),
            "facing_name": s.get("facing_name", ""),
            "team_color": int(s.get("team_color", 0)),
            "upper_level": bool(s.get("upper_level", False)),
        })
        facings.add(spawn_facing)
    return {
        "entd_idx": entd_idx,
        "units": units,
        "facings_present": sorted(facings),
    }


def _terrain_layer(map_name: str):
    """level_0 height + impassable grids and a content hash. The per-tile grids
    are what a depth-flip off-by-one (row shift) perturbs on a non-symmetric
    map. Returns None when the (gitignored) map asset is absent."""
    p = rp.assets_dir("maps/%s/terrain.json" % map_name)
    if not p.exists():
        return None
    terrain = json.loads(p.read_text())["terrain"]
    size_x = int(terrain["size_x"])
    size_z = int(terrain["size_z"])
    level0 = terrain["level_0"]
    heights = [[int(t["height"]) for t in row] for row in level0]
    impassable = [[bool(t.get("impassable", False)) for t in row] for row in level0]
    return {
        "size_x": size_x,
        "size_z": size_z,
        "height_grid": heights,
        "impassable_grid": impassable,
        "sha256": _canonical_hash(terrain),
    }


def _mesh_bounds_layer(map_name: str):
    """AABB (min/max) over every mesh vertex Position + the vertex count. A
    Placement transform error (Y-negate, depth-mirror) moves the bounds.
    Positions are rounded to 4 decimals so the snapshot is float-stable.
    Returns None when the (gitignored) map asset is absent."""
    p = rp.assets_dir("maps/%s/geometry_linked.json" % map_name)
    if not p.exists():
        return None
    geom = json.loads(p.read_text())
    lo = [float("inf")] * 3
    hi = [float("-inf")] * 3
    n = 0
    for mesh in geom.get("Meshes", {}).values():
        for v in mesh.get("Vertices", []):
            pos = v["Position"]
            for k in range(3):
                c = float(pos[k])
                lo[k] = min(lo[k], c)
                hi[k] = max(hi[k], c)
            n += 1
    if n == 0:
        return {"vertex_count": 0, "min": None, "max": None}
    return {
        "vertex_count": n,
        "min": [round(c, 4) for c in lo],
        "max": [round(c, 4) for c in hi],
    }


# Camera-angle sweep sampled for the cull-orbit oracle: 16 angles at 0x100
# steps across the PSX 0..0xFFF yaw wheel (0x000=N, 0x400=E, 0x800=S, 0xC00=W),
# so the four cardinals AND the inter-cardinal buckets are all hit.
_ORBIT_ANGLES = [a for a in range(0, 0x1000, 0x100)]


def _polygon_culled(vis: int, angle: int) -> bool:
    """Byte-for-byte transcription of fft_polygon_is_culled() in
    assets/shaders/fft_visible_angles.gdshaderinc (mode 2, angle-aware). Python
    arithmetic shift on the masked (non-negative) `vis` and on `(angle-1)`
    matches GLSL's here. Kept in lockstep with the shaderinc - if that Render
    formula changes, re-record and the orbit golden moves with it (which is the
    whole point for #135)."""
    vis &= 0x3FFC
    if vis == 0:
        return False
    angle &= 0xFFF
    shift1 = ((angle - 1) >> 9) & 7
    shift2 = (angle >> 10) & 3
    if ((angle + 0x200) & 0x3FF) != 0:
        shift2 = 4
    cull1 = (vis >> shift1) & 4
    cull2 = (vis >> shift2) & 0x400
    return cull1 != 0 or cull2 != 0


def _cull_layer(map_name: str):
    """visible-angles table digest + the camera-orbit cull oracle.

    Static digest: total polygons, how many carry a cull bit (mask 0x3FFC per
    fft_visible_angles.gdshaderinc), and a hash of the full bit sequence - a
    parser-side cull-table *remap* (#135 permutes bits 2-13) moves the hash.

    Orbit oracle: for each sampled camera yaw, how many polygons the Render cull
    discards, plus a hash of the full per-polygon decision vector. This is the
    per-bucket before/after oracle the #135 azimuth-negation remap is checked
    against under a camera orbit. Phase 0 locks CURRENT (possibly-wrong)
    behavior; #135 re-records after deriving the remap headful.

    Returns None when the (gitignored) map asset is absent."""
    p = rp.assets_dir("maps/%s/geometry_linked.json" % map_name)
    if not p.exists():
        return None
    geom = json.loads(p.read_text())
    bits: list[int] = []
    for mesh in geom.get("Meshes", {}).values():
        for prim in mesh.get("Primitives", []):
            for b in (prim.get("VisibleAngles") or []):
                bits.append(int(b))
    culled = sum(1 for b in bits if (b & 0x3FFC) != 0)
    orbit = []
    for angle in _ORBIT_ANGLES:
        decisions = [1 if _polygon_culled(b, angle) else 0 for b in bits]
        orbit.append({
            "angle": angle,
            "culled": sum(decisions),
            "decision_sha256": _canonical_hash(decisions),
        })
    return {
        "polygon_count": len(bits),
        "culled_polygon_count": culled,
        "bits_sha256": _canonical_hash(bits),
        "orbit": orbit,
    }


def _camera_layer(scenario_id: int):
    """The {19} Camera opcode operands, byte-exact (the `raw` hex per opcode).
    Locks the cinematic camera's Placement (X/Z/Y) + Orientation (Angle / Map
    Rotation / Camera Rotation) operands. Only the committed legacy chunk is
    read (assets/scenarios/chunks/ is gitignored), so this is populated for the
    cinematic reference (scenario 1) and null for the battles. Returns None
    when no committed chunk is found."""
    candidates = [
        rp.assets_dir("scenarios/scenario_%d_chunk.json" % scenario_id),
        rp.assets_dir("scenarios/scenario_%04d_setup_chunk.json" % scenario_id),
    ]
    chunk_path = next((c for c in candidates if c.exists()), None)
    if chunk_path is None:
        return None
    chunk = json.loads(chunk_path.read_text())
    raws = [i["raw"] for i in chunk.get("instructions", []) if int(i["opcode"]) == 0x19]
    return {
        "source": chunk_path.name,
        "opcode_0x19_count": len(raws),
        "opcode_0x19_raw": raws,
    }


def build_snapshot(role: str, scenario_id: int,
                   scenarios: dict, records: dict) -> dict:
    sc = scenarios[str(scenario_id)]
    map_id = int(sc["map_id"])
    map_name = "MAP%03d" % map_id
    entd_idx = int(sc["entd_idx"])
    snap = {
        "role": role,
        "scenario_id": scenario_id,
        "scenario_name": sc.get("scenario_name", ""),
        "map_id": map_id,
        "map": map_name,
        "entd": _entd_layer(entd_idx, records),
        "terrain": _terrain_layer(map_name),
        "mesh_bounds": _mesh_bounds_layer(map_name),
        "camera": _camera_layer(scenario_id),
    }
    if role == CULL_ROLE:
        snap["cull"] = _cull_layer(map_name)
    return snap


def golden_path(role: str, scenario_id: int) -> Path:
    return GOLDEN_DIR / ("%s_scn%04d.golden.json" % (role, scenario_id))


def dumps(snap: dict) -> str:
    return json.dumps(snap, indent=2, sort_keys=True) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true",
                    help="verify committed goldens match current assets; "
                         "exit non-zero on drift (does not write)")
    args = ap.parse_args()

    scenarios = _scenarios()
    records = _entd_records()
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)

    drift = []
    for role, sid in ROSTER:
        snap = build_snapshot(role, sid, scenarios, records)
        path = golden_path(role, sid)
        text = dumps(snap)
        if args.check:
            if not path.exists():
                drift.append("%s: golden missing (%s)" % (role, path.name))
            elif path.read_text() != text:
                drift.append("%s: golden drifted from current assets (%s)"
                             % (role, path.name))
        else:
            path.write_text(text)
            print("wrote %s" % path.relative_to(rp.godot_root()))

    if args.check:
        if drift:
            print("REFERENCE-SCENE GOLDEN DRIFT:", file=sys.stderr)
            for d in drift:
                print("  - " + d, file=sys.stderr)
            print("\nRegenerate: uv run python tools/gen_reference_goldens.py",
                  file=sys.stderr)
            return 1
        print("reference-scene goldens OK (%d scenes)" % len(ROSTER))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
