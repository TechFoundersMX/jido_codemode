defmodule JidoCodemode.DemoAccess.Hub do
  @moduledoc """
  Client for the invitation service's partner endpoints (contract of 29 Sep 2026,
  TechFoundersMX/ellingwood-demo#246):

      POST {base_url}/api/invite/partner/status   {session}
      POST {base_url}/api/invite/partner/consume  {session, conversationId}
      POST {base_url}/api/invite/partner/refund   {session, conversationId}

  Authenticated with `Authorization: Bearer AGENTIC_BI_SERVICE_TOKEN`. The session
  value is the visitor's `demo_invitation` cookie: it goes only in these request
  bodies and is never logged. Anything unexpected fails closed (`:unavailable`).

  Configured under `config :jido_codemode, JidoCodemode.DemoAccess.Hub` with
  `:base_url`, `:token`, and optional `:req_options`.
  """

  @behaviour JidoCodemode.DemoAccess

  @refund_attempts 3

  @impl true
  def status(session) do
    case post("status", %{session: session}) do
      {:ok, 200, %{"authorized" => true} = body} ->
        with {:ok, remaining} <- remaining_uses(body) do
          {:ok, %{authorized: true, remaining_uses: remaining, expires_at: body["expiresAt"]}}
        end

      {:ok, 200, %{"authorized" => false}} ->
        {:ok, %{authorized: false, remaining_uses: 0, expires_at: nil}}

      _other ->
        {:error, :unavailable}
    end
  end

  @impl true
  def consume(session, conversation_id) do
    case post("consume", %{session: session, conversationId: conversation_id}) do
      {:ok, 200, %{"ok" => true} = body} -> remaining_uses(body)
      {:ok, 403, %{"error" => "exhausted"}} -> {:error, :exhausted}
      {:ok, 403, %{"authorized" => false}} -> {:error, :invalid}
      _other -> {:error, :unavailable}
    end
  end

  @impl true
  def refund(session, conversation_id), do: refund(session, conversation_id, @refund_attempts)

  defp refund(_session, _conversation_id, 0), do: {:error, :unavailable}

  defp refund(session, conversation_id, attempts) do
    case post("refund", %{session: session, conversationId: conversation_id}) do
      {:ok, 200, %{"ok" => true}} ->
        :ok

      # Only a service fault is worth retrying; 400/401/403 won't change.
      {:ok, status, _body} when status < 500 ->
        {:error, {:refused, status}}

      _unavailable ->
        Process.sleep(backoff(attempts))
        refund(session, conversation_id, attempts - 1)
    end
  end

  defp backoff(attempts_left), do: 250 * (@refund_attempts - attempts_left + 1)

  defp remaining_uses(%{"remainingUses" => remaining})
       when is_integer(remaining) and remaining >= 0,
       do: {:ok, remaining}

  defp remaining_uses(_body), do: {:error, :unavailable}

  defp post(action, body) do
    config = Application.get_env(:jido_codemode, __MODULE__, [])

    options =
      [
        url:
          String.trim_trailing(Keyword.fetch!(config, :base_url), "/") <>
            "/api/invite/partner/" <> action,
        json: body,
        auth: {:bearer, Keyword.fetch!(config, :token)},
        receive_timeout: 5_000,
        retry: false
      ]
      |> Keyword.merge(Keyword.get(config, :req_options, []))

    case Req.post(options) do
      {:ok, %Req.Response{status: status, body: body}} when is_map(body) -> {:ok, status, body}
      {:ok, %Req.Response{status: status}} -> {:ok, status, %{}}
      {:error, _exception} -> :error
    end
  end
end
