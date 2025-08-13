defmodule LiveAiChat.FileStorage do
  @moduledoc """
  GenServer guarding access to files under priv/data/uploads/ .
  Performs write/read/delete so callers never touch the FS directly.
  """

  use GenServer
  require Logger

  @default_upload_dir Path.join(:code.priv_dir(:live_ai_chat), "data/uploads")

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

  @spec list_pdf_files() :: [String.t()]
  def list_pdf_files, do: GenServer.call(__MODULE__, :list_pdf)

  @spec list_mht_files() :: [String.t()]
  def list_mht_files, do: GenServer.call(__MODULE__, :list_mht)

  @spec safe_filename(String.t()) :: String.t()
  def safe_filename(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[^\w\.-]/, "_")
  end

  # -- GenServer callbacks --------------------------------------------------

  @impl true
  def init(_) do
    # We no longer store a fixed directory in the GenServer state. Instead, we
    # resolve the directory on-demand for every operation. This allows tests to
    # change the :upload_dir application environment at runtime and ensures the
    # GenServer will pick up the new value without needing a restart.
    ensure_upload_dir_exists()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:save, name, bin}, _from, state) do
    path = Path.join(current_upload_dir(), safe_filename(name))
    reply = File.write(path, bin, [:binary])
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:read, name}, _from, state) do
    path = Path.join(current_upload_dir(), name)
    reply = File.read(path)
    {:reply, reply, state}
  end

  @impl true
  def handle_call({:delete, name}, _from, state) do
    path = Path.join(current_upload_dir(), name)
    reply = File.rm(path)
    {:reply, reply, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    dir = current_upload_dir()

    case File.ls(dir) do
      {:ok, files} ->
        # Filter out directories, only return files
        actual_files =
          Enum.filter(files, fn file ->
            path = Path.join(dir, file)
            File.regular?(path)
          end)

        {:reply, actual_files, state}

      {:error, _} ->
        {:reply, [], state}
    end
  end

  @impl true
  def handle_call(:list_pdf, _from, state) do
    dir = current_upload_dir()

    case File.ls(dir) do
      {:ok, files} ->
        # Filter out directories and non-PDF files
        pdf_files =
          Enum.filter(files, fn file ->
            path = Path.join(dir, file)
            File.regular?(path) and String.ends_with?(String.downcase(file), ".pdf")
          end)

        {:reply, pdf_files, state}

      {:error, _} ->
        {:reply, [], state}
    end
  end

  @impl true
  def handle_call(:list_mht, _from, state) do
    dir = current_upload_dir()

    case File.ls(dir) do
      {:ok, files} ->
        # Filter out directories and non-MHT/MHTML files
        mht_files =
          Enum.filter(files, fn file ->
            path = Path.join(dir, file)
            down = String.downcase(file)

            File.regular?(path) and
              (String.ends_with?(down, ".mht") or String.ends_with?(down, ".mhtml"))
          end)

        {:reply, mht_files, state}

      {:error, _} ->
        {:reply, [], state}
    end
  end

  # -- Helper functions ------------------------------------------------------

  defp current_upload_dir do
    Application.get_env(:live_ai_chat, :upload_dir, @default_upload_dir)
  end

  defp ensure_upload_dir_exists do
    current_upload_dir() |> File.mkdir_p!()
  end
end
