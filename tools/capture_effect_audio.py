#!/usr/bin/env python3
"""
Effect Audio Capture - captures effect audio via PCSX-Redux bridge.

Prerequisites:
    1. PCSX-Redux running
    2. Effect editor loaded: dofile("...main.lua")
    3. Session loaded: ee_load_session("session_name")

Usage:
    # From Windows PowerShell (for PyAudioWPatch):
    python capture_effect_audio.py --output ./captures/E001

    # Or specify duration to wait:
    python capture_effect_audio.py --output ./captures/E001 --wait 10

Workflow:
    1. Starts WASAPI loopback recording
    2. Calls ee_capture_audio_start() via bridge (mutes music, runs effect)
    3. Waits for effect to complete
    4. Calls ee_capture_audio_read() via bridge (gets timestamps, unmutes)
    5. Stops recording and saves WAV
    6. Optionally slices WAV by phase timestamps
"""

import json
import re
import time
import wave
import argparse
from pathlib import Path

try:
    import pyaudiowpatch as pyaudio
    HAS_PYAUDIO = True
except ImportError:
    pyaudio = None
    HAS_PYAUDIO = False
    print("WARNING: PyAudioWPatch not available. Install with: pip install PyAudioWPatch")
    print("         Audio recording will be disabled.")

# File-based bridge paths - detect Windows vs WSL
import platform
if platform.system() == "Windows":
    COMMAND_FILE = Path(r"C:\Users\acurr\AppData\Roaming\pcsx-redux\bridge_command.lua")
    RESPONSE_FILE = Path(r"C:\Users\acurr\AppData\Roaming\pcsx-redux\bridge_response.txt")
else:
    # WSL path
    COMMAND_FILE = Path("/mnt/c/Users/acurr/AppData/Roaming/pcsx-redux/bridge_command.lua")
    RESPONSE_FILE = Path("/mnt/c/Users/acurr/AppData/Roaming/pcsx-redux/bridge_response.txt")

CHUNK_SIZE = 512


def bridge_call(lua_code: str, timeout: float = 10, wait_response: bool = False) -> str:
    """Execute Lua code via file-based bridge."""
    # Clear response file
    if wait_response and RESPONSE_FILE.exists():
        RESPONSE_FILE.unlink()

    # Write command to file
    COMMAND_FILE.write_text(lua_code)
    print(f"[Bridge] Sent: {lua_code[:50]}...")

    if not wait_response:
        return ""

    # Wait for response file
    start = time.time()
    while time.time() - start < timeout:
        if RESPONSE_FILE.exists():
            response = RESPONSE_FILE.read_text()
            if response.strip():
                return response
        time.sleep(0.1)

    print(f"[Bridge] No response after {timeout}s")
    return ""


def parse_timestamps(output: str) -> dict | None:
    """Parse TIMESTAMPS:{json} from Lua output."""
    match = re.search(r'TIMESTAMPS:(\{[^}]+\})', output)
    if match:
        try:
            return json.loads(match.group(1))
        except json.JSONDecodeError as e:
            print(f"ERROR: Failed to parse timestamps: {e}")
            return None
    return None


