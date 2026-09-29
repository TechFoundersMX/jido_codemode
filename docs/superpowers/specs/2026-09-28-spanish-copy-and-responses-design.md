# Spanish copy and responses for the Agentic BI demo

Date: 2026-09-28
Status: approved; revised 2026-09-28 during planning (see Revisions)

## Goal

Make the public demo at `https://agentic-bi.superdev.mx` work fully in Spanish
(Mexico) while keeping English. When the demo is in Spanish, the interface,
the agent's answers, generated reports, and all money figures are in Spanish
and in Mexican pesos (MXN).

## Decisions

| Topic | Decision |
| --- | --- |
| Languages | Bilingual: Spanish (Mexico, `es_MX`) and English (`en`). |
| Initial language | Chosen in this order: `?lang=` parameter, then the saved cookie, then the browser's `Accept-Language` (`es*` → `es_MX`), otherwise English. |
| Switching | An ES/EN switch in the header. It changes language in place (LiveView event, no page reload), saves the cookie, and updates `<html lang>`. The demo stays unlocked. |
| Voice | Mexican Spanish, *tú*, professional and warm. |
| Answer language | The agent mirrors the language of each question. It uses the page language only when the question gives no signal (for example "top 5?"). |
| Currency | Follows the page language, not the answer language. Spanish page: MXN. English page: USD. |
| Data labels | A fixed, reviewed glossary translates the 8 categories and 25 countries. Product, customer, and shipper names are proper nouns and are not translated. |
| Out of scope | Localized share previews (Open Graph tags and image), separate `/es` and `/en` routes, translating product or company names, and a daily automatic exchange-rate sync. |

## Architecture

The design follows Phoenix's standard `gettext` approach (approach A). It adds
five small units and changes the agent and query paths so that they receive
the page language.

### Units

| Unit | Responsibility | Depends on |
| --- | --- | --- |
| `JidoCodemodeWeb.Locale` (plug and LiveView `on_mount` hook) | Resolves the language in the order above. Sets the `Gettext` locale, stores the locale in the session, and exposes it for `<html lang>`. | Phoenix, `Gettext` |
| `priv/gettext/{en,es_MX}` | All interface copy (about 60 strings), the 5 example prompts, sample chart titles and axis labels, the unlock and error messages, the currency footnote, and page metadata. English source text stays in the templates. | `gettext` |
| `JidoCodemode.Locale.Glossary` | One reviewed English → Spanish map for categories and countries. It is used to build the Spanish database copy and in the agent instructions. | none |
| `JidoCodemode.Locale.Format` | Formats money, percentages, numbers, and dates per locale. | none |
| `JidoCodemode.Locale.Dataset` | Holds the exchange-rate configuration and builds the Spanish copy of the database at startup: money columns converted to MXN and category and country names translated. Exposes `path(locale)`, `currency(locale)`, and `fx()`. | `Exqlite`, `Glossary` |

### Data flow

1. A browser request arrives. `Locale` resolves the language and puts it in the
   session.
2. The LiveView `on_mount` hook reads it. The page renders in that language.
3. When the agent starts, and again whenever the language changes,
   `SidebarAgent.system_prompt(locale)` sets its instructions.
4. Each question passes the locale to the tools in `tool_context`. The query
   tools (`run_sqlite_query`, `BuildReport`, `describe_schema`) choose the USD
   database for English or the MXN database for Spanish.
5. The Spanish database copy already stores Spanish category and country
   names, so query results, the agent's prose, tables, and charts all use them
   with no post-processing, and a filter such as `WHERE CategoryName =
   'Bebidas'` works.
6. `Format` renders money, percentages, and dates for the page locale. The Vega
   charts receive Spanish number and time locales when the page is Spanish.

## Currency: MXN in the Spanish demo

The principle: convert the data, not the answers. Neither the model nor the
report code does currency arithmetic on results.

- Northwind has exactly three money columns: `Order.Freight`,
  `Product.UnitPrice`, and `OrderDetail.UnitPrice`. `OrderDetail.Discount` is a
  fraction and does not change.
- At startup, `Dataset` copies `northwind.sqlite` to a temporary file,
  multiplies those three columns by the USD → MXN rate, replaces the category
  and country names with their glossary translations, and marks the file
  read-only. Queries open it read-only, the same way as the original.
