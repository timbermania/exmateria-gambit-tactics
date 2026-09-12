"""
Shared SMD/feds opcode definitions for FFT sound system.

Extracted from tools/extract_feds.py. Used by both the SMD parser
and the sequencer. Identical encoding for smds (game music) and
feds (effect sounds) per VGMTrans FFTSeq.h.
"""

from dataclasses import dataclass
from enum import IntEnum
from typing import List, Optional

# From VGMTrans FFTSeq.h - tick durations indexed by (data_byte % 19)
# Index 0 means "read next byte for custom duration"
DELTA_TIME_TABLE = [0, 192, 144, 96, 72, 64, 48, 36, 32, 24, 18, 16, 12, 9, 8, 6, 4, 3, 2]

# PPQ (pulses per quarter note) - FFT uses 48 (0x30)
PPQ = 48

# Note names for relative_key values 0-13
NOTE_NAMES = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B', 'cont', 'rest']


class Opcode(IntEnum):
    """Named SMD/feds opcodes.

    This is the single source of truth — parser, writer, sequencer, and
    both MIDI converters should reference `Opcode.X` rather than raw
    hex literals. Since `Opcode` is an `IntEnum`, `op == Opcode.REST`
    is interchangeable with `op == 0x80` and `Opcode.REST in OPCODE_INFO`
    lookups work against int-keyed dicts.
    """

    # Timing
    REST = 0x80
    FERMATA = 0x81
    NOP = 0x82

    # Control flow
    END_BAR = 0x90
    LOOP = 0x91
    REPEAT = 0x98
    CODA = 0x99
    REPEAT_BREAK = 0x9A

    # Pitch
    OCTAVE = 0x94
    RAISE_OCTAVE = 0x95
    LOWER_OCTAVE = 0x96

    # Tempo / time
    TIME_SIGNATURE = 0x97
    TEMPO = 0xA0
    TEMPO_SLIDE = 0xA2

    # Instrument
    UNKNOWN_A9 = 0xA9
    INSTRUMENT = 0xAC
    UNKNOWN_AD = 0xAD
    PERCUSSION_ON = 0xAE
    PERCUSSION_OFF = 0xAF

    # Articulation
    SLUR_ON = 0xB0
    SLUR_OFF = 0xB1
    UNKNOWN_B2 = 0xB2
    UNKNOWN_B8 = 0xB8

    # Reverb
    REVERB_ON = 0xBA
    REVERB_OFF = 0xBB

    # ADSR
    ADSR_RESET = 0xC0
    ADSR_ATTACK = 0xC2
    ADSR_SUSTAIN_RATE = 0xC4
    ADSR_RELEASE = 0xC5
    UNKNOWN_C6 = 0xC6
    ADSR_DECAY_AND_SUSTAIN_LEVEL = 0xC7  # decay rate + sustain level combined
    UNKNOWN_C8 = 0xC8
    ADSR_DECAY = 0xC9
    ADSR_SUSTAIN_LEVEL = 0xCA
    UNKNOWN_CF = 0xCF

    # Pitch bend / modulation
    SET_PITCH_BEND = 0xD0
    ADD_PITCH_BEND = 0xD1
    PITCH_BEND = 0xD2
    PORTAMENTO = 0xD4
    DETUNE = 0xD6
    LFO_DEPTH_PITCH = 0xD7
    LFO_LENGTH_PITCH = 0xD8
    LFO_PITCH = 0xD9
    UNKNOWN_DB = 0xDB

    # Volume
    DYNAMICS = 0xE0
    ADD_VOLUME = 0xE1
    EXPRESSION = 0xE2
    LFO_DEPTH_VOL = 0xE3
    LFO_LENGTH_VOL = 0xE4
    LFO_VOL = 0xE5
    UNKNOWN_E7 = 0xE7

    # Pan
    PAN = 0xE8
    UNKNOWN_E9 = 0xE9
    PAN_SLIDE = 0xEA
    LFO_DEPTH_PAN = 0xEB
    LFO_LENGTH_PAN = 0xEC
    LFO_PAN = 0xED
    UNKNOWN_EF = 0xEF

    # Misc
    UNKNOWN_F8 = 0xF8
    UNKNOWN_F9 = 0xF9
    UNKNOWN_FB = 0xFB
    UNKNOWN_FC = 0xFC
    UNKNOWN_FD = 0xFD
    BANK_SELECT = 0xFE


