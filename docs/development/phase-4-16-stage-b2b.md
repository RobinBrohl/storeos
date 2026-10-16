# P4.16 Stage B2b — OpenAPI parity

**B2B-01 FIXED LOCALLY; independent targeted re-review is pending.** The latest
independent verdict remains **STAGE B2b CHANGES REQUIRED**, for the single MEDIUM
generator finding recorded in the remediation section below. The independent
review otherwise confirmed all sixteen routes, twenty-two schemas and historical
preservation. B2a remains independently APPROVED. No author approval replaces the
independent verdict.

The initial implementation record and its dated counts/hashes below are retained
as history. The final sections describe B2B-01 remediation and the current
39-path whole-worktree inventory.
Only implementation-plan Step 7 is implemented by this change. P4.16 remains
**IN PROGRESS**. Flutter Steps 8–9, expanded recovery and final acceptance remain
separate gates. All work is local and uncommitted.

## Starting snapshot and authorized delta

The starting branch was `codex/p416-stage-b2a-swap-http`; both HEAD and cached
`origin/main` were `289dc07bc5b8e85b3a3430f45244e13adc9e3a11`. The index was empty.
There were exactly 31 independently reviewed B2a paths, comprising 13 tracked
modifications and 18 untracked files. No B2b implementation was present.

The independent report
`.local/ingress-targeted-independent-c0e94965bf8546a49ffe43efb194f84b/Review.md`
concludes **STAGE B2a APPROVE**: F01–F03 and INGRESS-01/02 are CLOSED. Its
`review-final-snapshot.json` was reconciled before editing: all 31 approved path
hashes and all 29 migration hashes matched, with zero inventory/hash differences.
The independent full-server result was **1053 PASS / 0 FAIL / 21 opt-in SKIP**,
22m05s, with an observed process-exit-0 receipt. This is B2a evidence, not a newly
executed B2b full-server run.

All 31 approved B2a paths remain byte-identical, including their historical
handoff/status wording, ADR 0031, native ingress implementation, HTTP routes,
Application code, DTO remediation and tests. The new record here describes the
subsequent Step 7 state without rewriting those approved historical records.
Migrations 0001–0029 are unchanged. No runtime, database, Flutter source,
dependency or lockfile change is part of B2b.

Exactly six paths form the B2b delta:

| Git state | Path | Purpose |
| --- | --- | --- |
| new | `packages/api_contracts/tool/shift_swap_openapi.dart` | Bounded additive generator |
| new | `packages/api_contracts/test/shift_swap_openapi_test.dart` | Independent route/DTO/artifact parity |
| modified | `packages/api_contracts/platform.openapi.json` | 15 paths, 16 operations and 22 schemas |
| modified | `packages/api_contracts/openapi.yaml` | 15 canonical external path references |
| modified | `packages/api_contracts/README.md` | Implemented contract and qualifications |
| new | `docs/development/phase-4-16-stage-b2b.md` | This handoff |

The final whole worktree therefore contains **37 changed paths: 16 tracked
modifications and 21 untracked files**. There was no staging, commit, push, PR,
merge, rebase, reset, clean, stash, deployment or release.

## Exact operation mapping

All paths below have prefix `/api/v1/platform`. Schema names are the concrete
`ShiftSwap*` components. A dash means no JSON command body. Every command returns
`ShiftSwapCommandResult`; creation and its exact replay retain HTTP 201, and the
other accepted commands retain HTTP 200. GETs return HTTP 200.

| # | Method and path after prefix | operationId | Input | Success schema/status |
| --- | --- | --- | --- | --- |
| 1 | GET `/employee-home/shifts/{shiftId}/swap-colleagues` | `listShiftSwapColleagues` | — | `ShiftSwapColleaguePage` / 200 |
| 2 | GET `/me/shift-swaps` | `listSelfShiftSwaps` | — | `ShiftSwapPage` / 200 |
| 3 | POST `/me/shift-swaps` | `requestShiftSwap` | `ShiftSwapRequest` | `ShiftSwapCommandResult` / 201 |
| 4 | GET `/me/shift-swaps/{requestId}` | `readSelfShiftSwap` | — | `ShiftSwapDetail` / 200 |
| 5 | GET `/me/shift-swaps/{requestId}/history` | `listSelfShiftSwapHistory` | — | `ShiftSwapHistoryPage` / 200 |
| 6 | GET `/me/shift-swaps/{requestId}/counterparts` | `listShiftSwapCounterparts` | — | `ShiftSwapCounterpartPage` / 200 |
| 7 | GET `/me/shift-swaps/{requestId}/counterparts/{shiftId}` | `readShiftSwapCounterpart` | — | `ShiftSwapCounterpartDetail` / 200 |
| 8 | POST `/me/shift-swaps/{requestId}/offer` | `offerSelfShiftSwap` | `ShiftSwapOffer` | `ShiftSwapCommandResult` / 200 |
| 9 | POST `/me/shift-swaps/{requestId}/confirm` | `confirmSelfShiftSwap` | `ShiftSwapConfirm` | `ShiftSwapCommandResult` / 200 |
| 10 | POST `/me/shift-swaps/{requestId}/decline` | `declineSelfShiftSwap` | `ShiftSwapDecline` | `ShiftSwapCommandResult` / 200 |
| 11 | POST `/me/shift-swaps/{requestId}/withdraw` | `withdrawSelfShiftSwap` | `ShiftSwapWithdraw` | `ShiftSwapCommandResult` / 200 |
| 12 | GET `/locations/{locationId}/shift-swaps` | `listManagedShiftSwaps` | — | `ShiftSwapPage` / 200 |
| 13 | GET `/locations/{locationId}/shift-swaps/{requestId}` | `readManagedShiftSwap` | — | `ShiftSwapDetail` / 200 |
| 14 | GET `/locations/{locationId}/shift-swaps/{requestId}/history` | `listManagedShiftSwapHistory` | — | `ShiftSwapHistoryPage` / 200 |
| 15 | POST `/locations/{locationId}/shift-swaps/{requestId}/approve` | `approveManagedShiftSwap` | `ShiftSwapApprove` | `ShiftSwapCommandResult` / 200 |
| 16 | POST `/locations/{locationId}/shift-swaps/{requestId}/reject` | `rejectManagedShiftSwap` | `ShiftSwapReject` | `ShiftSwapCommandResult` / 200 |

The two list roots accept bounded `status`; the self list additionally accepts
`direction`. Only operations 1, 2, 5, 6, 12 and 14 accept `after`. Unknown or
duplicate query keys are rejected. The one public withdrawal endpoint derives
source/recipient intent from current server authority; clients cannot choose an
actor or kind.

## Concrete schemas and strictness

The 22 new schema names are:

