# P4.16 Stage A — local implementation handoff

Date: 2026-10-13. **Stage A independently approved; this snapshot is the owner-authorized local implementation commit.**
This implements the separately owner-authorized Steps 1–4 of the
[implementation plan](phase-4-16-implementation-plan.md).
Full P4.16 remains incomplete; Steps 5–10 are unimplemented and unauthorized.
The original implementation review required changes for F01–F03. The targeted
independent re-review returned **STAGE A APPROVE**, with all three findings CLOSED
and no new findings. This approves Steps 1–4 only. Full Security acceptance,
exact implementation CI, publication and P4.16 closure remain unclaimed.
ADR 0030 and the selected consent protocol are unchanged.

## Independent approval and local commit finalization — 2026-10-13

The owner supplied `StoreOS-P416-Stage-A-targeted-re-review.md` after the original
`StoreOS-P416-Stage-A-review.md`. Finalization read both complete reports and
matched every one of the reviewed 60 file paths and SHA-256 values before edits.
The independent verdict closes F01 HIGH (new replacement provenance), F02 MEDIUM
(strict persisted receipt/replay) and F03 LOW (exact terminal kind). P4.11
compatibility, shared claim integrity, populated upgrade/backfill/rollback and
P4.15 preservation are approved within Stage A's existing scope and threat boundary.

| Independent targeted execution | Result |
| --- | --- |
| Focused PostgreSQL/P4.11 regression, ten files, actual restricted role | **114 PASS / 0 FAIL / 0 SKIP**; server analyzer clean. |
| Additional independent probes | **5 PASS / 0 FAIL / 0 SKIP**; 332 SQL/Dart timestamp cases, copied/retrofit provenance refusal, optional receipt fields, all eight command-family exact replays, schema-4 Knowledge/Planogram paired content. |
| Bounded PostgreSQL dump/restore | **1 PASS**; preserved tables/origins/receipts, repeat empty migration, strict replay and restored origin refusal. |
| Full API contracts and analyzer | **362 PASS / 0 FAIL / 0 SKIP**; no issues. |
| Four package format checks, source hashes/inventory, historical SQL Git blobs and whitespace | **PASS**. |

The independent reviewer inspected the actual broader 842/362/425/2 test logs,
P4.11 controller/Chrome, analyzer and isolated Web build evidence below rather than
repeating expensive unaffected suites. These are preserved executed results, not
new finalization runs or additive unique coverage. The unchanged original external
seven-probe harness now has **4 PASS and 3 expected obsolete acceptance-assertion
failures**: F01/F02 are refused by SQL and F03 throws FormatException. These remain
identifiable historical counterexamples; committed regression tests require the
correct rejection/rollback and valid-state success and passed independently.

Finalization fetches origin without merging/rebasing and verifies remote main
remains `3b2d66f07ef7f261a74e922e32cbe656d8998837`. The local commit has this exact
parent on `codex/p416-bilateral-shift-swaps` and the 60-path inventory below.
Only this handoff, HANDOVER and actual status change from the approved re-review
snapshot, to record its verdict/evidence and local commit authorization. All 57
code/test/script paths retain their independently reviewed bytes. Private review
exports, temporary probes, credentials, logs and runtime artifacts stay outside
the commit. Six historical SQL checkout files retain pre-existing CRLF; all 27
Git-normalized SQL blobs are byte-identical to the parent, and all raw checkout
bytes are preserved. No applied migration is edited or normalized.

The final commit SHA, parent, committed paths and clean index/tree are reported
from Git after committing; this file does not embed its own self-referential SHA.
The pre-commit/remediation Git-state notes below retain their historical context.
No push, merge, rebase or deployment is authorized or performed. There is no
Stage B implementation or full P4.16 functional/Security/CI/DONE claim.

The nineteen remaining opt-in cases below retain their unverified browser,
controller or encrypted-recovery claims. The targeted review explicitly confirms
that no additional execution is necessary for bounded Stage A approval. They
remain gates for their named acceptance claims and later full P4.16 acceptance;
the bounded dump smoke does not establish encrypted/fenced Step 10 recovery.

