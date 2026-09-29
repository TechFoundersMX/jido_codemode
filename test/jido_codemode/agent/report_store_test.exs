defmodule JidoCodemode.Agent.ReportStoreTest do
  use ExUnit.Case, async: false

  alias JidoCodemode.Agent.ReportStore

  test "reports older than 24 hours are deleted, newer ones stay" do
    session = "prune-" <> Integer.to_string(System.unique_integer([:positive]))
    :ok = ReportStore.put(%{title: "kept"}, %{session_id: session})

    assert ReportStore.prune(DateTime.add(DateTime.utc_now(), 23 * 3600, :second)) == 0
    assert {:ok, %{report: %{title: "kept"}}} = ReportStore.latest_for_session(session)

    assert ReportStore.prune(DateTime.add(DateTime.utc_now(), 25 * 3600, :second)) >= 1
    assert :error = ReportStore.latest_for_session(session)
  end
end
