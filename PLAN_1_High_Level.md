# PLAN 1 — High-Level Guide Creation Plan

*(Implementation intentionally excluded — this file is only a roadmap for building `AIChatUIDataStream.md` later.)*

---
## 0. Preparation — Leverage Existing `docs/`

1. **Audit shipped docs**
   - `docs/Elixir/*` → BEAM & OTP concurrency, error-handling patterns.
   - `docs/Phoenix/*` → controllers, channels, sockets, Verified Routes, testing.
   - `docs/PhoenixLiveView/*` → `live_stream/4`, JS commands, testing helpers.
   - `docs/ash/*` → manual actions, Ash AI, auth, multi-tenancy.
2. Capture **principles & recommended APIs** only; skip screenshots or version-locked snippets.
3. Provide *Further Reading* appendix linking directly to these folders.

---
## 1. Document Goals & Constraints

| Constraint | Rationale |
|------------|-----------|
| **No database** | Simplicity; avoid migrations. |
| **Persistence → CSV files** | Use `File.open!/2`, `IO.write/2`; no new deps. |
| **No new dependencies** | Keep Hex/NPM lockfiles untouched. |
| **Primary focus: streaming UX** | Not on LLM hosting itself. |

---
## 2. Version Compass  *(review quarterly)*

| Component | Recommended Version | Why |
|-----------|--------------------|-----|
| Elixir | 1.16<br/>OTP 26 | Latest LTS; improved I/O latency. |
| Phoenix | 1.7.x | Verified Routes, HEEx components. |
| Phoenix LiveView | ≥ 0.20 | `live_stream/4`, DOM patch optimisations. |
| Ash | 3.5.x | Current stable; Ash AI ≥ 0.2.9. |
| Node | 18 | Matches Phoenix asset defaults. |
| TailwindCSS | 3.4 | Already vendored. |

> Tip: include `mix hex.outdated` snippet for readers to self-verify.

---
## 3. Conceptual Architecture (text-only)

```
Browser  ⇄  Phoenix LiveView (WebSocket)
              │
              ├── Task.async →  External AI HTTP chunk/SSE
              │
              ├── (Optional) Ash manual action wrapper
              │
              ├── Phoenix PubSub  (multi-viewer fan-out)
              │
              └── CSV Logger  (File.append)
```

Key Points:
- LiveView **never blocks** — offload external calls using `Task.async`.
- Each token/chunk triggers `stream_insert/4` for real-time chat.
- Completed Q/A pairs flushed to CSV immediately with `File.write!(…, [:append])`.

---
## 4. Best-Practice Nuggets (section stubs)

### A. LiveView Streaming
- Use `:temporary_assigns` for chat history (reduces memory).
- `stream_insert/4` for new tokens; `stream_reset/3` when user clears chat.
- Render function pattern: `<div id="messages" phx-update="stream">`.

### B. Async & Fault-Tolerance
- Wrap external calls in `Task.Supervisor` under LiveView.
- Handle `%Task{}` messages with `handle_info/2`.
- Supervise AI client with exponential-backoff restart.

### C. Ash Manual Actions & Ash AI
- Prefer **prompt-backed actions** when response can be structured.
- Use **manual actions** for arbitrary streaming APIs; maintain type safety via return schema.

### D. CSV Persistence Pattern
- Path convention: `priv/data/chat_logs/YYYY-MM-DD.csv`.
- Columns: `timestamp, user_id, role, content`.
- Atomically append via `File.write!(path, row, [:append])`.

### E. Security
- Leverage AshAuthentication (already installed) for all LiveView routes.
- Enforce Ash Policy checks even when AI agents invoke resource actions.
- Sanitize user prompts before logging to CSV.

### F. Performance & Observability
- Telemetry hooks around AI latency.
- Use `:telemetry.attach/4` to forward metrics to existing dashboard.
- Enable `plug Phoenix.LiveDashboard` in :dev for stream diff inspection.

---
## 5. Deliverables Checklist

- [ ] **Core Sections Drafted** (Goals, Versions, Architecture, Nuggets).
- [ ] Inline code examples ready for Elixir 1.16 syntax.
- [ ] Further Reading appendix linking to `docs/` trees.
- [ ] Review for dependency creep (no `mix.exs` changes).
- [ ] Copy-edit for clarity & timelessness.

---
## 6. Next Steps

1. Collect precise code snippets & command examples per section.
2. Integrate findings from existing `docs/` where value-add.
3. Draft `AIChatUIDataStream.md` following this blueprint.
4. Circulate for team review; iterate.

---
*End of PLAN 1*