Controlled publication proposal, requiring separate authorization: publish only
this reviewed branch/commit, open a Stage A scoped PR with the preserved evidence
and gaps, verify exact-commit CI, then obtain separate merge/deployment decisions.
Authorize Steps 5–10 separately before implementing the swap coordinator, scoped
discovery/guidance, permissions/audit/HTTP/OpenAPI, Flutter journeys and recovery.

## F01–F03 remediation — 2026-10-13

Authorization covers these three Stage A findings only. The original 55-file
uncommitted implementation was inventoried by SHA-256 before edits and retained.
The seven original external probes were executed unchanged before remediation:
7 observed-outcome checks passed, confirming all three defects as reported, plus
the two B-offer race orders, P4.15 preservation/replay and deferred second-leg
rollback. This was reproduction of defects, not an integrity approval.

### F01: database-owned replacement creation

The original guard checked matching Shift/Task attributes but could not distinguish
two unrelated previously published Shifts from newly created replacement effects.
Both exact matching third Shifts committed as APPROVED/4 without increasing Shift
or Task counts. Application overlap validation alone could not close this gap.

0028 now adds nullable `shifts.swap_request_id` and `swap_leg` provenance, one
scoped leg uniqueness anchor and a reciprocal, deferred scoped FK. The Workforce
replacement port binds a new server-generated ID **before** draft insertion in
the caller's transaction. The leg trigger refuses any already existing Shift ID,
including a draft created earlier in that same transaction. At Shift INSERT the
database derives provenance from that bound leg, requiring a confirmed parent,
exact incoming Employee/Location/interval and draft/version 1. The caller cannot
provide provenance; UPDATE cannot change it. Runtime UPDATE grants exclude both
columns, with a trigger also protecting immutability.

The deferred creation check requires that inserted replacement's parent to be
approved at commit. Existing deferred parent/leg checks and FKs require both
replacement effects and prohibit separately committed allocation/drafts. Fresh
approval explicitly checks each replacement's exact request/leg origin as well as
both original cancellations/version advances, intervals/owners, ordered selections,
complete Tasks and full content equality. Existing immediate Task scope/identity
FKs and immutable Task identities prevent old Tasks from moving into a newly
created Shift. Provenance therefore proves creation within the approval
transaction, without `xmin`, creation timestamps or caller assertions. The final
fresh database clock remains last in the fresh approval validation function.

Restricted-role negatives retain full pre/post hashes of Shifts/selections, Tasks
and execution evidence, requests/legs/receipts, claims/lineage, old P4.11 evidence
and audit. They cover the original two-existing-Shift SQL, one new/one matching
existing Shift, create-before-bind, duplicate/swapped pointers, missing/cross-linked
Tasks, another request's replacement IDs, missing second effects, partial terminal
claim release, foreign Company/Location, supplied origin and early draft commit.
Maximum-20-Task paired approval still commits; later ordinary execution and exact
historical replay retain the existing lifecycle boundary. Historical Shifts receive
NULL provenance; every original column is hashed across migration and the new NULL
columns are asserted separately. No old field is excluded from preservation proof.

### F02: one safely replayable persisted receipt contract

The original SQL copied supplied timestamp JSON values into expected evidence and
used PostgreSQL's permissive timestamptz cast. A space replacing the required `T`
committed but then failed strict Dart replay. The SQL guard now validates each of
requested/offered/confirmed/terminal instants and both legs' starts/ends before
evidence becomes immutable, using the same grammar and semantics as `shiftInstant`:

- Four-digit Gregorian year 0001–9999, real calendar date, literal `T`, HH:mm:ss,
  seconds 00–59, optional 1–6 fractional digits, and explicit uppercase `Z` or
  signed HH:mm offset (hours 00–23, minutes 00–59).
- The resulting UTC instant must remain within years 0001–9999 and equal its
  persisted fact. Offset arithmetic preserves legal protocol offsets that exceed
  PostgreSQL's input-cast offset range.
- Required instants are JSON strings. Absent optional lifecycle facts require an
  explicit JSON null; missing keys, numeric/boolean/object encodings and non-null
  values for absent facts refuse. Accepted strings are retained exactly in the
  immutable result, including supported offset spelling.
