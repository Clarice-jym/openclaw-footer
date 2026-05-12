#!/usr/bin/env bash
set -euo pipefail
# patch-feishu-footer.sh — Make Feishu card-note footer use shared footer-shared.mjs
#
# Since shared module introduction (2026-05-12), the Feishu monitor no longer
# hand-rolls footer formatting.  Instead it imports generateFooterLine() from
# footer-shared.mjs, stores raw numeric fields alongside formatted meta, and
# calls generateFooterLine() in resolveCardNote.
#
# Usage:
#   patch-feishu-footer.sh --check
#   patch-feishu-footer.sh --apply
#   patch-feishu-footer.sh --mode status|note|body
#   patch-feishu-footer.sh --check-duplicate-footer
#   patch-feishu-footer.sh --fix-duplicate-footer

MODE="apply"
MODE_VALUE=""
DUPLICATE_MODE=""
for arg in "$@"; do
  case "$arg" in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --check-duplicate-footer) DUPLICATE_MODE="check" ;;
    --fix-duplicate-footer) DUPLICATE_MODE="apply" ;;
    --mode=*) MODE="mode"; MODE_VALUE="${arg#--mode=}" ;;
    --mode) MODE="mode" ;;
    note|body|status) [[ "$MODE" == "mode" && -z "$MODE_VALUE" ]] && MODE_VALUE="$arg" ;;
    *) ;;
  esac
done

SHARED_MODULE="$HOME/.openclaw/footer-shared.mjs"
SHARED_MODULE_ASSET="$HOME/.openclaw/workspace/skills/openclaw-footer/assets/footer-shared.mjs"
RUNTIME="$HOME/.openclaw/npm/node_modules/@openclaw/feishu/dist/monitor.account-CUZxYkjE.js"
AGENT_RUNTIME="$HOME/.npm-global/lib/node_modules/openclaw/dist/agent-runner.runtime-CjYlXxbm.js"
MODE_FILE="$HOME/.openclaw/feishu-footer-mode"

usage() {
  cat <<'EOF'
Usage:
  patch-feishu-footer.sh --check
  patch-feishu-footer.sh --apply
  patch-feishu-footer.sh --mode status|note|body
  patch-feishu-footer.sh --check-duplicate-footer
  patch-feishu-footer.sh --fix-duplicate-footer

Shares the footer-shared.mjs module with the Feishu monitor.
Adds an ESM import and replaces resolveCardNote to call generateFooterLine().
EOF
}

# ---------- shared module markers ----------
check_markers() {
  python3 - "$RUNTIME" "$SHARED_MODULE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
shared = Path(sys.argv[2])
text = p.read_text()

markers = [
    'import { generateFooterLine } from "file:///home/momo/.openclaw/footer-shared.mjs";',
    '_inputTokens:',
    '_outputTokens:',
    '_contextUsed:',
    '_contextLimit:',
    '_sessionId:',
    '_startedAt:',
    '_durationMs:',
    '_cwd:',
    'generateFooterLine({',
    'style: "feishu"',
]
ok = True
if not shared.exists():
    print("MISSING: shared module")
    ok = False
missing = [m for m in markers if m not in text]
if missing:
    ok = False
    print("MISSING")
    for m in missing:
        print(f"  {m}")
if ok:
    print("OK")
else:
    raise SystemExit(1)
PY
}

# ---------- duplicate footer ----------
check_duplicate_markers() {
  python3 - "$AGENT_RUNTIME" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
marker = 'if (params.channel === "feishu") return null;'
if marker not in text:
    print('MISSING')
    print(marker)
    raise SystemExit(1)
print('OK')
PY
}

