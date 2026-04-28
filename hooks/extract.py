#!/usr/bin/env python3
"""T1.2 — Read CC Stop hook JSON on stdin, return speakable summary of last assistant turn.

Defensive about schema: tries known field names, falls back to scanning values for path-like
strings ending in .jsonl. Tries multiple transcript message shapes (role= vs type=, content
as string vs list of blocks).
"""
import json
import re
import sys
from pathlib import Path

CODE_FENCE  = re.compile(r"```.*?```", re.DOTALL)
INLINE_CODE = re.compile(r"`[^`]+`")
HEADER      = re.compile(r"^#{1,6}\s.*$", re.MULTILINE)
LIST_ITEM   = re.compile(r"^\s*[-*]\s.*$", re.MULTILINE)
TABLE_ROW   = re.compile(r"^\s*\|.*\|\s*$", re.MULTILINE)
INSIGHT     = re.compile(r"★ Insight ─+.*?─+", re.DOTALL)
LINK        = re.compile(r"\[([^\]]+)\]\([^)]+\)")
TOOL_LINE   = re.compile(r"^(Calling tool:|<tool_use>).*$", re.MULTILINE)
SAY_TAG     = re.compile(r"<say>(.*?)</say>", re.DOTALL | re.IGNORECASE)


def find_transcript_path(payload: dict) -> Path:
    for key in ("transcript_path", "transcriptPath"):
        if key in payload and isinstance(payload[key], str):
            p = Path(payload[key]).expanduser()
            if p.exists():
                return p
    for v in payload.values():
        if isinstance(v, str) and v.endswith(".jsonl"):
            p = Path(v).expanduser()
            if p.exists():
                return p
    raise SystemExit("extract.py: no transcript path in hook payload")


def last_assistant_text(p: Path) -> str:
    last = ""
    with p.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            inner = msg.get("message", msg)
            role = inner.get("role") or msg.get("type")
            if role != "assistant":
                continue
            content = inner.get("content")
            if isinstance(content, str):
                last = content
            elif isinstance(content, list):
                last = "\n".join(
                    blk.get("text", "")
                    for blk in content
                    if isinstance(blk, dict) and blk.get("type") == "text"
                )
    return last


def filter_for_speech(text: str) -> str:
    # Pre-clean: strip both code-block and inline-code so accidental <say> mentions
    # (when Claude is explaining the syntax in chat) don't trigger marker matching.
    text = CODE_FENCE.sub("", text)
    text = INLINE_CODE.sub("", text)
    # Marker-driven path: standalone <say>...</say> is authoritative.
    matches = [m.strip() for m in SAY_TAG.findall(text) if m.strip()]
    if matches:
        return " ".join(matches)
    # Fallback: last-paragraph heuristic with the rest of the filters.
    text = INSIGHT.sub("", text)
    text = TOOL_LINE.sub("", text)
    text = TABLE_ROW.sub("", text)
    text = LINK.sub(r"\1", text)
    text = HEADER.sub("", text)
    text = LIST_ITEM.sub("", text)
    text = re.sub(r"\n\s*\n+", "\n\n", text).strip()
    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    return paragraphs[-1] if paragraphs else ""


def get_assistant_text(payload: dict) -> str:
    direct = payload.get("last_assistant_message")
    if isinstance(direct, str) and direct.strip():
        return direct
    return last_assistant_text(find_transcript_path(payload))


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        raise SystemExit(f"extract.py: stdin not JSON: {e}")
    sys.stdout.write(filter_for_speech(get_assistant_text(payload)))


if __name__ == "__main__":
    main()
