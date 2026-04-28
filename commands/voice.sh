#!/usr/bin/env bash
# /voice — toggle voice-cc TTS, check status, or stop in-flight playback.
# Usage: /voice [on|off|status|stop|toggle]
set -u

FLAG_DIR="$HOME/.claude-data/voice-cc"
FLAG_FILE="$FLAG_DIR/disabled"
INTERRUPT="$HOME/.claude/voice-cc/hooks/interrupt.sh"

mkdir -p "$FLAG_DIR"

cmd="${1:-toggle}"

state() {
  if [ -f "$FLAG_FILE" ]; then echo "off"; else echo "on"; fi
}

case "$cmd" in
  on)
    rm -f "$FLAG_FILE"
    echo "🔊 voice: on"
    ;;
  off)
    touch "$FLAG_FILE"
    [ -x "$INTERRUPT" ] && "$INTERRUPT" >/dev/null 2>&1
    echo "🔇 voice: off"
    ;;
  toggle|"")
    if [ -f "$FLAG_FILE" ]; then
      rm -f "$FLAG_FILE"
      echo "🔊 voice: on"
    else
      touch "$FLAG_FILE"
      [ -x "$INTERRUPT" ] && "$INTERRUPT" >/dev/null 2>&1
      echo "🔇 voice: off"
    fi
    ;;
  status)
    echo "voice: $(state)"
    ;;
  stop)
    if [ -x "$INTERRUPT" ]; then
      "$INTERRUPT" >/dev/null 2>&1
      echo "✋ playback interrupted (voice still $(state))"
    else
      echo "❌ interrupt script missing: $INTERRUPT"
      exit 1
    fi
    ;;
  *)
    echo "usage: /voice [on|off|toggle|status|stop]"
    exit 1
    ;;
esac