class AudioRecorder:
    """WASAPI loopback recorder."""

    def __init__(self, output_path: Path):
        if not HAS_PYAUDIO:
            self.p = None
            self.device = None
            return

        self.output_path = output_path
        self.p = pyaudio.PyAudio()
        self.stream = None
        self.wave_file = None
        self.recording = False
        self.device = self._find_loopback_device()

    def _find_loopback_device(self):
        """Find the default speakers loopback device."""
        try:
            wasapi_info = self.p.get_host_api_info_by_type(pyaudio.paWASAPI)
        except OSError:
            print("ERROR: WASAPI not available on this system")
            return None

        default = self.p.get_device_info_by_index(wasapi_info["defaultOutputDevice"])
        print(f"Default output: {default['name']}")

        if not default.get("isLoopbackDevice", False):
            for loopback in self.p.get_loopback_device_info_generator():
                if default["name"] in loopback["name"]:
                    print(f"Using loopback: {loopback['name']}")
                    return loopback
            print("WARNING: Could not find loopback device, using default")

        return default

    def start(self):
        """Start recording."""
        if not self.p or not self.device:
            print("WARNING: Audio recording disabled (no PyAudioWPatch)")
            return False

        if self.recording:
            return True

        try:
            self.output_path.parent.mkdir(parents=True, exist_ok=True)
            self.wave_file = wave.open(str(self.output_path), 'wb')
            self.wave_file.setnchannels(self.device["maxInputChannels"])
            self.wave_file.setsampwidth(pyaudio.get_sample_size(pyaudio.paInt16))
            self.wave_file.setframerate(int(self.device["defaultSampleRate"]))
        except Exception as e:
            print(f"ERROR: Cannot open file: {e}")
            return False

        def callback(in_data, frame_count, time_info, status):
            if self.recording and self.wave_file:
                self.wave_file.writeframes(in_data)
            return (in_data, pyaudio.paContinue)

        try:
            self.stream = self.p.open(
                format=pyaudio.paInt16,
                channels=self.device["maxInputChannels"],
                rate=int(self.device["defaultSampleRate"]),
                frames_per_buffer=CHUNK_SIZE,
                input=True,
                input_device_index=self.device["index"],
                stream_callback=callback
            )
            self.recording = True
            print(f"Recording to {self.output_path}")
            return True
        except Exception as e:
            if self.wave_file:
                self.wave_file.close()
                self.wave_file = None
            print(f"ERROR: Cannot start stream: {e}")
            return False

    def stop(self):
        """Stop recording and close the file."""
        if not self.recording:
            return

        self.recording = False

        if self.stream:
            try:
                self.stream.stop_stream()
                self.stream.close()
            except Exception:
                pass
            self.stream = None

        if self.wave_file:
            try:
                self.wave_file.close()
            except Exception:
                pass
            self.wave_file = None

        print(f"Saved {self.output_path}")

    def cleanup(self):
        """Clean up resources."""
        self.stop()
        if self.p:
            self.p.terminate()


def slice_wav(wav_path: Path, output_dir: Path, timestamps: dict,
               record_start_time: float, record_stop_time: float):
    """Slice WAV into phase files based on system timestamps."""

    # Read source WAV
    with wave.open(str(wav_path), 'rb') as wav:
        params = wav.getparams()
        sample_rate = params.framerate
        n_channels = params.nchannels
        sample_width = params.sampwidth
        all_frames = wav.readframes(wav.getnframes())

    total_samples = len(all_frames) // (n_channels * sample_width)
    recording_duration = record_stop_time - record_start_time

    print(f"\nWAV: {total_samples} samples, {total_samples/sample_rate:.2f}s")
    print(f"Recording window: {recording_duration:.2f}s")

    def time_to_sample(system_time: float) -> int:
        """Convert UNIX timestamp to WAV sample position."""
        # Offset from when Python started recording
        offset_seconds = system_time - record_start_time
        return int(offset_seconds * sample_rate)

    # Calculate sample positions from system timestamps
    effect_start_sample = time_to_sample(timestamps['effect_start'])
    phase1_end_sample = time_to_sample(timestamps['phase1_end'])
    phase2_start_sample = time_to_sample(timestamps['phase2_start'])
    effect_end_sample = time_to_sample(timestamps['effect_end'])

    # foreach_end may not exist in older captures, fall back to phase2_start
    foreach_end_sample = time_to_sample(timestamps.get('foreach_end', timestamps['phase2_start']))

    print(f"Effect in WAV: samples {effect_start_sample} to {effect_end_sample}")
    print(f"  Phase 1: {effect_start_sample} - {phase1_end_sample}")
    print(f"  For-Each: {phase1_end_sample} - {foreach_end_sample}")
    print(f"  Phase 2: {phase2_start_sample} - {effect_end_sample}")

    bytes_per_sample = n_channels * sample_width

    def extract_segment(start_sample: int, end_sample: int, filename: str):
        # Clamp to valid range
        start_sample = max(0, start_sample)
        end_sample = min(total_samples, end_sample)
        if end_sample <= start_sample:
            print(f"  Skipping {filename}: invalid range")
            return

        start_byte = start_sample * bytes_per_sample
        end_byte = end_sample * bytes_per_sample
        segment = all_frames[start_byte:end_byte]

        out_path = output_dir / filename
        with wave.open(str(out_path), 'wb') as out:
            out.setparams(params)
            out.writeframes(segment)
        duration = (end_sample - start_sample) / sample_rate
        print(f"  Saved {filename}: {duration:.2f}s")

    print("\nSlicing WAV into phases:")

    # Phase 1: effect_start to phase1_end
    extract_segment(effect_start_sample, phase1_end_sample, "phase1.wav")

    # For-Each/Spawn: phase1_end to foreach_end (just the spawning, not the delay)
    extract_segment(phase1_end_sample, foreach_end_sample, "foreach.wav")

    # Phase 2: phase2_start to effect_end
    extract_segment(phase2_start_sample, effect_end_sample, "phase2.wav")

    # Full effect (trimmed)
    extract_segment(effect_start_sample, effect_end_sample, "effect_full.wav")


