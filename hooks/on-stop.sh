#!/usr/bin/env bash
# T1.4 — CC Stop hook → speak last assistant turn via macOS `say`.
# Detached subshell so the hook returns immediately and CC isn't blocked.
set -u

# Load voice-cc env from ~/.zshrc if not already in process env. Lets users
# change ELEVENLABS_API_KEY / VOICE_CC_TTS / VOICE_CC_VOICE_ID without
# restarting claude. Cherry-picks only voice-cc-related exports (safe in bash).
if [ -z "${VOICE_CC_TTS:-}" ] && [ -f "$HOME/.zshrc" ]; then
  eval "$(grep -E '^export (ELEVENLABS|VOICE_CC)' "$HOME/.zshrc" 2>/dev/null)" || true
fi

LOG=$HOME/.claude-data/voice-cc/log/hook.log
mkdir -p "$(dirname "$LOG")"
echo "[$(date -Iseconds)] on-stop fired" >> "$LOG"

[ "${VOICE_CC_ENABLED:-1}" = "1" ] || { echo "[$(date -Iseconds)] disabled (env)" >> "$LOG"; exit 0; }
[ ! -f "$HOME/.claude-data/voice-cc/disabled" ] || { echo "[$(date -Iseconds)] disabled (flag)" >> "$LOG"; exit 0; }

PAYLOAD=$(cat)
TEXT=$(printf '%s' "$PAYLOAD" | python3 "$HOME/.claude/voice-cc/hooks/extract.py" 2>>"$LOG")

if [ -z "$TEXT" ]; then
  echo "[$(date -Iseconds)] no spoken text" >> "$LOG"
  exit 0
fi

echo "[$(date -Iseconds)] speaking: ${TEXT:0:80}" >> "$LOG"
# Group the pipeline so </dev/null applies to the group's stdin (which printf
# ignores), not to tts.sh's stdin (which must come from the pipe).
( { printf '%s' "$TEXT" | "$HOME/.claude/voice-cc/hooks/tts.sh"; } </dev/null >/dev/null 2>&1 & )
exit 0