| Group | Schemas |
| --- | --- |
| Commands | `ShiftSwapRequest`, `ShiftSwapOffer`, `ShiftSwapConfirm`, `ShiftSwapDecline`, `ShiftSwapWithdraw`, `ShiftSwapApprove`, `ShiftSwapReject` |
| Guidance/work | `ShiftSwapKnowledgePin`, `ShiftSwapPlanogramPin`, `ShiftSwapTaskSummary`, `ShiftSwapTaskLink`, `ShiftSwapLeg` |
| Immutable evidence/receipts | `ShiftSwapEvidence`, `ShiftSwapCommandResult` |
| Detail and request pages | `ShiftSwapDetail`, `ShiftSwapPage`, `ShiftSwapHistoryPage` |
| Scoped discovery | `ShiftSwapColleague`, `ShiftSwapColleaguePage`, `ShiftSwapCounterpartCandidate`, `ShiftSwapCounterpartPage`, `ShiftSwapCounterpartDetail` |

Command objects are closed with `additionalProperties: false`, and every declared
field is required. All require `operationId`; creation additionally requires
`requestId`, `sourceShiftId`, `expectedSourceVersion` and `recipientEmployeeId`.
Offer requires `counterpartShiftId` and `expectedCounterpartVersion` as well as
`expectedVersion`. The remaining commands require `expectedVersion`; only
withdrawal and rejection require and permit `reason`. No actor, Account/link
authority, frozen snapshot, replacement identity or timestamp is accepted.

UUID input matches the existing case-insensitive 36-character hexadecimal shape;
it does not impose a UUID version/variant or reject the nil UUID syntactically.
Output UUIDs are canonical lower-case. Shift versions are JSON integer tokens
from 1 through 2147483647. Command stage versions are offer=1, confirm=2,
decline=1–2, withdraw=1–3, approve=3, reject=1–3. Recipient withdrawal is restricted
by server authority to stages 2–3; current eligible source ownership permits 1–3.

Reason normalization trims first and then validates **1–500 Unicode scalar
values**, forbidding retained C0/C1 controls and unpaired surrogates. Input has
no incorrect raw 500-character ceiling: surrounding whitespace may make the raw
string longer while the normalized reason remains valid. The **8192 UTF-8 byte
command body limit** is documented separately. Retained response reasons are
already trimmed. Tests include 500 supplementary characters, rejection of 501,
and valid padded input longer than 500 raw characters.

`x-storeos-*` annotations explain strict integer tokens, normalization and bounds
that portable JSON Schema cannot completely express. In particular Dart rejects
`2.0`/exponent number tokens where its parser requires an `int`; JSON Schema's
mathematical integer type alone is insufficient. The cursor limit follows Dart's
2048 UTF-16 code-unit length, with nonempty input and explicit annotation, rather
than an assumed UTF-8 byte limit. Tests accept 1024 supplementary cursor characters
and reject 1025. Accepted receipt payloads retain their separate 65536 UTF-8 byte
bound.

Response objects are closed and preserve required nullable properties: omission
is not equivalent to an explicit null. Evidence has at most two ordered legs,
each with 1–10 frozen original Tasks and at most ten ordered Task links, hence at
most twenty links overall. Position constraints apply to each array prefix item
as well as the complete referenced Task/link schema. Replaced legs have one link
per Task; unreplaced legs have none. Guidance pins, exact replacement lineage,
state/version, terminal reason/timestamp and receipt-kind conditions are concrete.
The counterpart detail discloses only the invited recipient's own candidate work,
without replacement/lineage authority.

Request/colleague/counterpart pages contain at most fifty items. History pages
contain at most **two receipts**; the immutable lifecycle contains at most four
receipts in total. Accepted result kind, original status, original accepted
version and `replayed` are explicit. Exact replay returns original evidence;
current available actions and non-actionable reason require a separate detail
read. Available actions are bounded, unique and conditioned on role/state.

Portable JSON Schema does not compare arbitrary variable IDs across distant
fields or order two arbitrary timestamp values. The exact reference identities,
disjoint original/replacement sets, paired identity bases, chronological rules
and receipt-operation binding are therefore stated in `x-storeos-invariants`.
Existing strict Dart DTOs enforce them; parity tests separately prove rejection
of forged cross-field identities. Structural schema validation alone is not
claimed to enforce those relational rules or confer authorization.

## Operation-specific HTTP error matrix

Each operation includes this common set, through the actual authentication,
authorization, query/identifier and exception boundaries:

| HTTP status | Codes |
| --- | --- |
| 400 | `invalid_request` |
| 401 | `unauthorized` |
| 403 | `forbidden`, `origin_forbidden` |
| 404 | `not_found` |
| 500 | `internal_error` |
| 503 | `database_unavailable` |

The following table specifies all additions to that common set. `JSON` means
400 `invalid_json`, 413 `body_too_large` and 415 `unsupported_media_type`.
`Cursor` means 400 `invalid_cursor`. `Fresh` means exactly the six 422 codes
`employee_unavailable`, `guidance_unavailable`, `planogram_guidance_unavailable`,
`shift_in_progress`, `shift_not_swappable`, `shift_not_transferable`.
A dash means the family is absent, not an unspecified blanket error response.

| # / operationId | Parser/cursor additions | 409 codes | 422 codes |
| --- | --- | --- | --- |
| 1 `listShiftSwapColleagues` | Cursor | `resource_limit` | Fresh |
| 2 `listSelfShiftSwaps` | Cursor | — | — |
| 3 `requestShiftSwap` | JSON | `operation_conflict`, `shift_conflict`, `swap_already_pending` | Fresh |
| 4 `readSelfShiftSwap` | — | — | — |
| 5 `listSelfShiftSwapHistory` | Cursor | — | — |
| 6 `listShiftSwapCounterparts` | Cursor | `shift_conflict`, `swap_conflict` | Fresh |
| 7 `readShiftSwapCounterpart` | — | `shift_conflict`, `shift_overlap`, `swap_already_pending`, `swap_conflict` | Fresh |
| 8 `offerSelfShiftSwap` | JSON | `operation_conflict`, `shift_conflict`, `shift_overlap`, `swap_already_pending`, `swap_conflict` | Fresh |
| 9 `confirmSelfShiftSwap` | JSON | `operation_conflict`, `shift_conflict`, `shift_overlap`, `swap_conflict` | Fresh |
| 10 `declineSelfShiftSwap` | JSON | `operation_conflict`, `swap_conflict` | — |
| 11 `withdrawSelfShiftSwap` | JSON | `operation_conflict`, `swap_conflict` | — |
| 12 `listManagedShiftSwaps` | Cursor | — | — |
| 13 `readManagedShiftSwap` | — | — | — |
| 14 `listManagedShiftSwapHistory` | Cursor | — | — |
| 15 `approveManagedShiftSwap` | JSON | `operation_conflict`, `shift_conflict`, `shift_overlap`, `swap_conflict` | Fresh plus `invalid_selection` |
| 16 `rejectManagedShiftSwap` | JSON | `operation_conflict`, `swap_conflict` | — |