def slice_phase_recording(full_wav: Path, out_wav: Path, timestamps: dict,
                          record_start: float, start_key: str, end_key: str,
                          buffer_seconds: float):
    """Extract phase segment from full recording, with end buffer."""
    if not full_wav.exists():
        print(f"  Skipping {out_wav.name}: source file not found")
        return

    with wave.open(str(full_wav), 'rb') as wav:
        params = wav.getparams()
        sample_rate = params.framerate
        n_channels = params.nchannels
        sample_width = params.sampwidth
        all_frames = wav.readframes(wav.getnframes())

    total_samples = len(all_frames) // (n_channels * sample_width)
    bytes_per_sample = n_channels * sample_width

    # Calculate sample positions
    start_time = timestamps[start_key]
    end_time = timestamps[end_key] + buffer_seconds

    start_offset = start_time - record_start
    end_offset = end_time - record_start

    start_sample = max(0, int(start_offset * sample_rate))
    end_sample = min(total_samples, int(end_offset * sample_rate))

    if end_sample <= start_sample:
        print(f"  Skipping {out_wav.name}: invalid range ({start_sample} to {end_sample})")
        return

    # Extract segment
    start_byte = start_sample * bytes_per_sample
    end_byte = end_sample * bytes_per_sample
    segment = all_frames[start_byte:end_byte]

    with wave.open(str(out_wav), 'wb') as out:
        out.setparams(params)
        out.writeframes(segment)

    duration = (end_sample - start_sample) / sample_rate
    print(f"  Saved {out_wav.name}: {duration:.2f}s")


# Buffer time at end of each phase to let notes resolve
# Some effects like Shiva have long-sustaining sounds that bleed well past phase boundaries
RESOLVE_BUFFER_SECONDS = 10.0


