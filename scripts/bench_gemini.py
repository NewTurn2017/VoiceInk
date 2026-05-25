#!/usr/bin/env python3
"""Benchmark Gemini one-call dictation cleanup latency.

Sends a recorded WAV to Gemini generateContent with the same cleanup prompt the
app will use, and measures wall-clock completion time. Tests a few Flash models,
with thinking ON (default) and OFF, to show the realistic latency we'd ship.

Usage:
  GEMINI_API_KEY=... python3 bench_gemini.py [audio.wav]
  # or put the key in /tmp/voiceink-bench/key.txt and run without the env var
  python3 bench_gemini.py --list      # list models the key can use
"""
import base64
import json
import os
import sys
import time
import urllib.request
import urllib.error

AUDIO_DEFAULT = "/tmp/voiceink-bench/bench.wav"
KEY_FILE = "/tmp/voiceink-bench/key.txt"
BASE = "https://generativelanguage.googleapis.com/v1beta"

PROMPT = """You are a dictation cleanup engine. The provided audio is a person dictating, \
usually in Korean. Transcribe what they say, then clean it up.

Rules:
- Remove filler words, repetitions, false starts, and stutters.
- If the speaker changes direction mid-sentence, keep ONLY the final intent and discard the abandoned attempt.
- Fix punctuation and capitalization.
- When the speech enumerates items or steps, format them as a bullet or numbered list.
- Keep the original language of the speech.
- Make the result clean enough to paste directly as a prompt to an AI coding agent.

Output ONLY the cleaned text. No preamble, no explanation, no markdown code fences."""

CANDIDATES = [
    "gemini-2.5-flash-lite",
    "gemini-2.5-flash",
    "gemini-3.1-flash-lite",
    "gemini-3-flash-preview",
    "gemini-3.5-flash",
]
RUNS = 3


def get_key():
    key = os.environ.get("GEMINI_API_KEY")
    if key:
        return key.strip()
    if os.path.exists(KEY_FILE):
        with open(KEY_FILE) as f:
            return f.read().strip()
    sys.exit("No API key. Set GEMINI_API_KEY env var or write it to " + KEY_FILE)


def http_json(method, url, key, body=None, timeout=120):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    req.add_header("x-goog-api-key", key)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status, json.loads(resp.read().decode())


def list_models(key):
    status, obj = http_json("GET", BASE + "/models", key)
    print(f"HTTP {status}\nModels supporting generateContent:")
    for m in obj.get("models", []):
        if "generateContent" in m.get("supportedGenerationMethods", []):
            print("  ", m["name"].replace("models/", ""))


def extract_text(obj):
    try:
        parts = obj["candidates"][0]["content"]["parts"]
        return "".join(p.get("text", "") for p in parts).strip()
    except (KeyError, IndexError):
        return ""


def run_once(model, key, b64, thinking_off):
    body = {
        "system_instruction": {"parts": [{"text": PROMPT}]},
        "contents": [{"role": "user", "parts": [{"inline_data": {"mime_type": "audio/wav", "data": b64}}]}],
    }
    if thinking_off:
        body["generationConfig"] = {"thinkingConfig": {"thinkingBudget": 0}}
    url = f"{BASE}/models/{model}:generateContent"
    t0 = time.perf_counter()
    status, obj = http_json("POST", url, key, body)
    elapsed = time.perf_counter() - t0
    return elapsed, extract_text(obj)


def bench_model(model, key, b64):
    results = {}
    for label, thinking_off in [("thinking ON ", False), ("thinking OFF", True)]:
        times, sample = [], ""
        for i in range(RUNS):
            try:
                el, text = run_once(model, key, b64, thinking_off)
            except urllib.error.HTTPError as e:
                detail = e.read().decode()[:200]
                print(f"  [{model}] {label}: HTTP {e.code} — {detail}")
                times = None
                break
            except Exception as e:
                print(f"  [{model}] {label}: ERROR {e}")
                times = None
                break
            times.append(el)
            if i == 0:
                sample = text
        if times:
            avg = sum(times) / len(times)
            best = min(times)
            tstr = ", ".join(f"{t:.2f}s" for t in times)
            print(f"  [{model}] {label}: runs=[{tstr}]  avg={avg:.2f}s  best={best:.2f}s  out={len(sample)}자")
            results[label] = (avg, best, sample)
    if results:
        # show one cleaned sample for sanity
        anylabel = next(iter(results))
        print(f"     sample({anylabel.strip()}): {results[anylabel][2][:120]!r}")
    return results


def main():
    key = get_key()
    if "--list" in sys.argv:
        list_models(key)
        return
    audio = next((a for a in sys.argv[1:] if not a.startswith("--")), AUDIO_DEFAULT)
    with open(audio, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    print(f"audio: {audio}  ({len(b64)} b64 chars)\nprompt chars: {len(PROMPT)}\nruns per config: {RUNS}\n")
    summary = {}
    for model in CANDIDATES:
        res = bench_model(model, key, b64)
        if res:
            summary[model] = res
        print()
    print("=== SUMMARY (avg / best, seconds) ===")
    for model, res in summary.items():
        for label, (avg, best, _) in res.items():
            print(f"  {model:24} {label}: avg {avg:.2f}s  best {best:.2f}s")


if __name__ == "__main__":
    main()
