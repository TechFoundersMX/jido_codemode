# Jido Codemode

Open source Phoenix demo of a Jido agent that can switch into codemode, write short Lua programs in a sandbox, query SQLite through a guarded interface, and render validated reports in LiveView.

## Background

This repo is inspired by Cloudflare's original codemode article:

- [Code Mode: the better way to use MCP](https://blog.cloudflare.com/code-mode/)

## What It Shows

- A small tool surface: `describe_schema`, `run_sqlite_query`, and `BuildReport`
- A sandboxed Lua runtime for multi-step report generation
- Read-only SQLite access with bounded previews and hard limits
- Elixir-side validation of report payloads before rendering
- LiveView rendering for text, metrics, tables, and Vega charts

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
- `OPENCODE_BASE_URL` defaults to `https://opencode.ai/zen/v1`
- `OPENCODE_MODEL` defaults to `gpt-5.4-mini`

If `OPENCODE_API_KEY` is unset, the app still boots and the static demo remains available, but live chat requests will fail.

## Tests

```bash
mix test
```

## Docs

See `docs/agent-database-interface.md` for the runtime boundaries and report contract.
