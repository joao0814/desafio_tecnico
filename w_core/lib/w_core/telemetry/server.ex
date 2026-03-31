defmodule WCore.Telemetry.Server do
  @moduledoc """
  Telemetry Event Ingestor — absorbs sensor events into ETS before batch persistence.
  
  This is the hot path: receives events via GenServer.cast, inserts into ETS (O(1)),
  increments counters atomically, and broadcasts to PubSub for real-time UI updates.
  
  ETS configuration:
    - :set → unique keys (one metric per node_id at any time)
    - :public → all processes can read/write directly
    - :named_table → access via atom instead of ETS id
    - read_concurrency: true → readers don't block writers
    - write_concurrency: true → multiple writers in parallel
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
  
  Returns immediately; processing happens in the GenServer mailbox.
  """
  def ingest(node_id, status, payload) do
    GenServer.cast(__MODULE__, {:ingest, node_id, status, payload})
  end

  @impl true
  def init(state) do
    # Create ETS table for telemetry cache
    :ets.new(@table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    Logger.info("Telemetry.Server started — ETS cache initialized")
    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest, node_id, status, payload}, state) do
    timestamp = DateTime.utc_now()
    
    # Build entry: {node_id, status, payload, timestamp, event_count}
    entry = {node_id, status, payload, timestamp, 0}
    
    case :ets.insert_new(@table, entry) do
      true ->
        # Key doesn't exist yet — fresh insert with count=0, then increment to 1
        :ets.update_counter(@table, node_id, {5, 1})
      false ->
        # Key exists — update only the relevant fields, preserve counter
        [{_, _, _, _, count}] = :ets.lookup(@table, node_id)
        :ets.insert(@table, {node_id, status, payload, timestamp, count + 1})
    end
    
    # Broadcast to PubSub for real-time subscribers (LiveView, etc)
    broadcast_metric_ingested(node_id, status, payload)
    
    {:noreply, state}
  end

  defp broadcast_metric_ingested(node_id, status, payload) do
    # Broadcast on a generic metrics topic
    # LiveView can subscribe to "telemetry:metrics" for real-time updates
    message = {:metric_ingested, node_id, status, payload, DateTime.utc_now()}
    
    Phoenix.PubSub.broadcast(
      @pubsub,
      "telemetry:metrics",
      message
    )
    
    # Also broadcast per-node topic for filtered subscriptions
    Phoenix.PubSub.broadcast(
      @pubsub,
      "telemetry:node:#{node_id}",
      message
    )
  end
end