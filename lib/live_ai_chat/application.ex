defmodule LiveAiChat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        LiveAiChatWeb.Telemetry,
        {DNSCluster, query: Application.get_env(:live_ai_chat, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: LiveAiChat.PubSub},
        # Start a worker by calling: LiveAiChat.Worker.start_link(arg)
        # {LiveAiChat.Worker, arg},
        # Start Goth for Google Cloud authentication
        {Goth, name: LiveAiChat.Goth, source: goth_source()},
        # Start the ChatStorageAdapter GenServer (needed for chat tests as well)
        LiveAiChat.ChatStorageAdapter,
        # Start the new ChatStorage GenServer
        LiveAiChat.ChatStorage
      ] ++
        extra_storage_children() ++
        [
          # Start the Task supervisor for AI tasks
          {Task.Supervisor, name: LiveAiChat.TaskSupervisor},
          # Start to serve requests, typically the last entry
          LiveAiChatWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LiveAiChat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LiveAiChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp goth_source do
    # First try explicit service account JSON from environment
    if service_account_json = System.get_env("GOOGLE_SERVICE_ACCOUNT_JSON") do
      {:service_account, Jason.decode!(service_account_json)}
    else
      # Fall back to application default credentials (works with both service account and user credentials)
      case System.get_env("GOOGLE_APPLICATION_CREDENTIALS") do
        nil ->
          # Use gcloud application default credentials if available
          default_creds_path =
            Path.join([
              System.user_home!(),
              ".config",
              "gcloud",
              "application_default_credentials.json"
            ])

          if File.exists?(default_creds_path) do
            {:refresh_token, File.read!(default_creds_path) |> Jason.decode!()}
          else
            raise """
            Google Cloud authentication not configured.

            Please run one of the following:

            1. Quick setup with gcloud CLI:
               export VERTEXAI_PROJECT="gen-lang-client-0910640178"
               export VERTEXAI_LOCATION="europe-west1"
               gcloud auth application-default login

            2. Or use a service account key:
               export GOOGLE_APPLICATION_CREDENTIALS="path/to/service-account.json"

            3. Or set service account JSON directly:
               export GOOGLE_SERVICE_ACCOUNT_JSON='{"type": "service_account", ...}'
            """
          end

        credentials_path ->
          # Use specified credentials file
          creds = File.read!(credentials_path) |> Jason.decode!()

          case creds["type"] do
            "service_account" -> {:service_account, creds}
            "authorized_user" -> {:refresh_token, creds}
            _ -> raise "Unsupported credential type: #{creds["type"]}"
          end
      end
    end
  end

  # -- Helpers ------------------------------------------------------------

  # In the test environment we let individual tests start FileStorage and
  # TagStorage with their own (temporary) configuration to avoid leaking
  # state between tests. In all other environments we start them under the
  # supervision tree as normal.
  defp extra_storage_children do
    [
      LiveAiChat.FileStorage,
      LiveAiChat.TagStorage
    ]
  end
end
