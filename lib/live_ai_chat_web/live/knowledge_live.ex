defmodule LiveAiChatWeb.KnowledgeLive do
  @moduledoc """
  LiveView for managing knowledge pool files and tags.
  Handles file uploads, tagging, and metadata management.
  """

  use LiveAiChatWeb, :live_view

  alias LiveAiChat.{FileStorage, TagStorage, Knowledge.Extractor}

  @impl true
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(:uploaded_files, [])
      |> assign(:selected_file, nil)
      |> assign(:file_metadata, %{})
      |> assign(:new_tags, "")
      |> assign(:show_modal, false)
      |> assign(:modal_meta, %{})
      |> assign(:current_user, Map.get(session, "user"))
      |> allow_upload(:knowledge_files,
        accept: ~w(.pdf .mht .mhtml),
        max_entries: 50,
        max_file_size: 10_000_000
      )

    if connected?(socket) do
      :ok = Phoenix.PubSub.subscribe(LiveAiChat.PubSub, "knowledge")

      {:ok,
       socket
       |> assign_files_and_tags()
       |> build_file_meta_map()}
    else
      {:ok,
       socket
       |> assign(:files, [])
       |> assign(:tags, %{})
       |> assign(:file_meta_map, %{})}
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

        case determine_upload_kind(safe_filename) do
          :pdf ->
            # Check if metadata already exists for this PDF
            if metadata_exists?(safe_filename) do
              {:ok, {:skipped, safe_filename}}
            else
              case FileStorage.save_file(safe_filename, binary_content) do
                :ok ->
                  # Create immediate metadata for PDF
                  TagStorage.create_immediate_metadata(safe_filename)
                  Extractor.enqueue(safe_filename, binary_content)
                  {:ok, safe_filename}

                {:error, reason} ->
                  {:postpone, {:error, reason}}
              end
            end

          :mht ->
            # Check if metadata already exists for the target PDF
            pdf_filename = mht_to_pdf_filename(safe_filename)
            if metadata_exists?(pdf_filename) do
              {:ok, {:skipped, safe_filename}}
            else
              case FileStorage.save_file(safe_filename, binary_content) do
                :ok ->
                  # Create immediate metadata using target PDF filename
                  TagStorage.create_immediate_metadata(pdf_filename, safe_filename)
                  # Kick off conversion in background
                  start_mht_conversion(safe_filename, binary_content)
                  {:ok, safe_filename}

                {:error, reason} ->
                  {:postpone, {:error, reason}}
              end
            end
        end
      end)

    case uploaded_files do
      [] ->
        {:noreply, put_flash(socket, :error, "No files were uploaded")}

      files when is_list(files) ->
        # Separate skipped files from processed files
        {skipped_files, processed_files} = 
          Enum.reduce(files, {[], []}, fn
            {:skipped, filename}, {skipped, processed} -> {[filename | skipped], processed}
            filename, {skipped, processed} -> {skipped, [filename | processed]}
          end)
        
        # Build flash message
        flash_message = 
          case {length(processed_files), length(skipped_files)} do
            {0, 0} -> "No files processed"
            {processed_count, 0} -> "#{processed_count} file(s) uploaded successfully"
            {0, skipped_count} -> "#{skipped_count} file(s) skipped (already exist)"
            {processed_count, skipped_count} -> 
              "#{processed_count} file(s) uploaded, #{skipped_count} skipped (already exist)"
          end
        
        all_files = processed_files ++ skipped_files
        
        {:noreply,
         socket
         |> update(:uploaded_files, &(&1 ++ all_files))
         |> assign_files_and_tags()
         |> put_flash(:info, flash_message)}
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
  def handle_event("show-details", %{"filename" => filename}, socket) do
    meta = Map.get(socket.assigns.file_meta_map, filename, %{})

    {:noreply,
     socket
     |> assign(:show_modal, true)
     |> assign(:modal_meta, %{filename: filename, meta: meta})}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, assign(socket, :show_modal, false)}
  end

  @impl true
  def handle_event("stop-propagation", _params, socket) do
    # This event handler prevents click events from propagating to parent elements
    {:noreply, socket}
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
     |> assign(:show_modal, false)
     |> put_flash(:info, "Tags updated for #{filename}")}
  end

  @impl true
  def handle_event("delete-file", %{"filename" => filename}, socket) do
    # Get metadata to check for related files
    metadata = TagStorage.get_extraction(filename)
    mht_filename = Map.get(metadata, "filename_mht")
    pdf_filename = Map.get(metadata, "filename")

    # Collect all files to delete
    files_to_delete = []
    files_to_delete = if mht_filename, do: [mht_filename | files_to_delete], else: files_to_delete
    files_to_delete = if pdf_filename, do: [pdf_filename | files_to_delete], else: files_to_delete

    # Also try to delete the display filename if it's different
    files_to_delete = if filename not in files_to_delete, do: [filename | files_to_delete], else: files_to_delete

    # Attempt to delete all related files
    deletion_results = Enum.map(files_to_delete, fn file ->
      case FileStorage.delete_file(file) do
        :ok -> {:ok, file}
        {:error, :enoent} -> {:ok, file}  # File already doesn't exist, that's fine
        {:error, reason} -> {:error, {file, reason}}
      end
    end)

    # Check if any deletions failed
    failed_deletions = Enum.filter(deletion_results, fn
      {:error, _} -> true
      _ -> false
    end)

    case failed_deletions do
      [] ->
        # All deletions successful, clean up tags and metadata
        TagStorage.remove_tags_for_file(filename)

        deleted_files = Enum.map(deletion_results, fn {:ok, file} -> file end)

        {:noreply,
         socket
         |> assign_files_and_tags()
         |> assign(:selected_file, nil)
         |> assign(:file_metadata, %{})
         |> assign(:new_tags, "")
         |> put_flash(:info, "Deleted #{length(deleted_files)} related file(s)")}

      errors ->
        error_details = Enum.map(errors, fn {:error, {file, reason}} -> "#{file}: #{inspect(reason)}" end)
        {:noreply, put_flash(socket, :error, "Failed to delete some files: #{Enum.join(error_details, ", ")}")}
    end
  end

  @impl true
  def handle_event("search-by-tags", %{"search_tags" => search_tags}, socket) do
    if search_tags == "" do
      # Show all files if search is empty
      {:noreply, assign(socket, :files, FileStorage.list_pdf_files())}
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

  @impl true
  def handle_event("show-metadata", %{"filename" => filename}, socket) do
    metadata = TagStorage.get_extraction(filename)
    {:noreply, assign(socket, :file_metadata, metadata)}
  end

  @impl true
  def handle_event("retry-conversion", %{"filename" => display_filename}, socket) do
    # Reset status to converting and re-run conversion using the stored MHT bytes
    # display_filename is the PDF filename shown in UI, need to find the MHT source
    meta = TagStorage.get_extraction(display_filename)
    mht_filename = Map.get(meta, "filename_mht")

    if mht_filename do
      TagStorage.update_metadata(display_filename, %{"status" => "converting"})

      mht_binary =
        case FileStorage.read_file(mht_filename) do
          {:ok, bin} -> bin
          _ -> <<>>
        end

      if byte_size(mht_binary) > 0 do
        start_mht_conversion(mht_filename, mht_binary)
      end
    end

    {:noreply, assign_files_and_tags(socket)}
  end

  @impl true
  def handle_info({:extraction_done, filename}, socket) do
    # Refresh metadata for just that file for efficiency
    meta = TagStorage.get_extraction(filename)
    new_meta_map = Map.put(socket.assigns.file_meta_map, filename, meta)

    socket =
      socket
      |> assign(:file_meta_map, new_meta_map)
      |> assign_files_and_tags()

    # If the modal or side panel is showing this file, refresh its metadata
    socket =
      if socket.assigns.selected_file == filename do
        assign(socket, :file_metadata, meta)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:conversion_done, mht_filename, pdf_filename}, socket) do
    meta = TagStorage.get_extraction(pdf_filename)
    new_meta_map = Map.put(socket.assigns.file_meta_map, pdf_filename, meta)

    socket =
      socket
      |> assign(:file_meta_map, new_meta_map)
      |> assign_files_and_tags()
      |> put_flash(:info, "Converted #{mht_filename} to #{pdf_filename}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:conversion_failed, mht_filename, reason}, socket) do
    {:noreply,
     socket
     |> assign_files_and_tags()
     |> put_flash(:error, "Conversion failed for #{mht_filename}: #{inspect(reason)}")}
  end

  # Helper functions

  defp assign_files_and_tags(socket) do
    # Get all files that have metadata (immediately created upon upload)
    all_metadata_files = TagStorage.list_all_metadata_files()

    socket
    |> assign(:files, all_metadata_files)
    |> assign(:tags, TagStorage.get_all_tags())
  end

  defp build_file_meta_map(socket) do
    meta_map =
      Enum.reduce(socket.assigns.files, %{}, fn filename, acc ->
        Map.put(acc, filename, TagStorage.get_extraction(filename))
      end)

    assign(socket, :file_meta_map, meta_map)
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
  defp error_to_string(:not_accepted), do: "File type not accepted (.pdf, .mht, .mhtml)"
  defp error_to_string(error), do: "Upload error: #{inspect(error)}"

  # Helper function to get the display filename for UI
  defp get_display_filename(filename, meta) do
    case Map.get(meta, "filename") do
      nil -> filename  # Show original filename if no PDF filename available
      pdf_filename -> pdf_filename  # Show PDF filename if available
    end
  end

  # -- MHT Conversion helpers -------------------------------------------------
  defp determine_upload_kind(filename) do
    case Path.extname(String.downcase(filename)) do
      ".pdf" -> :pdf
      ".mht" -> :mht
      ".mhtml" -> :mht
      _ -> :pdf
    end
  end

  # Convert MHT filename to target PDF filename (same logic as MhtConverter)
  defp mht_to_pdf_filename(mht_filename) do
    base = mht_filename |> Path.basename() |> Path.rootname()
    FileStorage.safe_filename(base <> ".pdf")
  end

  # Check if metadata already exists for a given filename
  defp metadata_exists?(filename) do
    metadata = TagStorage.get_extraction(filename)
    # Consider metadata exists if it has any content (not just an empty map)
    metadata != %{} and map_size(metadata) > 0
  end

  defp start_mht_conversion(mht_filename, mht_binary) do
    # Track status in UI via PubSub updates; initial status is implicit after upload
    Task.Supervisor.start_child(LiveAiChat.TaskSupervisor, fn ->
      # Helper to convert MHT filename to PDF filename within task
      mht_to_pdf_fn = fn mht_name ->
        base = mht_name |> Path.basename() |> Path.rootname()
        FileStorage.safe_filename(base <> ".pdf")
      end
      max_attempts = Application.get_env(:live_ai_chat, :mht_converter_max_attempts, 3)
      base_delay_ms = Application.get_env(:live_ai_chat, :mht_converter_backoff_ms, 2_000)

      attempt_convert = fn attempt, fun ->
        case LiveAiChat.MhtConverter.convert(mht_filename, mht_binary) do
          {:ok, %{pdf_filename: pdf_filename, pdf_binary: pdf_binary}} ->
            case FileStorage.save_file(pdf_filename, pdf_binary) do
              :ok ->
                # Update metadata to include PDF filename and change status
                # Metadata is stored under PDF filename, not MHT filename
                target_pdf_name = mht_to_pdf_fn.(mht_filename)
                TagStorage.update_metadata(target_pdf_name, %{
                  "filename" => pdf_filename,
                  "status" => "extracting"
                })

                Extractor.enqueue(pdf_filename, pdf_binary)

                Phoenix.PubSub.broadcast(
                  LiveAiChat.PubSub,
                  "knowledge",
                  {:conversion_done, mht_filename, pdf_filename}
                )

              {:error, reason} ->
                # Update metadata to show conversion failed
                target_pdf_name = mht_to_pdf_fn.(mht_filename)
                TagStorage.update_metadata(target_pdf_name, %{
                  "status" => "conversion_failed",
                  "error" => inspect(reason)
                })

                Phoenix.PubSub.broadcast(
                  LiveAiChat.PubSub,
                  "knowledge",
                  {:conversion_failed, mht_filename, {:save_pdf_failed, reason}}
                )
            end

          {:error, reason} ->
            if attempt < max_attempts do
              # exponential backoff: base * 2^(attempt-1)
              delay = base_delay_ms * :erlang.floor(:math.pow(2, attempt - 1))
              Process.sleep(delay)
              fun.(attempt + 1, fun)
            else
              # Update metadata to show conversion failed after retries
              target_pdf_name = mht_to_pdf_fn.(mht_filename)
              TagStorage.update_metadata(target_pdf_name, %{
                "status" => "conversion_failed",
                "error" => inspect(reason)
              })

              Phoenix.PubSub.broadcast(
                LiveAiChat.PubSub,
                "knowledge",
                {:conversion_failed, mht_filename, reason}
              )
            end
        end
      end

      attempt_convert.(1, attempt_convert)
    end)
  end
end
