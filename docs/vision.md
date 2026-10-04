# Product vision

**Long-term vision, reconciled 2026-10-04.** This defines the product direction, not a committed delivery schedule or final schema. [Actual status](roadmap/status.md) records implemented scope; [roadmap](roadmap/phases.md) records sequencing proposals; [open questions](risks-and-open-questions.md) records decisions still required.

## Product promise

StoreOS connects daily retail and gastronomy work with trustworthy operational data. Employees should know when, where, with whom, what and how to work. Managers should see relevant exceptions and make accountable decisions. Versioned instructions, schedules, tasks, goods and records share context rather than requiring repeated entry across apps and paper.

The first verified journey is:

`Company → Location → Employee → Shift → TaskTemplate → TaskInstance → Employee Home → Guided Work → Completion → Audit Log`

Its bounded online implementation exists through P1b.9. Automatic next-work recommendations, general rescheduling, shift swaps and device-offline writes remain future capabilities. Article, location Assortment and manual Stock provide the next goods foundation; the stock client still needs the corrections recorded in [technical debt](development/technical-debt.md).

## Local operation and ownership

StoreOS is a local-first, self-hosted modular monolith: Flutter clients, a Dart server and PostgreSQL. A site must operate without internet to headquarters or a vendor cloud. A disconnected device writing to its local queue is a separate capability with its own authorization, replay and conflict contract.

Operators own data, export formats, backups and recovery keys. No mandatory cloud account, subscription, external telemetry or AI is required for the operational core. Optional headquarters coordination needs explicit authority per aggregate and selective replication; a coherent data model does not imply one physical database or two unrestricted writers.

Company, Location, Account and Employee have separate stable identities. Future regions, departments, areas and workstations follow concrete operational needs. Contracts, skills, qualifications and HR records must remain distinct from the minimal Employee profile and from login identity.

## Users and operational permissions

Current fixed roles are a platform foundation. The intended evolution provides system role templates, company-defined Roles, role assignments and audited direct per-user grants. Capabilities describe actions; business titles such as store manager or baker are not hard-coded authorization semantics.

Future grants may apply to a Company, one Location or an explicit set of Locations when a real use case justifies it. Start with understandable additive grants; explicit deny/conflict precedence needs a separate justified decision. Server-side authorization, resource scope, revocation and protection against administrative lockout remain mandatory. This vision does not replace the current fixed-role catalog.

## Workforce, tasks and knowledge

Workforce owns planning, availability, absences and later time-recording rules. Planned shifts are not proof of attendance. Tasks owns work definitions, revision snapshots, execution state and evidence. Guidance supports employees; task activity must not become hidden scoring or automatic personnel sanctions.

Future recurring work, dependencies, windows and recommendations start with deterministic rules, visible reasons, blocked prerequisites and human overrides. Skills and training feed only the minimum authorized eligibility information into planning. Scheduling must not silently displace ongoing work or breaks.

The enterprise **Wiki** holds versioned operational knowledge. Drafts and employee improvement suggestions go through authorized review and approval before publication. Tasks pin the approved Wiki revision used as guidance; later knowledge edits do not change historical instructions or evidence. Reading, suggesting, approving and publishing are different permissions. A Wiki is not an unrestricted document dump.

## Shift swaps

A future **ShiftSwapRequest** is a bounded workflow: an employee proposes a swap to a named recipient, the recipient accepts or rejects and both may add relevant comments. Recipient acceptance records a proposal; it does not change the schedule. An authorized responsible person must approve.

Final approval revalidates current shift versions, identity, eligibility, assignments, overlaps and applicable rules, then commits the schedule mutation and audit/evidence atomically. A stale proposal requires a visible decision rather than silent replacement. Rejection, withdrawal and failed approval retain appropriate evidence.

Current published-shift employee assignment is immutable. A linked cancel-and-replacement design is a candidate for pristine work; in-place reassignment is not a decided implementation. Rules for begun work, partial swaps and an open marketplace remain undecided. Neither current cancellation nor interval amendment implements swaps.

## Articles, Assortment, Stock and purchasing

**Article** is the Company-wide product identity. **Assortment** says whether a Location carries an Article; Article and membership activation are independent. **StockLevel** is the current location quantity projection; **StockMovement** is the immutable movement ledger. Neither a barcode nor an assortment UUID replaces Article identity.

Purchasing and receiving will own Suppliers, orders and receipt evidence. Stock will apply explicit physical movements through its public commands. Batches, expiry dates, inventory counts, transfers, reservations, waste and traceability require their own rules. Deactivation preserves history and existing stock; it is not physical disposal.

