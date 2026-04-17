defmodule JidoCodemode.Agent.Schema do
  @moduledoc """
  Builds the database context sent to the analytics agent.

  The schema is built from two sources:

  - SQLite introspection against the configured Northwind database
  - curated semantic annotations that improve query quality

  The combined result is cached in memory for reuse across turns.
  """

  alias Exqlite.Sqlite3

  @cache_key {__MODULE__, :schema}
  @table_query """
  SELECT name
  FROM sqlite_master
  WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
  ORDER BY name
  """

  @curated_table_annotations %{
    "Category" => %{
      description: "Product categories used to group products.",
      display_fields: ["CategoryName"]
    },
    "Customer" => %{
      description: "Customers who place orders.",
      display_fields: ["CompanyName"]
    },
    "CustomerCustomerDemo" => %{
      description: "Join table between customers and customer demographics.",
      display_fields: []
    },
    "CustomerDemographic" => %{
      description: "Customer demographic segments.",
      display_fields: ["Id"]
    },
    "Employee" => %{
      description: "Employees responsible for orders and territories.",
      display_fields: ["FirstName", "LastName"]
    },
    "EmployeeTerritory" => %{
      description: "Join table between employees and territories.",
      display_fields: []
    },
    "Order" => %{
      description: "Order header records.",
      display_fields: ["Id", "ShipName"]
    },
    "OrderDetail" => %{
      description: "Order line items with price, quantity, and discount.",
      display_fields: []
    },
    "Product" => %{
      description: "Products sold in orders.",
      display_fields: ["ProductName"]
    },
    "Region" => %{
      description: "Sales regions used by territories.",
      display_fields: ["RegionDescription"]
    },
    "Shipper" => %{
      description: "Shipping companies used to fulfill orders.",
      display_fields: ["CompanyName"]
    },
    "Supplier" => %{
      description: "Suppliers that provide products.",
      display_fields: ["CompanyName"]
    },
    "Territory" => %{
      description: "Sales territories assigned to employees.",
      display_fields: ["TerritoryDescription"]
    }
  }

  @curated_relationships [
    %{
      from: %{table: "CustomerCustomerDemo", column: "CustomerId"},
      to: %{table: "Customer", column: "Id"},
      note: "customer to demographic bridge"
    },
    %{
      from: %{table: "CustomerCustomerDemo", column: "CustomerTypeId"},
      to: %{table: "CustomerDemographic", column: "Id"},
      note: "customer demographic bridge"
    },
    %{
      from: %{table: "Employee", column: "ReportsTo"},
      to: %{table: "Employee", column: "Id"},
      note: "employee manager relationship"
    },
    %{
      from: %{table: "EmployeeTerritory", column: "EmployeeId"},
      to: %{table: "Employee", column: "Id"},
      note: "employee to territory bridge"
    },
    %{
      from: %{table: "EmployeeTerritory", column: "TerritoryId"},
      to: %{table: "Territory", column: "Id"},
      note: "employee to territory bridge"
    },
    %{
      from: %{table: "Order", column: "CustomerId"},
      to: %{table: "Customer", column: "Id"},
      note: "order header to customer"
    },
    %{
      from: %{table: "Order", column: "EmployeeId"},
      to: %{table: "Employee", column: "Id"},
      note: "order header to employee"
    },
    %{
      from: %{table: "Order", column: "ShipVia"},
      to: %{table: "Shipper", column: "Id"},
      note: "order header to shipper"
    },
    %{
      from: %{table: "OrderDetail", column: "OrderId"},
      to: %{table: "Order", column: "Id"},
      note: "order line to order header"
    },
    %{
      from: %{table: "OrderDetail", column: "ProductId"},
      to: %{table: "Product", column: "Id"},
      note: "order line to product"
    },
    %{
      from: %{table: "Product", column: "CategoryId"},
      to: %{table: "Category", column: "Id"},
      note: "product to category"
    },
    %{
      from: %{table: "Product", column: "SupplierId"},
      to: %{table: "Supplier", column: "Id"},
      note: "product to supplier"
    },
    %{
      from: %{table: "Territory", column: "RegionId"},
      to: %{table: "Region", column: "Id"},
      note: "territory to region"
    }
  ]

  @semantic_notes [
    "Customer.CompanyName is the customer display name.",
    "Supplier.CompanyName is the supplier display name.",
    "Shipper.CompanyName is the shipper display name.",
    "Product.ProductName is the product display name.",
    "Category.CategoryName is the category display name.",
    "Employee names are built from FirstName and LastName.",
    "Order is the order header table.",
    "OrderDetail is the order line table.",
    "Revenue formula: OrderDetail.UnitPrice * OrderDetail.Quantity * (1 - OrderDetail.Discount).",
    "OrderDate, RequiredDate, and ShippedDate are stored on Order."
  ]

  @type column :: %{
          name: String.t(),
          type: String.t(),
          nullable?: boolean(),
          primary_key?: boolean(),
          position: non_neg_integer()
        }

  @type relationship :: %{
          from: %{table: String.t(), column: String.t()},
          to: %{table: String.t(), column: String.t()},
          note: String.t()
        }

  @type table :: %{
          name: String.t(),
          description: String.t() | nil,
          display_fields: [String.t()],
          columns: [column()],
          foreign_keys: [relationship()]
        }

  @type schema :: %{
          database: %{name: String.t(), path: String.t()},
          tables: [table()],
          relationships: [relationship()],
          semantic_notes: [String.t()],
          prompt_digest: String.t()
        }

  @spec get() :: schema()
  def get do
    case :persistent_term.get(@cache_key, :missing) do
      :missing ->
        schema = build(database_path())
        :persistent_term.put(@cache_key, schema)
        schema

      schema ->
        schema
    end
  end

  @spec refresh() :: schema()
  def refresh do
    schema = build(database_path())
    :persistent_term.put(@cache_key, schema)
    schema
  end

  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  @spec prompt_digest() :: String.t()
  def prompt_digest do
    get().prompt_digest
  end

  @spec detailed_schema() :: map()
  def detailed_schema do
    schema = get()

    %{
      database: schema.database,
      tables: schema.tables,
      relationships: schema.relationships,
      semantic_notes: schema.semantic_notes
    }
  end

  @spec build(String.t()) :: schema()
  def build(database_path) when is_binary(database_path) do
    with_connection(database_path, fn conn ->
      tables =
        conn
        |> fetch_table_names()
        |> Enum.map(&build_table(conn, &1))

      relationships = merge_relationships(tables)
      semantic_notes = @semantic_notes

      %{
        database: %{
          name: Path.basename(database_path),
          path: database_path
        },
        tables: tables,
        relationships: relationships,
        semantic_notes: semantic_notes,
        prompt_digest:
          build_prompt_digest(Path.basename(database_path), tables, relationships, semantic_notes)
      }
    end)
  end

  defp database_path do
    :jido_codemode
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:database_path, default_database_path())
  end

  defp default_database_path do
    Path.expand("../../../northwind.sqlite", __DIR__)
  end

  defp with_connection(database_path, fun) do
    case Sqlite3.open(database_path, mode: :readonly) do
      {:ok, conn} ->
        try do
          fun.(conn)
        after
          Sqlite3.close(conn)
        end

      {:error, reason} ->
        raise "failed to open analytics database at #{database_path}: #{inspect(reason)}"
    end
  end

  defp fetch_table_names(conn) do
    conn
    |> query!(@table_query)
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  defp build_table(conn, table_name) do
    annotation =
      Map.get(@curated_table_annotations, table_name, %{description: nil, display_fields: []})

    %{
      name: table_name,
      description: annotation.description,
      display_fields: annotation.display_fields,
      columns: fetch_columns(conn, table_name),
      foreign_keys: fetch_foreign_keys(conn, table_name)
    }
  end

  defp fetch_columns(conn, table_name) do
    pragma = "PRAGMA table_info(#{quote_pragma_name(table_name)})"

    conn
    |> query!(pragma)
    |> Enum.map(fn row ->
      %{
        name: Map.fetch!(row, "name"),
        type: Map.fetch!(row, "type") || "",
        nullable?: Map.get(row, "notnull") == 0,
        primary_key?: Map.get(row, "pk") != 0,
        position: Map.get(row, "cid")
      }
    end)
  end

  defp fetch_foreign_keys(conn, table_name) do
    pragma = "PRAGMA foreign_key_list(#{quote_pragma_name(table_name)})"

    conn
    |> query!(pragma)
    |> Enum.map(fn row ->
      relationship(
        table_name,
        Map.fetch!(row, "from"),
        Map.fetch!(row, "table"),
        Map.fetch!(row, "to"),
        "sqlite foreign key"
      )
    end)
  end

  defp merge_relationships(tables) do
    introspected = Enum.flat_map(tables, & &1.foreign_keys)

    (introspected ++ @curated_relationships)
    |> Enum.uniq_by(fn relationship ->
      {
        relationship.from.table,
        relationship.from.column,
        relationship.to.table,
        relationship.to.column
      }
    end)
  end

  defp build_prompt_digest(database_name, tables, relationships, semantic_notes) do
    [
      "Database: #{database_name}",
      "",
      "Tables:",
      Enum.map_join(tables, "\n", &format_table_digest/1),
      "",
      "Key joins:",
      Enum.map_join(relationships, "\n", &format_relationship_digest/1),
      "",
      "Semantic notes:",
      Enum.map_join(semantic_notes, "\n", &"- #{&1}")
    ]
    |> Enum.join("\n")
    |> String.trim()
  end

  defp format_table_digest(table) do
    columns =
      table.columns
      |> Enum.map_join(", ", fn column ->
        suffix =
          cond do
            column.primary_key? -> " pk"
            not column.nullable? -> " required"
            true -> ""
          end

        "#{column.name} (#{column.type}#{suffix})"
      end)

    extras =
      [
        table.description && "description: #{table.description}",
        table.display_fields != [] && "display fields: #{Enum.join(table.display_fields, ", ")}"
      ]
      |> Enum.reject(&(&1 in [nil, false]))

    base = "- #{table.name}: #{columns}"

    case extras do
      [] -> base
      _ -> base <> "; " <> Enum.join(extras, "; ")
    end
  end

  defp format_relationship_digest(relationship) do
    "- #{relationship.from.table}.#{relationship.from.column} -> #{relationship.to.table}.#{relationship.to.column} (#{relationship.note})"
  end

  defp query!(conn, sql) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, statement} ->
        try do
          with {:ok, columns} <- Sqlite3.columns(conn, statement),
               {:ok, rows} <- Sqlite3.fetch_all(conn, statement) do
            Enum.map(rows, fn row ->
              columns
              |> Enum.zip(row)
              |> Map.new()
            end)
          else
            {:error, reason} ->
              raise "failed to execute schema query #{inspect(sql)}: #{inspect(reason)}"
          end
        after
          Sqlite3.release(conn, statement)
        end

      {:error, reason} ->
        raise "failed to prepare schema query #{inspect(sql)}: #{inspect(reason)}"
    end
  end

  defp quote_pragma_name(name) do
    "'" <> String.replace(name, "'", "''") <> "'"
  end

  defp relationship(from_table, from_column, to_table, to_column, note) do
    %{
      from: %{table: from_table, column: from_column},
      to: %{table: to_table, column: to_column},
      note: note
    }
  end
end
