#!/usr/bin/env bash
# T3.4 — Kill any in-flight TTS playback. Called by Hammerspoon on PTT key-down.
PID_FILE=$HOME/.claude-data/voice-cc/tts.pid
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null
  fi
  rm -f "$PID_FILE"
fi
# Belt-and-suspenders: any stray say/ffplay we may have spawned
pkill -f "^say " 2>/dev/null
pkill -f "ffplay -nodisp -autoexit" 2>/dev/null
exit 0