- Exact root/request/leg/task/link keys and semantic equality remain enforced by
  the original expected-object comparison. Canonical UUIDs, exact actor/operation,
  lifecycle/version, pair and lineage identities come from persisted owner facts.
  Numeric intent/result fields must have integer JSON representations: JSONB's
  equality of `1` and `1.0` cannot admit a value Dart cannot decode as an integer.
  Retained reasons also match the existing Unicode trim/control bounds.

The timestamp negatives run for **all eight** fields, including the review's exact
space encoding, missing zone, lowercase z, seven fractional digits, wrong type,
null/missing required fields, invalid date/leap second/offset and extra keys.
Each failure restores all hashes and leaves no consumed operation. A corpus checks
SQL/Dart agreement for UTC/positive/negative/zero offsets, fractional precision,
leap years, range boundaries and explicit nulls. Valid offset receipts persist and
replay their exact retained strings without changing evidence. The original failed
request UUID is subsequently accepted and replayed using valid evidence. Dart
parsing was not relaxed and no replacement replay result is fabricated.

### F03: exact terminal result kind

Both withdrawal commands share the withdrawn state; the original parser only
bound that state/version/operation and missed `request.terminalKind` equality.
Every terminal result now requires its outer kind to equal retained terminal kind.
Focused contract cases accept source and recipient withdrawals at every permitted
stage, decline/rejection/approval, and reject every other command kind, including
both contradictory withdrawal directions. P4.11 DTOs are unchanged.

### Remediation verification and review boundary

The final full server rerun passed after all code and affected migration snapshot
corrections. Earlier runs exposed fixture import/setup errors and three legacy
snapshot assertions that treated new NULL column keys as changed old evidence.
Those comparisons now preserve every predecessor field and assert new NULL anchors
separately; assertions were not removed. The final outcomes below supersede those
failed intermediate runs.

| Remediation check | Final outcome |
| --- | --- |
| Complete server, disposable PostgreSQL 17, actual restricted role | **842 PASS / 0 FAIL / 21 opt-in SKIP**; [log](../../.local/p416-remediation/server-final.log). |
| Focused remediation, seven preserved probes, Stage A integrity/claims/clock/migration and affected P4.10/P4.11 migration checks | **61 PASS / 0 FAIL / 0 SKIP**; [log](../../.local/p416-remediation/focused-final.log). |
| Oldest Shift cancellation/amendment populated upgrade comparisons after final snapshot edits | **2 PASS / 0 FAIL / 0 SKIP**; also passed in the final full server run; [log](../../.local/p416-remediation/legacy-projection-final.log). |
| Complete API contracts | **362 PASS / 0 FAIL / 0 SKIP**; [log](../../.local/p416-remediation/api.log). |
| Complete Flutter client | **425 PASS / 0 FAIL / 0 SKIP**; [log](../../.local/p416-remediation/flutter-tests.log). |
| Complete design system | **2 PASS / 0 FAIL / 0 SKIP**; [log](../../.local/p416-remediation/design-tests.log). |
| Existing P4.11 controller/HTTP and actual headless Chrome opt-ins | **2 PASS / 0 FAIL / 0 SKIP**; restart/exact retry and ordinary recipient Guided Work; [log](../../.local/p416-remediation/transfer-optins.log). |
| Bounded PostgreSQL dump/restore of a genuine paired approval into a second disposable database | **1 PASS**; all tables' counts/hashes preserved, 0028 repeat empty, actual restricted-role exact receipt replay unchanged and restored creation guard rejects forged origin; source unchanged; [log](../../.local/p416-remediation/dump-smoke.log). |
| Four analyzers and format checks | **PASS**, no issues; zero changed files (server 237, contracts 65, client 107, design system 5). |
| Isolated Flutter Web release and Compose config / Git diff checks | **PASS**; [build log](../../.local/p416-remediation/web-build.log), output only under `.local/p416-remediation/web-build`. |

