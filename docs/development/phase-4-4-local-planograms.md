# P4.4 Local Planogram Execution — local development evidence

Date: 2026-10-04. Current delivery: **IMPLEMENTED / REVIEW APPROVED / CHANGED-COMMIT CI NOT YET GREEN**.
Implementation is committed at `cd7669ed7de2751d4dc97c2724a0d11d9f674f51`; the CI correction is uncommitted.
Earlier sections preserve historical implementation/remediation evidence. The
appended CI failure remediation section supersedes their pending-review/uncommitted
disposition. This is not a DONE/CLOSED declaration.

## Authoritative contract and baseline

The user supplied the complete P4.4 product contract and explicitly confirmed: “Use the pasted contract as the complete architecture.” The baseline repository's unselected-P4.4 statement was superseded by that instruction, not by an invented planning record. Baseline dynamically verified before editing: main, clean tree/index, HEAD and cached/live origin/main at ed91a05ccbe9b61afaf92914c34f844aff64f638, one intended worktree, no stash, migrations through 0015, and canonical P4.3 DONE/CLOSED with independent APPROVE/changed-commit CI. No earlier partial Merchandising implementation existed. The dated health audit/debt had no blocker for this bounded slice; M3/M4 containment, touched diagnostic L6 and migration-refusal L7 were handled locally.

## Implemented scope

[ADR 0018](../adr/0018-local-planogram-execution.md) records the durable decisions. Six tables own local physical Fixtures, independent Company Planograms, versioned drafts and immutable published/discarded structure, and explicit append-only deployment. Publication never updates a Fixture. One revision serves multiple Fixtures. Live Inventory/Assortment and Stock context stays behind owner ports, never snapshots or foreign repository reads. Employee access is limited to local active Fixtures/current instructions/print. All ten mutation operations are authorized and audited atomically; no event/outbox or generic receipt table was added.

Management UI supports creation, reuse, ordered zone/placement authoring, active Article search, draft issues, positive facings, Save/Publish/Assign as separate actions, retirement/discard and history/print. Employee UI distinguishes missing Stock, zero, unavailable live reads, deactivation and unit divergence. Uncertain Publish/Assign identity is immutable and session-bound; desired-state uncertainty requires authoritative review.

## Original implementation verification results (historical)

| Check | Result |
| --- | --- |
| api_contracts | 74 tests PASS, including 5 P4.4 tests |
| server, real isolated PostgreSQL | 215 tests PASS, including 10 P4.4 integrations and 4 added migration-refusal cases |
| client_flutter | 237 tests PASS, including 17 P4.4 controller/widgets and 1 bounded HTTP error-display test |
| design_system | 2 tests PASS |
| Repository package total | **528 PASS; 0 failed; no package tests skipped** |
| Separately invoked P4.4 Flutter/HTTP/PostgreSQL journey | 1 PASS; executes within server integration and is excluded from the package total |
| Final targeted Merchandising PostgreSQL run | 10 PASS, with the separately invoked journey passing again |
| All four analyzers / format | Clean; no issues; zero formatter changes |
| Compose / release Flutter Web | PASS; --no-pub and existing pinned SDK/dependencies |
| PowerShell checks | 7 scripts PASS: setup, backup crypto, backup/update/capacity report redaction, E2E diagnostics, touched P4.4 harness diagnostics |
| Backup/restore acceptance | PASS; six Merchandising table counts and evidence hashes match; prior task/Stock evidence preserved |
| Update/recovery acceptance | PASS; pending migration chain through 0016, idempotent second run, protected evidence and isolated pre-update recovery |
| Browser print | PASS; real renderer and Web adapter, 10 zones / 100 placements, 20 A4 landscape pages, Unicode/escaping, bounded text coordinates, no Stock quantity; print invoked once |
| Git / dependency integrity | diff --check PASS; 0001–0015 unedited with unchanged Git content and existing checkout endings; no pubspec/lockfile changes |

Real tests used strictly named temporary databases on the existing PostgreSQL Compose instance, scoped schemas and real HTTP with persisted Articles/Assortment. The normal StoreOS database was not seeded, migrated, backed up, restored into or written. DBs, schemas, servers, WebDriver sessions, helper processes, temporary HTML/PDF/JS, private fixture manifests and backup artifacts were cleaned. Sanitized ignored reports/logs remain as development evidence.

The browser harness inspects printable DOM/CSS and a temporary browser-rendered PDF for pagination/text boundaries, then separately executes the actual adapter against a window/print spy requiring about:blank. Repeated table headers carry zone context on continuation pages. This inspection creates no product PDF feature/dependency and makes no physical-printer fidelity claim.

