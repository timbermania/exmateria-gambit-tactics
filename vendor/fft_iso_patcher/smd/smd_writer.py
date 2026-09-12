#!/usr/bin/env python3
"""
smd_writer.py — Encode structured track data into FFT SMD binary format.

The SMD format is FFT's sequenced music data, played by the PSX sound driver
against WAVESET.WD instrument samples. This module produces valid SMD binaries
that can be injected into the game ISO to replace MUSIC_XX.SMD files.

Binary layout (verified against FFT SCUS ram:800136c0–ram:80013764):
    0x00-0x03: magic "smds"
    0x04-0x07: build ID / hash (4 bytes; unique per file in vanilla; not validated by game)
    0x08-0x09: file size (LE uint16)
    0x0A-0x0F: unused (always 0 in vanilla)
    0x10-0x11: flags (LE uint16; always 0x0000 in vanilla; read by FUN_800136C0)
    0x12: format version high (always 0x02 in vanilla)
    0x13: format version low  (always 0x01 in vanilla)
    0x14: track count (uint8)
    0x15: drum count (uint8)
    0x16-0x17: associated WDS ID (LE uint16; always 0 in vanilla)
    0x18: initial volume (uint8)
    0x19: unknown (always 0; read as high byte of u16 with 0x18)
    0x1A: init mode discriminator (always 0x04 in vanilla; passed as a0 to FUN_80018140 — NOT tempo)
    0x1B: initial tempo byte (BPM = val * 256 / 218; loaded, <<8, passed as a1 to FUN_80018140)
    0x1C-0x1D: padding (always 0; passed as a2/a3 to FUN_80018140)
    0x1E-0x1F: song title pointer (LE uint16)
    0x20-0x21: drumkit pointer (LE uint16)
    0x22+: track offset table (track_count × LE uint16)
    ...: song title (null-terminated ASCII)
    ...: track data (conductor + instrument tracks)

Usage:
    from tools.sound_synth.smd_writer import SmdBuilder

    builder = SmdBuilder(title="my_song", tempo_bpm=120)
    builder.add_instrument_track(
        instrument=70, octave=4, dynamics=80, pan=64,
        notes=[(60, 48, 64), (62, 48, 64), ...]  # (midi_note, duration_ticks, velocity)
    )
    smd_bytes = builder.build()
"""

import struct
from typing import List, Tuple, Optional
from dataclasses import dataclass, field

from .opcodes import DELTA_TIME_TABLE, Opcode
from .smd_events import (
    SMD_MAGIC,
    SMD_HEADER_SIZE,
    SMD_OFFSET_FILE_SIZE,
    SMD_OFFSET_FLAGS,
    SMD_OFFSET_FMT_VERSION_HI,
    SMD_OFFSET_FMT_VERSION_LO,
    SMD_OFFSET_TRACK_COUNT,
    SMD_OFFSET_DRUM_COUNT,
    SMD_OFFSET_WDS_ID,
    SMD_OFFSET_INITIAL_VOLUME,
    SMD_OFFSET_INIT_MODE,
    SMD_OFFSET_INITIAL_TEMPO,
    SMD_OFFSET_SONG_TITLE_PTR,
    SMD_OFFSET_DRUMKIT_PTR,
    smd_header_size,
)


def _bpm_to_tempo_byte(bpm: float) -> int:
    """Convert BPM to FFT tempo byte. Inverse of (val * 256) / 218."""
    val = int(bpm * 218 / 256 + 0.5)
    return max(1, min(255, val))


def _encode_delta_time(ticks: int) -> bytes:
    """Encode a tick duration into SMD delta format.

    Returns the delta_index byte (0-18) that maps to the duration,
    or 0 (custom) followed by the raw tick value.
    """
    # Check if ticks matches a table entry
    for idx, table_val in enumerate(DELTA_TIME_TABLE):
        if idx == 0:
            continue  # index 0 = custom
        if table_val == ticks:
            return idx
    # Custom duration: index 0, followed by tick value byte
    if ticks <= 255:
        return 0  # caller must append the tick byte
    return 0  # clamp to 255


