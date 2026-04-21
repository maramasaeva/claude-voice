#!/usr/bin/env python3
"""
claude-voice — talk to Claude Code with your voice.

Say "Claude" to start talking. Your message gets transcribed and sent
to the active Claude Code session automatically. Uses macOS on-device
speech recognition (same engine as Siri/Dictation).

Pair with the TTS hook (speak-response.sh) to hear responses back.

Usage:
    python3 voice.py              # start listening
    python3 voice.py --stop       # stop the listener
    python3 voice.py --bg         # start in background

Requires: macOS with Dictation enabled (System Settings > Keyboard > Dictation)
"""

import subprocess
import sys
import os
import signal
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LISTENER_BIN = os.path.join(SCRIPT_DIR, "live_listen")
PID_FILE = "/tmp/claude-voice.pid"


WAKE_CHIME = "/tmp/claude-wake.wav"
DONE_CHIME = "/tmp/claude-done.wav"


def ensure_chimes():
    """Generate chime files if they don't exist."""
    import numpy as np
    import wave as wav

    if not os.path.exists(WAKE_CHIME):
        rate = 44100
        t = np.linspace(0, 0.25, int(rate * 0.25), False)
        tone = 0.4 * np.sin(2 * np.pi * 880 * t) + 0.2 * np.sin(2 * np.pi * 1320 * t)
        tone *= np.linspace(1, 0, len(tone)) ** 2
        wf = wav.open(WAKE_CHIME, 'w')
        wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(rate)
        wf.writeframes((tone * 32767).astype(np.int16).tobytes())
        wf.close()

    if not os.path.exists(DONE_CHIME):
        rate = 44100
        t = np.linspace(0, 0.15, int(rate * 0.15), False)
        tone = 0.3 * np.sin(2 * np.pi * 440 * t)
        tone *= np.linspace(1, 0, len(tone)) ** 2
        wf = wav.open(DONE_CHIME, 'w')
        wf.setnchannels(1); wf.setsampwidth(2); wf.setframerate(rate)
        wf.writeframes((tone * 32767).astype(np.int16).tobytes())
        wf.close()


def play_chime():
    """Play wake chime through headphones."""
    subprocess.Popen(
        ["afplay", WAKE_CHIME],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def play_done():
    """Play done chime through headphones."""
    subprocess.Popen(
        ["afplay", DONE_CHIME],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def send_to_claude_code(text):
    """Type text into the frontmost terminal via AppleScript."""
    escaped = text.replace('\\', '\\\\').replace('"', '\\"')
    script = f'''
    tell application "System Events"
        keystroke "{escaped}"
        delay 0.1
        keystroke return
    end tell
    '''
    subprocess.run(["osascript", "-e", script], capture_output=True)


def speak_response(text):
    """Speak text aloud using Edge-TTS (Ava voice)."""
    import re
    # Strip markdown
    msg = re.sub(r'```[\s\S]*?```', '', text)
    msg = re.sub(r'`[^`]+`', '', msg)
    msg = re.sub(r'\*\*(.+?)\*\*', r'\1', msg)
    msg = re.sub(r'\*(.+?)\*', r'\1', msg)
    msg = re.sub(r'^#{1,6}\s+', '', msg, flags=re.MULTILINE)
    msg = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', msg)
    msg = re.sub(r'^[-*]\s+', '', msg, flags=re.MULTILINE)
    msg = re.sub(r'\n{2,}', '. ', msg)
    msg = re.sub(r'\n', ' ', msg)
    msg = msg.strip()
    if not msg:
        return
    if len(msg) > 2000:
        msg = msg[:2000] + '. Check the screen for the rest.'
    # Kill any previous TTS
    subprocess.run(["pkill", "-f", "afplay /tmp/claude_tts"], capture_output=True)
    tmpfile = f"/tmp/claude_tts_{os.getpid()}.mp3"
    subprocess.run(
        ["edge-tts", "--voice", "en-US-AvaNeural", "--text", msg, "--write-media", tmpfile],
        capture_output=True
    )
    subprocess.Popen(["afplay", tmpfile], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    # --stop
    if "--stop" in sys.argv:
        if os.path.exists(PID_FILE):
            with open(PID_FILE) as f:
                pid = int(f.read().strip())
            try:
                os.kill(pid, signal.SIGTERM)
                print(f"  stopped claude-voice (pid {pid})")
            except ProcessLookupError:
                print("  not running")
            os.unlink(PID_FILE)
        else:
            print("  not running")
        return

    # --bg
    if "--bg" in sys.argv:
        env = os.environ.copy()
        env["PYTHONUNBUFFERED"] = "1"
        proc = subprocess.Popen(
            [sys.executable, "-u", __file__],
            stdout=open("/tmp/claude-voice.log", "w"),
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=env
        )
        print(f"  claude-voice started (pid {proc.pid})")
        print(f"  say 'Claude' to start talking")
        print(f"  log: tail -f /tmp/claude-voice.log")
        print(f"  stop: python3 {__file__} --stop")
        return

    # Write PID
    with open(PID_FILE, 'w') as f:
        f.write(str(os.getpid()))

    def cleanup(sig=None, frame=None):
        try:
            os.unlink(PID_FILE)
        except:
            pass
        print("\n  voice listener stopped.")
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    ensure_chimes()

    # Check live_listen binary exists
    if not os.path.exists(LISTENER_BIN):
        print(f"  ERROR: {LISTENER_BIN} not found")
        print(f"  Run: swiftc -o live_listen live_listen.swift -framework Speech -framework AVFoundation -framework Foundation")
        sys.exit(1)

    print()
    print("  ╔══════════════════════════════════════╗")
    print("  ║       claude-voice is listening       ║")
    print("  ║  say 'claude' to start talking        ║")
    print("  ║  ctrl+c to stop                       ║")
    print("  ╚══════════════════════════════════════╝")
    print()

    # Start the Swift live listener as a subprocess
    proc = subprocess.Popen(
        [LISTENER_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1  # line buffered
    )

    try:
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue

            if line == "__WAKE__":
                print("  ✨ wake word — conversation started!")
                play_chime()
                continue

            if line == "__LISTENING__":
                print("  🎙️  listening... (just talk, no wake word needed)")
                play_chime()
                continue

            # This is a transcribed message
            print(f"  📝 {line}")
            send_to_claude_code(line)
            print(f"  ✅ sent\n")

    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
        cleanup()


if __name__ == "__main__":
    main()
