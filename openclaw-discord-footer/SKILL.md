---
name: openclaw-discord-footer
description: Manage the local OpenClaw Discord reply footer customization. Use when the user mentions Discord footer, usage footer, footer missing on Discord, applying/reapplying the Discord footer patch, or configuring Discord response usage metadata. Discord shares the same agent-runner runtime patch as Telegram — this skill delegates to the shared patch while providing Discord-specific context and verification.
---

# OpenClaw Discord Footer

## Purpose

Maintain the local Discord footer customization for OpenClaw replies. Discord uses the same agent-runner runtime patch as Telegram, since both are text-based channels that receive footers via the shared `formatResponseUsageLine` / `appendUsageLine` pipeline.

The patch does two things in the agent-runner runtime:

1. Replaces the built-in `formatResponseUsageLine` with a rich footer format:
   `Model: <model> | Session: <id8> (YYYY-MM-DD) | Thinking: <level> | Context: <used> / <limit> (<pct>) | Tokens: in <input> out <output> | Usage: <quota summary>`
2. Replaces `appendUsageLine` to add a visual separator `────` between the reply body and the footer.

Discord has no Feishu-style card `note` metadata, so this is a visible text footer appended to the final reply. The format is identical to Telegram.

### Visual separator

The patch prepends `────\n` to the footer line (4 box-drawing horizontal characters + newline). This visually separates the footer from the reply body.

Example Discord output:

```text
... reply body text

────
Model: gpt-5.4 | Session: 05a3adb2 (2026-05-11) | Thinking: high | Context: 27.3k / 272.0k (10%) | Tokens: in 36.2k out 2.1k | Usage: 5h 58% left ⏱4h 4m · Week 5% left ⏱1d 15h
```

### Discord-specific notes

- Discord has a 2000 character message limit. The footer line may be truncated if the reply body is very long. The patch does not attempt to shorten the body — it appends normally.
- Discord supports basic Markdown but the footer is plain text (no bold/italic) to avoid formatting issues.
- The `────` separator renders correctly in Discord as a horizontal rule-like line.

## Core commands

Since Discord and Telegram share the same runtime patch, this skill delegates to the Telegram patch script:

```bash
# Check if patch is applied:
~/.openclaw/scripts/patch-telegram-footer.sh --check

# Apply the patch:
~/.openclaw/scripts/patch-telegram-footer.sh --apply
```

Or use the bundled Discord wrapper (ensures the Telegram patcher is present first):

```bash
<skill-dir>/scripts/patch-discord-footer.sh --check
<skill-dir>/scripts/patch-discord-footer.sh --apply
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

- `discord footer check` / `discord footer status` → run `--check`.
- `discord footer apply` → run `--apply`, restart Gateway, verify.
- `discord footer install` / "配置 Discord footer" → ensure runtime script exists, run `--apply`, restart, verify.

## Workflow

1. **Check first:** Run `--check` to see if the shared runtime patch is already applied.
2. **Ensure the Telegram patch script exists:** If missing, install it from the Telegram footer skill or copy from `openclaw-telegram-footer/scripts/patch-telegram-footer.sh`.
3. **Apply if needed:** Run `--apply` only when markers are missing.
4. **Restart Gateway:** `openclaw gateway restart`
5. **Verify:** `openclaw gateway status` — must show `Runtime: running` and `Connectivity probe: ok`.
6. **Test:** Send a message through Discord and confirm the footer appears.

## Notes

- Discord and Telegram share the **exact same** agent-runner runtime patch. Applying the Telegram patch enables footers on both channels simultaneously.
- No Discord-specific code changes are needed — the footer generation is channel-agnostic.
- `/usage tokens` or `/usage full` must be enabled for the session; `/usage off` disables the footer.
- If OpenClaw updates and the footer reverts, run `--check`; if missing, run `--apply` again.
- The `Usage` field shows live provider quota (e.g., `5h 58% left ⏱4h 4m`), same as Telegram.

## Safety

- Do not edit secrets or OpenClaw config for this workflow.
- Do not guess if code patterns changed; stop and report the blocker.
- Prefer backup + `node --check` + Gateway status verification.
- The shared runtime patch targets `agent-runner.runtime-*.js`, not Discord delivery specifically.
