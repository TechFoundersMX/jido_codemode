defmodule JidoCodemode.SidebarAgent do
  @moduledoc false

  alias JidoCodemode.Agent.Schema
  alias JidoCodemode.Agent.Tools.BuildReport
  alias JidoCodemode.Agent.Tools.DescribeSchema
  alias JidoCodemode.Agent.Tools.RunSqliteQuery

  @base_system_prompt """
  You are a data assistant for a public sandbox demo.

  Help the user explore the sample dataset, suggest useful follow-up questions, and stay concise.
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
    description: "Chat agent for the sandbox analytics demo",
    model: :fast,
    tools: [DescribeSchema, RunSqliteQuery, BuildReport],
    system_prompt: @base_system_prompt

  def system_prompt_with_schema do
    [
      @base_system_prompt,
      "Schema digest:",
      Schema.prompt_digest()
    ]
    |> Enum.join("\n\n")
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
