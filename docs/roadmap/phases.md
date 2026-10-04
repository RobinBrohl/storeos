# Development roadmap

Reconciled 2026-10-04. [Status](status.md) owns actual delivery; [vision](../vision.md)
owns long-term capabilities. The legacy D0/P0–P12 labels below remain stable
navigation for existing phase records. They are domain groupings, not a promise
that all lower-numbered domains ship before higher-numbered ones.

A new slice needs a real use case, owner, permission/audit/error contract and
bounded acceptance. This document proposes sequencing; it does not authorize
parallel implementation or allocate speculative P4.4/P4.5 numbers.

## Near-term implementation direction

1. Close P4.3 acceptance with the focused F01/F06/F07 stock client correction and
   relevant regression/review/CI checks. The server ledger is committed; a code
   fix is still needed.
2. Select **one** next slice from operator evidence. First canonical external-POS
   sales ingestion is a candidate if an actual source/API/export is available.
   Define source authority, durable import identity, mapping and visible health;
   defer stock effects until their unit/cutover/return rules are defined.
3. If there is no usable sales source, a bounded recurring/guided-work use case
   is an alternative. Neither candidate is ACTIVE merely because it is listed.
   Resolve the appropriate open decisions before scope approval.

M3 containment applies to every new API. M1 gates the adoption of a real-user
proxy deployment. Wider RBAC, remote access, Wiki, Planograms, Recipes, Menus and
communications remain domain/dependency direction rather than a fixed sequence.

## D0 – Dokumentation und Repository-Grundlage

Documentation, principles, ADRs, risks and repository foundation exist.
Acceptance remains discoverable sources, bounded slices and truthful evidence;
D0 itself did not deliver applications.

## P0 – Dünne technische Grundlage

Single-site Dart/PostgreSQL and Flutter Web, configuration/secrets, migrations,
authentication, logs, CI, TLS example and encrypted backup/restore tooling.
Acceptance uses real initialization and recovery; no mandatory cloud.
Native runners and hardware acceptance are separate. [P0](../development/phase-0.md).

## P1 – Plattformverwaltung

Organization, Accounts, fixed RBAC, audit, local organization events and approved
external plugin clients are delivered per [ADR 0012](../adr/0012-phase-1-plattform-und-plugin-api.md).
Self-password change is a delivered bounded extension. Configurable Roles/grants
are future work; executable plugin code and multi-site sync are not P1 claims.
Acceptance preserves IDs, verifies rights/last admin/revocation/conflicts and
atomic audit with a real database. [P1](../development/phase-1.md).

## P1b – Erster fachlicher Vertical Slice (teilweise implementiert)

The bounded employee journey is delivered through P1b.9: identity, templates,
publication/snapshots, guided execution, blocking/resolution, numeric attempts,
pre-execution cancellation and interval amendment. [Status](status.md) links the
individual contracts and dated evidence.

General published employee/template changes, reconciliation of begun work,
recurrence, automatic recommendations and swaps are still planned. New work must
preserve immutable snapshots and command receipts, atomic rollback and explicit
conflict handling. No event generator replaces synchronous publication consistency.

## P2 – Betriebsfestigkeit und explizite Offline-Grenzen

Bounded restore/capacity/update harnesses exist. They prove their declared isolated
contracts, not automatic activation, arbitrary rollback, HA or production-hardware
throughput. Updates are forward-only; recovery uses an encrypted restore point
into a fenced target. [Update contract](../development/phase-2-update-recovery-acceptance.md).

Device cache/queue and enterprise sync need separate acceptance: allowed commands,
rights expiry, pending/accepted/refused status, replay retention, bounded storage,
conflicts, stale cursors and restore reconnection. Headquarters sync is optional
and is not a prerequisite for further single-site features. Never allow two
active authoritative writers for the same aggregate.

## P3 – Workforce und Wissensabläufe erweitern

Planned: skills, qualification validity, recurrence, dependencies/windows,
handover, justified absences, training and approved Wiki guidance. Boards may
provide a bounded durable communication slice before Chat. Recommendations start
with deterministic rules/reasons and human decisions; preserve breaks/ongoing work
and minimize HR data.

## P4 – Artikel, Einkauf und Bestand

Article and location Assortment are delivered. Manual Stock is committed with
active acceptance corrections. Future units/conversions, Suppliers, orders,
receiving, batches/expiry, inventory counts, transfers and valuation require
separate slices; a frozen unit label suffices for current manual stock.
[ADRs 0015–0017](../adr/README.md).

Planograms use generic Fixtures, immutable revisions, organizational assignments,
tasks/feedback and print. Editing/printing does not require a complete warehouse
system; live stock information uses Stock's public query contract.

