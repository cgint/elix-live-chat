defmodule LiveAiChat.ChatStorage do
  @moduledoc """
  A GenServer responsible for chat storage using JSON metadata files and separate message files.
  Each chat has:
  - A metadata.json file containing chat name, creation date, and other metadata
  - A messages.jsonl file containing the chat history (JSON Lines format)
  """
  use GenServer

  defp chats_dir,
    do: Application.get_env(:live_ai_chat, :chats_dir, "priv/data/chats")

  # --- Client API ---

  @doc "Starts the ChatStorage GenServer."
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Returns a list of all chat IDs with their metadata."
  def list_chats() do
    GenServer.call(__MODULE__, :list_chats)
  end

  @doc "Gets metadata for a specific chat."
  def get_chat_metadata(chat_id) do
    GenServer.call(__MODULE__, {:get_chat_metadata, chat_id})
  end

  @doc "Reads all messages for a given chat ID."
  def read_chat_messages(chat_id) do
    GenServer.call(__MODULE__, {:read_chat_messages, chat_id})
  end

  @doc "Appends a message to a chat's message file."
  def append_message(chat_id, message) do
    GenServer.call(__MODULE__, {:append_message, chat_id, message})
  end

  @doc "Creates a new chat with the given ID and optional name."
  def create_chat(chat_id, name \\ nil) do
    GenServer.call(__MODULE__, {:create_chat, chat_id, name})
  end

  @doc "Updates chat metadata (like name)."
  def update_chat_metadata(chat_id, metadata) do
    GenServer.call(__MODULE__, {:update_chat_metadata, chat_id, metadata})
  end

  @doc "Deletes a chat by moving it to an archived folder."
  def delete_chat(chat_id) do
    GenServer.call(__MODULE__, {:delete_chat, chat_id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(:ok) do
    # Ensure the directory for chats exists.
    File.mkdir_p!(chats_dir())
    {:ok, %{}}
  end

  @impl true
  def handle_call(:list_chats, _from, state) do
    chat_dirs =
      chats_dir()
      |> File.ls!()
      |> Enum.filter(fn item ->
        path = Path.join(chats_dir(), item)
        File.dir?(path) and File.exists?(Path.join(path, "metadata.json"))
      end)

    chats_with_metadata =
      chat_dirs
      |> Enum.map(fn chat_id ->
        metadata = read_metadata_file(chat_id)
        {chat_id, metadata}
      end)
      |> Enum.sort_by(fn {_id, metadata} -> metadata["created_at"] end, :desc)

    {:reply, chats_with_metadata, state}
  end

  @impl true
  def handle_call({:get_chat_metadata, chat_id}, _from, state) do
    metadata = read_metadata_file(chat_id)
    {:reply, metadata, state}
  end

  @impl true
  def handle_call({:read_chat_messages, chat_id}, _from, state) do
    messages_path = Path.join([chats_dir(), chat_id, "messages.jsonl"])

    messages =
      if File.exists?(messages_path) do
        messages_path
        |> File.stream!()
        |> Enum.map(fn line ->
          case Jason.decode(String.trim(line)) do
            {:ok, message} -> {:ok, message}
            {:error, _} -> {:error, :invalid_json}
          end
        end)
      else
        []
      end

    {:reply, messages, state}
  end

  @impl true
  def handle_call({:append_message, chat_id, message}, _from, state) do
    if chat_id == nil do
      {:reply, {:error, :invalid_chat_id}, state}
    else
      messages_path = Path.join([chats_dir(), chat_id, "messages.jsonl"])

      # Ensure the chat directory exists
      chat_dir = Path.join(chats_dir(), chat_id)
      File.mkdir_p!(chat_dir)

      # Add timestamp to message if not present
      message_with_timestamp =
        Map.put_new(message, "timestamp", DateTime.utc_now() |> DateTime.to_iso8601())

      # Encode message as JSON and append to file
      json_line = Jason.encode!(message_with_timestamp) <> "\n"
      File.write!(messages_path, json_line, [:append])

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:create_chat, chat_id, name}, _from, state) do
    chat_dir = Path.join(chats_dir(), chat_id)
    metadata_path = Path.join(chat_dir, "metadata.json")

    if File.exists?(metadata_path) do
      {:reply, {:error, :chat_already_exists}, state}
    else
      File.mkdir_p!(chat_dir)

      # Create metadata file
      metadata = %{
        "id" => chat_id,
        "name" => name || generate_default_name(),
        "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      File.write!(metadata_path, Jason.encode!(metadata, pretty: true))

      # Create empty messages file
      messages_path = Path.join(chat_dir, "messages.jsonl")
      File.touch!(messages_path)

      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:update_chat_metadata, chat_id, new_metadata}, _from, state) do
    chat_dir = Path.join(chats_dir(), chat_id)
    metadata_path = Path.join(chat_dir, "metadata.json")

    if File.exists?(metadata_path) do
      current_metadata = read_metadata_file(chat_id)

      updated_metadata =
        current_metadata
        |> Map.merge(new_metadata)
        |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

      File.write!(metadata_path, Jason.encode!(updated_metadata, pretty: true))
      {:reply, :ok, state}
    else
      {:reply, {:error, :chat_not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete_chat, chat_id}, _from, state) do
    chat_dir = Path.join(chats_dir(), chat_id)
    archived_dir = Path.join(chats_dir(), "archived")
    archived_chat_dir = Path.join(archived_dir, "#{chat_id}_#{System.system_time(:second)}")

    cond do
      not File.exists?(chat_dir) ->
        {:reply, {:error, :chat_not_found}, state}

      true ->
        File.mkdir_p!(archived_dir)

        case File.rename(chat_dir, archived_chat_dir) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  # --- Private Helper Functions ---

  defp read_metadata_file(chat_id) do
    metadata_path = Path.join([chats_dir(), chat_id, "metadata.json"])

    if File.exists?(metadata_path) do
      case File.read!(metadata_path) |> Jason.decode() do
        {:ok, metadata} -> metadata
        {:error, _} -> %{}
      end
    else
      %{}
    end
  end

  defp generate_default_name do
    "New Chat"
  end
end