# Opcode definitions: opcode -> (name, param_count)
# From wiki_articles/sound_section.txt and VGMTrans FFTSeq.cpp.
# Keyed by int for IntEnum compatibility — `Opcode.REST in OPCODE_INFO`
# works because IntEnum hashes as its int value.
OPCODE_INFO = {
    # Timing
    0x80: ("Rest", 1),
    0x81: ("Fermata", 1),       # Tie/Hold
    0x82: ("NOP", 0),

    # Control flow
    0x90: ("EndBar", 0),        # End of track
    0x91: ("Loop", 0),          # Infinite loop point marker
    0x98: ("Repeat", 1),        # Loop begin (param = count)
    0x99: ("Coda", 0),          # Loop end
    0x9A: ("RepeatBreak", 0),   # Exit loop on last iteration

    # Pitch
    0x94: ("Octave", 1),
    0x95: ("RaiseOctave", 0),
    0x96: ("LowerOctave", 0),

    # Tempo / time
    0x97: ("TimeSignature", 2),
    0xA0: ("Tempo", 1),
    0xA2: ("TempoSlide", 2),

    # Instrument
    0xA9: ("Unknown_A9", 1),
    0xAC: ("Instrument", 1),
    0xAD: ("Unknown_AD", 1),
    0xAE: ("PercussionOn", 0),
    0xAF: ("PercussionOff", 0),

    # Articulation
    0xB0: ("SlurOn", 0),
    0xB1: ("SlurOff", 0),
    0xB2: ("Unknown_B2", 0),
    0xB8: ("Unknown_B8", 3),

    # Reverb
    0xBA: ("ReverbOn", 0),
    0xBB: ("ReverbOff", 0),

    # ADSR
    0xC0: ("ADSR_Reset", 0),
    0xC2: ("ADSR_Attack", 1),
    0xC4: ("ADSR_SustainRate", 1),
    0xC5: ("ADSR_Release", 1),
    0xC6: ("Unknown_C6", 1),
    0xC7: ("Unknown_C7", 2),
    0xC8: ("Unknown_C8", 1),
    0xC9: ("ADSR_Decay", 1),
    0xCA: ("ADSR_SustainLevel", 1),
    0xCF: ("Unknown_CF", 0),

    # Pitch bend / modulation
    0xD0: ("SetPitchBend", 1),
    0xD1: ("AddPitchBend", 1),
    0xD2: ("PitchBend", 1),
    0xD4: ("Portamento", 2),
    0xD6: ("Detune", 1),
    0xD7: ("LFO_Depth_Pitch", 1),
    0xD8: ("LFO_Length_Pitch", 3),
    0xD9: ("LFO_Pitch", 3),
    0xDB: ("Unknown_DB", 0),

    # Volume
    0xE0: ("Dynamics", 1),      # Set volume
    0xE1: ("AddVolume", 1),
    0xE2: ("Expression", 2),    # Volume slide
    0xE3: ("LFO_Depth_Vol", 1),
    0xE4: ("LFO_Length_Vol", 3),
    0xE5: ("LFO_Vol", 3),
    0xE7: ("Unknown_E7", 0),

    # Pan
    0xE8: ("Pan", 1),
    0xE9: ("Unknown_E9", 1),
    0xEA: ("PanSlide", 2),
    0xEB: ("LFO_Depth_Pan", 1),
    0xEC: ("LFO_Length_Pan", 3),
    0xED: ("LFO_Pan", 3),
    0xEF: ("Unknown_EF", 0),

    # Misc
    0xF8: ("Unknown_F8", 3),
    0xF9: ("Unknown_F9", 2),
    0xFB: ("Unknown_FB", 1),
    0xFC: ("Unknown_FC", 2),
    0xFD: ("Unknown_FD", 1),
    0xFE: ("BankSelect", 1),
}


