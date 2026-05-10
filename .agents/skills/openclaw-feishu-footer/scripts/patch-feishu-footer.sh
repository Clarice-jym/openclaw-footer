#!/usr/bin/env bash
set -euo pipefail

MODE="apply"
MODE_VALUE=""
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --mode=*) MODE="mode"; MODE_VALUE="${arg#--mode=}" ;;
    --mode) MODE="mode" ;;
    note|body|status) [[ "$MODE" == "mode" && -z "$MODE_VALUE" ]] && MODE_VALUE="$arg" ;;
    *) ;;
  esac
done

RUNTIME="$HOME/.openclaw/npm/node_modules/@openclaw/feishu/dist/monitor.account-CUZxYkjE.js"
MODE_FILE="$HOME/.openclaw/feishu-footer-mode"

check_markers() {
  python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
markers = [
    'import { execFileSync } from "node:child_process";',
    'function formatFooterUsageWindow(window) {',
    'const footerUsageCache = new Map();',
    'meta.usage = resolveFooterUsageSummary(meta.modelProvider, meta.model);',
    'if (meta.usage) parts.push(`Usage: ${meta.usage}`);'
]
missing = [m for m in markers if m not in text]
if missing:
    print('MISSING')
    for m in missing:
        print(m)
    raise SystemExit(1)
print('OK')
PY
}

if [[ "$MODE" == "check" ]]; then
  check_markers
  exit 0
fi

if [[ "$MODE" == "mode" ]]; then
  case "$MODE_VALUE" in
    status|'')
      if [[ -f "$MODE_FILE" ]]; then cat "$MODE_FILE"; else echo note; fi
      ;;
    note|body)
      mkdir -p "$(dirname "$MODE_FILE")"
      printf '%s\n' "$MODE_VALUE" > "$MODE_FILE"
      echo "$MODE_VALUE"
      ;;
    *)
      echo "unsupported mode: $MODE_VALUE" >&2
      exit 2
      ;;
  esac
  exit 0
fi

python3 - "$RUNTIME" <<'PY'
from pathlib import Path
import shutil, sys, time
p = Path(sys.argv[1])
text = p.read_text()
orig = text
backup = p.with_suffix(p.suffix + f'.bak.{time.strftime("%Y%m%d-%H%M%S")}')

def rep(old, new, label):
    global text
    if old in text:
        text = text.replace(old, new, 1)
        print('patched', label)
    elif new in text:
        print('already', label)
    else:
        raise SystemExit(f'missing pattern for {label}')

rep('import fs from "node:fs";\nimport os from "node:os";\nimport path from "node:path";',
    'import fs from "node:fs";\nimport os from "node:os";\nimport path from "node:path";\nimport { execFileSync } from "node:child_process";',
    'child_process import')

