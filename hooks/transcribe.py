#!/usr/bin/env python3
"""T2.2 — Transcribe a WAV with faster-whisper. Print text to stdout, nothing else."""
import sys
from pathlib import Path

MODEL_NAME = "base.en"  # ~140 MB, int8 on M-series ≈ realtime; bump to small.en for accuracy

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: transcribe.py <wav>")
    wav = Path(sys.argv[1])
    if not wav.exists() or wav.stat().st_size < 1024:
        return
    from faster_whisper import WhisperModel
    model = WhisperModel(MODEL_NAME, compute_type="int8")
    segments, _ = model.transcribe(str(wav), vad_filter=True, beam_size=1)
    text = " ".join(s.text.strip() for s in segments).strip()
    if text:
        sys.stdout.write(text)

if __name__ == "__main__":
    main()
