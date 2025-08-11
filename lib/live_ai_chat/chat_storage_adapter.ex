defmodule LiveAiChat.ChatStorageAdapter do
  @moduledoc """
  A compatibility adapter that provides the old CsvStorage API while delegating
  to the new JSON-based ChatStorage system. This maintains backward compatibility
  for existing code that expects the CSV-based interface.

  This module acts as a bridge during the transition from CSV to JSON storage,
  ensuring that all file I/O is handled in a separate, supervised process.
  """
  use GenServer

  alias LiveAiChat.ChatStorage

  defp chat_logs_dir,
    do: Application.get_env(:live_ai_chat, :chat_logs_dir, "priv/data/chat_logs")

  # --- Client API ---

  @doc "Starts the CsvStorage GenServer."
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Returns a list of all chat IDs."
  def list_chats() do
    try do
      # Use the new ChatStorage system
      case ChatStorage.list_chats() do
        chats when is_list(chats) ->
          # Extract just the chat IDs for backward compatibility
          Enum.map(chats, fn {chat_id, _metadata} -> chat_id end)

        _ ->
          # Fallback to legacy CSV storage if needed
          GenServer.call(__MODULE__, :list_chats)
      end
    rescue
      _ ->
        # Fallback to legacy CSV storage if ChatStorage fails
        GenServer.call(__MODULE__, :list_chats)
    end
  end

  @doc "Reads all messages for a given chat ID."
  def read_chat(chat_id) do
    # Use the new ChatStorage system
    case ChatStorage.read_chat_messages(chat_id) do
      messages when is_list(messages) ->
        # Convert from new format to old format for backward compatibility
        Enum.map(messages, fn
          {:ok, message} -> {:ok, %{role: message["role"], content: message["content"]}}
          error -> error
        end)

      _ ->
        # Fallback to legacy CSV storage if needed
        GenServer.call(__MODULE__, {:read_chat, chat_id})
    end
  end

  @doc "Appends a message to a chat's message file."
  def append_message(chat_id, message) do
    # Convert from old format to new format and use ChatStorage
    new_message = %{
      "role" => to_string(message.role),
      "content" => to_string(message.content)
    }

    ChatStorage.append_message(chat_id, new_message)
  end

  @doc "Creates a new empty chat with the given ID."
  def create_chat(chat_id) do
    # Use the new ChatStorage system
    ChatStorage.create_chat(chat_id)
  end

  @doc "Renames a chat from old_chat_id to new_chat_id."
  def rename_chat(old_chat_id, new_chat_id) do
    # Update the chat name in metadata using ChatStorage
    ChatStorage.update_chat_metadata(old_chat_id, %{"name" => new_chat_id})
  end

  @doc "Deletes a chat by moving it to an archived folder."
  def delete_chat(chat_id) do
    # Use the new ChatStorage system
    ChatStorage.delete_chat(chat_id)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(:ok) do
    # Ensure the directory for chat logs exists.
    File.mkdir_p!(chat_logs_dir())
    {:ok, %{}}
  end

  @impl true
  def handle_call(:list_chats, _from, state) do
    chat_files =
      chat_logs_dir()
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".csv"))
      |> Enum.map(&Path.basename(&1, ".csv"))

    {:reply, chat_files, state}
  end

  def handle_call({:read_chat, chat_id}, _from, state) do
    path = Path.join(chat_logs_dir(), "#{chat_id}.csv")

    messages =
      if File.exists?(path) do
        path
        |> File.stream!()
        |> CSV.decode(headers: ~w(role content)a)
        |> Enum.to_list()
      else
        []
      end

    {:reply, messages, state}
  end

  @impl true
  def handle_call({:append_message, chat_id, message}, _from, state) do
    path = Path.join(chat_logs_dir(), "#{chat_id}.csv")
    row = [message.role, message.content]
    # Encode the row to a CSV string
    csv_string = CSV.encode([row]) |> Enum.join()
    # Append the string to the file
    File.write!(path, csv_string, [:append])
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:create_chat, chat_id}, _from, state) do
    path = Path.join(chat_logs_dir(), "#{chat_id}.csv")

    if File.exists?(path) do
      {:reply, {:error, :chat_already_exists}, state}
    else
      # Create an empty CSV file
      File.write!(path, "")
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:rename_chat, old_chat_id, new_chat_id}, _from, state) do
    old_path = Path.join(chat_logs_dir(), "#{old_chat_id}.csv")
    new_path = Path.join(chat_logs_dir(), "#{new_chat_id}.csv")

    cond do
      not File.exists?(old_path) ->
        {:reply, {:error, :chat_not_found}, state}

      File.exists?(new_path) ->
        {:reply, {:error, :chat_already_exists}, state}

      true ->
        case File.rename(old_path, new_path) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:delete_chat, chat_id}, _from, state) do
    path = Path.join(chat_logs_dir(), "#{chat_id}.csv")

    if not File.exists?(path) do
      {:reply, {:error, :chat_not_found}, state}
    else
      # Create archived directory if it doesn't exist
      archived_dir = Path.join(chat_logs_dir(), "archived")
      File.mkdir_p!(archived_dir)

      # Move file to archived directory
      archived_path = Path.join(archived_dir, "#{chat_id}.csv")

      case File.rename(path, archived_path) do
        :ok -> {:reply, :ok, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end
end
