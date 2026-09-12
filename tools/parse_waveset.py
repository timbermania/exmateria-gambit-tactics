#!/usr/bin/env python3
"""
WAVESET.WD Parser - Extracts VAG samples from FFT's sound bank

Parses the "dwds" format WAVESET.WD file and extracts individual instrument
samples as WAV files for use in Godot.

The WAVESET.WD format (per FFHacktics wiki):
  Offset  Size    Description
  0x00    4       Magic "dwds" (0x64776473)
  0x04    4       Unknown (possibly checksum)
  0x08    4       File size
  0x0C    4       Unknown
  0x10    4       Sample data offset (typically 0xB30)
  0x14    4       Unknown
  0x18    4       Sample data offset (duplicate)
  0x1C    4       Instrument count
  0x20    16      Unknown header data
  0x30    N*16    Instrument table (16 bytes per entry)
  0xB30+  var     VAG sample data

Instrument Entry (16 bytes at 0x30 + id*16):
  Offset  Size    Description
  0x00    4       Wave pointer - offset to VAG data from 0xB30
  0x04    2       ADPCM Repeat address (loop point) - NOT sample size!
  0x06    2       Unknown
  0x08    8       ADSR envelope parameters

NOTE: There is NO sample size field in the entry! The size must be
determined by scanning VAG blocks for the END flag (0x01 in flag byte).

VAG ADPCM Format:
  16-byte blocks, each produces 28 PCM samples
  Block header: shift_factor (4 bits), filter_index (4 bits), flags (8 bits)
  Flags: 0x01 = END, 0x02 = LOOP_REGION, 0x04 = LOOP_START
  14 bytes of 4-bit nibble pairs

Usage:
    python parse_waveset.py /path/to/WAVESET.WD output_dir
"""

import struct
import wave
import json
import sys
from pathlib import Path
from dataclasses import dataclass, asdict
from typing import List, Tuple, Optional

# =============================================================================
# VAG ADPCM Filter Coefficients (Standard PSX)
# =============================================================================

# These coefficients are fixed for PSX VAG decoding
# Each pair is [K0, K1] used in: sample = data + K0*prev1/64 + K1*prev2/64
VAG_FILTER_COEFFICIENTS = [
    [0, 0],      # Filter 0: No prediction
    [60, 0],     # Filter 1
    [115, -52],  # Filter 2
    [98, -55],   # Filter 3
    [122, -60],  # Filter 4
]

# VAG block flags
VAG_FLAG_LOOP_END = 0x01    # End of loop
VAG_FLAG_LOOP_REGION = 0x02 # Inside loop region
VAG_FLAG_LOOP_START = 0x04  # Start of loop

# =============================================================================
# Data Classes
# =============================================================================

@dataclass
class InstrumentEntry:
    """Represents a single instrument in WAVESET.WD

    Entry format (16 bytes at 0x30 + id*16):
      0x00: wave pointer (4 bytes) - offset to VAG data from sample_data_base
      0x04: ADPCM repeat address (2 bytes) - loop point, NOT sample size
      0x06-0x07: unknown
      0x08-0x0F: ADSR envelope parameters
    """
    id: int
    sample_offset: int        # wave pointer (offset to VAG data)
    repeat_addr: int          # ADPCM repeat address (loop point)
    adsr_params: bytes        # ADSR envelope (8 bytes)
    sample_size: int = 0      # Determined by VAG scanning, not from entry
    loop_start: int = -1
    loop_end: int = -1
    sample_rate: int = 22050  # Default PSX sample rate


@dataclass
class WavesetHeader:
    """WAVESET.WD file header"""
    magic: str
    file_size: int
    sample_data_offset: int
    instrument_count: int


# =============================================================================
# VAG ADPCM Decoder
# =============================================================================

def decode_vag_block(block: bytes, prev1: int, prev2: int) -> Tuple[List[int], int, int]:
    """
    Decode a single 16-byte VAG ADPCM block to 28 PCM samples.

    Args:
        block: 16-byte VAG block
        prev1: Previous sample (n-1)
        prev2: Previous sample (n-2)

    Returns:
        Tuple of (samples list, new_prev1, new_prev2)
    """
    if len(block) < 16:
        return [], prev1, prev2

    # Extract block header
    shift_factor = block[0] & 0x0F
    filter_index = (block[0] >> 4) & 0x0F
    flags = block[1]

    # Get filter coefficients
    if filter_index >= len(VAG_FILTER_COEFFICIENTS):
        filter_index = 0
    k0, k1 = VAG_FILTER_COEFFICIENTS[filter_index]

    samples = []

    # Process 14 data bytes (28 nibbles = 28 samples)
    for i in range(2, 16):
        byte = block[i]

        # Process low nibble first, then high nibble
        for nibble_idx in range(2):
            if nibble_idx == 0:
                nibble = byte & 0x0F
            else:
                nibble = (byte >> 4) & 0x0F

            # Sign-extend the 4-bit nibble to signed value
            if nibble >= 8:
                nibble -= 16

            # Apply shift (scale by 2^(12-shift))
            sample = nibble << (12 - shift_factor)

            # Apply prediction filter
            sample += (k0 * prev1 + k1 * prev2 + 32) >> 6

            # Clamp to 16-bit signed range
            sample = max(-32768, min(32767, sample))

            samples.append(sample)

            # Update history
            prev2 = prev1
            prev1 = sample

    return samples, prev1, prev2


