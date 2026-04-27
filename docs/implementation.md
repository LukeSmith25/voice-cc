# voice-cc — Implementation Guide

Companion to `spec.md`. Every task has a binary pass test. Tasks within a phase run in order; later tasks assume earlier ones passed. Phase boundaries are the spec's P*.G* gates.

## Conventions

- All scripts: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`, `set -u` for bash.
- Logs append to `~/.claude-data/voice-cc/log/`. Never to `~/.claude/`.
- Detach pattern (mandatory for any background work in hooks): `( cmd </dev/null >/dev/null 2>&1 & )`.
- Order for hook scripts: write → `chmod +x` → reference in `settings.json`. Reversing causes silent permission-denied.

## Prerequisites (one-time)

| ID | Step | Pass test |
|----|------|-----------|
| PR.1 | `which say afplay` | Both resolve |
| PR.2 | `python3 --version` | ≥ 3.11 |
| PR.3 | `mkdir -p ~/.claude/voice-cc/hooks ~/.claude-data/voice-cc/{log,recordings,fixtures}` | `ls` shows all 4 dirs |
| PR.4 | Decide CC scope: user (`~/.claude/settings.json`) or per-project | Pick one; stick with it |

---

# Phase 1 — One-way TTS

## T1.1 — Schema discovery (Stop hook payload)

**Why**: Stop hook stdin schema must be confirmed before writing the parser. Don't guess field names.

**Action**: Create a probe hook, run one CC turn, inspect dump.

```bash
cat > ~/.claude/voice-cc/hooks/probe.sh <<'EOF'
#!/usr/bin/env bash
mkdir -p ~/.claude-data/voice-cc/log
cat > ~/.claude-data/voice-cc/log/last-stop-payload.json
exit 0
EOF
chmod +x ~/.claude/voice-cc/hooks/probe.sh
```

Add to `~/.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/voice-cc/hooks/probe.sh" }] }
    ]
  }
}
```

Run `claude -p "say hi"`. Then:
```bash
jq . ~/.claude-data/voice-cc/log/last-stop-payload.json
```

**Pass**: JSON file exists, contains a key whose value is a path ending in `.jsonl` and that path exists. Note the exact key name (likely `transcript_path`); plug into T1.2.

---

## T1.2 — Transcript parser + filter

**File**: `~/.claude/voice-cc/hooks/extract.py`

```python
#!/usr/bin/env python3
"""Read Stop hook JSON on stdin, extract speakable summary from last assistant turn."""
import json, re, sys
from pathlib import Path

CODE_FENCE   = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE  = re.compile(r"`[^`]+`")
HEADER       = re.compile(r"^#{1,6}\s.*$", re.MULTILINE)
LIST_ITEM    = re.compile(r"^\s*[-*]\s.*$", re.MULTILINE)
TABLE_ROW    = re.compile(r"^\s*\|.*\|\s*$", re.MULTILINE)
INSIGHT      = re.compile(r"★ Insight ─+.*?─+", re.DOTALL)
LINK         = re.compile(r"\[([^\]]+)\]\([^)]+\)")
TOOL_LINE    = re.compile(r"^(Calling tool:|<tool_use>).*$", re.MULTILINE)

def find_transcript_path(payload):
    for key in ("transcript_path", "transcriptPath"):
        if key in payload:
            return Path(payload[key]).expanduser()
    for v in payload.values():
        if isinstance(v, str) and v.endswith(".jsonl") and Path(v).expanduser().exists():
            return Path(v).expanduser()
    raise SystemExit("no transcript path in payload")

def last_assistant_text(p: Path) -> str:
    last = ""
    with p.open() as f:
        for line in f:
            try: msg = json.loads(line)
            except json.JSONDecodeError: continue
            inner = msg.get("message", msg)
            if inner.get("role") != "assistant" and msg.get("type") != "assistant":
                continue
            content = inner.get("content")
            if isinstance(content, str):
                last = content
            elif isinstance(content, list):
                last = "\n".join(b.get("text", "") for b in content if b.get("type") == "text")
    return last

def filter_for_speech(text: str) -> str:
    text = INSIGHT.sub("", text)
    text = CODE_FENCE.sub("", text)
    text = TOOL_LINE.sub("", text)
    text = TABLE_ROW.sub("", text)
    text = LINK.sub(r"\1", text)
    text = INLINE_CODE.sub("", text)
    text = HEADER.sub("", text)
    text = LIST_ITEM.sub("", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text).strip()
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    return paragraphs[-1] if paragraphs else ""

