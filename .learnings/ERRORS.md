# Errors

Command failures and integration errors.

---

## [ERR-20260506-001] Feishu footer patch targeted non-loaded plugin path

**Logged**: 2026-05-06T23:18:00+08:00
**Priority**: medium

I initially patched `/home/momo/.npm-global/lib/node_modules/@openclaw/feishu/src/reply-dispatcher.ts`, but gateway logs showed the active Feishu plugin was loaded from `/home/momo/.openclaw/npm/node_modules/@openclaw/feishu/dist/index.js`. For plugin hotfixes, verify the runtime-loaded plugin path from gateway logs before editing.
## [ERR-20260507-001] node-eval-function-extraction

**Logged**: 2026-05-07T14:11:00+08:00
**Priority**: low
**Status**: resolved
**Area**: tests

### Summary
A quick Node verification script failed because a function declaration evaluated inside ESM `eval()` did not bind to the outer variable as expected.

### Details
While validating a compiled OpenClaw Feishu plugin patch, the script extracted `mergeStreamingText` and attempted to assign it via `eval`, but the binding was not available afterward (`TypeError: mergeStreamingText is not a function`).

### Suggested Action
For small verification snippets, define test helper functions explicitly or wrap extracted code in a `Function` constructor that returns the named function.

### Metadata
- Source: error
- Related Files: /home/momo/.openclaw/npm/node_modules/@openclaw/feishu/dist/monitor.account-CUZxYkjE.js
- Tags: node, esm, eval, verification

---

## [ERR-20260508-001] jq unavailable in workspace shell

**Logged**: 2026-05-08T15:14:00+08:00
**Context**: While vetting/installing a GitHub-hosted skill, a repo-metrics command failed because `jq` was not installed.
**What to do differently**: For portable JSON checks in this WSL workspace, use `python3 -m json.tool` or a short Python `urllib.request` snippet instead of assuming `jq` exists.

## [ERR-20260508-001] openclaw_telegram_usage_footer_runtime

**Logged**: 2026-05-08T15:56:08+08:00
**Priority**: high
**Status**: resolved
**Area**: infra

### Summary
Telegram replies could generate partially, then fail during final dispatch with `ReferenceError: usagePromptTokens is not defined` after enabling/customizing usage footer behavior.

### Details
Gateway/channel health can still show Telegram as `enabled, configured, running, connected, mode:polling, works`; the failure is in OpenClaw reply post-processing, not bot token, polling, or gateway connectivity. Key log signature:

```text
message processed: channel=telegram ... outcome=error ... error="ReferenceError: usagePromptTokens is not defined"
[telegram] dispatch failed: ReferenceError: usagePromptTokens is not defined
```

Root cause in bundled runtime:
`~/.npm-global/lib/node_modules/openclaw/dist/agent-runner.runtime-*.js`

`usagePromptTokens` / related usage variables were declared only inside the diagnostics branch, then referenced later by response usage footer code. If diagnostics did not run, footer dispatch crashed.

### Resolution
Move the common usage variables before `if (isDiagnosticsEnabled(cfg) && hasNonzeroUsage(usage))`:

```js
const input = usage.input ?? 0;
const output = usage.output ?? 0;
const cacheRead = usage.cacheRead ?? 0;
const cacheWrite = usage.cacheWrite ?? 0;
const usagePromptTokens = input + cacheRead + cacheWrite;
const totalTokens = usage.total ?? usagePromptTokens + output;
```

Then validate with `node --check`, restart `openclaw-gateway`, probe channels, and test via `openclaw agent --channel telegram --to 8762865539 --message '诊断测试：请只回复 OK。' --json --timeout 180`.

### Metadata
- Source: user_feedback
- Related Files: `~/.npm-global/lib/node_modules/openclaw/dist/agent-runner.runtime-CjYlXxbm.js`
- Backup Observed: `/home/momo/.npm-global/lib/node_modules/openclaw/dist/agent-runner.runtime-CjYlXxbm.js.bak.20260508-154701`
- Tags: openclaw, telegram, footer, runtime, ReferenceError, usagePromptTokens

---

## [ERR-20260509-001] openclaw_config_patch_schema_blocked_discord_update

**Logged**: 2026-05-09T22:01:00+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
`openclaw config patch` failed while trying to apply a Discord-only change because validation complained about unrelated existing channel fields.

