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
        test_pid: test_pid
      )
      |> stream(:messages, [])

    {:ok, load_messages(socket, active_chat_id)}
  end

  @impl true
  def handle_event("select_chat", %{"chat-id" => chat_id}, socket) do
    socket = assign(socket, :active_chat_id, chat_id)
    {:noreply, load_messages(socket, chat_id)}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    active_chat_id = socket.assigns.active_chat_id

    if content != "" do
      user_message = %{id: System.unique_integer(), role: "user", content: content}
      CsvStorage.append_message(active_chat_id, user_message)

      socket =
        stream_insert(socket, :messages, user_message)
        |> assign(form: to_form(%{"content" => ""}))

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

    {:noreply, assign(socket, :streaming_ai_response, nil)}
  end

  defp load_messages(socket, nil) do
    stream(socket, :messages, [])
  end

  defp load_messages(socket, chat_id) do
    messages =
      chat_id
      |> CsvStorage.read_chat()
      |> Enum.map(fn {:ok, message} -> Map.put(message, :id, System.unique_integer()) end)

    stream(socket, :messages, messages)
  end
end
