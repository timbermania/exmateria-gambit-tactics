#!/usr/bin/env python3
"""
smd_parser.py - Parse FFT MUSIC_##.SMD files

SMD (Sequenced Music Data) files use the same opcode encoding as feds
effect sounds. This parser reads the smds container header, extracts
track data pointers, and decodes each track's opcode stream.

Usage:
    python3 -m tools.sound_synth.smd_parser MUSIC_22.SMD
    python3 -m tools.sound_synth.smd_parser /path/to/SOUND/ --batch
    python3 -m tools.sound_synth.smd_parser MUSIC_00.SMD --track 0
"""

import argparse
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import List, Optional

from .opcodes import (
    OPCODE_INFO, DELTA_TIME_TABLE, PPQ, Event, NoteEvent, OpcodeEvent,
    decode_track, fft_tempo_to_bpm
)
from .smd_events import (
    SMD_MAGIC,
    SMD_HEADER_SIZE,
    SMD_OFFSET_FILE_SIZE,
    SMD_OFFSET_TRACK_COUNT,
    SMD_OFFSET_DRUM_COUNT,
    SMD_OFFSET_WDS_ID,
    SMD_OFFSET_INITIAL_VOLUME,
    SMD_OFFSET_UNK_19,
    SMD_OFFSET_INITIAL_TEMPO,
    SMD_OFFSET_SONG_TITLE_PTR,
    SMD_OFFSET_DRUMKIT_PTR,
    SMD_OFFSET_TRACK_TABLE,
    SMD_TRACK_PTR_SIZE,
)


@dataclass
class SmdsHeader:
    """Parsed smds file header"""
    magic: bytes                    # 'smds' (4 bytes)
    unknown_04: bytes               # 4 bytes at 0x04 (possibly checksum)
    file_size: int                  # uint16 LE at 0x08
    track_count: int                # uint8 at 0x14
    drum_count: int                 # uint8 at 0x15
    assoc_wds_id: int               # uint16 at 0x16
    initial_volume: int             # uint8 at 0x18
    unknown_19: int                 # uint8 at 0x19
    initial_tempo: int              # uint8 at 0x1B — THIS TOOL's convention; FFT reads no
                                    # header tempo at all (#619, SMD_OFFSET_INITIAL_TEMPO)
    song_title_ptr: int             # uint16 LE at 0x1E
    drumkit_ptr: int                # uint16 LE at 0x20
    track_ptrs: List[int] = field(default_factory=list)  # uint16 LE array at 0x22

    @property
    def initial_bpm(self) -> float:
        """BPM this tool would write for `initial_tempo`.

        NOT what FFT will play. FFT seeds tempo from a constant 102 and takes
        every subsequent change from opcode 0xA0, so it never reads this byte
        (#619). Meaningful for round-tripping a file this package authored;
        misleading if read as a fact about playback.
        """
        return fft_tempo_to_bpm(self.initial_tempo)


@dataclass
class SmdsFile:
    """A fully parsed SMD file"""
    header: SmdsHeader
    song_title: str
    tracks: List[bytes]             # Raw byte data for each track
    track_events: List[List[Event]] # Decoded events for each track

    @property
    def track_count(self) -> int:
        return self.header.track_count


def parse_smds_header(data: bytes) -> SmdsHeader:
    """Parse the smds container header."""
    if len(data) < SMD_HEADER_SIZE:
        raise ValueError(f"File too small for smds header ({len(data)} bytes)")

    magic = data[0:4]
    if magic != SMD_MAGIC:
        raise ValueError(f"Invalid magic: expected 'smds', got {magic!r}")

    unknown_04 = data[0x04:0x08]
    file_size = struct.unpack_from('<H', data, SMD_OFFSET_FILE_SIZE)[0]
    track_count = data[SMD_OFFSET_TRACK_COUNT]
    drum_count = data[SMD_OFFSET_DRUM_COUNT]
    assoc_wds_id = struct.unpack_from('<H', data, SMD_OFFSET_WDS_ID)[0]
    initial_volume = data[SMD_OFFSET_INITIAL_VOLUME]
    unknown_19 = data[SMD_OFFSET_UNK_19]
    initial_tempo = data[SMD_OFFSET_INITIAL_TEMPO]
    song_title_ptr = struct.unpack_from('<H', data, SMD_OFFSET_SONG_TITLE_PTR)[0]
    drumkit_ptr = struct.unpack_from('<H', data, SMD_OFFSET_DRUMKIT_PTR)[0]

    track_ptrs = []
    for i in range(track_count):
        offset = SMD_OFFSET_TRACK_TABLE + i * SMD_TRACK_PTR_SIZE
        if offset + SMD_TRACK_PTR_SIZE > len(data):
            break
        ptr = struct.unpack_from('<H', data, offset)[0]
        track_ptrs.append(ptr)

    return SmdsHeader(
        magic=magic,
        unknown_04=unknown_04,
        file_size=file_size,
        track_count=track_count,
        drum_count=drum_count,
        assoc_wds_id=assoc_wds_id,
        initial_volume=initial_volume,
        unknown_19=unknown_19,
        initial_tempo=initial_tempo,
        song_title_ptr=song_title_ptr,
        drumkit_ptr=drumkit_ptr,
        track_ptrs=track_ptrs,
    )


