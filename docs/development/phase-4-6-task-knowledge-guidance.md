# P4.6 Task + approved Knowledge revision pinning

Status: **DONE/CLOSED** — implementation `15679bf3c81f50ca31e4995d5b958d7c27e5284d`,
targeted independent review **APPROVE**, **64/64 PASS**, focused Codex Security
**SECURITY APPROVE** and fully green changed-commit CI **37287951549**.
No active P4.6 remediation remains. See [final closure](#final-documentation-closure--2026-10-05).

The implementation/pre-review/remediation sections below retain their dated local
states, including pending gates and the original CHANGES REQUIRED result. They are
historical evidence, superseded for current disposition by the final closure.
Final targeted/security outcomes are reconciled from the authoritative review
history supplied for this documentation closure; this pass did not rerun reviews.

## Verified baseline

Before implementation on 2026-10-04, main/tree/index were clean, HEAD/cached
origin/live GitHub main matched eef2f1eaf778300a10869539b8e94041113b9a07,
with one worktree, no stash, 17 unchanged migrations and no 0018. P4.1–P4.5
were canonically DONE/CLOSED and no active remediation blocked this slice.
All five jobs in [exact-baseline CI 37231793151](https://github.com/RobinBrohl/storeos/actions/runs/37231793151)
were successful. The immediately preceding P4.6 plan was reconciled with actual
repository patterns. GitHub remained read-only. Context7 clarified PostgreSQL
stored generated-column semantics and Dart browser interop after pinned-version
inspection. No broad security scan, dependency resolution or upgrade occurred.

## Architecture and behavior

[ADR 0020](../adr/0020-task-knowledge-guidance.md) records the bounded contract.
Task content schema 3 adds required nullable knowledgeGuidance. The concrete value
contains exactly articleId/revisionId; Company comes from its owner. Schemas 1/2
retain their exact shape, persisted source content, execution and replay semantics.
No Knowledge title/body/time/lifecycle is copied into Template/Task persistence.

New/replacement draft selection captures current approved Knowledge and previews
that exact revision. Unrelated editing and clone retain the pin after retirement.
Fresh Template and Shift publication validate same-Company published revision and
active Article in the authorized transaction, before any materialization. An older
retained published revision remains valid while the Article stays active. Committed
publication replay follows fresh authorization and precedes lifecycle validation,
returning original evidence without duplicate Tasks or audit. No silent upgrade occurs.

The Knowledge-owned public port never queries Tasks; Tasks repositories never query
Knowledge. Tasks/Workforce authorize visible Shift/Task first, then supply its stored
pin. Employees need current session, active Employee link, configured execution
Location, own visible Shift/Task and Knowledge read. Managers need existing authorized
Task scope and Knowledge read. Read adds no execution-window gate or cancelled-Shift
visibility. Two contextual GETs have no revision selector and reject query parameters.
The safe strict projection contains only Task/Article/Revision identity, revision number,
title/body/time, superseded and retired flags. No account/operation/audit/history data
is returned. Standalone employee discovery remains current-publication-only.

Retirement is **not emergency withdrawal**. It blocks fresh publication while existing
Tasks remain readable/executable. Exact historical content and current lifecycle flags
are distinct. Historical resolution failure never substitutes current content. Fresh
unavailable retained guidance at fresh publication uses bounded 422
`guidance_unavailable`; invalid create/replacement selection uses distinct 422
`guidance_selection_unavailable`. Retained editing/cloning is not fresh selection.
Committed publication replay emits neither availability error. Contextual failures use
bounded errors. OpenAPI inventories reachable statuses for new/touched operations.
Named supported conflicts map to 409; unexpected integrity faults remain 500 and
supported infrastructure failures 503. M3/M4 containment is local, not global closure.

Flutter provides optional select/preview/clear/replace, preserved selection, explicit
unavailable/conflict handling and save-before-publication. Shift authoring reviews pins.
The plain-text Assigned instruction panel returns to the same execution/input state.
Opaque session identity fences all new caches and callbacks, including same-account
replacement. Reads create no acknowledgment, Task mutation, receipt or readership
audit. Existing relevant audit actions add only two bounded Knowledge identity fields.

## Migration 0018 and PostgreSQL verification

Only 0018_task_knowledge_guidance.sql is new. Migrations 0001–0017 are unchanged.
The legacy validator is preserved; schema 3 is strict. Three independent stored
generated columns derive Article/Revision/published state from source JSON on both
Template revisions and Tasks. Composite FKs enforce same Company, Article and exact
published revision. Article activity is deliberately not a retained FK. The Task insert
guard enforces published Template/Task pin correspondence.

The existing BEFORE UPDATE Task guard excludes derived generated columns, computed
by PostgreSQL afterward, while preserving immutable source content and all prior
transition/evidence checks. SQL tests reject malformed, partial, unknown, cross-Article,
cross-Company, draft/discarded references, forged Task pins and generated/source drift.
Runtime permissions/guards reject published Template/Task content mutation.

Populated 0017 upgrade includes schema-1/2 drafts/publications, open/running/blocked/
completed/cancelled Tasks, confirmations/numeric results, blockings, receipts and
Knowledge history. Every old field is compared; new legacy guidance columns are
separately asserted NULL. Failed 0018 rolls back data/history/columns; reapply is empty.
Prior populated migration comparisons similarly preserve all old-field assertions.
Deterministic actual Company advisory-lock barriers test both retirement/publication
orderings, edit/publication conflict and duplicate Shift replay without sleeps.
Audit/insert fault tests preserve complete rollback assertions. Old generic 503
expectations for unexpected integrity faults were corrected to the required 500;
supported permission outages still assert 503.

## Pre-review checks and counts (historical implementation evidence)

All checks use installed pinned Dart 3.13.4, Flutter 3.47.5, postgres package 3.5.17
and PostgreSQL 17, with no package resolution. Final full runner completed successfully.

| Check | Result / exact count |
| --- | --- |
| API contracts | 94 passed, including 15 new guidance cases |
| Server / real PostgreSQL | 255 passed; 2 opt-in browser cases skipped here and passed separately |
| Flutter client | 268 passed |
| Design system | 2 passed |
| Focused Template/Task Flutter tests | 30 passed, included in full client suite |
| Real P4.6 Flutter/HTTP/PostgreSQL journey | 1 passed inside server suite |
| P4.6 actual Chrome workflow | 1 passed |
| Existing Knowledge actual Chrome workflow | 1 passed |
| Existing numeric Chrome E2E | 1 scenario passed |
| Strict analyzers | All 4 packages, zero issues |
| Formatting | 220 files across 4 packages, zero changes |
| Compose validation | Passed |
| Flutter Web release build | Passed, no pub/resources CDN |
| Backup/update report redaction | 6 and 9 cases passed respectively |
| New PowerShell runner parsing | Passed |
| Git diff/repository/resource checks | Passed |

Counts do not double-count focused reruns or nested journeys. Knowledge, Guided Work,
numeric, Stock and Planogram regressions are included. The two opt-in browser skips
are intentional and each passed in its separate real-Chrome invocation. Native-device,
physical hardware/accessibility and changed-commit CI were not performed or claimed.
Independent code/security review remains pending; no remote state was modified.
Ignored local logs: p46-regression.log, p46-browser.log, p46-knowledge-browser.log,
p46-numeric.log, p46-backup-final.log and p46-update-final.log.

The decisive real Flutter journey authors/publishes v1, selects/previews/publishes
schema-3 Template, publishes Shift, independently verifies persisted v1, publishes v2,
retires the Article, denies standalone/general history/revision guessing, reads exact
contextual v1, completes confirmation/numeric work, replays lost publication responses
and verifies restart still resolves v1. The actual Chrome workflow exercises manager
and employee UI, v2/retirement/refresh, literal script/link/image-handler/Markdown text,
no payload execution and no content-created executable/link/image DOM. Its server
fixture independently asserts completed Task pin, Template correspondence and receipts.

## Backup / restore and update / recovery

Encrypted backup/isolated restore **bf064aa35d774cba** passed: immutable source/restored
table hashes match; completed schema-3 Task stays pinned to v1 after v2/retirement;
restored constraints/generated columns/runtime protections and exact contextual read
remain valid. Employee arbitrary history is denied. Original sessions/plugin tokens
stay revoked and runtime CONNECT remains fenced. A fresh authenticated owner test
pool exercises the real authorized Application path without activating the restored
runtime or reviving old sessions. Tampered backup is rejected; source/restore/corruption
databases and acceptance service are removed.

Update/recovery **869bb8c06a574c2d** passed: populated 0010 upgrades through 0018,
checksums/all old projections preserved, second run empty. Current-server HTTP smoke
creates/completes schema-3 Task after v2/retirement and verifies exact v1 plus runtime
protections. Existing Stock/Planogram/Knowledge evidence remains (3 Knowledge Articles,
8 revisions including guidance). Recovery restores pre-update 0010 into a separate
fenced target, preserving old evidence and revoked credentials, without normal-installation
activation/downgrade. Both databases and acceptance port are removed.
Sanitized reports are retained under ignored .local/backup-acceptance/bf064aa35d774cba/report.json
and .local/update-recovery/869bb8c06a574c2d/report.json.

## Pre-review acceptance criteria (historical implementation assessment)

The initial implementation assessment below predates independent review. That review
returned CHANGES REQUIRED for criterion 51's selection/publication error contract;
the post-remediation reassessment below supersedes this initial 64/64 assessment.

| # | Result | Criterion | Evidence |
| --- | --- | --- | --- |
| 1 | PASS | Task guidance is optional. | No-guidance contract/UI and schema-1/2/3 contextual 404/execution tests. |
| 2 | PASS | Guidance stores exact WikiArticle identity. | Concrete two-field value and generated article ID SQL assertions. |
| 3 | PASS | Guidance stores exact WikiRevision identity. | Concrete two-field value and generated revision ID SQL assertions. |
| 4 | PASS | No Knowledge content is copied into Task persistence. | Independent persisted JSON checks; audit allowlist contains IDs only. |
| 5 | PASS | Schema 3 explicitly represents guidance. | Strict schema-3 decoder/OpenAPI/SQL validator. |
| 6 | PASS | Schemas 1/2 remain behaviorally unchanged. | Legacy execution, strict content, replay and numeric regressions. |
| 7 | PASS | Existing schema-1/2 persisted content is not rewritten. | Populated upgrade compares every old source field. |
| 8 | PASS | Draft selection uses a published Knowledge Revision. | Current approved picker; HTTP/SQL non-published-state rejection. |
| 9 | PASS | Template publication freezes exact reference. | Exact publication and published Template immutability tests. |
| 10 | PASS | Shift publication materializes exact reference into TaskInstance. | Independent persisted Task pin/Template correspondence checks. |
| 11 | PASS | TaskInstance reference is immutable. | Runtime content/generated-column mutation refusal. |
| 12 | PASS | New Knowledge publication cannot change retained pin. | v2 publication retains v1 Template/Task/read/completion evidence. |
| 13 | PASS | Article retirement before Template publication rejects fresh publication. | Retired draft publication 422, editable draft preserved. |
| 14 | PASS | Article retirement before Shift publication rejects fresh publication. | Retired fresh Shift publication 422 with complete rollback. |
| 15 | PASS | Retirement after Shift publication preserves contextual task read. | Employee/manager exact v1 reads after retirement and restore. |
| 16 | PASS | Retired Article remains absent from standalone employee Knowledge discovery. | Standalone employee current read 404 after retirement. |
| 17 | PASS | Superseded pinned Revision remains readable through legitimate Task. | Exact v1 body with superseded flag; real journeys. |
| 18 | PASS | Employee cannot arbitrarily browse historical Knowledge. | Employee history 403; arbitrary revision route 404. |
| 19 | PASS | Client cannot choose Revision on contextual Task read. | No revision selector; all query parameters rejected. |
| 20 | PASS | Server resolves pin from stored TaskInstance. | Authorized Task detail supplies stored decoded pin to Knowledge port. |
| 21 | PASS | Cross-Company reference rejected. | Company authorization and composite-FK SQL 23503. |
| 22 | PASS | Cross-Article Revision reference rejected. | Wrong Article rejected by HTTP and SQL 23503. |
| 23 | PASS | Draft Revision reference rejected. | Draft-state selection/SQL FK rejected. |
| 24 | PASS | Discarded Revision reference rejected. | Discarded-state selection/SQL FK rejected. |
| 25 | PASS | Partial/malformed guidance rejected. | Strict DTO and PostgreSQL malformed/partial reference tests. |
| 26 | PASS | Template/Task snapshot correspondence enforced. | Task insert guard rejects forged pin versus published Template. |
| 27 | PASS | Existing Task snapshot immutability preserved. | Original snapshot and transition/evidence checks retained. |
| 28 | PASS | Existing Task execution semantics unchanged. | Full Guided Work and real confirmation/numeric completion. |
| 29 | PASS | Opening guidance creates no acknowledgment. | No read writes, receipt or readership audit; unchanged SQL counts. |
| 30 | PASS | Opening guidance changes no Task state. | Panel return preserves execution status/input; read does not mutate Task. |
| 31 | PASS | Completion retains immutable assigned reference. | Completed JSON and completion audit retain v1. |
| 32 | PASS | No generic InstructionReference abstraction added. | Diff/ADR: one concrete KnowledgeGuidance only. |
| 33 | PASS | No generic receipt table added. | Only new migration 0018, no new tables. |
| 34 | PASS | No events/outbox added. | Existing audit actions only; no new events/outbox writes. |
| 35 | PASS | No Planogram guidance added. | No Planogram guidance or Merchandising production change. |
| 36 | PASS | Fresh publication authorization includes Knowledge read. | Knowledge read check in fresh authorized publication and replay. |
| 37 | PASS | Employee contextual read requires own visible Task. | Own employee/link/Location/Shift/Task HTTP negatives. |
| 38 | PASS | Manager contextual read requires authorized Task scope. | Existing manager Task visibility plus Knowledge read. |
| 39 | PASS | Viewer/auditor/plugin denied contextual Knowledge. | Viewer/auditor 403 and plugin credentials 401. |
| 40 | PASS | Late Template publication replay after retirement returns committed evidence. | Exact committed Template replay after retirement. |
| 41 | PASS | Late Shift publication replay after retirement returns committed evidence. | Exact committed Shift replay after retirement. |
| 42 | PASS | Replay creates no duplicate TaskInstances. | Replay/duplicate publication asserts one materialization. |
| 43 | PASS | Replay creates no duplicate audit. | Replay asserts unchanged relevant audit counts. |
| 44 | PASS | Retirement/publication race is atomic. | Deterministic advisory-lock barriers, both retirement orderings. |
| 45 | PASS | Audit failure rolls back relevant business mutation. | Injected audit faults 500 with complete business rollback. |
| 46 | PASS | Audit contains no Knowledge title/body. | Allowlisted IDs and SQL audit checks, no instruction text. |
| 47 | PASS | Session replacement fences picker data. | Held picker/preview tests for same/different account replacement. |
| 48 | PASS | Session replacement fences historical Task content. | Immediate historical cache clearing on opaque identity change. |
| 49 | PASS | Stale old-session callback cannot update new UI. | Old held callbacks cannot mutate replacement session UI. |
| 50 | PASS | Plain-text contextual browser rendering is non-executable. | Actual Chrome literal script/link/image/Markdown and DOM assertions. |
| 51 | PASS | New contextual APIs have complete bounded OpenAPI/error contracts. | Bounded contextual status parity, strict projection and HTTP faults. |
| 52 | PASS | Migration 0018 upgrades populated 0017 safely. | Populated 0017 upgrade: schema-1/2, all Task states and receipts. |
| 53 | PASS | Failed 0018 rolls back. | Failed 0018 leaves source/history unchanged and columns absent. |
| 54 | PASS | Migrations 0001–0017 unchanged. | Final Git comparison against HEAD: old migrations unchanged. |
| 55 | PASS | Backup/restore preserves schema-3 pins and historical contextual read. | Encrypted restore bf064aa35d774cba: v1 contextual read and constraints. |
| 56 | PASS | Existing Knowledge publication/history evidence remains green. | Full Knowledge suite, existing Chrome workflow and recovery evidence. |
| 57 | PASS | Existing Stock/Planogram evidence remains green. | Full Stock/Planogram suites and retained recovery evidence. |
| 58 | PASS | Existing Guided Work/numeric execution remains green. | Full Guided Work suites and real numeric browser E2E. |
| 59 | PASS | Real Flutter/HTTP/PostgreSQL P4.6 journey passes. | Real Flutter controllers/HTTP/PostgreSQL, SQL evidence and restart. |
| 60 | PASS | Real browser P4.6 workflow passes. | Actual Chrome manager/employee flow and independent SQL evidence. |
| 61 | PASS | Full repository regression is green. | Final suites, analysis, formatting, release build, Compose and diff checks. |
| 62 | PASS | P4.6 remains review/CI pending in docs. | HANDOVER/status/ADR explicitly implementation local, review/CI pending. |
| 63 | PASS | No unrelated P4.7+ capability added. | Hard-scope/diff verification; P4.7 not selected. |
| 64 | PASS | Normal StoreOS DB remains untouched. | Disposable strictly named DB runners; normal DB only existence checks. |

## Pre-review scope, residual limits and repository state (historical)

No Planogram/per-step/multiple/polymorphic guidance, generic InstructionReference,
read acknowledgment, training certification, read-conditioned completion, branching,
emergency withdrawal/reconciliation, regeneration, offline queue, configurable RBAC,
events/outbox or P4.7 capability was added. No dependency/lockfile/CI workflow change,
branch/commit/push/issue/PR occurred. Implementation is uncommitted/unstaged on main.
Normal StoreOS business data was not read, written, migrated, backed up, restored or
dropped; only catalog existence checks refer to that database. Run-owned databases,
drivers/servers/private browser define directories are cleaned up. Ignored sanitized
reports/logs remain for review; existing Docker/database services are not run-owned.
Targeted F01 review and changed-commit CI are remaining gates. Existing broader debt,
P4.5 LOW follow-ups, native/accessibility limits and operator gates retain their scope.
HANDOVER/status/architecture reflect local implementation, never DONE/CLOSED. P4.7
is not selected.

## Independent review and bounded F01 remediation — 2026-10-05

The supplied independent review returned **CHANGES REQUIRED** with exactly one
actionable finding: **F01 — LOW, COMMIT BLOCKER**. `guidance_unavailable` was emitted
outside its intended publication-only scope, including initial/replacement draft
selection. The other 63 criteria passed that review. This historical review remains
the authoritative pre-remediation result; no targeted approval is claimed here.

The Knowledge port now chooses bounded 422 `guidance_selection_unavailable` only
when validating fresh selection. TaskTemplate create and changed-pin edit already
invoke that selection mode; no mutation, authorization or replay ordering was moved.
Invalid selections include retired Articles, superseded non-current revisions and
missing/foreign/draft/discarded references. Unchanged retained-pin editing and
published-to-draft cloning still do not reselect or validate fresh availability.
Fresh Template/Shift publication continues to return 422 `guidance_unavailable`.
Committed publication replay still returns original evidence after authorization,
without either availability error, duplicate Tasks/audit or pin changes.

Flutter distinguishes selection failure from publication failure. A failed selection
save keeps local title, step text and chosen reference intact, while authoritative
draft/content/version remain unchanged and editable. Publication failure preserves
the saved Template/Shift draft and asks the manager to review/remove/replace the
retained instruction or review the Shift's Template selection. No unrelated UI changed.
`ApiError` already transports bounded string codes, so no shared DTO/taxonomy change
was necessary. Migration 0018, schema persistence, snapshots, replay, historical
reads, authorization, rendering and recovery production behavior are unchanged.

### OpenAPI / M3 route inventory

The inventory follows the route -> service -> Knowledge port and existing bounded
transport/authorization/database mappings. All five touched POST operations document
400/401/403/404/409/413/415/500/503 with operation-specific error descriptions and the
shared `ApiError` response. Their distinct validation responses are:

| POST operation | Actual reachable availability / validation response |
| --- | --- |
| `/task-templates` | 422 `guidance_selection_unavailable`; configured Location 404; no publication availability error or `empty_template`. |
| `/task-templates/{id}/revisions` | No availability 422: clones exact retained published content, including after retirement. |
| `/task-templates/{id}/revisions/{revisionId}/edit` | 422 `guidance_selection_unavailable` only for changed/new selection; unchanged retained pin editing remains allowed. |
| `/task-templates/{id}/revisions/{revisionId}/publish` | 422 `empty_template` or `guidance_unavailable` for fresh publication; committed replay precedes availability checks. |
| `/shifts/{id}/publish` | 422 `shift_not_publishable`, `employee_unavailable`, `invalid_selection` or `guidance_unavailable` for fresh publication; exact replay returns original Shift/Tasks. |

Paths above are relative to `/api/v1/platform`. The two contextual GET operations
retain 200/400/401/403/404/500/503, no availability 422 and no client-selected revision.
OpenAPI regression checks reject publication errors on selection-only operations,
selection errors on publication operations and availability 422 on clone. This
contains criterion 51/M3 locally; it does not close global M3/M4 debt.

### Fresh verification

Installed pinned SDKs/packages were reused without dependency resolution. Focused
checks preceded the full regression. Logs are under ignored `.local/p46-remediation/`.
These are new runs of the remediated working tree, not copied pre-review results.

| Check | Fresh result / exact count | Evidence |
| --- | --- | --- |
| Focused guidance HTTP/PostgreSQL | 26 passed; includes 2 new selection rollback tests, both publication errors, exact replay and real Flutter journey | `focused-server.log` |
| Focused guidance contract/OpenAPI | 16 passed; includes selection/publication/clone contract separation | `focused-contracts.log`; full run verifies final response descriptions |
| Focused Template/Task/Shift Flutter | 32 passed; includes 2 new failure-preservation tests | `focused-flutter.log` |
| API contracts | 95 passed | `full-regression.log` |
| Server / PostgreSQL | 257 passed; 2 opt-in browser cases skipped in this suite and executed separately | `full-regression.log` |
| Flutter client | 270 passed | `full-regression.log` |
| Design system | 2 passed | `full-regression.log` |
| Full suite total | 624 passed; focused/nested journeys are not added again | 95 + 257 + 270 + 2 |
| Strict analyzers | All 4 packages, zero issues | `full-regression.log` |
| Formatting | 220 files, zero changes | `full-regression.log` |
| Flutter Web release / Compose | Passed, `--no-pub --no-web-resources-cdn`; Compose config passed | `full-regression.log` |
| Real P4.6 Flutter/HTTP/PostgreSQL journey | 1 passed inside focused/full server suites, including independent SQL and restart | `focused-server.log`, `full-regression.log` |
| Actual P4.6 Chrome workflow | 1 passed | `p46-browser.log` |
| Existing Knowledge Chrome workflow | 1 passed | `knowledge-browser.log` |
| Existing numeric Chrome E2E | 1 scenario passed, all 3 browser phases and process replacement/replay | run `4e786e9707fd41e5b6268c1d45965f83`, `numeric-browser.log` |
| Backup/restore | 1 acceptance passed, including exact historical v1, immutability, revocation/fencing and tampered backup refusal | run `63148c0fccb44788`, `backup-restore.log` |
| Update/recovery | 1 acceptance passed, populated 0010 -> 0018, unchanged old projections/checksums, empty second migration run and separate fenced 0010 recovery | run `7363c2f8d6a04176`, `update-recovery.log` |
| Backup/update report redaction | 6 / 9 cases passed | `backup-redaction.log`, `update-redaction.log` |

Backup/update sanitized reports are retained under ignored
`.local/backup-acceptance/63148c0fccb44788/report.json` and
`.local/update-recovery/7363c2f8d6a04176/report.json`; both report all run-owned
databases removed, acceptance ports free and normal database present. Existing
Knowledge, Stock, Planogram and Guided Work tests ran in the full regression;
backup/update also compare their retained evidence.

### Post-remediation acceptance reassessment

Each criterion was reassessed against the bounded correction, newly executed tests,
and initial-versus-final file fingerprints. Source/persistence invariants outside
the error mapping remain byte-identical to the reviewed implementation. Independent
targeted review and changed-commit CI are still gates; this is local verification.

| # | Result | Reassessed criterion and fresh evidence |
| --- | --- | --- |
| 1 | PASS | Optional guidance: schema-1/2/3 no-guidance HTTP execution and Flutter tests rerun. |
| 2 | PASS | Exact Article identity: contract round trip and generated-reference SQL tests rerun. |
| 3 | PASS | Exact Revision identity: round trip, persisted pin and replay SQL assertions rerun. |
| 4 | PASS | No copied Knowledge text: Task JSON/audit minimization assertions rerun; persistence unchanged. |
| 5 | PASS | Explicit schema 3: strict DTO/OpenAPI/SQL validator tests rerun. |
| 6 | PASS | Schema-1/2 behavior: legacy execution and numeric regressions rerun. |
| 7 | PASS | Old content not rewritten: populated upgrade projection/checksum comparison passed anew. |
| 8 | PASS | Approved selection: invalid foreign/missing/draft/discarded/non-current/retired cases use the selection error; picker tests pass. |
| 9 | PASS | Template freezes exact pin: publication/immutability and replay tests rerun. |
| 10 | PASS | Shift materializes exact pin: real HTTP/SQL and browser workflow rerun. |
| 11 | PASS | Task reference immutable: source/generated-column drift refusals rerun. |
| 12 | PASS | New Knowledge publication leaves retained pin: v2 lifecycle/contextual/completion test rerun. |
| 13 | PASS | Retirement before Template publication: 422 `guidance_unavailable`, no audit and editable saved draft verified. |
| 14 | PASS | Retirement before Shift publication: 422 `guidance_unavailable`, zero Tasks/audit verified. |
| 15 | PASS | Retirement after publication retains read: employee/manager and restored exact-v1 reads verified anew. |
| 16 | PASS | Retired Article hidden from standalone discovery: employee 404 regression rerun. |
| 17 | PASS | Superseded pin readable contextually: exact-v1 body and lifecycle flags verified anew. |
| 18 | PASS | Arbitrary employee history denied: negative HTTP and restored contextual-scope checks rerun. |
| 19 | PASS | Contextual read accepts no Revision choice: query rejection and OpenAPI checks rerun. |
| 20 | PASS | Stored Task resolves pin: unchanged coordinator/port boundary plus actual HTTP/SQL journey verified. |
| 21 | PASS | Cross-Company rejection: authorization and composite-FK cases rerun. |
| 22 | PASS | Cross-Article rejection: fresh selection bounded error and SQL FK rejection rerun. |
| 23 | PASS | Draft Revision rejected: selection/SQL cases rerun with corrected selection semantics. |
| 24 | PASS | Discarded Revision rejected: HTTP/SQL rejection rerun. |
| 25 | PASS | Partial/malformed pin rejected: strict DTO and PostgreSQL cases rerun. |
| 26 | PASS | Task/Template correspondence enforced: forged-snapshot insertion rejection rerun. |
| 27 | PASS | Existing snapshot immutability: unchanged migration/service and full Guided Work SQL checks. |
| 28 | PASS | Execution semantics preserved: full execution/exception/numeric suites and real completion journeys. |
| 29 | PASS | Reads create no acknowledgment: unchanged read code and read/audit/receipt-count assertions rerun. |
| 30 | PASS | Reads do not change Task state: Flutter return/input and HTTP state checks rerun. |
| 31 | PASS | Completion keeps assigned reference: completed persisted v1 and minimized audit assertions rerun. |
| 32 | PASS | No generic InstructionReference: remediation fingerprint inventory shows only existing concrete pin/error handling. |
| 33 | PASS | No generic receipts: unchanged migration 0018 adds no tables; initial/final fingerprint matches. |
| 34 | PASS | No events/outbox added: only error mapping changes in server production; audit/state failure assertions pass. |
| 35 | PASS | No Planogram guidance: unchanged Merchandising production fingerprints and regression tests. |
| 36 | PASS | Fresh/replay Knowledge authorization: existing scoped/role negatives and authorization-before-replay retained. |
| 37 | PASS | Own visible Task required: Employee/link/Location/Shift/Task negatives rerun. |
| 38 | PASS | Manager scoped read: own authorized-context read and foreign-company denial rerun. |
| 39 | PASS | Viewer/auditor/plugin denied: 403/401 contextual negatives rerun. |
| 40 | PASS | Template replay after retirement: exact original revision evidence, HTTP 200, no error code and unchanged audit. |
| 41 | PASS | Shift replay after replacement/retirement: original Shift/Task IDs, HTTP 200, no availability error. |
| 42 | PASS | No duplicate Tasks: exact and queued duplicate-publication counts rerun; pin unchanged. |
| 43 | PASS | No duplicate audit: exact publication/completion replay counts rerun. |
| 44 | PASS | Retirement/publication race atomic: both advisory-lock orderings for Template and Shift rerun. |
| 45 | PASS | Audit fault rollback: both named/unknown integrity fault cases rerun; state and audit unchanged. |
| 46 | PASS | Audit avoids title/body: unchanged allowlist and fresh persisted evidence assertions. |
| 47 | PASS | Picker session fencing: held same/different-account replacement tests rerun. |
| 48 | PASS | Historical content session fencing: immediate opaque-identity clearing tests rerun. |
| 49 | PASS | Stale callbacks cannot repopulate UI: held picker/preview/contextual callbacks rerun. |
| 50 | PASS | Literal browser rendering: actual P4.6 Chrome workflow repeats text/DOM/no-execution assertions. |
| 51 | PASS | New/touched bounded errors: route inventory, corrected OpenAPI, distinct HTTP 422 codes, clone and replay regressions. |
| 52 | PASS | Populated 0017 safely upgrades: fresh schema-1/2/all-state/receipt preservation test. |
| 53 | PASS | Failed 0018 rolls back: source/history unchanged and generated columns absent checked anew. |
| 54 | PASS | 0001–0017 unchanged: no tracked migration diff against HEAD; 0018 matches pre-remediation fingerprint. |
| 55 | PASS | Backup keeps pins/history: acceptance `63148c0fccb44788` validates restored contextual v1 and protections. |
| 56 | PASS | Knowledge regressions: full Knowledge suites and populated backup/update history checks rerun. |
| 57 | PASS | Stock/Planogram regressions: full suites and backup/update evidence comparisons rerun. |
| 58 | PASS | Guided Work/numeric: full execution/exception/numeric suites; numeric browser result recorded above. |
| 59 | PASS | Real Flutter/HTTP/PostgreSQL: actual P4.6 journey plus independent SQL/restart passed anew. |
| 60 | PASS | Real P4.6 browser: actual Chrome manager/employee workflow passed anew. |
| 61 | PASS | Full regression: 624 passing package tests, analyzers/format, release build and Compose; final resource/diff checks below. |
| 62 | PASS | Status remains local/pending: historical CHANGES REQUIRED preserved, targeted review/remote CI pending; no DONE/CLOSED. |
| 63 | PASS | No P4.7+ feature: bounded file fingerprint/diff inventory, no unrelated production changes. |
| 64 | PASS | Normal DB untouched: strictly disposable runners, source/restore cleanup and normal-name catalog checks only. |

Recommendation: targeted independent review of F01 and criterion 51, followed by
the existing changed-commit CI gate. P4.6 remains IMPLEMENTED LOCALLY,
INDEPENDENT REVIEW REMEDIATION COMPLETE / TARGETED REVIEW PENDING,
REMOTE CHANGED-COMMIT CI PENDING; it is not DONE/CLOSED. No commit/push is authorized.

### Remediation repository and resource audit (historical)

Branch remains `main`, HEAD and cached `origin/main` remain
`eef2f1eaf778300a10869539b8e94041113b9a07`; one worktree, no stash, empty index.
The full P4.6 implementation remains uncommitted/unstaged; nothing was committed
or pushed. Migrations 0001–0017 have no diff against HEAD. The only new migration
is still 0018, whose SHA-256 matches the starting remediation fingerprint. All
package manifests/lockfiles and unrelated production files match the starting
fingerprints; manifests/lockfiles also have no diff against HEAD. The remediation
changes only the Knowledge availability error mapping, Template controller message,
focused tests, touched OpenAPI descriptions and P4.6 status/evidence documentation.

Final catalog checks find zero P4.6 test databases and zero run-owned backup/update
databases; the normal database is present. No acceptance listeners remain on
4444/9545/8095/8096/8097/8099, no acceptance fixture/driver processes remain, and
no private P4.6/Knowledge browser define directories or numeric define manifest
remain. Normal StoreOS business data was not read/written/migrated/restored.
Existing Docker/database services remain operator-owned. Ignored sanitized
reports/logs are retained for review. `git diff --check` passed.

## Final documentation closure — 2026-10-05

### Verified closure baseline and committed implementation

Before these documentation edits, branch was `main`, tree/index were clean, HEAD
and cached `origin/main` both equaled
`15679bf3c81f50ca31e4995d5b958d7c27e5284d` (Add task knowledge guidance).
Live read-only `git ls-remote origin refs/heads/main` independently returned the
same SHA. There was no stash and exactly one intended worktree, `C:/dev/storeos`.
This implementation commit is present after P4.5 closure baseline
`eef2f1eaf778300a10869539b8e94041113b9a07`.

Git comparison of that baseline to the implementation finds only migration
`0018_task_knowledge_guidance.sql` added; 0001–0017 have unchanged Git content.
The tracked migration chain contains exactly 0001–0018, with no 0019. Package
manifests/dependency lockfiles have no change. Migration 0018 adds bounded
Task/Knowledge reference integrity, no generic receipt table. This closure edits
Markdown only and performs no database operation, implementation/test/migration/
script/CI/OpenAPI/dependency change, branch creation/switch, staging, commit or push.

### Authoritative review and acceptance chronology

1. Fresh P4.6 capability selection chose **Task + Approved Knowledge Revision Pinning**.
2. Architecture selected concrete KnowledgeGuidance with exact WikiArticle/WikiRevision
   identity, schema 3 preserving schemas 1/2, pin frozen at Template publication and
   materialized into immutable TaskInstance content, and contextual historical read
   through legitimate Task context. No generic instruction abstraction, arbitrary
   historical browsing, Planogram guidance, acknowledgment or event was selected.
3. Local implementation completed and migration 0018 added bounded reference integrity.
4. Initial local acceptance reported 64/64; the first independent adversarial review
   returned **CHANGES REQUIRED**, with exactly one actionable finding, **F01 — LOW
   but commit-blocking**: selection-time reuse of `guidance_unavailable`. The other
   63 criteria passed. The original verdict remains historical and was not APPROVE.
5. Bounded remediation split selection and fresh-publication errors, retaining
   committed replay and all persistence/authorization/execution boundaries.
6. Targeted independent review returned **APPROVE**. Final acceptance was **64/64 PASS**.
7. Focused Codex Security review returned **SECURITY APPROVE**; no confirmed/probable
   P4.6 vulnerability or security commit blocker remained.
8. Implementation committed as `15679bf3c81f50ca31e4995d5b958d7c27e5284d`; its actual
   changed-commit CI is fully green. Documentation closure records **DONE/CLOSED**.

The full first review and bounded remediation are preserved above. The targeted
APPROVE and focused Security outcome/coverage below are authoritative results
supplied in the closure request, not newly executed reviews or invented report IDs.
Historical acceptance criterion 62 correctly described pending status at its own
assessment time; final current status is now DONE/CLOSED.

Final acceptance includes the remediated 624 passing package tests, strict analyzers,
formatting, Web build, real Flutter/HTTP/PostgreSQL journey, actual Chrome workflow,
existing Knowledge/numeric browser regressions, backup/restore and update/recovery.
Native-device, physical-device and accessibility acceptance are not claimed.

### Exact changed-commit CI evidence

Live GitHub run lookup for the implementation SHA returned
[CI run 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549),
run number 42, event `push`, branch `main`, attempt 1, **completed / success**.
Its head SHA is exactly `15679bf3c81f50ca31e4995d5b958d7c27e5284d`.
Run/job conclusions were fetched read-only during this documentation closure.

| Required CI job | Job ID | Status | Conclusion |
| --- | --- | --- | --- |
| dart | 111691257197 | completed | success |
| flutter | 111691257141 | completed | success |
| numeric-guided-work-e2e | 111691257095 | completed | success |
| backup-restore-acceptance | 111691256890 | completed | success |
| update-recovery-acceptance | 111691257133 | completed | success |

The earlier exact-baseline run 37231793151 remains historical evidence for
`eef2f1e`, not a substitute for implementation-commit CI.

### Final delivered contract and error/replay boundary

Guidance is optional and concrete: `KnowledgeGuidance` stores only `articleId` and
`revisionId`, never copied Knowledge title/body. Schema 3 explicitly represents
nullable guidance; schemas 1/2 and old persisted content remain behaviorally unchanged.
A manager explicitly selects the exact approved revision in a draft. Template
publication validates/freezes that pin; fresh Shift publication revalidates it and
copies the reference into immutable TaskInstance content. Task execution resolves
that exact stored pin, never whichever revision is current at execution time.

Knowledge v2 publication leaves retained Template/Task v1 pins and contextual reads
at v1. Retirement after Shift/Task publication leaves the Article retired, standalone
employee discovery unavailable and legitimate existing contextual v1 reads and Task
execution/completion available. Retirement before fresh Template/Shift publication
rejects the fresh operation. Retirement is **not an emergency withdrawal mechanism**.

- Selection/authoring: invalid unavailable new/replacement selection returns
  `guidance_selection_unavailable`.
- Fresh Template/Shift publication: unusable retained guidance returns
  `guidance_unavailable`.
- Committed replay: fresh current authorization/scope is still required; original
  evidence is returned without either availability error merely because Knowledge
  later changed/retired. Template replay adds no duplicate audit; Shift replay returns
  original Shift/Task IDs, adds no duplicate Tasks/audit and leaves pins unchanged.

Opening Assigned instruction does not start/complete a Task, complete a step,
satisfy numeric input, acknowledge reading, create readership tracking/receipt,
emit an event or mutate execution state. Completion retains Knowledge identity
because TaskInstance content is immutable; no proof of reading/understanding/following
an instruction is claimed.

### Historical authorization, module ownership and content safety

Employees cannot browse arbitrary historical Knowledge. Contextual historical,
superseded or retired-context read requires a valid current session, active Employee
link, Company/Location/work visibility, own visible Shift/Task, Task self-read,
an exact stored Task pin and Knowledge read. Managers require existing authorized
Shift/Task scope plus Knowledge read, not a general historical browser. The contextual
endpoint derives Article/Revision from stored Task content; no client-selected
arbitrary WikiRevision is accepted. Viewer, auditor and approved plugin tokens are denied.

Guided Template authoring/publication requires appropriate Task authorization plus
Knowledge read; guided Shift publication requires existing Shift publication
authorization plus Knowledge read where guidance exists. Roles remain fixed.

Tasks owns selection and immutable snapshot inclusion; Knowledge owns approved
content, revision lifecycle, exact published-revision validation and exact contextual
historical resolution; Workforce retains Shift publication context. Knowledge does
not query Tasks tables and Task repositories do not query Knowledge tables.
No generic polymorphic InstructionReference was introduced.

Contextual Knowledge renders literal text: no HTML/script execution, content-generated
active anchor/image/onerror behavior or rich Markdown. The verified safety comes
from literal rendering, not a general rich-text sanitizer. Mutation audit may carry
bounded `knowledgeArticleId`/`knowledgeRevisionId`; audit/logs exclude title/body/full
instruction content. Reads produce no readership audit, receipt or event.

### Focused Codex Security disposition

**SECURITY APPROVE**: no confirmed/probable P4.6 vulnerability or security commit blocker.
The supplied focused review covered historical Knowledge boundaries, IDOR/Task
ownership, cross-Company isolation, cross-Article/Revision integrity, viewer/auditor/
plugin denial, revoked/expired sessions, removed Employee links, session replacement/
stale callbacks, hostile schema-3 input, SQL injection, database privilege changes,
stored HTML/script/link/image injection, audit/log privacy, replay authorization,
retirement/publication races and backup/restore security boundaries.
Accepted threat-model exclusions, including privileged arbitrary SQL, remain accepted
boundaries rather than unresolved P4.6 vulnerabilities.

Tooling/report-bookkeeping note: the sealed Codex Security workbench reportedly
retained an obsolete pending-worker checkpoint and labeled coverage partial. The
supplied reconciliation states all **21 changed source items** were reviewed, the
worker had completed and no actionable finding remained. This is report bookkeeping,
not a product vulnerability or blocker. No sealed-workbench artifact/report ID is
invented or independently reverified by this documentation-only pass.

### Recovery evidence and retained follow-ups

The supported backup/restore evidence above retains schema-1/2 Tasks, schema-3 pins,
v1 historical identity, later Knowledge v2, Article retirement, Task completion,
related receipts and audit. Restored legitimate contextual read resolves original
v1; arbitrary history stays denied. Runtime protections/session/token fencing remain
valid. The update evidence includes clean migration through 0018, populated
0017→0018, failed-0018 rollback, unchanged old Task content/receipts, schema-3 pins,
Knowledge/Stock/Planogram/audit evidence and isolated fenced recovery. The end-to-end
populated wrapper also traverses 0010→0018. No downgrade support is claimed.

P4.5 F01 (mounted standalone Knowledge search text surviving session replacement)
remains open. P4.5 F02 also remains a broader non-blocking follow-up: P4.6 materially
strengthens its new contextual browser surface without closing global rendering proof.
M1 proxy/login-limiter pilot gate, closed M2, per-new-endpoint M3 containment, broader
M4 taxonomy, supported-writer/raw-SQL accepted boundary, memory-only uncertain-command
recovery and physical-device/accessibility/operator gaps keep their existing scope.
No unrelated debt is reopened and no cleanup project is introduced.

### Documentation validation

`git diff --check` passed; `git status`, `git diff --stat` and the full `git diff`
were reviewed. The diff is limited to ten Markdown documents, unstaged/uncommitted.
Canonical pending-state search leaves only explicitly historical assessment/remediation
wording; the original CHANGES REQUIRED verdict is preserved. Local document link
targets and the new final-closure anchor were checked. Migration/dependency invariants
and clean index were rechecked. No software regression was rerun for this docs-only
closure; software acceptance remains the recorded local runs and exact-commit CI.

### Final disposition and next state

Next action after the documentation closure commit is fresh P4.7 capability selection.
No P4.7 capability is preselected or ACTIVE. No Planogram/per-step/multiple guidance,
generic workflow engine, acknowledgment, offline queues or configurable RBAC was added.

P4.6 **DONE/CLOSED**. No active P4.6 remediation remains.