def decode_vag_data(vag_data: bytes) -> Tuple[List[int], int, int]:
    """
    Decode complete VAG data to PCM samples.

    Args:
        vag_data: Raw VAG ADPCM data

    Returns:
        Tuple of (pcm_samples, loop_start_sample, loop_end_sample)
    """
    pcm_samples = []
    prev1, prev2 = 0, 0
    loop_start = -1
    loop_end = -1

    # Process in 16-byte blocks
    num_blocks = len(vag_data) // 16

    for block_idx in range(num_blocks):
        block_offset = block_idx * 16
        block = vag_data[block_offset:block_offset + 16]

        if len(block) < 16:
            break

        flags = block[1]

        # Check for loop markers
        if flags & VAG_FLAG_LOOP_START:
            loop_start = len(pcm_samples)

        samples, prev1, prev2 = decode_vag_block(block, prev1, prev2)
        pcm_samples.extend(samples)

        if flags & VAG_FLAG_LOOP_END:
            loop_end = len(pcm_samples)
            # Don't break - some samples continue after loop end

    return pcm_samples, loop_start, loop_end


def get_vag_sample_size(data: bytes, start_offset: int, max_size: int) -> int:
    """
    Scan VAG blocks to determine sample size by finding END flag.

    The WAVESET.WD instrument entry does NOT contain a size field - we must
    scan VAG blocks until we find one with the END flag set.

    Args:
        data: Full file data
        start_offset: Absolute offset where VAG data starts
        max_size: Maximum bytes to scan (safety limit)

    Returns:
        Size in bytes of the VAG sample data
    """
    VAG_BLOCK_SIZE = 16
    offset = 0

    while offset < max_size:
        block_offset = start_offset + offset
        if block_offset + VAG_BLOCK_SIZE > len(data):
            break

        flags = data[block_offset + 1]  # Flag byte is at position 1 in VAG block
        offset += VAG_BLOCK_SIZE

        # Check for END flag (bit 0) - values 0x01, 0x03, 0x05, 0x07
        if flags & VAG_FLAG_LOOP_END:
            break

    return offset


def write_wav_file(output_path: Path, pcm_samples: List[int], sample_rate: int = 22050):
    """
    Write PCM samples to a WAV file.

    Args:
        output_path: Path to output WAV file
        pcm_samples: List of 16-bit signed PCM samples
        sample_rate: Sample rate in Hz
    """
    with wave.open(str(output_path), 'wb') as wav:
        wav.setnchannels(1)  # Mono
        wav.setsampwidth(2)  # 16-bit
        wav.setframerate(sample_rate)

        # Convert to bytes
        data = b''.join(struct.pack('<h', s) for s in pcm_samples)
        wav.writeframes(data)


# =============================================================================
# WAVESET.WD Parser
# =============================================================================

def parse_waveset_header(data: bytes) -> WavesetHeader:
    """Parse WAVESET.WD header"""
    magic = data[0:4].decode('ascii', errors='replace')

    if magic != 'dwds':
        raise ValueError(f"Invalid magic: expected 'dwds', got '{magic}'")

    file_size = struct.unpack_from('<I', data, 0x08)[0]
    sample_data_offset = struct.unpack_from('<I', data, 0x10)[0]

    # Instrument count appears to be at offset 0x1C
    instrument_count = struct.unpack_from('<I', data, 0x1C)[0]

    # Sanity check: calculate based on table size
    table_size = sample_data_offset - 0x30
    calculated_count = table_size // 16

    # Use the smaller of the two to be safe
    if instrument_count == 0 or instrument_count > calculated_count:
        instrument_count = calculated_count

    return WavesetHeader(
        magic=magic,
        file_size=file_size,
        sample_data_offset=sample_data_offset,
        instrument_count=instrument_count
    )


def parse_instrument_entry(data: bytes, offset: int, inst_id: int) -> InstrumentEntry:
    """Parse a single instrument table entry

    Entry format (16 bytes) per FFHacktics wiki:
      Bytes 0-3: wave pointer - offset to VAG data from sample_data_base
      Bytes 4-5: ADPCM repeat address - loop point, NOT sample size!
      Bytes 6-7: unknown
      Bytes 8-15: ADSR envelope parameters

    NOTE: There is NO sample size field! Size must be determined by
    scanning VAG blocks for the END flag.
    """
    wave_pointer = struct.unpack_from('<I', data, offset)[0]
    repeat_addr = struct.unpack_from('<H', data, offset + 4)[0]  # Loop point, not size!
    adsr_params = data[offset + 8:offset + 16]

    return InstrumentEntry(
        id=inst_id,
        sample_offset=wave_pointer,
        repeat_addr=repeat_addr,
        adsr_params=adsr_params,
        sample_size=0  # Will be determined by VAG scanning
    )


