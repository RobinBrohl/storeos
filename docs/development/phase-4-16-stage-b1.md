# P4.16 Stage B1 — internal bilateral swap Application handoff

Current status, 2026-10-14: **Independent STAGE B1 APPROVE; F01 CLOSED.** The owner
authorized exactly one local implementation commit of the approved 51-path
snapshot, with this bounded documentation finalization. Migration 0029 follows
the Application-only investigation and its six masking counterexamples. The
original independent **STAGE B1 CHANGES REQUIRED** verdict remains historical
evidence. See the [independent approval and local finalization](#independent-approval-and-local-finalization--2026-10-14),
[investigation](#f01-investigation--2026-10-14) and the subsequent
[forward-migration record](#f01-forward-migration-remediation--2026-10-14).
B1 is not published or verified by remote CI. P4.16 remains IN PROGRESS.

The implementation handoff below retains its original 2026-10-13 scope and
verification history. Its original pending-review statements precede the
independent CHANGES REQUIRED verdict and do not supersede the current status.

Date: 2026-10-13. **Local, uncommitted Stage B1 implementation verified; independent review required.**
The owner separately authorized Step 5 of the approved
[plan](phase-4-16-implementation-plan.md), its indispensable owner-port integration,
direct Application/PostgreSQL tests and this handoff. P4.16 remains IN PROGRESS.
This document supersedes earlier implementation-authorization statements only for
this bounded stage. Historical Stage A and design evidence is retained unchanged.
No independent Stage B1 verdict, Security acceptance, new CI, publication,
deployment or full P4.16 completion is claimed.

## Starting Git state and scope

- Initial checkout: clean `codex/p416-bilateral-shift-swaps` at
  `d775ff675cc214df7683ca5bb455baf5dd04a6b6`; index empty.
- Initial local main: `3b2d66f07ef7f261a74e922e32cbe656d8998837`.
- `git fetch origin` succeeded. `origin/main` was exactly the owner-specified
  integrated Stage A SHA `525abb7c975d08d8c93aeca3ac72e58ccbb38ce3`.
  Its tree matched the original Stage A branch tip. Local main was safely
  fast-forwarded with `git merge --ff-only origin/main`.
- New branch: `codex/p416-stage-b1-swap-orchestration`, from that exact main SHA.
  HEAD/main/origin/main remain at that SHA. The Stage A branch remains at its
  original tip. No commit, push, PR, merge of implementation, reset or rebase.
- Migrations remain exactly 0001–0028, ending at
  `0028_bilateral_shift_swaps.sql`; no migration or dependency lockfile changed.
  The owner's integrated main CI evidence is
  [run 38460242940](https://github.com/RobinBrohl/storeos/actions/runs/38460242940),
  reported successful on that exact SHA. It is baseline evidence, not B1 CI.

## Implemented Application operations

`ShiftSwapApplication` provides strict request, offer, confirmation, decline,
source withdrawal, recipient withdrawal, manager rejection and independent
manager approval using the existing `ShiftSwapCommandInput` and exact
`ShiftSwapCommandResult`. No alternative command/result encoding was introduced.

Scoped detail separates durable evidence, actionability and available actions.
Participant/manager list pages support direction/status filters and scoped opaque
cursors, with at most 50 items. History returns at most four original typed
accepted results; HTTP history shaping/pagination remains Step 6–7 work.
Readable cursor envelopes contain a SHA-256 binding of private identity bases,
never raw Account IDs, link IDs or Account versions. The already locked crypto
dependency supplies this digest; no new key, schema or dependency was added.
Colleague discovery exposes only eligible Employee ID/display name from an
authorized own Shift, with no one-way overlap filter. Request-specific counterpart
pages and selected detail authorize captured B and expose only B's own work.
Their feasibility query privately excludes exactly stored A and the selected
B-owned original; it accepts no client exclusion list. Offered/confirmed final
roster validation uses Stage A's persisted-pair owner port.

## Owner ports and current authorization

The coordinator uses public Workforce, Tasks, Identity, People and Organization
ports. Tasks owns full pristine-work validation, guidance validation through
`KnowledgeGuidancePort`/`PlanogramGuidancePort`, frozen materialization and paired
Task linkage. It retains the released content/pin behavior. The Application's
only direct SQL is `SELECT clock_timestamp()`; it imports no foreign repository
and reads no foreign module table.

The required additions are scoped request pages/history in the Workforce swap
port, exact owned-claim checks in the shared claim port, a private Workforce
candidate-overlap query behind its public port, and a swap-specific current
Account eligibility/version port. `matchesSwapIdentityBasis` now checks swap
eligibility directly; P4.11's identity operation and behavior are unchanged.

**Bounded Step 6 prerequisite moved forward:** fixed permissions
`workforce.swaps.self.read`, `.self.request`, `.self.respond`, and `.manage`.
Admin receives all four; Employee receives the three self permissions;
Viewer/Auditor/plugin receive none. No P4.11 capability authorizes a swap.
Self commands additionally require current self read, eligible Employee linkage
and their exact participant role. Source closure permits A's current replacement
Account, while offer/confirmation/decline/B withdrawal require their captured
Account/link. Current Account versions and both assignment intervals are
revalidated for progression. Manager approval requires swap manage, Shift manage,
Task read, existing guidance-read rights and an Account independent of both
captured participants. Company/session/configured Location/resource scope is
resolved before receipt access. No HTTP route is registered for these permissions.

## State, receipts, claims and audit

Every mutation runs in one `PlatformDatabase.runAuthorized` transaction.
Current authorization and strict command/resource intent precede replay.
Exact authorized replay precedes lifecycle, version, claim, eligibility and clock
checks and returns the original accepted evidence with `replayed=true`.
Actor, Location, request, command kind, expected versions and canonical payload
are bound to the operation UUID. Failure rolls back the UUID, state, receipts,
claims, Task/Shift effects and audit together.

Request captures A's original and exact ordered work plus both participant
Account/link/version bases, then acquires A's shared claim. Offer revalidates A,
captures B's own complete original and exact work, and atomically acquires B's
claim without stealing either workflow's occupancy. Confirmation uses only the
stored immutable pair. Opposite invitations remain separate until explicit
closure. Staleness changes derived actionability, never state, consent or claims.
Closure preserves prior offer/consent evidence and original schedules, releases
only its parent's claims and supports historical replay without reacquisition.

Accepted mutations append minimized `workforce.swap.<state>` audit containing
request/operation/participant/original IDs, kind, expected/accepted versions and
state. Approval additionally contains both replacement IDs. The only new audit
allowlist fields are bounded `sourceShiftIds`/`replacementShiftIds` lists. New swap
audit excludes names, intervals, instruction bodies, execution values and user
reasons. Existing owner-level audit remains in the same transaction. No event,
notification, scheduler or outbox was added.

## Paired approval and rollback evidence

Approval requires CONFIRMED/3 and both owned claims, captured current identities,
exact original versions/owners/intervals, full pristine 1–10 Task sets, exact current
guidance and final-roster eligibility. Both original Task sets and Shifts are
cancelled before either replacement is published. Two new server IDs are bound
to their exact legs before draft creation. The replacements exchange Employee
ownership, retaining the exact intervals, selections, ordered frozen content and
pins. Existing Workforce publication and Tasks paired linkage run in the same
transaction. APPROVED/4, exact receipt, audit and both claim releases commit
together. Initially deferred Stage A guards remain deferred through commit;
their final fresh database clock check supplies the final time invariant.

The direct tests use disposable PostgreSQL 17 and the actual restricted `storeos`
runtime role. Owner credentials install schema/fault fixtures and read canonical
hashes; they never replace the restricted role for Application commands.
Seven injected approval faults cover second cancellation, second replacement,
partial Task materialization, partial linkage, receipt insertion, audit insertion
and a deferred SQL refusal. Each proves unchanged hashes of originals, Tasks,
request/consent, both claims, lineage, receipts and audit, then reuses the exact
failed approval UUID successfully after removing its injected fault.
An intentionally corrupted missing-B-claim fixture fails closed and leaves its
input unchanged, without silently repairing or reacquiring the missing claim.

Positive cases cover all lifecycle/closure paths, 1 and 10 Tasks per leg, equal
and intersecting departing intervals, half-open adjacency, exact reversed-order
guidance pins, newer Knowledge with retained approved pins, and later execution
of both incoming replacements. Negative cases cover unrelated participants,
independent manager enforcement, Company/Location/session authority, Account/link
replacement and role ABA, stale versions/changed originals, wrong own counterpart,
third-Shift overlap, Knowledge retirement and Planogram invalidation at all three
progression stages. Observed Company-lock queues cover both transfer/swap orders
on A and B, swap/request races, competing B offers and opposite invitations.
Historical replay preserves later current claims as well as terminal release.
The final-clock test holds an observed barrier inside deferred Tasks validation,
crosses the captured start using database time and proves complete rollback.
Existing Stage A F01/F02/F03 probes, populated 0027→0028 preservation/backfill,
P4.11 and affected P4.15 suites passed in the broad run.

## Verification record

SDKs: repository/CI-pinned Dart 3.13.4 and Flutter 3.47.5. Locked dependencies
were used without upgrades or package resolution.

| Check | Result |
| --- | --- |
| Full server with isolated restricted PostgreSQL, including B1/Stage A/P4.11/P4.15 | 890 PASS / 0 FAIL / 21 explicit opt-in SKIP; process exit 0. |
| First B1 lifecycle invocation before matcher/page fixes | 21 PASS / 3 FAIL / 0 SKIP. |
| New B1 four-file invocation before the final Task-detail fixture correction | 44 PASS / 1 FAIL / 0 SKIP; production faults/guidance/final-clock rollback passed. |
| Final five-file B1 invocation, including decoded-cursor privacy and actual 50-item pages | 48 PASS / 0 FAIL / 0 SKIP; final server analyzer: no issues. |
| API contract full suite and analyzer | 362 PASS / 0 FAIL; no analyzer issues. |
| Existing Flutter client suite and analyzer | 425 PASS / 0 FAIL; no analyzer issues. Existing coverage, not swap Flutter acceptance. |
| Design system suite and analyzer | 2 PASS / 0 FAIL; no analyzer issues. |
| Server analyzer | No issues. |
| Four package format checks and `git diff --check` | PASS. |
| Docker Compose configuration | `docker compose config --quiet`: PASS. |
| B1 PowerShell harness syntax | Parser: PASS. |
| Historical migrations/lockfile preservation | Git diff from initial main: empty for all migrations and four lockfiles. |

The dedicated harness is `scripts/workforce/Run-P416StageB1Checks.ps1`.
It creates fresh private test secrets, a new temporary PostgreSQL container,
restricted runtime login, and only `*_test` databases, then removes the container
and blanks its secret files. It waits for TCP readiness to avoid PostgreSQL's
temporary initialization socket. Logs stay under ignored `.local/p416-stage-b1`.
No normal database, served Web assets, backup destination or real employee data
was used.

Draft failures were retained as distinct evidence: a map matcher used identity
comparison; a scoped-page nullable SQL parameter needed an explicit text cast;
the late-execution test needed the actual Task detail rather than the start
command's summary response. Assertions remain strict. One harness startup failed
before tests because the temporary initialization socket was mistaken for final
readiness. Initial sandbox Docker/compiler permission failures ran no acceptance
tests; authorized reruns used the actual restricted database role. The successful
contract rerun resolved the compiler temporary-directory access failure.
Final manual review found that base64 cursor envelopes included private captured
Identity fields. Those fields were replaced with digest bindings before handoff.
The added real pagination case checks decoded cursors and both complete page
traversals (52 colleague identities and 51 own counterpart Shifts).

No swap HTTP, OpenAPI, Flutter, Chrome, Web build or complete recovery acceptance
is reported PASS. A Web build is not required by this diff: shared client contracts,
client source and dependency lockfiles are unchanged. Existing opt-ins and their
unexecuted acceptance boundaries remain as follows: Article quantity
Flutter/Chrome/encrypted recovery (3), Knowledge Chrome (1), preparation assignment
Flutter/Chrome/encrypted recovery (3), preparation batch Flutter/Chrome (2),
Purchasing Flutter/Chrome (2), Purchasing delivery encrypted recovery (1),
Purchasing order encrypted recovery (1), Recipe Flutter/Chrome (2), P4.11 transfer
Flutter/Chrome (2), Stock count Flutter/Chrome (2), Task Knowledge Chrome (1), and
Task Planogram Chrome (1). These 21 opt-in cases were not executed. Existing
non-opt-in HTTP/controller journeys executed by the server suite passed; none is
swap HTTP/Flutter acceptance. No expanded recovery implementation was added.

Final B1 command: `pwsh -NoProfile -File scripts/workforce/Run-P416StageB1Checks.ps1 -Analyze`.
Its log is `.local/p416-stage-b1/3c25535c67f14a2892f81f7b83fd404c/tests.log`.
The broad server command is
`pwsh -NoProfile -File scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles test -Analyze`,
with log `.local/p416-stage-b1/67912ea1272b4bf6bf1360a7e8e8add8/tests.log`.
It was dispatched before the final cursor correction/new pagination file and
did not include the added pagination case. The separate final 48-test invocation
verifies the complete final Application and owner-port integration after that
correction, including pagination; the other changed runtime ports were stable
through the broad run. Counts are per invocation and must not be summed as unique
test cases. Both disposable test containers were removed successfully.

## Complete local change inventory

Modified tracked paths:

1. `apps/server/lib/src/identity/employee_links.dart`
2. `apps/server/lib/src/platform/audit_repository.dart`
3. `apps/server/lib/src/platform/platform_database.dart`
4. `apps/server/lib/src/workforce/shift_handoff_claim_repository.dart`
5. `apps/server/lib/src/workforce/shift_handoff_claim_service.dart`
6. `apps/server/lib/src/workforce/shift_repository.dart`
7. `apps/server/lib/src/workforce/shift_swap_repository.dart`
8. `apps/server/lib/src/workforce/shift_swap_service.dart`
9. `apps/server/lib/src/workforce/workforce_service.dart`
10. `docs/HANDOVER.md` (new current-stage section only)
11. `docs/roadmap/status.md` (new current-stage section only)

New untracked paths:

1. `apps/server/lib/src/application/shift_swap_application.dart`
2. `apps/server/test/shift_swap_application_fixture.dart`
3. `apps/server/test/shift_swap_application_test.dart`
4. `apps/server/test/shift_swap_application_safety_test.dart`
5. `apps/server/test/shift_swap_application_guidance_test.dart`
6. `apps/server/test/shift_swap_application_clock_test.dart`
7. `scripts/workforce/Run-P416StageB1Checks.ps1`
8. `docs/development/phase-4-16-stage-b1.md`
9. `apps/server/test/shift_swap_application_pagination_test.dart`

## Deviations, remaining work and stopping boundary

The only dependency moved forward is the fixed permission registry plus its
necessary minimized audit allowlist support. No new architectural decision or
schema change was necessary. History is a bounded typed internal operation;
HTTP pagination, endpoint errors, parser 413/415 and OpenAPI parity are still
Steps 6–7 work. No API delivery is inferred from internal tests.

Remaining: Step 6 HTTP/composition and complete permission/API/audit tests;
Step 7 generated OpenAPI; Steps 8–9 Flutter/data/controller/UI and actual browser
journeys; Step 10 expanded isolated recovery acceptance. P4.15 qualifications and
operator/privacy/retention/device readiness boundaries remain unchanged.

Final inventory: exactly 20 changed/new paths above. HEAD/main/origin/main remain
at the initial integrated SHA; the original Stage A branch tip is unchanged.
Git whitespace checks pass, the index is empty, and all historical migrations,
lockfiles, Stage A evidence, approved contract/plan and ADRs have empty diffs.

All implementation stays local and uncommitted with an empty index. The required
next action is **independent adversarial Stage B1 review**, particularly current
authorization before replay, immutable consent, both shared claims, exact paired
effects, guidance/final-roster scope and deferred rollback/time enforcement.
Do not proceed to B2, publication, Security approval or P4.16 DONE/CLOSED from
this handoff.

## F01 investigation — 2026-10-14

The independent review completed on 2026-10-14 with verdict **STAGE B1 CHANGES
REQUIRED**, with one LOW functional finding, F01. The complete report remains at
`C:\Users\Robin\AppData\Local\Temp\storeos-p416-b1-review-8c8ea68b75c343c98c30fdce84c49a66\StoreOS-P416-Stage-B1-independent-review.md`.
Its prior 131 selected server passes, 141 additional repository passes, 362
contract passes and 28 passing independent probes remain historical evidence;
the two failing clock probes remain required findings, not passing acceptance.
No independent approval or closure is claimed here.

### Preserved baseline and changed-file inventory

Before any edit, branch was `codex/p416-stage-b1-swap-orchestration`, HEAD was
`525abb7c975d08d8c93aeca3ac72e58ccbb38ce3`, index was empty, and the exact original
20-path inventory above was present (11 tracked modifications, 9 untracked files).
The reviewed 20 files were copied byte-for-byte into ignored local storage:
`.local/p416-stage-b1-f01/137024f6691a4408b240aa10d8179fda/reviewed-snapshot`.
The same directory contains `tracked.patch` and `before-remediation.json`, with
SHA-256 values for all 20 B1 files and all 28 migrations. Manifest SHA-256:
`C8910441FCA4C5E64CB8563BB341A7CFCEBDE64AED2965D4071DD5A1C84D1090`.

The only repository-visible edit made by this investigation is this handoff.
No Application, owner port, repository test, harness, contract, lockfile, migration,
HTTP or Flutter source changed. Diagnostic probe files are ignored artifacts
inside the same `.local/p416-stage-b1-f01/137024f6691a4408b240aa10d8179fda`
directory: `capture_metadata_test.dart`, `discriminator_test.dart` and
`rollback_uuid_test.dart`. The independent report and original probes were not
modified. The original 20-path Git inventory and empty index remain intact.

### Confirmed exception path and attempted discriminator

Both original independent probes were executed against the reviewed bytes before
any repository-visible edit. An observed advisory-lock waiter inside
`swap_leg_guard()` proves the command reached leg persistence. The barrier was
released only after `SELECT clock_timestamp()` reached the captured start.
Request's A leg INSERT and offer's B leg INSERT both failed immediately in that
BEFORE INSERT trigger. This is neither a deferred constraint failure nor a commit
failure. `PlatformDatabase.runAuthorized` / `Pool.runTx` rolls back the whole
authorized transaction before `_run` classifies the propagated `ServerException`.

Raw restricted-role owner-port probes confirmed the same metadata for both legs:

- SQLSTATE `23514`; message `Exact pristine swap leg required`.
- `constraintName`, `schemaName` and `tableName` are null.
- `routineName` is `exec_stmt_raise`.
- Trace is `PL/pgSQL function <fixture_schema>.swap_leg_guard() line 19 at RAISE`.

The `_run` handler recognizes the separate `swap_approval_future` constraint,
known uniqueness conflicts and published overlap. This immediate composite leg
exception has none of those markers and correctly reaches its generic integrity
fallback, resulting in the reported `500/internal_error`. The intended expiry
contract remains exactly `422/shift_not_swappable`.

A candidate Application-only discriminator was investigated without changing
runtime code: wrap only the specific request/offer leg INSERT in a savepoint,
restore that savepoint after the exception, validate the exact parent, Shift and
pristine ordered work through existing public ports, then compare the captured
start with PostgreSQL time. This avoids querying an aborted transaction, retains
the Company lock and does not retry a mutation. It is nevertheless insufficient.

Six controlled counterexamples independently combined expiry with a malformed
rejected leg: request and offer, each with an incorrect source version, changed
end interval or invalid immutable work-reference title. A fixture-only earlier
BEFORE INSERT trigger altered the rejected NEW tuple; the production composite
guard and all its predicates were retained. Every case produced exactly the raw
metadata above. After `ROLLBACK TO SAVEPOINT`, the parent and Shift were identical
to their captured values, Tasks `validateSwapWork` and `captureSwapWork` passed
with exact original references, and database time was expired. The malformed NEW
tuple left no persisted evidence available to those reads. Every outer transaction
then rolled back with the complete pre-command durable snapshot unchanged.

Consequently, checking the specific insert/function/message plus database expiry
and valid post-savepoint owner evidence would misclassify these integrity defects
as ordinary eligibility failures. Neither a new authorized read after full rollback
nor Dart wall-clock time supplies the missing rejected-row/error distinction.
No broad `23514`/message mapping, savepoint translator, exception framework or
automatic mutation retry was installed.

### Before/after behavior, rollback and operation identity

| Command | Required expiry result | Reproduced before | After investigation |
| --- | --- | --- | --- |
| Request | `422/shift_not_swappable` | `500/internal_error`; complete snapshot restored | Unchanged; no safe authorized fix applied |
| Offer | `422/shift_not_swappable` | `500/internal_error`; REQUESTED/1, A leg/claim retained exactly | Unchanged; no safe authorized fix applied |

Separate characterization probes verified complete durable hashes before any
response assertion, including requests/legs, shared claims, swap/transfer receipts,
Shift/Task/execution/lineage evidence and audit. Request retained no attempted
request/A leg/A claim/receipt/audit; offer retained no B leg/B claim/B consent,
OFFERED transition, receipt or audit. Generic response text remained
`Swap database operation failed.` with no SQL or employee details.

Both failed operation UUIDs were demonstrably reusable by explicit authorized
commands: A reused the failed request UUID for a fresh future own Shift and new
request; B reused the failed offer UUID for decline of the retained REQUESTED/1
invitation. Both succeeded without replay. These are explicit subsequent commands,
not an automatic retry of expired work. The original review probes still assert
422 and still fail; the characterization assertions do not replace or weaken them.

### Executed checks and exact evidence

Pinned Dart 3.13.4, disposable `postgres:17-alpine`, actual restricted `storeos`
runtime role. Schema installation, observed barriers/corruption fixtures and
snapshot reads used owner credentials only in isolated `_test` databases.
Application/owner-port commands ran through the restricted pool. All four test
containers were removed and all eight secret files were verified blank. One
earlier startup attempt ran no tests because Docker was stopped; its generated
secret files were also blanked. Docker Desktop was then started in the background.

All four test invocations used the existing repository harness, from PowerShell
at `C:\dev\storeos`:

```powershell
& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @($probe)
```

Each exact `$probe` and completed log is recorded below. Relative paths are from
the repository root; `artifact/` abbreviates only
`.local/p416-stage-b1-f01/137024f6691a4408b240aa10d8179fda/` in this table.

| Probe | Completed result | Log under `.local/p416-stage-b1/` |
| --- | --- | --- |
| Original `C:/Users/Robin/AppData/Local/Temp/storeos-p416-b1-review-8c8ea68b75c343c98c30fdce84c49a66/late_capture_test.dart` | 0 PASS / 2 FAIL / 0 SKIP; both required 422 assertions failed with actual 500; both rollback assertions passed; exit 1 | `eefe5cd02f0d4a7884aaf35c97e33c55/tests.log` |
| `artifact/capture_metadata_test.dart` | 2 PASS / 0 FAIL / 0 SKIP; exit 0 | `10122f08485149fca4f4bcdd58918998/tests.log` |
| `artifact/discriminator_test.dart` | 6 PASS / 0 FAIL / 0 SKIP; ambiguity/counterexample assertions, not remediation acceptance; exit 0 | `d1ad59c5335244d1831dc4c91ab2a099/tests.log` |
| `artifact/rollback_uuid_test.dart` | 2 PASS / 0 FAIL / 0 SKIP; current 500 characterization, complete rollback, bounded message and explicit UUID reuse; exit 0 | `d5ebdeead506425ca9c30c80d61c6376/tests.log` |

From `apps/server`, the pinned
`C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe analyze --fatal-infos`
completed with no issues, exit 0. The same executable with
`format --output=none --set-exit-if-changed lib test` completed with 224 files,
0 changed, exit 0. `git diff --check` passed. These completions are recorded in
the investigation command output; they are not additional test invocations.
Counts from separate invocations must not be summed as unique coverage.

No post-fix lifecycle, shared-claim, P4.11, Stage A F01–F03, replay or paired/final
approval regression run is claimed: no fix exists under the authorized boundary.
The earlier implementation/reviewer results retain their original scope. In
particular, no new late-approval result or CONFIRMED/3-with-two-claims assertion
was executed here, and its deferred `swap_approval_future` mapping is unchanged.
No Flutter, contracts, recovery, browser, Web build or unrelated broad suite was
repeated. No passing probe above establishes that F01 is remediated.

### Limitation and stopping boundary

**F01 is open; STAGE B1 CHANGES REQUIRED is preserved.** A safe database contract
needs to distinguish the clock condition from every malformed-leg condition,
including simultaneous expiry and malformed evidence. The minimal next proposal
is a separately authorized forward migration that preserves all non-time checks,
rejects those integrity defects first, and raises a distinct named clock constraint
only for an otherwise valid expired leg, followed by a narrowly scoped Application
mapping and the required regressions. Applied migrations 0001–0028 must remain
immutable; the deferred manager-approval clock contract must remain intact.

The owner's remediation request explicitly forbids new migrations and instructs:
"If safe classification truly requires broader schema changes, stop and report
the limitation instead of silently modifying Stage A." This investigation stops
at that boundary. No STAGE B1 APPROVE, F01 closure or independent targeted
re-review readiness is asserted. Further implementation requires revised schema
authorization; after an implemented and verified fix, independent targeted B1
re-review remains mandatory before any separately authorized commit. All work
remains local and uncommitted, index empty; no push, merge, rebase, deployment or
B2 implementation occurred. P4.16 remains IN PROGRESS.

## F01 forward-migration remediation — 2026-10-14

The owner subsequently authorized one new forward-only migration for F01, the
small corresponding Application mapping, rigorous tests, necessary exact migration
inventory updates and both existing encrypted recovery acceptance wrappers. This
supersedes the preceding no-migration stopping boundary for F01 only. The original
independent CHANGES REQUIRED verdict and the unsuccessful Application-only
investigation above are retained. No STAGE B1 APPROVE is asserted.

### Database marker and Application discriminator

Migration `0029_swap_leg_future_error.sql` is the next available migration after
0028. Its only DDL is `CREATE OR REPLACE FUNCTION ...swap_leg_guard()`. It retains
the complete original parent/ownership, published state, version/interval,
replacement-null, lifecycle, exact Tasks references and pristine Tasks predicates,
and the original UPDATE/DELETE/replacement binding branches. The original
`clock_timestamp() >= NEW.starts_at` condition now follows the combined non-time
integrity check and raises SQLSTATE **23514**, constraint metadata
**`swap_leg_future`**, for an otherwise valid expired leg.

The clock marker additionally requires a valid `a`/`b` leg label and the existing
parent/Shift scoped ownership tuple. Invalid labels and scoped FK tuples reach
their existing table checks/FKs/uniqueness errors; the migration neither removes
nor replaces those constraints. A direct negative probe first demonstrated that
an invalid B leg label would otherwise be hidden by the new clock marker. This
qualification preserves its original integrity classification. The six preceding
version/interval/reference counterexamples still fail the original non-time guard
before the clock marker, even when time has passed.

No table, column, index, trigger, grant, owner change or SECURITY DEFINER function
was added. The trigger still covers INSERT/UPDATE/DELETE in its caller's authorized
transaction. MigrationRunner needs no change: its existing 0028 grant branch is
reapplied without expanding privileges. The separate deferred
`swap_approval_future` guard/function remains unchanged.

`ShiftSwapApplication._run` now receives the command kind only from `command`.
Its new mapping requires **both exact SQLSTATE 23514 and exact constraintName
`swap_leg_future`, in request or offer context**. It returns bounded
`422/shift_not_swappable` after `runAuthorized`/`runTx` has rolled back the
transaction. The existing deferred-approval mapping and all known 409/503/internal
error mappings remain in place. There is no SQL message match, generic 23514
conversion, diagnostic read from an aborted transaction, secondary clock query,
savepoint translator or automatic mutation retry. Current authorization/resource
scope still precedes receipt lookup; accepted exact replay still precedes fresh
business validation. Formatter reflow of the command callback is mechanical.

### PostgreSQL diagnostics, rollback and operation identity

The unchanged independent `late_capture_test.dart` now passes both original
assertions: request and offer each changed from **500/internal_error** to
**422/shift_not_swappable**, with complete rollback. Its probe/report files were
not edited. The new repository tests use observed advisory-lock waiters at the
guarded write and PostgreSQL time. For offer, only B's counterpart start crosses;
A's captured invitation remains future.

Raw restricted-role owner-port transactions independently inspect actual
`ServerException.code` and `.constraintName`; Application calls then exercise the
same defect with complete durable snapshots checked before response assertions.
Each diagnostic line records SQLSTATE, constraintName, Application status/code and
rollback. The matrix covers both commands, each defect before and after the
captured start, and valid future acceptance plus exact replay:

| Condition | Real PostgreSQL diagnostics | Application result |
| --- | --- | --- |
| Valid leg, start crossed at INSERT | `23514 / swap_leg_future` | `422 / shift_not_swappable` |
| Wrong leg owner | `23514 / null` | `500 / internal_error` |
| Invalid leg label | A: `23514 / null`; B: `23514 / workforce_shift_swap_legs_leg_check` | `500 / internal_error` |
| Wrong scoped original identity | A: `23503 / workforce_shift_swap_legs_source_shift_id_company_id_locat_fkey`; B: `23505 / workforce_shift_swap_legs_company_id_request_id_source_shif_key` | `500 / internal_error` |
| Changed source version or end interval | `23514 / null` | `500 / internal_error` |
| Non-pristine Task execution state | `23514 / null` | `500 / internal_error` |
| Changed immutable work-reference title | `23514 / null` | `500 / internal_error` |
| Malformed shared claim owner shape | `23514 / handoff_owner_shape` | `500 / internal_error` |
| Invalid command receipt | A: `23514 / null`; B: `23514 / swap_command_intent` | `500 / internal_error` |
| Valid future request/offer | No SQL exception; committed normal result | Accepted result and exact no-write replay |

All failing commands restore the full Shift/Task/execution/request/leg/claim/
lineage/receipt/audit/old-transfer hash snapshot. Request leaves no attempted
request/A claim/receipt/audit; offer retains exact REQUESTED/1, its A leg and claim,
with no B leg/claim/consent/transition/receipt/audit. No SQL or employee detail is
included in the bounded failure messages. A real deferred fixture carrying the
same marker during decline is refused as 500 because the command context is
unsupported, with full rollback after transaction completion.

After removing each future integrity fault, the exact failed command body/UUID
succeeds. After genuine expiry, A explicitly reuses its failed UUID for a new
request with a fresh future own Shift; B explicitly reuses its failed offer UUID
for decline of the retained invitation. Neither command is an automatic retry of
expired work. The original successful exact replay paths remain covered.

### Forward migration, preservation and recovery

The starting branch/HEAD/index and original 20-path B1 inventory were reverified.
The ignored evidence directory is
`.local/p416-stage-b1-f01-forward/96e17a3cb0da48029506527fae5738b4`.
Its `before.json` records all 28 original raw migration hashes and 20 starting B1
file hashes; `handoff-before.md` preserves the prior handoff. The earlier complete
reviewed snapshot above is retained. All 0001–0028 raw SHA-256 values still match.
New migration 0029 SHA-256:
`BF49918DB80A1509BB3A6B60536651D497304F2749078DE5D78FCBCF75BE1567`.

Fresh 0001–0029 tests check all 29 database version/checksum pairs against actual
repository bytes, idempotence, restricted privileges and real paired approval.
The populated 0028 fixture retains CONFIRMED/3, both claims, receipts and all
business-table hashes. It injects failure after function replacement and,
separately, during schema_migrations AFTER INSERT bookkeeping; both restore the
old function definition, exact migration ledger and business evidence. Successful
0029 application changes only the intended function body: function OID/owner/
security/ACL, all relation/trigger identities and definitions, and complete runtime
column grants remain exact. The deferred approval function is byte-identical in
PostgreSQL; historical offer replay and subsequent approval succeed. Existing
actual populated 0027 tests now require exactly 0028 then 0029, retaining P4.11
active/stale backfill, historical replay and Stage A adversarial refusals.

The update/recovery fixture's exact pending-list comparison is retained and
extended through 0029. Both existing acceptance wrappers ran successfully in
the explicitly verified disposable Compose project
`storeos-p416-f01-recovery-086566c054b74707`, loopback port 61157 and synthetic
foundation database `storeos_p416_f01_recovery_086566c054b74707_test`.
No operational database or normally served assets were used. Reports:

- `.local/backup-acceptance/0b8cd7d1d2b949f4/report.json`: PASS; encrypted latest-chain
  dump/isolated restore, matching evidence, fencing, corruption rejection and
  exact P4.11 active claims. All acceptance databases removed.
- `.local/update-recovery/d162027b9880475d/report.json`: PASS; exactly 19 pending
  migrations 0011–0029, 29 versions/checksums matching repository, empty second run,
  preserved projections and restricted-role HTTP smoke. Encrypted pre-update
  restore is independently fenced at exactly 0010 and leaves the upgraded source
  independent. Both acceptance databases removed.

Wrapper logs are `backup-wrapper.log` and `update-wrapper.log` in the evidence
directory. The temporary Compose container, volume and network were removed after
checking their exact project ownership labels. Both existing redaction checks
passed. These are the existing recovery acceptance contracts across the new schema
chain; they do not establish the still-outstanding complete swap-inclusive Step 10
recovery or swap HTTP/Flutter acceptance.

Automatic approval review rejected an initial invocation of a historical recovery
launcher before execution because disposable targeting was insufficiently
established. Read-only Compose configuration/resource checks then proved exact
new project/volume/port identities. The current repository wrappers ran directly
with verified container labels in that new project. No rejected action or
operational database target was used.

### Verification completion record

The final seven-file B1 selection completed **91 PASS / 0 FAIL / 0 SKIP**, process
exit 0. It includes the original 48 B1 tests and 43 new F01/migration cases, with
server analyzer no issues. Command from the repository root:
`& ./scripts/workforce/Run-P416StageB1Checks.ps1 -Analyze`.
Log: `.local/p416-stage-b1/2d9d23467f3343a5ada45dc463d3f0cb/tests.log`.
Both original deferred approval clock/execution/replay tests passed: late approval
restores CONFIRMED/3 and both claims; accepted historical replay/execution remains
valid.

The full server suite completed **934 PASS / 0 FAIL / 21 explicit opt-in SKIP**,
process exit 0, in 18m55s, with server analyzer no issues. Command from the root:
`& ./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test') -Analyze`.
Log: `.local/p416-stage-b1/99a0ace6d1b74055ad312bf9d928f965/tests.log`.
This includes the final F01 matrix, fresh/populated migration tests, actual
0027→0028→0029 preservation/backfill/P4.11 historical replay, Stage A F01–F03,
shared transfer/swap claims and ordinary Shift/Task/guidance regressions. The
final two scope-fixture expectations were corrected before this suite loaded
that file; its real SQL diagnostics and zero-failure completion verify them.
All runtime/migration bytes were already stable when the run was dispatched.
Counts from separate invocations overlap and must not be added as unique tests.

The full invocation's 21 skips retain the existing opt-in scope listed earlier:
quantity Flutter/Chrome/encrypted recovery (3), Knowledge Chrome (1), preparation
assignment Flutter/Chrome/encrypted recovery (3), preparation batch Flutter/Chrome
(2), Purchasing Flutter/Chrome (2), delivery encrypted recovery (1), order encrypted
recovery (1), Recipe Flutter/Chrome (2), P4.11 transfer Flutter/Chrome (2), Stock
count Flutter/Chrome (2), Task Knowledge Chrome (1) and Task Planogram Chrome (1).
The exact 21 case names and reasons are retained in
`full-server-skips.json` in the evidence directory. The four historical encrypted
migration/recovery opt-in test files were skipped in this invocation; the two
general encrypted acceptance wrappers above were separately executed and passed.
No swap HTTP/OpenAPI/Flutter/browser journey, new Web build or complete P4.16
Step 10 recovery acceptance is claimed. Client source/contracts/dependencies
remain unchanged, so no new standalone Flutter/design-system suite was needed.

API contracts completed **362 PASS / 0 FAIL / 0 SKIP**, process exit 0, with analyzer
no issues. Its authorized log is `contracts-authorized.log` in the evidence
directory. From `packages/api_contracts`, the pinned Dart executable invoked
`--packages=.dart_tool/package_config.json <cached-test-package>/bin/test.dart test --reporter expanded`,
then `analyze --fatal-infos`. A prior sandbox invocation
failed all 34 file loads because the compiler temporary directory was denied;
it executed no acceptance cases (`contracts.log`).

The unchanged independent clock probes completed **2 PASS / 0 FAIL / 0 SKIP**,
process exit 0, after the fix; the prior 0 PASS / 2 FAIL record above retains the
before evidence. Command: the same B1 harness with `-TestFiles` containing the
absolute original `late_capture_test.dart` path recorded above. After log:
`.local/p416-stage-b1/7c2c3744f17f4400ad656522eb4c74eb/tests.log`.
Intermediate runs are preserved, not relabeled: first matrix 29 PASS / 4 fixture
FAIL; invalid B leg-label probe 0 PASS / 1 FAIL before narrowing the clock marker;
first migration selection 11 PASS / 1 catalog-serialization FAIL; corrected matrix
41 PASS / 2 scope-fixture expectation FAIL. The non-pristine fixture was corrected
to a valid SQL execution transition; catalog OIDs were cast to text; the B scope
fixture's pre-existing uniqueness failure takes precedence over its FK, so its
exact expected SQLSTATE is 23505. Assertions remain strict. One analyzer-only
attempt stopped before tests on a new fixture's missing braces. A redaction
invocation wrapper misread stale LASTEXITCODE from an intentional negative child
probe; fresh PowerShell processes for both redaction scripts completed exit 0.

Intermediate logs under `.local/p416-stage-b1/`, respectively:
`0eda4af4d2464c63889c6788a67f68e4/tests.log`,
`009dbcea925944559041283d1d7b9efe/tests.log`,
`465685ac77f0435abac53d4b44115d02/tests.log`, and
`5aea85657a10435592a2338e6280cccd/tests.log`.
All four completed with exit 1 and 0 SKIP; they are diagnostic/draft evidence.

Both recovery commands invoked the current repository scripts directly:
`& ./scripts/backup/Run-BackupRestoreAcceptance.ps1 -SkipPackageResolution -DartPath <pinned-dart>`
and
`& ./scripts/update/Run-UpdateRecoveryAcceptance.ps1 -SkipPackageResolution -DartPath <pinned-dart>`.
The validated project/port/database from `recovery-context.json` were set explicitly
in each process, with current container project labels checked before execution.
Both wrappers completed exit 0. The exact per-wrapper step/cleanup results are in
the sanitized reports above. Both redaction scripts were run with
`pwsh -NoProfile -File` and completed exit 0.

All verification uses pinned Dart 3.13.4, unchanged dependencies and disposable
PostgreSQL **17.11** (`postgres:17-alpine`, image
`sha256:b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24`)
with the restricted `storeos` runtime role. Owners install schema/
barrier/fault fixtures and read snapshots, rather than execute Application commands.
No unexecuted optional journey is reported PASS.

Pinned non-writing formatting across server lib/test/tool and contract lib/test
completed with **303 files / 0 changed**, exit 0. `git diff --check` and the B1
PowerShell harness parser passed. Existing historical migrations and all dependency
lockfiles retain empty Git diffs. All disposable B1 test containers were removed;
their generated secret files were blanked. Existing recovery secrets were used
read-only and never printed or modified. Final raw-hash and Git checks are recorded
in the evidence directory alongside this handoff.

### Exact F01 change inventory

The following 34 paths differ from the start of this forward-migration task.
The 27 existing test fixtures and one recovery tool change only their necessary
exact migration sequence/final version/count (and that tool's final-version
comments); assertions are not loosened. No migration runner or owner port changes
were needed. The three new files are 0029 and the two focused test files.

```text
apps/server/lib/src/application/shift_swap_application.dart
apps/server/migrations/0029_swap_leg_future_error.sql
apps/server/test/shift_swap_future_error_test.dart
apps/server/test/shift_swap_future_migration_test.dart
scripts/workforce/Run-P416StageB1Checks.ps1
docs/development/phase-4-16-stage-b1.md
apps/server/tool/update_recovery_fixture.dart
apps/server/test/article_integration_test.dart
apps/server/test/article_quantity_upgrade_recovery_test.dart
apps/server/test/backup_recovery_regression_test.dart
apps/server/test/knowledge_integration_test.dart
apps/server/test/merchandising_integration_test.dart
apps/server/test/postgres_integration_test.dart
apps/server/test/preparation_assignment_upgrade_recovery_test.dart
apps/server/test/purchasing_delivery_safety_test.dart
apps/server/test/purchasing_delivery_upgrade_recovery_test.dart
apps/server/test/purchasing_test.dart
apps/server/test/purchasing_upgrade_recovery_test.dart
apps/server/test/recipe_integration_test.dart
apps/server/test/shift_amendment_integration_cases.dart
apps/server/test/shift_cancellation_integration_cases.dart
apps/server/test/shift_handoff_claim_test.dart
apps/server/test/shift_integration_test.dart
apps/server/test/shift_swap_migration_test.dart
apps/server/test/shift_swap_review_regression_test.dart
apps/server/test/stock_count_integration_test.dart
apps/server/test/stock_integration_test.dart
apps/server/test/task_blocking_integration_cases.dart
apps/server/test/task_cancellation_integration_cases.dart
apps/server/test/task_execution_integration_cases.dart
apps/server/test/task_knowledge_integration_test.dart
apps/server/test/task_numeric_integration_cases.dart
apps/server/test/task_planogram_integration_test.dart
apps/server/test/task_template_integration_test.dart
```

The complete working tree is the union of these changes and the original 20-path
B1 inventory above: 51 paths (39 tracked modifications and 12 untracked files).
The other 17 original B1 paths remain byte-identical to the starting snapshot.
All work remains local and uncommitted; no stage/commit/push/merge/rebase/deployment
or B2 implementation is authorized or performed.

### Final boundary

**F01 is fixed locally, with the exact 23514 / swap_leg_future request/offer
discriminator verified in PostgreSQL and all required local checks complete.**
The historical independent verdict remains **STAGE B1 CHANGES REQUIRED** until a
new independent targeted F01 re-review assesses these changed bytes. This handoff
does not self-declare STAGE B1 APPROVE, Security approval or full P4.16 completion.
Branch remains `codex/p416-stage-b1-swap-orchestration`, HEAD remains
`525abb7c975d08d8c93aeca3ac72e58ccbb38ce3`, and the index is empty. P4.16 remains
IN PROGRESS. Stop here: the next action is independent targeted F01 re-review,
with no stage/commit/publication or Stage B2 work.

## Independent approval and local finalization — 2026-10-14

The subsequent independent targeted re-review returned **STAGE B1 APPROVE**,
**F01 CLOSED**, with no new blocking findings. This combines the unchanged
portions of the original complete B1 review with targeted verification of the
forward-migration remediation. The original CHANGES REQUIRED verdict, unsafe
Application-only investigation, six masking counterexamples and dated remediation
records above remain intact. Earlier pending-review and no-commit statements
describe their historical authorization boundaries; this owner instruction
supersedes them only for exactly one local B1 implementation commit.

Complete independent report:
`C:\Users\Robin\AppData\Local\Temp\storeos-p416-b1-f01-rereview-f74d8994a0b648a8af45f98c25866b61\StoreOS-P416-Stage-B1-F01-targeted-re-review.md`.
Its `before-review.json` and `after-review.json` contain the exact approved raw
hashes. Before finalization, all **79 SHA-256 values** matched: all 51 implementation
paths plus all 28 historical migrations. The exact inventory was 39 tracked
modifications and 12 untracked files, index empty, on
`codex/p416-stage-b1-swap-orchestration` at parent
`525abb7c975d08d8c93aeca3ac72e58ccbb38ce3`. A live read-only `git ls-remote` verified
remote main at that exact SHA and no remote B1 branch. Stage A is integrated on
main; its F01–F03 protections and migrations 0001–0028 remain unchanged.

The independent reviewer executed, with pinned Dart and disposable restricted-role
PostgreSQL, **71 targeted tests PASS**, **25 independent probes PASS** (24 masking/
NULL/marker/context/prefix probes and one complete catalog/dependency/ACL probe),
and **34 strict swap contract tests PASS**, all with 0 FAIL / 0 SKIP. It also
verified the unchanged original clock probes, exact marker exclusivity, all six
historical counterexamples, complete rollback, explicit failed UUID reuse, fresh
and populated upgrades, ledger/checksum failure refusals, preserved privileges,
Stage A F01–F03, P4.11 guidance/claims/replay and deferred paired approval. The
author's completed **934 PASS / 0 FAIL / 21 opt-in SKIP** server run, **91 focused
PASS**, **362 contract PASS** and both encrypted recovery reports were inspected
and reconciled. The general recovery wrappers were not needlessly rerun by the
reviewer. Counts overlap and are not additive unique coverage.

The finalization task introduces **no runtime, migration, test, fixture, harness,
permission or audit edit** after independent approval. Only this handoff records
the supplied approval and local commit boundary. Migration 0029 remains raw
SHA-256 `BF49918DB80A1509BB3A6B60536651D497304F2749078DE5D78FCBCF75BE1567`;
its database marker remains exact **23514 / swap_leg_future**, mapped only for
request/offer to **422 / shift_not_swappable**. The existing deferred
`swap_approval_future` contract and all unrelated integrity/conflict mappings
remain unchanged. The four fixed swap capabilities and two minimized audit
identifier keys are the only Step 6 prerequisites moved into B1.

The commit scope is explicitly the following **51 files**. Local logs, reports,
review exports, fixture caches, credentials, environment files and ignored generated
artifacts are excluded. Staging uses these exact paths, never `git add -A`.

```text
apps/server/lib/src/application/shift_swap_application.dart
apps/server/lib/src/identity/employee_links.dart
apps/server/lib/src/platform/audit_repository.dart
apps/server/lib/src/platform/platform_database.dart
apps/server/lib/src/workforce/shift_handoff_claim_repository.dart
apps/server/lib/src/workforce/shift_handoff_claim_service.dart
apps/server/lib/src/workforce/shift_repository.dart
apps/server/lib/src/workforce/shift_swap_repository.dart
apps/server/lib/src/workforce/shift_swap_service.dart
apps/server/lib/src/workforce/workforce_service.dart
apps/server/migrations/0029_swap_leg_future_error.sql
apps/server/test/article_integration_test.dart
apps/server/test/article_quantity_upgrade_recovery_test.dart
apps/server/test/backup_recovery_regression_test.dart
apps/server/test/knowledge_integration_test.dart
apps/server/test/merchandising_integration_test.dart
apps/server/test/postgres_integration_test.dart
apps/server/test/preparation_assignment_upgrade_recovery_test.dart
apps/server/test/purchasing_delivery_safety_test.dart
apps/server/test/purchasing_delivery_upgrade_recovery_test.dart
apps/server/test/purchasing_test.dart
apps/server/test/purchasing_upgrade_recovery_test.dart
apps/server/test/recipe_integration_test.dart
apps/server/test/shift_amendment_integration_cases.dart
apps/server/test/shift_cancellation_integration_cases.dart
apps/server/test/shift_handoff_claim_test.dart
apps/server/test/shift_integration_test.dart
apps/server/test/shift_swap_application_clock_test.dart
apps/server/test/shift_swap_application_fixture.dart
apps/server/test/shift_swap_application_guidance_test.dart
apps/server/test/shift_swap_application_pagination_test.dart
apps/server/test/shift_swap_application_safety_test.dart
apps/server/test/shift_swap_application_test.dart
apps/server/test/shift_swap_future_error_test.dart
apps/server/test/shift_swap_future_migration_test.dart
apps/server/test/shift_swap_migration_test.dart
apps/server/test/shift_swap_review_regression_test.dart
apps/server/test/stock_count_integration_test.dart
apps/server/test/stock_integration_test.dart
apps/server/test/task_blocking_integration_cases.dart
apps/server/test/task_cancellation_integration_cases.dart
apps/server/test/task_execution_integration_cases.dart
apps/server/test/task_knowledge_integration_test.dart
apps/server/test/task_numeric_integration_cases.dart
apps/server/test/task_planogram_integration_test.dart
apps/server/test/task_template_integration_test.dart
apps/server/tool/update_recovery_fixture.dart
docs/HANDOVER.md
docs/development/phase-4-16-stage-b1.md
docs/roadmap/status.md
scripts/workforce/Run-P416StageB1Checks.ps1
```

The finalized handoff accompanies the owner-authorized local implementation
commit, with message `Implement P4.16 Stage B1 swap orchestration`. Its exact SHA,
parent and complete committed inventory are recorded by Git and in the final
delivery response. Finalization evidence, including the approved-hash comparison
and the only post-approval documentation diff, is retained under ignored
`.local/p416-stage-b1-finalization/b6cbec6ffa3a4d969378ea50cf6ea480`.
No active Git hooks were configured. Source/test re-execution is unnecessary for
this documentation-only finalization; the approved implementation bytes and
completed verification above remain the acceptance evidence. Non-writing format,
whitespace, staged-inventory and post-commit blob/hash checks are the finalization
checks. No migration 0001–0028 may enter the staged diff.

All **21 opt-in skips** retain their exact case/reason list and qualifications
recorded above. The general backup/update wrapper passes do not convert the four
historical encrypted-recovery opt-in files into executions. No full P4.16 functional
or Security approval, swap HTTP/OpenAPI/Flutter/browser acceptance, remote B1 CI,
push, PR, merge or deployment is claimed.

After the local commit and clean-tree/index verification, B1 is ready for a
**separately authorized non-force push and Draft PR**. Steps 6–10 remain outside
this commit: swap HTTP/composition/error/parser/history tests and API audit
coverage; generated OpenAPI parity; Flutter data/controllers and session-fenced
pending intents; employee/manager surfaces and real browser journeys; expanded
swap-inclusive encrypted/fenced recovery and final functional/Security acceptance.
Only the bounded fixed permissions/minimized audit prerequisites are already in
B1. P4.16 remains **IN PROGRESS**. Stop after exactly one local commit; no Stage B2
work or publication is authorized by this finalization.
