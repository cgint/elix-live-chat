# PLAN 2 — Detailed Implementation How-To  
*(Concrete build steps & code-level blueprint — still **no actual code** here)*

---
## 0. Guiding Principles (recap)
• **Zero new deps** → stay within `mix.exs` as-is.  
• **CSV over DB** → flat-file persistence.  
• **Non-blocking UX** → `Task.async/await` + LiveView streams.  
• **Component-driven UI** → HEEx, Tailwind 3, DaisyUI.

---
## 1. File/Module Skeleton
```
lib/
  live_ai_chat/
    ai_client.ex          # Wrapper around external LLM streaming API
    csv_storage.ex        # Load/append chat logs
    chat_registry.ex      # Track open chats + generate IDs
  live_ai_chat_web/
    live/
      chat_live.ex        # Main LiveView (right pane)
    components/
      sidebar.ex          # Slim sidebar list + actions
      message_bubble.ex   # User / AI bubble component
      topbar.ex           # Mobile topbar (responsive)
```

---
## 2. CSV Storage Layer
1. **Path Convention**: `priv/chat_logs/<chat-id>.csv`.  
2. **Row Schema**: `timestamp,user_id,role,content`.  
3. API sketch (in `csv_storage.ex`):
   - `append(chat_id, row_map)` → `File.write!(…, [:append])`.  
   - `load(chat_id)` → `File.read!/1` → `CSV.decode/2` (use standard `:csv` module from Elixir stdlib; *no new dep*).  
   - `list_chats()` → `File.ls!("priv/chat_logs")`.
4. Ensure **atomic writes**: wrap `File.open!/3` with `:append` + `:delayed_write` ≈ 512 bytes.

---
## 3. Chat Registry & ID Generation
• Simple `Agent` or `Registry` holding `%{chat_id => %{title, created_at}}`.  
• `new()` → UUID v4 via `Ecto.UUID.generate/0` (already available through Ecto, no DB needed).  
• Store metadata in memory only; derive list from disk on boot for persistence.

---
## 4. AI Client Abstraction (`ai_client.ex`)
1. Function `stream_completion!(prompt, opts, pid)` → spawns a **linked** `Task`, performs HTTP/SSE, sends chunks to `pid` as `{:ai, chat_id, token}`.  
2. Keep **timeout** & **back-off** configurable via `Application.compile_env/3`.  
3. For dev mode, fallback to a dummy generator that streams lorem ipsum.

---
## 5. LiveView Flow (`chat_live.ex`)
### Mount
```
{:ok, socket} =
  socket
  |> assign(:chats, ChatRegistry.list())
  |> assign(:active_chat, nil)
  |> assign(:stream_opts, %{dom_id: "messages"})
  |> stream(:messages, [], reset: true)
```
### Events
| Event | Handler | Action |
|-------|---------|--------|
| "new_chat" | `handle_event/3` | calls `ChatRegistry.new/0`, pushes patch to new chat route |
| "select_chat" | `handle_event/3` | loads CSV logs → `stream_reset/3` with history |
| "send_msg" | `handle_event/3` | inserts user bubble, saves to CSV, invokes `AIClient.stream_completion!/3` |
| "clear_chat" | `handle_event/3` | `stream_reset/3`, archive CSV |
| "rename" | `handle_event/3` | updates Registry + sidebar |

### Info messages
```
handle_info({:ai, chat_id, token}, socket) do
  stream_insert(socket, :messages, %{id: uuid(), role: :assistant, token: token})
end
```
Use `:temporary_assigns` for `:messages` to limit memory.

---
## 6. Sidebar Component (`sidebar.ex`)
• Renders list of chats with current **active** highlight.  
• Hover row → inline rename & delete icons.  
• "New Chat" fixed button at bottom; DaisyUI `btn-primary`.

---
## 7. Message Bubble Component
| Variant | Classes | Notes |
|---------|---------|-------|
| user | `chat-bubble chat-bubble-info` | right-aligned │
| assistant | `chat-bubble chat-bubble-success` | left-aligned + logo avatar |
Include subtle **fade-in** keyframe + caret cursor when streaming.

---
## 8. Responsive Layout
1. **Desktop ≥ 768 px** → two-pane flex: `w-72` sidebar + `flex-1` chat.  
2. **Mobile** → sidebar collapses to drawer; topbar shows chat title + hamburger.

---
## 9. Supervision Tree Changes
Add under `LiveAiChat.Application`:
```
children = [
  {Registry, keys: :unique, name: LiveAiChat.ChatRegistry},
  LiveAiChat.CsvStorage,
  {Task.Supervisor, name: LiveAiChat.AITaskSup}
]
```
All spawned AI tasks should run under `AITaskSup` with `Task.Supervisor.async_nolink/3`.

---
## 10. Telemetry & Observability
• Emit `[:live_ai_chat, :ai, :latency_ms]`.  
• Attach observer in `telemetry.ex` → logs to console + dashboard chart.

---
## 11. Testing Strategy
1. **LiveView tests** (`Phoenix.LiveViewTest`):
   - stream inserts on send.  
   - history loads from CSV.  
2. **CsvStorage test**: round-trip append ➜ load.  
3. **AI Client**: stub via `Application.put_env/4` to ensure deterministic tokens.

---
## 12. Progressive Enhancement Ideas (edge of MVP)
• Fuzzy search across chats (`phx-change` on sidebar search input).  
• Keyboard shortcuts (Cmd+K, Cmd+Shift+N) via `phx-window-keydown` hooks.  
• "Jump to bottom" pill appears when user scrolls away from end.

---
## 13. Implementation Milestones & Checklist
- [ ] **Scaffold modules & supervision tree**.  
- [ ] **CSV storage layer works** (unit tests green).  
- [ ] **Sidebar & chat LiveView functional** (no AI yet).  
- [ ] **AI streaming integrated** (dummy client).  
- [ ] **Visual polish & responsiveness**.  
- [ ] **Telemetry + CI tests** pass.

---
*End of PLAN 2*