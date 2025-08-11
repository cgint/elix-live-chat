defmodule LiveAiChat.FileStorageTest do
  use ExUnit.Case, async: false

  alias LiveAiChat.FileStorage

  @upload_dir "priv/test_uploads"

  setup do
    # Create test directory
    File.mkdir_p!(@upload_dir)

    # Configure test upload directory
    Application.put_env(:live_ai_chat, :upload_dir, @upload_dir)

    # Start the FileStorage GenServer for testing (handle if already started)
    case FileStorage.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Clean up any existing files from previous tests
    case File.ls(@upload_dir) do
      {:ok, files} ->
        for file <- files do
          File.rm(Path.join(@upload_dir, file))
        end

      _ ->
        :ok
    end

    on_exit(fn ->
      # Clean up test directory
      File.rm_rf!(@upload_dir)
      Application.delete_env(:live_ai_chat, :upload_dir)
    end)

    :ok
  end

  describe "save_file/2" do
    test "saves file successfully" do
      content = "Hello, World!"
      filename = "test.txt"

      assert FileStorage.save_file(filename, content) == :ok

      # Verify file exists and has correct content
      file_path = Path.join(@upload_dir, filename)
      assert File.exists?(file_path)
      assert File.read!(file_path) == content
    end

    test "sanitizes filename" do
      content = "Test content"
      unsafe_filename = "../../../etc/passwd"

      assert FileStorage.save_file(unsafe_filename, content) == :ok

      # Should be sanitized to safe filename
      safe_files = File.ls!(@upload_dir)
      assert length(safe_files) == 1
      assert hd(safe_files) == "passwd"
    end

    test "replaces special characters in filename" do
      content = "Test content"
      filename = "test file @#$%^&*().txt"

      assert FileStorage.save_file(filename, content) == :ok

      files = File.ls!(@upload_dir)
      assert length(files) == 1
      # Special characters should be replaced with underscores
      assert hd(files) =~ ~r/test_file.*\.txt/
    end
  end

  describe "read_file/1" do
    test "reads existing file successfully" do
      content = "File content"
      filename = "read_test.txt"
      file_path = Path.join(@upload_dir, filename)

      File.write!(file_path, content)

      assert FileStorage.read_file(filename) == {:ok, content}
    end

    test "returns error for non-existent file" do
      assert FileStorage.read_file("nonexistent.txt") == {:error, :enoent}
    end
  end

  describe "delete_file/1" do
    test "deletes existing file successfully" do
      filename = "delete_test.txt"
      file_path = Path.join(@upload_dir, filename)

      File.write!(file_path, "content")
      assert File.exists?(file_path)

      assert FileStorage.delete_file(filename) == :ok
      refute File.exists?(file_path)
    end

    test "returns error when trying to delete non-existent file" do
      result = FileStorage.delete_file("nonexistent.txt")
      assert match?({:error, _}, result)
    end
  end

  describe "list_files/0" do
    test "returns empty list when no files exist" do
      assert FileStorage.list_files() == []
    end

    test "returns list of all files in upload directory" do
      files = ["file1.txt", "file2.pdf", "file3.md"]

      for file <- files do
        File.write!(Path.join(@upload_dir, file), "content")
      end

      result = FileStorage.list_files()
      assert Enum.sort(result) == Enum.sort(files)
    end

    test "does not include subdirectories" do
      File.write!(Path.join(@upload_dir, "file.txt"), "content")
      File.mkdir_p!(Path.join(@upload_dir, "subdir"))

      result = FileStorage.list_files()
      assert result == ["file.txt"]
    end
  end
end
