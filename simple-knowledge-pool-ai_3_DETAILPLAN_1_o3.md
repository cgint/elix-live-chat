# Detailed Implementation Blueprint – Simple Knowledge Pool AI → LiveAiChat  (o3 edition)

> This document expands Plan-4 into explicit engineering tasks, code skeletons, DB-free persistence logic, and test matrices.  All paths are absolute to `/Users/cgint/dev/elix-live-chat/`.

---
## 0. Conventions
* `@live_ai_chat/` → umbrella alias for `lib/live_ai_chat/`.
* `@web/` → `lib/live_ai_chat_web/`.
* Tests live in `test/` mirroring paths.
* **GenServer design rule**: public API → synchronous (`call`) for reads, asynchronous (`cast`) for writes where latency is non-critical.

---
## 1. Work-Package 1 – FileStorage
### 1.1 Module Skeleton
```elixir
# @live_ai_chat/file_storage.ex

# credo:disable-for-this-file

defmodule LiveAiChat.FileStorage do
  @moduledoc """
  GenServer guarding access to files under priv/uploads/ .
  Performs write/read/delete so callers never touch the FS directly.
  """

  use GenServer
  require Logger

  @upload_dir Path.join(:code.priv_dir(:live_ai_chat), "uploads")

  # -- Public API -----------------------------------------------------------

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @spec save_file(String.t(), binary()) :: :ok | {:error, term()}
  def save_file(name, bin), do: GenServer.call(__MODULE__, {:save, name, bin})

  @spec read_file(String.t()) :: {:ok, binary()} | {:error, :enoent}
  def read_file(name),        do: GenServer.call(__MODULE__, {:read, name})

  @spec delete_file(String.t()) :: :ok | {:error, term()}
  def delete_file(name),      do: GenServer.call(__MODULE__, {:delete, name})

  @spec list_files() :: [String.t()]
  def list_files,             do: GenServer.call(__MODULE__, :list)

  # -- GenServer callbacks --------------------------------------------------

  def init(_) do
    File.mkdir_p!(@upload_dir)
    {:ok, %{dir: @upload_dir}}
  end

  def handle_call({:save, name, bin}, _from, state) do
    path = Path.join(state.dir, safe_filename(name))
    reply = File.write(path, bin, [:binary])
    {:reply, reply, state}
  end

  def handle_call({:read, name}, _from, state) do
    path = Path.join(state.dir, name)
    reply = File.read(path)
    {:reply, reply, state}
  end

  def handle_call({:delete, name}, _from, state) do
    path = Path.join(state.dir, name)
    reply = File.rm(path)
    {:reply, reply, state}
  end

  def handle_call(:list, _from, state) do
    {:ok, files} = File.ls(state.dir)
    {:reply, files, state}
  end

  # -- Helpers --------------------------------------------------------------

  defp safe_filename(name) do
    name |> Path.basename() |> String.replace(~r/[^\w\.-]/, "_")
  end
end
```
### 1.2 Supervisor Hook
Add to `@live_ai_chat/application.ex`:
```elixir
# ... existing children ...
children = [
  LiveAiChat.FileStorage,
  LiveAiChat.TagStorage,
  {Task.Supervisor, name: LiveAiChat.TaskSupervisor}
]
```
### 1.3 Unit Tests
```
# test/live_ai_chat/file_storage_test.exs
...
```
* Cases: save → read, list length, delete non-existent returns error.

---
## 2. Work-Package 2 – TagStorage
### 2.1 Module Skeleton
```elixir
# @live_ai_chat/tag_storage.ex

defmodule LiveAiChat.TagStorage do
  use GenServer
  require Logger

  @tags_json Path.join(:code.priv_dir(:live_ai_chat), "data/file-tags.json")

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  # Public API
  def get_all_tags,               do: GenServer.call(__MODULE__, :all_tags)
  def update_tags_for_file(f, t), do: GenServer.cast(__MODULE__, {:update_tags, f, t})
  def get_extraction(f),          do: GenServer.call(__MODULE__, {:get_meta, f})
  def save_extraction(f, data),   do: GenServer.cast(__MODULE__, {:save_meta, f, data})

  ## callbacks
  def init(_) do
    File.mkdir_p!(Path.dirname(@tags_json))
    state = %{tags: load_json(@tags_json)}
    {:ok, state}
  end

  def handle_call(:all_tags, _from, st), do: {:reply, st.tags, st}

  def handle_call({:get_meta, file}, _f, st) do
    {:reply, read_meta(file), st}
  end

  def handle_cast({:update_tags, file, tag_list}, st) do
    new_tags = Map.put(st.tags, file, tag_list)
    File.write!(@tags_json, Jason.encode!(new_tags, pretty: true))
    {:noreply, %{st | tags: new_tags}}
  end

  def handle_cast({:save_meta, file, data}, st) do
    meta_path(file) |> File.write!(Jason.encode!(data, pretty: true))
    {:noreply, st}
  end

  # helpers
  defp load_json(path) do
    case File.read(path) do
      {:ok, bin} -> Jason.decode!(bin)
      _ -> %{}
    end
  end
  defp meta_path(file), do: Path.join(:code.priv_dir(:live_ai_chat), "uploads/#{file}.meta.json")
  defp read_meta(f), do: File.read(meta_path(f)) |> case do {:ok,b}->Jason.decode!(b); _->%{} end
end
```
### 2.2 Tests
* Concurrent updates (spawn 10 casts) → verify final JSON.

