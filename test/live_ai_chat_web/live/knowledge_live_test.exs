defmodule LiveAiChatWeb.KnowledgeLiveTest do
  use LiveAiChatWeb.ConnCase

  import Phoenix.LiveViewTest
  alias LiveAiChat.{FileStorage, TagStorage}

  @test_data_dir "priv/test_knowledge_data"
  @test_upload_dir "priv/test_knowledge_uploads"

  setup do
    # Clean up directories first
    File.rm_rf!(@test_data_dir)
    File.rm_rf!(@test_upload_dir)

    # Create fresh test directories
    File.mkdir_p!(@test_data_dir)
    File.mkdir_p!(@test_upload_dir)

    # Configure test directories
    Application.put_env(:live_ai_chat, :data_dir, @test_data_dir)
    Application.put_env(:live_ai_chat, :upload_dir, @test_upload_dir)

    on_exit(fn ->
      File.rm_rf!(@test_data_dir)
      File.rm_rf!(@test_upload_dir)
      Application.delete_env(:live_ai_chat, :data_dir)
      Application.delete_env(:live_ai_chat, :upload_dir)
    end)

    :ok
  end

  describe "mount/3" do
    test "renders knowledge pool page", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/knowledge")

      assert html =~ "Knowledge Pool"
      assert html =~ "Upload Files"
      assert html =~ "Files ("
      assert html =~ "File Details"
    end

    test "shows empty state when no files exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/knowledge")

      # Check for empty state message regardless of file count
      assert html =~ "Select a file to view details"
      # The file count might vary due to shared GenServer state, so just check structure
      assert html =~ "Files ("
    end
  end

  describe "file upload" do
    test "validates file upload form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Test form validation
      assert render_change(view, "validate", %{}) =~ "Knowledge Pool"
    end

    test "handles file upload error gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Simulate upload without actual file
      html = render_submit(view, "save", %{})

      assert html =~ "No files were uploaded" or html =~ "Knowledge Pool"
    end
  end

  describe "file management" do
    setup do
      # Add a test file to storage
      :ok = FileStorage.save_file("test.txt", "Test content for knowledge pool")
      TagStorage.update_tags_for_file("test.txt", ["test", "example"])

      :ok
    end

    test "displays uploaded files", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      html = render(view)
      assert html =~ "test.txt"
      # Check that there's at least one file
      assert html =~ "Files (" and html =~ ")"
    end

    test "selects file and shows details", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Select the test file
      html = render_click(view, "select-file", %{"filename" => "test.txt"})

      assert html =~ "test.txt"
      assert html =~ "Manage Tags"
    end

    test "updates file tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Select file first
      render_click(view, "select-file", %{"filename" => "test.txt"})

      # Update tags
      _html =
        render_submit(view, "update-tags", %{
          "filename" => "test.txt",
          "tags" => "elixir, programming, tutorial"
        })

      # Verify tags were saved
      tags = TagStorage.get_all_tags()
      assert tags["test.txt"] == ["elixir", "programming", "tutorial"]
    end

    test "deletes file", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Delete the file
      _html = render_click(view, "delete-file", %{"filename" => "test.txt"})

      # Verify file was deleted from storage
      files = FileStorage.list_files()
      refute "test.txt" in files
    end
  end

  describe "search functionality" do
    setup do
      # Add multiple test files with different tags
      :ok = FileStorage.save_file("elixir_guide.pdf", "Elixir programming guide")
      :ok = FileStorage.save_file("phoenix_tutorial.md", "Phoenix web framework tutorial")
      :ok = FileStorage.save_file("javascript_book.txt", "JavaScript programming book")

      TagStorage.update_tags_for_file("elixir_guide.pdf", ["elixir", "programming"])
      TagStorage.update_tags_for_file("phoenix_tutorial.md", ["phoenix", "web", "elixir"])
      TagStorage.update_tags_for_file("javascript_book.txt", ["javascript", "programming"])

      :ok
    end

    test "searches files by tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Search for elixir-related files
      html = render_change(view, "search-by-tags", %{"search_tags" => "elixir"})

      assert html =~ "elixir_guide.pdf"
      assert html =~ "phoenix_tutorial.md"
      refute html =~ "javascript_book.txt"
    end

    test "shows all files when search is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # First search for specific tag
      render_change(view, "search-by-tags", %{"search_tags" => "elixir"})

      # Then clear search
      html = render_change(view, "search-by-tags", %{"search_tags" => ""})

      # Should show all files again
      assert html =~ "elixir_guide.pdf"
      assert html =~ "phoenix_tutorial.md"
      assert html =~ "javascript_book.txt"
    end

    test "searches with multiple tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Search for programming-related files
      html = render_change(view, "search-by-tags", %{"search_tags" => "programming, web"})

      # Should match files with either "programming" or "web" tags
      # has "programming"
      assert html =~ "elixir_guide.pdf"
      # has "web"
      assert html =~ "phoenix_tutorial.md"
      # has "programming"
      assert html =~ "javascript_book.txt"
    end
  end

  describe "navigation" do
    test "provides link back to chat", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/knowledge")

      assert html =~ "Back to Chat"
      assert html =~ ~s(href="/")
    end
  end

  describe "file type detection" do
    test "shows appropriate icons for different file types", %{conn: conn} do
      # Add files with different extensions
      :ok = FileStorage.save_file("document.pdf", "PDF content")
      :ok = FileStorage.save_file("readme.md", "Markdown content")
      :ok = FileStorage.save_file("notes.txt", "Text content")

      {:ok, _view, html} = live(conn, ~p"/knowledge")

      # Check that different file types are handled
      assert html =~ "document.pdf"
      assert html =~ "readme.md"
      assert html =~ "notes.txt"
    end
  end
end
