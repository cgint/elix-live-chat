defmodule LiveAiChatWeb.Plugs.RequireAuth do
  @moduledoc """
  A plug that requires users to be authenticated.

  If the user is not authenticated (no user in session), they are redirected
  to the Google OAuth login flow. This plug should be added to pipelines that
  require authentication.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2, put_flash: 3]

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
        case get_session(conn, :user) do
      nil ->
        Logger.info("Unauthenticated request to #{conn.request_path}, redirecting to login page")

        conn
        |> put_flash(:info, "Please sign in to continue.")
        |> redirect(to: "/login")
        |> halt()

      _user ->
        # User is authenticated, continue with the request
        conn
    end
  end
end
