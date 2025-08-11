# Request (20250811_193212)

```
simple-knowledge-pool-ai.md contains t he code for an application done in sveltekit. this codebase is a simple chat done in elixir, phoenix, liveview. I need you to create the plan on how we can best integrate the functionslity from simple-knowledge-pool-ai.md into the current codebase by using elixir, phoenix, liveview best practices as of august 2025. create a detailed implementation plan.
```

# Response


Of course. Here is a detailed, phased implementation plan to integrate the functionality of the SvelteKit-based "Simple Knowledge Pool AI" into your existing Elixir/Phoenix/LiveView chat application.

This plan adheres to the project's established constraints (no new dependencies, no database) and follows best practices for building robust, concurrent applications with the Elixir/Phoenix stack as of August 2025.

### **Project Goal**

The objective is to evolve the existing `LiveAiChat` application from a simple multi-conversation chat into a powerful knowledge-based assistant. This involves integrating features for file uploading, tagging, and context-aware chatting, re-implementing the SvelteKit application's logic idiomatically in Elixir and Phoenix LiveView.

The core principle is to manage all state and I/O through robust, concurrent Elixir processes, ensuring a responsive, real-time user experience without blocking the UI.

---

### **Architectural Blueprint**

We will extend the current architecture by introducing new supervised processes to handle file and metadata management, while enhancing the `ChatLive` LiveView to incorporate knowledge context.

**New Components:**

*   **`FileStorage` GenServer:** A new GenServer responsible for managing files in a new `priv/uploads/` directory. It will handle file writes, reads, and deletions.
*   **`TagStorage` GenServer:** A new GenServer to manage metadata, specifically reading from and writing to `priv/data/file-tags.json` and individual `priv/uploads/<filename>.meta.json` files. This centralizes metadata I/O, preventing race conditions.
*   **`Knowledge.Extractor` Module:** A module containing logic to perform content extraction from uploaded files (PDFs, etc.) by sending them to the Gemini API. This will be run in background tasks.
*   **`KnowledgeLive` (or Component):** A new LiveView or a stateful component responsible for the UI of uploading and managing files and tags. This will be integrated into the main layout.

**Data Persistence:**

*   **Chat History:** Remains in `priv/chat_logs/<chat_id>.csv`.
*   **Uploaded Files:** Will be stored in `priv/uploads/`.
*   **File Tags:** A single JSON file at `priv/data/file-tags.json`.
*   **Extracted Metadata:** A corresponding `.meta.json` file for each uploaded file in `priv/uploads/`.

---

## **Step-by-Step Implementation Plan**

### **Phase 1: Foundational Backend Services**

This phase focuses on building the non-UI backend logic required to manage knowledge files and their metadata.

**Step 1.1: Create the `FileStorage` GenServer**
*   **Purpose:** To handle all physical file operations within `priv/uploads/`, ensuring they don't block calling processes.
*   **File:** `lib/live_ai_chat/file_storage.ex`
*   **API:**
    *   `start_link/1`
    *   `save_file(filename, binary_content)`
    *   `read_file(filename)`
    *   `delete_file(filename)`
    *   `list_files()`
*   **Action:** Add this GenServer to the main supervision tree in `lib/live_ai_chat/application.ex`. Create corresponding unit tests.

**Step 1.2: Create the `TagStorage` GenServer**
*   **Purpose:** To provide safe, concurrent access to the JSON files that store tags and extracted metadata.
*   **File:** `lib/live_ai_chat/tag_storage.ex`
*   **API:**
    *   `start_link/1`
    *   `get_all_tags()`: Reads `priv/data/file-tags.json`.
    *   `update_tags_for_file(filename, tags)`: Updates `file-tags.json`.
    *   `get_extraction(filename)`: Reads `priv/uploads/<filename>.meta.json`.
    *   `save_extraction(filename, metadata)`: Writes to `priv/uploads/<filename>.meta.json`.
*   **Action:** Add this GenServer to the supervision tree and create unit tests.

**Step 1.3: Implement the Content Extractor**
*   **Purpose:** To extract summaries, key points, and categories from files by leveraging the existing Gemini AI client. This avoids adding new dependencies for local file parsing.
*   **File:** `lib/live_ai_chat/knowledge/extractor.ex`
*   **Logic:**
    1.  Define a function `extract_content(filename, file_binary)`.
    2.  This function will call the `LiveAiChat.AIClient.Gemini` module, but with a modified prompt and body to handle file data (Base64 encoded). The prompt will ask the LLM to return a JSON object with `summary`, `keyPoints`, and `categories`.
    3.  The extraction will be triggered as a background task via `Task.Supervisor.start_child/2`.

### **Phase 2: UI for Knowledge Management**

This phase focuses on building the user-facing components for uploading and tagging files.