def parse_smds_file(data: bytes) -> SmdsFile:
    """Parse an entire SMD file: header, title, and all tracks."""
    header = parse_smds_header(data)

    # Extract song title (between song_title_ptr and drumkit_ptr or first track)
    title_end = header.drumkit_ptr if header.drumkit_ptr > header.song_title_ptr else header.song_title_ptr
    if header.track_ptrs:
        title_end = min(title_end, header.track_ptrs[0])
    if header.song_title_ptr > 0 and header.song_title_ptr < len(data):
        title_bytes = data[header.song_title_ptr:title_end]
        song_title = title_bytes.rstrip(b'\x00').decode('ascii', errors='replace')
    else:
        song_title = ""

    # Extract track data and decode events
    tracks = []
    track_events = []

    for i, ptr in enumerate(header.track_ptrs):
        # Track data extends from this pointer to the next pointer (or end of file)
        if i + 1 < len(header.track_ptrs):
            end = header.track_ptrs[i + 1]
        else:
            end = header.file_size if header.file_size > 0 else len(data)

        # Clamp to file bounds
        ptr = min(ptr, len(data))
        end = min(end, len(data))

        track_data = data[ptr:end]
        tracks.append(track_data)

        events = decode_track(track_data, start_offset=ptr, length=len(track_data))
        track_events.append(events)

    return SmdsFile(
        header=header,
        song_title=song_title,
        tracks=tracks,
        track_events=track_events,
    )


def print_smds_info(smd: SmdsFile, filename: str = ""):
    """Print header information for an SMD file."""
    h = smd.header
    print(f"{'=' * 60}")
    if filename:
        print(f"File: {filename}")
    print(f"{'=' * 60}")
    print(f"Magic:           {h.magic.decode('ascii')}")
    print(f"File Size:       {h.file_size} bytes (0x{h.file_size:X})")
    print(f"Track Count:     {h.track_count}")
    print(f"Drum Count:      {h.drum_count}")
    print(f"Assoc WDS ID:    {h.assoc_wds_id}")
    print(f"Initial Volume:  {h.initial_volume}")
    print(f"Initial Tempo:   {h.initial_tempo} (= {h.initial_bpm:.1f} BPM)")
    if smd.song_title:
        print(f"Song Title:      \"{smd.song_title}\"")
    print()

    print("Track Pointers:")
    for i, ptr in enumerate(h.track_ptrs):
        track_size = len(smd.tracks[i]) if i < len(smd.tracks) else 0
        n_events = len(smd.track_events[i]) if i < len(smd.track_events) else 0
        label = "conductor" if i == 0 else f"instrument"
        print(f"  Track {i:2d}: offset=0x{ptr:04X}, size={track_size:4d} bytes, "
              f"{n_events:3d} events ({label})")
    print()


def print_track_decode(smd: SmdsFile, track_idx: int):
    """Print decoded events for a single track."""
    if track_idx >= len(smd.track_events):
        print(f"Error: Track {track_idx} does not exist (max: {len(smd.track_events) - 1})")
        return

    events = smd.track_events[track_idx]
    label = "conductor" if track_idx == 0 else "instrument"
    print(f"\n--- Track {track_idx} ({label}, {len(events)} events) ---")

    for event in events:
        print(f"  {event}")


