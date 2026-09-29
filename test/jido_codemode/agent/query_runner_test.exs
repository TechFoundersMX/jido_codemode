defmodule JidoCodemode.Agent.QueryRunnerTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Agent.QueryRunner
  alias JidoCodemode.Agent.Tools.RunSqliteQuery

  test "runs a read-only query in memory" do
    {:ok, result} =
      QueryRunner.run(
        "SELECT ProductName, UnitPrice FROM Product ORDER BY UnitPrice DESC LIMIT 3",
        :table
      )

    assert result.columns == ["ProductName", "UnitPrice"]
    assert result.preview_columns == ["ProductName", "UnitPrice"]
    assert length(result.rows) == 3
    assert length(result.preview_rows) == 3
    assert result.row_count == 3
    assert result.truncated == false

    assert QueryRunner.to_source(result) == %{
             "columns" => ["ProductName", "UnitPrice"],
             "row_count" => 3,
             "rows" => result.rows,
             "truncated" => false
           }

    assert QueryRunner.to_preview(result) == %{
             columns: ["ProductName", "UnitPrice"],
             preview_rows: result.preview_rows,
             row_count: 3,
             truncated: false,
             preview_limited: false,
             column_count: 2,
             omitted_columns_count: 0,
             elapsed_ms: result.elapsed_ms
           }
  end

  test "enforces hard row limits and preview limits" do
    {:ok, result} = QueryRunner.run("SELECT Id FROM \"Order\" ORDER BY Id", "table")

    assert result.truncated == true
    assert result.row_count == 100
    assert length(result.preview_rows) == 20
    assert result.preview_limited == true
  end

  test "rejects invalid SQL" do
    assert {:error, {:invalid_sql, :only_select_and_with_are_allowed}} =
             QueryRunner.run("DELETE FROM Product", :analysis)

    assert {:error, {:invalid_sql, :multiple_statements_not_allowed}} =
             QueryRunner.run("SELECT 1; SELECT 2", :analysis)
  end

  test "run_sqlite_query action delegates to query runner" do
    {:ok, result} =
      RunSqliteQuery.run(
        %{
          sql: "SELECT CategoryName FROM Category ORDER BY CategoryName LIMIT 2",
          purpose: "analysis"
        },
        %{}
      )

    assert result.columns == ["CategoryName"]
    assert length(result.preview_rows) == 2
  end

  test "a Spanish query reads Spanish labels and MXN amounts" do
    {:ok, result} =
      QueryRunner.run(
        """
        SELECT c.CategoryName, ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS revenue
        FROM OrderDetail od
        JOIN Product p ON p.Id = od.ProductId
        JOIN Category c ON c.Id = p.CategoryId
        WHERE c.CategoryName = 'Bebidas'
        GROUP BY c.CategoryName
        """,
        :analysis,
        locale: "es_MX"
      )

    assert [%{"CategoryName" => "Bebidas", "revenue" => revenue}] = result.rows
    assert_in_delta revenue, 4_779_116.56, 0.01
  end

  test "an English query still reads USD and English labels" do
    {:ok, result} =
      QueryRunner.run(
        "SELECT CategoryName FROM Category WHERE CategoryName = 'Beverages'",
        :analysis
      )

    assert result.rows == [%{"CategoryName" => "Beverages"}]
  end

  test "run_sqlite_query uses the locale from the tool context" do
    {:ok, result} =
      RunSqliteQuery.run(
        %{
          sql: "SELECT CategoryName FROM Category WHERE CategoryName = 'Lácteos'",
          purpose: "analysis"
        },
        %{locale: "es_MX"}
      )

    assert result.preview_rows == [["Lácteos"]]
  end
end
