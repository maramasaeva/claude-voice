#!/usr/bin/env python3
"""
claude-voice — talk to Claude Code with your voice.

Say "Claude" or "Hey Claude" to start talking. Your message gets
transcribed and sent to the active Claude Code session automatically.
Pair with the TTS hook to hear responses back.

Usage:
    python3 voice.py              # start listening
    python3 voice.py --stop       # stop the listener
    python3 voice.py --bg         # start in background

Requires: openai-whisper, sounddevice, numpy, edge-tts
"""

import sounddevice as sd
import numpy as np
import tempfile
import subprocess
import sys
import os
import signal
import time
import wave

# ─── Config ───────────────────────────────────────────────────────
SAMPLE_RATE = 16000
CHANNELS = 1
WAKE_CHUNK_SECONDS = 2
SILENCE_THRESHOLD = 0.008       # RMS below this = silence
SILENCE_DURATION = 1.8          # seconds of silence = done talking
MAX_RECORD_SECONDS = 120
WAKE_WORDS = ["claude", "hey claude", "hi claude", "okay claude"]
WHISPER_MODEL = "base"          # tiny, base, small, medium, large
PID_FILE = "/tmp/claude-voice.pid"


# ─── Audio helpers ────────────────────────────────────────────────

def save_wav(filename, audio_data):
    audio_int16 = (audio_data * 32767).astype(np.int16)
    with wave.open(filename, 'w') as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(audio_int16.tobytes())


def get_rms(chunk):
    return np.sqrt(np.mean(chunk.astype(np.float64) ** 2))


def play_chime(freq=880, dur=0.15):
    t = np.linspace(0, dur, int(SAMPLE_RATE * dur), False)
    tone = 0.3 * np.sin(2 * np.pi * freq * t)
    tone *= np.linspace(1, 0, len(tone))
    sd.play(tone.astype(np.float32), SAMPLE_RATE)
    sd.wait()


def play_done():
    play_chime(freq=440, dur=0.12)


# ─── Whisper ──────────────────────────────────────────────────────

_model = None

def load_whisper():
    global _model
    import whisper
    print("  loading whisper model...")
    _model = whisper.load_model(WHISPER_MODEL)
    print("  whisper ready.")


def transcribe(audio_file):
    result = _model.transcribe(audio_file, language="en", fp16=False)
    return result["text"].strip()


# ─── Send to Claude Code ─────────────────────────────────────────

def send_to_claude_code(text):
    """Type text into the frontmost terminal (Claude Code) via AppleScript."""
    escaped = text.replace('\\', '\\\\').replace('"', '\\"').replace("'", "'\\''")
    # Use 'keystroke' for the text, then Return to send
    script = f'''
    tell application "System Events"
        keystroke "{escaped}"
        delay 0.1
        keystroke return
    end tell
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True)


# ─── Core loop ────────────────────────────────────────────────────

def check_wake_word(audio_data):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        save_wav(f.name, audio_data)
        try:
            text = transcribe(f.name).lower()
        finally:
            os.unlink(f.name)
    for w in WAKE_WORDS:
        if w in text:
            return True
    return False


def record_message():
    """Record until silence."""
    frames = []
    silence_start = None
    chunk_size = int(SAMPLE_RATE * 0.1)
    start = time.time()

    while True:
        audio = sd.rec(chunk_size, samplerate=SAMPLE_RATE, channels=CHANNELS, dtype='float32')
        sd.wait()
        frames.append(audio.flatten())

        if get_rms(audio) < SILENCE_THRESHOLD:
            if silence_start is None:
                silence_start = time.time()
            elif time.time() - silence_start > SILENCE_DURATION:
                break
        else:
            silence_start = None

        if time.time() - start > MAX_RECORD_SECONDS:
            break

    return np.concatenate(frames)


def main():
    # --stop
    if "--stop" in sys.argv:
        if os.path.exists(PID_FILE):
            with open(PID_FILE) as f:
                pid = int(f.read().strip())
            try:
                os.kill(pid, signal.SIGTERM)
                print(f"stopped claude-voice (pid {pid})")
            except ProcessLookupError:
                print("not running")
            os.unlink(PID_FILE)
        else:
            print("not running")
        return

    # --bg (relaunch self in background)
    if "--bg" in sys.argv:
        args = [sys.executable, __file__]
        proc = subprocess.Popen(
            args,
            stdout=open("/tmp/claude-voice.log", "w"),
            stderr=subprocess.STDOUT,
            start_new_session=True
        )
        print(f"  claude-voice started in background (pid {proc.pid})")
        print(f"  say 'Claude' to start talking")
        print(f"  run 'python3 {__file__} --stop' to stop")
        return

    # Write PID
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))

    def cleanup(sig=None, frame=None):
        try: os.unlink(PID_FILE)
        except: pass
        print("\n  voice listener stopped.")
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    load_whisper()

    print()
    print("  ╔══════════════════════════════════════╗")
    print("  ║       claude-voice is listening       ║")
    print("  ║  say 'claude' to start talking        ║")
    print("  ║  ctrl+c to stop                       ║")
    print("  ╚══════════════════════════════════════╝")
    print()

    chunk_samples = int(SAMPLE_RATE * WAKE_CHUNK_SECONDS)

    while True:
        try:
            audio = sd.rec(chunk_samples, samplerate=SAMPLE_RATE,
                          channels=CHANNELS, dtype='float32')
            sd.wait()
            flat = audio.flatten()

            if get_rms(flat) < SILENCE_THRESHOLD * 0.5:
                continue

            if check_wake_word(flat):
                print("  ✨ wake word!")
                play_chime()

                msg_audio = record_message()
                play_done()

                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                    save_wav(f.name, msg_audio)
                    try:
                        text = transcribe(f.name)
                    finally:
                        os.unlink(f.name)

                if text and text.strip():
                    clean = text.strip()
                    for w in sorted(WAKE_WORDS, key=len, reverse=True):
                        if clean.lower().startswith(w):
                            clean = clean[len(w):].lstrip('.,!? ')
                            break

                    if clean:
                        print(f"  📝 {clean}")
                        send_to_claude_code(clean)
                        print(f"  ✅ sent\n")
                    else:
                        print("  (wake word only)\n")
                else:
                    print("  (couldn't hear, try again)\n")

        except KeyboardInterrupt:
            cleanup()
        except Exception as e:
            print(f"  err: {e}")
            continue


if __name__ == "__main__":
    main()