def capture_isolated(output_dir: Path, wait_seconds: float = 10.0, session: str | None = None,
                     sound_source: Path | None = None):
    """
    Capture with phase-isolated audio (3 separate recordings).

    Each phase is recorded separately with only that phase's sounds enabled.
    This prevents audio bleeding between phases.

    Args:
        output_dir: Directory to save captures
        wait_seconds: How long to wait for effect to complete
        session: Session name to reload before each phase (REQUIRED for isolated capture)
        sound_source: Optional path to E###.BIN file to load sound data from
    """
    if not session:
        print("ERROR: --session is required for isolated capture mode.")
        print("       The session is reloaded before each phase to restore sound channels.")
        return

    output_dir.mkdir(parents=True, exist_ok=True)

    # Phase definitions: (name, start_timestamp_key, end_timestamp_key)
    phases = [
        ("phase1", "effect_start", "phase1_end"),
        ("foreach", "phase1_end", "foreach_end"),
        ("phase2", "phase2_start", "effect_end"),
    ]

    timestamps = None

    for phase_name, start_key, end_key in phases:
        print(f"\n{'='*60}")
        print(f"Recording {phase_name} (isolated)")
        print(f"{'='*60}")

        # 1. Reload session to get clean sound channel state (no_autoplay=true)
        print(f"Reloading session: {session} (no autoplay)")
        bridge_call(f'ee_load_session("{session}", true)')
        time.sleep(1)  # Let session load

        # 2. Load sound data from different BIN if specified
        if sound_source:
            # Convert to Windows path format for Lua
            sound_path = str(sound_source).replace("\\", "/")
            print(f"Loading sound from: {sound_path}")
            bridge_call(f'ee_load_sound_from_bin("{sound_path}")', wait_response=True, timeout=5)
            time.sleep(0.5)

        # 3. Isolate this phase's sounds (mute other phases)
        print(f"Isolating {phase_name} sounds...")
        bridge_call(f'ee_isolate_phase("{phase_name}")', wait_response=True, timeout=5)
        time.sleep(0.5)  # Let Lua process

        # 4. Record full effect with only this phase's sounds
        full_wav_path = output_dir / f"{phase_name}_full.wav"
        recorder = AudioRecorder(full_wav_path)

        record_start = time.time()
        recorder.start()
        time.sleep(2.0)  # Pre-buffer

        # Run effect
        print(f"Running effect...")
        bridge_call("ee_capture_audio_start()")
        time.sleep(wait_seconds)

        # Get timestamps
        bridge_call("ee_capture_audio_read()", wait_response=True, timeout=5)

        # Parse timestamps for THIS recording (each has different record_start)
        current_timestamps = None
        if RESPONSE_FILE.exists():
            output = RESPONSE_FILE.read_text()
            current_timestamps = parse_timestamps(output)
            if current_timestamps:
                print(f"Timestamps: effect_start={current_timestamps.get('effect_start', 0):.2f}, "
                      f"{start_key}={current_timestamps.get(start_key, 0):.2f}, "
                      f"{end_key}={current_timestamps.get(end_key, 0):.2f}")
                # Save first recording's timestamps for the JSON file
                if timestamps is None:
                    timestamps = current_timestamps

        # Add resolve buffer at end
        print(f"Recording {RESOLVE_BUFFER_SECONDS}s buffer for note resolution...")
        time.sleep(RESOLVE_BUFFER_SECONDS)

        record_stop = time.time()
        recorder.stop()
        recorder.cleanup()

        # 4. Slice to phase boundaries + buffer (using THIS recording's timestamps)
        if current_timestamps:
            final_wav_path = output_dir / f"{phase_name}.wav"
            print(f"Slicing to {phase_name} boundaries...")
            slice_phase_recording(
                full_wav_path, final_wav_path,
                current_timestamps, record_start,
                start_key, end_key, RESOLVE_BUFFER_SECONDS
            )

    # Save timestamps
    if timestamps:
        ts_path = output_dir / "timestamps.json"
        with open(ts_path, 'w') as f:
            json.dump(timestamps, f, indent=2)
        print(f"Saved timestamps to {ts_path}")

    print(f"\n{'='*60}")
    print("Isolated capture complete!")
    print(f"Output files in: {output_dir}")
    print(f"{'='*60}")


