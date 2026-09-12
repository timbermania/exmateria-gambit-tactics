"""Byte-exact SOUNDCONTAINER writer for E###.BIN (TIER-2, #289).

The inverse of `parse_effect.parse_sound_containers`. Given the base `E###.BIN`
bytes, a parsed (possibly edited) `sound_containers` doc, and the header's
`effect_flags_ptr`, `patch_containers_section` returns a NEW byte buffer in which
the 4 shared, effect-global SoundContainers — 4 bytes each `[mode, id_a, id_b,
id_c]` at `effect_flags_ptr + 8 + ci*4` — are re-serialized from their raw fields.
Every byte outside those 16 is preserved verbatim: a partial patch (mirroring
write_effect_sound).

These containers are what a timeline sound_id resolves THROUGH (container_idx =
sound_id - 2) before reaching a FEDS pair (TIER-3). They live INSIDE the header's
Effect-Flags section (#272); this writer owns ONLY the 16 container bytes at +8 —
the rest of that section (and the FEDS opcode stream) is left untouched, so #272's
own serializer can coexist over the disjoint bytes.

The convenience `index` field the parser adds has no ROM counterpart and is
dropped (only mode/id_a/id_b/id_c are bytes). Offset math (the +8 base, 4-byte
stride, field order) mirrors `parse_effect.parse_sound_containers` so reader and
writer share ONE ROM layout.
"""

from __future__ import annotations

from typing import Any, Dict

# Field order within a container's 4 bytes — the byte-order the parser reads.
_CONTAINER_FIELDS = ("mode", "id_a", "id_b", "id_c")
_CONTAINER_COUNT = 4
_CONTAINER_STRIDE = 4
_CONTAINERS_OFFSET = 8   # containers begin at effect_flags_ptr + 8


def patch_containers_into(
    buf: bytearray, sound_containers: Dict[str, Any], effect_flags_ptr: int
) -> None:
    """Partial-patch the 4 SoundContainers of `buf` IN PLACE from `sound_containers`
    (the parsed, possibly edited doc). Reusable core shared by the standalone
    `patch_containers_section` and the per-section serializer registry (F1 #264).

    Only the known container bytes (mode, id_a, id_b, id_c) are overwritten; all
    other bytes stay verbatim. A None/empty doc, or fewer than 4 container entries,
    leaves the missing ones untouched. Mirrors parse_sound_containers' base math
    (effect_flags_ptr + 8 + ci*4)."""
    if not isinstance(sound_containers, dict):
        return
    containers = sound_containers.get("containers")
    if not isinstance(containers, list):
        return
    base = effect_flags_ptr + _CONTAINERS_OFFSET
    for ci in range(min(_CONTAINER_COUNT, len(containers))):
        entry = containers[ci]
        if not isinstance(entry, dict):
            continue
        cbase = base + ci * _CONTAINER_STRIDE
        for k, field in enumerate(_CONTAINER_FIELDS):
            buf[cbase + k] = int(entry.get(field, 0)) & 0xFF


def patch_containers_section(
    base_bytes: bytes, sound_containers: Dict[str, Any], effect_flags_ptr: int
) -> bytes:
    """Return a copy of `base_bytes` with the SoundContainers re-serialized from
    `sound_containers`. A thin copy wrapper over `patch_containers_into`."""
    buf = bytearray(base_bytes)
    patch_containers_into(buf, sound_containers, effect_flags_ptr)
    return bytes(buf)
