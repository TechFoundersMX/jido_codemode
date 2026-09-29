defmodule JidoCodemode.DemoAccess.Tokens do
  @moduledoc """
  Server-side map from an opaque reference to an invitation token.

  The LiveView session is signed, not encrypted, and is embedded in the page, so
  the invitation token must never go into it. The plug stores the token here and
  puts only the reference in the session. References are an HMAC of the token
  under a key that lives only in this node's memory, so the same invitation maps
  to the same entry, and entries unused for `@ttl_seconds` are dropped.
  """

  use GenServer

  @table __MODULE__
  @key {__MODULE__, :hmac_key}
  @ttl_seconds 8 * 24 * 60 * 60
  @prune_every :timer.hours(1)

  def start_link(_opts \\ []), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "Stores `token` and returns its reference."
  @spec put(String.t()) :: String.t()
  def put(token) when is_binary(token) do
    ref =
      :crypto.mac(:hmac, :sha256, :persistent_term.get(@key), token)
      |> Base.url_encode64(padding: false)

    true = :ets.insert(@table, {ref, token, System.system_time(:second)})
    ref
  end

  @spec fetch(term()) :: {:ok, String.t()} | :error
  def fetch(ref) when is_binary(ref) do
    case :ets.lookup(@table, ref) do
      [{^ref, token, _seen_at}] -> {:ok, token}
      [] -> :error
    end
  end

  def fetch(_ref), do: :error

  @doc "Drops entries not seen since `now - ttl`."
  @spec prune(integer()) :: non_neg_integer()
  def prune(now \\ System.system_time(:second)) do
    cutoff = now - @ttl_seconds
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
  end

  @impl true
  def init(:ok) do
    :persistent_term.put(@key, :crypto.strong_rand_bytes(32))

    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
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