def collect_opcode_stats(smd: SmdsFile) -> dict:
    """Collect opcode usage statistics across all tracks."""
    stats = {}
    unknown_opcodes = set()

    for track_idx, events in enumerate(smd.track_events):
        for event in events:
            if isinstance(event, NoteEvent):
                stats["Note"] = stats.get("Note", 0) + 1
            elif isinstance(event, OpcodeEvent):
                key = f"0x{event.opcode:02X} {event.name}"
                stats[key] = stats.get(key, 0) + 1
                if event.name.startswith("Unknown_"):
                    unknown_opcodes.add(event.opcode)

    return stats, unknown_opcodes


def batch_parse(sound_dir: Path, decode: bool = False):
    """Parse all MUSIC_##.SMD files in a directory."""
    smd_files = sorted(sound_dir.glob("MUSIC_*.SMD"))
    if not smd_files:
        print(f"No MUSIC_*.SMD files found in {sound_dir}")
        return

    print(f"Found {len(smd_files)} SMD files in {sound_dir}\n")

    all_unknown = set()
    global_stats = {}
    total_tracks = 0
    total_events = 0

    for smd_path in smd_files:
        try:
            data = smd_path.read_bytes()
            smd = parse_smds_file(data)

            n_events = sum(len(t) for t in smd.track_events)
            total_tracks += smd.track_count
            total_events += n_events

            stats, unknowns = collect_opcode_stats(smd)
            all_unknown.update(unknowns)
            for k, v in stats.items():
                global_stats[k] = global_stats.get(k, 0) + v

            title_str = f' "{smd.song_title}"' if smd.song_title else ""
            print(f"  {smd_path.name}: {smd.track_count:2d} tracks, "
                  f"{n_events:4d} events, "
                  f"tempo={smd.header.initial_bpm:.0f} BPM{title_str}")

            if unknowns:
                print(f"    UNKNOWN OPCODES: {', '.join(f'0x{o:02X}' for o in sorted(unknowns))}")

            if decode:
                print_smds_info(smd, smd_path.name)
                for i in range(smd.track_count):
                    print_track_decode(smd, i)

        except Exception as e:
            print(f"  {smd_path.name}: ERROR - {e}")

    # Summary
    print(f"\n{'=' * 60}")
    print(f"SUMMARY")
    print(f"{'=' * 60}")
    print(f"Files:           {len(smd_files)}")
    print(f"Total Tracks:    {total_tracks}")
    print(f"Total Events:    {total_events}")

    if all_unknown:
        print(f"\nUNKNOWN OPCODES FOUND: {', '.join(f'0x{o:02X}' for o in sorted(all_unknown))}")
    else:
        print(f"\nNo unknown opcodes - all opcodes in the table!")

    print(f"\nOpcode Usage (across all files):")
    for key in sorted(global_stats.keys()):
        print(f"  {key:30s}: {global_stats[key]:5d}")


def main():
    parser = argparse.ArgumentParser(
        description="Parse FFT MUSIC_##.SMD files"
    )
    parser.add_argument("input", type=Path, help="SMD file or SOUND directory for batch mode")
    parser.add_argument("--batch", action="store_true", help="Parse all MUSIC_*.SMD files in directory")
    parser.add_argument("--decode", action="store_true", help="Decode and show all track opcodes")
    parser.add_argument("--track", type=int, help="Decode specific track only")
    parser.add_argument("--stats", action="store_true", help="Show opcode usage statistics")

    args = parser.parse_args()

    if args.batch:
        if not args.input.is_dir():
            print(f"Error: {args.input} is not a directory", file=sys.stderr)
            sys.exit(1)
        batch_parse(args.input, decode=args.decode)
    else:
        if not args.input.exists():
            print(f"Error: {args.input} does not exist", file=sys.stderr)
            sys.exit(1)

        data = args.input.read_bytes()
        smd = parse_smds_file(data)

        print_smds_info(smd, args.input.name)

        if args.stats:
            stats, unknowns = collect_opcode_stats(smd)
            print("Opcode Usage:")
            for key in sorted(stats.keys()):
                print(f"  {key:30s}: {stats[key]:5d}")
            if unknowns:
                print(f"\nUNKNOWN: {', '.join(f'0x{o:02X}' for o in sorted(unknowns))}")

        if args.decode or args.track is not None:
            if args.track is not None:
                print_track_decode(smd, args.track)
            else:
                for i in range(smd.track_count):
                    print_track_decode(smd, i)


if __name__ == "__main__":
    main()
