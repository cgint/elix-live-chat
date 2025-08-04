# PLAN 3 — Step-by-Step Implementation Plan

This plan breaks down the development of the LiveAiChat application into manageable, iterative steps. We will tackle one feature at a time to build the application incrementally.

---

## ✅ Step 1: Project Scaffolding & Basic UI

- [x] **1a. Setup Routes:** Define the root route `/` to point to a new `ChatLive` LiveView.
- [x] **1b. Create ChatLive LiveView:** Generate the `LiveAiChatWeb.ChatLive` module.
- [x] **1c. Basic Layout:** Implement the two-pane layout (sidebar and main chat area) in the `chat_live.html.heex` template using basic placeholders.

## ✅ Step 2: CSV Storage Layer

- [x] **2a. CsvStorage GenServer:** Create a `LiveAiChat.CsvStorage` GenServer to handle all file I/O operations.
- [x] **2b. Core Functions:** Implement `list_chats()`, `read_chat(chat_id)`, and `append_message(chat_id, message)` functions.
- [x] **2c. Supervision:** Add the `CsvStorage` GenServer to the main application supervision tree.
- [x] **2d. Unit Tests:** Write tests for the `CsvStorage` module to ensure file operations are reliable.

## ✅ Step 3: Sidebar - Listing Chats

- [x] **3a. Load Chats on Mount:** In `ChatLive`, call `CsvStorage.list_chats()` in the `mount/3` callback to populate the sidebar.
- [x] **3b. Render Chat List:** Display the list of chats in the sidebar.
- [x] **3c. Handle Chat Selection:** Use `phx-click` to handle selecting a chat from the sidebar, storing the active `chat_id` in the LiveView's assigns.

## ✅ Step 4: Chat View - Displaying Messages

- [x] **4a. Load Messages:** When a chat is selected, fetch its history using `CsvStorage.read_chat(chat_id)`.
- [x] **4b. Render Messages:** Use `live_stream` to render the messages for the active chat in the main view.
- [x] **4c. Message Bubbles:** Style the messages as chat bubbles, distinguishing between "user" and "assistant" roles.

## ✅ Step 5: Message Input & Form

- [x] **5a. Create Message Form:** Add a `<.form>` component for the user to type and submit messages.
- [x] **5b. Handle Form Submission:** Implement a `handle_event` for the "save" event from the form.
- [x] **5c. Append and Stream:** On submit, append the user's message to the CSV file and `stream_insert` it into the UI immediately.

## ✅ Step 6: Dummy AI Client

- [x] **6a. AIClient Module:** Create a `LiveAiChat.AIClient` module.
- [x] **6b. Dummy Streaming Function:** Implement a `stream_reply/1` function that simulates a streaming AI response by sending back a canned sentence, one word at a time, with a short delay between words. This will run in a `Task`.

## ✅ Step 7: AI Integration

- [x] **7a. Task Supervisor:** Add a `Task.Supervisor` to the application's supervision tree for managing AI tasks.
- [x] **7b. Call AI on Message:** After the user sends a message, start a supervised `Task` that calls the `AIClient.stream_reply/1` function.
- [x] **7c. Stream AI Response:** As the `AIClient` task sends back chunks of the reply, use `stream_insert` or `stream_configure` to append the tokens to the assistant's message bubble in the UI.
- [x] **7d. Pulsating Cursor:** Show a pulsating cursor element while the AI response is streaming.

## ✅ Step 8: Chat Management Features

- [ ] **8a. New Chat:** Add a "+ New Chat" button that creates a new, empty CSV file and adds it to the sidebar.
- [ ] **8b. Rename Chat:** Add a rename icon and functionality to edit chat titles inline.
- [ ] **8c. Delete Chat:** Add a delete icon and a confirmation step before removing the chat from the list and archiving its CSV file.

## ✅ Step 9: Final Polish

- [ ] **9a. Auto-Scrolling:** Implement JavaScript hooks to auto-scroll the chat view to the latest message.
- [ ] **9b. Fade-in Animations:** Add simple CSS fade-in animations for new messages.
- [ ] **9c. Responsive Design:** Ensure the layout works on smaller screens, potentially collapsing the sidebar into a drawer.
- [ ] **9d. Code Cleanup:** Run `mix format` and review the code for clarity and conventions.

---
*End of PLAN 3*
