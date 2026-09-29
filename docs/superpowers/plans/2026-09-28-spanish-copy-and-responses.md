# Spanish Copy and Responses Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Agentic BI demo work fully in Spanish (Mexico) with MXN figures, while keeping English with USD.

**Architecture:** A request-level locale (`?lang`, cookie, `Accept-Language`) drives `gettext` for interface copy, a language block in the agent's instructions, and the choice of database. The Spanish database is a read-only copy of Northwind built at startup, with the three money columns converted to MXN and category and country names translated, so every downstream result is already Spanish and MXN.

**Tech Stack:** Elixir 1.20, Phoenix LiveView 1.1, Gettext (Expo), Exqlite 0.36, Jido.AI 2.3, Vega-Lite via vega-embed.

**Spec:** `docs/superpowers/specs/2026-09-28-spanish-copy-and-responses-design.md`

## Global Constraints

- Supported locales: `"en"` and `"es_MX"`. Default: `"en"`. Any `es*` value resolves to `"es_MX"`.
- Resolution order: `?lang=` parameter, then cookie `agentic_bi_locale`, then `Accept-Language`, then `"en"`.
- Session key: `"locale"`. `<html lang>`: `"es-MX"` for `es_MX`, `"en"` otherwise.
- Exchange-rate environment variables: `FX_USD_MXN`, `FX_USD_MXN_DATE`, `FX_USD_MXN_SOURCE`. Initial values: `17.8413`, `2026-09-28`, `Banxico FIX (SuperDev ERP)`.
- Money columns (the only ones converted): `OrderDetail.UnitPrice`, `Product.UnitPrice`, `Order.Freight`. `OrderDetail.Discount` never changes.
- Country columns translated: `Customer.Country`, `Supplier.Country`, `Employee.Country`, `Order.ShipCountry`. Category column: `Category.CategoryName`.
- Money display: Spanish `$4,779,116.56 MXN`; English `$267,868.18`. Chart axes use `$` with no suffix in both languages.
- Copy rules: Mexican Spanish, *tú*, professional; full sentences end with a period; no emojis anywhere.
- Test command. Every `mix` command in this plan runs with this prefix (build artifacts live off Google Drive and no provider keys may be set):

  ```bash
  export MIX_DEPS_PATH=$HOME/Library/Caches/jido_codemode/deps MIX_BUILD_ROOT=$HOME/Library/Caches/jido_codemode/_build
  unset OPENAI_API_KEY OPENCODE_API_KEY CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET
  ```

## File Structure

| File | Status | Responsibility |
| --- | --- | --- |
| `lib/jido_codemode/locale.ex` | Create | Supported locales, normalization, `Accept-Language` parsing, resolution, `html_lang/1`. |
| `lib/jido_codemode/locale/glossary.ex` | Create | English → Spanish maps for categories and countries; prompt summary. |
| `lib/jido_codemode/locale/format.ex` | Create | Money, percent, number, and date formatting per locale and currency. |
| `lib/jido_codemode/locale/dataset.ex` | Create | FX configuration, Spanish database copy (build, path, currency, labels, rate). |
| `lib/jido_codemode/application.ex` | Modify | Build the Spanish database copy at startup. |
| `config/runtime.exs`, `config/dev.exs`, `config/test.exs` | Modify | FX configuration. |
| `lib/jido_codemode/agent/query_runner.ex` | Modify | Open the database for the requested locale. |
| `lib/jido_codemode/agent/tools/run_sqlite_query.ex` | Modify | Pass the locale from the tool context. |
| `lib/jido_codemode/agent/tools/build_report.ex` | Modify | Pass the locale from the tool context in `db.query`. |
| `lib/jido_codemode/sidebar_agent.ex` | Modify | `system_prompt_with_schema/1` with a language block. |
| `lib/jido_codemode_web/plugs/locale.ex` | Create | Resolve the locale per request; session, cookie, Gettext. |
| `lib/jido_codemode_web/locale_hook.ex` | Create | LiveView `on_mount`: locale from session into assigns and Gettext. |
| `lib/jido_codemode_web/router.ex` | Modify | Add the plug and the `live_session`. |
| `lib/jido_codemode_web/components/layouts/root.html.heex` | Modify | `<html lang>` and the title suffix. |
| `lib/jido_codemode_web/components/layouts.ex` | Modify | Translate theme-toggle labels and the header. |
| `lib/jido_codemode_web/live/sandbox_live.ex` | Modify | Copy through gettext, sample charts, formatting, switch, footnote, agent wiring. |
| `assets/js/app.js` | Modify | Apply `locale-changed` (cookie and `<html lang>`). |
| `priv/gettext/default.pot`, `priv/gettext/es_MX/LC_MESSAGES/default.po` | Create | Extracted copy and Spanish translations. |
| `test/jido_codemode/locale/*_test.exs`, `test/jido_codemode_web/*` | Create/Modify | Tests per task. |
| `README.md`, `.env.example` | Modify | Document the FX variables and the Spanish demo. |

---

### Task 1: Locale resolution and glossary

**Files:**
- Create: `lib/jido_codemode/locale.ex`
- Create: `lib/jido_codemode/locale/glossary.ex`
- Test: `test/jido_codemode/locale/locale_test.exs`
- Test: `test/jido_codemode/locale/glossary_test.exs`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `JidoCodemode.Locale.supported() :: [String.t()]`, `default() :: String.t()`
  - `JidoCodemode.Locale.normalize(term) :: "en" | "es_MX" | nil`
  - `JidoCodemode.Locale.from_accept_language(String.t() | nil) :: "en" | "es_MX" | nil`
  - `JidoCodemode.Locale.resolve(param, cookie, accept_language) :: "en" | "es_MX"`
  - `JidoCodemode.Locale.html_lang(locale) :: "es-MX" | "en"`
  - `JidoCodemode.Locale.cookie_name() :: "agentic_bi_locale"`
  - `JidoCodemode.Locale.Glossary.categories() :: %{String.t() => String.t()}`, `countries/0` (same type), `prompt_summary() :: String.t()`

- [ ] **Step 1: Write the failing tests**

`test/jido_codemode/locale/locale_test.exs`:

```elixir
defmodule JidoCodemode.LocaleTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Locale

  describe "normalize/1" do
    test "maps Spanish and English variants to supported locales" do
      assert Locale.normalize("es") == "es_MX"
      assert Locale.normalize("es-MX") == "es_MX"
      assert Locale.normalize("ES_es") == "es_MX"
      assert Locale.normalize("en") == "en"
      assert Locale.normalize("en-GB") == "en"
    end

    test "returns nil for unsupported or missing values" do
      assert Locale.normalize("fr") == nil
      assert Locale.normalize("") == nil
      assert Locale.normalize(nil) == nil
    end
  end

  describe "from_accept_language/1" do
    test "takes the highest-weighted supported language" do
      assert Locale.from_accept_language("es-MX,es;q=0.9,en;q=0.8") == "es_MX"
      assert Locale.from_accept_language("fr-FR,fr;q=0.9,es;q=0.8,en;q=0.7") == "es_MX"
      assert Locale.from_accept_language("en-US,en;q=0.9,es;q=0.8") == "en"
      assert Locale.from_accept_language("es;q=0.4,en;q=0.9") == "en"
    end

    test "returns nil when nothing is supported" do
      assert Locale.from_accept_language("fr-FR,de;q=0.8") == nil
      assert Locale.from_accept_language("") == nil
      assert Locale.from_accept_language(nil) == nil
    end
  end

  describe "resolve/3" do
    test "prefers the parameter, then the cookie, then the header" do
      assert Locale.resolve("en", "es_MX", "es-MX") == "en"
      assert Locale.resolve(nil, "es_MX", "en-US") == "es_MX"
      assert Locale.resolve("xx", nil, "es-ES") == "es_MX"
      assert Locale.resolve(nil, nil, nil) == "en"
    end
  end

  test "html_lang/1" do
    assert Locale.html_lang("es_MX") == "es-MX"
    assert Locale.html_lang("en") == "en"
  end
end
```

`test/jido_codemode/locale/glossary_test.exs`:

```elixir
defmodule JidoCodemode.Locale.GlossaryTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Locale.Glossary

  test "covers the 8 Northwind categories with the approved translations" do
    assert Glossary.categories() == %{
             "Beverages" => "Bebidas",
             "Condiments" => "Condimentos",
             "Confections" => "Dulces y postres",
             "Dairy Products" => "Lácteos",
             "Grains/Cereals" => "Granos y cereales",
             "Meat/Poultry" => "Carnes y aves",
             "Produce" => "Frutas y verduras",
             "Seafood" => "Pescados y mariscos"
           }
  end

  test "covers all 25 countries in the data" do
    countries = Glossary.countries()
    assert map_size(countries) == 25
    assert countries["Germany"] == "Alemania"
    assert countries["UK"] == "Reino Unido"
    assert countries["USA"] == "Estados Unidos"
    assert countries["Mexico"] == "México"
    assert countries["Netherlands"] == "Países Bajos"
  end

  test "prompt_summary/0 pairs Spanish names with the English originals" do
    summary = Glossary.prompt_summary()
    assert summary =~ "Bebidas (Beverages)"
    assert summary =~ "Alemania (Germany)"
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/jido_codemode/locale/locale_test.exs test/jido_codemode/locale/glossary_test.exs`
Expected: FAIL with `module JidoCodemode.Locale is not available` (and the same for `Glossary`).