This matrix was audited from the router, Application and called owner ports,
independently of the generator's table. Colleague discovery can hit the People
port's `resource_limit`. Counterpart-list candidate-specific failures are filtered;
its retained 409/422 failures concern the request/source checks. Detail reads
convert fresh-work 409/422 failures into `nonActionableReason`, so they have no
HTTP 409/422 response. Request creation has no B leg and no `shift_overlap` error.
Closure commands need no fresh-work 422 family.

The inherited `shift_not_transferable` is an explicit Shift owner-port error.
Approval also calls Tasks replacement creation, whose selection validation has
an explicit `invalid_selection` error. These source-backed paths are included
even though immutable valid published selections normally preclude the latter;
no claim is made that every source-backed code was induced in a live HTTP probe.
Unrelated SQL constraint failures remain **500**, including malformed late
integrity evidence. There is no generic 422 conversion of database constraints.

Existing B2a HTTP error tests cover current authority/privacy failures, stale
versions, claim/operation conflicts, third-Shift overlap, guidance/clock failures,
exact integrity mapping and late deferred rollback. The added local probe records
the specific statuses/codes it actually observed in
`.local/p416-stage-b2b/observed-http-parity.json`: all sixteen successes and common
401/400/Origin-403 cases, parser 400/413/415 on all seven JSON commands, cursor
errors on all six cursor GETs, and selected 404/409 failures. This observation
record is narrower than the complete source-derived matrix.

## Authorization, privacy and transport qualifications

All sixteen operations use the existing bearer `session` scheme. The server
checks configured Company/Location, resource scope, capabilities and current
eligible Account–Employee linkage. Self reads require `workforce.swaps.self.read`;
requests and own-Shift colleague discovery additionally require
`workforce.swaps.self.request`. Offer/counterpart access and exact confirmation
require `workforce.swaps.self.respond` plus the applicable captured participant
identity. Decline authority depends on the captured participant and stage.
Withdrawal derives current eligible source versus captured recipient authority
inside the authorized transaction, including the approved replacement-source
Account recovery behavior. Current authorization precedes any receipt replay.

Manager access requires `workforce.swaps.manage`. Approval additionally requires
`workforce.shifts.manage`, `tasks.instances.read`, applicable pinned guidance read
permissions and an approver Account independent of both consenting Accounts.
Fresh identity, work, exact consent pair, final roster and database time are
revalidated before atomic cancellation/replacement, lineage, receipt/audit and
claim release. Public evidence does not disclose internal Account IDs,
Employee-link IDs or Account-version authority.

Discovery is request-specific: A may discover eligible colleague ID/name from an
own Shift, and invited B may discover only B's own eligible counterparts. There
is no general colleague roster and no access from merely possessing a request
ID or cursor. OpenAPI/UI hints do not enforce or grant these permissions.

The approved native ingress and shared body-completion gates are unchanged.
Applicable completed JSON commands have bounded parsing and 413/415 behavior.
Native upload expiry can destroy the connection without a completed HTTP error;
there is **no pre-EOF 413 or new 408 guarantee**. Existing body-ignoring logout,
event acknowledgement and plugin-disable paths retain genuine EOF fencing before
side effects/replay. This stage does not rewrite their historical OpenAPI entries.

The two original unfinished-upload network assertions remain historical
**0 PASS / 2 FAIL** and were not rerun. No restricted unfinished-upload probe,
slow-upload/load/exhaustion simulation, scanner retry or security-control bypass
was performed. Finite native parser/control evidence does not measure real expiry
wire-close timing or OS descriptor reclamation. Actual Linux execution/process
signals, optional Caddy frontend TCP/HTTP2 lifetime/retention and hardware capacity
remain unverified. Timers/counts assume a responsive event loop. Completed business
work and slow response output have no new general execution timeout; active work
retains its request permit. B2a approval is bounded backend approval, not
deployment-wide availability certification. Codex Security/Daybreak results remain
unavailable; no automated clean-scan claim is made.

## Generator and independent preservation evidence

From `packages/api_contracts`, run
`dart run tool/shift_swap_openapi.dart` with the pinned SDK. The generator validates
both input documents before writing either one, then adds sorted owned members
using raw JSON span splices and bounded canonical YAML insertions. It does not
reserialize the historical JSON document. Existing identical P4.16 definitions
are accepted without rewriting. Duplicate JSON keys, including escaped aliases,
duplicate YAML path keys including quoted aliases, missing/wrong anchors,
unexpected partial additions and conflicting definitions fail with a clear
`FormatException`. A mismatched existing definition is not silently overwritten.

Two repeated CLI runs produced **zero raw-byte differences** in both artifacts;
the pure generator is also tested twice for exact equality. The retained receipt
is `.local/p416-stage-b2b/idempotence.json`.

Independent tests read the actual B2a route registration structure, including
self/manager roots and command-kind branches. A changed path or extra kind in a
mutated router source is detected; unsupported registration syntax fails clearly.
Tests do not import a generator operation/error inventory as their oracle.
They check globally unique operation IDs, all new local/external references,
session security, closed requests, valid/invalid DTO inputs, every evidence state,
nullable required fields, ten-Task legs, replacement links, original receipts,
current detail and bounded pages. A separate manually audited per-operation error
matrix is checked against the artifact and selected actual source/HTTP cases.

The preservation manifest
`.local/p416-stage-b2b/openapi-preservation.json` contains names and before/after
raw SHA-256 hashes for **436 historical JSON members**: 186 paths and 250 schemas.
All are byte-identical and semantically unchanged, including P4.11's ten paths,
eleven operations and twelve schemas, Article Quantity, Stock and Purchasing.
The whole historical JSON tree is semantically identical after removing only
the new owned members. Removing the fifteen new YAML reference entries restores
the original canonical YAML byte-for-byte. No existing operationId, response,
schema, security scheme or error taxonomy was rewritten.

| Historical artifact | Baseline SHA-256 |
| --- | --- |
| `platform.openapi.json` | `A3206A0664537E0F9A4B2E34CC63EC8D370E16B30272939195B38B7CD5289700` |
| `openapi.yaml` | `2D88833F42B970314026CA3917CC570ED7B7FEC4420432710F6138B7F810D34B` |
| package `README.md` | `E786D2022CA872EBF8B0C293466FA2FF454B78D1AEC7CC7EFBC651CEE2253332` |

