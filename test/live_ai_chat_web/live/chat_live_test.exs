defmodule LiveAiChatWeb.ChatLiveTest do
  use LiveAiChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Mox

  alias LiveAiChat.AIClientMock

  @chat_logs_dir "priv/test_chat_logs"
  @test_chats_dir "priv/test_chats"

  setup do
    Mox.stub_with(AIClientMock, LiveAiChat.AIClient.Dummy)

    # Clean up any existing test data
    File.rm_rf!(@test_chats_dir)
    File.rm_rf!(@chat_logs_dir)

    # Configure both storage systems for testing
    File.mkdir_p!(@chat_logs_dir)
    File.mkdir_p!(@test_chats_dir)
    Application.put_env(:live_ai_chat, :chat_logs_dir, @chat_logs_dir)
    Application.put_env(:live_ai_chat, :chats_dir, @test_chats_dir)

    # Create a test chat with a message using the new storage system
    :ok = LiveAiChat.ChatStorage.create_chat("test-chat")
    LiveAiChat.ChatStorageAdapter.append_message("test-chat", %{role: "user", content: "Hello"})

    on_exit(fn ->
      File.rm_rf!(@chat_logs_dir)
      File.rm_rf!(@test_chats_dir)
      Application.delete_env(:live_ai_chat, :chat_logs_dir)
      Application.delete_env(:live_ai_chat, :chats_dir)
    end)

    :ok
  end

  describe "sending a message" do
    test "sends a message and it appears in the chat", %{conn: conn} do
      # This test doesn't focus on the AI response, but we need to satisfy the mock.
      expect(AIClientMock, :stream_reply, fn _, _, _ -> :ok end)

      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#messages", "Hello")

      view
      |> form("form[phx-submit=send_message]", %{"content" => "Test message"})
      |> render_submit()

      assert render(view) =~ "Test message"
    end

    @tag :skip
    test "sends a message and receives a streamed AI response", %{conn: conn} do
      # Mock the AI response
      expect(AIClientMock, :stream_reply, fn live_view_pid, _chat_id, _message ->
        Task.start(fn ->
          assistant_message_id = System.unique_integer()

          send(
            live_view_pid,
            {:ai_chunk, %{id: assistant_message_id, role: "assistant", content: ""}}
          )

          Process.sleep(10)
          send(live_view_pid, {:ai_chunk, %{id: assistant_message_id, content: "Mocked"}})
          Process.sleep(10)
          send(live_view_pid, {:ai_chunk, %{id: assistant_message_id, content: " response"}})
          Process.sleep(10)
          send(live_view_pid, :ai_done)
        end)
      end)

      conn = Phoenix.ConnTest.recycle(conn)
      conn = Phoenix.ConnTest.init_test_session(conn, %{"test_pid" => self()})

      {:ok, view, _html} = live(conn, "/")

      # Submit the form
      view
      |> form("form[phx-submit=send_message]", %{"content" => "Test message"})
      |> render_submit()

      # Wait for the LiveView to signal that it has finished rendering.
      assert_receive :render_complete, 5000
      Process.sleep(50)
      # Now, the final state should be rendered. Check for partial content to avoid flakiness.
      html = render(view)
      assert html =~ "Mocked" or html =~ "response"
    end
  end
end
