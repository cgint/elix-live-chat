defmodule LiveAiChatWeb.ChatLive do
  use LiveAiChatWeb, :live_view

  alias LiveAiChat.CsvStorage
  alias LiveAiChat.AIClient

  @impl true
  def mount(_params, _session, socket) do
    chats = CsvStorage.list_chats()
    active_chat_id = List.first(chats)

    socket =
      assign(socket,
        chats: chats,
        active_chat_id: active_chat_id,
        form: to_form(%{"content" => ""}),
        streaming_ai_response: nil
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
  def handle_event("send_message", %{"message" => %{"content" => content}}, socket) do
    active_chat_id = socket.assigns.active_chat_id

    if content != "" do
      user_message = %{id: System.unique_integer(), role: "user", content: content}
      CsvStorage.append_message(active_chat_id, user_message)

      socket =
        stream_insert(socket, :messages, user_message)
        |> assign(form: to_form(%{"content" => ""}))

      Task.Supervisor.start_child(LiveAiChat.TaskSupervisor, fn ->
        AIClient.stream_reply(self(), user_message)
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
        # First chunk
        new_message = %{id: chunk.id, role: "assistant", content: chunk.content}
        socket =
          stream_insert(socket, :messages, new_message)
          |> assign(:streaming_ai_response, new_message)
        {:noreply, socket}
      current_message ->
        # Subsequent chunks
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
    # Persist the final AI message
    final_message = socket.assigns.streaming_ai_response
    CsvStorage.append_message(socket.assigns.active_chat_id, final_message)
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