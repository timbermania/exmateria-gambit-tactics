"""System-B mesh-animation parser (moving map geometry).

Decodes the `0x8C` mesh-animation chunk (keyframes + instruction-set state
machine + mesh properties) and the `0x90`-`0xAC` animated-mesh geometry chunks
from a map's mesh-resource data.

The decode math here is ported verbatim from the validated read-only decoder
`research/working_documents/map_animation/decode_mesh_animation.py`, which was
checked byte-exact against ROM on MAP036/002/047/064. Format authority:
GaneshaDx `ResourceContent/MeshResourceData.cs` and
`ContentDataTypes/MeshAnimations/*`.

The 14620-byte `0x8C` chunk:
      8B  keyframes header            (literal 01 00 00 00 80 00 00 00)
  10240   128 x 80B keyframes
      8B  instruction-sets header     (literal 02 00 00 00 10 00 40 00)
   4096   64 x 64B instruction sets   (each = 16 x 4B instructions)
      8B  mesh-properties header      (literal 03 00 00 00 40 00 00 00)
    256   64 x 4B mesh properties     (LinkedParentMesh + 3 unknown)
      4B  trailing (zero)
"""

import struct
import sys
from typing import Dict, List, Optional

from ..models.mesh_animation import (
    AnimatedMeshInstruction,
    AnimatedMeshInstructionSet,
    AnimatedMeshProperties,
    MeshAnimationKeyframe,
    MeshAnimationSet,
)
from ..models.polygon import MeshType, Polygon, PolygonType
from .mesh import parse_mesh

# Header pointer offsets (bytes into the mesh resource)
ANIM_INSTR_POINTER = 0x8C                                  # 0x8C mesh-animation chunk
ANIMATED_MESH_POINTERS = [0x90 + i * 4 for i in range(8)]  # 0x90..0xAC, mesh 1..8

CHUNK_SIZE = 14620
KEYFRAME_BYTES = 80
INSTR_SET_BYTES = 64
N_KEYFRAMES = 128
N_INSTR_SETS = 64
N_PROPERTIES = 64


def _i16(b: bytes, off: int) -> int:
    return struct.unpack_from("<h", b, off)[0]


def _u32(b: bytes, off: int) -> int:
    return struct.unpack_from("<I", b, off)[0] if off + 4 <= len(b) else 0


def decode_keyframe(raw: bytes) -> MeshAnimationKeyframe:
    """Decode one 80-byte keyframe into a :class:`MeshAnimationKeyframe`.

    ``raw`` -> 40 signed int16 "properties". Rotation/scale percents are
    int16 fixed-point /4096; rotation degrees are /4096*360 with X/Y negated;
    position is raw units with Y negated.
    """
    p = [_i16(raw, i * 2) for i in range(40)]
    return MeshAnimationKeyframe(
        props=p,
        rotation=(-p[0] / 4096 * 360, -p[1] / 4096 * 360, p[2] / 4096 * 360),
        position=(p[4], -p[5], p[6]),
        scale=(p[8] / 4096, p[9] / 4096, p[10] / 4096),
        rot_start_pct=(p[12] / 4096 * 100, p[13] / 4096 * 100, p[14] / 4096 * 100),
        pos_start_pct=(p[15] / 4096 * 100, p[16] / 4096 * 100, p[17] / 4096 * 100),
        scale_start_pct=(p[18] / 4096 * 100, p[19] / 4096 * 100, p[20] / 4096 * 100),
        rot_end_pct=(p[21] / 4096 * 100, p[22] / 4096 * 100, p[23] / 4096 * 100),
        pos_end_pct=(p[24] / 4096 * 100, p[25] / 4096 * 100, p[26] / 4096 * 100),
        scale_end_pct=(p[27] / 4096 * 100, p[28] / 4096 * 100, p[29] / 4096 * 100),
        rot_tween=(p[30], p[31], p[32]),
        pos_tween=(p[33], p[34], p[35]),
        scale_tween=(p[36], p[37], p[38]),
    )


def decode_instr_set(raw: bytes) -> AnimatedMeshInstructionSet:
    """Decode one 64-byte instruction set into 16 instructions."""
    instructions = []
    for i in range(16):
        off = i * 4
        instructions.append(AnimatedMeshInstruction(
            frame_state_id=raw[off],
            next_frame_id=raw[off + 1],
            duration=_i16(raw, off + 2),
        ))
    return AnimatedMeshInstructionSet(instructions=instructions)


def parse_mesh_animation_set(data: bytes) -> Optional[MeshAnimationSet]:
    """Parse the `0x8C` mesh-animation chunk.

    Returns ``None`` when the chunk is absent (null pointer) or truncated
    (fewer than 14620 bytes remain) — never raises on a normal map.
    """
    base = _u32(data, ANIM_INSTR_POINTER)
    if base == 0:
        return None
    if base + CHUNK_SIZE > len(data):
        # Non-null pointer but the chunk runs past the resource end. Per the
        # parser contract we return None rather than decode a partial chunk,
        # but warn so a corrupt/repacked extract isn't silently dropped.
        print(f"WARNING: 0x8C mesh-animation chunk truncated "
              f"(need {CHUNK_SIZE} bytes at 0x{base:x}, have {len(data) - base})",
              file=sys.stderr)
        return None

    pos = base
    kf_header = list(data[pos:pos + 8]); pos += 8
    keyframes = []
    for _ in range(N_KEYFRAMES):
        keyframes.append(decode_keyframe(data[pos:pos + KEYFRAME_BYTES]))
        pos += KEYFRAME_BYTES

    is_header = list(data[pos:pos + 8]); pos += 8
    instr_sets = []
    for _ in range(N_INSTR_SETS):
        instr_sets.append(decode_instr_set(data[pos:pos + INSTR_SET_BYTES]))
        pos += INSTR_SET_BYTES

    prop_header = list(data[pos:pos + 8]); pos += 8
    properties = []
    for _ in range(N_PROPERTIES):
        properties.append(AnimatedMeshProperties(
            linked_parent=data[pos],
            unk1=data[pos + 1], unk2=data[pos + 2], unk3=data[pos + 3],
        ))
        pos += 4

    trailing = list(data[pos:pos + 4])

    return MeshAnimationSet(
        keyframes_header=kf_header,
        instruction_sets_header=is_header,
        properties_header=prop_header,
        keyframes=keyframes,
        instruction_sets=instr_sets,
        properties=properties,
        trailing=trailing,
    )


def parse_animated_meshes(
    data: bytes,
) -> Dict[int, Dict[PolygonType, List[Polygon]]]:
    """Parse the `0x90`-`0xAC` animated-mesh geometry chunks.

    For each non-null pointer, parse the mesh exactly like the primary mesh
    (reusing :func:`parse_mesh` with the matching ``ANIMATED_MESH_n`` type, so
    it reads the correct 0x90+ pointer). Returns a dict keyed by 1-based mesh
    number; empty dict when no animated meshes are present.
    """
    result: Dict[int, Dict[PolygonType, List[Polygon]]] = {}
    for n in range(1, 9):
        off = ANIMATED_MESH_POINTERS[n - 1]
        if off + 4 > len(data) or _u32(data, off) == 0:
            continue
        mesh_type = MeshType(MeshType.ANIMATED_MESH_1.value + (n - 1))
        try:
            result[n] = parse_mesh(data, mesh_type)
        except Exception as e:  # corrupt/edge-case pointer — skip this mesh,
            # don't abort the whole map export (mirrors the reference decoder).
            print(f"WARNING: animated mesh {n} parse failed at 0x{_u32(data, off):x}: {e}",
                  file=sys.stderr)
    return result
