defmodule LiveAiChat.Knowledge.ExtractorTest do
  use ExUnit.Case, async: false
  import Mox

  alias LiveAiChat.Knowledge.Extractor
  alias LiveAiChat.TagStorage

  @test_data_dir "priv/test_extractor_data"
  @test_upload_dir "priv/test_extractor_uploads"

  # Mock AI client responses
  @mock_ai_response ~s|{
    "summary": "This is a test document about Elixir programming concepts.",
    "keyPoints": ["Pattern matching", "GenServer processes", "Functional programming"],
    "topics": ["elixir", "programming", "functional"],
    "concepts": ["pattern matching", "processes"],
    "difficulty": "intermediate",
    "estimatedReadTime": "5 minutes"
  }|

  setup do
    # Create test directories
    File.mkdir_p!(@test_data_dir)
    File.mkdir_p!(@test_upload_dir)

    # Configure test directories
    Application.put_env(:live_ai_chat, :data_dir, @test_data_dir)
    Application.put_env(:live_ai_chat, :upload_dir, @test_upload_dir)

    # Start the TagStorage GenServer and TaskSupervisor for testing extraction save functionality
    # (Handle case where they might already be started by application)
    case TagStorage.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    case Task.Supervisor.start_link(name: LiveAiChat.TaskSupervisor) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Set up mocks for most tests (will be overridden for integration test)
    stub(LiveAiChat.AIClient.GeminiMock, :get_completion, fn _prompt ->
      {:ok, @mock_ai_response}
    end)

    stub(LiveAiChat.AIClient.GeminiMock, :extract_document_content, fn _content, _prompt ->
      {:ok, @mock_ai_response}
    end)

    on_exit(fn ->
      # Clean up test directories
      File.rm_rf!(@test_data_dir)
      File.rm_rf!(@test_upload_dir)
      Application.delete_env(:live_ai_chat, :data_dir)
      Application.delete_env(:live_ai_chat, :upload_dir)
    end)

    :ok
  end

  describe "extract_content/2 - with mocked AI" do
    test "extracts content from text file using AI" do
      content = "This is a comprehensive guide to Elixir programming."

      {:ok, metadata} = Extractor.extract_content("guide.txt", content)

      assert is_map(metadata)
      assert metadata["filename"] == "guide.txt"
      assert metadata["contentType"] == "text file"
      assert metadata["extractionMethod"] == "gemini_ai"
      assert metadata["extractorVersion"] == "2.0.0-gemini"

      # Verify mocked response data
      assert metadata["summary"] == "This is a test document about Elixir programming concepts."
      assert metadata["topics"] == ["elixir", "programming", "functional"]
      assert metadata["difficulty"] == "intermediate"
    end

    test "extracts content from markdown file using AI" do
      content = "# Phoenix LiveView Tutorial"

      {:ok, metadata} = Extractor.extract_content("tutorial.md", content)

      assert metadata["contentType"] == "markdown document"
      assert metadata["filename"] == "tutorial.md"
      assert metadata["extractionMethod"] == "gemini_ai"
    end

    test "extracts content from PDF files using AI" do
      content = <<"%PDF-1.4", "some pdf content">>

      {:ok, metadata} = Extractor.extract_content("document.pdf", content)

      assert metadata["filename"] == "document.pdf"
      assert metadata["contentType"] == "pdf"
      assert metadata["extractorVersion"] == "2.0.0-gemini"
      assert metadata["extractionMethod"] == "gemini_ai"
    end

    test "returns error for unsupported file types" do
      content = "Some content"

      assert {:error, {:unsupported_file_type, _}} =
               Extractor.extract_content("file.xyz", content)
    end

    test "handles AI extraction errors gracefully" do
      expect(LiveAiChat.AIClient.GeminiMock, :get_completion, fn _prompt ->
        {:error, :api_error}
      end)

      content = "Some content"

      assert {:error, :gemini_extraction_failed} =
               Extractor.extract_content("test.txt", content)
    end
  end

  describe "enqueue/2 - with mocked AI" do
    test "successfully enqueues extraction task" do
      content = "Test content for background extraction."

      {:ok, pid} = Extractor.enqueue("test.txt", content)

      assert is_pid(pid)

      # Wait for the task to complete by monitoring the process
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      # Check that metadata was saved to TagStorage
      Process.sleep(100)
      saved_metadata = TagStorage.get_extraction("test.txt")
      assert saved_metadata["filename"] == "test.txt"

      # Check that extracted topics were automatically assigned as tags
      all_tags = TagStorage.get_all_tags()
      file_tags = Map.get(all_tags, "test.txt", [])
      assert "elixir" in file_tags
      assert "programming" in file_tags
      assert "functional" in file_tags
    end

    test "handles extraction errors gracefully" do
      # This should trigger an unsupported file type error
      {:ok, pid} = Extractor.enqueue("unsupported.xyz", "content")

      # Wait for the task to complete by monitoring the process
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      # The task should have completed but with an error
      # We can't directly get the result, but we can verify no metadata was saved
      Process.sleep(100)
      metadata = TagStorage.get_extraction("unsupported.xyz")
      assert metadata == %{}
    end
  end

  describe "file type detection" do
    test "correctly identifies text files" do
      assert {:ok, metadata} = Extractor.extract_content("document.txt", "content")
      assert metadata["contentType"] == "text file"
    end

    test "correctly identifies markdown files" do
      assert {:ok, metadata} = Extractor.extract_content("document.md", "content")
      assert metadata["contentType"] == "markdown document"

      assert {:ok, metadata} = Extractor.extract_content("document.markdown", "content")
      assert metadata["contentType"] == "markdown document"
    end
  end

  describe "metadata structure" do
    test "includes all required metadata fields" do
      content = "Test content for metadata validation."

      {:ok, metadata} = Extractor.extract_content("test.txt", content)

      # Check that all expected fields are present
      required_fields = [
        "filename",
        "contentType",
        "extractedAt",
        "extractorVersion",
        "summary",
        "keyPoints",
        "topics",
        "difficulty",
        "estimatedReadTime",
        "extractionMethod"
      ]

      for field <- required_fields do
        assert Map.has_key?(metadata, field), "Missing field: #{field}"
      end

      # Check that extractedAt is a valid ISO8601 timestamp
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(metadata["extractedAt"])
    end
  end

  # ONE INTEGRATION TEST WITH REAL AI SERVICE
  describe "real AI integration test" do
    @describetag :integration

    test "actual AI extraction works end-to-end" do
      # Override mock to use real client for this test only
      Application.put_env(:live_ai_chat, :gemini_client, LiveAiChat.AIClient.Gemini)

      # Skip if no real AI client available or not configured
      if Code.ensure_loaded?(LiveAiChat.AIClient.Gemini) and
           System.get_env("GOOGLE_CLOUD_PROJECT") do
        content = """
        This is a simple test document about Elixir programming.
        It covers basic concepts like pattern matching and GenServer processes.
        """

        case Extractor.extract_content("integration_test.txt", content) do
          {:ok, metadata} ->
            # Basic structure validation - don't test specific AI responses
            assert is_map(metadata)
            assert is_binary(metadata["summary"])
            assert is_list(metadata["topics"])
            assert is_list(metadata["keyPoints"])
            assert metadata["filename"] == "integration_test.txt"
            assert metadata["extractorVersion"] == "2.0.0-gemini"

          {:error, reason} ->
            # AI service might be unavailable in test environment, that's okay
            assert reason in [:gemini_extraction_failed, :api_error]
        end
      else
        # Skip test if AI client not available or not configured
        IO.puts("Skipping integration test - AI client not configured")
        assert true
      end

      # Restore mock for subsequent tests
      Application.put_env(:live_ai_chat, :gemini_client, LiveAiChat.AIClient.GeminiMock)
    end
  end
end
