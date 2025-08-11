# PLAN 0 — Project Vision & Feature Scope

## ✨ Project Elevator Pitch

A **stream-first, modern AI chat workspace** built with Phoenix LiveView, Ash Framework and pure Elixir.  
Users can open multiple chat “conversations”, see their message history at a glance, and enjoy real-time, token-by-token AI responses that feel as if the assistant is typing live.

*No database, no extra dependencies* — persistence is handled by lightweight CSV files so the whole stack stays lean and deploy-friendly.

---
## Core User Stories

1. **Start a New Chat**  
   • Click a “+ New Chat” button to open a blank conversation.  
   • The sidebar instantly lists the new chat with an editable title (defaults to today’s date & time).

2. **Send Messages & See Live AI Typing**  
   • Type into a single-line input (auto-expands for long text) and press Enter.  
   • Immediately see your message appear in the transcript.  
   • Watch the AI assistant stream its reply token-by-token for an authentic “typing” effect.

3. **Switch Between Conversations**  
   • Sidebar lists all previous chats.  
   • Clicking a chat loads its full history without page reloads.  
   • Active chat is highlighted; unread badge shows if the AI is still responding in a background chat.

4. **Persistent History**  
   • Each chat transcript is appended to a per-chat CSV file (`priv/data/chat_logs/<chat-id>.csv`).  
   • On reconnect or page refresh, the LiveView reconstructs the history from CSV so nothing is lost.

5. **Rename or Delete Chats**  
   • Hovering a chat title reveals ✏️ (rename) and 🗑️ (delete) icons.  
   • Rename opens an inline input; delete asks for confirmation.

6. **Clear Chat**  
   • “Clear conversation” action removes all messages from view but keeps the chat shell for fresh context.  
   • Under the hood `stream_reset/3` wipes the LiveView stream; the CSV file is archived not erased.

---
## UI Mood-Board

• **Layout**: Two-pane design: slim left sidebar (max 280 px) for conversations; right pane for active chat.  
• **Styling**: Tailwind 3 utility classes + DaisyUI theme already present in assets.  
• **Colour Palette**: Neutral dark mode first (slate/stone), accent with indigo & emerald for buttons and highlights.  
• **Typography**: Inter or system sans-serif, 14-15 px base, 1.6 line height.

**Delight Details**
- Subtle pulsating cursor while AI is streaming.  
- Smooth auto-scroll to newest message (unless user scrolls up, then show a “Jump to bottom” pill).  
- Chat bubbles fade-in (@keyframes) for a soft feel.

---
## Technical Pillars (high-level)

1. **Phoenix LiveView** — Real-time UI, WebSocket transport, `live_stream/4` for incremental rendering.  
2. **Ash Framework** — Domain & auth layer; potentially expose chats/messages as resources if future DB is added.  
3. **CSV Storage** — Minimal flat-file persistence using Elixir’s `File` & `IO` modules.  
4. **Task.async + PubSub** — Non-blocking AI calls; future-proof for multi-user broadcasting.

---
## Nice-to-Have (not MVP)

- **Search across chats** (client-side fuzzy filter first).  
- **Export conversation** to Markdown or JSON.  
- **Keyboard shortcuts** (Cmd+K to focus input, Cmd+Shift+N for new chat, etc.).  
- **Responsive mobile layout**: drawer instead of sidebar.

---
## Out-of-Scope for MVP

- User authentication (can layer AshAuthentication later).  
- File uploads / image generation.  
- Vector database or embeddings search.  
- Any additional Hex or NPM dependency.

---
### Success Criteria

✔ Users can hold multiple parallel chats and switch seamlessly.  
✔ AI replies stream in real time without blocking UI.  
✔ Chat histories survive browser refresh thanks to CSV logs.  
✔ The interface feels lightweight, responsive, and visually polished with zero additional dependencies.

*End of PLAN 0*