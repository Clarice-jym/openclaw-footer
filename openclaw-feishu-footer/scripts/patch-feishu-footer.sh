#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check}"
PLUGIN_ROOT="${FEISHU_PLUGIN_ROOT:-$HOME/.openclaw/npm/node_modules/@openclaw/feishu}"
DIST_DIR="$PLUGIN_ROOT/dist"

usage() {
  cat <<'EOF'
Usage:
  ~/.openclaw/scripts/patch-feishu-footer.sh --check
  ~/.openclaw/scripts/patch-feishu-footer.sh --apply
  ~/.openclaw/scripts/patch-feishu-footer.sh --mode status
  ~/.openclaw/scripts/patch-feishu-footer.sh --mode body
  ~/.openclaw/scripts/patch-feishu-footer.sh --mode note

What it does:
  - Finds the active @openclaw/feishu dist bundle that contains createFeishuReplyDispatcher.
  - Checks whether the custom final-only footer patch is present.
  - With --apply, safely patches the bundle and writes a timestamped .bak backup first.
  - Runs node --check after patching.

Footer modes:
  body  = visible footer inside final card body; costs a small amount of context tokens.
  note  = footer in Feishu card note/metadata; saves model/context tokens, but some clients hide it.

After --apply or --mode changes, restart OpenClaw Gateway manually:
  openclaw gateway restart
  openclaw gateway status
EOF
}

case "$MODE" in
  --check|--apply) ;;
  --mode)
    MODE_VALUE="${2:-status}"
    MODE_FILE="$HOME/.openclaw/feishu-footer-mode"
    mkdir -p "$(dirname "$MODE_FILE")"
    case "$MODE_VALUE" in
      body|visible|on) printf 'body\n' > "$MODE_FILE"; echo "Footer mode: body (visible in card body)"; exit 0 ;;
      note|metadata|off) printf 'note\n' > "$MODE_FILE"; echo "Footer mode: note (card metadata, token-saving)"; exit 0 ;;
      status) echo "Footer mode: $(cat "$MODE_FILE" 2>/dev/null || echo note)"; exit 0 ;;
      *) echo "Unknown footer mode: $MODE_VALUE" >&2; usage; exit 2 ;;
    esac
    ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "Unknown mode: $MODE" >&2; usage; exit 2 ;;
esac

if [[ ! -d "$DIST_DIR" ]]; then
  echo "Feishu dist dir not found: $DIST_DIR" >&2
  exit 1
fi

TARGET="$(grep -Rsl "function createFeishuReplyDispatcher\|createFeishuReplyDispatcher" "$DIST_DIR"/*.js 2>/dev/null | while read -r f; do
  if grep -q "function resolveCardNote" "$f" && grep -q "streaming.start" "$f"; then
    echo "$f"
    break
  fi
done)"

if [[ -z "${TARGET:-}" ]]; then
  echo "Could not find Feishu reply dispatcher bundle under: $DIST_DIR" >&2
  exit 1
fi

echo "Target: $TARGET"

python3 - "$MODE" "$TARGET" <<'PY'
from __future__ import annotations
import re
import shutil
import sys
import time
from pathlib import Path

mode = sys.argv[1]
path = Path(sys.argv[2])
s = path.read_text()

PATCH_MARKERS = [
    'let pendingFinalTextReply = null;',
    'function formatFooterSessionLabel',
    'function resolveFeishuFooterMode()',
    'parts.push(`Context: ${meta.context}`)',
    'parts.push(`CWD: ${meta.cwd}`)',
    'const footerMode = resolveFeishuFooterMode();',
    'reserveNote: resolveFeishuFooterMode() === "note"',
    'note: footerText && footerMode === "note" && isLast ? footerText : void 0',
    'await flushPendingFinalTextReply({ withFooter: true });',
]

missing_markers = [m for m in PATCH_MARKERS if m not in s]
if mode == '--check':
    if missing_markers:
        print('Patch status: missing')
        for marker in missing_markers:
            print(f'  missing: {marker}')
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
    raise SystemExit(f'Could not patch {label}: expected code pattern not found. OpenClaw/Feishu may have changed; inspect manually.')