apply_duplicate_fix() {
  python3 - "$AGENT_RUNTIME" <<'PY'
from pathlib import Path
import shutil, sys, time
p = Path(sys.argv[1])
text = p.read_text()
backup = p.with_suffix(p.suffix + f'.bak.{time.strftime("%Y%m%d-%H%M%S")}')
old = """const formatResponseUsageLine = (params) => {
\ttry {
\t\tif (params.channel === \"discord\") return formatDiscordFooterLine(params);
\t\treturn formatTelegramFooterLine(params);
\t} catch (e) {
\t\tconsole.warn(\"[footer] formatResponseUsageLine:\", e);
\t\treturn null;
\t}
};"""
new = """const formatResponseUsageLine = (params) => {
\ttry {
\t\tif (params.channel === \"feishu\") return null;
\t\tif (params.channel === \"discord\") return formatDiscordFooterLine(params);
\t\treturn formatTelegramFooterLine(params);
\t} catch (e) {
\t\tconsole.warn(\"[footer] formatResponseUsageLine:\", e);
\t\treturn null;
\t}
};"""
if new in text:
    print('already duplicate footer fix')
elif old in text:
    shutil.copy2(p, backup)
    p.write_text(text.replace(old, new, 1))
    print('backup', backup)
    print('patched duplicate footer fix')
else:
    raise SystemExit('missing pattern for duplicate footer fix')
PY
  node --check "$AGENT_RUNTIME"
}

# ---------- mode ----------
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

# ---------- check / apply ----------
if [[ "$MODE" == "check" ]]; then
  check_markers
  exit 0
fi

if [[ "$DUPLICATE_MODE" == "check" ]]; then
  check_duplicate_markers
  exit 0
fi

if [[ "$DUPLICATE_MODE" == "apply" ]]; then
  apply_duplicate_fix
  exit 0
fi

# ---------- apply ----------
python3 - "$RUNTIME" "$SHARED_MODULE" "$SHARED_MODULE_ASSET" <<'PY'
from pathlib import Path
import shutil, sys, time

p = Path(sys.argv[1])
shared = Path(sys.argv[2])
shared_asset = Path(sys.argv[3])
text = p.read_text()
orig = text

IMPORT_LINE = 'import { generateFooterLine } from "file:///home/momo/.openclaw/footer-shared.mjs";'

# ---- ensure shared module exists (copy from skill asset if needed) ----
if not shared.exists():
    if shared_asset.exists():
        shutil.copy2(shared_asset, shared)
        print(f"Shared module restored from asset: {shared_asset}")
    else:
        raise SystemExit(f"Shared footer module not found: {shared}\nAsset also missing: {shared_asset}\nRestore the skill bundle first.")

changed = False

# ---- 1) add import ----
if IMPORT_LINE not in text:
    lines = text.splitlines(keepends=True)
    last_import_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("import "):
            last_import_idx = i
    if last_import_idx < 0:
        raise SystemExit("Could not locate import section.")
    lines.insert(last_import_idx + 1, IMPORT_LINE + "\n")
    text = "".join(lines)
    changed = True
    print("patched: shared-module import")
else:
    print("already: shared-module import")

# ---- 2) extend meta with raw fields ----
old_meta_init = '''\tconst meta = {
\t\tmodel: normalizeOptionalString(prefixCtx?.model),
\t\tmodelProvider: null,
\t\tthinking: normalizeOptionalString(prefixCtx?.thinkingLevel),
\t\tsession: summarizeSessionKey(sessionKey),
\t\tcontext: null,
\t\ttokens: null,
\t\tusage: null
\t};'''
new_meta_init = '''\tconst meta = {
\t\tmodel: normalizeOptionalString(prefixCtx?.model),
\t\tmodelProvider: null,
\t\tthinking: normalizeOptionalString(prefixCtx?.thinkingLevel),
\t\tsession: summarizeSessionKey(sessionKey),
\t\tcontext: null,
\t\ttokens: null,
\t\tusage: null,
\t\t_inputTokens: null,
\t\t_outputTokens: null,
\t\t_contextUsed: null,
\t\t_contextLimit: null,
\t\t_sessionId: null,
\t\t_startedAt: null,
\t\t_durationMs: null,
\t\t_cwd: null
\t};'''

if new_meta_init in text:
    print("already: raw meta fields")
elif old_meta_init in text:
    text = text.replace(old_meta_init, new_meta_init, 1)
    changed = True
    print("patched: raw meta fields")
else:
    print("skip: meta init — unrecognized pattern")

