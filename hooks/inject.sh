#!/usr/bin/env bash
# T2.3 — Type transcribed text into focused window. No Enter — user reviews.
set -u
TEXT=$1
[ -n "$TEXT" ] || exit 0
exec cliclick t:"$TEXT"
