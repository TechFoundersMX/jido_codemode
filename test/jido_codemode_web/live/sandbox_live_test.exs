defmodule JidoCodemodeWeb.SandboxLiveTest do
  use JidoCodemodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  defmodule OpenCodeStub do
    def init(test_pid), do: test_pid

    def call(conn, test_pid) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      request = Jason.decode!(body)
      send(test_pid, {:opencode_session, Plug.Conn.get_req_header(conn, "x-opencode-session")})
      send(test_pid, {:opencode_request, conn.request_path, request["model"]})

      events =
        if Jason.encode!(List.last(request["input"])) =~ "First turn" do
          item = %{
            type: "function_call",
            id: "fc_schema",
            call_id: "call_schema",
            name: "describe_schema",
            arguments: "{}",
            status: "completed"
          }

          [
            %{type: "response.output_item.added", output_index: 0, item: item},
            %{
              type: "response.completed",
              response: %{id: "resp_schema", status: "completed", output: [item]}
            }
          ]
        else
          [
            %{
              type: "response.output_text.delta",
              delta: "Test reply",
              output_index: 0,
              content_index: 0
            },
            %{
              type: "response.completed",
              response: %{id: "resp_reply", status: "completed", output: []}
            }
          ]
        end

      body =
        Enum.map_join(events, "", fn event ->
          "event: #{event.type}\ndata: #{Jason.encode!(event)}\n\n"
        end)

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, body)
    end
  end

  defmodule GatewayStub do
    def init(test_pid), do: test_pid

    def call(conn, test_pid) do
      {:ok, _body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:gateway_request, conn.request_path, conn.req_headers})

      events = [
        %{type: "response.output_text.delta", delta: "Gateway reply"},
        %{type: "response.completed", response: %{id: "resp_gw", status: "completed", output: []}}
      ]

      body =
        Enum.map_join(events, "", fn event ->
          "event: #{event.type}\ndata: #{Jason.encode!(event)}\n\n"
        end)

      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.send_resp(200, body)
    end
  end

  setup do
    previous_password = Application.get_env(:jido_codemode, :demo_password)
    Application.put_env(:jido_codemode, :demo_password, "test-password")

    on_exit(fn ->
      if is_nil(previous_password) do
        Application.delete_env(:jido_codemode, :demo_password)
      else
        Application.put_env(:jido_codemode, :demo_password, previous_password)
      end
    end)

    :ok
  end

  test "renders the demo with the landing's header, examples and footer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/demo")

    assert has_element?(view, ".site-header a[href='/#pruebalo']")
    assert has_element?(view, "#locale-es_MX")
    assert has_element?(view, "h1", "Ask the sample distributor.")
    assert has_element?(view, "footer.site")

    for id <- ~w(trend categories shippers customers order-value countries) do
      assert has_element?(view, "#ex-#{id}")
    end

    # Locked: the example buttons can't ask yet.
    assert has_element?(view, "#ex-categories button.ask[disabled]")
    assert has_element?(view, "#unlock-form")
    refute has_element?(view, "#chat-form")
    refute has_element?(view, "#agent-report")
    refute has_element?(view, "#new-conversation")
  end

  test "once unlocked, an example asks its question and a new conversation can start",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/demo")
    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()

    refute has_element?(view, "#ex-categories button.ask[disabled]")

    assert has_element?(
             view,
             "#ex-categories button.ask[phx-value-prompt='Which 3 categories sell the most?']"
           )

    assert has_element?(view, "#new-conversation")
  end

  test "unlocks chat with the configured password", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/demo")

    view
    |> form("#unlock-form", unlock: %{password: "wrong-password"})
    |> render_submit()

    assert has_element?(view, "#unlock-error", "That password is not correct.")
    refute has_element?(view, "#chat-form")

    view
    |> form("#unlock-form", unlock: %{password: "test-password"})
    |> render_submit()

    assert has_element?(view, "#chat-form")
    refute has_element?(view, "#unlock-form")
  end

  test "OpenCode session is stable across turns and changes when chat resets", %{conn: conn} do
    server =
      start_supervised!({Bandit, plug: {OpenCodeStub, self()}, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    previous = Application.get_env(:req_llm, :openai)
    previous_key = Application.get_env(:req_llm, :openai_api_key)
    Application.put_env(:req_llm, :openai, base_url: "http://127.0.0.1:#{port}/v1")
    Application.put_env(:req_llm, :openai_api_key, "test-key")

    on_exit(fn ->
      for {key, value} <- [openai: previous, openai_api_key: previous_key] do
        if is_nil(value),
          do: Application.delete_env(:req_llm, key),
          else: Application.put_env(:req_llm, key, value)
      end
    end)

    {:ok, view, _html} = live(conn, ~p"/demo")
    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()

    view |> form("#chat-form", chat: %{prompt: "First turn"}) |> render_submit()
    assert_receive {:opencode_session, [session_id]}, 10_000
    assert_receive {:opencode_request, "/v1/responses", "gpt-5.6-luna"}
    assert session_id =~ ~r/^sandbox-[A-Za-z0-9_-]{32}$/
    # The model requests a schema tool, then receives its result in the same conversation.
    assert_receive {:opencode_session, [^session_id]}, 10_000
    render_async(view, 10_000)

    view |> form("#chat-form", chat: %{prompt: "Second turn"}) |> render_submit()
    assert_receive {:opencode_session, [^session_id]}, 10_000
    render_async(view, 10_000)

    render_click(view, "reset_chat")
    view |> form("#chat-form", chat: %{prompt: "New conversation"}) |> render_submit()
    assert_receive {:opencode_session, [new_session_id]}, 10_000
    refute new_session_id == session_id
    render_async(view, 10_000)
  end

  test "AI Gateway mode sends Access headers and never a provider Authorization header",
       %{conn: conn} do
    server =
      start_supervised!({Bandit, plug: {GatewayStub, self()}, ip: {127, 0, 0, 1}, port: 0})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    gateway_headers = [
      {"cf-access-client-id", "test-client-id"},
      {"cf-access-client-secret", "test-client-secret"},
      {"cf-aig-byok-alias", "production"}
    ]

    # Mirror what config/runtime.exs sets in gateway mode: no provider key, the
    # Access headers, and a model spec that lets ReqLLM omit Authorization.
    previous = %{
      openai: Application.get_env(:req_llm, :openai),
      openai_api_key: Application.get_env(:req_llm, :openai_api_key),
      ai: Application.get_env(:jido_codemode, JidoCodemode.AI),
      aliases: Application.get_env(:jido_ai, :model_aliases),
      env_key: System.get_env("OPENAI_API_KEY")
    }

    spec = %{
      provider: :openai,
      id: "gpt-5.6-luna",
      extra: %{openai_compatible_backend: :ollama}
    }

    Application.put_env(:req_llm, :openai, base_url: "http://127.0.0.1:#{port}/v1")
    Application.delete_env(:req_llm, :openai_api_key)
    System.delete_env("OPENAI_API_KEY")

    Application.put_env(
      :jido_codemode,
      JidoCodemode.AI,
      Keyword.put(previous.ai, :gateway_headers, gateway_headers)
    )

    Application.put_env(:jido_ai, :model_aliases, %{fast: spec, capable: spec})

    on_exit(fn ->
      restore = fn app, key, value ->
        if is_nil(value),
          do: Application.delete_env(app, key),
          else: Application.put_env(app, key, value)
      end

      restore.(:req_llm, :openai, previous.openai)
      restore.(:req_llm, :openai_api_key, previous.openai_api_key)
      restore.(:jido_codemode, JidoCodemode.AI, previous.ai)
      restore.(:jido_ai, :model_aliases, previous.aliases)
      if previous.env_key, do: System.put_env("OPENAI_API_KEY", previous.env_key)
    end)

    {:ok, view, _html} = live(conn, ~p"/demo")
    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()
    view |> form("#chat-form", chat: %{prompt: "Through the gateway"}) |> render_submit()

    assert_receive {:gateway_request, "/v1/responses", headers}, 10_000

    refute List.keymember?(headers, "authorization", 0)

    for {name, value} <- gateway_headers do
      assert {name, value} in headers
    end

    assert [{"x-opencode-session", "sandbox-" <> _}] =
             Enum.filter(headers, fn {name, _} -> name == "x-opencode-session" end)

    render_async(view, 10_000)
  end

  test "switching language in place keeps the demo unlocked and starts a new conversation", %{
    conn: conn
  } do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")
    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()
    assert has_element?(view, "#chat-form")

    html = view |> element("#locale-es_MX") |> render_click()

    assert html =~ "Pregúntale a la distribuidora de ejemplo."
    assert has_element?(view, "#chat-form")
    refute has_element?(view, "#unlock-form")

    assert has_element?(
             view,
             "#locale-notice",
             "Cambiaste a español. Las cifras ahora están en MXN."
           )

    assert_push_event(view, "locale-changed", %{
      locale: "es_MX",
      html_lang: "es-MX",
      title: "Agentic BI · Análisis listo para decidir"
    })
  end

  test "switching language patches the URL so a reload or rejoin keeps the language", %{
    conn: conn
  } do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")

    view |> element("#locale-es_MX") |> render_click()
    assert_patch(view, "/demo?lang=es")

    view |> element("#locale-en") |> render_click()
    assert_patch(view, "/demo?lang=en")
  end

  test "an explicit ?lang beats the session language when the LiveView mounts", %{conn: conn} do
    {:ok, _view, html} =
      conn
      |> put_req_cookie("agentic_bi_locale", "es_MX")
      |> put_req_header("accept-language", "es-MX")
      |> live(~p"/demo?lang=en")

    assert html =~ "Ask the sample distributor."
    refute html =~ "Pregúntale a la distribuidora"
  end

  test "the wrong-password error follows the page language", %{conn: conn} do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")

    view |> form("#unlock-form", unlock: %{password: "wrong-password"}) |> render_submit()
    assert has_element?(view, "#unlock-error", "That password is not correct.")

    view |> element("#locale-es_MX") |> render_click()

    assert has_element?(view, "#unlock-error", "Esa contraseña no es correcta.")
    refute has_element?(view, "#unlock-error", "That password is not correct.")
    assert has_element?(view, "#unlock-form input[aria-describedby='unlock-error']")
  end

  test "the Spanish page shows the MXN footnote with the rate", %{conn: conn} do
    {:ok, _view, html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/demo")

    assert html =~ "Cifras en pesos mexicanos (MXN)"
    assert html =~ "con el tipo de cambio FIX de Banxico del 28/09/2026: 1 USD = 17.8413 MXN."
    assert html =~ "1 USD = 17.8413 MXN"
    assert html =~ "28/09/2026"
  end

  test "the English page has no currency footnote", %{conn: conn} do
    {:ok, _view, html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")
    refute html =~ "Cifras en"
    refute html =~ "Figures in"
  end

  test "Spanish examples use translated labels and MXN amounts", %{conn: conn} do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/demo")

    card = view |> element("#ex-categories") |> render()
    assert card =~ "Bebidas"
    # 267,868.18 USD × 17.8413
    assert card =~ "$4.78 M"
  end

  test "agent requests carry the page locale in the tool context" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{__changed__: %{}, agent_id: "sandbox-1", locale: "es_MX"}
    }

    assert JidoCodemodeWeb.SandboxLive.tool_context(socket) == %{
             session_id: "sandbox-1",
             locale: "es_MX"
           }
  end

  test "ordinary events do not re-send the page copy, but a language switch does", %{conn: conn} do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")

    :erlang.trace(view.pid, true, [:send])

    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()
    unlock_diffs = collect_diffs()
    assert Enum.any?(unlock_diffs, &(&1 =~ "chat-form"))
    refute Enum.any?(unlock_diffs, &(&1 =~ "Ask the sample distributor"))
    refute Enum.any?(unlock_diffs, &(&1 =~ "find the internet"))

    view |> element("#locale-es_MX") |> render_click()
    switch_diffs = collect_diffs()
    assert Enum.any?(switch_diffs, &(&1 =~ "Pregúntale a la distribuidora"))
    assert Enum.any?(switch_diffs, &(&1 =~ "No encontramos conexión a internet"))

    view |> element("button[phx-click=reset_chat]") |> render_click()
    reset_diffs = collect_diffs()
    refute Enum.any?(reset_diffs, &(&1 =~ "Pregúntale a la distribuidora"))
    refute Enum.any?(reset_diffs, &(&1 =~ "No encontramos conexión a internet"))

    :erlang.trace(view.pid, false, [:send])
  end

  test "connection-lost pop-ups follow the language after an in-place switch", %{conn: conn} do
    {:ok, view, html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")

    assert html =~ "We can&#39;t find the internet"
    refute html =~ "No encontramos conexión a internet"

    html = view |> element("#locale-es_MX") |> render_click()

    assert html =~ "No encontramos conexión a internet"
    assert html =~ "Algo salió mal"
    refute html =~ "We can&#39;t find the internet"
    refute html =~ "We can't find the internet"
    refute html =~ "Something went wrong!"
  end

  test "the two suggestion buttons in the row have short labels and a full-prompt title", %{
    conn: conn
  } do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/demo")
    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()

    assert has_element?(
             view,
             "button[phx-click=use_suggestion][title='Show a monthly revenue trend']",
             "Trend"
           )

    assert has_element?(
             view,
             "button[phx-click=use_suggestion][title='Compare the top categories']",
             "Categories"
           )

    # The "More" menu buttons carry the full prompt as well.
    assert has_element?(
             view,
             "button[phx-click=use_suggestion][title='List the top customers by revenue']"
           )

    view |> element("#locale-es_MX") |> render_click()

    assert has_element?(view, "button[phx-click=use_suggestion] span", "Tendencia")
    assert has_element?(view, "button[phx-click=use_suggestion] span", "Categorías")
    refute render(view) =~ "Tendencia de ingresos"
    refute render(view) =~ "Categorías principales"
    refute render(view) =~ "Revenue trend"
  end

  test "table ids and years stay ungrouped while quantities and amounts are grouped" do
    format = &JidoCodemodeWeb.SandboxLive.format_table_value/2

    assert format.(10_248, "OrderId") == "10248"
    assert format.(10_248, "Id") == "10248"
    assert format.(10_248, "customerID") == "10248"
    assert format.(10_248, "ID de pedido") == "10248"
    assert format.(10_248, "id_pedido") == "10248"
    assert format.(10_248, "id") == "10248"
    assert format.(10_248, "Folio de factura") == "10248"
    assert format.(1_234_567, "Portafolio") == "1,234,567"
    assert format.(1_234, "Pedidos") == "1,234"
    assert format.(1997, "Year") == "1997"
    assert format.(1997, "order_year") == "1997"
    assert format.(2016, "Año") == "2016"
    assert format.(4_779_116.559, "revenue") == "4,779,116.56"
    assert format.(1234, "Quantity") == "1,234"
    assert format.(nil, "Quantity") == "-"
    assert format.("Beverages", "Category") == "Beverages"
  end

  describe "invitation access (invitation service connected)" do
    @uuid ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

    defp invitee(test_pid, opts \\ []) do
      JidoCodemode.DemoAccessFake.install(
        test_pid,
        Keyword.merge(
          [status: %{"inv-1" => {:ok, %{authorized: true, remaining_uses: 3, expires_at: nil}}}],
          opts
        )
      )
    end

    defp stub_model(port_or_nil) do
      previous = Application.get_env(:req_llm, :openai)
      previous_key = Application.get_env(:req_llm, :openai_api_key)

      base_url =
        case port_or_nil do
          nil -> "http://127.0.0.1:1/v1"
          port -> "http://127.0.0.1:#{port}/v1"
        end

      Application.put_env(:req_llm, :openai, base_url: base_url)
      Application.put_env(:req_llm, :openai_api_key, "test-key")

      on_exit(fn ->
        for {key, value} <- [openai: previous, openai_api_key: previous_key] do
          if is_nil(value),
            do: Application.delete_env(:req_llm, key),
            else: Application.put_env(:req_llm, key, value)
        end
      end)
    end

    defp start_model_stub do
      server =
        start_supervised!({Bandit, plug: {OpenCodeStub, self()}, ip: {127, 0, 0, 1}, port: 0})

      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
      stub_model(port)
    end

    test "a visitor without an invitation is sent to the self-serve form", %{conn: conn} do
      JidoCodemode.DemoAccessFake.install(self(), [])
      assert {:error, {:redirect, %{to: "/invite/solicitar"}}} = live(conn, ~p"/demo")
    end

    test "an invitee gets the agent without a password; one conversation spends one use",
         %{conn: conn} do
      invitee(self())
      start_model_stub()

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-1") |> live(~p"/demo")

      assert has_element?(view, "#chat-form")
      refute has_element?(view, "#unlock-form")
      assert has_element?(view, "#invite-status", "3 conversations left")

      assert has_element?(
               view,
               "#invite-status a[href='https://superdev.mx/calendar/?kind=demo&utm_source=demo_agentic_bi']"
             )

      view |> form("#chat-form", chat: %{prompt: "Hello"}) |> render_submit()
      assert_receive {:demo_access, :consume, ["inv-1", conversation_id]}, 5_000
      assert conversation_id =~ @uuid
      render_async(view, 10_000)
      assert has_element?(view, "#invite-status", "2 conversations left")

      view |> form("#chat-form", chat: %{prompt: "Hello again"}) |> render_submit()
      render_async(view, 10_000)
      refute_received {:demo_access, :consume, _args}

      render_click(view, "reset_chat")
      view |> form("#chat-form", chat: %{prompt: "New conversation"}) |> render_submit()
      assert_receive {:demo_access, :consume, ["inv-1", new_conversation_id]}, 5_000
      refute new_conversation_id == conversation_id
      render_async(view, 10_000)
      refute_received {:demo_access, :refund, _args}
    end

    test "a first turn that gets no answer gives the use back", %{conn: conn} do
      invitee(self())
      stub_model(nil)

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-1") |> live(~p"/demo")
      view |> form("#chat-form", chat: %{prompt: "Hello"}) |> render_submit()

      assert_receive {:demo_access, :consume, ["inv-1", conversation_id]}, 5_000
      assert_receive {:demo_access, :refund, ["inv-1", ^conversation_id]}, 15_000
      render_async(view, 10_000)

      # The refunded id is spent: the next question is a new conversation.
      view |> form("#chat-form", chat: %{prompt: "Try again"}) |> render_submit()
      assert_receive {:demo_access, :consume, ["inv-1", next_id]}, 5_000
      refute next_id == conversation_id
      render_async(view, 15_000)
    end

    test "an invitee who already used every conversation sees the call, not the form",
         %{conn: conn} do
      invitee(self(),
        status: %{"inv-0" => {:ok, %{authorized: true, remaining_uses: 0, expires_at: nil}}}
      )

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-0") |> live(~p"/demo")

      assert has_element?(view, "#access-ended", "Your invitation has no conversations left.")
      refute has_element?(view, "#chat-form")
      refute has_element?(view, "#unlock-form")
    end

    test "a second submit while a turn is pending is ignored", %{conn: conn} do
      invitee(self())
      start_model_stub()

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-1") |> live(~p"/demo")
      view |> form("#chat-form", chat: %{prompt: "Hello"}) |> render_submit()
      render_click(view, "use_suggestion", %{"prompt" => "Show a monthly revenue trend"})

      assert_receive {:demo_access, :consume, ["inv-1", _id]}, 5_000
      render_async(view, 10_000)
      refute_received {:demo_access, :consume, _args}
    end

    test "with no uses left the agent does not answer and offers the call", %{conn: conn} do
      invitee(self(), consume: {:error, :exhausted})
      stub_model(nil)

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-1") |> live(~p"/demo")
      view |> form("#chat-form", chat: %{prompt: "Hello"}) |> render_submit()
      render_async(view, 10_000)

      refute has_element?(view, "#chat-form")
      assert has_element?(view, "#access-ended", "Your invitation has no conversations left.")
      assert has_element?(view, "#access-ended a[href*='utm_source=demo_agentic_bi']")
      refute_received {:demo_access, :refund, _args}
    end

    test "an invitation revoked mid-visit sends the visitor to the form", %{conn: conn} do
      invitee(self(), consume: {:error, :invalid})
      stub_model(nil)

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-1") |> live(~p"/demo")
      view |> form("#chat-form", chat: %{prompt: "Hello"}) |> render_submit()

      assert_redirect(view, "/invite/solicitar", 10_000)
    end

    test "the service being down does not spend or answer", %{conn: conn} do
      invitee(self(), consume: {:error, :unavailable})
      stub_model(nil)

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "inv-1") |> live(~p"/demo")
      view |> form("#chat-form", chat: %{prompt: "Hello"}) |> render_submit()
      render_async(view, 10_000)

      assert has_element?(view, "#chat-form")
      assert render(view) =~ "check your invitation"
      refute_received {:demo_access, :refund, _args}
    end
  end

  defp collect_diffs(acc \\ []) do
    receive do
      {:trace, _pid, :send, %Phoenix.Socket.Message{event: "diff", payload: payload}, _to} ->
        collect_diffs([inspect_payload(payload) | acc])

      {:trace, _pid, :send, %Phoenix.Socket.Reply{payload: %{diff: diff}}, _to} ->
        collect_diffs([inspect_payload(diff) | acc])

      {:trace, _pid, :send, _other, _to} ->
        collect_diffs(acc)
    after
      300 -> Enum.reverse(acc)
    end
  end

  defp inspect_payload(payload),
    do: inspect(payload, limit: :infinity, printable_limit: :infinity)
end
