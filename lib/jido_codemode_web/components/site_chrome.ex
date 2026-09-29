defmodule JidoCodemodeWeb.SiteChrome do
  @moduledoc """
  The header and footer shared by the landing (`/`) and the live demo (`/demo`),
  so both pages carry the same brand, navigation, language switch and call link.
  Styles are in `assets/css/landing.css` (under `.lp`); on the demo, wrap them in
  `.lp.lp-chrome` so the landing styles reach only these parts.
  """

  use Phoenix.Component
  use Gettext, backend: JidoCodemodeWeb.Gettext

  alias JidoCodemodeWeb.Links

  attr :locale, :string, required: true

  attr :base, :string,
    default: "",
    doc: "prefix for section links: \"\" on the landing, \"/\" elsewhere"

  attr :id_prefix, :string, default: "lp-locale-", doc: "ids of the ES/EN buttons"
  attr :call_url, :string, required: true

  def site_header(assigns) do
    ~H"""
    <header class="site-header">
      <div class="wrap">
        <a
          class="brand"
          href={if @base == "", do: "#top", else: "/"}
          aria-label={gettext("Agentic BI, home")}
        >
          <span class="name">Agentic BI</span><span class="by">{gettext("by SuperDev")}</span>
        </a>
        <nav class="nav" aria-label={gettext("Main")}>
          <div class="links">
            <a class="nav-link" href={@base <> "#pruebalo"}>{gettext("Try it")}</a>
            <a class="nav-link" href={@base <> "#como-funciona"}>{gettext("How it works")}</a>
            <a class="nav-link" href={@base <> "#ti"}>{gettext("For IT")}</a>
            <a :if={@locale == "en"} class="nav-link" href={@base <> "#partners"}>
              {gettext("Partners")}
            </a>
            <a class="nav-link" href={@base <> "#preguntas"}>{gettext("FAQ")}</a>
          </div>
          <div class="lang" role="group" aria-label={gettext("Language")}>
            <button
              :for={{code, label} <- [{"es_MX", "ES"}, {"en", "EN"}]}
              id={@id_prefix <> code}
              type="button"
              phx-click="set_locale"
              phx-value-locale={code}
              aria-pressed={to_string(@locale == code)}
            >
              {label}
            </button>
          </div>
          <a class="lp-btn lp-btn-secondary lp-btn-sm" href={@call_url}>
            {gettext("Exploratory call")}
          </a>
        </nav>
      </div>
    </header>
    """
  end

  attr :footnote, :string, default: nil
  attr :footnote_id, :string, default: "landing-footnote"

  def site_footer(assigns) do
    ~H"""
    <footer class="site">
      <div class="wrap">
        <p>
          {gettext(
            "Agentic BI is part of SuperDev's Business Intelligence service. AI and business operations consulting."
          )}
        </p>
        <div class="links">
          <a href={Links.superdev()}>superdev.mx</a>
          <a href={Links.business_intelligence()}>Business Intelligence</a>
          <a href={Links.privacy()}>{gettext("Privacy notice")}</a>
        </div>
        <p :if={@footnote} class="fx" id={@footnote_id}>{@footnote}</p>
      </div>
    </footer>
    """
  end
end