The original seven probes ran unchanged before fixing the defects. After fixing,
their preserved repository regressions all passed: existing-Shift substitution now
raises `23514 / swap_replacement_creation` and restores confirmed state/all hashes;
the space timestamp now raises `23514 / swap_command_result`, consumes no UUID and
allows a valid exact retry; the contradictory withdrawal DTO now raises
`FormatException`. Both B-offer race orders, populated P4.15 preservation/replay
and commit-time missing-second-leg refusal still pass. Complete paired creation
and maximum twenty-Task lineage commit successfully; ordinary later execution and
approval replay also pass. There is no application-only substitution workaround.

Counts are per invocation, not additive unique coverage. The final broad run's
21 skips are the original explicit opt-ins listed below; its two P4.11 cases were
subsequently executed successfully in the separate opt-in run. The **nineteen
remaining unexecuted cases** are listed explicitly here:

| Existing file under `apps/server/test/` | Remaining unexecuted journey |
| --- | --- |
| `article_quantity_journey_test.dart` | Flutter controller; actual Chrome (2). |
| `article_quantity_upgrade_recovery_test.dart` | Encrypted quantity migration/recovery (1). |
| `knowledge_browser_test.dart` | Actual Chrome (1). |
| `preparation_assignment_browser_test.dart` | Actual Chrome (1). |
| `preparation_assignment_client_journey_test.dart` | Flutter controller/HTTP (1). |
| `preparation_assignment_upgrade_recovery_test.dart` | Encrypted assignment migration/recovery (1). |
| `preparation_batch_browser_test.dart` | Actual Chrome (1). |
| `preparation_batch_client_journey_test.dart` | Flutter controller/HTTP (1). |
| `purchasing_client_journey_test.dart` | Flutter controller; actual Chrome (2). |
| `purchasing_delivery_upgrade_recovery_test.dart` | Encrypted delivery migration/recovery (1). |
| `purchasing_upgrade_recovery_test.dart` | Encrypted order migration/recovery (1). |
| `recipe_browser_test.dart` | Actual Chrome (1). |
| `recipe_client_journey_test.dart` | Flutter controller/HTTP (1). |
| `stock_count_browser_test.dart` | Actual Chrome (1). |
| `stock_count_client_journey_test.dart` | Flutter controller/HTTP (1). |
| `task_knowledge_browser_test.dart` | Actual Chrome (1). |
| `task_planogram_browser_test.dart` | Actual Chrome (1). |

The four encrypted recovery comparison helpers were updated only for the added
NULL metadata, with original fields preserved and full post-upgrade restore hashes
retained where applicable. Their opt-ins remain unexecuted; the bounded dump/restore
check above does not establish encrypted, fenced swap-inclusive Step 10 acceptance.
No physical-device/accessibility, remote CI, full Security approval or full P4.16
acceptance is claimed. The independent Stage A re-review recorded above supersedes
the remediation's earlier pending-review state. ChromeDriver warned about untested compatibility
with installed Chrome 155; the actual journey passed in that executed environment.
No known remaining F01–F03 defect or contract deviation was identified by these
checks. New provenance refines the approved fresh-creation guarantee; five table
owners and consent/lifecycle policy remain unchanged.

All test-owned containers were removed and generated credential files cleared.
The original 55 paths remain; current inventory is **60 paths: 39 tracked
modifications, 21 untracked files; empty index**. Remediation changes 21 paths;
the other 39 original Stage A paths retain their pre-remediation SHA-256 values.
HEAD/local main/cached origin/main remain
`3b2d66f07ef7f261a74e922e32cbe656d8998837`; no commit/push/merge/deployment.
All 27 historical migration Git blob identities match HEAD. Verification artifacts,
source hashes and the bounded restore probe remain ignored under
`.local/p416-remediation/`; [pre-remediation inventory](../../.local/p416-remediation/before.json)
and [final inventory](../../.local/p416-remediation/final-inventory.json).

The seven review probes are preserved as repository regressions; their SQL/setup
remains, with only the three defect expectations changed to mandatory refusal and
rollback. These local remediation results are accompanied by the separately
executed independent Stage A approval recorded above.
No new architecture/consent policy, sixth table, coordinator, capability/audit
workflow, route, generated OpenAPI or Flutter swap UI was introduced.

Remediation changes exactly these twenty-one files (the complete Stage A inventory
below additionally includes the earlier implementation):

