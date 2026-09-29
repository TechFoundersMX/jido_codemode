defmodule JidoCodemodeWeb.Plugs.StaffAccess do
  @moduledoc """
  Gate for `/live`: only a request carrying a valid Cloudflare Access token
  (see `JidoCodemode.StaffAccess`) gets through. Everyone else gets a plain 404,
  so the page doesn't advertise itself. On success the co-founder's email and the
  token's expiry go into the (signed) session for the LiveView to re-check.
  """

  import Plug.Conn

  alias JidoCodemode.StaffAccess

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    jwt =
      conn |> get_req_header("cf-access-jwt-assertion") |> List.first() ||
        conn.cookies["CF_Authorization"]

    case StaffAccess.verify(jwt) do
      {:ok, %{email: email, expires_at: expires_at}} ->
        put_session(conn, "staff", %{"email" => email, "expires_at" => expires_at})

      :error ->
        conn
        |> delete_session("staff")
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Not Found")
        |> halt()
    end
  end
end
