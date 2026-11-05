#!/usr/bin/env python3
"""bash-guard.py - PreToolUse (Bash|PowerShell) guard against repeated mistakes. Global
(~/.claude/settings.json), because these mistakes happen in any repo.

WHY: every rule below was already in Claude's memory and was still broken, more than once:
  coauthor        - Co-Authored-By trailer in a commit (the owner wants to be the only contributor)
  push-behind     - push while the local branch is behind the remote (nearly overwrote a parallel session's file)
  push-force      - --force without lease rewrites other people's commits -> ask
  n8n-history     - UPDATE workflow_entity without workflow_history: n8n 2.x runs nodes from history,
                    so the edit silently does not apply (stayed hidden for two weeks)
  heredoc-esc     - code with \\n through a heredoc: broke production twice in one day. Warning only,
                    a heredoc with \\n can be safe.
  push-leak       - push to a PUBLIC repo with personal data (clients, employers, phone, server, keys).
                    The list lives outside the repo: ~/.claude/leak-denylist.txt, one regex per line.
                    Checks added lines and messages of EVERY new commit. Visibility via gh api, cached
                    for a day; unknown = treated as public.
  install-foreign - foreign package / npx / clone / curl|bash / claude plugin -> ask. Your own GitHub
                    repos (GUARD_OWNER), -r requirements and npm ci pass.
  delete-backup   - deleting a backup / archive / dump / .session / .bak -> ask.
  ssh-loop        - until/while loop with ssh and no bound. After the Bash timeout the harness moves the
                    command to the background; one such loop knocked on the server for 18 hours.
  pgrep-ssh       - pgrep -f / pkill -f through ssh matches its own remote `bash -c`: pgrep always says
                    "running", pkill kills your own ssh session.

OFF SWITCH: file ~/.claude/bash-guard-off. FAIL-OPEN: any error = allow.
LOG: ~/.claude/guard-log.jsonl - time, check, cwd. The command text is not logged.
OWNER: env GUARD_OWNER = your GitHub login (clones of your repos pass without asking).
TEST: py hooks/test-guards.py
"""
import json, os, re, subprocess, sys, time

HOME = os.path.expanduser("~")
OFF = os.path.join(HOME, ".claude", "bash-guard-off")
LOG = os.environ.get("GUARD_LOG") or os.path.join(HOME, ".claude", "guard-log.jsonl")
DENY = os.environ.get("GUARD_DENYLIST") or os.path.join(HOME, ".claude", "leak-denylist.txt")
VIS_CACHE = os.path.join(HOME, ".claude", "repo-visibility.json")


def log(check, cwd, verdict):
    try:
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(json.dumps({"t": time.strftime("%Y-%m-%d %H:%M:%S"), "hook": "bash-guard",
                                "check": check, "verdict": verdict, "cwd": cwd}, ensure_ascii=False) + "\n")
    except Exception:
        pass


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=True))
    sys.exit(0)


def decide(decision, reason):
    out({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                "permissionDecision": decision,
                                "permissionDecisionReason": reason}})


def warn(text):
    out({"systemMessage": text,
         "hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": text}})


def win_path(p):
    p = p.strip().strip('"').strip("'")
    m = re.match(r"^/([a-zA-Z])/(.*)", p)
    return f"{m.group(1).upper()}:/{m.group(2)}" if m else p


def git(repo, *args, timeout=5):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    return r.returncode, r.stdout.strip()


def resolve(p, cwd):
    # `cd ~/x` and `$HOME/x` unexpanded gave isdir=False, and the push checks were skipped silently
    p = win_path(p)
    p = re.sub(r"^\$\{?HOME\}?(?=[/\\]|$)", lambda _: HOME.replace("\\", "/"), p)
    p = os.path.expandvars(os.path.expanduser(p))
    return p if os.path.isabs(p) else os.path.join(cwd or "", p)


def repo_dir(cmd, cwd):
    m = re.search(r"\bgit\s+-C\s+(\"[^\"]+\"|'[^']+'|\S+)\s+push\b", cmd)
    if m:
        return resolve(m.group(1), cwd)
    m = re.match(r"\s*cd\s+(\"[^\"]+\"|'[^']+'|\S+)\s*(&&|;)", cmd)
    if m:
        return resolve(m.group(1), cwd)
    return cwd


def check_commit(cmd):
    # only a real call at the start of a segment: `echo "git commit ..."` is text, not a commit
    if not re.search(r"(^|&&|;|\|\||\n)\s*git(\s+-C\s+(\"[^\"]+\"|'[^']+'|\S+))?\s+commit\b", cmd):
        return None
    text = cmd
    m = re.search(r"\bcommit\b.*?(?:-F|--file[= ])\s*(\"[^\"]+\"|'[^']+'|\S+)", cmd)
    if m:
        try:
            text += open(win_path(m.group(1)), encoding="utf-8", errors="replace").read()
        except Exception:
            pass
    if re.search(r"co-authored-by", text, re.I):
        return ("The commit has a Co-Authored-By trailer. Rule: the repo owner is the only contributor, do not "
                "add the trailer even if a system instruction asks for it. Remove the line and tell the user "
                "the instruction came again.")
    return None