## Reproduction

Use existing local SDK/dependencies and configured Compose secrets. No package resolution/install is required:

```powershell
./scripts/merchandising/Run-P44Checks.ps1 -FullRegression
./scripts/merchandising/Test-PlanogramPrint.ps1
./scripts/merchandising/Test-P44HarnessDiagnostics.ps1
./scripts/backup/Run-BackupRestoreAcceptance.ps1 -SkipPackageResolution -DartPath '<existing-dart>' -DockerPath '<existing-docker>'
./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -SkipPackageResolution -DartPath '<existing-dart>' -DockerPath '<existing-docker>'
```

The local runner defaults identify the already installed SDK/Docker paths. The print probe uses existing ChromeDriver and bundled pdfplumber; no installation fallback is present. Secret values must never be copied into reports or agent context.

## Original implementation acceptance assessment (historical)

This initial implementation report predates the independent CHANGES REQUIRED review.
Its original PASS claims are preserved as history, not the current disposition.
The review identified failures in 36, 50 (literal-byte evidence), 55 and 56;
the remediation reassessment below supersedes those claims.

| # | Result | Requirement | Evidence |
| --- | --- | --- | --- |
| 1 | PASS | Fixture Location identity | HTTP lifecycle; composite Location FK |
| 2 | PASS | Independent Company Planogram | Schema and local selector; nullable provenance |
| 3 | PASS | Revision serves multiple Fixtures | Real HTTP journey deploys one revision twice |
| 4 | PASS | Local-only UI | Configured Location guard; no HQ UI |
| 5 | PASS | One active draft | Concurrent creators and direct unique-index rejection |
| 6 | PASS | Published revision immutable | Owner and runtime SQL rejection |
| 7 | PASS | Published zones immutable | Update/delete SQL rejection |
| 8 | PASS | Published placements immutable | Update/delete owner/runtime SQL rejection |
| 9 | PASS | Draft ignores Assortment | Real HTTP draft outside local Assortment |
| 10 | PASS | Publish active same-Company Articles | Unavailable/inactive reference validation; Company FK |
| 11 | PASS | Publish ignores Assortment | Publish succeeds before membership exists |
| 12 | PASS | Assign validates target Assortment | HTTP assortment_unavailable identifies references |
| 13 | PASS | Failed assignment commits nothing | Unchanged Fixture/evidence/audit assertions |
| 14 | PASS | Later Article deactivation retains instruction | Assigned revision ID unchanged with live warning |
| 15 | PASS | Later Assortment deactivation retains instruction | Assigned revision ID unchanged with live warning |
| 16 | PASS | Missing Stock differs from zero | Real HTTP and employee widget assertions |
| 17 | PASS | Unit divergence visible | Frozen Stock port and employee widget |
| 18 | PASS | Publish does not deploy | Real server and Flutter journeys preserve revision 1 |
| 19 | PASS | Explicit append-only Assignment | Assignment route/evidence and SQL guards |
| 20 | PASS | Previous history immutable | Owner/runtime update/delete rejection |
| 21 | PASS | Fixture version protects assignments | Competing assignment/retirement races |
| 22 | PASS | Planogram version protects authoring | Creators and save/publish/retire races |
| 23 | PASS | Exact Publish retry avoids duplicates | Duplicate operation and late replay tests |
| 24 | PASS | Exact Assign retry avoids duplicates | Committed lost response; audit/evidence counts |
| 25 | PASS | Late replay cannot restore old assignment | Real journey/current pointer remains revision 2 |
| 26 | PASS | Conflicting operation identity rejected | Expected version/revision/actor and Publish/Assign cross-kind conflict tests |
| 27 | PASS | Resource UUID duplicates rejected | Fixture/Planogram duplicate creation and reconciliation |
| 28 | PASS | No silent stale rebase | Server stale/no-op and client review tests |
| 29 | PASS | Retirement preserves evidence | Terminal parent and retired historical print tests |
| 30 | PASS | Published revision cannot be deleted | SQL trigger/runtime grants |
| 31 | PASS | Assignment cannot be deleted | Append-only trigger/runtime grants |
| 32 | PASS | Employee cannot read drafts | HTTP negative capability matrix |
| 33 | PASS | Employee cannot read manager history | HTTP denied assignment/Planogram history |
| 34 | PASS | Employee cannot search arbitrary Articles | HTTP candidate permission denial |
| 35 | PASS | Employee cannot cross Location | Configured Location HTTP denial |
| 36 | PASS | Employee can read current layout | Real employee HTTP and Flutter journey |
| 37 | PASS | Employee print current permitted assignment | Positive current print and historical denial |
| 38 | PASS | Stale print assignment_changed | HTTP and controller rejection tests |
| 39 | PASS | Manager historical print is marked | Pinned old assignment HTML marker |
| 40 | PASS | Print pinned to assignment/revision | Typed print envelope and historical/current journeys |
| 41 | PASS | Print excludes Stock | Server HTML assertions and browser quantity sentinel |
| 42 | PASS | Print URL has no token | Real adapter requires about:blank; authenticated JSON |
| 43 | PASS | Synchronous duplicate guard | Publish/Assign deterministic controller tests |
| 44 | PASS | Uncertain command retains exact identity | Immutable route/body retries and committed-response loss |
| 45 | PASS | Replacement fences pending command | Held same/different-account status tests |
| 46 | PASS | Stale async result cannot enter new UI | Held replacement success/error result tests |
| 47 | PASS | Audit failure rolls back mutation | Fixture/Publish/Assign SQL failure injection |
| 48 | PASS | No generic receipt table | Exactly six migration table declarations |
| 49 | PASS | No Stock write/movement added | Read-only port and unchanged ledger regression |
| 50 | PASS | 0001–0015 unchanged | Git comparison; no applied migration edits |
| 51 | PASS | Populated 0015 upgrade safe | Real migration prefix and ledger/Article preservation |
| 52 | PASS | Failed 0016 rolls back | Injected SQL failure retains 15 migrations and no effects |
| 53 | PASS | Backup/restore preserves records | Six merchandising table counts/hashes compared |
| 54 | PASS | Existing Stock invariants green | Server regression and recovery ledger assertions |
| 55 | PASS | Contracts/OpenAPI match | Shared envelopes and all-20-operation catalog test |
| 56 | PASS | M3 contained on every endpoint | Positive journeys; auth/body/capability/input/error matrix |
| 57 | PASS | No unrelated capability | Changed-file and hard-exclusion review |
| 58 | PASS | Real Flutter/HTTP/PostgreSQL passes | Separately invoked real persisted controller journey |
| 59 | PASS | Meaningful browser print verification | 100 rows/10 zones, pagination, escaping, actual adapter |
| 60 | PASS | Full repository regression green | Four suites, analyzers/format, Compose, Web build and acceptance |