- `apps/server/migrations/0028_bilateral_shift_swaps.sql`
- `apps/server/lib/src/workforce/shift_swap_service.dart`
- `apps/server/test/shift_swap_stage_a_fixture.dart`
- `apps/server/test/shift_swap_migration_test.dart`
- `apps/server/test/preparation_batch_migration_test.dart`
- `apps/server/test/shift_transfer_migration_test.dart`
- `apps/server/test/purchasing_journey_fixture.dart`
- `apps/server/test/purchasing_upgrade_recovery_test.dart`
- `apps/server/test/purchasing_delivery_upgrade_recovery_test.dart`
- `apps/server/test/preparation_assignment_upgrade_recovery_test.dart`
- `apps/server/test/article_quantity_upgrade_recovery_test.dart`
- `apps/server/test/shift_cancellation_integration_cases.dart`
- `apps/server/test/shift_amendment_integration_cases.dart`
- `apps/server/test/shift_integration_test.dart`
- `apps/server/test/shift_swap_review_regression_test.dart` (new)
- `apps/server/test/shift_swap_remediation_test.dart` (new)
- `packages/api_contracts/lib/src/shift_swaps.dart`
- `packages/api_contracts/test/shift_swap_evidence_test.dart`
- `docs/development/phase-4-16-stage-a.md`
- `docs/HANDOVER.md`
- `docs/roadmap/status.md`

The prior handoff below retains its original run counts and evidence limits;
its assertion that no unresolved defect was known was falsified by the independent
review. The remediation section is the current status for these findings.

## Pre-commit Git state and scope

Branch: `codex/p416-bilateral-shift-swaps`. HEAD, local `main` and cached
`origin/main` are `3b2d66f07ef7f261a74e922e32cbe656d8998837`.
Clean local `main` and its exact live-remote synchronization were verified before
branch creation. All implementation changes are unstaged/uncommitted; main has
no new commit. No commit, push, merge or deployment occurred.
Historical migrations 0001–0027 have no Git content changes. Migration 0028 was
available at the verified baseline and is the only added migration.
No dependency/lockfile, generated OpenAPI, Flutter implementation, normally served
Web assets, operational container, normal database or backup was changed.

## Contracts and owner ports

The new strict transport contracts cover command-specific intent, canonical UUIDs,
bounded versions/reasons, deliberately disclosed immutable leg/task/pin summaries,
complete paired lineage, original command results, current detail/actionability and
bounded request/colleague/counterpart pages. Internal Account/link/version evidence
is excluded from participant DTOs. Offer is version 2 of the immutable request pair;
confirmation binds that stored pair through expected version 2. Request/offer/
confirmation/approval use versions 1/2/3/4; every permitted closure increments once.
Actor, snapshots, replacements, timestamps and arbitrary overlap exclusions cannot
be supplied in commands. Inputs/results are deeply immutable and exact replay
retains the original accepted response separately from current detail.

The Workforce persistence and shared claim ports use the caller's transaction.
Claim ownership is derived from persisted transfer sources or swap legs. Occupancy
returns a boolean and busy conflicts disclose no other request identity. B acquisition
and paired release lock persisted originals in deterministic Shift-ID order.
The Workforce overlap query excludes exactly the two persisted originals and
checks incoming intervals against the remaining published roster.

Tasks owns capture/pristine/reference validation, exact replacement materialization
and paired Task lineage. Its SQL integrity ports protect source references and
complete approval-time snapshot correspondence. Identity's narrow boolean port
compares current Account/link/version eligibility to the captured swap basis.
Existing People/Identity public projections provide the remaining eligibility facts;
no new employee model or foreign application repository access was introduced.

P4.11 now uses the same occupancy authority, claims after proposal and releases
after every terminal transition in its existing authorized transaction. Its replay
path remains before fresh eligibility/occupancy checks. The existing
`transfer_already_pending` refusal also covers a source occupied by a swap.
All P4.11 routes, DTOs, states, version changes, receipt identities/results and
original Shift/Task lineage remain unchanged; `transfer_active_source` is retained.

## Migration and executed integrity proofs

