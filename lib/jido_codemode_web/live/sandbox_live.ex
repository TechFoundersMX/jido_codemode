defmodule JidoCodemodeWeb.SandboxLive do
  use JidoCodemodeWeb, :live_view

  alias Jido.AI, as: JidoAI
  alias Jido.Thread
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
    chat_unlocked = is_nil(demo_password())

    socket =
      socket
      |> assign(:page_title, "Agentic BI")
      |> assign(:charts, build_charts())
      |> assign(:agent_id, nil)
      |> assign(:agent_pid, nil)
      |> assign(:chat_form, chat_form())
      |> assign(:unlock_form, unlock_form())
      |> assign(:unlock_error, nil)
      |> assign(:chat_unlocked, chat_unlocked)
      |> assign(:chat_messages, [])
      |> assign(:agent_report, nil)
      |> assign(:chat_pending, false)
      |> assign(:chat_request_id, nil)
      |> assign(:pending_prompt, nil)
      |> assign(:pending_reply_content, nil)

    socket =
      if connected?(socket) and chat_unlocked do
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
    if socket.assigns.chat_unlocked do
      submit_prompt(socket, prompt)
    else
      {:noreply, socket}
    end
  end

  def handle_event("unlock_chat", %{"unlock" => %{"password" => password}}, socket) do
    if valid_demo_password?(password) do
      {:noreply,
       socket
       |> assign(:chat_unlocked, true)
       |> assign(:unlock_form, unlock_form())
       |> assign(:unlock_error, nil)
       |> start_sidebar_agent()}
    else
      {:noreply,
       socket
       |> assign(:unlock_form, unlock_form())
       |> assign(:unlock_error, "That password is not correct.")}
    end
  end

  def handle_event("use_suggestion", %{"prompt" => prompt}, socket) do
    if socket.assigns.chat_unlocked do
      submit_prompt(socket, prompt)
    else
      {:noreply, socket}
    end
  end

  def handle_event("reset_chat", _params, socket) do
    {:noreply,
     socket
     |> stop_sidebar_agent()
     |> assign(:chat_form, chat_form())
     |> assign(:chat_messages, [])
     |> assign(:agent_report, nil)
     |> clear_pending_chat()
     |> maybe_start_sidebar_agent()}
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
      app_chrome={false}
      full_width={true}
      main_class="min-h-dvh isolate"
      content_class="mx-auto max-w-[96rem] px-4 py-4 sm:px-6 lg:px-8 lg:py-5"
    >
      <section class="space-y-5">
        <header class="grid gap-5 border-b border-base-300/70 pb-5 md:grid-cols-[minmax(0,1fr)_auto] md:items-start">
          <div class="grid min-w-0 gap-4">
            <a href={~p"/"} aria-label="Homepage" class="flex w-fit items-center gap-3">
              <img
                src={~p"/images/agentic-bi-mark.svg"}
                alt=""
                class="size-10 shrink-0 rounded-xl"
              />
              <div class="min-w-0">
                <p class="font-mono text-xs font-semibold uppercase tracking-[0.16em] text-primary">
                  Decision intelligence
                </p>
                <p class="font-semibold tracking-tight text-base-content">Agentic BI</p>
              </div>
            </a>

            <div class="grid gap-2">
              <h1 class="max-w-[35ch] text-3xl font-semibold tracking-tight text-balance text-base-content sm:text-4xl">
                Turn business questions into clear analysis
              </h1>
              <p class="max-w-[56ch] text-base leading-7 text-pretty text-base-content/65">
                Explore your data with an agent that can query, compare, visualize, and explain
                its findings.
              </p>
            </div>
          </div>

          <div class="flex flex-wrap items-center gap-2 md:max-w-lg md:justify-end">
            <Layouts.theme_toggle />

            <details class="group open:w-full sm:relative sm:open:w-auto">
              <summary class="inline-flex w-fit cursor-pointer list-none rounded-full px-3 py-2 text-sm font-medium text-base-content/65 ring-1 ring-base-300/70 hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
                How it works
              </summary>
              <div class="mt-2 w-full rounded-2xl bg-base-100 p-4 text-base leading-7 text-base-content/70 shadow-lg ring-1 ring-base-300 sm:absolute sm:right-0 sm:z-20 sm:w-88 sm:text-sm sm:leading-6 [[data-theme=dark]_&]:shadow-none">
                <ol class="list-decimal space-y-2 pl-5">
                  <li>The agent reads a compact schema through a read-only connection.</li>
                  <li>It runs bounded queries and builds the needed metrics and visuals.</li>
                  <li>Every result is validated before it appears in your analysis.</li>
                </ol>
              </div>
            </details>
          </div>
        </header>

        <section class="grid gap-5 lg:grid-cols-[minmax(0,1fr)_23rem] lg:items-start 2xl:grid-cols-[minmax(0,1fr)_26rem]">
          <div class="order-2 min-w-0 space-y-5 lg:order-1">
            <section
              :if={@agent_report}
              id="agent-report"
              class="@container/report space-y-6 rounded-2xl bg-base-100 p-5 ring-1 ring-base-300/70 sm:p-6"
            >
              <div class="space-y-2">
                <p class="font-mono text-xs font-semibold uppercase tracking-[0.16em] text-secondary">
                  Generated analysis
                </p>
                <h2 class="text-2xl font-semibold tracking-tight text-base-content sm:text-3xl">
                  {@agent_report.title}
                </h2>
                <p
                  :if={@agent_report.summary}
                  class="max-w-3xl text-base leading-7 text-base-content/65"
                >
                  {@agent_report.summary}
                </p>
              </div>

              <div class="grid grid-cols-1 gap-6 @4xl/report:grid-cols-2">
                <div :for={block <- @agent_report.blocks} class={report_block_classes(block)}>
                  <%= case block do %>
                    <% %Report.TextBlock{} -> %>
                      <div class={assistant_markdown_classes()}>{render_markdown(block.body)}</div>
                    <% %Report.MetricBlock{} -> %>
                      <div class="space-y-2">
                        <p class="font-mono text-xs font-semibold uppercase tracking-[0.14em] text-base-content/45">
                          Metric
                        </p>
                        <p class="truncate text-sm text-base-content/60" title={block.label}>
                          {block.label}
                        </p>
                        <p class="text-4xl font-semibold tracking-tight tabular-nums text-base-content">
                          {format_metric_value(block.value, block.format)}
                        </p>
                      </div>
                    <% %Report.TableBlock{} -> %>
                      <div class="space-y-4">
                        <div class="space-y-1">
                          <h3 class="text-xl font-semibold tracking-tight text-base-content">
                            {block.title}
                          </h3>
                          <p
                            :if={block.summary}
                            class="text-base leading-7 text-base-content/60 sm:text-sm sm:leading-6"
                          >
                            {block.summary}
                          </p>
                        </div>

                        <div
                          :if={Enum.empty?(block.rows)}
                          class="py-8 text-base text-base-content/45 sm:text-sm"
                        >
                          No rows to show for this table.
                        </div>

                        <div
                          :if={not Enum.empty?(block.rows)}
                          class="-mx-5 -my-2 overflow-x-auto whitespace-nowrap sm:-mx-6"
                        >
                          <div class="inline-block min-w-full px-5 py-2 align-middle sm:px-6">
                            <table class="w-full border-separate border-spacing-0 text-base sm:text-sm">
                              <thead>
                                <tr>
                                  <th
                                    :for={column <- block.columns}
                                    class="whitespace-nowrap border-b border-base-300/70 px-0 py-3 pr-6 text-left text-base font-semibold text-base-content/60 sm:text-sm"
                                  >
                                    {column}
                                  </th>
                                </tr>
                              </thead>
                              <tbody>
                                <tr :for={row <- block.rows}>
                                  <td
                                    :for={column <- block.columns}
                                    class="whitespace-nowrap border-b border-base-300/55 px-0 py-3 pr-6 text-base-content/75 last:pr-0"
                                  >
                                    {format_table_value(Map.get(row, column))}
                                  </td>
                                </tr>
                              </tbody>
                            </table>
                          </div>
                        </div>
                      </div>
                    <% %Report.ChartBlock{} -> %>
                      <div class="space-y-4">
                        <div class="space-y-1">
                          <h3 class="text-xl font-semibold tracking-tight text-base-content">
                            {block.title}
                          </h3>
                          <p
                            :if={block.summary}
                            class="text-base leading-7 text-base-content/60 sm:text-sm sm:leading-6"
                          >
                            {block.summary}
                          </p>
                        </div>

                        <div
                          :if={not chart_block_has_rows?(block)}
                          class="py-8 text-base text-base-content/45 sm:text-sm"
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

            <section
              :if={is_nil(@agent_report)}
              class="flex min-h-72 items-center justify-center rounded-2xl border border-dashed border-base-300 bg-base-100/40 px-6 py-12 text-center"
            >
              <div class="max-w-md space-y-3">
                <.icon name="hero-chart-bar-square-micro" class="mx-auto size-4 text-primary" />
                <h2 class="text-xl font-semibold tracking-tight text-base-content">
                  Your analysis will appear here
                </h2>
                <p class="text-base leading-7 text-base-content/60">
                  Ask the analysis agent for a chart, table, metric, or complete report.
                </p>
              </div>
            </section>

            <details class="group rounded-2xl bg-base-100 ring-1 ring-base-300/70">
              <summary class="flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-4 sm:px-6">
                <div>
                  <p class="font-mono text-xs font-semibold uppercase tracking-[0.16em] text-primary">
                    Example analyses
                  </p>
                  <h2 class="mt-1 text-lg font-semibold tracking-tight text-base-content">
                    See what Agentic BI can build
                  </h2>
                </div>
                <.icon
                  name="hero-chevron-down"
                  class="size-4 shrink-0 text-base-content/50 group-open:rotate-180"
                />
              </summary>

              <div class="space-y-5 border-t border-base-300/70 p-5 sm:p-6">
                <div class="flex justify-end">
                  <button
                    type="button"
                    phx-click="reset_chat"
                    class="rounded-full px-3 py-2 text-sm font-medium text-base-content/65 ring-1 ring-base-300 hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                  >
                    Restart session
                  </button>
                </div>

                <div class="grid grid-cols-1 gap-8 lg:grid-cols-2">
                  <article :for={chart <- @charts} id={"chart-card-#{chart.id}"} class="space-y-4">
                    <div class="space-y-1">
                      <p class="font-mono text-xs font-semibold uppercase tracking-[0.14em] text-base-content/45">
                        {chart.kicker}
                      </p>
                      <h3 class="text-xl font-semibold tracking-tight text-base-content">
                        {chart.title}
                      </h3>
                      <p class="text-base leading-7 text-pretty text-base-content/55 sm:text-sm sm:leading-6">
                        {chart.description}
                      </p>
                    </div>

                    <div class="overflow-hidden border-t border-base-300/70 pt-3">
                      <div
                        id={"sample-chart-#{chart.id}"}
                        phx-hook=".VegaChart"
                        data-spec={chart.spec_json}
                        class="min-h-72 w-full"
                      />
                    </div>
                  </article>
                </div>
              </div>
            </details>
          </div>

          <aside class="order-1 min-w-0 lg:order-2 lg:sticky lg:top-5">
            <section class="flex h-120 min-h-120 flex-col overflow-hidden rounded-2xl bg-base-100 ring-1 ring-base-300/70 lg:h-[clamp(34rem,calc(100dvh-14rem),44rem)] lg:min-h-0">
              <header class="shrink-0 border-b border-base-300/70 px-5 py-4">
                <div class="flex items-start justify-between gap-4">
                  <div>
                    <p class="font-mono text-xs font-semibold uppercase tracking-[0.16em] text-secondary">
                      Analysis agent
                    </p>
                    <h2 class="mt-1 text-xl font-semibold tracking-tight text-base-content">
                      Ask about Northwind
                    </h2>
                  </div>
                  <span class="inline-flex items-center gap-1.5 text-xs text-base-content/50">
                    <span
                      class={[
                        "size-2 rounded-full",
                        @chat_unlocked && "bg-success",
                        not @chat_unlocked && "bg-warning"
                      ]}
                      aria-hidden="true"
                    >
                    </span>
                    {if @chat_unlocked, do: "Ready", else: "Locked"}
                  </span>
                </div>
                <p class="mt-2 text-base leading-7 text-pretty text-base-content/60 sm:text-sm sm:leading-6">
                  Ask a business question or request a complete analysis.
                </p>
              </header>

              <div class="shrink-0 border-b border-base-300/70 px-5 py-3">
                <div class="flex items-center gap-2">
                  <button
                    :for={suggestion <- Enum.take(suggestion_prompts(), 2)}
                    type="button"
                    phx-click="use_suggestion"
                    phx-value-prompt={suggestion.prompt}
                    disabled={not @chat_unlocked}
                    class="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-base-200 py-2 pr-3 pl-2 text-sm font-medium text-base-content ring-1 ring-base-300/70 hover:bg-base-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                  >
                    <.icon name={suggestion.icon} class="size-4 shrink-0 text-primary" />
                    <span class="truncate">{suggestion.label}</span>
                  </button>

                  <details class="group relative shrink-0">
                    <summary class="cursor-pointer list-none rounded-full px-3 py-2 text-sm font-medium text-base-content/65 ring-1 ring-base-300/70 hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
                      More
                    </summary>
                    <div class="absolute right-0 z-20 mt-2 w-72 space-y-1 rounded-xl bg-base-100 p-2 shadow-lg ring-1 ring-base-300 [[data-theme=dark]_&]:shadow-none">
                      <button
                        :for={suggestion <- Enum.drop(suggestion_prompts(), 2)}
                        type="button"
                        phx-click="use_suggestion"
                        phx-value-prompt={suggestion.prompt}
                        disabled={not @chat_unlocked}
                        class="flex w-full items-center gap-2 rounded-lg py-2 pr-3 pl-2 text-left text-sm font-medium text-base-content hover:bg-base-200 focus-visible:outline-2 focus-visible:outline-primary"
                      >
                        <.icon name={suggestion.icon} class="size-4 shrink-0 text-primary" />
                        <span class="min-w-0">{suggestion.label}</span>
                      </button>
                    </div>
                  </details>
                </div>
              </div>

              <div class="min-h-0 flex-1 overflow-y-auto bg-base-200/40 px-4 py-4">
                <div
                  :if={not show_chat_conversation?(@chat_messages, @pending_prompt, @chat_pending)}
                  class="flex h-full min-h-48 items-center justify-center text-center"
                >
                  <div class="max-w-xs space-y-2">
                    <.icon name="hero-sparkles-micro" class="mx-auto size-4 text-primary" />
                    <p class="font-medium text-base-content">Start with a prompt</p>
                    <p class="text-base leading-7 text-pretty text-base-content/55 sm:text-sm sm:leading-6">
                      Select an example above or describe the decision you want to support.
                    </p>
                  </div>
                </div>

                <div
                  :if={show_chat_conversation?(@chat_messages, @pending_prompt, @chat_pending)}
                  class="space-y-4"
                >
                  <div class="space-y-4">
                    <div :for={message <- @chat_messages} class={chat_row_classes(message.role)}>
                      <div class={message_classes(message.role)}>
                        <p class="mb-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] opacity-60">
                          {role_label(message.role)}
                        </p>
                        <div :if={message.role == :assistant} class={assistant_markdown_classes()}>
                          {render_markdown(message.content)}
                        </div>
                        <p
                          :if={message.role == :user}
                          class="text-base leading-7 sm:text-sm sm:leading-6"
                        >
                          {message.content}
                        </p>
                      </div>
                    </div>

                    <div :if={@pending_prompt} class="flex justify-end">
                      <div class={message_classes(:user)}>
                        <p class="mb-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] opacity-60">
                          You
                        </p>
                        <p class="text-base leading-7 sm:text-sm sm:leading-6">{@pending_prompt}</p>
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

              <.form
                :if={not @chat_unlocked}
                id="unlock-form"
                for={@unlock_form}
                phx-submit="unlock_chat"
                class="shrink-0 space-y-3 border-t border-base-300/70 px-4 py-4"
              >
                <div class="space-y-1">
                  <label
                    for={@unlock_form[:password].id}
                    class="text-sm font-medium text-base-content"
                  >
                    Demo password
                  </label>
                  <p class="text-sm leading-5 text-base-content/55">
                    Enter the password to unlock the analysis agent.
                  </p>
                </div>

                <div class="flex gap-2">
                  <.input
                    field={@unlock_form[:password]}
                    type="password"
                    autocomplete="current-password"
                    placeholder="Password"
                    aria-invalid={not is_nil(@unlock_error)}
                    aria-describedby={@unlock_error && "unlock-error"}
                    class="min-w-0 flex-1 rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-base text-base-content shadow-none outline-none focus:border-primary focus:ring-0"
                  />
                  <button
                    type="submit"
                    class="inline-flex shrink-0 items-center justify-center rounded-lg bg-primary px-3 py-2.5 text-sm font-semibold text-primary-content hover:brightness-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                  >
                    Unlock
                  </button>
                </div>

                <p :if={@unlock_error} id="unlock-error" class="text-sm text-error" role="alert">
                  {@unlock_error}
                </p>
              </.form>

              <.form
                :if={@chat_unlocked}
                id="chat-form"
                for={@chat_form}
                phx-submit="submit_chat"
                class="shrink-0 space-y-3 border-t border-base-300/70 px-4 py-4"
              >
                <.input
                  field={@chat_form[:prompt]}
                  type="textarea"
                  placeholder="Ask about revenue, customers, products, or trends"
                  rows="2"
                  disabled={@chat_pending}
                  class="w-full resize-none rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-base text-base-content shadow-none outline-none focus:border-primary focus:ring-0 disabled:cursor-not-allowed disabled:opacity-60"
                />

                <div class="flex items-center justify-between gap-3">
                  <p class="text-sm leading-5 text-base-content/50">
                    Connected with read-only access
                  </p>

                  <button
                    type="submit"
                    class="inline-flex shrink-0 items-center justify-center rounded-lg bg-primary px-3 py-2.5 text-sm font-semibold text-primary-content hover:brightness-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-60"
                    disabled={@chat_pending}
                  >
                    {if @chat_pending, do: "Analyzing...", else: "Send"}
                  </button>
                </div>
              </.form>
            </section>
          </aside>
        </section>
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

  defp unlock_form do
    to_form(%{"password" => ""}, as: :unlock)
  end

  defp demo_password do
    case Application.get_env(:jido_codemode, :demo_password) do
      password when is_binary(password) and password != "" -> password
      _ -> nil
    end
  end

  defp valid_demo_password?(password) when is_binary(password) do
    case demo_password() do
      expected when is_binary(expected) and byte_size(password) == byte_size(expected) ->
        Plug.Crypto.secure_compare(password, expected)

      _ ->
        false
    end
  end

  defp valid_demo_password?(_password), do: false

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

  defp maybe_start_sidebar_agent(socket) do
    if socket.assigns.chat_unlocked do
      start_sidebar_agent(socket)
    else
      socket
    end
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
      %{
        icon: "hero-chart-bar-micro",
        label: "Revenue trend",
        prompt: "Show a monthly revenue trend"
      },
      %{
        icon: "hero-squares-2x2-micro",
        label: "Top categories",
        prompt: "Compare the top categories"
      },
      %{
        icon: "hero-users-micro",
        label: "Top customers",
        prompt: "List the top customers by revenue"
      },
      %{
        icon: "hero-circle-stack-micro",
        label: "Important joins",
        prompt: "Describe the most important joins"
      },
      %{
        icon: "hero-sparkles-micro",
        label: "Complete analysis",
        prompt: "Build a short analysis with a chart and a table"
      }
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
  defp role_label(:assistant), do: "Agentic BI"

  defp render_markdown(content) when is_binary(content) do
    MDEx.new(@markdown_options)
    |> MDEx.Document.put_markdown(content)
    |> MDEx.to_html!()
    |> Phoenix.HTML.raw()
  end

  defp assistant_markdown_classes do
    "text-base leading-7 text-base-content sm:text-sm sm:leading-6 [&_a]:text-primary [&_a]:underline [&_blockquote]:border-l-2 [&_blockquote]:border-base-300 [&_blockquote]:pl-4 [&_code]:rounded-md [&_code]:bg-base-200 [&_code]:px-1.5 [&_code]:py-0.5 [&_h1]:text-xl [&_h1]:font-semibold [&_h2]:text-lg [&_h2]:font-semibold [&_h3]:font-semibold [&_li]:mt-1 [&_ol]:my-4 [&_ol]:list-decimal [&_ol]:pl-6 [&_p+*]:mt-4 [&_pre]:my-4 [&_pre]:overflow-x-auto [&_pre]:rounded-2xl [&_pre]:bg-base-200/80 [&_pre]:p-4 [&_pre_code]:bg-transparent [&_pre_code]:p-0 [&_strong]:font-semibold [&_ul]:my-4 [&_ul]:list-disc [&_ul]:pl-6"
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
      font: "Geist",
      mark: [color: "#2563EB"],
      view: [stroke: nil],
      range: [category: ["#2563EB", "#0F8B8D", "#D97706", "#0891B2", "#71717A"]],
      legend: [title: nil, orient: :bottom, label_font: "Geist", label_font_size: 11],
      axis: [
        grid_color: "#DCE1E8",
        domain: false,
        tick_color: "#DCE1E8",
        label_color: "#52525B",
        label_font: "Geist",
        title_font: "Geist"
      ]
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