# 1) Footer format helpers.
replace_once('''function formatFooterNumber(value) {
	if (!Number.isFinite(value) || value <= 0) return null;
	if (value >= 1e6) return `${(value / 1e6).toFixed(value >= 1e7 ? 0 : 1).replace(/\\.0$/, "")}m`;
	if (value >= 1e3) return `${(value / 1e3).toFixed(value >= 1e4 ? 0 : 1).replace(/\\.0$/, "")}k`;
	return String(Math.round(value));
}
''', '''function formatFooterNumber(value) {
	if (!Number.isFinite(value) || value <= 0) return null;
	if (value >= 1e6) return `${(value / 1e6).toFixed(value >= 1e7 ? 0 : 1).replace(/\\.0$/, "")}m`;
	if (value >= 1e3) return `${(value / 1e3).toFixed(value >= 1e4 ? 0 : 1).replace(/\\.0$/, "")}k`;
	return String(Math.round(value));
}
function formatFooterTokenAmount(value) {
	if (!Number.isFinite(value) || value <= 0) return null;
	if (value >= 1e6) return `${(value / 1e6).toFixed(1)}m`;
	if (value >= 1e3) return `${(value / 1e3).toFixed(1)}k`;
	return String(Math.round(value));
}
function formatFooterPercent(value) {
	if (!Number.isFinite(value) || value < 0) return null;
	return `${Math.round(value)}%`;
}
function formatFooterContext(used, limit) {
	const usedText = formatFooterTokenAmount(used);
	const limitText = formatFooterTokenAmount(limit);
	if (!usedText || !limitText) return null;
	const pct = formatFooterPercent(used / limit * 100);
	return pct ? `${usedText} / ${limitText} (${pct})` : `${usedText} / ${limitText}`;
}
function formatFooterTokens(input, output) {
	const inputText = formatFooterTokenAmount(input);
	const outputText = formatFooterTokenAmount(output);
	if (inputText && outputText) return `in ${inputText} out ${outputText}`;
	if (inputText) return `in ${inputText}`;
	if (outputText) return `out ${outputText}`;
	return null;
}
function formatFooterDate(timestamp) {
	if (!Number.isFinite(timestamp) || timestamp <= 0) return null;
	const date = new Date(normalizeEpochMs(timestamp));
	if (Number.isNaN(date.getTime())) return null;
	const year = date.getFullYear();
	const month = String(date.getMonth() + 1).padStart(2, "0");
	const day = String(date.getDate()).padStart(2, "0");
	return `${year}-${month}-${day}`;
}
function formatFooterSessionLabel(sessionId, timestamp, fallback) {
	const id = normalizeOptionalString(sessionId)?.slice(0, 8) ?? normalizeOptionalString(fallback);
	const date = formatFooterDate(timestamp);
	if (id && date) return `${id} (${date})`;
	return id ?? (date ? `(${date})` : null);
}
function shortenFooterPath(value) {
	const raw = normalizeOptionalString(value);
	if (!raw) return null;
	const home = process.env.HOME;
	if (home && raw === home) return "~";
	if (home && raw.startsWith(`${home}/`)) return `~/${raw.slice(home.length + 1)}`;
	return raw;
}
function firstFiniteNumber(...values) {
	for (const value of values) if (Number.isFinite(value) && value > 0) return value;
	return null;
}
''', 'footer helper functions')

# 2) Meta shape.
replace_once('''	const meta = {
		model: normalizeOptionalString(prefixCtx?.model),
		thinking: normalizeOptionalString(prefixCtx?.thinkingLevel),
		session: summarizeSessionKey(sessionKey),
		time: null,
		tokens: null
	};
''', '''	const meta = {
		model: normalizeOptionalString(prefixCtx?.model),
		thinking: normalizeOptionalString(prefixCtx?.thinkingLevel),
		session: summarizeSessionKey(sessionKey),
		context: null,
		tokens: null,
		time: null,
		cwd: null
	};
''', 'footer meta fields')

