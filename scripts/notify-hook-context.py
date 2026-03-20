#!/usr/bin/env python3
"""Collect hook notify context from hook JSON and transcript data."""

from __future__ import annotations

import json
import os
import re
import sys
from typing import Any

DEFAULT_BODY = sys.argv[1] if len(sys.argv) > 1 else "Task completed"
MODE = (sys.argv[2] if len(sys.argv) > 2 else "").strip().lower()
MAX_TRANSCRIPT_BYTES = 256 * 1024
MAX_QUERY_CHARS = 280
MAX_SUMMARY_CHARS = 8000


def truncate(text: str, limit: int) -> str:
    if len(text) <= limit:
        return text
    return text[: limit - 1].rstrip() + "..."


def clean_user_text(raw: str | None) -> str | None:
    if not isinstance(raw, str):
        return None

    text = raw.strip()
    if not text:
        return None

    match = re.fullmatch(r"<user_query>\s*(.*?)\s*</user_query>", text, flags=re.S)
    if match:
        text = match.group(1)

    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return None

    return truncate(text, MAX_QUERY_CHARS)


def clean_assistant_text(raw: str | None) -> str | None:
    if not isinstance(raw, str):
        return None

    text = raw.strip()
    if not text:
        return None

    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    if not text:
        return None

    return truncate(text, MAX_SUMMARY_CHARS)


def clean_raw_json(raw: str | None) -> str | None:
    if not isinstance(raw, str):
        return None

    text = raw.strip()
    if not text:
        return None

    return text


def read_transcript_tail(path: str | None) -> str:
    if not path:
        return ""

    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            read_size = min(size, MAX_TRANSCRIPT_BYTES)
            handle.seek(size - read_size)
            data = handle.read(read_size)
    except OSError:
        return ""

    if read_size < size:
        first_newline = data.find(b"\n")
        if first_newline != -1:
            data = data[first_newline + 1 :]

    return data.decode("utf-8", errors="replace")


def extract_user_text_from_content(content: Any) -> str | None:
    if isinstance(content, str):
        return clean_user_text(content)

    if not isinstance(content, list):
        return None

    parts: list[str] = []
    for item in content:
        if isinstance(item, str):
            text = clean_user_text(item)
            if text:
                parts.append(text)
            continue

        if not isinstance(item, dict):
            continue

        if item.get("type") == "tool_result":
            continue

        text = clean_user_text(item.get("text"))
        if text:
            parts.append(text)
            continue

        nested = clean_user_text(item.get("content"))
        if nested:
            parts.append(nested)

    if not parts:
        return None

    return clean_user_text(" ".join(parts))


def extract_assistant_text_from_content(content: Any) -> str | None:
    if isinstance(content, str):
        return clean_assistant_text(content)

    if not isinstance(content, list):
        return None

    parts: list[str] = []
    for item in content:
        if isinstance(item, str):
            text = clean_assistant_text(item)
            if text:
                parts.append(text)
            continue

        if not isinstance(item, dict):
            continue

        if item.get("type") != "text":
            continue

        text = clean_assistant_text(item.get("text"))
        if text:
            parts.append(text)

    if not parts:
        return None

    return clean_assistant_text("\n\n".join(parts))


def extract_user_prompt(entry: dict[str, Any]) -> str | None:
    last_prompt = clean_user_text(entry.get("lastPrompt"))
    if last_prompt:
        return last_prompt

    if entry.get("role") == "user":
        message = entry.get("message")
    elif entry.get("type") == "user":
        message = entry.get("message")
    else:
        return None

    if isinstance(message, dict):
        return extract_user_text_from_content(message.get("content"))
    return extract_user_text_from_content(message)


def extract_assistant_summary(entry: dict[str, Any]) -> str | None:
    if entry.get("role") == "assistant":
        message = entry.get("message")
    elif entry.get("type") == "assistant":
        message = entry.get("message")
        if isinstance(message, dict):
            role = message.get("role")
            if role not in (None, "assistant"):
                return None
    else:
        return None

    if isinstance(message, dict):
        return extract_assistant_text_from_content(message.get("content"))
    return extract_assistant_text_from_content(message)


def collect_transcript_context(transcript_path: str | None) -> dict[str, str]:
    text = read_transcript_tail(transcript_path)
    if not text:
        return {}

    request: str | None = None
    summary: str | None = None
    raw_response_json: str | None = None

    for raw_line in reversed(text.splitlines()):
        line = raw_line.strip()
        if not line:
            continue

        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        if summary is None:
            assistant = extract_assistant_summary(entry)
            if assistant:
                summary = assistant
                raw_response_json = clean_raw_json(raw_line)

        if request is None:
            request = extract_user_prompt(entry)

        if request is not None and summary is not None:
            break

    out: dict[str, str] = {}
    if request:
        out["request"] = request
    if summary:
        out["summary"] = summary
    if raw_response_json:
        out["raw_response_json"] = raw_response_json
    return out


def build_user_query_body(payload: dict[str, Any]) -> str:
    context = collect_transcript_context(payload.get("transcript_path"))
    query = context.get("request")
    if not query:
        return DEFAULT_BODY

    status = str(payload.get("status") or "").strip().lower()
    prefix = "Finished"
    if status in {"aborted", "cancelled", "canceled"}:
        prefix = "Stopped"
    elif status in {"error", "failed", "failure"}:
        prefix = "Stopped with error"

    return f"{prefix}: {query}"


def build_response_payload(payload: dict[str, Any]) -> dict[str, str]:
    context = collect_transcript_context(payload.get("transcript_path"))
    summary = context.get("summary")
    request = context.get("request")

    body = summary or request or DEFAULT_BODY

    out: dict[str, str] = {"body": body}
    if summary:
        out["summary"] = summary
    if request:
        out["request"] = request
    raw_response_json = context.get("raw_response_json")
    if raw_response_json:
        out["raw_response_json"] = raw_response_json
    return out


def main() -> int:
    if MODE not in {"latest-user-query", "latest-user", "query", "final-response", "response", "agent-response"}:
        print(DEFAULT_BODY, end="")
        return 0

    raw = sys.stdin.read()
    if not raw.strip():
        print(DEFAULT_BODY, end="")
        return 0

    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        print(DEFAULT_BODY, end="")
        return 0

    if MODE in {"final-response", "response", "agent-response"}:
        print(json.dumps(build_response_payload(payload), ensure_ascii=False), end="")
        return 0

    print(build_user_query_body(payload), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
