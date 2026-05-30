#!/usr/bin/env bash
set -euo pipefail
# patch-telegram-footer.sh — Make Telegram/Discord footer use shared footer-shared.mjs
#
# After shared module introduction (2026-05-12), this script no longer injects
# formatting code into the runtime.  Instead it adds a single import from
# footer-shared.mjs and replaces the two channel-specific footer functions
# with thin wrappers that call generateFooterLine().
#
# Usage:
#   patch-telegram-footer.sh --check
#   patch-telegram-footer.sh --apply

MODE="${1:---check}"
SHARED_MODULE="$HOME/.openclaw/footer-shared.mjs"
SHARED_MODULE_ASSET="$HOME/.openclaw/workspace/skills/openclaw-footer/assets/footer-shared.mjs"
OPENCLAW_ROOT="${OPENCLAW_ROOT:-$HOME/.npm-global/lib/node_modules/openclaw}"
DIST_DIR="$OPENCLAW_ROOT/dist"

usage() {
  cat <<'EOF'
Usage:
  patch-telegram-footer.sh --check
  patch-telegram-footer.sh --apply

Shares a single footer-shared.mjs across Telegram and Discord channels.
The script adds an ESM import of footer-shared.mjs to the agent-runner
runtime and replaces formatTelegramFooterLine / formatDiscordFooterLine
with thin wrappers that call generateFooterLine().

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

# ---------- locate runtime bundle ----------
TARGET="$(grep -Rsl "formatResponseUsageLine" "$DIST_DIR"/agent-runner.runtime-*.js 2>/dev/null | head -n 1 || true)"
if [[ -z "${TARGET:-}" ]]; then
  TARGET="$(grep -Rsl "formatResponseUsageLine" "$DIST_DIR"/*.js 2>/dev/null | grep 'agent-runner\.runtime' | head -n 1 || true)"
fi
if [[ -z "${TARGET:-}" ]]; then
  echo "Could not find agent-runner runtime bundle under: $DIST_DIR" >&2
  exit 1
fi

echo "Runtime target: $TARGET"
echo "Shared module: $SHARED_MODULE"

# ---------- Python payload ----------
python3 - "$MODE" "$TARGET" "$SHARED_MODULE" "$SHARED_MODULE_ASSET" <<'PY'
from __future__ import annotations
from pathlib import Path
import shutil, sys, time

mode = sys.argv[1]
path = Path(sys.argv[2])
shared_path = Path(sys.argv[3])
shared_asset = Path(sys.argv[4])
s = path.read_text()

# ---- markers for --check ----
IMPORT_MARKER = 'import { generateFooterLine } from "file:///home/momo/.openclaw/footer-shared.mjs";'
TG_WRAPPER_MARKER  = 'generateFooterLine({ ...params, style: "telegram" })'
DC_WRAPPER_MARKER  = 'generateFooterLine({ ...params, style: "discord" })'
SESSION_CONTEXT_MARKER = 'contextUsed: typeof activeSessionEntry?.totalTokens === "number" && Number.isFinite(activeSessionEntry.totalTokens) ? activeSessionEntry.totalTokens : usagePromptTokens'

def check():
    ok = True
    if not shared_path.exists():
        print(f"Shared module missing: {shared_path}")
        ok = False
    if IMPORT_MARKER not in s:
        print("runtime missing: shared-module import")
        ok = False
    if TG_WRAPPER_MARKER not in s:
        print("runtime missing: Telegram thin wrapper")
        ok = False
    if DC_WRAPPER_MARKER not in s:
        print("runtime missing: Discord thin wrapper")
        ok = False
    if SESSION_CONTEXT_MARKER not in s:
        print("runtime missing: footer session-context source patch")
        ok = False
    if ok:
        print("Patch status: present")
    else:
        print("Patch status: missing")
        sys.exit(3)

if mode == "--check":
    check()
    sys.exit(0)

# ---- ensure shared module exists (copy from skill asset if needed) ----
if not shared_path.exists():
    if shared_asset.exists():
        shutil.copy2(shared_asset, shared_path)
        print(f"Shared module restored from asset: {shared_asset}")
    else:
        raise SystemExit(f"Shared footer module not found: {shared_path}\nAsset also missing: {shared_asset}\nRestore the skill bundle first.")

# ---- 1) add import after the last existing import ----
if IMPORT_MARKER not in s:
    # Find the last import line that starts with "import "
    lines = s.splitlines(keepends=True)
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("import "):
            last_import_idx = i
    if last_import_idx < 0:
        raise SystemExit("Could not locate import section in runtime bundle.")
    lines.insert(last_import_idx + 1, IMPORT_MARKER + "\n")
    s = "".join(lines)
    print("patched: shared-module import")
else:
    print("already: shared-module import")

# ---- 2) replace formatTelegramFooterLine body ----
old_tg = '''function formatTelegramFooterLine(params) {
\tconst usage = params.usage;
\tif (!usage) return null;
\tconst inputText = formatTelegramFooterTokenAmount(usage.input);
\tconst outputText = formatTelegramFooterTokenAmount(usage.output);
\tconst parts = [];
\tconst model = formatTelegramFooterModel(params.model);
\tconst thinking = typeof params.thinking === "string" && params.thinking ? params.thinking : null;
\tif (model) parts.push(`Model: ${model}`);
\tif (thinking) parts.push(`Thinking: ${thinking}`);
\tconst sessionId = typeof params.sessionId === "string" && params.sessionId ? params.sessionId.slice(0, 8) : typeof params.sessionKey === "string" ? params.sessionKey.slice(0, 8) : null;
\tconst sessionDate = formatTelegramFooterDate(params.startedAt);
\tif (sessionId) parts.push(`Session: ${sessionId}${sessionDate ? ` (${sessionDate})` : ""}`);
\tconst contextUsed = formatTelegramFooterTokenAmount(params.contextUsed);
\tconst contextLimit = formatTelegramFooterTokenAmount(params.contextLimit);
\tif (contextUsed && contextLimit) {
\t\tconst pct = Math.round(params.contextUsed / params.contextLimit * 100);
\t\tparts.push(`Context: ${contextUsed} / ${contextLimit} (${Number.isFinite(pct) ? pct : 0}%)`);
\t} else if (contextLimit) parts.push(`Context: ? / ${contextLimit}`);
\tif (inputText || outputText) parts.push(`Tokens: ${inputText ? `in ${inputText}` : ""}${inputText && outputText ? " " : ""}${outputText ? `out ${outputText}` : ""}`);
\tconst usageSummary = formatTelegramFooterUsageSummary(params.usageSummary);
\tif (usageSummary) parts.push(`Usage: ${usageSummary}`);
\treturn parts.length ? parts.join(" | ") : null;
}'''
new_tg = '''function formatTelegramFooterLine(params) {
\treturn generateFooterLine({ ...params, style: "telegram" });
}'''

# ---- 3) replace formatDiscordFooterLine body ----
old_dc = '''function formatDiscordFooterLine(params) {
\tconst usage = params.usage;
\tif (!usage) return null;
\tconst inputText = formatDiscordFooterTokenAmount(usage.input);
\tconst outputText = formatDiscordFooterTokenAmount(usage.output);
\tconst parts = [];
\tconst model = formatDiscordFooterModel(params.model);
\tconst thinking = typeof params.thinking === "string" && params.thinking ? params.thinking : null;
\tif (model) parts.push(`**Model:** ${model}`);
\tif (thinking) parts.push(`\\u{1F9E0} ${thinking}`);
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
\tif (duration) parts.push(`\\u23F1 ${duration}`);
\tconst cwd = shortenDiscordFooterPath(params.cwd);
\tif (cwd) parts.push(`\\u{1F4C2} ${cwd}`);
\treturn parts.length ? parts.join(" | ") : null;
}'''
new_dc = '''function formatDiscordFooterLine(params) {
\treturn generateFooterLine({ ...params, style: "discord" });
}'''

changed = False

if new_tg in s:
    print("already: Telegram thin wrapper")
elif old_tg in s:
    s = s.replace(old_tg, new_tg, 1)
    changed = True
    print("patched: Telegram thin wrapper")
else:
    print("skip: Telegram — unrecognized function body (may already be patched)")

if new_dc in s:
    print("already: Discord thin wrapper")
elif old_dc in s:
    s = s.replace(old_dc, new_dc, 1)
    changed = True
    print("patched: Discord thin wrapper")
else:
    print("skip: Discord — unrecognized function body (may already be patched)")

# ---- 4) make footer Context use session-store totalTokens/contextTokens, not provider prompt usage ----
old_context_callsite = "\t\tconst channel = sessionCtx.OriginatingChannel ?? sessionCtx.Surface ?? sessionCtx.Provider ?? activeSessionEntry?.channel ?? \"\";\n\t\tif (hasNonzeroUsage(usage)) {"
new_context_callsite = "\t\tconst channel = sessionCtx.OriginatingChannel ?? sessionCtx.Surface ?? sessionCtx.Provider ?? activeSessionEntry?.channel ?? \"\";\n\t\tactiveSessionEntry = refreshSessionEntryFromStore({\n\t\t\tstorePath,\n\t\t\tsessionKey,\n\t\t\tfallbackEntry: activeSessionEntry,\n\t\t\tactiveSessionStore\n\t\t});\n\t\tif (hasNonzeroUsage(usage)) {"
old_context_fields = "\t\t\t\tcontextUsed: usagePromptTokens,\n\t\t\t\tcontextLimit: contextTokensUsed,"
new_context_fields = "\t\t\t\tcontextUsed: typeof activeSessionEntry?.totalTokens === \"number\" && Number.isFinite(activeSessionEntry.totalTokens) ? activeSessionEntry.totalTokens : usagePromptTokens,\n\t\t\t\tcontextLimit: typeof activeSessionEntry?.contextTokens === \"number\" && Number.isFinite(activeSessionEntry.contextTokens) ? activeSessionEntry.contextTokens : contextTokensUsed,"

if SESSION_CONTEXT_MARKER in s:
    print("already: footer session-context source patch")
else:
    if old_context_callsite in s:
        s = s.replace(old_context_callsite, new_context_callsite, 1)
        changed = True
        print("patched: pre-footer session refresh")
    else:
        print("skip: pre-footer session refresh — unrecognized callsite or already refreshed")
    if old_context_fields in s:
        s = s.replace(old_context_fields, new_context_fields, 1)
        changed = True
        print("patched: footer session-context source")
    else:
        print("skip: footer context fields — unrecognized callsite")

# ---- final checks ----
check_ok = True
if IMPORT_MARKER not in s:
    print("ERROR: import not present after apply")
    check_ok = False
if TG_WRAPPER_MARKER not in s:
    print("ERROR: Telegram wrapper not present after apply")
    check_ok = False
if DC_WRAPPER_MARKER not in s:
    print("ERROR: Discord wrapper not present after apply")
    check_ok = False
if SESSION_CONTEXT_MARKER not in s:
    print("ERROR: footer session-context source patch not present after apply")
    check_ok = False
if not check_ok:
    raise SystemExit("Patch incomplete after apply; inspect manually.")

if changed:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = path.with_suffix(path.suffix + f".bak-telegram-footer-{stamp}")
    shutil.copy2(path, backup)
    path.write_text(s)
    print(f"Backup: {backup}")
    print("Patch status: applied")
else:
    print("Patch status: already present")
PY

node --check "$TARGET"
echo "node --check: ok"
echo
echo "Next (after --apply):"
echo "  openclaw gateway restart"
echo "  openclaw gateway status"
