defmodule JidoCodemode.AI do
  @moduledoc false

  def config! do
    Application.fetch_env!(:jido_codemode, __MODULE__)
  end

  def model do
    Keyword.fetch!(config!(), :model)
  end

  def base_url do
    Keyword.fetch!(config!(), :base_url)
  end

  @doc """
  Headers every OpenCode request must carry.

  Empty in direct-key mode. In AI Gateway mode, the Cloudflare Access service
  token and the BYOK alias that selects the gateway's stored OpenCode key.
  """
  def request_headers do
    Keyword.get(config!(), :gateway_headers, [])
  end
end
