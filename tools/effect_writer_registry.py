"""Per-section serializer registry for byte-exact E###.BIN save (F1 #264).

The Effect Studio save loop needs to lower an author's edits back into a real
`E###.BIN` without disturbing the bytes it doesn't understand. #255 proved that
for ONE section (screen colour) via `write_effect_screen.patch_screen_section`:
a partial patch that re-serializes only the known fields and copies everything
else verbatim. This module generalizes that pattern to ALL sections so each
subsystem's build ticket can plug in its own serializer without touching the
save loop.

Shape:
  * Each subsystem registers `serialize_<section>(buf, header, block)` under a
    section name. The serializer partial-patches ITS section's bytes into the
    shared `bytearray buf` from `block` (that section's parsed, possibly edited
    sub-tree), reading its geometry from the parsed `header` (the single
    `parse_effect` offset source — no serializer hard-codes section pointers).
  * `patch_all(base, sections_by_name, header)` copies `base` once, then runs
    every registered serializer whose section is present in the edit set over
    that ONE buffer, and returns the new bytes. Sections absent from the edit
    set are left untouched; an unknown section name is a hard error (a typo must
    not silently drop an edit).

The screen serializer is registered here as the reference/first entry, wrapping
the proven in-place core `write_effect_screen.patch_screen_into`.
"""

from __future__ import annotations

import struct
from typing import Any, Callable, Dict, List

import parse_effect as pe
import write_effect_screen as wes
import write_effect_camera as wec
import write_effect_palette as wep
import write_effect_sound as wesnd
import write_effect_containers as wecon
import write_effect_emitters as wee
import write_effect_particle_timeline as wpt
import write_effect_flags as wef
import write_effect_time_scale as wts
import write_effect_frames as wef2
import write_effect_animation as wea
import write_effect_texture as wetx

# section name -> serialize(buf: bytearray, header: dict, block: Any) -> None
Serializer = Callable[[bytearray, Dict[str, Any], Any], None]

REGISTRY: Dict[str, Serializer] = {}

# Sections a studio edit can RESIZE. They splice LAST, because every other
# serializer reads fixed offsets out of the same parsed header and those are only
# valid while the buffer still has its original geometry (ADR-0085 2026-08-18b).
RESIZING_SECTIONS = ("sound_def",)

# Header geometry, shared by the relocation path.
_HEADER_SIZE = 0x28
_SOUND_DEF_PTR_OFF = 0x20
_TEXTURE_PTR_OFF = 0x24


def register(section: str, fn: Serializer = None):
    """Register `fn` as the serializer for `section`. Usable directly
    (`register("screen", serialize_screen)`) or as a decorator
    (`@register("screen")`). Refuses to silently clobber an existing section."""
    def _do(f: Serializer) -> Serializer:
        if section in REGISTRY and REGISTRY[section] is not f:
            raise ValueError("serializer for section %r already registered" % section)
        REGISTRY[section] = f
        return f

    return _do if fn is None else _do(fn)


def unregister(section: str) -> None:
    """Remove a section's serializer (mainly a test seam for probe registrations)."""
    REGISTRY.pop(section, None)


def serializer_for(section: str) -> Serializer:
    """The registered serializer for `section` (KeyError if none)."""
    return REGISTRY[section]


def registered_sections() -> List[str]:
    """The section names with a registered serializer."""
    return list(REGISTRY.keys())


def patch_all(
    base_bytes: bytes,
    sections_by_name: Dict[str, Any],
    header: Dict[str, Any],
    registry: Dict[str, Serializer] = None,
) -> bytes:
    """Return a NEW buffer: `base_bytes` with every section in `sections_by_name`
    partial-patched by its registered serializer, all other bytes verbatim.

    `sections_by_name` maps section name → that section's parsed (possibly edited)
    block. `header` is `parse_effect.parse_header`'s output (the geometry source).
    `registry` overrides the module registry (a test seam); defaults to `REGISTRY`.
    Raises KeyError if a named section has no registered serializer — a typo must
    surface, not drop the edit.
    """
    reg = REGISTRY if registry is None else registry
    buf = bytearray(base_bytes)
    # Stable sort: insertion order is preserved, resizing sections move to the end.
    for name in sorted(sections_by_name, key=lambda n: n in RESIZING_SECTIONS):
        if name not in reg:
            raise KeyError("no serializer registered for section %r" % name)
        reg[name](buf, header, sections_by_name[name])
    return bytes(buf)


# --- Built-in section serializers -----------------------------------------


