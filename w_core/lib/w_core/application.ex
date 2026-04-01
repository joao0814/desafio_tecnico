defmodule WCore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WCoreWeb.Telemetry,
      WCore.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:w_core, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:w_core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WCore.PubSub},
      WCore.Telemetry.Ingestor,
      WCore.Telemetry.FlushWorker,
      WCoreWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: WCore.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    WCoreWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    System.get_env("RELEASE_NAME") == nil
  end
end
