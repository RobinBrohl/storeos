# P4.14 — Purchase Order Delivery Evidence and Reconciliation

Status: **DONE/CLOSED — accepted implementation** at
`0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df`. P4.15 is **UNSELECTED**.
**Documentation-closure publication and its own exact-commit CI remain PENDING.**

## Final documentation closure — 2026-10-12

The accepted implementation was published by one explicitly authorized non-force
push from baseline `9e9cae3055b324413b93784491055beb20e826c4` to
`0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df`. Local HEAD, cached origin/main and live
remote main agreed at the implementation SHA; the tree/index were clean, the stash
empty and one worktree present before this documentation-only closure.

[GitHub Actions push run 38277299556](https://github.com/RobinBrohl/storeos/actions/runs/38277299556)
uses `.github/workflows/ci.yml`, branch `main`, event `push`, attempt 1, and the exact
implementation SHA above. The workflow is completed/success; every required job
completed successfully on that SHA:

| Required job | Job ID | Status | Conclusion |
| --- | --- | --- | --- |
| dart | 114905785848 | completed | success |
| flutter | 114905785910 | completed | success |
| numeric-guided-work-e2e | 114905785881 | completed | success |
| backup-restore-acceptance | 114905785981 | completed | success |
| update-recovery-acceptance | 114905786142 | completed | success |

The review chronology is retained in order:

1. Independent functional review returned **APPROVE** with two LOW follow-ups.
2. Bounded F01 remediation invalidated the loaded delivery register and cursor after
   confirmed Order/delivery commands, retaining filters and session fencing.
3. Bounded F02 remediation replaced weak raw-SQL negatives with canonical complete
   controls, specific rejection assertions and full rollback/same-ID replay proof.
4. Targeted independent F01/F02 re-review returned **APPROVE**; both findings are **CLOSED**.
5. Focused Codex Security returned **SECURITY APPROVE**.
6. Final remediation verification returned **PASS**; the unchanged implementation
   was committed and published, then its exact implementation CI succeeded.

Executed local evidence retains its original scope: the original 1,451 package
passes and sixteen verification phases, followed by 195 focused remediation passes
(51 API / 135 server / 9 client), 414 complete client passes, real controller/HTTP/
PostgreSQL and actual Chrome/page-reload journeys, both affected analyzers, formatting
and diff checks. Those earlier inventories are not rewritten as closure-source runs.
This closure changes Markdown only; no full regression, Security scan, migration,
backup/update acceptance or deployment operation is repeated or newly claimed.

The [109-criterion acceptance matrix](phase-4-14-acceptance.md) independently totals
**107 PASS / 2 QUALIFIED / 0 FAIL**. Criterion 105 is now PASS because exact
implementation CI has completed; criteria 106 and 109 remain QUALIFIED:

- **Standing operational limits (106):** physical goods verification, native devices/
  accessibility, supported-writer/raw-SQL trust, memory-only uncertain-command recovery,
  retention/export/offboarding, key custody, RPO/RTO and recovery activation are not
  certified by implementation acceptance. M1/M3/M4, P4.5 F01/F02 follow-ups, P4.12
  I01–I03 INFO, P4.9 history and P4.13 qualifications remain; M2 stays CLOSED.
- **Historical static-client incident (109):** an earlier invalidated release check
  temporarily replaced the normal proxy's served client. All 39 files were restored
  from a pinned published-baseline rebuild and matched it. Original pre-build hashes
  were unavailable, so exact previous-build byte identity remains qualified. No
  database write, container restart or image replacement occurred. Subsequent final
  and remediation checks preserved served contents, sizes and timestamps. The original
  incident record below remains unchanged; this closure does not erase or reclassify it.

**Recorded delivery evidence does not mutate or establish Stock.** P4.1–P4.14 are
DONE/CLOSED as accepted implementations. No active P4.14 review remediation or required
Security fix remains; accepted limits are not unrelated debt closure. P4.15 remains
UNSELECTED and no next capability is selected.

Implementation publication and its CI are complete. This documentation closure is
prepared as one local Markdown-only commit; its publication requires separate user
authorization, followed by verification of its own exact-SHA push CI. No documentation-
closure publication SHA, workflow run or successful closure CI is claimed in this
record before those gates exist. Local verification evidence is retained separately
under `.local/p414-closure`; it is not included in the closure commit.

## Historical implementation and remediation hand-off records

The following record is retained verbatim from the implementation commit, apart
from its already-reused document title. Earlier IMPLEMENTED LOCALLY and PENDING
states describe their original stages, including the approval/publication gate;
the dated final documentation closure above supplies the current disposition.

Status: **IMPLEMENTED LOCALLY**. Independent functional review: **APPROVE**.
Targeted F01/F02 re-review: **APPROVE**; both findings **CLOSED**.
Focused Codex Security: **SECURITY APPROVE**. Final remediation verification: **PASS**.
Implementation-commit CI and final P4.14 closure: **PENDING**. P4.15 is **UNSELECTED**.
The user authorized one local implementation commit; push requires separate authorization.

## Approval and implementation publication gate — 2026-10-12

The user confirmed independent functional APPROVE, targeted F01/F02 APPROVE with
both LOW findings CLOSED, focused SECURITY APPROVE, and final remediation PASS.
No additional independent review or Security scan is performed during commit
preparation. The approved source matches all 616 files in the final remediation
inventory; only approval documentation changes before this implementation commit.

Executed evidence remains: the original 1,451 package passes and sixteen verification
phases, followed by 195 focused remediation passes (51 API / 135 server / 9 client),
414 complete client passes, real controller/HTTP/PostgreSQL and Chrome/page-reload
journeys, both affected analyzers, formatting and diff checks. The original and
bounded source inventories retain their own scope; no new full-suite run is claimed.

This local implementation commit is not final P4.14 closure. Publication requires
explicit push authorization. After publication, CI must report completed/success
on this exact implementation SHA for all five jobs in `.github/workflows/ci.yml`:
dart, flutter, numeric-guided-work-e2e, backup-restore-acceptance and
update-recovery-acceptance. Only then may a separately authorized documentation
closure/publication proceed, with its own exact-commit CI. No implementation CI
result, closure SHA or closure CI outcome is invented here.

The static-client-asset incident, standing operator/device/privacy/recovery limits,
dependency metadata exception and all prior historical evidence remain preserved.

## Bounded LOW review remediation — 2026-10-12

At the bounded remediation hand-off, independent APPROVE had two LOW follow-ups;
targeted re-review and Security were then pending. The user subsequently confirmed
targeted APPROVE, both findings CLOSED and SECURITY APPROVE as recorded above.
Implementation-commit CI remains pending.

**F01 — stale delivery register.** Confirmed Order and delivery commands invalidate
the register's rows and cursor before detail refresh. Status, Supplier and search
filters remain unchanged. The existing register reload starts from the first page;
an old cursor cannot append stale rows. Tests begin with a loaded register, declare
a delivery or close an Order, and verify invalidation, retained filters and fresh
reads. Failed detail refresh still leaves the register invalidated. Held responses
from replaced same/different Account sessions cannot clear replacement-session rows.

**F02 — weak raw SQL negatives.** A shared test fixture uses canonical `1.000`
receipt quantities and creates a complete revision/line/receipt transaction. Its
unmodified control commits and replays through the supported API. Every malformed
transaction changes one invariant, checks SQLSTATE plus the intended constraint,
column or trigger message, and compares all Purchasing/delivery/audit evidence
after rollback. The identical unmodified intent then commits using the failed
transaction's IDs and replays, proving the fixture and rollback rather than merely
accepting an arbitrary ServerException. Duplicate-ledger tests now have an existing
ledger entry. Aggregate overflow uses individually valid quantities; integer syntax
and nonpositive quantity checks are separate. Earlier NULL receipt copies are also
replaced with complete controls, and grant/orphan probes assert specific rejections.

Bounded verification and exact counts are recorded in
`.local/p414-remediation/summary.json`, with focused, complete-client, analyzer,
real-controller and Chrome logs beside it. This evidence applies to the remediation;
the original `.local/p414/final` inventories and sixteen-phase results remain
historical evidence for the prior source. A full sixteen-phase rerun, operational
backup/update rerun were not performed during remediation; the subsequent independent
re-review and Security verdict are recorded separately in the approval section above.

All migrations, dependency files, business contracts and accepted limitations are
preserved. This remediation runs only disposable test projects and the test browser
server; no release build writes to the normal served directory. Before/after served
asset hashes, sizes and timestamps are retained with the bounded verification.

## Verified baseline

`main`, HEAD/cached/live origin `9e9cae3055b324413b93784491055beb20e826c4`,
`Close P4.13 acceptance`; clean tree/index, empty stash and one worktree.
The closure contains exactly sixteen Markdown files. Migrations 0001–0025 match
HEAD and their introduction commits; 0026 was absent. All eight manifests/lockfiles
match HEAD. P4.1–P4.13 are DONE/CLOSED with no active P4.13 remediation.

GitHub run [38229127545](https://github.com/RobinBrohl/storeos/actions/runs/38229127545)
is completed/success on that exact SHA: dart, flutter, numeric-guided-work-e2e,
backup-restore-acceptance and update-recovery-acceptance all succeeded. This supersedes
the pending publication statements retained in the historical P4.13 drafting record.
Those historical checks are not P4.14 verification.

## Operator workflow

Open Purchasing, issue an Order through the existing reviewed draft workflow, then
record accepted deliveries in each frozen Order-line unit. Choose a local reference,
select 1–50 exact lines and enter positive decimal strings. A note is required when
effective overdelivery increases. The register filters Order references, Supplier
and issued/terminal status and links to authorized Order detail.

Current reconciliation shows ordered quantity, effective recorded delivery,
recorded remainder and overdelivery per line. Inspect a declaration and its revision
history. Correct by replacing the complete line set with a reason; omitted lines
contribute zero. Void with a reason; correction can restore a voided declaration.
No-change commands return a definitive conflict without redundant evidence.

Close/cancel remains administrative and is allowed with a recorded shortfall. A
fresh issued-order terminal command atomically freezes the reconciliation boundary.
Existing declaration corrections remain available afterwards. A 12-unit Order with
5 and 7 records closure at 12. Correcting the first to 4 afterwards shows current
11 and remainder 1 alongside unchanged closure 12; Order state/version/time stay
terminal. New identities are disabled after termination. Pre-tracking terminal
Orders show “Delivery tracking was not available at closure”; cancellation before
issue explicitly shows no issued-delivery lifecycle.

**Recorded delivery evidence does not mutate or establish Stock.** It declares
accepted goods and excludes rejected goods. It does not establish physical receipt,
quality, supplier agreement/transmission, inventory availability or invoice acceptance.
No declaration does not prove no goods arrived. No unlike-unit Order total exists.
Local references are operator chosen, not supplier shipment UUIDs. Independent
identities can still mistakenly describe one physical shipment.

## Contract and ownership

Purchasing owns all four new tables and their projections. Domain/Application owns
selection/lifecycle/replacement/overdelivery validation; routes and widgets delegate.
Platform supplies current authorization, one Company transaction and atomic audit.
Organization retains configured scope. Frozen P4.12 Order lines provide Article and
unit meaning; delivery code reads no foreign business repositories or Stock tables.
Supplier retirement and catalog edits cannot reinterpret issued evidence.

The three complete DTOs are `PurchasingDeliveryDeclare`, `PurchasingDeliveryCorrect`
and `PurchasingDeliveryVoid`. All bind operation, expected Order and ledger versions,
target identity and canonical quantities/reason; correction/void also bind expected
revision. Declare alone supplies identity/reference. Nullable declare reason is an
explicit field. Canonical line sets sort by Order-line UUID. Every UUID is normalized.
Unknown fields, snapshots, units, supplied actors/times/totals/sequences are rejected.

Decimal strings use positive exact thousandths through 999999999999.999. Overflow-safe
per-line intermediate sums use BigInt/numeric; the same bound applies to effective
totals. `effectiveDelivered` sums only each identity's latest nonvoid revision.
`recordedRemainder=max(ordered-effective,0)` and `overdelivery=max(effective-ordered,0)`.

Capability `purchasing.orders.manage` protects every delivery read/write. Existing
close (`purchasing.orders.issue`) and cancellation capabilities remain unchanged.
Current session/active Account/Company/configured and Account Location plus persisted
Order/Delivery scope precede receipt disclosure. Employee/viewer/auditor/plugin
credentials gain no permission; no Employee link is required for managers.

Company writer and scoped Order locks serialize accepted revisions and terminal
capture. New delivery receipts and old Purchasing receipts share one operation UUID
namespace in both supported and database insertion directions. Exact replay returns
immutable original revision/summary/status with `replayed=true`, before fresh version
and lifecycle validation. Conflicts expose no receipt. Failed commands produce no
business evidence, receipt or audit and leave the UUID reusable.

Both receipt insertion guards require the supported read-committed mode, so waiting
for the Company lock cannot retain a repeatable-read snapshot that hides the other
table's accepted operation. Restricted-SQL tests reject higher isolation in both
insertion directions. Existing Platform transaction behavior remains unchanged.

Migration `0026_purchase_order_delivery_evidence.sql` adds exactly revisions, revision
lines, commands and terminal snapshots. Required FKs/JSON/lifecycle checks reject
NULL/UNKNOWN. Deferred validation binds complete line collections, receipt intent,
result and exact terminal operation/time/version/ledger. New evidence receives
SELECT/INSERT only; update/delete/truncate are denied. Migrations 0001–0025 and old
business/receipt rows remain unchanged. No migration 0027 or SECURITY DEFINER exists.

## HTTP and client

Root `/api/v1/platform/purchasing`; eight new operations:

| Method | Location-scoped suffix |
| --- | --- |
| GET | `/delivery-register` |
| GET | `/orders/{orderId}/delivery-summary` |
| GET / POST | `/orders/{orderId}/deliveries` |
| GET | `/orders/{orderId}/deliveries/{deliveryId}` |
| GET | `/orders/{orderId}/deliveries/{deliveryId}/history` |
| POST | `/orders/{orderId}/deliveries/{deliveryId}/correct` |
| POST | `/orders/{orderId}/deliveries/{deliveryId}/void` |

Both OpenAPI representations inventory reachable errors per operation and preserve
all prior contracts. Strict decoded JSON and queries, streamed 16,384-byte bodies,
bounded payload/result sizes, pages of 50 and 2,048-character endpoint/resource/filter
cursors contain M3 locally. M4 is not globally rewritten.

Flutter retains immutable accepted results separately from current actionable detail.
Before dispatch it freezes session, canonical route, complete intent and operation.
Uncertain outcomes allow only exact retry, including after a later authorization
denial. Confirmed commands survive refresh failure; stale detail is cleared. Opaque
same/different Account replacement clears lists, filters, histories, pending intent
and independently owned mounted-dialog controllers and fences delayed responses.
All untrusted business text renders literally. Pending client recovery remains memory
only; reload requires authentication and authoritative server reads.

Audit actions `purchasing.delivery.declared/corrected/voided` contain only scope,
Order/Delivery/operation IDs and revision/ledger identifiers. Quantities, references,
Supplier/Article names and reasons stay out of general audit/logs. No read evidence
or outbox event is introduced.

## Reproducible verification

Use pinned Flutter 3.47.5 / Dart 3.13.4 and existing locked dependencies. The normal
StoreOS app/proxy/database container processes and business database remain unchanged. P4.14 verification creates
unique disposable PostgreSQL projects/databases on available loopback ports. Owner
access is setup/inspection only; business writes use authenticated supported APIs
with restricted runtime credentials. Cleanup targets only owned test resources.

The only dependency metadata exception is an explicit Flutter SDK `flutter_driver`
development dependency in the client. It was already resolved transitively; offline
resolution changes only its lockfile classification to direct dev, with no package
version, hash or runtime dependency change. The required actual page refresh must run
before driver teardown, which the standard integration driver does not expose as a
callback. The dedicated Purchasing driver also retains failure diagnostics.

Run `scripts/purchasing/Run-P414Verification.ps1 -Mode focused`, `journey`, `browser`,
`migration`, `backup`, `update`, `regression`, `hosts` and `numeric` as needed.
`Run-P414FinalVerification.ps1` freezes every relevant tracked/untracked source and
documentation file, records hashes/sizes/UTC write times, runs complete verification
and rejects any content or timestamp change. Sanitized logs and exact counts live in
`.local/p414/final/summary.json`; before/after inventories are in that directory.
The [numbered acceptance matrix](phase-4-14-acceptance.md) maps actual evidence and
qualifications. Skipped conditional tests are never counted as executed acceptance.

The restricted PostgreSQL suites exercise arithmetic, originals/replacement/void,
terminal comparison, durable replay, configured scope, shared namespace, ordered
lock races, rollback injection, NULL/JSON integrity, restricted grants and pagination.
Real Flutter/HTTP/PostgreSQL and Chrome journeys exercise lost successful responses,
server restart/replay, forms, literal text, 50 lines and persisted reads.

Backup acceptance retains all established nonempty fixtures, nine delivery revisions,
nine new receipts, eight revision lines, partial/overdelivered Orders, immutable
closure followed by correction, and genuine pre-0026 terminal history. Deterministic
table contents/relationships, source conservation, runtime replay/access and fenced
restore are verified. Populated 0025 update/recovery additionally proves late failure
after grants/ledger, full rollback, forward/no-op migration and encrypted pre-0026
restore retaining P4.12/P4.13 evidence. No downgrade or second writer activation.

## Gates and standing limits

Implementation → independent adversarial review → bounded remediation/re-review →
focused Codex Security → user-controlled implementation commit/push → exact-commit
CI → documentation closure → user-controlled closure publication/CI.
Independent functional review and targeted F01/F02 re-review returned APPROVE;
both findings are CLOSED. Focused Codex Security returned SECURITY APPROVE.
Final remediation verification passed. Implementation-commit CI and final P4.14
closure remain PENDING; this is not DONE/CLOSED.

M1 proxy/login-limiter pilot gate remains; M2 is CLOSED. M3 remains endpoint local;
M4 global taxonomy remains open. P4.12 I01–I03 INFO, P4.5 F01/F02, P4.9 historical
qualification and P4.13 qualification/report follow-up remain historical dispositions.
P4.14 updates the touched update-report prose through 0026 without rewriting prior
evidence or claiming unrelated debt closure. Raw SQL supported-writer trust, device/
accessibility acceptance, retention/export/offboarding, physical verification,
backup-key custody, RPO/RTO and recovery activation remain operator decisions.

No StockLevel/Movement/Count, Production, Tasks/Shifts, returns, conversion, invoice,
financial, supplier transmission, attachment, offline queue or multi-site feature is
selected. No P4.15 is selected. The local implementation commit is authorized;
push and final documentation closure remain separate gates.

## Verification artifact incident

The first frozen-run attempt was invalidated by the bounded isolation-guard correction.
During that attempt, the inherited release-build command also wrote to
`apps/client_flutter/build/web`, which is mounted by the running normal proxy.
This temporarily replaced its static client assets. No normal database connection,
business write, container restart or image replacement occurred.

The published-HEAD client was rebuilt from a Git archive of
9e9cae3055b324413b93784491055beb20e826c4 with the pinned SDK and enforced offline locks.
All 39 restored served files match that baseline build exactly. The original pre-build
artifact hashes were unavailable, so exact previous-build byte identity is qualified.
A browser that loaded the temporary client may require a reload.

P4.14 release verification now writes only to `.local/p414/web-release`. The final
orchestrator additionally fingerprints every normally served client file and rejects
any content or timestamp change through all verification phases. The failed attempt
and restoration evidence remain under `.local/p414`; only the final successful frozen
run is current implementation evidence. This incident is disclosed, not called an
untouched deployment or hidden by the source verification result.