def parse_waveset(file_path: Path) -> Tuple[WavesetHeader, List[InstrumentEntry], bytes]:
    """
    Parse complete WAVESET.WD file.

    Returns:
        Tuple of (header, instruments list, raw file data)
    """
    with open(file_path, 'rb') as f:
        data = f.read()

    header = parse_waveset_header(data)

    print(f"WAVESET.WD Header:")
    print(f"  Magic: {header.magic}")
    print(f"  File size: {header.file_size} bytes")
    print(f"  Sample data offset: 0x{header.sample_data_offset:X}")
    print(f"  Instrument count: {header.instrument_count}")

    # Parse instrument table
    instruments = []
    for i in range(header.instrument_count):
        entry_offset = 0x30 + (i * 16)
        inst = parse_instrument_entry(data, entry_offset, i)
        instruments.append(inst)

    return header, instruments, data


def extract_instrument_sample(
    inst: InstrumentEntry,
    data: bytes,
    sample_data_base: int,
    file_size: int
) -> Tuple[List[int], int, int, int]:
    """
    Extract and decode a single instrument's sample data.

    Scans VAG blocks to find the END flag since WAVESET.WD entries
    do NOT contain a size field.

    Returns:
        Tuple of (pcm_samples, loop_start, loop_end, sample_size)
    """
    # Skip if wave pointer is 0 (no sample)
    if inst.sample_offset == 0:
        return [], -1, -1, 0

    # Calculate absolute offset in file
    sample_start = sample_data_base + inst.sample_offset

    if sample_start >= len(data):
        print(f"  Warning: Sample offset beyond file (inst {inst.id})")
        return [], -1, -1, 0

    # Scan VAG blocks to find actual sample size (look for END flag)
    max_scan = len(data) - sample_start  # Don't read past end of file
    sample_size = get_vag_sample_size(data, sample_start, max_scan)

    if sample_size == 0:
        return [], -1, -1, 0

    sample_end = sample_start + sample_size
    vag_data = data[sample_start:sample_end]

    # Check if it's all zeros (silent sample)
    if len(vag_data) > 0 and all(b == 0 for b in vag_data[:min(32, len(vag_data))]):
        return [], -1, -1, 0

    pcm_samples, loop_start, loop_end = decode_vag_data(vag_data)
    return pcm_samples, loop_start, loop_end, sample_size


def main():
    if len(sys.argv) < 3:
        print("Usage: python parse_waveset.py WAVESET.WD output_dir")
        print("\nExtracts VAG samples from WAVESET.WD to WAV files")
        sys.exit(1)

    input_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])

    if not input_path.exists():
        print(f"Error: Input file not found: {input_path}")
        sys.exit(1)

    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)

    # Parse WAVESET.WD
    header, instruments, data = parse_waveset(input_path)

    # Build index
    index = {
        "source_file": str(input_path.name),
        "instrument_count": len(instruments),
        "samples": []
    }

    # Extract each instrument
    extracted_count = 0
    silent_count = 0

    for inst in instruments:
        pcm_samples, loop_start, loop_end, sample_size = extract_instrument_sample(
            inst, data, header.sample_data_offset, header.file_size
        )

        if not pcm_samples:
            silent_count += 1
            index["samples"].append({
                "id": inst.id,
                "file": None,
                "silent": True,
                "repeat_addr": inst.repeat_addr,
                "sample_rate": inst.sample_rate
            })
            continue

        # Write WAV file
        wav_name = f"sample_{inst.id:03d}.wav"
        wav_path = output_dir / wav_name
        write_wav_file(wav_path, pcm_samples, inst.sample_rate)

        # Update loop info in instrument
        inst.loop_start = loop_start
        inst.loop_end = loop_end
        inst.sample_size = sample_size

        index["samples"].append({
            "id": inst.id,
            "file": wav_name,
            "silent": False,
            "repeat_addr": inst.repeat_addr,
            "sample_rate": inst.sample_rate,
            "sample_count": len(pcm_samples),
            "vag_size": sample_size,
            "loop_start": loop_start if loop_start >= 0 else None,
            "loop_end": loop_end if loop_end >= 0 else None
        })

        extracted_count += 1

        if extracted_count <= 10 or extracted_count % 20 == 0:
            print(f"  Extracted instrument {inst.id}: {len(pcm_samples)} samples ({sample_size} bytes VAG)")

    # Write index file
    index_path = output_dir / "waveset_index.json"
    with open(index_path, 'w') as f:
        json.dump(index, f, indent=2)

    print(f"\nExtraction complete:")
    print(f"  Total instruments: {len(instruments)}")
    print(f"  Extracted: {extracted_count}")
    print(f"  Silent: {silent_count}")
    print(f"  Output directory: {output_dir}")
    print(f"  Index file: {index_path}")


if __name__ == '__main__':
    main()