@dataclass
class NoteEvent:
    """A decoded note event (opcode < 0x80)"""
    offset: int
    velocity: int       # 0-127
    relative_key: int   # 0-11 = C..B, 12 = continue/tie, 13 = rest
    delta_time: int     # Duration in ticks
    raw_bytes: bytes

    @property
    def is_note(self) -> bool:
        return self.relative_key < 12

    @property
    def is_tie(self) -> bool:
        return self.relative_key == 12

    @property
    def is_rest(self) -> bool:
        return self.relative_key == 13

    @property
    def note_name(self) -> str:
        if self.relative_key < len(NOTE_NAMES):
            return NOTE_NAMES[self.relative_key]
        return f'?{self.relative_key}'

    def __str__(self) -> str:
        hex_bytes = ' '.join(f'{b:02X}' for b in self.raw_bytes)
        return f"{self.offset:04X}: {hex_bytes:12s} Note vel={self.velocity} key={self.note_name} dur={self.delta_time}"


@dataclass
class OpcodeEvent:
    """A decoded control opcode event (opcode >= 0x80)"""
    offset: int
    opcode: int
    name: str
    params: List[int]
    raw_bytes: bytes

    def __str__(self) -> str:
        hex_bytes = ' '.join(f'{b:02X}' for b in self.raw_bytes)
        if self.params:
            param_str = ', '.join(f'{p}' for p in self.params)
            return f"{self.offset:04X}: {hex_bytes:12s} {self.name}({param_str})"
        return f"{self.offset:04X}: {hex_bytes:12s} {self.name}"


# Union type for decoded events
Event = NoteEvent | OpcodeEvent


def decode_track(data: bytes, start_offset: int = 0, length: Optional[int] = None) -> List[Event]:
    """
    Decode SMD/feds opcodes from a track's byte stream.

    Note encoding (opcode < 0x80):
        velocity = opcode
        data_byte = next byte
        relative_key = data_byte // 19 (0-11 = notes, 12 = continue, 13 = rest)
        delta_index = data_byte % 19
        delta_time = DELTA_TIME_TABLE[delta_index] (0 means read next byte)

    Returns list of NoteEvent and OpcodeEvent objects.
    """
    if length is None:
        length = len(data)

    events: List[Event] = []
    pos = 0

    while pos < length:
        offset = start_offset + pos
        byte = data[pos]
        pos += 1

        if byte < 0x80:
            # Note event
            if pos >= length:
                break
            data_byte = data[pos]
            pos += 1

            relative_key = data_byte // 19
            delta_index = data_byte % 19
            delta_time = DELTA_TIME_TABLE[delta_index]

            raw = bytes([byte, data_byte])

            # Custom duration: delta_index 0 means read next byte
            if delta_time == 0 and pos < length:
                delta_time = data[pos]
                raw = bytes([byte, data_byte, delta_time])
                pos += 1

            events.append(NoteEvent(
                offset=offset,
                velocity=byte,
                relative_key=relative_key,
                delta_time=delta_time,
                raw_bytes=raw,
            ))
        else:
            # Control opcode
            if byte in OPCODE_INFO:
                name, param_count = OPCODE_INFO[byte]
            else:
                name, param_count = f"Unknown_{byte:02X}", 0

            params = []
            raw = bytes([byte])
            for _ in range(param_count):
                if pos >= length:
                    break
                params.append(data[pos])
                raw += bytes([data[pos]])
                pos += 1

            events.append(OpcodeEvent(
                offset=offset,
                opcode=byte,
                name=name,
                params=params,
                raw_bytes=raw,
            ))

            # Stop at EndBar
            if byte == Opcode.END_BAR:
                break

    return events


def fft_tempo_to_bpm(tempo_val: int) -> float:
    """Convert FFT tempo byte to BPM. From VGMTrans: bpm = (val * 256) / 218"""
    if tempo_val == 0:
        return 120.0
    return (tempo_val * 256) / 218
