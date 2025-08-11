# Integration Roadmap (Plan 4): Simple Knowledge Pool AI → LiveAiChat

> Consolidated & time-boxed execution roadmap, incorporating feedback from Plans 1-3.

---
## 1. Objectives Recap
* Seamless file-upload, tagging, and context-aware chat in Phoenix 1.8 / LiveView 0.20.
* Zero new runtime deps, disk-only persistence.
* Target delivery window: **4 weeks**.

---
## 2. Work-Package Breakdown & Timeline
| Week | Work-Package | Key Tasks | Owner | Exit Criteria |
|------|--------------|-----------|-------|---------------|
|1|WP-1 Backend Foundations| • Scaffold `FileStorage` & `TagStorage` GenServers  
• Add to supervision tree, unit tests  
• Implement `knowledge/extractor.ex` stub w/ mocked Gemini call | BE | All functions return OK, tests green |
|1-2|WP-2 Extractor & Background Tasks| • Connect real Gemini client  
• Task.Supervisor integration  
• Store summaries in `.meta.json`; property tests for JSON schema | BE | Summaries saved, 95% test coverage |
|2|WP-3 KnowledgeLive UI α| • `allow_upload/3` drag-&-drop  
• Display file list via streams  
• Tag chips editable (local state only) | FE | Upload & list flows work in browser |
|3|WP-4 KnowledgeLive β| • Persist tags via `TagStorage`  
• Suggested tags from extractor  
• Error flashes, MIME/size guards | FE | E2E LiveView test passes |
|3-4|WP-5 Context-Aware Chat| • Chat metadata struct & file  
• New-chat modal (select tags/files)  
• Pool context loading & ETS cache  
• Prompt concatenation | BE + FE | User sees assistant using file context |
|4|WP-6 API Parity| • `/api/files`, `/api/file-tags`, `/api/chat` controllers  
• Channel/Plug streaming impl  
• JSON contract tests | BE | cURL examples succeed |
|4|WP-7 Quality & Ops| • Telemetry metrics  
• Security hardening checklist  
• README & new guide  
• Precommit + full test suite | Dev Ex | `./precommit.sh` clean |

---
## 3. Testing Strategy
1. **Unit** – GenServers, extractor, API controllers.  
2. **Integration** – LiveView upload & tag editing (`Phoenix.LiveViewTest`).  
3. **Property** – extracted JSON conforms to schema; fuzz file names.

---
## 4. Risk Register & Mitigations
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
|Gemini latency for large files|M|M|Extract in Task, show progress, cache result|
|File system race conditions|L|H|Serialise writes via GenServer, use `:timer.sleep` backoff on contention|
|Large context exceeds LLM token limit|M|H|Truncate/summary fallback, configurable max bytes|
|User uploads malicious file|M|M|MIME whitelist, size cap 10 MB, store under random UUID filename|

---
## 5. Open Questions
1. Final maximum upload size? (assumed 10 MB)  
2. Should chat context support **per-tag** summary rather than full text?  
3. Prod feature-flag name: `:knowledge_pool` or `:knowledge_ui`?

---
## 6. Definition of Done (DOD)
* All exit criteria above met.
* CI `precommit.sh` pipeline green.
* Docs updated; new guide linked from README.
* Security review checklist signed off.

---
## 7. Next Action
Begin WP-1 – create `FileStorage` GenServer + tests.
