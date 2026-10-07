# P4.9 — Approved Article Recipe / Composition

**IMPLEMENTED LOCALLY · INDEPENDENT REVIEW REMEDIATION COMPLETE · TARGETED REVIEW
PENDING · SECURITY REVIEW PENDING · REMOTE CHANGED-COMMIT CI PENDING.** This record does not close P4.9. No P4.10
capability is selected. Work stays uncommitted/unstaged on main for review.

## Verified planning baseline

Before any edits: main, clean tree/index, no stash, one intended worktree; HEAD,
cached origin/main and live origin/main all
`e9515d61788bc2bd378ab21f48df9626a17cf8e9`. P4.1–P4.8 were canonically DONE/CLOSED,
with no active remediation or selected/ACTIVE P4.9. Migration chain ended at 0020;
0001–0020 were committed and unchanged. All five jobs in exact-HEAD
[CI 37456182116](https://github.com/RobinBrohl/storeos/actions/runs/37456182116)
succeeded. The preceding P4.9 selection plan and detailed implementation request
are the selected composition-only product contract.

## Delivered vertical slice

[ADR 0023](../adr/0023-approved-article-recipe-composition.md) and
[Production architecture](../architecture/production-recipes.md) describe identity,
lifecycle, declared batch, frozen Article references, exact thousandths, publication
replay, authorization and ownership. Migration 0021 is the only new migration.
Existing migration/dependency/lockfile bytes are preserved.

The normal API provides Company-wide manager Article selection, Recipe creation,
whole-draft saving, saved preview, exact history, replacement/discard, publication
and terminal retirement; employee APIs expose current approved compositions.
Flutter exposes those workflows with dirty-save publication blocking, deliberate
reference reselection, separate current warnings and session-safe controls.
Reading and work navigation create no business evidence.

## Verification protocol and evidence surfaces

Final-source results and exact counts are retained in ignored `.local/p49` logs
and the final review response, after all source/test/tool/document edits. A source
fingerprint covers tracked and non-ignored new files before/after verification.
No source edit after that run may reuse its results without rerunning verification.

| Surface | Independent evidence |
| --- | --- |
| Strict contracts / bounds / Web arithmetic | `packages/api_contracts/test/recipe_contracts_test.dart` |
| Lifecycle, snapshot preservation, replay, unit gates and Stock isolation | `apps/server/test/recipe_integration_test.dart` |
| 50/51 lines, order, maximum quantity, forged/duplicate/self references | Same PostgreSQL acceptance, using actual HTTP and saved/released composition |
| Current capability, Company/resource and real plugin denial | Same PostgreSQL acceptance; all thirteen routes and OpenAPI parity |
| Deterministic save/save, save/publish, save/discard, publish/publish, publish/retire, draft/retire, unit/publish and inactivity/publish | Company lock plus observed `pg_locks` queue; both orders; no fixed sleeps |
| Publication revision/pointer/audit faults | Injected test-only trigger failures; full Recipe/audit hashes unchanged |
| Clean/populated migration and late failure | Existing migrations, populated schema 1–4 work/Knowledge/Planogram/Stock/count receipts, catalog absence and rerun |
| Controller/editor safety | `apps/client_flutter/test/recipe_test.dart`; exact retry, deep immutability, invalid transport, dirty state, session replacement/delayed response and literal widgets |
| Real Flutter / HTTP / PostgreSQL | `recipe_client_journey_test.dart` invokes real Flutter adapters/controllers against the runtime API; independent Stock oracle |
| Real Chrome | `recipe_browser_test.dart` and `integration_test/recipe_test.dart`; author/preview/employee reads, unit mismatch/reselection, lost committed response, same-port server restart, exact retry, history, reactivation and retirement |
| Backup | `tool/recipe_acceptance.dart` seeds through authorized API; all three table hashes/counts included in encrypted source/restore comparison; restored visibility/history/replay/employee denial and terminal protections |
| Update/recovery | Pending migrations include 0021; upgraded HTTP seed and authorization/replay checks; pre-update restore/fencing retains existing contract |
| Regression | API/server/PostgreSQL/Flutter/design system tests, analyzers, format, Compose, release Web, four existing Chrome workflows, numeric E2E, encrypted backup/update, crypto and report diagnostics/redaction |

Run `scripts/recipes/Run-P49Checks.ps1` for the bounded PostgreSQL suite;
`-ClientJourney`, `-Browser`, `-BrowserRegressions`, `-Numeric`, `-FullRegression`
select the other repository acceptance paths. `-TestName` supports targeted repair.
Use already installed SDK/Docker/ChromeDriver paths. The wrapper creates a strictly
named disposable database, runs the runtime role and always drops run resources.
Backup/update use existing isolated wrappers with `-SkipPackageResolution`.
No dependencies are installed/upgraded, business evidence is never seeded by
unauthorized database writes, and the normal StoreOS database is untouched by the verified run. This does not
claim retrospective forensic proof of every historical implementation action.

## Focused independent/security review preparation

Security was not run during implementation. Review Company/Article/Recipe scope,
employee draft/history/operation exclusion, manager picker scope, current replay
authorization and actor/operation binding, frozen/current units, session replacement
and delayed responses, literal browser rendering, runtime grants/terminal guards
and restored authorization. Exact manager history context and explicit Article-ID
reselection are separate from frozen evidence. General runtime SQL grants remain
within the repository supported-writer threat model, not an arbitrary-writer API.

## Scope and remaining review gates

No yield, consumption, production run, recursive expansion, conversion, costing,
HACCP, allergens/nutrition, Task pins, acknowledgment, readership, events/outbox,
offline device writes or multi-site synchronization is introduced. P4.1–P4.8
closure stays intact. Targeted independent review, focused security review and changed-commit
remote CI must complete before any DONE/CLOSED statement.

## Independent review and bounded remediation — 2026-10-07

Chronology is retained: initial implementation claimed **152/152 local PASS**;
the independent adversarial review returned **CHANGES REQUIRED**. Its supported
core architecture, atomic publication/replay, authorization, immutable evidence,
exact quantities, Company isolation, unit semantics, concurrency, backup/restore
and migration rollback remain intact. That initial claim is historical, not the
final remediation assessment.

| Finding | Review disposition | Bounded correction / evidence |
| --- | --- | --- |
| F01 | MEDIUM product defect: initial discard stranded authoring | Existing new-draft command creates an empty next revision when active with no draft/publication; same Recipe, current active produced snapshot, manage authorization/version/Company lock. Exact initial recovery, discarded evidence, both race orders, real Flutter/HTTP and Chrome authoring coverage. |
| F02 | MEDIUM product defect: stale snapshot cache after reconciliation | Explicit accept clears transient snapshots. Stale and uncertain save widget tests verify resident mg/SKU/name/quantity, rendered labels, next save and publication; real two-editor HTTP journey changes kg to mg and preserves accepted mg. |
| F03 | LOW product defect: duplicate JSON names accepted | Opt-in iterative lexical name detector with decoded string/escape equality, per-object scopes and canonical syntax validation; Recipe writes return bounded 400 invalid_json with zero effects. All six write shapes, nested/escaped duplicates, independent array objects, transport/UTF-8 and unchanged unrelated APIs are covered. |
| F04 | LOW contract defect: copied broad OpenAPI error unions | All thirteen operations inventory actual supported paths. Exact status/code metadata and descriptions have an independent contract test; production HTTP parity probes cover representative business and transport outcomes. Revision-allocation collision is not reachable through the Company-serialized supported writer; creation has no publication receipt conflict. |
| F05 | MEDIUM evidence gap: empty observed Count fixtures | Supported P4.8 APIs seed two real StockLevels, approved Count/two lines, three rounds/observations (including superseded/recount), recording Account/Employee, six receipts, nonzero correction provenance and zero-variance outcome. Actual 0020 prefix is asserted before 0021; all seven Stock/Count tables have nonempty before/after hashes for migration and Recipe lifecycle independently. Existing backup assertions remain. |
| F06 | INFO accepted design | Durable publication identity is Company + operation UUID. Binding conflicts apply within that Company; current authorization precedes foreign receipt access. No global uniqueness change. Criterion 69 is assessed against this supported scope. |
| F07 | INFO accepted evidence limitation | Current/future verification uses disposable databases and records cleanup. Criterion 152 proves the verified remediation run's target discipline; its unqualified historical reading remains QUALIFIED. No retrospective proof is fabricated. |

Migration 0021 must retain SHA-256
`e371771ddfec4c8889d2995caaf3b53a0d8b4d05f8fe82fc410271f50bf37eca`.
Migrations 0001–0020, dependencies/lockfiles, branch and baseline HEAD are preserved.
No P4.10, commit, stage, push or Codex Security run is part of remediation.

The final-source inventory, exact executed counts, sanitized logs/reports, all
152 reassessed criteria (especially 31/34/69/129/148/152), per-operation error sets,
Count hashes and run cleanup are retained in
`.local/p49/remediation-evidence.md` and `.local/p49/remediation-final-summary.json`.
They are separate from the historical implementation reports. Final verification
requires an identical deterministic source inventory before/after every phase;
no inventoried file may be edited after verification starts.
