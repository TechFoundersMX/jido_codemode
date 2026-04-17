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
end
