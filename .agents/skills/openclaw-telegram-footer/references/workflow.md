# Telegram Footer Workflow

## Implementation target

Patch the OpenClaw agent runner usage footer, not Telegram transport. Current built-in footer is generated around `formatResponseUsageLine(...)` and appended with `appendUsageLine(...)` inside `agent-runner.runtime-*.js`.

This keeps Telegram delivery simple and avoids touching media/chunk/button reply logic.

## Patch components

Two modifications are made:
1. **formatResponseUsageLine** — replaced with `formatTelegramFooterLine()` that produces the rich footer line.
2. **appendUsageLine** — modified to prepend `────\n` to the footer line for visual separation from the reply body.

## Desired line

```text
Model: gpt-5.5 | Session: 05a3adb2 (2026-05-08) | Thinking: high | Context: 27.3k / 272.0k (10%) | Tokens: in 36.2k out 2.1k | Usage: 5h 58% left ⏱4h 4m · Week 5% left ⏱1d 15h
```

## Field sources

- Model: current run `modelUsed`, shortened to basename after `/`.
- Session: current run `followupRun.run.sessionId`, first 8 chars, date from run start.
- Context: current run context used/limit when available.
- Tokens: current response usage input/output.
- Usage: live provider quota summary resolved from the current provider.

## Example output

```
... reply body text

────
Model: gpt-5.5 | Session: 05a3adb2 (2026-05-08) | Thinking: high | Context: 27.3k / 272.0k (10%) | Tokens: in 36.2k out 2.1k | Usage: 5h 58% left ⏱4h 4m · Week 5% left ⏱1d 15h
```

## Markers (used by script for --check)

These strings must all be present in the patched runtime:
- `function formatTelegramFooterTokenAmount`
- `function formatTelegramFooterUsageSummary`
- `function formatTelegramFooterLine`
- `model: modelUsed,` (inside callsite)
- `contextUsed: usagePromptTokens,`
- `usageSummary: providerUsageSummary`
- `const decoratedLine = \`────\\n${line}\`;`

## Caveats

- `/usage off` still disables the footer.
- `/usage full` or `/usage tokens` must be enabled for the session to see the footer.
- Telegram cannot hide this as metadata; it is visible text.
- OpenClaw updates may change bundle hashes or source patterns; re-run `--check` and stop if markers do not match.
