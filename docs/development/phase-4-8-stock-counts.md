# P4.8 Selected-article inventory counts

Current state: **IMPLEMENTED LOCALLY** on `main`, uncommitted and unstaged.
**INDEPENDENT REVIEW REMEDIATION COMPLETE**. **TARGETED REVIEW PENDING**,
**SECURITY REVIEW PENDING**, **REMOTE CHANGED-COMMIT CI PENDING**.
This record does not close P4.8. No Codex Security scan was run.

## Baseline and authoritative contract

The immediately preceding capability-selection plan and the user's 124-point
implementation contract select this bounded MEDIUM slice. Dynamic pre-edit checks
established clean tree/index, `main`, HEAD/cached/live origin at
`59b6e81b4dde9d887a0b88c60514c0ec9e6f94fe`, no stash and one intended worktree.
P4.1–P4.7 were canonically DONE/CLOSED without active remediation. The migration
chain ended at 0019; no 0020 or active P4.8 existed. All five jobs succeeded in
[exact baseline CI 37379316991](https://github.com/RobinBrohl/storeos/actions/runs/37379316991).
That CI is evidence for the baseline, not these uncommitted changes.

See [ADR 0022](../adr/0022-selected-article-stock-counts.md) for ownership,
frozen labels, Account separation, zero variance and supported-writer decisions.

## Delivered local behavior

Manager → select 1–100 existing levels → one eligible Employee → open immutable
rounds. Employee → own blind count → one exact physical observation per current
round. Manager → review baseline/observation/discrepancy/current Stock → explicitly
recount selected lines if stale → whole atomic approval. Nonzero discrepancies create
typed `count_correction` movements; zero discrepancy preserves outcome evidence with
no Stock mutation/version/timestamp change. Terminal cancellation retains evidence;
new counts may link approved/cancelled predecessors without reversing Stock.

Migration `0020_stock_counts.sql` adds five Stock-owned tables, full scoped identities,
append-only observations/rounds/receipts, line/terminal guards, exact approved-outcome
checks and movement provenance. Migrations 0001–0019 and dependency lockfiles remain
unchanged. Runtime columns are narrowly granted, with no SECURITY DEFINER.

Current session, fixed capabilities and configured Company/Location equality precede
all reads/replays. Managers additionally require existing Stock management authority.
Own reads/recording require current eligible Employee linkage; new observations and
recounts stop after eligibility loss. Accepted evidence remains manager-reviewable.
Admin can count through an eligible own link but cannot approve any CURRENT
observation recorded by that Account. Superseded observations remain historical.

## API and user interaction

Production namespace: `/api/v1/platform/locations/{locationId}/stock-counts`.
It provides manager list/open, eligible assignee choices, detail, scoped round history
and recount/approve/cancel commands. `/api/v1/platform/me/stock-counts` provides own
list/detail/history and line observations. Complete request/response schemas and
route-specific errors live in [OpenAPI](../../packages/api_contracts/openapi.yaml).
List/history pages have a fixed maximum of 50; count detail has 1–100 current lines.

Manager access starts in Stock; employee access starts in Meine Arbeit. Quantity and
unit identities, accepted observation, recount-required state, terminal outcomes and
literal purpose/reason/note labels are visible in the appropriate flow. Manager
baseline and current Stock are explicitly distinct. Employee DTOs and history decode
only their blind shapes; no client hiding is relied on. No HTML/Markdown execution.

Commands keep memory-only immutable route/body/UUID/session identity. An uncertain
outcome blocks a new command and offers exact retry. A confirmed command followed by
failed refresh is confirmed with a separate warning. Same/different Account replacement
clears reads, picker selections, input and tracking; old responses cannot populate a
replacement session or acquire its token. Browser reload can lose local tracking and
requires server-state inspection; it never reverses a server command.

Audit uses bounded IDs/versions/transition facts for open, observation, recount,
approval, cancellation and Stock correction. Quantities/discrepancies/free text stay
in business records. No events/outbox or generic workflow engine is added.

## Reproducible verification

Pinned local SDKs: Dart 3.13.4 / Flutter 3.47.5. Existing dependencies only;
all Flutter commands use `--no-pub`, Dart tests use cached package configuration.
The [P4.8 runner](../../scripts/stock/Run-P48Checks.ps1) creates strictly named
`storeos_p48_<hex16>_test` databases, uses supported HTTP writers, and drops only
its owned database in `finally`. The normal StoreOS database is untouched.

- Default: real PostgreSQL count/integrity/concurrency/migration suite, including
  100-line mixed approval with bounded Unicode notes/recount reasons and a 1 MiB
  maximum original-result receipt, explicit 101 rejection, third-line stale and self-recorded
  whole rejection, plugin/Company/Location/current-capability denial, deterministic
  advisory-lock queue orderings, movement/line-outcome/audit rollback injection,
  sanitized operational failure and restart replay.
- `-ClientJourney`: actual Flutter controllers and HTTP adapters over the fixture API
  into PostgreSQL; two lines 10 kg/5 Stk, observe 9/5, manual 12, stale rejection,
  recount at 12, observe 11, mixed approval, deliberately lost committed approval
  response, later Stock correction, exact retry and independent ledger oracle.
- `-Browser`: real Chrome production manager creation, blind employee observations,
  stale disabled approval, recount, blind superseded history, whole mixed approval,
  linked follow-up and terminal cancellation; independent PostgreSQL outcomes.
- `-BrowserRegressions`: existing Knowledge, Task+Knowledge and Task+Planogram Chrome
  journeys. `-Numeric`: existing three-phase numeric Chrome/process-replacement E2E.
- `-FullRegression`: all four package tests, all analyzers/formatters, Web release
  build and Compose validation. Opt-in database tests require the explicit test DB;
  opt-in browser/client/capacity tests are reported separately, never treated as passes
  merely because discovery skipped them.
- Existing backup/restore and update/recovery wrappers run with
  `-SkipPackageResolution`. Backup hashes five count tables, scoped movements,
  approved/zero outcomes, cancellation/follow-up and receipts. Restored reads/replay
  verify blindness and Location scope after session/plugin revocation and runtime
  fencing. Update smoke runs the count journey through 0020; recovery restores the
  independent pre-update point. Separate 0019→0020 test hashes populated Task schemas
  1–4, Knowledge, Planogram, Stock and execution evidence through failed/successful
  migration. Existing diagnostic/report redaction and crypto checks also apply.

Local detailed run logs and sanitized operational reports are ignored `.local`
artifacts, not committed secrets or fabricated fixtures. The final review handoff
reports exact counts and the independent 1–124 results. A deterministic source
fingerprint is captured before/after final-source checks; all source/tool/test/doc
edits precede that boundary. No commit, push, branch switch or remote mutation occurs.

Preflight verification on 2026-10-06 passed 111 API-contract tests, 325 server tests
against isolated PostgreSQL, 2 design-system tests and 310 Flutter tests. The server
inventory includes 27 count integrity/concurrency/migration tests; the Flutter
inventory includes 24 count controller/session/widget tests and contracts include
6 count-specific tests. The five opt-in discoveries (four Chrome wrappers and the
count HTTP client journey) are executed separately. The count-specific PostgreSQL
suite also passed independently after the Unicode receipt-bound change. All four
analyzers and format checks passed. Final-source runs use ignored `final-*` logs;
their actual results, exact counts, source fingerprint and operational report links
are reported in the review handoff without modifying source after verification.

## Limits and pending gates

Only selected existing levels, one Employee and whole approval are delivered. No
whole-Location/statutory inventory, valuation, reservations, purchases/sales,
unit conversion, batches/expiry, multiple assignees, partial approvals, recurring
counts, generated Tasks, scanner/device acceptance, offline queues, sync or P4.9.
Targeted independent review, focused security review and remote changed-commit CI remain
pending. Existing M1 proxy/deployment and broader M3/M4 debt are not closed here.

## Independent review and bounded remediation — 2026-10-06

Chronology is retained: the initial implementation claimed **124/124 local PASS**.
The independent adversarial review returned **CHANGES REQUIRED**, with
**122 PASS / 2 QUALIFIED / 0 FAIL** in the numbered matrix. Core Stock correctness
passed. F01/F02 were additional review gates outside that matrix.

| Finding | Original independent result | Bounded remediation |
| --- | --- | --- |
| F01 | LOW product defect; malformed cursor null/type/UUID escaped validation; commit blocker | Decode required non-null UUID or safe positive integer within the existing scoped cursor parser; all malformed forms use the same private `400 invalid_cursor`. No Count domain change. |
| F02 | LOW documentation/contract defect; assignees lacked `400`, manager list omitted malformed Location `invalid_count`; commit blocker | Inventory all 12 operations; document reachable identity/cursor errors and assert exact route-specific validation/status/conflict sets. The reachable `403 origin_forbidden` middleware code is explicit for all 12 operations. Existing non-Count operations/schemas remain unchanged. |
| F03 | LOW security-relevant defect; hidden manager history maps/cursor/error survived authenticated identity replacement; commit blocker; criterion 19 qualified | A session listener clears resident rows, cursor, error and loading synchronously on every opaque replacement; captured identity and existing controller epoch fence delayed responses. Dispose also discards retained state. |
| F04 | INFO restore authorization evidence gap; nonblocking; criterion 119 qualified | Link another same-Company/Location Employee before encrypted backup; authenticate B after restore, prove eligible own list, then deny A's Count detail, Round history and exact observation replay through production Application paths (`404 not_found`). |

Focused verification passed **29/29 P4.8 HTTP/PostgreSQL tests**, including
**50 malformed-cursor HTTP probes** across manager/employee lists and histories,
malformed path/Location parity, valid ascending Count pagination and descending
manager/employee Round pagination without omission/duplication or scope crossing.
**28/28 Flutter tests** include four new resident-state widget proofs for same-Account
replacement in both audiences, manager-to-employee and employee-to-manager changes.
Each has multiple loaded rows, an old pagination error, an outstanding page, immediate
state inspection before render, delayed-response fencing and close/reopen validation.
**7/7 Count contract tests** inventory all operations. The focused encrypted restore
acceptance passed with **3/3 explicit foreign-Count denials**, alongside unchanged
assigned-Employee blindness, provenance, hashes, receipts and revocation/fencing checks.

### Reachable validation inventory

All operations retain authenticated `401`, authorization `403 forbidden` / Origin `403 origin_forbidden`, scoped
`404`, sanitized `500`/`503`, and their documented success response. Writes alone
have bounded `413`/`415` and command conflicts (`409`). The Location guard can
return `404` when the configured Location is unavailable; own lists can also lack
current eligible Employee context. Malformed identity validation is `invalid_count`.
Only paged reads use `invalid_cursor`; only writes parse JSON (`invalid_json`).

| Operation | 400 codes | Additional domain validation |
| --- | --- | --- |
| listStockCounts | invalid_count, invalid_cursor | None |
| openStockCount | invalid_json, invalid_count | 409 operation/count conflict, version exhausted; 422 assignee unavailable |
| eligibleStockCounters | invalid_count | None |
| reviewStockCount | invalid_count | None |
| reviewStockCountHistory | invalid_count, invalid_cursor | None |
| recountStockCount | invalid_json, invalid_count | 409 operation/count conflict, version exhausted, count stale; 422 assignee unavailable |
| approveStockCount | invalid_json, invalid_count | 409 operation/count conflict, version exhausted, count stale; 422 incomplete or self-approval forbidden |
| cancelStockCount | invalid_json, invalid_count | 409 operation/count conflict, version exhausted |
| ownStockCounts | invalid_cursor | None |
| ownStockCount | invalid_count | None |
| ownStockCountHistory | invalid_count, invalid_cursor | None |
| recordStockCountObservation | invalid_json, invalid_count | 409 operation/count conflict, version exhausted, round conflict, observation exists |

### Final-source evidence boundary

Remediation preflight matched the reviewed **454-file** fingerprint
`c32c5254751eb3a68a0ab72a32640813de9241be4fc21d33a886caeed01b4561`.
Migration 0020's raw SHA-256 remains
`5a536a70fbcc713cc6ca8e27099fa22f0bfb1aa56afce8b3fd2c7efe94d7c525`.
Only the four findings and their evidence/documentation are touched. Migrations
0001–0019, dependencies, core Count semantics and existing contract definitions
are preserved. No branch/commit/push, dependency resolution, normal-database write
or Codex Security run is part of this pass.

All source/test/tool/doc edits precede the final verification boundary. The ignored
`.local/p48/remediation-final-summary.json`, before/after source manifests and
`remediation-acceptance.md` retain exact final results and a reassessment of each
original criterion 1–124. Criteria 19/119 require the new state-clearing/restore
proofs; criterion 121 requires the complete final-source regression. No criteria
are added. Final results are reported in the handoff only after execution;
unchanged fingerprints prove no source edits followed the final boundary.

Canonical state: **P4.8 IMPLEMENTED LOCALLY / INDEPENDENT REVIEW REMEDIATION
COMPLETE / TARGETED REVIEW PENDING / SECURITY REVIEW PENDING / REMOTE
CHANGED-COMMIT CI PENDING**. This is not DONE/CLOSED and does not replace the
original independent findings with an approval.