def main():
    payload = json.load(sys.stdin)
    raw = last_assistant_text(find_transcript_path(payload))
    sys.stdout.write(filter_for_speech(raw))

if __name__ == "__main__":
    main()
```

**Pass**: T1.3 fixture suite passes (next task).

---

## T1.3 — Filter fixtures

**Files**: `~/.claude-data/voice-cc/fixtures/{name}.json` + `{name}.expected.txt` for 4 cases.

Each fixture is a fake CC transcript (one JSONL line) wrapped in a Stop hook payload. Use this script to generate them:

```bash
mkdir -p ~/.claude-data/voice-cc/fixtures
cd ~/.claude-data/voice-cc/fixtures

make_fixture() {
  local name=$1; local assistant_text=$2; local expected=$3
  local jsonl=$(mktemp)
  printf '%s\n' "$(jq -n --arg t "$assistant_text" '{role:"assistant",content:[{type:"text",text:$t}]}')" > "$jsonl"
  jq -n --arg p "$jsonl" '{transcript_path:$p, session_id:"test"}' > "$name.json"
  printf '%s' "$expected" > "$name.expected.txt"
}

make_fixture pure-text \
  "The answer is 4." \
  "The answer is 4."

make_fixture with-code \
  "Here is the function:

\`\`\`python
def hello(): return 'hi'
\`\`\`

That returns the string hi." \
  "That returns the string hi."

make_fixture with-insight \
  "★ Insight ─────────
- thing one
- thing two
─────────────────────

Done. Tests pass." \
  "Done. Tests pass."

make_fixture with-table \
  "| ID | Gate |
|---|---|
| G1 | foo |

Summary sentence here." \
  "Summary sentence here."
```

**Test**:
```bash
for f in ~/.claude-data/voice-cc/fixtures/*.json; do
  name=$(basename "$f" .json)
  expected=~/.claude-data/voice-cc/fixtures/$name.expected.txt
  actual=$(python3 ~/.claude/voice-cc/hooks/extract.py < "$f")
  if [ "$actual" = "$(cat "$expected")" ]; then
    echo "PASS $name"
  else
    echo "FAIL $name"; diff <(echo "$actual") "$expected"
  fi
done
```

**Pass (P1.G7)**: All 4 print `PASS`.

---

## T1.4 — Stop hook script

**File**: `~/.claude/voice-cc/hooks/on-stop.sh`

```bash
#!/usr/bin/env bash
set -u
LOG=$HOME/.claude-data/voice-cc/log/hook.log
mkdir -p "$(dirname "$LOG")"
echo "[$(date -Iseconds)] stop hook fired" >> "$LOG"

[ "${VOICE_CC_ENABLED:-1}" = "1" ] || exit 0

PAYLOAD=$(cat)
TEXT=$(printf '%s' "$PAYLOAD" | python3 "$HOME/.claude/voice-cc/hooks/extract.py" 2>>"$LOG")

if [ -z "$TEXT" ]; then
  echo "[$(date -Iseconds)] no spoken text" >> "$LOG"
  exit 0
fi

# Detach so hook returns immediately
( say "$TEXT" </dev/null >/dev/null 2>&1 & )
exit 0
```

```bash
chmod +x ~/.claude/voice-cc/hooks/on-stop.sh
```

**Pass**:
- Standalone: `echo '{"transcript_path":"/some/file.jsonl"}' | ~/.claude/voice-cc/hooks/on-stop.sh; echo $?` → exits 0 within 100ms (it'll log "no spoken text" because the path is fake; that's fine).
- Smoke: `printf '%s' "$(cat ~/.claude-data/voice-cc/fixtures/pure-text.json)" | ~/.claude/voice-cc/hooks/on-stop.sh` → speaks "The answer is 4." aloud.

---

## T1.5 — Replace probe with real hook

Edit `~/.claude/settings.json`:
```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "$HOME/.claude/voice-cc/hooks/on-stop.sh" }] }
    ]
  }
}
```

**Pass**: in a fresh terminal, run `claude -p "what is 2 plus 2"`. macOS speaks the answer. `tail -1 ~/.claude-data/voice-cc/log/hook.log` shows a fresh entry.

