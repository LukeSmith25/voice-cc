# voice-cc — Spec

Voice peripheral around Claude Code CLI. Preserves all CC features (hooks, agents, MCPs, plugins, sessions, slash commands). Voice is bolted on, not wrapped around.

## Architecture

```
INPUT:  [PTT key held] → [mic] → [STT] → [keystroke inject] → CC prompt
OUTPUT: CC turn ends → [Stop hook] → [filter] → [TTS] → [afplay] → speakers
```

No daemon. No new process supervisor. STT is hotkey-triggered (Hammerspoon). TTS is hook-triggered (CC's Stop event). Both detach immediately so they never block CC.

## Runtime layout

```
~/.claude/voice-cc/hooks/        scripts referenced by settings.json
~/.claude-data/voice-cc/log/     hook.log, stt.log
~/.claude-data/voice-cc/recordings/  ephemeral mic captures (gitignored, auto-purged)
~/.hammerspoon/voice-cc.lua      PTT config, loaded from init.lua
```

Reason for the split: `~/.claude/` is sensitive (per memory). Runtime data goes to `~/.claude-data/`. Scripts loaded by CC stay under `~/.claude/`.

## Phase 1 — One-way TTS

**Scope**: Stop hook reads aloud the final summary sentence(s) of every assistant turn. Input still typed.

**Out of scope**: streaming TTS, interrupt, voice input, cloud TTS.

**Pass criteria (all must be T):**

| ID | Gate | Test | Pass condition |
|----|------|------|----------------|
| P1.G1 | Hook fires every turn | Run `claude` with 5 turns. `wc -l ~/.claude-data/voice-cc/log/hook.log` | == 5 |
| P1.G2 | Audio plays for plain-text turns | Ask Claude "what is 2+2?" | macOS speaks the answer aloud |
| P1.G3 | Code blocks not spoken verbatim | Ask Claude to print a Python hello-world | TTS does NOT speak `def`/`print`/colons; speaks ≤ 1 sentence summary or skips |
| P1.G4 | Hook does not block CC | Time `claude -p "say hi"` with hook enabled vs `VOICE_CC_ENABLED=0` | Δ ≤ 100ms |
| P1.G5 | Toggle works | `VOICE_CC_ENABLED=0 claude -p "hi"` | No audio plays, hook log line still written |
| P1.G6 | No process leaks | After 10 turns, `pgrep -f afplay \| wc -l` (5s after last turn) | == 0 |
| P1.G7 | Filter fixtures pass | `python3 hooks/extract.py < fixtures/<name>.json \| diff - fixtures/<name>.expected.txt` for all 4 fixtures | All 4 exit 0 |

## Phase 2 — Local STT input

**Scope**: Push-to-talk hotkey records mic, transcribes with faster-whisper, types result into focused terminal. User reviews and presses Enter manually.

**Out of scope**: cloud STT, auto-submit, voice activity detection, continuous listen.

**Pass criteria (all must be T):**

| ID | Gate | Test | Pass condition |
|----|------|------|----------------|
| P2.G1 | Hotkey records only while held | Press+hold PTT 2s, release, then `ls -l ~/.claude-data/voice-cc/recordings/` | Latest file >0 bytes, no recording started outside hold |
| P2.G2 | Transcription latency budget | Record 5s of speech, time from release to text-injected | ≤ 2.5s total |
| P2.G3 | Injection works in iTerm | Focus iTerm with `claude` running, hold PTT, say "hello world", release | "hello world" appears in CC prompt buffer |
| P2.G4 | Injection works in Ghostty | Same test in Ghostty | Same result |
| P2.G5 | Enter NOT auto-pressed | After P2.G3, prompt is unsubmitted | User can edit before pressing Enter |
| P2.G6 | Recordings auto-purged | After 24h, `find ~/.claude-data/voice-cc/recordings -mtime +1` | Empty |
| P2.G7 | STT accuracy on smoke set | Record fixed phrase set (10 phrases incl. "claude code", "scope-lock", "AWB"), compute WER | WER ≤ 15% |

## Phase 3 — Streaming + interrupt + cloud quality

**Scope**: Swap `say` → ElevenLabs streaming WebSocket. Add interrupt-on-PTT-down (kills in-flight TTS). Provider abstraction so `say` remains fallback.

**Out of scope**: cloud STT (defer unless P2.G7 fails), voice cloning, multi-voice routing.

**Pass criteria (all must be T):**

| ID | Gate | Test | Pass condition |
|----|------|------|----------------|
| P3.G1 | First audio chunk under budget | `time` from hook fire to first audible byte for a 1-sentence reply | ≤ 600ms |
| P3.G2 | Interrupt kills TTS | While Claude is speaking, press PTT | Audio stops within 200ms; recording starts |
| P3.G3 | Fallback to `say` on API failure | Set `ELEVENLABS_API_KEY=invalid`, run a turn | Audio still plays via `say`; log notes fallback |
| P3.G4 | Secrets not committed | `git -C ~/.claude grep -E "(ELEVENLABS\|OPENAI)_API_KEY=[A-Za-z0-9]"` | No matches |
| P3.G5 | No regressions in P1/P2 gates | Re-run all P1.G* and P2.G* with Phase 3 active | All pass |
| P3.G6 | Provider switch is one env var | `VOICE_CC_TTS=say` vs `VOICE_CC_TTS=elevenlabs` | Both work end-to-end |

## Cross-cutting non-goals

- No wake word ("hey Claude"). Push-to-talk only.
- No always-on listening. Mic only active during hold window.
- No speaking of: code blocks, file paths, tool-use blocks, `★ Insight` boxes, error stacks, JSON, markdown headers/lists.
- No persistent audio storage. Recordings auto-purge at 24h.
- No CC fork or wrapper binary. Plain hook + plain hotkey.

## Definition of Done (overall)

All P1.G*, P2.G*, P3.G* gates pass on a fresh terminal session, after a `claude` reload, with no manual setup beyond what's in `implementation.md` § Prerequisites.

## Open questions

- Voice selection: Daniel (en-GB, default `say` voice) or Alex (en-US)? **Defer to user pref after Phase 1 ships.**
- ElevenLabs voice ID: which preset? **Pick during Phase 3; not blocking earlier phases.**
- Should `★ Insight` blocks be summarized ("insight block, 3 points") or fully skipped? **Default: skipped. Revisit if Phase 1 use reveals demand.**
