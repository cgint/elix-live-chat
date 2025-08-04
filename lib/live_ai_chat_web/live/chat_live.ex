defmodule LiveAiChatWeb.ChatLive do
  use LiveAiChatWeb, :live_view

  alias LiveAiChat.CsvStorage

  @impl true
  def mount(_params, %{"test_pid" => test_pid}, socket) do
    setup(socket, test_pid)
  end

  # This is the default mount for normal application startup.
  @impl true
  def mount(_params, _session, socket) do
    setup(socket, nil)
  end

  defp setup(socket, test_pid) do
    chats = CsvStorage.list_chats()
    active_chat_id = List.first(chats)

    socket =
      assign(socket,
        chats: chats,
        active_chat_id: active_chat_id,
        form: to_form(%{"content" => ""}),
        streaming_ai_response: nil,
        processing_request: false,
        editing_chat_id: nil,
        test_pid: test_pid
      )
      |> stream(:messages, [])

    {:ok, load_messages(socket, active_chat_id)}
  end

  @impl true
  def handle_event("select_chat", %{"chat-id" => chat_id}, socket) do
    # Prevent chat switching during AI response processing
    if socket.assigns.streaming_ai_response == nil and not socket.assigns.processing_request do
      socket = assign(socket, :active_chat_id, chat_id)
      {:noreply, load_messages(socket, chat_id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    # Prevent new chat creation during AI response processing
    if socket.assigns.streaming_ai_response == nil and not socket.assigns.processing_request do
      # Generate a unique chat ID with timestamp
      chat_id = "chat-#{System.system_time(:second)}"

      case CsvStorage.create_chat(chat_id) do
        :ok ->
          chats = CsvStorage.list_chats()
          socket =
            assign(socket,
              chats: chats,
              active_chat_id: chat_id,
              editing_chat_id: nil
            )
            |> stream(:messages, [])
          {:noreply, socket}
        {:error, _reason} ->
          # Could add flash message here for error handling
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("start_rename", %{"chat-id" => chat_id}, socket) do
    # Prevent rename during AI response processing
    if socket.assigns.streaming_ai_response == nil and not socket.assigns.processing_request do
      socket = assign(socket, :editing_chat_id, chat_id)
      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_rename", _params, socket) do
    socket = assign(socket, :editing_chat_id, nil)
    {:noreply, socket}
  end

  @impl true
  def handle_event("confirm_rename", %{"chat-id" => old_chat_id, "new-name" => new_name}, socket) do
    new_chat_id = String.trim(new_name)

    if new_chat_id != "" and new_chat_id != old_chat_id do
      case CsvStorage.rename_chat(old_chat_id, new_chat_id) do
        :ok ->
          chats = CsvStorage.list_chats()
          active_chat_id = if socket.assigns.active_chat_id == old_chat_id, do: new_chat_id, else: socket.assigns.active_chat_id
          socket =
            assign(socket,
              chats: chats,
              active_chat_id: active_chat_id,
              editing_chat_id: nil
            )
          {:noreply, socket}
        {:error, _reason} ->
          # Could add flash message here for error handling
          socket = assign(socket, :editing_chat_id, nil)
          {:noreply, socket}
      end
    else
      socket = assign(socket, :editing_chat_id, nil)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete_chat", %{"chat-id" => chat_id}, socket) do
    # Prevent delete during AI response processing
    if socket.assigns.streaming_ai_response == nil and not socket.assigns.processing_request do
      case CsvStorage.delete_chat(chat_id) do
        :ok ->
          chats = CsvStorage.list_chats()
          # If we deleted the active chat, select the first available chat
          active_chat_id = if socket.assigns.active_chat_id == chat_id do
            List.first(chats)
          else
            socket.assigns.active_chat_id
          end

          socket =
            assign(socket, chats: chats, active_chat_id: active_chat_id)
            |> load_messages(active_chat_id)
          {:noreply, socket}
        {:error, _reason} ->
          # Could add flash message here for error handling
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    active_chat_id = socket.assigns.active_chat_id

    # Prevent multiple simultaneous requests
    if content != "" and socket.assigns.streaming_ai_response == nil do
      user_message = %{id: System.unique_integer(), role: "user", content: content}
      CsvStorage.append_message(active_chat_id, user_message)

      # Clear input immediately and show processing state
      socket =
        stream_insert(socket, :messages, user_message)
        |> assign(form: to_form(%{"content" => ""}))
        |> assign(:processing_request, true)

      live_view_pid = self()
      Task.Supervisor.start_child(LiveAiChat.TaskSupervisor, fn ->
        ai_client = Application.get_env(:live_ai_chat, :ai_client, LiveAiChat.AIClient.Dummy)
        ai_client.stream_reply(live_view_pid, user_message)
      end)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:ai_chunk, chunk}, socket) do
    case socket.assigns.streaming_ai_response do
      nil ->
        new_message = %{id: chunk.id, role: "assistant", content: chunk.content}
        socket =
          stream_insert(socket, :messages, new_message)
          |> assign(:streaming_ai_response, new_message)
        {:noreply, socket}
      current_message ->
        updated_content = current_message.content <> chunk.content
        updated_message = %{current_message | content: updated_content}
        socket =
          stream_insert(socket, :messages, updated_message)
          |> assign(:streaming_ai_response, updated_message)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:ai_done, socket) do
    final_message = socket.assigns.streaming_ai_response
    CsvStorage.append_message(socket.assigns.active_chat_id, final_message)

    if pid = socket.assigns.test_pid, do: send(pid, :render_complete)

    {:noreply, assign(socket, streaming_ai_response: nil, processing_request: false)}
  end

  defp load_messages(socket, nil) do
    stream(socket, :messages, [], reset: true)
  end

  defp load_messages(socket, chat_id) do
    messages =
      chat_id
      |> CsvStorage.read_chat()
      |> Enum.map(fn {:ok, message} -> Map.put(message, :id, System.unique_integer()) end)

    stream(socket, :messages, messages, reset: true)
  end
end
