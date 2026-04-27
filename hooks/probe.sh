#!/usr/bin/env bash
# T1.1 — Stop hook payload probe. Dumps stdin JSON to a known location for inspection.
# Disposable: remove from settings.json after schema is confirmed.
set -u
LOG_DIR=$HOME/.claude-data/voice-cc/log
mkdir -p "$LOG_DIR"
cat > "$LOG_DIR/last-stop-payload.json"
echo "[$(date -Iseconds)] probe captured $(wc -c < "$LOG_DIR/last-stop-payload.json" | tr -d ' ') bytes" >> "$LOG_DIR/hook.log"
exit 0
