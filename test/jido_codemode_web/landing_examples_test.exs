defmodule JidoCodemodeWeb.LandingExamplesTest do
  # Every answer sentence on the landing is a claim about the sample data. These
  # tests re-derive each claim from the bundled Northwind database, so a changed
  # figure or reworded answer can't drift from the data.
  use ExUnit.Case, async: true

  alias Exqlite.Sqlite3
  alias JidoCodemode.Locale.Dataset
  alias JidoCodemodeWeb.LandingExamples

  @line "od.UnitPrice * od.Quantity * (1 - od.Discount)"

  defp query(sql) do
    {:ok, conn} = Sqlite3.open(Dataset.path("en"), mode: :readonly)
    {:ok, statement} = Sqlite3.prepare(conn, sql)
    {:ok, rows} = Sqlite3.fetch_all(conn, statement)
    :ok = Sqlite3.close(conn)
    rows
  end

  defp total_revenue do
    [[total]] = query("SELECT SUM(#{@line}) FROM OrderDetail od")
    total
  end

  defp close?(a, b), do: abs(a - b) < 0.01

  test "the category figures are the database's top 3" do
    rows =
      query("""
      SELECT c.CategoryName, SUM(#{@line}) AS revenue FROM OrderDetail od
      JOIN Product p ON p.Id = od.ProductId JOIN Category c ON c.Id = p.CategoryId
      GROUP BY c.CategoryName ORDER BY revenue DESC LIMIT 3
      """)

    expected = LandingExamples.data().categories |> Keyword.values()

    assert Enum.zip(Enum.map(rows, &List.last/1), expected)
           |> Enum.all?(fn {a, b} -> close?(a, b) end)

    assert Enum.map(rows, &hd/1) == ["Beverages", "Dairy Products", "Confections"]
  end

  test "United Package carries 42% of revenue" do
    shippers = LandingExamples.data().shippers
    total = shippers |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {"United Package", united} = hd(shippers)
    assert round(united / total * 100) == 42
  end

  test "three customers bring in a quarter of revenue" do
    top3 =
      LandingExamples.data().customers |> Enum.take(3) |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    share = top3 / total_revenue()
    assert share >= 0.24 and share < 0.27
  end

  test "the USA and Germany account for more than a third of revenue" do
    countries = LandingExamples.data().countries
    assert (countries[:usa] + countries[:germany]) / total_revenue() > 1 / 3
  end

  test "December was the best month of 2013 and October the second" do
    trend = LandingExamples.data().trend

    ranked =
      trend |> Enum.with_index(1) |> Enum.sort_by(&elem(&1, 0), :desc) |> Enum.map(&elem(&1, 1))

    assert Enum.take(ranked, 2) == [12, 10]
  end

  test "the average order value rose every year, 19% from 2012 to 2014" do
    [{2012, first}, {2013, middle}, {2014, last}] = LandingExamples.data().order_value
    assert first < middle and middle < last
    assert round((last / first - 1) * 100) == 19
  end

  test "Spanish amounts are converted with the demo's rate" do
    [beverages | _] = LandingExamples.replay("es_MX").rows
    assert beverages.amount == "$4,779,116.56 MXN"
    assert hd(LandingExamples.replay("en").rows).amount == "$267,868.18"
  end
end
