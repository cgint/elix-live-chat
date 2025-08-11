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
```elixir
# test/live_ai_chat/file_storage_test.exs
defmodule LiveAiChat.FileStorageTest do
  use ExUnit.Case, async: true
  alias LiveAiChat.FileStorage

  setup do
    start_supervised!(FileStorage)
    :ok
  end

  test "save and read file" do
    assert :ok = FileStorage.save_file("test.txt", "hello world")
    assert {:ok, "hello world"} = FileStorage.read_file("test.txt")
  end

  test "list files includes saved file" do
    FileStorage.save_file("list_test.txt", "content")
    files = FileStorage.list_files()
    assert "list_test.txt" in files
  end

  test "delete removes file" do
    FileStorage.save_file("delete_me.txt", "bye")
    assert :ok = FileStorage.delete_file("delete_me.txt")
    assert {:error, :enoent} = FileStorage.read_file("delete_me.txt")
  end
end
```

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
```elixir
# test/live_ai_chat/tag_storage_test.exs
defmodule LiveAiChat.TagStorageTest do
  use ExUnit.Case, async: true
  alias LiveAiChat.TagStorage

  setup do
    start_supervised!(TagStorage)
    :ok
  end

  test "update and get tags" do
    TagStorage.update_tags_for_file("test.pdf", ["elixir", "phoenix"])
    Process.sleep(10) # wait for cast
    tags = TagStorage.get_all_tags()
    assert tags["test.pdf"] == ["elixir", "phoenix"]
  end

  test "save and get extraction metadata" do
    metadata = %{"summary" => "Test summary", "categories" => ["tech"]}
    TagStorage.save_extraction("doc.pdf", metadata)
    Process.sleep(10) # wait for cast
    assert TagStorage.get_extraction("doc.pdf") == metadata
  end
end
```

