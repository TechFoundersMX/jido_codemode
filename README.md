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

### SuperDev AI Gateway mode

Instead of holding an OpenCode key, the app can call OpenCode through the
SuperDev AI Gateway (`TechFoundersMX/monorepo`, `docs/ai-gateway.md`). The
gateway injects its stored OpenCode key, so the app must not send one.

- `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET` enable gateway mode; set
  both or neither. Use a Cloudflare Access service token created for this
  service and environment.
- `AI_GATEWAY_DOMAIN` defaults to `gateway.superdev.mx`
- `AI_GATEWAY_KEY_ALIAS` defaults to `production`
- `OPENCODE_BASE_URL` defaults to `https://<AI_GATEWAY_DOMAIN>/opencode/v1` and
  must stay on the gateway domain

In gateway mode the app refuses to boot if `OPENCODE_API_KEY` or
`OPENAI_API_KEY` is also set, because a request-supplied key overrides the
gateway's stored key. ReqLLM omits the `Authorization` header through the model
spec's `openai_compatible_backend: :ollama` marker, whose only effect in ReqLLM
1.10 is to permit a missing API key.

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
