defmodule WCore.Telemetry.Server do
  use GenServer
  
  @table :w_core_telemetry_cache

  # --- Interface (O que o resto do app chama) ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # Função para os sensores enviarem dados
  def ingest(node_id, status, payload) do
    GenServer.cast(__MODULE__, {:ingest, node_id, status, payload})
  end

  # --- Servidor (O que acontece por trás) ---

  @impl true
  def init(state) do
    # Criamos a tabela ETS: 
    # :set (chaves únicas), :public (todos leem/escrevem), :named_table (chamamos pelo nome)
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    {:ok, state}
  end

  @impl true
  def handle_cast({:ingest, node_id, status, payload}, state) do
    timestamp = DateTime.utc_now()
    
    # Salva no ETS (RAM) instantaneamente
    :ets.insert(@table, {node_id, status, payload, timestamp})
    
    # Aqui depois avisaremos o LiveView via PubSub!
    {:noreply, state}
  end
end