# ---- 3) store raw values alongside formatted ----
old_fmt = '''\t\tmeta.context = formatFooterContext(contextUsed, contextLimit);
\t\tmeta.tokens = formatFooterTokens(inputTokens, outputTokens) ?? formatFooterNumber(totalTokens ?? entry.inputTokens + entry.outputTokens);'''
new_fmt = '''\t\tmeta.context = formatFooterContext(contextUsed, contextLimit);
\t\tmeta.tokens = formatFooterTokens(inputTokens, outputTokens) ?? formatFooterNumber(totalTokens ?? entry.inputTokens + entry.outputTokens);
\t\tmeta._inputTokens = inputTokens;
\t\tmeta._outputTokens = outputTokens;
\t\tmeta._contextUsed = contextUsed;
\t\tmeta._contextLimit = contextLimit;
\t\tmeta._sessionId = entry.sessionId;
\t\tmeta._startedAt = entry.sessionStartedAt ?? entry.createdAt ?? entry.updatedAt;
\t\tmeta._durationMs = entry.runtimeMs;
\t\tmeta._cwd = entry.cwd ?? entry.runtimeOptions?.cwd ?? entry.systemPromptReport?.workspaceDir ?? entry.systemPromptReport?.cwd;'''

if new_fmt in text:
    print("already: raw value storage")
elif old_fmt in text:
    text = text.replace(old_fmt, new_fmt, 1)
    changed = True
    print("patched: raw value storage")
else:
    print("skip: raw value storage — unrecognized pattern")

# ---- 4) replace resolveCardNote body ----
old_cardnote = '''async function resolveCardNote(prefixCtx, options = {}) {
\tconst meta = await resolveFooterSessionMeta({
\t\tstorePath: options.storePath,
\t\tsessionKey: options.sessionKey,
\t\tprefixCtx
\t});
\tconst parts = [];
\tif (meta.model) parts.push(`Model: ${meta.model}`);
\tif (meta.session) parts.push(`Session: ${meta.session}`);
\tif (meta.thinking) parts.push(`Thinking: ${meta.thinking}`);
\tif (meta.context) parts.push(`Context: ${meta.context}`);
\tif (meta.tokens) parts.push(`Tokens: ${meta.tokens}`);
\tif (meta.usage) parts.push(`Usage: ${meta.usage}`);
\treturn parts.join(" | ");
}'''
new_cardnote = '''async function resolveCardNote(prefixCtx, options = {}) {
\tconst meta = await resolveFooterSessionMeta({
\t\tstorePath: options.storePath,
\t\tsessionKey: options.sessionKey,
\t\tprefixCtx
\t});
\treturn generateFooterLine({
\t\tusage: { input: meta._inputTokens ?? void 0, output: meta._outputTokens ?? void 0 },
\t\tmodel: meta.model,
\t\tthinking: meta.thinking,
\t\tsessionId: meta._sessionId,
\t\tsessionKey: options.sessionKey,
\t\tstartedAt: meta._startedAt,
\t\tcontextUsed: meta._contextUsed,
\t\tcontextLimit: meta._contextLimit,
\t\tusageSummary: meta.usage,
\t\tdurationMs: meta._durationMs,
\t\tcwd: meta._cwd,
\t\tstyle: "feishu"
\t}) ?? "";
}'''

if new_cardnote in text:
    print("already: resolveCardNote")
elif old_cardnote in text:
    text = text.replace(old_cardnote, new_cardnote, 1)
    changed = True
    print("patched: resolveCardNote")
else:
    print("skip: resolveCardNote — unrecognized pattern")

# ---- final checks ----
markers = [IMPORT_LINE, 'generateFooterLine({', 'style: "feishu"']
missing = [m for m in markers if m not in text]
if missing:
    raise SystemExit("Patch incomplete: " + ", ".join(missing))

if changed and text != orig:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = p.with_suffix(p.suffix + f".bak-feishu-footer-{stamp}")
    shutil.copy2(p, backup)
    p.write_text(text)
    print(f"Backup: {backup}")
    print("Patch status: applied")
elif not changed:
    print("Patch status: already present")
PY

node --check "$RUNTIME"
echo "node --check: ok"
echo
echo "Next (after --apply):"
echo "  openclaw gateway restart"
echo "  openclaw gateway status"
