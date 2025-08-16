defmodule LiveAiChatWeb.Plugs.RequireAuthTest do
  use LiveAiChatWeb.ConnCase, async: true

  alias LiveAiChatWeb.Plugs.RequireAuth

  describe "RequireAuth plug" do
    test "redirects to Google OAuth when user is not in session", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> fetch_flash()
        |> RequireAuth.call(RequireAuth.init([]))

      assert redirected_to(conn) == "/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Please sign in to continue."
    end

    test "allows request to continue when user is in session", %{conn: conn} do
      user = %{sub: "123", email: "test@example.com", name: "Test User"}

      conn =
        conn
        |> init_test_session(%{})
        |> put_session(:user, user)
        |> RequireAuth.call(RequireAuth.init([]))

      refute conn.halted
    end
  end
end
