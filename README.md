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
1.25 is to permit a missing API key.

Chat requests send `x-opencode-session` with a random ID for each agent conversation.
The ID stays the same across turns, tool calls, and retries. Starting a new chat
agent creates a new ID. This header is passed through Jido's `req_http_options`;
ReqLLM does not add it automatically.

## Operations

### Deployment

- Production runs on Coolify as `jido_codemode:master` at
  `https://agentic-bi.superdev.mx`. A push to `master` triggers a deploy through
  the Coolify webhook. An environment variable change alone needs a manual
  redeploy.
- `GET /health` returns `ok`. Coolify's container health check calls it through
  `curl`, which the runtime image installs. `force_ssl` excludes `localhost`,
  so the in-container check is not redirected to HTTPS.
- The image builds on Elixir 1.20 / OTP 27, the same toolchain as `devenv.nix`.

### AI Gateway credentials

This service uses one provider through the SuperDev AI Gateway: OpenCode Go at
`/opencode` (model `gpt-5.6-luna` through the Responses API). Each environment
has its own Cloudflare Access service token and Service Auth policy on the
"SuperDev AI Gateway" Access application. Both are listed in
`cloudflare/ai-gateway/gateway.config.js` in `TechFoundersMX/monorepo`.

| Environment | Token and policy name | Expires | Where the secret is stored |
| --- | --- | --- | --- |
| Development | `agentic-bi development` | 2027-09-26 | Developer's local `.env` (gitignored) |
| Production | `agentic-bi production` | 2027-09-28 | Coolify app env, `CF_ACCESS_CLIENT_SECRET` locked, runtime only |

Owner: SuperDev, Cloudflare Zero Trust (Superdev account). Never commit a token
value. To rotate, use **Rotate secret** on the token in Zero Trust → Access
controls → Service credentials. Update the stored secret, redeploy, and verify
with the command below. The client ID and policy do not change.

Verification: the request below lists models without running inference.
`HTTP 200` means the domain, Access token, BYOK alias, and upstream provider
all work. A `302` to a Cloudflare Access login means the token or secret is
wrong, or the token has no policy on the gateway application.

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" \
  -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET" \
  -H 'cf-aig-byok-alias: production' \
  https://gateway.superdev.mx/opencode/v1/models
```

OpenCode Go rejects model requests that have no `x-opencode-session` header
(`400 MissingSessionID`). The model-list request above does not need it.

## Tests

```bash
mix test
```

## Docs

See `docs/agent-database-interface.md` for the runtime boundaries and report contract.
