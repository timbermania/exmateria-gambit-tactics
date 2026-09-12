"""Animation parsing from mesh resource data."""

from typing import List, Optional, Tuple

from ..models.animation import (
    UvAnimation,
    UvAnimationMode,
    PaletteAnimation,
    PaletteAnimationMode,
)
from ..utils.binary import read_int32_le


# Animation pointers in mesh resource header
TEXTURE_ANIMATIONS_POINTER = 108


def parse_texture_animations(data: bytes) -> Tuple[List[UvAnimation], List[PaletteAnimation]]:
    """Parse texture animations from mesh resource.

    There are 32 animation instruction slots (20 bytes each).
    Each can be either UV animation or palette animation based on content.

    Args:
        data: Raw mesh resource data

    Returns:
        Tuple of (uv_animations, palette_animations)
    """
    # Read animations pointer
    pointer = read_int32_le(data, TEXTURE_ANIMATIONS_POINTER)

    if pointer == 0:
        return [], []

    uv_animations = []
    palette_animations = []
    offset = pointer

    # 32 animation instruction slots
    for _ in range(32):
        raw_data = data[offset:offset + 20]
        offset += 20

        # Determine animation type based on byte 14 (mode)
        # UV: 0,1,2,5,6,7,8,21,23,24
        # Palette: 3,4,13
        mode_byte = raw_data[14]

        if mode_byte in [3, 4, 13, 0] and raw_data[2] == 224:
            # Palette animation (byte 2 == 224 is a strong indicator)
            anim = _parse_palette_animation(raw_data)
            if anim and anim.frame_count > 0:
                palette_animations.append(anim)
        elif mode_byte in [1, 2, 5, 6, 7, 8, 21, 23, 24]:
            # UV animation
            anim = _parse_uv_animation(raw_data)
            if anim and anim.frame_count > 0:
                uv_animations.append(anim)
        # mode 0 with byte 2 != 224 is disabled

    return uv_animations, palette_animations


def parse_texture_animation_slots(data: bytes) -> List[dict]:
    """Parse the 32 texture-animation instruction slots, preserving slot index.

    Unlike :func:`parse_texture_animations` (which splits the table into two
    filtered lists and discards which physical slot each came from), this keeps
    the table as an ordered, index-stable list of all 32 slots. The slot index
    IS the event-script "Field Object ID" — `{55} Use Field Object ID=N` plays
    slot N. The PSX runtime mirrors this exactly: descriptor table `0x80121d7c`,
    stride 0x14, indexed by ID (live-validated: chapel slot 1 == the descriptor
    read out of RAM for ID=1). See
    `research/working_documents/scenario_1_captures/use_field_object_decode.md`.

    Each returned dict carries the decoded UV/palette fields the renderer needs,
    plus `mode_byte` and the raw hex (for byte-exact verification against the
    live oracle).

    Returns a list of 32 dicts (empty list only if the section pointer is null).
    """
    pointer = read_int32_le(data, TEXTURE_ANIMATIONS_POINTER)
    if pointer == 0:
        return []

    slots: List[dict] = []
    offset = pointer
    for slot_index in range(32):
        raw_data = data[offset:offset + 20]
        offset += 20
        slots.append(_slot_to_dict(slot_index, raw_data))

    return slots