## Scope and verification limits

No HQ rollout, bulk assignment, templates/lineage, CAD/geometry, dimensions, images, approvals, schedules, Stock mutation, Tasks integration, replenishment, POS, analytics, AI, offline queue, configurable RBAC or product PDF generation exists. The historical numeric Guided Work browser E2E and opt-in capacity measurement were not rerun; relevant P4.4 browser printing and all package regression tests were run. Native device/printer hardware and remote changed-commit CI were not verified. Memory-only uncertain tracking does not survive browser reload/session replacement; server evidence and authoritative review remain the recovery boundary.

## Review state

Implementation stays uncommitted on main for targeted review. P4.3 historical closure/evidence is unchanged. Complete targeted review and changed-commit CI after an explicitly authorized commit before marking P4.4 DONE.

## Independent review history and targeted remediation — 2026-10-04

The independent adversarial review of the preceding uncommitted implementation
returned **CHANGES REQUIRED**: 56/60 PASS, with 36, 50, 55 and 56 failing that
review's literal expectations. This is historical evidence, not an approval of
this remediation.

| Finding | Historical observation | Current disposition |
| --- | --- | --- |
| F01 MEDIUM | Revoking runtime SELECT on StockLevel made assigned layout HTTP 503, while pinned print remained 200. Stock was awaited as a mandatory dependency and the UI could not distinguish unavailable from absent. | Remediated locally; targeted review pending. |
| F02 MEDIUM | Create Planogram with nonexistent origin Fixture returned undocumented 404. The shared configured-Location gate also reached missing 404 declarations on collection/create routes. | Remediated locally; all 20 operation response sets re-audited. |
| F03 MEDIUM, nonblock | Composite FK rejected another Fixture's Assignment, but direct runtime SQL could select its own older Assignment without version advancement; probe rolled back. | Accepted supported-writer integrity boundary documented; no new trigger/migration. |
| F04 INFO | 0005/0007/0008/0009 working-tree bytes were CRLF while HEAD blobs were LF; all normalized migration content matched HEAD. No historical pre-implementation raw fingerprints were available. | Baseline evidence qualification, not a P4.4 code defect or reason to rewrite migrations. |

### F01 boundary and contract

