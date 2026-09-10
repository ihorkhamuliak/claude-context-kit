# claude-context-kit

**English** | [Українська](README_UA.md)

Start every Claude Code session on a big Obsidian vault with a short, current brief, instead of reading 430 KB of notes. PowerShell hooks and scripts, plus the measurements that shaped them.

This is my working setup, cleaned of client data. Paths and section names match my vault, so treat it as a case study you can adapt, not a plug-and-play tool.

## The problem

My session start rule said: read `CLAUDE.md`, then `Dashboard.md`, then the project state log `_стан.md`. After a year these files were 434 KB, about 129,500 tokens.

You do not pay for that once. The context is sent again on every step as cache read. In 9 days I had 1.36 billion cache-read tokens, about 288,000 per step. So the real question is not "does it fit in the window". It is "how much context do I carry into every step".

## What is inside

```
hooks/
  session-start-hook.ps1   puts the brief into the session (fail-safe, off switch)
  read-guard-hook.ps1      blocks reading a file over 100 KB in full (fail-safe, off switch)
scripts/
  brief.ps1                builds the brief: the fresh part of each file within a character
                           budget, the rest as a map with line numbers, growth signals on top
  facts.example.ps1        control facts the brief must contain (copy to facts.ps1)
  test-brief.ps1           regression test: all facts present, size under the hook limit,
                           growth signal alive
  measure-context.ps1      what the old start rule would cost, with a self-test
  spend.ps1                real token usage from Claude Code transcripts
  reread-by-tool.py        what re-reading tool results costs, per tool, images priced right
  rtk-audit.ps1            should you turn on an RTK auto-hook? measured on your own history
```

## What I learned

### 1. My brief never reached the session. 31 times out of 31.

Claude Code caps hook output at 10,000 characters. Anything longer is saved to a file, and the session gets a 2 KB preview. My brief was 57 to 98 KB. So from the first day, every session started with a preview instead of a brief.

The test was green the whole time. It checked that the facts were in the script output. It never checked that the output arrived.

> A test that measures the input, not the delivery, is green exactly when things are broken.

### 2. My first fix missed too

I measured the limit for tool output (about 20,000 characters) and cut the brief to 14,000. The test went green, the hook "delivered", and I said it works. Then I checked with a fresh session: the brief still did not arrive. Hooks have their own limit, 10,000, and it is written in the raw docs. A summary of the docs page had told me "no limits described".

Now the brief is about 9,000 characters, and it cuts its own tail if it ever grows past 9,500.

**How I prove delivery now.** Start a new headless session (`claude -p`) with all tools disabled and ask it to copy one line from deep inside the brief, about 6,500 characters in. A 2 KB preview cannot reach it. With the 14k brief the answer was "NOT FOUND". With the 9k brief it quoted the line word for word.

### 3. A popular tool can miss your workload

[RTK](https://github.com/rtk-ai/rtk) compresses command output. On my sessions an auto-hook would save 0.25%. 56% of my commands go through `ssh` to a server, and RTK has no filter for that. Its own savings report counted 4,671 commands where my logs had 2,631: pipe stages were counted as separate commands.

### 4. Count your own logs, and count images by pixels

Re-reading tool results is about 9% of my load. My first number was 21%, because a base64 image counted as text turns one screenshot into about 100,000 "tokens". The model bills it by pixels, (width × height) / 750, so about 5,000.

### 5. Growth should show up on its own

The brief grew from 57 to 98 KB in 17 days and nobody noticed, because the check was "when I remember". Now the brief adds a warning block on top when something gets big: the memory index, `CLAUDE.md`, the dashboard, the state log, or the brief itself. On a normal day there is no block. The test proves the signal works by lowering the limits until it must fire.

## Setup

1. Point the scripts to your vault and project: `setx CLAUDE_VAULT "C:\path\to\vault"` and `setx CLAUDE_PROJECT "02 - Projects\my-project"` (the folder with `_стан.md`). Add `setx CLAUDE_MEMORY_DIR "..."` if you use Claude Code memory.
2. Copy `scripts/facts.example.ps1` to `scripts/facts.ps1` and write facts your sessions must know. Match values (`42%`), not topics (`costs`).
3. Add the hooks to `.claude/settings.json` in the vault:

```json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "powershell",
        "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<path>\\hooks\\session-start-hook.ps1"],
        "timeout": 30 } ] }
    ],
    "PreToolUse": [
      { "matcher": "Read", "hooks": [ { "type": "command", "command": "powershell",
        "args": ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "<path>\\hooks\\read-guard-hook.ps1"],
        "timeout": 10 } ] }
    ]
  }
}
```

4. Run `scripts\test-brief.ps1 -SelfTest`, then `scripts\test-brief.ps1`.

Save the `.ps1` files as UTF-8 with BOM: Windows PowerShell 5.1 breaks Cyrillic without it.

Off switches: create `.claude\brief-off` or `.claude\read-guard-off` in the vault. No restart needed.

## Credits

- [fomoles/claude-code-spend](https://github.com/fomoles/claude-code-spend) by Fomoles. The idea behind `spend.ps1` and the re-read math come from there, and running it on my own logs is what led me to the brief bug. Thanks!
- [rtk-ai/rtk](https://github.com/rtk-ai/rtk), measured in `rtk-audit.ps1`.

## License

[MIT](LICENSE)