External sales ingest can precede receiving/valuation and the StoreOS checkout.
It owns source/import/mapping/health; physical Stock effects additionally need
unit mapping, cutover and correction/return policy. No arbitrary unit conversion.

## P5 – Lebensmittelsicherheit und Geräte

Planned: controls, measurements, deviations, corrective actions, cleaning,
traceability/recall and maintenance. HACCP owns safety records, Tasks presents
guided work. Acceptance preserves failed measurements, responsible follow-up and
version/provenance; sector/jurisdiction review precedes claims or real safety use.

## P6 – Produktion, Rezepte und Kennzeichnung

Planned: normal Article + optional versioned Recipe, ingredient quantities/yield,
production orders/batches, labels and explicit stock effects. Production may
stock finished goods or consume ingredients on sale only under a decided model.
Costs/margins require trustworthy cost basis; no Recipe-only valuation semantics.
Allergens and labels require verified data and approval.

## P7 – Erweiterte Personalplanung und Zeiterfassung

Planned: actual time records/corrections, availability, human-approved
ShiftSwapRequest and explainable staffing proposals. Recipient acceptance does
not alter schedules; final approval revalidates current versions/eligibility/
overlaps and commits atomically. Begun-work rules remain open. Planning is not
attendance evidence; no automatic personnel sanctions.

## P8 – Analyse und Prognose

Planned: defined metrics, freshness/provenance, scoped drill-down/export and
forecast baselines with uncertainty. Imported sales can enable reporting before
StoreOS checkout; margins wait for cost semantics. ML/autodisposition are optional
and require demonstrated value and explicit activation.

## P9 – POS und Bargeld

**Deferred optional StoreOS-owned checkout.** Payments, receipts, cash, returns,
fiscal/TSE/terminal adapters and offline failure procedures need a separate product
decision and qualified regulatory review. Existing-POS ingestion is a different
boundary and need not wait for this domain. No checkout release from placeholder UI.

## P10 – Gastronomie

Planned: table/order/kitchen-display/reservation/take-away journeys with coherent
product and settlement contracts. Recipes, structured Menus and static publishing
can ship independently; this heading must not make a complete POS a prerequisite
for every gastronomy feature.

## P11 – Dokumente und Finanzen

Planned: documents, invoices, e-invoice formats and finance with dedicated
retention/export/correction rules. Operational Stock quantities and sales
normalization are not accounting valuation or a certified fiscal archive.

## P12 – Öffentliche Kanäle und optionale KI

Planned: structured Menu publication, public artifacts, pre-orders, integrations
and optional AI. Public publishing needs an explicit authorized publisher with
safe replacement/status; no public access to operational DB/admin APIs.
Remote employee self-service is a separate authenticated access context with an
allowlist and no-private-device fallback, not a general public website.

## Übergreifende Release-Gates

Each release requires persistence, server authorization/validation, relevant
audit/events, migration preservation, errors, meaningful tests, UI, documentation
and operator impact. Review existing data, active task snapshots, old receipts
and declared client/plugin compatibility; a fresh installation alone is not
upgrade proof. [Compliance](../compliance/overview.md) and [risks](../risks-and-open-questions.md)
hold qualified review/operator gates.

## Product dependency map

Dependencies describe required information, not direct table access or circular
module ownership. Simple content slices can ship before richer live integrations.

| Capability | Prerequisite for the stated behavior |
| --- | --- |
| Planogram editing / print | Fixture + Article reference + published revision; complete Stock is not required. |
| Planogram live information | Article + Assortment + Stock authorized read contracts and visible freshness. |
| Manufactured product | Article + optional versioned Recipe with ingredients/quantities/yield. |
| Recipe cost / margin | Recipe + compatible units + trustworthy effective cost basis; sales/pricing semantics for margin. |
| Menu item | Optional Article/Recipe reference; structured content can stand alone. |
| Menu prices | Defined Pricing contract and currency, not incidental Article data. |
| Task knowledge guidance | Approved Wiki revision pinned to execution. |
| Shift swap | Shift + identity/eligibility + responsible approval + current atomic schedule contract. |
| Configurable operational roles | Capability catalog + Roles/assignments/grants/scope/revocation/audit policy. |
| Remote self-service | Secure identity/access context + allowlist + local fallback. |
| Public Menu publication | Approved Menu artifact + explicit publisher; no direct DB exposure. |
| Canonical external sales | Real source contract + durable identity + mapping/visible unresolved lines + import health. |
| Automatic sales Stock effects | Canonical sales + explicit units/source actor/provenance/cutover + return/production policy. |
| Sales/margin reporting | Reliable sales provenance/freshness; cost basis required for margin, not basic ingestion. |
