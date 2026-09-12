"""System-B mesh-animation data models (moving map geometry).

These mirror GaneshaDx `ContentDataTypes/MeshAnimations/*`. The `0x8C`
mesh-resource chunk decodes into a :class:`MeshAnimationSet`: 128 keyframes,
64 instruction sets (8 playing-state banks x 8 mesh slots), and 64
mesh-property records. Pure data, no I/O — the parser builds these and the
exporter serialises them.

System B is "moving geometry" — swinging castle gates, the Unstoppable Cog,
Goug machinery — distinct from System A texture-animation (scrolling/flipbook
textures on a static mesh). See
`research/working_documents/map_animation/map_animation_systems.md`.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Tuple


class MeshAnimationTweenType(Enum):
    """Per-axis interpolation type for a keyframe target.

    Values are the raw bytes stored in keyframe properties p30..p38. Names
    match GaneshaDx. ``Unk9``/``Unk17`` are not yet understood; they are
    preserved verbatim, not interpreted (see #130 Out of Scope).
    """
    Invalid = 0
    TweenTo = 5
    TweenBy = 6
    Unk9 = 9
    Oscillate = 10
    Unk17 = 17
    OscillateOffset = 18


@dataclass
class MeshAnimationKeyframe:
    """One 80-byte keyframe = 40 signed int16 "properties".

    The decoded fields are the ones GaneshaDx exposes
    (``MeshAnimationKeyframe.cs``). ``props`` keeps the raw 40 int16 so the
    decode is round-trippable and verifiable. Rotation is degrees, position is
    raw FFT units, scale is a multiplier; the per-axis start/end percents and
    tween types describe how the animation interpolates toward this keyframe.
    """
    props: List[int] = field(default_factory=list)  # 40 signed int16
    rotation: Tuple[float, float, float] = (0.0, 0.0, 0.0)   # degrees
    position: Tuple[float, float, float] = (0.0, 0.0, 0.0)   # raw FFT units
    scale: Tuple[float, float, float] = (0.0, 0.0, 0.0)      # multiplier
    rot_start_pct: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    pos_start_pct: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    scale_start_pct: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    rot_end_pct: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    pos_end_pct: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    scale_end_pct: Tuple[float, float, float] = (0.0, 0.0, 0.0)
    rot_tween: Tuple[int, int, int] = (0, 0, 0)
    pos_tween: Tuple[int, int, int] = (0, 0, 0)
    scale_tween: Tuple[int, int, int] = (0, 0, 0)

    @property
    def is_empty(self) -> bool:
        """True if every raw property is zero (an unused keyframe slot)."""
        return all(v == 0 for v in self.props)


@dataclass
class AnimatedMeshInstruction:
    """One 4-byte instruction in an instruction set's state machine."""
    frame_state_id: int = 0   # 1-based keyframe ref; 0 = terminal
    next_frame_id: int = 0    # jump target (instruction step) after this one
    duration: int = 0         # int16 ticks; /60 = seconds


@dataclass
class AnimatedMeshInstructionSet:
    """One 64-byte instruction set = 16 instructions for a single mesh slot."""
    instructions: List[AnimatedMeshInstruction] = field(default_factory=list)

    @property
    def is_active(self) -> bool:
        """A set is "live" iff its first instruction's FrameStateId > 0
        (GaneshaDx ``MeshAnimationController.cs:55``)."""
        return bool(self.instructions) and self.instructions[0].frame_state_id > 0


@dataclass
class AnimatedMeshProperties:
    """One 4-byte mesh-property record (parallel to the instruction sets)."""
    linked_parent: int = 0   # parent another animated mesh (0 = none)
    unk1: int = 0
    unk2: int = 0
    unk3: int = 0


@dataclass
class MeshAnimationSet:
    """The full decoded `0x8C` chunk (fixed 14620 bytes on disc).

    All 128 keyframes, 64 instruction sets, and 64 property records are kept,
    index-stable, so a runtime can address them by the
    ``(meshType-1) + playingState*8`` formula. The three header byte-lists and
    the 4-byte trailer are preserved for sanity-checking/round-trip.
    """
    keyframes_header: List[int] = field(default_factory=list)          # 8 bytes
    instruction_sets_header: List[int] = field(default_factory=list)   # 8 bytes
    properties_header: List[int] = field(default_factory=list)         # 8 bytes
    keyframes: List[MeshAnimationKeyframe] = field(default_factory=list)        # 128
    instruction_sets: List[AnimatedMeshInstructionSet] = field(default_factory=list)  # 64
    properties: List[AnimatedMeshProperties] = field(default_factory=list)     # 64
    trailing: List[int] = field(default_factory=list)                  # 4 bytes

    def active_set_indices(self) -> List[int]:
        """Indices of the instruction sets whose first instruction is live."""
        return [i for i, s in enumerate(self.instruction_sets) if s.is_active]
