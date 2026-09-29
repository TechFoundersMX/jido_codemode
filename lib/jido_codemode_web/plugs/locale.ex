defmodule JidoCodemodeWeb.Plugs.Locale do
  @moduledoc "Chooses the page language for each request and remembers an explicit choice."

  import Plug.Conn

  alias JidoCodemode.Locale

  @max_age 365 * 24 * 60 * 60

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_query_params() |> fetch_cookies()
    param = conn.query_params["lang"]
    accept_language = conn |> get_req_header("accept-language") |> List.first()
    locale = Locale.resolve(param, conn.cookies[Locale.cookie_name()], accept_language)

    Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)

    conn
    |> put_session("locale", locale)
    |> assign(:locale, locale)
    |> maybe_remember(param, locale)
  end

  defp maybe_remember(conn, param, locale) do
    if Locale.normalize(param) do
      put_resp_cookie(conn, Locale.cookie_name(), locale, max_age: @max_age, same_site: "Lax")
    else
      conn
    end
  end
end