---

## T1.6 — Latency check

**Test**:
```bash
time VOICE_CC_ENABLED=0 claude -p "say hi"
time VOICE_CC_ENABLED=1 claude -p "say hi"
```

**Pass (P1.G4)**: Δ wall-clock ≤ 100ms.

---

## T1.7 — Process-leak check

**Test**: Run 10 turns, wait 5s after last:
```bash
for i in 1 2 3 4 5 6 7 8 9 10; do claude -p "very short reply $i"; done
sleep 5
pgrep -f afplay | wc -l   # afplay not used by `say` directly
pgrep -f "say " | wc -l
```

**Pass (P1.G6)**: Both counts == 0.

---

## Phase 1 acceptance

Run all P1.G1–P1.G7 from `spec.md`. All T. Move to Phase 2.

---

# Phase 2 — Local STT input

## T2.0 — Prereqs

| ID | Step | Pass |
|----|------|------|
| T2.0.a | `brew install hammerspoon sox cliclick ffmpeg` | All four installed |
| T2.0.b | Open Hammerspoon, grant Accessibility permission in System Settings → Privacy & Security | Hammerspoon menu icon appears |
| T2.0.c | `cliclick t:hello && pbpaste` (after focusing a text field) | "hello" gets typed |
| T2.0.d | `pip3 install --user faster-whisper` | `python3 -c "from faster_whisper import WhisperModel; print('ok')"` prints `ok` |
| T2.0.e | Grant Microphone permission to Hammerspoon and your terminal | System Settings shows both as enabled |

---

## T2.1 — Mic recorder

**File**: `~/.claude/voice-cc/hooks/record.sh`

```bash
#!/usr/bin/env bash
# Record from default mic until SIGTERM. Output mono 16kHz WAV.
OUT=$1
mkdir -p "$(dirname "$OUT")"
exec sox -d -r 16000 -c 1 -b 16 "$OUT"
```

```bash
chmod +x ~/.claude/voice-cc/hooks/record.sh
```

**Test**: `~/.claude/voice-cc/hooks/record.sh /tmp/test.wav &` say "hello hello hello", `kill %1`, `ls -l /tmp/test.wav`.

**Pass**: file is >50 KB and `afplay /tmp/test.wav` plays your voice.

---

## T2.2 — Whisper transcriber

**File**: `~/.claude/voice-cc/hooks/transcribe.py`

```python
#!/usr/bin/env python3
"""Transcribe a WAV file with faster-whisper. Print text to stdout."""
import sys
from pathlib import Path
from faster_whisper import WhisperModel

MODEL_NAME = "base.en"  # ~140 MB, M-series ~0.5x realtime int8

def main():
    wav = Path(sys.argv[1])
    if not wav.exists() or wav.stat().st_size < 1024:
        return
    model = WhisperModel(MODEL_NAME, compute_type="int8")
    segments, _ = model.transcribe(str(wav), vad_filter=True, beam_size=1)
    text = " ".join(s.text.strip() for s in segments).strip()
    if text:
        sys.stdout.write(text)

if __name__ == "__main__":
    main()
```

**Test**:
```bash
time python3 ~/.claude/voice-cc/hooks/transcribe.py /tmp/test.wav
```

**Pass**: prints transcript matching the recorded speech (≥ 80% word match by eyeball).

**Latency note**: cold model load ~1.5–2s on M-series. Phase 2 gate P2.G2 measures the *5th consecutive* invocation (warm); if even warm misses 2.5s, daemonize via T2.6-opt.

---

## T2.3 — Keystroke injector

**File**: `~/.claude/voice-cc/hooks/inject.sh`

```bash
#!/usr/bin/env bash
TEXT=$1
[ -n "$TEXT" ] || exit 0
# Type at current cursor. Do NOT press Enter.
cliclick t:"$TEXT"
```

```bash
chmod +x ~/.claude/voice-cc/hooks/inject.sh
```

**Test (manual)**: Focus iTerm with `claude` running. `~/.claude/voice-cc/hooks/inject.sh "hello world"`.

**Pass (P2.G3)**: "hello world" appears in CC prompt within 300ms; no Enter pressed.

---

## T2.4 — Hammerspoon push-to-talk

