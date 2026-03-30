defmodule WCore.Telemetry do
  @moduledoc """
  The Telemetry context.
  """

  import Ecto.Query, warn: false
  alias WCore.Repo

  alias WCore.Telemetry.Node
  alias WCore.Accounts.Scope

  @doc """
  Subscribes to scoped notifications about any node changes.

  The broadcasted messages match the pattern:

    * {:created, %Node{}}
    * {:updated, %Node{}}
    * {:deleted, %Node{}}

  """
  def subscribe_nodes(%Scope{} = scope) do
    key = scope.user.id

    Phoenix.PubSub.subscribe(WCore.PubSub, "user:#{key}:nodes")
  end

  defp broadcast_node(%Scope{} = scope, message) do
    key = scope.user.id

    Phoenix.PubSub.broadcast(WCore.PubSub, "user:#{key}:nodes", message)
  end

  @doc """
  Returns the list of nodes.

  ## Examples

      iex> list_nodes(scope)
      [%Node{}, ...]

  """
  def list_nodes(%Scope{} = scope) do
    Repo.all_by(Node, user_id: scope.user.id)
  end

  @doc """
  Gets a single node.

  Raises `Ecto.NoResultsError` if the Node does not exist.

  ## Examples

      iex> get_node!(scope, 123)
      %Node{}

      iex> get_node!(scope, 456)
      ** (Ecto.NoResultsError)

  """
  def get_node!(%Scope{} = scope, id) do
    Repo.get_by!(Node, id: id, user_id: scope.user.id)
  end

  @doc """
  Creates a node.

  ## Examples

      iex> create_node(scope, %{field: value})
      {:ok, %Node{}}

      iex> create_node(scope, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_node(%Scope{} = scope, attrs) do
    with {:ok, node = %Node{}} <-
           %Node{}
           |> Node.changeset(attrs, scope)
           |> Repo.insert() do
      broadcast_node(scope, {:created, node})
      {:ok, node}
    end
  end

  @doc """
  Updates a node.

  ## Examples

      iex> update_node(scope, node, %{field: new_value})
      {:ok, %Node{}}

      iex> update_node(scope, node, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_node(%Scope{} = scope, %Node{} = node, attrs) do
    true = node.user_id == scope.user.id

    with {:ok, node = %Node{}} <-
           node
           |> Node.changeset(attrs, scope)
           |> Repo.update() do
      broadcast_node(scope, {:updated, node})
      {:ok, node}
    end
  end

  @doc """
  Deletes a node.

  ## Examples

      iex> delete_node(scope, node)
      {:ok, %Node{}}

      iex> delete_node(scope, node)
      {:error, %Ecto.Changeset{}}

  """
  def delete_node(%Scope{} = scope, %Node{} = node) do
    true = node.user_id == scope.user.id

    with {:ok, node = %Node{}} <-
           Repo.delete(node) do
      broadcast_node(scope, {:deleted, node})
      {:ok, node}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking node changes.

  ## Examples

      iex> change_node(scope, node)
      %Ecto.Changeset{data: %Node{}}

  """
  def change_node(%Scope{} = scope, %Node{} = node, attrs \\ %{}) do
    true = node.user_id == scope.user.id

    Node.changeset(node, attrs, scope)
  end
end
