defmodule LiveAiChat.AIClient do
  @moduledoc """
  A client for interacting with an AI service.
  For now, it provides a dummy implementation for development.
  """

  @canned_response "This is a dummy response from the AI, streamed to you one word at a time."

  @doc """
  Streams a dummy AI reply to the calling process.
  """
  def stream_reply(recipient_pid, _user_message) do
    Task.start(fn ->
      # Send the initial assistant message chunk
      assistant_message_id = System.unique_integer()
      send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}})

      # Stream the rest of the response
      for word <- String.split(@canned_response) do
        Process.sleep(150)
        send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: " " <> word}})
      end

      send(recipient_pid, :ai_done)
    end)
  end
end
