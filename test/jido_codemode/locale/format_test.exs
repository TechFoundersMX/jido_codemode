defmodule JidoCodemode.Locale.FormatTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Locale.Format

  test "money/2 groups digits and labels the currency" do
    assert Format.money(267_868.18, :usd) == "$267,868.18"
    assert Format.money(4_779_116.56, :mxn) == "$4,779,116.56 MXN"
    assert Format.money(1200, :usd) == "$1,200.00"
    assert Format.money(-1234.5, :mxn) == "-$1,234.50 MXN"
  end

  test "percent/1 takes a fraction" do
    assert Format.percent(0.1234) == "12.3%"
    assert Format.percent(1) == "100.0%"
  end

  test "number/1 groups integers and rounds floats to 2 decimals" do
    assert Format.number(1_234_567) == "1,234,567"
    assert Format.number(4_779_116.559999) == "4,779,116.56"
    assert Format.number(12) == "12"
  end

  test "date/3 in Spanish and English" do
    date = ~D[2026-09-28]
    assert Format.date(date, "es_MX", :long) == "28 de septiembre de 2026"
    assert Format.date(date, "es_MX", :short) == "28/09/2026"
    assert Format.date(date, "en", :long) == "September 28, 2026"
    assert Format.date(date, "en", :short) == "09/28/2026"
  end
end