- All query paths already open the database through one function
  (`database_path/0` in `QueryRunner` and `Schema`). It takes the locale and
  returns the matching path.
- The rate is configuration, set by runtime environment variables:

  | Variable | Initial value |
  | --- | --- |
  | `FX_USD_MXN` | `17.8413` |
  | `FX_USD_MXN_DATE` | `2026-09-28` |
  | `FX_USD_MXN_SOURCE` | `FIX de Banxico` |

  The initial value is the Banxico FIX for 28 Sep 2026, read from SuperDev ERP
  (Odoo `res_currency_rate` id 205, stored as 0.05604972731807659 USD per MXN).
  To update it, change the variables and restart the app.
- Display: Spanish amounts in text and metrics show as `$4,779,116.56 MXN`.
  English amounts stay `$267,868.18` (USD). Mexico uses the same digit grouping
  and decimal point as the US; only the currency label changes. Chart axes show
  `$` without the `MXN` suffix, which is too long for tick labels; the footnote
  states the currency. Table columns carry no type, so numeric cells get digit
  grouping and 2 decimals in both languages, and the agent names money columns
  with the currency, for example "Ingresos (MXN)".
- The four sample charts on the page use illustrative data defined in code, not
  the database. In Spanish, their labels are translated through `gettext` and
  their amounts are multiplied by the rate.
- A footnote shows under the chat and reports in Spanish:
  *"Cifras en pesos mexicanos (MXN), convertidas de USD con el tipo de cambio
  FIX de Banxico del 28/09/2026: 1 USD = 17.8413 MXN."*
  The Northwind orders are from the 1990s, so the conversion is for
  readability, not historical accuracy.
- The Spanish language block tells the agent that amounts are already in MXN
  and must not be converted again. Correctness does not depend on the agent
  following this.

## Agent behaviour

- `SidebarAgent.system_prompt(locale)` returns the existing instructions plus a
  language block that states:
  - the page language, and the mirror-the-question rule
  - the voice: Mexican Spanish, *tú*, professional; answer first, then context;
    do not repeat the question; ask a one-line clarifying question when the
    request is ambiguous
  - the glossary for categories and countries
  - the currency rule for the page locale
  - the date style: "28 de septiembre de 2026", `28/09/2026`
- Report titles, summaries, and column headers are written by the agent, so
  they follow the answer language. The Lua examples in the `BuildReport` tool
  description stay in English; they are instructions to the model.
- Switching language starts a new conversation and keeps the demo unlocked.
  This prevents earlier USD answers from mixing with new MXN answers. A short
  note in the chat explains the change, for example
  *"Cambiaste a español. Las cifras ahora están en MXN."*

## Copy and voice

### Voice rules (interface and agent)

- *Tú*, professional and warm: "Pregúntale al agente…".
- Mexican terms: *reporte* (not "informe"), *gráfica* (not "gráfico"),
  *ingresos* for revenue, *pedidos* for orders, *tipo de cambio*.
- Full sentences end with a period. No emojis anywhere.
- Spanish runs 15–30% longer than English. Buttons and chips are checked at
  mobile widths.
- Dates: "28 de septiembre de 2026" in full, `28/09/2026` numeric, lowercase
  month abbreviations on chart axes ("ene", "feb").

### Key interface copy

| English | Spanish |
| --- | --- |
| Turn business questions into clear analysis | Convierte preguntas de negocio en análisis claros |
| Explore your data with an agent that can query, compare, visualize, and explain its findings. | Explora tus datos con un agente que consulta, compara, visualiza y explica lo que encuentra. |
| Your analysis will appear here | Aquí aparecerá tu análisis |
| Ask the analysis agent for a chart, table, metric, or complete report. | Pídele al agente una gráfica, una tabla, una métrica o un reporte completo. |
| Analysis agent | Agente de análisis |
| Ready / Locked | Listo / Bloqueado |
| Revenue trend · Top categories · More | Tendencia de ingresos · Categorías principales · Más |
| Ask about revenue, customers, products, or trends | Pregunta sobre ingresos, clientes, productos o tendencias |
| Connected with read-only access | Conectado con acceso de solo lectura |
| Send · Analyzing… | Enviar · Analizando… |
| Enter the password to unlock the analysis agent. | Escribe la contraseña para activar el agente de análisis. |
| That password is not correct. | Esa contraseña no es correcta. Revísala e inténtalo de nuevo. |