**File**: `~/.hammerspoon/voice-cc.lua`

```lua
local SCRIPTS = os.getenv("HOME") .. "/.claude/voice-cc/hooks"
local DATA    = os.getenv("HOME") .. "/.claude-data/voice-cc"
local PTT_KEY = "f19"  -- map your hardware key to F19, or change here

local recordTask = nil
local recordingPath = nil

local function startRecord()
  if recordTask then return end
  recordingPath = string.format("%s/recordings/%s.wav", DATA, os.date("%Y%m%dT%H%M%S"))
  recordTask = hs.task.new("/bin/bash", nil, {SCRIPTS .. "/record.sh", recordingPath})
  recordTask:start()
  hs.alert.closeAll()
  hs.alert.show("● rec", 0.3)
end

local function stopRecord()
  if not recordTask then return end
  recordTask:terminate()
  recordTask = nil
  local wav = recordingPath
  recordingPath = nil
  if not wav then return end
  hs.task.new("/bin/bash", function(_, stdout, _)
    local text = (stdout or ""):gsub("^%s+",""):gsub("%s+$","")
    if #text == 0 then return end
    hs.task.new("/bin/bash", nil, {SCRIPTS .. "/inject.sh", text}):start()
  end, {"-c", "python3 " .. SCRIPTS .. "/transcribe.py " .. wav}):start()
end

hs.hotkey.bind({}, PTT_KEY, startRecord, stopRecord)
```

In `~/.hammerspoon/init.lua` (create if missing), add:
```lua
require("voice-cc")
```

Reload Hammerspoon (menu → Reload Config).

**Test**: focus iTerm with `claude` running. Hold F19 (or your remapped key), say "test message", release.

**Pass (P2.G3 / P2.G4)**: "test message" (or close approximation) appears in CC prompt buffer in iTerm AND Ghostty. No Enter pressed.

---

## T2.5 — Auto-purge old recordings

**File**: `~/.claude/voice-cc/hooks/purge.sh`

```bash
#!/usr/bin/env bash
find ~/.claude-data/voice-cc/recordings -name '*.wav' -mtime +1 -delete 2>/dev/null
```

```bash
chmod +x ~/.claude/voice-cc/hooks/purge.sh
```

Add to crontab (`crontab -e`):
```
0 4 * * * $HOME/.claude/voice-cc/hooks/purge.sh
```

**Pass (P2.G6)**: Touch a fake old wav, run purge manually:
```bash
touch -t 202001010000 ~/.claude-data/voice-cc/recordings/old.wav
~/.claude/voice-cc/hooks/purge.sh
ls ~/.claude-data/voice-cc/recordings/old.wav 2>&1   # should say no such file
```

---

## T2.6 — STT accuracy smoke test

**File**: `~/.claude-data/voice-cc/fixtures/stt-phrases.txt`

```
claude code
scope lock
agentic workbench
typescript
phase one ships first
say hello world
list pull requests
disable voice for this session
hammerspoon push to talk
fast whisper base english
```

**Test**: record each phrase via PTT, compare transcript to expected. Compute WER:
```bash
# WER ≈ (substitutions + deletions + insertions) / reference word count
# Manual eyeball is fine for 10 phrases.
```

**Pass (P2.G7)**: ≥ 8/10 phrases transcribed with ≤ 1 word error each (effective WER ≤ 15%).

**If FAIL**: switch model to `small.en` in transcribe.py (~470 MB, slower, more accurate). If still fails, escalate to ElevenLabs Scribe in Phase 3.

---

## T2.6-opt — Daemonize transcriber (only if P2.G2 fails warm)

**Trigger**: warm transcription > 2.5s. Skip otherwise.

**Approach**: small Unix-socket daemon keeps model loaded. `transcribe.sh` becomes a thin client.

Sketch (build only if needed):

```python
# ~/.claude/voice-cc/hooks/transcribe-daemon.py
# Listens on $HOME/.claude-data/voice-cc/transcribe.sock
# Reads WAV path, writes transcript, keeps model in memory.
```

Started via `launchd` user agent. Defer file content until needed.

---

## Phase 2 acceptance

All P2.G1–P2.G7. Move to Phase 3.

---

# Phase 3 — Streaming + interrupt + cloud quality

## T3.1 — Secrets

