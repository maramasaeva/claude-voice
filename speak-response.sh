#!/bin/bash
# Speak Claude's response aloud using Edge-TTS (Ava voice)
# Called as a Claude Code Stop hook

# Read hook input from stdin
HOOK_INPUT=$(cat)
TRANSCRIPT=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null)

[ -z "$TRANSCRIPT" ] && exit 0
[ ! -f "$TRANSCRIPT" ] && exit 0

# Extract the last assistant message from the transcript
TEXT=$(python3 -c "
import json, re, sys

# Read last few lines to find the last assistant message
lines = []
with open('$TRANSCRIPT', 'r') as f:
    for line in f:
        line = line.strip()
        if line:
            lines.append(line)

# Search backwards for assistant message
msg = ''
for line in reversed(lines):
    try:
        data = json.loads(line)
        role = data.get('role', '')
        if role == 'assistant':
            content = data.get('content', '')
            if isinstance(content, list):
                msg = ' '.join(b.get('text', '') for b in content if b.get('type') == 'text')
            elif isinstance(content, str):
                msg = content
            break
    except:
        continue

# Strip markdown for cleaner speech
msg = re.sub(r'\`\`\`[\s\S]*?\`\`\`', '', msg)  # code blocks
msg = re.sub(r'\`[^\`]+\`', '', msg)              # inline code
msg = re.sub(r'\*\*(.+?)\*\*', r'\1', msg)        # bold
msg = re.sub(r'\*(.+?)\*', r'\1', msg)             # italic
msg = re.sub(r'^\#{1,6}\s+', '', msg, flags=re.MULTILINE)
msg = re.sub(r'\[([^\]]+)\]\([^\)]+\)', r'\1', msg)
msg = re.sub(r'^[-\*]\s+', '', msg, flags=re.MULTILINE)
msg = re.sub(r'\n{2,}', '. ', msg)
msg = re.sub(r'\n', ' ', msg)
msg = msg.strip()

if len(msg) > 2000:
    msg = msg[:2000] + '. Check the screen for the rest.'

print(msg)
" 2>/dev/null)

[ -z "$TEXT" ] && exit 0

# Kill any previous TTS still playing
pkill -f 'afplay /tmp/claude_tts' 2>/dev/null

# Run TTS and play
TMPFILE="/tmp/claude_tts_$$.mp3"
edge-tts --voice en-US-AvaNeural --text "$TEXT" --write-media "$TMPFILE" 2>/dev/null && afplay "$TMPFILE" 2>/dev/null
rm -f "$TMPFILE"
