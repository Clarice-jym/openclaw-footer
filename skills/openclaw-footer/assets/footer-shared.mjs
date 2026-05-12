// ~/.openclaw/footer-shared.mjs
// Shared footer content generation for all OpenClaw channels.
// Edit this file to change footer format across Telegram, Discord, and Feishu.
// After editing: restart Gateway to apply.

// ---- Shared formatting helpers ----

function formatTokenAmount(value) {
  if (!Number.isFinite(value) || value <= 0) return null;
  if (value >= 1e6) return `${(value / 1e6).toFixed(1).replace(/\.0$/, "")}m`;
  if (value >= 1e3) return `${(value / 1e3).toFixed(1).replace(/\.0$/, "")}k`;
  return String(Math.round(value));
}

function formatDate(timestamp) {
  if (!Number.isFinite(timestamp) || timestamp <= 0) return null;
  const date = new Date(timestamp);
  if (Number.isNaN(date.getTime())) return null;
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatDuration(ms) {
  if (!Number.isFinite(ms) || ms < 0) return null;
  const totalSeconds = Math.max(0, Math.round(ms / 1e3));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

function stripModelProvider(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  const raw = value.trim();
  return raw.includes("/") ? raw.split("/").filter(Boolean).pop() ?? raw : raw;
}

function parseResetMinutes(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  const raw = value.trim();
  if (raw === "now") return 0;
  let totalMinutes = 0;
  for (const match of raw.matchAll(/(\d+)\s*(d|h|m)\b/g)) {
    const amount = Number(match[1]);
    if (!Number.isFinite(amount)) continue;
    if (match[2] === "d") totalMinutes += amount * 24 * 60;
    if (match[2] === "h") totalMinutes += amount * 60;
    if (match[2] === "m") totalMinutes += amount;
  }
  return totalMinutes > 0 ? totalMinutes : null;
}

function formatResetHours(value) {
  const totalMinutes = parseResetMinutes(value);
  if (totalMinutes === 0) return "0h";
  if (totalMinutes === null) return typeof value === "string" ? value.trim().replace(/\s+/g, "") : null;
  return `${Math.max(1, Math.round(totalMinutes / 60))}h`;
}

function formatResetDaysHours(value) {
  const totalMinutes = parseResetMinutes(value);
  if (totalMinutes === 0) return "0h";
  if (totalMinutes === null) return typeof value === "string" ? value.trim() : null;
  const totalHours = Math.max(1, Math.round(totalMinutes / 60));
  const days = Math.floor(totalHours / 24);
  const hours = totalHours % 24;
  if (days > 0 && hours > 0) return `${days}d ${hours}h`;
  if (days > 0) return `${days}d`;
  return `${hours}h`;
}

function formatUsageSummary(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  return value
    .split("|")
    .map((part, index) => {
      const raw = part.trim();
      const match = raw.match(/^(?:(\S+)\s+)?(\d+)%\s+left(?:\s+⏱️?\s*(.+))?$/u);
      if (!match) return raw;
      const label = match[1];
      const percent = match[2];
      const reset = label === "Week" ? formatResetDaysHours(match[3]) : formatResetHours(match[3]);
      const prefix = index === 0 && label !== "Week" ? "" : `${label ?? ""} `;
      return `${prefix}${percent}%${reset ? `/${reset}` : ""}`.trim();
    })
    .join(", ");
}

// ---- Channel field label specs ----

const FIELD_SPECS = {
  telegram: {
    model: (v) => (v ? `Model: ${v}` : null),
    thinking: (v) => (v ? `Thinking: ${v}` : null),
  },
  discord: {
    model: (v) => (v ? `**Model:** ${v}` : null),
    thinking: (v) => (v ? `\u{1F9E0} ${v}` : null),
  },
  feishu: {
    model: (v) => (v ? `Model: ${v}` : null),
    thinking: (v) => (v ? `Thinking: ${v}` : null),
  },
};

// ---- Main export ----

/**
 * Generate the canonical footer line for any channel.
 *
 * @param {Object} params
 * @param {Object} params.usage          - { input, output } token counts
 * @param {string} params.model          - model identifier (e.g. "deepseek/deepseek-v4-pro")
 * @param {string} [params.thinking]     - thinking level (e.g. "high", "medium")
 * @param {string} [params.sessionId]    - session id (first 8 chars used)
 * @param {string} [params.sessionKey]   - fallback session key
 * @param {number} [params.startedAt]    - session start timestamp (ms)
 * @param {number} [params.contextUsed]  - context tokens used
 * @param {number} [params.contextLimit] - context window limit
 * @param {string} [params.usageSummary] - pre-formatted provider usage summary
 * @param {number} [params.durationMs]   - response duration in ms
 * @param {string} [params.cwd]          - workspace directory path
 * @param {string} [params.style]        - "telegram" | "discord" | "feishu"
 * @returns {string|null} footer line or null if no usage data
 */
export function generateFooterLine(params) {
  const usage = params.usage;
  if (!usage) return null;

  const style = params.style || "telegram";
  const spec = FIELD_SPECS[style] || FIELD_SPECS.telegram;

  const inputText = formatTokenAmount(usage.input);
  const outputText = formatTokenAmount(usage.output);
  const parts = [];

  // Model
  const model = stripModelProvider(params.model);
  const modelPart = spec.model(model);
  if (modelPart) parts.push(modelPart);

  // Thinking
  const thinking =
    typeof params.thinking === "string" && params.thinking
      ? params.thinking
      : null;
  const thinkingPart = spec.thinking(thinking);
  if (thinkingPart) parts.push(thinkingPart);

  // Session
  const sessionId =
    typeof params.sessionId === "string" && params.sessionId
      ? params.sessionId.slice(0, 8)
      : typeof params.sessionKey === "string"
        ? params.sessionKey.slice(0, 8)
        : null;
  const sessionDate = formatDate(params.startedAt);
  if (sessionId)
    parts.push(
      `Session: ${sessionId}${sessionDate ? ` (${sessionDate})` : ""}`
    );

  // Context
  const contextUsed = formatTokenAmount(params.contextUsed);
  const contextLimit = formatTokenAmount(params.contextLimit);
  if (contextUsed && contextLimit) {
    const pct = Math.round((params.contextUsed / params.contextLimit) * 100);
    parts.push(
      `Context: ${contextUsed} / ${contextLimit} (${Number.isFinite(pct) ? pct : 0}%)`
    );
  } else if (contextLimit) {
    parts.push(`Context: ? / ${contextLimit}`);
  }

  // Tokens
  if (inputText || outputText) {
    parts.push(
      `Tokens: ${inputText ? `in ${inputText}` : ""}${inputText && outputText ? " " : ""}${outputText ? `out ${outputText}` : ""}`
    );
  }

  // Provider/model usage quota summary
  const usageSummary = formatUsageSummary(params.usageSummary);
  if (usageSummary) {
    parts.push(`Usage: ${usageSummary}`);
  }

  // Time and CWD intentionally omitted per user preference.

  return parts.length ? parts.join(" | ") : null;
}