`0028_bilateral_shift_swaps.sql` adds the approved five tables: Workforce requests,
legs, commands and handoff claims, plus Tasks-owned `task_swap_links`.
It adds the necessary scoped transfer-source anchor and scoped FK/index targets.
No historical migration or business evidence is rewritten.

Immediate `(company_id,shift_id)` uniqueness arbitrates one occupancy winner.
A strict typed XOR check rejects NULL/UNKNOWN owner tuples; scoped FKs bind each
claim to its exact source or leg. Deferred parent/leg/claim checks require exactly
A for requested swaps, A+B for offered/confirmed swaps, the source for proposed/
accepted transfers and zero claims for terminal parents. Claim deletion requires
an already terminal owner, and ownership cannot be edited. Staleness never expires
claims. Immutable guards protect request identity, accepted consents, original leg
facts, receipts and Task correspondence; replacement pointers are assigned once.

Fresh deferred approval checks validate both cancelled originals/version advances,
both exact published replacements, complete ordered Task correspondence, Employee
ownership, pristine replacements and full frozen-content equality. Database
`clock_timestamp()` is checked last against both captured starts. Ordinary later
Task execution and original receipt replay do not update the request or rerun this
fresh guard. Runtime grants are SELECT/INSERT on evidence, specified lifecycle
UPDATE columns, the one-time replacement pointer and guarded DELETE on claims.
No SECURITY DEFINER, evidence DELETE/UPDATE or TRUNCATE grant is introduced.

Restricted PostgreSQL tests executed fresh installation/application, repeated
application, typed ownership/NULL failures, foreign Company/Location and orphaned/
extra claims, missing claims, premature deletion/release, evidence edits, all
closure stages, malformed receipts, wrong/incomplete correspondence and altered
full snapshots. A complete maximum pair persists 20 unique ordered Task links.
A deferred Tasks validation barrier was observed in `pg_locks`; crossing the
original start rejected approval and restored all attempted evidence/effects.
Another integrity fixture approved before the boundary and subsequently exercised
ordinary incoming Task execution and original approval replay after the start.
These are owner-port/adversarial SQL integrity fixtures, not swap HTTP/UI acceptance.

## Populated 0027 upgrade

The fixture extracts immutable released P4.11 libraries from the verified baseline
and uses their actual authorized HTTP workflow against an actual 0027 schema.
It creates 11 genuine constructed requests: two proposed, two accepted, one
declined, three withdrawn, two rejected and one approved. One proposed source is
ordinarily cancelled and one accepted source is ordinarily amended to make them
stale. Existing durable receipts and the approved Task-transfer lineage are present.

The upgrade backfills exactly four claims, including both stale requests, with
exact scoped ownership. Terminal requests receive no fabricated historical claim.
All pre-existing tables' row counts and canonical row hashes match before/after
successful application. The injected failure occurs after meaningful DDL, guards,
backfill and verification; all old row hashes and catalog/constraint/trigger/
function/grant/migration-checksum evidence match the pre-upgrade state after rollback.
Subsequent application succeeds; repeated application is empty. Authorized replay
of every retained seeded P4.11 command preserves the four current claims.

## Observed concurrency and compatibility

Tests use a held Company advisory lock, count actual queued writers in `pg_locks`
and release an explicit barrier; they do not infer order from sleeps.

| Scenario | Observed result |
| --- | --- |
| Two P4.11 proposals | One created; second `transfer_already_pending`; one claim. |
| Transfer then swap A | Transfer wins; swap receives bounded busy conflict. |
| Swap A then transfer | Swap wins; transfer retains `transfer_already_pending`. |
| Two swap A requests | First wins; second rolls back; one request/claim. |
| B owned by an active transfer | Offer fails; existing A request/claim and B occupancy remain unchanged. |
| Reverse invitations | Both A claims coexist; both attempted offers refuse to steal B and leave evidence unchanged. Explicit closure permits the remaining offer. |
| Ordinary source cancellation / Account role ABA | Request becomes stale; claim remains until explicit closure. |
| Historical transfer replay after swap acquisition | Original response is returned; the later swap's claims/evidence remain unchanged. |

