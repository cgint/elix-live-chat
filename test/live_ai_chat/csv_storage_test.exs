defmodule LiveAiChat.CsvStorageTest do
  use ExUnit.Case, async: false

  alias LiveAiChat.CsvStorage

  @chat_logs_dir "priv/test_chat_logs"

  setup do
    # The CsvStorage server is already started by the application supervisor.
    # Use a separate directory for tests and configure it.
    File.mkdir_p!(@chat_logs_dir)
    Application.put_env(:live_ai_chat, :chat_logs_dir, @chat_logs_dir)

    on_exit(fn ->
      File.rm_rf!(@chat_logs_dir)
      # Restore original config
      Application.delete_env(:live_ai_chat, :chat_logs_dir)
    end)

    :ok
  end

  describe "list_chats/0" do
    test "returns an empty list when no chats exist" do
      assert CsvStorage.list_chats() == []
    end

    test "returns a list of chat_ids from csv files" do
      File.touch!(Path.join(@chat_logs_dir, "chat1.csv"))
      File.touch!(Path.join(@chat_logs_dir, "chat2.csv"))
      File.touch!(Path.join(@chat_logs_dir, "non-csv.txt"))

      assert Enum.sort(CsvStorage.list_chats()) == ["chat1", "chat2"]
    end
  end

  describe "append_message/2 and read_chat/1" do
    test "appends messages and reads them back" do
      chat_id = "test_chat"
      msg1 = %{role: "user", content: "Hello"}
      msg2 = %{role: "assistant", content: "Hi there"}

      assert CsvStorage.read_chat(chat_id) == []

      CsvStorage.append_message(chat_id, msg1)
      assert CsvStorage.read_chat(chat_id) == [{:ok, %{role: "user", content: "Hello"}}]

      CsvStorage.append_message(chat_id, msg2)

      assert CsvStorage.read_chat(chat_id) == [
               {:ok, %{role: "user", content: "Hello"}},
               {:ok, %{role: "assistant", content: "Hi there"}}
             ]
    end
  end
end
