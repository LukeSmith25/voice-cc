#!/usr/bin/env bash
# Provider abstraction: pipe text on stdin → speak via $VOICE_CC_TTS (default: say).
# On elevenlabs failure, automatically falls back to `say` so you never go silent.
set -u
LOG=$HOME/.claude-data/voice-cc/log/hook.log
PID_FILE=$HOME/.claude-data/voice-cc/tts.pid

TEXT=$(cat)
[ -z "$TEXT" ] && exit 0

PROVIDER=${VOICE_CC_TTS:-say}

case "$PROVIDER" in
  elevenlabs)
    if printf '%s' "$TEXT" | python3 "$HOME/.claude/voice-cc/hooks/tts_elevenlabs.py" 2>>"$LOG"; then
      exit 0
    fi
    echo "[$(date -Iseconds)] elevenlabs failed → fallback say" >> "$LOG"
    ;;
esac

# `say` path (also the fallback)
say "$TEXT" &
SAY_PID=$!
echo "$SAY_PID" > "$PID_FILE"
wait "$SAY_PID" 2>/dev/null
rm -f "$PID_FILE"
exit 0
