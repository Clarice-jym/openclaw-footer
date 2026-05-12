# Feishu Footer Workflows

## Local state

- Runtime script: `~/.openclaw/scripts/patch-feishu-footer.sh`
- Mode file: `~/.openclaw/feishu-footer-mode`
- Reference doc: `~/.openclaw/patches/feishu-footer-final-only.README.md`
- Feishu plugin root default: `~/.openclaw/npm/node_modules/@openclaw/feishu`
- Active bundle is auto-located under `dist/*.js` by searching for `createFeishuReplyDispatcher`, `resolveCardNote`, and `streaming.start`.

## Footer modes

- `note` is the recommended/default mode. Footer is sent as Feishu card `note`/metadata, visible in streaming cards after the `reserveNote` fix, and does not pollute assistant正文/context.
- `body` is only a temporary fallback if a future Feishu/OpenClaw change hides card notes again. It appends footer to final card body after `---`, which is visible but may cost context tokens later.
- Plain text replies append footer in text because they have no card metadata.
- Current footer fields are aligned with Telegram: `Model | Session | Thinking | Context | Tokens | Usage`.
- `Usage` is live provider quota summary text such as `5h 58% left ⏱4h 4m · Week 5% left ⏱1d 15h`.

## User shorthand commands

Handle these directly when the user sends them:

- `footer status`: run `~/.openclaw/scripts/patch-feishu-footer.sh --mode status` and optionally `--check`.
- `footer note`: run `~/.openclaw/scripts/patch-feishu-footer.sh --mode note`, then restart Gateway and verify status. This is the recommended steady state.
- `footer body`: fallback only; run `~/.openclaw/scripts/patch-feishu-footer.sh --mode body`, then restart Gateway and verify status.
- `footer check`: run `~/.openclaw/scripts/patch-feishu-footer.sh --check`.
- `footer apply`: run `~/.openclaw/scripts/patch-feishu-footer.sh --apply`, then restart Gateway and verify status.
- `footer install` or `新飞书渠道配置 footer`: ensure the runtime script exists, run `--apply`, set preferred mode, restart Gateway, verify.

## Safe restart pattern

Gateway restart often SIGTERMs the current run; this is expected. Use:

```bash
openclaw gateway restart || true
sleep 5
openclaw gateway status
```

If status says `deactivating` or `stopped` but probe is ok, wait 10-30 seconds and check again. Success gate:

- `Runtime: running`
- `Connectivity probe: ok`

## Fresh setup / new Feishu channel

1. Ensure runtime script is installed:

```bash
mkdir -p ~/.openclaw/scripts ~/.openclaw/patches
cp <skill-dir>/scripts/patch-feishu-footer.sh ~/.openclaw/scripts/patch-feishu-footer.sh
chmod +x ~/.openclaw/scripts/patch-feishu-footer.sh
```

2. Apply patch:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --apply
```

3. Choose mode. Use `note` unless troubleshooting:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --mode note   # recommended steady state
# temporary fallback only:
~/.openclaw/scripts/patch-feishu-footer.sh --mode body
```

4. Restart and verify:

```bash
openclaw gateway restart || true
sleep 5
openclaw gateway status
```

## After OpenClaw update / footer disappeared

1. Check patch:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --check
```

2. If missing, apply:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --apply
```

3. Re-check and restart:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --check
openclaw gateway restart || true
sleep 5
openclaw gateway status
```

## Safety notes

- The script backs up the target bundle before writing.
- The script runs `node --check` on the patched bundle.
- If expected patterns are missing, it exits instead of guessing.
- Avoid editing OpenClaw config or secrets for this task.

## Streaming card note/footer implementation

Feishu streaming cards must contain a `note` element when the card is created; otherwise final close cannot update a nonexistent note/footer element. The runtime patch therefore uses `reserveNote: resolveFeishuFooterMode() === "note"` when starting streaming cards.

Behavior:

1. In `note` mode, `streaming.start(...)` passes `reserveNote: true`.
2. `FeishuStreamingSession.start(...)` creates an empty note markdown element (`element_id: "note"`) plus an `hr` separator.
3. `state.hasNote` is true when `options.note || options.reserveNote`.
4. On final `streaming.close(..., { note })`, `updateNoteContent(note)` writes the real footer into the reserved element.
5. Intermediate/reasoning updates still do not show footer content.

If footer is missing only for streaming cards, verify these markers in the active bundle:

- `reserveNote: resolveFeishuFooterMode() === "note"`
- `options?.note || options?.reserveNote`
- `hasNote: !!(options?.note || options?.reserveNote)`
- `updateNoteContent(options.note)` or equivalent final note update path