### Error
```text
Dry run failed: config schema validation failed.
- channels.feishu.webhookPath: invalid config: must have required property 'webhookPath'
- channels.feishu.dmPolicy: invalid config: must have required property 'dmPolicy'
- channels.feishu.reactionNotifications: invalid config: must have required property 'reactionNotifications'
- channels.feishu.typingIndicator: invalid config: must have required property 'typingIndicator'
- channels.feishu.resolveSenderNames: invalid config: must have required property 'resolveSenderNames'
- channels.telegram.groupPolicy: invalid config: must have required property 'groupPolicy'
```

### Context
- Operation attempted: apply a small Discord guild allowlist patch via `openclaw config patch --file ... --dry-run`
- Impact: blocked the safer hot-reload config workflow for a targeted channel change
- Workaround used: backed up `~/.openclaw/openclaw.json` and edited only `channels.discord` directly

### Suggested Fix
Investigate why `openclaw config patch` validates the full config against stricter requirements than the currently running config, or normalize legacy/missing fields before patching.

### Metadata
- Reproducible: unknown
- Related Files: /home/momo/.openclaw/openclaw.json

---
## [ERR-20260510-001] openclaw_plugins_install_quantclaw_source

**Logged**: 2026-05-10T16:41:00+08:00
**Priority**: high
**Status**: pending
**Area**: config

### Summary
Installing QuantClaw from source/clawhub failed because the published package only exposed TypeScript entrypoints and lacked compiled JS runtime output required by OpenClaw 2026.5.5.

### Error
```
package install requires compiled runtime output for TypeScript entry ./index.ts: expected ./dist/index.js, ./dist/index.mjs, ./dist/index.cjs, ./index.js, ./index.mjs, ./index.cjs
```

### Context
- Command attempted: `openclaw plugins install ./quantclaw`
- Also failed with: `openclaw plugins install clawhub:@sparkengineai/quantclaw`
- Workaround used: locally compile plugin to `dist/` and then install from the patched local checkout.

### Suggested Fix
Plugin authors should publish compiled JS artifacts (for example `dist/index.js`) and update the package contents before distributing via source or ClawHub.

### Metadata
- Reproducible: yes
- Related Files: quantclaw/package.json, quantclaw/index.ts

---
## [ERR-20260511-001] Discord footer ReferenceError: channel is not defined

**Logged**: 2026-05-11T16:55:00+08:00
**Priority**: high
**Status**: resolved
**Area**: runtime

### Summary
Footer 补丁中 `channel` 变量用 `const` 声明在 `if (responseUsageMode !== "off")` 块内，但在 `try-catch` 调用处被引用在块外部。虽然理论上 `if (responseUsageLine)` 短路保护，但实际运行时触发了 `ReferenceError: channel is not defined`，导致回复 dispatch 失败。

### Resolution
将 `const channel = sessionCtx.OriginatingChannel ?? ...` 移到 `if` 块外部声明，确保始终可用。所有 footer 路径加 try-catch。

### Metadata
- Related Files: `agent-runner.runtime-CjYlXxbm.js`
- Tags: discord, footer, ReferenceError, runtime

---

## [ERR-20260511-002] openclaw gateway restart 被 SIGTERM 截断

**Logged**: 2026-05-11T16:55:00+08:00
**Priority**: medium
**Status**: workaround
**Area**: infra

### Summary
`openclaw gateway restart` 和 `systemctl --user restart openclaw-gateway.service` 在执行时向旧 gateway 进程发 SIGTERM，导致当前 exec shell 也被杀掉。

### Workaround
用后台方式启动：`openclaw gateway start >/dev/null 2>&1 & disown`

### Metadata
- Tags: restart, SIGTERM, gateway

---

## [ERR-20260510-001] openclaw gateway restart

**Logged**: 2026-05-10T21:38:59+08:00
**Priority**: medium
**Status**: pending
**Area**: config

### Summary
`openclaw gateway restart` exited with code 1 without useful stderr on this host.

### Error
```
exit code 1
```

### Context
- Command attempted after editing `/home/momo/.openclaw/openclaw.json`
- Goal was to force config reload after removing `tencent-tokenhub` / `hy3-preview`
- `openclaw status --deep | grep -E 'hy3-preview|tencent-tokenhub|TokenHub'` returned no matches afterward

### Suggested Fix
Check whether this OpenClaw build expects a different restart command/path, or whether config reload is already implicit and restart is unnecessary.

### Metadata
- Reproducible: unknown
- Related Files: /home/momo/.openclaw/openclaw.json

---