- [ ] **Step 3: Implement**

`lib/jido_codemode/locale.ex`:

```elixir
defmodule JidoCodemode.Locale do
  @moduledoc """
  Supported page languages and how the language of a request is chosen.

  Order: an explicit `?lang=` value, then the saved cookie, then the browser's
  `Accept-Language` header, then English.
  """

  @supported ["en", "es_MX"]
  @default "en"
  @cookie "agentic_bi_locale"

  @spec supported() :: [String.t()]
  def supported, do: @supported

  @spec default() :: String.t()
  def default, do: @default

  @spec cookie_name() :: String.t()
  def cookie_name, do: @cookie

  @doc "Maps a user-supplied value to a supported locale, or nil."
  @spec normalize(term()) :: String.t() | nil
  def normalize(value) when is_binary(value) do
    case value |> String.trim() |> String.downcase() |> String.replace("-", "_") do
      "es" <> _ -> "es_MX"
      "en" <> _ -> "en"
      _ -> nil
    end
  end

  def normalize(_value), do: nil

  @doc "The highest-weighted supported language in an Accept-Language header, or nil."
  @spec from_accept_language(String.t() | nil) :: String.t() | nil
  def from_accept_language(header) when is_binary(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {_tag, weight} -> -weight end)
    |> Enum.find_value(fn {tag, _weight} -> normalize(tag) end)
  end

  def from_accept_language(_header), do: nil

  @spec resolve(term(), term(), String.t() | nil) :: String.t()
  def resolve(param, cookie, accept_language) do
    normalize(param) || normalize(cookie) || from_accept_language(accept_language) || @default
  end

  @spec html_lang(String.t()) :: String.t()
  def html_lang("es_MX"), do: "es-MX"
  def html_lang(_locale), do: "en"

  defp parse_entry(entry) do
    case entry |> String.trim() |> String.split(";") do
      [""] -> nil
      [tag | params] -> {String.trim(tag), weight(params)}
    end
  end

  defp weight(params) do
    Enum.find_value(params, 1.0, fn param ->
      case param |> String.trim() |> String.split("=") do
        ["q", value] ->
          case Float.parse(value) do
            {weight, _rest} -> weight
            :error -> 0.0
          end

        _other ->
          nil
      end
    end)
  end
end
```

`lib/jido_codemode/locale/glossary.ex`:

```elixir
defmodule JidoCodemode.Locale.Glossary do
  @moduledoc """
  Reviewed English to Spanish (Mexico) names for Northwind's categories and
  countries. Product, customer, and shipper names are proper nouns and are not
  translated.
  """

  @categories %{
    "Beverages" => "Bebidas",
    "Condiments" => "Condimentos",
    "Confections" => "Dulces y postres",
    "Dairy Products" => "Lácteos",
    "Grains/Cereals" => "Granos y cereales",
    "Meat/Poultry" => "Carnes y aves",
    "Produce" => "Frutas y verduras",
    "Seafood" => "Pescados y mariscos"
  }

  @countries %{
    "Argentina" => "Argentina",
    "Australia" => "Australia",
    "Austria" => "Austria",
    "Belgium" => "Bélgica",
    "Brazil" => "Brasil",
    "Canada" => "Canadá",
    "Denmark" => "Dinamarca",
    "Finland" => "Finlandia",
    "France" => "Francia",
    "Germany" => "Alemania",
    "Ireland" => "Irlanda",
    "Italy" => "Italia",
    "Japan" => "Japón",
    "Mexico" => "México",
    "Netherlands" => "Países Bajos",
    "Norway" => "Noruega",
    "Poland" => "Polonia",
    "Portugal" => "Portugal",
    "Singapore" => "Singapur",
    "Spain" => "España",
    "Sweden" => "Suecia",
    "Switzerland" => "Suiza",
    "UK" => "Reino Unido",
    "USA" => "Estados Unidos",
    "Venezuela" => "Venezuela"
  }

  @spec categories() :: %{String.t() => String.t()}
  def categories, do: @categories

  @spec countries() :: %{String.t() => String.t()}
  def countries, do: @countries

  @doc "One line for the agent instructions: Spanish names with the English original."
  @spec prompt_summary() :: String.t()
  def prompt_summary do
    "categories: " <> pairs(@categories) <> "; countries: " <> pairs(@countries)
  end

  defp pairs(map) do
    map
    |> Enum.sort_by(fn {english, _spanish} -> english end)
    |> Enum.map_join(", ", fn {english, spanish} -> "#{spanish} (#{english})" end)
  end
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/jido_codemode/locale/locale_test.exs test/jido_codemode/locale/glossary_test.exs`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add lib/jido_codemode/locale.ex lib/jido_codemode/locale/glossary.ex test/jido_codemode/locale
git commit -m "Add locale resolution and the Spanish glossary"
```

---

### Task 2: Locale-aware formatting

**Files:**
- Create: `lib/jido_codemode/locale/format.ex`
- Test: `test/jido_codemode/locale/format_test.exs`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `JidoCodemode.Locale.Format.money(number, :usd | :mxn) :: String.t()`
  - `JidoCodemode.Locale.Format.percent(number) :: String.t()` (input is a fraction)
  - `JidoCodemode.Locale.Format.number(number) :: String.t()`
  - `JidoCodemode.Locale.Format.date(Date.t(), locale, :long | :short) :: String.t()`

- [ ] **Step 1: Write the failing test**

`test/jido_codemode/locale/format_test.exs`:

```elixir
defmodule JidoCodemode.Locale.FormatTest do
  use ExUnit.Case, async: true

  alias JidoCodemode.Locale.Format

  test "money/2 groups digits and labels the currency" do
    assert Format.money(267_868.18, :usd) == "$267,868.18"
    assert Format.money(4_779_116.56, :mxn) == "$4,779,116.56 MXN"
    assert Format.money(1200, :usd) == "$1,200.00"
    assert Format.money(-1234.5, :mxn) == "-$1,234.50 MXN"
  end

  test "percent/1 takes a fraction" do
    assert Format.percent(0.1234) == "12.3%"
    assert Format.percent(1) == "100.0%"
  end

  test "number/1 groups integers and rounds floats to 2 decimals" do
    assert Format.number(1_234_567) == "1,234,567"
    assert Format.number(4_779_116.559999) == "4,779,116.56"
    assert Format.number(12) == "12"
  end

  test "date/3 in Spanish and English" do
    date = ~D[2026-09-28]
    assert Format.date(date, "es_MX", :long) == "28 de septiembre de 2026"
    assert Format.date(date, "es_MX", :short) == "28/09/2026"
    assert Format.date(date, "en", :long) == "September 28, 2026"
    assert Format.date(date, "en", :short) == "09/28/2026"
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/jido_codemode/locale/format_test.exs`
Expected: FAIL with `module JidoCodemode.Locale.Format is not available`.

- [ ] **Step 3: Implement**

`lib/jido_codemode/locale/format.ex`:

```elixir
defmodule JidoCodemode.Locale.Format do
  @moduledoc """
  Number and date formatting for the demo's two locales. Mexico uses the same
  digit grouping and decimal point as the US, so only labels and dates differ.
  """

  @es_months ~w(enero febrero marzo abril mayo junio julio agosto septiembre octubre noviembre diciembre)
  @en_months ~w(January February March April May June July August September October November December)

  @spec money(number(), :usd | :mxn) :: String.t()
  def money(value, currency) when is_number(value) do
    sign = if value < 0, do: "-", else: ""
    amount = "$" <> delimit(abs(value), 2)

    case currency do
      :mxn -> sign <> amount <> " MXN"
      _usd -> sign <> amount
    end
  end

  @spec percent(number()) :: String.t()
  def percent(fraction) when is_number(fraction), do: delimit(fraction * 100, 1) <> "%"

  @spec number(number()) :: String.t()
  def number(value) when is_integer(value), do: delimit(value, 0)
  def number(value) when is_float(value), do: delimit(value, 2)

  @spec date(Date.t(), String.t(), :long | :short) :: String.t()
  def date(%Date{} = date, "es_MX", :long),
    do: "#{date.day} de #{Enum.at(@es_months, date.month - 1)} de #{date.year}"

  def date(%Date{} = date, "es_MX", :short), do: "#{pad(date.day)}/#{pad(date.month)}/#{date.year}"

  def date(%Date{} = date, _locale, :long),
    do: "#{Enum.at(@en_months, date.month - 1)} #{date.day}, #{date.year}"

  def date(%Date{} = date, _locale, :short), do: "#{pad(date.month)}/#{pad(date.day)}/#{date.year}"

  defp delimit(value, decimals) do
    formatted = :erlang.float_to_binary(value * 1.0, decimals: decimals)
    {sign, digits} = split_sign(formatted)
    [integer | fraction] = String.split(digits, ".")

    grouped =
      integer
      |> String.reverse()
      |> String.graphemes()
      |> Enum.chunk_every(3)
      |> Enum.map_join(",", &Enum.join/1)
      |> String.reverse()

    sign <> Enum.join([grouped | fraction], ".")
  end

  defp split_sign("-" <> digits), do: {"-", digits}
  defp split_sign(digits), do: {"", digits}

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `mix test test/jido_codemode/locale/format_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/jido_codemode/locale/format.ex test/jido_codemode/locale/format_test.exs
git commit -m "Add locale-aware money, number, and date formatting"
```

