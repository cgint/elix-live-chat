defmodule LiveAiChatWeb.ChatLiveTest do
  use LiveAiChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @chat_logs_dir "priv/test_chat_logs"

  setup do
    File.mkdir_p!(@chat_logs_dir)
    Application.put_env(:live_ai_chat, :chat_logs_dir, @chat_logs_dir)
    File.write!(Path.join(@chat_logs_dir, "test-chat.csv"), "user,Hello\n")

    on_exit(fn ->
      File.rm_rf!(@chat_logs_dir)
      Application.delete_env(:live_ai_chat, :chat_logs_dir)
    end)

    :ok
  end

  describe "sending a message" do
    test "sends a message and it appears in the chat", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/")

      assert has_element?(view, "#messages", "Hello")

      view
      |> form("form[phx-submit=send_message]", %{"content" => "Test message"})
      |> render_submit()

      assert render(view) =~ "Test message"
    end
  end
end