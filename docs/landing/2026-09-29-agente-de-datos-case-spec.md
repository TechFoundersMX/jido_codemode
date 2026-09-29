# /projects/agente-de-datos: content spec to match the Agentic BI demo

**For:** SITE, which implements this in the superdev.mx repo and ships on Alex's word. Jido doesn't edit that repo.
**From:** Jido (Agentic BI), 29 Sep 2026, at Alex's request (relayed by SITE).
**Rules:** tú; no em dashes or exclamation marks; canonical CTAs; numbers only from `catalogo-indicadores`; never name the client (the case is «Agente de Datos»).

## 1. How the case should read (Alex decides)

**Recommendation: keep it as the real client case, framed as "Agentic BI in production".** Don't merge it into the demo story.

- The demo runs on fictitious data, and the case is the proof it works on real data. Merging the two would blur the one thing each must make clear: the demo is not a client, and the case is not a demo.
- The case keeps its catalog numbers exactly as approved: 42 users, the agent live in < 2 months, the full project in 16 weeks with 12 deliverables, ERP Dynamics 365.
- What changes is the framing and the links. The case explains that the agent in the Agentic BI demo is the one a real distributor uses, and points to the demo to try it.

## 2. Copy

### Eyebrow
- ES: «Caso · Agentic BI en producción · Distribución»
- EN: "Case · Agentic BI in production · Distribution"

### H1 (keeps the approved proof number)
- ES: «42 personas le preguntan a los datos del negocio como hablan»
- EN: "42 people ask the business's data the way they talk"

### Lede
- ES: «Lo que ves en la demo de Agentic BI, conectado a los datos reales de una distribuidora en Dynamics 365. Del repartidor al director general, consultan ventas, clientes y productos en lenguaje natural, también desde el celular.»
- EN: "What you see in the Agentic BI demo, connected to a distributor's real data in Dynamics 365. From delivery drivers to the CEO, they query sales, customers and products in plain language, from their phones too."

### Visión general / Overview
- ES: «Una distribuidora con su operación en Dynamics 365 necesitaba que todas las áreas trabajaran con el mismo número sin pedir reportes. Conectamos sus datos una vez y pusimos encima un agente: la misma experiencia que la demo de Agentic BI, con sus datos y sus permisos.»
- EN: "A distributor running its operation on Dynamics 365 needed every team to work from the same number without requesting reports. We connected its data once and put an agent on top: the same experience as the Agentic BI demo, with its own data and permissions."

### El reto / The challenge
- ES: «Cada reporte dependía de una persona que sabía sacar la información. Los datos estaban en el ERP, pero llegaban por Excel y WhatsApp, tarde y con una versión distinta por área.»
- EN: "Every report depended on the one person who knew how to pull it. The data lived in the ERP, but it arrived through Excel and WhatsApp, late, with a different version per team."

### Nuestra solución / Our solution
- ES: «Conectamos Dynamics 365 en modo de solo lectura, definimos cada indicador con su dueño y construimos el agente: preguntas en español y respuestas con el número, la gráfica y la tabla. Cada respuesta se puede fijar en un tablero personal y actualizarse con datos del día. El proyecto completo incluyó gobernanza y capacitación para que el equipo lo opere.»
- EN: "We connected Dynamics 365 read-only, defined every KPI with its owner, and built the agent: questions in plain language, answers with the number, the chart and the table. Any answer can be pinned to a personal dashboard and refreshed with current data. The full project included governance and training so the team runs it."

### Impacto / Impact (7, the same facts as today, reworded; no "ETL")
| # | ES | EN |
|---|---|---|
| 1 | 42 personas con acceso en lenguaje natural a los datos del negocio | 42 people with plain-language access to business data |
| 2 | Respuestas al momento, sin pedir reportes | Instant answers, no report requests |
| 3 | Tableros personales con respuestas fijadas | Personal dashboards with pinned answers |
| 4 | En web y en el celular | On the web and on mobile |
| 5 | Agente en vivo en menos de 2 meses | Agent live in under 2 months |
| 6 | Proyecto completo: 16 semanas y 12 entregables formales | Full project: 16 weeks and 12 formal deliverables |
| 7 | El equipo del cliente opera la carga de datos y recibió el catálogo de indicadores | The client's team runs the data loads and received the KPI catalog |

## 3. CTAs
- Primary (canon): «Agenda tu llamada exploratoria» / "Book your exploratory call" → `https://superdev.mx/calendar/`, "30 min · gratis · sin compromiso".
- Secondary: «Ver demo en vivo» / "See the live demo" → **`https://agentic-bi.superdev.mx/`**, the landing, not `/demo`. Since invitations went live, `/demo` sends anyone without an invitation straight to the request form. The landing gives the context first: examples, the saved answer, and the way in.
- Remove «Visitar sitio» → lucava.superdev.mx.
- Add a line in «Nuestra solución» or below Impacto: «Pruébalo con datos de ejemplo» → `https://agentic-bi.superdev.mx/#pruebalo`. Optional; skip it if the page already has two CTAs close by.

## 4. Image
**Recommendation: replace it with a capture of the Agentic BI demo on sample data.** Don't keep the redacted client screenshot.

- The redacted shot is still the client's product. Its logo icon is a trace Alex asked to remove, and any leftover detail becomes a privacy risk. A demo capture carries neither.
- It also ties the case visually to the demo the page now points to.
- **What to capture:** `https://agentic-bi.superdev.mx/?lang=es`, the hero spreadsheet with the category bars, at 1440 px. Or the gallery section, if the card format needs a wider shot.
- **Caption (required, so nobody reads it as the client's system):** «Demo de Agentic BI con datos ficticios.» / "Agentic BI demo with fictitious data."
- **Alt:** «Pregunta en español y respuesta con gráfica en la demo de Agentic BI» / "A question in Spanish answered with a chart in the Agentic BI demo".

## 5. Elsewhere
- `/business-intelligence/` Casos card and stats band: keep them. They're the same case under «Agente de Datos», so no copy change is needed. Point the card to `/projects/agente-de-datos` as today.
- Lucava cleanup: as you listed. Rename the i18n keys `lucava.*`, `portfolio.lucava.*` and `b.case.lucava` to a neutral prefix such as `datos.*`, remove the lucava.superdev.mx link, and replace the image. Grep for "lucava" (any case) in `static/`, `src/`, `context/` and generated files (`llms*.txt`, sitemaps) after `seo:build`.
