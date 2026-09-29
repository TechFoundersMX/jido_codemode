defmodule JidoCodemodeWeb.LocaleHookTest do
  use ExUnit.Case, async: true

  alias JidoCodemodeWeb.LocaleHook

  defp mount(params, session) do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
    {:cont, socket} = LocaleHook.on_mount(:default, params, session, socket)
    socket.assigns.locale
  end

  test "the ?lang param beats the session locale" do
    assert mount(%{"lang" => "en"}, %{"locale" => "es_MX"}) == "en"
    assert mount(%{"lang" => "es"}, %{"locale" => "en"}) == "es_MX"
  end

  test "an unusable ?lang falls back to the session locale" do
    assert mount(%{"lang" => "fr"}, %{"locale" => "es_MX"}) == "es_MX"
    assert mount(%{}, %{"locale" => "es_MX"}) == "es_MX"
  end

  test "params that are not a map fall back to the session locale" do
    assert mount(:not_mounted_at_router, %{"locale" => "es_MX"}) == "es_MX"
  end

  test "with no param and no session the default locale is used" do
    assert mount(%{}, %{}) == JidoCodemode.Locale.default()
  end
end