# 3) Session store field mapping.
replace_once('''		meta.model ??= normalizeOptionalString(entry.model);
		meta.thinking ??= normalizeOptionalString(entry.thinkingLevel);
		meta.session = normalizeOptionalString(entry.sessionId)?.slice(0, 8) ?? meta.session;
		meta.time = formatFooterDuration(entry.runtimeMs);
		meta.tokens = formatFooterNumber(entry.totalTokensFresh ?? entry.totalTokens ?? entry.inputTokens + entry.outputTokens);
		return meta;
''', '''		meta.model ??= normalizeOptionalString(entry.model);
		meta.thinking ??= normalizeOptionalString(entry.thinkingLevel ?? entry.resolvedThinkLevel ?? entry.thinking);
		meta.session = formatFooterSessionLabel(entry.sessionId, entry.sessionStartedAt ?? entry.createdAt ?? entry.updatedAt, meta.session);
		const inputTokens = firstFiniteNumber(entry.inputTokensFresh, entry.inputTokens);
		const outputTokens = firstFiniteNumber(entry.outputTokensFresh, entry.outputTokens);
		const totalTokens = firstFiniteNumber(entry.totalTokensFresh, entry.totalTokens);
		const contextUsed = firstFiniteNumber(entry.contextUsedTokens, entry.contextTokensUsed, entry.currentContextTokens, entry.lastContextTokens, totalTokens, entry.promptTokens, inputTokens);
		const contextLimit = firstFiniteNumber(entry.contextTokens, entry.contextWindow, entry.systemPromptReport?.contextTokens);
		meta.context = formatFooterContext(contextUsed, contextLimit);
		meta.tokens = formatFooterTokens(inputTokens, outputTokens) ?? formatFooterNumber(totalTokens ?? entry.inputTokens + entry.outputTokens);
		meta.time = formatFooterDuration(entry.runtimeMs ?? (Number.isFinite(entry.startedAt) ? Date.now() - normalizeEpochMs(entry.startedAt) : void 0));
		meta.cwd = shortenFooterPath(entry.cwd ?? entry.runtimeOptions?.cwd ?? entry.systemPromptReport?.cwd ?? entry.systemPromptReport?.workspaceDir);
		return meta;
''', 'session store footer mapping')

# 4) Footer part order.
replace_once('''	if (meta.thinking) parts.push(`Thinking: ${meta.thinking}`);
	if (meta.time) parts.push(`Time: ${meta.time}`);
	if (meta.tokens) parts.push(`Tokens: ${meta.tokens}`);
''', '''	if (meta.thinking) parts.push(`Thinking: ${meta.thinking}`);
	if (meta.context) parts.push(`Context: ${meta.context}`);
	if (meta.tokens) parts.push(`Tokens: ${meta.tokens}`);
	if (meta.time) parts.push(`Time: ${meta.time}`);
	if (meta.cwd) parts.push(`CWD: ${meta.cwd}`);
''', 'footer part order')

# 4b) Footer mode resolver: body vs note, controlled by env or ~/.openclaw/feishu-footer-mode.
mode_resolver = '''function resolveFeishuFooterMode() {
	const normalizeMode = (value) => {
		const mode = normalizeOptionalString(value)?.toLowerCase();
		return mode === "body" || mode === "visible" || mode === "on" ? "body" : "note";
	};
	const envMode = normalizeOptionalString(process.env.OPENCLAW_FEISHU_FOOTER_MODE);
	if (envMode) return normalizeMode(envMode);
	try {
		const modeFile = path.join(os.homedir(), ".openclaw", "feishu-footer-mode");
		return normalizeMode(fs.readFileSync(modeFile, "utf8"));
	} catch {
		return "note";
	}
}
'''
if 'function resolveFeishuFooterMode()' in s:
    print('already: footer mode resolver')
else:
    marker = '\nfunction createFeishuReplyDispatcher(params) {'
    if marker not in s:
        raise SystemExit('Could not insert footer mode resolver: dispatcher marker not found.')
    s = s.replace(marker, '\n' + mode_resolver + marker, 1)
    changed = True
    print('patched: footer mode resolver')

# 5) State for pending final text reply.
replace_once('''	let streamingStartPromise = null;
	let streamingClosedForReply = false;
	let streamingCloseErroredForReply = false;
''', '''	let streamingStartPromise = null;
	let streamingClosedForReply = false;
	let streamingCloseErroredForReply = false;
	let pendingFinalTextReply = null;
''', 'pending final state')

