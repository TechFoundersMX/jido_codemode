defmodule JidoCodemode.SidebarAgent do
  @moduledoc false

  alias JidoCodemode.Agent.Schema
  alias JidoCodemode.Agent.Tools.BuildReport
  alias JidoCodemode.Agent.Tools.DescribeSchema
  alias JidoCodemode.Agent.Tools.RunSqliteQuery
  alias JidoCodemode.Locale.{Dataset, Glossary}

  @base_system_prompt """
  You are the analysis agent inside Agentic BI.

  Turn business questions into clear, decision-ready analysis. Help the user explore the sample
  dataset, explain important signals, suggest useful follow-up questions, and stay concise.
  If the data does not support a claim, say so.

  Workflow:
  1. Use the schema digest already in context first.
  2. Use describe_schema only when you need more detail about a specific table or join.
  3. Use run_sqlite_query when you need to inspect data and reason about the results directly.
  4. Use BuildReport when the user asks for a report, chart, graph, table, or other structured visual output.
  5. After using BuildReport, give a short assistant message that explains the result.
  6. If a tool returns an error with guidance, fix the tool call and retry instead of ignoring it.

  Use describe_schema when the schema digest is not enough.
  Use run_sqlite_query when you need to inspect real query results before deciding what to show.
  Use BuildReport for multi-step reporting logic and final visual output.
  In BuildReport, write Lua that returns the final report payload as a table; Elixir validates and stores it.

  Never invent database values. Use only data returned by tool calls.

  The BuildReport tool description contains the available Lua APIs and a working example.

  Use plain assistant text without rendering a report when the user only wants a short answer.
  Ask a concise clarification question instead of guessing when the request is ambiguous.
  """

  use Jido.AI.Agent,
    name: "sandbox_agent",
    description: "Analysis agent for Agentic BI",
    model: :fast,
    llm_opts: [temperature: 1.0],
    tools: [DescribeSchema, RunSqliteQuery, BuildReport],
    system_prompt: @base_system_prompt

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
            Glossary.prompt_summary() <>
            ". Use these Spanish names, including in SQL filters. " <>
            "The text in parentheses is only the English original and must not be used in SQL filters."

        :en ->
          "The database stores category and country names in English."
      end

    money =
      case {Dataset.currency("es_MX"), Dataset.fx()} do
        {:mxn, {:ok, fx}} ->
          "Money amounts in the database are already in Mexican pesos (MXN), converted from USD " <>
            "at #{fx.rate} MXN per USD (#{fx.source}, #{fx.date}). Never convert them again. " <>
            "Write amounts as $1,234.56 MXN. In report tables, name money columns with the " <>
            ~s|currency, for example "Ingresos (MXN)".|

        _usd ->
          "Money amounts in the database are in US dollars (USD). Write amounts as $1,234.56 USD."
      end

    """
    Language:
    - The page language is Spanish (Mexico).
    - Answer in the language of the user's question. If the question gives no language signal, answer in Spanish.
    - When you answer in Spanish: use Mexican Spanish with "tú", professional and warm. Give the answer first, then the context. Do not repeat the question. Use "reporte", "gráfica", "ingresos", and "pedidos". Write dates as "28 de septiembre de 2026" or 28/09/2026.
    - #{report_text(~s|AS "Ingresos (MXN)"|)}
    - #{labels}
    - #{money}
    """
  end

  defp language_block(_locale) do
    """
    Language:
    - The page language is English.
    - Answer in the language of the user's question. If the question gives no language signal, answer in English.
    - #{report_text(~s|AS "Revenue"|)}
    - Money amounts in the database are in US dollars (USD). Write amounts as $1,234.56.
    """
  end

  defp report_text(alias_example) do
    "Every string you pass to BuildReport is written in the language of your answer: report and " <>
      "block titles, summaries, metric labels, chart titles, and SQL column aliases used as table " <>
      "headers or axis titles. Alias SQL columns in the language of your answer, for example " <>
      alias_example <> "."
  end

  def recent_tool_calls(agent_pid, limit \\ 10) do
    case Jido.AgentServer.status(agent_pid) do
      {:ok, %{raw_state: raw_state}} ->
        raw_state
        |> Map.get(:__thread__)
        |> case do
          %Jido.Thread{} = thread ->
            thread
            |> Jido.Thread.to_list()
            |> Enum.flat_map(fn
              %{kind: :ai_message, payload: %{tool_calls: tool_calls}} -> tool_calls
              _ -> []
            end)
            |> Enum.take(-limit)

          _ ->
            []
        end

      _ ->
        []
    end
  end
end
