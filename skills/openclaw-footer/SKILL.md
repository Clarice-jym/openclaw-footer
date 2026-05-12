---
name: openclaw-footer
description: >
  Unified OpenClaw reply footer management across all channels (Feishu, Telegram, and Discord). Use when the user mentions any footer topic: footer missing, footer mode, footer config, footer setup, footer check, footer apply, footer install, footer patching, footer format, usage footer, card footer, note footer, body footer, footer visibility, footer token saving, footer after OpenClaw update, or configuring footer for a new channel. Routes to channel-specific workflows based on the conversation context: Feishu channel → openclaw-feishu-footer workflow (card note/body modes, --mode body/note, patch-feishu-footer.sh) · Telegram channel → openclaw-telegram-footer workflow (text footer with visual separator, patch-telegram-footer.sh) · Discord channel → openclaw-discord-footer workflow (text footer, shared runtime patch with Telegram) · User explicitly names a channel → route accordingly. Single entry point: footer status|note|body|check|apply|install shorthand works across all channels.
---

# OpenClaw Footer

Unified dispatcher for reply footer management across all OpenClaw channels. Routes footer requests to the correct channel-specific sub-skill.

## Routing logic

1. **Check current channel** from the inbound metadata (`channel` field in conversation context).
2. **Check if user named a channel explicitly:**
   - Contains `飞书` / `feishu` / `lark` → Feishu workflow
   - Contains `telegram` / `tg` → Telegram workflow
   - Contains `discord` / `dc` → Discord workflow
3. **Route by active channel:**
   - `feishu` → read and follow `openclaw-feishu-footer`
   - `telegram` → read and follow `openclaw-telegram-footer`
   - `discord` → read and follow `openclaw-discord-footer`
   - other/unknown → ask the user which channel
4. **Read the sub-skill's SKILL.md** at `/home/momo/.openclaw/workspace/skills/openclaw-{channel}-footer/SKILL.md` and follow its workflow.

## Channel-agnostic shortcuts (route automatically)

| Shortcut | Action |
|----------|--------|
| `footer status` | Show current mode + patch status (channel-appropriate) |
| `footer check` | Verify patch is still present |
| `footer apply` | Re-apply patch if missing |
| `footer install` | Full setup from scratch for this channel |

## Feishu-specific

- `footer note` → Feishu card note/metadata mode (token-saving, preferred)
- `footer body` → Feishu visible footer in card body (fallback)

## Telegram-specific

- No extra shorthands; shared ones above cover it.

## Discord-specific

- Discord has its OWN `patch-discord-footer.sh` which **delegates to `patch-telegram-footer.sh`** since the two channels share the same runtime and footer module.
- `discord footer check` → verify the Discord-specific markers via delegated script.
- `discord footer apply` → apply via `patch-discord-footer.sh` (delegates to `patch-telegram-footer.sh`).
- Discord footer format differs from Telegram: bold `**Model:**` label, emoji fields (🧠 ⏱ 📂), `────────` divider. All defined in `footer-shared.mjs` `FIELD_SPECS.discord`.

## When this router triggers

The sub-skills have channel-specific descriptions and will also match channel-specific queries. This router covers:

- **Ambiguous queries:** "footer 不见了", "检查 footer", "footer 状态"
- **Multi-channel:** "两个渠道都检查一下"
- **First usage:** "footer 是什么 / 怎么配置"
- **Explicit routing:** User says "飞书的 footer", "Telegram 的 footer", or "Discord 的 footer"

## Implementation notes

- Sub-skills live at `/home/momo/.openclaw/workspace/skills/openclaw-feishu-footer/`, `.../openclaw-telegram-footer/`, and `.../openclaw-discord-footer/`.
- **Canonical footer content** is defined in `skills/openclaw-footer/assets/footer-shared.mjs` — this is the single source of truth.
- At runtime, the module lives at `~/.openclaw/footer-shared.mjs` and is imported by all three channel bundles.
- The patch scripts (`--apply`) automatically copy the asset to `~/.openclaw/footer-shared.mjs` if missing.
- To change footer format: edit `skills/openclaw-footer/assets/footer-shared.mjs`, run `patch-*-footer.sh --apply`, restart Gateway.
- This router does not duplicate scripts or workflows — delegate entirely to sub-skills.
- If OpenClaw updates break footers on both channels, fix one channel at a time: complete one before starting the next.
- The inbound metadata has the channel info; use that for routing, not assumptions.