```bash
# Append to ~/.zshrc (or wherever you load env)
export ELEVENLABS_API_KEY="sk_..."
export VOICE_CC_VOICE_ID="21m00Tcm4TlvDq8ikWAM"   # or your chosen voice
export VOICE_CC_TTS=elevenlabs
```

```bash
pip3 install --user websockets
```

**Pass (P3.G4)**: `git -C ~/.claude grep -E "(ELEVENLABS|OPENAI)_API_KEY=[A-Za-z0-9]"` prints nothing. Add `voice-cc/log` and `recordings` to `.gitignore` if `~/.claude` is a repo.

---

## T3.2 — Provider abstraction

**File**: `~/.claude/voice-cc/hooks/tts.sh`

```bash
#!/usr/bin/env bash
set -u
LOG=$HOME/.claude-data/voice-cc/log/hook.log
TEXT=$(cat)
[ -z "$TEXT" ] && exit 0
PROVIDER=${VOICE_CC_TTS:-say}

case "$PROVIDER" in
  elevenlabs)
    if printf '%s' "$TEXT" | python3 "$HOME/.claude/voice-cc/hooks/tts_elevenlabs.py"; then
      exit 0
    fi
    echo "[$(date -Iseconds)] elevenlabs failed → fallback say" >> "$LOG"
    ;;
esac
say "$TEXT"
```

```bash
chmod +x ~/.claude/voice-cc/hooks/tts.sh
```

Update `on-stop.sh` to pipe to tts.sh instead of calling `say`:
```bash
# replace the line:  ( say "$TEXT" </dev/null >/dev/null 2>&1 & )
# with:
( printf '%s' "$TEXT" | $HOME/.claude/voice-cc/hooks/tts.sh </dev/null >/dev/null 2>&1 & )
```

**Pass (P3.G6)**:
- `VOICE_CC_TTS=say claude -p "hi"` → speaks via macOS voice
- `VOICE_CC_TTS=elevenlabs claude -p "hi"` → speaks via ElevenLabs voice

---

## T3.3 — ElevenLabs streaming TTS

**File**: `~/.claude/voice-cc/hooks/tts_elevenlabs.py`

```python
#!/usr/bin/env python3
"""ElevenLabs WebSocket streaming → ffplay. Records PID for interrupt."""
import asyncio, base64, json, os, subprocess, sys
import websockets

VOICE_ID = os.environ.get("VOICE_CC_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")
API_KEY  = os.environ.get("ELEVENLABS_API_KEY")
MODEL    = "eleven_turbo_v2_5"
URI      = (f"wss://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}/stream-input"
            f"?model_id={MODEL}&output_format=mp3_22050_32")
PID_FILE = os.path.expanduser("~/.claude-data/voice-cc/tts.pid")

async def stream(text: str) -> int:
    if not API_KEY:
        return 1
    player = subprocess.Popen(
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-"],
        stdin=subprocess.PIPE,
    )
    with open(PID_FILE, "w") as f:
        f.write(str(player.pid))
    try:
        async with websockets.connect(URI, additional_headers={"xi-api-key": API_KEY}) as ws:
            await ws.send(json.dumps({
                "text": " ",
                "voice_settings": {"stability": 0.5, "similarity_boost": 0.8},
            }))
            await ws.send(json.dumps({"text": text}))
            await ws.send(json.dumps({"text": ""}))  # flush sentinel
            async for msg in ws:
                data = json.loads(msg)
                if data.get("audio"):
                    try:
                        player.stdin.write(base64.b64decode(data["audio"]))
                        player.stdin.flush()
                    except BrokenPipeError:
                        return 0
                if data.get("isFinal"):
                    break
    finally:
        try: player.stdin.close()
        except Exception: pass
        try: player.wait(timeout=10)
        except subprocess.TimeoutExpired: player.kill()
        try: os.remove(PID_FILE)
        except FileNotFoundError: pass
    return 0

def main():
    text = sys.stdin.read().strip()
    if not text:
        return
    sys.exit(asyncio.run(stream(text)))

if __name__ == "__main__":
    main()
```

**Test**: `printf 'Phase three is alive.' | VOICE_CC_TTS=elevenlabs ~/.claude/voice-cc/hooks/tts.sh`.

