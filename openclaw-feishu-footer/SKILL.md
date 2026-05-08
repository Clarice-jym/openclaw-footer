---
name: openclaw-feishu-footer
description: Manage the local OpenClaw Feishu reply footer customization. Use when the user mentions Feishu footer, card footer/note metadata, footer missing after OpenClaw update, switching footer body/note modes, checking footer mode or patch status, applying/reapplying the Feishu footer patch, or configuring this footer from scratch for a new Feishu channel.
---

# OpenClaw Feishu Footer

## Purpose

Maintain the local Feishu footer customization for OpenClaw replies. The footer is final-only and includes:

`Model | Session: <id8> (YYYY-MM-DD) | Thinking | Context | Tokens | Time | CWD`

Use the bundled script if the runtime script is missing or stale.

## Core commands

Runtime script:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh
```

Supported operations:

```bash
~/.openclaw/scripts/patch-feishu-footer.sh --check        # patch present/missing
~/.openclaw/scripts/patch-feishu-footer.sh --apply        # apply/reapply patch safely
~/.openclaw/scripts/patch-feishu-footer.sh --mode status  # current footer mode
~/.openclaw/scripts/patch-feishu-footer.sh --mode note    # recommended: Feishu card note/metadata, token-saving
~/.openclaw/scripts/patch-feishu-footer.sh --mode body    # fallback only: visible footer in card body
```

Mode file:

```bash
~/.openclaw/feishu-footer-mode
```

## User shorthand

When the user sends one of these, act directly:

- `footer status` → show current mode and patch status.
- `footer note` → set recommended note mode, restart Gateway, verify.
- `footer body` → fallback only if note mode is broken/hidden; set body mode, restart Gateway, verify.
- `footer check` → check patch status.
- `footer apply` → apply patch, restart Gateway, verify.
- `footer install` / “新飞书渠道配置 footer” → install runtime script if needed, apply patch, set desired mode, restart, verify.

## Workflow

1. If the runtime script is missing, copy this skill’s bundled script:

```bash
mkdir -p ~/.openclaw/scripts
cp <skill-dir>/scripts/patch-feishu-footer.sh ~/.openclaw/scripts/patch-feishu-footer.sh
chmod +x ~/.openclaw/scripts/patch-feishu-footer.sh
```

2. Run the requested script command. Prefer `--mode note`; use `--mode body` only as a temporary visibility fallback.
3. For mode changes or apply, restart Gateway and verify:

```bash
openclaw gateway restart || true
sleep 5
openclaw gateway status
```

Gateway restart can abort the current run or leave status briefly `deactivating`; wait and check again. Success requires:

- `Runtime: running`
- `Connectivity probe: ok`

## When more detail is needed

Read `references/workflows.md` for fresh setup, OpenClaw-update recovery, shortcut mapping, restart handling, and the streaming-card `reserveNote` fix that makes Feishu note footers visible.

## Safety

- Do not use destructive commands.
- Do not edit secrets or OpenClaw config for this workflow.
- The patch script should back up bundles and run `node --check`; if it cannot find expected code patterns, stop and report the blocker instead of guessing.
