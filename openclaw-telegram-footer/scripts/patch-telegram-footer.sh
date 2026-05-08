#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check}"
OPENCLAW_ROOT="${OPENCLAW_ROOT:-$HOME/.npm-global/lib/node_modules/openclaw}"
DIST_DIR="$OPENCLAW_ROOT/dist"

usage() {
  cat <<'EOF'
Usage:
  ~/.openclaw/scripts/patch-telegram-footer.sh --check
  ~/.openclaw/scripts/patch-telegram-footer.sh --apply

What it does:
  - Finds the active OpenClaw agent-runner runtime bundle.
  - Replaces the built-in response usage footer format with the local Telegram footer format:
    Model | Session | Context | Tokens | Time | CWD
  - Separates footer from reply body with a `────` visual separator
  - Backs up the target bundle before writing.
  - Runs node --check after patching.

After --apply, restart OpenClaw Gateway:
  openclaw gateway restart
  openclaw gateway status
EOF
}

case "$MODE" in
  --check|--apply) ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "Unknown mode: $MODE" >&2; usage; exit 2 ;;
esac

if [[ ! -d "$DIST_DIR" ]]; then
  echo "OpenClaw dist dir not found: $DIST_DIR" >&2
  exit 1
fi

TARGET="$(grep -Rsl "formatResponseUsageLine" "$DIST_DIR"/agent-runner.runtime-*.js 2>/dev/null | head -n 1 || true)"
if [[ -z "${TARGET:-}" ]]; then
  TARGET="$(grep -Rsl "formatResponseUsageLine" "$DIST_DIR"/*.js 2>/dev/null | grep 'agent-runner\.runtime' | head -n 1 || true)"
fi
if [[ -z "${TARGET:-}" ]]; then
  echo "Could not find agent-runner runtime bundle under: $DIST_DIR" >&2
  exit 1
fi

echo "Target: $TARGET"

python3 - "$MODE" "$TARGET" <<'PY'
from __future__ import annotations
from pathlib import Path
import re, shutil, sys, time

mode = sys.argv[1]
path = Path(sys.argv[2])
s = path.read_text()

MARKERS = [
    'function formatTelegramFooterTokenAmount',
    'function formatTelegramFooterLine',
    'model: modelUsed,',
    'contextUsed: usagePromptTokens,',
    'thinking: normalizeOptionalString(followupRun.run.thinkLevel),',
    'cwd: followupRun.run.workspaceDir',
	'const decoratedLine = `────\\n${line}`;'
]

missing = [m for m in MARKERS if m not in s]
if mode == '--check':
    if missing:
        print('Patch status: missing')
        for m in missing:
            print(f'  missing: {m}')
        sys.exit(3)
    print('Patch status: present')
    sys.exit(0)

changed = False

def replace_once(old: str, new: str, label: str):
    global s, changed
    if old in s:
        s = s.replace(old, new, 1)
        changed = True
        print(f'patched: {label}')
        return
    if new in s:
        print(f'already: {label}')
        return
    raise SystemExit(f'Could not patch {label}: expected code pattern not found. OpenClaw may have changed; inspect manually.')