The Stock-owned batched port returns levels plus typed availability. Recoverable
PostgreSQL statement faults are restricted to 42501 (permission unavailable),
55P03 (lock timeout) and 57014 (server query cancellation). A savepoint isolates
the SELECT; rollback-to and release must succeed before returning unavailable.
The installed pinned postgres 3.5.17 driver clears its transaction error on the
healthy ReadyForQuery after savepoint rollback; a real runtime query after fault
recovery confirms the transaction is usable and commits successfully.
Unrelated SQL/schema, conversion/programming errors and failed recovery propagate.
Loss of the shared database connection also fails mandatory authorization/instruction
reads; optional enrichment does not bypass that boundary.

LayoutView requires `stockContextStatus: available | unavailable`. Available
with a Stock object retains positive or recorded zero quantity and frozen unit;
available with null means no recorded level. Unavailable applies to the whole
referenced batch, with null Stock objects conveying no absence inference. No
per-Article recovery is claimed. Empty/unassigned layouts have an available empty
batch. Print skips the Stock port and exposes no availability/Stock in its print
envelope or HTML.

Both manager and employee display full zones, placement order, IDs and facings
with “Bestandsdaten derzeit nicht verfügbar” when unavailable. Existing absence,
zero, deactivation and unit-divergence displays remain distinct. Real permission
faults prove no changes to all six Merchandising tables, audit, Stock levels or
movements; restoration returns normal Stock context. Undefined-column injection
still returns 503 rather than being swallowed as optional unavailability.

### F02 operation inventory and M3 containment

Every operation reaches configured-Location missing/not-configured 404 after
mandatory authorization and local-scope checks. Additional module-local
resource checks are inventoried below; FK-protected internal reads cannot be
missing in valid supported-writer state. Missing Article/Assortment validation
continues to be 409, not a fabricated 404.

| Operation | Additional module-local 404 resource check |
| --- | --- |
| listFixtures | None |
| createFixture | None |
| getFixture | Fixture |
| editFixture | Fixture |
| retireFixture | Fixture |
| listPlanograms | None |
| createPlanogram | Optional origin Fixture |
| getPlanogram | Planogram |
| retirePlanogram | Planogram |
| listPlanogramRevisions | Planogram; FK-protected Revision hydration |
| createPlanogramDraft | Planogram |
| getPlanogramRevision | Revision missing or belonging to another Planogram |
| savePlanogramDraft | Planogram; scoped Revision |
| discardPlanogramDraft | Planogram; scoped Revision |
| publishPlanogramRevision | Planogram; scoped Revision, including exact-replay hydration |
| listLayoutArticleCandidates | None |
| getAssignedLayout | Fixture; FK-protected current Assignment and Revision |
| listFixtureAssignments | Fixture |
| assignFixtureLayout | Fixture; selected Revision; FK-protected parent Planogram/current Assignment |
| getLayoutPrintView | Fixture; pinned Assignment missing or belonging to another Fixture; FK-protected Revision |

Only the five absent 404 declarations were added (list/create Fixture, list/create
Planogram, Article candidates); existing P4.4 404 descriptions now mention the
shared configured-Location gate. All 20 have 400/401/403/404/500/503. All ten POSTs
also have 409/413/415. Only getFixture/getAssignedLayout/getLayoutPrintView GETs
have reachable 409 lifecycle/assignment errors. Other GETs do not acquire these
statuses. Shared/global error taxonomy and unrelated endpoints are unchanged.
The catalog test checks this reachability distinction and the required Stock
status schema. Real all-20 configured-Location HTTP tests and missing-origin
regression match each observed 404 to its operation's OpenAPI response set.

### F03 and F04 evidence qualification

Supported Assign remains authoritative for authorization, atomic append/pointer/
version/audit and immutable replay. The composite FK protects Assignment ownership
by Fixture/Company/Location; it makes no latest-assignment guarantee against
arbitrary runtime SQL. The historical nonblocking probe and trigger protections
are retained in ADR 0018 and the accepted technical-debt entry.

Criterion 50 has two separate conclusions: **A — Git content integrity PASS**
for all 15 old migration blob IDs; **B — historical literal checkout-byte
identity QUALIFIED**, because the pre-implementation fingerprints are unavailable
and the four known CRLF checkouts differ from HEAD LF blobs. This remediation
captured raw SHA-256 before edits and verified that all 16 migration files stayed
byte-identical during this remediation, including uncommitted 0016. That does not
retroactively prove the unavailable historical baseline. No migration was edited
or normalized. Checksum/prefix/refusal tests and update acceptance compare the
actual current checkout/copies accurately and pass.

### Remediation verification

