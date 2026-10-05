# P4.7 — Task Planogram Assignment execution pinning

Date: 2026-10-05.

**IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING.**

This record covers implementation verification on uncommitted, unstaged `main`. Independent normal review APPROVE and the subsequent Codex Security SECURITY CHANGES REQUIRED verdict are supplied review evidence; targeted security re-review remains pending. The 80 product criteria retain their original numbering, with separate security evidence below. This remediation invoked no new security scan, dependency install/upgrade, branch switch, staging, commit, push or GitHub mutation. P4.8 is not selected.

## Verified starting baseline

Before any implementation, tree/index were clean, no stash existed, exactly one intended worktree existed, and HEAD/cached origin/live origin were all `a0ed6346f7453c8f4e170aee43af8d775677f97b`. The migration chain ended at committed 0018 with no 0019. P4.1–P4.6 were canonically DONE/CLOSED, with no active remediation or selected P4.7 capability. Read-only GitHub verified all five exact-HEAD jobs successful in [baseline CI 37290533013](https://github.com/RobinBrohl/storeos/actions/runs/37290533013). This CI proves only the unchanged baseline.

The immediately preceding user-selected P4.7 architecture plan and repository source/ADRs were reconciled before implementation. [ADR 0021](../adr/0021-task-planogram-assignment-guidance.md) records the resulting bounded decision.

## Contract and ownership

Task content schema 4 requires independent nullable `knowledgeGuidance` and `planogramGuidance`. The concrete Planogram value has exactly `fixtureId`, `assignmentId`, `revisionId`; no layout, labels, stock, timestamps, current status or redundant Planogram ID enters Task content. Schemas 1–3 remain strict and their persisted content is not rewritten. Confirmation/numeric execution stays unchanged.

Merchandising owns `PlanogramGuidancePort`; Tasks owns Template selection and immutable snapshots; Workforce authorizes Shift/Task context. Repositories do not query foreign module tables. Inventory and Stock are consumed through existing public read ports. There is no shared polymorphic guidance port/reference, event/outbox consumer, read acknowledgment or completion gate.

Fixture and Planogram have actual terminal `retired` lifecycle; published Revisions and append-only Assignments remain durable evidence. Current deployment selection and fresh Template/Shift publication require the exact scoped current Assignment, active Fixture/Planogram, published Revision and active Article/Assortment. R2 publication alone does not invalidate A1/R1. A1 becomes stale when F receives A2, including when A3 later deploys R1 again. Unchanged draft editing/cloning preserves stale identities so operators can explicitly clear or replace them.

Fresh validation and all publication mutations/audit execute in the existing Company transaction. Publication replay rechecks current authorization/scope, recognizes committed evidence, and returns the original identities before fresh availability validation. Pristine interval amendment preserves snapshots without treating the amendment as fresh guidance publication.

## Migration 0019

Only `0019_task_planogram_guidance.sql` is new. The predecessor validator is retained and schemas 1–3 delegated unchanged; schema 4 has strict required fields, exact canonical UUID tuple and existing content limits. JSON-derived generated Fixture/Assignment/Revision columns on Template revisions and TaskInstances reference the narrow immutable Merchandising-owned `(id, company_id, location_id, fixture_id, revision_id)` Assignment anchor. Current/active status is absent from permanent integrity.

Task/Template correspondence compares both concrete pins. Task immutability excludes generated fields from BEFORE-trigger comparison while retaining immutable source content and all existing execution/evidence guards. Existing runtime column privileges remain restricted. No new receipt/evidence/operation table or copied layout exists.

A populated 0018 fixture contains schemas 1/2/3, a draft and open, in_progress, blocked, completed and cancelled Tasks. Successful 0019 preserves original content and receipts/results/attempts/blockings/audit. Injected end-of-migration failure rolls back columns, history and source evidence. Clean 0001→0019 and existing checksum/idempotent migration contracts pass in full regression.

## HTTP and authorization

New contextual GETs, all without query selectors:

- `/api/v1/platform/task-templates/{id}/revisions/{revisionId}/planogram`
- `/api/v1/platform/shifts/{shiftId}/tasks/{taskId}/planogram`
- `/api/v1/platform/employee-home/shifts/{shiftId}/tasks/{taskId}/planogram`

A bounded current selector is `/api/v1/platform/locations/{locationId}/merchandising/fixtures/{fixtureId}/guidance-selection`. Existing Template detail has no retained-layout projection, and standalone current layout does not expose fresh Planogram lifecycle eligibility; these bounded reads avoid extending employee historical browsing. The selector requires `tasks.templates.manage` plus `merchandising.layouts.read` and configured Company/Location, derives current identity and accepts no historical selectors.

Template contextual preview requires Template management plus Merchandising read. Manager Task reads require existing scoped Shift/Task permissions plus Merchandising read. Employee reads require current session, active Employee link, configured Location and own visible Shift/Task plus existing self-read and Merchandising read. No new capability exists. Viewer, auditor and approved plugin are denied. Knowledge permissions remain independent.

Selection uses 422 `planogram_selection_unavailable`; fresh publication uses 422 `planogram_guidance_unavailable`. Committed replay uses neither after authorized evidence recognition. Context has bounded 400/401/403/404/500/503 behavior. Optional Stock uses the existing savepoint fallback; mandatory identity/integrity faults remain hard errors. OpenAPI specifies concrete retained response shape and bounded errors; guessed/query selectors cannot override stored pins.

## Frozen instruction and live context

`RetainedLayoutDto.instruction` contains exact retained deployment, derived Planogram/revision identity, and published ordered Zones/Placements/facings. `currentContext` contains explicitly current Fixture descriptors, reassigned/retired indicators, current Article/Assortment labels/status, optional current Stock and query time. No live label/Stock is claimed as historical evidence. Missing Stock, recorded zero and unavailable optional context remain distinct; optional failure preserves frozen instruction.

## Flutter

The Template picker captures the exact current tuple, supports explicit preview/save/clear/replace and preserves unrelated local fields. Unsaved preview verifies captured identity against the bounded current selector; saved preview resolves stored historical content. Dirty draft publication remains disabled until an explicit save. Selection/publication failure preserves inputs and actionable error distinction. Knowledge remains independent.

Assigned layout opens from manager/employee Task context and returns to unchanged Task state and numeric/reason inputs. Literal Flutter Text/SelectableText renders editable content; no HTML renderer/sanitizer is claimed. Same-account and different-actor replacement fence selector, previews, pending historical/Stock response and cached state through opaque session identity. No old callback continues using a replacement token.

Real Chrome initially exposed a lazy viewport correction loop with the long dual-guidance editor. The bounded editor children now share a stable Column within its scroll view; the regression test mutates both previews while scrolled and checks for render errors. The Chrome driver also checks framework exceptions rather than silently accepting completed HTTP operations.

## Initial implementation verification (historical)

| Check | Final result |
| --- | --- |
| API contracts | 105 passed |
| Server + isolated PostgreSQL | 296 passed; 3 opt-in browser tests skipped in the normal suite and each passed separately |
| Flutter client | 286 passed |
| Design system | 2 passed |
| P4.7 targeted PostgreSQL | 39 passed, including real Flutter/HTTP journey |
| P4.7 targeted Flutter Template/Task | 41 passed |
| Four analyzers | No issues, fatal infos enabled |
| Four format checks | 32 / 126 / 5 / 68 files; zero changes |
| Flutter Web release | PASS; no package resolution or CDN assets |
| Compose validation | PASS |
| Git diff whitespace check | PASS |

The initial full test-suite run is recorded in `.local/p47-regression.log`. Its analyzer tail found two acceptance-fixture lint issues; after those behavior-preserving fixes and formatting the audit test, `.local/p47-final-checks.log` records all four clean analyzer/format checks plus Web release and Compose success. No tests were weakened or removed. The original completion claim was subsequently qualified by F01/F02 below; these historical runs do not prove the final remediation source.

The normal server suite explicitly skips three opt-in Chrome tests. Each was executed separately: P4.7 Task Planogram, P4.6 Task Knowledge and Knowledge management, each **1/1 PASS**. Numeric Guided Work Chrome E2E passed, including server replacement and fixture cleanup. Planogram print passed: **20 A4 landscape pages, 100 placements, 10 Zones**, Unicode/escaping/no clipped text; the actual Web adapter invokes open/write/print once. Browser acceptance does not establish physical device/printer or accessibility acceptance.

Backup/update report redaction, E2E diagnostics, P4.4 harness diagnostics (2 harnesses / 10 secret-representation assertions), capacity report redaction and backup crypto roundtrip/wrong-key/tamper/truncation/reorder checks pass. All use installed pinned tools; no package resolution/upgrade is invoked.

## Real Flutter → HTTP → PostgreSQL and Chrome evidence

The real Dart/Flutter API/controller journey uses production HTTP writes for Article/Assortment, Fixture F, published R1, Assignment A1, a schema-4 dual-guidance Template and Shift. A supported transport wrapper loses successful Template/Shift publication responses. It then publishes/assigns R2 as A2, retires Fixture/Planogram, replays original publication requests and receives original IDs without duplicate Tasks/audit. Existing Task/manager context remains A1/R1, standalone current layout differs before retirement, stale fresh publication fails atomically, normal confirmation/numeric completion works and a restarted server returns the original evidence. Independent SQL checks tuple/Assignment/Template correspondence, completed status, four receipts and minimized audit.

Chrome exercises actual Template picker/preview/save/publish, Shift review/publication, employee Assigned layout/return, replacement deployment/lifecycle and normal execution. Literal editable Fixture, Article and layout content produce no content-created script, unsafe link, image/onerror or injection. It compares current A2/R2 and reopened retained A1/R1; independent PostgreSQL checks completed tuple and four receipts. Both guidance panels remain independently accessible after lifecycle changes.

## Backup / restore and update / recovery

Initial encrypted backup/restore acceptance **PASS for its narrower historical-pin/read checks**, run `b4019a14c6804f8c`; sanitized report `.local/backup-acceptance/b4019a14c6804f8c/report.json`. Supported API seed contains schemas 1/2/3 and completed schema 4 with both pins, retained A1/R1, later current A2/R2, retired Fixture/Planogram, original retired Knowledge v1, results/attempts/blocking, seven execution receipts and audit. Compared table hashes/sequences and contextual historical read survived restore; credentials/plugin tokens and runtime CONNECT remained fenced, corruption was rejected and owned resources were cleaned. The original record overstated Article/Stock restoration and arbitrary historical Planogram denial/tuple protections: Article/Assortment were omitted from table hashes, Stock was empty, the denial proof was Knowledge-specific and Planogram probes only rejected generated-column writes. F02 identified incomplete broader acceptance evidence, not demonstrated restore corruption.

Forward update/recovery acceptance **PASS**, run `bce661be19734b00`; sanitized report `.local/update-recovery/bce661be19734b00/report.json`. The real populated 0010 restore point upgrades through 0019 with exact repository checksums and empty second apply. Current API smoke verifies both pins, later A2/R2, historical retired Task completion/read and runtime guards. Isolated recovery returns to the original fenced 0010 point, preserving original business projection/sequence evidence and leaving the upgraded source intact. Populated 0018/failed 0019 proof is separately supplied by the PostgreSQL test above. This acceptance does not redesign recovery or activate a restored database.

## Reproduce

Use the already installed pinned Dart/Flutter, PostgreSQL/Docker and compatible ChromeDriver. Supply installed absolute tool paths as appropriate for the host. The new wrapper reads secret files internally, never printing credentials, creates only `storeos_p47_<16 hex>_test`, and drops its own DB in finally; browser drivers are run-owned and hidden.

```powershell
$checks = @{
  DartPath = 'C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe'
  FlutterPath = 'C:\dev\flutter\bin\flutter.bat'
  FlutterSnapshot = 'C:\dev\flutter\bin\cache\flutter_tools.snapshot'
  DockerPath = 'C:\Users\Robin\AppData\Local\Programs\DockerDesktop\resources\bin\docker.exe'
}
$browser = @{
  DriverPath = 'C:\tools\chromedriver-win64\chromedriver.exe'
  ChromePath = 'C:\Program Files\Google\Chrome\Application\chrome.exe'
}
./scripts/guidance/Run-P47Checks.ps1 @checks
./scripts/guidance/Run-P47Checks.ps1 @checks @browser -Browser
./scripts/guidance/Run-P47Checks.ps1 @checks @browser -TaskKnowledgeBrowserRegression
./scripts/guidance/Run-P47Checks.ps1 @checks @browser -KnowledgeBrowserRegression
./scripts/guidance/Run-P47Checks.ps1 @checks @browser -Numeric
./scripts/guidance/Run-P47Checks.ps1 @checks -FullRegression
./scripts/backup/Run-BackupRestoreAcceptance.ps1 -SkipPackageResolution -DartPath $checks.DartPath -DockerPath $checks.DockerPath
./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -SkipPackageResolution -DartPath $checks.DartPath -DockerPath $checks.DockerPath
./scripts/merchandising/Test-PlanogramPrint.ps1 -DriverPath $browser.DriverPath
```

APPDATA for pinned tooling was directed to `.local/p47-tooling/appdata` with `DART_SUPPRESS_ANALYTICS=true` for this verification. Versioned commands/scripts contain no credentials. Private logs and sanitized acceptance reports remain under ignored `.local`; temporary key/dump/manifest artifacts and owned databases/processes are cleaned by their wrappers.

## Independent review and bounded normal remediation — 2026-10-05 (historical)

The initial implementation claimed **80/80 PASS**. The independent adversarial
review returned **CHANGES REQUIRED** with exactly two actionable LOW commit
blockers: **F01**, unreachable selector `409 invalid_lifecycle` in OpenAPI, and
**F02**, incomplete broader backup/restore evidence. Architecture, persistence,
authorization, replay, lifecycle and execution otherwise passed that review. This
preserves the supplied review historically; remediation does not claim approval
or close P4.7.

F01 removes only the selector-specific 409 from `platform.openapi.json`, to which
shared `openapi.yaml` delegates. Contract tests require exactly
200/400/401/403/404/422/500/503 and retain `planogram_selection_unavailable` and
Template/Shift publication 409. Template management is checked before `_view`:
only the fixed admin role qualifies, so retired/unavailable deployment failures
use selection validation. Real HTTP checks prove malformed UUID/query 400, absent
session 401, employee 403, missing Fixture 404, unassigned/retired Fixture/retired
Planogram/inactive Article or Assortment 422 and database permission outage 503.
An injected internal fault through the actual selector router/server middleware
proves 500. Publication still returns `template_conflict`/`shift_conflict` 409.
No production lifecycle, role, capability or route implementation changed.

F02 changes the backup fixture and a backup-specific probe helper. Supported HTTP
APIs seed the retained placement Article, its active Location Assortment, one
StockLevel with **12.5 Stk** and one attributable **opening** StockMovement
(12500 exact thousandths, admin actor, recorded timestamp, version 1). No receiving
or count provenance is invented. The four non-empty tables join deterministic
full-row comparisons: **20 tables and 2 sequences** match source and restore
before verification sessions. SQL additionally checks Article/Assortment state,
Stock identity, frozen unit and ledger actor/kind/delta/balance/version/timestamp.

Fresh authenticated Application reads on the isolated fenced restore return exact
historical **F/A1/R1** and current **F/A2/R2**, checked against source manifest IDs,
plus retained placement Article identity, current label/unit/active status, active
Assortment and available non-zero Stock. Frozen instruction and live context remain
separate. A second employee's real published pinned Task is seeded through APIs and
confirmed readable by the manager. **Five** employee denials cover historical
Assignment print (existing retired-Fixture 409), Assignment history and historical
Revision (403), another Task ID in the legitimate Shift (404), and the other
employee's actual Shift/Task (404). Legitimate contextual read succeeds; Planogram
reads add no audit. Verification login/logout retains ordinary authentication audit.

**Fourteen** rollback-only restored rejection probes cover Assignment/Fixture and
Assignment/Revision mismatch (exact `task_revision_planogram_fk`/23503), foreign
Company/Location (23503), Task pin versus published Template pin (exact
`task_guidance_snapshot`/23514), immutable open-Task retained content (23514),
published Template content (23514), six owner generated-column writes (428C9) and
runtime Task-content write (42501). All **six** generated columns are independently
checked against JSON. Existing Knowledge/runtime protections remain. Evidence and
sequences still match exactly after mutation probes. Revoked sessions/plugin
credentials, runtime connection rejection, corruption rejection, isolated restore
and cleanup remain verified. The normal StoreOS database receives no acceptance
writes.

Focused checks on final remediation source: contracts **105/105**, P4.7
PostgreSQL/real HTTP journey **40/40**, extended encrypted backup **PASS**, run
`7578ce18683e425f`, sanitized report
`.local/backup-acceptance/7578ce18683e425f/report.json`. An initial remediation run
failed an overly broad comparison after fresh authentication audits; the fixture
now compares exact evidence before those sessions and asserts no Planogram-read
audit during them. No restore corruption was found; failed-run resources cleaned.

All source, test, tooling and documentation edits precede final regression.
`.local/p47-remediation-final-summary.json` records phase results and the unchanged
working-tree SHA-256 fingerprint; detailed logs use `.local/p47-remediation-final-`.
The final run repeats contracts **105**, server/PostgreSQL **297** (three opt-in
Chrome skips, each separately passed), Flutter **286**, design system **2**:
**690 passing suite tests**. P4.7 PostgreSQL repeats **40/40**; P4.7/P4.6/Knowledge
Chrome each **1/1**. Numeric Guided Work E2E, Planogram print (**20 pages, 100
placements, 10 Zones**), encrypted backup/restore, update/recovery, six
diagnostic/redaction/crypto harnesses, four analyzers, format (**32/127/5/68 files,
zero changes**), Compose, Web release and `git diff --check` pass on the frozen
tree. Final sanitized backup/update report paths are recorded in their phase logs.
No tests are removed or weakened.

All 80 rows below are reassessed against final contracts/source and new executions,
including schema, tuple, replay, authorization, frozen/live and session tests.
Criterion 63 now proves accurate reachable contracts. Criterion 70 retains its
narrower original historical-pin/read PASS and now proves the entire broader backup
gate. Criterion 77 uses exact final source. Status is **IMPLEMENTED LOCALLY /
INDEPENDENT REVIEW REMEDIATION COMPLETE / TARGETED REVIEW PENDING / REMOTE
CHANGED-COMMIT CI PENDING**, never DONE/CLOSED. Targeted independent review,
separately requested security review and remote changed-commit CI remain gates.

## Codex Security F01 and bounded security remediation — 2026-10-05

After the initial implementation, independent **CHANGES REQUIRED** review for
normal-review F01/F02 and bounded normal remediation, the supplied targeted
independent review returned **APPROVE**. Codex Security subsequently returned
**SECURITY CHANGES REQUIRED** for one **LOW / PROBABLE VULNERABILITY / CWE-863**:
**Security F01**, omitted configured work Location scope in retained Planogram
resolution/fresh validation. These are distinct findings; the prior selector
contract and extended backup evidence remain intact.

The original path was runtime-reproduced using valid B work created entirely
through supported HTTP APIs in an isolated PostgreSQL database. After execution
was configured for A and an A admin authenticated, Template historical preview
returned B's exact instruction, Fixture descriptor, Article/Assortment context
and non-zero Stock. `.local/p47-security-repro.log` retains that expected failing
security test; the earlier `.local/p47-security-before.log` includes a test-setup
failure before this decisive reproduction, not a security result.

`PlanogramGuidancePort.requireWorkLocation` now requires the configured Company,
actor Location equal to configured execution Location, work Location equal to
that same configured Location, existing Merchandising read capability and a
named Company-owned Organization Location. It uses canonical configuration and
UUID handling, with existing **403 forbidden / Local location required** semantics.
The global Organization Location-registry behavior is unchanged. The check runs
before Fixture/Assignment/Revision reads and before Article/Assortment/Stock
enrichment. It also guards retained Template cloning/unchanged editing and both
committed publication replays. No new authorization framework, response code,
OpenAPI response or migration is needed; existing 403 contracts already apply.

The decisive new integration case covers **20 cross-Location denials**: published
and draft Template previews, manager Task read, selector, fresh Template/Shift
publication, committed Template/Shift replay, cloning, retained/replacement
editing, new selection, employee scope, three denials with mandatory layout-table
access revoked, and four retained read/replay denials after reassignment/retirement.
Denied responses contain no B descriptor, Article label, quantity or retained
Assignment/Revision identity. Reconfiguration to B restores contextual access and
exact replay without duplicate Tasks or audit. Authentication's expected login
audit is measured before each business-operation group. Same-Location historical
reads still ignore permitted lifecycle changes; fresh validation retains its
selection/publication availability distinction.

Backup acceptance seeds an alternate named Location and admin through supported
HTTP APIs. On the isolated restored database, **four additional scope denials**
cover Template preview, manager Task read and both committed replays. Returning
to B restores the same retained F/A1/R1 and replay, with unchanged Task and audit
counts. Existing 20-table/2-sequence comparison, live A2/R2, non-empty Stock,
five employee history denials, 14 database rejections and six generated-column
checks remain. Sanitized reports add explicit configured-Location proof fields.

The read-only candidate review found no concrete surviving bypass or regression.
Its analyzer lacked package-cache access; the primary verification uses installed
cached dependencies with the requested access. Focused runtime security proof
passed before final regression. All versioned edits are frozen before final-source
checks. Exact commands, counts and final working-tree fingerprint are retained in
`.local/p47-security-final-summary.json`; detailed final logs use
`.local/p47-security-final-`. The final checks repeat focused PostgreSQL/HTTP,
the full four-package regression/analyzers/format/Web/Compose, P4.7/P4.6/Knowledge
Chrome, numeric E2E, print, backup/restore, update/recovery and diagnostic/crypto
harnesses. Historical counts above describe their earlier source, not this pass.

Current delivery is **IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY
REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT
CI PENDING**. The original **80/80 PASS** product matrix is reassessed for regression;
Security F01 is an additional delivery gate, not an 81st product criterion.
This record does not claim independent security closure or DONE/CLOSED.

## Acceptance criteria (final security remediation source)

Evidence abbreviations refer to production contract tests, `apps/server/test/task_planogram_integration_test.dart`, `apps/client_flutter/test/task_template_test.dart`, `apps/client_flutter/test/task_planogram_test.dart`, the real HTTP journey/browser test and final security remediation regression/acceptance runs above. Each row states its own result and decisive proof. Independent normal review APPROVE is preserved; targeted security re-review remains pending.

| # | Criterion | Local result | Evidence |
| --- | --- | --- | --- |
| 1 | Planogram guidance is optional. | PASS | Contract four nullable combinations; no-pin PostgreSQL execution; no-request Flutter case. |
| 2 | Schema 4 explicitly supports it. | PASS | Strict TaskTemplateContent schema-4 round trips and 0019 validator. |
| 3 | Schemas 1–3 remain unchanged. | PASS | Schemas 1/2/3 decoder round trips and rejection of extra Planogram key; populated predecessor tests. |
| 4 | Old persisted Task content is not rewritten. | PASS | Populated 0018 migration compares original content, lifecycle evidence and receipts before/after. |
| 5 | Knowledge guidance remains independently supported in schema 4. | PASS | All four Knowledge/Planogram nullable combinations; real journey carries both. |
| 6 | No generic instruction/reference abstraction is introduced. | PASS | Concrete PlanogramGuidance, separate KnowledgeGuidancePort and PlanogramGuidancePort; inspected diff. |
| 7 | Planogram pin contains Fixture ID. | PASS | PlanogramGuidance strict fixtureId; generated identity assertion. |
| 8 | Planogram pin contains Assignment ID. | PASS | PlanogramGuidance strict assignmentId; generated identity assertion. |
| 9 | Planogram pin contains Revision ID. | PASS | PlanogramGuidance strict revisionId; generated identity assertion. |
| 10 | No Planogram layout content is copied into Task persistence. | PASS | Independent persisted JSON and audit checks contain IDs only; layout resolved from Merchandising. |
| 11 | New selection requires current valid Assignment. | PASS | Current selector and fresh selection eligibility tests. |
| 12 | Selection binds Assignment to exact Fixture. | PASS | Fresh selection and composite FK reject a different Fixture. |
| 13 | Selection binds Assignment to exact Revision. | PASS | Fresh selection and composite FK reject a different Revision. |
| 14 | Cross-Company pin rejected. | PASS | Wrong-Company composite FK 23503 and scoped Application authorization test. |
| 15 | Cross-Location pin rejected. | PASS | Wrong-Location composite FK 23503 and real valid B work denied to current A admin across retained/fresh/replay paths. |
| 16 | Cross-Fixture Assignment rejected. | PASS | Forged tuple composite FK 23503 and HTTP selection rejection. |
| 17 | Wrong Revision for Assignment rejected. | PASS | Forged tuple composite FK 23503 and HTTP selection rejection. |
| 18 | Partial/malformed pin rejected. | PASS | Contract malformed/partial/unknown-key cases and PostgreSQL content CHECK probes. |
| 19 | Template publication freezes exact pin. | PASS | Fresh publication, persisted exact pin, immutable published revision and real journey. |
| 20 | Shift publication materializes exact pin. | PASS | Independent Task/Template/Assignment SQL correspondence and real Shift publication. |
| 21 | Task pin is immutable. | PASS | Owner trigger and restricted runtime mutation rejection. |
| 22 | Template/Task correspondence is enforced. | PASS | Mismatch insert rejected by task_guidance_snapshot; generated fields checked. |
| 23 | Publishing another Revision alone does not invalidate retained Assignment. | PASS | R2 published without assignment leaves A1/R1 fresh and publishable. |
| 24 | Reassigning Fixture makes old Assignment stale for fresh publication. | PASS | Reassignment makes both fresh Template and Shift publication reject without partial evidence. |
| 25 | Reassigning away and back does not revive old Assignment. | PASS | A3 reassigns R1 but A1 remains unavailable for fresh work. |
| 26 | Existing Task pin survives reassignment. | PASS | Historical immutable tuple compared before/after reassignment. |
| 27 | Existing contextual read survives reassignment. | PASS | Employee and manager contextual reads return original R1 after A2. |
| 28 | Fresh publication rejects stale Assignment. | PASS | Both publication paths return planogram_guidance_unavailable atomically. |
| 29 | Relevant retirement/deactivation blocks fresh publication. | PASS | Fixture retirement, Planogram retirement, Article/Assortment deactivation publication tests. |
| 30 | Historical Task pin survives later retirement/deactivation. | PASS | Historical FK and exact pin survive retirement and normal completion. |
| 31 | Historical contextual read survives permitted lifecycle changes. | PASS | Contextual employee/manager and saved Template previews survive permitted lifecycle changes. |
| 32 | Standalone employee current-layout behavior remains unchanged. | PASS | Existing standalone rules retained; real journey compares A2/R2 before retirement. |
| 33 | Client cannot choose arbitrary historical Assignment/Revision. | PASS | Context routes accept only Shift/Task or Template/revision IDs; query selectors rejected 400. |
| 34 | Server resolves stored Task pin. | PASS | Scoped Application loads persisted Task content before Merchandising port call. |
| 35 | Employee contextual read requires own visible Task. | PASS | Unlinked/revoked/removed link, other linked employee, wrong Shift/Task and mismatch negatives. |
| 36 | Manager contextual read requires authorized Task scope. | PASS | Manager scoped context; employee denied manager route; wrong Company/Location negatives. |
| 37 | Viewer denied. | PASS | Viewer historical route 403 tests. |
| 38 | Auditor denied according to canonical contract. | PASS | Auditor historical route 403 tests; existing capability contract unchanged. |
| 39 | Plugin denied. | PASS | Approved plugin denied historical route; session authorization remains mandatory. |
| 40 | Opening Assigned layout mutates no Task state. | PASS | Execution/number/reason input preservation and no POST widget/controller checks; SQL no changes on reads. |
| 41 | No read acknowledgment is created. | PASS | No read receipt mechanism; independent command-count comparison before/after reads. |
| 42 | No readership audit/event is created. | PASS | Independent audit count unchanged by reads; no events/outbox added. |
| 43 | Completion retains exact A1/F/R1 identity. | PASS | Completed Task, receipt and minimized audit keep original tuple in independent SQL. |
| 44 | Knowledge and Planogram guidance coexist independently. | PASS | Both guidance panels, independent clear/replace and real schema-4 dual-pin journey. |
| 45 | Knowledge lifecycle does not mutate Planogram pin. | PASS | Knowledge v2 publication/retirement preserves original Planogram identity. |
| 46 | Planogram lifecycle does not mutate Knowledge pin. | PASS | R2 assignment and Fixture/Planogram retirement preserve Knowledge v1. |
| 47 | Optional Stock failure does not hide retained layout. | PASS | Real runtime Stock SELECT outage returns unavailable while retaining frozen instruction. |
| 48 | Missing Stock differs from zero. | PASS | Separate real absent and zero reads and widget assertions. |
| 49 | Live enrichment is clearly separated from frozen evidence. | PASS | Concrete instruction/currentContext DTO and separate literal UI sections with query timestamp. |
| 50 | Article labels are not falsely represented as historical if they are live. | PASS | Current Article labels/status explicitly labeled live; frozen structure exposes Article IDs. |
| 51 | Template replay after reassignment/lifecycle change returns committed evidence. | PASS | Lost Template publication response and exact replay after lifecycle return original committed evidence. |
| 52 | Shift replay after reassignment/lifecycle change returns committed evidence. | PASS | Lost Shift publication response and exact replay after lifecycle return original IDs. |
| 53 | Replay creates no duplicate Tasks. | PASS | Independent Task count and exact returned IDs across replay. |
| 54 | Replay creates no duplicate audit. | PASS | Independent publication audit counts across replay. |
| 55 | Assignment/publication race is atomic. | PASS | Deterministic Company-lock queued reassignment races against both publication paths, both orders. |
| 56 | Retirement/publication race is atomic. | PASS | Deterministic Fixture/Planogram retirement races against both publication paths, both orders. |
| 57 | Audit failure rolls back relevant mutation. | PASS | Injected audit failure rolls back Template and Shift publication; no version/Task/audit drift. |
| 58 | Audit excludes layout content/labels/Stock. | PASS | Allowlisted bounded tuple IDs only; audit content checked independently. |
| 59 | Session replacement fences selector data. | PASS | Same/different principal replacement tests fence picker choices and captured exact selection. |
| 60 | Session replacement fences historical layout content. | PASS | Same/different principal replacement tests clear pending/cached historical panel. |
| 61 | Stale callbacks cannot update replacement session. | PASS | Completer-controlled late picker/preview/context callbacks cannot write replacement state or use its token. |
| 62 | Browser rendering is non-executable. | PASS | Actual Chrome literal editable Fixture/Article/Planogram text, DOM and JavaScript assertions. |
| 63 | API/OpenAPI error contracts are bounded and accurate. | PASS | Exact selector 200/400/401/403/404/422/500/503; no impossible 409; real HTTP lifecycle/auth/malformed/fault checks and unchanged publication 409. |
| 64 | Selection uses planogram_selection_unavailable. | PASS | Fresh selection 422 has planogram_selection_unavailable; Flutter preserves inputs. |
| 65 | Fresh publication uses planogram_guidance_unavailable. | PASS | Fresh Template/Shift 422 has planogram_guidance_unavailable; atomic failure assertions. |
| 66 | Committed replay uses neither availability error. | PASS | Committed exact replay bypasses fresh lifecycle validation after current authorization. |
| 67 | Migration 0019 upgrades populated 0018 safely. | PASS | Populated 0018 schemas 1/2/3, draft, open/in_progress/blocked/completed/cancelled tasks preserved. |
| 68 | Failed 0019 rolls back. | PASS | Injected division-by-zero at end of 0019 rolls back history, columns and source evidence. |
| 69 | Migrations 0001–0018 remain unchanged. | PASS | Read-only Git/hash comparison of all 18 predecessor migrations against HEAD. |
| 70 | Backup/restore preserves exact historical pin and contextual read. | PASS | Final encrypted acceptance: exact F/A1/R1 and F/A2/R2; 20 table hashes/2 sequences; non-empty Article/Assortment/Stock/Movement; live context; 5 Planogram denials, 14 restored rejections, 6 derived columns; fencing/corruption/cleanup. |
| 71 | Existing Knowledge guidance regressions remain green. | PASS | Full Knowledge suites, P4.6 Chrome and Knowledge Chrome passed. |
| 72 | Existing Stock regressions remain green. | PASS | Full Stock suite including old populated-migration and numeric/read context tests. |
| 73 | Existing Planogram regressions/print remain green. | PASS | Full Merchandising suite and actual 20-page print/adapter acceptance. |
| 74 | Existing Guided Work/numeric regressions remain green. | PASS | Full Guided Work suite and numeric Chrome/server-replacement E2E. |
| 75 | Real Flutter/HTTP/PostgreSQL P4.7 journey passes. | PASS | Real Flutter transport to HTTP/PostgreSQL, lost-response replay, lifecycle, completion and restart. |
| 76 | Real P4.7 browser workflow passes. | PASS | Real P4.7 Chrome editor/Shift/employee historical workflow with independent SQL verification. |
| 77 | Full repository regression is green. | PASS | Final security summary records exact four-suite counts and separate acceptance results after frozen source/tool/test/doc edits; four analyzers/formats, Web/Compose and unchanged tree fingerprint. |
| 78 | P4.7 remains review/CI pending in docs. | PASS | Canonical HANDOVER/status/README and ADR 0021 retain local implementation, independent review APPROVE, security remediation complete, targeted security re-review and remote changed-commit CI pending; no closure claim. |
| 79 | No unrelated P4.8 capability added. | PASS | Bounded diff inspection; excluded capabilities absent; no P4.8 selected. |
| 80 | Normal StoreOS database remains untouched. | PASS | Strict generated database identities, owned-resource cleanup and normal database identity check. |

## Repository and residual boundaries

Final read-only Git checks confirm `main` at unchanged HEAD/cached/live origin `a0ed6346f7453c8f4e170aee43af8d775677f97b`, empty index, no stash and one worktree. The complete implementation remains unstaged/uncommitted; nothing was pushed. Only migration 0019 is new; all 18 predecessors retain identical Git content (line-ending-normalized comparison against HEAD), and no dependency/lockfile changed. Local documentation links and `git diff --check` pass.

Read-only PostgreSQL catalog verification from `postgres` found the normal `storeos` database present and no P4.7/backup/update/recovery run databases left. The original healthy PostgreSQL container remains. No ChromeDriver or acceptance/E2E listeners remain on their owned ports. Latest backup/update run directories contain only sanitized `report.json`; keys, dumps and private manifests were removed. Normal StoreOS business data was never migrated or written by these runs. Ignored test logs/reports and the release build are retained as intentional verification artifacts.

P4.7 does not add Stock writes, events/outbox, generic guidance, per-step/multiple Planograms, read acknowledgment, photo/deviation workflows, printing extensions, recurrence, emergency withdrawal, offline queues, synchronization or a P4.8 capability. Existing supported-writer and physical-device/accessibility/operator limits remain as documented in prior accepted slices. Targeted security re-review and remote changed-commit CI are the remaining delivery gates; independent normal review APPROVE and the Security F01 chronology are preserved.
