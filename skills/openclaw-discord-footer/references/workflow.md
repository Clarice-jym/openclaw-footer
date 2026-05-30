# Discord Footer Workflow

## Implementation target

Discord has its **OWN** independent agent-runner runtime patch (`patch-discord-footer.sh`). Unlike the previous shared approach, Discord now uses channel-aware dispatch with Discord-specific formatting: bold `**Model:**` label, ` | ` separator, `🧠` thinking field, `CWD: ...`, and no Telegram-style `────` divider.

## Why separate

The patch is channel-aware: `formatResponseUsageLine` checks `params.channel === "discord"` and routes to `formatDiscordFooterLine()`. Discord bypasses the `────` divider that Telegram uses, making the footer visually distinct for each platform.

## Patch components

Six modifications in the runtime bundle + one in the thinking module:

1. **Discord helper functions** — `formatDiscordFooterLine()`, `formatDiscordFooterTokenAmount()`, `formatDiscordFooterDate()`, `formatDiscordFooterDuration()`, `shortenDiscordFooterPath()`, `formatDiscordFooterModel()`, `formatDiscordFooterUsageSummary()` — inserted after Telegram helpers.
2. **formatResponseUsageLine dispatch** — wraps in channel check: `channel === "discord"` → Discord formatter, else → Telegram formatter.
3. **appendUsageLine** — accepts `channel` param, Discord gets `\n${line}` (no divider), Telegram gets `────\n${line}`.
4. **Call site channel resolution** — extracts `channel` from `sessionCtx.OriginatingChannel` before calling format/append.
5. **channel param pass-through** — `channel` passed to both `formatResponseUsageLine` and `appendUsageLine`.
6. **Thinking module default fix** — changes `normalizeUsageDisplay(raw) ?? "off"` → `"tokens"`.

## Verification

To verify the footer is working on Discord:
1. Ensure the patch is applied: `~/.openclaw/scripts/patch-discord-footer.sh --check`
2. Send a message through Discord DM or channel
3. Check the output for the footer line with `**Model:** ... | 🧠 ... | CWD: ...`

## Discord-specific considerations

- **Message limit:** Discord messages cap at 2000 characters. Very long replies may cause the footer to be truncated. The patch does not add truncation logic.
- **Markdown:** Discord supports bold `**text**`, so `**Model:**` renders as bold in the footer.
- **Format:** `**Model:** name | 🧠 medium | CWD: ~/project | Context: 10k / 200k (5%) | Tokens: in 5k out 1k | Usage: 92%/4h, Week 99%/6d 23h`

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No footer on Discord | Patch reverted by update | Run `--check` then `--apply` |
| No footer on Discord | thinking module default = "off" | Verify thinking patch applied |
| `ReferenceError: channel is not defined` | `const channel` declared inside wrong scope | Verify call site declaration is before the `if` block |
| Footer on Telegram but not Discord | Dispatch not channel-aware | Run `--check` to verify all markers |
| Footer reverted after OpenClaw update | Bundle overwritten | Run `--check` then `--apply` |
