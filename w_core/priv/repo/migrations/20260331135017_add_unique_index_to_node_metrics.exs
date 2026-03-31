defmodule WCore.Repo.Migrations.AddUniqueIndexToNodeMetrics do
  use Ecto.Migration

  def change do
    drop_if_exists index(:node_metrics, [:node_id])
    create unique_index(:node_metrics, [:node_id], name: :node_metrics_node_id_index)
  end
end