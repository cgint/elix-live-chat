defmodule LiveAiChatWeb.AuthController do
  use LiveAiChatWeb, :controller

  plug Ueberauth

  require Logger

  def request(conn, _params) do
    # This action initiates the OAuth flow - Ueberauth handles the redirect
    redirect(conn, external: Ueberauth.Strategy.Helpers.callback_url(conn))
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.info("Google OAuth callback received for email: #{auth.info.email}")

    # Extract user information from Google OAuth response
    user = %{
      sub: auth.uid,
      email: auth.info.email,
      name: auth.info.name,
      picture: auth.info.image
    }

    # Store user in session and redirect to home page
    conn
    |> put_session(:user, user)
    |> put_flash(:info, "Successfully signed in with Google!")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_failure: failure}} = conn, _params) do
    Logger.error("Google OAuth failed: #{inspect(failure)}")

    conn
    |> put_flash(:error, "Authentication failed. Please try again.")
    |> redirect(to: ~p"/")
  end

  def logout(conn, _params) do
    Logger.info("User logging out")

    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "You have been logged out.")
    |> redirect(to: ~p"/")
  end
end
