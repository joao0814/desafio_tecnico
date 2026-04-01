defmodule WCore.TelemetryChaosTest do
  use WCore.DataCase

  alias WCore.Repo
  alias WCore.Telemetry
  alias WCore.Telemetry.NodeMetric

  import WCore.AccountsFixtures, only: [user_scope_fixture: 0]

  @total_events 10_000
  @nodes_count 10

  test "handles 10_000 concurrent events with correct ETS and persisted counts" do
    scope = user_scope_fixture()

    node_ids =
      for idx <- 1..@nodes_count do
        {:ok, node} =
          Telemetry.create_node(scope, %{
            machine_identifier: "edge-node-#{idx}",
            location: "plant-42"
          })

        node.id
      end

    start_ms = System.monotonic_time(:millisecond)

    1..@total_events
    |> Task.async_stream(
      fn i ->
        node_id = Enum.at(node_ids, rem(i - 1, @nodes_count))
        WCore.Telemetry.Server.ingest(node_id, "ativo", %{seq: i})
      end,
      max_concurrency: System.schedulers_online() * 4,
      timeout: 30_000,
      ordered: false
    )
    |> Stream.run()

    # Ensure all queued async casts were processed before asserting counts.
    WCore.Telemetry.Server.sync()

    expected_per_node = div(@total_events, @nodes_count)

    assert wait_until(fn ->
             ets_total_count() == @total_events and
               Enum.all?(node_ids, fn node_id ->
                 ets_count_for_node(node_id) == expected_per_node
               end)
           end, 10_000), "ETS did not reach expected counts in time"

    flush_pid = flush_worker_pid()
    flush_start_ms = System.monotonic_time(:millisecond)
    send(flush_pid, :flush)

    assert wait_until(fn ->
             persisted_total_count(node_ids) == @total_events and
               Enum.all?(node_ids, fn node_id ->
                 persisted_count_for_node(node_id) == expected_per_node
               end)
           end, 10_000), "Persisted counts did not reach expected values in time"

    ingest_elapsed_ms = System.monotonic_time(:millisecond) - start_ms
    flush_elapsed_ms = System.monotonic_time(:millisecond) - flush_start_ms

    # Strong evidence metrics for chaos scenario
    assert ingest_elapsed_ms > 0
    assert flush_elapsed_ms > 0
  end

  defp ets_total_count do
    :ets.tab2list(:w_core_telemetry_cache)
    |> Enum.map(fn {_node_id, _status, _payload, _ts, count} -> count end)
    |> Enum.sum()
  end

  defp ets_count_for_node(node_id) do
    case :ets.lookup(:w_core_telemetry_cache, node_id) do
      [{^node_id, _status, _payload, _ts, count}] -> count
      [] -> 0
    end
  end

  defp persisted_total_count(node_ids) do
    from(m in NodeMetric, where: m.node_id in ^node_ids, select: sum(m.total_events_processed))
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp persisted_count_for_node(node_id) do
    from(m in NodeMetric, where: m.node_id == ^node_id, select: m.total_events_processed)
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp flush_worker_pid do
    WCore.Supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {WCore.Telemetry.FlushWorker, pid, :worker, _modules} when is_pid(pid) -> pid
      _ -> nil
    end)
    |> case do
      pid when is_pid(pid) -> pid
      _ -> flunk("Could not find WCore.Telemetry.FlushWorker pid")
    end
  end

  defp wait_until(fun, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_until(fun, deadline)
  end

  defp do_wait_until(fun, deadline) do
    if fun.() do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(50)
        do_wait_until(fun, deadline)
      end
    end
  end
end
