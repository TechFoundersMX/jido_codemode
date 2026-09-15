# Agentic BI

Agentic BI turns business questions into clear, decision-ready analysis. The Phoenix demo can inspect a dataset, run guarded read-only queries, and build validated reports with metrics, tables, and charts.

## What It Shows

- A focused analysis agent with a small, bounded tool surface
- A sandboxed runtime for multi-step report generation
- Read-only SQLite access with bounded previews and hard limits
- Elixir-side validation before results reach the interface
- LiveView rendering for text, metrics, tables, and Vega charts

## Analysis Workflow

1. Ask a business question.
2. The agent inspects the available schema and runs bounded queries.
3. Agentic BI builds and validates the resulting analysis.
4. LiveView presents the metrics, tables, charts, and explanation.

## Stack

- Elixir + Phoenix LiveView
- Jido + Jido AI
- Lua sandboxing via `lua`
- SQLite via `exqlite`
- Charts via `tucan` + `vega_lite`

## Setup

```bash
mix setup
mix phx.server
```

The app runs at `http://localhost:4000`.

## Environment

- `OPENCODE_API_KEY` enables live model calls for the chat demo
- `OPENCODE_BASE_URL` defaults to `https://opencode.ai/zen/go/v1`
- `OPENCODE_MODEL` defaults to `gpt-5.6-luna` (Responses API)
- `DEMO_PASSWORD` locks the analysis agent behind a password while leaving the public page and OG image accessible

If `OPENCODE_API_KEY` is unset, the app still boots and the static demo remains available, but live chat requests will fail.

Chat requests send `x-opencode-session` with a random ID for each agent conversation.
The ID stays the same across turns, tool calls, and retries. Starting a new chat
agent creates a new ID. This header is passed through Jido's `req_http_options`;
ReqLLM does not add it automatically.

## Tests

```bash
mix test
```

## Docs

See `docs/agent-database-interface.md` for the runtime boundaries and report contract.
