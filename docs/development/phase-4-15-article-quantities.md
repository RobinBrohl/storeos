# P4.15 — Explicit Article quantity semantics

## Q5 authentication subgate reconciliation — 2026-10-21

**Q13/Q5 AUTHENTICATION REGRESSION — CLOSED.** The later, independently approved
[closure addendum](phase-4-16-q13-q5-authentication-closure.md) records dedicated
plugin-token/session denial execution and exact-main CI for the ten protected
Article/Stock quantity endpoints. Earlier Q5 statements that dedicated plugin-token
journeys had not been separately executed remain historical statements; this dated
addendum supplies the later evidence without rewriting them.

**Full P4.15 Q5 remains OPEN for unproven operational requirements.** Exclusion of
plugin credentials from core routes does not demonstrate executable plugin
integration, plugin-specific operational readiness or broader third-party runtime
isolation. Q1–Q4/Q6, historical 7 PASS / 6 QUALIFIED / 0 FAIL and original skips,
failures and findings retain their individual dispositions. Q13 overall and
Q03–Q10 remain OPEN; Option B is mandatory; P4.16 is IN PROGRESS; P4.17 is UNSELECTED;
pilot/production readiness is NOT APPROVED. Earlier phase-selection statements
below are historical. This uncommitted documentation change awaits independent
review and separate publication authorization.

