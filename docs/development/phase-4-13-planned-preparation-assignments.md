# P4.13: Planned Preparation Assignment

User-selected implementation, 2026-10-11. State: **IMPLEMENTED LOCALLY**.
Independent review returned **CHANGES REQUIRED** for F01. F01 is **REMEDIATED LOCALLY**;
targeted independent re-review, focused Codex Security and changed-commit remote CI
are **PENDING**. P4.13 is not DONE/CLOSED. P4.14 is **UNSELECTED**.

## Baseline and delivery boundary

Implementation began on clean `main` at `d48856f8eb0ccf4565295616606fe674bc0f2b49`
(`Close P4.12 acceptance`). Cached and live origin matched. All five jobs succeeded
in [baseline closure CI 38156014870](https://github.com/RobinBrohl/storeos/actions/runs/38156014870).
P4.1–P4.12 remain DONE/CLOSED; their dated evidence is retained. Baseline P4.12
closure publication has therefore completed, although its historical documentation
described that then-pending gate. No claim about P4.13 remote CI follows from baseline CI.

All changes remain unstaged/uncommitted on the original HEAD. No branch, stash,
commit, push or PR is created. Historical migrations 0001–0024 and dependencies remain
unchanged. Only `0025_planned_preparation_assignments.sql` is added. All database
journeys use disposable resources; the normal StoreOS deployment is untouched.

## Independent review F01 and bounded remediation

Review chronology is retained without claiming independent approval:

| Assessment | Result | Evidence boundary |
| --- | --- | --- |
| Initial implementation | 96 PASS / 4 QUALIFIED / 0 FAIL | 1,352 package tests; 16 phases; 15 opt-in journeys and 2 migration cases; 3 numeric browser stages. |
| Supplied independent adversarial review | **CHANGES REQUIRED**, 95 PASS / 4 QUALIFIED / 1 FAIL | F01: **MEDIUM PRODUCT DEFECT, COMMIT BLOCKER**, criterion 04 manager assignment creation. |
| Bounded F01 remediation, local self-assessment | **F01 REMEDIATED**, 96 PASS / 4 QUALIFIED / 0 FAIL | Valid only after the fresh final-source verifier passes with unchanged content/timestamps. Targeted independent re-review remains pending. |

Before changing the service, the retained regression exercised real HTTP routing,
authorization, Production and Identity ports over restricted PostgreSQL. Configured
Location was `aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa`:

| Route spelling | Eligible picker | Create |
| --- | --- | --- |
| lowercase | one eligible Employee | 201, canonical stored Location |
| uppercase | incorrectly empty | 422 `assignee_unavailable` |
| mixed case | incorrectly empty | 422 `assignee_unavailable` |

`.local/p413/f01/pre-fix-http.log` retains **0 PASS / 1 FAIL / 0 SKIP**, as expected.
A second directly related pre-fix regression returned 400 `invalid_cursor` when a real
lowercase self-list cursor was used on the equivalent uppercase route. Evidence:
`.local/p413/f01/pre-fix-self-cursor.log`, **0 PASS / 1 FAIL / 0 SKIP**. The saved original
service was used only for that bounded reproduction; the fix was reinstated in `finally`.

Root cause: `_run` validated `recipeId(location)` but discarded its canonical value.
Callbacks captured raw route spelling. Identity correctly compared that string with
canonical stored Location IDs; cursor scope also used raw string identity. The fix
uses the existing validator once inside the authorized transaction and supplies its
canonical value to every assignment callback. Organization/Identity/Inventory arguments,
cursor scope, audit Location and related reads now share that identity. Assignment
persistence and receipt matching continue to use configured canonical scope. Identity
eligibility, command schemas, Company locking and Batch execution rules are unchanged.

The [UUID HTTP/PG tests](../../apps/server/test/preparation_assignment_location_uuid_test.dart)
cover all three spellings, minimal picker projection, canonical assignment/receipt/audit
identity, all four requested replay combinations, payload/target/version/actor conflicts,
concurrent identical creation, distinct/nonconfigured Location and Company denials,
foreign Employee/missing target, inactive Employee/Account, revoked link/capabilities and
stale Employee versions. Self list/detail/recipe/history/start, cross-spelling pagination
and replay, retained R1 after R2 and standalone historical-opening denial use real ports.

The focused verifier explicitly runs the new UUID file plus existing assignment HTTP/PG,
contract/OpenAPI and Flutter manager/session tests. Final remediation evidence is
`.local/p413/final/summary.json`, phase logs and source manifests. Exact fresh totals and
fingerprint come from that report. All established opt-in/Purchasing/Recipe/Batch/Transfer/
Count/guidance journeys, numeric browser work, migration recovery, encrypted backup/update,
crypto/redaction/diagnostics, printing, setup, Compose and diff checks are rerun.
The old 593-file fingerprint
`d5e80aa6d9b1e1f63e6c0c887710157442fa3f438e2c9da02af9dad9ad6e26a3`
is exclusively pre-remediation evidence, retained in `.local/p413/f01/pre-remediation-final/`.

Migrations 0001–0025 and grants are unchanged. Migration 0025 retains SHA-256
`c08228a7812e600a57c3850079afcecfd6660d05a959132dd9cf346d79e3baf0`.
No 0026, dependency change, normal-database operation, Security scan or P4.14 work is
part of remediation. Original main/HEAD/origin, empty index/stash and one worktree remain
required; changes stay unstaged/uncommitted. Qualifications 89–92 retain targeted
independent approval, focused Security approval, remote implementation-commit CI and
accepted standing limitations. The independent F01 finding is preserved above.

## Delivered contract

[ADR 0027](../adr/0027-planned-preparation-assignment.md) records the genuine retained
revision execution decision. Production owns both new tables, the aggregate, receipts
and Application service. It uses public People, Identity, Organization and Inventory
ports and existing Production Recipe/Batch ownership. No foreign repository/table
access is introduced into assignment application code.

Managers create a request for one current eligible Employee and exact current approved
Recipe revision, with required planned count 1–9999. Assigned v1 terminates at started
or withdrawn v2. Withdrawal retains its reason and creates no Batch. Start opens one
exact matching Batch atomically; assignment stays started while Batch outcomes evolve.
Immutable requested count, original actual completion, effective corrected count and
correction chain are presented separately. A zero correction leaves original completion
intact. There is no scheduling, recurrence, reassignment, Task/Shift coupling,
attendance/HACCP semantics, yield conversion, Goods Receipt or automatic Stock effect.

Creation requires current Recipe execution eligibility. Assigned R1 may start after
R2 publication only through the narrow persisted-assignment Batch opening path.
Retirement or current Article/Assortment/unit failures block fresh execution. Authorized
historical Recipe/Batch context still resolves exact R1 with current warnings; ordinary
Recipe discovery and standalone opening retain their previous rules.

## Authorization, evidence and recovery

Admin has `production.assignments.manage`; Employee has self read/start. Recipe read,
Batch execute and linked-detail Batch authority remain additional requirements.
Every operation revalidates current Account/session under the Company lock. Route,
configured and current Account Location must match. Self identity is derived from a
current active link and People activity interval. Assignment ownership follows Employee
identity after valid Account replacement; replay continues to bind the original actor.
Scoped denial precedes receipt disclosure. The eligible picker returns only ID, display
name and Employee version, never Account/session credentials.

Three immutable command kinds bind Company/operation, actor, kind, Location, resource,
expected version and canonical intent. Replay returns original accepted evidence, even
after completion/correction or retirement; current Batch detail is fetched separately.
Failed writes consume no UUID. Both receipt families, linkage and minimized audit commit
with the Batch or roll back together, including deferred failures. Assignment creation,
withdrawal and start audits contain IDs/transitions; start also creates one Batch-opening
audit. Counts, reasons, names and Recipe text remain in authorized business evidence.
No integration event is emitted.

Migration 0025 adds two tables, scoped FKs, exact published revision binding, a narrow
Batch uniqueness anchor, unique non-null Batch link, null-safe lifecycle checks, typed
JSON payload/result checks and deferred canonical opening evidence validation. Runtime
has SELECT/INSERT and only lifecycle/evidence column updates. Content, receipts, deletes
and truncation are protected. Malformed runtime SQL does not become business authority;
the accepted supported-writer boundary remains explicit.

## API and Flutter

Manager root: `/api/v1/platform/production/manage/locations/{locationId}/preparation-assignments`.
Self root: `/api/v1/platform/production/self/locations/{locationId}/preparation-assignments`.
Twelve operations provide manager list/create/assignees/detail/recipe/history/withdraw
and own list/detail/recipe/history/start. Existing Recipe discovery and Batch routes
remain execution APIs. Shared strict DTOs and both OpenAPI representations are updated
with endpoint-local statuses/codes and baseline preservation tests; M4 is not rewritten.
Body limit is 16,384 streamed bytes, decoded duplicate keys are rejected, lists are
bounded at 50 and cursors at 2,048 characters with complete endpoint/filter/owner scope.

Manager UI includes exact preview, eligible picker, planned count, confirmation,
withdrawal and linked execution/history. Own UI includes list/detail, exact context,
explicit start, Work shortcut and navigation into existing Batch execution/corrections.
All text is literal. Frozen uncertain intent disables editing/alternative submission.
Later reconciliation denial retains uncertainty; logout/reload loses memory tracking
only. Same/different Account replacement clears resident and mounted state. Confirmed
commands survive failed detail refreshes while stale actionable detail is removed.

## Verification and reproducibility

The evidence-backed [acceptance matrix](phase-4-13-acceptance.md) covers the original
92 requirements and eight explicit expansions. Local results and exact counts are
reported from the frozen verifier, not inferred from skipped tests or earlier HEAD CI.

Run `scripts/preparation/Run-P413FinalVerification.ps1`. It inventories every tracked
and non-ignored untracked source file by path, length, SHA-256 and modification time,
then verifies four package suites/analyzers/formatters, release Web, Compose, focused
tests, every established/new opt-in host, populated migrations, numeric Guided Work,
encrypted backup/restore, update/recovery, crypto/redaction/diagnostics, print and setup.
It checks content and timestamps after every phase. Ignored local reports do not alter
the source inventory. Sanitized results: `.local/p413/final/summary.json`, phase logs
and `source-before.json`/`source-after.json`. A final report is valid only when this
verifier reports pass with unchanged source; source edits invalidate earlier evidence.

Focused tests cover typed intent, authorization, scoped pagination, replacement links,
retained R1, observed lock queues in both orders, exact replay, grants and deliberate
faults at every persistence stage. Malformed opening payload/result or linked timestamp
is rejected atomically and the same operation can subsequently succeed. Flutter tests
exercise all command kinds, immutable retry, later denial, failed refresh, held reads/
writes/status and mounted dialogs for same/different Accounts.

The real controller and actual Chrome gateways create through manager UI/controller,
publish R2 before Employee start, deny another Employee, observe competing HTTP starts,
lose a committed response and restart the server. Exact retry opens one R1 Batch;
Employee completes actual 2, manager appends 1 then 0, and original remains 2. Retirement
blocks a fresh pending start while retained context/replay remain exact. Deterministic
protected Purchasing, Stock/Count, Workforce/Tasks, Knowledge/Planogram and event hashes
remain unchanged.

Backup acceptance adds seven assignments/twelve receipts across two Employees and four
linked Batches: assigned, withdrawn, started/open, completed with corrections 1 then 0,
cancelled and uncorrected completed. Total preparation evidence is nine Batches/twenty
Batch receipts/four corrections. It compares deterministic complete table contents,
IDs, timestamps, pins, receipts, audit and corrections; fresh sessions verify ownership,
historical context, scope denial and exact effect-free replay. Old sessions/plugin tokens
and restored runtime activation remain fenced. Sources and disposable targets are distinct.

Forward recovery includes clean 0001→0025, real populated 0024→0025 with meaningful
Purchasing, transfers, Batch/corrections, Counts and guidance, and a deferred injected
fault after migration grants and ledger insertion. Catalog/data/grants/ledger roll back;
forward application succeeds and reapplication is a no-op. Encrypted pre-0025 restoration
preserves historical schema with 0025 absent, revokes sessions/runtime CONNECT, and
leaves updated source assignment evidence intact. There is no downgrade/auto-activation.

## Remaining gates and standing limitations

Supplied independent CHANGES REQUIRED → bounded F01 remediation → pending targeted
independent re-review → focused Codex Security → user-controlled implementation
publication → exact-head remote CI → documentation closure publication → closure
exact-head CI. This implementation/remediation work does not conduct independent or
Security review, or stage/commit/push.

M1 proxy/login-limiter pilot gate; M2 CLOSED; M3 local containment; M4 global taxonomy;
P4.12 I01–I03 INFO; P4.5 F01/F02; P4.9 historical qualification; supported-writer/raw-SQL;
memory-only retry recovery; physical device/accessibility gaps; retention/export/offboarding
and RPO/RTO/recovery decisions retain their previous dispositions. Real employee-data
use still requires operator privacy decisions. P4.14 is UNSELECTED.