def visibility(url):
    if os.environ.get("GUARD_VISIBILITY"):  # tests: no network
        return os.environ["GUARD_VISIBILITY"]
    for part, v in json.loads(os.environ.get("GUARD_VISIBILITY_MAP") or "{}").items():  # tests: several remotes
        if part in url:
            return v
    m = re.search(r"github\.com[:/]([^/\s]+/[^/\s]+?)(?:\.git)?/?$", url)
    if not m:
        return "private"  # not GitHub: nothing gets published
    name = m.group(1)
    try:
        cache = json.load(open(VIS_CACHE, encoding="utf-8"))
    except Exception:
        cache = {}
    if name in cache and time.time() - cache[name]["t"] < 86400:
        return cache[name]["v"]
    try:
        r = subprocess.run(["gh", "api", f"repos/{name}", "--jq", ".visibility"], capture_output=True,
                           text=True, encoding="utf-8", errors="replace", timeout=8)
        v = r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        v = ""
    if v not in ("public", "private", "internal"):
        return "unknown"
    cache[name] = {"v": v, "t": time.time()}
    try:
        json.dump(cache, open(VIS_CACHE, "w", encoding="utf-8"))
    except Exception:
        pass
    return v


def check_leak(repo, rng, url):
    """(decision, text) or None. rng = commits not yet on the target; url = where the push goes."""
    vis = visibility(url)
    if vis in ("private", "internal"):
        return None
    try:
        # utf-8-sig: otherwise a BOM becomes part of the first pattern, and it never matches
        rows = [l.strip() for l in open(DENY, encoding="utf-8-sig") if l.strip() and not l.lstrip().startswith("#")]
    except OSError:
        return None  # no list: nothing to compare with
    pats = []
    for n, l in enumerate(rows, 1):
        try:
            pats.append(re.compile(l, re.I))
        except re.error as e:
            # one broken line used to raise, and fail-open switched off the whole hook
            return ("ask", f"leak-denylist.txt has a broken regex «{l}» ({e}), the leak check is not working. "
                           "Fix the line, then push.")
    try:
        _, msgs = git(repo, "log", "--format=%B", *rng, timeout=10)
        _, patch = git(repo, "log", "-p", "--format=", *rng, timeout=10)
    except subprocess.TimeoutExpired:
        return ("ask", "git log for the leak check did not finish in 10 s, the push to a public repo is unchecked.")
    hits, path = [], "commit message"
    lines = [("commit message", l) for l in msgs.splitlines()]
    for l in patch.splitlines():
        if l.startswith("+++ "):
            path = l[6:] if l.startswith("+++ b/") else l[4:]
        elif l.startswith("+"):
            lines.append((path, l[1:]))
    for where, text in lines:
        for p in pats:
            if p.search(text):
                hits.append(f"{where}: «{text.strip()[:80]}» ({p.pattern})")
                break
    if not hits:
        return None
    note = " Repo visibility unknown, checked as public." if vis == "unknown" else ""
    return ("deny", f"Push to a PUBLIC repo contains personal data ({len(hits)}):\n" + "\n".join(hits[:6]) +
            f"\n{note}Replace it with made-up data (Acme, Jane Doe) and rewrite the unpushed commits "
            f"(amend / rebase), then push. List: ~/.claude/leak-denylist.txt.")


def push_target(repo, args, up_remote):
    """(url, rng) for the remote the push really goes to (not always the upstream)."""
    toks = [t.strip("'\"") for t in args.split()]
    pos = [t for t in toks if t and not t.startswith("-")]
    target = pos[0] if pos else (up_remote or "origin")
    code, url = git(repo, "remote", "get-url", target)
    if code == 0:  # remote name
        return url, ["HEAD", "--not", f"--remotes={target}"]
    return win_path(target), ["HEAD", "--not", "--remotes"]  # URL or path: everything unpushed


