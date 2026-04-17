defmodule JidoCodemode.Agent.QueryRunner do
  @moduledoc false

  alias Exqlite.Sqlite3
  alias JidoCodemode.Agent.Schema

  @supported_purposes ["analysis", "chart", "table"]
  @disallowed_keyword_regex ~r/\b(insert|update|delete|drop|alter|attach|detach|pragma|create|replace|vacuum)\b/i
  @comment_regex ~r/(--|\/\*)/
  @default_limits %{
    preview_rows: 20,
    preview_columns: 8,
    preview_cell_chars: 120,
    max_columns: 20,
    max_cell_chars: 1_000,
    timeout_ms: 2_000
  }
  @purpose_limits %{
    "analysis" => %{hard_rows: 200},
    "chart" => %{hard_rows: 500},
    "table" => %{hard_rows: 100}
  }

  @type result :: %{
          columns: [String.t()],
          rows: [map()],
          preview_columns: [String.t()],
          preview_rows: [list()],
          row_count: non_neg_integer(),
          truncated: boolean(),
          preview_limited: boolean(),
          column_count: non_neg_integer(),
          omitted_columns_count: non_neg_integer(),
          elapsed_ms: non_neg_integer()
        }

  @spec run(String.t(), String.t() | atom(), keyword()) :: {:ok, result()} | {:error, term()}
  def run(sql, purpose, opts \\ [])

  def run(sql, purpose, opts) when is_binary(sql) do
    with {:ok, purpose} <- normalize_purpose(purpose),
         {:ok, normalized_sql} <- validate_sql(sql) do
      limits = limits_for(purpose, opts)

      normalized_sql
      |> start_query_task(limits)
      |> await_result(limits.timeout_ms)
    end
  end

  def run(_sql, purpose, _opts), do: {:error, {:invalid_purpose, purpose}}

  @spec to_preview(result()) :: map()
  def to_preview(result) when is_map(result) do
    %{
      columns: result.preview_columns,
      preview_rows: result.preview_rows,
      row_count: result.row_count,
      truncated: result.truncated,
      preview_limited: result.preview_limited,
      column_count: result.column_count,
      omitted_columns_count: result.omitted_columns_count,
      elapsed_ms: result.elapsed_ms
    }
  end

  @spec to_source(result()) :: map()
  def to_source(result) when is_map(result) do
    %{
      "columns" => result.columns,
      "rows" => result.rows,
      "row_count" => result.row_count,
      "truncated" => result.truncated
    }
  end

  defp await_result(task, timeout_ms) do
    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end

  defp start_query_task(sql, limits) do
    if Process.whereis(JidoCodemode.Agent.TaskSupervisor) do
      Task.Supervisor.async_nolink(JidoCodemode.Agent.TaskSupervisor, fn ->
        execute_query(sql, limits)
      end)
    else
      Task.async(fn -> execute_query(sql, limits) end)
    end
  end

  defp execute_query(sql, limits) do
    started_at = System.monotonic_time(:millisecond)

    with_connection(fn conn ->
      case Sqlite3.prepare(conn, sql) do
        {:ok, statement} ->
          try do
            with {:ok, columns} <- Sqlite3.columns(conn, statement),
                 :ok <- validate_column_count(columns, limits.max_columns),
                 {:ok, rows, truncated} <- fetch_rows(conn, statement, limits.hard_rows) do
              elapsed_ms = System.monotonic_time(:millisecond) - started_at
              build_result(columns, rows, truncated, elapsed_ms, limits)
            else
              {:error, reason} -> {:error, normalize_query_error(reason)}
            end
          after
            Sqlite3.release(conn, statement)
          end

        {:error, reason} ->
          {:error, {:query_failed, reason}}
      end
    end)
  end

  defp build_result(columns, rows, truncated, elapsed_ms, limits) do
    normalized_rows = Enum.map(rows, &normalize_row(columns, &1, limits.max_cell_chars))

    preview_columns = Enum.take(columns, limits.preview_columns)

    preview_rows =
      normalized_rows
      |> Enum.take(limits.preview_rows)
      |> Enum.map(&preview_row(&1, preview_columns, limits.preview_cell_chars))

    omitted_columns_count = max(length(columns) - length(preview_columns), 0)

    {:ok,
     %{
       columns: columns,
       rows: normalized_rows,
       preview_columns: preview_columns,
       preview_rows: preview_rows,
       row_count: length(normalized_rows),
       truncated: truncated,
       preview_limited:
         length(normalized_rows) > length(preview_rows) or omitted_columns_count > 0,
       column_count: length(columns),
       omitted_columns_count: omitted_columns_count,
       elapsed_ms: elapsed_ms
     }}
  end

  defp fetch_rows(conn, statement, hard_rows) do
    do_fetch_rows(conn, statement, hard_rows, [])
  end

  defp do_fetch_rows(conn, statement, hard_rows, acc) do
    case Sqlite3.step(conn, statement) do
      {:row, row} when length(acc) < hard_rows ->
        do_fetch_rows(conn, statement, hard_rows, [row | acc])

      {:row, _row} ->
        {:ok, Enum.reverse(acc), true}

      :done ->
        {:ok, Enum.reverse(acc), false}

      :busy ->
        {:error, :busy}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_column_count(columns, max_columns) when length(columns) <= max_columns, do: :ok

  defp validate_column_count(columns, max_columns),
    do: {:error, {:too_many_columns, length(columns), max_columns}}

  defp normalize_purpose(purpose) when is_atom(purpose),
    do: normalize_purpose(Atom.to_string(purpose))

  defp normalize_purpose(purpose) when is_binary(purpose) do
    normalized = purpose |> String.trim() |> String.downcase()

    if normalized in @supported_purposes do
      {:ok, normalized}
    else
      {:error, {:invalid_purpose, purpose}}
    end
  end

  defp validate_sql(sql) do
    normalized_sql =
      sql
      |> String.trim()
      |> String.replace(~r/;\s*$/, "")

    cond do
      normalized_sql == "" ->
        {:error, {:invalid_sql, :empty}}

      Regex.match?(@comment_regex, normalized_sql) ->
        {:error, {:invalid_sql, :comments_not_allowed}}

      String.contains?(normalized_sql, ";") ->
        {:error, {:invalid_sql, :multiple_statements_not_allowed}}

      not Regex.match?(~r/^\s*(select|with)\b/i, normalized_sql) ->
        {:error, {:invalid_sql, :only_select_and_with_are_allowed}}

      Regex.match?(@disallowed_keyword_regex, normalized_sql) ->
        {:error, {:invalid_sql, :disallowed_keyword}}

      true ->
        {:ok, normalized_sql}
    end
  end

  defp limits_for(purpose, opts) do
    @default_limits
    |> Map.merge(Map.fetch!(@purpose_limits, purpose))
    |> Map.merge(Enum.into(opts, %{}))
  end

  defp normalize_row(columns, row, max_cell_chars) do
    columns
    |> Enum.zip(row)
    |> Enum.map(fn {column, value} -> {column, normalize_cell(value, max_cell_chars)} end)
    |> Map.new()
  end

  defp preview_row(row, columns, max_cell_chars) do
    Enum.map(columns, fn column -> shorten_value(Map.get(row, column), max_cell_chars) end)
  end

  defp normalize_cell(value, max_cell_chars) do
    value
    |> normalize_scalar()
    |> shorten_value(max_cell_chars)
  end

  defp normalize_scalar(value) when is_binary(value) do
    if String.valid?(value) do
      value
    else
      "[binary #{byte_size(value)} bytes]"
    end
  end

  defp normalize_scalar(value) when is_integer(value) or is_float(value) or is_nil(value),
    do: value

  defp normalize_scalar(value) when is_boolean(value), do: value
  defp normalize_scalar(value), do: inspect(value, pretty: false, limit: 10)

  defp shorten_value(value, max_chars) when is_binary(value) do
    if String.length(value) > max_chars do
      String.slice(value, 0, max_chars) <> "..."
    else
      value
    end
  end

  defp shorten_value(value, _max_chars), do: value

  defp with_connection(fun) do
    case Sqlite3.open(database_path(), mode: :readonly) do
      {:ok, conn} ->
        try do
          fun.(conn)
        after
          Sqlite3.close(conn)
        end

      {:error, reason} ->
        {:error, {:database_open_failed, reason}}
    end
  end

  defp database_path do
    :jido_codemode
    |> Application.get_env(Schema, [])
    |> Keyword.get(:database_path, Path.expand("../../../northwind.sqlite", __DIR__))
  end

  defp normalize_query_error({:too_many_columns, _count, _max} = reason), do: reason
  defp normalize_query_error(reason), do: {:query_failed, reason}
end
