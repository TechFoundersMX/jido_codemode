defmodule JidoCodemodeWeb.LocaleHook do
  @moduledoc "Carries the request's page language into the LiveView process."

  import Phoenix.Component, only: [assign: 3]

  alias JidoCodemode.Locale

  # An explicit ?lang in the URL wins: the language switch patches it in, so a rejoin
  # (which reuses the URL, not the frozen first-render session) keeps the chosen language.
  def on_mount(:default, params, session, socket) do
    locale =
      Locale.normalize(lang_param(params)) || Locale.normalize(session["locale"]) ||
        Locale.default()

    Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)
    {:cont, assign(socket, :locale, locale)}
  end

  defp lang_param(%{"lang" => lang}), do: lang
  defp lang_param(_params), do: nil
end
