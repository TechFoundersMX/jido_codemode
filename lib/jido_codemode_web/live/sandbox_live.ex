defmodule JidoCodemodeWeb.SandboxLive do
  use JidoCodemodeWeb, :live_view

  alias Jido.AI, as: JidoAI
  alias Jido.Thread
  alias JidoCodemode.Agent.Report
  alias JidoCodemode.DemoAccess
  alias JidoCodemode.Locale
  alias JidoCodemode.Locale.{Dataset, Format}
  alias JidoCodemode.SidebarAgent
  alias JidoCodemodeWeb.{LandingCharts, LandingExamples, Links, SiteChrome}

  @markdown_options [
    auto_close: true,
    extension: [autolink: true, strikethrough: true, table: true, tasklist: true],
    render: [hardbreaks: true],
    sanitize: MDEx.Document.default_sanitize_options()
  ]

  @impl true
  def mount(_params, session, socket) do
    access = access(session["demo_access"])

    # Once the invitation service is connected, only invitees see the agent:
    # everyone else goes to its self-serve form (partner contract, 29 Sep 2026).
    if DemoAccess.enabled?() and access.state not in [:invited, :exhausted] do
      {:ok, redirect(socket, to: Links.access_request())}
    else
      mount_demo(socket, access)
    end
  end

  defp mount_demo(socket, access) do
    unlocked_by =
      cond do
        access.state == :invited -> :invite
        access.state == :exhausted -> nil
        is_nil(demo_password()) -> :open
        true -> nil
      end

    chat_unlocked = not is_nil(unlocked_by)

    socket =
      socket
      |> assign(:page_title, page_title())
      |> assign(:access, access)
      |> assign(:unlocked_by, unlocked_by)
      |> assign(:conversation_id, nil)
      |> assign(:conversation_paid, false)
      |> assign(:currency, Dataset.currency(socket.assigns.locale))
      |> assign(:examples, LandingExamples.all(socket.assigns.locale))
      |> assign(:locale_notice, nil)
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
       |> assign(:unlocked_by, :password)
       |> assign(:unlock_form, unlock_form())
       |> assign(:unlock_error, nil)
       |> start_sidebar_agent()}
    else
      {:noreply,
       socket
       |> assign(:unlock_form, unlock_form())
       |> assign(:unlock_error, :invalid_password)}
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
    {:noreply, socket |> assign(:locale_notice, nil) |> restart_conversation()}
  end

  def handle_event("set_locale", %{"locale" => value}, socket) do
    case Locale.normalize(value) do
      nil ->
        {:noreply, socket}

      locale when locale == socket.assigns.locale ->
        {:noreply, socket}

      locale ->
        Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)

        socket =
          socket
          |> assign(:locale, locale)
          |> assign(:page_title, page_title())
          |> assign(:currency, Dataset.currency(locale))
          |> assign(:examples, LandingExamples.all(locale))

        socket =
          if socket.assigns.chat_unlocked do
            socket
            |> restart_conversation()
            |> assign(:locale_notice, locale_notice(locale, socket.assigns.currency))
          else
            socket
          end

        {:noreply,
         socket
         |> push_event("locale-changed", %{
           locale: locale,
           html_lang: Locale.html_lang(locale),
           title: socket.assigns.page_title
         })
         |> push_patch(to: ~p"/demo?lang=#{lang_param(locale)}")}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # Invitees are demo testers in Odoo (source 73); everyone else is the landing's funnel.
  defp call_url(:invite), do: Links.calendar(:demo_invitee)
  defp call_url(_unlocked_by), do: Links.calendar(:landing)

  defp page_title, do: "Agentic BI · " <> gettext("Decision-ready analysis")

  defp access(%{"state" => "invited", "remaining" => remaining, "ref" => ref})
       when is_integer(remaining) and is_binary(ref),
       do: %{state: :invited, remaining: remaining, ref: ref}

  defp access(%{"state" => "exhausted"}), do: %{state: :exhausted}
  defp access(%{"state" => "expired"}), do: %{state: :expired}
  defp access(_none), do: %{state: :public}

  defp lang_param("es_MX"), do: "es"
  defp lang_param(_locale), do: "en"

  defp unlock_error_text(:invalid_password), do: gettext("That password is not correct.")

  defp restart_conversation(socket) do
    socket
    |> stop_sidebar_agent()
    |> assign(:chat_form, chat_form())
    |> assign(:chat_messages, [])
    |> assign(:agent_report, nil)
    |> clear_pending_chat()
    |> maybe_start_sidebar_agent()
  end

  defp locale_notice("es_MX", :mxn),
    do: gettext("You switched to Spanish. Figures are now in MXN.")

  defp locale_notice("es_MX", _currency), do: gettext("You switched to Spanish.")

  defp locale_notice(_locale, _currency),
    do: gettext("You switched to English. Figures are now in USD.")

  @doc false
  def tool_context(socket),
    do: %{session_id: socket.assigns.agent_id, locale: socket.assigns.locale}

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
  def handle_async({:agent_reply, request_id}, {:ok, {use, result}}, socket) do
    if socket.assigns.chat_request_id == request_id do
      {:noreply, socket |> apply_use(use) |> finish_reply(result)}
    else
      {:noreply, socket}
    end
  end

  def handle_async({:agent_reply, request_id}, {:exit, reason}, socket) do
    if socket.assigns.chat_request_id == request_id do
      {:noreply, finish_reply(socket, {:error, reason})}
    else
      {:noreply, socket}
    end
  end

  defp finish_reply(socket, result) do
    socket =
      socket
      |> refresh_chat_messages()
      |> refresh_agent_report()
      |> clear_pending_chat()

    case result do
      {:ok, reply} -> maybe_put_reply_flash(socket, reply)
      {:error, {:access, reason}} -> put_flash(socket, :error, access_error(reason))
      {:error, reason} -> put_flash(socket, :error, error_reply(reason))
    end
  end

  # What the invitation service did for this turn (see run_turn/2).
  defp apply_use(socket, :none), do: socket
  # The refunded id is spent on the service's side: the next question starts a new one.
  defp apply_use(socket, :refunded),
    do: assign(socket, conversation_id: uuid4(), conversation_paid: false)

  defp apply_use(socket, {:consumed, remaining}) do
    socket
    |> assign(:conversation_paid, true)
    |> assign(:access, %{socket.assigns.access | remaining: remaining})
  end

  defp apply_use(socket, {:denied, :exhausted}) do
    socket
    |> assign(:chat_unlocked, false)
    |> assign(:unlocked_by, nil)
    |> assign(:access, %{state: :exhausted})
  end

  # The invitation is gone (expired or revoked): back to the request form.
  defp apply_use(socket, {:denied, :invalid}), do: redirect(socket, to: Links.access_request())

  defp apply_use(socket, {:denied, _unavailable}), do: socket

  defp access_error(:exhausted), do: gettext("Your invitation has no conversations left.")
  defp access_error(:invalid), do: gettext("Your invitation is no longer available.")

  defp access_error(_unavailable),
    do: gettext("We couldn't check your invitation. Reload the page and try again.")

  @doc """
  Runs one agent turn. For an invitee's first question in a conversation, spends
  one use first, and gives it back once if the turn gets no answer. Returns
  `{use, result}` where `result` is `{:ok, reply}` or `{:error, reason}`.
  """
  def run_turn(nil, ask), do: {:none, safe_ask(ask)}

  def run_turn({token, conversation_id}, ask) do
    case DemoAccess.consume(token, conversation_id) do
      {:ok, remaining} ->
        case safe_ask(ask) do
          {:ok, _reply} = ok ->
            {{:consumed, remaining}, ok}

          error ->
            _ = DemoAccess.refund(token, conversation_id)
            {:refunded, error}
        end

      {:error, reason} ->
        {{:denied, reason}, {:error, {:access, reason}}}
    end
  end

  defp safe_ask(ask) do
    case ask.() do
      {:ok, _reply} = ok -> ok
      {:error, _reason} = error -> error
      other -> {:error, other}
    end
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      locale={@locale}
      app_chrome={false}
      full_width={true}
      main_class="min-h-dvh isolate bg-base-200"
      content_class=""
    >
      <%!-- Keyed iteration over [@locale] re-renders the page copy in full only when the locale changes: gettext text has no assigns, so change tracking would otherwise skip it. Without the :key, every assign change would re-send the whole section. --%>
      <div :for={loc <- [@locale]} :key={loc}>
        <div class="lp lp-chrome">
          <SiteChrome.site_header
            locale={loc}
            base="/"
            id_prefix="locale-"
            call_url={call_url(@unlocked_by)}
          />
        </div>

        <section class="mx-auto max-w-[96rem] space-y-5 px-4 py-5 sm:px-6 lg:px-8">
          <header class="grid max-w-3xl gap-2">
            <p class="font-mono text-xs font-semibold uppercase tracking-[0.08em] text-primary">
              {gettext("Live agent · sample data")}
            </p>
            <h1 class="text-3xl font-bold tracking-tight text-balance text-base-content sm:text-4xl">
              {gettext("Ask the sample distributor.")}
            </h1>
            <p class="max-w-[62ch] text-base leading-7 text-pretty text-base-content/70">
              {gettext(
                "A fictitious distributor with orders from 2012 to 2014. Ask in plain language: the agent reads the data without changing it, and every answer comes with the number, a chart and a table."
              )}
            </p>
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
                    {gettext("Generated analysis")}
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
                            {gettext("Metric")}
                          </p>
                          <p class="truncate text-sm text-base-content/60" title={block.label}>
                            {block.label}
                          </p>
                          <p class="text-4xl font-semibold tracking-tight tabular-nums text-base-content">
                            {format_metric_value(block.value, block.format, @currency)}
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
                            {gettext("No rows to show for this table.")}
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
                                      {format_table_value(Map.get(row, column), column)}
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
                            {gettext("No rows to show for this chart.")}
                          </div>

                          <div :if={chart_block_has_rows?(block)} class="overflow-hidden">
                            <div
                              id={"report-chart-#{block.id}"}
                              phx-hook=".VegaChart"
                              data-spec={block.spec_json}
                              data-locale={Locale.html_lang(@locale)}
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
                    {gettext("Your analysis will appear here")}
                  </h2>
                  <p class="text-base leading-7 text-base-content/60">
                    {gettext("Ask the analysis agent for a chart, table, metric, or complete report.")}
                  </p>
                </div>
              </section>

              <div class="lp lp-chrome">
                <div class="panel" id="ejemplos">
                  <div class="sec-head">
                    <p class="eyebrow">{gettext("What you can ask")}</p>
                    <h2>{gettext("Ask it what you ask someone on your team today.")}</h2>
                  </div>
                  <div class="gallery" id={"demo-gallery-#{loc}"}>
                    <article :for={example <- @examples} class="ex" id={"ex-#{example.id}"}>
                      <div class="kind"><span class={"t#{example.tone}"}>{example.kind}</span></div>
                      <p class="prompt">{example.question}</p>
                      <p class="say">{example.answer}</p>
                      <div class="viz"><LandingCharts.viz example={example} /></div>
                      <button
                        type="button"
                        class="ask lp-btn lp-btn-secondary lp-btn-sm"
                        phx-click="use_suggestion"
                        phx-value-prompt={example.question}
                        disabled={not @chat_unlocked or @chat_pending}
                      >
                        {gettext("Ask this")}
                      </button>
                    </article>
                  </div>
                </div>
              </div>
            </div>

            <aside class="order-1 min-w-0 lg:order-2 lg:sticky lg:top-20">
              <section class="flex h-120 min-h-120 flex-col overflow-hidden rounded-2xl bg-base-100 ring-1 ring-base-300/70 lg:h-[clamp(34rem,calc(100dvh-14rem),44rem)] lg:min-h-0">
                <header class="shrink-0 border-b border-base-300/70 px-5 py-4">
                  <div class="flex items-start justify-between gap-4">
                    <div>
                      <p class="font-mono text-xs font-semibold uppercase tracking-[0.16em] text-secondary">
                        {gettext("Analysis agent")}
                      </p>
                      <h2 class="mt-1 text-xl font-semibold tracking-tight text-base-content">
                        {gettext("Ask about Northwind")}
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
                      {if @chat_unlocked, do: gettext("Ready"), else: gettext("Locked")}
                    </span>
                    <button
                      :if={@chat_unlocked}
                      id="new-conversation"
                      type="button"
                      phx-click="reset_chat"
                      disabled={@chat_pending}
                      class="rounded-full px-3 py-1.5 text-xs font-medium text-base-content/70 ring-1 ring-base-300 hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50"
                    >
                      {gettext("New conversation")}
                    </button>
                  </div>
                  <p class="mt-2 text-base leading-7 text-pretty text-base-content/60 sm:text-sm sm:leading-6">
                    {gettext("Ask a business question or request a complete analysis.")}
                  </p>
                </header>

                <div class="shrink-0 border-b border-base-300/70 px-5 py-3">
                  <div class="flex items-center gap-2">
                    <button
                      :for={suggestion <- Enum.take(suggestion_prompts(), 2)}
                      type="button"
                      phx-click="use_suggestion"
                      phx-value-prompt={suggestion.prompt}
                      title={suggestion.prompt}
                      disabled={not @chat_unlocked}
                      class="inline-flex min-w-0 items-center gap-1.5 rounded-full bg-base-200 py-2 pr-3 pl-2 text-sm font-medium text-base-content ring-1 ring-base-300/70 hover:bg-base-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                    >
                      <.icon name={suggestion.icon} class="size-4 shrink-0 text-primary" />
                      <span class="truncate">{suggestion.label}</span>
                    </button>

                    <details class="group relative shrink-0">
                      <summary class="cursor-pointer list-none rounded-full px-3 py-2 text-sm font-medium text-base-content/65 ring-1 ring-base-300/70 hover:bg-base-200 hover:text-base-content focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary">
                        {gettext("More")}
                      </summary>
                      <div class="absolute right-0 z-20 mt-2 w-72 space-y-1 rounded-xl bg-base-100 p-2 shadow-lg ring-1 ring-base-300 [[data-theme=dark]_&]:shadow-none">
                        <button
                          :for={suggestion <- Enum.drop(suggestion_prompts(), 2)}
                          type="button"
                          phx-click="use_suggestion"
                          phx-value-prompt={suggestion.prompt}
                          title={suggestion.prompt}
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
                  <p
                    :if={@locale_notice}
                    id="locale-notice"
                    class="mb-4 rounded-lg bg-base-200/70 px-3 py-2 text-sm text-base-content/75"
                  >
                    {@locale_notice}
                  </p>

                  <div
                    :if={not show_chat_conversation?(@chat_messages, @pending_prompt, @chat_pending)}
                    class="flex h-full min-h-48 items-center justify-center text-center"
                  >
                    <div class="max-w-xs space-y-2">
                      <.icon name="hero-sparkles-micro" class="mx-auto size-4 text-primary" />
                      <p class="font-medium text-base-content">{gettext("Start with a prompt")}</p>
                      <p class="text-base leading-7 text-pretty text-base-content/55 sm:text-sm sm:leading-6">
                        {gettext("Pick an example or describe the decision you want to support.")}
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
                            {gettext("You")}
                          </p>
                          <p class="text-base leading-7 sm:text-sm sm:leading-6">{@pending_prompt}</p>
                        </div>
                      </div>

                      <div :if={@chat_pending and @pending_reply_content} class="flex justify-start">
                        <div class={message_classes(:assistant)}>
                          <p class="mb-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] opacity-60">
                            {gettext("Agent")}
                          </p>
                          <div class={assistant_markdown_classes()}>
                            {render_markdown(@pending_reply_content)}
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>

                <div
                  :if={not @chat_unlocked and DemoAccess.enabled?()}
                  id="access-ended"
                  class="shrink-0 space-y-2 border-t border-base-300/70 px-4 py-4 text-sm leading-5"
                >
                  <p class="font-medium text-base-content">
                    {gettext("Your invitation has no conversations left.")}
                  </p>
                  <p class="text-base-content/70">
                    {gettext("Rather see it with your company's data?")}
                    <a href={Links.calendar(:demo_invitee)} class="font-medium text-primary underline">
                      {gettext("Book your exploratory call")}
                    </a>
                  </p>
                </div>

                <.form
                  :if={not @chat_unlocked and not DemoAccess.enabled?()}
                  id="unlock-form"
                  for={@unlock_form}
                  phx-submit="unlock_chat"
                  class="shrink-0 space-y-3 border-t border-base-300/70 px-4 py-4"
                >
                  <p id="access-notice" class="text-sm leading-5 text-base-content/75">
                    {if @access.state == :expired,
                      do: gettext("Your invitation is no longer available."),
                      else: gettext("The live agent is by invitation.")}
                    <a href={~p"/" <> "#pruebalo"} class="font-medium text-primary underline">
                      {gettext("Request access")}
                    </a>
                  </p>

                  <div class="space-y-1">
                    <label
                      for={@unlock_form[:password].id}
                      class="text-sm font-medium text-base-content"
                    >
                      {gettext("Demo password")}
                    </label>
                    <p class="text-sm leading-5 text-base-content/55">
                      {gettext("Enter the password to unlock the analysis agent.")}
                    </p>
                  </div>

                  <div class="flex gap-2">
                    <.input
                      field={@unlock_form[:password]}
                      type="password"
                      autocomplete="current-password"
                      placeholder={gettext("Password")}
                      aria-invalid={not is_nil(@unlock_error)}
                      aria-describedby={@unlock_error && "unlock-error"}
                      class="min-w-0 flex-1 rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-base text-base-content shadow-none outline-none focus:border-primary focus:ring-0"
                    />
                    <button
                      type="submit"
                      class="inline-flex shrink-0 items-center justify-center rounded-lg bg-primary px-3 py-2.5 text-sm font-semibold text-primary-content hover:brightness-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
                    >
                      {gettext("Unlock")}
                    </button>
                  </div>

                  <p :if={@unlock_error} id="unlock-error" class="text-sm text-error" role="alert">
                    {unlock_error_text(@unlock_error)}
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
                    placeholder={gettext("Ask about revenue, customers, products, or trends")}
                    rows="2"
                    disabled={@chat_pending}
                    class="w-full resize-none rounded-xl border border-base-300 bg-base-100 px-3 py-2.5 text-base text-base-content shadow-none outline-none focus:border-primary focus:ring-0 disabled:cursor-not-allowed disabled:opacity-60"
                  />

                  <div class="flex items-center justify-between gap-3">
                    <p class="text-sm leading-5 text-base-content/50">
                      {gettext("Connected with read-only access")}
                    </p>

                    <button
                      type="submit"
                      class="inline-flex shrink-0 items-center justify-center rounded-lg bg-primary px-3 py-2.5 text-sm font-semibold text-primary-content hover:brightness-95 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-60"
                      disabled={@chat_pending}
                    >
                      {if @chat_pending, do: gettext("Analyzing..."), else: gettext("Send")}
                    </button>
                  </div>
                </.form>
              </section>

              <div
                :if={@unlocked_by == :invite}
                id="invite-status"
                class="mt-3 space-y-1 px-1 text-xs leading-5 text-pretty text-base-content/65"
              >
                <p>
                  {ngettext(
                    "1 conversation left on your invitation. Each new conversation uses one.",
                    "%{count} conversations left on your invitation. Each new conversation uses one.",
                    @access.remaining
                  )}
                </p>
                <p>
                  {gettext("Rather see it with your company's data?")}
                  <a href={Links.calendar(:demo_invitee)} class="font-medium text-primary underline">
                    {gettext("Book your exploratory call")}
                  </a>
                </p>
              </div>

              <%!-- Outside the fixed-height card so it never takes space from the conversation. --%>
              <p
                :if={footnote = JidoCodemodeWeb.CurrencyNote.footnote(@locale, @currency)}
                id="currency-footnote"
                class="mt-3 px-1 text-xs leading-5 text-pretty text-base-content/55"
              >
                {footnote}
              </p>
            </aside>
          </section>
        </section>

        <div class="lp lp-chrome">
          <SiteChrome.site_footer />
        </div>
      </div>

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

            const esMX = this.el.dataset.locale === "es-MX"

            const options = {actions: false, renderer: "svg"}

            // vega-embed sets its locale globally and never resets it, so always
            // pass one: otherwise Spanish labels leak into English charts.
            options.formatLocale = {decimal: ".", thousands: ",", grouping: [3], currency: ["$", ""]}

            if (esMX) {
              options.timeFormatLocale = {
                dateTime: "%A, %e de %B de %Y, %X",
                date: "%d/%m/%Y",
                time: "%H:%M:%S",
                periods: ["AM", "PM"],
                days: ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"],
                shortDays: ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"],
                months: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
                shortMonths: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"],
              }
            } else {
              options.timeFormatLocale = {
                dateTime: "%x, %X",
                date: "%-m/%-d/%Y",
                time: "%-I:%M:%S %p",
                periods: ["AM", "PM"],
                days: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"],
                shortDays: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
                months: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"],
                shortMonths: ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"],
              }
            }

            const result = await vegaEmbed(this.el, JSON.parse(spec), options)

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

      # The input is disabled while a turn runs; the server enforces it too.
      socket.assigns.chat_pending ->
        {:noreply, socket}

      is_nil(socket.assigns.agent_pid) ->
        {:noreply,
         socket
         |> assign(:chat_form, chat_form(prompt))
         |> put_flash(
           :error,
           gettext("The agent session is still starting. Try again in a moment.")
         )}

      billing(socket) == :missing_token ->
        {:noreply,
         socket
         |> assign(:chat_form, chat_form(prompt))
         |> put_flash(:error, access_error(:unavailable))}

      true ->
        agent_pid = socket.assigns.agent_pid
        agent_id = socket.assigns.agent_id
        tool_context = tool_context(socket)
        request_id = System.unique_integer([:positive])
        billing = billing(socket)

        Process.send_after(self(), {:poll_agent_reply, request_id}, 120)

        {:noreply,
         socket
         |> assign(:chat_form, chat_form())
         |> assign(:locale_notice, nil)
         |> assign(:chat_pending, true)
         |> assign(:chat_request_id, request_id)
         |> assign(:pending_prompt, prompt)
         |> assign(:pending_reply_content, nil)
         |> start_async({:agent_reply, request_id}, fn ->
           # Unlinked, so closing the tab mid-answer can't kill the turn between
           # spending the use and refunding it.
           JidoCodemode.Agent.TaskSupervisor
           |> Task.Supervisor.async_nolink(fn ->
             run_turn(billing, fn ->
               SidebarAgent.ask_sync(agent_pid, prompt,
                 timeout: 60_000,
                 req_http_options: [
                   headers:
                     JidoCodemode.AI.request_headers() ++ [{"x-opencode-session", agent_id}]
                 ],
                 tool_context: tool_context
               )
             end)
           end)
           |> Task.await(:infinity)
         end)}
    end
  end

  # nil when this turn costs nothing: team password, open demo, or a conversation
  # that already spent its use. Otherwise the invitation token and conversation id.
  defp billing(%{assigns: %{unlocked_by: :invite, conversation_paid: false}} = socket) do
    case DemoAccess.Tokens.fetch(socket.assigns.access[:ref]) do
      {:ok, token} -> {token, socket.assigns.conversation_id}
      :error -> :missing_token
    end
  end

  defp billing(_socket), do: nil

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
    agent_id = "sandbox-" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    {:ok, agent_pid} = Jido.start_agent(JidoCodemode.Jido, SidebarAgent, id: agent_id)

    _ =
      JidoAI.set_system_prompt(
        agent_pid,
        SidebarAgent.system_prompt_with_schema(socket.assigns.locale),
        timeout: 15_000
      )

    socket
    |> assign(:agent_id, agent_id)
    |> assign(:agent_pid, agent_pid)
    |> assign(:conversation_id, uuid4())
    |> assign(:conversation_paid, false)
    |> refresh_chat_messages()
    |> refresh_agent_report()
  end

  # A new conversation id per agent session: the invitation service spends one use
  # per id and treats repeats as the same conversation.
  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> then(fn hex ->
      Enum.join(
        [
          binary_part(hex, 0, 8),
          binary_part(hex, 8, 4),
          binary_part(hex, 12, 4),
          binary_part(hex, 16, 4),
          binary_part(hex, 20, 12)
        ],
        "-"
      )
    end)
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
        label: gettext("Trend"),
        prompt: gettext("Show a monthly revenue trend")
      },
      %{
        icon: "hero-squares-2x2-micro",
        label: gettext("Categories"),
        prompt: gettext("Compare the top categories")
      },
      %{
        icon: "hero-users-micro",
        label: gettext("Top customers"),
        prompt: gettext("List the top customers by revenue")
      },
      %{
        icon: "hero-circle-stack-micro",
        label: gettext("Important joins"),
        prompt: gettext("Describe the most important joins")
      },
      %{
        icon: "hero-sparkles-micro",
        label: gettext("Complete analysis"),
        prompt: gettext("Build a short analysis with a chart and a table")
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
      gettext("The agent returned a non-text response: %{details}",
        details: inspect(reply, pretty: true, limit: 20)
      )
    )
  end

  defp error_reply(reason) do
    gettext("The agent request failed: %{reason}",
      reason: inspect(reason, pretty: true, limit: 20)
    )
  end

  defp chat_row_classes(:user), do: "flex justify-end"
  defp chat_row_classes(:assistant), do: "flex justify-start"

  defp role_label(:user), do: gettext("You")
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

  defp format_metric_value(value, :currency, currency) when is_number(value),
    do: Format.money(value, currency)

  defp format_metric_value(value, :percent, _currency) when is_number(value),
    do: Format.percent(value)

  defp format_metric_value(value, :number, _currency) when is_number(value),
    do: Format.number(value)

  defp format_metric_value(value, _format, _currency), do: to_string(value)

  @doc false
  def format_table_value(nil, _column), do: "-"

  def format_table_value(value, column) when is_integer(value) do
    if identifier_column?(column), do: Integer.to_string(value), else: Format.number(value)
  end

  def format_table_value(value, _column) when is_number(value), do: Format.number(value)
  def format_table_value(value, _column), do: to_string(value)

  # Ids, folios (names starting with "folio", not "Portafolio"), and years are labels, not quantities: they stay ungrouped.
  defp identifier_column?(column) do
    name = to_string(column)
    lowered = String.downcase(name)

    name == "Id" or String.ends_with?(name, ["Id", "ID"]) or lowered == "id" or
      String.starts_with?(lowered, ["id ", "id_"]) or
      String.contains?(lowered, ["year", "año"]) or String.starts_with?(lowered, "folio")
  end

  defp clear_pending_chat(socket) do
    socket
    |> assign(:chat_pending, false)
    |> assign(:chat_request_id, nil)
    |> assign(:pending_prompt, nil)
    |> assign(:pending_reply_content, nil)
  end
end
