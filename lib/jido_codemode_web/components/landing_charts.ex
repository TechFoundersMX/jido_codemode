defmodule JidoCodemodeWeb.LandingCharts do
  @moduledoc """
  Small server-rendered charts for the landing's examples (no chart library).

  They render in their final state, so they read fine without JavaScript; the
  landing's hooks add a `play` class to animate them in (see `landing.css`).
  """

  use Phoenix.Component

  attr :example, :map, required: true

  def viz(%{example: %{type: :bars}} = assigns) do
    ~H"""
    <div class="bars">
      <div :for={{row, i} <- Enum.with_index(@example.chart, 1)} class="bar">
        <span class="lbl">{row.label}</span>
        <span class="track">
          <span class={"fill c#{i}"} style={"--w:#{row.width}%"}></span>
          <span class="val">{row.value}</span>
        </span>
      </div>
    </div>
    """
  end

  def viz(%{example: %{type: :line}} = assigns) do
    ~H"""
    <svg
      class="chart"
      viewBox={"0 0 #{@example.chart.width} #{@example.chart.height}"}
      aria-hidden="true"
      focusable="false"
    >
      <g :for={tick <- @example.chart.ticks}>
        <line class="gridline" x1="48" x2={@example.chart.grid_x2} y1={tick.y} y2={tick.y} />
        <text x="0" y={tick.y + 3}>{tick.label}</text>
      </g>
      <path class="area" d={@example.chart.area} />
      <path class="line" style={"--len:#{@example.chart.length}"} d={@example.chart.path} />
      <circle :for={point <- @example.chart.points} class="pt" r="2.6" cx={point.x} cy={point.y} />
      <text :for={label <- @example.chart.x_labels} x={label.x} y={label.y}>{label.label}</text>
    </svg>
    """
  end

  def viz(%{example: %{type: :donut}} = assigns) do
    ~H"""
    <div class="donut">
      <svg viewBox="0 0 120 120" aria-hidden="true" focusable="false">
        <circle class="base" r={@example.chart.radius} cx="60" cy="60" />
        <circle
          :for={segment <- @example.chart.segments}
          class={"seg t#{segment.tone}"}
          r={@example.chart.radius}
          cx="60"
          cy="60"
          stroke-dasharray={segment.dasharray}
          stroke-dashoffset={segment.dashoffset}
          style={"animation-delay:#{segment.delay}s"}
        />
      </svg>
      <ul class="legend">
        <li :for={segment <- @example.chart.segments} class={"t#{segment.tone}"}>
          <i></i><span>{segment.label}</span><span class="v">{segment.share}%</span>
        </li>
      </ul>
    </div>
    """
  end

  def viz(%{example: %{type: :table}} = assigns) do
    ~H"""
    <table class="mini-table">
      <tbody>
        <tr :for={row <- @example.chart}>
          <td class="rank">{row.rank}</td>
          <td>{row.name}</td>
          <td class="r">{row.value}</td>
        </tr>
      </tbody>
    </table>
    """
  end

  def viz(%{example: %{type: :kpis}} = assigns) do
    ~H"""
    <div class="kpis">
      <div :for={kpi <- @example.chart}>
        <span class="y">{kpi.year}</span>
        <span class="k">{kpi.value}</span>
        <span class="d">{kpi.delta || " "}</span>
      </div>
    </div>
    """
  end
end