**Pass (P3.G1)**: First audible byte ≤ 600ms after invocation. Measure with stopwatch or:
```bash
time (printf 'one two three four five.' | VOICE_CC_TTS=elevenlabs ~/.claude/voice-cc/hooks/tts.sh) 2>&1 | head
```
(audio starts before command returns).

---

## T3.4 — Interrupt

**File**: `~/.claude/voice-cc/hooks/interrupt.sh`

```bash
#!/usr/bin/env bash
PID_FILE=$HOME/.claude-data/voice-cc/tts.pid
[ -f "$PID_FILE" ] || exit 0
PID=$(cat "$PID_FILE" 2>/dev/null)
if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null
fi
# Belt-and-suspenders: kill any stray ffplay we spawned
pkill -f "ffplay -nodisp -autoexit" 2>/dev/null
rm -f "$PID_FILE"
```

```bash
chmod +x ~/.claude/voice-cc/hooks/interrupt.sh
```

Wire into Hammerspoon — update `voice-cc.lua` `startRecord`:

```lua
local function startRecord()
  if recordTask then return end
  -- INTERRUPT: kill any in-flight TTS first
  hs.task.new("/bin/bash", nil, {SCRIPTS .. "/interrupt.sh"}):start()
  recordingPath = string.format("%s/recordings/%s.wav", DATA, os.date("%Y%m%dT%H%M%S"))
  recordTask = hs.task.new("/bin/bash", nil, {SCRIPTS .. "/record.sh", recordingPath})
  recordTask:start()
  hs.alert.closeAll(); hs.alert.show("● rec", 0.3)
end
```

Reload Hammerspoon.

**Test**: Trigger a long Claude reply ("recite the alphabet slowly"). Mid-speech, press PTT.

**Pass (P3.G2)**: ffplay stops within 200ms; mic recording begins.

---

## T3.5 — Fallback chain

**Test**:
```bash
ELEVENLABS_API_KEY=invalid VOICE_CC_TTS=elevenlabs printf 'fallback test' | ~/.claude/voice-cc/hooks/tts.sh
```

**Pass (P3.G3)**: Hear `say` voice within 2s. `tail -1 ~/.claude-data/voice-cc/log/hook.log` shows `elevenlabs failed → fallback say`.

---

## T3.6 — Regression sweep

Re-run all P1.G* and P2.G* gates with `VOICE_CC_TTS=elevenlabs` set.

**Pass (P3.G5)**: All previous gates still T.

---

## Phase 3 acceptance

All P3.G1–P3.G6. Project DoD met.

---

# Operational notes

## Disabling temporarily

```bash
export VOICE_CC_ENABLED=0   # mute TTS for the session
# or comment the Stop hook entry in settings.json for permanent off
```

PTT is independent of `VOICE_CC_ENABLED`. To disable PTT: Hammerspoon menu → Reload Config after commenting the `require("voice-cc")` line.

## Logs to check when something breaks

| Symptom | First file to read |
|---------|--------------------|
| No audio for any turn | `~/.claude-data/voice-cc/log/hook.log` (last 20 lines) |
| Audio for some turns only | Same file; correlate "no spoken text" entries with offending turns |
| Wrong text spoken | `~/.claude-data/voice-cc/log/last-stop-payload.json` (re-enable probe) |
| Hotkey does nothing | Hammerspoon Console (menu → Console) |
| Transcription empty | `~/.claude-data/voice-cc/log/stt.log` |
| ElevenLabs failing silently | Add `set -x` to `tts.sh` temporarily |

## Files inventory (after all phases)

```
~/.claude/voice-cc/hooks/
  on-stop.sh
  extract.py
  tts.sh
  tts_elevenlabs.py
  record.sh
  transcribe.py
  inject.sh
  interrupt.sh
  purge.sh

~/.hammerspoon/voice-cc.lua

~/.claude-data/voice-cc/
  log/{hook,stt}.log
  recordings/*.wav (purged daily)
  fixtures/{*.json, *.expected.txt, stt-phrases.txt}
```

## When to revisit

- Phase 1 filter starts missing important info → switch to marker-driven (`<say>...</say>` blocks Claude emits explicitly).
- WER on technical jargon stays > 15% on `small.en` → ElevenLabs Scribe (cloud STT) as Phase 3.5.
- ffplay buffer underruns / chunk artifacts → swap to `pyaudio`-based player with explicit ring buffer.
