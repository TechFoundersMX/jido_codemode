# superdev.mx: bringing the Agentic BI landing's UI, UX and copy patterns to the site

**For:** the SITE session (repo `Channels/Website/superdev`, plain static HTML/CSS/JS, `main` deploys to production).
**From:** the Agentic BI session, 29 Sep 2026, at Alex's request.
**Reference:** the approved landing draft `jido_codemode/docs/landing/2026-09-29-landing-draft.html` (artifact https://claude.ai/artifact/5zmUN6EdnPGfmqWWBD9Jrx) and the copy deck `2026-09-29-copy-deck.md` in the same folder.

## 0. Ground rules

- **Port the patterns, not the sub-brand.** Agentic BI has its own look: Geist, green accent, spreadsheet hero. superdev.mx keeps its editorial identity: Fraunces + Public Sans, `--paper #FAF7F1`, terracotta `--acc #B4452A`. Every pattern below is written against the site's existing tokens in `static/styles.css`. Don't import Geist, the green palette or the spreadsheet chrome.
- The site's own rules still apply and override anything here:
  - `AGENTS.md`.
  - `context/site-messaging.md`: tú; no em dashes or exclamation marks; "IA" only in headlines; canonical CTAs.
  - `context/catalogo-indicadores.md`: numbers.
  - `npm test` before every commit, and `npm run seo:build` after any copy change.
- Every new `data-i18n` key needs inline Spanish **and** an `i18n.en` entry in `static/main.js`.
- Nothing here ships without Alex's OK. Items marked **(Alex)** need a decision first.

## 1. What to port, in priority order

| # | Pattern | Where on superdev.mx | Effort |
|---|---|---|---|
| 1 | Live question-to-chart hero mock, using real sample data | `/business-intelligence/` hero (replaces the static `hs-chart`) | M |
| 2 | Example gallery: six questions, each with its answer and chart | `/business-intelligence/`, new section after "La diferencia" | M |
| 3 | Demo links to the landing, with the request-access form | `/projects/agentic-bi`, BI page, new form (§4) | M |
| 4 | "Para tu equipo de TI" governance block | `/business-intelligence/`, after "Sobre tu ERP actual" | S |
| 5 | Case stats band that tells the agent timeline apart from the project timeline | BI page "Casos", `/projects/agentic-bi` | S |
| 6 | Maturity strip that states what the agent covers today | BI page `#madurez` (copy tweak) | XS |
| 7 | FAQ about limits | BI page FAQ (add items) | XS |
| 8 | Number styling: tabular figures and one format helper | `static/components.css`, `currency.js` if relevant | XS |
| 9 | Motion rules: reveal plus chart draw-in, reduced-motion safe | `static/components.css`, `main.js` | S |
| 10 | White-label partners block, English only **(Alex)** | none yet; see §6 | S |

Don't port:
- The review toolbar.
- The palette and background switchers.
- The spreadsheet frame (formula bar, column letters, sheet tabs). It belongs to the Agentic BI sub-brand.
- The stacked "explore" panels. The BI page already has its own section rhythm.

## 2. Patterns in detail

### 2.1 Live hero mock (BI page)

Today the mock is a static `.hs-chart` with five `<i>` bars and the message "¿Qué vendimos por sucursal este mes?". Replace it with a small cycling demo.

**Behaviour:**
- Cycle through four examples: categories, trend, shipper mix, top customers.
- Show each one for 4 s. For each example:
  - Type the question into the message line at about 3 characters per 18 ms.
  - Then show a one-sentence answer.
  - Then draw the chart (bars grow; the line strokes in).
- Put small dots under the mock to jump to an example. Pause while the pointer hovers or keyboard focus is inside.
- With `prefers-reduced-motion: reduce`: no typing, no auto-cycle, no draw-in. Show example 1 fully rendered; the dots still work.
- Label it honestly: keep the caption, and add «Datos de ejemplo de una distribuidora ficticia.» (EN: "Sample data from a fictitious distributor."). No real client data or logos, ever (#demos).

**Markup contract.** Keep the existing `.hero-mock.mock` wrapper and `role="img"`, and change the `aria-label` to describe the whole cycle. Visible question and answer text should be real text, not canvas, so `llms-full.txt` and screen readers get it. Put the moving parts under `aria-hidden="true"` and add one visually hidden `<p>` with the current question and answer, updated politely (`aria-live="polite"`, at most once per cycle).

**Implementation.**
- New file `static/assets/bi-examples.js`, deferred and loaded only on `/business-intelligence/`.
- Charts are inline SVG built from the data in the appendix, so no chart library is needed. Colours come from CSS variables:

  ```css
  .bi-viz { --s1: var(--acc); --s2: #2f6f73; --s3: #c28a2c; --s4: #7d5ba6; --s5: #4a6fa5; }
  ```

  These are the "Marca SuperDev" series already proven in the landing draft; check contrast against `--card`.
- Reuse the landing draft's renderers (`vizBars`, `vizLine`, `vizDonut`, `vizTable`, `vizKpi`), which are about 60 lines of vanilla JS. They are in the draft's `<script>`; copy them and rename the classes to the site's conventions.
- Numbers use `font-variant-numeric: tabular-nums` (Public Sans supports it). The Spanish view shows **MXN** (`$4.78 M`, table cells `$1,967,490.39 MXN`); the English view shows USD. Convert with one constant, `RATE = 17.8413` (the rate the demo uses). Add a footnote: «Cifras de ejemplo convertidas a MXN con tipo de cambio fijo.» Don't label it "FIX de Banxico" unless the rate is kept in sync with the demo's Coolify vars.

### 2.2 Example gallery (BI page, new section)

- **Eyebrow** «Ejemplos». **H2** «Pregunta como hablas. Recibe la gráfica.» (EN "Ask the way you talk. Get the chart.").
- **Layout:** a 3×2 grid of cards (`auto-fill, minmax(280px, 1fr)`), one column on phones. Each card has:
  - a kind tag (Tendencia / Comparación / Mezcla / Ranking / Indicador / Geografía);
  - the question in an `--acc-wash` speech bubble;
  - the one-sentence answer;
  - the chart.
- Cards animate in once, when they reach the viewport (IntersectionObserver, threshold 0.3). Bars grow with `transform: scaleX()` from 0; the line uses `stroke-dasharray` with the path length; the donut animates `stroke-dasharray`. Everything is off under reduced motion.
- **Close the section** with one link, not a button: «Pruébalo con el agente en vivo» → `https://agentic-bi.superdev.mx/#pruebalo`. Leave it untagged: a new `utm_source` would land unattributed in Odoo until the ERP adds it. If you want to track it, add the source to `utm_data.xml` first, as you did for `agentic_bi`, and keep the query before the `#`.
- **Copy is fixed and verified against the data** (appendix). Don't reword an answer without re-checking the number it claims.

### 2.3 Demo entry points and the request form

After the landing launches:
- **`/projects/agentic-bi`:** «Ver demo en vivo» → `https://agentic-bi.superdev.mx/demo`. The root becomes the landing.
- **`/business-intelligence/`:** the hero's secondary button stays «Ver casos». Add the gallery link above, and a line in "Casos" linking to `https://agentic-bi.superdev.mx`.
- **Link `/projects/agentic-bi` from the BI page's "Casos"** (today only another case page links to it).
- **Request-access form: the invitation service hosts it, not superdev.mx** (hub proposal 29 Sep, pending Alex). The Worker serves the self-serve form at `https://agentic-bi.superdev.mx/solicitud`. It reuses the live Expo / Te Invitamos access-campaign code: Turnstile, per-email and per-IP limits, the email with the link, and a CRM lead only with consent. **superdev.mx only links to it**, labelled «Pide acceso al agente en vivo».
- **SITE owns the privacy side of that form:**
  - Add the Agentic BI demo to the privacy notice (#demos).
  - Set the consent wording in ES and EN. Alex chose the short sentence: «Al entrar guardamos tu nombre, correo y empresa para darte acceso y enviarte el enlace.» The hub notes its follow-up box is now at version 2 («…guarde mis datos y esta conversación…»). Agentic BI conversations never reach the Worker or the CRM, so the "esta conversación" part doesn't apply. Confirm with Alex which box text to show.
- The form's copy comes from the approved draft:
  - Fields: Nombre, Correo, Empresa.
  - Body: «Tienes tres conversaciones de prueba durante 7 días con la distribuidora de ejemplo, y entras en cuanto envías tus datos.»
  - Submit button: «Entrar al agente».
  - Below it: «¿Prefieres verlo con los datos de tu empresa? Agenda tu llamada exploratoria».
- Attribution: the ERP must accept `demo.app = "agentic_bi"` (Odoo returns 422 for unknown apps today), in addition to `utm_source=agentic_bi` (id 72).

### 2.4 "Para tu equipo de TI" (BI page)

A definition list in three columns (one on phones) with a hairline top border per item. It uses the existing `.section` spacing and no new colours.

- **Eyebrow** «Para tu equipo de TI».
- **H2** «Lo que tu área de sistemas va a preguntar.»
- **Lede** «El agente solo lee. Cada consulta pasa por controles antes de ejecutarse, y cada número tiene una definición y un dueño.»

| Title | Body |
|---|---|
| Solo lectura | No puede modificar ni borrar información. Solo ejecuta consultas de lectura que se validan antes de correr. |
| Tus datos no se mudan | Se conecta a Dynamics 365, Odoo, SAP Business One o Airtable. No reemplazamos tu ERP ni copiamos tu operación a otra herramienta. |
| Un solo número | Cada indicador queda escrito: su definición, su fuente y su dueño. Se acaba la versión de cada área. |
| Quién ve qué | Permisos por rol. Queda escrito de quién es cada dato y quién puede verlo. |
| Límites claros | Cada consulta tiene tiempo y tamaño máximos. Si la pregunta es ambigua, el agente lo dice o pregunta; no inventa números. |
| Privacidad | La demo usa datos ficticios. En tu proyecto, los datos personales se tratan según nuestro aviso de privacidad. |

"Quién ve qué" and "Un solo número" are still open with Alex (copy deck §6.4): confirm that role permissions and indicator ownership are standard in every implementation before shipping these two.

### 2.5 Case stats band

Three numbers in one row with hairline dividers. The labels say which timeline each number belongs to (SITE's own rule):
- **42**: usuarios en lenguaje natural.
- **< 2**: meses para tener el agente en vivo.
- **16**: semanas y 12 entregables, el proyecto completo.

Set the numbers in `--font-display` at `--fs-stat` with tabular figures. Follow them with «ERP fuente: Dynamics 365.» Never name Lucava; the case is «Agente de Datos».

### 2.6 Maturity strip (copy tweak)

Keep the four levels (Descriptivo · Diagnóstico · Predictivo · Prescriptivo, each with its question). Visually mark the first two as "today" and add the fineprint «Empezamos donde estás, casi siempre en descriptivo, y construimos la ruta hacia arriba. El agente cubre hoy las dos primeras etapas.» This keeps the page from implying the agent predicts or prescribes.

### 2.7 FAQ additions (BI page)

The FAQ already exists. Add only the items that are missing, with the wording from the copy deck §3.10:
- ¿Tengo que mudar mis datos?
- ¿Qué pasa si la pregunta es ambigua?
- ¿Puede cambiar mi información?
- ¿Con qué sistemas funciona?
- ¿La demo usa mis datos?

### 2.8 Numbers and motion (shared CSS and JS)

- Add `.num { font-variant-numeric: tabular-nums; }` to `components.css` and use it for every figure, table cell and axis label.
- Motion stays in one place:
  - The existing `.reveal` observer in `main.js` handles section entrance.
  - Chart draw-in is triggered by the same observer, via a `data-draw` attribute that `bi-examples.js` listens for.
  - One `@media (prefers-reduced-motion: reduce)` block turns off all transitions and animations for `.bi-viz` and `.hero-mock`.
- No autoplay audio or video. The hero cycle is the only auto-advancing element, and it pauses on hover and focus.

## 3. Copy lines approved for reuse

From the landing, all within site-messaging rules:
- H1 on the landing: «Tu próximo reporte, en una pregunta.» The BI page keeps its own H1 («¿Pedir un reporte en tu empresa tarda días?»). Use the landing line as the BI final-CTA headline only if it reads better than «¿Y si tu próximo reporte tardara segundos?». **(Alex)**
- Lede: «Tienes los datos, pero cada reporte tarda días y depende de una persona. Conectamos tus fuentes (Dynamics 365, Odoo, SAP Business One, Airtable) para que cualquiera pregunte y decida al instante.»
- ¿Te suena? items:
  - «Cada reporte depende de una persona que "sabe sacar la información".»
  - «Tus datos están en el ERP, pero sacarlos es un proyecto.»
  - «Cada área llega a la junta con su propio número.»
  - «Decides con datos del mes pasado, o con intuición.»
- CTA pair, unchanged canon:
  - «Agenda tu llamada exploratoria» / «30 min · gratis · sin compromiso».
  - «Haz la evaluación preliminar» / «3 min · 14 preguntas · resultado al instante».

## 4. Files to touch (SITE repo)

| File | Change |
|---|---|
| `static/business-intelligence/index.html` | Hero mock markup; new gallery and TI sections; case stats; maturity fineprint; FAQ items; links |
| `static/projects/agentic-bi.html` | Demo link → `/demo`; stats band labels |
| `static/assets/bi-examples.js` (new) | Data, format helpers, SVG renderers, hero cycle, gallery draw-in |
| `static/components.css` | `.bi-viz`, `.bi-gallery`, `.it-list`, `.stats-band`, `.num`, reduced-motion block |
| `static/main.js` | `i18n.en` entries for every new key; optional `data-draw` hook in the reveal observer |
| `static/privacidad/` | Add the Agentic BI demo to #demos, with the consent wording (§2.3) |
| Generated files | `npm run seo:build` (sitemap, `llms.txt`, `llms-full.txt`) |

## 5. Acceptance checks

- [ ] `npm test` passes: one h1, identical nav, complete `i18n.en`, JSON-LD valid.
- [ ] `npm run seo:build` run and its output committed.
- [ ] At 375 px and 1280 px, ES and EN: no horizontal scroll; the hero mock fits without clipping chart labels; gallery cards are one column on phones.
- [ ] With reduced motion on: nothing moves, and example 1 is fully visible.
- [ ] Each answer sentence matches its data (appendix). MXN in Spanish, USD in English, with the footnote present.
- [ ] Every demo link points to `agentic-bi.superdev.mx` (`/demo` for the live agent). The CTAs are exactly canon.
- [ ] No new numbers outside `catalogo-indicadores.md`.
- [ ] Lighthouse accessibility ≥ 95 on the BI page. Charts have text equivalents.
- [ ] Alex approved before the push to `main` (it deploys).

## 6. Open items for Alex

1. **White-label.** The Agentic BI landing's English view now has a partners block: «Offer it under your brand.», covering your brand, we do the build, your client, your call. Nothing in the site canon documents a white-label BI offer. Should superdev.mx mention it anywhere (EN BI page, or the AI Employee offer), or keep it only on the landing?
2. **Governance claims** in §2.4 ("Quién ve qué", "Un solo número") need confirming.
3. **BI final-CTA headline:** keep the current one or reuse the landing's (§3).
4. **Consent box:** the short sentence (Alex's pick) or the hub's version 2 box («…y esta conversación…»)? Conversations don't reach the CRM, so the short one fits.

## Appendix: example data (Northwind sample, USD; Spanish shows ×17.8413 MXN)

| id | Kind | Question (ES / EN) | Answer (ES / EN) | Data |
|---|---|---|---|---|
| trend | line | Muestra la tendencia mensual de ingresos de 2013. / Show the monthly revenue trend for 2013. | Diciembre fue el mejor mes del año y octubre el segundo. / December was the best month of the year, and October the second. | Jan–Dec: 61258.07, 38483.64, 38547.22, 53032.95, 53781.29, 36362.80, 51020.86, 47287.67, 55629.24, 66749.23, 43533.81, 71398.43 |
| cats | bars | ¿Cuáles son las 3 categorías que más venden? / Which 3 categories sell the most? | Bebidas lidera, seguida de Lácteos y Dulces y postres. / Beverages leads, followed by Dairy Products and Confections. | Bebidas 267868.18 · Lácteos 234507.29 · Dulces y postres 167357.23 |
| ship | donut | ¿Cómo se reparten los ingresos por paquetería? / How is revenue split by shipper? | United Package mueve el 42% de los ingresos. / United Package carries 42% of revenue. | United Package 533547.63 · Federal Shipping 383405.47 · Speedy Express 348839.94 |
| cust | table | Enlista los 5 clientes con más ingresos. / List the top 5 customers by revenue. | Tres clientes concentran una cuarta parte de los ingresos. / Three customers bring in a quarter of revenue. | QUICK-Stop 110277.30 · Ernst Handel 104874.98 · Save-a-lot Markets 104361.95 · Rattlesnake Canyon Grocery 51097.80 · Hungry Owl All-Night Grocers 49979.90 |
| aov | kpi | ¿Cómo cambió el ticket promedio por año? / How did the average order value change by year? | Subió cada año: 19% de 2012 a 2014. / It rose every year: 19% from 2012 to 2014. | 2012 1368.97 · 2013 1512.46 (+10.5%) · 2014 1631.94 (+7.9%) |
| geo | bars | ¿En qué países vendemos más? / Which countries do we sell the most in? | Estados Unidos y Alemania suman más de un tercio de los ingresos. / The USA and Germany account for more than a third of revenue. | Estados Unidos 245584.61 · Alemania 230284.63 · Austria 128003.84 · Brasil 106925.78 · Francia 81358.32 |

Hero cycle order: cats → trend → ship → cust. Month labels are Spanish lowercase (ene, feb, …) in ES and English (Jan, Feb, …) in EN.
