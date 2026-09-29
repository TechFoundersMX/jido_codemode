defmodule JidoCodemodeWeb.LandingLive do
  @moduledoc """
  The public landing at `/`: the pitch, examples on the sample data, a saved agent
  answer, and the way into the live agent at `/demo`.

  Visual system: the "Hoja de cálculo" palette on the "Hielo" background, approved
  by Alex on 29 Sep 2026 (see `docs/landing/2026-09-29-copy-deck.md`). Styles live
  in `assets/css/landing.css`, scoped under `.lp`.
  """

  use JidoCodemodeWeb, :live_view

  alias JidoCodemode.Locale
  alias JidoCodemode.Locale.Dataset
  alias JidoCodemodeWeb.{CurrencyNote, LandingCharts, LandingExamples, Links, SiteChrome}

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:access, access(session["demo_access"]))
     |> assign_copy(socket.assigns.locale)}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("set_locale", %{"locale" => value}, socket) do
    case Locale.normalize(value) do
      locale when is_binary(locale) and locale != socket.assigns.locale ->
        Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)
        socket = socket |> assign(:locale, locale) |> assign_copy(locale)

        {:noreply,
         socket
         |> push_event("locale-changed", %{
           locale: locale,
           html_lang: Locale.html_lang(locale),
           title: socket.assigns.page_title
         })
         |> push_patch(to: ~p"/?lang=#{if locale == "es_MX", do: "es", else: "en"}")}

      _same_or_unknown ->
        {:noreply, socket}
    end
  end

  defp assign_copy(socket, locale) do
    socket
    |> assign(:page_title, gettext("Agentic BI · Your next report, one question away"))
    |> assign(:hero, LandingExamples.hero(locale))
    |> assign(:examples, LandingExamples.all(locale))
    |> assign(:replay, LandingExamples.replay(locale))
    |> assign(:footnote, CurrencyNote.footnote(locale, Dataset.currency(locale)))
  end

  defp access(%{"state" => "invited", "remaining" => remaining}) when is_integer(remaining),
    do: %{state: :invited, remaining: remaining}

  defp access(%{"state" => state}) when state in ["expired", "exhausted"], do: %{state: :expired}
  defp access(_none), do: %{state: :public}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} locale={@locale} app_chrome={false} full_width={true}>
      <%!-- Keyed on the locale: gettext copy has no assigns, so only a new key re-renders it in the other language. --%>
      <div :for={loc <- [@locale]} :key={loc} class="lp" id={"landing-#{loc}"}>
        <SiteChrome.site_header locale={loc} call_url={Links.calendar(:landing)} />

        <div id="top">
          <section class="lp-hero" aria-labelledby="hero-h">
            <div class="wrap">
              <div
                class="book"
                id={"hero-book-#{loc}"}
                phx-hook=".LandingHero"
                phx-update="ignore"
              >
                <div class="fbar">
                  <span class="namebox">B4</span>
                  <span class="fx" aria-hidden="true">fx</span>
                  <span class="formula">
                    <span class="eq" aria-hidden="true">=</span><span data-hero-q>{hd(@hero).question}</span>
                  </span>
                </div>
                <div class="colhead" aria-hidden="true">
                  <span></span><span>A</span><span class="on">B</span><span class="on">C</span><span class="on">D</span><span class="on">E</span><span>F</span><span>G</span><span>H</span><span>I</span><span>J</span><span>K</span><span>L</span>
                </div>
                <div class="canvas">
                  <ol class="rows" aria-hidden="true">
                    <li :for={n <- 1..40} class={n in [4, 5] && "on"}>{n}</li>
                  </ol>
                  <div class="cells">
                    <div class="copy">
                      <h1 id="hero-h">
                        {gettext("Your next report,")}
                        <span class="hl">{gettext("one question away.")}</span>
                      </h1>
                      <p class="lede">
                        {gettext(
                          "You have the data, but every report takes days and depends on one person. We connect your sources (Dynamics 365, Odoo, SAP Business One, Airtable) so anyone can ask and decide on the spot."
                        )}
                      </p>
                      <div class="cta-row">
                        <a class="lp-btn lp-btn-primary" href={Links.calendar(:landing)}>
                          {gettext("Book your exploratory call")}
                        </a>
                        <a class="textlink" href="#pruebalo">{gettext("See the live demo")}</a>
                      </div>
                      <p class="cta-note">{gettext("30 min · free · no commitment")}</p>
                    </div>
                    <figure class="query obj" aria-label={gettext("Example question")}>
                      <div
                        :for={{example, i} <- Enum.with_index(@hero)}
                        class="hero-item"
                        data-hero-item
                        data-question={example.question}
                        hidden={i > 0}
                      >
                        <div class="objhead">
                          <b>{example.kind}</b>
                          <span><span class="num">4 s</span> · {gettext("sample data")}</span>
                        </div>
                        <p class="answer">{example.answer}</p>
                        <div class="q-chart"><LandingCharts.viz example={example} /></div>
                      </div>
                      <div class="foot">
                        <figcaption class="caption">
                          {gettext("Sample data from a fictitious distributor.")}
                        </figcaption>
                        <div class="dots" role="group" aria-label={gettext("Examples")}>
                          <button
                            :for={{example, i} <- Enum.with_index(@hero)}
                            type="button"
                            data-hero-dot
                            aria-label={example.kind}
                            aria-current={to_string(i == 0)}
                          >
                          </button>
                        </div>
                      </div>
                    </figure>
                  </div>
                </div>
                <div class="sheet-tabs" aria-hidden="true">
                  <span>{gettext("Sales_Sept")}</span><span>{gettext("Sales_Sept (2)")}</span><span>{gettext("Report_FINAL_v7")}</span><span class="now">{gettext("Question")}</span><span>+</span>
                </div>
              </div>
            </div>
          </section>

          <section class="band tint slim" aria-labelledby="suena-h">
            <div class="wrap">
              <div class="sec-head">
                <p class="eyebrow">{gettext("Sound familiar?")}</p>
                <h2 id="suena-h">{gettext("Your data already exists. The answer doesn't.")}</h2>
              </div>
              <ul class="symptoms" role="list">
                <li>
                  <span class="k">01</span><span>{gettext("Every report depends on the one person who \"knows how to pull it\".")}</span>
                </li>
                <li>
                  <span class="k">02</span><span>{gettext("Your data lives in the ERP, but getting it out is a project.")}</span>
                </li>
                <li>
                  <span class="k">03</span><span>{gettext("Every team shows up to the meeting with its own number.")}</span>
                </li>
                <li>
                  <span class="k">04</span><span>{gettext("You decide with last month's data, or with gut feel.")}</span>
                </li>
              </ul>
            </div>
          </section>

          <section class="band explore" aria-label={gettext("Explore Agentic BI")}>
            <div class="wrap">
              <div class="panel" id="ejemplos">
                <div class="sec-head">
                  <p class="eyebrow">{gettext("What you can ask")}</p>
                  <h2>{gettext("Ask it what you ask someone on your team today.")}</h2>
                  <p class="lede">
                    {gettext(
                      "Trends, comparisons, mixes, rankings and KPIs. Every answer comes with the number, the chart that explains it best and the table. These are real examples on the demo's fictitious data."
                    )}
                  </p>
                </div>
                <div class="gallery" id={"gallery-#{loc}"} phx-hook=".LandingReveal">
                  <article :for={example <- @examples} class="ex" id={"ex-#{example.id}"}>
                    <div class="kind"><span class={"t#{example.tone}"}>{example.kind}</span></div>
                    <p class="prompt">{example.question}</p>
                    <p class="say">{example.answer}</p>
                    <div class="viz"><LandingCharts.viz example={example} /></div>
                  </article>
                </div>
              </div>

              <div class="panel" id="pruebalo">
                <div class="sec-head">
                  <p class="eyebrow">{gettext("Try it")}</p>
                  <h2>{gettext("See it before you believe us.")}</h2>
                  <p class="lede">
                    {gettext(
                      "A sample distributor with fictitious data. This is how the agent answers a business question: the number, the chart and the table."
                    )}
                  </p>
                </div>
                <div class="try">
                  <article class="replay" id="replay" aria-label={gettext("Sample answer")}>
                    <div class="head">
                      <span>{gettext("A real agent answer, saved.")}</span>
                      <span class="tag">{gettext("Fictitious data")}</span>
                    </div>
                    <div class="body">
                      <p class="bubble">{@replay.question}</p>
                      <p class="answer">{@replay.answer}</p>
                      <p class="report-title">{gettext("Revenue by category")}</p>
                      <div class="tbl-wrap">
                        <table>
                          <thead>
                            <tr>
                              <th>{gettext("Category")}</th>
                              <th class="r">{@replay.amount_column}</th>
                            </tr>
                          </thead>
                          <tbody>
                            <tr :for={row <- @replay.rows}>
                              <td>{row.name}</td>
                              <td class="r">{row.amount}</td>
                            </tr>
                          </tbody>
                        </table>
                      </div>
                      <p class="fineprint">{gettext("Fictitious data. Not your operation yet.")}</p>
                    </div>
                  </article>

                  <.access_card access={@access} />
                </div>
              </div>

              <div class="panel" id="como-funciona">
                <div class="sec-head">
                  <p class="eyebrow">{gettext("How it works")}</p>
                  <h2>{gettext("Three steps. The number comes to you.")}</h2>
                </div>
                <div class="how">
                  <div class="compare">
                    <div class="before">
                      <h3>{gettext("Before")}</h3>
                      <ol>
                        <li>{gettext("You request the report")}</li>
                        <li>{gettext("Someone builds it by hand")}</li>
                        <li>{gettext("You wait")}</li>
                        <li>{gettext("It arrives out of date")}</li>
                        <li>{gettext("Nobody trusts the number")}</li>
                      </ol>
                    </div>
                    <div class="after">
                      <h3>{gettext("With Agentic BI")}</h3>
                      <ol>
                        <li>{gettext("You ask the question")}</li>
                        <li>{gettext("The answer arrives in seconds")}</li>
                        <li>{gettext("With a chart and a table")}</li>
                        <li>{gettext("The same number for every team")}</li>
                      </ol>
                    </div>
                  </div>
                  <ol class="how-steps">
                    <li>
                      <span class="n">01</span>
                      <h3>{gettext("We connect your sources once.")}</h3>
                      <p>
                        {gettext(
                          "Your ERP, spreadsheets and billing. Your data doesn't move: it gets connected."
                        )}
                      </p>
                    </li>
                    <li>
                      <span class="n">02</span>
                      <h3>{gettext("You ask in plain language.")}</h3>
                      <p>{gettext("The way you'd ask someone on your team, from your phone too.")}</p>
                    </li>
                    <li>
                      <span class="n">03</span>
                      <h3>{gettext("You decide with the answer.")}</h3>
                      <p>
                        {gettext(
                          "The number, a chart and a table, with one definition for every team."
                        )}
                      </p>
                    </li>
                  </ol>
                </div>
              </div>

              <div class="panel" id="ti">
                <div class="sec-head">
                  <p class="eyebrow">{gettext("For your IT team")}</p>
                  <h2>{gettext("What your systems team will ask.")}</h2>
                  <p class="lede">
                    {gettext(
                      "The agent only reads. Every query goes through checks before it runs, and every number has a definition and an owner."
                    )}
                  </p>
                </div>
                <dl class="it">
                  <div>
                    <dt>{gettext("Read-only")}</dt>
                    <dd>
                      {gettext(
                        "It can't change or delete anything. It only runs read queries, validated before they execute."
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{gettext("Your data stays put")}</dt>
                    <dd>
                      {gettext(
                        "It connects to Dynamics 365, Odoo, SAP Business One or Airtable. We don't replace your ERP or copy your operation into another tool."
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{gettext("One number")}</dt>
                    <dd>
                      {gettext(
                        "Every KPI is written down: its definition, its source and its owner. No more one version per team."
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{gettext("Who sees what")}</dt>
                    <dd>
                      {gettext(
                        "Role-based permissions. It's documented who owns each piece of data and who can see it."
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{gettext("Clear limits")}</dt>
                    <dd>
                      {gettext(
                        "Every query has a time and size limit. If a question is ambiguous, the agent says so or asks; it doesn't make up numbers."
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{gettext("Privacy")}</dt>
                    <dd>
                      {gettext(
                        "The demo uses fictitious data. In your project, personal data is handled under our"
                      )}
                      <a class="textlink" href={Links.privacy()}>{gettext("privacy notice")}</a>.
                    </dd>
                  </div>
                </dl>
                <div class="maturity" aria-label={gettext("Data maturity")}>
                  <div class="now">
                    <span class="lvl">{gettext("01 · Descriptive")}</span>
                    <span class="q">{gettext("What happened?")}</span>
                  </div>
                  <div class="now">
                    <span class="lvl">{gettext("02 · Diagnostic")}</span>
                    <span class="q">{gettext("Why did it happen?")}</span>
                  </div>
                  <div>
                    <span class="lvl">{gettext("03 · Predictive")}</span>
                    <span class="q">{gettext("What will happen?")}</span>
                  </div>
                  <div>
                    <span class="lvl">{gettext("04 · Prescriptive")}</span>
                    <span class="q">{gettext("What should we do?")}</span>
                  </div>
                </div>
                <p class="fineprint maturity-note">
                  {gettext(
                    "We start where you are, usually descriptive, and build the path up. The agent covers the first two stages today."
                  )}
                </p>
              </div>

              <div class="panel" id="caso">
                <div class="case">
                  <div class="sec-head">
                    <p class="eyebrow">{gettext("Case")}</p>
                    <h2>{gettext("Data Agent.")}</h2>
                  </div>
                  <div class="body">
                    <dl class="case-stats">
                      <div>
                        <dt>{gettext("users in plain language")}</dt>
                        <dd>42</dd>
                      </div>
                      <div>
                        <dt>{gettext("months to get the agent live")}</dt>
                        <dd>&lt; 2</dd>
                      </div>
                      <div>
                        <dt>{gettext("weeks and 12 deliverables, the full project")}</dt>
                        <dd>16</dd>
                      </div>
                    </dl>
                    <p class="lede">
                      {gettext(
                        "From delivery drivers to the CEO, they query business data in plain language, from their phones too. The full project included governance and training. Source ERP: Dynamics 365."
                      )}
                    </p>
                    <p><a class="textlink" href={Links.case_study()}>{gettext("See the case")}</a></p>
                  </div>
                </div>
              </div>

              <div :if={loc == "en"} class="panel" id="partners">
                <div class="sec-head">
                  <p class="eyebrow">{gettext("For partners")}</p>
                  <h2>{gettext("Offer it under your brand.")}</h2>
                  <p class="lede">
                    {gettext(
                      "Agencies, consultancies, and software resellers can offer Agentic BI to their clients as their own. We build and run the agent. You keep the client relationship."
                    )}
                  </p>
                </div>
                <dl class="it">
                  <div>
                    <dt>{gettext("Your brand")}</dt>
                    <dd>{gettext("Your name, logo, and colors on the agent your clients use.")}</dd>
                  </div>
                  <div>
                    <dt>{gettext("We do the build")}</dt>
                    <dd>
                      {gettext(
                        "We connect each client's data, set up the agent, and support it after launch."
                      )}
                    </dd>
                  </div>
                  <div>
                    <dt>{gettext("Your client, your call")}</dt>
                    <dd>
                      {gettext(
                        "You own the relationship and the pricing to your clients. We stay behind the scenes."
                      )}
                    </dd>
                  </div>
                </dl>
                <div class="process-cta cta-row">
                  <a class="lp-btn lp-btn-primary" href={Links.calendar(:landing)}>
                    {gettext("Book your exploratory call")}
                  </a>
                  <span class="cta-note">{gettext("30 min · free · no commitment")}</span>
                </div>
              </div>

              <div class="panel" id="proceso">
                <div class="sec-head">
                  <p class="eyebrow">{gettext("How we work")}</p>
                  <h2>{gettext("It all starts with a 30-minute call.")}</h2>
                </div>
                <ol class="process">
                  <li>
                    <span class="n">01</span>
                    <h3>{gettext("Exploratory call")}</h3>
                    <p>{gettext("We understand your operation and check the fit. Free.")}</p>
                  </li>
                  <li>
                    <span class="n">02</span>
                    <h3>{gettext("AI Diagnostic")}</h3>
                    <p>
                      {gettext(
                        "With access to your systems: a report with your starting point and a prioritized plan."
                      )}
                    </p>
                  </li>
                  <li>
                    <span class="n">03</span>
                    <h3>{gettext("Implementation")}</h3>
                    <p>
                      {gettext(
                        "We build what the diagnostic prioritizes, deliverable by deliverable. Reference timeline: 16 weeks."
                      )}
                    </p>
                  </li>
                  <li>
                    <span class="n">04</span>
                    <h3>{gettext("Measurement")}</h3>
                    <p>{gettext("We compare against the baseline set in the diagnostic.")}</p>
                  </li>
                  <li>
                    <span class="n">05</span>
                    <h3>{gettext("Ongoing support")}</h3>
                    <p>{gettext("A monthly retainer to maintain and improve.")}</p>
                  </li>
                </ol>
                <div class="process-cta cta-row">
                  <a class="lp-btn lp-btn-secondary" href={Links.ai_readiness()}>
                    {gettext("Take the preliminary assessment")}
                  </a>
                  <span class="cta-note">{gettext("3 min · 14 questions · instant result")}</span>
                </div>
              </div>

              <div class="panel" id="preguntas">
                <div class="faq">
                  <div class="sec-head">
                    <p class="eyebrow">{gettext("FAQ")}</p>
                    <h2>{gettext("What people ask before we start.")}</h2>
                  </div>
                  <div class="faq-list">
                    <details :for={{question, answer} <- faq()}>
                      <summary>{question}</summary>
                      <p>{answer}</p>
                    </details>
                  </div>
                </div>
              </div>
            </div>
          </section>

          <section class="final" aria-labelledby="final-h">
            <div class="wrap">
              <div>
                <h2 id="final-h">{gettext("What if your next report took seconds?")}</h2>
                <p class="lede">
                  {gettext(
                    "A 30-minute call to review your data sources and tell you what's possible."
                  )}
                </p>
              </div>
              <div class="cta-row">
                <a class="lp-btn lp-btn-primary" href={Links.calendar(:landing)}>
                  {gettext("Book your exploratory call")}
                </a>
                <a class="textlink" href={Links.ai_readiness()}>
                  {gettext("Take the preliminary assessment")}
                </a>
              </div>
              <p class="cta-note">{gettext("30 min · free · no commitment")}</p>
            </div>
          </section>
        </div>

        <SiteChrome.site_footer footnote={@footnote} />
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LandingHero">
        // Cycles the hero's example questions: types the question into the formula
        // bar, then shows its answer and chart. Pauses on hover and focus; with
        // reduced motion it shows the first example and only the dots change it.
        export default {
          mounted() {
            this.items = [...this.el.querySelectorAll("[data-hero-item]")]
            this.dots = [...this.el.querySelectorAll("[data-hero-dot]")]
            this.q = this.el.querySelector("[data-hero-q]")
            this.reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
            this.paused = false
            const figure = this.el.querySelector("figure")
            const pause = () => { this.paused = true }
            const resume = () => { this.paused = false }
            figure.addEventListener("mouseenter", pause)
            figure.addEventListener("mouseleave", resume)
            figure.addEventListener("focusin", pause)
            figure.addEventListener("focusout", resume)
            this.dots.forEach((dot, i) => dot.addEventListener("click", () => this.show(i, true)))
            this.show(0, !this.reduce)
            if (!this.reduce) {
              this.timer = setInterval(() => {
                if (!this.paused && !document.hidden) this.show((this.index + 1) % this.items.length, true)
              }, 4000)
            }
          },
          destroyed() {
            clearInterval(this.timer)
            clearInterval(this.typing)
          },
          show(index, animate) {
            this.index = index
            this.items.forEach((item, i) => {
              item.hidden = i !== index
              item.classList.remove("play")
            })
            const item = this.items[index]
            // Restart the chart animation: reflow between removing and adding the class.
            void item.offsetWidth
            if (animate && !this.reduce) item.classList.add("play")
            this.dots.forEach((dot, i) => dot.setAttribute("aria-current", String(i === index)))
            this.type(item.dataset.question, animate && !this.reduce)
          },
          type(text, animate) {
            clearInterval(this.typing)
            if (!animate) {
              this.q.textContent = text
              return
            }
            let shown = 0
            this.q.textContent = ""
            this.typing = setInterval(() => {
              shown = Math.min(text.length, shown + 3)
              this.q.textContent = text.slice(0, shown)
              if (shown >= text.length) clearInterval(this.typing)
            }, 18)
          },
        }
      </script>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".LandingReveal">
        // Animates each gallery chart once, when it scrolls into view. Charts are
        // already drawn server-side, so nothing depends on this running.
        export default {
          mounted() {
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return
            if (!("IntersectionObserver" in window)) return
            this.observer = new IntersectionObserver((entries) => {
              for (const entry of entries) {
                if (!entry.isIntersecting) continue
                entry.target.classList.add("play")
                this.observer.unobserve(entry.target)
              }
            }, {threshold: 0.3})
            this.el.querySelectorAll(".ex").forEach((card) => this.observer.observe(card))
          },
          destroyed() {
            this.observer?.disconnect()
          },
        }
      </script>
    </Layouts.app>
    """
  end

  attr :access, :map, required: true

  defp access_card(assigns) do
    assigns = assign(assigns, :request_url, Links.access_request())

    ~H"""
    <aside class="access" id="access" data-mode={@access.state}>
      <div :if={@access.state == :invited} class="state">
        <p class="access-status">
          <i></i><span id="access-status">{ngettext(
            "You have access to the live agent. You have 1 conversation left.",
            "You have access to the live agent. You have %{count} conversations left.",
            @access.remaining
          )}</span>
        </p>
        <h3>{gettext("Ask the sample distributor.")}</h3>
        <div>
          <.link navigate={~p"/demo"} class="lp-btn lp-btn-primary" id="access-open">
            {gettext("Open the live agent")}
          </.link>
        </div>
        <p class="fineprint">
          {gettext("Each new conversation uses one. Questions within a conversation don't count.")}
        </p>
      </div>

      <div :if={@access.state == :expired} class="state">
        <p class="access-status"><i></i><span>{gettext("Invitation unavailable")}</span></p>
        <h3>{gettext("This invitation is no longer available.")}</h3>
        <p>
          {gettext(
            "It expired or its conversations are used up. Ask for a new one and we'll send it."
          )}
        </p>
        <.request_access request_url={@request_url} />
      </div>

      <div :if={@access.state == :public} class="state">
        <p class="access-status"><i></i><span>{gettext("Live agent · by invitation")}</span></p>
        <h3>{gettext("Ask it your own questions.")}</h3>
        <p :if={@request_url}>
          {gettext(
            "Request access with your details and you're in right away: three trial conversations over 7 days with the sample distributor."
          )}
        </p>
        <p :if={is_nil(@request_url)}>
          {gettext(
            "For now, access is by invitation. Book your exploratory call and we'll send you one."
          )}
        </p>
        <.request_access request_url={@request_url} />
        <p :if={@request_url} class="fineprint">
          {gettext("Free. We email you a link to come back from another device.")}
        </p>
      </div>

      <%!-- Before the invitation service is connected, the team reaches the agent with the password. --%>
      <p :if={is_nil(@request_url)} class="fineprint">
        <.link navigate={~p"/demo"} class="textlink" id="access-full-demo">
          {gettext("Open the full demo")}
        </.link>
      </p>
    </aside>
    """
  end

  attr :request_url, :string, default: nil

  defp request_access(assigns) do
    ~H"""
    <div>
      <a :if={@request_url} class="lp-btn lp-btn-secondary" id="access-request" href={@request_url}>
        {gettext("Request access to the live agent")}
      </a>
      <a
        :if={is_nil(@request_url)}
        class="lp-btn lp-btn-primary"
        id="access-call"
        href={Links.calendar(:landing)}
      >
        {gettext("Book your exploratory call")}
      </a>
    </div>
    """
  end

  defp faq do
    [
      {gettext("Do we have to move our data?"),
       gettext(
         "No. We connect to the ERP and spreadsheets you already use. Moving data is a separate project and is rarely needed to start."
       )},
      {gettext("Can it change or delete anything?"),
       gettext("No. The agent only reads, and every query is checked before it runs.")},
      {gettext("What if my question is ambiguous?"),
       gettext(
         "The agent states its assumption or asks you. If the data doesn't exist, it says so instead of making it up."
       )},
      {gettext("Which systems does it work with?"),
       gettext(
         "Dynamics 365, Odoo, SAP Business One, Airtable and spreadsheets. The AI Diagnostic confirms which sources connect and how."
       )},
      {gettext("What if our data is messy?"),
       gettext(
         "That's normal. The AI Diagnostic shows how usable it is today and what to clean first."
       )},
      {gettext("Is the demo data from a client?"), gettext("No. It's a fictitious distributor.")},
      {gettext("How much does it cost?"),
       gettext(
         "It's quoted in a formal proposal after the AI Diagnostic, based on your sources and scope."
       )},
      {gettext("Who maintains it afterwards?"),
       gettext(
         "Your team. We close with documentation and training, so it doesn't depend only on us."
       )}
    ]
  end
end
