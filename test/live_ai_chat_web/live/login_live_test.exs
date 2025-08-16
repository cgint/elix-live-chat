defmodule LiveAiChatWeb.LoginLiveTest do
  use LiveAiChatWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "LoginLive" do
    test "renders login page for unauthenticated users", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ "Welcome to LiveAiChat"
      assert html =~ "Sign in with Google"
      assert html =~ "Sign in to start chatting"
    end

    test "redirects authenticated users to home page", %{conn: conn} do
      user = %{sub: "123", email: "test@example.com", name: "Test User"}

      conn =
        conn
        |> init_test_session(%{user: user})

      assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/login")
    end

    test "contains Google OAuth link", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/login")

      assert html =~ ~s(href="/auth/google")
    end
  end
end
