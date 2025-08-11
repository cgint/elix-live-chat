defmodule LiveAiChat.TagStorageTest do
  use ExUnit.Case, async: false

  alias LiveAiChat.TagStorage

  @test_data_dir "priv/test_data"
  @test_upload_dir "priv/test_uploads"

  setup do
    # Create test directories
    File.mkdir_p!(@test_data_dir)
    File.mkdir_p!(@test_upload_dir)

    # Configure test directories
    Application.put_env(:live_ai_chat, :data_dir, @test_data_dir)
    Application.put_env(:live_ai_chat, :upload_dir, @test_upload_dir)

    # Start the TagStorage GenServer for testing (handle if already started)
    case TagStorage.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    on_exit(fn ->
      # Clean up test directories
      File.rm_rf!(@test_data_dir)
      File.rm_rf!(@test_upload_dir)
      Application.delete_env(:live_ai_chat, :data_dir)
      Application.delete_env(:live_ai_chat, :upload_dir)
    end)

    :ok
  end

  describe "get_all_tags/0" do
    test "returns empty map when no tags exist" do
      assert TagStorage.get_all_tags() == %{}
    end

    test "returns existing tags after they are set" do
      TagStorage.update_tags_for_file("test.txt", ["tag1", "tag2"])
      # Give the cast operation time to complete
      Process.sleep(10)

      result = TagStorage.get_all_tags()
      assert result == %{"test.txt" => ["tag1", "tag2"]}
    end
  end

  describe "update_tags_for_file/2" do
    test "updates tags for a file" do
      TagStorage.update_tags_for_file("document.pdf", ["elixir", "phoenix"])
      Process.sleep(10)

      tags = TagStorage.get_all_tags()
      assert tags["document.pdf"] == ["elixir", "phoenix"]
    end

    test "updates existing tags for a file" do
      TagStorage.update_tags_for_file("document.pdf", ["elixir"])
      Process.sleep(10)

      TagStorage.update_tags_for_file("document.pdf", ["elixir", "phoenix", "liveview"])
      Process.sleep(10)

      tags = TagStorage.get_all_tags()
      assert tags["document.pdf"] == ["elixir", "phoenix", "liveview"]
    end

    test "handles multiple files with different tags" do
      TagStorage.update_tags_for_file("file1.txt", ["tag1", "tag2"])
      TagStorage.update_tags_for_file("file2.txt", ["tag3", "tag4"])
      Process.sleep(10)

      tags = TagStorage.get_all_tags()
      assert tags["file1.txt"] == ["tag1", "tag2"]
      assert tags["file2.txt"] == ["tag3", "tag4"]
    end

    test "persists tags to JSON file" do
      TagStorage.update_tags_for_file("persistent.txt", ["test", "persistent"])
      Process.sleep(10)

      # Check that the file was written
      tags_file = Path.join(@test_data_dir, "file-tags.json")
      assert File.exists?(tags_file)

      {:ok, content} = File.read(tags_file)
      {:ok, data} = Jason.decode(content)
      assert data["persistent.txt"] == ["test", "persistent"]
    end
  end

  describe "remove_tags_for_file/1" do
    test "removes tags for a file completely" do
      TagStorage.update_tags_for_file("document.pdf", ["elixir", "phoenix"])
      Process.sleep(10)

      # Verify tags exist
      tags = TagStorage.get_all_tags()
      assert tags["document.pdf"] == ["elixir", "phoenix"]

      # Remove tags
      TagStorage.remove_tags_for_file("document.pdf")
      Process.sleep(10)

      # Verify tags are completely removed
      tags = TagStorage.get_all_tags()
      refute Map.has_key?(tags, "document.pdf")
    end

    test "removes tags from JSON file permanently" do
      TagStorage.update_tags_for_file("test_file.txt", ["test", "tag"])
      Process.sleep(10)

      # Verify file exists in JSON
      tags_file = Path.join(@test_data_dir, "file-tags.json")
      {:ok, content} = File.read(tags_file)
      {:ok, data} = Jason.decode(content)
      assert Map.has_key?(data, "test_file.txt")

      # Remove tags
      TagStorage.remove_tags_for_file("test_file.txt")
      Process.sleep(10)

      # Verify file is removed from JSON
      {:ok, content} = File.read(tags_file)
      {:ok, data} = Jason.decode(content)
      refute Map.has_key?(data, "test_file.txt")
    end

    test "handles removing tags for non-existent file" do
      # Should not crash when removing tags for a file that doesn't exist
      TagStorage.remove_tags_for_file("nonexistent.txt")
      Process.sleep(10)

      tags = TagStorage.get_all_tags()
      assert tags == %{}
    end

    test "removes only specified file while preserving others" do
      TagStorage.update_tags_for_file("file1.txt", ["tag1"])
      TagStorage.update_tags_for_file("file2.txt", ["tag2"])
      TagStorage.update_tags_for_file("file3.txt", ["tag3"])
      Process.sleep(10)

      # Remove tags for file2 only
      TagStorage.remove_tags_for_file("file2.txt")
      Process.sleep(10)

      tags = TagStorage.get_all_tags()
      assert tags["file1.txt"] == ["tag1"]
      assert tags["file3.txt"] == ["tag3"]
      refute Map.has_key?(tags, "file2.txt")
    end

    test "removes corresponding metadata file when removing tags" do
      filename = "test_with_meta.pdf"

      # Create metadata file
      metadata = %{"summary" => "Test document", "keyPoints" => ["point1"]}
      TagStorage.save_extraction(filename, metadata)
      TagStorage.update_tags_for_file(filename, ["test", "pdf"])
      Process.sleep(10)

      # Verify both tags and metadata exist
      tags = TagStorage.get_all_tags()
      assert tags[filename] == ["test", "pdf"]

      meta_file = Path.join(@test_upload_dir, "#{filename}.meta.json")
      assert File.exists?(meta_file)

      # Remove tags (should also remove metadata)
      TagStorage.remove_tags_for_file(filename)
      Process.sleep(10)

      # Verify both tags and metadata are removed
      tags = TagStorage.get_all_tags()
      refute Map.has_key?(tags, filename)
      refute File.exists?(meta_file)
    end

    test "handles removal when metadata file doesn't exist" do
      # Create tags without metadata
      TagStorage.update_tags_for_file("no_meta.txt", ["test"])
      Process.sleep(10)

      # Remove tags (should not crash even though no metadata file exists)
      TagStorage.remove_tags_for_file("no_meta.txt")
      Process.sleep(10)

      tags = TagStorage.get_all_tags()
      refute Map.has_key?(tags, "no_meta.txt")
    end
  end

  describe "save_extraction/2 and get_extraction/1" do
    test "saves and retrieves extraction metadata" do
      filename = "test_document.pdf"

      metadata = %{
        "summary" => "This is a test document about Elixir programming",
        "keyPoints" => ["GenServers", "OTP", "Concurrency"],
        "topics" => ["Elixir", "Programming"],
        "extractedAt" => "2025-01-11T10:30:00Z"
      }

      TagStorage.save_extraction(filename, metadata)
      Process.sleep(10)

      retrieved = TagStorage.get_extraction(filename)
      assert retrieved == metadata
    end

    test "returns empty map for non-existent extraction" do
      result = TagStorage.get_extraction("nonexistent.txt")
      assert result == %{}
    end

    test "saves extraction to separate meta file" do
      filename = "document.txt"
      metadata = %{"summary" => "Test summary", "keyPoints" => ["point1", "point2"]}

      TagStorage.save_extraction(filename, metadata)
      Process.sleep(10)

      # Check that the meta file was created
      meta_file = Path.join(@test_upload_dir, "#{filename}.meta.json")
      assert File.exists?(meta_file)

      {:ok, content} = File.read(meta_file)
      {:ok, data} = Jason.decode(content)
      assert data == metadata
    end
  end

  describe "get_files_by_tags/1" do
    test "returns empty list when no files match tags" do
      result = TagStorage.get_files_by_tags(["nonexistent"])
      assert result == []
    end

    test "returns files that match any of the requested tags" do
      TagStorage.update_tags_for_file("elixir_guide.pdf", ["elixir", "programming"])
      TagStorage.update_tags_for_file("phoenix_tutorial.md", ["phoenix", "web"])
      TagStorage.update_tags_for_file("javascript_book.pdf", ["javascript", "web"])
      Process.sleep(10)

      # Should return files that have "web" tag
      result = TagStorage.get_files_by_tags(["web"])
      assert Enum.sort(result) == ["javascript_book.pdf", "phoenix_tutorial.md"]

      # Should return files that have "elixir" tag
      result = TagStorage.get_files_by_tags(["elixir"])
      assert result == ["elixir_guide.pdf"]

      # Should return files that have either "elixir" or "javascript" tags
      result = TagStorage.get_files_by_tags(["elixir", "javascript"])
      assert Enum.sort(result) == ["elixir_guide.pdf", "javascript_book.pdf"]
    end

    test "performs case-insensitive tag matching" do
      TagStorage.update_tags_for_file("test.txt", ["Elixir", "Phoenix"])
      Process.sleep(10)

      # Should match regardless of case
      result = TagStorage.get_files_by_tags(["elixir"])
      assert result == ["test.txt"]

      result = TagStorage.get_files_by_tags(["PHOENIX"])
      assert result == ["test.txt"]
    end
  end

  describe "concurrent operations" do
    test "handles concurrent tag updates correctly" do
      # Spawn multiple processes updating tags concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            TagStorage.update_tags_for_file("concurrent_#{i}.txt", ["tag_#{i}"])
          end)
        end

      # Wait for all tasks to complete
      Task.await_many(tasks, 5000)
      Process.sleep(50)

      tags = TagStorage.get_all_tags()

      # All files should have their respective tags
      for i <- 1..10 do
        assert tags["concurrent_#{i}.txt"] == ["tag_#{i}"]
      end
    end
  end
end
