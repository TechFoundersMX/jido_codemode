defmodule JidoCodemodeWeb.Plugs.LocaleTest do
  use JidoCodemodeWeb.ConnCase, async: true

  test "a Spanish browser gets the Spanish page", %{conn: conn} do
    html =
      conn
      |> put_req_header("accept-language", "es-MX,es;q=0.9")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(<html lang="es-MX")
  end

  test "an English browser gets the English page", %{conn: conn} do
    html =
      conn
      |> put_req_header("accept-language", "en-US,en;q=0.9")
      |> get(~p"/")
      |> html_response(200)

    assert html =~ ~s(<html lang="en")
  end

  test "?lang overrides the header and is saved in a cookie", %{conn: conn} do
    conn = conn |> put_req_header("accept-language", "en-US") |> get(~p"/?lang=es")
    assert html_response(conn, 200) =~ ~s(<html lang="es-MX")
    assert conn.resp_cookies["agentic_bi_locale"].value == "es_MX"
  end

  test "the cookie beats the header", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("agentic_bi_locale", "es_MX")
      |> put_req_header("accept-language", "en-US")
      |> get(~p"/")

    assert html_response(conn, 200) =~ ~s(<html lang="es-MX")
  end

  test "the locale cookie is readable by the page so the language switch can update it", %{
    conn: conn
  } do
    conn = get(conn, ~p"/?lang=es")
    cookie = conn.resp_cookies["agentic_bi_locale"]

    assert cookie.max_age == 365 * 24 * 60 * 60

    [header] =
      conn |> Plug.Conn.get_resp_header("set-cookie") |> Enum.filter(&(&1 =~ "agentic_bi_locale"))

    refute String.downcase(header) =~ "httponly"
    assert header =~ "SameSite=Lax"
    assert header =~ "max-age=31536000"
    assert header =~ "path=/"
  end
end