rep('''function formatFooterDate(timestamp) {
\tif (!Number.isFinite(timestamp) || timestamp <= 0) return null;
\tconst date = new Date(normalizeEpochMs(timestamp));
\tif (Number.isNaN(date.getTime())) return null;
\tconst year = date.getFullYear();
\tconst month = String(date.getMonth() + 1).padStart(2, "0");
\tconst day = String(date.getDate()).padStart(2, "0");
\treturn `${year}-${month}-${day}`;
}
function formatFooterSessionLabel(sessionId, timestamp, fallback) {''',
'''function formatFooterDate(timestamp) {
\tif (!Number.isFinite(timestamp) || timestamp <= 0) return null;
\tconst date = new Date(normalizeEpochMs(timestamp));
\tif (Number.isNaN(date.getTime())) return null;
\tconst year = date.getFullYear();
\tconst month = String(date.getMonth() + 1).padStart(2, "0");
\tconst day = String(date.getDate()).padStart(2, "0");
\treturn `${year}-${month}-${day}`;
}
function formatFooterRemainingDuration(timestamp) {
\tif (!Number.isFinite(timestamp) || timestamp <= 0) return null;
\tconst diffMs = timestamp - Date.now();
\tif (!Number.isFinite(diffMs) || diffMs <= 0) return "0m";
\tconst totalMinutes = Math.ceil(diffMs / 6e4);
\tconst days = Math.floor(totalMinutes / 1440);
\tconst hours = Math.floor(totalMinutes % 1440 / 60);
\tconst minutes = totalMinutes % 60;
\tif (days > 0) return hours > 0 ? `${days}d ${hours}h` : `${days}d`;
\tif (hours > 0) return minutes > 0 ? `${hours}h ${minutes}m` : `${hours}h`;
\treturn `${minutes}m`;
}
function formatFooterUsageWindow(window) {
\tif (!window || typeof window !== "object") return null;
\tconst label = normalizeOptionalString(window.label);
\tconst usedPercent = Number.isFinite(window.usedPercent) ? window.usedPercent : null;
\tif (!label || usedPercent === null) return null;
\tconst left = Math.max(0, Math.min(100, 100 - Math.round(usedPercent)));
\tconst reset = formatFooterRemainingDuration(window.resetAt);
\treturn `${label} ${left}% left${reset ? ` ⏱${reset}` : ""}`;
}
const footerUsageCache = new Map();
function resolveFooterUsageProvider(modelProvider, model) {
\tconst rawProvider = normalizeOptionalString(modelProvider)?.toLowerCase();
\tif (rawProvider) {
\t\tif (rawProvider === "openai" || rawProvider === "openai-codex") return "openai-codex";
\t\tif (rawProvider === "anthropic") return "anthropic";
\t\tif (rawProvider === "google" || rawProvider === "gemini") return "gemini";
\t\tif (rawProvider === "deepseek") return "deepseek";
\t}
\tconst rawModel = normalizeOptionalString(model)?.toLowerCase();
\tif (!rawModel) return null;
\tif (rawModel.startsWith("gpt") || rawModel.includes("openai") || rawModel.includes("codex")) return "openai-codex";
\tif (rawModel.includes("claude") || rawModel.includes("anthropic")) return "anthropic";
\tif (rawModel.includes("gemini") || rawModel.includes("google")) return "gemini";
\tif (rawModel.includes("deepseek")) return "deepseek";
\treturn null;
}
function resolveFooterUsageSummary(modelProvider, model) {
\tconst provider = resolveFooterUsageProvider(modelProvider, model);
\tif (!provider) return null;
\tconst cached = footerUsageCache.get(provider);
\tif (cached && cached.expiresAt > Date.now()) return cached.value;
\ttry {
\t\tconst raw = execFileSync("openclaw", ["status", "--usage", "--json"], {
\t\t\tencoding: "utf8",
\t\t\ttimeout: 2500,
\t\t\tmaxBuffer: 1024 * 1024
\t\t});
\t\tconst parsed = JSON.parse(raw);
\t\tconst providers = Array.isArray(parsed?.usage?.providers) ? parsed.usage.providers : [];
\t\tconst entry = providers.find((item) => normalizeOptionalString(item?.provider) === provider && Array.isArray(item?.windows) && item.windows.length > 0);
\t\tconst value = entry ? entry.windows.map(formatFooterUsageWindow).filter(Boolean).slice(0, 2).join(" · ") : null;
\t\tfooterUsageCache.set(provider, { value, expiresAt: Date.now() + 6e4 });
\t\treturn value;
\t} catch {
\t\tfooterUsageCache.set(provider, { value: null, expiresAt: Date.now() + 15e3 });
\t\treturn null;
\t}
}
function formatFooterSessionLabel(sessionId, timestamp, fallback) {''',
    'usage helpers')

rep('''\tconst meta = {
\t\tmodel: normalizeOptionalString(prefixCtx?.model),
\t\tthinking: normalizeOptionalString(prefixCtx?.thinkingLevel),
\t\tsession: summarizeSessionKey(sessionKey),
\t\tcontext: null,
\t\ttokens: null,
\t\ttime: null,
\t\tcwd: null
\t};''',
'''\tconst meta = {
\t\tmodel: normalizeOptionalString(prefixCtx?.model),
\t\tmodelProvider: null,
\t\tthinking: normalizeOptionalString(prefixCtx?.thinkingLevel),
\t\tsession: summarizeSessionKey(sessionKey),
\t\tcontext: null,
\t\ttokens: null,
\t\tusage: null
\t};''', 'meta shape')

