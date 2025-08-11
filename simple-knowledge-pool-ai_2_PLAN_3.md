# Integration Plan: Bringing Simple Knowledge Pool AI into LiveAiChat (Phoenix LiveView, Aug 2025)

> Goal: re-implement the SvelteKit-based knowledge-pool features (file upload, tagging, context-aware chat) idiomatically in Elixir, Phoenix 1.8 and LiveView 0.20 without new runtime dependencies or a database.

---
## TL;DR (one-screen summary)
1. **GenServers** – `FileStorage` & `TagStorage` for safe, concurrent disk I/O.
2. **Extractor** – background Task to summarise uploads via existing Gemini client.
3. **KnowledgeLive** – LiveView UI for drag-drop uploads & tag editing.
4. **Context-Aware Chat** – extend `ChatLive` to start sessions with selected tags/files and prepend that context to prompts.
5. **Minimal JSON API** – thin controllers for parity with the original REST endpoints.
6. **Quality & Ops** – tests, telemetry, security hardening, docs.

---
## Architectural Blueprint
```
Supervisor
├─ FileStorage (GenServer)          # priv/uploads/*
├─ TagStorage  (GenServer)          # priv/data/file-tags.json + *.meta.json
└─ Task.Supervisor
     └─ Knowledge.Extractor tasks   # Gemini summaries in background
```
*LiveView tree*: `ChatLive` ↔ `KnowledgeLive` component

---
## Phase 1 – Backend Foundations
| Step | File | Description |
|------|------|-------------|
|1.1|`lib/live_ai_chat/file_storage.ex`|Save/read/delete/list files in **priv/uploads/**. Add to supervision tree.|
|1.2|`lib/live_ai_chat/tag_storage.ex`|Manage `file-tags.json` and per-file `.meta.json` with safe concurrent access.|
|1.3|`lib/live_ai_chat/knowledge/extractor.ex`|`extract_content/2` ⇒ Task.Supervisor ⇒ Gemini ⇒ `%{summary,key_points,categories}` JSON; save via TagStorage.|

---
## Phase 2 – UI for Knowledge Management
1. **KnowledgeLive (`lib/live_ai_chat_web/live/knowledge_live.ex`)**  
   • `allow_upload/3` for drag-&-drop.  
   • On consume → `FileStorage.save_file/2` then start extractor Task.  
   • Stream list of files, display/edit tags, suggest categories.
2. UX details  
   • Chips for tags (Phoenix.Component).  
   • Flash on errors, size caps, MIME whitelist.

---
## Phase 3 – Context-Aware Chat
1. **Chat metadata**: each chat gains `%{chat_id, context: %{tags: [], files: []}}` persisted in `priv/chat_logs/<id>.meta.json`.
2. **New-chat modal**: select tags/files before creating room.
3. **On mount/select** in `ChatLive`:  
   a. Resolve tags → filenames (TagStorage)  
   b. Read contents (FileStorage)  
   c. Build/ETS-cache `pool_context` assign.
4. **send_message event**: prepend `pool_context` + chat history + prompt → `AIClient` stream.

---
## Phase 4 – Thin JSON API (parity, optional)
```
scope "/api", LiveAiChatWeb do
  pipe_through :api
  get  "/files",        FileController, :index
  post "/files/upload", FileController, :upload
  get  "/file-tags",    TagController,  :index
  put  "/file-tags",    TagController,  :update
  post "/chat",         ChatApiController, :create   # stream or channel
end
```
Controllers are pass-through wrappers around GenServers & `AIClient`.

---
## Phase 5 – Quality, Observability & Deployment
* **Tests**: unit (GenServers), LiveView integration (uploads & tags), property test extractor JSON schema.
* **Telemetry**: counters for uploads, extraction time, chat latency.
* **Security**: CSRF, MIME whitelist, size caps, path sanitisation, Phoenix.Upload validations.
* **Performance**: ETS cache for large contexts; streams in LiveView; `chunk_size: :dynamic` in uploads.
* **Docs**: update README and add `docs/knowledge_pool_usage.md`.

---
## Roll-out Strategy
1. Merge Phase 1 – run full chat regression tests.  
2. Gate Phase 2 behind feature flag `:knowledge_ui` – enable on staging.  
3. Migrate chats to new metadata file format lazily on first load.  
4. Observe metrics; enable Phase 3 for production users.  
5. Iterate & polish.

---
## Appendix – Why this follows Aug 2025 Best Practices
* LiveView 0.20 streams/components remove most JS → consistent UX.
* GenServer supervision = fault-tolerant, hot reload friendly.
* ETS caching pattern documented in LiveView Guides §Deployments 2025.
* No extra deps → respects repo constraints.
* Clear separation: storage ↔ extraction ↔ UI ↔ chat logic.

---
_End of plan_
