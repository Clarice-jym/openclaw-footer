# USER.md - About Your Human

_Learn about the person you're helping. Update this as you go._

- **Name:** (未提供)
- **What to call them:** 中文名未提供。Discord 中昵称为 @Elmo莲莫🎍
- **Pronouns:** _(optional)_
- **Timezone:** Asia/Shanghai (GMT+8)
- **Channels:**
  - Feishu: `ou_559628d053a51cd4ba38512480b2dba2`（主渠道）
  - Telegram: `8762865539`
  - Discord: User `1480167237817077911`, Server `1502496757458665632`
- **Notes:**
  - Preference: Whenever secrets/API keys/tokens/passwords are needed, inject them via environment variables or env-backed SecretRefs instead of storing plaintext in config, docs, scripts, or chat-visible examples.
  - Prefers to review a plan before execution ("先给出方案再执行")
  - Likes script-based solutions that survive OpenClaw updates (e.g., patch scripts for footer)
  - Attention to detail — expects accurate field values, not sample/copied data

## Context

### Projects
- **QuantClaw Plugin** — installed from GitHub (SparkEngineAI/QuantClaw-plugin), needs route router configuration
- **OpenClaw Footer Customization** — custom footer across Feishu, Telegram, Discord; patched runtime JS bundles
- **Discord Channel Setup** — pairing, permissions, no-@mention mode
- **Telegram Streaming Fix** — disabled streaming to fix truncated responses

### Historical Model Config
- Past: `openai-codex/gpt-5.4` → `openai-codex/gpt-5.4-mini` → `openai-codex/gpt-5.5`
- Current: `deepseek/deepseek-v4-flash` (primary), `openai-codex` as provider (via OAuth)
- Compaction model: was set to `openai-codex/gpt-5.4-mini` (pre-LCM era)

### Known Issues Encountered
- Feishu footer: required patching runtime bundle, pure-text replies don't support native card footer
- Telegram footer: runtime `ReferenceError: usagePromptTokens is not defined` (fixed by lifting variable declarations)
- Discord: `ReferenceError: channel is not defined` in runtime
- Compaction: `server_is_overloaded` error
- Card streaming: duplicate content bug

### Footer Format Preference (跨渠道统一)
```
Model: {model} | Session: {id} ({date}) | Thinking: {level} | Context: X / Y (Z%) | Tokens: in X out Y | Time: Xm Ys | CWD: {path}
```
---

_The more you know, the better you can help. But remember — you're learning about a person, not building a dossier. Respect the difference._
