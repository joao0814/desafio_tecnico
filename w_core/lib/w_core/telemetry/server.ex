defmodule WCore.Telemetry.Server do
  @moduledoc """
  Backwards-compatible facade for `WCore.Telemetry.Ingestor`.

  Keep this module so existing callers using `WCore.Telemetry.Server` continue to work.
  """

  @doc """
  Ingest a sensor event asynchronously.
  """
  def ingest(node_id, status, payload) do
    WCore.Telemetry.Ingestor.ingest(node_id, status, payload)
  end

  @doc """
  Synchronization barrier used by tests.
  """
  def sync do
    WCore.Telemetry.Ingestor.sync()
  end
end