---
name: openclaw-discord-footer
description: Manage the local OpenClaw Discord reply footer customization. Use when the user mentions Discord footer, usage footer, footer missing on Discord, applying/reapplying the Discord footer patch, or configuring Discord response usage metadata. Discord shares the same agent-runner runtime and footer-shared.mjs module with Telegram.
---

# OpenClaw Discord Footer

## Purpose

Maintain the local Discord footer customization for OpenClaw replies. Since 2026-05-12, Discord shares the same `footer-shared.mjs` module and agent-runner runtime as Telegram.

The patch (via `patch-telegram-footer.sh`) does these things in the agent-runner runtime:

1. **Adds an ESM import** of `footer-shared.mjs` → `generateFooterLine()`
2. **Replaces `formatDiscordFooterLine`** with a thin wrapper: `generateFooterLine({ ...params, style: "discord" })`
3. **Patches the footer callsite** so `Context` uses refreshed session-store `totalTokens / contextTokens`, matching `/status`-style context pressure rather than provider prompt usage.
4. The channel-aware `formatResponseUsageLine` dispatches to the Discord wrapper when `channel === "discord"`.
4. **`appendUsageLine`** is channel-aware: Discord gets `────────` divider, Telegram gets `────`.

**To change footer format across all channels:** edit `~/.openclaw/footer-shared.mjs` → restart Gateway. No re-patching needed.

**Discord-specific formatting** (bold Model, `🧠` thinking field, `CWD: ...`, 8-dash divider) is defined in `footer-shared.mjs` `FIELD_SPECS.discord`.

The patch does these things in the agent-runner runtime:

1. **Adds Discord-specific helper functions** (`formatDiscordFooterLine`, etc.) — same structure as Telegram helpers but with ` | ` separator, bold `**Model:**` label, and Discord-specific field ordering.
2. **Makes `formatResponseUsageLine` channel-aware** — dispatches to `formatDiscordFooterLine` when `channel === "discord"`, otherwise falls through to `formatTelegramFooterLine`. **Both paths wrapped in try-catch** so footer errors never block message dispatch.
3. **Makes `appendUsageLine` channel-aware** — Discord gets `────────` divider with ` | ` separator using bold `**Model:**` label, Telegram keeps the `────` divider with plain label. **Entire function wrapped in try-catch** for safety.
4. **Adds channel resolution** at the call site — `const channel = sessionCtx.OriginatingChannel ?? ...` declared **outside** the `if (responseUsageMode)` block to avoid ReferenceError.
5. **`appendUsageLine` call site wrapped in try-catch** — footer failure is caught and logged, never blocks reply dispatch.
6. **Supports provider usage summary in the Discord footer** — when provider usage data is available, the footer can include `Usage: ...` with the same shared provider-usage formatting (` | ` separators, `⏱️` reset markers).
7. **Current live runtime is shared with Telegram** — Discord formatting is selected by `channel === "discord"`, not by a fully separate runtime bundle.

### Discord footer format

```
────────
**Model:** deepseek-v4-flash | 🧠 medium | CWD: ~/.openclaw/workspace | Context: 10k / 200k (5%) | Tokens: in 5k out 1k | Usage: 92%/4h, Week 99%/6d 23h
```

Key differences from Telegram:

| Aspect | Discord | Telegram |
|--------|---------|----------|
| Divider | `────────` (8 dashes) | `────` (4 em dash) |
| Model label | `**Model:** name` (bold) | `Model: name` (plain) |
| Separator | ` | ` | ` | ` |
| Thinking | `🧠 medium` | `Thinking: medium` |
| Working directory | `CWD: ~/project` after thinking | `CWD: ~/project` before thinking |
| Location | DMs + channels | DMs (off by default unless requested) |
| Error handling | try-catch everywhere, logs [footer] warnings | none (error = message failure) |
| Usage support | Shared provider-usage summary when available | Shared provider-usage summary when available |
| Default mode | Runtime behavior should be verified against live bundle; do not assume old manual `/usage tokens` gate | Usage currently patched to show without the old gate |

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
4. The script delegates to `patch-telegram-footer.sh` since Discord shares the same runtime bundle.
5. Restart Gateway after `--apply`.

## Notes

