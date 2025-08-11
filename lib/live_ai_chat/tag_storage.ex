defmodule LiveAiChat.TagStorage do
  @moduledoc """
  GenServer managing JSON-based metadata for file tags and AI-extracted content.
  Handles concurrent access to tag files and extracted metadata safely.
  """

  use GenServer
  require Logger

  @default_data_dir Path.join(:code.priv_dir(:live_ai_chat), "data")
  @default_upload_dir Path.join(:code.priv_dir(:live_ai_chat), "uploads")

  # -- Public API -----------------------------------------------------------

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @spec get_all_tags() :: map()
  def get_all_tags(), do: GenServer.call(__MODULE__, :all_tags)

  @spec update_tags_for_file(String.t(), [String.t()]) :: :ok
  def update_tags_for_file(filename, tag_list),
    do: GenServer.call(__MODULE__, {:update_tags, filename, tag_list})

  @spec get_extraction(String.t()) :: map()
  def get_extraction(filename), do: GenServer.call(__MODULE__, {:get_meta, filename})

  @spec save_extraction(String.t(), map()) :: :ok
  def save_extraction(filename, data),
    do: GenServer.cast(__MODULE__, {:save_meta, filename, data})

  @spec get_files_by_tags([String.t()]) :: [String.t()]
  def get_files_by_tags(tag_list), do: GenServer.call(__MODULE__, {:files_by_tags, tag_list})

  # -- GenServer callbacks --------------------------------------------------

  @impl true
  def init(_) do
    ensure_dirs_exist()

    state = %{
      # We still keep the in-memory map for fast look-ups but it will be lazily
      # reloaded from disk if the underlying JSON file changes path due to a
      # test overriding the data_dir configuration.
      tags: load_json(tags_json_path())
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:all_tags, _from, state) do
    current_tags = load_json(tags_json_path())
    {:reply, current_tags, %{state | tags: current_tags}}
  end

  @impl true
  def handle_call({:get_meta, filename}, _from, state) do
    meta_data = read_meta(filename)
    {:reply, meta_data, state}
  end

  @impl true
  def handle_call({:files_by_tags, tag_list}, _from, state) do
    tags = load_json(tags_json_path())

    matching_files =
      tags
      |> Enum.filter(fn {_filename, file_tags} ->
        Enum.any?(tag_list, fn requested_tag ->
          Enum.any?(file_tags, fn file_tag ->
            String.downcase(requested_tag) == String.downcase(file_tag)
          end)
        end)
      end)
      |> Enum.map(fn {filename, _tags} -> filename end)

    {:reply, matching_files, %{state | tags: tags}}
  end

  @impl true
  def handle_call({:update_tags, filename, tag_list}, _from, state) do
    current_tags = load_json(tags_json_path())
    new_tags = Map.put(current_tags, filename, tag_list)

    case write_json(tags_json_path(), new_tags) do
      :ok ->
        {:reply, :ok, %{state | tags: new_tags}}

      {:error, reason} ->
        Logger.error("Failed to save tags: #{inspect(reason)}")
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_cast({:save_meta, filename, data}, state) do
    meta_path = meta_path(filename)

    case write_json(meta_path, data) do
      :ok ->
        Logger.debug("Saved metadata for #{filename}")
        broadcast_extraction_done(filename)

      {:error, reason} ->
        Logger.error("Failed to save metadata for #{filename}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # -- Helpers --------------------------------------------------------------

  defp load_json(path) do
    case File.read(path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, data} -> data
          {:error, _} -> %{}
        end

      _ ->
        %{}
    end
  end

  defp write_json(path, data) do
    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        File.write(path, json)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp meta_path(filename) do
    Path.join(current_upload_dir(), "#{filename}.meta.json")
  end

  defp read_meta(filename) do
    meta_path = meta_path(filename)

    case File.read(meta_path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, data} -> data
          {:error, _} -> %{}
        end

      _ ->
        %{}
    end
  end

  defp broadcast_extraction_done(filename) do
    case Phoenix.PubSub.broadcast(LiveAiChat.PubSub, "knowledge", {:extraction_done, filename}) do
      :ok ->
        :ok

      :error ->
        Logger.warning(
          "Failed to broadcast extraction_done for #{filename}: PubSub may not be ready or no subscribers"
        )

        :error
    end
  end

  # -- Dynamic path helpers --------------------------------------------------

  defp current_data_dir do
    Application.get_env(:live_ai_chat, :data_dir, @default_data_dir)
  end

  defp current_upload_dir do
    Application.get_env(:live_ai_chat, :upload_dir, @default_upload_dir)
  end

  defp tags_json_path do
    Path.join(current_data_dir(), "file-tags.json")
  end

  defp ensure_dirs_exist do
    File.mkdir_p!(current_data_dir())
    File.mkdir_p!(current_upload_dir())
  end
end
