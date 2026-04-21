# claude-voice

talk to claude code with your voice. say "claude" to start talking.

## how it works

1. always-on listening through your mic
2. detects wake word ("claude", "hey claude", "hi claude")
3. records your message until you stop talking
4. transcribes with whisper (local, offline)
5. auto-sends to the active claude code session

pair with the TTS hook (`speak-response.sh`) to hear responses back through your headphones.

## setup

```bash
pip3 install openai-whisper sounddevice numpy edge-tts
```

## usage

```bash
# start listening (foreground)
python3 voice.py

# start in background
python3 voice.py --bg

# stop
python3 voice.py --stop
```

## tts hook (hear responses)

copy `speak-response.sh` to `~/.claude/hooks/` and add to `~/.claude/settings.json`:

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

uses edge-tts with microsoft's Ava neural voice. change the voice in the script.

## requirements

- macOS (uses AppleScript for keystroke injection)
- microphone access
- python 3.9+
- whisper model downloads on first run (~150MB for base)

## license

mit