def capture(output_dir: Path, wait_seconds: float = 10.0, session: str | None = None):
    """
    Capture effect audio.

    Args:
        output_dir: Directory to save captures
        wait_seconds: How long to wait for effect to complete
        session: Optional session name to load first
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    wav_path = output_dir / "capture.wav"

    # Optionally load a session first
    if session:
        print(f"Loading session: {session}")
        bridge_call(f'ee_load_session("{session}")')
        time.sleep(1)  # Give it a moment to load

    # 1. Record Python start time and start recording BEFORE sending command
    record_start_time = time.time()
    print(f"Recording started at: {record_start_time:.6f}")

    # 2. Start WASAPI recording
    recorder = AudioRecorder(wav_path)
    recorder.start()

    # 3. Wait 2 seconds buffer before sending command
    # This ensures we have clean audio at the start of the WAV
    print("Recording 2s buffer before command...")
    time.sleep(2.0)

    try:
        # 4. Call ee_capture_audio_start() - mutes music, runs effect
        command_sent_time = time.time()
        print(f"Starting capture at: {command_sent_time:.6f}")
        bridge_call("ee_capture_audio_start()")

        # 5. Wait for effect to complete
        print(f"Waiting {wait_seconds}s for effect to complete...")
        time.sleep(wait_seconds)

        # 6. Call ee_capture_audio_read() - get timestamps, unmute
        print("Reading capture results...")
        bridge_call("ee_capture_audio_read()", wait_response=True, timeout=5)

        # Read response file directly
        output = ""
        if RESPONSE_FILE.exists():
            output = RESPONSE_FILE.read_text()
            print(output)

        # 7. Wait 2 more seconds buffer at end
        print("Recording 2s buffer after effect...")
        time.sleep(2.0)

        # 8. Record Python stop time
        record_stop_time = time.time()
        print(f"Recording stopped at: {record_stop_time:.6f}")

        # 9. Stop recording
        recorder.stop()

        # 10. Parse timestamps
        timestamps = parse_timestamps(output)
        if timestamps:
            print(f"\nTimestamps: {json.dumps(timestamps, indent=2)}")

            # Add Python recording times to timestamps
            timestamps['record_start'] = record_start_time
            timestamps['record_stop'] = record_stop_time

            # Save timestamps to JSON
            ts_path = output_dir / "timestamps.json"
            with open(ts_path, 'w') as f:
                json.dump(timestamps, f, indent=2)
            print(f"Saved timestamps to {ts_path}")

            # 9. Slice WAV into phase files
            if wav_path.exists():
                slice_wav(wav_path, output_dir, timestamps,
                         record_start_time, record_stop_time)

        return timestamps

    finally:
        recorder.cleanup()


def main():
    parser = argparse.ArgumentParser(
        description="Capture FFT effect audio via PCSX-Redux bridge"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("./captures"),
        help="Output directory for captures (default: ./captures)"
    )
    parser.add_argument(
        "--wait", "-w",
        type=float,
        default=10.0,
        help="Seconds to wait for effect to complete (default: 10)"
    )
    parser.add_argument(
        "--session", "-s",
        type=str,
        help="Session name to load before capture (optional)"
    )
    parser.add_argument(
        "--list-devices",
        action="store_true",
        help="List available audio devices and exit"
    )
    parser.add_argument(
        "--isolated",
        action="store_true",
        help="Use 3-pass isolated phase recording (cleaner audio, slower)"
    )
    parser.add_argument(
        "--sound-source",
        type=Path,
        help="Load sound data from this E###.BIN file before capture"
    )
    args = parser.parse_args()

    if args.list_devices:
        if not HAS_PYAUDIO:
            print("ERROR: PyAudioWPatch not available")
            return
        p = pyaudio.PyAudio()
        print("Available audio devices:")
        print()
        for i in range(p.get_device_count()):
            dev = p.get_device_info_by_index(i)
            loopback = " [LOOPBACK]" if dev.get("isLoopbackDevice") else ""
            print(f"  {i}: {dev['name']}{loopback}")
        p.terminate()
        return

    if args.isolated:
        capture_isolated(args.output, args.wait, args.session, args.sound_source)
    else:
        capture(args.output, args.wait, args.session)


if __name__ == "__main__":
    main()