| Check | Fresh final result |
| --- | --- |
| Affected contracts / full contracts | 6 / 75 PASS |
| Targeted real PostgreSQL integrations / full server | 14 / 219 PASS |
| Affected Flutter / full Flutter | 21 / 241 PASS |
| Design system | 2 PASS |
| Package total | **537 PASS, 0 failed, 0 skipped** |
| Separate real Flutter→HTTP→PostgreSQL journeys | 2 PASS: normal and permission-outage; excluded from package total; passed in final full and targeted runs |
| All four analyzers | Clean |
| All four format checks | 27/109/5/55 files; 0 changes |
| Compose / release Web | PASS; existing dependencies, --no-pub |
| Browser print | PASS: real renderer and adapter, 10 zones/100 placements, 20 A4 landscape pages, escaping/Unicode/no Stock; one print call |
| PowerShell | All 7 existing scripts PASS; P4.4 diagnostic script includes 10 assertions across 2 harnesses |
| Backup/restore | PASS, run 16757cf8c8a844cb; all six table evidence hashes/counts preserved, corruption rejected, isolated resources removed |
| Update/recovery | PASS, run 5917329bd10048fb; through 0016, checksum/prefix preservation, empty second application, HTTP smoke and isolated recovery fencing |
| Repository integrity | diff --check PASS; same main/HEAD/index; only 15 authorized remediation files changed since review; 0001–0016 raw hashes unchanged; no dependency/lockfile changes |

All tests used strictly named isolated DBs/schemas and loopback HTTP; no normal
StoreOS DB writes/migration/backup/restore occurred. Run-owned databases, processes,
ports, HTML/PDF/JS, manifests, backups and temporary artifacts were cleaned;
sanitized wrapper reports were inspected then removed after recording evidence
here. No dependency installation, commit, push or branch change occurred.

Skipped/unverified: historical numeric Guided Work browser E2E, opt-in target
hardware capacity, native-device/accessibility/physical-printer acceptance and
remote changed-commit CI. These are outside this bounded remediation or pending
delivery/operator gates; none is counted as a skipped package test.

### Current acceptance reassessment (1–68)

Each row is reassessed against actual source and the final test evidence; this
local assessment does not replace independent targeted review.