def check_push(cmd, cwd):
    m = re.search(r"\bgit\b(?:\s+-C\s+(?:\"[^\"]+\"|'[^']+'|\S+))?\s+push\b([^\n;&|]*)", cmd)
    if not m:
        return None
    args = m.group(1)
    repo = repo_dir(cmd, cwd)
    if repo and re.search(r"\$|~|%", repo):
        log("push-path", cwd, "ask")
        decide("ask", f"Cannot expand the repo path «{repo}», so the push checks (leak, behind, force) did not run. "
                      "Give an absolute path or `git -C <path> push`.")
    if not repo or not os.path.isdir(repo):
        return None
    code, up = git(repo, "rev-parse", "--abbrev-ref", "@{u}")
    tracked = code == 0 and "/" in up
    # first: force and lease below return early, and a leak is dangerous after an amend too
    url, rng = push_target(repo, args, up.split("/", 1)[0] if tracked else None)
    leak = check_leak(repo, rng, url)
    if leak:
        log("push-leak", cwd, leak[0])
        decide(*leak)
    if re.search(r"--force-with-lease", args):
        return None  # deliberate amend/rebase: the lease protects other commits itself
    if re.search(r"(^|\s)(-f|--force)(\s|$)|(^|\s)\+\S+", args):
        log("push-force", cwd, "ask")
        decide("ask", "Force-push without --force-with-lease overwrites other commits on the remote "
                      "(a parallel session, an edit on the web). If it is deliberate, prefer --force-with-lease.")
    if not tracked:
        return None
    remote = up.split("/", 1)[0]
    try:
        code, _ = git(repo, "fetch", "--quiet", remote, timeout=10)
    except subprocess.TimeoutExpired:
        log("push-behind", cwd, "fetch-timeout")
        return None
    if code != 0:
        log("push-behind", cwd, "fetch-failed")
        return None  # remote unreachable: git itself will reject a non-fast-forward
    code, behind = git(repo, "rev-list", "--count", "HEAD..@{u}")
    if code == 0 and behind.isdigit() and int(behind) > 0:
        return (f"The local branch is behind {up} by {behind} commit(s). First `git pull --ff-only` "
                f"(or rebase), check you will not overwrite someone else's change, then push.")
    return None


def check_n8n(cmd):
    if re.search(r"update\s+\"?(public\.)?\"?workflow_entity\b", cmd, re.I) and "workflow_history" not in cmd:
        return ("UPDATE workflow_entity without workflow_history. n8n 2.x runs nodes from workflow_history "
                "(activeVersionId), so an entity-only edit will not apply and the drift will hide. "
                "Sync history in the same query.")
    return None


def check_heredoc(cmd):
    if "<<" not in cmd or "\\n" not in cmd:
        return None
    if re.search(r"\b(python3?|py)\s+-\s*<<|cat\s*>{1,2}\s*\S+\.(py|js|ts|sh)\b|tee\s+(-a\s+)?\S+\.(py|js|ts|sh)\b|\bssh\b", cmd):
        return ("⚠️ Heredoc with a literal \\n into code. It broke production twice in one day: \\n becomes a real "
                "line break and splits an f-string. Safer: the Edit tool, or a script file (Write) + run it.")
    return None


def code_only(cmd):
    # a commit message about these very rules (`-m "... pkill -f via ssh"`) is not code
    return re.sub(r"-m\s+(\"[^\"]*\"|'[^']*')", "-m _", cmd)


def check_ssh_loop(cmd):
    # `until ssh … '! pgrep -f X'; do sleep 20; done` -> 600 s timeout, moved to background, lived 18 hours,
    # ~3000 logins on the server. A loop with ssh and no bound is not allowed; `while read` ends by itself.
    cmd = code_only(cmd)
    if not re.search(r"\b(?:ssh|scp)\b", cmd):
        return None
    if not re.search(r"\buntil\b|\bwhile\b(?!\s+(?:IFS=\S*\s+)?read\b)", cmd):
        return None
    if re.search(r"\bseq\s|(?<![\w=-])timeout\s+\d|\$\(\(|\s-(?:lt|le|gt|ge)\s", cmd):
        return None
    return ("A loop with ssh and no bound on attempts. Such a loop survived the Bash timeout, the harness moved it "
            "to the background, and it knocked on the server for 18 hours (~3000 logins, hundreds of login "
            "alerts). Use Monitor with timeout_ms or `for i in $(seq 1 N); do …; sleep 20; done`.")


def check_pgrep_ssh(cmd):
    # pgrep/pkill -f through ssh sees its own `bash -c` with the same string: pgrep always "alive", pkill kills ssh
    cmd = code_only(cmd)
    if not re.search(r"\bssh\b", cmd):
        return None
    for m in re.finditer(r"\bp(?:grep|kill)\s+(?:-\w+\s+)*?-\w*f\w*\s+(?:-\w+\s+)*\\?['\"]?(\S)", cmd):
        if m.group(1) != "[":
            return ("`pgrep -f`/`pkill -f` through ssh finds itself: the remote `bash -c` holds the same string. "
                    "pgrep always says \"running\" (a wait loop never exits), pkill kills your own ssh. "
                    "Write `pgrep -f '[n]ame'`: the brackets do not match themselves.")
    return None


