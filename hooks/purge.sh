#!/usr/bin/env bash
# T2.5 — Purge recordings older than 1 day. Add to crontab: 0 4 * * *
find "$HOME/.claude-data/voice-cc/recordings" -name '*.wav' -mtime +1 -delete 2>/dev/null
exit 0