Existing P4.11 server domain, HTTP integration/safety, guidance and populated
migration cases passed, including exact replay, independent approval, scope,
fresh-clock checks and ordinary replacement execution. All P4.11 API contract and
OpenAPI parity tests passed. Existing one-way Chrome/controller-HTTP opt-ins were
skipped in the broad server run and are explicitly unverified here.

## Verification results and limitations

| Executed check | Result |
| --- | --- |
| Full server suite, disposable PostgreSQL 17 and restricted runtime role | 811 PASS / 0 FAIL / 21 opt-in SKIP. |
| Final Stage A + P4.11 domain/guidance run after final edits | 134 PASS / 0 FAIL / 0 SKIP; includes the three additional final Stage A cases. |
| Full API contract suite | 351 PASS / 0 FAIL / 0 SKIP. |
| Full Flutter client suite | 425 PASS / 0 FAIL / 0 SKIP. |
| Design system suite | 2 PASS / 0 FAIL / 0 SKIP. |
| All four analyzers | No issues. |
| All four format checks and `git diff --check` | PASS. |
| Flutter Web release, `--no-web-resources-cdn --no-pub` | PASS; output only in `.local/p416-stage-a/client-web`. |
| Docker Compose configuration | `docker compose config --quiet`: PASS. |

The installed SDKs match the repository/CI pins: Flutter 3.47.5 and Dart 3.13.4.
All dependency lockfiles remain unchanged.

The broad run preceded the final additive Identity-basis port/domain case,
maximum-20-Task case and removal of the unused old private pending query. The final
134-test run exercises those edits and the complete Stage A database/migration/
clock/contract-relevant owner-port cases, plus P4.11 domain/guidance regression.
Counts are per invocation and must not be added as unique tests.

The 21 skipped broad-server cases are existing explicit opt-ins: Article quantity
Flutter/Chrome/encrypted recovery (3), Knowledge Chrome (1), preparation assignment
Chrome/Flutter/encrypted recovery (3), preparation batch Chrome/Flutter (2),
Purchasing Flutter/Chrome (2), Purchasing delivery encrypted recovery (1), Purchasing
order encrypted recovery (1), Recipe Chrome/Flutter (2), P4.11 transfer Flutter/Chrome
(2), Stock count Flutter/Chrome (2), Task Knowledge Chrome (1), Task Planogram Chrome
(1). Their migration-chain expectations were updated where necessary; their
opt-in journeys/recovery are not claimed as freshly executed.

Early draft checks found and corrected SQL CASE-parenthesis errors, missing Dart
braces, the replay query's surplus Location parameter, legacy-fixture subprocess
harness errors and migration-chain assertions ending at 0027. One sandboxed Dart
test invocation could not create compiler temporary files; the normally permitted
test run passed. No tests were removed or weakened; final executed runs above have
zero failures. No unresolved defect or architecture deviation is known within
Stage A. New swap permissions/audit and functional acceptance remain future gates.

Reproduce the PostgreSQL proofs with
`scripts/workforce/Run-P416StageAChecks.ps1 -TestFiles @('test/shift_swap_test.dart','test/shift_handoff_claim_test.dart','test/shift_swap_integrity_test.dart','test/shift_swap_clock_test.dart','test/shift_swap_migration_test.dart','test/shift_transfer_test.dart','test/shift_transfer_guidance_test.dart')`.
The wrapper starts a unique disposable tmpfs container/database, generated test
credentials, a restricted role and a random loopback port; it removes that container
and clears credential files on completion. Full-suite invocation uses
`-TestFiles @('test')`. Logs and immutable baseline fixture copies stay under ignored
`.local/p416-stage-a/`; no production connection or persistent Compose volume is used.

## Remaining Steps 5–10

Step 5: authorized full swap coordinator, participant eligibility/discovery,
guidance/final-roster validation and atomic production workflow orchestration.
Step 6: fixed swap capabilities, minimized atomic swap audit, HTTP routes and actual
error sets. Step 7: route/DTO/OpenAPI publication parity. Steps 8–9: Flutter data,
controllers, pending-intent/session fencing, employee/manager surfaces and actual
four-actor journeys. Step 10: swap-inclusive encrypted backup/restore, fenced update/
recovery, functional/Security reviews and final evidence. None is implemented by
Stage A. Existing P4.15 qualifications and all unrelated debt remain unchanged.

