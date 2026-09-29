defmodule JidoCodemodeWeb.CurrencyNote do
  @moduledoc "The footnote that states which currency the Spanish page shows, and at what rate."

  use Gettext, backend: JidoCodemodeWeb.Gettext

  alias JidoCodemode.Locale.{Dataset, Format}

  @spec footnote(String.t(), :usd | :mxn) :: String.t() | nil
  def footnote("es_MX", :mxn) do
    {:ok, fx} = Dataset.fx()

    date =
      case Date.from_iso8601(fx.date) do
        {:ok, date} -> Format.date(date, "es_MX", :short)
        _error -> fx.date
      end

    gettext(
      "Figures in Mexican pesos (MXN), converted from USD at the %{source} exchange rate of %{date}: 1 USD = %{rate} MXN.",
      source: fx.source,
      date: date,
      rate: :erlang.float_to_binary(fx.rate, [:short])
    )
  end

  def footnote("es_MX", _usd), do: gettext("Figures in US dollars (USD).")
  def footnote(_locale, _currency), do: nil
end
