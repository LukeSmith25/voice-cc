# voice-cc

Talk to Claude Code with your voice. macOS only.

Voice as a peripheral around the Claude Code CLI — adds speech in/out without giving up hooks, MCPs, plugins, agents, slash commands, or session state. STT runs locally (faster-whisper); TTS runs via macOS `say` by default with optional ElevenLabs streaming for human-grade voice.

## Why not the cookbook examples?

[ElevenLabs cookbook](https://github.com/anthropics/claude-cookbooks/tree/main/third_party/ElevenLabs) and [bidirectional_streaming_ai_voice](https://github.com/ccappetta/bidirectional_streaming_ai_voice) wrap the Anthropic API in a custom chat loop. You get voice but you lose Claude Code — no tool use, no plugins, no hooks, no sessions, no slash commands.

voice-cc inverts that: keep the full Claude Code runtime, attach voice as IO peripherals via a Stop hook (output) and Hammerspoon push-to-talk (input). Nothing replaces Claude Code; voice is bolted on.

## How it works

```
INPUT:   PTT key held → mic → faster-whisper → cliclick → CC prompt
OUTPUT:  CC turn ends → Stop hook → filter → say or ElevenLabs → speakers
```

**Marker-driven speak**: instruct Claude (via `CLAUDE.md` rule) to wrap its end-of-turn summary in `<say>...</say>` tags. The filter speaks only that. Falls back to last-paragraph extraction if the marker is missing — so it never goes silent unexpectedly.

**Interrupt**: pressing PTT kills any in-flight TTS, so you can barge in mid-sentence.

**Fallback chain**: if ElevenLabs fails (no key, quota out, network drop), the script auto-falls back to macOS `say` so audio never goes dark.

## Install (macOS only)

```bash
git clone https://github.com/LukeSmith25/voice-cc ~/Code/voice-cc
cd ~/Code/voice-cc
./install.sh
```

The installer copies hook scripts into `~/.claude/voice-cc/hooks/` and the Hammerspoon config into `~/.hammerspoon/`, runs `pip install`, and prints the remaining manual steps (brew packages, OS permissions, settings.json snippet, optional ElevenLabs config).

## Usage

| Action | How |
|---|---|
| Talk | Hold **Ctrl+Option+Space**, speak, release |
| Listen | Every assistant turn's `<say>` content (or last paragraph) is read aloud |
| Interrupt | Press PTT during TTS playback — kills the audio instantly |
| Disable for one session | `export VOICE_CC_ENABLED=0` |
| Disable PTT | Hammerspoon menu → Disable Hammerspoon |
| Disable permanently | Comment the Stop hook entry in `~/.claude/settings.json` |

## ElevenLabs upgrade

The default `say` voice is fine for testing but robotic for sustained use. Swap to ElevenLabs for human-grade streaming TTS:

```bash
export ELEVENLABS_API_KEY="sk_..."           # https://elevenlabs.io/app/settings/api-keys
export VOICE_CC_TTS=elevenlabs
export VOICE_CC_VOICE_ID="nPczCjzI2devNBz1zQrb"   # any voice from elevenlabs.io/voice-library
```

Free tier gives 10k chars/month — enough to evaluate. Restrict the API key to **Text to Speech** scope only.

## Voice mode marker rule

Add this to your global `~/.claude/CLAUDE.md` so Claude wraps summaries appropriately:

```markdown
## Voice Mode (voice-cc)
- Wrap your end-of-turn summary in `<say>...</say>` tags. Tags appear in chat — that's intentional.
- Make the summary stand alone — no references to "this response" or surrounding context.
- Aim for one sentence, two max. Omit the marker only if the response truly has no useful spoken summary.
```

## Documentation

- [`docs/spec.md`](docs/spec.md) — phase spec with binary pass criteria for every gate
- [`docs/implementation.md`](docs/implementation.md) — task-level guide with full code

## Troubleshooting

| Symptom | First place to look |
|---|---|
| No audio for any turn | `~/.claude-data/voice-cc/log/hook.log` |
| Wrong text spoken | Run `probe.sh` instead of `on-stop.sh` to dump payload schema |
| Hotkey does nothing | Hammerspoon Console (menu → Console) |
| Empty transcription | `~/.claude-data/voice-cc/log/stt.log` + check mic permission |
| ElevenLabs silent | `tail ~/.claude-data/voice-cc/log/hook.log` for fallback notice |
| `cliclick` doesn't type | Accessibility permission not granted to cliclick |

## Architecture choices

- **Why a Stop hook, not stdout tailing?** Stop fires once per turn with a clean JSON payload pointing to the transcript. Tailing stdout means parsing terminal escape sequences and guessing turn boundaries.
- **Why local Whisper, not cloud STT?** Privacy + zero per-minute cost + ~200ms warm latency. Cloud STT (ElevenLabs Scribe, Deepgram) is a swap-in if accuracy is bad on technical jargon.
- **Why push-to-talk, not wake word?** Wake words add latency and false-trigger on dictated code. Hold-a-key matches bursty engineering work.
- **Why `<say>` markers, not always-speak?** Code, paths, tables, error stacks read terribly. Markers let Claude pick the speakable summary; falling back to last-paragraph keeps it useful even when markers are forgotten.

## License

MIT. See [LICENSE](LICENSE).

## Credits

- Inspired by the [ElevenLabs Claude cookbook](https://github.com/anthropics/claude-cookbooks/tree/main/third_party/ElevenLabs) and [bidirectional_streaming_ai_voice](https://github.com/ccappetta/bidirectional_streaming_ai_voice) — though voice-cc takes the opposite architectural approach.