## Changed-file inventory

The inventory below lists all tracked modifications and new reviewable files.
Ignored build/test logs, temporary fixture copies and cleared credential files are
local verification artifacts. Paths are relative to `C:/dev/storeos`.

- `apps/server/lib/src/application/shift_transfer_application.dart`
- `apps/server/lib/src/identity/employee_links.dart`
- `apps/server/lib/src/infrastructure/migration_runner.dart`
- `apps/server/lib/src/tasks/task_instance_repository.dart`
- `apps/server/lib/src/tasks/task_instance_service.dart`
- `apps/server/lib/src/workforce/shift_repository.dart`
- `apps/server/lib/src/workforce/shift_transfer_repository.dart`
- `apps/server/lib/src/workforce/shift_transfer_service.dart`
- `apps/server/lib/src/workforce/workforce_service.dart`
- `apps/server/test/article_integration_test.dart`
- `apps/server/test/article_quantity_upgrade_recovery_test.dart`
- `apps/server/test/knowledge_integration_test.dart`
- `apps/server/test/merchandising_fixture.dart`
- `apps/server/test/merchandising_integration_test.dart`
- `apps/server/test/postgres_integration_test.dart`
- `apps/server/test/preparation_assignment_upgrade_recovery_test.dart`
- `apps/server/test/preparation_batch_migration_test.dart`
- `apps/server/test/purchasing_delivery_safety_test.dart`
- `apps/server/test/purchasing_delivery_upgrade_recovery_test.dart`
- `apps/server/test/purchasing_test.dart`
- `apps/server/test/purchasing_journey_fixture.dart`
- `apps/server/test/purchasing_upgrade_recovery_test.dart`
- `apps/server/test/recipe_integration_test.dart`
- `apps/server/test/shift_amendment_integration_cases.dart`
- `apps/server/test/shift_cancellation_integration_cases.dart`
- `apps/server/test/shift_integration_test.dart`
- `apps/server/test/stock_count_integration_test.dart`
- `apps/server/test/stock_integration_test.dart`
- `apps/server/test/task_blocking_integration_cases.dart`
- `apps/server/test/task_cancellation_integration_cases.dart`
- `apps/server/test/task_execution_integration_cases.dart`
- `apps/server/test/task_knowledge_integration_test.dart`
- `apps/server/test/task_numeric_integration_cases.dart`
- `apps/server/test/task_planogram_integration_test.dart`
- `apps/server/test/task_template_integration_test.dart`
- `apps/server/test/shift_transfer_migration_test.dart`
- `docs/HANDOVER.md`
- `docs/roadmap/status.md`
- `packages/api_contracts/lib/api_contracts.dart`
- `apps/server/lib/src/workforce/shift_handoff_claim_repository.dart`
- `apps/server/lib/src/workforce/shift_handoff_claim_service.dart`
- `apps/server/lib/src/workforce/shift_swap.dart`
- `apps/server/lib/src/workforce/shift_swap_repository.dart`
- `apps/server/lib/src/workforce/shift_swap_service.dart`
- `apps/server/migrations/0028_bilateral_shift_swaps.sql`
- `apps/server/test/shift_handoff_claim_test.dart`
- `apps/server/test/shift_swap_clock_test.dart`
- `apps/server/test/shift_swap_integrity_test.dart`
- `apps/server/test/shift_swap_legacy_fixture.dart`
- `apps/server/test/shift_swap_migration_test.dart`
- `apps/server/test/shift_swap_stage_a_fixture.dart`
- `apps/server/test/shift_swap_test.dart`
- `apps/server/test/shift_swap_review_regression_test.dart`
- `apps/server/test/shift_swap_remediation_test.dart`
- `docs/development/phase-4-16-stage-a.md`
- `packages/api_contracts/lib/src/shift_swaps.dart`
- `packages/api_contracts/test/shift_swap_evidence_test.dart`
- `packages/api_contracts/test/shift_swap_fixture.dart`
- `packages/api_contracts/test/shift_swaps_test.dart`
- `scripts/workforce/Run-P416StageAChecks.ps1`
