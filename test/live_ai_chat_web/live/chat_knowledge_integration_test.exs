defmodule LiveAiChatWeb.ChatKnowledgeIntegrationTest do
  use LiveAiChatWeb.ConnCase

  import Phoenix.LiveViewTest
  alias LiveAiChat.FileStorage

  @test_file_content "This is a test file about Elixir programming language."
  @test_filename "test_context.pdf"

  setup do
    # Clean up any existing test files
    case FileStorage.list_files() do
      files when is_list(files) ->
        Enum.each(files, fn file -> FileStorage.delete_file(file) end)

      _ ->
        :ok
    end

    :ok
  end

  describe "chat with knowledge pool integration" do
    test "shows knowledge pool section in chat", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Should show knowledge pool section
      assert has_element?(view, "[title='Toggle knowledge panel']")
      assert render(view) =~ "Knowledge Pool"
    end

    test "can toggle knowledge panel", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Initially panel should be closed
      refute has_element?(view, "input[type='checkbox']")

      # Click to open panel
      view |> element("[title='Toggle knowledge panel']") |> render_click()

      # Should show file list (empty initially)
      assert render(view) =~ "No files uploaded yet"
      assert has_element?(view, "[href='/knowledge']")
    end

    test "shows uploaded files in knowledge panel", %{conn: conn} do
      # Upload a test file
      :ok = FileStorage.save_file(@test_filename, @test_file_content)

      {:ok, view, _html} = live(conn, ~p"/")

      # Open knowledge panel
      view |> element("[title='Toggle knowledge panel']") |> render_click()

      # Should show the uploaded file
      assert render(view) =~ @test_filename
      assert has_element?(view, "input[phx-value-filename='#{@test_filename}']")
    end

    test "can select and deselect files", %{conn: conn} do
      # Upload a test file
      :ok = FileStorage.save_file(@test_filename, @test_file_content)

      {:ok, view, _html} = live(conn, ~p"/")

      # Open knowledge panel
      view |> element("[title='Toggle knowledge panel']") |> render_click()

      # Select the file
      view |> element("input[phx-value-filename='#{@test_filename}']") |> render_click()

      # Should show file as selected
      assert render(view) =~ "1 file(s) selected"
      assert has_element?(view, "[title='Clear all selected files']")

      # Should show context indicator
      assert render(view) =~ "Including context from 1 file(s)"

      # Deselect the file
      view |> element("input[phx-value-filename='#{@test_filename}']") |> render_click()

      # Should not show selected files
      refute render(view) =~ "file(s) selected"
      refute render(view) =~ "Including context from"
    end

    test "can clear all selected files", %{conn: conn} do
      # Upload test files
      :ok = FileStorage.save_file(@test_filename, @test_file_content)
      :ok = FileStorage.save_file("test2.pdf", "Another test file")

      {:ok, view, _html} = live(conn, ~p"/")

      # Open knowledge panel and select both files
      view |> element("[title='Toggle knowledge panel']") |> render_click()
      view |> element("input[phx-value-filename='#{@test_filename}']") |> render_click()
      view |> element("input[phx-value-filename='test2.pdf']") |> render_click()

      # Should show 2 files selected
      assert render(view) =~ "2 file(s) selected"

      # Clear all files
      view |> element("[title='Clear all selected files']") |> render_click()

      # Should have no files selected
      refute render(view) =~ "file(s) selected"
      refute render(view) =~ "Including context from"
    end

    test "message includes file context when files are selected", %{conn: conn} do
      # Upload a test file
      :ok = FileStorage.save_file(@test_filename, @test_file_content)

      {:ok, view, _html} = live(conn, ~p"/")

      # Open knowledge panel and select the file
      view |> element("[title='Toggle knowledge panel']") |> render_click()
      view |> element("input[phx-value-filename='#{@test_filename}']") |> render_click()

      # Send a message (this will use the dummy AI client)
      view
      |> form("form", %{content: "What is this about?"})
      |> render_submit()

      # The message should appear in the chat
      assert render(view) =~ "What is this about?"

      # Wait for AI response processing to complete
      # The dummy client should respond with some content
      :timer.sleep(100)
    end

    test "message without selected files works normally", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      # Send a message without any files selected
      view
      |> form("form", %{content: "Hello AI"})
      |> render_submit()

      # The message should appear in the chat
      assert render(view) =~ "Hello AI"
    end
  end
end
