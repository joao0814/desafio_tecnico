defmodule WCore.Telemetry.Ingestor do
  @moduledoc """
  Telemetry Event Ingestor — absorbs sensor events into ETS before batch persistence.

  This is the hot path: receives events via GenServer.cast, inserts into ETS (O(1)),
  increments counters, and broadcasts to PubSub for real-time UI updates.
  """
  use GenServer
  require Logger

  @table :w_core_telemetry_cache
  @pubsub WCore.PubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Ingest a sensor event asynchronously.
  """
  def ingest(node_id, status, payload) do
    GenServer.cast(__MODULE__, {:ingest, node_id, status, payload})
  end

  @doc """
  Synchronization barrier for tests and maintenance operations.

  Returns only after all previously queued casts are processed.
  """
  def sync do
    GenServer.call(__MODULE__, :sync, 30_000)
  end

  @impl true
  def init(state) do
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    Logger.info("Telemetry.Ingestor started — ETS cache initialized")
    {:ok, state}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:ingest, node_id, status, payload}, state) do
    timestamp = DateTime.utc_now()

    :ets.update_counter(@table, node_id, {5, 1}, {node_id, status, payload, timestamp, 0})
    :ets.update_element(@table, node_id, [{2, status}, {3, payload}, {4, timestamp}])

    broadcast_metric_ingested(node_id, status, payload)

    {:noreply, state}
  end

  defp broadcast_metric_ingested(node_id, status, payload) do
    message = {:metric_ingested, node_id, status, payload, DateTime.utc_now()}

    Phoenix.PubSub.broadcast(@pubsub, "telemetry:metrics", message)
    Phoenix.PubSub.broadcast(@pubsub, "telemetry:node:#{node_id}", message)
  end
end