For an insertion-only review use
`git diff --minimal -- packages/api_contracts/platform.openapi.json packages/api_contracts/openapi.yaml`.
The JSON adds 2554 lines and YAML adds 30, with zero removed lines. Default Myers
diff alignment can look noisy around repeated JSON delimiters; the raw-member
hashes and minimal diff independently establish preservation.

## Verification on the final implementation bytes

Pinned Dart is 3.13.4; tests use the existing cached test 1.32.0 and dependencies,
without dependency resolution/upgrades. All listed exits are observed exit 0.
Local evidence is ignored under `.local/p416-stage-b2b/` unless noted.

| Check | Result | Evidence |
| --- | --- | --- |
| New OpenAPI suite | **33 PASS / 0 FAIL / 0 SKIP** | `parity-second.log`; also included in full package run |
| All API-contract tests, including P4.11 and Article Quantity OpenAPI | **410 PASS / 0 FAIL / 0 SKIP** | `contracts-final.log`, `contracts-final-receipt.json` |
| Approved B2a HTTP cases plus six actual-response schema probes | **67 PASS / 0 FAIL / 0 SKIP**, test output 3m24s, harness 220.60s | `http-regressions-final.log`, `http-final-receipt.json`; harness run `012bdd5a57e242e389c4b4d49ce595d8` |
| API-contract analyzer | clean | `contracts-analyzer.log` |
| Server analyzer | clean, before the HTTP bundle | `http-regressions-final.log` |
| Flutter analyzer | clean | `flutter-analyzer.log`, `flutter-analyzer-receipt.json` |
| Formatter | **306 files, zero changes** | `format.log` |
| CLI regeneration twice | **zero differences on either repeat** | `idempotence.json` |
| Historical raw JSON members | **436 checked, zero differences** | `openapi-preservation.json` |
| Approved B2a/migrations | **60 checked, zero differences**, at start and finish | `baseline.json`, `final-snapshot.json` |
| Flutter Web release | **PASS**, exit 0, 55.4s compiler output | `web-release.log`, `web-release-receipt.json` |

The 61 existing HTTP cases are the six unchanged files `shift_swap_http_test.dart`,
`shift_swap_http_parser_test.dart`, `shift_swap_http_privacy_test.dart`,
`shift_swap_http_pagination_test.dart`, `shift_swap_http_error_test.dart` and
`shift_swap_http_remediation_test.dart`. The six additional local cases are in
`.local/p416-stage-b2b/http_parity_test.dart`. They validate actual production
guard/auth/router/PostgreSQL responses against the schemas: paired ten-Task work,
all reads, two-page original history, 201/200 replay, all four closure intents and
normalized reasons, parser failures and per-route cursor/common errors. Every
network request in this invocation completes its body.

The existing `scripts/workforce/Run-P416StageB1Checks.ps1 -Analyze -TestFiles ...`
harness ran these seven files against a unique loopback `postgres:17-alpine`
tmpfs installation, owner fixture and restricted `storeos` runtime role, with
concurrency two. No normal installation was used. Cleanup verification found
both B2b-owned containers absent and all four generated credential files empty
(`cleanup.json`). Secrets were not included in logs or manifests.

Direct cached test execution uses the test package's `bin/test.dart` from
`.dart_tool/package_config.json`, with `--packages=.dart_tool/package_config.json`
and `--reporter expanded`. The package run has no file filter; the standalone run
selects `test/shift_swap_openapi_test.dart`. Analyzer commands are
`dart analyze --fatal-infos` in `packages/api_contracts` and `apps/server`, and
`flutter analyze --no-pub` in `apps/client_flutter`. Formatting checks use
`dart format --output=none --set-exit-if-changed` on server `bin/lib/test`, contract
`lib/test` and the new generator.

The release compatibility command, from `apps/client_flutter`, was:

```powershell
C:\dev\flutter\bin\flutter.bat build web --release --no-pub --output=C:\dev\storeos\.local\p416-stage-b2b\web-release
```

It produced isolated assets successfully. The tool's Wasm dry run also succeeded;
this is not an actual Wasm release/runtime test or Chrome/operator acceptance.
There are no swap Flutter controllers, navigation or widgets in this delta.

Development failures remain recorded. The first parity invocation had **32 PASS /
1 FAIL** because its raw-member preservation helper also captured `info` members;
the helper was corrected to scope the exact `paths`/`schemas` objects. The first
combined HTTP invocation had **63 PASS / 1 FAIL**, with all 61 approved B2a cases
passing: the new closure loop tried to create duplicate fixture users in one
schema. Each closure now gets a separate isolated fixture, producing the final
67 passes above. `parity-first.log`, `http-regressions.log`, `http-receipt.json`
and the failed harness run `57b265e1aacc4c9da60dd62c84bad584` are retained. No
production behavior or approved assertion was weakened to obtain the passes.

## Remaining gates and review eligibility

This implementation is ready for **independent adversarial Stage B2b review**.
It is an author implementation/verification result, not independent B2b approval.
The existing full-server 1053/0/21 independent B2a result is retained; no new full
server run or enabled opt-in is claimed for B2b. The 21 named opt-ins below remain
explicitly unverified. Broader OpenAPI drift/error-taxonomy debt remains M3/M4;
this bounded slice does not constitute a global router/OpenAPI gate.

Still required under separate authorization: Flutter Application/data Step 8,
employee/manager UI Step 9, actual Chrome and incoming Guided Work/operator
journeys, expanded fenced backup/update recovery Step 10, full A01–A16 acceptance,
appropriate independent functional/security review, and eventual exact-commit CI
and publication approval. Existing P4.15/M1/device/proxy/operator qualifications
are not closed by an OpenAPI change or Web compilation. Stop after this local
Step 7 handoff; do not begin Flutter work automatically.

## Retained opt-in skip inventory

These are the exact 21 existing full-server test-name/reason pairs, copied from
the approved evidence; they were not selected or executed in this stage.

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

## Historical initial B2b changed-file/hash inventory

This is the original 37-path implementation snapshot, before B2B-01 remediation.
Every path below is relative to `C:/dev/storeos`. `B2a preserved` means its raw
SHA-256 equals the independently approved snapshot. `B2b` marks the six-path delta.
The handoff's own hash is stored externally to avoid a recursive self-hash:
`.local/p416-stage-b2b/final-snapshot.json` contains all 37 path hashes, all 29
migration hashes, Git/index state and the approved-baseline comparison. The
following table contains the other 36 raw hashes and the explicit handoff entry.

