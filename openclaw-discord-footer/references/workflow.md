# Discord Footer Workflow

## Implementation target

Discord and Telegram share the **exact same** agent-runner runtime patch. Both channels route through `formatResponseUsageLine()` and `appendUsageLine()` in `agent-runner.runtime-*.js`. No Discord-specific code changes are required.

## Why shared

OpenClaw's agent-runner generates the usage footer line once per reply, then appends it to the final text payload via `appendUsageLine`. This is channel-agnostic — the footer is added before the reply is dispatched to the specific channel plugin (Telegram, Discord, etc.).

## Patch components (from Telegram skill)

Two modifications in the runtime:

1. **formatResponseUsageLine** — replaced with `formatTelegramFooterLine()` that produces the rich footer line with Model, Session, Thinking, Context, Tokens, Usage fields.
2. **appendUsageLine** — prepends `────\n` for visual separation.

## Verification

To verify the footer is working on Discord:
1. Ensure `/usage tokens` or `/usage full` is active
2. Send a message through Discord
3. Check the output for the `────` separator and footer line

## Discord-specific considerations

- **Message limit:** Discord messages cap at 2000 characters. Very long replies may cause the footer to be truncated or split across messages. The patch does not add truncation logic — if this becomes a problem, consider shortening the reply body.
- **Markdown:** The footer is plain text. Discord's limited Markdown support (no headers in bots) means formatting like bold/italic on footer fields adds visual noise without benefit.
- **Embeds vs text:** The footer is appended as plain text, not as a Discord embed. This is intentional — embed footers are visually distinct from message content and could be confused with system messages.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| No footer on Discord | `/usage off` | Enable `/usage tokens` or `/usage full` |
| Footer on Telegram but not Discord | Different session/bot | Both use same agent; check same session |
| Footer reverted after OpenClaw update | Bundle overwritten | Run `--check` then `--apply` |
| Footer truncated | Message > 2000 chars | Reduce reply length or accept truncation |
