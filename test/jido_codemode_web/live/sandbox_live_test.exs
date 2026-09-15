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

  test "renders the sandbox demo", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#chart-card-revenue-trend")
    assert has_element?(view, "#chart-card-category-revenue")
    assert has_element?(view, "#chart-card-channel-mix")
    assert has_element?(view, "#chart-card-customer-shape")
    assert has_element?(view, "#unlock-form")
    refute has_element?(view, "#chat-form")
    refute has_element?(view, "#agent-report")
    assert render(view) =~ "Turn business questions into clear analysis"

    assert has_element?(
             view,
             "#sample-chart-revenue-trend[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )

    assert has_element?(
             view,
             "#sample-chart-category-revenue[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )

    assert has_element?(
             view,
             "#sample-chart-channel-mix[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )

    assert has_element?(
             view,
             "#sample-chart-customer-shape[phx-hook='JidoCodemodeWeb.SandboxLive.VegaChart']"
           )
  end

  test "unlocks chat with the configured password", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

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

    {:ok, view, _html} = live(conn, ~p"/")
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
end