| # | Result | Requirement | Evidence |
| --- | --- | --- | --- |
| 1 | PASS | Fixture Location identity | HTTP lifecycle; composite Location FK |
| 2 | PASS | Independent Company Planogram | Schema and local selector; nullable provenance |
| 3 | PASS | Revision serves multiple Fixtures | Real HTTP journey deploys one revision twice |
| 4 | PASS | Local-only UI | Configured Location guard; no HQ UI |
| 5 | PASS | One active draft | Concurrent creators and direct unique-index rejection |
| 6 | PASS | Published revision immutable | Owner and runtime SQL rejection |
| 7 | PASS | Published zones immutable | Update/delete SQL rejection |
| 8 | PASS | Published placements immutable | Update/delete owner/runtime SQL rejection |
| 9 | PASS | Draft ignores Assortment | Real HTTP draft outside local Assortment |
| 10 | PASS | Publish active same-Company Articles | Unavailable/inactive reference validation; Company FK |
| 11 | PASS | Publish ignores Assortment | Publish succeeds before membership exists |
| 12 | PASS | Assign validates target Assortment | HTTP assortment_unavailable identifies references |
| 13 | PASS | Failed assignment commits nothing | Unchanged Fixture/evidence/audit assertions |
| 14 | PASS | Later Article deactivation retains instruction | Assigned revision ID unchanged with live warning |
| 15 | PASS | Later Assortment deactivation retains instruction | Assigned revision ID unchanged with live warning |
| 16 | PASS | Missing Stock differs from zero | Real HTTP and employee widget assertions |
| 17 | PASS | Unit divergence visible | Frozen Stock port and employee widget |
| 18 | PASS | Publish does not deploy | Real server and Flutter journeys preserve revision 1 |
| 19 | PASS | Explicit append-only Assignment | Assignment route/evidence and SQL guards |
| 20 | PASS | Previous history immutable | Owner/runtime update/delete rejection |
| 21 | PASS | Fixture version protects assignments | Competing assignment/retirement races |
| 22 | PASS | Planogram version protects authoring | Creators and save/publish/retire races |
| 23 | PASS | Exact Publish retry avoids duplicates | Duplicate operation and late replay tests |
| 24 | PASS | Exact Assign retry avoids duplicates | Committed lost response; audit/evidence counts |
| 25 | PASS | Late replay cannot restore old assignment | Real journey/current pointer remains revision 2 |
| 26 | PASS | Conflicting operation identity rejected | Expected version/revision/actor and Publish/Assign cross-kind conflict tests |
| 27 | PASS | Resource UUID duplicates rejected | Fixture/Planogram duplicate creation and reconciliation |
| 28 | PASS | No silent stale rebase | Server stale/no-op and client review tests |
| 29 | PASS | Retirement preserves evidence | Terminal parent and retired historical print tests |
| 30 | PASS | Published revision cannot be deleted | SQL trigger/runtime grants |
| 31 | PASS | Assignment cannot be deleted | Append-only trigger/runtime grants |
| 32 | PASS | Employee cannot read drafts | HTTP negative capability matrix |
| 33 | PASS | Employee cannot read manager history | HTTP denied assignment/Planogram history |
| 34 | PASS | Employee cannot search arbitrary Articles | HTTP candidate permission denial |
| 35 | PASS | Employee cannot cross Location | Configured Location HTTP denial |
| 36 | PASS | Employee can read current layout, including unavailable Stock | Real permission-fault HTTP, real Flutter outage journey and widget assertions |
| 37 | PASS | Employee print current permitted assignment | Positive current print and historical denial |
| 38 | PASS | Stale print assignment_changed | HTTP and controller rejection tests |
| 39 | PASS | Manager historical print is marked | Pinned old assignment HTML marker |
| 40 | PASS | Print pinned to assignment/revision | Typed print envelope and historical/current journeys |
| 41 | PASS | Print excludes Stock | Server HTML assertions and browser quantity sentinel |
| 42 | PASS | Print URL has no token | Real adapter requires about:blank; authenticated JSON |
| 43 | PASS | Synchronous duplicate guard | Publish/Assign deterministic controller tests |
| 44 | PASS | Uncertain command retains exact identity | Immutable route/body retries and committed-response loss |
| 45 | PASS | Replacement fences pending command | Held same/different-account status tests |
| 46 | PASS | Stale async result cannot enter new UI | Held replacement success/error result tests |
| 47 | PASS | Audit failure rolls back mutation | Fixture/Publish/Assign SQL failure injection |
| 48 | PASS | No generic receipt table | Exactly six migration table declarations |
| 49 | PASS | No Stock write/movement added | Read-only port and unchanged ledger regression |
| 50 | PASS — Git content; byte qualification | 0001–0015 unchanged | All 15 normalized Git blob IDs equal HEAD. All 16 raw migration hashes unchanged during remediation. Historical pre-implementation raw fingerprints unavailable; 0005/0007/0008/0009 checkout CRLF differs from HEAD LF |
| 51 | PASS | Populated 0015 upgrade safe | Real migration prefix and ledger/Article preservation |
| 52 | PASS | Failed 0016 rolls back | Injected SQL failure retains 15 migrations and no effects |
| 53 | PASS | Backup/restore preserves records | Six merchandising table counts/hashes compared |
| 54 | PASS | Existing Stock invariants green | Server regression and recovery ledger assertions |
| 55 | PASS | DTO/OpenAPI match reachable responses | Required two-value Stock status; exact 409/413/415 reachability; all 20 mandatory-location 404 assertions |
| 56 | PASS | P4.4 M3 containment | All-route auth/body tests plus real missing-origin and all-20 configured-Location HTTP 404 matched against OpenAPI |
| 57 | PASS | No unrelated capability | Changed-file and hard-exclusion review |
| 58 | PASS | Real Flutter/HTTP/PostgreSQL passes | Normal and revoked Stock-permission journeys, persisted deployment and late replay |
| 59 | PASS | Meaningful browser print verification | 100 rows/10 zones, pagination, escaping, actual adapter |
| 60 | PASS | Full repository regression green | 537 package tests, analyzers/format, Compose, Web release, print, backup/restore and update/recovery |
| 61 | PASS | Stock-context infrastructure failure preserves assigned instruction | Real SELECT permission fault: employee/admin layout HTTP 200; subsequent transaction query succeeds |
| 62 | PASS | Unavailable differs from absent and recorded zero | Positive 12.5 kg, zero 0 kg, available/null and unavailable/null wire/DTO/widget assertions |
| 63 | PASS | Print remains independent of Stock | Revoked SELECT print HTTP 200 in both roles and real Flutter outage journey; browser print passes |
| 64 | PASS | Every reachable P4.4 404 is in OpenAPI | All-20 mandatory-location HTTP/status-schema checks and resource inventory below |
| 65 | PASS | Missing origin Fixture regression | Create Planogram HTTP 404/not_found, no created evidence; status checked against the matched OpenAPI operation |
| 66 | PASS | Configured-Location regressions | Isolated Location name=NULL: ten reads and ten mutations return documented 404/not_found |
| 67 | PASS | Supported-writer limitation accurately documented | ADR 0018, accepted technical-debt entry and review F03 history; no latest-pointer DB guarantee |
| 68 | PASS | Old migrations not rewritten for CRLF | Before/after raw SHA-256 fingerprints unchanged for 0001–0016; all 15 committed Git contents identical |