Current stock uses exact thousandths and a frozen unit label. A shared unit catalog and explicit conversions are needed before effects involving unlike purchase, recipe or sales units. No code should infer a conversion from a text label. Money needs exact amounts and currency; quantity precision and rounding must be defined independently.

## Manufactured Articles, Recipes and production

A manufactured product remains a normal **Article** with an optional versioned **Recipe**, rather than a parallel product identity. A Recipe references ingredient Articles, quantities, units, yield and instructions, with optional ordered preparation steps. Publication and production records pin the applicable revision.

A Recipe alone cannot produce trustworthy cost or margin. Cost calculation needs a decided, reliable basis such as purchase-derived cost, weighted average or a maintained standard; these are alternatives still requiring policy, not invented valuation semantics. Currency, waste/yield treatment, effective dates, source provenance and unit conversion matter. Comparable same-unit calculations can form a bounded first slice without pretending to be accounting valuation.

Production owns production orders, batch/yield evidence and labels; Stock owns their physical ledger effects. The product must explicitly decide between finished-goods stocking and ingredient consumption on sale for each supported model. It must not consume ingredients and finished goods twice. Allergen and safety information requires verified sources and responsible approval.

## Fixtures and Planograms

A generic **Fixture** represents a shelf, display, refrigerator or service counter. Optional dimensions, zones, slots and facings provide useful structure without forcing every counter into a shelf grid or CAD model.

A **Planogram** has editable drafts and immutable published revisions. Placements reference Articles, quantities/facings and fixture zones. Headquarters or another higher organizational level can assign a revision to Locations with effective dates, acknowledgement and execution tracking. Assignment scope and permitted local overrides require explicit policy.

A task can pin the assigned revision, guide setup and capture employee feedback, deviations and authorized resolution. The plan's frozen instructions remain distinct from live Article/SKU/barcode, Assortment and Stock drill-down, whose freshness must be visible. A live query must not rewrite an old plan.

Printable/PDF A4 or A3 outputs, including landscape layouts for counters, use the selected revision. Rich spatial simulation and general drawing tools are outside scope. Planogram editing can precede complete stock functionality; live stock information depends on the stock read contract, not foreign table access.

## HACCP and food safety

A future HACCP domain owns control plans, control executions, measurements, deviations and corrective actions. Guided Work can present a control task but does not own the authoritative safety record. Limit versions, device provenance, follow-up and retention need explicit contracts.

Current numeric task inputs and blocking are generic evidence, not a certified HACCP product. Jurisdiction and sector-specific claims require qualified review. Digital instructions do not replace required qualification, training or human responsibility.

## Pricing, Menus and public publication

Pricing will own effective prices, currency, source and approval rules. A **Menu** is structured, versioned content: sections and ordered items with names, descriptions and visibility. Items may reference an Article or Recipe, but free-standing content is supported where appropriate. Displayed prices require a defined pricing source rather than incidental Article fields.

Themes/templates provide typography, logos, brand tokens and deterministic printable output. They do not turn StoreOS into a general page builder. Print or PDF artifacts pin the chosen revision.

Website publication is an explicit authorized action producing a public artifact from approved content. A publisher handles deployment, status and reversible replacement atomically at the publication boundary. The public website must not require direct access to the operational database or administrative APIs. The hosting mechanism remains open; menus and static publishing do not depend on implementing a StoreOS checkout.

## Boards, Chat and notifications

**Boards** hold durable announcements, handovers and operational notices with publication/visibility rules. They can deliver useful communication before a full Chat feature. **Chats** are a separate direct/group conversation model; introduce them when a real operational use case justifies membership, delivery and lifecycle complexity.

Communication needs purpose limitation, minimum employee data, scoped membership, controlled administrative access, retention, export/deletion and offboarding. Backups and restored memberships must respect those policies. Presence profiling, employee ranking and automated sanctions are outside the product direction.

Notifications derive from real domain facts. Durable delivery status, retry/failure handling, preferences and permitted contact use belong to delivery, not conversation ownership. Email can provide a fallback and should minimize sensitive content by default; full chat bodies are not the default email payload. A notification is not proof that a user read or accepted a business change.

## Workplace, remote self-service and fallback

The operational core remains local. Three access contexts guide future product design:

| Context | Intended access |
| --- | --- |
| Trusted workplace | Shared terminals/handhelds and authorized operational capabilities, with safe session switching. |
| Remote employee self-service | Selected own roster/balances, Wiki, Boards, appropriate Chat, notifications and swap requests, subject to policy. |
| No private-device use | In-store kiosk/access, print and suitable email notification alternatives. |