- Since 2026-05-12, Discord footer content is defined in `~/.openclaw/footer-shared.mjs` with `style: "discord"`.
- The `patch-discord-footer.sh` script **delegates to `patch-telegram-footer.sh`** because both channels share the same agent-runner runtime and footer module.
- Discord-specific formatting (bold **Model:**, `🧠`, `CWD: ...`, `────────` divider) is in `FIELD_SPECS.discord` in the shared module.
- All footer code is wrapped in **try-catch**. If anything fails, the warning goes to gateway logs (`[footer] ...`) and the message is sent without footer.
- The `channel` variable is declared **outside** the usage block to prevent `ReferenceError: channel is not defined`.
- For Discord **group channels** (like #elmo), you also need `messages.groupChat.visibleReplies = true` in the Gateway config, otherwise the agent's reply (including the footer) won't appear in the channel.
- If OpenClaw updates and the import or wrappers are lost, run `patch-discord-footer.sh --check`; if missing, run `--apply` again.
- Discord has a 2000 character message limit. The footer is appended to the final reply; if the combined body + footer exceeds the limit, Discord truncation may apply (same as any long message).

## Known Issues

- `openclaw gateway restart` / `systemctl --user restart` sends SIGTERM that kills the current exec shell. Use `openclaw gateway start >/dev/null 2>&1 & disown` instead.

## Exact code to insert (legacy)

With the shared module approach (2026-05-12+), manual code insertion is no longer needed. Use `patch-discord-footer.sh --apply` instead, which delegates to `patch-telegram-footer.sh`. The sections below are kept for historical reference only and do **not** define the current canonical footer fields.

```javascript
// Discord footer helpers
function formatDiscordFooterTokenAmount(value) {
	if (!Number.isFinite(value) || value <= 0) return null;
	if (value >= 1e6) return `${(value / 1e6).toFixed(1).replace(/\.0$/, "")}m`;
	if (value >= 1e3) return `${(value / 1e3).toFixed(1).replace(/\.0$/, "")}k`;
	return String(Math.round(value));
}
function formatDiscordFooterDate(timestamp) {
	if (!Number.isFinite(timestamp) || timestamp <= 0) return null;
	const date = new Date(timestamp);
	if (Number.isNaN(date.getTime())) return null;
	const year = date.getFullYear();
	const month = String(date.getMonth() + 1).padStart(2, "0");
	const day = String(date.getDate()).padStart(2, "0");
	return `${year}-${month}-${day}`;
}
function formatDiscordFooterDuration(ms) {
	if (!Number.isFinite(ms) || ms < 0) return null;
	const totalSeconds = Math.max(0, Math.round(ms / 1e3));
	const minutes = Math.floor(totalSeconds / 60);
	const seconds = totalSeconds % 60;
	if (minutes > 0) return `${minutes}m ${seconds}s`;
	return `${seconds}s`;
}
function shortenDiscordFooterPath(value) {
	if (typeof value !== "string" || !value.trim()) return null;
	const raw = value.trim();
	const home = process.env.HOME;
	if (home && raw === home) return "~";
	if (home && raw.startsWith(`${home}/`)) return `~/${raw.slice(home.length + 1)}`;
	return raw;
}
function formatDiscordFooterModel(value) {
	if (typeof value !== "string" || !value.trim()) return null;
	const raw = value.trim();
	return raw.includes("/") ? raw.split("/").filter(Boolean).pop() ?? raw : raw;
}
function formatDiscordFooterUsageSummary(value) {
	if (typeof value !== "string" || !value.trim()) return null;
	return value.trim();
}
function formatDiscordFooterLine(params) {
	const usage = params.usage;
	if (!usage) return null;
	const inputText = formatDiscordFooterTokenAmount(usage.input);
	const outputText = formatDiscordFooterTokenAmount(usage.output);
	const parts = [];
	const model = formatDiscordFooterModel(params.model);
	const thinking = typeof params.thinking === "string" && params.thinking ? params.thinking : null;
	if (model) parts.push(`**Model:** ${model}`);
	if (thinking) parts.push(`\u{1F9E0} ${thinking}`);
	const cwd = shortenDiscordFooterPath(params.cwd);
	if (cwd) parts.push(`CWD: ${cwd}`);
	const contextUsed = formatDiscordFooterTokenAmount(params.contextUsed);
	const contextLimit = formatDiscordFooterTokenAmount(params.contextLimit);
	if (contextUsed && contextLimit) {
		const pct = Math.round(params.contextUsed / params.contextLimit * 100);
		parts.push(`Context: ${contextUsed} / ${contextLimit} (${Number.isFinite(pct) ? pct : 0}%)`);
	} else if (contextLimit) parts.push(`Context: ? / ${contextLimit}`);
	if (inputText || outputText) parts.push(`Tokens: ${inputText ? `in ${inputText}` : ""}${inputText && outputText ? " " : ""}${outputText ? `out ${outputText}` : ""}`);
	const usageSummary = formatDiscordFooterUsageSummary(params.usageSummary);
	if (usageSummary) parts.push(`Usage: ${usageSummary}`);
	const duration = formatDiscordFooterDuration(params.durationMs);
	if (duration) parts.push(`\u23F1 ${duration}`);
	const cwd = shortenDiscordFooterPath(params.cwd);
	if (cwd) parts.push(`\u{1F4C2} ${cwd}`);
	return parts.length ? parts.join(" | ") : null;
}
```

### 2. Replace `formatResponseUsageLine` with try-catch dispatch

Replace the one-liner with:

```javascript
const formatResponseUsageLine = (params) => {
	try {
		if (params.channel === "discord") return formatDiscordFooterLine(params);
		return formatTelegramFooterLine(params);
	} catch (e) {
		console.warn("[footer] formatResponseUsageLine:", e);
		return null;
	}
};
```

### 3. Replace `appendUsageLine` with channel-aware + try-catch

Replace the original function (2-arg, no try-catch) with:

```javascript
const appendUsageLine = (payloads, line, channel) => {
	try {
		const isDiscord = channel === "discord";
		const decoratedLine = isDiscord ? `\n────────\n${line}` : `────\n${line}`;
		let index = -1;
		for (let i = payloads.length - 1; i >= 0; i -= 1) if (payloads[i]?.text) {
			index = i;
			break;
		}
		if (index === -1) return [...payloads, { text: decoratedLine }];
		const existing = payloads[index];
		const existingText = existing.text ?? "";
		const separator = existingText.endsWith("\n") ? "\n" : "\n";
		const next = {
			...existing,
			text: `${existingText}${separator}${decoratedLine}`
		};
		const updated = payloads.slice();
		updated[index] = next;
		return updated;
	} catch (e) {
		console.warn("[footer] appendUsageLine:", e);
		return payloads;
	}
};
```

### 4. Move `channel` declaration outside the usage if-block

Find:
```javascript
const responseUsageMode = resolveResponseUsageMode(...);
if (responseUsageMode !== "off" && hasNonzeroUsage(usage)) {
```

Insert after `responseUsageMode` line:
```javascript
const channel = sessionCtx.OriginatingChannel ?? sessionCtx.Surface ?? sessionCtx.Provider ?? activeSessionEntry?.channel ?? "";
```

Then **remove** the old `const channel = ...` line from inside the if-block.

### 5. Add `channel` param to `formatResponseUsageLine` call

Add `channel` to the params object passed to `formatResponseUsageLine`:
```javascript
// Before:
				usageSummary: providerUsageSummary
			});
// After:
				usageSummary: providerUsageSummary,
				channel
			});
```

### 6. Wrap `appendUsageLine` call in try-catch

```javascript
// Before:
		if (responseUsageLine) finalPayloads = appendUsageLine(finalPayloads, responseUsageLine);
// After:
		try {
			if (responseUsageLine) finalPayloads = appendUsageLine(finalPayloads, responseUsageLine, channel);
		} catch (e) {
			console.warn("[footer] appendUsageLine call:", e);
		}
```

### Verification

After each edit, run:
```bash
node --check /path/to/agent-runner.runtime-*.js
```
Then restart the gateway.

## Safety

- Do not edit secrets or OpenClaw config for this workflow.
- Do not guess if code patterns changed; stop and report the blocker.
- Prefer backup + `node --check` + Gateway status verification.
- The patch is Discord-specific and does NOT affect Telegram or Feishu footer behavior.
- Always wrap footer code in try-catch — footer failure should NEVER block message dispatch.
- Provider usage can be fetched for footer display when available; do not reintroduce a manual `/usage tokens` gate for the shared footer.
