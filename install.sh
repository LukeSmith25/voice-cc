#!/usr/bin/env bash
# voice-cc installer. Idempotent. macOS only.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
HOOKS_DIR=$HOME/.claude/voice-cc/hooks
DATA_DIR=$HOME/.claude-data/voice-cc
HS_DIR=$HOME/.hammerspoon

echo "==> Creating directories"
mkdir -p "$HOOKS_DIR" "$DATA_DIR"/{log,recordings,fixtures} "$HS_DIR"

echo "==> Installing hook scripts → $HOOKS_DIR"
cp "$REPO_DIR"/hooks/*.sh "$HOOKS_DIR/"
cp "$REPO_DIR"/hooks/*.py "$HOOKS_DIR/"
chmod +x "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.py

echo "==> Installing Hammerspoon config → $HS_DIR"
cp "$REPO_DIR"/hammerspoon/voice-cc.lua "$HS_DIR/"
if [ ! -f "$HS_DIR/init.lua" ]; then
  printf 'hs.ipc.cliInstall()\nrequire("voice-cc")\n' > "$HS_DIR/init.lua"
elif ! grep -q 'require("voice-cc")' "$HS_DIR/init.lua"; then
  printf '\nrequire("voice-cc")\n' >> "$HS_DIR/init.lua"
fi

echo "==> Installing Python deps (faster-whisper, websockets)"
pip3 install --user faster-whisper websockets

cat <<'EOF'

✓ Files installed:
   ~/.claude/voice-cc/hooks/
   ~/.hammerspoon/voice-cc.lua
   ~/.hammerspoon/init.lua (require added)

==> Manual steps still required:

1. Install brew packages:
     brew install --cask hammerspoon
     brew install cliclick sox ffmpeg

2. Open Hammerspoon once. Grant Accessibility permission when prompted.

3. Grant permissions in System Settings → Privacy & Security:
     - Accessibility:  Hammerspoon, cliclick
     - Microphone:     Hammerspoon, your terminal app (iTerm/Ghostty)

4. Add the Stop hook to ~/.claude/settings.json — merge into existing `hooks.Stop`:

     "Stop": [
       {
         "matcher": "*",
         "hooks": [
           {
             "type": "command",
             "command": "$HOME/.claude/voice-cc/hooks/on-stop.sh",
             "timeout": 5
           }
         ]
       }
     ]

5. (Recommended) Add Voice Mode rule to your global ~/.claude/CLAUDE.md:

     ## Voice Mode (voice-cc)
     - Wrap your end-of-turn summary in `<say>...</say>` tags.
     - Make the summary stand alone — no references to "this response".
     - Aim for one sentence. Omit if no useful audio summary.

6. (Optional) ElevenLabs streaming TTS — add to ~/.zshrc and reload:

     export ELEVENLABS_API_KEY="sk_..."
     export VOICE_CC_TTS=elevenlabs
     export VOICE_CC_VOICE_ID="nPczCjzI2devNBz1zQrb"   # or any voice ID

Open a new terminal, run `claude`, and try Ctrl+Option+Space.

EOF
