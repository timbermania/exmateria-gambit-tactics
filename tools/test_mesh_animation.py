"""Tests for the System-B mesh-animation parser/exporter (#130).

Asset-free unit tests pin the decode math, the absent/truncated guard, and the
exported JSON shape using synthetic byte fixtures + in-memory models — they run
everywhere, including machines without the gitignored project-assets extract.

Asset-gated integration tests (skipped when the MAP extract is missing) check
real maps against ground truth re-derived from the validated decoder:
  MAP036  cog: 2 animated meshes (34 polys each); bank-1 sets rot ±45° Oscillate
  MAP047  8 animated meshes (2 polys each) + mesh2->mesh1 parent link
  MAP064  inert: 1 active set flagged target_missing, zero animated meshes

Run from tools/:
    uv run python -m unittest test_mesh_animation
"""

from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

from fft_exporter.models.mesh_animation import (
    AnimatedMeshInstruction,
    AnimatedMeshInstructionSet,
    AnimatedMeshProperties,
    MeshAnimationKeyframe,
    MeshAnimationSet,
    MeshAnimationTweenType,
)
from fft_exporter.parsers.mesh_animation import (
    CHUNK_SIZE,
    decode_instr_set,
    decode_keyframe,
    parse_animated_meshes,
    parse_mesh_animation_set,
)
from fft_exporter.exporters.mesh_animation import export_mesh_animation
from fft_exporter.models.polygon import PolygonType

MAP_DIR = Path(__file__).resolve().parents[1].parent / "project-assets" / "fft-extract" / "MAP"


def _pack_props(overrides: dict) -> bytes:
    """Build an 80-byte keyframe: 40 int16, zero except the given indices."""
    p = [0] * 40
    for i, v in overrides.items():
        p[i] = v
    return b"".join(struct.pack("<h", v) for v in p)


# --------------------------------------------------------------------------
# Asset-free decode-math unit tests
# --------------------------------------------------------------------------
class DecodeKeyframeTest(unittest.TestCase):

    def test_rotation_negates_x_y_and_scales_degrees(self) -> None:
        # p0=-512 -> -(-512)/4096*360 = 45.0 ; p1=512 -> -45.0 ; p2=512 -> +45.0
        kf = decode_keyframe(_pack_props({0: -512, 1: 512, 2: 512}))
        self.assertAlmostEqual(kf.rotation[0], 45.0)
        self.assertAlmostEqual(kf.rotation[1], -45.0)
        self.assertAlmostEqual(kf.rotation[2], 45.0)

    def test_position_negates_y_and_is_raw_units(self) -> None:
        kf = decode_keyframe(_pack_props({4: 70, 5: -293, 6: 182}))
        self.assertEqual(kf.position, (70, 293, 182))

    def test_scale_is_fixed_point_over_4096(self) -> None:
        kf = decode_keyframe(_pack_props({8: 4096, 9: 2048, 10: 0}))
        self.assertAlmostEqual(kf.scale[0], 1.0)
        self.assertAlmostEqual(kf.scale[1], 0.5)
        self.assertAlmostEqual(kf.scale[2], 0.0)

    def test_tween_bytes_are_preserved_raw(self) -> None:
        kf = decode_keyframe(_pack_props({30: 10, 31: 6, 32: 5, 33: 18, 36: 9}))
        self.assertEqual(kf.rot_tween, (10, 6, 5))
        self.assertEqual(kf.pos_tween, (18, 0, 0))
        self.assertEqual(kf.scale_tween, (9, 0, 0))

    def test_empty_keyframe_flagged(self) -> None:
        self.assertTrue(decode_keyframe(_pack_props({})).is_empty)
        self.assertFalse(decode_keyframe(_pack_props({0: 1})).is_empty)


class DecodeInstrSetTest(unittest.TestCase):

    def test_instruction_layout(self) -> None:
        raw = bytearray(64)
        # instr[0] = {frame_state_id=3, next_frame_id=1, duration=180}
        raw[0] = 3
        raw[1] = 1
        struct.pack_into("<h", raw, 2, 180)
        iset = decode_instr_set(bytes(raw))
        self.assertEqual(len(iset.instructions), 16)
        self.assertEqual(iset.instructions[0].frame_state_id, 3)
        self.assertEqual(iset.instructions[0].next_frame_id, 1)
        self.assertEqual(iset.instructions[0].duration, 180)
        self.assertTrue(iset.is_active)

    def test_inactive_when_first_frame_state_zero(self) -> None:
        self.assertFalse(decode_instr_set(bytes(64)).is_active)


class TweenEnumTest(unittest.TestCase):

    def test_known_values(self) -> None:
        self.assertEqual(MeshAnimationTweenType(10), MeshAnimationTweenType.Oscillate)
        self.assertEqual(MeshAnimationTweenType(5), MeshAnimationTweenType.TweenTo)
        self.assertEqual(MeshAnimationTweenType(18), MeshAnimationTweenType.OscillateOffset)