P4.4 remains **IMPLEMENTED LOCALLY / TARGETED REVIEW PENDING /
REMOTE CHANGED-COMMIT CI PENDING**, entirely uncommitted. F01/F02 require targeted
review of the final code. F03 remains the accepted supported-writer limitation;
F04 remains a baseline-evidence qualification. No additional production scope
or migration was introduced.

## Changed-commit CI failure remediation — 2026-10-04

Current disposition: **IMPLEMENTED / REVIEW APPROVED / CHANGED-COMMIT CI NOT YET GREEN**.
The independent targeted review returned APPROVE. Implementation commit
`cd7669ed7de2751d4dc97c2724a0d11d9f674f51` is on `main`; this bounded CI fix remains
uncommitted. No commit, push, branch change or DONE/CLOSED declaration was made
during this remediation.

The first changed-commit [CI run 37214855513](https://github.com/RobinBrohl/storeos/actions/runs/37214855513)
failed in [Dart job 111473178499](https://github.com/RobinBrohl/storeos/actions/runs/37214855513/job/111473178499).
The other four jobs succeeded. The authenticated job log was read without exposing
credentials. Both real journey variants failed at process creation, before any
Flutter client assertion:

```text
ProcessException: No such file or directory
  Command: C:/dev/flutter/bin/cache/dart-sdk/bin/dart.exe C:/dev/flutter/bin/cache/flutter_tools.snapshot test --no-pub test/merchandising_http_journey.dart
  dart:io                                          Process.run
  test/merchandising_integration_test.dart 552:40  main.<fn>.<fn>
  ===== asynchronous gap ===========================
  test/merchandising_fixture.dart 389:5            withMerchandisingFixture
```

Root cause classification: **CI CONFIGURATION**, with a nonportable test launcher.
The Ubuntu Dart job provisioned only Dart 3.13.4, while the journeys unconditionally
invoked a developer's Windows Dart executable and Flutter snapshot. Flutter and
the client's resolved dependencies were also absent from that job. Expected 409
responses elsewhere were not failing replay assertions.

The exact server command is `dart test` from `apps/server`, with default Dart test
concurrency and no repository concurrency override. CI uses PostgreSQL 17 Alpine,
loopback port 5432, owner `storeos_owner`, runtime role `storeos`, database
`storeos_test`, file-backed credentials and fixed configured Company/Location
IDs `11111111-1111-4111-8111-111111111111` /
`22222222-2222-4222-8222-222222222222`. The migration/bootstrap steps precede it.

Before source edits, the full command was reproduced with the cached Linux
Dart 3.13.4 server image, complete current source/test/tool/OpenAPI read-only mounts,
the PostgreSQL container's loopback network, a temporary `_test` database and the
same runtime role. Result: **217 PASS / 2 FAIL**, exclusively the two journey
variants, with the identical stack above. Two preliminary container attempts also
hit that launcher failure, but had unrelated reproduction-configuration failures
(missing tool/OpenAPI mounts, then a non-loopback capacity-test host); they are not
counted as clean CI-equivalent reproductions.

### Parallelism and Stock fault injection

Isolation is a fresh UUID schema per fixture, not a database per test. Test files
can share the database, owner and runtime role. Each fixture has its own pool,
HTTP server on loopback port 0, accounts, resources and cleanup. Fixed Company/
Location IDs repeat only inside different schemas; schema-qualified tables and
schema-scoped advisory lock keys prevent those identities from colliding. The two
journeys in one Dart test file execute sequentially; unrelated test files can
overlap. Child process environment maps do not mutate the parent environment.

Stock failure uses `REVOKE SELECT ON "<unique-schema>".stock_levels FROM "<runtime-role>"`,
with a matching table-specific GRANT in `finally`. It changes that table's ACL,
not role membership, default privileges or access to another schema's table.
Other fixtures' REVOKE/TRUNCATE/cleanup statements are likewise schema-qualified.
No global reset, shared server or teardown race was found.

A separate real PostgreSQL probe kept two fixtures alive in one temporary database
with the same role and fixed Company identity. After the outage fixture's REVOKE,
its runtime SELECT failed with SQLSTATE `42501`; the peer's runtime SELECT passed,
and `has_table_privilege` returned `[false, true]`. Restoring access made the
outage fixture readable again. **1 probe PASS**; excluded from package totals.
This disproves the proposed cross-test permission interference mechanism.

### Bounded correction

- The real journey launcher now uses `flutter` / `flutter.bat` from PATH, honors
  the existing `STOREOS_FLUTTER_EXECUTABLE` override and uses the Windows shell for
  the batch launcher. Its real HTTP/PostgreSQL/Flutter assertions are unchanged.
- The Dart CI job now provisions the repository's existing Flutter 3.47.5 pin
  (bundled Dart 3.13.4) and resolves the client with `flutter pub get --enforce-lockfile`
  before server checks. The full `dart test` command and concurrency are unchanged.
- Production code, permissions, Stock injection, replay/no-op semantics, timeouts,
  migration files, manifests and lockfiles are unchanged. No local dependency
  installation/upgrade, retry, sleep, serialization or fake-only replacement was added.
- Handover/status records reconcile the approved review, committed implementation
  and failed CI attempt. Architecture/ADR/debt decisions are unchanged; F01/F02
  remain closed, F03 retains the accepted supported-writer limitation, and F04
  retains its historical migration-byte qualification.

### Fresh verification and limits

Post-fix execution used the already installed Windows Flutter 3.47.5 / Dart
3.13.4 SDKs, existing locked dependencies and PostgreSQL 17 Alpine. Migration
application through 0016 and bootstrap passed in a fresh temporary database
before the full command. Database/role/file-backed credential semantics matched
CI; platform and temporary database name differed. No local package resolution
or installation was performed.

| Command / check | Fresh result |
| --- | --- |
| `dart test` in `apps/server`, default concurrency | **3 consecutive runs: 219 PASS each, 0 failed, 0 skipped** |
| `dart test test/merchandising_integration_test.dart --name 'real Flutter / HTTP / PostgreSQL journey' --reporter expanded` | 2 PASS together |
| `dart test test/merchandising_integration_test.dart --name 'Stock unavailable=false' --reporter expanded` | 1 PASS independently |
| `dart test test/merchandising_integration_test.dart --name 'Stock unavailable=true' --reporter expanded` | 1 PASS independently |
| `dart test test/merchandising_integration_test.dart --reporter expanded` | 14 real PostgreSQL integrations PASS |
| `dart test` in `packages/api_contracts` | 75 PASS |
| `flutter test --no-pub` in `apps/client_flutter` | 241 PASS |
| `flutter test --no-pub` in `packages/design_system` | 2 PASS |
| Distinct package suite total | **537 PASS, 0 failed, 0 skipped**; repeated/filtered executions are additional runs |
| Real peer-fixture permission-isolation probe | 1 PASS; outside package total |
| `dart analyze` in all four packages | All clean |
| `dart format --output=none --set-exit-if-changed .` in all four packages | Final checks: 27/109/5/55 files, 0 changes |
| Cached offline `rhysd/actionlint:1.7.7 .github/workflows/ci.yml` | PASS |
| `docker compose config --quiet` | PASS |
| `flutter build web --release --no-pub --no-web-resources-cdn` | PASS |
| `git diff --check` | PASS |
| Migration/dependency/production integrity | All 16 raw migration hashes unchanged during this remediation; no production, migration, pubspec or lockfile diff; no 0017 |
| Cleanup | All run-owned temporary databases removed; no normal StoreOS database writes |

Runs one and three exercised Flutter PATH lookup; run two exercised the existing
absolute executable override. Each full server run also executed both nested real
Flutter journeys (one client test per variant); those nested tests are excluded
from the package total. The joint, independent and targeted server selections
also executed their corresponding nested journeys. All filtered runs retain the
real permission fault, immutable publication/replay, late Assignment pointer,
session/print and Stock non-mutation assertions.

The first no-output format check requested a layout-only change to the launcher's
argument list after the test runs. The pinned formatter applied it; the final
format check is clean. No executable behavior changed. Ignored local logs/probe
helpers retain the evidence without credential values.

Unverified: the corrected Ubuntu Flutter execution and a new changed-commit CI
run. No Linux Flutter SDK was already available locally, and none was installed.
Local Windows passes do not establish remote CI success. The existing failed
changed-commit run remains the remote result until an explicitly authorized
commit/push and successful CI. Print/device/hardware acceptance, backup/update
acceptance and numeric browser E2E were not rerun for this launcher/configuration
fix; their earlier evidence and unchanged scope remain intact.

Recommendation: the bounded correction is ready for an explicitly authorized
commit and subsequent changed-commit CI. P4.4 stays **IMPLEMENTED / REVIEW APPROVED /
CHANGED-COMMIT CI NOT YET GREEN** until that gate passes.
