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
end
