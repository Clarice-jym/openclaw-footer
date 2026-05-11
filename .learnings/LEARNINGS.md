# Learnings

Corrections, insights, and knowledge gaps captured during development.

**Categories**: correction | insight | knowledge_gap | best_practice

---

## [LRN-20260511-001] Discord groupChat visibleReplies 配置影响 footer 可见性

**Logged**: 2026-05-11T16:55:00+08:00
**Category**: insight

### Summary
`messages.groupChat.visibleReplies = "message_tool"` 时，Discord 群组频道中只有通过 message tool 发送的回复才显示，runtime 自动生成的 final answer（包括 footer）不会出现在频道里。这导致 footer 补丁看起来
