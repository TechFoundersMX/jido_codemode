defmodule JidoCodemode.DemoAccessTest do
  use ExUnit.Case, async: false

  alias JidoCodemode.DemoAccess.{Hub, Tokens}

  # Plays the invitation service's partner endpoints (contract of 29 Sep 2026).
  defmodule PartnerStub do
    def init(test_pid), do: test_pid

    def call(conn, test_pid) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      auth = Plug.Conn.get_req_header(conn, "authorization")
      send(test_pid, {:partner, conn.method, conn.request_path, auth, request})

      {status, response} =
        case {conn.request_path, request} do
          {"/api/invite/partner/status", %{"session" => "live"}} ->
            {200, %{authorized: true, remainingUses: 2, expiresAt: "2026-10-06T00:00:00Z"}}

          {"/api/invite/partner/status", %{"session" => "down"}} ->
            {500, %{}}

          {"/api/invite/partner/status", _other} ->
            {200, %{authorized: false}}

          {"/api/invite/partner/consume", %{"session" => "live"}} ->
            {200, %{ok: true, charged: true, remainingUses: 1, expiresAt: "2026-10-06T00:00:00Z"}}

          {"/api/invite/partner/consume", %{"session" => "spent"}} ->
            {403, %{ok: false, error: "exhausted", remainingUses: 0}}

          {"/api/invite/partner/consume", %{"session" => "gone"}} ->
            {403, %{authorized: false}}

          {"/api/invite/partner/consume", _other} ->
            {503, %{ok: false, error: "unavailable"}}

          {"/api/invite/partner/refund", %{"session" => "flaky"}} ->
            if :counters.get(:persistent_term.get(:refund_calls), 1) == 0 do
              :counters.add(:persistent_term.get(:refund_calls), 1, 1)
              {503, %{ok: false, error: "unavailable"}}
            else
              {200, %{ok: true, refunded: true, remainingUses: 2}}
            end

          {"/api/invite/partner/refund", %{"session" => "gone"}} ->
            {403, %{authorized: false}}

          {"/api/invite/partner/refund", _other} ->
            {200, %{ok: true, refunded: true, remainingUses: 2}}
        end

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(response))
    end
  end

  setup do
    server =
      start_supervised!({Bandit, plug: {PartnerStub, self()}, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    previous = Application.get_env(:jido_codemode, Hub)

    Application.put_env(:jido_codemode, Hub,
      base_url: "http://127.0.0.1:#{port}/",
      token: "test-service-token"
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:jido_codemode, Hub, previous),
        else: Application.delete_env(:jido_codemode, Hub)
    end)

    :ok
  end

  test "status posts the session with the bearer token and reads the uses left" do
    assert {:ok, %{authorized: true, remaining_uses: 2, expires_at: "2026-10-06T00:00:00Z"}} =
             Hub.status("live")

    assert_received {:partner, "POST", "/api/invite/partner/status",
                     ["Bearer test-service-token"], %{"session" => "live"}}
  end

  test "status: authorized false is an answer, a server error is unavailable" do
    assert {:ok, %{authorized: false}} = Hub.status("expired")
    assert {:error, :unavailable} = Hub.status("down")
  end

  test "consume sends the conversation id and maps the 403s" do
    assert {:ok, 1} = Hub.consume("live", "conv-12345678")

    assert_received {:partner, "POST", "/api/invite/partner/consume", _auth,
                     %{"session" => "live", "conversationId" => "conv-12345678"}}

    assert {:error, :exhausted} = Hub.consume("spent", "conv-12345678")
    assert {:error, :invalid} = Hub.consume("gone", "conv-12345678")
    assert {:error, :unavailable} = Hub.consume("other", "conv-12345678")
  end

  test "refund retries a 503 and then succeeds" do
    :persistent_term.put(:refund_calls, :counters.new(1, []))
    assert :ok = Hub.refund("flaky", "conv-12345678")
    assert_received {:partner, "POST", "/api/invite/partner/refund", _auth, _body}
    assert_received {:partner, "POST", "/api/invite/partner/refund", _auth, _body}
  end

  test "a refund the service refuses (403) is not retried" do
    assert {:error, {:refused, 403}} = Hub.refund("gone", "conv-12345678")
    assert_received {:partner, "POST", "/api/invite/partner/refund", _auth, _body}
    refute_received {:partner, "POST", "/api/invite/partner/refund", _auth, _body}
  end

  test "an unreachable service fails closed" do
    Application.put_env(:jido_codemode, Hub, base_url: "http://127.0.0.1:1", token: "t")
    assert {:error, :unavailable} = Hub.status("live")
    assert {:error, :unavailable} = Hub.consume("live", "conv-12345678")
  end

  test "token references are stable, opaque, and expire" do
    ref = Tokens.put("token-abc")
    assert ref == Tokens.put("token-abc")
    refute ref =~ "token-abc"
    assert {:ok, "token-abc"} = Tokens.fetch(ref)
    assert :error = Tokens.fetch("unknown")

    Tokens.prune(System.system_time(:second) + 9 * 24 * 60 * 60)
    assert :error = Tokens.fetch(ref)
  end
end
