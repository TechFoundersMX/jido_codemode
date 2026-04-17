defmodule JidoCodemodeWeb.SandboxLive do
  use JidoCodemodeWeb, :live_view

  alias Jido.AI, as: JidoAI
  alias Jido.Thread
  alias JidoCodemode.AI
  alias JidoCodemode.Agent.Report
  alias JidoCodemode.SidebarAgent
  alias VegaLite, as: Vl

  @markdown_options [
    streaming: true,
    extension: [autolink: true, strikethrough: true, table: true, tasklist: true],
    render: [hardbreaks: true],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Jido codemode reference")
      |> assign(:charts, build_charts())
      |> assign(:agent_id, nil)
      |> assign(:agent_pid, nil)
      |> assign(:agent_model, AI.model())
      |> assign(:chat_form, chat_form())
      |> assign(:chat_messages, [])
      |> assign(:agent_report, nil)
      |> assign(:chat_pending, false)
      |> assign(:chat_request_id, nil)
      |> assign(:pending_prompt, nil)
      |> assign(:pending_reply_content, nil)

    socket =
      if connected?(socket) do
        start_sidebar_agent(socket)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    case socket.assigns[:agent_id] do
      nil -> :ok
      agent_id -> _ = Jido.stop_agent(JidoCodemode.Jido, agent_id)
    end

    :ok
  end

  @impl true
  def handle_event("submit_chat", %{"chat" => %{"prompt" => prompt}}, socket) do
    submit_prompt(socket, prompt)
  end

  def handle_event("use_suggestion", %{"prompt" => prompt}, socket) do
    submit_prompt(socket, prompt)
  end

  def handle_event("reset_chat", _params, socket) do
    {:noreply,
     socket
     |> stop_sidebar_agent()
     |> assign(:chat_form, chat_form())
     |> assign(:chat_messages, [])
     |> assign(:agent_report, nil)
     |> clear_pending_chat()
     |> start_sidebar_agent()}
  end

  @impl true
  def handle_info({:poll_agent_reply, request_id}, socket) do
    if socket.assigns.chat_pending and socket.assigns.chat_request_id == request_id do
      socket =
        assign(socket, :pending_reply_content, pending_reply_content(socket.assigns.agent_pid))

      Process.send_after(self(), {:poll_agent_reply, request_id}, 120)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_async({:agent_reply, request_id}, {:ok, {:ok, reply}}, socket) do
    if socket.assigns.chat_request_id == request_id do
      {:noreply,
       socket
       |> refresh_chat_messages()
       |> refresh_agent_report()
       |> clear_pending_chat()
       |> maybe_put_reply_flash(reply)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:agent_reply, request_id}, {:ok, {:error, reason}}, socket) do
    if socket.assigns.chat_request_id == request_id do
      {:noreply,
       socket
       |> refresh_chat_messages()
       |> refresh_agent_report()
       |> clear_pending_chat()
       |> put_flash(:error, error_reply(reason))}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:agent_reply, request_id}, {:exit, reason}, socket) do
    if socket.assigns.chat_request_id == request_id do
      {:noreply,
       socket
       |> refresh_chat_messages()
       |> refresh_agent_report()
       |> clear_pending_chat()
       |> put_flash(:error, error_reply(reason))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      full_width={true}
      main_class="min-h-screen"
      content_class="mx-auto max-w-7xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8"
    >
      <section class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_24rem] lg:items-start">
        <div class="space-y-6">
          <section class="overflow-hidden rounded-[2rem] border border-base-300/60 bg-base-100 shadow-sm">
            <div class="grid gap-8 px-6 py-8 sm:px-8 lg:grid-cols-[minmax(0,1fr)_20rem] lg:items-end lg:px-10">
              <div class="space-y-5">
                <p class="text-[0.72rem] font-semibold uppercase tracking-[0.28em] text-primary">
                  Jido Codemode
                </p>

                <div class="space-y-4">
                  <h1 class="max-w-[14ch] text-4xl font-semibold tracking-tight text-balance text-base-content sm:text-5xl">
                    Reference implementation for sandboxed report generation.
                  </h1>

                  <p class="max-w-3xl text-base leading-7 text-base-content/70 sm:text-lg">
                    A Jido agent can answer directly, inspect schema metadata, run bounded
                    read-only SQL, or switch into codemode and write Lua that returns validated
                    report blocks for LiveView.
                  </p>
                </div>

                <div class="flex flex-wrap gap-3 text-sm text-base-content/70">
                  <span class="rounded-full border border-base-300/70 bg-base-200 px-3 py-1.5">
                    Lua report runtime
                  </span>
                  <span class="rounded-full border border-base-300/70 bg-base-200 px-3 py-1.5">
                    Read-only SQLite tools
                  </span>
                  <span class="rounded-full border border-base-300/70 bg-base-200 px-3 py-1.5">
                    LiveView + Vega rendering
                  </span>
                </div>
              </div>

              <div class="rounded-[1.6rem] border border-base-300/70 bg-base-200/60 p-5">
                <div class="space-y-4">
                  <p class="text-xs font-semibold uppercase tracking-[0.22em] text-base-content/45">
                    Runtime
                  </p>

                  <div class="space-y-3 text-sm leading-6 text-base-content/70">
                    <p>
                      1. The agent gets a compact schema digest and three explicit tools.
                    </p>
                    <p>
                      2. Multi-step reporting uses sandboxed Lua with `db.query(...)` and
                      `report.*` helpers.
                    </p>
                    <p>
                      3. Elixir validates the payload, stores the report, and LiveView renders the
                      result.
                    </p>
                  </div>

                  <div class="rounded-2xl bg-base-100 px-4 py-3 text-sm text-base-content/65 ring-1 ring-base-300/60">
                    Model alias: <span class="font-semibold text-base-content">{@agent_model}</span>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <section
            :if={@agent_report}
            id="agent-report"
            class="space-y-6 rounded-[1.6rem] border border-base-300/70 bg-base-100 p-6 shadow-sm"
          >
            <div class="space-y-2">
              <p class="text-[0.72rem] font-semibold uppercase tracking-[0.28em] text-secondary">
                Agent output
              </p>
              <h2 class="text-3xl font-semibold tracking-tight text-base-content">
                {@agent_report.title}
              </h2>
              <p :if={@agent_report.summary} class="max-w-3xl text-sm leading-6 text-base-content/65">
                {@agent_report.summary}
              </p>
            </div>

            <div class="grid grid-cols-1 gap-6 xl:grid-cols-2">
              <div :for={block <- @agent_report.blocks} class={report_block_classes(block)}>
                <%= case block do %>
                  <% %Report.TextBlock{} -> %>
                    <div class={assistant_markdown_classes()}>{render_markdown(block.body)}</div>
                  <% %Report.MetricBlock{} -> %>
                    <div class="space-y-2">
                      <p class="text-xs font-semibold uppercase tracking-[0.22em] text-base-content/45">
                        Metric
                      </p>
                      <p class="text-sm text-base-content/60">{block.label}</p>
                      <p class="text-4xl font-semibold tracking-tight text-base-content">
                        {format_metric_value(block.value, block.format)}
                      </p>
                    </div>
                  <% %Report.TableBlock{} -> %>
                    <div class="space-y-4">
                      <div class="space-y-1">
                        <h3 class="text-xl font-semibold tracking-tight text-base-content">
                          {block.title}
                        </h3>
                        <p :if={block.summary} class="text-sm leading-6 text-base-content/60">
                          {block.summary}
                        </p>
                      </div>

                      <div :if={Enum.empty?(block.rows)} class="py-8 text-sm text-base-content/45">
                        No rows to show for this table.
                      </div>

                      <div :if={not Enum.empty?(block.rows)} class="overflow-x-auto">
                        <table class="min-w-full border-separate border-spacing-0 text-sm">
                          <thead>
                            <tr>
                              <th
                                :for={column <- block.columns}
                                class="border-b border-base-300/70 px-0 py-3 pr-6 text-left text-xs font-semibold uppercase tracking-[0.18em] text-base-content/50"
                              >
                                {column}
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr :for={row <- block.rows}>
                              <td
                                :for={column <- block.columns}
                                class="border-b border-base-300/55 px-0 py-3 pr-6 text-base-content/75 last:pr-0"
                              >
                                {format_table_value(Map.get(row, column))}
                              </td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                    </div>
                  <% %Report.ChartBlock{} -> %>
                    <div class="space-y-4">
                      <div class="space-y-1">
                        <h3 class="text-xl font-semibold tracking-tight text-base-content">
                          {block.title}
                        </h3>
                        <p :if={block.summary} class="text-sm leading-6 text-base-content/60">
                          {block.summary}
                        </p>
                      </div>

                      <div
                        :if={not chart_block_has_rows?(block)}
                        class="py-8 text-sm text-base-content/45"
                      >
                        No rows to show for this chart.
                      </div>

                      <div :if={chart_block_has_rows?(block)} class="overflow-hidden">
                        <div
                          id={"report-chart-#{block.id}"}
                          phx-hook=".VegaChart"
                          data-spec={block.spec_json}
                          class="min-h-72 w-full"
                        />
                      </div>
                    </div>
                <% end %>
              </div>
            </div>
          </section>

          <section class="space-y-4 rounded-[1.6rem] border border-base-300/70 bg-base-100 p-6 shadow-sm">
            <div class="flex items-end justify-between gap-4">
              <div class="space-y-1">
                <p class="text-[0.72rem] font-semibold uppercase tracking-[0.28em] text-primary">
                  Reference charts
                </p>
                <h2 class="text-2xl font-semibold tracking-tight text-base-content">
                  Seed charts for quick prompts
                </h2>
              </div>

              <button
                type="button"
                phx-click="reset_chat"
                class="rounded-full border border-base-300 bg-base-200 px-3 py-2 text-sm font-medium text-base-content transition hover:bg-base-300"
              >
                Restart session
              </button>
            </div>

            <div class="grid grid-cols-1 gap-6 xl:grid-cols-2">
              <article :for={chart <- @charts} id={"chart-card-#{chart.id}"} class="space-y-4">
                <div class="space-y-1">
                  <p class="text-xs font-semibold uppercase tracking-[0.24em] text-base-content/40">
                    {chart.kicker}
                  </p>
                  <h3 class="text-xl font-semibold tracking-tight text-base-content">
                    {chart.title}
                  </h3>
                  <p class="text-sm leading-6 text-base-content/55">{chart.description}</p>
                </div>

                <div class="overflow-hidden rounded-[1.3rem] bg-base-100 ring-1 ring-base-300/55">
                  <div
                    id={"sample-chart-#{chart.id}"}
                    phx-hook=".VegaChart"
                    data-spec={chart.spec_json}
                    class="min-h-72 w-full"
                  />
                </div>
              </article>
            </div>
          </section>
        </div>

        <aside class="lg:sticky lg:top-6">
          <section class="overflow-hidden rounded-[1.6rem] border border-base-300/70 bg-base-100 shadow-sm">
            <div class="border-b border-base-300/70 px-5 py-4">
              <p class="text-[0.72rem] font-semibold uppercase tracking-[0.28em] text-secondary">
                Interactive sandbox
              </p>
              <h2 class="mt-2 text-xl font-semibold tracking-tight text-base-content">
                Request schema details, data previews, or a report
              </h2>
              <p class="mt-2 text-sm leading-6 text-base-content/60">
                The agent can inspect schema metadata, run bounded SQL previews, and switch into
                codemode when structured output is the right boundary.
              </p>
            </div>

            <div class="space-y-4 px-5 py-4">
              <div class="flex flex-wrap gap-2">
                <button
                  :for={suggestion <- suggestion_prompts()}
                  type="button"
                  phx-click="use_suggestion"
                  phx-value-prompt={suggestion.prompt}
                  class="inline-flex items-center gap-1.5 rounded-full border border-base-300 bg-base-200 px-3 py-1.5 text-xs font-medium text-base-content transition hover:bg-base-300"
                >
                  <.icon name={suggestion.icon} class="size-3.5 text-primary" />
                  {suggestion.prompt}
                </button>
              </div>

              <div class="rounded-[1.35rem] bg-base-200/55 p-4 ring-1 ring-base-300/60">
                <div
                  :if={not show_chat_conversation?(@chat_messages, @pending_prompt, @chat_pending)}
                  class="space-y-3"
                >
                  <p class="text-sm leading-6 text-base-content/60">
                    Start with a schema question, a query request, or a report prompt.
                  </p>

                  <div class="rounded-2xl border border-base-300/70 bg-base-100 px-4 py-3 text-sm text-base-content/65">
                    Example:
                    <span class="font-medium text-base-content">
                      Build a report with revenue by category and a top-customer table.
                    </span>
                  </div>
                </div>

                <div
                  :if={show_chat_conversation?(@chat_messages, @pending_prompt, @chat_pending)}
                  class="space-y-4"
                >
                  <div class="max-h-[28rem] space-y-4 overflow-y-auto pr-1">
                    <div :for={message <- @chat_messages} class={chat_row_classes(message.role)}>
                      <div class={message_classes(message.role)}>
                        <p class="mb-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] opacity-60">
                          {role_label(message.role)}
                        </p>
                        <div :if={message.role == :assistant} class={assistant_markdown_classes()}>
                          {render_markdown(message.content)}
                        </div>
                        <p :if={message.role == :user} class="text-sm leading-6">{message.content}</p>
                      </div>
                    </div>

                    <div :if={@pending_prompt} class="flex justify-end">
                      <div class={message_classes(:user)}>
                        <p class="mb-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] opacity-60">
                          You
                        </p>
                        <p class="text-sm leading-6">{@pending_prompt}</p>
                      </div>
                    </div>

                    <div :if={@chat_pending and @pending_reply_content} class="flex justify-start">
                      <div class={message_classes(:assistant)}>
                        <p class="mb-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] opacity-60">
                          Agent
                        </p>
                        <div class={assistant_markdown_classes()}>
                          {render_markdown(@pending_reply_content)}
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <.form id="chat-form" for={@chat_form} phx-submit="submit_chat" class="space-y-3">
                <.input
                  field={@chat_form[:prompt]}
                  type="textarea"
                  placeholder="Ask for schema details, a query, or a report"
                  rows="4"
                  disabled={@chat_pending}
                  class="w-full rounded-[1.35rem] border border-base-300 bg-base-100 px-4 py-3 text-sm text-base-content shadow-none outline-none transition focus:border-primary focus:ring-0 disabled:cursor-not-allowed disabled:opacity-60"
                />

                <div class="flex items-center justify-between gap-3">
                  <p class="text-xs leading-5 text-base-content/50">
                    Read-only queries, bounded previews, validated report blocks.
                  </p>

                  <button
                    type="submit"
                    class="inline-flex shrink-0 items-center justify-center rounded-full bg-primary px-4 py-2.5 text-sm font-medium text-primary-content transition hover:brightness-95 disabled:cursor-not-allowed disabled:opacity-60"
                    disabled={@chat_pending}
                  >
                    {if @chat_pending, do: "Working...", else: "Send"}
                  </button>
                </div>
              </.form>
            </div>
          </section>
        </aside>
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".VegaChart">
        import vegaEmbed from "vega-embed"

        export default {
          mounted() {
            this.renderChart()
          },

          updated() {
            this.renderChart()
          },

          destroyed() {
            this.view?.finalize()
          },

          async renderChart() {
            const spec = this.el.dataset.spec

            if (!spec) {
              return
            }

            this.view?.finalize()

            const result = await vegaEmbed(this.el, JSON.parse(spec), {
              actions: false,
              renderer: "svg",
            })

            this.view = result.view
          },
        }
      </script>
    </Layouts.app>
    """
  end

  defp submit_prompt(socket, prompt) do
    prompt = String.trim(prompt)

    cond do
      prompt == "" ->
        {:noreply, assign(socket, :chat_form, chat_form())}

      is_nil(socket.assigns.agent_pid) ->
        {:noreply,
         socket
         |> assign(:chat_form, chat_form(prompt))
         |> put_flash(:error, "The agent session is still starting. Try again in a moment.")}

      true ->
        agent_pid = socket.assigns.agent_pid
        agent_id = socket.assigns.agent_id
        request_id = System.unique_integer([:positive])

        Process.send_after(self(), {:poll_agent_reply, request_id}, 120)

        {:noreply,
         socket
         |> assign(:chat_form, chat_form())
         |> assign(:chat_pending, true)
         |> assign(:chat_request_id, request_id)
         |> assign(:pending_prompt, prompt)
         |> assign(:pending_reply_content, nil)
         |> start_async({:agent_reply, request_id}, fn ->
           SidebarAgent.ask_sync(agent_pid, prompt,
             timeout: 60_000,
             tool_context: %{session_id: agent_id}
           )
         end)}
    end
  end

  defp build_charts do
    [
      %{
        id: "revenue-trend",
        kicker: "Line",
        title: "Monthly revenue trend",
        description: "A simple time-series anchor for the conversation.",
        spec_json: revenue_trend_spec()
      },
      %{
        id: "category-revenue",
        kicker: "Bar",
        title: "Revenue by category",
        description: "A ranked comparison of the biggest drivers.",
        spec_json: category_revenue_spec()
      },
      %{
        id: "channel-mix",
        kicker: "Donut",
        title: "Channel mix",
        description: "A quick composition view for share of revenue.",
        spec_json: channel_mix_spec()
      },
      %{
        id: "customer-shape",
        kicker: "Scatter",
        title: "Customer value vs. order volume",
        description: "A compact way to spot high-value segments.",
        spec_json: customer_shape_spec()
      }
    ]
  end

  defp chat_form(prompt \\ "") do
    to_form(%{"prompt" => prompt}, as: :chat)
  end

  defp show_chat_conversation?(chat_messages, pending_prompt, chat_pending) do
    chat_messages != [] or not is_nil(pending_prompt) or chat_pending == true
  end

  defp start_sidebar_agent(socket) do
    agent_id = "sandbox-" <> Integer.to_string(System.unique_integer([:positive]))
    {:ok, agent_pid} = Jido.start_agent(JidoCodemode.Jido, SidebarAgent, id: agent_id)

    _ =
      JidoAI.set_system_prompt(agent_pid, SidebarAgent.system_prompt_with_schema(),
        timeout: 15_000
      )

    socket
    |> assign(:agent_id, agent_id)
    |> assign(:agent_pid, agent_pid)
    |> refresh_chat_messages()
    |> refresh_agent_report()
  end

  defp stop_sidebar_agent(socket) do
    case socket.assigns[:agent_id] do
      nil -> :ok
      agent_id -> _ = Jido.stop_agent(JidoCodemode.Jido, agent_id)
    end

    socket
    |> assign(:agent_id, nil)
    |> assign(:agent_pid, nil)
    |> assign(:agent_report, nil)
  end

  defp refresh_chat_messages(socket) do
    assign(socket, :chat_messages, chat_messages(socket.assigns[:agent_pid]))
  end

  defp refresh_agent_report(socket) do
    assign(socket, :agent_report, latest_agent_report(socket.assigns[:agent_id]))
  end

  defp suggestion_prompts do
    [
      %{icon: "hero-chart-bar", prompt: "Show a monthly revenue trend"},
      %{icon: "hero-squares-2x2", prompt: "Compare the top categories"},
      %{icon: "hero-users", prompt: "List the top customers by revenue"},
      %{icon: "hero-circle-stack", prompt: "Describe the most important joins"},
      %{icon: "hero-sparkles", prompt: "Build a short report with a chart and a table"}
    ]
  end

  defp pending_reply_content(nil), do: nil

  defp pending_reply_content(agent_pid) do
    case Jido.AgentServer.status(agent_pid) do
      {:ok, %{raw_state: raw_state}} ->
        raw_state
        |> Map.get(:__strategy__, %{})
        |> Map.get(:streaming_text)
        |> case do
          text when is_binary(text) and text != "" -> text
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp chat_messages(nil), do: []

  defp chat_messages(agent_pid) do
    case Jido.AgentServer.status(agent_pid) do
      {:ok, status} ->
        status.raw_state
        |> Map.get(:__thread__)
        |> thread_messages()

      _ ->
        []
    end
  end

  defp thread_messages(%Thread{} = thread) do
    thread
    |> Thread.to_list()
    |> Enum.flat_map(&thread_message/1)
  end

  defp thread_messages(_), do: []

  defp thread_message(%{kind: :ai_message, id: id, payload: %{role: role, content: content}})
       when role in [:user, :assistant] and is_binary(content) and content != "" do
    [%{id: id, role: role, content: content}]
  end

  defp thread_message(_), do: []

  defp latest_agent_report(nil), do: nil

  defp latest_agent_report(agent_id) do
    case Report.latest_for_session(agent_id) do
      {:ok, report} -> report
      :error -> nil
    end
  end

  defp maybe_put_reply_flash(socket, reply) when is_binary(reply), do: socket
  defp maybe_put_reply_flash(socket, %{text: _text}), do: socket

  defp maybe_put_reply_flash(socket, reply) do
    put_flash(
      socket,
      :info,
      "The agent returned a non-text response: #{inspect(reply, pretty: true, limit: 20)}"
    )
  end

  defp error_reply(reason) do
    "The agent request failed: #{inspect(reason, pretty: true, limit: 20)}"
  end

  defp chat_row_classes(:user), do: "flex justify-end"
  defp chat_row_classes(:assistant), do: "flex justify-start"

  defp role_label(:user), do: "You"
  defp role_label(:assistant), do: "Agent"

  defp render_markdown(content) when is_binary(content) do
    MDEx.new(@markdown_options)
    |> MDEx.Document.put_markdown(content)
    |> MDEx.to_html!()
    |> Phoenix.HTML.raw()
  end

  defp assistant_markdown_classes do
    "text-sm leading-6 text-base-content [&_a]:text-primary [&_a]:underline [&_blockquote]:border-l-2 [&_blockquote]:border-base-300 [&_blockquote]:pl-4 [&_code]:rounded-md [&_code]:bg-base-200 [&_code]:px-1.5 [&_code]:py-0.5 [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold [&_li]:mt-1 [&_ol]:my-4 [&_ol]:list-decimal [&_ol]:pl-6 [&_p+*]:mt-4 [&_pre]:my-4 [&_pre]:overflow-x-auto [&_pre]:rounded-2xl [&_pre]:bg-base-200/80 [&_pre]:p-4 [&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_strong]:font-semibold [&_ul]:my-4 [&_ul]:list-disc [&_ul]:pl-6"
  end

  defp report_block_classes(%Report.MetricBlock{}) do
    "rounded-[1.15rem] border border-base-300/60 bg-base-200/35 px-5 py-4"
  end

  defp report_block_classes(%Report.TextBlock{}) do
    "rounded-[1.15rem] border-l border-base-300/70 pl-5"
  end

  defp report_block_classes(_block) do
    "min-w-0 space-y-4"
  end

  defp chart_block_has_rows?(%Report.ChartBlock{row_count: row_count}) when is_integer(row_count),
    do: row_count > 0

  defp chart_block_has_rows?(_block), do: false

  defp message_classes(:user) do
    "max-w-[85%] rounded-[1.5rem] rounded-br-md bg-primary px-4 py-3 text-primary-content"
  end

  defp message_classes(:assistant) do
    "max-w-[92%] rounded-[1.5rem] rounded-bl-md bg-base-100 px-4 py-3 text-base-content ring-1 ring-base-300/60"
  end

  defp format_metric_value(value, :currency) when is_integer(value),
    do: "$" <> format_integer(value)

  defp format_metric_value(value, :currency) when is_float(value),
    do: "$" <> :erlang.float_to_binary(value, decimals: 2)

  defp format_metric_value(value, :percent) when is_number(value),
    do: :erlang.float_to_binary(value * 100, decimals: 1) <> "%"

  defp format_metric_value(value, _format), do: to_string(value)

  defp format_table_value(nil), do: "-"
  defp format_table_value(value), do: to_string(value)

  defp format_integer(value) do
    value
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp clear_pending_chat(socket) do
    socket
    |> assign(:chat_pending, false)
    |> assign(:chat_request_id, nil)
    |> assign(:pending_prompt, nil)
    |> assign(:pending_reply_content, nil)
  end

  defp revenue_trend_spec do
    monthly_revenue_data()
    |> Tucan.lineplot("month", "revenue",
      height: 260,
      width: :container,
      points: true,
      tooltip: :data,
      x: [type: :temporal, axis: [title: nil, format: "%b"]],
      y: [axis: [title: nil, format: "$,.0f"]]
    )
    |> style_spec()
    |> encode_spec()
  end

  defp category_revenue_spec do
    category_revenue_data()
    |> Tucan.bar("category", "revenue",
      height: 260,
      width: :container,
      tooltip: :data,
      orient: :horizontal,
      x: [axis: [title: nil, format: "$,.0f"]],
      y: [axis: [title: nil], sort: "-x"]
    )
    |> style_spec()
    |> encode_spec()
  end

  defp channel_mix_spec do
    channel_mix_data()
    |> Tucan.donut("revenue", "channel",
      height: 260,
      width: :container,
      tooltip: :data
    )
    |> style_spec()
    |> encode_spec()
  end

  defp customer_shape_spec do
    customer_shape_data()
    |> Tucan.scatter("avg_order_value", "orders",
      height: 260,
      width: :container,
      tooltip: :data,
      color_by: "segment",
      x: [axis: [title: "Average order value", format: "$,.0f"]],
      y: [axis: [title: "Orders"]]
    )
    |> Tucan.size_by("revenue")
    |> style_spec()
    |> encode_spec()
  end

  defp style_spec(vl) do
    vl
    |> Tucan.set_theme(:latimes)
    |> Vl.config(
      background: "transparent",
      view: [stroke: nil],
      legend: [title: nil, orient: :bottom, label_font_size: 11],
      axis: [grid_color: "#E5E7EB", domain: false, tick_color: "#CBD5E1", label_color: "#475569"]
    )
  end

  defp encode_spec(vl) do
    vl
    |> Vl.to_spec()
    |> Jason.encode!()
  end

  defp monthly_revenue_data do
    [
      %{month: ~D[2024-01-01], revenue: 48_200},
      %{month: ~D[2024-02-01], revenue: 52_800},
      %{month: ~D[2024-03-01], revenue: 57_600},
      %{month: ~D[2024-04-01], revenue: 61_400},
      %{month: ~D[2024-05-01], revenue: 66_900},
      %{month: ~D[2024-06-01], revenue: 64_100},
      %{month: ~D[2024-07-01], revenue: 72_300},
      %{month: ~D[2024-08-01], revenue: 76_800}
    ]
  end

  defp category_revenue_data do
    [
      %{category: "Beverages", revenue: 267_900},
      %{category: "Dairy", revenue: 234_500},
      %{category: "Confections", revenue: 167_400},
      %{category: "Meat", revenue: 163_000},
      %{category: "Seafood", revenue: 131_300}
    ]
  end

  defp channel_mix_data do
    [
      %{channel: "Direct", revenue: 228_000},
      %{channel: "Partners", revenue: 154_000},
      %{channel: "Inbound", revenue: 96_000},
      %{channel: "Expansion", revenue: 72_000}
    ]
  end

  defp customer_shape_data do
    [
      %{
        customer: "QuickStop",
        orders: 26,
        avg_order_value: 4_240,
        revenue: 110_200,
        segment: "Enterprise"
      },
      %{
        customer: "Ernst Handel",
        orders: 24,
        avg_order_value: 4_360,
        revenue: 104_900,
        segment: "Enterprise"
      },
      %{
        customer: "Save-a-lot",
        orders: 23,
        avg_order_value: 4_100,
        revenue: 104_400,
        segment: "Enterprise"
      },
      %{
        customer: "Hungry Owl",
        orders: 14,
        avg_order_value: 3_570,
        revenue: 50_000,
        segment: "Growth"
      },
      %{
        customer: "Rattlesnake",
        orders: 13,
        avg_order_value: 3_930,
        revenue: 51_100,
        segment: "Growth"
      },
      %{
        customer: "Hanari",
        orders: 9,
        avg_order_value: 3_650,
        revenue: 32_800,
        segment: "Mid-market"
      },
      %{
        customer: "White Clover",
        orders: 8,
        avg_order_value: 3_420,
        revenue: 27_400,
        segment: "Mid-market"
      },
      %{
        customer: "Folk och fa HB",
        orders: 7,
        avg_order_value: 4_220,
        revenue: 29_600,
        segment: "Mid-market"
      }
    ]
  end
end
