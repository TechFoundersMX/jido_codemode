defmodule JidoCodemode.Locale.Format do
  @moduledoc """
  Number and date formatting for the demo's two locales. Mexico uses the same
  digit grouping and decimal point as the US, so only labels and dates differ.
  """

  @es_months ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
  @en_months ~w(January February March April May June July August September October November December)

  @spec money(number(), :usd | :mxn) :: String.t()
  def money(value, currency) when is_number(value) do
    sign = if value < 0, do: "-", else: ""
    amount = "$" <> delimit(abs(value), 2)

    case currency do
      :mxn -> sign <> amount <> " MXN"
      _usd -> sign <> amount
    end
  end

  @spec percent(number()) :: String.t()
  def percent(fraction) when is_number(fraction), do: delimit(fraction * 100, 1) <> "%"

  @spec number(number()) :: String.t()
  def number(value) when is_integer(value), do: delimit(value, 0)
  def number(value) when is_float(value), do: delimit(value, 2)

  @spec date(Date.t(), String.t(), :long | :short) :: String.t()
  def date(%Date{} = date, "es_MX", :long),
    do: "#{date.day} de #{Enum.at(@es_months, date.month - 1)} de #{date.year}"

  def date(%Date{} = date, "es_MX", :short),
    do: "#{pad(date.day)}/#{pad(date.month)}/#{date.year}"

  def date(%Date{} = date, _locale, :long),
    do: "#{Enum.at(@en_months, date.month - 1)} #{date.day}, #{date.year}"

  def date(%Date{} = date, _locale, :short),
    do: "#{pad(date.month)}/#{pad(date.day)}/#{date.year}"

  defp delimit(value, decimals) do
    formatted = :erlang.float_to_binary(value * 1.0, decimals: decimals)
    {sign, digits} = split_sign(formatted)
    [integer | fraction] = String.split(digits, ".")

    grouped =
      integer
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign <> Enum.join([grouped | fraction], ".")
  end

  defp split_sign("-" <> digits), do: {"-", digits}
  defp split_sign(digits), do: {"", digits}

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