The remaining strings follow the same rules.

### Data glossary

Categories:

| English | Spanish |
| --- | --- |
| Beverages | Bebidas |
| Condiments | Condimentos |
| Confections | Dulces y postres |
| Dairy Products | Lácteos |
| Grains/Cereals | Granos y cereales |
| Meat/Poultry | Carnes y aves |
| Produce | Frutas y verduras |
| Seafood | Pescados y mariscos |

Countries (all 25 values in the data):

| English | Spanish | English | Spanish |
| --- | --- | --- | --- |
| Argentina | Argentina | Italy | Italia |
| Australia | Australia | Japan | Japón |
| Austria | Austria | Mexico | México |
| Belgium | Bélgica | Netherlands | Países Bajos |
| Brazil | Brasil | Norway | Noruega |
| Canada | Canadá | Poland | Polonia |
| Denmark | Dinamarca | Portugal | Portugal |
| Finland | Finlandia | Singapore | Singapur |
| France | Francia | Spain | España |
| Germany | Alemania | Sweden | Suecia |
| Ireland | Irlanda | Switzerland | Suiza |
| UK | Reino Unido | USA | Estados Unidos |
| Venezuela | Venezuela | | |

## Error handling

- Rate missing or invalid (`FX_USD_MXN` unset, not a number, or not positive):
  the Spanish page falls back to USD and USD labels. The footnote reads
  *"Cifras en dólares estadounidenses (USD)."* A warning is logged. The demo
  keeps working and never shows a currency label that is wrong. The currency
  is decided once, by `Dataset`, and every consumer reads that decision: the
  query tools, `Format`, the footnote, and the agent's language block (which
  then states USD instead of MXN).
- The MXN database fails to build at startup: the same fallback, with an error
  in the log.
- A value that is not in the glossary stays in English.
- A missing Spanish translation shows the English text. A test prevents this
  from shipping.

## Testing

Automated:

- Locale resolution: `?lang` beats the cookie, the cookie beats
  `Accept-Language`; `es-MX` and `es-ES` resolve to `es_MX`; a missing or
  unsupported header resolves to English.
- Glossary and `Format`: MXN and USD amounts, percentages, and dates in both
  languages.
- MXN database: only the three money columns change, each by exactly the rate;
  the copy is read-only; with the rate missing or invalid, the app falls back
  to USD.
- LiveView: Spanish copy renders for a Spanish browser; the switch changes
  language without a reload and keeps the demo unlocked; `<html lang>` updates;
  switching starts a new conversation with the explanatory note.
- Agent: `system_prompt(:es_MX)` contains the mirror rule, the glossary, and the
  MXN rule. A stub-server test proves that a Spanish session queries the MXN
  database.
- Spanish database copy: category and country names are translated; product,
  customer, and shipper names are unchanged.
- Translations: `mix gettext.extract --check-up-to-date` passes, and no
  `es_MX` entry has an empty `msgstr`.

Manual, after deploy (integrated browser, desktop and mobile widths):

- Spanish, "Categorías principales por ingresos": Bebidas $4,779,116.56 MXN,
  Lácteos $4,183,914.82 MXN, Dulces y postres $2,985,870.46 MXN.
- English, "Top 3 categories by revenue": Beverages $267,868.18, Dairy Products
  $234,507.29, Confections $167,357.23 (unchanged).
- An English question on the Spanish page gets an English answer with MXN
  figures.
- A Vega chart on the Spanish page shows Spanish month labels.

## Rollout

1. One pull request with the implementation and tests.
2. Set `FX_USD_MXN`, `FX_USD_MXN_DATE`, and `FX_USD_MXN_SOURCE` in Coolify
   (runtime only) through the API.
3. Merge, which deploys through the Coolify webhook.
4. Run the manual checks above.

## Revisions

Made while writing the implementation plan, after reading the code:

1. Category and country names are translated in the Spanish database copy, not
   after report validation. `Report.normalize/1` builds the Vega chart specs
   itself, so post-processing would have to rewrite chart JSON, and the agent's
   `WHERE` filters on Spanish names would not match an English database.
2. The sample charts use illustrative data defined in code. Their labels go
   through `gettext` and their amounts are multiplied by the rate.
3. Chart axes in Spanish show `$` without `MXN`. Table money columns are named
   with the currency by the agent, because table columns carry no type.

