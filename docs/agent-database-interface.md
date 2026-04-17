# Agent / Database Interface

## Goal

Keep the agent loop small and explicit while still allowing the model to produce useful structured outputs.

## Core Boundaries

- The model gets a compact schema digest up front.
- The model can ask for more schema detail through `describe_schema`.
- The model can run read-only SQL through `run_sqlite_query`.
- When it needs multi-step logic, it uses `BuildReport` and writes Lua inside a sandbox.
- Elixir validates the returned payload before any UI rendering happens.

## Tool Surface

### `describe_schema`

Returns structured schema information and semantic notes.

### `run_sqlite_query`

Runs a single read-only `SELECT` or `WITH` query and returns a compact preview.

Guardrails:

- read-only SQLite connection
- single statement only
- only `SELECT` and `WITH`
- bounded rows, columns, cell sizes, and execution time

### `BuildReport`

Runs a short Lua program with three APIs:

- `schema.digest()`
- `db.query(...)`
- `report.*` helpers

The Lua code must return a report payload. Elixir normalizes and validates it into one of these block types:

- text
- metric
- table
- line / bar / donut / scatter chart

## Why Codemode Exists

Simple questions can be answered with normal assistant text.

Codemode is useful when the model needs to:

- run more than one query
- derive intermediate values
- choose chart fields dynamically
- assemble a final structured report instead of plain prose

## Report Contract

Every report must include:

- `version`
- `title`
- `blocks`

Optional fields:

- `summary`

Each block is validated on the server before it is stored or rendered.

## Demo Dataset

This repo ships with a local `northwind.sqlite` database so the sandbox is runnable without any client data.

## Rendering Path

1. The agent returns a validated report.
2. The report is stored in ETS by session id.
3. LiveView fetches the latest report for the session.
4. Tables render directly in HEEx.
5. Chart specs render through `vega-embed` in a colocated hook.
