defmodule JidoCodemode.Agent.ReportStore do
  @moduledoc """
  In-memory store of generated reports, keyed by the conversation's session id.

  Nothing is written to disk. Reports older than `@ttl_seconds` (24 hours) are
  deleted every `@prune_every`, and a restart clears everything.
  """

  use GenServer

  @table __MODULE__
  @ttl_seconds 24 * 60 * 60
  @prune_every :timer.minutes(15)

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

  @doc "Deletes reports stored more than 24 hours before `now`; returns how many."
  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@ttl_seconds, :second)

    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {_key, stored} -> DateTime.before?(stored.inserted_at, cutoff) end)
    |> Enum.reduce(0, fn {key, _stored}, deleted ->
      :ets.delete(@table, key)
      deleted + 1
    end)
  end

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

      _table ->
        :ok
    end

    schedule_prune()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune, state) do
    prune()
    schedule_prune()
    {:noreply, state}
  end

  defp schedule_prune, do: Process.send_after(self(), :prune, @prune_every)
end
