#!/usr/bin/env python
"""reread-by-tool.py - what re-reading tool results costs, by tool, with images priced right.

A tool result that lands at step t of a session is carried - and paid for as
cache read - on every step after it. This script sums that per tool
(Read / Bash / Grep ...) so you can see which tool you are paying rent on.

Re-read arithmetic from fomoles/claude-code-spend, thanks (tokens x steps ahead x
cache-read rate). Images are priced by pixels: an image result is a base64 blob in the transcript,
and `len/4` turns a 2576x1450 JPEG into ~100k "tokens" when the model is billed
(width x height) / 750 = ~5k for it. Measured 10.09.2026: the naive method
overstated our corpus x2.6, and "77% of Read is images" was really 2.6%.

Text results: characters / 4.  Images: (w * h) / 750, capped at 1600.

Read-only. Reads ~/.claude/projects/**/*.jsonl and nothing else.

    python reread-by-tool.py
"""
import base64, collections, json, os, pathlib, struct, sys

sys.stdout.reconfigure(encoding="utf-8")

RATE = 0.50 / 1e6          # Opus cache-read, $/token - load measure on a subscription
ROOT = pathlib.Path(os.path.expanduser("~")) / ".claude" / "projects"
IMG_CAP = 1600


def jpeg_dims(buf):
    i, n = 2, len(buf)
    while i < n:
        if buf[i] != 0xFF:
            i += 1
            continue
        while i < n and buf[i] == 0xFF:
            i += 1
        if i >= n:
            return None
        m = buf[i]
        i += 1
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            if i + 7 > n:
                return None
            h, w = struct.unpack(">HH", buf[i + 3:i + 7])
            return w, h
        if i + 2 > n:
            return None
        i += struct.unpack(">H", buf[i:i + 2])[0]
    return None


def png_dims(buf):
    if len(buf) >= 24 and buf[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", buf[16:24])
    return None


def image_tokens(src):
    data = src.get("data") or ""
    # the header is enough; decoding 400 KB of base64 per image is the whole runtime
    head = base64.b64decode(data[:4096] + "==", validate=False) if data else b""
    dims = jpeg_dims(head) or png_dims(head)
    if not dims:
        return float(IMG_CAP)  # unknown shape: assume the cap, never the blob length
    return min(dims[0] * dims[1] / 750.0, IMG_CAP)


def result_tokens(body):
    """(tokens, is_image) for one tool_result body."""
    if isinstance(body, list):
        tok, img = 0.0, False
        for blk in body:
            if not isinstance(blk, dict):
                continue
            if blk.get("type") == "image":
                tok += image_tokens(blk.get("source") or {})
                img = True
            else:
                tok += len(json.dumps(blk, ensure_ascii=False)) / 4.0
        return tok, img
    if body is None:
        return 0.0, False
    return len(json.dumps(body, ensure_ascii=False)) / 4.0, False


cost_by = collections.Counter()
count_by = collections.Counter()
tok_by = collections.Counter()
img_cost = naive_total = 0.0
top = []

for path in sorted(ROOT.rglob("*.jsonl")):
    if path.parent.name == "subagents":
        continue
    steps, names, pend = 0, {}, []
    for line in path.open(encoding="utf-8", errors="replace"):
        if '"usage"' not in line and '"tool_result"' not in line and '"tool_use"' not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        msg = rec.get("message") or {}
        if rec.get("type") == "assistant":
            if msg.get("usage") is not None:
                steps += 1
            for b in msg.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use":
                    inp = b.get("input") or {}
                    # full path, not basename: different _стан.md files must not merge
                    names[b.get("id")] = (b.get("name") or "?",
                                          str(inp.get("file_path") or inp.get("command") or "")[:90])
            continue
        if rec.get("type") != "user" or rec.get("isSidechain"):
            continue
        for b in msg.get("content") or []:
            if not isinstance(b, dict) or b.get("type") != "tool_result":
                continue
            body = b.get("content")
            tok, is_img = result_tokens(body)
            naive = len(json.dumps(body, ensure_ascii=False)) / 4.0 if body is not None else 0.0
            tool, detail = names.get(b.get("tool_use_id"), ("(unknown)", ""))
            pend.append((tok, naive, steps, tool, detail, is_img))

    for tok, naive, at, tool, detail, is_img in pend:
        ahead = steps - at
        cost = tok * ahead * RATE
        cost_by[tool] += cost
        count_by[tool] += 1
        tok_by[tool] += tok
        naive_total += naive * ahead * RATE
        if is_img:
            img_cost += cost
        top.append((cost, tok, ahead, tool, detail))

total = sum(cost_by.values())
print("RE-READING TOOL RESULTS - by tool, images priced by pixels")
print()
print("  %-12s %8s %13s %9s %7s" % ("tool", "calls", "tokens", "$", "share"))
print("  " + "-" * 54)
for tool, cost in cost_by.most_common(10):
    print("  %-12s %8d %13s %9s %6.1f%%" % (tool[:12], count_by[tool], format(int(tok_by[tool]), ",d"),
                                            "$%.0f" % cost, 100 * cost / total if total else 0))
print("  " + "-" * 54)
print("  %-12s %8d %13s %9s" % ("TOTAL", sum(count_by.values()),
                                format(int(sum(tok_by.values())), ",d"), "$%.0f" % total))
print()
print("  images: $%.0f (%.1f%%)" % (img_cost, 100 * img_cost / total if total else 0))
print("  naive len/4 method would say: $%.0f  (x%.1f)" % (naive_total, naive_total / total if total else 0))
print()
print("TOP 10 single results:")
top.sort(reverse=True)
for cost, tok, ahead, tool, detail in top[:10]:
    print("  $%-6.2f %-6s %9s tok %5d steps  %s" % (cost, tool[:6], format(int(tok), ",d"), ahead, detail))