Status: **DONE/CLOSED — accepted implementation** at
`f4ffffaae235307424133c4ed280328df3e33f01`, with bounded test-only correction
`c132a88feb619268c65fae69d3eeff64d5363218` on `main`. Targeted functional APPROVE;
F01/F02/F03 CLOSED; SECURITY APPROVE, no required fixes. Final acceptance:
**7 PASS / 6 QUALIFIED / 0 FAIL**. Migration chain: **0001–0027**.
Feature CI 38317916154 and corrected main CI 38323585842 succeeded, all five jobs.
Original main CI 38320235803 remains a recorded FAILURE from the demonstrated
audit-privacy substring test defect. See the [final closure](#final-documentation-closure--2026-10-13)
for the complete chronology and exact URLs.
**Separate documentation-closure commit publication and its own exact-commit CI: PENDING.**
No publication or CI success is claimed for this local documentation commit.
**P4.16 is UNSELECTED.**

The following selection and authorization passage records the pre-publication
snapshot; subsequent publication, main integration, test correction and authorized
documentation closure are recorded at the end without rewriting historical results.

Selected 2026-10-12 on clean synchronized `main` at
`f83fece49671946f3a83240458464434ef09573c`; branch
`codex/p415-article-quantities`. One local implementation commit was authorized
on 2026-10-13 after final verification. Push, merge and closure are not authorized.

## Bounded contract

Inventory owns one explicit, immutable semantic anchor per Company Article:
dimension and base measurement unit (`g`, `kg`, `mL`, `L`, `piece`). Its
versioned profile contains at most sixteen direct Article packages. A package
has an opaque UUID, readable label and positive exact decimal content in the
anchor's base unit. Replacing packaging publishes a full immutable revision;
no nested packages, implicit contents or dimension changes exist. Article
identity, metadata/version and opaque `Article.unit` remain independent.
An erroneous profile can be permanently suspended with a reason. Suspension
retains revisions and evidence and prevents fresh semantic bindings/conversions;
it never changes a semantic anchor or Stock balance. Anchor replacement and
Stock rebasing require a future separately reviewed remediation contract.

Stock owns a single immutable prospective binding per StockLevel. An operator
explicitly declares what **one frozen Stock unit** means, choosing a compatible
measurement unit or a package from the exact current profile revision. The
binding retains the selected unit, label, revision, rational content, actor,
reason and checked Stock version. It does not rewrite opening/history, change
quantity, advance Stock version or assert that historical labels proved meaning.
Bindings cannot be replaced. Pre-binding evidence remains legacy evidence.
New levels also use explicit binding; configuration alone never auto-binds.

Inventory exposes a narrow transaction-scoped quantity read port. Stock never
reads Inventory quantity tables/repositories. Conversion uses fixed same-dimension
measurement ratios and direct package contents, with reduced BigInt rationals.
Input quantities/contents are decimal strings, at most twelve integer and six
fractional digits. Stock remains exact bounded thousandths
(`0..999999999999.999`). Nonrepresentable results and overflow are rejected;
no rounding or label inference. Fractional counts/packages are permitted only
when the resulting Stock target is exactly representable.

Read-only conversion preview pins the anchor, profile version, immutable binding,
current Stock version, input unit/quantity, reduced conversion ratio, absolute
target and delta. The reviewed command supplies that entire canonical preview
plus an operation UUID and required reason. Fresh correction recomputes and
compares the reviewed evidence in the authorized transaction. Changed packaging
revision, suspension, Stock version, binding or review values rejects with zero
writes. Nonzero targets use the existing `adjustment` movement kind, with a
separate typed immutable conversion record linked to that exact movement.
Zero delta still consumes an immutable receipt and audit, with no movement or
Stock version/timestamp change. UUID reuse with another payload/actor/scope
conflicts. Exact replay returns the original result before current lifecycle or
version checks, after fresh authorization. Evidence reads retain original facts.

Company profile APIs use `inventory.articles.manage`; Stock binding, preview,
correction and evidence APIs use `stock.levels.manage`. Fixed Admin only;
employee/viewer/auditor/plugin credentials cannot use these APIs. New Stock APIs
require actor and route Location equal to the configured execution Location
before resource/receipt lookup. Session revocation and Company authorization use
the existing Company transaction lock. Mutations and minimized audit are atomic.
No consumer needs events; no events/outbox effects are introduced.

Flutter provides explicit Article configuration/history/suspension and Stock
binding/preview/review/submit/evidence. Pending commands are deeply immutable,
memory-only and fenced by opaque session identity and Location; uncertain outcomes
allow only exact retry. A later rejected attempt cannot settle an earlier uncertain
attempt or discard its frozen identity/payload. A genuine session/Location replacement
still clears the previous context. Inputs cannot alter a pending/reviewed command. A confirmed
write with failed refresh remains confirmed. Browser reload/session replacement can lose
local uncertain tracking; durable evidence remains available on the server.

## Exclusions

Goods Receipt, automatic posting, Purchasing/Recipe conversions, consumption,
costing, density, cross-dimensional or cross-Article conversion, variable-weight
packs, nested packages, offline queues, synchronization, general unit framework,
anchor replacement, binding replacement and unrelated refactors are excluded.
Legacy unconfigured openings/corrections/counts and old replay contracts continue.
Existing immutable snapshots and receipts are not upgraded or reinterpreted.

## Acceptance and verification plan

1. Explicit profile configuration/revision/history and permanent reasoned suspension
   persist through real HTTP/PostgreSQL and Flutter.
2. kg/g, mL/L, cartons/pieces and bottle/volume conversions produce exact targets
   and readable immutable evidence; labels never select semantics.
3. Stale profiles/Stock, ambiguous or absent binding, invalid dimensions,
   nonrepresentable precision, invalid wire types and overflow reject atomically.
4. Authorization/revocation, configured Location/resource scope, audit rollback,
   zero effects, optimistic concurrency and exact replay after later writes or
   suspension are verified, including concurrent commands.
5. One forward-only `0027` migration preserves populated 0026 data/catalog and
   rolls back on late failure; PostgreSQL scope, immutability and final-state
   constraints and restricted runtime grants are exercised.
6. Flutter controller/session/uncertainty tests, real browser journeys, relevant
   regressions, all package analyzers/format, and isolated release Web build pass.
7. Encrypted backup/isolated restore retains profiles, revisions, bindings,
   conversion evidence/receipts and legacy records. Normal database and normally
   served client assets remain untouched.

Executed checks and limitations will be recorded below; historical evidence and
planned checks are not new passes. Independent reviews remain separate gates.

## Implemented files and operational use

Migration `apps/server/migrations/0027_article_quantities.sql` adds five tables:
Inventory's `inventory_quantity_profiles`, `inventory_quantity_revisions` and
`inventory_quantity_commands`; Stock's `stock_quantity_bindings` and
`stock_quantity_corrections`. Inventory owns the exact retained-factor SQL port
used by deferred integrity guards. Existing tables/migrations are not rewritten.
Runtime grants are SELECT/INSERT, with only profile `version`/`status` updates;
evidence is append-only and semantic anchor changes/deletion are rejected.

Shared wire contracts are in `packages/api_contracts/lib/src/article_quantities.dart`.
Inventory and Stock each have their own Domain/Application/repository files;
the sole cross-module Dart dependency is `ArticleQuantityPort`. Composition and
transport are in `article_quantity_routes.dart` and `platform_app.dart`. Existing
manual adjustment prevents reuse of a P4.15 operation UUID while preserving its
old retry behavior. Audit uses explicit quantity profile/binding identifiers and
versions; no quantities, package contents or reasons are copied into audit.

New API roots are `/api/v1/platform/articles/{articleId}/quantity` and
`/api/v1/platform/locations/{locationId}/stock/{levelId}/quantity`. The first has
GET current/retained `?version=`, GET `/history?before=` and POST
`/configure`, `/replace`, `/suspend`. The second has GET context, GET
`/evidence?after=` and POST `/bind`, `/preview`, `/correct`.
`platform.openapi.json`, `openapi.yaml` and the bounded generator/test document
the strict DTOs. Duplicate JSON names, unknown fields/query keys, numeric quantity
JSON, invalid unit/dimension/package references and non-UTC evidence are rejected.

In Flutter, **Artikel → Mengenbedeutung** configures the immutable base unit and
direct package contents, shows history and permits reasoned terminal suspension.
**Bestand → Andere Einheit / Nachweise** declares one frozen Stock unit, previews
an absolute alternate-unit target, shows the exact target/delta/factor and pinned
versions, then requires explicit confirmation. Review fields and uncertain
commands are locked; exact retry keeps UUID, reason and review unchanged.
Confirmed results survive refresh failure. Replacement sessions/Locations clear
and hide the previous context. The response adapter explains precision, scope,
revision/binding and suspension failures. Reload explicitly opens a new decision.

## Initial implementation verification — 2026-10-12 (before independent review)

All commands used pinned Dart 3.13.4 / Flutter 3.47.5, existing lockfiles and
isolated verification resources. No package resolution or dependency upgrade ran.

| Check | Executed result |
| --- | --- |
| Final focused contracts | 4 PASS: decimal/type/precision/package limits, deep retry immutability and strict immutable evidence validation. |
| Final focused server | 15 PASS: exact measurement/direct packaging, frozen binding after packaging change, stale/ABA review, overflow/nonrepresentability, zero receipts, replay after later writes/restart/suspension, role/Location/resource/session authorization, audit rollback, direct SQL scope/factor/evidence/immutability guards and 52-record pagination. Includes isolated `/health` and `/ready` smoke reads. |
| Final Flutter controller/widget tests | 5 PASS: immutable pending commands, duplicate suppression, exact retries, same-account held session replacement, Location fencing, confirmed refresh failure and locked visible review. |
| Real Flutter/HTTP/PostgreSQL journey | PASS: explicit configuration/binding, lost committed response, exact retry, original evidence, profile replacement/history and suspension. |
| Final actual Chrome | PASS: kg/g, mL/L, cartons/pieces and bottle/volume through real UI/API/PostgreSQL; committed response loss/restart/retry, stale Stock and packaging reviews, fractional precision rejection, literal package labels and historical evidence after suspension. |
| Final populated migration/recovery | PASS: populated actual 0026 data/catalog preserved, intentional post-grant deferred 0027 fault fully rolled back, valid forward apply/idempotency, encrypted backup/fenced isolated restore, fresh authorized restored reads/replay and unchanged source. A fresh login adds exactly its own audit; replay adds none. |
| Broad package regression | 327 API contracts + 729 server + 2 design system + 419 Flutter = 1,477 PASS. Server reported 21 conditional SKIP. Nested real HTTP controller journeys also passed. |
| Analyzers/format | All four package analyzers: no issues. Final formatting: 396 files, zero changes. |
| Web release / Compose | PASS: release build with `--no-pub --no-web-resources-cdn --output .local/p415/web-release`; Compose configuration valid. |
| Isolation and Git checks | PASS: 39 normally served Web assets retain the recorded hashes and original earlier write times; no verification writer targeted the normal database. Disposable projects/containers/volumes and isolated restore target removed. Applied migrations 0001–0026, dependencies and lockfiles have no Git changes. Index remains empty. |

The broad package run started before the final P4.15 audit-field, identity-conflict,
response-scope and evidence-validation refinements. Final focused, Chrome and
migration/recovery checks cover those refinements; the broad legacy suites were
not repeated afterward. All package analyzers/format and the Web release build
completed against the resulting source. No exact-commit CI or independent review
is inferred from any local check.

Sanitized local logs are `.local/p415/{regression,focused-final,journey,browser-final,migration-final}.log`.
`.local/p415/source-final.json` inventories changed technical files and hashes;
`.local/p415/normal-web-assets.json` records the normally served asset comparison.
Local logs/fixtures/manifests are ignored artifacts, not committed delivery records.
Older failed migration-syntax and browser-focus attempts remain local history;
their errors were corrected and are superseded by the successful runs above.

## Historical qualifications and gates before publication

This section retains the earlier verification/publication snapshot. Current gate
completion and all six retained qualifications are reconciled in the final closure.

The initial broad run's 21 skips are separately opted-in browser/recovery/client
journeys across current and earlier slices; they are not failed tests or automatic
passes. P4.15's browser and encrypted migration/recovery opt-ins passed separately.
The initial implementation/remediation did not freshly rerun the complete historical
host matrix; final-source skip reconciliation is recorded below. Historical numeric
browser stages, global backup/update wrappers, native devices, physical scanners
and accessibility remain qualified unless explicitly recorded as newly executed.
No broad production or hardware readiness is claimed.
Plugin-specific P4.15 token journeys were not separately exercised; the new routes
use the existing session-only authentication boundary, with no plugin grants.

One anchor per Article and one prospective binding per StockLevel are immutable.
Suspension is permanent. Correcting an erroneous anchor/binding in place, rebasing
Stock or resuming a suspended profile is deliberately unavailable. Existing legacy
manual corrections/counts remain available; historical labels still prove no
quantity semantics. Fractional pieces/packages are permitted only when their
target fits exact Stock thousandths. Pending recovery is memory-only; browser reload or
session replacement can lose unconfirmed client tracking without undoing a
committed command. Operators inspect durable evidence before a new decision.

Initial independent functional review returned **CHANGES REQUIRED** for F01–F03.
On 2026-10-13 the user reported targeted independent **APPROVE**, F01/F02/F03
**CLOSED**, and focused Codex Security **SECURITY APPROVE**, with no required
security remediation. These external approvals are distinct from local executed
verification; no reviewer identity, report URL or review test total was supplied.
F04 remains nonblocking existing Location-picker technical debt. The final-source
verification and local implementation commit are authorized. Push, merge and
DONE/CLOSED require later authorization; exact-commit remote CI remains pending.

Historical remediation Git handoff: branch `codex/p415-article-quantities`, HEAD
`f83fece49671946f3a83240458464434ef09573c`, no commits since the baseline,
all changes unstaged/uncommitted, no configured branch upstream. Local `main` and
cached `origin/main` remain at the same SHA; live remote `main` matched at startup.

## Bounded functional remediation — 2026-10-12

Initial independent functional verdict: **CHANGES REQUIRED**. This remediation addresses
only F01–F03 and necessary tests/documentation. These are local implementation
and verification findings from the 2026-10-12 remediation. The subsequent targeted
functional **APPROVE** and F01/F02/F03 **CLOSED** were reported on 2026-10-13.

| Finding | Remediation | Local acceptance |
| --- | --- | --- |
| F01 — uncertain command lost after rejected retry | The controller remembers uncertainty across attempts. A later definitive rejection retains the deeply frozen operation UUID, payload, kind and review. Fresh first-attempt rejection still requires a new decision; genuine session/Location replacement still clears the old context. | Controller regressions cover 400/403/409/422 after a lost committed response, restored exact replay, first-attempt rejection and session replacement. Real HTTP/PostgreSQL and browser assertions require a real 403 under a temporarily different configured execution Location, followed by restored authorization using the same session and identical request bytes. Exactly one receipt, adjustment movement and correction audit entry must exist. |
| F02 — removed package dropdown selection | A missing input option becomes an empty selection with an explicit reselection message. Profile revision changes reset retained Flutter FormField state. Confirmed binding/result evidence remains intact; reload cannot silently choose a replacement. Preview/binding controls require a valid explicit selection. | Widget regression passes for package binding at revision 1 followed by package removal at revision 2, preserved binding/result, empty selected value and disabled preview until reselection. A fresh measurement-unit review uses revision 2 and the original binding factor. The browser exercises the same race through a competing real API profile replacement. |
| F03 — Location UUID spelling inconsistency | Stock quantity entry points validate and canonicalize the route Location before authorization, resource access, audit and receipt/replay scope comparison. Configured Location identity uses the same canonical spelling. | Real HTTP/PostgreSQL regression passes for lowercase, uppercase and mixed-case UUIDs containing letters across context, bind, preview, correct, evidence and exact replay. Malformed/foreign Locations, foreign resources/actors, forbidden roles and revoked sessions still reject; no duplicate receipt, movement, audit or balance change occurs. |

No architectural decision changes: ADR 0029, immutable anchors and bindings,
exact arithmetic, prior contracts, authorization and migration 0027 remain intact.
All pre-remediation repository files outside the eleven listed below retain their
recorded hashes. No commit, staging, push, merge or DONE/CLOSED transition occurred.

Exact remediation files:

- `apps/client_flutter/lib/src/application/article_quantity_controller.dart`
- `apps/client_flutter/lib/src/ui/article_quantity_dialog.dart`
- `apps/server/lib/src/stock/stock_quantity_service.dart`
- `apps/client_flutter/test/article_quantity_test.dart`
- `apps/client_flutter/test/article_quantity_http_journey.dart`
- `apps/client_flutter/integration_test/article_quantity_test.dart`
- `apps/server/test/article_quantity_integration_test.dart`
- `apps/server/test/article_quantity_journey_test.dart`
- `docs/development/phase-4-15-article-quantities.md`
- `docs/HANDOVER.md`
- `docs/roadmap/status.md`

Executed remediation checks use isolated resources, pinned SDKs and existing
lockfiles, without package resolution:

| Check | Result |
| --- | --- |
| Focused quantity contracts/server/Flutter | 4 / 16 / 11 PASS; no skips. |
| Affected server regressions | 98 PASS: Stock, Stock Count, Article and merchandising HTTP/PostgreSQL suites; includes existing nested real client journeys. |
| Affected Flutter regressions | 136 PASS: quantity, session, Article, assortment, Stock and Stock Count; includes the eleven focused quantity cases. |
| Real HTTP/Flutter controller journey | PASS on final fixture: committed response loss → actual 403 → restored same-session exact replay, one durable effect, history/revision/suspension. |
| Actual Chrome journey | PASS: all original mass/volume/packaging workflows, same-session uncertain → 403 → exact replay, stale Stock/profile revisions and package removal after confirmed binding. Removed selection stays empty after reload; preview stays disabled until explicit reselection. Binding revision 1/factor 12 survives revision 2 package removal; fresh piece target produces exactly 2 Stock units. All exception assertions remain enabled. |
| All four package analyzers and formatting | PASS: no issues; 396 files, zero formatting changes. |
| Web release | PASS: `--no-pub --no-web-resources-cdn --output .local/p415/remediation/web-release`; normal served output preserved. |
| Isolation / preservation / Git | PASS: 39 normal served asset hashes unchanged; disposable verification resources cleaned up; migration 0027, every other pre-remediation file, dependencies and lockfiles unchanged outside the eleven listed remediation files. HEAD remains the baseline and the index is empty. |

The new retry-scope fixture initially exposed an **existing, unrelated** six-pixel
overflow in the fixed-width Stock Location picker for the label
`Temporary execution scope` (`stock_section.dart`, unchanged by remediation).
The fixture now uses `Retry scope`; the journey explicitly selects `Home` because
registry order is not guaranteed. Exception assertions and framework error chaining
remain enabled. The long-Location-name layout limitation remains outside F01–F03;
no product layout fix or error suppression was introduced. Failed diagnostic runs
are retained, not treated as passes.

Sanitized ignored logs/manifests are under `.local/p415/remediation/`:
`focused.log`, `server-regressions.log`, `client-regressions.log`,
`journey-final.log`, `browser-verified.log`, `analyzers-format-final.log`,
`web-release.log` and the pre-remediation file/normal-asset hash inventories.
Populated 0027 migration, encrypted backup/restore and broad historical matrices
were not rerun for these runtime/UI fixes; their earlier executed evidence above
remains historical evidence. The subsequent external functional and Security
approvals and final-source verification are recorded below.

## Final approval and implementation verification — 2026-10-13

This is the historical local verification snapshot before publication and main CI.
Its pending statements are superseded by the final closure below; its executed
results, failed diagnostic attempts and conditional-skip accounting are retained.

Review provenance: the user supplied targeted independent functional **APPROVE**,
F01/F02/F03 **CLOSED**, focused Codex Security **SECURITY APPROVE**, and no required
security remediation. Local verification does not manufacture those approvals.
F04 is **ACTIVE / NONBLOCKING** [technical debt](technical-debt.md#p415-nonblocking-location-picker-debt),
not an expansion of the implementation. The accepted technical source is unchanged
from the completed remediation; only affected documentation was edited here.

Final-source regression and all required separate conditional acceptance passed.
No technical source or test assertion changed during finalization. Only affected
documentation was updated before staging the 70 intended implementation files.
The local commit's parent is the stated baseline; obtain its exact SHA from the
Git handoff/commit object. Publication, remote CI and phase closure remain pending.

| Final-source check | Executed result |
| --- | --- |
| Four complete package suites | 328 API contracts + 732 server + 2 design system + 425 Flutter = **1,487 PASS**. Server package runner reported **21 conditional SKIP**; no database suite was skipped for missing PostgreSQL. Nested real HTTP client journeys also passed. |
| Analyzers/format | All four analyzers passed with no issues; 396 files checked, zero formatting changes. |
| Web release / Compose | PASS: isolated `.local/p415/web-release`, `--no-pub --no-web-resources-cdn`; Compose configuration valid. Normal served assets were not rebuilt. |
| P4.15 actual Chrome | PASS: real UI/HTTP/PostgreSQL mass/volume/direct packaging, reviewed exact targets, committed response loss, real 403 and restored exact replay, stale Stock/package revisions, removed input package after confirmed binding, literal labels and suspended historical evidence. |
| P4.15 HTTP/PostgreSQL controller | PASS: production adapters/services, same-session frozen lost-response/rejected-retry/replay with one durable effect, explicit binding and revision/suspension evidence. |
| Populated 0027 encrypted recovery | PASS: populated 0026 records/catalog preserved, intentional post-grant deferred rollback, valid forward apply/idempotency, encrypted backup/fenced restore, fresh restored reads and original authorized correction/zero receipt replay; unchanged source database. |
| Changed-chain prior recovery opt-ins | **3 PASS**: P4.12, P4.13 and P4.14 populated encrypted recovery cases executed with the 0027 forward chain. |
| Remaining host opt-ins | **15 PASS** across thirteen file targets: controller and actual Chrome host journeys. The final Task Planogram case passed unchanged with a fresh driver after the initial pre-journey Chrome startup failure described below. |
| Historical/API/dependency preservation | PASS: 26 historical migrations and eight dependency/lock files match baseline Git blobs. All 176 prior API paths and 235 schemas/other components are unchanged; only ten quantity paths and fifteen quantity schemas are added. |

Runs used unique disposable PostgreSQL projects/databases and existing restricted
runtime credentials, pinned Dart 3.13.4 / Flutter 3.47.5 and existing lockfiles.
No package resolution, dependency upgrade, normally operating database writer,
normal-container replacement or normal Web-output build ran. The technical-source
hash inventory is unchanged throughout final verification. All earlier failed
implementation/remediation diagnostic runs remain historical failures, superseded
only by their identified successful reruns, not counted as passes.

The first final host run completed fourteen cases, then failed to create the last
Chrome session (`SessionNotCreatedException`: Chrome instance exited). The
application journey had not started. A fresh disposable project/ChromeDriver ran
that unchanged Task Planogram case successfully. The startup cause was not
reproduced or conclusively established; local Chrome 155 / ChromeDriver 154 emitted
a compatibility warning. No source/assertion was changed, no exception was
suppressed, and the failed run/crash report are retained alongside the successful
rerun. Exact-commit CI's configured matching Chrome/driver installation is still
a separate pending check.

### Conditional-skip reconciliation

The package runner result remains **1,487 PASS / 21 conditional SKIP**. The following
**21 separate opt-in executions PASS / 0 SKIP / 0 unresolved FAIL** supply their
acceptance; they do not relabel the skipped package-run entries as passes. Exact
twenty-one test names/reasons are retained in `conditional-skips.json`.

| Skipped test group | Count | Separate final-source execution |
| --- | --- | --- |
| P4.15 quantity controller, Chrome and populated encrypted recovery | 3 | `journey.log`, `browser.log`, `migration.log`: PASS. |
| P4.12 / P4.13 / P4.14 populated encrypted upgrade/recovery | 3 | `prior-recovery.log`: 3 PASS with the final 0027 forward chain. |
| Preparation Assignment controller and Chrome | 2 | `hosts.log`: both PASS. |
| Purchasing controller and Chrome | 2 | `hosts.log`: both PASS, including delivery evidence. |
| Recipe controller and Chrome | 2 | `hosts.log`: both PASS. |
| Preparation Batch controller and Chrome | 2 | `hosts.log`: both PASS. |
| Shift Transfer controller and Chrome | 2 | `hosts.log`: both PASS. |
| Stock Count controller and Chrome | 2 | `hosts.log`: both PASS. |
| Knowledge, Task Knowledge and Task Planogram Chrome | 3 | First two PASS in `hosts.log`; unchanged final case PASS in `task-planogram-rerun.log` after the preserved startup failure. |

These executions used the existing assertions/oracles, real adapters, HTTP,
restricted PostgreSQL and actual headless Chrome. No missing-database skip was
accepted as integration evidence. Remaining broader/hardware qualifications are
listed explicitly below.

The final local acceptance matrix uses the seven bounded contract criteria above,
plus six explicit qualifications. It is not an invented independent review score;
external reviews supplied verdicts and finding dispositions, without numeric totals.

| Criterion from the bounded verification plan | Evidence | Result |
| --- | --- | --- |
| 1 — Explicit persisted configuration, revisions/history and suspension through API/UI | Full quantity server/Flutter suites; final controller and Chrome journeys; recovery retains suspended profile/history. | PASS |
| 2 — Exact mass, volume and direct packaging targets/readable evidence; inert labels | Quantity Domain/contracts/integration cases and actual Chrome kg/g, mL/L, cartons/pieces and bottle/volume. | PASS |
| 3 — Stale/ambiguous/unbound/incompatible/inexact/overflow/wire rejection is atomic | Full focused cases inside final suites; stale Stock/profile and removed-package Chrome cases; integrity/rollback oracles. | PASS |
| 4 — Authorization, canonical Location/resource scope, session fencing, concurrency, audit and exact replay | F01–F03 regressions, revocation/conflict/concurrency/zero-receipt tests, real 403/restored exact replay and restored receipt evidence. | PASS |
| 5 — One forward-only 0027 preserves populated 0026 and restricted database protections | Final populated migration/late-fault rollback; four quantity/changed-chain encrypted recoveries; 26 historical migration blobs/bytes preserved. | PASS |
| 6 — Client/UI/regression/analyzers/format and isolated release build | All four complete suites: 1,487 PASS; 21 explicit separate opt-ins; four clean analyzers; 396 formatted files; Web release and Compose PASS. | PASS |
| 7 — Encrypted fenced restore preserves new and legacy evidence; normal resources protected | Final P4.15 recovery with hashes/fence/fresh authorization/original replay; unchanged 39 normal asset hashes/timestamps and original normal container IDs; all disposable projects removed. | PASS |

Final local grouped acceptance: **7 PASS / 6 QUALIFIED / 0 FAIL**, across thirteen
rows. F01/F02/F03 are CLOSED by the supplied independent targeted APPROVE; focused
Security APPROVE has no required remediation. F04 remains nonblocking open debt.

| Qualification | Retained boundary |
| --- | --- |
| Q1 — memory-only recovery | Browser/process reload or genuine session/Location replacement can lose uncertain client tracking. Durable original receipts/evidence remain; a live uncertain command permits only exact retry, including after a later rejection. |
| Q2 — immutable semantics | One Article anchor and one prospective Stock binding remain immutable. Suspension is permanent; redefinition, rebinding, resumption or rebasing require a separate reviewed contract. |
| Q3 — F04 debt | Pre-existing long-name Stock Location-picker overflow remains ACTIVE / NONBLOCKING. No layout functionality was changed in this slice. |
| Q4 — physical/readiness evidence | Native devices, physical scanners/printers, accessibility and broad production/operator readiness are not established by these local browser/API checks. |
| Q5 — plugin-specific execution | Quantity routes use the existing session-only boundary without plugin grants; dedicated P4.15 plugin-token journeys were not separately executed. |
| Q6 — broader acceptance wrappers | Historical numeric browser stages and global backup/update acceptance wrappers were not freshly rerun here. Dedicated populated P4.15 encrypted recovery and changed-chain prior recoveries are explicitly executed; they do not manufacture results for the broader wrappers. |

Goods Receipt, automatic Stock posting, Purchasing/Recipe conversions, production
consumption, costing, density, cross-Article/dimensional conversion, variable-weight
packs, offline queues and synchronization remain outside the accepted contract.

Sanitized ignored evidence is in `.local/p415/final-2026-10-13/`: `regression.log`,
`browser.log`, `journey.log`, `migration.log`, `prior-recovery.log`, `hosts.log`,
`task-planogram-rerun.log`, `flutter-crash-task-planogram.log`,
`conditional-skips.json`, `compatibility-preservation.log`, pre/final file and
normal-Web inventories, intended-path inventory and staged diff. API compatibility
was compared semantically to the baseline, not inferred from textual reformatting.
Private local credential/generated-file checks and the complete staged inventory
are required before the one authorized commit. None of these local results claims
remote CI, production deployment, push, merge or P4.15 DONE/CLOSED.

### Historical publication procedure before authorization

This delivery authorizes one local implementation commit only. P4.15 remains
publication/remote-CI pending, with no merge or DONE/CLOSED transition.

After separate push authorization:

1. Verify a clean branch, the local implementation SHA and live `origin/main`.
   Confirm the remote feature branch is absent or a safe ancestor of the intended
   commit. If another writer changed either branch, reassess before publication.
2. Publish only `codex/p415-article-quantities` with a normal non-force push.
   Keep `main` unchanged and do not merge implicitly.
3. Select the `CI` push run whose `headSha` exactly equals the implementation SHA;
   a different commit or synthetic pull-request merge SHA is not exact-commit evidence.
4. Require all five jobs in `.github/workflows/ci.yml` to complete successfully:
   `dart`, `flutter`, `numeric-guided-work-e2e`, `backup-restore-acceptance`, and
   `update-recovery-acceptance`. Inspect failures and conditional skips rather than
   inferring success from dispatch or an unrelated green run. P4.15 browser and
   encrypted quantity recovery opt-ins retain their explicit local acceptance records.
5. Record that exact SHA, run URL, event, attempt and job outcomes before proposing
   any separately authorized merge/publication closure. No remote CI result is claimed here.

## Final documentation closure — 2026-10-13

P4.15 is **DONE/CLOSED — accepted implementation**. Implementation commit:
`f4ffffaae235307424133c4ed280328df3e33f01` (`Add explicit article quantities and exact stock targets`).
The bounded test-only correction is `c132a88feb619268c65fae69d3eeff64d5363218`
(`Fix quantity audit privacy assertions`), whose parent is the implementation.
This documentation-only closure began on clean synchronized `main` at that fix SHA.
The feature branch remains preserved at the original implementation SHA.

Independent targeted functional review returned **APPROVE**; F01/F02/F03 are
**CLOSED**. Focused Codex Security returned **SECURITY APPROVE**, with no required
fixes. These are the user-supplied independent verdicts recorded above, not new
reviews manufactured by this closure. No unchanged production code was re-reviewed.

### Publication and CI chronology

| Event | Exact source and result |
| --- | --- |
| Implementation selection and commit | Selected on `f83fece49671946f3a83240458464434ef09573c`; implementation `f4ffffaae235307424133c4ed280328df3e33f01`, 70 files. |
| Feature publication | One non-force feature push; [CI 38317916154](https://github.com/RobinBrohl/storeos/actions/runs/38317916154), `push`, `codex/p415-article-quantities`, exact implementation SHA, attempt 1: SUCCESS, all five jobs. |
| Main integration | Authorized fast-forward-only integration and one non-force main push to the same implementation SHA; no new merge commit or content change. |
| Original main CI failure | [CI 38320235803](https://github.com/RobinBrohl/storeos/actions/runs/38320235803), `push`, `main`, implementation SHA, attempt 1: FAILURE. Dart failed; the other four jobs succeeded. Server: 731 PASS / 1 FAIL / 21 conditional SKIP. Subsequent HTTP readiness/login smoke was skipped. This failed run was not rerun or relabeled as success. |
| Bounded test-only correction | `c132a88feb619268c65fae69d3eeff64d5363218`, one changed file: `apps/server/test/article_quantity_integration_test.dart`. No production, migration, API schema, Flutter, dependency, CI configuration or unrelated-test change. One non-force main push. |
| Corrected exact-commit main CI | [CI 38323585842](https://github.com/RobinBrohl/storeos/actions/runs/38323585842), `push`, `main`, exact correction SHA, attempt 1: SUCCESS, all five jobs. Both the structural privacy regression and the original kg/g/replay integration case passed. Server: 733 PASS / 21 conditional SKIP. |
| Separate documentation closure | One local documentation-only commit is authorized. Its publication and its own exact-commit CI remain PENDING. Its SHA is supplied by the Git handoff; no push or CI success is claimed for it here. |

The original failure was a demonstrated test-assertion defect at the then-current
`article_quantity_integration_test.dart:304`: serialized audit JSON was required
not to contain `1250`. The valid Article UUID
`2db8c724-12b2-46ec-a512-e4125093bd5c` contained those digits. The correction matches
decoded audit fields against exact per-action allowed keys and types. Canonical
UUIDs and positive integer version metadata can contain those digits; business
quantities, factors, reasons, labels, nested contents and free text are rejected
as extra fields or invalid values. The integration fixture uses the demonstrated
UUID deterministically. Five audit records, Stock/evidence integrity and exact
replay remain asserted. The failed CI URL is also retained in the test comment.

The correction passed three isolated PostgreSQL integration repetitions with
ordering seeds 41501, 41502 and 41503: **12/12 each**. The full affected server
suite passed **733 tests / 21 conditional SKIP**; analyzer reported no issues;
formatting checked **223 files / 0 changes**. The first sandboxed compiler attempt
was blocked before loading tests by a temporary-file permission error; the same
privacy test passed with the required execution permission. No assertion was
disabled or weakened to bypass an application failure. Disposable PostgreSQL
resources were removed; normal container identities and 39 served Web asset
hashes/timestamps remained unchanged. No normal database writer was used.

Earlier final-source verification remains **1,487 package PASS / 21 conditional
SKIP**, with **21 separately executed opt-ins PASS** as reconciled above. Those
skipped entries are not converted into package passes. The later server-only
test-fix result and exact-commit CI are separate executed evidence; no new combined
four-package local total is inferred. Migration `0027_article_quantities.sql`
and historical 0001–0026, semantic anchors, bindings and existing contracts are
unchanged by the correction and this documentation closure.

All five configured jobs completed SUCCESS in corrected main CI:

| Job | Main CI 38323585842, exact `c132a88feb619268c65fae69d3eeff64d5363218`, attempt 1 |
| --- | --- |
| dart | SUCCESS |
| flutter | SUCCESS |
| numeric-guided-work-e2e | SUCCESS |
| backup-restore-acceptance | SUCCESS |
| update-recovery-acceptance | SUCCESS |

### Retained acceptance and boundaries

Final acceptance remains **7 PASS / 6 QUALIFIED / 0 FAIL**. This is the bounded
local acceptance matrix, not an invented independent review score. The six
qualifications remain explicit:

| Qualification | Closure disposition |
| --- | --- |
| Q1 — memory-only recovery | Browser/process reload or genuine session/Location replacement can lose uncertain client tracking. A live uncertain command retains frozen identity/payload through later rejection and permits exact retry only; durable server receipts/evidence remain. |
| Q2 — immutable semantics | One Article anchor and one prospective Stock binding remain immutable. Suspension is permanent. Anchor replacement, rebinding, resumption or Stock rebasing needs a separate reviewed contract. |
| Q3 — F04 debt | Pre-existing long-name Location-picker overflow remains ACTIVE / NONBLOCKING [technical debt](technical-debt.md#p415-nonblocking-location-picker-debt). It was not fixed or suppressed in this slice. |
| Q4 — physical/readiness evidence | Native devices, scanners/printers, accessibility and broad production/operator readiness are not established by browser/API or CI checks. |
| Q5 — plugin-specific execution | Quantity routes retain the existing session-only boundary without plugin grants. Dedicated P4.15 plugin-token journeys were not separately executed. |
| Q6 — broader acceptance boundaries | The historical local verification did not freshly execute numeric/global backup/update wrappers. The feature and corrected-main CI now separately execute those configured jobs successfully. This does not broaden their declared acceptance, replace dedicated P4.15 Chrome/encrypted-recovery evidence or establish arbitrary recovery, hardware or operator readiness. |

The delivered contract is explicit quantity configuration/binding and reasoned,
reviewed exact absolute manual Stock targets, with compatible mass/volume/count
units and bounded direct Article packaging. It does not deliver automatic Goods
Receipt, automatic Stock posting, Recipe/Purchasing conversion, production
consumption, POS ingestion, costing, density, cross-dimensional/cross-Article
conversion, variable-weight packs, offline queues or synchronization. Inventory
and Stock ownership/public ports, self-hosted modular-monolith operation and
operator data ownership remain intact; the long-term vision and strategic roadmap
are unchanged. **P4.16 is UNSELECTED.**

### Documentation publication gate

**The separate documentation-closure commit publication and its own exact-commit
CI remain PENDING.** This local documentation reconciliation does not claim a
push or CI result for its own commit. No full application regression rerun is
needed or claimed for Markdown-only changes.

Documentation verification checked 250 local links/heading anchors without errors,
current status consistency, the nine-file Markdown-only scope and preserved
historical verification/qualification blocks, ADR decision and strategic roadmap.
The three CI run identities, exact SHAs, events, branches, attempts and outcomes
were rechecked; external approvals remain the supplied review evidence.

After separate publication authorization, fetch and verify clean local `main`,
the exact local documentation SHA, its parent
`c132a88feb619268c65fae69d3eeff64d5363218` and unchanged remote `main`. Stop on
unexpected work or protection requiring another path. Push that verified result
once without force to `origin/main`; verify the remote SHA; select its exact-SHA
`main`/`push` CI run and require completed SUCCESS for all five configured jobs.
Record that documentation SHA, URL, event, attempt and results separately from
implementation/correction CI. No next capability is selected by that step.
