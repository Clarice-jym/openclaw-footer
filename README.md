# OpenClaw Footer Skills

Unified footer management for OpenClaw responses across multiple channels.

## Skills

| Skill | Description |
|-------|-------------|
| `openclaw-footer` | Router skill - routes to channel-specific footer skills |
| `openclaw-feishu-footer` | Feishu card footer with body/note mode support |
| `openclaw-telegram-footer` | Telegram text footer with usage metadata |

## Installation

```bash
# Install individual skills
lark-cli skills add ~/.openclaw/workspace/.agents/skills/openclaw-feishu-footer
lark-cli skills add ~/.openclaw/workspace/.agents/skills/openclaw-telegram-footer
lark-cli skills add ~/.openclaw/workspace/.agents/skills/openclaw-footer
```

Or install via URL:
```bash
lark-cli skills add https://github.com/Clarice-jym/openclaw-footer
```

## Usage

### Feishu
- `footer status` - Check patch status
- `footer mode body` - Switch to body mode
- `footer mode note` - Switch to note mode (节省 token)
- `footer apply` - Apply patch
- `footer check` - Verify patch

### Telegram
- `footer check` - Check if patch is applied
- `footer apply` - Apply the Telegram footer patch

## Links

- Repository: https://github.com/Clarice-jym/openclaw-footer
- OpenClaw Docs: https://docs.openclaw.ai
