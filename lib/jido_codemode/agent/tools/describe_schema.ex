defmodule JidoCodemode.Agent.Tools.DescribeSchema do
  @moduledoc false

  use Jido.Action,
    name: "describe_schema",
    description: "Describe the analytics database schema and semantic notes",
    schema: [
      tables: [
        type: {:list, :string},
        default: [],
        doc: "Optional table names to focus on. Leave empty to return the full schema."
      ]
    ]

  alias JidoCodemode.Agent.Schema

  @impl true
  def run(params, _context) do
    schema = Schema.detailed_schema()
    requested_tables = Map.get(params, :tables, [])

    {tables, relationships, missing_tables} = filter_schema(schema, requested_tables)

    result = %{
      database: schema.database,
      tables: tables,
      relationships: relationships,
      semantic_notes: schema.semantic_notes,
      requested_tables: requested_tables,
      missing_tables: missing_tables
    }

    {:ok, result}
  end

  defp filter_schema(schema, []), do: {schema.tables, schema.relationships, []}

  defp filter_schema(schema, requested_tables) do
    requested = MapSet.new(requested_tables)

    tables = Enum.filter(schema.tables, &MapSet.member?(requested, &1.name))
    available = MapSet.new(Enum.map(tables, & &1.name))

    relationships =
      Enum.filter(schema.relationships, fn relationship ->
        MapSet.member?(available, relationship.from.table) or
          MapSet.member?(available, relationship.to.table)
      end)

    missing_tables =
      requested
      |> MapSet.difference(available)
      |> Enum.sort()

    {tables, relationships, missing_tables}
  end
end
