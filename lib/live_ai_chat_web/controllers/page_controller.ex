defmodule LiveAiChatWeb.PageController do
  use LiveAiChatWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
