# P4.16 Stage B2a — authenticated bilateral swap HTTP transport

Current INGRESS-01/02 remediation, 2026-10-16: **both findings fixed locally and
verified; independent targeted re-review pending.** Latest independent verdict:
**STAGE B2a CHANGES REQUIRED**, INGRESS-01 MEDIUM and INGRESS-02 LOW. F01–F03
remain independently **CLOSED**. The complete eligible server run on one frozen
source snapshot is **1053 PASS / 0 FAIL / 21 explicit opt-in SKIP**. See the
[two-finding remediation record](#ingress-01--ingress-02-local-remediation--2026-10-16)
for exact changes, hashes, tests, skips and remaining qualifications. P4.16
remains **IN PROGRESS**; no independent approval, B2b work or publication is claimed.

Previous native ingress implementation record, 2026-10-16: **native ingress implemented locally;
independent targeted transport review pending.** F01–F03 are independently
**CLOSED**. The then-current independent overall verdict was **STAGE B2a INSUFFICIENT
EVIDENCE**, concerning finite retention of unfinished uploads. No material
resource-exhaustion vulnerability was demonstrated. The separately authorized
implementation and its evidence are recorded [below](#native-ingress-remediation--2026-10-16)
and in [ADR 0031](../adr/0031-bounded-native-http-ingress.md). Earlier dated review
and author-remediation statements below retain their historical context. P4.16
remains **IN PROGRESS**; no B2a approval, B2b work or publication is claimed.

Current remediation, 2026-10-14: **F01/F02/F03 fixed locally and verified;
independent targeted re-review pending.** The historical independent verdict
is **STAGE B2a CHANGES REQUIRED**, with three LOW functional contract findings and
no confirmed security vulnerability. It is not replaced by author approval. The
[remediation record](#f01f02f03-local-remediation--2026-10-14) below is the current
change/evidence inventory; the original 13-path implementation record retains its
reviewed baseline and historical verification. P4.16 remains IN PROGRESS.

Date: 2026-10-14. **Local uncommitted implementation verified; independent review pending.**
P4.16 remains **IN PROGRESS**. This implements the remaining HTTP-specific scope
of implementation-plan Step 6 on the independently approved and integrated
Stage A/B1 baseline. Independent adversarial B2a review is the next gate.
No B2a independent approval, public OpenAPI parity, publication or closure is claimed.

## Baseline, authorization and final Git boundary

The owner's attached instruction authorized local B2a implementation/testing,
bounded router composition, indispensable Application transport adapters and
this handoff. It explicitly excluded commits, pushes, PRs, implementation merges,
deployment, new migrations, changed consent/claims, Step 7 generated OpenAPI,
Steps 8–9 Flutter/UI and Step 10 expanded recovery implementation.

Before editing, the working tree and index were clean on
`codex/p416-stage-b1-swap-orchestration`, HEAD
`ce66dd57668101da037aef530ac2be0fc94e797e`.
`git fetch origin` verified `origin/main` at exactly
`289dc07bc5b8e85b3a3430f45244e13adc9e3a11`.
Local main was at `525abb7c975d08d8c93aeca3ac72e58ccbb38ce3` and was safely
fast-forwarded with `git switch main; git merge --ff-only origin/main`.
`codex/p416-stage-b2a-swap-http` was created from that exact integrated commit.
The Stage A/B1 branches and published history were preserved.

The baseline [main CI run 38547731797](https://github.com/RobinBrohl/storeos/actions/runs/38547731797)
was read through GitHub: push event, exact `289dc07…` head, attempt 1, completed
SUCCESS, all five jobs SUCCESS. This is integrated baseline evidence, not B2a CI.
The earlier design-only and local/pending-publication statements in the plan,
contract, architecture documents and Stage A/B1 handoffs retain their dated history.
They do not supersede the owner's verified integrated baseline or B2a authorization.

HEAD, local main and origin/main remain at `289dc07…`; the implementation is
uncommitted and the Git index is empty. No B2b work is started.

## Complete implementation inventory

Modified tracked paths:

```text
apps/server/lib/src/application/shift_swap_application.dart
apps/server/lib/src/http/platform_app.dart
apps/server/test/merchandising_fixture.dart
docs/HANDOVER.md
docs/roadmap/status.md
```

New untracked paths:

```text
apps/server/lib/src/http/shift_swap_routes.dart
apps/server/test/shift_swap_http_fixture.dart
apps/server/test/shift_swap_http_test.dart
apps/server/test/shift_swap_http_parser_test.dart
apps/server/test/shift_swap_http_privacy_test.dart
apps/server/test/shift_swap_http_pagination_test.dart
apps/server/test/shift_swap_http_error_test.dart
docs/development/phase-4-16-stage-b2a.md
```

The test fixture's only extension is an optional Company ID, with unchanged
defaults, so two real isolated installations can prove cross-Company privacy
without violating the database's one-Company invariant. No existing assertions
are weakened. All five new HTTP test files use network requests to `ServerApp`,
the actual Shelf composition/authentication/error boundary, and restricted SQL.
They do not mock Application results or use direct B1 commands for swap acceptance.
Existing owner-port fixture helpers only construct references or inspect evidence;
guided work is constructed through the existing HTTP fixture.

Ignored local evidence lives in `.local/p416-stage-b2a/` and the existing isolated
B1 harness's `.local/p416-stage-b1/<run>/tests.log`. It is excluded from the source
inventory. Migration files 0001–0029, dependency lockfiles, generated OpenAPI,
CI, client/UI and recovery tools/fixtures are unchanged.

## Implemented operation inventory

Every path below has prefix `/api/v1/platform`. GET responses are 200. All POSTs
accept the approved `ShiftSwapCommandInput` fields for their resolved command.

| Method and path | Application method / exact kind | Request fields or queries | Response |
| --- | --- | --- | --- |
| GET `/employee-home/shifts/{id}/swap-colleagues` | `colleagues` | `after` only | `ShiftSwapColleaguePageDto` |
| GET `/me/shift-swaps` | `list(self: true)` | `status`, `direction`, `after` | `ShiftSwapPageDto` |
| POST `/me/shift-swaps` | `command`, `request` | `requestId`, `operationId`, `sourceShiftId`, `expectedSourceVersion`, `recipientEmployeeId` | `ShiftSwapCommandResult`, 201 |
| GET `/me/shift-swaps/{id}` | `detail(self: true)` | none | `ShiftSwapDetailDto` |
| GET `/me/shift-swaps/{id}/history` | `historyPage(self: true)` | `after` only | receipt page, described below |
| GET `/me/shift-swaps/{id}/counterparts` | `counterparts` | `after` only | `ShiftSwapCounterpartPageDto` |
| GET `/me/shift-swaps/{id}/counterparts/{shiftId}` | `counterpart` | none | `ShiftSwapLegDto` |
| POST `/me/shift-swaps/{id}/offer` | `command`, `offer` | `operationId`, `expectedVersion=1`, `counterpartShiftId`, `expectedCounterpartVersion` | `ShiftSwapCommandResult`, 200 |
| POST `/me/shift-swaps/{id}/confirm` | `command`, `confirm` | `operationId`, `expectedVersion=2` | `ShiftSwapCommandResult`, 200 |
| POST `/me/shift-swaps/{id}/decline` | `command`, `decline` | `operationId`, `expectedVersion=1 or 2` | `ShiftSwapCommandResult`, 200 |
| POST `/me/shift-swaps/{id}/withdraw` | `withdraw`, resolved `source_withdraw` / `recipient_withdraw` | `operationId`, `expectedVersion`, `reason` | `ShiftSwapCommandResult`, 200 |
| GET `/locations/{locationId}/shift-swaps` | `list(self: false)` | `status`, `after` | `ShiftSwapPageDto` |
| GET `/locations/{locationId}/shift-swaps/{id}` | `detail(self: false)` | none | `ShiftSwapDetailDto` |
| GET `/locations/{locationId}/shift-swaps/{id}/history` | `historyPage(self: false)` | `after` only | receipt page |
| POST `/locations/{locationId}/shift-swaps/{id}/approve` | `command`, `manager_approve` | `operationId`, `expectedVersion=3` | `ShiftSwapCommandResult`, 200 |
| POST `/locations/{locationId}/shift-swaps/{id}/reject` | `command`, `manager_reject` | `operationId`, `expectedVersion=1..3`, `reason` | `ShiftSwapCommandResult`, 200 |

The router is registered after the existing Shift and P4.11 transfer routers and
before TaskTemplate/other platform routers. Distinct path segments preserve their
existing routing/payloads. No business lifecycle is implemented in the router.

## Transport and DTO behavior

Bearer authentication uses the existing platform session conventions, including
live session/Account validation again in the authorized Company transaction.
All JSON output uses `jsonResponse` with `application/json; charset=utf-8`.
The existing middleware supplies `cache-control: no-store`, correlation UUID,
`nosniff`, frame/referrer protection and existing origin policy. HTTP tests assert
status, JSON shape, media type/charset, no-store, nosniff and correlation header.

Every POST uses `readJson(limit: 8192, rejectDuplicateNames: true)` and the approved
strict command DTO. Media type is case-insensitive `application/json`, allowing
parameters; missing/other media types return 415. Declared and actual streamed
UTF-8 byte limits return 413. Exact 8192-byte JSON succeeds. Duplicate decoded
object names at every nested level return `invalid_json` before DTO processing.

A route-local broadcast request stream prevents a streaming size rejection from
cancelling the native HTTP input before Shelf can deliver its 413. After the
bounded reader cancels, the source drains discarded chunks without retaining them.
The shared helper and existing P4.11 stream handling are unchanged. Real declared
and chunked ASCII/multibyte overflow and subsequent valid requests are verified.

Unknown fields, missing fields, wrong types, invalid command stages/versions,
non-UUID IDs and injected actor/Account/owner/replacement/snapshot/timestamp/role/
kind fields fail strictly. UUID case is normalized exactly; whitespace is refused.
Reasons use existing trimmed plain text, 1–500 Unicode code points, excluding
control characters. Confirmation binds only the immutable offered pair.

Every endpoint rejects unknown/duplicate decoded query keys, even on POST. Detail
and commands accept none. `status` is one of the seven approved lifecycle states;
self-only `direction` is `incoming` or `outgoing`. No client page-size parameter is
accepted. Cursor strings are limited to 2048 characters. Lists, colleagues and
own counterparts contain at most 50 results.

Responses reuse the Stage A/B1 DTOs without edits: colleague items contain only
Employee ID/display name; counterpart pages contain own Shift ID/version/interval;
selected counterpart and request legs contain deliberately disclosed exact work
references and replacement lineage. Detail separates original evidence, current
actionability/reason, participant role and available actions. Command results retain
`operationId`, exact `kind`, `acceptedVersion`, stored `statusCode`, original request
evidence and `replayed`. Accepted mutations and historical replays use the result's
stored status; a historical request replay remains HTTP 201.

Exact public response field inventory for subsequent OpenAPI work:

| DTO / object | JSON fields |
| --- | --- |
| All page envelopes | `items`, `nextCursor` (nullable); history items are unchanged command results |
| Colleague item | `employeeId`, `displayName` |
| Counterpart metadata item | `shiftId`, `version`, `startsAt`, `endsAt` |
| `ShiftSwapDetailDto` | `request`, `participantRole`, `actionable`, `nonActionableReason`, `availableActions` |
| `ShiftSwapCommandResult` | `operationId`, `kind`, `acceptedVersion`, `statusCode`, `request`, `replayed` |
| `ShiftSwapDto` | `id`, `companyId`, `locationId`, `sourceEmployeeId`, `recipientEmployeeId`, `sourceName`, `recipientName`, `status`, `version`, `requestedAt`, `requestOperationId`, `offeredAt`, `offerOperationId`, `confirmedAt`, `confirmationOperationId`, `terminalAt`, `terminalOperationId`, `terminalKind`, `terminalReason`, `legs` |
| `ShiftSwapLegDto` | `leg`, `sourceShiftId`, `sourceVersion`, `sourceEmployeeId`, `incomingEmployeeId`, `startsAt`, `endsAt`, `tasks`, `taskLinks`, `replacementShiftId` |
| Disclosed Task reference | `id`, `templateId`, `revisionId`, `position`, `title`, `knowledgeGuidance`, `planogramGuidance` |
| Task lineage item | `sourceTaskId`, `replacementTaskId`, `sourceShiftId`, `replacementShiftId`, `templateId`, `revisionId`, `position` |

Nullable lifecycle fields remain explicit nulls in the existing DTOs; guidance
pins retain their exact established Article/Fixture/Assignment/Revision ID shapes.
No Account/link/version basis, instruction content or execution evidence is added
to swap DTOs. The unchanged strict contract definitions remain the authoritative
shape/type/state validation source; this table does not replace Step 7 schemas.

## Authorization and withdrawal resolution

Existing fixed swap capabilities remain unchanged: Employee has self read/request/
respond; Admin additionally has manage; Viewer/Auditor/plugin have none. Manager
approval retains Shift manage, Task read, exact guidance rights and independence
from both captured consenting Accounts. A participant promoted to Admin cannot
approve its own pair.

Configured Company/Location, live session, eligible current Employee linkage,
participant or manager resource scope are rechecked before evidence/receipt reads.
B sees addressed requests and only B-owned candidate Shifts. A cannot use B's
candidate endpoints. Unrelated Employees receive empty discovery lists or bounded
404 errors, never another request's evidence, occupancy details or private identity
bases. Guessed foreign resources and valid credentials for another installation
are refused. The real other-Location manager cannot read or approve the original
Location's request; wrong configured Location paths return 403.

`withdraw` resolves intent from authorized stored participant identity in one
`runAuthorized` transaction. The current eligible source Employee resolves to
`source_withdraw`, including a replacement Account's explicit stale-work closure.
Only the exact captured B Account/link resolves to `recipient_withdraw`; its DTO
and Domain transition require the offered/confirmed stage. No client role/kind is
trusted; no attempted unauthorized mutation/fallback occurs.

The existing command body is extracted into a private transaction method shared
by direct B1 commands and the adapter. All lifecycle, replay, claim, owner-port,
audit and final approval rules retain their original implementation. Role
resolution does not depend on today's terminal state: the same accepted withdrawal
can replay after closure and claim release. Exact kind/actor/request/payload/version
receipt binding remains authoritative; replacement Accounts cannot replay another
actor's accepted request. Failed commands consume no operation UUID.

## Scoped history contract

The existing internal `history` method still returns at most four immutable
`ShiftSwapCommandResult` receipts. New `historyPage` supplies a narrow transport
envelope `{items: [original receipt results], nextCursor: string|null}` with **two
receipts per page**, ascending accepted version. This makes the specified `after`
parameter useful without modifying receipt DTOs, adding schema or a history index.

The base64url JSON cursor binds history endpoint, Company, configured Location,
request, self/manager reader class and a SHA-256 digest of reader Account/current
link plus both captured Account/link/version bases. Only the digest is exposed;
private raw identity fields are absent. Its marker is the exact existing
`[acceptedVersion, operationId]` receipt. Scope, marker shape/types and membership
are checked. It advances strictly beyond that receipt; the exact last receipt
returns an empty page. Bad, substituted, cross-reader, cross-request and cross-
endpoint cursors return 400. Supplied cursors are never silently ignored, including
an encoded null marker (also rejected by the shared Application cursor validator).

Current request authorization precedes history cursor decoding and receipt access.
An unrelated Employee or another configured Location/Company cannot use a cursor
to discover request existence or history. Reader relinking invalidates prior
history cursors. Generic transport query/length errors remain resource-independent.
Participant and manager two-page traversals, exact order, original `replayed=false`
history, terminal exhaustion and malicious cursor substitutions are verified.

## Observed HTTP error matrix

Errors have only the existing `{code, message}` JSON shape and middleware headers.
Tests forbid SQL, schema names, stack/exception details and Account/link basis in
responses. The following outcomes are observed through real HTTP, not direct
Application exception assertions.

| HTTP | Observed codes | Conditions / evidence |
| --- | --- | --- |
| 400 | `invalid_json` | malformed/non-object JSON, duplicate decoded names including nested arrays/objects |
| 400 | `invalid_request` | missing/unknown/injected command fields, wrong types/versions/reasons/IDs, unknown/duplicate queries, invalid filters |
| 400 | `invalid_cursor` | malformed/overlong/empty cursors, wrong scope/endpoint/reader, null/invalid history markers, invalid counterpart marker shape |
| 401 | `unauthorized` | absent/malformed/random, expired/revoked sessions, revoked old links, plugin tokens, foreign-installation credentials, Company mismatch |
| 403 | `forbidden` | Viewer/Auditor, employee manager access, configured Location mismatch, participant self-approval |
| 404 | `not_found` | unavailable/protected requests or own work, unrelated Employee, wrong participant/counterpart, replacement B identity, cross-Company/Location resource IDs |
| 409 | `swap_conflict` | wrong current lifecycle or expected request version |
| 409 | `shift_conflict` | source/counterpart version mismatch |
| 409 | `operation_conflict` | changed request/payload/version/kind or actor binding of an accepted operation UUID |
| 409 | `swap_already_pending` | shared current Shift claim already occupied; bounded error without another request's details |
| 409 | `shift_overlap` | third published Shift overlaps the final exchanged roster |
| 422 | `shift_not_swappable` | actual request/offer capture crosses original start; actual deferred approval validation crosses original start |
| 422 | `employee_unavailable` | unknown or stale captured Employee/Account/link/version basis |
| 422 | `guidance_unavailable` | exact Knowledge pin retired before approval |
| 422 | `planogram_guidance_unavailable` | exact deployed Planogram replaced before approval |
| 413 | `body_too_large` | declared/chunked bodies beyond 8192 UTF-8 bytes |
| 415 | `unsupported_media_type` | absent or unsupported media type |
| 503 | `database_unavailable` | injected supported SQLSTATEs 08006, 42501, 55P03, 57014, 57P01, 53300 at the actual restricted command boundary |
| 500 | `internal_error` | unrelated 23503/23505/23514/42P01 defects, lookalike marker, exact capture marker on manager approval, real malformed leg version even after expiry |

The reviewed **23514 / swap_leg_future** discriminator is preserved byte-for-byte
in migration 0029 and in the existing Application mapping. Only request/offer
capture uses it for 422. The actual malformed-version counterexamples after
expiry remain 500. Deferred approval-time enforcement still uses the separate
`swap_approval_future` marker and rolls back all effects. No SQL exception mapping
is broadened. Supported unavailable failures and integrity faults injected at
receipt insertion occur after attempted cancellation/replacement work; canonical
hashes prove full rollback and the same failed approval UUID subsequently succeeds.

## Verification and retained diagnostic history

Runtime: pinned Dart 3.13.4, locked cached dependencies, PostgreSQL 17-alpine,
image digest `sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24`.
Every new HTTP command uses the actual restricted `storeos` login. Owners install
schema/barrier/fault fixtures and inspect canonical hashes; they do not substitute
for runtime commands. Databases end in `_test`; containers are disposable, removed
by the existing harness, and its generated secret files are blanked. No secrets,
normal database, served Web assets or real employee data enter the handoff.

Commands from the repository root use the existing harness:

```powershell
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test/shift_swap_http_test.dart','test/shift_swap_http_parser_test.dart','test/shift_swap_http_privacy_test.dart','test/shift_swap_http_pagination_test.dart','test/shift_swap_http_error_test.dart') -Analyze
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test') -Analyze
```

| Check | Result / local evidence |
| --- | --- |
| Final five-file B2a HTTP suite | **47 PASS / 0 FAIL / 0 SKIP**, exit 0, 2m48s; `.local/p416-stage-b1/80a643b54b084f959750042f6af214f1/tests.log` |
| Initial lifecycle/closure suite | **14 PASS / 0 FAIL / 0 SKIP**, exit 0; `.local/p416-stage-b1/23948b3a7aff4cafa175bc42840c2f0d/tests.log` |
| Corrected parser/privacy plus complete error/clock suite | **31 PASS / 0 FAIL / 0 SKIP**, exit 0; `.local/p416-stage-b1/265e277b3a9046deb3e67534b6d26279/tests.log` |
| Full server regression | **981 PASS / 0 FAIL / 21 explicit opt-in SKIP**, exit 0, 20m04s; `.local/p416-stage-b1/1e3747a75d1a468392e1df97e4665656/tests.log` |
| API contracts, unchanged suite and analyzer | **362 PASS / 0 FAIL / 0 SKIP**, exit 0, no issues; `.local/p416-stage-b2a/contracts.log` |
| Server analyzer | PASS, no issues, including final dedicated and broad harness starts |
| Format | PASS, 310 server/contract files, zero changes; pinned non-writing formatter |
| Whitespace, preserved-file and final inventory/index checks | PASS; 13 intended paths, index empty, 29 unchanged migration hashes and six unchanged HTTP test-file hashes; `.local/p416-stage-b2a/final-verification.json` |

Counts from overlapping invocations are not additive unique coverage. B2a's 47
cases comprise lifecycle/closure/replay/ordinary work (14), strict parser/query
cases (4), authentication/privacy/identity/scope cases (7), actual large-page and
history-cursor traversals (2), and SQL/clock/guidance/claim/overlap errors (20).

The full invocation includes every Stage B1 Application/clock/guidance/pagination/
identity regression, the entire retained F01 future-error/migration matrix, Stage A
shared-claim/integrity/clock/remediation/populated upgrade tests, P4.11 domain,
HTTP lifecycle/parser/privacy/replay/guidance/rollback/concurrency and migration
tests, platform authentication/security and HTTP smoke, ordinary Shift/Task
execution and guidance, affected Stock/P4.15 suites, and existing non-opt-in
backup/recovery regressions. All passed. P4.11 routing/payloads remain unchanged;
the new router's real composition does not shadow its operations or existing
Shift, Task, Employee Home and Platform routes. Existing non-opt-in Flutter
controller journeys executed by server tests also passed; this is retained
compatibility evidence, not swap Flutter delivery.

All **21 opt-in skips** preserve their existing gates: Article quantity Flutter/
Chrome/encrypted recovery (3), Knowledge Chrome (1), preparation assignment
Flutter/Chrome/encrypted recovery (3), preparation batch Flutter/Chrome (2),
Purchasing Flutter/Chrome (2), delivery encrypted recovery (1), order encrypted
recovery (1), Recipe Flutter/Chrome (2), P4.11 transfer Flutter/Chrome (2), Stock
count Flutter/Chrome (2), Task Knowledge Chrome (1), Task Planogram Chrome (1).
The exact case names and reasons are in
`.local/p416-stage-b2a/full-server-skips.json`. No unexecuted opt-in is labeled PASS.
No new swap/browser/recovery opt-in replaces the direct 47-case HTTP acceptance.

The first combined draft invocation retained **23 PASS / 4 FAIL / 0 SKIP**, exit 1:
`.local/p416-stage-b1/309e978040e14938ba6d5cfd7ec085ae/tests.log`.
The chunked size limit exposed native stream cancellation before response headers;
the route-local drain fixes it. Three fixture errors were corrected: peer candidate
privacy must be tested at the original invitation stage; expired session timestamps
must satisfy the existing expiry check; foreign Companies need separate isolated
installations to preserve the singleton constraint. Assertions were retained and
the final dedicated suite passes. A contracts sandbox attempt failed all 34 file
loads on denied compiler temporary output; **no acceptance tests executed**. The
authorized rerun uses the exact cached test package from its package config and
passes. Initial authoring format/path/syntax diagnostics were corrected before
the final runs; they are not acceptance passes.

## Remaining gates and independent review eligibility

Step 7 is separate. `platform.openapi.json`, `openapi.yaml`, generated operations
and contract package README are unchanged. B2b must generate all 16 implemented
operations above, exact request/response DTO schemas (including the new two-receipt
history envelope), scoped cursor/query restrictions, original-status replay and
per-operation actual error sets; add route/DTO/OpenAPI parity tests and the planned
release Flutter Web compile. Complete public API parity is **not** claimed.

Steps 8–9 still require Flutter data/controllers, immutable session-fenced pending
intents, employee/manager pair-review surfaces and real browser journeys. B2a's
ordinary incoming-work test uses existing authenticated HTTP work behavior; it is
not a new swap Flutter/browser acceptance. No new client/design-system suite or
Web build is claimed for this server-only diff.

Step 10's swap-inclusive encrypted/fenced backup/update/recovery implementation
and acceptance remain pending. The existing recovery fixtures/CI are preserved.
General recovery wrappers are not rerun by B2a: no schema, recovery tool, generated
contract or recovery fixture changed. Existing regression cases and explicit opt-in
skips remain distinct from expanded P4.16 recovery acceptance. Native devices,
accessibility, operator/retention/offboarding, labor-law and multi-site/offline
qualifications remain unchanged.

With broad verification and final inventory/index checks complete, this local branch
is eligible for **independent adversarial Stage B2a review**, focusing on shared
withdrawal intent/receipt binding, scoped history/cursor substitutions, runtime
authorization/privacy, streaming parser delivery, exact F01 discrimination and
deferred paired approval. No independent approval is self-declared. Stop with
local uncommitted code/documentation and an empty index; do not publish the
partially documented API, begin B2b, or mark P4.16 DONE/CLOSED.

## F01/F02/F03 local remediation — 2026-10-14

### Authorization, exact reviewed snapshot and historical verdict

The owner authorized only bounded F01–F03 corrections, directly related tests and
this handoff update. No migration, consent/claim/replay redesign, unrelated feature,
OpenAPI, Flutter, expanded recovery, commit, publication or deployment is authorized.

Before editing: branch `codex/p416-stage-b2a-swap-http`, HEAD and cached origin/main
`289dc07bc5b8e85b3a3430f45244e13adc9e3a11`, exactly the original five modified/eight
untracked paths, and empty index. All **42 raw SHA-256 hashes** from the independent
snapshot matched: the 13 implementation paths and all 29 migration files. Windows
separator differences in the manifest were normalized only for path comparison;
the files and raw hash values were not changed. Initial comparison-script diagnostics
incorrectly assumed a separate migration array and then uniform slash separators;
the corrected complete comparison established zero discrepancies before patching.
Read-only `git ls-remote --heads origin main codex/p416-stage-b2a-swap-http` confirmed
exact remote main and no published B2a branch. No ref update/fetch was performed.

The complete review and security report were read, including all reproduction,
source/hash, positive probe and qualified-framing records:

```text
C:\Users\Robin\.codex\state\plugins\codex-security\scans\storeos\289dc07bc5b8e85b3a3430f45244e13adc9e3a11_20261014T114034Z_aj3e8w4n\artifacts\Stage-B2a-independent-review.md
C:\Users\Robin\.codex\state\plugins\codex-security\scans\storeos\289dc07bc5b8e85b3a3430f45244e13adc9e3a11_20261014T114034Z_aj3e8w4n\report.md
```

**Historical independent verdict: STAGE B2a CHANGES REQUIRED.** The review reported
155 focused source tests PASS, 362 contract tests PASS, 11 observed HTTP races PASS
and the full four-actor HTTP journey PASS. It independently reproduced the three
LOW contract defects below, without confirming protected-row disclosure, inherited
consent, replay duplication or partial approval effects. Its vulnerability-only
security report contains no reportable security vulnerability; that disposition
is not implementation approval. All original review sources/logs/manifests and
workbench artifacts remain untouched. The review's draft/load/framing failures and
its 21 opt-in qualifications remain historical evidence, not silently relabeled.

### Original reproductions and before/after results

The unchanged archived `adversarial_input_test.dart` was run before editing using
the existing isolated PostgreSQL harness. It produced **1 PASS / 3 FAIL / 0 SKIP**,
exit 1, reproducing the original expected-outcome failures. The separate unchanged
scalar/marker diagnostic selection produced **2 PASS / 0 FAIL / 0 SKIP**, reporting
all eight malformed-scalar HTTP outcomes and all four typed-marker code mismatches.
Those diagnostic passes characterize the old defects; they do not mean acceptance.

| Finding / exact trigger | Before | After |
| --- | --- | --- |
| F01: escaped lone high/low surrogate, high followed by text, or text followed by lone low; source withdrawal and manager rejection | `500 / internal_error`, message `Swap database operation failed.`; canonical JSONB cast raises 22P02; no committed effects | `400 / invalid_request`, message `Invalid swap reason.`; rejected before canonical encoding/persistence; failed UUID remains reusable |
| F02: genuine issued self list cursor reused after source Account/link replacement | 200, one continuation item | `400 / invalid_cursor`, no evidence page or mutations |
| F02: genuine issued manager cursor reused by another authorized same-Location manager | 200, one continuation item | `400 / invalid_cursor`, no evidence page or mutations |
| F03: correct list envelope plus marker `1`, `true`, `[]` or `"bad"` | `400 / invalid_request` | `400 / invalid_cursor` |

After correction, the **unchanged original four-test input probe passes 4/4** as
part of the 18-case focused invocation. Its historical F03 envelope is necessarily
stale after F02's scope extension; the new F03 tests separately mutate **genuine
current server-issued envelopes**, proving typed conversion is corrected rather
than merely masked by an outdated scope. Exact before/after diagnostics are retained
in `.local/p416-b2a-remediation/before-http-outcomes.txt` and `after-http-outcomes.txt`.

### F01 correction: Unicode scalar validation at the shared reason boundary

`transferReason()` in `packages/api_contracts/lib/src/shift_transfers.dart` now
checks UTF-16 code units after the existing trim. Each high surrogate D800–DBFF
must be immediately followed by a low surrogate DC00–DFFF; a valid pair is skipped
as a pair, and a standalone low surrogate is refused. Invalid sequences raise the
existing sanitized `TransferInputException('invalid_reason', …)` before counting
runes or returning text. The existing 1–500 Unicode-code-point and control-character
checks remain unchanged. There is no truncation, replacement or normalization of
malformed scalars and no new restrictions on well-formed supplementary characters.

The traced failure path was escaped ASCII JSON → valid UTF-8/JSON decode → a Dart
String containing an unpaired surrogate → previously permissive shared validator →
canonical command JSON → PostgreSQL JSONB 22P02 → existing sanitized integrity 500.
The patch interrupts that path in the input validator. Swap DTOs retain their existing
conversion to `SwapInputException('Invalid swap reason.')`, producing HTTP
`400 / invalid_request`. P4.11 retains `400 / invalid_reason` with its existing
plain-text bounds message. Neither the HTTP middleware nor SQL/integrity exception
classification is broadened.

Actual HTTP tests cover source withdrawal, captured recipient withdrawal after offer
and manager rejection. Escaped inputs include both extreme lone high and low units,
reversed/repeated surrogates and high followed by a non-low BMP unit. Invalid commands
preserve complete business hashes, including receipts/audit/claims/consent, and the
attempted operation UUID has no receipt or audit. The same UUID subsequently accepts
an explicit valid closure and exact replay returns the original result.

Valid escaped pairs for U+10000, U+10FFFF and emoji, mixed BMP/supplementary text,
exactly 500 valid code points, 501 valid code points and existing forbidden controls
are tested. The HTTP 500-point mixed reason `A😀` repeated 250 times persists exactly
after trimming and replays correctly. Direct contract tests exercise the shared
helper and all three reason-bearing P4.11 and swap command kinds. Actual P4.11
withdrawal/rejection tests reject malformed scalars without effects and accept/reuse
the valid 500-point reason. Existing valid P4.11 payloads and reason semantics remain.

### F02 correction: current reader basis inside the authorized transaction

List scope retains its existing domain, Company, configured Location, Employee and
direction/status filters. It adds explicit `self`/`manager` family and a SHA-256
digest of `[reader Account ID, current Account version, current self link ID,
current self link version]`. The Employee identity remains explicitly scoped for
self lists; manager scopes now differ by reader instead of sharing null Employee.

The current Account version is obtained through the minimal public Identity owner
port `EmployeeLinks.currentReaderAccountVersion(tx, actor)`. Its private identity
repository already provides the scoped active Account record; the port releases
only the version and checks actor Company/Location. Application calls it inside
the existing currently authorized, Company-locked transaction. No foreign
repository/table access, extra authorization grant, signing key or persistence is
introduced. Consent bases, fresh progression and historical command replay remain
unchanged. Only list cursor context uses the current reader version.

The current readable envelope is:

```text
["swaps", companyId, locationId, employeeId|null, direction|null, status|null,
 "self"|"manager", readerBasisSha256, lastRequestId]
```

No raw Account ID, Account version or link ID/version enters the readable cursor.
Ordering, filtering, 50-item pages and 2048-character cursor limits remain. Earlier
list scope envelopes are rejected as stale with `400 / invalid_cursor`.

The new genuine-issued-cursor matrix constructs 51 real requested swaps and verifies
complete, duplicate-free source, recipient and manager traversals. It rejects another
Employee, another authorized manager, source and recipient Account/link replacement,
same-Account relinking, self and manager Account-version ABA, changed Company/Location,
direction/status and endpoint family. Company and Location tests include genuinely
authorized separate-installation/other-Location managers. The same linked Admin is
authorized for both families but cannot interchange their issued cursors. Each
authorized new reader can obtain a fresh cursor and traverse all expected rows.
Decoded payloads are checked for raw private IDs and numeric version leakage.
Invalid/stale cursor uses return exact `400 / invalid_cursor` without mutations.
Existing session/capability failures retain their 401/403 before protected evidence.

### F03 correction: local typed-marker error boundaries

Two private Application helpers validate cursor-only UUID and timestamp markers.
`_cursorUuid` requires the normalized UUID to equal its input, refusing malformed,
wrong-type and noncanonical uppercase/whitespace markers. `_cursorInstant` uses the
existing strict explicit-UTC/offset/calendar validator. Each catches only the typed
conversion's `FormatException` and raises sanitized `400 / invalid_cursor`.

Participant/manager list and colleague UUID markers, both counterpart timestamp/UUID
markers, and history operation UUID markers use these local validators. Existing
envelope length/scope/null checks and history exact receipt membership remain.
There is no catch around an entire request, no invalid-marker-to-null fallback and
no change to generic route ID/filter/command classification or database integrity.
Route/command UUID case normalization remains supported; internal cursor UUID markers
are strict canonical identities.

Tests mutate actual issued participant, manager, colleague, counterpart and history
cursors: wrong JSON types, malformed/noncanonical UUIDs, null markers, wrong array
length, invalid calendar/syntax/missing-zone timestamps, missing/extra envelope
fields, wrong endpoint and wrong reader digest. Every refused marker returns
`400 / invalid_cursor` with unchanged business hashes. Unauthorized counterpart
access still returns 404 before cursor data, and malformed unrelated route IDs and
filters retain `400 / invalid_request`. Genuine continuation/history order remains.

### Verification commands, counts and compatibility

All invocations use pinned Dart 3.13.4, the existing locked package config and the
existing `Run-P416StageB1Checks.ps1` harness. HTTP uses loopback Shelf and actual
restricted `storeos` PostgreSQL commands. Owners install isolated fixture data,
read hashes and apply diagnostic faults; they do not replace runtime command roles.
No normal database, public server, credentials or real personnel data were used.
All new source tests live in the repository; review artifacts are only read/executed.

From the repository root, with `$reviewArtifacts` assigned to the unchanged review's
absolute artifacts directory shown above:

```powershell
# Original before/after required expectations (same archived bytes).
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @("$reviewArtifacts/adversarial_input_test.dart")
# Before-only diagnostic matrices documenting the old 500/code mismatch.
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @("$reviewArtifacts/adversarial_framed_test.dart") -TestName 'independent malformed scalar matrix|independent invalid list-marker matrix'
# Focused new regressions plus unchanged original expectations.
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test/shift_swap_http_remediation_test.dart',"$reviewArtifacts/adversarial_input_test.dart")
# All original 47 plus final 14 new HTTP cases.
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test/shift_swap_http_test.dart','test/shift_swap_http_parser_test.dart','test/shift_swap_http_privacy_test.dart','test/shift_swap_http_pagination_test.dart','test/shift_swap_http_error_test.dart','test/shift_swap_http_remediation_test.dart') -Analyze
# Unchanged reviewed races, four-actor journey and complete framing controls.
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @("$reviewArtifacts/adversarial_concurrency_verified_test.dart","$reviewArtifacts/adversarial_framed_test.dart") -TestName 'independent competing HTTP|independent HTTP|independent opposite|independent four actor|independent raw declared'
# Broad shared-helper/Application/authorization/P4.11 regression.
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test') -Analyze
```

Contracts run from `packages/api_contracts` using pinned Dart
`--packages=.dart_tool/package_config.json <test package root from package_config>/bin/test.dart test --reporter expanded`,
followed by `analyze --fatal-infos`. No package resolution/upgrade occurs.
Both affected-package analyzers and the non-writing formatter run separately.

| Invocation | Outcome and evidence |
| --- | --- |
| Unchanged original required probes before patch | **1 PASS / 3 FAIL / 0 SKIP**, exit 1; `.local/p416-stage-b1/2d554553bb2c4a9c8b03b810f8e7d443/tests.log` |
| Original scalar/marker diagnostic matrices before patch | **2 PASS / 0 FAIL / 0 SKIP**, exit 0; `.local/p416-stage-b1/fefa5831814e406a9654720f3193f2d4/tests.log` |
| Original required probes after patch plus new focused regression | **18 PASS / 0 FAIL / 0 SKIP**, exit 0; 4 unchanged originals + 14 new; `.local/p416-stage-b1/22b43eb34c3a47479cad199d40ace6b3/tests.log` |
| Final six-file B2a HTTP regression | **61 PASS / 0 FAIL / 0 SKIP**, exit 0, 3m00s; all original 47 + final 14; `.local/p416-stage-b1/e95df52f5cc143a4a0a27724df56c10b/tests.log` |
| Original verified races/journey/complete-framing controls | **13 PASS / 0 FAIL / 0 SKIP**, exit 0; 11 races, full four-actor journey, complete-upload/method/split-stream test; `.local/p416-stage-b1/8da2bf58b9494afdbd980d59068ffb3b/tests.log` |
| Full server shared-helper/B1/P4.11 regression | **995 PASS / 0 FAIL / 21 explicit opt-in SKIP**, exit 0, 21m36s; `.local/p416-stage-b1/7513a71ece3747c9888747cf117b8f1d/tests.log` |
| Full contract regression | **377 PASS / 0 FAIL / 0 SKIP**, exit 0 for tests; original 362 + 15 new Unicode cases; `.local/p416-b2a-remediation/contracts.log` |
| Server and contract analyzers | PASS, no issues. Initial new contract test had one interpolation lint after all 377 tests passed; fixed without changing its assertion and final analyzer passes |
| Format | PASS, 312 server/contract lib/test/tool files, zero changes |

The 18-case run preceded the final additional same-Account self/manager-family
assertions; those final test-only assertions pass in the 61-case run. Production
bytes were unchanged between these runs. Counts overlap and are not additive unique
coverage. The original diagnostics intentionally asserting 500/invalid_request are
preserved as before-only characterizations; the corrected required assertions and
equivalent input matrices now assert the approved outcomes. Historical erroneous
draft race/collector fixtures are not substituted for the verified 11 race cases.
Their original logs remain intact; no repository assertions were weakened.

The final 61-case selection retains exact original request replay HTTP 201 and all
other stored status/results; REQUESTED/OFFERED/CONFIRMED and terminal withdrawal
resolution; durable history; large colleague/counterpart/list pages; current auth,
privacy and role/link replacement; real future-expiry versus integrity 500 and
deferred final-clock rollback. P4.11 gains only malformed-scalar input rejection;
valid command/receipt/lifecycle/claim behavior is unchanged. The final full invocation
passes every B1 Application/authorization/identity/guidance/clock/pagination suite,
P4.11 contract/domain/HTTP/guidance/migration/receipt tests, Stage A shared claims and
concurrency/atomicity tests, the full F01 database-time-versus-corruption matrix,
existing auth/privacy/HTTP smoke and ordinary work/guidance/recovery regressions.
The same **21 explicit opt-in skips** listed in the original handoff remain; exact
case names/reasons are retained in `.local/p416-b2a-remediation/full-server-skips.json`.
No skipped Flutter/Chrome/encrypted recovery acceptance is presented as a pass.

### Incomplete-body framing: explicitly retained and evaluated qualification

The review's qualified framing assertions were rerun **unchanged** after remediation:

```powershell
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @("$reviewArtifacts/adversarial_final_test.dart","$reviewArtifacts/adversarial_complete_test.dart") -TestName 'independent raw declared limit'
```

They retain **0 PASS / 2 FAIL / 0 SKIP**, exit 1, matching the reviewed qualification:
`.local/p416-stage-b1/27dfcc5ce0144254b87b9120269758fb/tests.log`.
The held-open empty upload declaring 8193 bytes produces zero response bytes during
the collector's 10-second observation; premature incomplete-body EOF yields no
usable headers and the unchanged collector raises RangeError. The original promised
early-413 assertion does not pass. These are not concealed as acceptance passes.

A separate bounded observation probe records those outcomes directly while checking
readiness and the complete business hash. It reports **2 observations PASS / 0 FAIL /
0 SKIP**, exit 0, with both modes returning zero response bytes, `/ready` remaining
200/ok on a separate connection and unchanged business evidence. Source is retained
only under ignored `.local/p416-b2a-remediation/framing_observation_test.dart`; log is
`.local/p416-stage-b1/50c71797c209422bae2c29d54d7dc66a/tests.log`. Its passing observation
is not incomplete-framing acceptance and does not weaken the original failing tests.

The native Dart unsubscribed-input drain still governs response timing; no general
HTTP stream/parser, early-rejection deadline or new timeout contract is implemented.
Complete framed oversized uploads still give sanitized 413; byte-split valid Unicode,
unsupported-method isolation and read-only HEAD pass the original complete-framing
probe. No new material safety defect or service-wide exhaustion was demonstrated.
This known response-timing gap remains separately qualified and outside F01–F03.

### Current changed-file/hash inventory and stopping boundary

Relative to the reviewed snapshot, remediation changes exactly six paths:

```text
apps/server/lib/src/application/shift_swap_application.dart
apps/server/lib/src/identity/employee_links.dart
packages/api_contracts/lib/src/shift_transfers.dart
apps/server/test/shift_swap_http_remediation_test.dart
packages/api_contracts/test/shift_reason_unicode_test.dart
docs/development/phase-4-16-stage-b2a.md
```

The complete uncommitted B2a tree is the original 13-path inventory plus the four
additional Identity/shared-validator/new-test paths: **17 paths**, seven tracked
modifications and ten untracked files. Eleven of the original 13 reviewed paths
remain byte-identical; Application and this handoff are the two changed reviewed
paths. The current raw SHA-256 inventory, including all 17 paths and 29 unchanged
migrations, is retained in `.local/p416-b2a-remediation/final-snapshot.json` after
final verification. This document's own hash is recorded there to avoid recursive
self-hashing. Evidence files, generated disposable credentials and caches are ignored,
not additional implementation paths. Final exact scope, all 29 migration hashes,
stable runtime/test hashes, empty index and disposable credential/container cleanup
are verified. No runtime/test file changed during the final full invocation; only
this handoff was completed afterward. All disposable test secret files are blank.

The full current path/hash table follows. This handoff's self-hash, plus all 29
unchanged migration hashes, is included in the final external manifest.

| Current path | Raw SHA-256 |
| --- | --- |
| apps/server/lib/src/application/shift_swap_application.dart | 333D450C80AA909612CAAA31838E56975CA5BFB584B1B099D7A0615BDB5C69B6 |
| apps/server/lib/src/http/platform_app.dart | A89357187712469D097AFA90B45B2FAFB9B5AAA7500C34413A00210CE150EC2C |
| apps/server/lib/src/identity/employee_links.dart | 8D795CE662D6E9D7DA7A917D00EE1CC99AA96842BC61B3579D5B2AB72A0DA1BE |
| apps/server/test/merchandising_fixture.dart | 4AEE81933ECA705E458EA036258D07A573937345B7911B23E373F35B3CD2CD9D |
| docs/HANDOVER.md | 23C1C4FD3D82FBA1DC7D661D2D1EE8A93E5791159710B5402E7A26D84114ED1B |
| docs/roadmap/status.md | E0908CC01D8E9AC4803CC637853505F1149EE9E8029A6E59B9D8214C97411AD6 |
| packages/api_contracts/lib/src/shift_transfers.dart | 7F978272D22FE899F0648BBEC3D87B67B10F2AEB789E277EB6002591D3A57E62 |
| apps/server/lib/src/http/shift_swap_routes.dart | 47612E96551604A6583CF298CA8B7F541FB4EF5FE41B881CB42525279E6B9529 |
| apps/server/test/shift_swap_http_error_test.dart | A249DB171B1F885034CA868C06707945B2C5A77F524F8211619D215CEC951C0E |
| apps/server/test/shift_swap_http_fixture.dart | 65483CC1B623A5EA04A368C2B52307A25C6B8486513CE49ACF1889BE03570342 |
| apps/server/test/shift_swap_http_pagination_test.dart | B01EA2B9B09063BE78B3983664B16B46DFB6A8B90228A2A080697572C3613444 |
| apps/server/test/shift_swap_http_parser_test.dart | BA35E21870853E81D7F040C0ED291B57CA75494EA3BDC13B08056C3DE1CBEC69 |
| apps/server/test/shift_swap_http_privacy_test.dart | D3A0829B895FDEF88368B7EAEE18D01D3B5367C377A314761418942E3D25E05C |
| apps/server/test/shift_swap_http_remediation_test.dart | C500544E16D6567DCE1C77F63D8CE2F405B8F18644A7D0ADA506A6254AFAD0D0 |
| apps/server/test/shift_swap_http_test.dart | 92222935431CDA1EE73D5698D8F8A2187D94FB8F6A4560A5F7D45E815B028CC0 |
| docs/development/phase-4-16-stage-b2a.md | Recorded in final-snapshot.json (self-hash) |
| packages/api_contracts/test/shift_reason_unicode_test.dart | 3AAAE182E1F9C0F252F84259C845CA6DEF7383E169755581FD405FE1B153B857 |

The historical verdict remains **STAGE B2a CHANGES REQUIRED** until an independent
targeted F01–F03 re-review assesses the changed bytes. Author testing does not declare
independent approval or Security acceptance. The unchanged OpenAPI Step 7, Flutter/
browser Steps 8–9 and swap-inclusive expanded recovery Step 10 remain separate,
unexecuted implementation/acceptance gates; existing opt-in qualifications remain.
No recovery wrapper, Web build, native-device or full A01–A16 acceptance is claimed.
P4.16 remains **IN PROGRESS**, with local uncommitted code/documentation and an empty
index. Stop after final local verification; no commit/push/PR/merge/rebase/deployment
or B2b work. The next action is **independent targeted F01–F03 re-review**.

## Native ingress remediation — 2026-10-16

### Authority, retained reviews and baseline

The owner separately authorized bounded native HTTP resource protection, safe
in-process lifecycle tests, completed-request regressions and ADR 0031. That
authorization supersedes the older transport-out-of-scope statement only for
this slice. B2b, Flutter implementation, migrations, business-rule changes and
Git publication remain excluded.

The original independent **STAGE B2a CHANGES REQUIRED** report remains historical.
The subsequent independent targeted re-review returned **F01/F02/F03 CLOSED** and
overall **STAGE B2a INSUFFICIENT EVIDENCE**: acceptable finite retention of
indefinitely unfinished HTTP uploads was not established. No material resource
exhaustion vulnerability was demonstrated. The later read-only architecture
assessment returned **DESIGN READY FOR SEPARATE IMPLEMENTATION AUTHORIZATION**.
That is design readiness, not B2a approval.

The full final architecture assessment was read from chat **Assess upload resource
bounds**, `01a143a9-1f81-7be3-ad3e-67fd79ca63d2`, and the full final targeted
re-review from **Review B2a swap HTTP security**,
`01a13a36-3401-7580-8ced-eb19956c618b`. Their final reports are retained verbatim
under ignored `.local/p416-native-ingress/approved-architecture-report.md` and
`targeted-re-review.md`. The original report remains at
`C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/289dc07bc5b8e85b3a3430f45244e13adc9e3a11_20261014T114034Z_aj3e8w4n/artifacts/Stage-B2a-independent-review.md`.

Before edits, all **46 SHA-256 values matched, zero differences**: the 17 B2a paths
plus 29 migrations, against the independent targeted review's
`289dc07bc5b8e85b3a3430f45244e13adc9e3a11_20261014T134902Z_azc4ege0/artifacts/reviewed-snapshot.json`.
A copy is `.local/p416-native-ingress/baseline.json`. Branch,
HEAD/cached origin/main, seven tracked modifications, ten untracked paths and
empty index exactly matched the owner's baseline. No remote ref was changed.

### Gate A — supported pinned APIs

Inspected local Dart **3.13.4** sources under
`C:/dev/flutter/bin/cache/dart-sdk/lib/` and locked Shelf **1.4.2**
`lib/shelf_io.dart`. No dependency resolution, upgrade, reflection, private API
call or SDK modification was needed.

| Gate | Source evidence / feasibility result |
| --- | --- |
| Native body -> Shelf | Shelf `_fromHttpRequest` supplies `body: request`; public `handleRequest` accepts a delegating `HttpRequest` with the owned stream. |
| Deadline before dispatch | The native `HttpServer.listen` callback arms the lifecycle before calling Shelf or authentication. |
| Genuine completion | One `HttpRequest.listen`; error-free `onDone` alone completes. SDK `http_parser.dart` reports truncated framed bodies as input errors before closing. Reader cancellation never cancels the native subscriber until abort. |
| Actual termination | SDK `http_impl.dart:1313` deadline timer calls connection `destroy`; `:3414` destroys its socket without waiting for a drain. Public `Socket.destroy` specifies both directions. |
| Unread input / response | SDK `writeHeaders` at `:1822` can await native drain; the guard subscribes first and owns a bounded discard phase before Shelf writes. |
| Closure / permits | Public Socket adapter intercepts native `destroy`. Send-side `done` first causes our own physical `destroy`; it is not itself a permit release. |
| Pre-header admission | Public ServerSocket adapter synchronously admits/rejects accepted Socket events before passing them to HttpServer. Header timer also bounds connections with no complete headers. |
| Listener shutdown | Public `HttpServer.listenOn` explicitly does not close its supplied listener; guard owns and closes it. |
| Supported implementation | Concrete public `ServerSocket`, `Socket` and `HttpRequest` interfaces compile/analyze with every public member delegated. Production uses no `noSuchMethod` or runtime hooks. |
| Single stream / pressure | One native subscription, initially paused; Shelf pause/resume propagates to native input. SDK parser also pauses its socket subscription while parsing a received buffer. |

An ignored feasibility program `.local/p416-native-ingress/gate_a.dart` compiled
cleanly and ran one **completed** loopback exchange, verifying body delivery and
native destroy interception. The first sandbox attempt could not connect; the
permitted local execution passed. It was not an unfinished-upload probe and does
not establish expiry wire timing.

### Actual implementation and resource proof

[ADR 0031](../adr/0031-bounded-native-http-ingress.md) records the policy, all six
environment variables, validation and deployment distinctions. Defaults are
**64 connections / 32 dispatched requests / 16 incomplete bodies / 30-second body
lifetime / 1-second discard / 15-second idle**, with no application wait queue.
Header reception is separately limited to the body-lifetime value, including the
first connection and the gap after each response. Ordinary idle expiry remains
the native periodic keep-alive control, not an active-body deadline.

`guarded_http_server.dart` owns acceptance, socket registry, native request
dispatch, response completion and shutdown. `upload_lifecycle.dart` owns the sole
native body subscription, two finite guard timers, output backpressure and
idempotent body release. Production `server.dart` uses this guard exclusively.
`merchandising_fixture.dart` uses the same ingress for existing HTTP/PostgreSQL
tests. Swap route broadcast draining is removed. Shared/default and login readers
now check remaining allowance before appending; their limits and error codes stay
unchanged. No Application/Domain, Identity or shared-contract byte changes were
made in this transport slice.

For each admitted body, reading can only reach complete EOF or aborted state;
discard is a bounded reading mode. Chunks do not reschedule either deadline.
Successful native EOF cancels protection and releases the body permit once.
Parser rejection, reader cancellation and response construction do not clear it.
Discard stops delivery to the cancelled reader and drops native chunks with no
body accumulation, while both its one-second timer and original absolute timer
remain eligible to terminate.

Abort settles once, advances the native response deadline to zero, then calls the
production socket adapter's physical `Socket.destroy()` **before** asynchronous
input cancellation. The native deadline is never set to null on abort. A redundant
absolute guard protects against native response-completion deadline cancellation.
Input errors/abort emit `UploadAborted`, never successful EOF, so partial JSON
cannot complete a reader and reach a command. ServerApp propagates that sentinel
to the native adapter without logging body, headers or query data. No automatic
mutation retry is introduced.

Connection release follows physical destroy, request release follows the actual
handler/response future, and body release follows EOF/abort. Each release is
idempotent. Closed sockets cannot admit unlimited still-running handlers. After
valid EOF, ordinary business work has no upload deadline and is allowed to finish
after disconnect. Shutdown destroys transports/active uploads, stops listener
and HTTP subscription, awaits dispatched work, then the composition root stops
EventBus and pool. Startup rollback closes an acquired listener if HTTP setup fails.

Pipelining ownership is identity checked: cleanup for an older response cannot
clear the next request's lifecycle or arm a header timer over its business work.
Queued stale header callbacks also check timer identity. Both races have
deterministic regressions.

Public connection metadata omits the destination address. An accepted socket
whose remote-address/remote-port/local-port key is already admitted is destroyed
before HTTP dispatch, and its temporary permit returned. It cannot replace the
live registry owner. This preserves safe lookup on wildcard bindings; duplicate
metadata is rejected rather than guessed. A finite regression proves one owner
survives and both permit paths release correctly.

These mechanisms bound active transport retention assuming a responsive event
loop and the inspected SDK's public destroy contract. They do not certify target
hardware capacity or real OS descriptor reclamation. Count limits alone do not
guarantee availability; expired peers may see connection termination instead of
a complete error response. No pre-EOF 413 is promised.

### Verification and remaining qualifications

The final runtime passed **33 PASS / 0 FAIL / 0 SKIP** in the dedicated safe
lifecycle/configuration/completed-ingress bundle:
`.local/p416-native-ingress/safe-tests-final.log`. This is 22 finite lifecycle/
admission cases, six completed native HTTP/shutdown cases and five configuration
cases. At each of 8192/16384/65536/262144 bytes the native tests accept an exact
completed body, reject completed declared and chunked overflow with 413, then
accept another valid request. Malformed JSON, duplicate names and media errors
retain 400/415. No unfinished input goes over a network in this bundle.

The dedicated B2a suite passed **61 PASS / 0 FAIL / 0 SKIP**, log
`.local/p416-stage-b1/b8a2b6999ae14226b1017ff15f98e9e9/tests.log`. That run preceded
the final pipelining ownership fix; the final 71-case targeted bundle repeats its
unchanged 61 assertions on the final runtime. API-contract analyzer and tests:
**377 PASS / 0 FAIL / 0 SKIP**, `.local/p416-native-ingress/contracts.log`; contract
source remains identical to the independently closed F01–F03 snapshot.

Six preserved independent-review **completed-request** controls were rerun by the
author on the final ingress: **6 PASS / 0 FAIL / 0 SKIP**, log
`.local/p416-stage-b1/db9ef931f0a94ef1988a5124fc87c5ce/tests.log`. Selection combines
`adversarial_input_test.dart` and only the completed framing/four-actor tests in
`adversarial_framed_test.dart`. It verifies malformed UTF-8/path inputs, Unicode
reasons, typed cursors/reader replacement, a complete 8193-byte declared upload,
unsupported methods, byte-split valid Unicode, HEAD and two legs of three guided
Tasks followed by four exact historical replays. The old diagnostic scalar/code
expectations and both unfinished-upload files are excluded. A legacy probe's
printed label `DECLARED no-body` is misleading: its selected source supplies the
complete declared body; it is not either prohibited held-open probe.

Additional ignored compatibility probes pass **2 PASS / 0 FAIL / 0 SKIP**, log
`.local/p416-stage-b1/f05ec566e8934e36af19d54e9708eeec/tests.log`, source
`.local/p416-native-ingress/completed_http_compatibility_test.dart`. Actual guarded
ServerApp/HTTP/PostgreSQL checks cover health/readiness, allowed/forbidden origins,
OPTIONS 204/405, security headers, login/logout and rejection of the revoked
session; login retains exact 16384-byte parser acceptance and 16385-byte declared/
chunked 413. Valid escaped Knowledge and Recipe requests above 16384 wire bytes
persist their full content, and a valid order-save JSON body above 65536 bytes
persists its line. Domain limits remain distinct from the larger transport caps.

The P4.11 HTTP integration/safety suite was rerun through guarded ingress in an
ignored copy: **64 PASS / 0 FAIL / 0 SKIP**, log
`.local/p416-stage-b1/54c7f2cdbf7e441b973ffb81549ef156/tests.log`. Copy provenance
is `.local/p416-native-ingress/p411-copy-provenance.json`: eight part files are
byte-identical, and the main file has exactly three fixture substitutions (import,
server type and bind call). Completed lifecycle, exact restart replay, strict
parsing, clock crossing, observed authorization/consent races, injected rollback
and runtime grants all pass. This run preceded the duplicate-key admission fix;
the final targeted bundle repeats P4.11 approval/replay and strict body controls.

The broad full-server run uses
`.local/p416-native-ingress/full-run-start-snapshot.json`. After this run started,
three paths changed: `guarded_http_server.dart`, `upload_lifecycle_test.dart` and
`merchandising_fixture.dart`. These reject an ambiguous accepted connection key
before registry insertion, add its regression and preserve legacy seeding below.
This is **not** claimed as an exact-final-byte full run. The final 33-case safe
bundle and the completed-request bundle use the final runtime/test snapshot.
Broad server run `7a42a76871d24c3bbab0b59ca6e5f206` finished in 39m49s with
**1023 PASS / 2 FAIL / 21 SKIP**, exit 1. The failed cases are the populated-0027
seed import and the new ambiguous-key assertion exercising the earlier loaded
ingress (two owners observed). Both cases pass in fresh final-code runners.
The 21 explicit opt-ins remain unverified; exact cases/reasons are in
`.local/p416-native-ingress/full-server-skips.json`. No clean exact-final-byte
full-suite invocation is claimed. This mixed-snapshot run is retained as broad
regression evidence, including its two failures, rather than relabeled as a pass.

The broad run exposed one real fixture compatibility regression: populated-0027
migration seeding remaps `package:storeos_server` to immutable released P4.11
sources, which do not contain the new ingress import. The shared fixture now
imports the **same current production ingress source** by relative file path,
outside that business-package remapping. The released business libraries and
their package mapping are unchanged. A narrowly documented
`avoid_relative_lib_imports` exception is required for this fixture bridge; no
assertion, migration or business code is weakened. The failed seed compilation
and its parent migration-test failure remain in the broad log. A fresh final
bundle includes that exact populated migration regression as well as all 71
completed-request controls; its result is recorded below.

Fresh final-code bundle: **72 PASS / 0 FAIL / 0 SKIP**, exit 0, log
`.local/p416-stage-b1/b5bc4f5366fb44a6b1d46f2288887203/tests.log`. It repeats all
71 controls and the previously failed populated migration test. A fresh final
safe bundle again passes **33 / 0 / 0**, including the previously failed
ambiguity assertion. Server analyzer is clean after the fixture bridge and its
documented import exception. Runtime source/test hashes are retained in the
final targeted snapshot. The broad full suite was not repeated again after these
bounded fixes; that exact-final full-suite result remains unverified.

Final redaction/cleanup checks cover **38,209 JSON log events**, with zero
credential/body/query fields, bearer-token/DB-URL patterns or the deliberately
supplied query marker in those log events. This is a bounded pattern/field check,
not a general secret scanner verdict. All **14** task-created disposable
PostgreSQL container names are absent and all **28** generated credential files
are blank by length. Evidence is `redaction-cleanup-check.json` and
`container-cleanup-check.json` under `.local/p416-native-ingress/`.

Completed-request bundle before the legacy fixture import correction:
**71 PASS / 0 FAIL / 0 SKIP**, log
`.local/p416-stage-b1/3900c8df1c2243198a6c14f1aa794399/tests.log`, exit 0. It
contains all **61 B2a** tests, the **six** preserved review controls, the **two**
actual ServerApp/large-body compatibility probes, and **two P4.11** guarded
approval/restart replay and strict parser/body controls. These use the final
duplicate-key rejection code. The final 72-case invocation repeats these after
the fixture correction. Counts overlap earlier dedicated/broad runs and
are not added to imply unique coverage. The broad run overlaps the final
fix; its result does not establish blanket exact-final-byte coverage.

Final server and contract analyzers are clean with pinned Dart 3.13.4. The
non-writing formatter checks **325 files / zero changes**; whitespace check exits
0 (only the existing Git CRLF-normalization notice). Logs are
`.local/p416-native-ingress/server-analyzer-final.log`, `format-final.log` and
`whitespace-final.log`. PostgreSQL uses the existing local 17-alpine image digest
`sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24`.

Unsuccessful/interrupted attempts remain distinct from final acceptance:

- The sandbox test compiler could not copy its temporary kernel: **0 PASS /
  2 load FAIL**. Execution with required temporary-file access succeeded.
- `.local/p416-native-ingress/lifecycle-first.log`: **20 PASS / 1 FAIL**, exposing
  the queued old-header timer issue; fixed with identity checking and regression.
- `.local/p416-native-ingress/safe-tests.log`: **27 PASS / 4 FAIL** in new test
  record/map comparisons despite correct 413 DTOs. Assertions were corrected to
  compare status and map contents separately; no existing assertion was weakened.
- Initial PostgreSQL launch failed because Docker was stopped. The installed
  local engine was started; no tests ran in that failed launch.
- The first full-suite attempt, run `a3f6105f51aa44019734562c2172963f`, was
  deliberately stopped after **244 observed PASS / 11 observed SKIP** to apply
  the pipelining fix. Its exit 1 is **INTERRUPTED**, not a full-suite result. Its
  harness removed the container and blanked credentials before the final restart.
- Three temporary compatibility-probe compilation attempts each had **0 PASS /
  1 load FAIL** (empty-map type inference and UUID-helper imports), retained in
  runs `b1c283cae0844612b3521b50c1873461`, `7f7d680144094c3a9adcf10232890af9`
  and `901bb7f3607c4ba2ae7f5181619ffe5c`. The final two-case source passed.

All tests use finite in-process streams/fake timers or **completed** loopback
requests. No new active incomplete-upload network probe, DoS/load simulation,
Daybreak retry or restriction workaround ran. The two old unchanged unfinished
assertions remain **0 PASS / 2 FAIL**, at the historical log cited above; neither
was rerun or relabeled. The earlier security-testing interruption remains respected.

Deterministic expiry tests invoke production `IngressSocket.destroy` with a fake
physical transport; this is direct component-boundary evidence, not observation
of OS socket reclamation. The still-unresolved wire evidence is real transport
closure/resource release at expiry under a separately permitted verification
plan, if required by the independent reviewer. Closing Dart's backend connection
does not establish Caddy's original client TCP/HTTP2 stream closure or buffering
bounds. Optional proxy frontend qualification remains separate.

Tests execute on Windows. Linux execution and actual Ctrl+C/SIGTERM process
delivery are not claimed; signal registration is preserved by source inspection.
The native completed-request shutdown test proves port release/rebind and waits
for already-valid business work; finite component tests cover active-upload abort
and startup rollback. Broader Flutter/Chrome/encrypted recovery opt-ins remain
separate; no new Web build, native device run or expanded P4.16 Step 10 acceptance
is claimed.

### Current inventory and stopping boundary

This transport slice changes exactly 15 paths relative to the independently
retained 17-path baseline: `server.dart`, `config.dart`, `api_support.dart`,
`server_app.dart`, `shift_swap_routes.dart`, `merchandising_fixture.dart`,
`config_test.dart`, the two new ingress implementation files, the two new safe
permanent test files, ADR 0031 and the three handover/status documents.

The complete uncommitted B2a tree is **27 paths: 12 tracked modifications and
15 untracked files**, index empty. Twelve of the original 17 reviewed paths remain
byte-identical, including all F01–F03 business/identity/shared-contract fixes and
their regression assertions. All 29 migration hashes remain unchanged. No
lockfile, generated API, Flutter implementation, CI or recovery-wrapper source
is modified.

| Path | Raw SHA-256 |
| --- | --- |
| apps/server/bin/server.dart | EC2C24B790F7A4AD2DAF24A4DB2958E1E4AF669A78F5C32CE01BCE6BA2A28B0A |
| apps/server/lib/src/application/shift_swap_application.dart | 333D450C80AA909612CAAA31838E56975CA5BFB584B1B099D7A0615BDB5C69B6 |
| apps/server/lib/src/config.dart | BD331AAB734AFAB63076EAB7402D23A991AFD5F28F963C803B790D09EB0816F4 |
| apps/server/lib/src/http/api_support.dart | 9AC4DC787E42320B29D40D988F8B60C7FF472D4C2FAD3C4FF1B618A5BD82726F |
| apps/server/lib/src/http/guarded_http_server.dart | 9FD9D7512B7A6B138A4819F802B9BC693C0DD83D5584F2D42F0EE90B64737F28 |
| apps/server/lib/src/http/platform_app.dart | A89357187712469D097AFA90B45B2FAFB9B5AAA7500C34413A00210CE150EC2C |
| apps/server/lib/src/http/server_app.dart | BD0789C977C408F65B33AC165233FAA819DCF2ACDC4784F0053BEDA940F1CC4C |
| apps/server/lib/src/http/shift_swap_routes.dart | 838D96B02449244845469400B0904CD170A0104E35677537628F8FACE17FA857 |
| apps/server/lib/src/http/upload_lifecycle.dart | 3D570A478D57135259F0731A8C73F34E89C5A3AB6B6FCDACFFCC94534EB95D69 |
| apps/server/lib/src/identity/employee_links.dart | 8D795CE662D6E9D7DA7A917D00EE1CC99AA96842BC61B3579D5B2AB72A0DA1BE |
| apps/server/test/config_test.dart | EFCCB8E84C3A926DA3D971DBBD2241C21C273193EC67DE12CF563CEA7143B9CE |
| apps/server/test/guarded_http_server_test.dart | 228A2E60B9F9163D1F7DFE49CA17D2EC59465C28A21FEAF5F1D210DB7731D75C |
| apps/server/test/merchandising_fixture.dart | 3C9B2A54C9B795B0CF5EA96096CE16CCDBC8E090181E56B0FF3680F29CB538ED |
| apps/server/test/shift_swap_http_error_test.dart | A249DB171B1F885034CA868C06707945B2C5A77F524F8211619D215CEC951C0E |
| apps/server/test/shift_swap_http_fixture.dart | 65483CC1B623A5EA04A368C2B52307A25C6B8486513CE49ACF1889BE03570342 |
| apps/server/test/shift_swap_http_pagination_test.dart | B01EA2B9B09063BE78B3983664B16B46DFB6A8B90228A2A080697572C3613444 |
| apps/server/test/shift_swap_http_parser_test.dart | BA35E21870853E81D7F040C0ED291B57CA75494EA3BDC13B08056C3DE1CBEC69 |
| apps/server/test/shift_swap_http_privacy_test.dart | D3A0829B895FDEF88368B7EAEE18D01D3B5367C377A314761418942E3D25E05C |
| apps/server/test/shift_swap_http_remediation_test.dart | C500544E16D6567DCE1C77F63D8CE2F405B8F18644A7D0ADA506A6254AFAD0D0 |
| apps/server/test/shift_swap_http_test.dart | 92222935431CDA1EE73D5698D8F8A2187D94FB8F6A4560A5F7D45E815B028CC0 |
| apps/server/test/upload_lifecycle_test.dart | 36F83B18E22D8B480D304CFF84E9D6FDA578283487731B49F1040012DEA182A2 |
| docs/adr/0031-bounded-native-http-ingress.md | 48F51E56BBFF1D732BEB50EE70B40F63F5D569F644545E06242CD0DEFAE2B938 |
| docs/development/phase-4-16-stage-b2a.md | External final manifest (self-hash) |
| docs/HANDOVER.md | 07B9F70E59C7FBEA3D8C9336F7DE718B412ABC1DE25DF6C7F1071F9EAF877DEF |
| docs/roadmap/status.md | A651005E5DBD1C8BF5704FA13F5AAC0535C1419A255227D4FD4492E66F22F545 |
| packages/api_contracts/lib/src/shift_transfers.dart | 7F978272D22FE899F0648BBEC3D87B67B10F2AEB789E277EB6002591D3A57E62 |
| packages/api_contracts/test/shift_reason_unicode_test.dart | 3AAAE182E1F9C0F252F84259C845CA6DEF7383E169755581FD405FE1B153B857 |

The authoritative final manifest is ignored
`.local/p416-native-ingress/final-snapshot.json`: all 27 source/documentation
hashes (including this self-hash), 29 migration hashes and final Git/cleanup facts.
`.local/p416-native-ingress/runtime-test-snapshot.json` identifies the exact
11 affected runtime/test files used by final targeted tests. The
full-suite start snapshot is retained separately; its three-path difference from
the final target is explicitly qualified in verification. Ignored evidence,
probe copies and disposable credentials are excluded from the implementation
inventory.

The independent overall verdict is still **STAGE B2a INSUFFICIENT EVIDENCE**.
The bounded implementation/evidence is ready for **independent targeted transport
review**, not author approval. The reviewer must assess the lifecycle proof and
remaining permitted wire/proxy evidence requirement. P4.16 stays **IN PROGRESS**.
No commit, stage, push, PR, merge, rebase, deployment, release or B2b implementation
was performed or is authorized by this handoff. Stop after local evidence collection.


## INGRESS-01 / INGRESS-02 local remediation — 2026-10-16

**Both findings are fixed locally; independent targeted re-review is required.**
The latest independent verdict remains **STAGE B2a CHANGES REQUIRED**. Original
HTTP findings **F01–F03 remain independently CLOSED**. This is an author
remediation record, not an independent approval. P4.16 remains **IN PROGRESS**.
No Stage B2b/OpenAPI, Flutter feature or recovery implementation was started.

### Reviewed baseline and exact counterexamples

The complete independent [native ingress review](C:/dev/storeos/.local/native-ingress-independent-17bb6ee50c4a4042b56f8424c624b3f5/Review.md)
was read before editing, alongside ADR 0031, this handoff, production ingress,
ServerApp, AuthService, configuration/ingress fixtures and the retained original
[F01–F03 re-review](C:/dev/storeos/.local/p416-native-ingress/targeted-re-review.md).
Branch `codex/p416-stage-b2a-swap-http`, HEAD and cached `origin/main`
`289dc07bc5b8e85b3a3430f45244e13adc9e3a11`, empty index and the complete
27-path inventory (12 tracked modifications / 15 untracked) matched exactly.
All **56 independently recorded raw SHA-256 hashes matched**: 27 reviewed paths
plus migrations 0001–0029. No unexplained drift existed. The four pinned SDK/Shelf
source hashes also match. The retained baseline and reconciliation are in
`C:/dev/storeos/.local/p416-ingress-01-02-remediation/`.

- **INGRESS-01 MEDIUM / P2:**
  `independent_ingress_test.dart`, case `independent aborted partial logout must
  preserve session state`, and `independent_logout_postgres_test.dart`, case
  `independent restricted PostgreSQL session survives aborted in-process partial
  logout`, both under the independent review directory linked above. The real
  native parser, guard, ServerApp and AuthService receive authenticated POST
  logout headers with Content-Length 2 and only `{`. The original route revoked
  the session before reading any body. Response construction then started
  one-second discard; abort destroyed the fake physical transport with zero
  response bytes. The restricted PostgreSQL counterexample observed that the
  persisted session was already revoked. This is the confirmed session-state
  invariant violation, not a demonstrated cross-account authorization bypass.
- **INGRESS-02 LOW / P3:** the same `independent_ingress_test.dart`, case
  `independent bodyless GET retains keepalive compatibility`. A fully completed
  HTTP/1.1 GET has neither Content-Length nor Transfer-Encoding. Native framing
  treats it as empty, but public `contentLength` is -1. The old guard resumed
  only exact zero, leaving the body subscriber paused until unnecessary discard
  disabled reuse. The counterexample observed one destroyed transport, zero
  active connections and `connection: close`; repeated completed POSTs reused
  the same transport correctly.

Those review artifacts remain unmodified. Their historical results remain
8 independent in-process probe passes / 2 failures, and 0 passes / 1 failure for
the restricted PostgreSQL logout counterexample. The new regression tests below
exercise the corrected semantics. In particular, a valid logout now reads until
EOF under the original 30-second deadline, rather than immediately returning and
starting the former one-second discard. The old logout reproducer's one-second
destruction expectation is not relabeled as a passing new contract.

### Corrections and compatibility

`completeRequestBody` in `api_support.dart` drains the existing Shelf-facing
single-subscription body without buffering or JSON validation, then calls the
owned `UploadLifecycle.requireComplete` supplied in request context by the guard.
Only actual successful native EOF satisfies that check. A shortened/cancelled
reader or discard cannot authorize mutation, even if the native input later
finishes. Normal cancellation of an already completed stream is distinguished
from cancellation before EOF. No second native subscriber, broadcast buffer,
new timer or unbounded unprotected wait was introduced.

Logout authenticates first, awaits this completion gate, then invokes unchanged
`AuthService.logout`, which revalidates the session and performs its existing
atomic revocation/audit. A valid partial body therefore cannot revoke a session.
Abort, malformed chunk framing, input error, deadline and shutdown do not count
as successful completion. Bodyless, explicit-zero, arbitrary finite non-JSON,
zero-chunked and finite-chunked completed logout requests retain 204 behavior.
Invalid/revoked completed sessions retain 401. No new media-type/JSON/empty-body
validation contract or automatic logout retry was added.

Inspection found two other body-ignoring state-changing adapters with the same
integration flaw: `POST /api/v1/platform/events/<eventId>/replay` and
`POST /api/plugin/v1/events/<eventId>/ack`. They use the same helper before their
existing service mutation. Replay retains session authentication before the gate;
plugin acknowledgement retains plugin authentication inside its unchanged
transaction after body completion. Completed-input status/authentication/resource
outcomes remain unchanged. No event/plugin service, authorization policy, receipt
or schema was changed. Restricted PostgreSQL regressions preserve a dead-letter
event and a pending plugin delivery across partial-input expiry, then verify the
separate completed finite-body command still succeeds. Test setup publishes via
authorized ports and uses the dispatcher's existing failure transition; it does
not implement a new business endpoint.

The guard now classifies unambiguously empty native framing using
`!headers.chunkedTransferEncoding && contentLength <= 0`. It resumes its sole
subscriber and waits for genuine native EOF before dispatching such a request.
Header classification never synthesizes completion or clears a deadline. This
handles absent framing and explicit zero while retaining positive-length and
chunked input as body-bearing, regardless of method. A completed zero-byte
chunked entity reaches EOF through normal consumption. A body-bearing GET that
returns without consuming its body still uses bounded discard and closes reuse;
it receives no method-based exemption. The existing one-second discard/original
absolute deadline behavior remains intact for rejected inputs.

Defaults and ownership remain 64 connections, 32 dispatched requests, 16
incomplete bodies, absolute 30-second header/upload lifetimes, one-second discard,
15-second idle timeout, no application admission queue, actual native destroy on
expiry, exactly-once permits, backpressure and owned shutdown. Body completion
remains separate from handler completion. Already valid post-EOF business work
can finish after disconnect; incomplete JSON cannot reach command mutation.
Pinned SDK socket-level errors may queue on the paused request-parser stream;
the independent upload deadline still aborts the body without revocation. A
native malformed-chunk body error is also covered directly. Neither error is EOF.

### Safe regression matrix

The new `native_ingress_fixture.dart` adapts the independent finite in-process
transport harness, retaining the real production `HttpServer` parser and guard.
It creates no network connection. `native_ingress_regression_test.dart` covers
five completed logout framing/content cases; declared and chunked started bodies
with zero mutation before EOF and exactly one afterward; disconnect, socket
error, malformed chunk, expiry and shutdown; both EOF/abort race orders; invalid
and revoked sessions; health/readiness/authenticated status and repeated unframed
GETs on one admitted transport; explicit zero; completed zero-chunked/finite GET
consumption; unfinished chunked GET protection; and admission cleanup followed by
a healthy bodyless request after rejected body-bearing GET.

Two new `upload_lifecycle_test.dart` cases use the production component to prove
that `take(1)` cancellation/synthetic reader EOF cannot pass the gate, including
after later native EOF, and that duplicate close/abort/discard/timer cleanup
cannot repeat mutation or body-permit release. Existing 33 ingress/configuration
checks are preserved, including admission caps, no partial JSON mutation,
backpressure, single ownership, expiry/destroy, discard, post-EOF business work,
startup failure, pipelined ownership and shutdown.

Five `native_ingress_postgres_test.dart` cases cover the two related command
adapters, session preservation before/after declared expiry and chunked disconnect,
successful finite logout only after EOF, and completed real HTTP connection
reuse. The session store runs under the restricted runtime PostgreSQL role.
Failed partial logout leaves its session discoverable and usable by a separate
completed authenticated HTTP status request; it adds no `auth.logout` audit.
Successful EOF produces exactly one revocation call and one persisted logout
audit, then the old session receives 401. Network operations in this test file
are ordinary fully completed requests only.

Actual reuse is asserted using four requests (`/health`, `/ready`, authenticated
`/api/v1/platform/organization`, `/health`) arriving with the same actual TCP
remote port and one active admitted connection. The normal `HttpClient` is
configured with `maxConnectionsPerHost = 1`, responses are fully drained and
persistent, and shutdown releases all three counters. In-process repeated GETs
also assert repeated 200 response lines on the exact same fake physical socket,
without destroy or `connection: close`. Two successful statuses alone are not
used as reuse evidence.

### Verification on the frozen source

All 304 server/API-contract Dart sources were formatted and analyzed before the
broad run, then frozen in `frozen-source.json`. All 304 raw hashes and the source
inventory match after completion, with zero migration differences. No implementation
or test source was edited during that invocation. Final documentation/status
evidence was applied afterward. The safe permanent suite has 82 test files;
no external unfinished-upload network probe was selected.

| Check | Actual final result | Retained evidence |
| --- | --- | --- |
| Existing 33 ingress/configuration checks plus 23 new finite cases | **56 PASS / 0 FAIL / 0 SKIP** | `focused-second.log` |
| Restricted PostgreSQL session/shared-gate/completed-wire regressions | **5 PASS / 0 FAIL / 0 SKIP** | `.local/p416-stage-b1/7c1c544646a84375a0ed526c445a947d/tests.log` |
| Eight existing completed controls plus all 64 guarded P4.11 cases | **72 PASS / 0 FAIL / 0 SKIP** | `.local/p416-stage-b1/95c21254bf4a4a40aeecc130c279fdec/tests.log` |
| Complete eligible server suite, one frozen-source invocation | **1053 PASS / 0 FAIL / 21 SKIP**, **20m48s** | `.local/p416-stage-b1/d46c2ab8542d4befba864e7ebf90bd60/tests.log` |
| API contracts | **377 PASS / 0 FAIL / 0 SKIP** | `contracts.log` |
| Server and contract analyzers | **No issues** | `server-analyzer.log`, `contracts-analyzer.log`; broad run also uses `-Analyze` |
| Non-writing formatter | **304 files / zero changes** | `format.log` |

These are separate overlapping invocations, not additive unique-test counts.
The full invocation includes the original 61 B2a HTTP cases, all 28 new cases,
authentication/login/logout/session, ordinary P4.11, body-limit/parser, F01–F03
and Stage B1 replay/atomicity/migration regressions. The extra guarded P4.11 copy
differs only in its three transport setup substitutions; all eight case part files
are byte-identical (`p411-copy-provenance.json`). The runner log reports all tests
passed. After the resumed chat the original tool process receipt was unavailable,
so the retained log and completed harness cleanup establish completion; no newly
fetched process exit code is claimed.

`final-verification.json` checks 304 frozen sources, 29 migrations, seven retained
independent review artifacts, four external control entry files and four pinned
SDK/Shelf sources: **zero differences**. All seven task-owned disposable containers
are absent and all fourteen generated credential files are blank by length.
Ten retained logs contain 23,949 JSON events with zero forbidden credential fields
or bearer/database-URL value patterns. Docker was unavailable at the first final
inventory check; starting the installed Desktop engine restored read-only access,
and the final cleanup inventory passed. No credentials were printed.

The independent review's unchanged-source **1025 PASS / 0 FAIL / 21 SKIP** broad
run (`777a3039e9ff4f61acfdbbd34ee5eabb`) remains historical evidence for the reviewed
baseline. Its 33 ingress/configuration, 377 contract and eight completed-control
passes also remain historical. The earlier author's **1023 PASS / 2 FAIL / 21
SKIP** mixed-snapshot run is retained above; the independent consistent run
subsequently passed its populated-0027 and duplicate-owner cases. No earlier
failure is erased by separate later passes.

During test development, the first focused run was 54 PASS / 1 FAIL because a new
socket-error test incorrectly expected immediate parser-error delivery rather
than the retained absolute-deadline cleanup. It now asserts zero mutation before
deadline and bounded cleanup, alongside a direct malformed-chunk error case.
The first three-case PostgreSQL run had two passes and a reuse assertion failure:
the default client pool could open a second socket before returning the first to
the pool. The one-connection client makes reuse an explicit test requirement.
The first two additional shared-adapter fixture attempts each had 3 PASS / 2 FAIL
because bootstrap emits multiple events; selecting the uniquely marked fixture
event corrected the setup. Assertions and production invariants were preserved.
All attempt logs remain retained in the ignored evidence directory.

The 21 explicit opt-in skips are retained individually below (17 browser/Flutter
journeys and four encrypted migration/recovery cases). No opt-in was enabled.

- `test/article_quantity_journey_test.dart: real Flutter controller quantity journey` — Opt-in isolated HTTP/Flutter journey.
- `test/article_quantity_journey_test.dart: actual Chrome quantity journeys` — Opt-in isolated Chrome journey.
- `test/article_quantity_upgrade_recovery_test.dart: populated 0026 preservation, post-grant deferred rollback and encrypted 0027 fenced restore with exact replay` — Explicit isolated encrypted migration/recovery opt-in required.
- `test/knowledge_browser_test.dart: actual Chrome Knowledge workflow and literal plain text` — Opt-in ChromeDriver and isolated PostgreSQL required.
- `test/preparation_assignment_browser_test.dart: actual Chrome manager creation, own retained Recipe start, completion, linked correction history` — Opt-in actual Chrome and isolated PostgreSQL required.
- `test/preparation_assignment_client_journey_test.dart: real Flutter controller assignment R1, competing starts, lost response/restart, actual 2 and corrections 1 then 0` — Opt-in Flutter and isolated PostgreSQL required.
- `test/preparation_assignment_upgrade_recovery_test.dart: real populated 0024 to 0025, late catalog/grant rollback and encrypted fenced pre-0025 recovery` — Dedicated isolated P4.13 encrypted migration/recovery opt-in required.
- `test/preparation_batch_browser_test.dart: actual Chrome retained Recipe batch, committed response loss, server restart, exact retry, correction and separate zero outcome` — Opt-in Chrome and isolated PostgreSQL required.
- `test/preparation_batch_client_journey_test.dart: real Flutter controllers HTTP PostgreSQL retained Recipe, exact restart replay, correction and zero` — Opt-in Flutter and isolated PostgreSQL required.
- `test/purchasing_client_journey_test.dart: P4.12 real Flutter controller HTTP restricted PostgreSQL journey` — Explicit isolated PostgreSQL and opt-in Flutter/Chrome required.
- `test/purchasing_client_journey_test.dart: P4.12 actual Chrome HTTP restricted PostgreSQL journey` — Explicit isolated PostgreSQL and opt-in Flutter/Chrome required.
- `test/purchasing_delivery_upgrade_recovery_test.dart: populated 0025 to 0026: deferred post-grant rollback, encrypted fenced pre-0026 recovery and unchanged source` — Explicit isolated encrypted-recovery opt-in required.
- `test/purchasing_upgrade_recovery_test.dart: real populated 0023 to 0024, late catalog/grant rollback and encrypted fenced pre-0024 recovery` — Dedicated isolated P4.12 encrypted migration/recovery opt-in required.
- `test/recipe_browser_test.dart: actual Chrome Recipe authoring, frozen units, restart/lost-response retry, employee read and retirement` — Opt-in ChromeDriver and isolated PostgreSQL required.
- `test/recipe_client_journey_test.dart: real Flutter Recipe controllers, HTTP API and PostgreSQL evidence` — Opt-in real Flutter and isolated PostgreSQL required.
- `test/shift_transfer_browser_test.dart: P4.11 real Flutter controllers approval, exact restart retry and recipient ordinary Guided Work` — Opt-in Flutter with isolated PostgreSQL required.
- `test/shift_transfer_browser_test.dart: P4.11 real Chrome UI approval, exact restart retry and recipient ordinary Guided Work` — Opt-in Flutter with isolated PostgreSQL required.
- `test/stock_count_browser_test.dart: real Chrome Stock count workflow and PostgreSQL zero/provenance oracle` — Opt-in ChromeDriver and isolated PostgreSQL required.
- `test/stock_count_client_journey_test.dart: real count client/API/database journey and independent ledger oracle` — Opt-in real Flutter and isolated PostgreSQL required.
- `test/task_knowledge_browser_test.dart: real Chrome P4.6 authoring, immutable historical panel and literal DOM` — Opt-in ChromeDriver and isolated PostgreSQL required.
- `test/task_planogram_browser_test.dart: real Chrome P4.7 authoring, immutable historical panel and literal DOM` — Opt-in ChromeDriver and isolated PostgreSQL required.

### Retained limitations and stopping boundary

The original two real unfinished-upload network assertions remain historical
**0 PASS / 2 FAIL**, and were not rerun. No new unfinished-upload network probe,
slow-upload/load/resource-exhaustion experiment, restricted scanner retry or
security-control bypass was performed. Finite in-process input/clock tests prove
StoreOS/native parser control flow, successful completion/mutation ordering and
public destroy invocation; they do not measure real expiry wire-close timing or
OS file-descriptor reclamation. No pre-EOF 413 or new 408 guarantee is claimed.
Linux runtime/actual process signals, optional Caddy frontend TCP/HTTP2 retention
and hardware capacity remain unverified. The inspected pinned native termination
mechanism and event-loop qualification remain as documented in ADR 0031.

Both local fixes are ready for independent targeted INGRESS-01/02 re-review;
the independent CHANGES REQUIRED verdict is not replaced by author approval.
No stage, commit, push, PR, merge, deployment or release was performed. The index
is empty. P4.16 remains IN PROGRESS; Stage B2b remains separate and unstarted.

### Final inventory and raw hashes

This remediation changes exactly **13 paths** relative to the independently
reviewed tree: five HTTP implementation files (`api_support`, native guard,
`server_app`, `upload_lifecycle`, `platform_plugin_routes`), the existing lifecycle
test, three new native-ingress test/fixture files, ADR 0031, this handoff and two
existing current-status summaries. Those summaries only correct the current
verdict and point to this evidence; older dated history remains intact.

The complete local B2a tree is **31 paths: 13 tracked modifications / 18 untracked**,
index empty. Compared with the reviewed 27 paths, nine change, eighteen remain
byte-identical and four join the inventory (one previously tracked plugin-route
file and three new test/fixture files). F01–F03 Application/Identity/shared-contract
sources and assertions, migrations 0001–0029, lockfiles and OpenAPI/Flutter/recovery
sources remain unchanged. Branch, HEAD and cached origin/main remain the reviewed
values above. No fetch or Git-reference mutation was performed.

The table is the complete 31-path worktree. All 31 raw hashes, including this
document, and all 29 migration hashes are in the external
`C:/dev/storeos/.local/p416-ingress-01-02-remediation/final-snapshot.json`.
The self-referencing row refers there instead of embedding a hash that would
change itself. `yes` identifies this task's thirteen changed paths.

| State | Changed this remediation | Absolute path | Raw SHA-256 |
| --- | --- | --- | --- |
| M | no | `C:/dev/storeos/apps/server/bin/server.dart` | EC2C24B790F7A4AD2DAF24A4DB2958E1E4AF669A78F5C32CE01BCE6BA2A28B0A |
| M | no | `C:/dev/storeos/apps/server/lib/src/application/shift_swap_application.dart` | 333D450C80AA909612CAAA31838E56975CA5BFB584B1B099D7A0615BDB5C69B6 |
| M | no | `C:/dev/storeos/apps/server/lib/src/config.dart` | BD331AAB734AFAB63076EAB7402D23A991AFD5F28F963C803B790D09EB0816F4 |
| M | yes | `C:/dev/storeos/apps/server/lib/src/http/api_support.dart` | F1D3D7F4238218D1BC2B915A776840B0F454EBB819E1852332F2F5B49A6EF8E5 |
| M | no | `C:/dev/storeos/apps/server/lib/src/http/platform_app.dart` | A89357187712469D097AFA90B45B2FAFB9B5AAA7500C34413A00210CE150EC2C |
| M | yes | `C:/dev/storeos/apps/server/lib/src/http/platform_plugin_routes.dart` | 549AAB5D78C11D2CDDA8E64176E4D19C604F4AC524FCE5EDF606D6B89FCEB64F |
| M | yes | `C:/dev/storeos/apps/server/lib/src/http/server_app.dart` | 7CD0E2CF5D64083E8DB1B78684322321F42F76FE41F33A7117F8711765640761 |
| M | no | `C:/dev/storeos/apps/server/lib/src/identity/employee_links.dart` | 8D795CE662D6E9D7DA7A917D00EE1CC99AA96842BC61B3579D5B2AB72A0DA1BE |
| M | no | `C:/dev/storeos/apps/server/test/config_test.dart` | EFCCB8E84C3A926DA3D971DBBD2241C21C273193EC67DE12CF563CEA7143B9CE |
| M | no | `C:/dev/storeos/apps/server/test/merchandising_fixture.dart` | 3C9B2A54C9B795B0CF5EA96096CE16CCDBC8E090181E56B0FF3680F29CB538ED |
| M | yes | `C:/dev/storeos/docs/HANDOVER.md` | 932974F80E57B3623E471956282D9217D5AD8EA5B7371F10AF831D8C1FED4D7E |
| M | yes | `C:/dev/storeos/docs/roadmap/status.md` | 162BE956907193505F965B20FBFBA97FC3FB16C71DA46F17CB0CF4022CD8C86B |
| M | no | `C:/dev/storeos/packages/api_contracts/lib/src/shift_transfers.dart` | 7F978272D22FE899F0648BBEC3D87B67B10F2AEB789E277EB6002591D3A57E62 |
| ?? | yes | `C:/dev/storeos/apps/server/lib/src/http/guarded_http_server.dart` | 6D63BEBF72D33F5B3448DAB13B7C657583B0F34E5FA2539DACCB0FD0CBAF3C3C |
| ?? | no | `C:/dev/storeos/apps/server/lib/src/http/shift_swap_routes.dart` | 838D96B02449244845469400B0904CD170A0104E35677537628F8FACE17FA857 |
| ?? | yes | `C:/dev/storeos/apps/server/lib/src/http/upload_lifecycle.dart` | 449A83C8355BAF874815C550648607F1ADB16436CF8EC67B1B9BC8682EEFF472 |
| ?? | no | `C:/dev/storeos/apps/server/test/guarded_http_server_test.dart` | 228A2E60B9F9163D1F7DFE49CA17D2EC59465C28A21FEAF5F1D210DB7731D75C |
| ?? | yes | `C:/dev/storeos/apps/server/test/native_ingress_fixture.dart` | AE9BDDFD204BA890F571831BD04C138B71CF7F4B412B628587336336A1E0A2EF |
| ?? | yes | `C:/dev/storeos/apps/server/test/native_ingress_postgres_test.dart` | 7D914176BB85B5F584CD7DF94D3FFFFF4CE7E4EB85044D2942EA13F1210798BD |
| ?? | yes | `C:/dev/storeos/apps/server/test/native_ingress_regression_test.dart` | 80DC06FDC03B3B2C1221600A318A8DB08ECD98B65227543328ED59F85722AE10 |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_error_test.dart` | A249DB171B1F885034CA868C06707945B2C5A77F524F8211619D215CEC951C0E |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_fixture.dart` | 65483CC1B623A5EA04A368C2B52307A25C6B8486513CE49ACF1889BE03570342 |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_pagination_test.dart` | B01EA2B9B09063BE78B3983664B16B46DFB6A8B90228A2A080697572C3613444 |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_parser_test.dart` | BA35E21870853E81D7F040C0ED291B57CA75494EA3BDC13B08056C3DE1CBEC69 |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_privacy_test.dart` | D3A0829B895FDEF88368B7EAEE18D01D3B5367C377A314761418942E3D25E05C |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_remediation_test.dart` | C500544E16D6567DCE1C77F63D8CE2F405B8F18644A7D0ADA506A6254AFAD0D0 |
| ?? | no | `C:/dev/storeos/apps/server/test/shift_swap_http_test.dart` | 92222935431CDA1EE73D5698D8F8A2187D94FB8F6A4560A5F7D45E815B028CC0 |
| ?? | yes | `C:/dev/storeos/apps/server/test/upload_lifecycle_test.dart` | 52D16FF74C9CC2581C4C546CE51C29949E7B978EBA11A725A0AB1424587D215F |
| ?? | yes | `C:/dev/storeos/docs/adr/0031-bounded-native-http-ingress.md` | 7FA15A3392BF09B6BB8BA542B5F984403BAFFE8A8AD2AF9278C896C7BF700079 |
| ?? | yes | `C:/dev/storeos/docs/development/phase-4-16-stage-b2a.md` | See external final-snapshot.json (self-reference) |
| ?? | no | `C:/dev/storeos/packages/api_contracts/test/shift_reason_unicode_test.dart` | 3AAAE182E1F9C0F252F84259C845CA6DEF7383E169755581FD405FE1B153B857 |
