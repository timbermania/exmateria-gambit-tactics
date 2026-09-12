"""System-C map-state enumeration (#131).

A FFT map's GNS index lists multiple mesh rows, each tagged with
arrangement / time / weather and a resource type (INITIAL / OVERRIDE /
ALTERNATE). Some rows ship a whole alternate baked geometry (the Bethla
Sluice open-gate, night/weather variants, post-event geometry); many others
only patch the *non-geometry* sections (lighting/palette) and carry a null
primary-mesh pointer.

These pure functions turn the mesh rows into an ordered list of states (default
PRIMARY/DAY/NONE first) with a unique output subdirectory each, and resolve
which states actually need their own geometry export vs. which deduplicate onto
an already-exported one. They are deliberately content-free where possible so
they unit-test with synthetic ``MapResource`` lists (no asset extract needed);
the geometry signatures used for dedup are computed by the caller and passed in.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

from .models.map_resource import (
    MapResource,
    MapArrangementState,
    MapTime,
    MapWeather,
    ResourceType,
)
from .models.lighting import Lighting
from .models.palette import Palette
from .parsers.lighting import lighting_to_dict


# Short, manifest-friendly labels for the mesh resource types.
_RESOURCE_TYPE_LABEL = {
    ResourceType.INITIAL_MESH_DATA: "Initial",
    ResourceType.OVERRIDE_MESH_DATA: "Override",
    ResourceType.ALTERNATE_STATE_MESH_DATA: "Alternate",
}


def state_dir_name(
    arrangement: MapArrangementState,
    time: MapTime,
    weather: MapWeather,
) -> str:
    """Directory leaf name for a state: ``<arrangement>_<time>_<weather>`` lower."""
    return f"{arrangement.name}_{time.name}_{weather.name}".lower()


@dataclass
class MapStateRef:
    """One distinct GNS mesh row, tagged for export routing.

    ``subdir`` is the unique output leaf for non-default states (``"."`` for the
    default state, which stays at the map root). ``resource`` points back at the
    source mesh row so the caller can read its ``resource_data``.
    """

    resource: MapResource
    arrangement: MapArrangementState
    time: MapTime
    weather: MapWeather
    resource_type: ResourceType
    x_file: int
    is_default: bool
    subdir: str

    @property
    def resource_type_label(self) -> str:
        return _RESOURCE_TYPE_LABEL.get(
            self.resource_type, self.resource_type.name.title()
        )


def _pick_default(mesh_resources: Sequence[MapResource]) -> Optional[MapResource]:
    """The default (root) state: first PRIMARY/DAY/NONE row, else the first row.

    Matches the long-standing single-state selection in ``parse_map`` /
    ``fft_exporter.__main__`` exactly so the default export stays byte-identical.
    """
    for r in mesh_resources:
        if (
            r.arrangement == MapArrangementState.PRIMARY
            and r.time == MapTime.DAY
            and r.weather == MapWeather.NONE
        ):
            return r
    return mesh_resources[0] if mesh_resources else None


def enumerate_map_states(mesh_resources: Sequence[MapResource]) -> List[MapStateRef]:
    """Ordered distinct GNS mesh rows, default first, each with a unique subdir.

    Pure metadata transform (no ``resource_data`` required). The default state
    (PRIMARY/DAY/NONE, or the first row) comes first with ``subdir == "."``;
    every other row follows in GNS order with a unique ``states/`` leaf name.
    When two non-default rows share an ``<arrangement>_<time>_<weather>`` key
    (e.g. two alternate PRIMARY/DAY/NONE geometries), later ones get a numeric
    ``_2``, ``_3`` ... suffix so directories never collide.
    """
    if not mesh_resources:
        return []

    default = _pick_default(mesh_resources)
    states: List[MapStateRef] = [
        MapStateRef(
            resource=default,
            arrangement=default.arrangement,
            time=default.time,
            weather=default.weather,
            resource_type=default.resource_type,
            x_file=default.x_file,
            is_default=True,
            subdir=".",
        )
    ]

    used: set[str] = set()
    for r in mesh_resources:
        if r is default:
            continue
        base = state_dir_name(r.arrangement, r.time, r.weather)
        name = base
        n = 2
        while name in used:
            name = f"{base}_{n}"
            n += 1
        used.add(name)
        states.append(
            MapStateRef(
                resource=r,
                arrangement=r.arrangement,
                time=r.time,
                weather=r.weather,
                resource_type=r.resource_type,
                x_file=r.x_file,
                is_default=False,
                subdir=name,
            )
        )
    return states


@dataclass
class ResolvedState:
    """A state plus the dedup verdict.

    ``export`` is True when this state must write its own geometry. ``rel_dir``
    is the map-root-relative directory holding the geometry this state resolves
    to (``"."`` for the default / a state that reuses the default geometry, or
    ``states/<subdir>`` otherwise) — i.e. where the manifest ``states[]`` entry
    should point.
    """

    state: MapStateRef
    export: bool
    rel_dir: str


def _rel_dir(subdir: str) -> str:
    return "." if subdir == "." else f"states/{subdir}"


def resolve_state_exports(
    states: Sequence[MapStateRef],
    signatures: Sequence[Optional[str]],
) -> List[ResolvedState]:
    """Decide which states export their own geometry; dedup the rest.

    ``signatures[i]`` is a content hash of ``states[i]``'s primary-mesh geometry,
    or ``None``/``""`` when that row carries *no* primary mesh (null ``0x40``
    pointer — a lighting/palette-only override). A non-default state is NOT
    re-exported (it deduplicates) when:

    * it has no own geometry (signature falsy) — it reuses the default geometry; or
    * its geometry signature duplicates an already-exported state — it points at
      that state's directory.

    The default state always exports (it owns the map root). This is the
    System-C dedup rule: MAP064's PRIMARY OVERRIDE has a byte-identical
    primary-mesh to PRIMARY INITIAL, so it collapses onto ``"."`` while still
    being listed.
    """
    resolved: List[ResolvedState] = []
    sig_to_dir: dict[str, str] = {}

    for st, sig in zip(states, signatures):
        if st.is_default:
            resolved.append(ResolvedState(st, True, "."))
            if sig:
                sig_to_dir.setdefault(sig, ".")
            continue

        if not sig:
            # No own primary mesh — reuses the default geometry.
            resolved.append(ResolvedState(st, False, "."))
            continue

        if sig in sig_to_dir:
            resolved.append(ResolvedState(st, False, sig_to_dir[sig]))
        else:
            sig_to_dir[sig] = _rel_dir(st.subdir)
            resolved.append(ResolvedState(st, True, _rel_dir(st.subdir)))

    return resolved


def _palette_set_hash(palettes: Sequence[Palette]) -> str:
    """Stable content hash of a 16×16 palette set (5-bit channels + transparency)."""
    h = hashlib.sha1()
    for pal in palettes:
        for c in pal.colors:
            h.update(bytes((c.red, c.green, c.blue, 1 if c.is_transparent else 0)))
        h.update(b"|")  # palette boundary so [A][BC] != [AB][C]
    return h.hexdigest()[:12]


def _appearance_hash(
    palettes: Sequence[Palette],
    frames: Optional[Sequence[Palette]],
) -> str:
    """Content hash of a state's full palette *appearance* — base CLUT **and**
    its resolved palette-animation frames (#132).

    Two states with identical base palettes but different animated-water frames
    (e.g. a day row that inherits the default frames vs. a night row that ships
    its own) must NOT dedup onto one sidecar, so the frame table is part of the
    key — not just the base palettes.
    """
    h = hashlib.sha1()
    h.update(_palette_set_hash(palettes).encode())
    h.update(b"#anim#")
    for pal in frames or ():
        for c in pal.colors:
            h.update(bytes((c.red, c.green, c.blue, 1 if c.is_transparent else 0)))
        h.update(b"|")
    return h.hexdigest()[:12]


def resolve_palette_sidecars(
    resolved: Sequence[ResolvedState],
    palette_sets: Sequence[Optional[Sequence[Palette]]],
    frame_sets: Optional[Sequence[Optional[Sequence[Palette]]]] = None,
) -> Tuple[List[Optional[str]], Dict[str, Tuple[Sequence[Palette], Sequence[Palette]]]]:
    """Dedup per-state palette *appearance* into sidecar files (ADR-0056, #132).

    ``palette_sets[i]`` is the 16-palette base CLUT parsed for ``resolved[i]``
    (``None`` when that row carries no palette). ``frame_sets[i]`` is that row's
    own palette-animation frames (offset 112), or empty when it patches only the
    base CLUT. A frameless override **inherits the default state's frames** — the
    PSX frame table persists from the default resource unless a state ships its
    own — so day-weather water still cycles with the (unchanged) animated palette.

    The default state's appearance IS the root ``palettes.json``; any state whose
    base CLUT *and* resolved frames match it — or that has no own palette —
    resolves to ``None`` (reuse the root). Every *distinct* appearance is written
    once as ``palettes_<hash>.json`` and shared by all states carrying it.

    Returns ``(palette_files, sidecars)`` where ``palette_files[i]`` is the
    sidecar filename for state ``i`` (or ``None`` = root ``palettes.json``), and
    ``sidecars`` maps each filename to a ``(palette_set, frames)`` pair to write.
    """
    n = len(resolved)
    palette_files: List[Optional[str]] = [None] * n
    sidecars: Dict[str, Tuple[Sequence[Palette], Sequence[Palette]]] = {}
    if frame_sets is None:
        frame_sets = [None] * n

    default_pset: Optional[Sequence[Palette]] = None
    default_frames: Optional[Sequence[Palette]] = None
    for i in range(n):
        if resolved[i].state.is_default:
            default_pset = palette_sets[i]
            default_frames = frame_sets[i]
            break

    def resolved_frames(i: int) -> Sequence[Palette]:
        # A state's own frames, else inherit the default's (frame table persists).
        own = frame_sets[i]
        return own if own else (default_frames or [])

    default_key: Optional[str] = (
        _appearance_hash(default_pset, default_frames) if default_pset else None
    )

    key_to_file: Dict[str, str] = {}
    for i, rs in enumerate(resolved):
        pset = palette_sets[i]
        if rs.state.is_default or not pset:
            continue
        frames = resolved_frames(i)
        key = _appearance_hash(pset, frames)
        if key == default_key:
            continue  # identical appearance to the root palettes.json — reuse it.
        if key not in key_to_file:
            fname = f"palettes_{key}.json"
            key_to_file[key] = fname
            sidecars[fname] = (pset, frames)
        palette_files[i] = key_to_file[key]

    return palette_files, sidecars


def resolve_texture_sidecars(
    resolved: Sequence[ResolvedState],
    texture_payloads: Sequence[Optional[bytes]],
) -> Tuple[List[Optional[str]], Dict[str, bytes]]:
    """Dedup per-state *texture* payloads into sidecar files (#132).

    ``texture_payloads[i]`` is the raw texture-resource bytes resolved for
    ``resolved[i]`` (via ``find_texture_for_state`` in the caller), or ``None``
    when the state has no own texture. This is the direct structural twin of
    :func:`resolve_palette_sidecars`, but for the orthogonal texture layer: a
    night/weather row can differ from the default in its texture, its palette,
    or both.

    The default state's texture IS the root ``texture_indexed.tga``; any state
    whose full payload matches it — or that has no own texture — resolves to
    ``None`` (reuse the root). Every *distinct* payload is written once as
    ``texture_<hash>.tga`` (never ``texture_indexed.tga``, so the root is never
    shadowed) and shared by all states carrying it.

    Returns ``(texture_files, sidecars)`` where ``texture_files[i]`` is the
    sidecar filename for state ``i`` (or ``None`` = root ``texture_indexed.tga``),
    and ``sidecars`` maps each filename to the raw payload bytes to export.
    """
    n = len(resolved)
    texture_files: List[Optional[str]] = [None] * n
    sidecars: Dict[str, bytes] = {}

    default_payload: Optional[bytes] = None
    for i in range(n):
        if resolved[i].state.is_default:
            default_payload = texture_payloads[i]
            break

    def key(payload: bytes) -> str:
        return hashlib.sha1(payload).hexdigest()[:12]

    default_key: Optional[str] = key(default_payload) if default_payload else None

    key_to_file: Dict[str, str] = {}
    for i, rs in enumerate(resolved):
        payload = texture_payloads[i]
        if rs.state.is_default or not payload:
            continue
        k = key(payload)
        if k == default_key:
            continue  # identical texture to the root texture_indexed.tga — reuse it.
        if k not in key_to_file:
            fname = f"texture_{k}.tga"
            key_to_file[k] = fname
            sidecars[fname] = payload
        texture_files[i] = key_to_file[k]

    return texture_files, sidecars


def build_states_index(
    resolved: Sequence[ResolvedState],
    lightings: Optional[Sequence[Optional["Lighting"]]] = None,
    palette_files: Optional[Sequence[Optional[str]]] = None,
    texture_files: Optional[Sequence[Optional[str]]] = None,
) -> List[dict]:
    """Manifest ``states[]`` index — one entry per GNS mesh row.

    Lists every state (including deduplicated ones) with its arrangement / time
    / weather, resource type, and the directory holding its geometry. Each entry
    also carries the raw-int match keys the runtime selects on (ADR-0056) and its
    own ``lighting`` (sky gradient + ambient + directional lights) — the latter
    is per-state even for geometry-deduped rows, since an env-only weather/night
    row's whole purpose is a distinct sky over the shared geometry.

    ``lightings[i]`` is the parsed ``Lighting`` for ``resolved[i]`` (``None`` when
    that row has no lighting chunk → engine-default sky). When ``lightings`` is
    omitted entirely, every state falls back to the default sky. ``palette_files[i]``
    is the state's deduped palette sidecar name (``None`` = root ``palettes.json``),
    as produced by :func:`resolve_palette_sidecars`. ``texture_files[i]`` is the
    state's deduped texture sidecar name (``None`` = root ``texture_indexed.tga``),
    as produced by :func:`resolve_texture_sidecars` — the orthogonal texture layer.
    """
    index: List[dict] = []
    for i, rs in enumerate(resolved):
        st = rs.state
        lighting = lightings[i] if lightings is not None else None
        palette_file = palette_files[i] if palette_files is not None else None
        texture_file = texture_files[i] if texture_files is not None else None
        index.append(
            {
                "arrangement": st.arrangement.name.title(),
                "time": st.time.name.title(),
                "weather": st.weather.name.title(),
                # Raw-int authoritative match keys (ADR-0056): the runtime
                # selects on these, never on the labels above.
                "arrangement_id": st.arrangement.value,
                "night": st.time.value,
                "weather_raw": st.weather.value,
                "resource_type": st.resource_type_label,
                "dir": rs.rel_dir,
                "default": st.is_default,
                "lighting": lighting_to_dict(lighting),
                "palette_file": palette_file,
                "texture_file": texture_file,
            }
        )
    return index
