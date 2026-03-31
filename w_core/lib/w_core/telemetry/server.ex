defmodule WCore.Telemetry.Server do
  use GenServer
  
  @table :w_core_telemetry_cache


  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def ingest(node_id, status, payload) do
    GenServer.cast(__MODULE__, {:ingest, node_id, status, payload})
  end


  @impl true
  def init(state) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest, node_id, status, payload}, state) do
    timestamp = DateTime.utc_now()
    
    :ets.insert(@table, {node_id, status, payload, timestamp})
    
    {:noreply, state}
  end
end