old_func = '''const formatResponseUsageLine = (params) => {
	const usage = params.usage;
	if (!usage) return null;
	const input = usage.input;
	const output = usage.output;
	if (typeof input !== "number" && typeof output !== "number") return null;
	const inputLabel = typeof input === "number" ? formatTokenCount(input) : "?";
	const outputLabel = typeof output === "number" ? formatTokenCount(output) : "?";
	const cacheRead = typeof usage.cacheRead === "number" ? usage.cacheRead : void 0;
	const cacheWrite = typeof usage.cacheWrite === "number" ? usage.cacheWrite : void 0;
	const cost = params.showCost && typeof input === "number" && typeof output === "number" ? estimateUsageCost({
		usage: {
			input,
			output,
			cacheRead: usage.cacheRead,
			cacheWrite: usage.cacheWrite
		},
		cost: params.costConfig
	}) : void 0;
	const costLabel = params.showCost ? formatUsd(cost) : void 0;
	return `Usage: ${inputLabel} in / ${outputLabel} out${typeof cacheRead === "number" && cacheRead > 0 || typeof cacheWrite === "number" && cacheWrite > 0 ? ` · cache ${formatTokenCount(cacheRead ?? 0)} cached / ${formatTokenCount(cacheWrite ?? 0)} new` : ""}${costLabel ? ` · est ${costLabel}` : ""}`;
};'''
new_func = '''function formatTelegramFooterTokenAmount(value) {
	if (!Number.isFinite(value) || value <= 0) return null;
	if (value >= 1e6) return `${(value / 1e6).toFixed(1).replace(/\\.0$/, "")}m`;
	if (value >= 1e3) return `${(value / 1e3).toFixed(1).replace(/\\.0$/, "")}k`;
	return String(Math.round(value));
}
function formatTelegramFooterDate(timestamp) {
	if (!Number.isFinite(timestamp) || timestamp <= 0) return null;
	const date = new Date(timestamp);
	if (Number.isNaN(date.getTime())) return null;
	const year = date.getFullYear();
	const month = String(date.getMonth() + 1).padStart(2, "0");
	const day = String(date.getDate()).padStart(2, "0");
	return `${year}-${month}-${day}`;
}
function formatTelegramFooterDuration(ms) {
	if (!Number.isFinite(ms) || ms < 0) return null;
	const totalSeconds = Math.max(0, Math.round(ms / 1e3));
	const minutes = Math.floor(totalSeconds / 60);
	const seconds = totalSeconds % 60;
	if (minutes > 0) return `${minutes}m ${seconds}s`;
	return `${seconds}s`;
}
function shortenTelegramFooterPath(value) {
	if (typeof value !== "string" || !value.trim()) return null;
	const raw = value.trim();
	const home = process.env.HOME;
	if (home && raw === home) return "~";
	if (home && raw.startsWith(`${home}/`)) return `~/${raw.slice(home.length + 1)}`;
	return raw;
}
function formatTelegramFooterModel(value) {
	if (typeof value !== "string" || !value.trim()) return null;
	const raw = value.trim();
	return raw.includes("/") ? raw.split("/").filter(Boolean).pop() ?? raw : raw;
}
function formatTelegramFooterLine(params) {
	const usage = params.usage;
	if (!usage) return null;
	const inputText = formatTelegramFooterTokenAmount(usage.input);
	const outputText = formatTelegramFooterTokenAmount(usage.output);
	const parts = [];
	const model = formatTelegramFooterModel(params.model);
	const thinking = typeof params.thinking === "string" && params.thinking ? params.thinking : null;
	if (model) parts.push(`Model: ${model}`);
	if (thinking) parts.push(`Thinking: ${thinking}`);
	const sessionId = typeof params.sessionId === "string" && params.sessionId ? params.sessionId.slice(0, 8) : typeof params.sessionKey === "string" ? params.sessionKey.slice(0, 8) : null;
	const sessionDate = formatTelegramFooterDate(params.startedAt);
	if (sessionId) parts.push(`Session: ${sessionId}${sessionDate ? ` (${sessionDate})` : ""}`);
	const contextUsed = formatTelegramFooterTokenAmount(params.contextUsed);
	const contextLimit = formatTelegramFooterTokenAmount(params.contextLimit);
	if (contextUsed && contextLimit) {
		const pct = Math.round(params.contextUsed / params.contextLimit * 100);
		parts.push(`Context: ${contextUsed} / ${contextLimit} (${Number.isFinite(pct) ? pct : 0}%)`);
	} else if (contextLimit) parts.push(`Context: ? / ${contextLimit}`);
	if (inputText || outputText) parts.push(`Tokens: ${inputText ? `in ${inputText}` : ""}${inputText && outputText ? " " : ""}${outputText ? `out ${outputText}` : ""}`);
	const duration = formatTelegramFooterDuration(params.durationMs);
	if (duration) parts.push(`Time: ${duration}`);
	const cwd = shortenTelegramFooterPath(params.cwd);
	if (cwd) parts.push(`CWD: ${cwd}`);
	return parts.length ? parts.join(" | ") : null;
}
const formatResponseUsageLine = (params) => formatTelegramFooterLine(params);'''
try:
    replace_once(old_func, new_func, 'response usage formatter')
except SystemExit as exc:
    # Already partially patched; skip full replace — thinking fix below handles it
    print(f'Full replace skipped (already patched runtime, {exc})')

old_call = '''			let formatted = formatResponseUsageLine({
				usage,
				showCost,
				costConfig: showCost ? resolveModelCostConfig({
					provider: providerUsed,
					model: modelUsed,
					config: cfg
				}) : void 0
			});
			if (formatted && responseUsageMode === "full" && sessionKey) formatted = `${formatted} · session ${sessionKey}`;
			if (formatted) responseUsageLine = formatted;'''