No private smartphone or app is mandatory. Remote access does not automatically expose stock administration, full employee records or every management capability. An access-context capability allowlist combines authenticated identity, grants and resource scope; an IP address alone is not a trustworthy access context.

An optional secure gateway/relay is a direction, not a selected vendor or mandatory cloud dependency. VPN deployment may be suitable for some operators; identity assurance, MFA/passkeys, recovery and gateway trust still need decisions. Failure of remote access must not disable independent local work. Remote access is not device-offline synchronization.

## External POS sales ingestion

External POS integration is a distinct capability from a StoreOS-owned checkout. Stock reconciliation and reporting must be able to consume existing POS sales without waiting for StoreOS payments, receipts or fiscal checkout implementation.

The Core owns a canonical sales-ingestion boundary: source configuration, validation, durable event identity, Article mapping, checkpoints, import health and downstream effects. Vendor adapters own authentication, API/file acquisition and conversion into that contract. Begin with a first-party adapter for a real source; a separately deployed plugin or integration service is an option, not a requirement for every vendor.

Company and Location authority come from the configured SalesSource and authenticated integration context, not unchecked IDs in an imported payload. Conceptual SalesSource, import/checkpoint, Sale, SaleLine and ExternalReference describe responsibilities; they are not final tables.

Ingestion preserves source identity and provenance. A durable key combining source and external transaction/line/event identity supports repeated, delayed and partial delivery with at-most-once StoreOS effects over an at-least-once feed. Corrections, voids and returns are explicit evidence; they must not silently overwrite history. Ordering, gaps, checkpoints and replay need tested source-specific contracts.

External product IDs/PLUs/SKUs/EANs map explicitly to Company Articles. Uncertain or unmapped lines stay visible for authorized resolution; never guess by product name or silently discard them. Timestamps, business date, exact amounts/currency and gross/net/tax semantics are accepted only with clear source meaning.

Versioned **DSFinV-K** fiscal exports can support bulk backfill and reconciliation; the format does not itself provide a real-time ingestion API. Use vendor APIs where operational latency requires them. Normalized StoreOS sales evidence does not replace a required fiscal archive. Do not ingest card numbers, payment secrets or unnecessary customer data.

Canonical sales can be accepted before stock effects are enabled. Missing Article mappings, unit conversions or effect policy remain visible as unresolved lines/effects. Stock consumption additionally needs frozen unit mapping/precision, physical opening balance and cutover rules so delayed/backfilled sales do not double-count movements.

Returns require physical disposition distinct from fiscal reversal, void or correction. Recipe/finished-goods consumption policy must be decided before automatic effects. Cost basis and pricing semantics are prerequisites for reliable margins, not prerequisites for basic canonical ingestion.

Import health is product functionality: last sync/source time, failures, unmapped lines, unresolved effects, duplicates/gaps and explicit retry/reconciliation. Prefer local adapters and outbound HTTPS where the source permits it; importing sales does not itself require exposing a site to inbound remote administration.

## Reporting, finance, checkout and optional intelligence

Reporting uses defined metrics, provenance, freshness and permitted drill-down. Forecasts start with measurable baselines and uncertainty; ML, automatic disposition and AI are optional and need demonstrated value. AI consumes only approved sources within access scope and must not make critical business/personnel decisions autonomously.

Finance and business documents need dedicated invoice, export, retention and correction rules; an operational stock ledger is not accounting valuation. Financial reporting must expose missing cost/source data rather than fabricate margin.

A StoreOS-owned **POS** checkout remains deferred and optional: payments, receipts, cash, fiscal/TSE integrations and failure procedures require a separate product decision and jurisdiction-specific review. Restaurants' tables, ordering, kitchen display and reservations are additional domains, not prerequisites for Recipes, Menus or imported sales.

## Product boundaries

StoreOS includes bounded capabilities only when they support retail/gastronomy operations. It should not become a generic ERP, full HRIS, Slack replacement, WordPress replacement, Canva/Figma replacement or CAD system. Operational knowledge, notices, structured publishing and fixture plans share business context; unrestricted collaboration, arbitrary websites and general design tooling would dilute that focus.

Measure fewer media breaks, reliable task completion and understandable decisions. Never present placeholder features as complete. Each delivered slice needs persistence, validation, authorization, relevant audit/events, migrations where required, errors, tests, UI and documentation. Privacy by design/default is a requirement, not a claim of legal certification; legal and organizational policies remain operator responsibilities.
