defmodule LiveAiChat.AIClient do
  @moduledoc """
  A behaviour for clients that interact with an AI service.
  """

  @callback stream_reply(pid :: pid(), user_message :: map()) :: any()

  defmodule Dummy do
    @behaviour LiveAiChat.AIClient

    @canned_response "This is a dummy response from the AI, streamed to you one word at a time."

    @impl true
    def stream_reply(recipient_pid, _user_message) do
      Task.start(fn ->
        # Send the initial assistant message chunk
        assistant_message_id = System.unique_integer()
        send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}})

        # Stream the rest of the response
        for word <- String.split(@canned_response) do
          Process.sleep(5) # Use a shorter sleep for tests
          send(recipient_pid, {:ai_chunk, %{id: assistant_message_id, content: " " <> word}})
        end

        send(recipient_pid, :ai_done)
      end)
    end
  end
end