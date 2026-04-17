defmodule JidoCodemodeWeb.SandboxLiveTest do
  use JidoCodemodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the sandbox demo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#chart-card-revenue-trend")
    assert has_element?(view, "#chart-card-category-revenue")
    assert has_element?(view, "#chart-card-channel-mix")
    assert has_element?(view, "#chart-card-customer-shape")
    assert has_element?(view, "#chat-form")
    refute has_element?(view, "#agent-report")
    assert render(view) =~ "Reference implementation for sandboxed report generation"

    assert has_element?(
             view,
             "#sample-chart-revenue-trend[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )

    assert has_element?(
             view,
             "#sample-chart-category-revenue[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )

    assert has_element?(
             view,
             "#sample-chart-channel-mix[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )

    assert has_element?(
             view,
             "#sample-chart-customer-shape[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )
  end
end