def _slot_to_dict(slot_index: int, raw_data: bytes) -> dict:
    """Classify a 20-byte slot and decode it into a self-describing dict."""
    base = {
        "slot_index": slot_index,
        "raw": raw_data.hex(),
        "mode_byte": raw_data[14] if len(raw_data) >= 15 else 0,
    }

    if len(raw_data) < 20 or not any(raw_data):
        base["kind"] = "empty"
        return base

    mode_byte = raw_data[14]

    # Palette animation (byte 2 == 224 is the strong indicator, mirrors
    # parse_texture_animations classification).
    if mode_byte in (3, 4, 13, 0) and raw_data[2] == 224:
        anim = _parse_palette_animation(raw_data)
        if anim and anim.frame_count > 0:
            base.update({
                "kind": "palette",
                "animation_mode": anim.animation_mode.name.replace('_', ''),
                "overridden_palette_id": anim.overridden_palette_id,
                "animation_start_index": anim.animation_start_index,
                "frame_count": anim.frame_count,
                "frame_duration": anim.frame_duration,
            })
            return base

    # UV animation.
    if mode_byte in (1, 2, 5, 6, 7, 8, 21, 23, 24):
        anim = _parse_uv_animation(raw_data)
        if anim and anim.frame_count > 0:
            base.update({
                "kind": "uv",
                "animation_mode": anim.animation_mode.name.replace('_', ''),
                "canvas_x": anim.canvas_x,
                "canvas_y": anim.canvas_y,
                "canvas_texture_page": anim.canvas_texture_page,
                "size_width": anim.size_width,
                "size_height": anim.size_height,
                "first_frame_x": anim.first_frame_x,
                "first_frame_y": anim.first_frame_y,
                "first_frame_texture_page": anim.first_frame_texture_page,
                "frame_count": anim.frame_count,
                "frame_duration": anim.frame_duration,
            })
            return base

    base["kind"] = "disabled"
    return base


def _parse_uv_animation(raw_data: bytes) -> Optional[UvAnimation]:
    """Parse a UV animation from 20 bytes of instruction data."""
    # Parse coordinates (multiply by 4 for actual pixel values)
    canvas_x = raw_data[0] * 4
    canvas_y = raw_data[2]
    size_width = raw_data[4] * 4
    size_height = raw_data[6]
    first_frame_x = raw_data[8] * 4
    first_frame_y = raw_data[10]

    # Calculate texture pages
    canvas_texture_page = 0
    while canvas_x >= 256:
        canvas_x -= 256
        canvas_texture_page += 1

    first_frame_texture_page = 0
    while first_frame_x >= 256:
        first_frame_x -= 256
        first_frame_texture_page += 1

    # Parse mode
    mode_byte = raw_data[14]
    mode = {
        0: UvAnimationMode.Disabled,
        1: UvAnimationMode.ForwardLooping,
        2: UvAnimationMode.ForwardAndReverseLooping,
        5: UvAnimationMode.ForwardOnceOnTrigger,
        6: UvAnimationMode.ForwardOnceOnTrigger,
        7: UvAnimationMode.ForwardOnceOnTrigger,
        8: UvAnimationMode.ForwardOnceOnTrigger,
        21: UvAnimationMode.ReverseOnceOnTrigger,
        23: UvAnimationMode.ReverseOnceOnTrigger,
        24: UvAnimationMode.ReverseOnceOnTrigger,
    }.get(mode_byte, UvAnimationMode.Unknown)

    frame_count = raw_data[15]
    frame_duration = raw_data[17]

    return UvAnimation(
        canvas_x=canvas_x,
        canvas_y=canvas_y,
        canvas_texture_page=canvas_texture_page,
        size_width=size_width,
        size_height=size_height,
        first_frame_x=first_frame_x,
        first_frame_y=first_frame_y,
        first_frame_texture_page=first_frame_texture_page,
        frame_count=frame_count,
        frame_duration=frame_duration,
        animation_mode=mode,
    )


def _parse_palette_animation(raw_data: bytes) -> Optional[PaletteAnimation]:
    """Parse a palette animation from 20 bytes of instruction data."""
    # Byte 0: upper 4 bits = palette ID, lower 4 bits = unknown
    byte0 = raw_data[0]
    overridden_palette_id = (byte0 >> 4) & 0x0F

    animation_start_index = raw_data[8]

    # Parse mode
    mode_byte = raw_data[14]
    mode = {
        0: PaletteAnimationMode.ForwardLoopingOnTrigger,
        3: PaletteAnimationMode.ForwardLooping,
        4: PaletteAnimationMode.ForwardAndReverseLooping,
        13: PaletteAnimationMode.ForwardOnceOnTrigger,
    }.get(mode_byte, PaletteAnimationMode.Unknown)

    frame_count = raw_data[15]
    frame_duration = raw_data[17]

    return PaletteAnimation(
        overridden_palette_id=overridden_palette_id,
        animation_start_index=animation_start_index,
        frame_count=frame_count,
        frame_duration=frame_duration,
        animation_mode=mode,
    )
