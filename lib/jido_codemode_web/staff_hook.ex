defmodule JidoCodemodeWeb.StaffHook do
  @moduledoc """
  Re-checks the co-founder's Access session when `/live` mounts, including on
  the LiveView connection, which doesn't pass through the plug. A missing or
  expired session is sent back to `/live`, where Cloudflare Access signs in again.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:default, _params, session, socket) do
    case session["staff"] do
      %{"email" => email, "expires_at" => expires_at} when is_binary(email) ->
        if expires_at > System.system_time(:second) do
          {:cont, assign(socket, :staff_email, email)}
        else
          {:halt, redirect(socket, to: "/live")}
        end

      _missing ->
        {:halt, redirect(socket, to: "/live")}
    end
  end
end
