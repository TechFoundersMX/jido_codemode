defmodule JidoCodemode.Agent.Tools.BuildReport do
  @moduledoc false

  alias Jido.Action.Error
  alias JidoCodemode.Agent.QueryRunner
  alias JidoCodemode.Agent.Report
  alias JidoCodemode.Agent.ReportStore
  alias JidoCodemode.Agent.Schema

  @description """
  Execute a short Lua analytics script in a sandboxed VM.

  Use this tool to build a report when the task requires multiple queries, intermediate logic, and a final rendered report.
  Prefer the `report.*` helper functions instead of hand-writing chart block maps.

  Available Lua APIs:

  - `schema.digest()` -> returns the compact schema digest string already used in the base agent context
  - `db.query({ sql = string, purpose = \"analysis\" | \"chart\" | \"table\" })`
    -> returns `{ columns = {string, ...}, rows = { { column = value, ... }, ... }, row_count = number, truncated = boolean }`
  - `report.build({ version?, title, summary?, blocks })` -> returns a report payload table
  - `report.field({ field, type, format? })` -> returns a field reference table
  - `report.text({ id, body })` -> returns a text block table
  - `report.metric({ id, label, value, format })` -> returns a metric block table
  - `report.table({ id, title, source, columns, row_limit?, summary? })` -> returns a table block table
  - `report.line({ id, title, source, x, y, summary?, color_by?, size_by? })` -> returns a line chart block table
  - `report.bar({ id, title, source, x, y, summary?, color_by?, size_by? })` -> returns a bar chart block table
  - `report.donut({ id, title, source, x?, y?, label_field?, label_type?, label_format?, value_field?, value_type?, value_format?, summary? })`
    -> returns a donut chart block table. Prefer `label_field` and `value_field` for pie-style charts.
  - `report.pie(...)` -> alias for `report.donut(...)`
  - `report.scatter({ id, title, source, x, y, summary?, color_by?, size_by? })` -> returns a scatter chart block table

  Your Lua script must `return` the final report payload as a Lua table, ideally from `report.build(...)`.
  Elixir validates the returned report structure and stores it after the script finishes.
  Return the final report payload from Lua instead of trying to call another report tool.

  Lua notes:

  - Lua arrays are 1-based, not 0-based
  - Use tables for maps and lists
  - Example map: `{ title = \"Revenue\", version = 1 }`
  - Example list: `{\"customer\", \"revenue\"}`
  - Table block `row_limit` values above 20 are clamped to 20
  - Supported chart kinds are `line`, `bar`, `donut`, and `scatter`
  - Use `donut` for pie-style charts. `report.pie(...)` is accepted as a friendly alias.

  Example:

  ```lua
  local customers = db.query({
    sql = [[
      SELECT c.CompanyName AS customer,
             ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS revenue
      FROM "Order" o
      JOIN Customer c ON c.Id = o.CustomerId
      JOIN OrderDetail od ON od.OrderId = o.Id
      GROUP BY c.CompanyName
      ORDER BY revenue DESC
      LIMIT 10
    ]],
    purpose = "analysis"
  })

  return report.build({
    version = 1,
    title = "Revenue by customer",
    summary = "Top customers by revenue.",
    blocks = {
      report.bar({
        id = "customer_revenue_chart",
        title = "Revenue by customer",
        source = customers,
        x = report.field({ field = "customer", type = "nominal", format = "string" }),
        y = report.field({ field = "revenue", type = "quantitative", format = "currency" })
      }),
      report.table({
        id = "customer_revenue_table",
        title = "Top customers",
        source = customers,
        columns = {"customer", "revenue"},
        row_limit = 10
      })
    }
  })
  ```

  Donut example:

  ```lua
  return report.build({
    version = 1,
    title = "Revenue mix by channel",
    blocks = {
      report.donut({
        id = "channel_mix",
        title = "Revenue mix by channel",
        source = customers,
        label_field = "customer",
        value_field = "revenue",
        value_format = "currency"
      })
    }
  })
  ```

  If a function fails, read the returned tool error, fix the script, and retry.
  """

  use Jido.Action,
    name: "BuildReport",
    description: @description,
    schema: [
      code: [
        type: :string,
        required: true,
        doc:
          "Lua analytics script to execute. Use schema.digest() and db.query(...), then return the final report payload as a Lua table."
      ],
      timeout_ms: [
        type: :non_neg_integer,
        default: 5_000,
        doc: "Execution timeout in milliseconds."
      ],
      max_heap_bytes: [
        type: :non_neg_integer,
        default: 0,
        doc: "Per-process heap limit in bytes. 0 disables the limit."
      ]
    ],
    output_schema: []

  @impl true
  def run(params, context) do
    if Code.ensure_loaded?(Lua) do
      timeout_ms = Map.get(params, :timeout_ms, 5_000)

      JidoCodemode.Agent.TaskSupervisor
      |> Task.Supervisor.async_nolink(fn -> do_run(params, context) end)
      |> await_result(timeout_ms)
    else
      {:error,
       Error.execution_error("Lua library is not available", %{
         hint: "Add {:lua, \"~> 0.4\"} to your deps and restart the server.",
         type: :dependency_error
       })}
    end
  end

  defp await_result(task, timeout_ms) do
    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} ->
        result

      nil ->
        {:error,
         Error.timeout_error("Lua execution timed out after #{timeout_ms}ms", %{
           timeout: timeout_ms
         })}
    end
  end

  defp do_run(params, context) do
    code = Map.fetch!(params, :code)
    max_heap_bytes = Map.get(params, :max_heap_bytes, 0)

    if is_integer(max_heap_bytes) and max_heap_bytes > 0 do
      :erlang.process_flag(:max_heap_size, %{size: max_heap_bytes, kill: true})
    end

    lua =
      Lua.new()
      |> Lua.put_private(:tool_context, context)
      |> Lua.load_api(__MODULE__.SchemaAPI)
      |> Lua.load_api(__MODULE__.DbAPI)
      |> Lua.load_api(__MODULE__.ReportAPI)

    try do
      {values, _state} = Lua.eval!(lua, code)
      values = Enum.map(values, &normalize_lua_value/1)

      with {:ok, raw_report} <- fetch_report_result(values),
           {:ok, report} <- Report.normalize(raw_report),
           :ok <- ReportStore.put(report, metadata(context)) do
        {:ok,
         %{
           title: report.title,
           block_count: length(report.blocks)
         }}
      else
        {:error, reason} ->
          {:error, invalid_report_error(reason, code, values)}
      end
    rescue
      e in Lua.CompilerException ->
        {:error,
         Error.execution_error("Lua compile error: #{Exception.message(e)}", %{
           type: :compile_error,
           code: code
         })}

      e in Lua.RuntimeException ->
        {:error,
         Error.execution_error("Lua runtime error: #{Exception.message(e)}", %{
           type: :lua_error,
           code: code
         })}

      e ->
        {:error,
         Error.execution_error("Lua execution failed: #{Exception.message(e)}", %{
           type: :lua_error,
           code: code
         })}
    end
  end

  def normalize_lua_value(value) when is_map(value) do
    normalized =
      Enum.into(value, %{}, fn {key, inner_value} ->
        {normalize_lua_key(key), normalize_lua_value(inner_value)}
      end)

    if numeric_index_map?(normalized) do
      normalized
      |> Enum.sort_by(fn {key, _value} -> String.to_integer(key) end)
      |> Enum.map(fn {_key, inner_value} -> inner_value end)
    else
      normalized
    end
  end

  def normalize_lua_value(value) when is_list(value) do
    cond do
      Enum.all?(value, &match?({_, _}, &1)) ->
        value
        |> Enum.into(%{}, fn {key, inner_value} ->
          {normalize_lua_key(key), normalize_lua_value(inner_value)}
        end)
        |> normalize_lua_value()

      Enum.all?(value, &is_integer/1) ->
        List.to_string(value)

      true ->
        Enum.map(value, &normalize_lua_value/1)
    end
  end

  def normalize_lua_value(value), do: value

  defp normalize_lua_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_lua_key(key) when is_binary(key), do: key

  defp normalize_lua_key(key) when is_list(key) do
    if Enum.all?(key, &is_integer/1) do
      List.to_string(key)
    else
      to_string(key)
    end
  end

  defp normalize_lua_key(key), do: to_string(key)

  defp numeric_index_map?(map) when map_size(map) == 0, do: false

  defp numeric_index_map?(map) do
    Enum.all?(Map.keys(map), &match?(<<_::binary>>, &1)) and
      Enum.all?(Map.keys(map), fn key -> Regex.match?(~r/^\d+$/, key) end)
  end

  defp fetch_report_result([report | _rest]) when is_map(report), do: {:ok, report}
  defp fetch_report_result([]), do: {:error, :missing_return_value}
  defp fetch_report_result([other | _rest]), do: {:error, {:invalid_return_value, other}}

  defp metadata(context) do
    case Map.get(context, :session_id) do
      session_id when is_binary(session_id) -> %{session_id: session_id}
      _ -> %{}
    end
  end

  defp invalid_report_error(reason, code, values) do
    Error.execution_error(
      "BuildReport must return a valid report payload as the first Lua return value. #{humanize_report_reason(reason)}",
      %{
        reason: inspect(reason, pretty: true, limit: :infinity),
        hint:
          "Return a Lua table with version, title, and blocks. Prefer report.build/report.bar/report.donut helpers when possible.",
        returned_values: values,
        code: code
      }
    )
  end

  defp humanize_report_reason(:missing_return_value), do: "The script returned nothing."

  defp humanize_report_reason({:invalid_return_value, value}),
    do: "The first returned value was not a report map: #{inspect(value)}"

  defp humanize_report_reason(reason), do: inspect(reason, pretty: true, limit: :infinity)

  defmodule SchemaAPI do
    @moduledoc false

    use Lua.API, scope: "schema"

    deflua digest() do
      Schema.prompt_digest()
    end
  end

  defmodule DbAPI do
    @moduledoc false

    use Lua.API, scope: "db"

    deflua query(params), state do
      params =
        state |> Lua.decode!(params) |> JidoCodemode.Agent.Tools.BuildReport.normalize_lua_value()

      sql = Map.get(params, "sql")
      purpose = Map.get(params, "purpose") || "analysis"

      case QueryRunner.run(sql, purpose) do
        {:ok, result} ->
          {encoded, state} = Lua.encode!(state, QueryRunner.to_source(result))
          {[encoded], state}

        {:error, reason} ->
          raise "db.query failed: #{humanize_reason(reason)}"
      end
    end

    defp humanize_reason(reason), do: inspect(reason, pretty: true, limit: :infinity)
  end

  defmodule ReportAPI do
    @moduledoc false

    use Lua.API, scope: "report"

    deflua build(params), state do
      params
      |> decode_params!(state)
      |> build_report()
      |> encode_result(state)
    end

    deflua field(params), state do
      params
      |> decode_params!(state)
      |> build_field_ref()
      |> encode_result(state)
    end

    deflua text(params), state do
      params
      |> decode_params!(state)
      |> build_text_block()
      |> encode_result(state)
    end

    deflua metric(params), state do
      params
      |> decode_params!(state)
      |> build_metric_block()
      |> encode_result(state)
    end

    deflua table(params), state do
      params
      |> decode_params!(state)
      |> build_table_block()
      |> encode_result(state)
    end

    deflua line(params), state do
      params
      |> decode_params!(state)
      |> build_chart_block("line")
      |> encode_result(state)
    end

    deflua bar(params), state do
      params
      |> decode_params!(state)
      |> build_chart_block("bar")
      |> encode_result(state)
    end

    deflua donut(params), state do
      params
      |> decode_params!(state)
      |> build_donut_block()
      |> encode_result(state)
    end

    deflua pie(params), state do
      params
      |> decode_params!(state)
      |> build_donut_block()
      |> encode_result(state)
    end

    deflua scatter(params), state do
      params
      |> decode_params!(state)
      |> build_chart_block("scatter")
      |> encode_result(state)
    end

    defp decode_params!(params, state) do
      params =
        state
        |> Lua.decode!(params)
        |> JidoCodemode.Agent.Tools.BuildReport.normalize_lua_value()

      if is_map(params) do
        params
      else
        raise "report helpers expect a Lua table as their only argument"
      end
    end

    defp encode_result(value, state) do
      {encoded, state} = Lua.encode!(state, value)
      {[encoded], state}
    end

    defp build_report(params) do
      %{
        "version" => get(params, "version") || 1,
        "title" => get(params, "title"),
        "summary" => get(params, "summary"),
        "blocks" => get(params, "blocks")
      }
      |> compact_map()
    end

    defp build_field_ref(params) do
      %{
        "field" => get(params, "field"),
        "type" => get(params, "type"),
        "format" => get(params, "format")
      }
      |> compact_map()
    end

    defp build_text_block(params) do
      %{
        "type" => "text",
        "id" => get(params, "id"),
        "body" => get(params, "body")
      }
      |> compact_map()
    end

    defp build_metric_block(params) do
      %{
        "type" => "metric",
        "id" => get(params, "id"),
        "label" => get(params, "label"),
        "value" => get(params, "value"),
        "format" => get(params, "format")
      }
      |> compact_map()
    end

    defp build_table_block(params) do
      %{
        "type" => "table",
        "id" => get(params, "id"),
        "title" => get(params, "title"),
        "source" => get(params, "source"),
        "columns" => get(params, "columns"),
        "row_limit" => get(params, "row_limit"),
        "summary" => get(params, "summary")
      }
      |> compact_map()
    end

    defp build_chart_block(params, kind, overrides \\ %{}) do
      %{
        "type" => kind,
        "id" => get(params, "id"),
        "title" => get(params, "title"),
        "source" => get(params, "source"),
        "x" => Map.get(overrides, "x", get(params, "x")),
        "y" => Map.get(overrides, "y", get(params, "y")),
        "color_by" => Map.get(overrides, "color_by", get(params, "color_by")),
        "size_by" => Map.get(overrides, "size_by", get(params, "size_by")),
        "summary" => get(params, "summary")
      }
      |> compact_map()
    end

    defp build_donut_block(params) do
      build_chart_block(params, "donut", %{
        "x" => get(params, "x") || build_donut_label_field(params),
        "y" => get(params, "y") || build_donut_value_field(params)
      })
    end

    defp build_donut_label_field(params) do
      case get(params, "label_field") do
        nil ->
          nil

        field ->
          %{
            "field" => field,
            "type" => get(params, "label_type") || "nominal",
            "format" => get(params, "label_format") || "string"
          }
          |> compact_map()
      end
    end

    defp build_donut_value_field(params) do
      case get(params, "value_field") do
        nil ->
          nil

        field ->
          %{
            "field" => field,
            "type" => get(params, "value_type") || "quantitative",
            "format" => get(params, "value_format")
          }
          |> compact_map()
      end
    end

    defp compact_map(map) do
      Map.reject(map, fn {_key, value} -> is_nil(value) end)
    end

    defp get(map, key) when is_map(map) do
      Map.get(map, key)
    end
  end
end