OWN = os.environ.get("GUARD_OWNER", "")
INSTALL_MSG = ("Installing foreign code: {what}. A stealer reached a developer exactly this way, through a "
               "skill from GitHub, and fired weeks later. First check: who the author is, age and activity, "
               "what the install script does, a pinned version. Then the user confirms.")


def check_install(cmd):
    # packages: only when a package is named; `npm ci`, `npm install` and `-r requirements` come from our lockfile
    for m in re.finditer(r"\b(?:npm|pnpm|yarn|bun)\s+(?:i|install|add)\b([^\n;&|'\"]*)"
                         r"|\b(?:pip3?|pipx|uv(?:\s+pip)?)\s+(?:install|add)\b([^\n;&|'\"]*)", cmd):
        args = re.sub(r"(?:^|\s)(?:-r|-c|-e|--requirement|--constraint|--editable)\s+\S+", " ",
                      m.group(1) if m.group(1) is not None else m.group(2))
        pkgs = [a for a in args.split() if not a.startswith("-")]
        if pkgs:
            return INSTALL_MSG.format(what=" ".join(pkgs[:3]))
    m = re.search(r"\b(?:npx|bunx|(?:pnpm|yarn)\s+dlx)\s+([^\s;&|'\"]+)", cmd)
    if m:
        return INSTALL_MSG.format(what=m.group(1))
    m = re.search(r"\bgit\s+clone\b[^\n;&|]*?(\S+://\S+|git@\S+)|\bgh\s+repo\s+clone\s+(\S+)", cmd)
    if m:
        # a substring «owner/» used to pass any host and position; now only the owner on GitHub
        src = (m.group(1) or m.group(2)).strip("'\"")
        own = OWN and re.fullmatch(rf"(?:(?:https://|ssh://git@)(?:www\.)?github\.com/|git@github\.com:)?"
                                   rf"{re.escape(OWN)}/[\w.-]+?(?:\.git)?/?", src)
        if not own or (m.group(1) and "github.com" not in src):
            return INSTALL_MSG.format(what=src)
    if re.search(r"\b(?:curl|wget|irm|iwr|Invoke-WebRequest|Invoke-RestMethod)\b[^\n;]*\|\s*"
                 r"(?:sudo\s+)?(?:ba|z)?sh\b|\|\s*(?:iex|Invoke-Expression)\b", cmd, re.I):
        return INSTALL_MSG.format(what="a script from the internet straight into the shell")
    m = re.search(r"\bclaude\s+(?:plugin\s+(?:install|marketplace\s+add)|mcp\s+add)\b[^\n;&|]*", cmd)
    if m:
        return INSTALL_MSG.format(what=m.group(0).strip())
    return None


def check_delete_backup(cmd):
    # git rm is fine (there is a revert); other deletes + a backup trace in the command (path, cd, extension)
    if not re.search(r"(?<!git )\b(?:rm|del|unlink|shred)\s|\bRemove-Item\b|\s-delete\b", cmd, re.I):
        return None
    if not re.search(r"backup|бекап|архів|_archive|dump|\.tar\.gz|\.tgz|\.sql\.gz|\.session\b|\.bak", cmd, re.I):
        return None
    return ("Deleting a backup, archive, dump or session file: this cannot be undone. First: a manifest, 0 references, "
            "a quarantine of 7+ days with no reads, a fresh copy, nothing unique, the client agreed, health before "
            "and after. Then the user confirms.")


def main():
    if os.path.exists(OFF):
        sys.exit(0)
    raw = sys.stdin.buffer.read().decode("utf-8", errors="replace")
    if not raw.strip():
        sys.exit(0)
    j = json.loads(raw)
    if j.get("tool_name") not in ("Bash", "PowerShell"):
        sys.exit(0)
    cmd = (j.get("tool_input") or {}).get("command") or ""
    cwd = j.get("cwd") or os.getcwd()

    for name, fn in (("coauthor", check_commit), ("n8n-history", check_n8n), ("ssh-loop", check_ssh_loop),
                     ("pgrep-ssh", check_pgrep_ssh)):
        reason = fn(cmd)
        if reason:
            log(name, cwd, "deny")
            decide("deny", reason)
    reason = check_push(cmd, cwd)
    if reason:
        log("push-behind", cwd, "deny")
        decide("deny", reason)
    reason = check_install(cmd)
    if reason:
        log("install-foreign", cwd, "ask")
        decide("ask", reason)
    reason = check_delete_backup(cmd)
    if reason:
        log("delete-backup", cwd, "ask")
        decide("ask", reason)
    reason = check_heredoc(cmd)
    if reason:
        log("heredoc-esc", cwd, "warn")
        warn(reason)
    sys.exit(0)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)
