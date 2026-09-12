"""
Shared SMD file-format constants and event type aliases.

The SMD (Sequenced Music Data) binary format is consumed by smd_parser
and produced by smd_writer. Both modules used to hard-code the header
field offsets (0x22, 0x08, 0x14, …) as bare hex — if one of them ever
changed, the other would silently produce broken files. This module is
the single source of truth for those offsets.

Event-type aliases expose the parser's existing `NoteEvent | OpcodeEvent`
union under the shorter name `SmdEvent`, and provide an `SmdTrack`
dataclass that higher-level code (e.g. round-trip tests) can use to
carry parsed tracks around without leaking parser internals.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Final, List

from .opcodes import Event, NoteEvent, OpcodeEvent

# ---------------------------------------------------------------------------
# File magic
# ---------------------------------------------------------------------------

SMD_MAGIC: Final[bytes] = b"smds"
WAVESET_MAGIC: Final[bytes] = b"dwds"


# ---------------------------------------------------------------------------
# SMD header layout
# ---------------------------------------------------------------------------
# The SMD header is a fixed 0x22 bytes, followed by a variable-length
# table of track pointers. Every named offset below corresponds to a
# single field in the header struct.

SMD_HEADER_SIZE: Final[int] = 0x22

# Offsets within the header
SMD_OFFSET_MAGIC: Final[int] = 0x00           # 4 bytes, 'smds'
SMD_OFFSET_BUILD_ID: Final[int] = 0x04        # 4 bytes, unique per file (build hash/CRC?); not validated by game
SMD_OFFSET_FILE_SIZE: Final[int] = 0x08       # uint16 LE; not read by game-side song-init (FUN_800136C0)
SMD_OFFSET_FLAGS: Final[int] = 0x10           # uint16 LE; read by FUN_800136C0 → entity+0x12, always 0x0000 in vanilla
SMD_OFFSET_FMT_VERSION_HI: Final[int] = 0x12  # uint8; read separately, always 0x02 in vanilla (possible major version)
SMD_OFFSET_FMT_VERSION_LO: Final[int] = 0x13  # uint8; read separately, always 0x01 in vanilla (possible minor version)
SMD_OFFSET_TRACK_COUNT: Final[int] = 0x14     # uint8
SMD_OFFSET_DRUM_COUNT: Final[int] = 0x15      # uint8
SMD_OFFSET_WDS_ID: Final[int] = 0x16          # uint16 LE; always 0 in vanilla (WAVESET selected elsewhere)
SMD_OFFSET_INITIAL_VOLUME: Final[int] = 0x18  # uint8; read as part of u16 with byte 0x19
SMD_OFFSET_UNK_19: Final[int] = 0x19          # uint8; always 0 in vanilla (high byte of vol u16)
SMD_OFFSET_INIT_MODE: Final[int] = 0x1A       # uint8 (signed); always 0x04 in vanilla — mode discriminator for FUN_80018140, NOT tempo
SMD_OFFSET_INITIAL_TEMPO: Final[int] = 0x1B   # uint8; THIS TOOL's tempo byte, not FFT's. See below.
# FFT reads NO tempo from the SMD header (#619). The tempo state is the channel
# triple +0x7C / +0x78 / +0x8A, and the init at 0x8001386C-0x80013888 writes it as
# literals for the constant 102 -- every retail song then issues opcode 0xA0
# (smd_tempo @ 0x80015CB0) before its first note. A complete scan of every sb/sh/sw
# to those offsets in 0x80013000-0x80019000 finds no header byte reaching them.
# 0x1B itself is read once, <<8, into global 0x8003704C, whose only reader writes an
# (a1+0, a1+2) halfword pair with conditional negation -- a stereo shape, suggestive
# of volume, not a scalar tempo.
#
# The old comment here -- "the REAL tempo byte ... Verified at ram:80013740" -- cited
# a verification the ROM does not support. The OFFSET stays: this package is an
# authoring tool, smd_writer.py:351 writes its own tempo here and smd_parser.py reads
# it back, and that round-trip is a real feature. FFT simply ignores the byte, which
# is why writing it is harmless. Same call, same reason, as fft-plugin (0a173acf2).
SMD_OFFSET_SONG_TITLE_PTR: Final[int] = 0x1E  # uint16 LE
SMD_OFFSET_DRUMKIT_PTR: Final[int] = 0x20     # uint16 LE
SMD_OFFSET_TRACK_TABLE: Final[int] = 0x22     # start of track_count × uint16 LE

# Size of each track-table entry.
SMD_TRACK_PTR_SIZE: Final[int] = 2


def smd_header_size(track_count: int) -> int:
    """Total size of header + track pointer table for a given track count."""
    return SMD_HEADER_SIZE + track_count * SMD_TRACK_PTR_SIZE


# ---------------------------------------------------------------------------
# Event type aliases
# ---------------------------------------------------------------------------

# Short name for the existing parser-produced event union. Callers that
# want a concrete type for tracks should use this instead of reaching
# into opcodes.py.
SmdEvent = Event


@dataclass
class SmdTrack:
    """
    A parsed SMD track: a flat list of events in order. Used as a
    transport type between parser and writer once Phase 6/4 unification
    is complete. For now, `smd_parser.SmdsFile.track_events` still holds
    the primary representation; this dataclass is used for future
    round-trip tests.
    """

    events: List[SmdEvent] = field(default_factory=list)