# 6) Streaming start must not attach footer/note.
replace_once('''				const cardHeader = resolveCardHeader(agentId, identity);
				const cardNote = resolveCardNote(prefixContext.prefixContext, {
					sessionKey,
					storePath
				});
				await streaming.start(chatId, resolveReceiveIdType(chatId), {
					replyToMessageId,
					replyInThread: effectiveReplyInThread,
					rootId,
					header: cardHeader,
					note: cardNote
				});
''', '''				const cardHeader = resolveCardHeader(agentId, identity);
				await streaming.start(chatId, resolveReceiveIdType(chatId), {
					replyToMessageId,
					replyInThread: effectiveReplyInThread,
					rootId,
					header: cardHeader,
					reserveNote: resolveFeishuFooterMode() === "note"
				});
''', 'streaming start with reserved note footer')

# 6b) Streaming card must reserve a note element so final note updates can display.
replace_once('''		if (options?.note) {
			elements.push({ tag: "hr" });
			elements.push({
				tag: "markdown",
				content: `<font color='grey'>${options.note}</font>`,
				element_id: "note"
			});
		}
''', '''		if (options?.note || options?.reserveNote) {
			elements.push({ tag: "hr" });
			elements.push({
				tag: "markdown",
				content: options?.note ? `<font color='grey'>${options.note}</font>` : " ",
				element_id: "note"
			});
		}
''', 'streaming note element reservation')
replace_once('''			hasNote: !!options?.note
''', '''			hasNote: !!(options?.note || options?.reserveNote)
''', 'streaming note state reservation')

# 7) Streaming close uses configurable footer mode: body or note.
replace_once('''				let text = buildCombinedStreamText(reasoningText, streamText);
				if (mentionTargets?.length) text = buildMentionedCardContent(mentionTargets, text);
				const finalNote = resolveCardNote(prefixContext.prefixContext, {
					sessionKey,
					storePath
				});
				await streaming.close(text, { note: finalNote });
''', '''				let text = buildCombinedStreamText(reasoningText, streamText);
				const finalFooter = options?.withFooter === false ? null : resolveCardNote(prefixContext.prefixContext, {
					sessionKey,
					storePath
				});
				const footerMode = resolveFeishuFooterMode();
				if (finalFooter && footerMode === "body") text = `${text}\n\n---\n${finalFooter}`;
				if (mentionTargets?.length) text = buildMentionedCardContent(mentionTargets, text);
				await streaming.close(text, { note: finalFooter && footerMode === "note" ? finalFooter : void 0 });
''', 'streaming close configurable footer')

# 8) Chunk sender knows last chunk.
replace_once('''		for (const [index, chunk] of chunks.entries()) await params.sendChunk({
			chunk,
			isFirst: index === 0
		});
''', '''		for (const [index, chunk] of chunks.entries()) await params.sendChunk({
			chunk,
			isFirst: index === 0,
			isLast: index === chunks.length - 1
		});
''', 'chunk last marker')

# 9) Insert sendTextReplyNow / flushPendingFinalTextReply before dispatcher creation.
helper = '''	const sendTextReplyNow = async (params) => {
		const footerText = params.withFooter === true ? resolveCardNote(prefixContext.prefixContext, {
			sessionKey,
			storePath
		}) : void 0;
		const footerMode = resolveFeishuFooterMode();
		const textWithFooter = footerText && (footerMode === "body" || !params.useCard) ? `${params.text}\n\n---\n${footerText}` : params.text;
		if (params.useCard) {
			const cardHeader = resolveCardHeader(agentId, identity);
			await sendChunkedTextReply({
				text: textWithFooter,
				useCard: true,
				infoKind: params.infoKind,
				sendChunk: async ({ chunk, isFirst, isLast }) => {
					await sendStructuredCardFeishu({
						cfg,
						to: chatId,
						text: chunk,
						replyToMessageId: sendReplyToMessageId,
						replyInThread: effectiveReplyInThread,
						mentions: isFirst ? mentionTargets : void 0,
						accountId,
						header: cardHeader,
						note: footerText && footerMode === "note" && isLast ? footerText : void 0
					});
				}
			});
			return;
		}
		await sendChunkedTextReply({
			text: textWithFooter,
			useCard: false,
			infoKind: params.infoKind,
			sendChunk: async ({ chunk, isFirst }) => {
				await sendMessageFeishu({
					cfg,
					to: chatId,
					text: chunk,
					replyToMessageId: sendReplyToMessageId,
					replyInThread: effectiveReplyInThread,
					mentions: isFirst ? mentionTargets : void 0,
					accountId
				});
			}
		});
	};
	const flushPendingFinalTextReply = async (options) => {
		const pending = pendingFinalTextReply;
		if (!pending) return;
		pendingFinalTextReply = null;
		await sendTextReplyNow({
			text: pending.text,
			useCard: pending.useCard,
			infoKind: "final",
			withFooter: options?.withFooter === true
		});
	};
'''
replace_once('\tconst { dispatcher, replyOptions, markDispatchIdle } = core.channel.reply.createReplyDispatcherWithTyping({\n', helper + '\tconst { dispatcher, replyOptions, markDispatchIdle } = core.channel.reply.createReplyDispatcherWithTyping({\n', 'final text helpers')

