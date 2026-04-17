defmodule JidoCodemode.Agent.ReportStore do
  @moduledoc false

  use GenServer

  @table __MODULE__

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @spec put(map(), map()) :: :ok
  def put(report, metadata \\ %{}) when is_map(report) and is_map(metadata) do
    entry_key = System.unique_integer([:positive])

    stored_report = %{
      report: report,
      metadata: metadata,
      inserted_at: DateTime.utc_now()
    }

    true = :ets.insert(@table, {entry_key, stored_report})

    :ok
  end

  @spec latest_for_session(String.t()) :: {:ok, map()} | :error
  def latest_for_session(session_id) when is_binary(session_id) do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {_id, stored_report} -> stored_report end)
    |> Enum.filter(fn stored_report ->
      Map.get(stored_report.metadata, :session_id) == session_id
    end)
    |> Enum.max_by(&DateTime.to_unix(&1.inserted_at, :microsecond), fn -> nil end)
    |> case do
      nil -> :error
      stored_report -> {:ok, stored_report}
    end
  end

  def latest_for_session(_session_id), do: :error

  @impl true
  def init(:ok) do
    case :ets.whereis(@table) do
      :undefined ->
        _ =
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])

        {:ok, %{}}

      _table ->
        {:ok, %{}}
    end
  end
end
