defmodule JidoCodemode.Locale.Dataset do
  @moduledoc """
  One Northwind database per locale.

  English queries the original file. Spanish (Mexico) queries a copy built at
  startup: the three money columns are converted to MXN at the configured
  USD to MXN rate, and category and country names are translated. The copy is
  read-only, like the original.

  If the rate is missing or invalid, the Spanish copy keeps USD amounts. If the
  copy cannot be built, Spanish falls back to the original database (English
  labels, USD).
  """

  require Logger

  alias Exqlite.Sqlite3
  alias JidoCodemode.Locale.Glossary

  @key {__MODULE__, :es_MX}

  @money_columns [{"OrderDetail", "UnitPrice"}, {"Product", "UnitPrice"}, {"Order", "Freight"}]

  @country_columns [
    {"Customer", "Country"},
    {"Supplier", "Country"},
    {"Employee", "Country"},
    {"Order", "ShipCountry"}
  ]

  @spec source_path() :: Path.t()
  def source_path do
    :jido_codemode
    |> Application.get_env(JidoCodemode.Agent.Schema, [])
    |> Keyword.get(:database_path, Path.expand("../../../northwind.sqlite", __DIR__))
  end

  @spec parse_rate(term()) :: {:ok, float()} | :error
  def parse_rate(value) when is_float(value) and value > 0, do: {:ok, value}
  def parse_rate(value) when is_integer(value) and value > 0, do: {:ok, value * 1.0}

  def parse_rate(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {rate, ""} when rate > 0 -> {:ok, rate}
      _other -> :error
    end
  end

  def parse_rate(_value), do: :error

  @spec fx() :: {:ok, %{rate: float(), date: String.t(), source: String.t()}} | :error
  def fx do
    config = Application.get_env(:jido_codemode, __MODULE__, [])

    with {:ok, rate} <- parse_rate(Keyword.get(config, :fx_usd_mxn)) do
      {:ok,
       %{
         rate: rate,
         date: Keyword.get(config, :fx_date) || "",
         source: Keyword.get(config, :fx_source) || ""
       }}
    end
  end

  @doc "Builds the Spanish copy of `source` at `target`. Converts money only when `rate` is a number."
  @spec build(Path.t(), Path.t(), float() | nil) :: :ok | {:error, term()}
  def build(source, target, rate) do
    _ = File.rm(target)

    with :ok <- File.cp(source, target),
         {:ok, conn} <- Sqlite3.open(target) do
      result =
        try do
          run_statements(conn, statements(rate))
        after
          Sqlite3.close(conn)
        end

      with :ok <- result, do: File.chmod(target, 0o444)
    end
  end

  @doc "Builds the Spanish copy from configuration and caches the result."
  @spec setup() :: :ok
  def setup do
    target =
      Path.join(
        System.tmp_dir!(),
        "agentic-bi-es_MX-#{System.unique_integer([:positive])}.sqlite"
      )

    {rate, currency} =
      case fx() do
        {:ok, %{rate: rate}} ->
          {rate, :mxn}

        :error ->
          Logger.warning("FX_USD_MXN is missing or invalid; the Spanish demo shows USD.")
          {nil, :usd}
      end

    state =
      case build(source_path(), target, rate) do
        :ok ->
          %{path: target, currency: currency, labels: :es}

        {:error, reason} ->
          Logger.error("Could not build the Spanish database copy: #{inspect(reason)}")
          %{path: source_path(), currency: :usd, labels: :en}
      end

    :persistent_term.put(@key, state)
    :ok
  end

  @doc "Forgets the cached Spanish copy so the next call rebuilds it. For tests."
  @spec reset() :: :ok
  def reset do
    _ = :persistent_term.erase(@key)
    :ok
  end

  @spec path(String.t()) :: Path.t()
  def path("es_MX"), do: state().path
  def path(_locale), do: source_path()

  @spec currency(String.t()) :: :usd | :mxn
  def currency("es_MX"), do: state().currency
  def currency(_locale), do: :usd

  @spec labels(String.t()) :: :en | :es
  def labels("es_MX"), do: state().labels
  def labels(_locale), do: :en

  @spec rate(String.t()) :: float()
  def rate(locale) do
    with :mxn <- currency(locale),
         {:ok, %{rate: rate}} <- fx() do
      rate
    else
      _other -> 1.0
    end
  end

  defp state do
    case :persistent_term.get(@key, nil) do
      nil ->
        :ok = setup()
        :persistent_term.get(@key)

      state ->
        state
    end
  end

  defp statements(rate) do
    money =
      if rate do
        Enum.map(@money_columns, fn {table, column} ->
          ~s(UPDATE "#{table}" SET "#{column}" = "#{column}" * #{:erlang.float_to_binary(rate * 1.0, [:short])})
        end)
      else
        []
      end

    labels = [
      rename("Category", "CategoryName", Glossary.categories())
      | Enum.map(@country_columns, fn {table, column} ->
          rename(table, column, Glossary.countries())
        end)
    ]

    ["BEGIN"] ++ money ++ labels ++ ["COMMIT"]
  end

  defp rename(table, column, translations) do
    cases =
      Enum.map_join(translations, " ", fn {english, spanish} ->
        "WHEN #{literal(english)} THEN #{literal(spanish)}"
      end)

    ~s(UPDATE "#{table}" SET "#{column}" = CASE "#{column}" #{cases} ELSE "#{column}" END)
  end

  defp literal(value), do: "'" <> String.replace(value, "'", "''") <> "'"

  defp run_statements(conn, statements) do
    Enum.reduce_while(statements, :ok, fn sql, :ok ->
      case Sqlite3.execute(conn, sql) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {sql, reason}}}
      end
    end)
  end
end