# --------------------------------------------------------------------------
# Asset-free parser-guard tests (synthetic full chunk)
# --------------------------------------------------------------------------
def _synthetic_resource(chunk_offset: int, chunk: bytes) -> bytes:
    """Build a minimal mesh-resource: header with 0x8C pointer + chunk."""
    size = max(chunk_offset + len(chunk), 0xB4)
    data = bytearray(size)
    struct.pack_into("<I", data, 0x8C, chunk_offset)
    data[chunk_offset:chunk_offset + len(chunk)] = chunk
    return bytes(data)


def _make_chunk(kf0_overrides: dict, set0_first: tuple) -> bytes:
    """Build a full 14620-byte chunk with one crafted keyframe + instruction."""
    buf = bytearray(CHUNK_SIZE)
    pos = 0
    buf[pos:pos + 8] = bytes([1, 0, 0, 0, 0x80, 0, 0, 0]); pos += 8
    # keyframe 0
    buf[pos:pos + 80] = _pack_props(kf0_overrides)
    pos += 80 * 128
    buf[pos:pos + 8] = bytes([2, 0, 0, 0, 0x10, 0, 0x40, 0]); pos += 8
    # instruction set 0, instruction 0
    fsid, nfid, dur = set0_first
    buf[pos] = fsid
    buf[pos + 1] = nfid
    struct.pack_into("<h", buf, pos + 2, dur)
    pos += 64 * 64
    buf[pos:pos + 8] = bytes([3, 0, 0, 0, 0x40, 0, 0, 0]); pos += 8
    pos += 4 * 64
    # trailing 4 bytes already zero
    return bytes(buf)