| Git state | Delta | Path | SHA-256 |
| --- | --- | --- | --- |
| M | B2a preserved | `apps/server/bin/server.dart` | `EC2C24B790F7A4AD2DAF24A4DB2958E1E4AF669A78F5C32CE01BCE6BA2A28B0A` |
| M | B2a preserved | `apps/server/lib/src/application/shift_swap_application.dart` | `333D450C80AA909612CAAA31838E56975CA5BFB584B1B099D7A0615BDB5C69B6` |
| M | B2a preserved | `apps/server/lib/src/config.dart` | `BD331AAB734AFAB63076EAB7402D23A991AFD5F28F963C803B790D09EB0816F4` |
| M | B2a preserved | `apps/server/lib/src/http/api_support.dart` | `F1D3D7F4238218D1BC2B915A776840B0F454EBB819E1852332F2F5B49A6EF8E5` |
| M | B2a preserved | `apps/server/lib/src/http/platform_app.dart` | `A89357187712469D097AFA90B45B2FAFB9B5AAA7500C34413A00210CE150EC2C` |
| M | B2a preserved | `apps/server/lib/src/http/platform_plugin_routes.dart` | `549AAB5D78C11D2CDDA8E64176E4D19C604F4AC524FCE5EDF606D6B89FCEB64F` |
| M | B2a preserved | `apps/server/lib/src/http/server_app.dart` | `7CD0E2CF5D64083E8DB1B78684322321F42F76FE41F33A7117F8711765640761` |
| M | B2a preserved | `apps/server/lib/src/identity/employee_links.dart` | `8D795CE662D6E9D7DA7A917D00EE1CC99AA96842BC61B3579D5B2AB72A0DA1BE` |
| M | B2a preserved | `apps/server/test/config_test.dart` | `EFCCB8E84C3A926DA3D971DBBD2241C21C273193EC67DE12CF563CEA7143B9CE` |
| M | B2a preserved | `apps/server/test/merchandising_fixture.dart` | `3C9B2A54C9B795B0CF5EA96096CE16CCDBC8E090181E56B0FF3680F29CB538ED` |
| M | B2a preserved | `docs/HANDOVER.md` | `932974F80E57B3623E471956282D9217D5AD8EA5B7371F10AF831D8C1FED4D7E` |
| M | B2a preserved | `docs/roadmap/status.md` | `162BE956907193505F965B20FBFBA97FC3FB16C71DA46F17CB0CF4022CD8C86B` |
| M | B2b | `packages/api_contracts/README.md` | `C5B97D320037726AFF8D917BBC57074DADBF4B21A936F4647B62E03CE204B362` |
| M | B2a preserved | `packages/api_contracts/lib/src/shift_transfers.dart` | `7F978272D22FE899F0648BBEC3D87B67B10F2AEB789E277EB6002591D3A57E62` |
| M | B2b | `packages/api_contracts/openapi.yaml` | `9876B2B7D34FB33C52BB3F37E6C3B84EAB350528A7B21E38324826DE8FA6F17A` |
| M | B2b | `packages/api_contracts/platform.openapi.json` | `342BEA8D44627056081E92D2F43A568C1C36125E3314DBBF543314824D5546BE` |
| ?? | B2a preserved | `apps/server/lib/src/http/guarded_http_server.dart` | `6D63BEBF72D33F5B3448DAB13B7C657583B0F34E5FA2539DACCB0FD0CBAF3C3C` |
| ?? | B2a preserved | `apps/server/lib/src/http/shift_swap_routes.dart` | `838D96B02449244845469400B0904CD170A0104E35677537628F8FACE17FA857` |
| ?? | B2a preserved | `apps/server/lib/src/http/upload_lifecycle.dart` | `449A83C8355BAF874815C550648607F1ADB16436CF8EC67B1B9BC8682EEFF472` |
| ?? | B2a preserved | `apps/server/test/guarded_http_server_test.dart` | `228A2E60B9F9163D1F7DFE49CA17D2EC59465C28A21FEAF5F1D210DB7731D75C` |
| ?? | B2a preserved | `apps/server/test/native_ingress_fixture.dart` | `AE9BDDFD204BA890F571831BD04C138B71CF7F4B412B628587336336A1E0A2EF` |
| ?? | B2a preserved | `apps/server/test/native_ingress_postgres_test.dart` | `7D914176BB85B5F584CD7DF94D3FFFFF4CE7E4EB85044D2942EA13F1210798BD` |
| ?? | B2a preserved | `apps/server/test/native_ingress_regression_test.dart` | `80DC06FDC03B3B2C1221600A318A8DB08ECD98B65227543328ED59F85722AE10` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_error_test.dart` | `A249DB171B1F885034CA868C06707945B2C5A77F524F8211619D215CEC951C0E` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_fixture.dart` | `65483CC1B623A5EA04A368C2B52307A25C6B8486513CE49ACF1889BE03570342` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_pagination_test.dart` | `B01EA2B9B09063BE78B3983664B16B46DFB6A8B90228A2A080697572C3613444` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_parser_test.dart` | `BA35E21870853E81D7F040C0ED291B57CA75494EA3BDC13B08056C3DE1CBEC69` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_privacy_test.dart` | `D3A0829B895FDEF88368B7EAEE18D01D3B5367C377A314761418942E3D25E05C` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_remediation_test.dart` | `C500544E16D6567DCE1C77F63D8CE2F405B8F18644A7D0ADA506A6254AFAD0D0` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_test.dart` | `92222935431CDA1EE73D5698D8F8A2187D94FB8F6A4560A5F7D45E815B028CC0` |
| ?? | B2a preserved | `apps/server/test/upload_lifecycle_test.dart` | `52D16FF74C9CC2581C4C546CE51C29949E7B978EBA11A725A0AB1424587D215F` |
| ?? | B2a preserved | `docs/adr/0031-bounded-native-http-ingress.md` | `7FA15A3392BF09B6BB8BA542B5F984403BAFFE8A8AD2AF9278C896C7BF700079` |
| ?? | B2a preserved | `docs/development/phase-4-16-stage-b2a.md` | `E3D708855052BB0535E59E0510928A9C2B90E46192E88DF2ACFD5FB767E3040B` |
| ?? | B2b | `docs/development/phase-4-16-stage-b2b.md` | `See external final-snapshot.json` |
| ?? | B2a preserved | `packages/api_contracts/test/shift_reason_unicode_test.dart` | `3AAAE182E1F9C0F252F84259C845CA6DEF7383E169755581FD405FE1B153B857` |
| ?? | B2b | `packages/api_contracts/test/shift_swap_openapi_test.dart` | `F34406F96098D9A9A8C38680C4D2CBD8825F0CD0EF7F1C37F8A06717FF5AEA93` |
| ?? | B2b | `packages/api_contracts/tool/shift_swap_openapi.dart` | `7AE7101EC62B36503D2C49141A6767B4743B5138751507BFCA61906C81FE9BC2` |

## B2B-01 local remediation — 2026-10-16

### Independent finding and reconciled baseline

The complete independent report is
`C:/Users/Robin/.codex/visualizations/2026/10/16/01a144ba-e660-7021-968a-20ce0b96125f/b2b-review/Review.md`,
SHA-256 `FD4FB55BF754859A66BD6D616FFF9AB962A4994FD4170F494533C614906D635A`.
It returns **STAGE B2b CHANGES REQUIRED** for **B2B-01 MEDIUM** near the original
generator line 1008. It independently confirms route/schema/error parity,
references, all 436 historical members, 410 contract passes, 61 existing and six
fresh completed-request HTTP passes, and 85 independently validated wire bodies.
Those are review evidence, not new remediation runs.

Before editing, the 37-path worktree and all 29 migrations matched the retained
B2b snapshot: **66 raw hashes, zero differences**, empty index, unchanged branch,
HEAD and cached `origin/main`. All 31 approved B2a paths remained unchanged.
The independent review's complete 702-file source manifest was also reconciled;
the only subsequent differences are the five authorized remediation paths listed
below. The original independent review/report/reproducer and prior B2b manifests
remain unmodified.

### Original reproduction and root cause

The reviewer supplied this valid YAML entry, inserted before `components:` in
the integrated baseline YAML, with baseline JSON awaiting swap generation:

```yaml
  /api/v1/platform/me/shift-swaps: # existing conflicting owned path
    $ref: "./platform.openapi.json#/paths/~1api~1v1~1platform~1organization"