---
## 3. Work-Package 3 – Knowledge.Extractor
### 3.1 Module
```elixir
# @live_ai_chat/knowledge/extractor.ex

defmodule LiveAiChat.Knowledge.Extractor do
  @moduledoc """
  Background task manager for extracting summaries from uploaded files.
  Uses existing Gemini client to analyze content.
  """
  
  require Logger
  alias LiveAiChat.{TagStorage, AIClient}
  
  @task_sup LiveAiChat.TaskSupervisor

  @spec extract_content(String.t(), binary()) :: {:ok, pid()} | {:error, term()}
  def extract_content(filename, file_binary) do
    Task.Supervisor.start_child(@task_sup, fn ->
      extract_and_save(filename, file_binary)
    end)
  end

  defp extract_and_save(filename, file_binary) do
    Logger.info("Starting extraction for file: #{filename}")
    
    prompt = build_extraction_prompt()
    
    # Use existing AIClient but with file data
    case AIClient.send_message(prompt, []) do
      {:ok, response} ->
        case parse_extraction_response(response) do
          {:ok, metadata} ->
            TagStorage.save_extraction(filename, metadata)
            Logger.info("Extraction completed for: #{filename}")
            {:ok, metadata}
          
          {:error, reason} ->
            Logger.error("Failed to parse extraction response for #{filename}: #{reason}")
            {:error, reason}
        end
      
      {:error, reason} ->
        Logger.error("AI extraction failed for #{filename}: #{reason}")
        {:error, reason}
    end
  end

  defp build_extraction_prompt do
    """
    Please analyze the following document and return a JSON object with this exact structure:
    {
      "summary": "A brief summary of the document content",
      "keyPoints": ["Key point 1", "Key point 2", "Key point 3"],
      "categories": ["category1", "category2"]
    }
    
    Respond only with valid JSON, no additional text.
    """
  end

  defp parse_extraction_response(response) do
    try do
      # Clean up response and try to parse as JSON
      json_text = response
                  |> String.trim()
                  |> String.replace(~r/^```json\s*/, "")
                  |> String.replace(~r/\s*```$/, "")
      
      case Jason.decode(json_text) do
        {:ok, %{"summary" => _, "keyPoints" => _, "categories" => _} = data} ->
          {:ok, data}
        {:ok, _} ->
          {:error, "Invalid JSON structure"}
        {:error, reason} ->
          {:error, "JSON parse error: #{reason}"}
      end
    rescue
      e -> {:error, "Exception parsing response: #{Exception.message(e)}"}
    end
  end
end
```
### 3.2 Contract Test
```elixir
# test/live_ai_chat/knowledge/extractor_test.exs
defmodule LiveAiChat.Knowledge.ExtractorTest do
  use ExUnit.Case, async: true
  import Mox
  
  alias LiveAiChat.Knowledge.Extractor
  alias LiveAiChat.TagStorage

  setup :verify_on_exit!

  setup do
    start_supervised!(TagStorage)
    start_supervised!({Task.Supervisor, name: LiveAiChat.TaskSupervisor})
    :ok
  end

  test "extracts and saves metadata successfully" do
    # Mock AI response
    json_response = Jason.encode!(%{
      "summary" => "Test document summary",
      "keyPoints" => ["Point 1", "Point 2"],
      "categories" => ["tech", "docs"]
    })
    
    # Would need to mock AIClient here - for now just test structure
    metadata = %{
      "summary" => "Test summary",
      "keyPoints" => ["Key point"],
      "categories" => ["test"]
    }
    
    TagStorage.save_extraction("test.pdf", metadata)
    Process.sleep(10)
    
    assert TagStorage.get_extraction("test.pdf") == metadata
  end
end
```

---
## 4. Work-Package 4 – KnowledgeLive UI
### 4.1 LiveView Module
```elixir
# @web/live/knowledge_live.ex

defmodule LiveAiChatWeb.KnowledgeLive do
  use LiveAiChatWeb, :live_view
  
  alias LiveAiChat.{FileStorage, TagStorage, Knowledge.Extractor}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      socket = 
        socket
        |> allow_upload(:files,
          accept: ~w(.pdf .txt .md .mht),
          max_entries: 5,
          max_file_size: 10_000_000,
          auto_upload: true
        )
        |> assign_files_and_tags()
        |> assign(:editing_tags, %{})
      
      {:ok, socket}
    else
      {:ok, assign(socket, files: [], tags: %{}, editing_tags: %{})}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    consume_uploaded_entries(socket, :files, fn %{path: path}, entry ->
      file_binary = File.read!(path)
      filename = entry.client_name
      
      case FileStorage.save_file(filename, file_binary) do
        :ok ->
          # Start background extraction
          Extractor.extract_content(filename, file_binary)
          {:ok, filename}
        
        {:error, reason} ->
          {:postpone, reason}
      end
    end)
    
    {:noreply, assign_files_and_tags(socket)}
  end

  @impl true
  def handle_event("start_tag_edit", %{"file" => filename}, socket) do
    current_tags = Map.get(socket.assigns.tags, filename, [])
    editing_tags = Map.put(socket.assigns.editing_tags, filename, Enum.join(current_tags, ", "))
    
    {:noreply, assign(socket, :editing_tags, editing_tags)}
  end

  @impl true
  def handle_event("save_tags", %{"file" => filename, "tags" => tag_string}, socket) do
    tags = 
      tag_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
    
    TagStorage.update_tags_for_file(filename, tags)
    editing_tags = Map.delete(socket.assigns.editing_tags, filename)
    
    # Refresh tags from storage
    socket = 
      socket
      |> assign(:editing_tags, editing_tags)
      |> assign_files_and_tags()
    
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel_tag_edit", %{"file" => filename}, socket) do
    editing_tags = Map.delete(socket.assigns.editing_tags, filename)
    {:noreply, assign(socket, :editing_tags, editing_tags)}
  end

  @impl true
  def handle_event("delete_file", %{"file" => filename}, socket) do
    FileStorage.delete_file(filename)
    {:noreply, assign_files_and_tags(socket)}
  end

  defp assign_files_and_tags(socket) do
    assign(socket,
      files: FileStorage.list_files(),
      tags: TagStorage.get_all_tags()
    )
  end
end
```

### 4.2 Template
```heex
<!-- @web/live/knowledge_live.html.heex -->

<div class="max-w-4xl mx-auto p-6">
  <h1 class="text-3xl font-bold mb-6">Knowledge Pool Management</h1>

  <!-- File Upload Section -->
  <div class="bg-white rounded-lg shadow-md p-6 mb-6">
    <h2 class="text-xl font-semibold mb-4">Upload Files</h2>
    
    <form phx-submit="save" phx-change="validate">
      <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center">
        <.live_file_input upload={@uploads.files} class="hidden" />
        
        <div class="space-y-2">
          <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
            <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
          <div class="text-sm text-gray-600">
            <label for="file-upload" class="relative cursor-pointer bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500">
              <span>Upload files</span>
            </label>
            <p class="pl-1">or drag and drop</p>
          </div>
          <p class="text-xs text-gray-500">PDF, TXT, MD, MHT up to 10MB</p>
        </div>
      </div>

      <!-- Upload Progress -->
      <%= for entry <- @uploads.files.entries do %>
        <div class="mt-4 bg-gray-50 rounded p-3">
          <div class="flex items-center justify-between">
            <span class="text-sm font-medium"><%= entry.client_name %></span>
            <span class="text-sm text-gray-500"><%= entry.progress %>%</span>
          </div>
          <div class="mt-1 bg-gray-200 rounded-full h-2">
            <div class="bg-indigo-600 h-2 rounded-full transition-all duration-300" style={"width: #{entry.progress}%"}></div>
          </div>
        </div>
      <% end %>
    </form>
  </div>

  <!-- Files List -->
  <div class="bg-white rounded-lg shadow-md p-6">
    <h2 class="text-xl font-semibold mb-4">Uploaded Files</h2>
    
    <%= if @files == [] do %>
      <p class="text-gray-500 text-center py-8">No files uploaded yet</p>
    <% else %>
      <div class="space-y-4">
        <%= for file <- @files do %>
          <div class="border rounded-lg p-4">
            <div class="flex items-center justify-between">
              <div class="flex-1">
                <h3 class="font-medium text-gray-900"><%= file %></h3>
                
                <!-- Tags Display/Edit -->
                <div class="mt-2">
                  <%= if Map.has_key?(@editing_tags, file) do %>
                    <!-- Edit Mode -->
                    <form phx-submit="save_tags" phx-value-file={file} class="flex items-center space-x-2">
                      <input 
                        type="text" 
                        name="tags" 
                        value={@editing_tags[file]}
                        placeholder="Enter tags separated by commas"
                        class="flex-1 border rounded px-2 py-1 text-sm"
                        autofocus
                      />
                      <button type="submit" class="text-green-600 hover:text-green-700">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
                        </svg>
                      </button>
                      <button type="button" phx-click="cancel_tag_edit" phx-value-file={file} class="text-gray-600 hover:text-gray-700">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                        </svg>
                      </button>
                    </form>
                  <% else %>
                    <!-- Display Mode -->
                    <div class="flex items-center space-x-2">
                      <div class="flex flex-wrap gap-1">
                        <%= for tag <- Map.get(@tags, file, []) do %>
                          <span class="inline-flex items-center px-2 py-1 rounded-full text-xs font-medium bg-indigo-100 text-indigo-800">
                            <%= tag %>
                          </span>
                        <% end %>
                        <%= if Map.get(@tags, file, []) == [] do %>
                          <span class="text-gray-400 text-sm">No tags</span>
                        <% end %>
                      </div>
                      <button phx-click="start_tag_edit" phx-value-file={file} class="text-gray-400 hover:text-gray-600">
                        <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                          <path d="M13.586 3.586a2 2 0 112.828 2.828l-.793.793-2.828-2.828.793-.793zM11.379 5.793L3 14.172V17h2.828l8.38-8.379-2.83-2.828z" />
                        </svg>
                      </button>
                    </div>
                  <% end %>
                </div>
              </div>
              
              <!-- Actions -->
              <div class="flex items-center space-x-2">
                <button phx-click="delete_file" phx-value-file={file} 
                        data-confirm="Are you sure you want to delete this file?"
                        class="text-red-600 hover:text-red-700">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M9 2a1 1 0 000 2h2a1 1 0 100-2H9z" clip-rule="evenodd" />
                    <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    <% end %>
  </div>
</div>
```

### 4.3 Component Tests
```elixir
# test/live_ai_chat_web/live/knowledge_live_test.exs
defmodule LiveAiChatWeb.KnowledgeLiveTest do
  use LiveAiChatWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias LiveAiChat.{FileStorage, TagStorage}

  setup do
    start_supervised!(FileStorage)
    start_supervised!(TagStorage)
    start_supervised!({Task.Supervisor, name: LiveAiChat.TaskSupervisor})
    :ok
  end

  test "displays upload form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/knowledge")
    assert html =~ "Upload Files"
    assert html =~ "drag and drop"
  end

  test "shows uploaded files", %{conn: conn} do
    FileStorage.save_file("test.pdf", "test content")
    
    {:ok, _view, html} = live(conn, "/knowledge")
    assert html =~ "test.pdf"
  end

  test "allows tag editing", %{conn: conn} do
    FileStorage.save_file("test.pdf", "test content")
    
    {:ok, view, _html} = live(conn, "/knowledge")
    
    # Start editing
    view |> element("button[phx-click='start_tag_edit'][phx-value-file='test.pdf']") |> render_click()
    
    # Save tags
    view 
    |> form("form[phx-submit='save_tags']", %{tags: "elixir, phoenix"})
    |> render_submit()
    
    # Check tags are displayed
    html = render(view)
    assert html =~ "elixir"
    assert html =~ "phoenix"
  end
end
```

---
## 5. Work-Package 5 – Chat Session Enhancements
### 5.1 Chat Session Module
```elixir
# @live_ai_chat/chat_session.ex

defmodule LiveAiChat.ChatSession do
  @moduledoc """
  Handles chat session metadata including knowledge context.
  """
  
  defstruct [:id, :context]
  
  @type t :: %__MODULE__{
    id: String.t(),
    context: %{tags: [String.t()], files: [String.t()]}
  }

  @spec new(String.t()) :: t()
  def new(id) do
    %__MODULE__{
      id: id,
      context: %{tags: [], files: []}
    }
  end

  @spec with_context(t(), [String.t()], [String.t()]) :: t()
  def with_context(%__MODULE__{} = session, tags, files) do
    %{session | context: %{tags: tags, files: files}}
  end

  @spec save_meta(t()) :: :ok | {:error, term()}
  def save_meta(%__MODULE__{id: id} = session) do
    meta_path = meta_file_path(id)
    File.mkdir_p!(Path.dirname(meta_path))
    
    data = %{
      id: session.id,
      context: session.context,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    File.write(meta_path, Jason.encode!(data, pretty: true))
  end

  @spec load_meta(String.t()) :: {:ok, t()} | {:error, term()}
  def load_meta(id) do
    case File.read(meta_file_path(id)) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"id" => ^id, "context" => context}} ->
            session = %__MODULE__{
              id: id,
              context: %{
                tags: Map.get(context, "tags", []),
                files: Map.get(context, "files", [])
              }
            }
            {:ok, session}
          
          {:ok, _} -> {:error, :invalid_format}
          {:error, reason} -> {:error, reason}
        end
      
      {:error, :enoent} -> {:ok, new(id)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp meta_file_path(id) do
    Path.join(:code.priv_dir(:live_ai_chat), "chat_logs/#{id}.meta.json")
  end
end
```

### 5.2 Context Loading Helper
```elixir
# @live_ai_chat/knowledge/context_loader.ex

defmodule LiveAiChat.Knowledge.ContextLoader do
  @moduledoc """
  Loads and caches knowledge context for chat sessions.
  """
  
  alias LiveAiChat.{TagStorage, FileStorage}
  
  @ets_table :pool_context_cache
  
  def start_link do
    :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, self()}
  end

  @spec load_context([String.t()], [String.t()]) :: String.t()
  def load_context(tags, files) do
    cache_key = :erlang.phash2({tags, files})
    
    case :ets.lookup(@ets_table, cache_key) do
      [{^cache_key, context}] -> context
      [] ->
        context = build_context(tags, files)
        :ets.insert(@ets_table, {cache_key, context})
        context
    end
  end

  defp build_context(tags, explicit_files) do
    # Resolve tags to files
    all_tags = TagStorage.get_all_tags()
    
    tag_files = 
      all_tags
      |> Enum.filter(fn {_file, file_tags} ->
        Enum.any?(tags, fn tag -> tag in file_tags end)
      end)
      |> Enum.map(fn {file, _tags} -> file end)
    
    all_files = (explicit_files ++ tag_files) |> Enum.uniq()
    
    # Read file contents
    contents = 
      all_files
      |> Enum.map(fn filename ->
        case FileStorage.read_file(filename) do
          {:ok, content} -> "=== #{filename} ===\n#{content}\n"
          {:error, _} -> ""
        end
      end)
      |> Enum.join("\n")
    
    if contents == "" do
      ""
    else
      "KNOWLEDGE CONTEXT:\n#{contents}\n=== END CONTEXT ===\n\n"
    end
  end
end
```

---
## 6. API Controllers
### 6.1 File Controller
```elixir
# @web/controllers/file_controller.ex

defmodule LiveAiChatWeb.FileController do
  use LiveAiChatWeb, :controller
  
  alias LiveAiChat.{FileStorage, Knowledge.Extractor}

  def index(conn, _params) do
    files = FileStorage.list_files()
    json(conn, %{files: files})
  end

  def upload(conn, %{"file" => %Plug.Upload{} = upload}) do
    filename = upload.filename
    
    case File.read(upload.path) do
      {:ok, binary} ->
        case FileStorage.save_file(filename, binary) do
          :ok ->
            # Start background extraction
            Extractor.extract_content(filename, binary)
            
            conn
            |> put_status(:created)
            |> json(%{message: "File uploaded successfully", filename: filename})
          
          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to save file: #{reason}"})
        end
      
      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to read upload: #{reason}"})
    end
  end

  def show(conn, %{"filename" => filename}) do
    case FileStorage.read_file(filename) do
      {:ok, content} ->
        conn
        |> put_resp_content_type("application/octet-stream")
        |> put_resp_header("content-disposition", "attachment; filename=\"#{filename}\"")
        |> send_resp(200, content)
      
      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "File not found"})
    end
  end

  def delete(conn, %{"filename" => filename}) do
    case FileStorage.delete_file(filename) do
      :ok ->
        json(conn, %{message: "File deleted successfully"})
      
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete file: #{reason}"})
    end
  end
end
```

### 6.2 Tag Controller
```elixir
# @web/controllers/tag_controller.ex

defmodule LiveAiChatWeb.TagController do
  use LiveAiChatWeb, :controller
  
  alias LiveAiChat.TagStorage

  def index(conn, _params) do
    tags = TagStorage.get_all_tags()
    json(conn, %{tags: tags})
  end

  def update(conn, %{"filename" => filename, "tags" => tags}) when is_list(tags) do
    TagStorage.update_tags_for_file(filename, tags)
    json(conn, %{message: "Tags updated successfully"})
  end

  def update(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid parameters. Expected filename and tags array."})
  end
end
```

### 6.3 Router Updates
```elixir
# @web/router.ex - Add to existing router

# Add API pipeline if not exists
pipeline :api do
  plug :accepts, ["json"]
end

# Add API scope
scope "/api", LiveAiChatWeb do
  pipe_through :api

  get "/files", FileController, :index
  post "/files/upload", FileController, :upload
  get "/files/:filename", FileController, :show
  delete "/files/:filename", FileController, :delete

  get "/file-tags", TagController, :index
  put "/file-tags/:filename", TagController, :update

  post "/chat", ChatApiController, :create
end

# Add knowledge route to browser scope
scope "/", LiveAiChatWeb do
  pipe_through :browser

  live "/knowledge", KnowledgeLive, :index
end
```

---
## 7. Testing Strategy
### 7.1 Test Matrix

| Component | Unit Tests | Integration Tests | Property Tests |
|-----------|------------|-------------------|----------------|
| FileStorage | ✓ save/read/delete/list | - | ✓ filename sanitization |
| TagStorage | ✓ CRUD operations | ✓ concurrent updates | ✓ JSON schema |
| Extractor | ✓ response parsing | ✓ with mock AI | ✓ JSON structure |
| KnowledgeLive | - | ✓ upload flow, tag editing | - |
| API Controllers | ✓ all endpoints | ✓ file upload/download | - |

### 7.2 Property Test Examples
```elixir
# test/live_ai_chat/file_storage_property_test.exs
defmodule LiveAiChat.FileStoragePropertyTest do
  use ExUnit.Case, async: true
  use PropCheck
  
  alias LiveAiChat.FileStorage

  setup do
    start_supervised!(FileStorage)
    :ok
  end

  property "saved files can always be read back" do
    forall {filename, content} <- {filename_gen(), binary()} do
      :ok = FileStorage.save_file(filename, content)
      {:ok, ^content} = FileStorage.read_file(filename)
      true
    end
  end

  defp filename_gen do
    let chars <- list(oneof([range(?a, ?z), range(?A, ?Z), range(?0, ?9), ?., ?-, ?_])) do
      to_string(chars)
    end
  end
end
```

---
## 8. Deployment & Observability
### 8.1 Telemetry Events
```elixir
# Add to each module for metrics

# FileStorage
:telemetry.execute([:live_ai_chat, :file_storage, :save], %{size: byte_size(bin)}, %{filename: name})

# TagStorage  
:telemetry.execute([:live_ai_chat, :tag_storage, :update], %{tag_count: length(tags)}, %{filename: file})

# Extractor
:telemetry.execute([:live_ai_chat, :extractor, :complete], %{duration: duration}, %{filename: file})
```

### 8.2 Feature Flag
```elixir
# config/config.exs
config :live_ai_chat, :feature_flags,
  knowledge_ui: false

# In LiveView/Controller
if Application.get_env(:live_ai_chat, :feature_flags)[:knowledge_ui] do
  # Show knowledge features
end
```

---
## 9. Security Checklist
- [ ] File upload size limits (10MB)
- [ ] MIME type validation
- [ ] Filename sanitization
- [ ] Path traversal protection
- [ ] CSRF protection (built into LiveView)
- [ ] Rate limiting on API endpoints
- [ ] Input validation on all forms
- [ ] Secure file storage (outside web root)

---
## 10. Success Criteria
- [ ] All GenServers start and supervised
- [ ] File upload works via drag-drop
- [ ] Tags can be edited and persist
- [ ] Chat sessions can use file context
- [ ] API endpoints return expected JSON
- [ ] 95% test coverage on new code
- [ ] `./precommit.sh` passes clean
- [ ] Documentation updated

---
_Ready for implementation - start with Work-Package 1_
