defmodule JidoCodemode.Agent.Tools.RunSqliteQuery do
  @moduledoc false

  use Jido.Action,
    name: "run_sqlite_query",
    description: "Run a read-only SQLite query and return a compact preview",
    schema: [
      sql: [
        type: :string,
        required: true,
        doc: "A single read-only SELECT or WITH query against the analytics SQLite database."
      ],
      purpose: [
        type: {:in, ["analysis", "chart", "table"]},
        required: true,
        doc: "Why the query is being run. This controls limits and preview behavior."
      ]
    ]

  alias JidoCodemode.Agent.QueryRunner

  @impl true
  def run(%{sql: sql, purpose: purpose}, _context) do
    with {:ok, result} <- QueryRunner.run(sql, purpose) do
      {:ok, QueryRunner.to_preview(result)}
    end
  end
end
