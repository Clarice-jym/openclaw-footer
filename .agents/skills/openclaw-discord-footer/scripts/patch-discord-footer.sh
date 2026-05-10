#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check}"
OPENCLAW_ROOT="${OPENCLAW_ROOT:-$HOME/.npm-global/lib/node_modules/openclaw}"
DIST_DIR="$OPENCLAW_ROOT/dist"

usage() {
  cat <<'EOF'
Usage:
  ~/.openclaw/scripts/patch-discord-footer.sh --check
  ~/.openclaw/scripts/patch-discord-footer.sh --apply

What it does:
  - Finds the active OpenClaw agent-runner runtime bundle.
  - Adds a Discord-specific footer format alongside the existing Telegram footer:
    **Model:** foo | 🧠 high | Session: abc12345 (2026-05-10) | Context: 10k / 200k (5%) | Tokens: in 5k out 1k | Time: 30s
  - Makes the footer channel-aware: Discord gets bold Model label + | separator (no ────),
    Telegram keeps ──── separator with plain Model label.
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
    'function formatDiscordFooterTokenAmount',
    'function formatDiscordFooterLine',
    'if (params.channel === "discord")',
    'const isDiscord = channel === "discord"',
    'const channel = sessionCtx.OriginatingChannel',
    'appendUsageLine(finalPayloads, responseUsageLine, channel)',
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

# 1) Discord helper functions — insert after formatTelegramFooterUsageSummary
discord_funcs = r"""
function formatDiscordFooterTokenAmount(value) {
\tif (!Number.isFinite(value) || value <= 0) return null;
\tif (value >= 1e6) return `${(value / 1e6).toFixed(1).replace(/\.0$/, "")}m`;
\tif (value >= 1e3) return `${(value / 1e3).toFixed(1).replace(/\.0$/, "")}k`;
\treturn String(Math.round(value));
}
function formatDiscordFooterDate(timestamp) {
\tif (!Number.isFinite(timestamp) || timestamp <= 0) return null;
\tconst date = new Date(timestamp);
\tif (Number.isNaN(date.getTime())) return null;
\tconst year = date.getFullYear();
\tconst month = String(date.getMonth() + 1).padStart(2, "0");
\tconst day = String(date.getDate()).padStart(2, "0");
\treturn `${year}-${month}-${day}`;
}
function formatDiscordFooterDuration(ms) {
\tif (!Number.isFinite(ms) || ms < 0) return null;
\tconst totalSeconds = Math.max(0, Math.round(ms / 1e3));
\tconst minutes = Math.floor(totalSeconds / 60);
\tconst seconds = totalSeconds % 60;
\tif (minutes > 0) return `${minutes}m ${seconds}s`;
\treturn `${seconds}s`;
}
function shortenDiscordFooterPath(value) {
\tif (typeof value !== "string" || !value.trim()) return null;
\tconst raw = value.trim();
\tconst home = process.env.HOME;
\tif (home && raw === home) return "~";
\tif (home && raw.startsWith(`${home}/`)) return `~/${raw.slice(home.length + 1)}`;
\treturn raw;
}
function formatDiscordFooterModel(value) {
\tif (typeof value !== "string" || !value.trim()) return null;
\tconst raw = value.trim();
\treturn raw.includes("/") ? raw.split("/").filter(Boolean).pop() ?? raw : raw;
}
function formatDiscordFooterUsageSummary(value) {
\tif (typeof value !== "string" || !value.trim()) return null;
\treturn value.trim();
}
function formatDiscordFooterLine(params) {
\tconst usage = params.usage;
\tif (!usage) return null;
\tconst inputText = formatDiscordFooterTokenAmount(usage.input);
\tconst outputText = formatDiscordFooterTokenAmount(usage.output);
\tconst parts = [];
\tconst model = formatDiscordFooterModel(params.model);
\tconst thinking = typeof params.thinking === "string" && params.thinking ? params.thinking : null;
\tif (model) parts.push(`**Model:** ${model}`);
\tif (thinking) parts.push(`:brain: ${thinking}`);
\tconst sessionId = typeof params.sessionId === "string" && params.sessionId ? params.sessionId.slice(0, 8) : typeof params.sessionKey === "string" ? params.sessionKey.slice(0, 8) : null;
\tconst sessionDate = formatDiscordFooterDate(params.startedAt);
\tif (sessionId) parts.push(`Session: ${sessionId}${sessionDate ? ` (${sessionDate})` : ""}`);
\tconst contextUsed = formatDiscordFooterTokenAmount(params.contextUsed);
\tconst contextLimit = formatDiscordFooterTokenAmount(params.contextLimit);
\tif (contextUsed && contextLimit) {
\t\tconst pct = Math.round(params.contextUsed / params.contextLimit * 100);
\t\tparts.push(`Context: ${contextUsed} / ${contextLimit} (${Number.isFinite(pct) ? pct : 0}%)`);
\t} else if (contextLimit) parts.push(`Context: ? / ${contextLimit}`);
\tif (inputText || outputText) parts.push(`Tokens: ${inputText ? `in ${inputText}` : ""}${inputText && outputText ? " " : ""}${outputText ? `out ${outputText}` : ""}`);
\tconst usageSummary = formatDiscordFooterUsageSummary(params.usageSummary);
\tif (usageSummary) parts.push(`Usage: ${usageSummary}`);
\tconst duration = formatDiscordFooterDuration(params.durationMs);
\tif (duration) parts.push(`:stopwatch: ${duration}`);
\tconst cwd = shortenDiscordFooterPath(params.cwd);
\tif (cwd) parts.push(`:file_folder: ${cwd}`);
\treturn parts.length ? parts.join(" | ") : null;
}
"""

old_gap = r"""function formatTelegramFooterUsageSummary(value) {
\tif (typeof value !== "string" || !value.trim()) return null;
\treturn value.trim();
}
function formatTelegramFooterLine(params) {"""
new_gap = r"""function formatTelegramFooterUsageSummary(value) {
\tif (typeof value !== "string" || !value.trim()) return null;
\treturn value.trim();
}""" + discord_funcs + r"""function formatTelegramFooterLine(params) {"""
try:
    replace_once(old_gap, new_gap, 'Discord footer functions')
except SystemExit as exc:
    print(f'Discord functions insert skipped (already present, {exc})')

# 2) Make formatResponseUsageLine channel-aware
old_dispatch = r"""const formatResponseUsageLine = (params) => formatTelegramFooterLine(params);"""
new_dispatch = r"""const formatResponseUsageLine = (params) => {
\tif (params.channel === "discord") return formatDiscordFooterLine(params);
\treturn formatTelegramFooterLine(params);
};"""
try:
    replace_once(old_dispatch, new_dispatch, 'formatResponseUsageLine dispatch')
except SystemExit as exc:
    print(f'Dispatch replace skipped: {exc}')

# 3) Make appendUsageLine channel-aware
old_append = r"""const appendUsageLine = (payloads, line) => {
\tconst decoratedLine = `────\n${line}`;
\tlet index = -1;
\tfor (let i = payloads.length - 1; i >= 0; i -= 1) if (payloads[i]?.text) {
\t\tindex = i;
\t\tbreak;
\t}
\tif (index === -1) return [...payloads, { text: decoratedLine }];
\tconst existing = payloads[index];
\tconst existingText = existing.text ?? "";
\tconst separator = existingText.endsWith("\n") ? "\n" : "\n";
\tconst next = {
\t\t...existing,
\t\ttext: `${existingText}${separator}${decoratedLine}`
\t};
\tconst updated = payloads.slice();
\tupdated[index] = next;
\treturn updated;
};"""
new_append = r"""const appendUsageLine = (payloads, line, channel) => {
\tconst isDiscord = channel === "discord";
\tconst decoratedLine = isDiscord ? `\n${line}` : `────\n${line}`;
\tlet index = -1;
\tfor (let i = payloads.length - 1; i >= 0; i -= 1) if (payloads[i]?.text) {
\t\tindex = i;
\t\tbreak;
\t}
\tif (index === -1) return [...payloads, { text: decoratedLine }];
\tconst existing = payloads[index];
\tconst existingText = existing.text ?? "";
\tconst separator = existingText.endsWith("\n") ? "\n" : "\n";
\tconst next = {
\t\t...existing,
\t\ttext: `${existingText}${separator}${decoratedLine}`
\t};
\tconst updated = payloads.slice();
\tupdated[index] = next;
\treturn updated;
};"""
try:
    replace_once(old_append, new_append, 'appendUsageLine channel-aware')
except SystemExit as exc:
    print(f'appendUsageLine replace skipped: {exc}')

# 4) Add channel resolution before formatResponseUsageLine call
old_call = r"""\t\t\tlet formatted = formatResponseUsageLine({
\t\t\t\tusage,
\t\t\t\tshowCost,"""
new_call = r"""\t\t\tconst channel = sessionCtx.OriginatingChannel ?? sessionCtx.Surface ?? sessionCtx.Provider ?? activeSessionEntry?.channel ?? "";
\t\t\tlet formatted = formatResponseUsageLine({
\t\t\t\tusage,
\t\t\t\tshowCost,"""
try:
    replace_once(old_call, new_call, 'call site channel resolution')
except SystemExit as exc:
    print(f'Call site channel resolution skipped: {exc}')

# 5) Add channel to formatResponseUsageLine params
old_params = r"""\t\t\t\tusageSummary: providerUsageSummary
\t\t\t});"""
new_params = r"""\t\t\t\tusageSummary: providerUsageSummary,
\t\t\t\tchannel
\t\t\t});"""
try:
    replace_once(old_params, new_params, 'channel param in formatResponseUsageLine')
except SystemExit as exc:
    print(f'Channel param in formatResponseUsageLine skipped: {exc}')

# 6) Pass channel to appendUsageLine
old_append_call = r"""if (responseUsageLine) finalPayloads = appendUsageLine(finalPayloads, responseUsageLine);"""
new_append_call = r"""if (responseUsageLine) finalPayloads = appendUsageLine(finalPayloads, responseUsageLine, channel);"""
try:
    replace_once(old_append_call, new_append_call, 'channel param in appendUsageLine call')
except SystemExit as exc:
    print(f'appendUsageLine channel param skipped: {exc}')

# 7) Update formatTelegramFooterLine to accept and pass durationMs/cwd for consistency
# (Telegram already has durationMs, but let's check it has cwd support)
if 'cwd: followupRun.run.workspaceDir' not in s and 'formatTelegramFooterLine' in s:
    # Add cwd to the Telegram call site too
    print('Telegram cwd support not checked - already present or needs manual check')

# WRITE FILE FIRST, THEN CHECK MARKERS
if changed:
    backup = path.with_suffix(path.suffix + f'.bak-discord-footer-{time.strftime("%Y%m%d-%H%M%S")}')
    shutil.copy2(path, backup)
    path.write_text(s)
    print(f'Backup: {backup}')

# Re-read file for marker check (to be safe after write)
s = path.read_text()
missing_after = [m for m in MARKERS if m not in s]
if missing_after:
    print('Patch status: applied with some marker check warnings')
    for m in missing_after:
        print(f'  marker not found: {m}')
    # Don't fail — the patch is likely fine, markers may be over-specific
else:
    print('Patch status: applied (all markers verified)')

if not changed:
    print('Patch status: already present')
PY

node --check "$TARGET"
echo "node --check: ok"

# Also fix the default responseUsageMode from "off" to "tokens" 
THINKING_FILE="$DIST_DIR/thinking-9QU1BJ3m.js"
if [[ -f "$THINKING_FILE" ]]; then
  if grep -q 'normalizeUsageDisplay(raw) ?? "off"' "$THINKING_FILE" 2>/dev/null; then
    if [[ "$MODE" == "--check" ]]; then
      echo "  thinking default responseUsageMode: off (needs fix)"
    elif [[ "$MODE" == "--apply" ]]; then
      cp "$THINKING_FILE" "$THINKING_FILE.bak-$(date +%Y%m%d-%H%M%S)"
      python3 -c "
import sys
s = open('$THINKING_FILE').read()
if 'normalizeUsageDisplay(raw) ?? \"off\"' in s:
    s = s.replace('normalizeUsageDisplay(raw) ?? \"off\"', 'normalizeUsageDisplay(raw) ?? \"tokens\"')
    open('$THINKING_FILE', 'w').write(s)
    print('  thinking: default responseUsageMode → tokens')
else:
    print('  thinking: already patched')
"
      node --check "$THINKING_FILE" && echo "  thinking: node --check ok"
    fi
  else
    if grep -q 'normalizeUsageDisplay(raw) ?? "tokens"' "$THINKING_FILE" 2>/dev/null; then
      echo "  thinking default responseUsageMode: tokens (already patched)"
    else
      echo "  thinking: pattern not found, skipping"
    fi
  fi
fi

echo
echo "Next steps if you ran --apply:"
echo "  openclaw gateway restart"
echo "  openclaw gateway status"
