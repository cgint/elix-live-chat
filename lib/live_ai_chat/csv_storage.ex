defmodule LiveAiChat.CsvStorage do
  @moduledoc """
  A GenServer responsible for all file-based operations related to chat logs.
  It ensures that all file I/O is handled in a separate, supervised process,
  preventing the main application or LiveViews from being blocked.
  """
  use GenServer

  defp chat_logs_dir, do: Application.get_env(:live_ai_chat, :chat_logs_dir, "priv/chat_logs")

  # --- Client API ---

  @doc "Starts the CsvStorage GenServer."
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Returns a list of all chat IDs."
  def list_chats() do
    GenServer.call(__MODULE__, :list_chats)
  end

  @doc "Reads all messages for a given chat ID."
  def read_chat(chat_id) do
    GenServer.call(__MODULE__, {:read_chat, chat_id})
  end

  @doc "Appends a message to a chat's CSV file."
  def append_message(chat_id, message) do
    GenServer.call(__MODULE__, {:append_message, chat_id, message})
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
end
