#!/usr/bin/env bash
set -euo pipefail
# Discord footer patch — thin wrapper that delegates to the shared Telegram patch.
# Discord and Telegram use the exact same agent-runner runtime modification,
# so we ensure the canonical patcher is installed and forward all arguments.

MODE="${1:---check}"
OPENCLAW_SCRIPTS="${OPENCLAW_SCRIPTS:-$HOME/.openclaw/scripts}"
TELEGRAM_PATCHER="$OPENCLAW_SCRIPTS/patch-telegram-footer.sh"

case "$MODE" in
  --check|--apply) ;;
  -h|--help|help)
    cat <<'EOF'
Usage:
  patch-discord-footer.sh --check
  patch-discord-footer.sh --apply

Discord footer — delegates to the shared Telegram runtime patch.
EOF
    exit 0
    ;;
  *) echo "Unknown mode: $MODE" >&2; exit 2 ;;
esac

# Ensure the canonical Telegram patcher exists
if [[ ! -x "$TELEGRAM_PATCHER" ]]; then
  echo "Canonical patcher not found at: $TELEGRAM_PATCHER" >&2
  echo "Copying from skill bundle..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  SKILL_DIR="$(dirname "$SCRIPT_DIR")"
  TELEGRAM_SKILL_DIR="$SKILL_DIR/../openclaw-telegram-footer"
  TELEGRAM_SRC="$TELEGRAM_SKILL_DIR/scripts/patch-telegram-footer.sh"
  if [[ -f "$TELEGRAM_SRC" ]]; then
    mkdir -p "$OPENCLAW_SCRIPTS"
    cp "$TELEGRAM_SRC" "$TELEGRAM_PATCHER"
    chmod +x "$TELEGRAM_PATCHER"
    echo "Installed: $TELEGRAM_PATCHER"
  else
    echo "ERROR: Cannot find bundled telegram patcher at $TELEGRAM_SRC" >&2
    echo "Make sure the openclaw-telegram-footer skill is installed." >&2
    exit 1
  fi
fi

echo "[discord-footer] Delegating to shared Telegram runtime patch..."
exec "$TELEGRAM_PATCHER" "$MODE"
