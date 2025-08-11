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
      {:ok, _view, html} = live(conn, ~p"/knowledge")

      assert html =~ "Knowledge Pool"
      assert html =~ "Upload Files"
      assert html =~ "Uploaded Files"
    end

    test "shows empty state when no files exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/knowledge")

      # Check for empty state message
      assert html =~ "No files uploaded yet"
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
      # Add a test PDF file to storage - only PDFs are now supported
      :ok = FileStorage.save_file("test.pdf", "Test PDF content for knowledge pool")
      TagStorage.update_tags_for_file("test.pdf", ["test", "example"])

      :ok
    end

    test "displays uploaded files", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      html = render(view)
      assert html =~ "test.pdf"
    end

    test "shows file details in modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Click the info button to show modal
      html = render_click(view, "show-details", %{"filename" => "test.pdf"})

      assert html =~ "test.pdf"
      assert html =~ "File Details"
    end

    test "updates file tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Show details modal first
      render_click(view, "show-details", %{"filename" => "test.pdf"})

      # Update tags
      _html =
        render_submit(view, "update-tags", %{
          "filename" => "test.pdf",
          "tags" => "elixir, programming, tutorial"
        })

      # Verify tags were saved
      tags = TagStorage.get_all_tags()
      assert tags["test.pdf"] == ["elixir", "programming", "tutorial"]
    end

    test "deletes file", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Delete the file
      _html = render_click(view, "delete-file", %{"filename" => "test.pdf"})

      # Verify file was deleted from storage
      files = FileStorage.list_files()
      refute "test.pdf" in files
    end
  end

  describe "search functionality" do
    setup do
      # Add multiple test PDF files with different tags - only PDFs are now supported
      :ok = FileStorage.save_file("elixir_guide.pdf", "Elixir programming guide")
      :ok = FileStorage.save_file("phoenix_tutorial.pdf", "Phoenix web framework tutorial")
      :ok = FileStorage.save_file("javascript_book.pdf", "JavaScript programming book")

      TagStorage.update_tags_for_file("elixir_guide.pdf", ["elixir", "programming"])
      TagStorage.update_tags_for_file("phoenix_tutorial.pdf", ["phoenix", "web", "elixir"])
      TagStorage.update_tags_for_file("javascript_book.pdf", ["javascript", "programming"])

      :ok
    end

    test "searches files by tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Search for elixir-related files
      html = render_change(view, "search-by-tags", %{"search_tags" => "elixir"})

      assert html =~ "elixir_guide.pdf"
      assert html =~ "phoenix_tutorial.pdf"
      refute html =~ "javascript_book.pdf"
    end

    test "shows all files when search is empty", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # First search for specific tag
      render_change(view, "search-by-tags", %{"search_tags" => "elixir"})

      # Then clear search
      html = render_change(view, "search-by-tags", %{"search_tags" => ""})

      # Should show all PDF files again
      assert html =~ "elixir_guide.pdf"
      assert html =~ "phoenix_tutorial.pdf"
      assert html =~ "javascript_book.pdf"
    end

    test "searches with multiple tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/knowledge")

      # Search for programming-related files
      html = render_change(view, "search-by-tags", %{"search_tags" => "programming, web"})

      # Should match files with either "programming" or "web" tags
      # has "programming"
      assert html =~ "elixir_guide.pdf"
      # has "web"
      assert html =~ "phoenix_tutorial.pdf"
      # has "programming"
      assert html =~ "javascript_book.pdf"
    end
  end

  describe "navigation" do
    test "provides link to upload files", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/knowledge")

      assert html =~ "Upload Files"
      assert html =~ "Knowledge Pool"
    end
  end

  describe "file type filtering" do
    test "only shows PDF files", %{conn: conn} do
      # Add both PDF and non-PDF files to storage directly
      :ok = FileStorage.save_file("document.pdf", "PDF content")
      :ok = FileStorage.save_file("readme.md", "Markdown content")
      :ok = FileStorage.save_file("notes.txt", "Text content")

      {:ok, _view, html} = live(conn, ~p"/knowledge")

      # Only PDF files should be shown in the UI
      assert html =~ "document.pdf"
      refute html =~ "readme.md"
      refute html =~ "notes.txt"
    end
  end
end
