defmodule LiveAiChat.Knowledge.ExtractorTest do
  use ExUnit.Case, async: false

  alias LiveAiChat.Knowledge.Extractor
  alias LiveAiChat.TagStorage

  @test_data_dir "priv/test_extractor_data"
  @test_upload_dir "priv/test_extractor_uploads"

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

    on_exit(fn ->
      # Clean up test directories
      File.rm_rf!(@test_data_dir)
      File.rm_rf!(@test_upload_dir)
      Application.delete_env(:live_ai_chat, :data_dir)
      Application.delete_env(:live_ai_chat, :upload_dir)
    end)

    :ok
  end

  describe "extract_content/2" do
    test "extracts content from text file" do
      content = """
      This is a comprehensive guide to Elixir programming.

      Key concepts include:
      - Pattern matching
      - GenServers for state management
      - Supervisor trees for fault tolerance

      Elixir is a functional programming language that runs on the BEAM virtual machine.
      Phoenix is the web framework built on top of Elixir.
      """

      {:ok, metadata} = Extractor.extract_content("guide.txt", content)

      assert is_map(metadata)
      assert is_binary(metadata["summary"])
      assert is_list(metadata["keyPoints"])
      assert is_list(metadata["topics"])
      assert metadata["filename"] == "guide.txt"
      assert metadata["contentType"] == "text file"
      assert metadata["extractionMethod"] == "simple_analysis"

      # Should detect Elixir-related topics
      assert "elixir" in metadata["topics"]
      assert "phoenix" in metadata["topics"]
    end

    test "extracts content from markdown file" do
      content = """
      # Phoenix LiveView Tutorial

      This tutorial covers the basics of Phoenix LiveView development.

      ## Key Topics
      - Real-time web applications
      - Server-side rendering
      - WebSocket connections

      LiveView enables interactive web applications without writing JavaScript.
      """

      {:ok, metadata} = Extractor.extract_content("tutorial.md", content)

      assert metadata["contentType"] == "markdown document"
      assert metadata["filename"] == "tutorial.md"
      assert "liveview" in metadata["topics"]
      assert "phoenix" in metadata["topics"]
    end

    test "determines difficulty level based on content" do
      beginner_content = "This is a simple introduction to programming concepts."

      intermediate_content =
        "GenServer processes handle state in Elixir applications using pattern matching."

      advanced_content =
        "Metaprogramming with macros allows compile-time code generation and protocol implementations."

      {:ok, beginner_meta} = Extractor.extract_content("beginner.txt", beginner_content)

      {:ok, intermediate_meta} =
        Extractor.extract_content("intermediate.txt", intermediate_content)

      {:ok, advanced_meta} = Extractor.extract_content("advanced.txt", advanced_content)

      assert beginner_meta["difficulty"] == "beginner"
      assert intermediate_meta["difficulty"] == "intermediate"
      assert advanced_meta["difficulty"] == "advanced"
    end

    test "calculates estimated read time" do
      short_content = "Short text."
      long_content = String.duplicate("word ", 1000)

      {:ok, short_meta} = Extractor.extract_content("short.txt", short_content)
      {:ok, long_meta} = Extractor.extract_content("long.txt", long_content)

      assert short_meta["estimatedReadTime"] == "1 minutes"
      assert String.contains?(long_meta["estimatedReadTime"], "5 minutes")
    end

    test "extracts bullet points from content" do
      content = """
      Here are the main points:
      - First important point
      - Second key concept
      * Third bullet point
      • Fourth point with different bullet
      1. Numbered first point
      2. Numbered second point

      Some regular text here.
      """

      {:ok, metadata} = Extractor.extract_content("bullets.txt", content)

      key_points = metadata["keyPoints"]
      # Should limit to 5 points
      assert length(key_points) <= 5
      assert "First important point" in key_points
      assert "Second key concept" in key_points
    end

    test "handles content without bullet points" do
      content = "This is just regular text without any bullet points or lists."

      {:ok, metadata} = Extractor.extract_content("plain.txt", content)

      assert metadata["keyPoints"] == ["No bullet points found"]
    end

    test "returns error for unsupported file types" do
      content = "Some content"

      assert {:error, {:unsupported_file_type, _}} =
               Extractor.extract_content("file.xyz", content)
    end

    test "extracts content from PDF files using Gemini (with fallback)" do
      content = <<"%PDF-1.4", "some pdf content">>

      assert {:ok, metadata} = Extractor.extract_content("document.pdf", content)
      assert metadata["filename"] == "document.pdf"
      assert metadata["contentType"] == "pdf"
      assert metadata["extractorVersion"] in ["1.0.0", "2.0.0-gemini"]

      # Should have basic metadata structure
      assert is_binary(metadata["summary"])
      assert is_list(metadata["keyPoints"])
      assert is_list(metadata["topics"])
      assert metadata["difficulty"] in ["beginner", "intermediate", "advanced"]
    end
  end

  describe "enqueue/2" do
    test "successfully enqueues extraction task" do
      content = "Test content for background extraction with Elixir programming concepts."

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
      # Give the cast operation time to complete
      Process.sleep(100)
      saved_metadata = TagStorage.get_extraction("test.txt")
      assert saved_metadata["filename"] == "test.txt"
      assert "elixir" in saved_metadata["topics"]

      # Check that extracted topics were automatically assigned as tags
      all_tags = TagStorage.get_all_tags()
      file_tags = Map.get(all_tags, "test.txt", [])
      assert "elixir" in file_tags
      assert "programming" in file_tags
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

  describe "topic extraction" do
    test "identifies technical topics correctly" do
      content = """
      This document covers web development with Phoenix framework.
      We'll discuss API design, database integration with PostgreSQL,
      and testing strategies including TDD approaches.
      """

      {:ok, metadata} = Extractor.extract_content("tech.txt", content)

      topics = metadata["topics"]
      assert "phoenix" in topics
      assert "web" in topics
      assert "api" in topics
      assert "database" in topics
      assert "testing" in topics
    end

    test "returns general topic when no specific topics found" do
      content = "This is some general content without specific technical terms."

      {:ok, metadata} = Extractor.extract_content("general.txt", content)

      assert metadata["topics"] == ["general"]
    end
  end

  describe "topic-to-tag assignment" do
    test "automatically assigns extracted topics as initial tags" do
      content = """
      This is a comprehensive guide about Elixir Phoenix web development.

      Topics covered:
      - LiveView real-time applications
      - GenServer process management
      - Database integration with PostgreSQL
      - API design and testing strategies

      Phoenix framework makes web development enjoyable with Elixir's functional programming paradigm.
      """

      # Use enqueue to test the full workflow including tag assignment
      {:ok, pid} = Extractor.enqueue("comprehensive_guide.txt", content)

      # Wait for task completion
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      # Allow time for the cast operations to complete
      Process.sleep(200)

      # Verify metadata was saved
      metadata = TagStorage.get_extraction("comprehensive_guide.txt")
      assert metadata["filename"] == "comprehensive_guide.txt"
      topics = metadata["topics"]
      assert "elixir" in topics
      assert "phoenix" in topics
      assert "web" in topics

      # Verify that topics were automatically assigned as tags
      all_tags = TagStorage.get_all_tags()
      file_tags = Map.get(all_tags, "comprehensive_guide.txt", [])

      # All extracted topics should be present as tags
      for topic <- topics do
        assert topic in file_tags, "Topic '#{topic}' should be assigned as a tag"
      end

      assert length(file_tags) == length(topics), "Number of tags should match number of topics"
    end

    test "handles empty or invalid topics gracefully" do
      # Test extraction with content that produces no specific topics
      empty_content = "This is some very generic content without technical terms."

      {:ok, pid} = Extractor.enqueue("empty_topics_test.txt", empty_content)

      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      Process.sleep(200)

      # Should assign "general" as the topic/tag when no specific topics found
      all_tags = TagStorage.get_all_tags()
      file_tags = Map.get(all_tags, "empty_topics_test.txt", [])
      assert file_tags == ["general"], "Should assign 'general' tag when no specific topics found"
    end

    test "assigns topics from content that contains multiple tech terms" do
      # Test content that should generate multiple topics
      content = """
      This guide covers Phoenix LiveView development with Elixir and testing strategies.
      We'll explore web development patterns, API design, and database integration.
      """

      filename = "multi_topic_test.txt"
      {:ok, pid} = Extractor.enqueue(filename, content)

      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        5000 -> flunk("Task did not complete within 5 seconds")
      end

      Process.sleep(200)

      # Verify that multiple topics were detected and assigned as tags
      all_tags = TagStorage.get_all_tags()
      file_tags = Map.get(all_tags, filename, [])

      # Should include all detected topics
      assert "elixir" in file_tags
      assert "phoenix" in file_tags
      assert "liveview" in file_tags
      assert "web" in file_tags
      assert "api" in file_tags
      assert "testing" in file_tags

      # Verify metadata contains the same topics
      metadata = TagStorage.get_extraction(filename)
      metadata_topics = metadata["topics"]

      # All topics in metadata should be present as tags
      for topic <- metadata_topics do
        assert topic in file_tags, "Topic '#{topic}' should be assigned as a tag"
      end
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
        "wordCount",
        "estimatedReadTime",
        "difficulty",
        "extractionMethod"
      ]

      for field <- required_fields do
        assert Map.has_key?(metadata, field), "Missing field: #{field}"
      end

      # Check that extractedAt is a valid ISO8601 timestamp
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(metadata["extractedAt"])
    end
  end
end
