# Feishu Duplicate Footer Troubleshooting

Only read this file when the user reports that Feishu shows two footers.

## Symptom

- Feishu note/footer is present as expected
- Another near-identical footer is appended in the visible message body

## Cause

Two layers both add footer text:

1. `@openclaw/feishu` runtime adds the Feishu footer/note
2. OpenClaw shared `agent-runner.runtime-*.js` appends a generic usage/footer line for non-Discord channels

Without the special fix, Feishu is treated like Telegram by the shared runtime and gets a second footer.

## Check

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --check-duplicate-footer
```

Success marker in `agent-runner.runtime-*.js`:

```js
if (params.channel === "feishu") return null;
```

## Fix

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --fix-duplicate-footer
openclaw gateway restart || true
sleep 5
openclaw gateway status
```

## Notes

- This fix is intentionally separate from the normal Feishu footer patch so agents do not need to load duplicate-footer details during routine work.
- OpenClaw updates may overwrite both the Feishu runtime patch and this upstream duplicate-footer fix.
