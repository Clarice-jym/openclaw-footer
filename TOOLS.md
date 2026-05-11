# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## What Goes Here

Things like:

- Camera names and locations
- SSH hosts and aliases
- Preferred voices for TTS
- Speaker/room names
- Device nicknames
- Anything environment-specific

## Examples

```markdown
### Cameras

- living-room → Main area, 180° wide angle
- front-door → Entrance, motion-triggered

### SSH

- home-server → 192.168.1.100, user: admin

### TTS

- Preferred voice: "Nova" (warm, slightly British)
- Default speaker: Kitchen HomePod
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.


## OpenClaw Telegram Footer Runtime Gotcha

If Telegram starts replying but fails halfway with `Something went wrong while processing your request. Please try again.`, check gateway logs before assuming token/polling failure:

```bash
journalctl --user -u openclaw-gateway --since 'YYYY-MM-DD HH:MM:SS' --no-pager -o cat
```

Known log signature after footer changes:

```text
ReferenceError: usagePromptTokens is not defined
[telegram] dispatch failed: ReferenceError: usagePromptTokens is not defined
```

Root cause can be in bundled runtime `~/.npm-global/lib/node_modules/openclaw/dist/agent-runner.runtime-*.js`: response usage footer references `usagePromptTokens` outside the diagnostics branch where it was declared. Fix by lifting these variables before `if (isDiagnosticsEnabled(cfg) && hasNonzeroUsage(usage))`:

```js
const input = usage.input ?? 0;
const output = usage.output ?? 0;
const cacheRead = usage.cacheRead ?? 0;
const cacheWrite = usage.cacheWrite ?? 0;
const usagePromptTokens = input + cacheRead + cacheWrite;
const totalTokens = usage.total ?? usagePromptTokens + output;
```

After patching: `node --check "$f"`, restart gateway, run `openclaw channels status --probe`, then verify with `openclaw agent --channel telegram --to 8762865539 --message '诊断测试：请只回复 OK。' --json --timeout 180`.

OpenClaw/npm updates may overwrite this bundled patch.