---

### Task 3: Spanish database copy and FX configuration

**Files:**
- Create: `lib/jido_codemode/locale/dataset.ex`
- Modify: `lib/jido_codemode/application.ex` (`start/2`)
- Modify: `config/runtime.exs`, `config/dev.exs`, `config/test.exs`
- Modify: `.env.example`
- Test: `test/jido_codemode/locale/dataset_test.exs`

**Interfaces:**
- Consumes: `JidoCodemode.Locale.Glossary.categories/0`, `countries/0` (Task 1).
- Produces:
  - `JidoCodemode.Locale.Dataset.source_path() :: Path.t()`
  - `JidoCodemode.Locale.Dataset.parse_rate(term) :: {:ok, float} | :error`
  - `JidoCodemode.Locale.Dataset.fx() :: {:ok, %{rate: float, date: String.t(), source: String.t()}} | :error`
  - `JidoCodemode.Locale.Dataset.build(source, target, rate :: float | nil) :: :ok | {:error, term}`
  - `JidoCodemode.Locale.Dataset.setup() :: :ok` and `reset() :: :ok` (tests)
  - `JidoCodemode.Locale.Dataset.path(locale) :: Path.t()`
  - `JidoCodemode.Locale.Dataset.currency(locale) :: :usd | :mxn`
  - `JidoCodemode.Locale.Dataset.labels(locale) :: :en | :es`
  - `JidoCodemode.Locale.Dataset.rate(locale) :: float` (1.0 unless the locale's currency is MXN)

- [ ] **Step 1: Write the failing test**

`test/jido_codemode/locale/dataset_test.exs`:

```elixir
defmodule JidoCodemode.Locale.DatasetTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias JidoCodemode.Locale.Dataset

  setup do
    previous = Application.get_env(:jido_codemode, Dataset)
    target = Path.join(System.tmp_dir!(), "dataset-test-#{System.unique_integer([:positive])}.sqlite")

    on_exit(fn ->
      File.rm(target)
      if previous, do: Application.put_env(:jido_codemode, Dataset, previous), else: Application.delete_env(:jido_codemode, Dataset)
      Dataset.reset()
    end)

    %{target: target, source: Dataset.source_path()}
  end

  test "parse_rate/1 accepts only positive numbers" do
    assert Dataset.parse_rate("17.8413") == {:ok, 17.8413}
    assert Dataset.parse_rate(" 18 ") == {:ok, 18.0}
    assert Dataset.parse_rate(17.5) == {:ok, 17.5}
    assert Dataset.parse_rate("abc") == :error
    assert Dataset.parse_rate("0") == :error
    assert Dataset.parse_rate("-3") == :error
    assert Dataset.parse_rate(nil) == :error
  end

  test "build/3 converts exactly the three money columns", %{source: source, target: target} do
    assert :ok = Dataset.build(source, target, 2.0)

    for {table, column} <- [{"OrderDetail", "UnitPrice"}, {"Product", "UnitPrice"}, {"Order", "Freight"}] do
      sql = ~s(SELECT SUM("#{column}") FROM "#{table}")
      assert_in_delta scalar(target, sql), scalar(source, sql) * 2.0, 0.01
    end

    discount = ~s(SELECT SUM(Discount) FROM "OrderDetail")
    assert scalar(target, discount) == scalar(source, discount)
  end

  test "build/3 translates categories and countries and keeps proper nouns", %{source: source, target: target} do
    assert :ok = Dataset.build(source, target, 2.0)

    assert scalar(target, ~s(SELECT COUNT(*) FROM "Category" WHERE CategoryName = 'Bebidas')) == 1
    assert scalar(target, ~s(SELECT COUNT(*) FROM "Category" WHERE CategoryName = 'Beverages')) == 0
    assert scalar(target, ~s(SELECT COUNT(*) FROM "Order" WHERE ShipCountry = 'Alemania')) > 0
    assert scalar(target, ~s(SELECT COUNT(*) FROM "Customer" WHERE Country = 'Germany')) == 0
    assert scalar(target, ~s(SELECT COUNT(*) FROM "Supplier" WHERE Country = 'Estados Unidos')) > 0

    product = ~s(SELECT ProductName FROM "Product" ORDER BY Id LIMIT 1)
    assert scalar(target, product) == scalar(source, product)
  end

  test "build/3 with no rate translates labels but keeps USD amounts", %{source: source, target: target} do
    assert :ok = Dataset.build(source, target, nil)

    sql = ~s(SELECT SUM(UnitPrice) FROM "Product")
    assert scalar(target, sql) == scalar(source, sql)
    assert scalar(target, ~s(SELECT COUNT(*) FROM "Category" WHERE CategoryName = 'Lácteos')) == 1
  end

  test "the built copy is read-only", %{source: source, target: target} do
    assert :ok = Dataset.build(source, target, 2.0)
    assert {:error, :eacces} = File.write(target, "x")
  end

  test "setup/0 with a valid rate serves MXN for Spanish and USD for English" do
    Application.put_env(:jido_codemode, Dataset, fx_usd_mxn: "17.8413", fx_date: "2026-09-28", fx_source: "Banxico FIX (SuperDev ERP)")
    Dataset.reset()

    assert Dataset.currency("es_MX") == :mxn
    assert Dataset.labels("es_MX") == :es
    assert Dataset.rate("es_MX") == 17.8413
    assert Dataset.currency("en") == :usd
    assert Dataset.rate("en") == 1.0
    assert Dataset.path("en") == Dataset.source_path()
    refute Dataset.path("es_MX") == Dataset.source_path()
  end

  test "setup/0 with an invalid rate falls back to USD but keeps Spanish labels" do
    Application.put_env(:jido_codemode, Dataset, fx_usd_mxn: "abc")
    Dataset.reset()

    assert Dataset.currency("es_MX") == :usd
    assert Dataset.labels("es_MX") == :es
    assert Dataset.rate("es_MX") == 1.0
  end

  defp scalar(path, sql) do
    {:ok, conn} = Sqlite3.open(path, mode: :readonly)
    {:ok, statement} = Sqlite3.prepare(conn, sql)
    {:row, [value]} = Sqlite3.step(conn, statement)
    :ok = Sqlite3.release(conn, statement)
    :ok = Sqlite3.close(conn)
    value
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/jido_codemode/locale/dataset_test.exs`
Expected: FAIL with `module JidoCodemode.Locale.Dataset is not available`.

- [ ] **Step 3: Implement the module**

`lib/jido_codemode/locale/dataset.ex`:

```elixir
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
      Path.join(System.tmp_dir!(), "agentic-bi-es_MX-#{System.unique_integer([:positive])}.sqlite")

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
      | Enum.map(@country_columns, fn {table, column} -> rename(table, column, Glossary.countries()) end)
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
```

- [ ] **Step 4: Add the FX configuration**

Append to `config/dev.exs` and `config/test.exs`:

```elixir
config :jido_codemode, JidoCodemode.Locale.Dataset,
  fx_usd_mxn: "17.8413",
  fx_date: "2026-09-28",
  fx_source: "Banxico FIX (SuperDev ERP)"
```

In `config/runtime.exs`, after the `config :jido_codemode, demo_password: ...` block, add:

```elixir
if fx_usd_mxn = System.get_env("FX_USD_MXN") do
  config :jido_codemode, JidoCodemode.Locale.Dataset,
    fx_usd_mxn: fx_usd_mxn,
    fx_date: System.get_env("FX_USD_MXN_DATE"),
    fx_source: System.get_env("FX_USD_MXN_SOURCE")
end
```

In `.env.example`, before `# Phoenix HTTP port.`, add:

```bash
# Spanish demo: USD to MXN rate (MXN per 1 USD), its date, and its source.
# Without a valid rate, the Spanish page shows USD.
# FX_USD_MXN=17.8413
# FX_USD_MXN_DATE=2026-09-28
# FX_USD_MXN_SOURCE=Banxico FIX (SuperDev ERP)
```

- [ ] **Step 5: Build the copy at startup**

In `lib/jido_codemode/application.ex`, first line of `start/2`:

```elixir
  def start(_type, _args) do
    :ok = JidoCodemode.Locale.Dataset.setup()

    children = [
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/jido_codemode/locale/dataset_test.exs`
Expected: PASS (7 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/jido_codemode/locale/dataset.ex lib/jido_codemode/application.ex config/dev.exs config/test.exs config/runtime.exs .env.example test/jido_codemode/locale/dataset_test.exs
git commit -m "Build a Spanish Northwind copy with MXN amounts and Spanish labels"
```

---

### Task 4: Query paths honor the locale

**Files:**
- Modify: `lib/jido_codemode/agent/query_runner.ex` (`execute_query/2`, `with_connection/1`, `database_path/0`)
- Modify: `lib/jido_codemode/agent/tools/run_sqlite_query.ex` (`run/2`)
- Modify: `lib/jido_codemode/agent/tools/build_report.ex` (`DbAPI.query/1`)
- Test: `test/jido_codemode/agent/query_runner_test.exs`, `test/jido_codemode/agent/build_report_test.exs`

**Interfaces:**
- Consumes: `Dataset.path/1` (Task 3).
- Produces: `QueryRunner.run(sql, purpose, locale: "es_MX")` queries the Spanish copy. Tools read `Map.get(context, :locale, "en")`.

- [ ] **Step 1: Write the failing tests**

Append to `test/jido_codemode/agent/query_runner_test.exs` (before the final `end`):

```elixir
  test "a Spanish query reads Spanish labels and MXN amounts" do
    {:ok, result} =
      QueryRunner.run(
        """
        SELECT c.CategoryName, ROUND(SUM(od.UnitPrice * od.Quantity * (1 - od.Discount)), 2) AS revenue
        FROM OrderDetail od
        JOIN Product p ON p.Id = od.ProductId
        JOIN Category c ON c.Id = p.CategoryId
        WHERE c.CategoryName = 'Bebidas'
        GROUP BY c.CategoryName
        """,
        :analysis,
        locale: "es_MX"
      )

    assert [%{"CategoryName" => "Bebidas", "revenue" => revenue}] = result.rows
    assert_in_delta revenue, 4_779_116.56, 0.01
  end

  test "an English query still reads USD and English labels" do
    {:ok, result} =
      QueryRunner.run("SELECT CategoryName FROM Category WHERE CategoryName = 'Beverages'", :analysis)

    assert result.rows == [%{"CategoryName" => "Beverages"}]
  end

  test "run_sqlite_query uses the locale from the tool context" do
    {:ok, result} =
      RunSqliteQuery.run(
        %{sql: "SELECT CategoryName FROM Category WHERE CategoryName = 'Lácteos'", purpose: "analysis"},
        %{locale: "es_MX"}
      )

    assert result.preview_rows == [["Lácteos"]]
  end
```

Append to `test/jido_codemode/agent/build_report_test.exs` (before the final `end`):

```elixir
  test "db.query in build_report uses the locale from the tool context" do
    session_id = "build-report-locale-test"

    {:ok, _result} =
      BuildReport.run(
        %{
          code: ~S'''
            local result = db.query({
              sql = [[SELECT CategoryName FROM Category WHERE CategoryName = 'Bebidas']],
              purpose = "analysis"
            })

            return {
              version = 1,
              title = "Categorías",
              blocks = {
                { type = "table", id = "cats", title = "Categorías", source = result, columns = {"CategoryName"}, row_limit = 5 }
              }
            }
          '''
        },
        %{session_id: session_id, locale: "es_MX"}
      )

    assert {:ok, %Report{blocks: [%Report.TableBlock{rows: rows}]}} = Report.latest_for_session(session_id)
    assert inspect(rows) =~ "Bebidas"
    refute inspect(rows) =~ "Beverages"
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/jido_codemode/agent/query_runner_test.exs test/jido_codemode/agent/build_report_test.exs`
Expected: FAIL. The Spanish queries return no rows (`[]`), because every query still opens the English database.

- [ ] **Step 3: Implement**

In `lib/jido_codemode/agent/query_runner.ex`:

1. Add `alias JidoCodemode.Locale.Dataset` next to the existing aliases.
2. In `execute_query/2`, change `with_connection(fn conn ->` to:

```elixir
    with_connection(Map.get(limits, :locale, "en"), fn conn ->
```

3. Replace `with_connection/1` and delete `database_path/0` (the source path now lives in `Dataset.source_path/0`):

```elixir
  defp with_connection(locale, fun) do
    case Sqlite3.open(Dataset.path(locale), mode: :readonly) do
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
```

`limits_for/2` already merges every option into `limits`, so `locale: "es_MX"` reaches `execute_query/2` with no further change.

In `lib/jido_codemode/agent/tools/run_sqlite_query.ex`, replace `run/2`:

```elixir
  @impl true
  def run(%{sql: sql, purpose: purpose}, context) do
    locale = Map.get(context, :locale, "en")

    with {:ok, result} <- QueryRunner.run(sql, purpose, locale: locale) do
      {:ok, QueryRunner.to_preview(result)}
    end
  end
```

In `lib/jido_codemode/agent/tools/build_report.ex`, inside `deflua query(params), state do`, replace `case QueryRunner.run(sql, purpose) do` with:

```elixir
      locale =
        case Lua.get_private(state, :tool_context) do
          {:ok, context} when is_map(context) -> Map.get(context, :locale, "en")
          _other -> "en"
        end

      case QueryRunner.run(sql, purpose, locale: locale) do
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/jido_codemode/agent`
Expected: PASS (all agent tests, including the three new ones).

- [ ] **Step 5: Commit**

```bash
git add lib/jido_codemode/agent test/jido_codemode/agent
git commit -m "Query the Spanish database copy when the tool context is Spanish"
```

---

### Task 5: Agent language instructions

**Files:**
- Modify: `lib/jido_codemode/sidebar_agent.ex` (`system_prompt_with_schema/0`)
- Test: `test/jido_codemode/sidebar_agent_test.exs`

**Interfaces:**
- Consumes: `Dataset.currency/1`, `labels/1`, `fx/0` (Task 3); `Glossary.prompt_summary/0` (Task 1).
- Produces: `SidebarAgent.system_prompt_with_schema(locale \\ "en") :: String.t()`.

- [ ] **Step 1: Write the failing test**

`test/jido_codemode/sidebar_agent_test.exs`:

```elixir
defmodule JidoCodemode.SidebarAgentTest do
  use ExUnit.Case, async: false

  alias JidoCodemode.SidebarAgent

  test "the Spanish prompt carries the mirror rule, voice, glossary, and MXN rule" do
    prompt = SidebarAgent.system_prompt_with_schema("es_MX")

    assert prompt =~ "The page language is Spanish (Mexico)."
    assert prompt =~ "Answer in the language of the user's question."
    assert prompt =~ ~s(use Mexican Spanish with "tú")
    assert prompt =~ "Bebidas (Beverages)"
    assert prompt =~ "already in Mexican pesos (MXN)"
    assert prompt =~ "17.8413"
    assert prompt =~ "Never convert them again."
    assert prompt =~ "Schema digest:"
  end

  test "the English prompt keeps USD and has no Spanish glossary" do
    prompt = SidebarAgent.system_prompt_with_schema("en")

    assert prompt =~ "The page language is English."
    assert prompt =~ "US dollars (USD)"
    refute prompt =~ "Bebidas"
  end

  test "the default is English" do
    assert SidebarAgent.system_prompt_with_schema() == SidebarAgent.system_prompt_with_schema("en")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/jido_codemode/sidebar_agent_test.exs`
Expected: FAIL with `undefined function system_prompt_with_schema/1`.

- [ ] **Step 3: Implement**

In `lib/jido_codemode/sidebar_agent.ex`, add aliases:

```elixir
  alias JidoCodemode.Locale.{Dataset, Glossary}
```

Replace `system_prompt_with_schema/0` with:

```elixir
  def system_prompt_with_schema(locale \\ "en") do
    [
      @base_system_prompt,
      language_block(locale),
      "Schema digest:",
      Schema.prompt_digest()
    ]
    |> Enum.join("\n\n")
  end

  defp language_block("es_MX") do
    labels =
      case Dataset.labels("es_MX") do
        :es ->
          "The database stores category and country names in Spanish: " <>
            Glossary.prompt_summary() <> ". Use these Spanish names, including in SQL filters."

        :en ->
          "The database stores category and country names in English."
      end

    money =
      case {Dataset.currency("es_MX"), Dataset.fx()} do
        {:mxn, {:ok, fx}} ->
          "Money amounts in the database are already in Mexican pesos (MXN), converted from USD " <>
            "at #{fx.rate} MXN per USD (#{fx.source}, #{fx.date}). Never convert them again. " <>
            "Write amounts as $1,234.56 MXN. In report tables, name money columns with the " <>
            ~s(currency, for example "Ingresos (MXN)".)

        _usd ->
          "Money amounts in the database are in US dollars (USD). Write amounts as $1,234.56 USD."
      end

    """
    Language:
    - The page language is Spanish (Mexico).
    - Answer in the language of the user's question. If the question gives no language signal, answer in Spanish.
    - When you answer in Spanish: use Mexican Spanish with "tú", professional and warm. Give the answer first, then the context. Do not repeat the question. Use "reporte", "gráfica", "ingresos", and "pedidos". Write dates as "28 de septiembre de 2026" or 28/09/2026.
    - Write report titles, summaries, and column headers in the language of your answer.
    - #{labels}
    - #{money}
    """
  end

  defp language_block(_locale) do
    """
    Language:
    - The page language is English.
    - Answer in the language of the user's question. If the question gives no language signal, answer in English.
    - Write report titles, summaries, and column headers in the language of your answer.
    - Money amounts in the database are in US dollars (USD). Write amounts as $1,234.56.
    """
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/jido_codemode/sidebar_agent_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/jido_codemode/sidebar_agent.ex test/jido_codemode/sidebar_agent_test.exs
git commit -m "Add a per-locale language block to the agent instructions"
```

---

### Task 6: Request locale plumbing

**Files:**
- Create: `lib/jido_codemode_web/plugs/locale.ex`
- Create: `lib/jido_codemode_web/locale_hook.ex`
- Modify: `lib/jido_codemode_web/router.ex`
- Modify: `lib/jido_codemode_web/components/layouts/root.html.heex` (line 2 and line 7)
- Test: `test/jido_codemode_web/plugs/locale_test.exs`

**Interfaces:**
- Consumes: `JidoCodemode.Locale.resolve/3`, `html_lang/1`, `cookie_name/0` (Task 1).
- Produces: `conn.assigns.locale`, session `"locale"`, LiveView `socket.assigns.locale`, and the Gettext locale in the LiveView process.

- [ ] **Step 1: Write the failing test**

`test/jido_codemode_web/plugs/locale_test.exs`:

```elixir
defmodule JidoCodemodeWeb.Plugs.LocaleTest do
  use JidoCodemodeWeb.ConnCase, async: true

  test "a Spanish browser gets the Spanish page", %{conn: conn} do
    html = conn |> put_req_header("accept-language", "es-MX,es;q=0.9") |> get(~p"/") |> html_response(200)
    assert html =~ ~s(<html lang="es-MX")
  end

  test "an English browser gets the English page", %{conn: conn} do
    html = conn |> put_req_header("accept-language", "en-US,en;q=0.9") |> get(~p"/") |> html_response(200)
    assert html =~ ~s(<html lang="en")
  end

  test "?lang overrides the header and is saved in a cookie", %{conn: conn} do
    conn = conn |> put_req_header("accept-language", "en-US") |> get(~p"/?lang=es")
    assert html_response(conn, 200) =~ ~s(<html lang="es-MX")
    assert conn.resp_cookies["agentic_bi_locale"].value == "es_MX"
  end

  test "the cookie beats the header", %{conn: conn} do
    conn =
      conn
      |> put_req_cookie("agentic_bi_locale", "es_MX")
      |> put_req_header("accept-language", "en-US")
      |> get(~p"/")

    assert html_response(conn, 200) =~ ~s(<html lang="es-MX")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/jido_codemode_web/plugs/locale_test.exs`
Expected: FAIL. Every response still has `<html lang="en">`.

- [ ] **Step 3: Implement the plug**

`lib/jido_codemode_web/plugs/locale.ex`:

```elixir
defmodule JidoCodemodeWeb.Plugs.Locale do
  @moduledoc "Chooses the page language for each request and remembers an explicit choice."

  import Plug.Conn

  alias JidoCodemode.Locale

  @max_age 365 * 24 * 60 * 60

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = conn |> fetch_query_params() |> fetch_cookies()
    param = conn.query_params["lang"]
    accept_language = conn |> get_req_header("accept-language") |> List.first()
    locale = Locale.resolve(param, conn.cookies[Locale.cookie_name()], accept_language)

    Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)

    conn
    |> put_session("locale", locale)
    |> assign(:locale, locale)
    |> maybe_remember(param, locale)
  end

  defp maybe_remember(conn, param, locale) do
    if Locale.normalize(param) do
      put_resp_cookie(conn, Locale.cookie_name(), locale, max_age: @max_age, same_site: "Lax")
    else
      conn
    end
  end
end
```

`lib/jido_codemode_web/locale_hook.ex`:

```elixir
defmodule JidoCodemodeWeb.LocaleHook do
  @moduledoc "Carries the request's page language into the LiveView process."

  import Phoenix.Component, only: [assign: 3]

  alias JidoCodemode.Locale

  def on_mount(:default, _params, session, socket) do
    locale = Locale.normalize(session["locale"]) || Locale.default()
    Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)
    {:cont, assign(socket, :locale, locale)}
  end
end
```

- [ ] **Step 4: Wire the router and root layout**

In `lib/jido_codemode_web/router.ex`, add `plug JidoCodemodeWeb.Plugs.Locale` to the `:browser` pipeline after `plug :fetch_session`, and wrap the LiveView route:

```elixir
  scope "/", JidoCodemodeWeb do
    pipe_through :browser

    get "/health", PageController, :health

    live_session :default, on_mount: [JidoCodemodeWeb.LocaleHook] do
      live "/", SandboxLive
    end
  end
```

In `lib/jido_codemode_web/components/layouts/root.html.heex`, replace line 2:

```heex
<html lang={JidoCodemode.Locale.html_lang(assigns[:locale] || "en")}>
```

and replace the `suffix` on line 7:

```heex
    <.live_title default="Agentic BI" suffix={" · " <> gettext("Decision-ready analysis")}>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/jido_codemode_web`
Expected: PASS (the new plug tests and the existing LiveView tests).

- [ ] **Step 6: Commit**

```bash
git add lib/jido_codemode_web/plugs lib/jido_codemode_web/locale_hook.ex lib/jido_codemode_web/router.ex lib/jido_codemode_web/components/layouts/root.html.heex test/jido_codemode_web/plugs
git commit -m "Resolve the page language per request and carry it into LiveView"
```

---

### Task 7: Interface copy through gettext, with Spanish translations

**Files:**
- Modify: `lib/jido_codemode_web/live/sandbox_live.ex` (render template, `unlock_chat` handler, `submit_prompt`, error helpers near lines 886 and 891, `build_charts/0`, `suggestions` list near line 795, sample data functions, `customer_shape_spec/0` axis titles)
- Modify: `lib/jido_codemode_web/components/layouts.ex` (header label, theme-toggle `aria-label`s)
- Create: `priv/gettext/default.pot`, `priv/gettext/es_MX/LC_MESSAGES/default.po`
- Test: `test/jido_codemode_web/translations_test.exs`

**Interfaces:**
- Consumes: the Gettext locale set by Task 6.
- Produces: Spanish copy for every string below. The msgids below are exact; later tasks reuse them.

- [ ] **Step 1: Write the failing test**

`test/jido_codemode_web/translations_test.exs`:

```elixir
defmodule JidoCodemodeWeb.TranslationsTest do
  use JidoCodemodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "every es_MX message is translated" do
    {:ok, po} = Expo.PO.parse_file("priv/gettext/es_MX/LC_MESSAGES/default.po")

    untranslated =
      for %Expo.Message.Singular{msgid: id, msgstr: str} <- po.messages,
          IO.iodata_to_binary(str) == "",
          do: IO.iodata_to_binary(id)

    assert untranslated == []
  end

  test "the Spanish page shows Spanish copy and no English interface copy", %{conn: conn} do
    {:ok, _view, html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/")

    for spanish <- [
          "Convierte preguntas de negocio en análisis claros",
          "Aquí aparecerá tu análisis",
          "Agente de análisis",
          "Tendencia mensual de ingresos",
          "Contraseña de la demo"
        ] do
      assert html =~ spanish
    end

    for english <- [
          "Turn business questions into clear analysis",
          "Your analysis will appear here",
          "Monthly revenue trend",
          "Demo password",
          "How it works"
        ] do
      refute html =~ english
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/jido_codemode_web/translations_test.exs`
Expected: FAIL with `{:error, %File.Error{reason: :enoent}}` for the `.po` file, and the Spanish page still showing English copy.

- [ ] **Step 3: Wrap every interface string in gettext**

Rule: in HEEx, replace a literal text node `Some text` with `{gettext("Some text")}` and a literal attribute `attr="Some text"` with `attr={gettext("Some text")}`; in Elixir code, replace `"Some text"` with `gettext("Some text")`. Use the msgids exactly as listed. Do not wrap `Agentic BI`, `Northwind`, customer names in sample data, or technical values.

Strings in `sandbox_live.ex` and `layouts.ex`, grouped by where they appear:

- Header: `Decision intelligence` (in both `sandbox_live.ex` and `layouts.ex`), `Turn business questions into clear analysis`, `Explore your data with an agent that can query, compare, visualize, and explain its findings.` (currently wrapped across two source lines; make it one msgid), `How it works`, `The agent reads a compact schema through a read-only connection.`, `It runs bounded queries and builds the needed metrics and visuals.`, `Every result is validated before it appears in your analysis.`, `aria-label="Homepage"`.
- Report area: `Generated analysis`, `Metric`, `No rows to show for this table.`, `No rows to show for this chart.`, `Your analysis will appear here`, `Ask the analysis agent for a chart, table, metric, or complete report.`, `Example analyses`, `See what Agentic BI can build`.
- Agent panel: `Restart session`, `Analysis agent`, `Ask about Northwind`, `Ask a business question or request a complete analysis.`, `More`, `Start with a prompt`, `Select an example above or describe the decision you want to support.`, `You`, `Agent`, `Demo password`, `Enter the password to unlock the analysis agent.`, `Unlock`, `Connected with read-only access`, `placeholder="Password"`, `placeholder="Ask about revenue, customers, products, or trends"`, the status badge `"Ready"` / `"Locked"` (line 429), the send button `"Analyzing..."` / `"Send"` (line 599).
- Code: in `unlock_chat`, `"That password is not correct."`; in `submit_prompt`, `"The agent session is still starting. Try again in a moment."`; near line 886, `"The agent returned a non-text response: #{...}"` becomes `gettext("The agent returned a non-text response: %{details}", details: inspect(reply, pretty: true, limit: 20))`; near line 891, `"The agent request failed: #{...}"` becomes `gettext("The agent request failed: %{reason}", reason: inspect(reason, pretty: true, limit: 20))`.
- `build_charts/0` (becomes `build_charts/1` in Task 8; wrap now): kickers `Line`, `Bar`, `Donut`, `Scatter`; titles `Monthly revenue trend`, `Revenue by category`, `Channel mix`, `Customer value vs. order volume`; descriptions `A simple time-series anchor for the conversation.`, `A ranked comparison of the biggest drivers.`, `A quick composition view for share of revenue.`, `A compact way to spot high-value segments.`.
- Suggestions (near line 795): labels `Revenue trend`, `Top categories`, `Top customers`, `Important joins`, `Complete analysis`; prompts `Show a monthly revenue trend`, `Compare the top categories`, `List the top customers by revenue`, `Describe the most important joins`, `Build a short analysis with a chart and a table`.
- `customer_shape_spec/0` axis titles: `Average order value`, `Orders`.
- Sample data labels: categories `Beverages`, `Dairy`, `Confections`, `Meat`, `Seafood`; channels `Direct`, `Partners`, `Inbound`, `Expansion`; segments `Enterprise`, `Growth`, `Mid-market`. Wrap the `category:`, `channel:`, and `segment:` values; leave `customer:` names unwrapped.
- `layouts.ex` theme toggle: `aria-label="Use system theme"`, `aria-label="Use light theme"`, `aria-label="Use dark theme"`.

`layouts.ex` needs Gettext available: if it does not already `use JidoCodemodeWeb, :html` (which brings in `use Gettext, backend: JidoCodemodeWeb.Gettext`), add `use Gettext, backend: JidoCodemodeWeb.Gettext` at the top of the module.

- [ ] **Step 4: Extract and create the Spanish catalog**

Run:

```bash
mix gettext.extract
mix gettext.merge priv/gettext --locale es_MX
```

Expected: `priv/gettext/default.pot` and `priv/gettext/es_MX/LC_MESSAGES/default.po` exist, with empty `msgstr` values.

- [ ] **Step 5: Fill in every translation**

In `priv/gettext/es_MX/LC_MESSAGES/default.po`, set `msgstr` for each `msgid`. Keep the `#:` reference comments the merge wrote. The complete set (the next task adds the last six; add them now too so the file is complete):

| msgid | msgstr |
| --- | --- |
| Decision-ready analysis | Análisis listo para decidir |
| Decision intelligence | Inteligencia para decidir |
| Turn business questions into clear analysis | Convierte preguntas de negocio en análisis claros |
| Explore your data with an agent that can query, compare, visualize, and explain its findings. | Explora tus datos con un agente que consulta, compara, visualiza y explica lo que encuentra. |
| How it works | Cómo funciona |
| The agent reads a compact schema through a read-only connection. | El agente lee un esquema compacto mediante una conexión de solo lectura. |
| It runs bounded queries and builds the needed metrics and visuals. | Ejecuta consultas acotadas y construye las métricas y visualizaciones necesarias. |
| Every result is validated before it appears in your analysis. | Cada resultado se valida antes de aparecer en tu análisis. |
| Homepage | Página de inicio |
| Generated analysis | Análisis generado |
| Metric | Métrica |
| No rows to show for this table. | Esta tabla no tiene filas para mostrar. |
| No rows to show for this chart. | Esta gráfica no tiene filas para mostrar. |
| Your analysis will appear here | Aquí aparecerá tu análisis |
| Ask the analysis agent for a chart, table, metric, or complete report. | Pídele al agente una gráfica, una tabla, una métrica o un reporte completo. |
| Example analyses | Análisis de ejemplo |
| See what Agentic BI can build | Mira lo que Agentic BI puede construir |
| Restart session | Reiniciar sesión |
| Analysis agent | Agente de análisis |
| Ask about Northwind | Pregunta sobre Northwind |
| Ask a business question or request a complete analysis. | Haz una pregunta de negocio o pide un análisis completo. |
| More | Más |
| Start with a prompt | Empieza con una pregunta |
| Select an example above or describe the decision you want to support. | Elige un ejemplo de arriba o describe la decisión que quieres respaldar. |
| You | Tú |
| Agent | Agente |
| Demo password | Contraseña de la demo |
| Enter the password to unlock the analysis agent. | Escribe la contraseña para activar el agente de análisis. |
| Unlock | Desbloquear |
| Connected with read-only access | Conectado con acceso de solo lectura |
| Password | Contraseña |
| Ask about revenue, customers, products, or trends | Pregunta sobre ingresos, clientes, productos o tendencias |
| Ready | Listo |
| Locked | Bloqueado |
| Analyzing... | Analizando… |
| Send | Enviar |
| That password is not correct. | Esa contraseña no es correcta. Revísala e inténtalo de nuevo. |
| The agent session is still starting. Try again in a moment. | La sesión del agente aún se está iniciando. Inténtalo de nuevo en un momento. |
| The agent returned a non-text response: %{details} | El agente devolvió una respuesta que no es texto: %{details} |
| The agent request failed: %{reason} | La solicitud al agente falló: %{reason} |
| Line | Línea |
| Bar | Barras |
| Donut | Dona |
| Scatter | Dispersión |
| Monthly revenue trend | Tendencia mensual de ingresos |
| Revenue by category | Ingresos por categoría |
| Channel mix | Mezcla de canales |
| Customer value vs. order volume | Valor del cliente vs. volumen de pedidos |
| A simple time-series anchor for the conversation. | Una serie de tiempo sencilla como punto de partida. |
| A ranked comparison of the biggest drivers. | Una comparación ordenada de los principales impulsores. |
| A quick composition view for share of revenue. | Una vista rápida de cómo se reparten los ingresos. |
| A compact way to spot high-value segments. | Una forma compacta de detectar segmentos de alto valor. |
| Revenue trend | Tendencia de ingresos |
| Top categories | Categorías principales |
| Top customers | Clientes principales |
| Important joins | Relaciones clave |
| Complete analysis | Análisis completo |
| Show a monthly revenue trend | Muestra la tendencia mensual de ingresos |
| Compare the top categories | Compara las categorías principales |
| List the top customers by revenue | Enlista los clientes principales por ingresos |
| Describe the most important joins | Describe las relaciones más importantes entre tablas |
| Build a short analysis with a chart and a table | Arma un análisis breve con una gráfica y una tabla |
| Average order value | Valor promedio por pedido |
| Orders | Pedidos |
| Beverages | Bebidas |
| Dairy | Lácteos |
| Confections | Dulces y postres |
| Meat | Carnes y aves |
| Seafood | Pescados y mariscos |
| Direct | Directo |
| Partners | Socios |
| Inbound | Entrantes |
| Expansion | Expansión |
| Enterprise | Corporativo |
| Growth | Crecimiento |
| Mid-market | Mercado medio |
| Use system theme | Usar el tema del sistema |
| Use light theme | Usar tema claro |
| Use dark theme | Usar tema oscuro |
| Language | Idioma |
| Switch to Spanish | Cambiar a español |
| Switch to English | Cambiar a inglés |
| You switched to Spanish. Figures are now in MXN. | Cambiaste a español. Las cifras ahora están en MXN. |
| You switched to Spanish. | Cambiaste a español. |
| You switched to English. Figures are now in USD. | Cambiaste a inglés. Las cifras ahora están en USD. |
| Figures in Mexican pesos (MXN), converted from USD at the %{source} exchange rate of %{date}: 1 USD = %{rate} MXN. | Cifras en pesos mexicanos (MXN), convertidas de USD con el tipo de cambio %{source} del %{date}: 1 USD = %{rate} MXN. |
| Figures in US dollars (USD). | Cifras en dólares estadounidenses (USD). |

The last eight rows (from `Language` onward) are used in Task 8. `mix gettext.extract` only writes msgids that appear in code, so add those eight entries to the `.po` file by hand now, each as:

```po
msgid "Language"
msgstr "Idioma"
```

Task 8 re-runs extraction, which adds their `#:` references to `default.pot`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/jido_codemode_web`
Expected: PASS, including the existing English LiveView tests (English copy is unchanged).

- [ ] **Step 7: Commit**

```bash
git add lib/jido_codemode_web priv/gettext test/jido_codemode_web/translations_test.exs
git commit -m "Translate the interface copy to Mexican Spanish through gettext"
```

---

### Task 8: Language switch, footnote, agent wiring, and localized charts and numbers

**Files:**
- Modify: `lib/jido_codemode_web/live/sandbox_live.ex` (`mount/3`, `handle_event/3` for `reset_chat` and new `set_locale`, `submit_prompt`, `start_sidebar_agent/1`, `build_charts`, sample data functions, `format_metric_value/2`, `format_table_value/1`, header template, VegaChart hook and chart `div`s)
- Modify: `assets/js/app.js`
- Modify: `priv/gettext/default.pot`, `priv/gettext/es_MX/LC_MESSAGES/default.po` (re-extract)
- Test: `test/jido_codemode_web/live/sandbox_live_test.exs`

**Interfaces:**
- Consumes: `socket.assigns.locale` (Task 6); `Dataset.currency/1`, `rate/1`, `fx/0` (Task 3); `Format.money/2`, `percent/1`, `number/1`, `date/3` (Task 2); `SidebarAgent.system_prompt_with_schema/1` (Task 5); msgids from Task 7.
- Produces: `set_locale` LiveView event; push event `"locale-changed"` with `%{locale: String.t(), html_lang: String.t()}`; assigns `:currency` and `:locale_notice`.

- [ ] **Step 1: Write the failing tests**

Append to `test/jido_codemode_web/live/sandbox_live_test.exs` (before the final `end`; the file's `setup` already sets the demo password to `"test-password"`):

```elixir
  test "switching language in place keeps the demo unlocked and starts a new conversation", %{conn: conn} do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/")
    view |> form("#unlock-form", unlock: %{password: "test-password"}) |> render_submit()
    assert has_element?(view, "#chat-form")

    html = view |> element("#locale-es_MX") |> render_click()

    assert html =~ "Convierte preguntas de negocio en análisis claros"
    assert has_element?(view, "#chat-form")
    refute has_element?(view, "#unlock-form")
    assert has_element?(view, "#locale-notice", "Cambiaste a español. Las cifras ahora están en MXN.")
    assert_push_event(view, "locale-changed", %{locale: "es_MX", html_lang: "es-MX"})
  end

  test "the Spanish page shows the MXN footnote with the rate", %{conn: conn} do
    {:ok, _view, html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/")

    assert html =~ "Cifras en pesos mexicanos (MXN)"
    assert html =~ "1 USD = 17.8413 MXN"
    assert html =~ "28/09/2026"
  end

  test "the English page has no currency footnote", %{conn: conn} do
    {:ok, _view, html} = conn |> put_req_header("accept-language", "en-US") |> live(~p"/")
    refute html =~ "Cifras en"
    refute html =~ "Figures in"
  end

  test "Spanish sample charts use translated labels, MXN amounts, and a Spanish chart locale", %{conn: conn} do
    {:ok, view, _html} = conn |> put_req_header("accept-language", "es-MX") |> live(~p"/")

    spec = view |> element("#sample-chart-category-revenue") |> render()
    assert spec =~ "Bebidas"
    assert spec =~ ~s(data-locale="es-MX")
    # 267_900 USD sample value times 17.8413
    assert spec =~ "4779684"
  end

  test "agent requests carry the page locale in the tool context" do
    socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, agent_id: "sandbox-1", locale: "es_MX"}}
    assert JidoCodemodeWeb.SandboxLive.tool_context(socket) == %{session_id: "sandbox-1", locale: "es_MX"}
  end
```

The last test builds a socket directly, so it does not depend on LiveView process internals.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/jido_codemode_web/live/sandbox_live_test.exs`
Expected: FAIL: no `#locale-es_MX` element, no footnote, English sample labels, and `tool_context/1` undefined.

- [ ] **Step 3: Implement the LiveView changes**

In `lib/jido_codemode_web/live/sandbox_live.ex`:

1. Aliases:

```elixir
  alias JidoCodemode.Locale
  alias JidoCodemode.Locale.{Dataset, Format}
```

2. In `mount/3`, replace `|> assign(:charts, build_charts())` with:

```elixir
      |> assign(:currency, Dataset.currency(socket.assigns.locale))
      |> assign(:charts, build_charts(socket.assigns.locale))
      |> assign(:locale_notice, nil)
```

3. Replace `handle_event("reset_chat", ...)` (currently lines 91-100) with a version that calls a new `restart_conversation/1` holding the same pipeline, and add `set_locale`:

```elixir
  def handle_event("reset_chat", _params, socket) do
    {:noreply, socket |> assign(:locale_notice, nil) |> restart_conversation()}
  end

  def handle_event("set_locale", %{"locale" => value}, socket) do
    case Locale.normalize(value) do
      nil ->
        {:noreply, socket}

      locale when locale == socket.assigns.locale ->
        {:noreply, socket}

      locale ->
        Gettext.put_locale(JidoCodemodeWeb.Gettext, locale)

        socket =
          socket
          |> assign(:locale, locale)
          |> assign(:currency, Dataset.currency(locale))
          |> assign(:charts, build_charts(locale))

        socket =
          if socket.assigns.chat_unlocked do
            socket
            |> restart_conversation()
            |> assign(:locale_notice, locale_notice(locale, socket.assigns.currency))
          else
            socket
          end

        {:noreply,
         push_event(socket, "locale-changed", %{locale: locale, html_lang: Locale.html_lang(locale)})}
    end
  end

  defp restart_conversation(socket) do
    socket
    |> stop_sidebar_agent()
    |> assign(:chat_form, chat_form())
    |> assign(:chat_messages, [])
    |> assign(:agent_report, nil)
    |> clear_pending_chat()
    |> maybe_start_sidebar_agent()
  end

  defp locale_notice("es_MX", :mxn), do: gettext("You switched to Spanish. Figures are now in MXN.")
  defp locale_notice("es_MX", _currency), do: gettext("You switched to Spanish.")
  defp locale_notice(_locale, _currency), do: gettext("You switched to English. Figures are now in USD.")

  @doc false
  def tool_context(socket), do: %{session_id: socket.assigns.agent_id, locale: socket.assigns.locale}

  defp currency_footnote("es_MX", :mxn) do
    {:ok, fx} = Dataset.fx()

    date =
      case Date.from_iso8601(fx.date) do
        {:ok, date} -> Format.date(date, "es_MX", :short)
        _error -> fx.date
      end

    gettext(
      "Figures in Mexican pesos (MXN), converted from USD at the %{source} exchange rate of %{date}: 1 USD = %{rate} MXN.",
      source: fx.source,
      date: date,
      rate: :erlang.float_to_binary(fx.rate, [:short])
    )
  end

  defp currency_footnote("es_MX", _usd), do: gettext("Figures in US dollars (USD).")
  defp currency_footnote(_locale, _currency), do: nil
```

4. In `submit_prompt`, clear the notice and pass the locale: add `|> assign(:locale_notice, nil)` to the pipeline in the `true ->` branch, and replace `tool_context: %{session_id: agent_id}` with:

```elixir
             tool_context: tool_context(socket)
```

`socket.assigns.agent_id` equals `agent_id` at that point, so the value is unchanged apart from the added `locale`.

5. In `start_sidebar_agent/1`, replace `SidebarAgent.system_prompt_with_schema()` with `SidebarAgent.system_prompt_with_schema(socket.assigns.locale)`.

6. Sample charts: rename `build_charts/0` to `build_charts(locale)`, and make each spec function take the rate. Replace the four `spec_json:` values with `revenue_trend_spec(rate)`, `category_revenue_spec(rate)`, `channel_mix_spec(rate)`, and `customer_shape_spec(rate)`, where `rate = Dataset.rate(locale)` is bound at the top of `build_charts/1`. Each spec function passes `rate` to its data function, and each data function multiplies money fields:

```elixir
  defp monthly_revenue_data(rate) do
    [
      %{month: ~D[2024-01-01], revenue: 48_200},
      %{month: ~D[2024-02-01], revenue: 52_800},
      %{month: ~D[2024-03-01], revenue: 57_600},
      %{month: ~D[2024-04-01], revenue: 61_400},
      %{month: ~D[2024-05-01], revenue: 66_900},
      %{month: ~D[2024-06-01], revenue: 64_100},
      %{month: ~D[2024-07-01], revenue: 72_300},
      %{month: ~D[2024-08-01], revenue: 76_800}
    ]
    |> Enum.map(&%{&1 | revenue: round(&1.revenue * rate)})
  end
```

Apply the same `|> Enum.map(&%{&1 | revenue: round(&1.revenue * rate)})` to `category_revenue_data/1` and `channel_mix_data/1`, and `|> Enum.map(&%{&1 | revenue: round(&1.revenue * rate), avg_order_value: round(&1.avg_order_value * rate)})` to `customer_shape_data/1`. (`round(267_900 * 17.8413)` is `4_779_684`, which the test checks.)

7. Numbers in reports: replace `format_metric_value/2` and `format_table_value/1`:

```elixir
  defp format_metric_value(value, :currency, currency) when is_number(value),
    do: Format.money(value, currency)

  defp format_metric_value(value, :percent, _currency) when is_number(value),
    do: Format.percent(value)

  defp format_metric_value(value, :number, _currency) when is_number(value),
    do: Format.number(value)

  defp format_metric_value(value, _format, _currency), do: to_string(value)

  defp format_table_value(nil), do: "-"
  defp format_table_value(value) when is_number(value), do: Format.number(value)
  defp format_table_value(value), do: to_string(value)
```

Update every template call `format_metric_value(x, y)` to `format_metric_value(x, y, @currency)`. Delete the now-unused `format_integer/1` if nothing else calls it (`mix compile --warnings-as-errors` reports it).

8. Header switch: in the header's action row, directly before `<Layouts.theme_toggle />`, add:

```heex
            <div
              role="group"
              aria-label={gettext("Language")}
              class="inline-flex items-center rounded-full p-0.5 ring-1 ring-base-300/70"
            >
              <button
                :for={{code, label, aria} <- [{"es_MX", "ES", gettext("Switch to Spanish")}, {"en", "EN", gettext("Switch to English")}]}
                id={"locale-#{code}"}
                type="button"
                phx-click="set_locale"
                phx-value-locale={code}
                aria-label={aria}
                aria-pressed={to_string(@locale == code)}
                class={[
                  "rounded-full px-3 py-1.5 text-xs font-semibold tracking-wide transition-colors focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary",
                  @locale == code && "bg-base-content text-base-100",
                  @locale != code && "text-base-content/65 hover:text-base-content"
                ]}
              >
                {label}
              </button>
            </div>
```

9. Notice and footnote: directly above the chat conversation list, add:

```heex
                <p
                  :if={@locale_notice}
                  id="locale-notice"
                  class="rounded-lg bg-base-200/70 px-3 py-2 text-sm text-base-content/75"
                >
                  {@locale_notice}
                </p>
```

and directly below the chat form (after the `Connected with read-only access` line) add:

```heex
                <p
                  :if={footnote = currency_footnote(@locale, @currency)}
                  id="currency-footnote"
                  class="text-xs leading-5 text-pretty text-base-content/55"
                >
                  {footnote}
                </p>
```

10. Vega locale: on every `div` with `phx-hook=".VegaChart"` (sample and report charts), add `data-locale={Locale.html_lang(@locale)}`. In the colocated `.VegaChart` hook, replace the `vegaEmbed(...)` call with:

```javascript
            const esMX = this.el.dataset.locale === "es-MX"

            const options = {actions: false, renderer: "svg"}

            if (esMX) {
              options.formatLocale = {decimal: ".", thousands: ",", grouping: [3], currency: ["$", ""]}
              options.timeFormatLocale = {
                dateTime: "%A, %e de %B de %Y, %X",
                date: "%d/%m/%Y",
                time: "%H:%M:%S",
                periods: ["AM", "PM"],
                days: ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"],
                shortDays: ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"],
                months: ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"],
                shortMonths: ["ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic"],
              }
            }

            const result = await vegaEmbed(this.el, JSON.parse(spec), options)
```

- [ ] **Step 4: Apply the locale in the browser**

Append to `assets/js/app.js`:

```javascript
// Page language: the LiveView switches copy in place; persist the choice and
// update <html lang> so the next visit and assistive technology agree.
window.addEventListener("phx:locale-changed", (event) => {
  const {locale, html_lang: htmlLang} = event.detail
  document.documentElement.lang = htmlLang
  document.cookie = `agentic_bi_locale=${locale}; path=/; max-age=31536000; samesite=lax`
})
```

- [ ] **Step 5: Re-extract the messages**

Run: `mix gettext.extract --merge`
Expected: the eight Task 8 msgids gain `#:` references; every `msgstr` from Task 7 is kept. Then run `mix gettext.extract --check-up-to-date`. Expected: exits 0.

- [ ] **Step 6: Run the full suite**

Run: `mix compile --warnings-as-errors && mix test`
Expected: compile passes; all tests PASS (previous 21 plus the new ones).

- [ ] **Step 7: Check the page at desktop and mobile widths**

Start the server with the development config (`set -a && . ./.env && set +a && mix phx.server`), open `http://localhost:4000/?lang=es` in the integrated browser, and check at 1280 px and 375 px wide:
- Spanish copy fits the chips, buttons, and the ES/EN switch without wrapping or overflow.
- The sample category chart shows Bebidas and Spanish month labels on the revenue trend ("ene", "feb").
- The footnote reads "…1 USD = 17.8413 MXN." and wraps cleanly.
- Switching to EN and back keeps the demo unlocked and shows the notice.

- [ ] **Step 8: Commit**

```bash
git add lib/jido_codemode_web assets/js/app.js priv/gettext test/jido_codemode_web
git commit -m "Add the ES/EN switch, MXN footnote, localized charts, and locale-aware agent requests"
```

---

### Task 9: Documentation, production configuration, and release

**Files:**
- Modify: `README.md` (Environment and Operations sections)

**Interfaces:**
- Consumes: everything above.
- Produces: the deployed Spanish demo.

- [ ] **Step 1: Document the Spanish demo**

In `README.md`, under `## Environment`, add:

```markdown
### Spanish demo and exchange rate

The page is available in English and Mexican Spanish. The language comes from
`?lang=es|en`, then the `agentic_bi_locale` cookie, then the browser. The ES/EN
switch in the header changes language in place and starts a new conversation.

In Spanish, amounts are in Mexican pesos. At startup the app builds a
read-only copy of `northwind.sqlite` with the three money columns converted and
category and country names translated.

- `FX_USD_MXN`: MXN per 1 USD, for example `17.8413`
- `FX_USD_MXN_DATE`: the rate's date, `YYYY-MM-DD`
- `FX_USD_MXN_SOURCE`: shown in the footnote, for example `Banxico FIX (SuperDev ERP)`

Without a valid `FX_USD_MXN`, the Spanish page shows USD. To update the rate,
change the variables and restart the app. SuperDev ERP records the Banxico FIX
daily (Odoo `res_currency_rate`, company currency MXN, stored as USD per MXN).
```

- [ ] **Step 2: Run the full suite and the gettext check**

Run: `mix compile --warnings-as-errors && mix test && mix gettext.extract --check-up-to-date && mix hex.audit`
Expected: all pass; no advisories.

- [ ] **Step 3: Commit, push, and open the pull request**

```bash
git add README.md
git commit -m "Document the Spanish demo and its exchange-rate settings"
git push -u origin spanish-localization
gh pr create -R TechFoundersMX/jido_codemode --base master --head spanish-localization --title "Spanish (Mexico) copy and responses with MXN figures" --fill
```

- [ ] **Step 4: Set the production exchange rate in Coolify**

With the automation token (`~/.config/superdev/coolify-api-token`) and this Mac's IP on Coolify's API allowlist, create three runtime-only variables on app `cq42xyjofqcw8uhcoiuh4qsc`:

```bash
python3 - <<'PY'
import json, os, urllib.request
tok = open(os.path.expanduser("~/.config/superdev/coolify-api-token")).read().strip()
url = "https://coolify.linguavid.net/api/v1/applications/cq42xyjofqcw8uhcoiuh4qsc/envs"
for key, value in [("FX_USD_MXN", "17.8413"), ("FX_USD_MXN_DATE", "2026-09-28"), ("FX_USD_MXN_SOURCE", "Banxico FIX (SuperDev ERP)")]:
    body = {"key": key, "value": value, "is_preview": False, "is_buildtime": False, "is_runtime": True, "is_literal": True}
    req = urllib.request.Request(url, method="POST", data=json.dumps(body).encode(), headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        print(key, r.status)
PY
```

Expected: `201` for each key. If a key already exists, the API returns an error; update it with `PATCH` on the same URL and the same body instead.

- [ ] **Step 5: Merge and deploy**

Merge the pull request with a rebase (`gh pr merge <number> -R TechFoundersMX/jido_codemode --rebase`). The Coolify webhook deploys `master`. Wait for the deployment to report `finished` and the app status `running:healthy`.

- [ ] **Step 6: Run the manual checks in the integrated browser**

On `https://agentic-bi.superdev.mx` (unlock with the demo password when asked):
- `?lang=es`, ask "Categorías principales por ingresos": Bebidas $4,779,116.56 MXN, Lácteos $4,183,914.82 MXN, Dulces y postres $2,985,870.46 MXN.
- `?lang=en`, ask "Top 3 categories by revenue": Beverages $267,868.18, Dairy Products $234,507.29, Confections $167,357.23.
- On the Spanish page, ask in English "Top 3 categories by revenue": the answer is in English with MXN figures.
- The Spanish revenue trend chart shows Spanish month labels.
- Desktop and mobile widths show no overflow.
```