# 10) Reset pending reply at reply start.
replace_once('''			deliveredFinalTexts.clear();
			streamingClosedForReply = false;
			streamingCloseErroredForReply = false;
			if (streamingEnabled && renderMode === "card") startStreaming();
''', '''			deliveredFinalTexts.clear();
			streamingClosedForReply = false;
			streamingCloseErroredForReply = false;
			pendingFinalTextReply = null;
			if (streamingEnabled && renderMode === "card") startStreaming();
''', 'reset pending at reply start')

# 11) If an active streaming final differs, close without footer first.
replace_once('''				if (info?.kind === "final" && streamingEnabled && useCard) {
					startStreaming();
''', '''				if (info?.kind === "final" && streamingEnabled && useCard) {
					if (streaming?.isActive() && streamText && streamText !== text) await closeStreaming({ withFooter: false });
					startStreaming();
''', 'streaming final replacement guard')

# 12) Replace immediate non-streaming delivery block with pending-final buffering.
try:
    start = s.index('\t\t\t\tif (useCard) {\n', s.index('deliver: async'))
    end = s.index('\t\t\t}\n\t\t\tif (hasMedia)', start)
except ValueError as exc:
    raise SystemExit('Could not locate non-streaming delivery block. OpenClaw/Feishu may have changed; inspect manually.') from exc
block = s[start:end]
if 'pendingFinalTextReply = { text, useCard: true };' in block:
    print('already: pending-final delivery block')
else:
    s = s[:start] + '''				if (useCard) {
					if (info?.kind === "final") {
						await flushPendingFinalTextReply({ withFooter: false });
						pendingFinalTextReply = { text, useCard: true };
					} else await sendTextReplyNow({
						text,
						useCard: true,
						infoKind: info?.kind,
						withFooter: false
					});
				} else if (info?.kind === "final") {
					await flushPendingFinalTextReply({ withFooter: false });
					pendingFinalTextReply = { text, useCard: false };
				} else await sendTextReplyNow({
					text,
					useCard: false,
					infoKind: info?.kind,
					withFooter: false
				});
''' + s[end:]
    changed = True
    print('patched: pending-final delivery block')

# 13) onError / onIdle behavior.
replace_once('''			await closeStreaming({ markClosedForReply: false });
			typingCallbacks?.onIdle?.();
		},
		onIdle: async () => {
			await closeStreaming();
			typingCallbacks?.onIdle?.();
''', '''			pendingFinalTextReply = null;
			await closeStreaming({ markClosedForReply: false, withFooter: false });
			typingCallbacks?.onIdle?.();
		},
		onIdle: async () => {
			if (pendingFinalTextReply) {
				await closeStreaming({ withFooter: false });
				await flushPendingFinalTextReply({ withFooter: true });
			} else await closeStreaming({ withFooter: true });
			typingCallbacks?.onIdle?.();
''', 'idle-only footer flush')

missing_after = [m for m in PATCH_MARKERS if m not in s]
if missing_after:
    raise SystemExit('Patch incomplete; missing markers after patch: ' + ', '.join(missing_after))

if changed:
    backup = path.with_suffix(path.suffix + f'.bak-footer-{time.strftime("%Y%m%d-%H%M%S")}')
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