rep('''\t\tmeta.model ??= normalizeOptionalString(entry.model);
\t\tmeta.thinking ??= normalizeOptionalString(entry.thinkingLevel ?? entry.resolvedThinkLevel ?? entry.thinking);
\t\tmeta.session = formatFooterSessionLabel(entry.sessionId, entry.sessionStartedAt ?? entry.createdAt ?? entry.updatedAt, meta.session);
\t\tconst inputTokens = firstFiniteNumber(entry.inputTokensFresh, entry.inputTokens);
\t\tconst outputTokens = firstFiniteNumber(entry.outputTokensFresh, entry.outputTokens);
\t\tconst totalTokens = firstFiniteNumber(entry.totalTokensFresh, entry.totalTokens);
\t\tconst contextUsed = firstFiniteNumber(entry.contextUsedTokens, entry.contextTokensUsed, entry.currentContextTokens, entry.lastContextTokens, totalTokens, entry.promptTokens, inputTokens);
\t\tconst contextLimit = firstFiniteNumber(entry.contextTokens, entry.contextWindow, entry.systemPromptReport?.contextTokens);
\t\tmeta.context = formatFooterContext(contextUsed, contextLimit);
\t\tmeta.tokens = formatFooterTokens(inputTokens, outputTokens) ?? formatFooterNumber(totalTokens ?? entry.inputTokens + entry.outputTokens);
\t\tmeta.time = formatFooterDuration(entry.runtimeMs ?? (Number.isFinite(entry.startedAt) ? Date.now() - normalizeEpochMs(entry.startedAt) : void 0));
\t\tmeta.cwd = shortenFooterPath(entry.cwd ?? entry.runtimeOptions?.cwd ?? entry.systemPromptReport?.workspaceDir ?? entry.systemPromptReport?.cwd);
\t\treturn meta;''',
'''\t\tmeta.model ??= normalizeOptionalString(entry.model);
\t\tmeta.modelProvider = normalizeOptionalString(entry.modelProvider ?? entry.provider);
\t\tmeta.thinking ??= normalizeOptionalString(entry.thinkingLevel ?? entry.resolvedThinkLevel ?? entry.thinking);
\t\tmeta.session = formatFooterSessionLabel(entry.sessionId, entry.sessionStartedAt ?? entry.createdAt ?? entry.updatedAt, meta.session);
\t\tconst inputTokens = firstFiniteNumber(entry.inputTokensFresh, entry.inputTokens);
\t\tconst outputTokens = firstFiniteNumber(entry.outputTokensFresh, entry.outputTokens);
\t\tconst totalTokens = firstFiniteNumber(entry.totalTokensFresh, entry.totalTokens);
\t\tconst contextUsed = firstFiniteNumber(entry.contextUsedTokens, entry.contextTokensUsed, entry.currentContextTokens, entry.lastContextTokens, totalTokens, entry.promptTokens, inputTokens);
\t\tconst contextLimit = firstFiniteNumber(entry.contextTokens, entry.contextWindow, entry.systemPromptReport?.contextTokens);
\t\tmeta.context = formatFooterContext(contextUsed, contextLimit);
\t\tmeta.tokens = formatFooterTokens(inputTokens, outputTokens) ?? formatFooterNumber(totalTokens ?? entry.inputTokens + entry.outputTokens);
\t\tmeta.usage = resolveFooterUsageSummary(meta.modelProvider, meta.model);
\t\treturn meta;''', 'usage lookup')

rep('''\tif (meta.context) parts.push(`Context: ${meta.context}`);
\tif (meta.tokens) parts.push(`Tokens: ${meta.tokens}`);
\tif (meta.time) parts.push(`Time: ${meta.time}`);
\tif (meta.cwd) parts.push(`CWD: ${meta.cwd}`);''',
'''\tif (meta.context) parts.push(`Context: ${meta.context}`);
\tif (meta.tokens) parts.push(`Tokens: ${meta.tokens}`);
\tif (meta.usage) parts.push(`Usage: ${meta.usage}`);''', 'footer line')

if text != orig:
    shutil.copy2(p, backup)
    p.write_text(text)
    print('backup', backup)
else:
    print('already patched')
PY

node --check "$RUNTIME"
