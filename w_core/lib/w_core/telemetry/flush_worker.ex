defmodule WCore.Telemetry.FlushWorker do
  use GenServer
  require Logger
  alias WCore.Repo
  alias WCore.Telemetry.NodeMetric

  @table :w_core_telemetry_cache
  @interval 5_000 

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  @impl true
  def init(state) do
    schedule_flush()
    {:ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    data = :ets.tab2list(@table)

    if data != [] do
      Enum.each(data, fn {node_id, status, payload, _ts} ->
        save_to_db(node_id, status, payload)
      end)
    end

    schedule_flush()
    {:noreply, state}
  end

  defp save_to_db(node_id, status, payload) do
    now = DateTime.utc_now()

    result =
      try do
        %NodeMetric{}
        |> NodeMetric.changeset(%{
          node_id: node_id,
          status: status,
          last_payload: payload,
          last_seen_at: now,
          total_events_processed: 1 
        })
        |> Repo.insert(
          on_conflict: [
            set: [status: status, last_payload: payload, last_seen_at: now, updated_at: now],
            inc: [total_events_processed: 1]
          ],
          conflict_target: [:node_id]
        )
      rescue
        error in Ecto.ConstraintError ->
          Logger.warning("Skipping node_metric flush due to DB constraint error: #{Exception.message(error)}")
          :error
      end

    result
    |> case do
      {:ok, _metric} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Skipping node_metric flush due to constraint/validation error: #{inspect(changeset.errors)}")
        :error

      :error ->
        :error
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @interval)
  end
end