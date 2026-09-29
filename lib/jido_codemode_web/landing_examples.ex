defmodule JidoCodemodeWeb.LandingExamples do
  @moduledoc """
  The landing's example questions, with answers the agent gave on the bundled
  Northwind sample (a fictitious distributor).

  Amounts are stored in USD exactly as the queries returned them and converted
  with the same rate as the demo's Spanish database, so the landing and the live
  agent always show the same pesos. Each answer sentence is a claim about these
  numbers; `test/jido_codemode_web/landing_examples_test.exs` checks them.
  """

  use Gettext, backend: JidoCodemodeWeb.Gettext

  alias JidoCodemode.Locale.{Dataset, Format}

  # 2013 monthly revenue, January to December.
  @trend [
    61_258.07,
    38_483.64,
    38_547.22,
    53_032.95,
    53_781.29,
    36_362.80,
    51_020.86,
    47_287.67,
    55_629.24,
    66_749.23,
    43_533.81,
    71_398.43
  ]
  # Unrounded sums, so converting to MXN gives the exact cents the agent returns on
  # the Spanish database (it converts each line before summing).
  @categories [beverages: 267_868.18, dairy: 234_507.285, confections: 167_357.225]
  @shippers [
    {"United Package", 533_547.63},
    {"Federal Shipping", 383_405.47},
    {"Speedy Express", 348_839.94}
  ]
  @customers [
    {"QUICK-Stop", 110_277.30},
    {"Ernst Handel", 104_874.98},
    {"Save-a-lot Markets", 104_361.95},
    {"Rattlesnake Canyon Grocery", 51_097.80},
    {"Hungry Owl All-Night Grocers", 49_979.90}
  ]
  @order_value [{2012, 1_368.97}, {2013, 1_512.46}, {2014, 1_631.94}]
  @countries [
    usa: 245_584.61,
    germany: 230_284.63,
    austria: 128_003.84,
    brazil: 106_925.78,
    france: 81_358.32
  ]

  @hero_ids ~w(categories trend shippers customers)

  @doc "Raw figures, in USD, for tests that check the answer sentences."
  def data do
    %{
      trend: @trend,
      categories: @categories,
      shippers: @shippers,
      customers: @customers,
      order_value: @order_value,
      countries: @countries
    }
  end

  @doc "All six gallery examples, localized."
  @spec all(String.t()) :: [map()]
  def all(locale) do
    rate = Dataset.rate(locale)

    [
      trend(locale, rate),
      categories(rate),
      shippers(),
      customers(rate),
      order_value(rate),
      countries(rate)
    ]
  end

  @doc "The four examples the hero cycles through, in order."
  @spec hero(String.t()) :: [map()]
  def hero(locale) do
    by_id = Map.new(all(locale), &{&1.id, &1})
    Enum.map(@hero_ids, &Map.fetch!(by_id, &1))
  end

  @doc "The saved agent answer shown in «Pruébalo»: top 3 categories, full amounts."
  @spec replay(String.t()) :: map()
  def replay(locale) do
    rate = Dataset.rate(locale)
    currency = Dataset.currency(locale)

    rows =
      Enum.map(@categories, fn {key, usd} ->
        %{name: category_name(key), amount: Format.money(round2(usd * rate), currency)}
      end)

    [a, b, c] = rows

    %{
      question: gettext("What are the top 3 categories by revenue?"),
      answer:
        gettext(
          "The top 3 categories by revenue are %{first} (%{first_amount}), %{second} (%{second_amount}) and %{third} (%{third_amount}).",
          first: a.name,
          first_amount: a.amount,
          second: b.name,
          second_amount: b.amount,
          third: c.name,
          third_amount: c.amount
        ),
      amount_column:
        if(currency == :mxn, do: gettext("Revenue (MXN)"), else: gettext("Revenue (USD)")),
      rows: rows
    }
  end

  defp trend(locale, rate) do
    %{
      id: "trend",
      type: :line,
      tone: 1,
      kind: gettext("Trend"),
      question: gettext("Show the monthly revenue trend for 2013."),
      answer: gettext("December was the best month of the year, and October the second."),
      chart: line_chart(Enum.map(@trend, &(&1 * rate)), months(locale))
    }
  end

  defp categories(rate) do
    %{
      id: "categories",
      type: :bars,
      tone: 2,
      kind: gettext("Comparison"),
      question: gettext("Which 3 categories sell the most?"),
      answer: gettext("Beverages leads, followed by Dairy Products and Confections."),
      chart: bars(Enum.map(@categories, fn {key, usd} -> {category_name(key), usd * rate} end))
    }
  end

  defp shippers do
    total = @shippers |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      id: "shippers",
      type: :donut,
      tone: 3,
      kind: gettext("Mix"),
      question: gettext("How is revenue split by shipper?"),
      answer: gettext("United Package carries 42% of revenue."),
      chart: donut(@shippers, total)
    }
  end

  defp customers(rate) do
    %{
      id: "customers",
      type: :table,
      tone: 4,
      kind: gettext("Ranking"),
      question: gettext("List the top 5 customers by revenue."),
      answer: gettext("Three customers bring in a quarter of revenue."),
      chart:
        @customers
        |> Enum.with_index(1)
        |> Enum.map(fn {{name, usd}, rank} ->
          %{rank: rank, name: name, value: short_money(usd * rate)}
        end)
    }
  end

  defp order_value(rate) do
    %{
      id: "order-value",
      type: :kpis,
      tone: 5,
      kind: gettext("KPI"),
      question: gettext("How did the average order value change by year?"),
      answer: gettext("It rose every year: 19% from 2012 to 2014."),
      chart:
        @order_value
        |> Enum.with_index()
        |> Enum.map(fn {{year, usd}, index} ->
          delta =
            if index > 0 do
              {_year, previous} = Enum.at(@order_value, index - 1)
              "+" <> :erlang.float_to_binary((usd / previous - 1) * 100, decimals: 1) <> "%"
            end

          %{year: year, value: "$" <> Format.number(round(usd * rate)), delta: delta}
        end)
    }
  end

  defp countries(rate) do
    %{
      id: "countries",
      type: :bars,
      tone: 1,
      kind: gettext("Geography"),
      question: gettext("Which countries do we sell the most in?"),
      answer: gettext("The USA and Germany account for more than a third of revenue."),
      chart: bars(Enum.map(@countries, fn {key, usd} -> {country_name(key), usd * rate} end))
    }
  end

  defp category_name(:beverages), do: gettext("Beverages")
  defp category_name(:dairy), do: gettext("Dairy Products")
  defp category_name(:confections), do: gettext("Confections")

  defp country_name(:usa), do: gettext("USA")
  defp country_name(:germany), do: gettext("Germany")
  defp country_name(:austria), do: gettext("Austria")
  defp country_name(:brazil), do: gettext("Brazil")
  defp country_name(:france), do: gettext("France")

  defp months("es_MX"), do: ~w(ene feb mar abr may jun jul ago sep oct nov dic)
  defp months(_locale), do: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  defp bars(rows) do
    max = rows |> Enum.map(&elem(&1, 1)) |> Enum.max()

    Enum.map(rows, fn {label, value} ->
      %{label: label, width: Float.round(value / max * 100, 1), value: short_money(value)}
    end)
  end

  @donut_radius 40
  defp donut(rows, total) do
    circumference = 2 * :math.pi() * @donut_radius

    {segments, _offset} =
      rows
      |> Enum.with_index()
      |> Enum.map_reduce(0.0, fn {{label, value}, index}, offset ->
        length = value / total * circumference

        segment = %{
          label: label,
          share: round(value / total * 100),
          tone: Enum.at([3, 1, 2], index),
          dasharray: "#{Float.round(length, 1)} #{Float.round(circumference, 1)}",
          dashoffset: Float.round(-offset, 1),
          delay: index * 0.12
        }

        {segment, offset + length}
      end)

    %{radius: @donut_radius, segments: segments}
  end

  # SVG geometry for a 300×130 line chart with y ticks at 0, half and max.
  @w 300
  @h 130
  @pad_left 48
  @pad_bottom 18
  @pad_top 8
  defp line_chart(values, month_labels) do
    max = Enum.max(values) * 1.1
    last = length(values) - 1
    x = fn i -> @pad_left + i * (@w - @pad_left - 6) / last end
    y = fn v -> @pad_top + (@h - @pad_top - @pad_bottom) * (1 - v / max) end

    points = values |> Enum.with_index() |> Enum.map(fn {v, i} -> {x.(i), y.(v)} end)

    path =
      points
      |> Enum.with_index()
      |> Enum.map_join(" ", fn {{px, py}, i} ->
        if(i == 0, do: "M", else: "L") <> "#{r1(px)} #{r1(py)}"
      end)

    length =
      points
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{x1, y1}, {x2, y2}] -> :math.sqrt((x2 - x1) ** 2 + (y2 - y1) ** 2) end)
      |> Enum.sum()

    %{
      width: @w,
      height: @h,
      path: path,
      area: path <> " L#{r1(x.(last))} #{r1(y.(0))} L#{r1(x.(0))} #{r1(y.(0))} Z",
      length: round(length),
      points: Enum.map(points, fn {px, py} -> %{x: r1(px), y: r1(py)} end),
      ticks:
        Enum.map([0, 0.5, 1], fn fraction ->
          %{y: r1(y.(max * fraction)), label: short_money(max * fraction)}
        end),
      grid_x2: @w,
      x_labels:
        for {label, i} <- Enum.with_index(month_labels), rem(i, 2) == 0 do
          %{x: r1(x.(i) - 8), y: @h - 2, label: label}
        end
    }
  end

  @doc false
  def short_money(value) when value >= 1_000_000,
    do: "$" <> :erlang.float_to_binary(value / 1_000_000, decimals: 2) <> " M"

  def short_money(value), do: "$" <> Format.number(round(value / 1000)) <> " k"

  defp r1(value), do: Float.round(value * 1.0, 1)
  defp round2(value), do: Float.round(value, 2)
end
