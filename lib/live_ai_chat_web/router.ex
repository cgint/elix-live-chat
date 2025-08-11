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

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LiveAiChatWeb do
    pipe_through :browser

    live_session :default, session: {__MODULE__, :session_values, []} do
      live "/", ChatLive
      live "/chat/:chat_id", ChatLive
      live "/knowledge", KnowledgeLive
    end
  end

  # Return a map of values to put in the live session. We only forward
  # test_pid if present in the Plug session so normal runtime is unaffected.
  def session_values(%Plug.Conn{private: %{plug_session: plug_session}}) do
    case Map.get(plug_session, "test_pid") do
      nil -> %{}
      pid -> %{"test_pid" => pid}
    end
  end

  def session_values(_conn), do: %{}

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
