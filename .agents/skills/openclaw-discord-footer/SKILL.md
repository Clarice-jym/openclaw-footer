---
name: openclaw-discord-footer
description: Manage the local OpenClaw Discord reply footer customization. Use when the user mentions Discord footer, usage footer, footer missing on Discord, applying/reapplying the Discord footer patch, or configuring Discord response usage metadata. Discord uses its own agent-runner runtime patch (separate from Telegram) with bold Model label, | separator, emoji fields, and no ──── divider.
---

# OpenClaw Discord Footer

## Purpose

Maintain the local Discord footer customization for OpenClaw replies. The patch modifies the agent-runner runtime to add Discord-specific channel-aware formatting, distinct from Telegram.

The patch does these things in the agent-runner runtime:

1. **Adds Discord-specific helper functions** (`formatDiscordFooterLine`, etc.) — same structure as Telegram helpers but with ` | ` separator, bold `**Model:**` label, and emoji field decorators (🧠, ⏱, 📂).
2. **Makes `formatResponseUsageLine` channel-aware** — dispatches to `formatDiscordFooterLine` when `channel === "discord"`, otherwise falls through to `formatTelegramFooterLine`.
3. **Makes `appendUsageLine` channel-aware** — Discord gets NO `────` divider (just a newline before the footer line), Telegram keeps the `────` divider.
4. **Adds channel resolution** at the call site — extracts `channel` from `sessionCtx.OriginatingChannel` and passes it through.
5. **Fixes the default `responseUsageMode`** from `"off"` to `"tokens"` in the thinking module, so footers display by default without needing `/usage tokens`.

### Discord footer format

```
**Model:** deepseek-v4-pro | 🧠 high | Session: 05a3adb2 (2026-05-10) | Context: 27.3k / 272.0k (10%) | Tokens: in 36.2k out 2.1k | ⏱ 30s | 📂 ~/project
```

Key differences from Telegram:

| Aspect | Discord | Telegram |
|--------|---------|----------|
| Divider | None (just newline) | `────` |
| Model label | `**Model:** name` (bold) | `Model: name` (plain) |
| Separator | ` | ` | ` | ` |
| Thinking | `🧠 medium` | `Thinking: medium` |
| Time | `⏱ 30s` | `Time: 30s` |
| CWD | `📂 ~/project` | `CWD: ~/project` |
| Location | DMs + channels | DMs (off by default unless requested) |

## Core commands

Runtime script:

```bash
~/.openclaw/scripts/patch-discord-footer.sh
```

Supported operations:

```bash
~/.openclaw/scripts/patch-discord-footer.sh --check
~/.openclaw/scripts/patch-discord-footer.sh --apply
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

1. If runtime script is missing or stale, copy bundled script:

```bash
mkdir -p ~/.openclaw/scripts
cp <skill-dir>/scripts/patch-discord-footer.sh ~/.openclaw/scripts/patch-discord-footer.sh
chmod +x ~/.openclaw/scripts/patch-discord-footer.sh
```

2. Run `--check` before applying.
3. Run `--apply` only when expected markers are found.
4. The script backs up the target bundle and the thinking module, runs `node --check` on both.
5. Restart Gateway after `--apply`.

## Notes

- The patch targets `agent-runner.runtime-*.js` AND `thinking-*.js` (for the default mode fix).
- The patch is **channel-aware**: it detects `channel === "discord"` and routes to Discord-specific formatting. Telegram and other channels are unaffected.
- The user still needs `/usage tokens` or `/usage full` enabled for the session — but only if the thinking module default fix was not applied. With the default fix, footers show automatically.
- If OpenClaw updates and the footer reverts, run `--check`; if missing, run `--apply` again.
- Discord has a 2000 character message limit. The footer is appended to the final reply; if the combined body + footer exceeds the limit, Discord truncation may apply (same as any long message).

## Safety

- Do not edit secrets or OpenClaw config for this workflow.
- Do not guess if code patterns changed; stop and report the blocker.
- Prefer backup + `node --check` + Gateway status verification.
- The patch is Discord-specific and does NOT affect Telegram or Feishu footer behavior.