**Step 2.1: Create a new `KnowledgeLive` LiveView**
*   **Purpose:** Provide a dedicated UI for file upload and tag management.
*   **File:** `lib/live_ai_chat_web/live/knowledge_live.ex` and corresponding template.
*   **Routing:** Add a new route, e.g., `/knowledge`, in `lib/live_ai_chat_web/router.ex`.
*   **Implementation:**
    *   Use `Phoenix.LiveView.Uploads` (`allow_upload/3`) to handle file transfers securely and efficiently with a drag-and-drop zone.
    *   On completion of an upload (`handle_event("validate", ...)` and `consume_uploaded_entries/3`), save the file using the `FileStorage` GenServer.
    *   After saving, asynchronously trigger the `Knowledge.Extractor` task for PDF and MHT files.

**Step 2.2: Implement the Tag Management UI in `KnowledgeLive`**
*   **Purpose:** Allow users to view all uploaded files and manage their associated tags.
*   **Implementation:**
    *   In `mount/3`, fetch all files from `FileStorage` and all tags from `TagStorage`.
    *   Render a list of files. For each file, display its current tags as removable badges.
    *   Add an input field per file to add new tags.
    *   `handle_event` callbacks will call `TagStorage.update_tags_for_file/2` to persist changes.
    *   Display extracted categories as suggested, clickable tags.

### **Phase 3: Integrating Knowledge into the Chat**

This phase modifies the existing chat interface to make it context-aware.

**Step 3.1: Update the Chat Data Model and Creation Flow**
*   **Purpose:** Allow users to start a chat session based on selected tags or a specific file.
*   **File:** `lib/live_ai_chat_web/live/chat_live.ex`
*   **UI Changes:**
    *   Modify the "New Chat" button to navigate to a new page or show a modal where the user can select from a list of existing tags or files to define the chat's context.
    *   The concept of a `ChatSession` (currently just a `chat_id`) will be expanded to store the context (e.g., `%{chat_id: "...", context: %{tags: ["elixir"], files: []}}`). This context will be saved to a new `.meta.json` file alongside the chat's CSV (e.g., `priv/chat_logs/<chat_id>.meta.json`).

**Step 3.2: Load Context into the Chat**
*   **Purpose:** When a chat is selected, load the content of all associated knowledge files.
*   **File:** `lib/live_ai_chat_web/live/chat_live.ex`
*   **Implementation:**
    *   In `handle_event("select_chat", ...)`:
        1.  Read the chat's metadata to get its associated tags/files.
        2.  Use `TagStorage` to resolve tags to a list of filenames.
        3.  Use `FileStorage` to read the content of each required file.
        4.  Concatenate the file contents into a single `pool_context` string.
        5.  Store this `pool_context` in the socket assigns.
    *   **Optimization:** For large contexts, consider caching this in an ETS table or only loading it when the first message is sent.

**Step 3.3: Modify the AI Client Call**
*   **Purpose:** Prepend the loaded knowledge context to the user's message before sending it to the LLM.
*   **File:** `lib/live_ai_chat/ai_client.ex` and `lib/live_ai_chat_web/live/chat_live.ex`
*   **Implementation:**
    *   In `ChatLive`, when handling the "send\_message" event, retrieve the `pool_context` from the socket assigns.
    *   Create a new prompt that combines the `pool_context`, the chat history, and the new user message, similar to the SvelteKit app's `formatPrompt` logic.
    *   Pass this combined prompt to the `AIClient`.

### **Phase 4: API Endpoints for Parity**

To match the functionality of the SvelteKit application, we will expose the backend services via a JSON API.

*   **File:** `lib/live_ai_chat_web/router.ex`
*   **Implementation:**
    *   Create a new pipeline `:api` in the router.
    *   Add a new scope `/api`.
    *   Create controllers (`FileController`, `TagController`, `ChatApiController`) that act as thin wrappers around the GenServers (`FileStorage`, `TagStorage`) and the `AIClient`.
    *   **Endpoints to create:**
        *   `GET /api/files`: Calls `FileStorage.list_files()`.
        *   `POST /api/files/upload`: A controller action to handle raw file uploads.
        *   `GET /api/file-tags`: Calls `TagStorage.get_all_tags()`.
        *   `PUT /api/file-tags`: Calls `TagStorage.update_tags_for_file/2`.
        *   `POST /api/chat`: Takes a JSON body with `{tags, message, history}` and returns a streamed response. This will require a custom Plug to handle streaming over HTTP, or it can be implemented via Phoenix Channels for external clients.

---

### **Conclusion**

This plan provides a phased approach to integrating the knowledge pool functionality into the `LiveAiChat` application. By leveraging Elixir's strengths in concurrency and state management with GenServers and Tasks, we can build a highly responsive and robust application that adheres to the original project's constraints. The result will be a powerful, context-aware AI chat application built entirely on the Elixir/Phoenix stack.

## Grounding Information

**Note:** LLM was instructed to use Google Search via -S flag but did not use it for this query.


## Token Usage

🔢 **Model**: gemini-2.5-pro

📊 Token Usage
  ├─ Prompt:    1046232
  ├─ Response:  2489
  ├─ Thoughts:  1349
  └─ Total:     1050070

## Generated Files

* Context: .codegiant/20250811_193212_codegiant_context.md
* Raw Output: .codegiant/20250811_193212_codegiant_llm_raw_output.json
* Response: .codegiant/20250811_193212_codegiant_llm_response.md