@dataclass
class InstrumentChange:
    """Mid-track instrument change event."""
    instrument: int         # SMD instrument param


@dataclass
class NoteData:
    """A note to encode into SMD."""
    midi_note: int          # Absolute MIDI note (0-127)
    duration_ticks: int     # Duration in SMD ticks (PPQ=48)
    velocity: int = 64      # 0-127


@dataclass
class TrackData:
    """Data for a single SMD track."""
    # Preamble settings
    instrument: int = 0     # SMD instrument param (maps to WAVESET entry+1)
    octave: int = 4
    dynamics: int = 80      # 0-127
    pan: int = 64           # 0=left, 64=center, 127=right
    reverb: bool = True
    loop: bool = True       # emit Opcode.LOOP so engine restarts at END_BAR

    # Notes: list of (NoteData | rest_ticks)
    # A positive int = rest in ticks, NoteData = a note event
    events: list = field(default_factory=list)


class SmdBuilder:
    """Build an SMD binary from structured track data."""

    def __init__(self, title: str = "custom", tempo_bpm: float = 120.0,
                 time_sig: Tuple[int, int] = (4, 4)):
        self.title = title[:15]  # max ~15 chars
        self.tempo_bpm = tempo_bpm
        self.time_sig = time_sig
        self.tracks: List[TrackData] = []

    def add_track(self, track: TrackData):
        """Add an instrument track."""
        self.tracks.append(track)

    def add_simple_track(self, instrument: int, octave: int, dynamics: int,
                         pan: int, notes: List[Tuple[int, int, int]],
                         rests_between: Optional[List[int]] = None,
                         reverb: bool = True):
        """Add a track with a simple note sequence.

        Args:
            instrument: SMD instrument param (WAVESET entry = param + 1)
            octave: Starting octave (0-9)
            dynamics: Volume (0-127)
            pan: Pan (0=left, 64=center, 127=right)
            notes: List of (midi_note, duration_ticks, velocity)
            rests_between: Optional list of rest durations between notes
            reverb: Enable reverb
        """
        track = TrackData(
            instrument=instrument,
            octave=octave,
            dynamics=dynamics,
            pan=pan,
            reverb=reverb,
        )

        for i, (midi, dur, vel) in enumerate(notes):
            track.events.append(NoteData(midi, dur, vel))
            if rests_between and i < len(rests_between):
                rest = rests_between[i]
                if rest > 0:
                    track.events.append(rest)  # int = rest ticks

        self.tracks.append(track)

    def _encode_conductor(self) -> bytes:
        """Encode the conductor track (Track 0)."""
        out = bytearray()

        # Preamble
        out.append(Opcode.REVERB_ON)
        out.append(Opcode.TEMPO)
        out.append(_bpm_to_tempo_byte(self.tempo_bpm))
        out.append(Opcode.TIME_SIGNATURE)
        out.append(self.time_sig[0])
        out.append(self.time_sig[1])

        # Repeat(16) for looping
        out.append(Opcode.REPEAT)
        out.append(16)

        # Rest for one measure (time_sig[0] beats × PPQ ticks)
        measure_ticks = self.time_sig[0] * 48
        out.append(Opcode.REST)
        out.append(min(255, measure_ticks))

        out.append(Opcode.CODA)
        out.append(Opcode.END_BAR)

        return bytes(out)

    def _encode_note(self, note: NoteData, current_octave: int) -> Tuple[bytes, int]:
        """Encode a single note event. Returns (bytes, new_octave)."""
        out = bytearray()

        # Determine octave and relative key
        target_octave = note.midi_note // 12
        relative_key = note.midi_note % 12

        # Emit octave changes
        new_octave = current_octave
        if target_octave != current_octave:
            diff = target_octave - current_octave
            if abs(diff) == 1:
                if diff > 0:
                    out.append(Opcode.RAISE_OCTAVE)
                else:
                    out.append(Opcode.LOWER_OCTAVE)
            else:
                out.append(Opcode.OCTAVE)
                out.append(target_octave)
            new_octave = target_octave

        # Find best delta_time encoding
        dur = note.duration_ticks
        delta_index = None
        for idx in range(1, len(DELTA_TIME_TABLE)):
            if DELTA_TIME_TABLE[idx] == dur:
                delta_index = idx
                break

        # Encode: velocity byte, data byte (key * 19 + delta_index)
        vel = max(1, min(127, note.velocity))  # velocity 0 is reserved

        if delta_index is not None:
            data_byte = relative_key * 19 + delta_index
        else:
            # Custom duration: delta_index = 0
            data_byte = relative_key * 19 + 0

        out.append(vel)
        out.append(data_byte)

        # If custom duration, append the tick value
        if delta_index is None:
            out.append(min(255, dur))

        return bytes(out), new_octave

    def _encode_rest(self, ticks: int) -> bytes:
        """Encode a Rest opcode, splitting into 255-tick chunks if needed."""
        out = bytearray()
        remaining = ticks
        while remaining > 0:
            chunk = min(255, remaining)
            out.append(Opcode.REST)
            out.append(chunk)
            remaining -= chunk
        return bytes(out)

    def _encode_track(self, track: TrackData) -> bytes:
        """Encode a single instrument track."""
        out = bytearray()

        # Preamble
        if track.reverb:
            out.append(Opcode.REVERB_ON)

        if track.loop:
            out.append(Opcode.LOOP)  # infinite loop marker

        out.append(Opcode.DYNAMICS)
        out.append(track.dynamics)

        out.append(Opcode.PAN)
        out.append(track.pan)

        out.append(Opcode.INSTRUMENT)
        out.append(track.instrument)

        out.append(Opcode.OCTAVE)
        out.append(track.octave)

        # Encode events
        current_octave = track.octave
        for event in track.events:
            if isinstance(event, NoteData):
                note_bytes, current_octave = self._encode_note(event, current_octave)
                out.extend(note_bytes)
            elif isinstance(event, InstrumentChange):
                out.append(Opcode.INSTRUMENT)
                out.append(event.instrument & 0xFF)
            elif isinstance(event, int):
                # Rest
                out.extend(self._encode_rest(event))

        # End track: Instrument(255) = mute, then EndBar
        out.append(Opcode.INSTRUMENT)
        out.append(0xFF)
        out.append(Opcode.END_BAR)

        return bytes(out)

    def build(self) -> bytes:
        """Build the complete SMD binary."""
        track_count = 1 + len(self.tracks)  # conductor + instruments

        # Encode all tracks
        conductor_data = self._encode_conductor()
        track_datas = [self._encode_track(t) for t in self.tracks]
        all_tracks = [conductor_data] + track_datas

        # Layout: fixed header, then track pointer table, then title, then tracks.
        title_bytes = self.title.encode('ascii') + b'\x00'
        header_size = smd_header_size(track_count)

        title_offset = header_size
        data_start = title_offset + len(title_bytes)

        # Pad to even boundary
        if data_start % 2 != 0:
            title_bytes += b'\x00'
            data_start += 1

        # Track offsets (from file start)
        track_offsets = []
        pos = data_start
        for td in all_tracks:
            track_offsets.append(pos)
            pos += len(td)

        file_size = pos

        # Build header — match vanilla MUSIC_NN.SMD layout verified against
        # FFT SCUS disasm (ram:800136c0–ram:80013764). See
        # research/working_documents/SMD_HEADER_GROUND_TRUTH.md.
        header = bytearray(SMD_HEADER_SIZE)
        header[0:4] = SMD_MAGIC
        header[4:8] = b'\x00\x00\x00\x00'  # build ID; not validated by game
        struct.pack_into('<H', header, SMD_OFFSET_FILE_SIZE, file_size)
        # 0x0A-0x0F: zeros (vanilla pattern)
        # flags: 0x0000 in vanilla (was previously hardcoded 0x0002 here — wrong)
        struct.pack_into('<H', header, SMD_OFFSET_FLAGS, 0x0000)
        header[SMD_OFFSET_FMT_VERSION_HI] = 0x02   # always 02 in vanilla
        header[SMD_OFFSET_FMT_VERSION_LO] = 0x01   # always 01 in vanilla
        header[SMD_OFFSET_TRACK_COUNT] = track_count
        header[SMD_OFFSET_DRUM_COUNT] = 0
        struct.pack_into('<H', header, SMD_OFFSET_WDS_ID, 0)
        header[SMD_OFFSET_INITIAL_VOLUME] = 70
        header[0x19] = 0                            # always 0
        # 0x1A = INIT_MODE discriminator (always 0x04 in vanilla; passed as
        # mode arg to FUN_80018140). NOT tempo — previous writer mistakenly
        # wrote the tempo byte here.
        header[SMD_OFFSET_INIT_MODE] = 0x04
        # 0x1B = the real initial tempo byte. The game does
        # `lbu v0,0x1b(v1); sll v0,v0,8; sh v0,0x48(s0)` at ram:80013740
        # and passes the Q8.8 value as the tempo arg to FUN_80018140.
        # (In practice every conductor track sets a Tempo opcode within 1-2
        # events, so this initial value is only audible for sub-millisecond
        # ramp-in.)
        header[SMD_OFFSET_INITIAL_TEMPO] = _bpm_to_tempo_byte(self.tempo_bpm)
        # 0x1C-0x1D: zeros (passed as a2/a3 to FUN_80018140; always 0 in vanilla)
        struct.pack_into('<H', header, SMD_OFFSET_SONG_TITLE_PTR, title_offset)
        # drumkit ptr points at the conductor track (drum kit data lives there)
        struct.pack_into('<H', header, SMD_OFFSET_DRUMKIT_PTR, track_offsets[0])

        # Track offset table (uint16 LE per track)
        offset_table = bytearray(track_count * 2)
        for i, off in enumerate(track_offsets):
            struct.pack_into('<H', offset_table, i * 2, off)

        # Assemble
        result = bytes(header) + bytes(offset_table) + title_bytes
        for td in all_tracks:
            result += td

        return result