---
## 3. Work-Package 3 – Knowledge.Extractor
### 3.1 Module
```elixir
# @live_ai_chat/knowledge/extractor.ex

defmodule LiveAiChat.Knowledge.Extractor do
  @task_sup LiveAiChat.TaskSupervisor
  @gemini LiveAiChat.AIClient

  def enqueue(filename, bin) do
    Task.Supervisor.start_child(@task_sup, fn -> extract_and_save(filename, bin) end)
  end

  defp extract_and_save(file, bin) do
    payload = %{file: Base.encode64(bin)} # simplistic
    case @gemini.extract_file(payload) do
      {:ok, %{"summary" => s} = data} ->
        LiveAiChat.TagStorage.save_extraction(file, data)
      err -> Logger.error("Extractor failed #{inspect err}")
    end
  end
end
```
### 3.2 Contract Test
* Mock `AIClient` with Mox.

---
## 4. Work-Package 4 – KnowledgeLive UI
### 4.1 LiveView Skeleton
```elixir
# @web/live/knowledge_live.ex

defmodule LiveAiChatWeb.KnowledgeLive do
  use LiveAiChatWeb, :live_view
  alias Phoenix.LiveView.UploadConfig
  alias LiveAiChat.{FileStorage, TagStorage, Knowledge.Extractor}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      {:ok, allow_upload(socket, :file,
                accept: ~w(.pdf .mht .txt), max_entries: 5, max_file_size: 10_000_000)
           |> assign_files_and_tags()}
    else
      {:ok, socket |> assign(:files, []) |> assign(:tags, %{})}
    end
  end

  defp assign_files_and_tags(socket) do
    assign(socket,
      files: FileStorage.list_files(),
      tags:  TagStorage.get_all_tags()
    )
  end

  @impl true
  def handle_event("save", _params, socket) do
    {:ok, entries} = consume_uploaded_entries(socket, :file, fn %{path: path}, entry ->
      bin = File.read!(path)
      :ok = FileStorage.save_file(entry.client_name, bin)
      Exractor.enqueue(entry.client_name, bin)
      {:ok, "done"}
    end)
    {:noreply, assign_files_and_tags(socket)}
  end

  # tag editing etc ...
end
```
### 4.2 Component Tests with `Phoenix.LiveViewTest`

---
## 5. Work-Package 5 – Chat Enhancements
### 5.1 Metadata Struct & Storage
* New module `LiveAiChat.ChatSession` encapsulates `%{id, context: %{tags: [], files: []}}` and provides `save_meta/1`, `load_meta/1` (JSON next to CSV).

### 5.2 ChatLive Changes
* Add selection modal (Bootstrap DaisyUI modal) invoked by "New Chat" btn.
* On chat select, call helper `load_pool_context/1` → Tag resolve → File read → maybe cache in ETS: `:ets.new(:pool_ctx, [:set, :public, read_concurrency: true])`.
* Modify `handle_event("send_message",...)` to include context when calling `AIClient`.

---
## 6. API Controllers
### 6.1 Routes
`@web/router.ex` snippet already in Plan-3.
### 6.2 FileController example
```elixir
# @web/controllers/file_controller.ex

def index(conn, _params) do
  json(conn, FileStorage.list_files())
end
```
# etc.

---
## 7. Telemetry
Attach metrics in each GenServer `handle_call/handle_cast` and LiveView actions under event prefix `[:live_ai_chat, :knowledge_pool, ...]`.

---
## 8. CI / Pre-commit Changes
* Update `precommit.sh` to run `mix test --color`.
* Ensure `mix format --check-formatted`.

---
## 9. Deliverable Checklist
- [ ] All modules compiled with `mix compile`.  
- [ ] 95% unit test coverage on new code.  
- [ ] LiveView integration tests pass.  
- [ ] Docs updated.  
- [ ] Feature flag `:knowledge_ui` default false.

---
_End of detailed blueprint_
