#!/usr/bin/env python3
"""ElevenLabs WebSocket streaming TTS → ffplay. Writes player PID to tts.pid for interrupt."""
import asyncio
import base64
import json
import os
import subprocess
import sys

from websockets.asyncio.client import connect

VOICE_ID = os.environ.get("VOICE_CC_VOICE_ID", "21m00Tcm4TlvDq8ikWAM")  # Rachel default
API_KEY  = os.environ.get("ELEVENLABS_API_KEY")
MODEL    = os.environ.get("VOICE_CC_TTS_MODEL", "eleven_flash_v2_5")
URI      = (
    f"wss://api.elevenlabs.io/v1/text-to-speech/{VOICE_ID}/stream-input"
    f"?model_id={MODEL}&output_format=mp3_22050_32"
)
PID_FILE = os.path.expanduser("~/.claude-data/voice-cc/tts.pid")


async def stream(text: str) -> int:
    if not API_KEY:
        sys.stderr.write("elevenlabs: ELEVENLABS_API_KEY not set\n")
        return 1
    player = subprocess.Popen(
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", "-"],
        stdin=subprocess.PIPE,
    )
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(player.pid))
        async with connect(URI, additional_headers={"xi-api-key": API_KEY}) as ws:
            await ws.send(json.dumps({
                "text": " ",
                "voice_settings": {"stability": 0.5, "similarity_boost": 0.8},
            }))
            await ws.send(json.dumps({"text": text}))
            await ws.send(json.dumps({"text": ""}))  # flush sentinel
            async for msg in ws:
                data = json.loads(msg)
                audio_b64 = data.get("audio")
                if audio_b64:
                    try:
                        player.stdin.write(base64.b64decode(audio_b64))
                        player.stdin.flush()
                    except BrokenPipeError:
                        break
                if data.get("isFinal"):
                    break
    except Exception as e:
        sys.stderr.write(f"elevenlabs: {e}\n")
        return 1
    finally:
        try: player.stdin.close()
        except Exception: pass
        try: player.wait(timeout=20)
        except subprocess.TimeoutExpired: player.kill()
        try: os.remove(PID_FILE)
        except FileNotFoundError: pass
    return 0


def main() -> None:
    text = sys.stdin.read().strip()
    if not text:
        return
    sys.exit(asyncio.run(stream(text)))


if __name__ == "__main__":
    main()
