defmodule JidoCodemodeWeb.Router do
  use JidoCodemodeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug JidoCodemodeWeb.Plugs.Locale
    plug :fetch_live_flash
    plug :put_root_layout, html: {JidoCodemodeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", JidoCodemodeWeb do
    pipe_through :browser

    get "/health", PageController, :health

    live_session :default, on_mount: [JidoCodemodeWeb.LocaleHook] do
      live "/", SandboxLive
    end
  end
end
