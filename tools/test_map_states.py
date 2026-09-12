"""Tests for the System-C map-state enumeration + export fan-out (#131).

Asset-free unit tests pin the pure state-enumeration / dedup logic with
synthetic ``MapResource`` lists — they run everywhere, including machines
without the gitignored project-assets extract.

Asset-gated integration tests (skipped when the MAP extract is missing) parse
MAP064 (Bethla Sluice) end-to-end and assert the root holds the 547-poly closed
gate while ``states/secondary_day_none/`` holds the 500-poly open gate, and that
the root manifest's ``states[]`` lists both plus the deduplicated OVERRIDE.

Run from tools/:
    uv run python -m unittest test_map_states
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS_DIR))

from fft_exporter.map_states import (
    build_states_index,
    enumerate_map_states,
    resolve_palette_sidecars,
    resolve_state_exports,
    resolve_texture_sidecars,
    state_dir_name,
)
from fft_exporter.models.map_resource import (
    MapResource,
    MapArrangementState,
    MapTime,
    MapWeather,
    ResourceType,
)
from fft_exporter.models.lighting import Lighting
from fft_exporter.models.palette import Palette, PaletteColor

MAP_DIR = TOOLS_DIR.parent.parent / "project-assets" / "fft-extract" / "MAP"


def _mesh(
    arrangement: MapArrangementState,
    time: MapTime,
    weather: MapWeather,
    resource_type: ResourceType,
    x_file: int,
) -> MapResource:
    """A synthetic mesh row (no resource_data; enumeration is metadata-only)."""
    return MapResource(
        resource_type=resource_type,
        arrangement=arrangement,
        time=time,
        weather=weather,
        file_sector=x_file,
        raw_data=b"",
        x_file=x_file,
    )


PRI, SEC = MapArrangementState.PRIMARY, MapArrangementState.SECONDARY
DAY, NIGHT = MapTime.DAY, MapTime.NIGHT
NONE = MapWeather.NONE
INITIAL = ResourceType.INITIAL_MESH_DATA
OVERRIDE = ResourceType.OVERRIDE_MESH_DATA
ALTERNATE = ResourceType.ALTERNATE_STATE_MESH_DATA


# --------------------------------------------------------------------------
# enumerate_map_states
# --------------------------------------------------------------------------
class EnumerateStatesTest(unittest.TestCase):

    def test_dir_name(self) -> None:
        self.assertEqual(state_dir_name(SEC, DAY, NONE), "secondary_day_none")
        self.assertEqual(
            state_dir_name(PRI, NIGHT, MapWeather.HEAVY),
            "primary_night_heavy",
        )

    def test_empty(self) -> None:
        self.assertEqual(enumerate_map_states([]), [])

    def test_default_is_primary_day_none_first(self) -> None:
        rows = [
            _mesh(SEC, DAY, NONE, ALTERNATE, 19),
            _mesh(PRI, DAY, NONE, INITIAL, 10),  # the default, even though 2nd
        ]
        states = enumerate_map_states(rows)
        self.assertTrue(states[0].is_default)
        self.assertEqual(states[0].x_file, 10)
        self.assertEqual(states[0].subdir, ".")
        self.assertEqual(states[1].subdir, "secondary_day_none")
        self.assertFalse(states[1].is_default)

    def test_default_falls_back_to_first_row(self) -> None:
        # No PRIMARY/DAY/NONE row -> first row is the default (MAP034 shape).
        rows = [
            _mesh(PRI, DAY, NONE, OVERRIDE, 5),  # OVERRIDE still matches PRI/DAY/NONE
            _mesh(SEC, DAY, NONE, ALTERNATE, 9),
        ]
        states = enumerate_map_states(rows)
        self.assertTrue(states[0].is_default)
        self.assertEqual(states[0].resource_type, OVERRIDE)

    def test_default_fallback_when_no_canonical_key(self) -> None:
        rows = [_mesh(SEC, NIGHT, NONE, ALTERNATE, 3)]
        states = enumerate_map_states(rows)
        self.assertTrue(states[0].is_default)
        self.assertEqual(states[0].subdir, ".")

    def test_subdir_collision_disambiguated(self) -> None:
        # Two distinct non-default PRIMARY/DAY/NONE alternates (MAP011/MAP034).
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, NONE, ALTERNATE, 14),
            _mesh(PRI, DAY, NONE, ALTERNATE, 18),
        ]
        states = enumerate_map_states(rows)
        self.assertEqual(states[1].subdir, "primary_day_none")
        self.assertEqual(states[2].subdir, "primary_day_none_2")
        # all subdirs unique
        subdirs = [s.subdir for s in states]
        self.assertEqual(len(subdirs), len(set(subdirs)))


# --------------------------------------------------------------------------
# resolve_state_exports (dedup rule)
# --------------------------------------------------------------------------
class ResolveExportsTest(unittest.TestCase):

    def test_map064_shape(self) -> None:
        # INITIAL (default) + OVERRIDE same geometry + SECONDARY distinct.
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, NONE, OVERRIDE, 14),
            _mesh(SEC, DAY, NONE, ALTERNATE, 19),
        ]
        states = enumerate_map_states(rows)
        sigs = ["geomA", "geomA", "geomB"]  # OVERRIDE duplicates INITIAL
        resolved = resolve_state_exports(states, sigs)

        self.assertTrue(resolved[0].export)
        self.assertEqual(resolved[0].rel_dir, ".")
        # OVERRIDE deduped onto the default dir, not exported.
        self.assertFalse(resolved[1].export)
        self.assertEqual(resolved[1].rel_dir, ".")
        # SECONDARY exports into its own subdir.
        self.assertTrue(resolved[2].export)
        self.assertEqual(resolved[2].rel_dir, "states/secondary_day_none")

    def test_empty_geometry_reuses_default(self) -> None:
        # NIGHT/weather rows with a null primary mesh (signature None).
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["geomA", None])
        self.assertFalse(resolved[1].export)
        self.assertEqual(resolved[1].rel_dir, ".")

    def test_distinct_geometry_each_exports(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, NONE, ALTERNATE, 14),
            _mesh(PRI, DAY, NONE, ALTERNATE, 18),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", "g1", "g2"])
        self.assertEqual([r.export for r in resolved], [True, True, True])
        self.assertEqual(resolved[1].rel_dir, "states/primary_day_none")
        self.assertEqual(resolved[2].rel_dir, "states/primary_day_none_2")

    def test_second_dedup_points_at_first_nondefault(self) -> None:
        # A later row matching an exported NON-default geometry points at it.
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(SEC, DAY, NONE, ALTERNATE, 14),
            _mesh(SEC, NIGHT, NONE, ALTERNATE, 18),  # same geom as the SEC/DAY row
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", "gSEC", "gSEC"])
        self.assertTrue(resolved[1].export)
        self.assertFalse(resolved[2].export)
        self.assertEqual(resolved[2].rel_dir, "states/secondary_day_none")

    def test_default_with_empty_geometry_still_exports(self) -> None:
        # MAP053 shape: default INITIAL has a null primary mesh (pre-existing
        # GLTF failure downstream) but is still the root export.
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, NONE, OVERRIDE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, [None, "real"])
        self.assertTrue(resolved[0].export)
        # OVERRIDE has real geometry -> exports into its own subdir.
        self.assertTrue(resolved[1].export)
        self.assertEqual(resolved[1].rel_dir, "states/primary_day_none")


# --------------------------------------------------------------------------
# build_states_index
# --------------------------------------------------------------------------
class StatesIndexTest(unittest.TestCase):

    def test_index_lists_every_row(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, NONE, OVERRIDE, 14),
            _mesh(SEC, DAY, NONE, ALTERNATE, 19),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g", "g", "g2"])
        index = build_states_index(resolved)
        self.assertEqual(len(index), 3)
        self.assertEqual(
            index[0],
            {
                "arrangement": "Primary",
                "time": "Day",
                "weather": "None",
                "arrangement_id": 0,
                "night": 0,
                "weather_raw": 0,
                "resource_type": "Initial",
                "dir": ".",
                "default": True,
                "lighting": {
                    "ambient": {"r": 0, "g": 0, "b": 0},
                    "directional_lights": [],
                    "gradient": {
                        "top": {"r": 26, "g": 38, "b": 77},
                        "bottom": {"r": 77, "g": 128, "b": 179},
                    },
                },
                "palette_file": None,
                "texture_file": None,
            },
        )
        self.assertEqual(index[1]["resource_type"], "Override")
        self.assertEqual(index[1]["dir"], ".")
        self.assertEqual(index[2]["resource_type"], "Alternate")
        self.assertEqual(index[2]["dir"], "states/secondary_day_none")

    def test_index_carries_raw_match_keys(self) -> None:
        # ADR-0056: the runtime selects a map state on RAW ints, never labels
        # (the scenario/GNS weather enums are offset by NoneAlt). Each entry
        # carries authoritative match keys alongside the human labels.
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, MapWeather.LIGHT, ALTERNATE, 14),
            _mesh(SEC, DAY, MapWeather.NONE_ALT, ALTERNATE, 18),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", "g1", "g2"])
        index = build_states_index(resolved)

        # default = primary/day/none -> 0/0/0
        self.assertEqual(index[0]["weather_raw"], 0)
        self.assertEqual(index[0]["night"], 0)
        self.assertEqual(index[0]["arrangement_id"], 0)
        # primary night LIGHT -> weather 2, night 1, arrangement 0
        self.assertEqual(index[1]["weather_raw"], 2)
        self.assertEqual(index[1]["night"], 1)
        self.assertEqual(index[1]["arrangement_id"], 0)
        # secondary day NONE_ALT -> weather 1, night 0, arrangement 1
        self.assertEqual(index[2]["weather_raw"], 1)
        self.assertEqual(index[2]["night"], 0)
        self.assertEqual(index[2]["arrangement_id"], 1)
        # human labels still present + unchanged
        self.assertEqual(index[0]["weather"], "None")
        self.assertEqual(index[1]["time"], "Night")


# --------------------------------------------------------------------------
# build_states_index — per-state lighting (ADR-0056)
# --------------------------------------------------------------------------
class StatesIndexLightingTest(unittest.TestCase):

    def test_each_state_carries_its_own_lighting(self) -> None:
        # A geometry-deduped env-only row (null primary mesh) must STILL keep
        # its distinct sky/ambient — that is the whole point of ADR-0056.
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),  # env-only, reuses default geom
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        day = Lighting(
            ambient_r=73, ambient_g=61, ambient_b=46,
            gradient_top_r=135, gradient_top_g=138, gradient_top_b=149,
            gradient_bottom_r=0, gradient_bottom_g=8, gradient_bottom_b=16,
        )
        night = Lighting(gradient_top_r=10, gradient_top_g=10, gradient_top_b=30)

        index = build_states_index(resolved, [day, night])

        self.assertEqual(
            index[0]["lighting"]["gradient"]["top"], {"r": 135, "g": 138, "b": 149}
        )
        self.assertEqual(
            index[0]["lighting"]["gradient"]["bottom"], {"r": 0, "g": 8, "b": 16}
        )
        self.assertEqual(index[0]["lighting"]["ambient"], {"r": 73, "g": 61, "b": 46})
        # deduped night row keeps its OWN sky, not the default's.
        self.assertEqual(
            index[1]["lighting"]["gradient"]["top"], {"r": 10, "g": 10, "b": 30}
        )

    def test_missing_lighting_falls_back_to_engine_default(self) -> None:
        rows = [_mesh(PRI, DAY, NONE, INITIAL, 10)]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0"])
        index = build_states_index(resolved, [None])
        # same default the single-state manifest uses when a row has no lighting.
        self.assertEqual(
            index[0]["lighting"]["gradient"]["top"], {"r": 26, "g": 38, "b": 77}
        )

    def test_each_state_carries_its_palette_file(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        index = build_states_index(
            resolved, [None, None], palette_files=[None, "palettes_abc123.json"]
        )
        # default -> null (root palettes.json); night -> its own sidecar.
        self.assertIsNone(index[0]["palette_file"])
        self.assertEqual(index[1]["palette_file"], "palettes_abc123.json")

    def test_palette_file_defaults_to_null_when_omitted(self) -> None:
        rows = [_mesh(PRI, DAY, NONE, INITIAL, 10)]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0"])
        index = build_states_index(resolved)
        self.assertIsNone(index[0]["palette_file"])

    def test_each_state_carries_its_texture_file(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        index = build_states_index(
            resolved, [None, None],
            palette_files=[None, None],
            texture_files=[None, "texture_abc123.tga"],
        )
        # default -> null (root texture_indexed.tga); night -> its own sidecar.
        self.assertIsNone(index[0]["texture_file"])
        self.assertEqual(index[1]["texture_file"], "texture_abc123.tga")

    def test_texture_file_defaults_to_null_when_omitted(self) -> None:
        rows = [_mesh(PRI, DAY, NONE, INITIAL, 10)]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0"])
        index = build_states_index(resolved)
        self.assertIsNone(index[0]["texture_file"])


# --------------------------------------------------------------------------
# resolve_palette_sidecars — deduped per-state palette files (ADR-0056)
# --------------------------------------------------------------------------
def _pal(*rgb: int) -> Palette:
    """A tiny synthetic palette keyed by one color (content is all that matters)."""
    return Palette(colors=[PaletteColor(red=r, green=r, blue=r, is_transparent=False)
                           for r in rgb])


class ResolvePaletteSidecarsTest(unittest.TestCase):

    def test_default_uses_root_palettes_json(self) -> None:
        # The default state's palette is the root palettes.json — no sidecar.
        rows = [_mesh(PRI, DAY, NONE, INITIAL, 10)]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0"])
        files, sidecars = resolve_palette_sidecars(resolved, [[_pal(1, 2, 3)]])
        self.assertEqual(files, [None])
        self.assertEqual(sidecars, {})

    def test_state_matching_default_reuses_root(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),  # same palette as default
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        same = [_pal(1, 2, 3)]
        files, sidecars = resolve_palette_sidecars(resolved, [same, [_pal(1, 2, 3)]])
        self.assertEqual(files, [None, None])
        self.assertEqual(sidecars, {})

    def test_distinct_palette_gets_one_sidecar(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        files, sidecars = resolve_palette_sidecars(
            resolved, [[_pal(1, 1, 1)], [_pal(9, 9, 9)]]
        )
        self.assertIsNone(files[0])
        self.assertIsNotNone(files[1])
        self.assertTrue(files[1].startswith("palettes_") and files[1].endswith(".json"))
        # exactly one sidecar written, and files[1] points at it.
        self.assertEqual(list(sidecars.keys()), [files[1]])

    def test_two_states_same_distinct_palette_share_one_sidecar(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
            _mesh(SEC, NIGHT, NONE, ALTERNATE, 18),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None, None])
        weather = [_pal(7, 7, 7)]
        files, sidecars = resolve_palette_sidecars(
            resolved, [[_pal(0, 0, 0)], weather, [_pal(7, 7, 7)]]
        )
        # the two weather states dedup onto ONE sidecar.
        self.assertEqual(files[1], files[2])
        self.assertIsNotNone(files[1])
        self.assertEqual(len(sidecars), 1)

    # -- per-state palette-animation frames (#132) --

    def test_sidecar_with_own_frames_carries_them(self) -> None:
        # A night row that overrides its base CLUT *and* ships its own animated-
        # water frames → the sidecar carries those exact frames (not []).
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        night_frames = [_pal(4, 4, 4), _pal(5, 5, 5)]
        files, sidecars = resolve_palette_sidecars(
            resolved,
            [[_pal(1, 1, 1)], [_pal(9, 9, 9)]],
            [[], night_frames],
        )
        pset, frames = sidecars[files[1]]
        self.assertEqual(frames, night_frames)

    def test_frameless_override_inherits_default_frames(self) -> None:
        # A day-weather row that patches only its base CLUT (no own offset-112
        # table) inherits the DEFAULT state's frames so its animated palette
        # still cycles — this is the scenario-6 water fix (#132).
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, MapWeather.STRONG, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        default_frames = [_pal(2, 2, 2), _pal(3, 3, 3)]
        files, sidecars = resolve_palette_sidecars(
            resolved,
            [[_pal(1, 1, 1)], [_pal(8, 8, 8)]],  # distinct base CLUT
            [default_frames, []],                 # override carries no own frames
        )
        self.assertIsNotNone(files[1])
        pset, frames = sidecars[files[1]]
        self.assertEqual(frames, default_frames)

    def test_same_base_different_frames_do_not_dedup(self) -> None:
        # Identical base CLUT but distinct frame tables must stay separate
        # sidecars — the frame table is part of the dedup key.
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, DAY, MapWeather.STRONG, ALTERNATE, 14),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 18),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None, None])
        base = [_pal(6, 6, 6)]
        files, sidecars = resolve_palette_sidecars(
            resolved,
            [[_pal(1, 1, 1)], base, [_pal(6, 6, 6)]],
            [[], [_pal(4, 4, 4)], [_pal(5, 5, 5)]],  # same base, different frames
        )
        self.assertNotEqual(files[1], files[2])
        self.assertEqual(len(sidecars), 2)


# --------------------------------------------------------------------------
# resolve_texture_sidecars — deduped per-state texture files (#132)
# --------------------------------------------------------------------------
class ResolveTextureSidecarsTest(unittest.TestCase):
    """Full-payload texture dedup, the direct twin of resolve_palette_sidecars.

    The payload is the raw texture-resource bytes (find_texture_for_state
    resolves which one each state gets); the default state's payload IS the
    root texture_indexed.tga, so any state matching it — or with no texture —
    reuses the root (file == None).
    """

    def test_default_uses_root_texture(self) -> None:
        rows = [_mesh(PRI, DAY, NONE, INITIAL, 10)]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0"])
        files, sidecars = resolve_texture_sidecars(resolved, [b"DAYTEX"])
        self.assertEqual(files, [None])
        self.assertEqual(sidecars, {})

    def test_state_matching_default_reuses_root(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),  # same texture as default
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        files, sidecars = resolve_texture_sidecars(resolved, [b"DAYTEX", b"DAYTEX"])
        self.assertEqual(files, [None, None])
        self.assertEqual(sidecars, {})

    def test_state_without_texture_reuses_root(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        files, sidecars = resolve_texture_sidecars(resolved, [b"DAYTEX", None])
        self.assertEqual(files, [None, None])
        self.assertEqual(sidecars, {})

    def test_distinct_texture_gets_one_sidecar(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None])
        files, sidecars = resolve_texture_sidecars(resolved, [b"DAYTEX", b"NIGHTTEX"])
        self.assertIsNone(files[0])
        self.assertIsNotNone(files[1])
        self.assertTrue(files[1].startswith("texture_") and files[1].endswith(".tga"))
        # never collide with the root texture name.
        self.assertNotEqual(files[1], "texture_indexed.tga")
        # exactly one sidecar written, mapping filename -> payload.
        self.assertEqual(sidecars, {files[1]: b"NIGHTTEX"})

    def test_two_states_same_distinct_texture_share_one_sidecar(self) -> None:
        rows = [
            _mesh(PRI, DAY, NONE, INITIAL, 10),
            _mesh(PRI, NIGHT, NONE, ALTERNATE, 14),
            _mesh(SEC, NIGHT, NONE, ALTERNATE, 18),
        ]
        states = enumerate_map_states(rows)
        resolved = resolve_state_exports(states, ["g0", None, None])
        files, sidecars = resolve_texture_sidecars(
            resolved, [b"DAYTEX", b"NIGHTTEX", b"NIGHTTEX"]
        )
        # the two night states dedup onto ONE sidecar.
        self.assertEqual(files[1], files[2])
        self.assertIsNotNone(files[1])
        self.assertEqual(len(sidecars), 1)


# --------------------------------------------------------------------------
# Asset-gated integration: MAP064 Bethla Sluice
# --------------------------------------------------------------------------
def _poly_count(geometry_linked_path: Path) -> int:
    data = json.loads(geometry_linked_path.read_text())
    prims = data["Meshes"]["PrimaryMesh"]["Primitives"]
    return sum(p["PolygonCount"] for p in prims)


@unittest.skipUnless(MAP_DIR.is_dir(), "MAP extract not present")
class Map064IntegrationTest(unittest.TestCase):

    def test_secondary_state_geometry_split(self) -> None:
        from parse_map import parse_map

        with tempfile.TemporaryDirectory() as td:
            out = Path(td) / "MAP064"
            self.assertTrue(parse_map(MAP_DIR / "MAP064.GNS", out, verbose=False))

            # Root = 547-poly closed gate.
            self.assertEqual(_poly_count(out / "geometry_linked.json"), 547)

            # SECONDARY (open gate) = 500-poly geometry in its own subdir.
            sec = out / "states" / "secondary_day_none"
            self.assertTrue(sec.is_dir(), "secondary_day_none/ not created")
            self.assertEqual(_poly_count(sec / "geometry_linked.json"), 500)

            # Root scene manifest states[] lists both + the deduped OVERRIDE
            # (ADR-0056: states[] is a scene-level environmental concern).
            manifest = json.loads((out / "scene_manifest.json").read_text())
            self.assertIn("states", manifest)
            states = manifest["states"]
            dirs = sorted(s["dir"] for s in states)
            self.assertIn("states/secondary_day_none", dirs)
            # default + deduped OVERRIDE both point at "."
            self.assertEqual(dirs.count("."), 2)
            sec_entry = next(s for s in states if s["dir"] == "states/secondary_day_none")
            self.assertEqual(sec_entry["arrangement"], "Secondary")
            self.assertEqual(sec_entry["resource_type"], "Alternate")


if __name__ == "__main__":
    unittest.main()