```

The unmodified generator was executed against exact copied reviewer inputs in
`.local/p416-b2b-01-remediation/original-before/`. It exited **0**, changed both
files, and produced **two** declarations of `/api/v1/platform/me/shift-swaps`.
The path values conflicted. The old regex required the colon to end the line,
so comments/valid alternate mapping syntax could hide keys from duplicate and
owned-definition checks. It also did not parse nested mappings, allowing a
commented historical duplicate and duplicate `components.schemas` to survive.
The defect concerns tooling validation; no approved runtime defect was reopened.

Exact input/output byte copies, SHA-256 hashes, lengths and process results are
retained in `original-before/`, `generator/owned-yaml-comment/` and
`original-reproducer-before-after.json` under the remediation evidence directory.
The two executions used identical inputs:

| Artifact | Input SHA-256 | Old output SHA-256 | Corrected output SHA-256 |
| --- | --- | --- | --- |
| JSON | `A3206A0664537E0F9A4B2E34CC63EC8D370E16B30272939195B38B7CD5289700` | `342BEA8D44627056081E92D2F43A568C1C36125E3314DBBF543314824D5546BE` | same as input |
| YAML | `96A62A07160336BD41EE00711AD5DB6C94CC19B88CF408DD0662569B019F99DE` | `D2EB3E673E10B11F01FD97B2E9EC64CB8968ADEB8FE260A1FD70BC4F32A1A95F` | same as input |

After remediation, the same original input exits **nonzero** (Windows Python
process result 3221225480), reports
`FormatException: Conflicting canonical P4.16 reference: /api/v1/platform/me/shift-swaps.`,
and leaves both files byte-identical: JSON 997996 bytes, YAML 32466 bytes.
There is still exactly the one original path declaration, with zero duplicate
keys. No original working-tree artifact was used for destructive reproduction.

### Exact correction and bounded dependency support

The generator uses the existing cached/locked Dart `yaml` **3.1.4** parser,
without recovery, to validate the whole canonical YAML document. That parser
rejects decoded duplicate keys at every mapping depth, including paths,
components, schemas and path-item properties. Quoting, escapes, trailing comments,
ordinary whitespace and LF/CRLF are interpreted as YAML rather than approximated
by a path-line regex. A quoted `#` and quoted JSON Pointer fragment remain scalar
content. Only direct children of the decoded `paths` map are path declarations.

Managed paths are recognized at complete reserved path-segment boundaries, so a
distinct path such as `/me/shift-swaps-archive` is not mistaken for a swap path.
Every present managed definition must be exactly its expected single `$ref`;
wrong files/fragments, missing/non-string references, extra operation fields,
unexpected managed paths and partial sets fail with a path-specific diagnostic.
A complete valid generated set remains idempotent even when keys are quoted
or carry comments; its bytes are not rewritten merely for presentation.

The bounded canonical layout is explicit: a single OpenAPI 3.1 root block map,
nonempty path block followed directly by the components block, and a schema map.
Unsupported aliases/shared nodes, merge/non-string keys, flow path/root mappings,
intervening root mappings and multiple documents reject clearly. This is a parser
plus bounded layout/reference validation, not a newly implemented YAML language.

Parser source spans locate the insertion point and existing path indentation.
Raw sorted insertion still preserves historical bytes. Input YAML and proposed
YAML are fully parsed and reference-checked; proposed JSON is duplicate-checked
before `main` writes either artifact. Existing JSON input checks are retained.
On validation failure neither output is written or silently repaired. Writes
after successful validation remain sequential: **no crash-proof or I/O-failure
two-file atomicity is claimed**.

To declare the parser import correctly, `pubspec.yaml` promotes the already
locked package to a pinned dev dependency and `pubspec.lock` changes only its
classification from transitive to direct dev. No package version, archive hash,
runtime dependency or other lock entry changes; no package was downloaded or
dependency resolution/upgrade performed. This supporting manifest change is
within generator remediation. No general OpenAPI-tooling refactor was made.

The five paths changed relative to the reviewed B2b snapshot are:

- `packages/api_contracts/tool/shift_swap_openapi.dart`
- `packages/api_contracts/test/shift_swap_openapi_test.dart`
- `packages/api_contracts/pubspec.yaml`
- `packages/api_contracts/pubspec.lock`
- `docs/development/phase-4-16-stage-b2b.md`

The JSON, canonical YAML and README retain their exact reviewed B2b hashes.
There are no new operations, schemas, HTTP/DTO changes, B2a changes or migrations.

### New permanent CLI regressions

Thirty cases extend the existing parity test file: **25 rejected inputs and five
successful inputs**. Each rejected case starts a real Dart generator process in
a disposable directory, asserts a nonzero exit and meaningful `FormatException`
diagnostic, and compares the exact before/after byte arrays of **both** files.
An already malformed duplicate input remains unchanged rather than being repaired;
no additional duplicate or partial output is written.

The 25 rejection cases are:

