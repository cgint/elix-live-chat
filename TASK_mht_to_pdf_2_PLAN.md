### Task: MHT to PDF conversion on upload

#### Goals
- Accept `.mht/.mhtml` uploads in Knowledge page, convert them to PDF via remote REST service, then process like any other PDF (store, extract metadata, tag, and make available to chat).
- Keep UI responsive: show “Converting to PDF…” until conversion completes; surface errors if conversion fails.

#### Scope (minimal changes)
- Only change Knowledge upload flow and supporting modules; do not alter chat logic except relying on existing “PDF-only” listing.
- Add a small converter client and PubSub wiring. No DB; reuse `FileStorage` and `TagStorage`.

#### Architecture
- Upload handler stores the original `.mht/.mhtml`, kicks off async conversion task, tracks status in LiveView assigns and optional on-disk marker.
- Converter client posts the MHT bytes to a configured REST endpoint, receives PDF bytes, writes sanitized `*.pdf`, and enqueues extraction with existing `Knowledge.Extractor`.
- PubSub events update UI: conversion done/failed. Extraction continues to work as-is and publishes its own `{:extraction_done, filename}`.

#### Module and file changes
- `lib/live_ai_chat_web/live/knowledge_live.ex`
  - `allow_upload(:knowledge_files, accept: ~w(.pdf .mht .mhtml), ...)`.
  - In `handle_event("save", ...)`, branch by extension:
    - For `.pdf`: keep current path.
    - For `.mht/.mhtml`:
      - Save the original via `FileStorage.save_file/2`.
      - Start `Task.Supervisor` job to run conversion (see Converter section).
      - Maintain `:conversion_status` assign map `%{filename => :converting | :failed | {:done, pdf}}`.
  - `handle_info` for new PubSub topics:
    - `{:conversion_done, mht_filename, pdf_filename}`: update status map, refresh files/tags, optionally flash success.
    - `{:conversion_failed, mht_filename, reason}`: mark failed, flash error.
  - UI (template) changes: next to items in files list, show spinner/text for converting entries; failed state message. PDFs continue to list normally via `FileStorage.list_pdf_files/0`.

- New: `lib/live_ai_chat/mht_converter.ex`
  - Behaviour `LiveAiChat.MhtConverter` with `@callback convert(mht_filename :: String.t(), mht_binary :: binary()) :: {:ok, pdf_binary :: binary(), pdf_filename :: String.t()} | {:error, term()}`.
  - Adapter `LiveAiChat.MhtConverter.Remote` using `Req` to POST to configured endpoint; supports auth headers; sensible timeouts; validates `application/pdf` and non-empty body.
  - Helper to derive `pdf_filename` from `.mht/.mhtml` (`Path.rootname <> ".pdf"`) using `FileStorage.safe_filename/1`.

- Optional marker files (resilience)
  - Write `"<name>.conv.json"` in upload dir while in progress with `{status, startedAt, source, target?}`; update on success/failure. On `mount/3`, read markers to restore UI state if needed.

#### PubSub
- Use existing `LiveAiChat.PubSub` and topic `"knowledge"`.
- New events broadcast by conversion task:
  - `{:conversion_done, mht_filename, pdf_filename}`
  - `{:conversion_failed, mht_filename, reason}`

#### Configuration
- Add in `config/*.exs`:
  - `config :live_ai_chat, :mht_converter, adapter: LiveAiChat.MhtConverter.Remote`
  - `config :live_ai_chat, :mht_converter_url, "https://converter.example/convert"`
  - Optional: `:mht_converter_headers` (e.g., `Authorization`), `:mht_converter_timeout_ms`.

#### Error handling & limits
- Respect existing upload max size; ensure remote request has a timeout and limited retries (e.g., 1 retry).
- Validate converter response content-type and non-empty bytes.
- On failure: keep original MHT, mark status failed, show flash, do not list in chat (chat lists PDFs only).

#### Extraction flow (unchanged)
- After successful conversion and save of `pdf_filename`, call `Knowledge.Extractor.enqueue(pdf_filename, pdf_bytes)`.
- Optionally enhance saved metadata with `"sourceMhtFile"` pointing to the original `.mht`.

#### Tests (TDD)
- Unit: `LiveAiChat.MhtConverter.Remote` using `Mox` to stub `Req.request/1` (or wrap `Req` in a small client for easier mocking). Cases: success, timeout, non-PDF content.
- LiveView: extend `test/live_ai_chat_web/live/knowledge_live_test.exs`:
  - Accept `.mht` upload, assert “Converting…” indicator.
  - Simulate success by sending `{:conversion_done, "foo.mht", "foo.pdf"}`; assert PDF appears in list, status cleared.
  - Simulate failure `{:conversion_failed, ...}`; assert error flash and no PDF listed.
- Integration happy path: conversion success triggers `Extractor.enqueue` (can assert PubSub and metadata save via `TagStorage`).

#### Rollout steps
1) Add converter behaviour/adapter and configs.
2) Update `KnowledgeLive` accept list and conversion branch.
3) Wire PubSub messages and UI state.
4) Add tests per above and ensure they fail.
5) Implement until tests pass; run `./precommit.sh` repeatedly until green.
6) Manual check: upload `.mht` → see “Converting…”, then PDF appears and is extractable/searchable.

#### Non-goals (now)
- Handling embedded assets beyond what the remote service returns in the PDF.
- Direct MHT preview in UI (only status + final PDF supported).

#### Open config questions
- Converter endpoint shape (path, method, payload contract) and auth. Default assumption: `POST /convert` with raw body or multipart; returns PDF as body. Adjust adapter accordingly.


