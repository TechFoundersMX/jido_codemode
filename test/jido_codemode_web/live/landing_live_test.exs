defmodule JidoCodemodeWeb.LandingLiveTest do
  use JidoCodemodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCodemode.DemoAccessFake

  @landing_call "https://superdev.mx/calendar/?utm_source=agentic_bi&amp;utm_medium=landing"

  test "the Spanish landing shows the approved copy, pesos, and the rate footnote", %{conn: conn} do
    {:ok, view, html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/")

    assert html =~ "Tu próximo reporte,"
    assert html =~ "en una pregunta."
    assert html =~ "Pregúntale lo que hoy le pides a alguien de tu equipo."
    assert html =~ "Lo que tu área de sistemas va a preguntar."

    # The saved answer matches what the agent returns on the Spanish database.
    assert has_element?(view, "#replay", "Bebidas ($4,779,116.56 MXN)")
    assert has_element?(view, "#replay", "Lácteos ($4,183,914.82 MXN)")
    assert has_element?(view, "#replay", "Dulces y postres ($2,985,870.46 MXN)")
    assert has_element?(view, "#replay th", "Ingresos (MXN)")

    assert has_element?(view, "#landing-footnote", "1 USD = 17.8413 MXN")
    refute has_element?(view, "#partners")
    refute html =~ "Offer it under your brand"
  end

  test "the English landing pitches partners and shows dollars", %{conn: conn} do
    {:ok, view, html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/")

    assert html =~ "Your next report,"
    assert has_element?(view, "#partners", "Offer it under your brand.")
    assert has_element?(view, "a[href='#partners']")
    assert has_element?(view, "#replay", "Beverages ($267,868.18)")
    assert has_element?(view, "#replay", "Dairy Products ($234,507.29)")
    refute has_element?(view, "#landing-footnote")
  end

  test "the landing makes no client-case claim, in either language", %{conn: conn} do
    for lang <- ["es", "en"] do
      html = conn |> get("/?lang=#{lang}") |> html_response(200)
      refute html =~ ~s(id="caso")
      refute html =~ "Agente de Datos"
      refute html =~ "Data Agent"
      refute html =~ "Dynamics 365."
      refute html =~ "projects/agente-de-datos"
    end
  end

  test "every exploratory-call link carries the landing's attribution", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")

    calendar_links = Regex.scan(~r/href="(https:\/\/superdev\.mx\/calendar\/[^"]*)"/, html)
    assert calendar_links != []
    assert Enum.all?(calendar_links, fn [_, href] -> "href=\"#{href}\"" =~ @landing_call end)
    refute html =~ "kind=demo"
    assert html =~ ~s(href="https://superdev.mx/ai-readiness/")
  end

  test "the hero cycles four examples and the gallery shows six", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "[phx-hook='JidoCodemodeWeb.LandingLive.LandingHero']")
    doc = view |> render() |> LazyHTML.from_fragment()
    assert doc |> LazyHTML.query("[data-hero-item]") |> Enum.count() == 4
    assert doc |> LazyHTML.query("[data-hero-item][hidden]") |> Enum.count() == 3

    for id <- ~w(trend categories shippers customers order-value countries) do
      assert has_element?(view, "#ex-#{id}")
    end
  end

  test "switching language patches the URL and re-renders the copy", %{conn: conn} do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/")

    html = view |> element("#lp-locale-es_MX") |> render_click()
    assert_patch(view, "/?lang=es")
    assert html =~ "Tu próximo reporte,"

    assert_push_event(view, "locale-changed", %{
      locale: "es_MX",
      html_lang: "es-MX",
      title: "Agentic BI · Tu próximo reporte, en una pregunta"
    })
  end

  test "meta and social tags follow the page language", %{conn: conn} do
    html = conn |> get(~p"/?lang=es") |> html_response(200)

    assert html =~ ~s(<html lang="es-MX">)
    assert html =~ ~s(<meta property="og:locale" content="es_MX">)
    assert html =~ "Pregúntale a los datos de tu empresa como hablas"
    assert html =~ "Agentic BI · Tu próximo reporte, en una pregunta"

    html = build_conn() |> get(~p"/?lang=en") |> html_response(200)
    assert html =~ ~s(<meta property="og:locale" content="en_US">)
    assert html =~ "Ask your business data in plain language"
  end

  describe "access card" do
    test "before the invitation service is connected, it offers the call and the team demo",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#access[data-mode='public']")
      assert has_element?(view, "#access-call[href*='utm_source=agentic_bi']")
      assert has_element?(view, "#access-full-demo[href='/demo']")
      refute has_element?(view, "#access-request")
    end

    test "with the service connected, a public visitor gets the self-serve form", %{conn: conn} do
      DemoAccessFake.install(self(), [])
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#access-request[href='/invite/solicitar']")
      refute has_element?(view, "#access-full-demo")
    end

    test "an invitee sees the uses left and a way into the live agent", %{conn: conn} do
      DemoAccessFake.install(self(),
        status: %{"inv-1" => {:ok, %{authorized: true, remaining_uses: 2, expires_at: nil}}}
      )

      {:ok, view, _html} =
        conn
        |> put_req_header("accept-language", "es-MX")
        |> put_req_cookie("demo_invitation", "inv-1")
        |> live(~p"/")

      assert has_element?(view, "#access[data-mode='invited']")
      assert has_element?(view, "#access-status", "Te quedan 2 conversaciones.")
      assert has_element?(view, "#access-open[href='/demo']")
      assert_received {:demo_access, :status, ["inv-1"]}
    end

    test "an expired invitation asks for a new one", %{conn: conn} do
      DemoAccessFake.install(self(),
        status: %{"old" => {:ok, %{authorized: false, remaining_uses: 0, expires_at: nil}}}
      )

      {:ok, view, _html} = conn |> put_req_cookie("demo_invitation", "old") |> live(~p"/")

      assert has_element?(view, "#access[data-mode='expired']")
      assert has_element?(view, "#access-request[href='/invite/solicitar']")
    end

    test "the invitation token never reaches the page", %{conn: conn} do
      DemoAccessFake.install(self(),
        status: %{
          "secret-token-value" => {:ok, %{authorized: true, remaining_uses: 3, expires_at: nil}}
        }
      )

      conn = conn |> put_req_cookie("demo_invitation", "secret-token-value") |> get(~p"/")
      html = html_response(conn, 200)

      refute html =~ "secret-token-value"
      # The session cookie is signed, not encrypted: it must not carry the token either.
      [session_cookie] =
        conn |> get_resp_header("set-cookie") |> Enum.filter(&(&1 =~ "_jido_codemode_key"))

      [_prefix, payload, _signature] =
        session_cookie
        |> String.split(";")
        |> hd()
        |> String.split("=", parts: 2)
        |> List.last()
        |> String.split(".")

      assert payload |> Base.url_decode64!(padding: false) |> :binary.match("secret-token-value") ==
               :nomatch
    end
  end
end
