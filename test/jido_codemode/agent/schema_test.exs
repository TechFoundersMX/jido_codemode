defmodule JidoCodemode.Agent.SchemaTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Agent.Schema
  alias JidoCodemode.Agent.Tools.DescribeSchema

  @database_path Path.expand("../../../northwind.sqlite", __DIR__)

  test "builds the northwind schema with prompt digest" do
    schema = Schema.build(@database_path)

    assert schema.database.name == "northwind.sqlite"
    assert length(schema.tables) >= 10
    assert Enum.any?(schema.tables, &(&1.name == "Order"))
    assert Enum.any?(schema.tables, &(&1.name == "OrderDetail"))

    assert Enum.any?(schema.relationships, fn relationship ->
             relationship.from.table == "OrderDetail" and
               relationship.from.column == "OrderId" and
               relationship.to.table == "Order"
           end)

    assert schema.prompt_digest =~ "Database: northwind.sqlite"

    assert schema.prompt_digest =~
             "Revenue formula: OrderDetail.UnitPrice * OrderDetail.Quantity * (1 - OrderDetail.Discount)."

    assert schema.prompt_digest =~ "Order.CustomerId -> Customer.Id"
  end

  test "describe_schema can narrow to requested tables" do
    {:ok, result} = DescribeSchema.run(%{tables: ["Order", "OrderDetail"]}, %{})

    assert Enum.map(result.tables, & &1.name) == ["Order", "OrderDetail"]

    assert Enum.any?(result.relationships, fn relationship ->
             relationship.from.table == "OrderDetail" and relationship.to.table == "Order"
           end)

    assert result.missing_tables == []
  end

  test "describe_schema reports missing tables" do
    {:ok, result} = DescribeSchema.run(%{tables: ["Order", "DoesNotExist"]}, %{})

    assert Enum.map(result.tables, & &1.name) == ["Order"]
    assert result.missing_tables == ["DoesNotExist"]
    refute Map.has_key?(result, :prompt_digest)
  end
end
