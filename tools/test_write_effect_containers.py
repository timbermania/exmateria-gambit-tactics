"""Unit tests for the byte-exact SOUNDCONTAINER writer (TIER-2, #289).

`write_effect_containers.patch_containers_section` is the inverse of
`parse_effect.parse_sound_containers`: it takes the base `E###.BIN` bytes, the
parsed (possibly edited) `sound_containers` doc ({"containers": [ {mode, id_a,
id_b, id_c, index}, ... ]}), and the header's `effect_flags_ptr`, and returns a
NEW byte buffer in which the 4 containers — 4 bytes each [mode, id_a, id_b, id_c]
at effect_flags_ptr + 8 + ci*4 — are re-serialized from their raw fields. Every
byte outside those 16 is preserved verbatim (a partial patch, mirroring
write_effect_sound). The convenience `index` field has no ROM counterpart and is
dropped.

These are the SHARED, effect-global TIER-2 SoundContainers a timeline sound_id
resolves THROUGH (container_idx = sound_id - 2) before reaching a FEDS pair. The
containers live in the header's Effect-Flags section (#272); this writer owns ONLY
the 16 container bytes at +8, leaving the rest of that section to #272.

Expected values come from an independent copy of the ROM layout recomputed here,
NOT from the writer's own computation.

Run from tools/:
    python3 -m unittest test_write_effect_containers
"""

from __future__ import annotations

import os
import unittest

import parse_effect as pe
import write_effect_containers as wec
import effect_writer_registry as ewr
import sys
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from _repo_paths import effect_dir as _effect_dir  # noqa: E402


_EFFECT_FLAGS_PTR = 0x40


def _container_base(ci: int) -> int:
    """Independent copy of the ROM layout: 4 bytes per container at flags+8+ci*4."""
    return _EFFECT_FLAGS_PTR + 8 + ci * 4


def _field_offset(ci: int, field: str) -> int:
    return _container_base(ci) + ["mode", "id_a", "id_b", "id_c"].index(field)


def _synthetic_base() -> bytearray:
    """A base buffer covering the 4 containers, filled with a deterministic
    non-trivial pattern so untouched regions are verifiable."""
    size = _container_base(4) + 32
    return bytearray((i * 11 + 5) & 0xFF for i in range(size))


def _diff_indices(a: bytes, b: bytes) -> list:
    assert len(a) == len(b)
    return [i for i in range(len(a)) if a[i] != b[i]]


class ContainerWriterRoundTrip(unittest.TestCase):
    def test_unchanged_roundtrip_is_byte_identical(self):
        base = bytes(_synthetic_base())
        doc = pe.parse_sound_containers(base, _EFFECT_FLAGS_PTR)
        out = wec.patch_containers_section(base, doc, _EFFECT_FLAGS_PTR)
        self.assertEqual(out, base)

    def test_patch_does_not_mutate_input(self):
        base_ba = _synthetic_base()
        snapshot = bytes(base_ba)
        doc = pe.parse_sound_containers(bytes(base_ba), _EFFECT_FLAGS_PTR)
        wec.patch_containers_section(bytes(base_ba), doc, _EFFECT_FLAGS_PTR)
        self.assertEqual(bytes(base_ba), snapshot)

    def test_single_mode_edit_touches_exactly_one_byte(self):
        base = bytes(_synthetic_base())
        doc = pe.parse_sound_containers(base, _EFFECT_FLAGS_PTR)
        target = _field_offset(2, "mode")
        new_val = base[target] ^ 0xFF
        doc["containers"][2]["mode"] = new_val
        out = wec.patch_containers_section(base, doc, _EFFECT_FLAGS_PTR)
        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_val)
        reparsed = pe.parse_sound_containers(out, _EFFECT_FLAGS_PTR)
        self.assertEqual(reparsed["containers"][2]["mode"], new_val)

    def test_id_b_edit_touches_exactly_one_byte(self):
        base = bytes(_synthetic_base())
        doc = pe.parse_sound_containers(base, _EFFECT_FLAGS_PTR)
        target = _field_offset(0, "id_b")
        new_val = base[target] ^ 0x5A
        doc["containers"][0]["id_b"] = new_val
        out = wec.patch_containers_section(base, doc, _EFFECT_FLAGS_PTR)
        self.assertEqual(_diff_indices(base, out), [target])
        self.assertEqual(out[target], new_val)

    def test_index_key_is_dropped_byte_identical(self):
        """The convenience `index` field has no ROM byte — a doc carrying it must
        serialize byte-identically (the writer reads only mode + id_a/id_b/id_c)."""
        base = bytes(_synthetic_base())
        doc = pe.parse_sound_containers(base, _EFFECT_FLAGS_PTR)
        for ci, c in enumerate(doc["containers"]):
            c["index"] = 99 - ci   # clobber the convenience field
        out = wec.patch_containers_section(base, doc, _EFFECT_FLAGS_PTR)
        self.assertEqual(out, base)

    def test_registry_patch_all_writes_the_container_section(self):
        """The registry seam: patch_all routes a 'sound_containers' block through the
        registered serializer using the header's effect_flags_ptr geometry."""
        base = bytes(_synthetic_base())
        doc = pe.parse_sound_containers(base, _EFFECT_FLAGS_PTR)
        target = _field_offset(3, "id_c")
        doc["containers"][3]["id_c"] = base[target] ^ 0xFF
        header = {"effect_flags_ptr": _EFFECT_FLAGS_PTR}
        out = ewr.patch_all(base, {"sound_containers": doc}, header)
        self.assertEqual(_diff_indices(base, out), [target])


_E019 = str(_effect_dir() / "E019.BIN")


class ContainerWriterRealBin(unittest.TestCase):
    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_unchanged_roundtrip_is_byte_identical(self):
        with open(_E019, "rb") as f:
            base = f.read()
        flags_ptr = pe.parse_header(base)["effect_flags_ptr"]
        doc = pe.parse_sound_containers(base, flags_ptr)
        if doc is None:
            self.skipTest("E019 has no container region")
        out = wec.patch_containers_section(base, doc, flags_ptr)
        self.assertEqual(out, base)

    @unittest.skipUnless(os.path.exists(_E019), "E019.BIN not available")
    def test_real_e019_edited_mode_changes_only_that_byte(self):
        with open(_E019, "rb") as f:
            base = f.read()
        flags_ptr = pe.parse_header(base)["effect_flags_ptr"]
        doc = pe.parse_sound_containers(base, flags_ptr)
        if doc is None:
            self.skipTest("E019 has no container region")
        target = flags_ptr + 8 + 1 * 4 + 1   # container 1, id_a
        doc["containers"][1]["id_a"] = base[target] ^ 0x3C
        out = wec.patch_containers_section(base, doc, flags_ptr)
        self.assertEqual(_diff_indices(base, out), [target])


if __name__ == "__main__":
    unittest.main()
