defmodule LiveAiChatWeb.Router do
  use LiveAiChatWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LiveAiChatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :protected do
    plug :browser
    plug LiveAiChatWeb.Plugs.RequireAuth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/auth", LiveAiChatWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/logout", AuthController, :logout
  end

  scope "/", LiveAiChatWeb do
    pipe_through :browser

    live_session :public, session: {__MODULE__, :session_values, []} do
      live "/login", LoginLive
    end
  end

  scope "/", LiveAiChatWeb do
    pipe_through :protected

    live_session :default, session: {__MODULE__, :session_values, []} do
      live "/", ChatLive
      live "/chat/:chat_id", ChatLive
      live "/knowledge", KnowledgeLive
    end

    # Route for serving uploaded PDF files
    get "/files/:filename", PageController, :serve_file
  end

  # Return a map of values to put in the live session. We forward both user
  # and test_pid if present in the Plug session.
  def session_values(%Plug.Conn{private: %{plug_session: plug_session}}) do
    %{}
    |> maybe_put("user", Map.get(plug_session, "user"))
    |> maybe_put("test_pid", Map.get(plug_session, "test_pid"))
  end

  def session_values(_conn), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  # Other scopes may use custom stacks.
  # scope "/api", LiveAiChatWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:live_ai_chat, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LiveAiChatWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
