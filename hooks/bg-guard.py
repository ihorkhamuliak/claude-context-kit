#!/usr/bin/env python3
"""bg-guard.py - PostToolUse (Bash|PowerShell): a command ran past its timeout and the harness moved it to the
background -> remind Claude to decide now. A forgotten wait loop lived this way for 18 hours and hit the server
~3000 times. Blocks nothing. Off switch: bg-guard-off in ~/.claude or the project's .claude."""
import json, os, sys

OFF = [os.path.join(os.path.expanduser("~"), ".claude", "bg-guard-off"), os.path.join(".claude", "bg-guard-off")]


def main():
    if any(os.path.exists(p) for p in OFF):
        return
    j = json.loads(sys.stdin.buffer.read().decode("utf-8", errors="replace") or "{}")
    resp = j.get("tool_response")
    timed = isinstance(resp, dict) and resp.get("timedOutAfterMs")
    if not timed and "moved to the background" not in json.dumps(resp, ensure_ascii=False):
        return
    task = resp.get("backgroundTaskId", "?") if isinstance(resp, dict) else "?"
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": (
        f"⚠️ The command did not finish within its timeout, and the harness MOVED it to the background (task {task}): "
        "it is still running. Decide now: TaskStop if the result is no longer needed (a loop, a hung ssh); if it is "
        "needed, tell the user what you are waiting for and until when. A forgotten loop like this once knocked on "
        "a server for 18 hours.")}}))
    # ensure_ascii (default): hook stdout on Windows may be a legacy code page, non-ASCII would fail silently


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
