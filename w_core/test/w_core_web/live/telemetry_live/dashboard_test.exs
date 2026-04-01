defmodule WCoreWeb.TelemetryLive.DashboardTest do
  use WCoreWeb.ConnCase

  import Phoenix.LiveViewTest
  import WCore.TelemetryFixtures

  describe "dashboard access" do
    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/dashboard")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "You must log in to access this page."} = flash
    end

    test "renders initial telemetry from ETS for current user nodes", %{conn: conn} do
      user = WCore.AccountsFixtures.user_fixture()
      scope = WCore.Accounts.Scope.for_user(user)
      node = node_fixture(scope, %{machine_identifier: "edge-a1", location: "plant-42"})

      WCore.Telemetry.Server.ingest(node.id, "ativo", %{pressao: 100})
      Process.sleep(50)

      {:ok, _lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/dashboard")

      assert html =~ "Telemetry Dashboard"
      assert html =~ "edge-a1"
      assert html =~ "ativo"
      assert html =~ "100"
    end

    test "updates incrementally after PubSub event", %{conn: conn} do
      user = WCore.AccountsFixtures.user_fixture()
      scope = WCore.Accounts.Scope.for_user(user)
      node = node_fixture(scope, %{machine_identifier: "edge-b2", location: "plant-42"})

      {:ok, lv, _html} =
        conn
        |> log_in_user(user)
        |> live(~p"/dashboard")

      WCore.Telemetry.Server.ingest(node.id, "ativo", %{pressao: 101})
      Process.sleep(550)

      html = render(lv)

      assert html =~ "edge-b2"
      assert html =~ "ativo"
      assert html =~ "101"
    end
  end
end
