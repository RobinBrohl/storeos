# Development roadmap

Reconciled 2026-10-04. [Status](status.md) owns actual delivery; [vision](../vision.md)
owns long-term capabilities. The legacy D0/P0–P12 labels below remain stable
navigation for existing phase records. They are domain groupings, not a promise
that all lower-numbered domains ship before higher-numbered ones.

A new slice needs a real use case, owner, permission/audit/error contract and
bounded acceptance. This document proposes sequencing; it does not authorize
parallel implementation or preselect a subsequent capability.

## Near-term implementation direction

P4.3 Manual Stock Foundation is **DONE/CLOSED**: foundation `e8ce8c3`, accepted
correction `f9c8b07`, independent targeted review APPROVE, 28/28 PASS and all five
jobs green in [CI run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795).
No active P4.3 remediation gate remains absent regression; see the
[phase closure](../development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04).

P4.4 Local Planogram Execution is **DONE/CLOSED**: implementation `cd7669ed`,
bounded CI portability fix `73dca5a4`, targeted review APPROVE and all five jobs
green in [CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802).
Migration 0016, real journeys, browser print and backup/update/recovery acceptance
are recorded in the [final closure](../development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04).
No P4.4 remediation remains active absent regression.

P4.5 Approved Operational Knowledge is **DONE/CLOSED**: implementation 93072a4,
migration 0017, independent adversarial review APPROVE, 60/60 PASS and all five
jobs green in [changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360).
[Final closure](../development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04)
retains the selection, local implementation, independent review and CI chronology.
No active P4.5 remediation remains; F01/F02 are LOW non-blocking follow-ups.

P4.6 Guided Operation is implemented locally, independent review remediation complete / targeted review pending and remote
changed-commit CI pending. [ADR 0020](../adr/0020-task-knowledge-guidance.md) pins exact
Knowledge revisions through Templates and Tasks; retirement preserves historical
contextual access. See [evidence](../development/phase-4-6-task-knowledge-guidance.md).
P4.6 is not DONE/CLOSED. P4.7 is not selected.

M3 containment applies to every new API. M1 gates the adoption of a real-user
proxy deployment. Wider RBAC, remote access, Knowledge extensions, Planogram extensions, Recipes, Menus and
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
handover, justified absences, training and Task-pinned Wiki guidance. Company-wide
approved Knowledge discovery/read is delivered by P4.5; exact Task pinning is implemented
locally in P4.6, with independent review remediation complete / targeted review pending and changed-commit CI pending. Boards may
provide a bounded durable communication slice before Chat. Recommendations start
with deterministic rules/reasons and human decisions; preserve breaks/ongoing work
and minimize HR data.

## P4 – Artikel, Einkauf und Bestand

Article and location Assortment are delivered. P4.3 Manual Stock is **DONE/CLOSED**,
including the committed and accepted adjustment retry correction. Future
units/conversions, Suppliers, orders, receiving, batches/expiry, inventory counts,
transfers and valuation require
separate slices; a frozen unit label suffices for current manual stock.
[ADRs 0015–0018](../adr/README.md).

P4.4 Local Planogram Execution is **DONE/CLOSED**: Location Fixtures, independent
Company Planograms, immutable published revisions, explicit append-only Assignments,
target-Location Assortment validation and browser print. Live optional Stock context
uses Stock's public read port. Higher-level rollout, tasks/feedback and PDF output
remain future scope; browser verification establishes no physical printer acceptance.

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
