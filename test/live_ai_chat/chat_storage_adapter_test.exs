defmodule LiveAiChat.ChatStorageAdapterTest do
  use ExUnit.Case, async: false

  alias LiveAiChat.ChatStorageAdapter

  @chat_logs_dir "priv/test_chat_logs"
  @test_chats_dir "priv/test_chats"

  setup do
    # Clean up any existing test data
    File.rm_rf!(@test_chats_dir)
    File.rm_rf!(@chat_logs_dir)

    # Configure both storage systems for testing
    File.mkdir_p!(@chat_logs_dir)
    File.mkdir_p!(@test_chats_dir)
    Application.put_env(:live_ai_chat, :chat_logs_dir, @chat_logs_dir)
    Application.put_env(:live_ai_chat, :chats_dir, @test_chats_dir)

    on_exit(fn ->
      File.rm_rf!(@chat_logs_dir)
      File.rm_rf!(@test_chats_dir)
      # Restore original config
      Application.delete_env(:live_ai_chat, :chat_logs_dir)
      Application.delete_env(:live_ai_chat, :chats_dir)
    end)

    :ok
  end

  describe "list_chats/0" do
    test "returns an empty list when no chats exist" do
      assert ChatStorageAdapter.list_chats() == []
    end

    test "returns a list of chat_ids from json storage" do
      # Create test chats using the new storage system
      :ok = LiveAiChat.ChatStorage.create_chat("chat1")
      :ok = LiveAiChat.ChatStorage.create_chat("chat2")

      assert Enum.sort(ChatStorageAdapter.list_chats()) == ["chat1", "chat2"]
    end
  end

  describe "append_message/2 and read_chat/1" do
    test "appends messages and reads them back" do
      chat_id = "test_chat"
      msg1 = %{role: "user", content: "Hello"}
      msg2 = %{role: "assistant", content: "Hi there"}

      # Create the chat first
      :ok = LiveAiChat.ChatStorage.create_chat(chat_id)

      assert ChatStorageAdapter.read_chat(chat_id) == []

      ChatStorageAdapter.append_message(chat_id, msg1)
      assert ChatStorageAdapter.read_chat(chat_id) == [{:ok, %{role: "user", content: "Hello"}}]

      ChatStorageAdapter.append_message(chat_id, msg2)

      assert ChatStorageAdapter.read_chat(chat_id) == [
               {:ok, %{role: "user", content: "Hello"}},
               {:ok, %{role: "assistant", content: "Hi there"}}
             ]
    end
  end
end
