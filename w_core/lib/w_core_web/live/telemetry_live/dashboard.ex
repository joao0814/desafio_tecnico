defmodule WCoreWeb.TelemetryLive.Dashboard do
  use WCoreWeb, :live_view

  alias WCore.Telemetry

  @table :w_core_telemetry_cache
  @ui_batch_window_ms 400

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    nodes = Telemetry.list_nodes(scope)
    node_ids = MapSet.new(Enum.map(nodes, & &1.id))
    node_names = Map.new(nodes, fn node -> {node.id, node.machine_identifier} end)

    if connected?(socket) do
      Enum.each(node_ids, fn node_id ->
        Phoenix.PubSub.subscribe(WCore.PubSub, "telemetry:node:#{node_id}")
      end)
    end

    {:ok,
     socket
     |> assign(:page_title, "Telemetry Dashboard")
     |> assign(:node_ids, node_ids)
     |> assign(:node_names, node_names)
     |> assign(:refresh_scheduled, false)
     |> assign(:metrics, read_metrics_from_ets(node_ids))}
  end

  @impl true
  def handle_info({:metric_ingested, node_id, _status, _payload, _ts}, socket) do
    if MapSet.member?(socket.assigns.node_ids, node_id) do
      maybe_schedule_refresh(socket)
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refresh_ui, socket) do
    {:noreply,
     socket
     |> assign(:metrics, read_metrics_from_ets(socket.assigns.node_ids))
     |> assign(:refresh_scheduled, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />

    <section class="mx-auto max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
      <header class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold">Telemetry Dashboard</h1>
          <p class="text-sm text-base-content/70">
            Live updates via PubSub without polling.
          </p>
        </div>
      </header>

      <%= if @metrics == [] do %>
        <div class="rounded-box border border-base-300 bg-base-100 p-6">
          <p class="text-sm text-base-content/70">
            No telemetry yet for your nodes.
          </p>
        </div>
      <% else %>
        <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
          <table class="table">
            <thead>
              <tr>
                <th>Node</th>
                <th>Status</th>
                <th>Total Events</th>
                <th>Last Seen</th>
                <th>Payload</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={metric <- @metrics} id={"metric-#{metric.node_id}"}>
                <td>
                  <div class="font-medium"><%= Map.get(@node_names, metric.node_id, "node-#{metric.node_id}") %></div>
                  <div class="text-xs text-base-content/60">ID: <%= metric.node_id %></div>
                </td>
                <td>
                  <span class="badge badge-outline"><%= metric.status %></span>
                </td>
                <td><%= metric.total_events_processed %></td>
                <td><%= Calendar.strftime(metric.last_seen_at, "%Y-%m-%d %H:%M:%S") %> UTC</td>
                <td class="max-w-xs truncate"><%= inspect(metric.last_payload) %></td>
              </tr>
            </tbody>
          </table>
        </div>
      <% end %>
    </section>
    """
  end

  defp maybe_schedule_refresh(%{assigns: %{refresh_scheduled: true}} = socket), do: {:noreply, socket}

  defp maybe_schedule_refresh(socket) do
    Process.send_after(self(), :refresh_ui, @ui_batch_window_ms)
    {:noreply, assign(socket, :refresh_scheduled, true)}
  end

  defp read_metrics_from_ets(node_ids) do
    if :ets.whereis(@table) == :undefined do
      []
    else
      @table
      |> :ets.tab2list()
      |> Enum.filter(fn {node_id, _status, _payload, _last_seen_at, _count} ->
        MapSet.member?(node_ids, node_id)
      end)
      |> Enum.map(fn {node_id, status, last_payload, last_seen_at, total_events_processed} ->
        %{
          node_id: node_id,
          status: status,
          last_payload: last_payload,
          last_seen_at: last_seen_at,
          total_events_processed: total_events_processed
        }
      end)
      |> Enum.sort_by(& &1.last_seen_at, {:desc, DateTime})
    end
  end
end
