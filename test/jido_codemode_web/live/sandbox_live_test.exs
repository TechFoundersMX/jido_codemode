defmodule JidoCodemodeWeb.SandboxLiveTest do
  use JidoCodemodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    previous_password = Application.get_env(:jido_codemode, :demo_password)
    Application.put_env(:jido_codemode, :demo_password, "test-password")

    on_exit(fn ->
      if is_nil(previous_password) do
        Application.delete_env(:jido_codemode, :demo_password)
      else
        Application.put_env(:jido_codemode, :demo_password, previous_password)
      end
    end)

    :ok
  end

  test "renders the sandbox demo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#chart-card-revenue-trend")
    assert has_element?(view, "#chart-card-category-revenue")
    assert has_element?(view, "#chart-card-channel-mix")
    assert has_element?(view, "#chart-card-customer-shape")
    assert has_element?(view, "#unlock-form")
    refute has_element?(view, "#chat-form")
    refute has_element?(view, "#agent-report")
    assert render(view) =~ "Turn business questions into clear analysis"

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

  test "unlocks chat with the configured password", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#unlock-form", unlock: %{password: "wrong-password"})
    |> render_submit()

    assert has_element?(view, "#unlock-error", "That password is not correct.")
    refute has_element?(view, "#chat-form")

    view
    |> form("#unlock-form", unlock: %{password: "test-password"})
    |> render_submit()

    assert has_element?(view, "#chat-form")
    refute has_element?(view, "#unlock-form")
  end
end
