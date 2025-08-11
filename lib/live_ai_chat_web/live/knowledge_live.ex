defmodule LiveAiChatWeb.KnowledgeLive do
  @moduledoc """
  LiveView for managing knowledge pool files and tags.
  Handles file uploads, tagging, and metadata management.
  """

  use LiveAiChatWeb, :live_view

  alias LiveAiChat.{FileStorage, TagStorage, Knowledge.Extractor}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> assign(:selected_file, nil)
      |> assign(:file_metadata, %{})
      |> assign(:new_tags, "")
             |> allow_upload(:knowledge_files,
        accept: ~w(.pdf .txt .md .markdown),
        max_entries: 5,
        max_file_size: 10_000_000
      )

    if connected?(socket) do
      {:ok,
       socket
       |> assign(:files, FileStorage.list_files())
       |> assign(:tags, TagStorage.get_all_tags())}
    else
      {:ok,
       socket
       |> assign(:files, [])
       |> assign(:tags, %{})}
    end
  end

  @impl true
  def handle_event("validate", _params, socket) do
    # Required for upload validation
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :knowledge_files, fn %{path: path}, entry ->
        # Read the file content
        binary_content = File.read!(path)

        # Use sanitized filename for storage
        safe_filename = FileStorage.safe_filename(entry.client_name)

        # Save the file using FileStorage GenServer
        case FileStorage.save_file(safe_filename, binary_content) do
          :ok ->
            # Enqueue for background content extraction
            Extractor.enqueue(safe_filename, binary_content)
            {:ok, safe_filename}
          {:error, reason} ->
            {:postpone, {:error, reason}}
        end
      end)

    case uploaded_files do
      [] ->
        {:noreply, put_flash(socket, :error, "No files were uploaded")}
      files when is_list(files) ->
        {:noreply,
         socket
         |> update(:uploaded_files, &(&1 ++ files))
         |> assign_files_and_tags()
         |> put_flash(:info, "#{length(files)} file(s) uploaded successfully")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Upload failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :knowledge_files, ref)}
  end

  @impl true
  def handle_event("select-file", %{"filename" => filename}, socket) do
    metadata = TagStorage.get_extraction(filename)

    {:noreply,
     socket
     |> assign(:selected_file, filename)
     |> assign(:file_metadata, metadata)
     |> assign(:new_tags, get_tags_string(filename, socket.assigns.tags))}
  end

  @impl true
  def handle_event("update-tags", %{"filename" => filename, "tags" => tags_string}, socket) do
    # Parse the tags from the comma-separated string
    tag_list =
      tags_string
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    # Update tags in storage
    TagStorage.update_tags_for_file(filename, tag_list)

    {:noreply,
     socket
     |> assign_files_and_tags()
     |> assign(:new_tags, tags_string)
     |> put_flash(:info, "Tags updated for #{filename}")}
  end

  @impl true
  def handle_event("delete-file", %{"filename" => filename}, socket) do
    case FileStorage.delete_file(filename) do
      :ok ->
        # Also clean up tags and metadata
        TagStorage.update_tags_for_file(filename, [])

        {:noreply,
         socket
         |> assign_files_and_tags()
         |> assign(:selected_file, nil)
         |> assign(:file_metadata, %{})
         |> assign(:new_tags, "")
         |> put_flash(:info, "File #{filename} deleted")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete file: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("search-by-tags", %{"search_tags" => search_tags}, socket) do
    if search_tags == "" do
      # Show all files if search is empty
      {:noreply, assign(socket, :files, FileStorage.list_files())}
    else
      # Parse search tags and find matching files
      tag_list =
        search_tags
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))

      matching_files = TagStorage.get_files_by_tags(tag_list)

      {:noreply, assign(socket, :files, matching_files)}
    end
  end

  # Helper functions

  defp assign_files_and_tags(socket) do
    socket
    |> assign(:files, FileStorage.list_files())
    |> assign(:tags, TagStorage.get_all_tags())
  end

  defp get_tags_string(filename, tags_map) do
    case Map.get(tags_map, filename) do
      nil -> ""
      tag_list when is_list(tag_list) -> Enum.join(tag_list, ", ")
      _ -> ""
    end
  end

  defp error_to_string(:too_large), do: "File too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Too many files selected (max 5)"
  defp error_to_string(:not_accepted), do: "File type not accepted (.pdf, .txt, .md only)"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"

  defp file_icon(filename) do
    case Path.extname(filename) |> String.downcase() do
      ".pdf" -> "hero-document-text"
      ".md" -> "hero-document"
      ".markdown" -> "hero-document"
      ".txt" -> "hero-document-text"
      _ -> "hero-document"
    end
  end
end