@register("screen")
def serialize_screen(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Screen colour section (#255): three backdrop channels (for_each / phase1 /
    phase2). Geometry = the header's `timeline_section_ptr`; the write is the
    proven in-place core."""
    wes.patch_screen_into(buf, block, header["timeline_section_ptr"])


@register("palette")
def serialize_palette(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Palette / field-tint section (Subsystem 1, #266): nine channels (for_each /
    phase1 / phase2 x affected_units / caster / target). Geometry = the header's
    `timeline_section_ptr` (same super-section as screen); the write is the
    in-place core `write_effect_palette.patch_palette_into`."""
    wep.patch_palette_into(buf, block, header["timeline_section_ptr"])


@register("camera")
def serialize_camera(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Camera Timeline section (#267): three SoA tables (for_each / phase1 /
    phase2) of angle/position/zoom keyframes. Same geometry base as screen
    (the header's `timeline_section_ptr`); the write is the byte-exact in-place
    core, re-serializing each keyframe's raw arrays + command word."""
    wec.patch_camera_into(buf, block, header["timeline_section_ptr"])


@register("sound")
def serialize_sound(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Sound Timeline SFX-trigger tracks (Subsystem 3, #268): six outer (30 B) +
    three for-each (54 B) channels in the timeline section. Same geometry base as
    screen (the header's `timeline_section_ptr`); the write is the byte-exact
    in-place core, re-serializing only each keyframe's raw duration_frames +
    sound_id (TIER-1). TIER-2 SoundContainers / TIER-3 FEDS stay untouched."""
    wesnd.patch_sound_into(buf, block, header["timeline_section_ptr"])


@register("sound_def")
def serialize_sound_def(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """TIER-3 FEDS sound-definition section: `block` (the edited feds blob bytes)
    replaces [sound_def_ptr, texture_ptr).

    A bounded parameter patch is same-size and this degenerates to a pure splice.
    A STRUCTURAL edit resizes the stream — prune-for-real shrinks it, an inserted
    opcode grows it — and there is no room to absorb that in place: the amendment
    measured 0-3 bytes of slack per section across all 401 effects, so one added
    opcode overflows a quarter of the corpus. So a resize RELOCATES (ADR-0085
    amendment 2026-08-18b): splice, shift the whole tail, and repoint the one
    header pointer that lives after `sound_def_ptr` — `texture_ptr` — leaving the
    FEDS section still bounded by being immediately before the texture, which is
    the invariant `FedsBank._load_from_effect_bin` derives the section from.

    The blob is padded up to a 4-byte multiple first: every FEDS section in the
    corpus starts, ends and sizes 4-aligned, and those measured slack bytes ARE
    that padding, so this preserves the alignment rather than inventing one.

    A blob without the "feds" magic is a mis-addressed splice → refused, and so is
    a resize whose header geometry disagrees with the bytes it is about to move."""
    start = int(header["sound_def_ptr"])
    end = min(int(header["texture_ptr"]), len(buf))
    if start <= 0 or end <= start:
        raise ValueError("sound_def: no feds section (sound_def_ptr=%r texture_ptr=%r)"
                         % (header.get("sound_def_ptr"), header.get("texture_ptr")))
    blob = bytes(block)
    if blob[:4] != b"feds":
        raise ValueError("sound_def: blob lacks the 'feds' magic — refusing the splice")
    if len(blob) % 4:
        blob += bytes(4 - len(blob) % 4)
    delta = len(blob) - (end - start)
    if delta != 0:
        _repoint_texture(buf, header, start, delta)
    buf[start:end] = blob          # a bytearray slice-assign shifts the tail for us


def _repoint_texture(buf: bytearray, header: Dict[str, Any],
                     sound_def_ptr: int, delta: int) -> None:
    """The relocation half of a resized `sound_def`: add `delta` to `texture_ptr`,
    the only header pointer after the FEDS section.

    The stored pointers are relative to the header base — 0 for DATA-format
    effects, the MIPS prologue's length for the 107 CODE-format ones — while the
    parsed `header` hands us absolutes. `frames_ptr` is the header's own first
    field and is always 0x28, so it names the base exactly (verified against all
    401 extracted headers) with no scanning. That derived base is then CHECKED
    against the file: the stored `sound_def_ptr` / `texture_ptr` must resolve to
    the very section being moved, or we refuse rather than write a pointer into
    the middle of some other section."""
    if "frames_ptr" not in header:
        raise ValueError(
            "sound_def: a %+d-byte resize has to repoint texture_ptr, and this geometry "
            "carries no frames_ptr to derive the header base from" % delta)
    base = int(header["frames_ptr"]) - _HEADER_SIZE
    texture_ptr = int(header["texture_ptr"])
    if base < 0 or base + _HEADER_SIZE > len(buf):
        raise ValueError("sound_def: header base %d is outside the %d-byte file"
                         % (base, len(buf)))
    stored_sd = pe.read_u32(buf, base + _SOUND_DEF_PTR_OFF)
    stored_tx = pe.read_u32(buf, base + _TEXTURE_PTR_OFF)
    if base + stored_sd != sound_def_ptr or base + stored_tx != texture_ptr:
        raise ValueError(
            "sound_def: refusing a %+d-byte resize — the header at %d puts the section at "
            "[%d, %d) but the geometry says [%d, %d)"
            % (delta, base, base + stored_sd, base + stored_tx, sound_def_ptr, texture_ptr))
    struct.pack_into("<I", buf, base + _TEXTURE_PTR_OFF, stored_tx + delta)


@register("sound_containers")
def serialize_sound_containers(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Shared, effect-global TIER-2 SoundContainers (#289): 4 entries of 4 bytes
    [mode, id_a, id_b, id_c] at effect_flags_ptr + 8. These live INSIDE the header's
    Effect-Flags section (#272) but this serializer owns ONLY the 16 container bytes,
    so #272's own effect-flags serializer coexists over the disjoint bytes. Geometry =
    the header's `effect_flags_ptr`; the write is the byte-exact in-place core."""
    wecon.patch_containers_into(buf, block, header["effect_flags_ptr"])


@register("emitters")
def serialize_emitters(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Shared emitter parameters (ADR-0089): the 14 x 196-byte records after the
    particle-system header at `effect_data_ptr`. Partial patch at two grains —
    per dict key AND per byte: unparsed bytes (unknown_12/13, 0x4D/0x50-0x53,
    the 0x11 high nibble, reserved_C2/C3) are never written. The particle header
    itself (count/gravity) stays display-only."""
    wee.patch_emitters_into(buf, block, header["effect_data_ptr"])


@register("particle_timeline")
def serialize_particle_timeline(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Particle-timeline events (ADR-0089 particle_timeline amendment): the 15
    particle channels (5 for_each + 5 phase1 + 5 phase2) in the timeline section.
    Same geometry base as screen (the header's `timeline_section_ptr`); the write
    is the byte-exact in-place core, re-serializing each channel's raw SoA arrays
    (time / emitter_id / action_flags + max_keyframe). The shared byte-0x31 overlap
    is handled by write order (time before emitter_id)."""
    wpt.patch_particle_timeline_into(buf, block, header["timeline_section_ptr"])


@register("effect_flags")
def serialize_effect_flags(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Effect Flags byte (#272, ADR-0092): the single flags byte @0x00 of the
    effect_flags section. Geometry = the header's `effect_flags_ptr`; the write is
    the byte-exact in-place core. Only bits 3-6 are engine-read, but the WHOLE raw
    byte is written so the engine-ignored bits 0-2/7 ride along untouched. The dead
    0x04 override and the 16 sound-channel bytes @0x08-0x17 stay verbatim (the
    latter edit in their own container view)."""
    wef.patch_effect_flags_into(buf, block, header["effect_flags_ptr"])


@register("time_scale")
def serialize_time_scale(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Time-Scale pacing curves (#270, ADR-0093): the two 600-nibble regions
    (`outer_phases` @+0x000, `for_each` @+0x12C) at the header's `time_scale_ptr`.
    The write is the byte-exact in-place core, re-packing each 600-int curve into
    300 nibble bytes. The two enable bits live in the effect_flags byte and are
    edited via the `effect_flags` serializer, not here."""
    wts.patch_time_scale_into(buf, block, header["time_scale_ptr"])


@register("frames")
def serialize_frames(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Frames / Frameset section (#278): the flat frameset array (group 0's
    framesets first, etc. — SAME shape `parse_frames_section` returns). v1 scope
    is IN-PLACE FIELD EDITS ONLY (UV rect, vertices, palette_id, blend mode,
    semi_trans_on, is_8bpp) — no add/remove/reorder of frames, framesets, or
    frameset-group membership, so this writer never touches the group table,
    per-frameset offset table, header_flags, frame_count, or texture_page bytes;
    it locates each frame by walking that (untouched) structure. Geometry = the
    header's `frames_ptr`."""
    wef2.patch_frames_into(buf, block, header["frames_ptr"])


@register("animation")
def serialize_animation(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Animation / Sequence section (#275): the sequence array (SAME shape
    `parse_animations_section` returns). v1 scope is IN-PLACE PARAMETER EDITS
    ONLY (a FRAME's frameset/duration/depth_mode, SET_OFFSET's x/y, ADD_OFFSET's
    dx/dy) — no insert/delete/reorder of opcodes and no opcode TYPE changes,
    which would re-length the variable-size stream and desync the offset table.
    So this writer never touches the sequence count or the per-sequence offset
    table; it locates each opcode by walking that (untouched) structure.
    Geometry = the header's `animation_ptr`, bounded by `script_data_ptr` (the
    next section) — the only serializer here needing an explicit section SIZE,
    because a sequence's extent is defined by its neighbours, not by a record
    count."""
    ptr = int(header["animation_ptr"])
    wea.patch_animation_into(buf, block, ptr, int(header["script_data_ptr"]) - ptr)


@register("texture")
def serialize_texture(buf: bytearray, header: Dict[str, Any], block: Any) -> None:
    """Texture pixel plane (#280, ADR-0199): a pure section SPLICE of
    [texture_ptr + 0x404, EOF) — `block` is the re-quantized indexed plane and
    replaces those bytes verbatim, exactly as `serialize_sound_def` does for the
    feds blob. A length mismatch can only mean a resize (the deferred defrag
    path) or wrong geometry → refused.

    The CLUT is held FIXED, so the two 512-byte palettes at +0x000/+0x200 and
    the 4-byte VRAM header at +0x400 are never written by this serializer."""
    wetx.patch_texture_into(buf, block, header["texture_ptr"])
