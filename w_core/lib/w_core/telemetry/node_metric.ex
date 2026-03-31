defmodule WCore.Telemetry.NodeMetric do
  use Ecto.Schema
  import Ecto.Changeset

  schema "node_metrics" do
    field :status, :string
    field :total_events_processed, :integer
    field :last_payload, :map
    field :last_seen_at, :utc_datetime
    field :node_id, :id
    # field :user_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(node_metric, attrs ) do
    node_metric
    |> cast(attrs, [:status, :total_events_processed, :last_payload, :last_seen_at, :node_id])
    |> validate_required([:status, :total_events_processed, :last_seen_at, :node_id])
    |> foreign_key_constraint(:node_id)
    |> unique_constraint(:node_id)
  end
end
