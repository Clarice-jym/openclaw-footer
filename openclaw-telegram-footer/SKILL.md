---
name: openclaw-telegram-footer
description: Manage the local OpenClaw Telegram reply footer customization. Use when the user mentions Telegram footer, usage footer, exact footer labels, footer missing after OpenClaw update, applying/reapplying the Telegram footer patch, or configuring custom Telegram response usage metadata.
---

# OpenClaw Telegram Footer

## Purpose

Maintain the local Telegram footer customization for OpenClaw replies. The patch patches two things in the agent-runner runtime:

1. Replaces the built-in `formatResponseUsageLine` with a rich footer format:
   `Model: <model> | Session: <id8> (YYYY-MM-DD) | Thinking: <level> | Context: <used> / <limit> (<pct>) | Tokens: in <input> out <output> | Time: <duration> | CWD: <path>`
2. Replaces `appendUsageLine` to add a visual separator `────` between the reply body and the footer.

Telegram has no Feishu-style card `note` metadata, so this is a visible text footer appended to the final reply line.

### Visual separator

The patch prepends `────\n` to the footer line (4 em-dashes + newline). This visually separates the footer from the reply body with:
- A blank line after the body text (single `\n` if body ends with `\n`, otherwise a single `\n`)
- A `────` line
- The footer content on the next line, with no extra blank line between `────` and the content

Example output:

```text
... reply body text

────
Model: gpt-5.5 | Session: 05a3adb2 (2026-05-08) | Thinking: high | Context: 27.3k / 272.0k (10%) | Tokens: in 36.2k out 2.1k | Time: 1m 26s | CWD: ~/.openclaw/workspace
```

## Core commands

Runtime script:

```bash
~/.openclaw/scripts/patch-telegram-footer.sh
```

Supported operations:

```bash
~/.openclaw/scripts/patch-telegram-footer.sh --check
~/.openclaw/scripts/patch-telegram-footer.sh --apply
```

After applying, restart and verify Gateway:

```bash
openclaw gateway restart || true
sleep 5
openclaw gateway status
```

Success gate:

- `Runtime: running`
- `Connectivity probe: ok`

## User shorthand

- `telegram footer check` → run `--check`.
- `telegram footer apply` → run `--apply`, restart Gateway, verify.
- `telegram footer install` / “配置 Telegram footer” → ensure runtime script exists, run `--apply`, restart, verify.

## Workflow

1. If runtime script is missing or stale, copy bundled script:

```bash
mkdir -p ~/.openclaw/scripts
cp <skill-dir>/scripts/patch-telegram-footer.sh ~/.openclaw/scripts/patch-telegram-footer.sh
chmod +x ~/.openclaw/scripts/patch-telegram-footer.sh
```

2. Run `--check` before applying.
3. Run `--apply` only when expected markers are found.
4. The script backs up the target bundle and runs `node --check`.
5. Restart Gateway after `--apply`.

## Notes

- The patch targets `agent-runner.runtime-*.js`, not Telegram delivery, because OpenClaw already appends `/usage` footers from the agent-runner layer.
- The user still needs `/usage tokens` or `/usage full` enabled for the session; `/usage off` disables the footer.
- If OpenClaw updates and the footer reverts, run `--check`; if missing, run `--apply` again.

## Safety

- Do not edit secrets or OpenClaw config for this workflow.
- Do not guess if code patterns changed; stop and report the blocker.
- Prefer backup + `node --check` + Gateway status verification.