1. Original conflicting owned path with trailing comment.
2. Commented duplicate historical path.
3. Conflicting path with spaces/tabs around its colon.
4. Original conflict using CRLF.
5. Double-quoted conflicting path with trailing comment.
6. Single-quoted conflicting path with trailing comment.
7. Escaped quoted duplicate historical key.
8. Two identical owned keys, one commented.
9. Correct but partial managed reference set.
10. Malformed managed pointer fragment.
11. Managed reference to another file.
12. Non-string managed reference.
13. Missing managed reference.
14. Contradictory reference plus operation.
15. Duplicate `$ref` property.
16. Duplicate `components.schemas` mapping from the review.
17. Duplicate root `paths` mapping.
18. Nested duplicate operation property.
19. Unsupported merge key.
20. Unsupported aliased path item.
21. Unsupported intervening root mapping.
22. Multiple YAML documents.
23. Conflicting generated JSON path definition.
24. Conflicting generated JSON schema definition.
25. Duplicate JSON path key.

The five successful cases cover exact reviewed-artifact repeats, generation from
historical inputs reproducing the reviewed artifacts, commented/quoted complete
managed definitions, whitespace/CRLF/four-space indentation, and quoted hashes,
nested path-like properties, comment-only path text and a similar distinct path.
Each runs the CLI twice, verifies sixteen operations against an independently
written fifteen-path inventory, retains twenty-two schemas, resolves canonical
references and checks second-run byte equality. YAML parsing rejects duplicate
keys; a separate YAML JSON-subset parse independently checks the raw JSON scanner.
The existing actual-router and DTO parity tests remain intact.

### Verification and preservation

All evidence below is under `.local/p416-b2b-01-remediation/`. Commands use pinned
Dart 3.13.4, cached test 1.32.0 and the existing absolute package configuration;
no dependency installation was required.

| Executed check | Result | Evidence |
| --- | --- | --- |
| Original unmodified reviewer reproducer, before fix | exit 0, two path declarations, both outputs changed | `original-before/receipt.json`, exact byte copies |
| Same original input after fix | nonzero, one original declaration, both outputs unchanged | `original-reproducer-before-after.json` |
| Original independent 14-scenario generator harness | **14 expected outcomes PASS / 0 FAIL**: three successes and eleven rejected/no-write cases | `generator_checks.py`, `generator-results.json`, `generator-after-receipt.json` |
| Focused swap/P4.11/Article Quantity OpenAPI | **65 PASS / 0 FAIL / 0 SKIP**: 63 swap + 1 + 1 | `focused-first.log`, process receipt |
| Complete API-contract suite | **440 PASS / 0 FAIL / 0 SKIP** | `contracts-final.log`, `contracts-final-receipt.json` |
| Pinned contracts analyzer | clean, exit 0 | `analyzer-final.log`, `tooling-receipt.json` |
| Non-writing formatting | **306 files, zero changes**, exit 0 | `format-all.log`, `format-whitespace-receipt.json` |
| Git whitespace check | exit 0 | `whitespace.log`, receipt |
| Historical preservation | **436 members, zero raw differences**, semantic equality and unrelated canonical byte equality | `openapi-preservation.json`, `preservation.log` |
| Successful baseline generation and two repeats | exact reviewed JSON/YAML, then zero byte differences twice | original harness baseline/repeat/repeat-two copies and receipts |
| Final B2a and migrations | **60/60 approved hashes unchanged** | `final-snapshot.json` |

The focused CLI command selects `test/shift_swap_openapi_test.dart`,
`test/shift_transfer_openapi_test.dart` and `test/article_quantity_openapi_test.dart`
through cached test `bin/test.dart --reporter expanded`; the full run has no
file filter. The analyzer is `dart analyze --fatal-infos` in `api_contracts`.
Formatting uses `dart format --output=none --set-exit-if-changed` over server
`bin/lib/test`, contract `lib/test` and the swap generator. The adapted copy of
the original reviewer harness changes only artifact/output locations, validator
lookup and the explicit existing package-config argument required by the parser
import; its fourteen inputs and rejection expectations are retained. A final
assertion checks every exit and no-write expectation. Counts overlap and are not
summed into distinct coverage.

The first sandboxed test attempt failed during kernel-file copying with access
denied, before any test loaded (0 PASS / one load error). Its log is preserved as
`parity-first.log`. Authorized compiler execution outside that temporary-file
restriction produced the clean focused/full results above; no assertion or
production behavior was weakened. No implementation-test failure was hidden.

All 186 historical JSON paths and 250 schemas remain raw-byte identical, including
P4.11 and Article Quantity. The whole JSON/YAML artifacts themselves also retain
their reviewed B2b SHA-256 values from the historical inventory above. All existing
operation IDs, responses/errors, security definitions and canonical references
are unchanged. Both first generation from historical inputs and subsequent
repeats reproduce those exact artifact bytes.

No HTTP suite, full server run, restricted unfinished-upload probe, scanner or
second Flutter Web release build was needed or executed for this tooling-only
remediation. Their prior results and qualifications remain historical evidence.
The 21 opt-ins, real expiry/OS/Linux/proxy/hardware qualifications and later
Flutter/Chrome/recovery/full A01–A16 gates above remain unchanged. No Flutter work,
publication or independently approved B2b verdict is claimed.

**B2B-01 FIXED LOCALLY**, ready for **independent targeted B2B-01 re-review**.
The independent CHANGES REQUIRED verdict is not self-replaced. P4.16 remains
**IN PROGRESS**; the stopping boundary is this local remediation and verification.

## Current complete changed-file/hash inventory after B2B-01

The branch, HEAD/cached origin and empty index are unchanged. There are **39 total
changed paths: 18 tracked modifications and 21 untracked files**. The original
31 B2a paths and 29 migrations remain approved-byte identical. Five paths changed
relative to the reviewed B2b snapshot, including the two supporting manifests;
the combined eight-path B2b-plus-remediation delta remains disjoint from B2a.

All paths below are relative to `C:/dev/storeos`. The handoff's own hash is stored
externally in `.local/p416-b2b-01-remediation/final-snapshot.json`, alongside all
39 path hashes, all 29 migration hashes, the 702-file review reconciliation and
exact five-path remediation delta. Previous manifests remain historical and
unmodified. `B2b preserved` means the reviewed B2b bytes are unchanged;
`B2B-01` marks the five corrected/supporting paths.

