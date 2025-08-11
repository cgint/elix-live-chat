defmodule LiveAiChat.FileStorage do
  @moduledoc """
  GenServer guarding access to files under priv/uploads/ .
  Performs write/read/delete so callers never touch the FS directly.
  """

  use GenServer
  require Logger

  @default_upload_dir Path.join(:code.priv_dir(:live_ai_chat), "uploads")

  # -- Public API -----------------------------------------------------------

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @spec save_file(String.t(), binary()) :: :ok | {:error, term()}
  def save_file(name, bin), do: GenServer.call(__MODULE__, {:save, name, bin})

  @spec read_file(String.t()) :: {:ok, binary()} | {:error, :enoent}
  def read_file(name), do: GenServer.call(__MODULE__, {:read, name})

  @spec delete_file(String.t()) :: :ok | {:error, term()}
  def delete_file(name), do: GenServer.call(__MODULE__, {:delete, name})

  @spec list_files() :: [String.t()]
  def list_files, do: GenServer.call(__MODULE__, :list)

  @spec safe_filename(String.t()) :: String.t()
  def safe_filename(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[^\w\.-]/, "_")
  end

  # -- GenServer callbacks --------------------------------------------------

  @impl true
  def init(_) do
    upload_dir = Application.get_env(:live_ai_chat, :upload_dir, @default_upload_dir)
    File.mkdir_p!(upload_dir)
    {:ok, %{dir: upload_dir}}
  end

  @impl true
  def handle_call({:save, name, bin}, _from, state) do
    path = Path.join(state.dir, safe_filename(name))
    reply = File.write(path, bin, [:binary])
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:read, name}, _from, state) do
    path = Path.join(state.dir, name)
    reply = File.read(path)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) do
    path = Path.join(state.dir, name)
    reply = File.rm(path)
    {:reply, reply, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    case File.ls(state.dir) do
      {:ok, files} ->
        # Filter out directories, only return files
        actual_files =
          Enum.filter(files, fn file ->
            path = Path.join(state.dir, file)
            File.regular?(path)
          end)

        {:reply, actual_files, state}

      {:error, _} ->
        {:reply, [], state}
    end
  end
end
