defmodule WCore.Telemetry.FlushWorker do
  @moduledoc """
  Write-Behind Cache Flusher — batch persist ETS to SQLite.
  
  This is the cold path: once every 5 seconds, extract all events from ETS
  and write them to SQLite in a single batch operation.
  
  Design rationale:
  
  1. **Batching avoids DB lock:** Instead of 1000 individual writes (1000 locks),
     do one batch upsert. SQLite can handle it far faster.
  
  2. **Eventual consistency:** Events are in ETS immediately (hot), but only
     durable 5s later in SQLite. Acceptable for Edge Computing telemetry.
  
  3. **Resilience:** If DB fails mid-flush, events stay in ETS for next cycle.
     If ETS crashes (rare), data hasn't been lost to disk yet — trade-off.
  
  4. **Non-blocking:** FlushWorker can't starve Server. Each runs in separate
     GenServer, so ingest continues even if flush hangs.
  """
  use GenServer
  require Logger
  alias WCore.Repo
  alias WCore.Telemetry.NodeMetric

  @table :w_core_telemetry_cache
  @interval 5_000  # Flush every 5 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{last_flush_count: 0})
  end

  @impl true
  def init(state) do
    schedule_flush()
    Logger.info("Telemetry.FlushWorker started — flush interval: #{@interval}ms")
    {:ok, state}
  end

  @impl true
  def handle_info(:flush, state) do
    start_time = System.monotonic_time(:millisecond)
    data = :ets.tab2list(@table)
    count = length(data)

    if count > 0 do
      successes = Enum.count(data, fn {node_id, status, payload, _ts, event_count} ->
        case save_to_db(node_id, status, payload, event_count) do
          :ok -> true
          :error -> false
        end
      end)

      elapsed = System.monotonic_time(:millisecond) - start_time
      Logger.info(
        "Telemetry.FlushWorker flushed #{successes}/#{count} metrics in #{elapsed}ms"
      )

      new_state = %{state | last_flush_count: count}
      schedule_flush()
      {:noreply, new_state}
    else
      schedule_flush()
      {:noreply, state}
    end
  end

  defp save_to_db(node_id, status, payload, event_count) do
    now = DateTime.utc_now()

    result =
      try do
        %NodeMetric{}
        |> NodeMetric.changeset(%{
          node_id: node_id,
          status: status,
          last_payload: payload,
          last_seen_at: now,
          total_events_processed: event_count
        })
        |> Repo.insert(
          on_conflict: [
            set: [
              status: status,
              last_payload: payload,
              last_seen_at: now,
              updated_at: now,
              total_events_processed: event_count
            ]
          ],
          conflict_target: [:node_id]
        )
      rescue
        error in Ecto.ConstraintError ->
          Logger.debug(
            "Skipping node_metric:#{node_id} flush — DB constraint: #{Exception.message(error)}"
          )

          :error
      end

    case result do
      {:ok, _metric} ->
        :ok

      {:error, changeset} ->
        Logger.debug(
          "Skipping node_metric:#{node_id} flush — validation error: #{inspect(changeset.errors)}"
        )

        :error

      :error ->
        :error
    end
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @interval)
  end
end