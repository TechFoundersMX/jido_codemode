defmodule JidoCodemode.DemoAccess do
  @moduledoc """
  Invitation access to the live agent, backed by SuperDev's demo invitation service.

  The service's Worker owns `/invite/*` and `/api/invite/*` on this host and sets
  the host-only `demo_invitation` cookie. This app never sets, renames, or logs
  that cookie: it only forwards its value to the service's server-to-server
  endpoints. One conversation spends one use; a conversation that got no answer
  gets its use back once.

  The client is chosen with `config :jido_codemode, :demo_access_client`. The
  default, `JidoCodemode.DemoAccess.Disabled`, grants nobody access, so the demo
  falls back to the team password until the service is live.
  """

  @type token :: String.t()
  @type conversation_id :: String.t()
  @type status :: %{
          authorized: boolean(),
          remaining_uses: non_neg_integer(),
          expires_at: integer() | nil
        }

  @callback status(token()) :: {:ok, status()} | {:error, :invalid | :unavailable}
  @callback consume(token(), conversation_id()) ::
              {:ok, non_neg_integer()} | {:error, :exhausted | :invalid | :unavailable}
  @callback refund(token(), conversation_id()) :: :ok | {:error, term()}

  @cookie "demo_invitation"

  @spec cookie_name() :: String.t()
  def cookie_name, do: @cookie

  @spec status(token()) :: {:ok, status()} | {:error, :invalid | :unavailable}
  def status(token), do: client().status(token)

  @spec consume(token(), conversation_id()) ::
          {:ok, non_neg_integer()} | {:error, :exhausted | :invalid | :unavailable}
  def consume(token, conversation_id), do: client().consume(token, conversation_id)

  @spec refund(token(), conversation_id()) :: :ok | {:error, term()}
  def refund(token, conversation_id), do: client().refund(token, conversation_id)

  @doc "True once the invitation service is connected (`AGENTIC_BI_SERVICE_TOKEN` is set)."
  @spec enabled?() :: boolean()
  def enabled?, do: client() != JidoCodemode.DemoAccess.Disabled

  defp client do
    Application.get_env(:jido_codemode, :demo_access_client, JidoCodemode.DemoAccess.Disabled)
  end
end
