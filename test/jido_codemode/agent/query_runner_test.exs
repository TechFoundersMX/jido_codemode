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
end
