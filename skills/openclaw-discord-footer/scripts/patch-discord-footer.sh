#!/usr/bin/env bash
set -euo pipefail
# patch-discord-footer.sh — Make Discord footer use shared footer-shared.mjs
#
# Discord and Telegram now share the same agent-runner runtime and the same
# footer-shared.mjs module.  This script delegates to patch-telegram-footer.sh
# because the two channels share one runtime bundle.
#
# Usage:
#   patch-discord-footer.sh --check
#   patch-discord-footer.sh --apply

MODE="${1:---check}"
TELEGRAM_SCRIPT="$HOME/.openclaw/scripts/patch-telegram-footer.sh"

usage() {
  cat <<'EOF'
Usage:
  patch-discord-footer.sh --check
  patch-discord-footer.sh --apply

Discord shares the agent-runner runtime with Telegram.
Delegates to patch-telegram-footer.sh.
EOF
}

case "$MODE" in
  --check|--apply) ;;
  -h|--help|help) usage; exit 0 ;;
  *) echo "Unknown mode: $MODE" >&2; usage; exit 2 ;;
esac

if [[ ! -x "$TELEGRAM_SCRIPT" ]]; then
  echo "Telegram footer script not found at $TELEGRAM_SCRIPT" >&2
  echo "Install it first: cp <skill>/scripts/patch-telegram-footer.sh $TELEGRAM_SCRIPT && chmod +x $TELEGRAM_SCRIPT" >&2
  exit 1
fi

exec "$TELEGRAM_SCRIPT" "$MODE"
