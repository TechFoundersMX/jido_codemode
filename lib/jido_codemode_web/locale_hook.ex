defmodule JidoCodemodeWeb.LocaleHook do
  @moduledoc "Carries the request's page language into the LiveView process."

  import Phoenix.Component, only: [assign: 3]

  alias JidoCodemode.Locale

  def on_mount(:default, _params, session, socket) do
    locale = Locale.normalize(session["locale"]) || Locale.default()
    Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)
    {:cont, assign(socket, :locale, locale)}
  end
end
