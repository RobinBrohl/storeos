# P4.5: Approved Operational Knowledge

Status: **IMPLEMENTED LOCALLY**, **INDEPENDENT REVIEW PENDING**,
**REMOTE CHANGED-COMMIT CI PENDING**. Uncommitted on `main`; not DONE/CLOSED.
Local evidence date: 2026-10-04. Decision: [ADR 0019](../adr/0019-approved-operational-knowledge.md).

## Starting baseline

Before implementation, HEAD, cached `origin/main` and live remote `main` all
resolved to `ce00a241b967ab9242604e4d043a8241b3593f64`. Tree/index/untracked files
were clean, with no stash and exactly one intended worktree. P4.1/P4.2 were
committed DONE; P4.3/P4.4 were DONE/CLOSED. Migrations 0001–0016 were committed,
unchanged and no 0017 existed. Baseline [CI run 37218392419](https://github.com/RobinBrohl/storeos/actions/runs/37218392419)
had all five jobs green. This is baseline CI evidence, not CI for these changes.
No branch switch/create, commit, push, dependency installation/upgrade or lockfile
change was performed. Earlier review/closure history remains authoritative.

The immediately preceding approved plan selected this bounded slice. M1 remains
the existing proxy/operator gate; M3/M4 are contained locally on the new APIs.
Other debt was not broadened into this implementation.

## Implemented contract

Knowledge owns `WikiArticle` and `WikiRevision`, persisted in exactly
`knowledge_articles` and `knowledge_revisions` by migration
`0017_approved_operational_knowledge.sql`. Article identity is Company-scoped,
versioned and retained. One active draft may exist. Revision numbers are monotonic
and never reused. Published/discarded content is frozen by database triggers.
Composite deferred pointer FKs enforce Company, Article and published/draft state.
Retired Articles are terminal, retain publication/history and have no active draft.
Runtime column grants deny identity/creation edits, DELETE and TRUNCATE.

Creation stores an initial draft, which may be incomplete. Save persists the full
title/body at the expected Article version; normalized identical save is a no-op
without audit/version change. Replacement draft copies the current publication.
Publish approves only the saved, valid draft. Pointer/version, publication evidence
and audit commit together. Retirement freezes any draft as discarded and removes
employee visibility without deleting evidence. Domain/Application owns these
decisions; HTTP routes and Flutter widgets delegate.

Canonical size is `utf8(normalizedTitle).length + utf8(normalizedBody).length`,
maximum 8192 bytes. CRLF/CR become LF; other meaningful whitespace and Unicode are
preserved. Title is at most 120 Unicode code points, without ASCII controls;
unpaired surrogates and body NUL are rejected. Publication requires both fields
to be nonblank. The transport ceiling is separately 65536 bytes, including JSON
escaping/structure. Content is rendered literally with SelectableText: Markdown,
HTML, script tags, entities, angle brackets and links have no interpreter.

Publication requires an operation UUID and expected version. Fresh authorization
and Company/resource checks precede replay. The immutable published revision
binds Company/Article/Revision/actor/operation/expected and applied versions and
database timestamp. Exact replay returns original evidence without effects, even
after replacement publication or retirement. Reuse with a different actor,
resource or expected version returns `operation_conflict`; unknown command fields
are invalid input. Other writes have optimistic concurrency, without generic
server replay receipts or automatic rebase.

## Authorization, discovery and API

Admin has read/manage/publish; employee has read only. Auditor/viewer/plugin have
no Knowledge capability. Server authorization is fresh on each command/query.
Employee projection contains only Article/Revision IDs, title/body, revision
number and published time from active Articles' current publications. Guessed
draft/discard/history/retired IDs cannot bypass this query. Management retains
scoped draft/current/history/retired evidence.

Employee search is literal, case-insensitive title substring matching with
PostgreSQL `lower`/`strpos` under database collation. `%`, `_` and backslash are
literal; no accent folding or ranking is promised. Visibility is filtered before
the UUID keyset and 50-item limit. Management uses UUID keysets; revision history
uses descending revision-number keysets. Invalid cursors are rejected.

Twelve operations across ten paths are documented in
`packages/api_contracts/platform.openapi.json` and referenced by `openapi.yaml`:

| Path below `/api/v1/platform/knowledge` | Method / behavior |
| --- | --- |
| `/articles` | GET employee list/search |
| `/articles/{articleId}` | GET current employee instruction |
| `/manage/articles` | GET management list; POST create initial draft |
| `/manage/articles/{articleId}` | GET management detail |
| `/manage/articles/{articleId}/retire` | POST terminal retirement |
| `/manage/articles/{articleId}/revisions` | GET history; POST replacement draft |
| `/manage/articles/{articleId}/revisions/{revisionId}` | GET saved revision |
| `…/{revisionId}/edit` | POST full draft save |
| `…/{revisionId}/discard` | POST freeze active draft |
| `…/{revisionId}/publish` | POST publication/exact replay |

Strict DTOs reject unknown fields, payload scope IDs, malformed UUIDs and unsafe
versions. Endpoint tests exercise 401/403, malformed JSON/shape/fields, 400 cursor/
ID/version failures, 404 scoped absence, 409 conflicts, 413 transport/content bounds
and 415 media type. Recognized unique constraints map to bounded conflicts;
injected unknown integrity failures remain 500, and permission/unavailability
becomes 503. They do not inherit broad global constraint-to-400 mapping. Tests
check reachable response statuses against each new OpenAPI operation.

Audit records minimized identifiers, expected/applied versions, lifecycle changes,
changed field names and publication operation ID. Full title/body are absent from
audit metadata and diagnostic logs. Logging records SQL state/constraint and
request status/correlation, without content or credentials. Audit append failure
rolls back the mutation. No event/outbox producer or consumer was added.

## Flutter behavior and session safety

Manager UI separates editing, Save, saved-revision preview and Publish; unsaved
input cannot be published. History visibly distinguishes DRAFT, PUBLISHED CURRENT,
PUBLISHED HISTORICAL, DISCARDED and retired Articles. Employee UI has search,
bounded paging, current revision/time, literal text, explicit refresh and empty/
loading/error states. Meine Arbeit opens Knowledge on a separate route while
retaining the selected work page. Reading creates no work evidence.

Pending commands are immutable and bound to opaque SessionController identity.
The synchronous busy guard runs before UUID generation or pending replacement.
Live identity is checked again immediately before transport; stale callbacks are
ignored after same-account or different-account replacement, including a held
replacement-status request. Replacement clears draft fields, preview, search,
history, errors and pending state.

Uncertain publication retries the exact original route/body/operation/version.
transport failure, HTTP 408 and unexpected failure statuses retain this identity.
Duplicate submit cannot replace it. Confirmed publication followed by failed
refresh stays confirmed, retains authoritative evidence and has no write retry.
Ambiguous Save retains input and requires authoritative reload plus explicit
review before new editing. Stable Article/Revision creation UUIDs are reconciled
through authoritative reads; retry is offered only after verified absence.
Recovery is memory-only and does not survive browser reload/logout/session end.

## Local verification

Existing Flutter 3.47.5 / Dart 3.13.4, cached pinned packages and PostgreSQL 17 were
used. No dependencies were resolved/installed/upgraded. Isolated databases and
private fixtures were removed; the normal StoreOS database was not migrated or
written. Logs/reports under `.local/` are ignored, sanitized evidence for this run.

| Check | Final local evidence |
| --- | --- |
| Full API contracts suite | 79 PASS; four new Knowledge contract tests |
| Full server suite with PostgreSQL | 231 PASS; one opt-in browser test skipped here and run separately |
| Full design-system suite | 2 PASS |
| Full Flutter suite | 257 PASS; 16 new deterministic Knowledge controller/widget tests |
| Total ordinary suites | 569 PASS; one qualified skip as above |
| Knowledge PostgreSQL suite | 12/12 PASS, including the nested real Flutter/HTTP journey |
| Real Knowledge Flutter/HTTP/PostgreSQL journey | 1/1 PASS; actual controllers, HTTP routes and PostgreSQL |
| Knowledge Chrome workflow | 1/1 PASS; author/save/preview/publish, literal read/search, replacement and selected work-page return |
| Static verification | Four analyzers with fatal infos: no issues; four format checks: zero changes |
| Release Web / Compose / diff | Release build PASS, local Web resources; Compose quiet validation PASS; `git diff --check` PASS |
| Existing diagnostics/setup/crypto | Seven regression scripts PASS |
| Existing Planogram print | PASS: 100 placements, 20 A4 landscape pages, Unicode/escaping, no clipping, adapter invokes print once |
| Existing numeric Guided Work browser E2E | Three phases PASS across server replacement; isolated fixture cleanup PASS; package resolution skipped explicitly |

The 569 suite count excludes nested Flutter subprocess test counts and separately
run browser/harness checks to avoid double counting. Three existing real Flutter
subprocess journeys and the Knowledge journey also passed within server wrappers.
Initial test-harness readiness/scroll/localization issues and strict analyzer
findings were corrected; final results above use enabled controls, condition-based
polling, actual HTTP outcomes and retained assertions. No test was weakened.

The new client fake records transport calls/held responses only; it does not
implement PostgreSQL publication or concurrency semantics. Session races use
controlled completers and synchronous replacement, not timing sleeps.

### PostgreSQL and migration evidence

Real tests cover current-pointer lifecycle, late v1 replay after v2/retirement,
restart, operation conflicts and fresh-rights denial; incomplete/UTF-8/LF content;
frozen discarded revisions and number retention; scope, pointer-state constraints
and runtime grants; concurrent draft/edit/publish/retire conflicts; audit rollback,
500 unknown integrity and 503 failures; minimized audit and unchanged outbox.

The populated 0016 fixture contains published Task template evidence, Article/
Assortment, Stock opening ledger, published Planogram and Assignment plus audit.
Fourteen deterministic table snapshots match before and after a deliberately
failed 0017 and after successful 0017. Failed application leaves no Knowledge
tables and exactly 16 migration records. Successful application reports only
0017 and supports real Knowledge creation. Separately, full Task tests and update/
backup harnesses preserve instance/result/attempt/blocking/receipt evidence.
Migrations 0001–0016 match HEAD Git object hashes; no applied file was normalized.

### Backup, update and recovery evidence

Encrypted backup/isolated restore runs `89b1b9a1c3da4683` and final
`2d3e231504c742f8` PASS. Sixteen table
count/hash pairs and two sequence states match. Knowledge retains two Articles
and six revisions: three published (including historical and retired), two
discarded and one active draft. Same-scope pointers, publication operation/version
evidence and audit survive. Runtime published/discarded update, DELETE and TRUNCATE
probes remain rejected after restore. Sessions/plugin tokens are revoked, runtime
CONNECT is fenced, corruption is rejected and all owned databases are removed.

Forward update/isolated pre-update recovery runs `9277107910d14758`,
`3787fafaceb84a12` and final `12e6027c52ba43f0` PASS. The
existing populated 0010 fixture preserves 19 table snapshots across 0011–0017 and
recovering the pre-update restore point. Current HTTP smoke creates the same two
Knowledge Articles/six revision states and verifies late replay/runtime protections.
The dedicated populated 0016→0017 test above supplies the immediate-predecessor
upgrade/failed-application proof. Recovery is isolated and fenced; this does not
claim down migration, application downgrade or automatic restored activation.

Reproduction: `scripts/knowledge/Run-P45Checks.ps1` runs the isolated Knowledge
suite; `-Browser` runs opt-in Chrome acceptance; `-FullRegression` runs all ordinary
suites/static/build/Compose checks. Existing backup/update runners use
`-SkipPackageResolution` and explicit local tool paths when needed. The Knowledge
runner resolves tools from PATH or accepts `-DartPath`, `-FlutterPath`,
`-DockerPath`, `-DriverPath` and optional `-ChromePath`; it installs nothing and
refuses an occupied driver port. The numeric
runner has the same opt-out so cached pinned dependencies can be used without
resolution; its default behavior is preserved.

## Independent acceptance mapping

Each row is a separate assertion. K = real PostgreSQL Knowledge tests;
C = deterministic client tests; J = real Flutter/HTTP/PostgreSQL journey;
B = actual Chrome workflow; R = recovery harnesses; S = static/schema/diff review.

| # | Result | Assertion / evidence |
| --- | --- | --- |
| 1 | PASS | Company-scoped stable Article; K scope/lifecycle, composite keys |
| 2 | PASS | Exact Revision Article/Company ownership; K adversarial composite FKs |
| 3 | PASS | At most one draft; K concurrent draft and partial unique index |
| 4 | PASS | Incomplete draft persists; K/J creation |
| 5 | PASS | Nonblank valid publication required; K bounds/blank, contracts |
| 6 | PASS | Published immutable; K runtime probes, R restored probes |
| 7 | PASS | Discarded immutable; K discard/probes, R restored probes |
| 8 | PASS | Monotonic unique numbers; K discard/reallocation and SQL constraint |
| 9 | PASS | Publication pointer/evidence/audit atomic; K lifecycle/audit fault |
| 10 | PASS | Draft creation preserves publication pointer; K/J replacement |
| 11 | PASS | Replacement draft hidden; K/J employee reads |
| 12 | PASS | Replacement publication switches current content; K/J/B |
| 13 | PASS | Historical publication retained; K/J/R hash comparison |
| 14 | PASS | Retirement removes discovery/read; K/J employee 404/search |
| 15 | PASS | Retirement retains manager history; K/J/R |
| 16 | PASS | No hard delete; S routes, K runtime DELETE/TRUNCATE denial |
| 17 | PASS | Employee draft reads denied; K guessed ID/management denial |
| 18 | PASS | Employee discarded reads denied; K safe current-only query |
| 19 | PASS | Employee arbitrary history denied; K/J old-revision guesses |
| 20 | PASS | Employee management APIs denied; K all management operations |
| 21 | PASS | Active approved plugin token denied on all twelve endpoints; K real organization grant proves token valid |
| 22 | PASS | Admin read/manage/publish; K full lifecycle/J/B |
| 23 | PASS | Employee current active publication read; K/J/B |
| 24 | PASS | Visibility filtered before paging; K 51 visible rows plus hidden rows |
| 25 | PASS | Draft/historical titles absent from search; K literal-title fixture |
| 26 | PASS | Plain text literal; C/J/B exact markup/Unicode text |
| 27 | PASS | No rich-text/HTML execution; S SelectableText only, B literal tags |
| 28 | PASS | Required publication operation UUID; contracts/K malformed input |
| 29 | PASS | Exact replay adds no audit; K count/version equality, J lost response |
| 30 | PASS | Late v1 replay leaves v2 current; K/J explicit pointer/content equality |
| 31 | PASS | Retired replay does not reactivate; K/J terminal state equality |
| 32 | PASS | Conflicting operation reuse rejected; K actor/resource/version conflicts |
| 33 | PASS | Save rejects stale version; K edit/publish race and stale save |
| 34 | PASS | Ambiguous Save requires reload/review; C retained input and explicit acceptance |
| 35 | PASS | Confirmed publication refresh failure stays confirmed; C evidence/no retry |
| 36 | PASS | Synchronous duplicate guard; C held submission preserves UUID/payload |
| 37 | PASS | Pending publication bound to opaque identity; C same/different actor cases |
| 38 | PASS | Replacement session cannot dispatch old command; C held status/pre-dispatch replacement |
| 39 | PASS | Old callbacks cannot update new UI; C completer release after replacement |
| 40 | PASS | Audit failure rollback; K real revoked INSERT and state/audit equality |
| 41 | PASS | No full content in audit/logs; K metadata checks and S sanitized logger |
| 42 | PASS | Exactly two owned tables; S migration/Knowledge repository |
| 43 | PASS | No generic receipt table; S publication evidence on revision |
| 44 | PASS | No Task schema/execution change; S production diff and full Task regression |
| 45 | PASS | No Wiki reference in Task evidence; S contracts/schema and preserved Task snapshots |
| 46 | PASS | No readership tracking; S read paths have no audit/business write |
| 47 | PASS | No events/outbox additions; K unchanged event count and S producers |
| 48 | PASS | Populated 0016 upgrade safe; K 14 preserved snapshots, only 0017 applied |
| 49 | PASS | Failed 0017 rollback; K absent new tables, 16 records, unchanged snapshots |
| 50 | PASS | Migrations 0001–0016 unchanged; S HEAD versus working Git object hashes |
| 51 | PASS | Backup retains current/history/draft/retired; R six revision hash equality |
| 52 | PASS | Restored immutability enforced; R runtime published/discarded probes |
| 53 | PASS | New OpenAPI operations match; K response parity and S twelve-route catalog |
| 54 | PASS | Local M3/M4 containment; K malformed/large/media bodies, unknown SQL 500/outage 503 |
| 55 | PASS | No adjacent P4.6+ capability; S bounded schema/API/UI/diff |
| 56 | PASS | Real Flutter/HTTP/PostgreSQL journey; J 1/1, K wrapper |
| 57 | PASS | Meaningful browser workflow; B real authoring/employee/replacement/work return |
| 58 | PASS | Task/Stock/Planogram green; full suites, populated upgrade, R and print regression |
| 59 | PASS | Full repository regression; 569 suite passes plus static/build/Compose/scripts |
| 60 | PASS | Review/CI pending in docs; HANDOVER/status/ADR/evidence; no DONE/CLOSED claim |

## Scope and residual limits

No Task schema, execution receipt, snapshot, confirmation or completion contract
was modified. The only work UI change is the navigation shortcut. No Wiki revision
is persisted into Tasks. P4.5 does not establish which Knowledge revision informed
a completed Task; Guided Operation revision pinning needs a later approved
integration. No readership/acknowledgment, attachment, search service,
suggestion, separate review workflow, offline queue, sync, notification or new
dependency exists. Migration 0017 is the sole new migration.

Independent review and changed-commit remote CI remain pending. Browser checks do
not establish physical-device or accessibility acceptance. Pending recovery is
memory-only. Arbitrary raw runtime SQL can repoint an active Article to its own
historical publication without supported-writer version/audit advancement; SQL
still enforces ownership/state and immutable revision content. This follows the
accepted existing writer threat boundary, documented in ADR 0019. Current search
case behavior follows database collation. Existing proxy/operator deployment,
retention/key-custody and isolated-restore activation gates remain unchanged.
