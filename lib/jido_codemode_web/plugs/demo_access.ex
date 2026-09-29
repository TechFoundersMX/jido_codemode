defmodule JidoCodemodeWeb.Plugs.DemoAccess do
  @moduledoc """
  Reads the invitation service's `demo_invitation` cookie and records what the page
  may show: `"invited"` (with the uses left), `"exhausted"`, `"expired"`, or nothing for a public
  visitor. Only a server-side reference to the token enters the session (see
  `JidoCodemode.DemoAccess.Tokens`); the cookie itself is never written.
  """

  import Plug.Conn

  alias JidoCodemode.DemoAccess
  alias JidoCodemode.DemoAccess.Tokens

  @session_key "demo_access"

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/health"} = conn, _opts), do: conn

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    case conn.cookies[DemoAccess.cookie_name()] do
      token when is_binary(token) and token != "" -> put_access(conn, token)
      _missing -> delete_session(conn, @session_key)
    end
  end

  defp put_access(conn, token) do
    case DemoAccess.status(token) do
      {:ok, %{authorized: true, remaining_uses: remaining}} when remaining > 0 ->
        put_session(conn, @session_key, %{
          "state" => "invited",
          "remaining" => remaining,
          "ref" => Tokens.put(token)
        })

      # Still valid but no uses left: /demo shows the call, not the request form.
      {:ok, %{authorized: true}} ->
        put_session(conn, @session_key, %{"state" => "exhausted"})

      {:ok, _revoked_or_expired} ->
        put_session(conn, @session_key, %{"state" => "expired"})

      {:error, :invalid} ->
        put_session(conn, @session_key, %{"state" => "expired"})

      # Service down or not connected: treat the visitor as public rather than
      # showing a misleading "expired" message.
      {:error, _unavailable} ->
        delete_session(conn, @session_key)
    end
  end
end
