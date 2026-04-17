defmodule JidoCodemode.Agent.Report do
  @moduledoc false

  alias JidoCodemode.Agent.ReportStore
  alias VegaLite, as: Vl

  @chart_kinds ["line", "bar", "donut", "scatter"]
  @chart_kind_aliases %{"pie" => "donut"}
  @chart_type_values @chart_kinds ++ Map.keys(@chart_kind_aliases)
  @field_types ["nominal", "ordinal", "quantitative", "temporal"]
  @field_formats ["number", "currency", "percent", "string", "date"]
  @metric_formats ["number", "currency", "percent", "string"]
  @chart_kind_atoms %{"line" => :line, "bar" => :bar, "donut" => :donut, "scatter" => :scatter}
  @field_type_atoms %{
    "nominal" => :nominal,
    "ordinal" => :ordinal,
    "quantitative" => :quantitative,
    "temporal" => :temporal
  }
  @format_atoms %{
    "number" => :number,
    "currency" => :currency,
    "percent" => :percent,
    "string" => :string,
    "date" => :date
  }

  defmodule FieldRef do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [:field, :type, :format]
  end

  defmodule TextBlock do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [:id, :body]
  end

  defmodule MetricBlock do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [:id, :label, :value, :format]
  end

  defmodule TableBlock do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [:id, :title, :columns, :row_limit, :summary, :rows]
  end

  defmodule ChartBlock do
    @moduledoc false
    @derive Jason.Encoder
    defstruct [
      :id,
      :kind,
      :title,
      :x,
      :y,
      :color_by,
      :size_by,
      :summary,
      :row_count,
      :spec_json
    ]
  end

  @derive Jason.Encoder
  defstruct [:version, :title, :summary, :blocks]

  def normalize(report) when is_map(report) do
    with {:ok, version} <- fetch_version(report),
         {:ok, title} <- fetch_string(report, :title),
         {:ok, blocks} <- fetch_list(report, :blocks),
         true <- blocks != [] or {:error, {:invalid_report, :blocks_must_not_be_empty}},
         {:ok, normalized_blocks} <- Enum.reduce_while(blocks, {:ok, []}, &normalize_block/2) do
      {:ok,
       %__MODULE__{
         version: version,
         title: title,
         summary: optional_string(report, :summary),
         blocks: Enum.reverse(normalized_blocks)
       }}
    end
  end

  def normalize(_), do: {:error, {:invalid_report, :expected_map}}

  def latest_for_session(session_id) when is_binary(session_id) do
    case ReportStore.latest_for_session(session_id) do
      {:ok, stored_report} -> {:ok, stored_report.report}
      :error -> :error
    end
  end

  def latest_for_session(_), do: :error

  defp normalize_block(block, {:ok, acc}) do
    case get(block, :type) do
      "text" -> continue_with(normalize_text_block(block), acc)
      "metric" -> continue_with(normalize_metric_block(block), acc)
      "table" -> continue_with(normalize_table_block(block), acc)
      type when type in @chart_type_values -> continue_with(normalize_chart_block(block), acc)
      type -> {:halt, {:error, {:invalid_block_type, type}}}
    end
  end

  defp continue_with({:ok, block}, acc), do: {:cont, {:ok, [block | acc]}}
  defp continue_with({:error, reason}, _acc), do: {:halt, {:error, reason}}

  defp normalize_text_block(block) do
    with {:ok, id} <- fetch_string(block, :id),
         {:ok, body} <- fetch_string(block, :body) do
      {:ok, %TextBlock{id: id, body: body}}
    end
  end

  defp normalize_metric_block(block) do
    with {:ok, id} <- fetch_string(block, :id),
         {:ok, label} <- fetch_string(block, :label),
         {:ok, format} <- fetch_enum(block, :format, @metric_formats) do
      {:ok,
       %MetricBlock{
         id: id,
         label: label,
         value: get(block, :value),
         format: Map.fetch!(@format_atoms, format)
       }}
    end
  end

  defp normalize_table_block(block) do
    with {:ok, id} <- fetch_string(block, :id),
         {:ok, title} <- fetch_string(block, :title),
         {:ok, source} <- required_query_source(block),
         {:ok, columns} <- fetch_list(block, :columns),
         :ok <- validate_requested_columns(columns, source.columns),
         {:ok, row_limit} <- optional_row_limit(block) do
      {:ok,
       %TableBlock{
         id: id,
         title: title,
         columns: columns,
         row_limit: row_limit,
         summary: optional_string(block, :summary),
         rows: materialize_table_rows(source.rows, columns, row_limit)
       }}
    end
  end

  defp normalize_chart_block(block) do
    with {:ok, id} <- fetch_string(block, :id),
         {:ok, kind} <- chart_kind(block),
         {:ok, title} <- fetch_string(block, :title),
         {:ok, source} <- required_query_source(block),
         {:ok, x} <- normalize_field_ref(get(block, :x), :x),
         {:ok, y} <- normalize_field_ref(get(block, :y), :y),
         {:ok, color_by} <- optional_field_ref(block, :color_by),
         {:ok, size_by} <- optional_field_ref(block, :size_by),
         :ok <- validate_chart_fields(source.columns, [x, y, color_by, size_by]),
         {:ok, spec_json} <- build_chart_spec(kind, source.rows, x, y, color_by, size_by) do
      {:ok,
       %ChartBlock{
         id: id,
         kind: Map.fetch!(@chart_kind_atoms, kind),
         title: title,
         x: x,
         y: y,
         color_by: color_by,
         size_by: size_by,
         summary: optional_string(block, :summary),
         row_count: source.row_count,
         spec_json: spec_json
       }}
    end
  end

  defp required_query_source(block) do
    case get(block, :source) do
      nil -> {:error, {:missing_field, :source}}
      source -> normalize_query_source(source)
    end
  end

  defp normalize_query_source(source) when is_map(source) do
    with {:ok, columns} <- fetch_list(source, :columns),
         {:ok, rows} <- fetch_source_rows(source),
         {:ok, row_count} <- fetch_source_row_count(source, rows) do
      {:ok, %{columns: columns, rows: rows, row_count: row_count}}
    end
  end

  defp normalize_query_source(_source), do: {:error, {:invalid_source, :expected_map}}

  defp normalize_field_ref(nil, field_name), do: {:error, {:missing_field, field_name}}

  defp normalize_field_ref(field_ref, _field_name) when is_map(field_ref) do
    with {:ok, field} <- fetch_string(field_ref, :field),
         {:ok, type} <- fetch_enum(field_ref, :type, @field_types) do
      {:ok,
       %FieldRef{
         field: field,
         type: Map.fetch!(@field_type_atoms, type),
         format: normalize_format(field_ref)
       }}
    end
  end

  defp normalize_field_ref(_field_ref, field_name), do: {:error, {:invalid_field_ref, field_name}}

  defp optional_field_ref(block, key) do
    case get(block, key) do
      nil -> {:ok, nil}
      field_ref -> normalize_field_ref(field_ref, key)
    end
  end

  defp normalize_format(field_ref) do
    case optional_string(field_ref, :format) do
      nil -> nil
      format when format in @field_formats -> Map.fetch!(@format_atoms, format)
      _ -> nil
    end
  end

  defp optional_row_limit(block) do
    case get(block, :row_limit) do
      nil -> {:ok, 10}
      value when is_integer(value) and value > 0 -> {:ok, min(value, 20)}
      value -> {:error, {:invalid_row_limit, value}}
    end
  end

  defp validate_requested_columns(requested_columns, available_columns) do
    case requested_columns -- available_columns do
      [] -> :ok
      missing -> {:error, {:unknown_columns, missing}}
    end
  end

  defp validate_chart_fields(available_columns, field_refs) do
    requested_columns =
      field_refs
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.field)

    validate_requested_columns(requested_columns, available_columns)
  end

  defp materialize_table_rows(rows, columns, row_limit) do
    rows
    |> Enum.take(row_limit)
    |> Enum.map(&Map.take(&1, columns))
  end

  defp build_chart_spec(kind, rows, x, y, color_by, size_by) do
    rows
    |> chart_spec(kind, x, y, color_by, size_by)
    |> style_spec()
    |> Vl.to_spec()
    |> Jason.encode!()
    |> then(&{:ok, &1})
  rescue
    error -> {:error, {:chart_render_failed, Exception.message(error)}}
  end

  defp chart_spec(rows, "line", x, y, _color_by, _size_by) do
    Tucan.lineplot(rows, x.field, y.field,
      height: 260,
      width: :container,
      points: true,
      tooltip: :data,
      x: [type: x.type, axis: axis_for(x, nil)],
      y: [type: y.type, axis: axis_for(y, nil)]
    )
  end

  defp chart_spec(rows, "bar", x, y, _color_by, _size_by) do
    options = [
      height: 260,
      width: :container,
      tooltip: :data,
      x: [type: x.type, axis: axis_for(x, nil)],
      y: [type: y.type, axis: axis_for(y, nil)]
    ]

    options =
      if x.type == :quantitative and y.type in [:nominal, :ordinal] do
        Keyword.put(options, :orient, :horizontal)
      else
        options
      end

    Tucan.bar(rows, x.field, y.field, options)
  end

  defp chart_spec(rows, "donut", x, y, _color_by, _size_by) do
    Tucan.donut(rows, y.field, x.field,
      height: 260,
      width: :container,
      tooltip: :data
    )
  end

  defp chart_spec(rows, "scatter", x, y, color_by, size_by) do
    rows
    |> Tucan.scatter(x.field, y.field,
      height: 260,
      width: :container,
      tooltip: :data,
      color_by: color_by && color_by.field,
      x: [type: x.type, axis: axis_for(x, x.field)],
      y: [type: y.type, axis: axis_for(y, y.field)]
    )
    |> maybe_size_by(size_by)
  end

  defp maybe_size_by(vl, nil), do: vl
  defp maybe_size_by(vl, %FieldRef{field: field}), do: Tucan.size_by(vl, field)

  defp style_spec(vl) do
    vl
    |> Tucan.set_theme(:latimes)
    |> Vl.config(
      background: "transparent",
      view: [stroke: nil],
      legend: [title: nil, orient: :bottom, label_font_size: 11],
      axis: [grid_color: "#E5E7EB", domain: false, tick_color: "#CBD5E1", label_color: "#475569"]
    )
  end

  defp axis_for(field_ref, title) do
    base = [title: title]

    case field_ref.format do
      :currency -> Keyword.put(base, :format, "$,.0f")
      :percent -> Keyword.put(base, :format, ".0%")
      :date -> Keyword.put(base, :format, "%b %Y")
      _ -> base
    end
  end

  defp fetch_string(map, key) do
    case get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:missing_or_invalid_field, key}}
    end
  end

  defp fetch_list(map, key) do
    case get(map, key) do
      value when is_list(value) -> {:ok, value}
      value when is_binary(value) -> decode_json_list(value, key)
      _ -> {:error, {:missing_or_invalid_field, key}}
    end
  end

  defp fetch_enum(map, key, allowed_values) do
    with {:ok, value} <- fetch_string(map, key),
         true <- value in allowed_values or {:error, {:invalid_enum_value, key, value}} do
      {:ok, value}
    end
  end

  defp fetch_source_rows(source) do
    with {:ok, rows} <- fetch_list(source, :rows) do
      Enum.reduce_while(rows, {:ok, []}, fn
        row, {:ok, acc} when is_map(row) ->
          normalized_row =
            Enum.into(row, %{}, fn {key, value} ->
              {normalize_row_key(key), value}
            end)

          {:cont, {:ok, [normalized_row | acc]}}

        row, _acc ->
          {:halt, {:error, {:invalid_source_row, row}}}
      end)
      |> case do
        {:ok, normalized_rows} -> {:ok, Enum.reverse(normalized_rows)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp fetch_source_row_count(source, rows) do
    case get(source, :row_count) do
      nil -> {:ok, length(rows)}
      value when is_integer(value) and value >= 0 -> {:ok, value}
      value -> {:error, {:missing_or_invalid_field, {:row_count, value}}}
    end
  end

  defp optional_string(map, key) do
    case get(map, key) do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp normalize_row_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_row_key(key) when is_binary(key), do: key
  defp normalize_row_key(key), do: to_string(key)

  defp get(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp fetch_version(report) do
    case get(report, :version) do
      1 -> {:ok, "1"}
      "1" -> {:ok, "1"}
      value -> {:error, {:missing_or_invalid_field, {:version, value}}}
    end
  end

  defp chart_kind(block) do
    case canonical_chart_kind(get(block, :type)) do
      kind when kind in @chart_kinds -> {:ok, kind}
      type -> {:error, {:invalid_block_type, type}}
    end
  end

  defp canonical_chart_kind(nil), do: nil
  defp canonical_chart_kind(kind), do: Map.get(@chart_kind_aliases, kind, kind)

  defp decode_json_list(value, key) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, {:missing_or_invalid_field, key}}
      {:error, _reason} -> {:error, {:invalid_json_list, key}}
    end
  end
end