| State | Scope | Path | SHA-256 |
| --- | --- | --- | --- |
| M | B2a preserved | `apps/server/bin/server.dart` | `EC2C24B790F7A4AD2DAF24A4DB2958E1E4AF669A78F5C32CE01BCE6BA2A28B0A` |
| M | B2a preserved | `apps/server/lib/src/application/shift_swap_application.dart` | `333D450C80AA909612CAAA31838E56975CA5BFB584B1B099D7A0615BDB5C69B6` |
| M | B2a preserved | `apps/server/lib/src/config.dart` | `BD331AAB734AFAB63076EAB7402D23A991AFD5F28F963C803B790D09EB0816F4` |
| M | B2a preserved | `apps/server/lib/src/http/api_support.dart` | `F1D3D7F4238218D1BC2B915A776840B0F454EBB819E1852332F2F5B49A6EF8E5` |
| M | B2a preserved | `apps/server/lib/src/http/platform_app.dart` | `A89357187712469D097AFA90B45B2FAFB9B5AAA7500C34413A00210CE150EC2C` |
| M | B2a preserved | `apps/server/lib/src/http/platform_plugin_routes.dart` | `549AAB5D78C11D2CDDA8E64176E4D19C604F4AC524FCE5EDF606D6B89FCEB64F` |
| M | B2a preserved | `apps/server/lib/src/http/server_app.dart` | `7CD0E2CF5D64083E8DB1B78684322321F42F76FE41F33A7117F8711765640761` |
| M | B2a preserved | `apps/server/lib/src/identity/employee_links.dart` | `8D795CE662D6E9D7DA7A917D00EE1CC99AA96842BC61B3579D5B2AB72A0DA1BE` |
| M | B2a preserved | `apps/server/test/config_test.dart` | `EFCCB8E84C3A926DA3D971DBBD2241C21C273193EC67DE12CF563CEA7143B9CE` |
| M | B2a preserved | `apps/server/test/merchandising_fixture.dart` | `3C9B2A54C9B795B0CF5EA96096CE16CCDBC8E090181E56B0FF3680F29CB538ED` |
| M | B2a preserved | `docs/HANDOVER.md` | `932974F80E57B3623E471956282D9217D5AD8EA5B7371F10AF831D8C1FED4D7E` |
| M | B2a preserved | `docs/roadmap/status.md` | `162BE956907193505F965B20FBFBA97FC3FB16C71DA46F17CB0CF4022CD8C86B` |
| M | B2b preserved | `packages/api_contracts/README.md` | `C5B97D320037726AFF8D917BBC57074DADBF4B21A936F4647B62E03CE204B362` |
| M | B2a preserved | `packages/api_contracts/lib/src/shift_transfers.dart` | `7F978272D22FE899F0648BBEC3D87B67B10F2AEB789E277EB6002591D3A57E62` |
| M | B2b preserved | `packages/api_contracts/openapi.yaml` | `9876B2B7D34FB33C52BB3F37E6C3B84EAB350528A7B21E38324826DE8FA6F17A` |
| M | B2b preserved | `packages/api_contracts/platform.openapi.json` | `342BEA8D44627056081E92D2F43A568C1C36125E3314DBBF543314824D5546BE` |
| M | B2B-01 | `packages/api_contracts/pubspec.lock` | `A340048958A63D8D13C438EFCD0BA20116A0B56273F5855C469A94729A329560` |
| M | B2B-01 | `packages/api_contracts/pubspec.yaml` | `87C74D5FA31A98428DE03A4C6A6C0DC6C846BAB75E0F891E75A11276E4526781` |
| ?? | B2a preserved | `apps/server/lib/src/http/guarded_http_server.dart` | `6D63BEBF72D33F5B3448DAB13B7C657583B0F34E5FA2539DACCB0FD0CBAF3C3C` |
| ?? | B2a preserved | `apps/server/lib/src/http/shift_swap_routes.dart` | `838D96B02449244845469400B0904CD170A0104E35677537628F8FACE17FA857` |
| ?? | B2a preserved | `apps/server/lib/src/http/upload_lifecycle.dart` | `449A83C8355BAF874815C550648607F1ADB16436CF8EC67B1B9BC8682EEFF472` |
| ?? | B2a preserved | `apps/server/test/guarded_http_server_test.dart` | `228A2E60B9F9163D1F7DFE49CA17D2EC59465C28A21FEAF5F1D210DB7731D75C` |
| ?? | B2a preserved | `apps/server/test/native_ingress_fixture.dart` | `AE9BDDFD204BA890F571831BD04C138B71CF7F4B412B628587336336A1E0A2EF` |
| ?? | B2a preserved | `apps/server/test/native_ingress_postgres_test.dart` | `7D914176BB85B5F584CD7DF94D3FFFFF4CE7E4EB85044D2942EA13F1210798BD` |
| ?? | B2a preserved | `apps/server/test/native_ingress_regression_test.dart` | `80DC06FDC03B3B2C1221600A318A8DB08ECD98B65227543328ED59F85722AE10` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_error_test.dart` | `A249DB171B1F885034CA868C06707945B2C5A77F524F8211619D215CEC951C0E` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_fixture.dart` | `65483CC1B623A5EA04A368C2B52307A25C6B8486513CE49ACF1889BE03570342` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_pagination_test.dart` | `B01EA2B9B09063BE78B3983664B16B46DFB6A8B90228A2A080697572C3613444` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_parser_test.dart` | `BA35E21870853E81D7F040C0ED291B57CA75494EA3BDC13B08056C3DE1CBEC69` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_privacy_test.dart` | `D3A0829B895FDEF88368B7EAEE18D01D3B5367C377A314761418942E3D25E05C` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_remediation_test.dart` | `C500544E16D6567DCE1C77F63D8CE2F405B8F18644A7D0ADA506A6254AFAD0D0` |
| ?? | B2a preserved | `apps/server/test/shift_swap_http_test.dart` | `92222935431CDA1EE73D5698D8F8A2187D94FB8F6A4560A5F7D45E815B028CC0` |
| ?? | B2a preserved | `apps/server/test/upload_lifecycle_test.dart` | `52D16FF74C9CC2581C4C546CE51C29949E7B978EBA11A725A0AB1424587D215F` |
| ?? | B2a preserved | `docs/adr/0031-bounded-native-http-ingress.md` | `7FA15A3392BF09B6BB8BA542B5F984403BAFFE8A8AD2AF9278C896C7BF700079` |
| ?? | B2a preserved | `docs/development/phase-4-16-stage-b2a.md` | `E3D708855052BB0535E59E0510928A9C2B90E46192E88DF2ACFD5FB767E3040B` |
| ?? | B2B-01 | `docs/development/phase-4-16-stage-b2b.md` | `See remediation final-snapshot.json` |
| ?? | B2a preserved | `packages/api_contracts/test/shift_reason_unicode_test.dart` | `3AAAE182E1F9C0F252F84259C845CA6DEF7383E169755581FD405FE1B153B857` |
| ?? | B2B-01 | `packages/api_contracts/test/shift_swap_openapi_test.dart` | `8B3AC4D6766D0676D3B6F7C21A4AFED2C05BB924BCAF61BE063E283C90E03305` |
| ?? | B2B-01 | `packages/api_contracts/tool/shift_swap_openapi.dart` | `DCAD5CED67BE48C12E1909642EBEB233B8CF31AA6B757E7C35395A32812CFDBD` |
