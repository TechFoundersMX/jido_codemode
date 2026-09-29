defmodule JidoCodemodeWeb.Router do
  use JidoCodemodeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug JidoCodemodeWeb.Plugs.Locale
    plug JidoCodemodeWeb.Plugs.DemoAccess
    plug :fetch_live_flash
    plug :put_root_layout, html: {JidoCodemodeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :staff do
    plug JidoCodemodeWeb.Plugs.StaffAccess
  end

  # Co-founders only: Cloudflare Access guards /live*, and the plug verifies its token.
  scope "/", JidoCodemodeWeb do
    pipe_through [:browser, :staff]

    live_session :staff, on_mount: [JidoCodemodeWeb.LocaleHook, JidoCodemodeWeb.StaffHook] do
      live "/live", SandboxLive, :staff
    end
  end

  scope "/", JidoCodemodeWeb do
    pipe_through :browser

    get "/health", PageController, :health

    live_session :default, on_mount: [JidoCodemodeWeb.LocaleHook] do
      live "/", LandingLive
      live "/demo", SandboxLive
    end
  end
end
