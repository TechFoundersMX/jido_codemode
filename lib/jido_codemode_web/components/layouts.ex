defmodule JidoCodemodeWeb.Layouts do
  use JidoCodemodeWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :app_chrome, :boolean, default: true, doc: "whether to render the top navigation"
  attr :full_width, :boolean, default: false, doc: "whether content should span the page width"
  attr :main_class, :string, default: nil, doc: "optional classes for the main element"
  attr :content_class, :string, default: nil, doc: "optional classes for the content wrapper"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header
      :if={@app_chrome}
      class="border-b border-base-300/60 bg-base-100/90 backdrop-blur supports-[backdrop-filter]:bg-base-100/80"
    >
      <div class="mx-auto flex max-w-7xl items-center justify-between gap-4 px-4 py-4 sm:px-6 lg:px-8">
        <a href={~p"/"} class="flex items-center gap-3">
          <span class="inline-flex size-10 items-center justify-center rounded-2xl bg-primary text-sm font-semibold text-primary-content shadow-sm">
            JC
          </span>

          <div>
            <p class="text-[0.68rem] font-semibold uppercase tracking-[0.24em] text-primary/80">
              Reference App
            </p>
            <p class="text-sm font-semibold tracking-tight text-base-content">Jido Codemode</p>
          </div>
        </a>

        <div class="flex items-center gap-3">
          <a
            href="https://github.com/agentjido/jido"
            class="hidden text-sm font-medium text-base-content/65 transition hover:text-base-content sm:inline-flex"
          >
            Jido
          </a>
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main class={@main_class}>
      <div class={[
        "space-y-4",
        !@full_width && "mx-auto max-w-2xl",
        @content_class
      ]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="relative flex flex-row items-center rounded-full border border-base-300 bg-base-200 p-0.5 shadow-sm">
      <div class="absolute left-0 h-[calc(100%-0.25rem)] w-1/3 rounded-full border border-base-200 bg-base-100 transition-[left] [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3" />

      <button
        class="flex w-1/3 cursor-pointer p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex w-1/3 cursor-pointer p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex w-1/3 cursor-pointer p-2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
