defmodule JidoCodemode.Locale.DatasetTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias JidoCodemode.Locale.Dataset

  setup do
    previous = Application.get_env(:jido_codemode, Dataset)

    target =
      Path.join(System.tmp_dir!(), "dataset-test-#{System.unique_integer([:positive])}.sqlite")

    on_exit(fn ->
      File.rm(target)

      if previous,
        do: Application.put_env(:jido_codemode, Dataset, previous),
        else: Application.delete_env(:jido_codemode, Dataset)

      Dataset.reset()
    end)

    %{target: target, source: Dataset.source_path()}
  end

  test "parse_rate/1 accepts only positive numbers" do
    assert Dataset.parse_rate("17.8413") == {:ok, 17.8413}
    assert Dataset.parse_rate(" 18 ") == {:ok, 18.0}
    assert Dataset.parse_rate(17.5) == {:ok, 17.5}
    assert Dataset.parse_rate("abc") == :error
    assert Dataset.parse_rate("0") == :error
    assert Dataset.parse_rate("-3") == :error
    assert Dataset.parse_rate(nil) == :error
  end

  test "build/3 converts exactly the three money columns", %{source: source, target: target} do
    assert :ok = Dataset.build(source, target, 2.0)

    for {table, column} <- [
          {"OrderDetail", "UnitPrice"},
          {"Product", "UnitPrice"},
          {"Order", "Freight"}
        ] do
      sql = ~s|SELECT SUM("#{column}") FROM "#{table}"|
      assert_in_delta scalar(target, sql), scalar(source, sql) * 2.0, 0.01
    end

    discount = ~s|SELECT SUM(Discount) FROM "OrderDetail"|
    assert scalar(target, discount) == scalar(source, discount)
  end

  test "build/3 translates categories and countries and keeps proper nouns", %{
    source: source,
    target: target
  } do
    assert :ok = Dataset.build(source, target, 2.0)

    assert scalar(target, ~s|SELECT COUNT(*) FROM "Category" WHERE CategoryName = 'Bebidas'|) == 1

    assert scalar(target, ~s|SELECT COUNT(*) FROM "Category" WHERE CategoryName = 'Beverages'|) ==
             0

    assert scalar(target, ~s|SELECT COUNT(*) FROM "Order" WHERE ShipCountry = 'Alemania'|) > 0
    assert scalar(target, ~s|SELECT COUNT(*) FROM "Customer" WHERE Country = 'Germany'|) == 0

    assert scalar(target, ~s|SELECT COUNT(*) FROM "Supplier" WHERE Country = 'Estados Unidos'|) >
             0

    product = ~s|SELECT ProductName FROM "Product" ORDER BY Id LIMIT 1|
    assert scalar(target, product) == scalar(source, product)
  end

  test "build/3 with no rate translates labels but keeps USD amounts", %{
    source: source,
    target: target
  } do
    assert :ok = Dataset.build(source, target, nil)

    sql = ~s|SELECT SUM(UnitPrice) FROM "Product"|
    assert scalar(target, sql) == scalar(source, sql)
    assert scalar(target, ~s|SELECT COUNT(*) FROM "Category" WHERE CategoryName = 'Lácteos'|) == 1
  end

  test "the built copy is read-only", %{source: source, target: target} do
    assert :ok = Dataset.build(source, target, 2.0)
    assert {:error, :eacces} = File.write(target, "x")
  end

  test "setup/0 with a valid rate serves MXN for Spanish and USD for English" do
    Application.put_env(:jido_codemode, Dataset,
      fx_usd_mxn: "17.8413",
      fx_date: "2026-09-28",
      fx_source: "FIX de Banxico"
    )

    Dataset.reset()

    assert Dataset.currency("es_MX") == :mxn
    assert Dataset.labels("es_MX") == :es
    assert Dataset.rate("es_MX") == 17.8413
    assert Dataset.currency("en") == :usd
    assert Dataset.rate("en") == 1.0
    assert Dataset.path("en") == Dataset.source_path()
    refute Dataset.path("es_MX") == Dataset.source_path()
  end

  @tag :capture_log
  test "setup/0 with an invalid rate falls back to USD but keeps Spanish labels" do
    Application.put_env(:jido_codemode, Dataset, fx_usd_mxn: "abc")
    Dataset.reset()

    assert Dataset.currency("es_MX") == :usd
    assert Dataset.labels("es_MX") == :es
    assert Dataset.rate("es_MX") == 1.0
  end

  test "target_path/1 is unique per BEAM and per call" do
    first = Dataset.target_path("/tmp")
    second = Dataset.target_path("/tmp")

    assert Path.dirname(first) == "/tmp"
    assert Path.basename(first) =~ System.pid()
    assert String.ends_with?(first, ".sqlite")
    refute first == second
  end

  test "target_path/1 has no path when there is no temp directory" do
    assert Dataset.target_path(nil) == nil
  end

  defp scalar(path, sql) do
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)
    {:ok, statement} = Sqlite3.prepare(conn, sql)
    {:row, [value]} = Sqlite3.step(conn, statement)
    :ok = Sqlite3.release(conn, statement)
    :ok = Sqlite3.close(conn)
    value
  end
end