def main():
    """Test: build a simple SMD and render it."""
    import sys
    from pathlib import Path

    builder = SmdBuilder(title="test_song", tempo_bpm=120)

    # Simple melody: C major scale
    notes = [
        (60, 48, 64),  # C4, quarter note
        (62, 48, 64),  # D4
        (64, 48, 64),  # E4
        (65, 48, 64),  # F4
        (67, 48, 64),  # G4
        (69, 48, 64),  # A4
        (71, 48, 64),  # B4
        (72, 96, 64),  # C5, half note
    ]

    # Use FFT instrument 70 (a piano-like sound)
    builder.add_simple_track(
        instrument=70, octave=4, dynamics=80, pan=64,
        notes=notes,
        rests_between=[0, 0, 0, 0, 0, 0, 0, 48],  # rest after last note
    )

    smd_bytes = builder.build()

    from .config import OUTPUT_DIR
    out_path = OUTPUT_DIR / "test_song.smd"
    out_path.write_bytes(smd_bytes)
    print(f"Wrote {len(smd_bytes)} bytes to {out_path}")

    # Verify it parses correctly
    from .smd_parser import parse_smds_file, print_smds_info
    smd = parse_smds_file(smd_bytes)
    print_smds_info(smd, "test_song.smd")


if __name__ == "__main__":
    main()
