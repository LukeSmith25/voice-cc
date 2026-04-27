#!/usr/bin/env bash
# T1.4 — CC Stop hook → speak last assistant turn via macOS `say`.
# Detached subshell so the hook returns immediately and CC isn't blocked.
set -u

LOG=$HOME/.claude-data/voice-cc/log/hook.log
mkdir -p "$(dirname "$LOG")"
echo "[$(date -Iseconds)] on-stop fired" >> "$LOG"

[ "${VOICE_CC_ENABLED:-1}" = "1" ] || { echo "[$(date -Iseconds)] disabled" >> "$LOG"; exit 0; }

PAYLOAD=$(cat)
TEXT=$(printf '%s' "$PAYLOAD" | python3 "$HOME/.claude/voice-cc/hooks/extract.py" 2>>"$LOG")

if [ -z "$TEXT" ]; then
  echo "[$(date -Iseconds)] no spoken text" >> "$LOG"
  exit 0
fi

echo "[$(date -Iseconds)] speaking: ${TEXT:0:80}" >> "$LOG"
( printf '%s' "$TEXT" | "$HOME/.claude/voice-cc/hooks/tts.sh" </dev/null >/dev/null 2>&1 & )
exit 0
