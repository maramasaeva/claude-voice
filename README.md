# claude-voice

talk to claude code with your voice. say "claude" to start a conversation, then just keep talking.

## how it works

1. say "claude" — wake word activates conversation mode
2. hear a chime — that's your cue to talk
3. speak your message — macOS on-device speech recognition transcribes it
4. message auto-sends to the active claude code session
5. claude responds — ava (microsoft neural voice) reads the response to you
6. hear another chime — just keep talking, no wake word needed
7. after 2 minutes of silence, goes back to wake-word mode

uses apple's SFSpeechRecognizer (same engine as siri/dictation) for transcription — works at normal distance from laptop mic, no model downloads needed.

uses edge-tts with microsoft's ava neural voice for text-to-speech output.

## setup

```bash
# install python dependencies
pip3 install edge-tts numpy

# compile the swift listener
swiftc -o live_listen live_listen.swift \
  -framework Speech -framework AVFoundation -framework Foundation

# enable dictation on macos
# system settings > keyboard > dictation > on
```

## usage

```bash
# start listening (foreground)
python3 voice.py

# start in background
python3 voice.py --bg

# check the log
tail -f /tmp/claude-voice.log

# stop
python3 voice.py --stop
```

## tts hook (auto-speak responses)

to automatically hear claude's responses, copy the hook and configure it:

```bash
cp speak-response.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/speak-response.sh
```

add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/speak-response.sh",
            "timeout": 60
          }
        ]
      }
    ]
  }
}
```

## architecture

```
you (voice)
  → macOS mic
  → SFSpeechRecognizer (on-device, live_listen.swift)
  → voice.py (orchestrator)
  → AppleScript keystroke injection → Claude Code
  → Claude responds
  → edge-tts (Ava voice) → your headphones
```

## files

- `voice.py` — main orchestrator: chimes, message routing, tts
- `live_listen.swift` — wake word detection + live transcription (macOS Speech framework)
- `speak-response.sh` — claude code hook for auto-speaking responses
- `transcribe_macos.swift` — standalone file transcription utility

## requirements

- macOS 13+ (ventura or later)
- dictation enabled (system settings > keyboard > dictation)
- accessibility permission for terminal (for keystroke injection)
- bluetooth headphones work for output, laptop mic for input
- python 3.9+, edge-tts, numpy

## notes

- bluetooth headphone mics often don't work as input on macos (A2DP vs HFP mode). the laptop mic works fine at normal talking distance.
- the conversation timeout is 2 minutes of silence. configurable in `live_listen.swift` (`CONVERSATION_TIMEOUT`).
- voice is set to en-US-AvaNeural. change in `voice.py` and `speak-response.sh`.

## license

mit
