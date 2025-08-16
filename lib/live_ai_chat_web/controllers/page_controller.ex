defmodule LiveAiChatWeb.PageController do
  use LiveAiChatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def serve_file(conn, %{"filename" => filename}) do
    safe_filename = Path.basename(filename)

    case LiveAiChat.FileStorage.read_file(safe_filename) do
      {:ok, file_binary} ->
        content_type =
          case Path.extname(String.downcase(safe_filename)) do
            ".pdf" -> "application/pdf"
            ".mht" -> "message/rfc822"
            ".mhtml" -> "message/rfc822"
            _ -> "application/octet-stream"
          end

        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("content-disposition", "inline; filename=\"#{safe_filename}\"")
        |> send_resp(200, file_binary)

      {:error, :enoent} ->
        conn
        |> put_status(:not_found)
        |> put_view(html: LiveAiChatWeb.ErrorHTML)
        |> render(:"404")

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> put_view(html: LiveAiChatWeb.ErrorHTML)
        |> render(:"500")
    end
  end
end
