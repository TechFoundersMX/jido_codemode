import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/jido_codemode start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :jido_codemode, JidoCodemodeWeb.Endpoint, server: true
end

config :jido_codemode, JidoCodemodeWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :jido_codemode,
  demo_password: System.get_env("DEMO_PASSWORD")

present_env = fn name ->
  case System.get_env(name) do
    value when is_binary(value) and value != "" -> value
    _other -> nil
  end
end

# SuperDev AI Gateway mode. When both Cloudflare Access service-token values
# are set, OpenCode requests go through gateway.superdev.mx, which injects the
# stored OpenCode key (BYOK). The app then must not send a provider key: a
# request-supplied Authorization header overrides the gateway's stored key.
# Contract: TechFoundersMX/monorepo docs/ai-gateway.md.
opencode_gateway =
  case {present_env.("CF_ACCESS_CLIENT_ID"), present_env.("CF_ACCESS_CLIENT_SECRET")} do
    {nil, nil} ->
      nil

    {client_id, client_secret} when is_binary(client_id) and is_binary(client_secret) ->
      if present_env.("OPENCODE_API_KEY") || present_env.("OPENAI_API_KEY") do
        raise "AI Gateway mode is enabled (CF_ACCESS_CLIENT_ID is set). Unset OPENCODE_API_KEY " <>
                "and OPENAI_API_KEY: a provider key would override the gateway's stored key."
      end

      domain = present_env.("AI_GATEWAY_DOMAIN") || "gateway.superdev.mx"

      unless Regex.match?(~r/^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9-]+$/, domain) do
        raise "AI_GATEWAY_DOMAIN must be a bare hostname, got: #{inspect(domain)}"
      end

      %{
        domain: domain,
        headers: [
          {"cf-access-client-id", client_id},
          {"cf-access-client-secret", client_secret},
          {"cf-aig-byok-alias", present_env.("AI_GATEWAY_KEY_ALIAS") || "production"}
        ]
      }

    _partial ->
      raise "Set both CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET for AI Gateway mode, or neither."
  end

opencode_base_url =
  present_env.("OPENCODE_BASE_URL") ||
    if(opencode_gateway,
      do: "https://#{opencode_gateway.domain}/opencode/v1",
      else: "https://opencode.ai/zen/go/v1"
    )

# The Access credentials must only ever be sent to the gateway itself.
if opencode_gateway &&
     not String.starts_with?(opencode_base_url, "https://#{opencode_gateway.domain}/") do
  raise "In AI Gateway mode OPENCODE_BASE_URL must point at https://#{opencode_gateway.domain}/, " <>
          "got: #{opencode_base_url}"
end

# ReqLLM routes GPT-5 models through OpenCode Go's Responses API.
opencode_model = present_env.("OPENCODE_MODEL") || "gpt-5.6-luna"

# In gateway mode, `openai_compatible_backend: :ollama` makes ReqLLM send no
# Authorization header when no API key is configured. Despite the name, this
# is its only effect in ReqLLM 1.10: it permits a missing API key.
opencode_model_spec =
  if opencode_gateway,
    do: %{provider: :openai, id: opencode_model, extra: %{openai_compatible_backend: :ollama}},
    else: %{provider: :openai, id: opencode_model}

config :jido_ai,
  model_aliases: %{
    fast: opencode_model_spec,
    capable: opencode_model_spec
  },
  llm_defaults: %{
    text: %{temperature: 1.0},
    object: %{temperature: 1.0},
    stream: %{temperature: 1.0}
  }

config :jido_codemode, JidoCodemode.AI,
  base_url: opencode_base_url,
  model: opencode_model,
  gateway_headers: if(opencode_gateway, do: opencode_gateway.headers, else: [])

opencode_api_key = present_env.("OPENCODE_API_KEY")

if opencode_api_key do
  config :req_llm, :openai_api_key, opencode_api_key
end

if opencode_api_key || opencode_gateway do
  config :req_llm, :openai, base_url: opencode_base_url
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :jido_codemode, JidoCodemodeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :jido_codemode, JidoCodemodeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :jido_codemode, JidoCodemodeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
