#!/usr/bin/env bash
# T2.1 — Record from default mic until SIGTERM. Mono 16kHz WAV.
# Hammerspoon spawns this on PTT key-down; terminates on key-up.
set -u
OUT=$1
mkdir -p "$(dirname "$OUT")"
exec sox -d -r 16000 -c 1 -b 16 "$OUT"