class ParserGuardTest(unittest.TestCase):

    def test_absent_chunk_returns_none(self) -> None:
        data = bytearray(0x200)  # 0x8C pointer left at 0
        self.assertIsNone(parse_mesh_animation_set(bytes(data)))

    def test_truncated_chunk_returns_none(self) -> None:
        # pointer present but fewer than CHUNK_SIZE bytes remain -> None (with a
        # stderr warning, which we suppress here to keep test output clean)
        import contextlib
        import io
        data = _synthetic_resource(0x100, bytes(CHUNK_SIZE // 2))
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertIsNone(parse_mesh_animation_set(data))

    def test_full_chunk_decodes(self) -> None:
        chunk = _make_chunk({0: -512}, (1, 2, 60))
        data = _synthetic_resource(0x100, chunk)
        mset = parse_mesh_animation_set(data)
        self.assertIsNotNone(mset)
        self.assertEqual(len(mset.keyframes), 128)
        self.assertEqual(len(mset.instruction_sets), 64)
        self.assertEqual(len(mset.properties), 64)
        self.assertAlmostEqual(mset.keyframes[0].rotation[0], 45.0)
        self.assertEqual(mset.instruction_sets[0].instructions[0].frame_state_id, 1)
        self.assertEqual(mset.active_set_indices(), [0])
        self.assertEqual(mset.keyframes_header, [1, 0, 0, 0, 0x80, 0, 0, 0])

    def test_no_animated_meshes_when_pointers_null(self) -> None:
        data = _synthetic_resource(0x100, _make_chunk({}, (0, 0, 0)))
        self.assertEqual(parse_animated_meshes(data), {})


# --------------------------------------------------------------------------
# Asset-free exporter JSON-shape test (in-memory model)
# --------------------------------------------------------------------------
class ExporterShapeTest(unittest.TestCase):

    def _build_set(self) -> MeshAnimationSet:
        keyframes = [MeshAnimationKeyframe(props=[0] * 40) for _ in range(128)]
        keyframes[2] = MeshAnimationKeyframe(
            props=[1] + [0] * 39, rotation=(-45.0, 0.0, 0.0),
            rot_tween=(10, 6, 6),
        )
        sets = [AnimatedMeshInstructionSet(
            instructions=[AnimatedMeshInstruction() for _ in range(16)]
        ) for _ in range(64)]
        # set index 8 = playing-state 1, mesh_type 1, active, targets missing mesh
        sets[8].instructions[0] = AnimatedMeshInstruction(frame_state_id=3, next_frame_id=1, duration=180)
        props = [AnimatedMeshProperties() for _ in range(64)]
        return MeshAnimationSet(
            keyframes_header=[1, 0, 0, 0, 0x80, 0, 0, 0],
            instruction_sets_header=[2, 0, 0, 0, 0x10, 0, 0x40, 0],
            properties_header=[3, 0, 0, 0, 0x40, 0, 0, 0],
            keyframes=keyframes, instruction_sets=sets, properties=props,
            trailing=[0, 0, 0, 0],
        )

    def test_exported_json_shape(self) -> None:
        mset = self._build_set()
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            export_mesh_animation(mset, {}, out)  # no animated-mesh geometry
            data = json.loads((out / "mesh_animation.json").read_text())

        self.assertEqual(len(data["keyframes"]), 128)
        self.assertEqual(len(data["instruction_sets"]), 64)
        self.assertEqual(len(data["mesh_properties"]), 64)
        self.assertEqual(data["headers"]["keyframes"], "01 00 00 00 80 00 00 00")

        s8 = data["instruction_sets"][8]
        self.assertEqual(s8["playing_state"], 1)
        self.assertEqual(s8["mesh_type"], 1)
        self.assertTrue(s8["active"])
        self.assertTrue(s8["target_missing"])  # no geometry supplied
        self.assertEqual(s8["instructions"][0]["frame_state_id"], 3)

        self.assertEqual(data["banks"], {"1": [8]})
        self.assertEqual(data["keyframes"][2]["rot_tween"], ["Oscillate", "TweenBy", "TweenBy"])
        self.assertEqual(data["animated_meshes"]["count"], 0)

    def test_target_present_not_flagged_missing(self) -> None:
        mset = self._build_set()
        # supply geometry for mesh 1 -> set[8] (mesh_type 1) no longer missing
        meshes = {1: {pt: [] for pt in PolygonType}}
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            export_mesh_animation(mset, meshes, out)
            data = json.loads((out / "mesh_animation.json").read_text())
        self.assertFalse(data["instruction_sets"][8]["target_missing"])
        self.assertEqual(data["animated_meshes"]["present"], [1])


# --------------------------------------------------------------------------
# Asset-gated integration tests
# --------------------------------------------------------------------------
def _load_primary_resource(map_id: str) -> bytes:
    from fft_exporter.parsers.gns import parse_gns_file, load_resource_files
    gns = MAP_DIR / f"{map_id}.GNS"
    all_res, mesh_res, _tex = parse_gns_file(gns)
    load_resource_files(gns.parent / gns.stem, all_res)
    cands = [r for r in mesh_res
             if r.arrangement.name == "PRIMARY" and r.time.name == "DAY"
             and r.weather.name == "NONE"]
    return (cands or mesh_res[:1])[0].resource_data


def _total(polys) -> int:
    return sum(len(v) for v in polys.values())


@unittest.skipUnless(MAP_DIR.is_dir(), "MAP extract not present")
class MapIntegrationTest(unittest.TestCase):

    def test_map036_cog(self) -> None:
        data = _load_primary_resource("MAP036")
        meshes = parse_animated_meshes(data)
        # Real animated-mesh geometry is 34 polys each (NOT the 512 the buggy
        # decoder reported — it had read the primary mesh twice).
        self.assertEqual(sorted(meshes.keys()), [1, 2])
        self.assertEqual(_total(meshes[1]), 34)
        self.assertEqual(_total(meshes[2]), 34)

        mset = parse_mesh_animation_set(data)
        self.assertEqual(mset.active_set_indices(), [0, 1, 8, 9])
        # bank 1: mesh1 (set 8) rotates -45° Oscillate over 180 ticks; mesh2 +45°
        s8 = mset.instruction_sets[8].instructions[0]
        s9 = mset.instruction_sets[9].instructions[0]
        self.assertEqual(s8.frame_state_id, 3)
        self.assertEqual(s8.duration, 180)
        kf8 = mset.keyframes[s8.frame_state_id - 1]
        kf9 = mset.keyframes[s9.frame_state_id - 1]
        self.assertAlmostEqual(kf8.rotation[0], -45.0)
        self.assertAlmostEqual(kf9.rotation[0], 45.0)
        self.assertEqual(kf8.rot_tween[0], MeshAnimationTweenType.Oscillate.value)

    def test_map047_eight_meshes_with_parent_link(self) -> None:
        data = _load_primary_resource("MAP047")
        meshes = parse_animated_meshes(data)
        self.assertEqual(sorted(meshes.keys()), [1, 2, 3, 4, 5, 6, 7, 8])
        for n in meshes:
            self.assertEqual(_total(meshes[n]), 2)  # 2 textured quads each
        mset = parse_mesh_animation_set(data)
        # set[1] = playing-state 0, mesh_type 2 -> parent mesh 1
        self.assertEqual(mset.properties[1].linked_parent, 1)

    def test_map064_inert_chunk(self) -> None:
        data = _load_primary_resource("MAP064")
        meshes = parse_animated_meshes(data)
        self.assertEqual(meshes, {})  # no animated-mesh geometry
        mset = parse_mesh_animation_set(data)
        self.assertIsNotNone(mset)
        self.assertEqual(mset.active_set_indices(), [8])  # bank 1, mesh_type 1
        # Exporter must flag the target as missing, not error.
        with tempfile.TemporaryDirectory() as td:
            out = Path(td)
            export_mesh_animation(mset, meshes, out)
            jd = json.loads((out / "mesh_animation.json").read_text())
        self.assertTrue(jd["instruction_sets"][8]["target_missing"])
        self.assertEqual(jd["animated_meshes"]["count"], 0)


if __name__ == "__main__":
    unittest.main()
