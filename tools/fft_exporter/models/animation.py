"""Animation data models."""

from dataclasses import dataclass
from enum import Enum


class UvAnimationMode(Enum):
    """UV animation mode enum - names match C# for JSON serialization."""
    Disabled = 0
    ForwardLooping = 1
    ForwardAndReverseLooping = 2
    ForwardOnceOnTrigger = 5
    ReverseOnceOnTrigger = 21
    Unknown = 255


class PaletteAnimationMode(Enum):
    """Palette animation mode enum - names match C# for JSON serialization."""
    ForwardLoopingOnTrigger = 0
    ForwardLooping = 3
    ForwardAndReverseLooping = 4
    ForwardOnceOnTrigger = 13
    Unknown = 255


@dataclass
class UvAnimation:
    """UV animation data."""
    canvas_x: int = 0
    canvas_y: int = 0
    canvas_texture_page: int = 0
    size_width: int = 0
    size_height: int = 0
    first_frame_x: int = 0
    first_frame_y: int = 0
    first_frame_texture_page: int = 0
    frame_count: int = 0
    frame_duration: int = 0
    animation_mode: UvAnimationMode = UvAnimationMode.Disabled


@dataclass
class PaletteAnimation:
    """Palette animation data."""
    overridden_palette_id: int = 0
    animation_start_index: int = 0
    frame_count: int = 0
    frame_duration: int = 0
    animation_mode: PaletteAnimationMode = PaletteAnimationMode.ForwardLooping