new_call = '''			let formatted = formatResponseUsageLine({
				usage,
				showCost,
				costConfig: showCost ? resolveModelCostConfig({
					provider: providerUsed,
					model: modelUsed,
					config: cfg
				}) : void 0,
				model: modelUsed,
				sessionId: followupRun.run.sessionId,
				sessionKey,
				startedAt: runStartedAt,
				thinking: normalizeOptionalString(followupRun.run.thinkLevel),
				contextUsed: usagePromptTokens,
				contextLimit: contextTokensUsed,
				durationMs: Date.now() - runStartedAt,
				cwd: followupRun.run.workspaceDir
			});
			if (formatted) responseUsageLine = formatted;'''
try:
    replace_once(old_call, new_call, 'response usage callsite')
except SystemExit as exc:
    print(f'Callsite replace skipped (already patched runtime, {exc})')

old_append = '''const appendUsageLine = (payloads, line) => {
	let index = -1;
	for (let i = payloads.length - 1; i >= 0; i -= 1) if (payloads[i]?.text) {
		index = i;
		break;
	}
	if (index === -1) return [...payloads, { text: line }];
	const existing = payloads[index];
	const existingText = existing.text ?? "";
	const separator = existingText.endsWith("\n") ? "" : "\n";
	const next = {
		...existing,
		text: `${existingText}${separator}${line}`
	};
	const updated = payloads.slice();
	updated[index] = next;
	return updated;
};'''
new_append = '''const appendUsageLine = (payloads, line) => {
	const decoratedLine = `────\\n${line}`;
	let index = -1;
	for (let i = payloads.length - 1; i >= 0; i -= 1) if (payloads[i]?.text) {
		index = i;
		break;
	}
	if (index === -1) return [...payloads, { text: decoratedLine }];
	const existing = payloads[index];
	const existingText = existing.text ?? "";
	const separator = existingText.endsWith("\\n") ? "\\n" : "\\n";
	const next = {
		...existing,
		text: `${existingText}${separator}${decoratedLine}`
	};
	const updated = payloads.slice();
	updated[index] = next;
	return updated;
};'''
try:
    replace_once(old_append, new_append, 'footer visual separator')
except SystemExit as exc:
    print(f'Visual separator replace skipped (already patched runtime, {exc})')

# Thinking fallback: if formatTelegramFooterLine exists but missing thinking field
if 'thinking: normalizeOptionalString' not in s and 'function formatTelegramFooterLine' in s:
    print('Adding missing Thinking field to already-patched runtime...')
    for ins_pat, ins_new, ins_label in [
        (
            'const model = formatTelegramFooterModel(params.model);',
            'const model = formatTelegramFooterModel(params.model);\n\tconst thinking = typeof params.thinking === \"string\" && params.thinking ? params.thinking : null;',
            'thinking declaration'
        ),
        (
            'if (model) parts.push(`Model: ${model}`);',
            'if (model) parts.push(`Model: ${model}`);\n\tif (thinking) parts.push(`Thinking: ${thinking}`);',
            'Thinking line push'
        ),
        (
            'startedAt: runStartedAt,',
            'startedAt: runStartedAt,\n\t\t\t\tthinking: normalizeOptionalString(followupRun.run.thinkLevel),',
            'thinking param in callsite'
        ),
    ]:
        if ins_pat in s and ins_new.replace('\\n', '\n') not in s:
            s = s.replace(ins_pat, ins_new, 1)
            changed = True
            print(f'  patched: {ins_label}')
        elif ins_new.replace('\\n', '\n') in s:
            print(f'  already: {ins_label}')
        else:
            print(f'  skip: {ins_label} (pattern not found)')


missing_after = [m for m in MARKERS if m not in s]
if missing_after:
    raise SystemExit('Patch incomplete; missing markers after patch: ' + ', '.join(missing_after))

if changed:
    backup = path.with_suffix(path.suffix + f'.bak-telegram-footer-{time.strftime("%Y%m%d-%H%M%S")}')
    shutil.copy2(path, backup)
    path.write_text(s)
    print(f'Backup: {backup}')
    print('Patch status: applied')
else:
    print('Patch status: already present')
PY

node --check "$TARGET"
echo "node --check: ok"

echo
echo "Next steps if you ran --apply:"
echo "  openclaw gateway restart"
echo "  openclaw gateway status"
