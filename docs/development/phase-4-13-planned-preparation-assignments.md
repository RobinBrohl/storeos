# P4.13: Planned Preparation Assignment

User-selected capability, 2026-10-11: **Planned Preparation Assignment**, estimated
size **MEDIUM**, Production-owned. Current state, 2026-10-12: **DONE/CLOSED — accepted
implementation** at `625bb7ef9643989e2182c966d87839115a0cca6f`.
F01 is **CLOSED**; targeted independent **APPROVE**, focused **SECURITY APPROVE** and
successful exact implementation-commit CI establish acceptance. Current matrix:
**99 PASS / 1 QUALIFIED / 0 FAIL**. Final documentation publication and its own
closure-commit CI remain **PENDING**. P4.14 is **UNSELECTED**.
See [final documentation closure](#final-documentation-closure--2026-10-12).

## Historical implementation baseline and delivery boundary

Implementation began on clean `main` at `d48856f8eb0ccf4565295616606fe674bc0f2b49`
(`Close P4.12 acceptance`). Cached and live origin matched. All five jobs succeeded
in [baseline closure CI 38156014870](https://github.com/RobinBrohl/storeos/actions/runs/38156014870).
P4.1–P4.12 remain DONE/CLOSED; their dated evidence is retained. Baseline P4.12
closure publication has therefore completed, although its historical documentation
described that then-pending gate. No claim about P4.13 remote CI follows from baseline CI.

At implementation/remediation handoff, all changes were unstaged/uncommitted on the original HEAD. No branch, stash,
commit, push or PR is created. Historical migrations 0001–0024 and dependencies remain
unchanged. Only `0025_planned_preparation_assignments.sql` is added. All database
journeys use disposable resources; the normal StoreOS deployment is untouched.

## Historical independent review F01 and bounded remediation

These assessments preserve their original gate state; later approval is recorded in the dated closure below:

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
verifier reports pass with unchanged inventoried content during that execution.
The retained run is historical source-frozen evidence, independently matched before
this docs-only closure. Closure Markdown edits change the docs-inclusive inventory;
they do not represent a rerun or a match of the edited tree to its old byte hashes.

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

## Remaining publication gate and standing limitations

Supplied independent CHANGES REQUIRED → bounded F01 remediation CLOSED → targeted
independent APPROVE → focused SECURITY APPROVE → implementation commit → successful
exact implementation-commit CI are complete. Documentation closure publication and
its own exact-head CI are PENDING. This docs-only pass leaves all edits unstaged and
uncommitted; no future closure SHA, run or outcome is claimed.

M1 proxy/login-limiter pilot gate; M2 CLOSED; M3 local containment; M4 global taxonomy;
P4.12 I01–I03 INFO; P4.5 F01/F02; P4.9 historical qualification; supported-writer/raw-SQL;
memory-only retry recovery; physical device/accessibility gaps; retention/export/offboarding
and RPO/RTO/recovery decisions retain their previous dispositions. Real employee-data
use still requires operator privacy decisions. P4.14 is UNSELECTED.

## Final documentation closure — 2026-10-12

**DONE/CLOSED — accepted implementation. Final documentation publication: PENDING.**
This reconciliation changes Markdown only. P4.1–P4.12 stay DONE/CLOSED; no active
P4.13 implementation remediation remains. P4.14 stays UNSELECTED.

### Verified baseline and implementation CI

Before edits, `main` was clean at `625bb7ef9643989e2182c966d87839115a0cca6f`
(`Add planned preparation assignments`), equal to cached `origin/main` and the live
GitHub branch. Index/stash were empty and exactly one worktree existed. Shell remote
lookup could not initialize networking and `gh` was unavailable; connected read-only
GitHub branch/run/job APIs supplied live evidence instead.

[Implementation CI 38224661628](https://github.com/RobinBrohl/storeos/actions/runs/38224661628)
was verified as **completed / success** for that exact SHA and `main`, with all five
jobs **completed / success**: `dart`, `flutter`, `numeric-guided-work-e2e`,
`backup-restore-acceptance`, `update-recovery-acceptance`. This proves the implementation
commit, independently of baseline P4.12 closure CI 38156014870.
No documentation-closure commit, SHA or CI run exists yet; its separate publication
gate remains PENDING until the user commits/publishes these edits and that commit's
own exact-head remote CI succeeds.

### Review chronology and F01 closure

| Stage | Verdict / acceptance | Evidence |
| --- | --- | --- |
| Initial implementation | 96 PASS / 4 QUALIFIED / 0 FAIL | 1,352 package tests; historical pre-F01 source. |
| Independent adversarial review | CHANGES REQUIRED; 95 PASS / 4 QUALIFIED / 1 FAIL | Criterion 04; F01 MEDIUM PRODUCT DEFECT, commit blocker YES. |
| Bounded remediation | Locally remediated; 96 PASS / 4 QUALIFIED / 0 FAIL | Two pre-fix behavioral failures retained; 15 new UUID regression cases; final-source verifier passed. |
| Independent targeted re-review | APPROVE; F01 CLOSED; 96 PASS / 4 QUALIFIED / 0 FAIL under the historical matrix convention | 153 fresh PASS / 0 FAIL / 0 SKIP; no remaining actionable finding or product commit blocker in its reviewed scope. |
| Focused Codex Security | SECURITY APPROVE | 74 changed files; zero identified vulnerabilities, security blockers or required remediation. |
| Exact implementation-commit CI | SUCCESS | Run 38224661628, all five jobs; SHA verified above. |
| Current implementation acceptance | 99 PASS / 1 QUALIFIED / 0 FAIL | Criteria 89–91 PASS; criterion 92 QUALIFIED; all 100 definitions retained. |

F01's root cause was validated configured Location authority followed by raw route
UUID spelling in downstream Identity eligibility and self cursor scope. Before the
fix, lowercase returned an eligible Employee and create 201; uppercase/mixed routes
returned an empty picker and create 422 `assignee_unavailable`. The related self
pagination cursor failed with 400 `invalid_cursor`. The two retained failing tests
are historical behavioral evidence, not unresolved failures.

One validated canonical Location UUID now flows through authorization callbacks,
Identity eligibility, manager picker/create, self scope, pagination/cursors,
persistence, receipts and audit. Current Company/Location isolation, Employee/link
authority, receipt privacy, canonical replay and existing Recipe/Batch semantics
remain enforced. The finding is **CLOSED**, not erased from history.

The [independent re-review summary](../../.local/p413/re-review/summary.json) and its
named logs independently match final implementation evidence. Fresh execution:
15 UUID + 40 Assignment + 38 Batch + 9 independent probes + 34 contract/OpenAPI +
17 Flutter = **153 PASS / 0 FAIL / 0 SKIP**. It covers lowercase/uppercase/mixed
creation and picker consistency; cross-representation replay and persisted scope;
wrong Location/Company denial; Employee/link revocation; self routes; 52-record
picker/Assignment pagination and cursor binding; R1 after R2 publication; standalone
historical opening denial; and Batch/receipt/audit atomicity.

The first independent seven-probe attempt recorded five passes and two harness
comparison failures caused by including intentional login audit; denial assertions
were correct. The corrected boundary and all nine final probes passed. The attempted
Recipe Chrome phase is also retained in `.local/p413/f01/failed-host-timeout`.
The independent product reviewer associated its timeout with Windows battery-triggered
sleep around 00:00–01:12 CEST on 12 October; the entire host phase later passed with
unchanged source and timestamps. Security did not independently establish that
causal explanation. Neither report establishes an unresolved product defect.

### Final delivered operator and domain contract

Manager selects an active Recipe's exact current approved RecipeRevision, eligible
Employee and planned whole declared-batch count, then creates an immutable request.
Employee opens their own assignment, reads its exact retained revision, explicitly
starts, then completes or cancels the linked Batch. Manager inspects original and
effective corrected outcomes; historical evidence remains available under current
authority. Opening instructions alone creates no execution or readership evidence.

PreparationAssignment retains stable UUID, Company/configured Location, exact
Employee/Recipe/approved Revision identities, planned count, immutable selection,
creation actor/time/operation, lifecycle/version, withdrawal actor/time/reason or
Batch linkage/start evidence, and historical attribution. Only `assigned v1 →
started v2` or `assigned v1 → withdrawn v2` exists. No reopening or Assignment
completed state exists. Started permanently references exactly one Batch; Batch
completion, cancellation and correction do not alter Assignment lifecycle.
Changing the request requires withdrawal and a new identity.

Planned count is integer **1–9999**, whole repetitions of the Recipe's declared
batch. Verified actual workflow: requested **3**, original completion **2**, first
effective correction **1**, second **0**. Original completion remains immutable;
corrections append evidence. No ingredient consumption, finished-goods Stock
increase, yield/unit conversion, Purchasing, Task/Shift or event/outbox effect exists.

Creation requires an active Recipe, exact current approved/published revision,
eligible Employee, authorized manager and matching Company/Location. Persisted R1
remains pinned when R2 is published; publication alone does not invalidate execution.
Fresh start still checks current Recipe/Article/Assortment/unit and Employee eligibility;
Recipe retirement blocks it. Exact historical context and committed replay remain
available under current authority. Standalone Batch opening still requires the
current revision. Retained execution authority is restricted to a valid persisted
Assignment and never grants arbitrary historical Recipe execution.

Production owns Assignment, Recipe, Batch and both receipt families. People owns
Employee eligibility; Identity owns current Account/session/Employee linkage;
Inventory owns Article/Assortment eligibility; Organization owns Company/Location
configuration; Platform owns authorized transactions and audit. Public ports preserve
ownership. Current authorization is server-side, not widget or route-prefix authority.

Delivered capabilities: `production.assignments.manage`,
`production.assignments.self.read`, `production.assignments.self.start`.
Admin receives management and self capabilities, but self actions require its own
valid current eligible Employee link and requisite existing Recipe/Batch rights.
Employee receives own read/start; Viewer, Auditor and Plugin receive no assignment
access. Current Account/session, Account–Employee link, Employee eligibility,
configured Company/Location, Account Location, route Location, persisted scope and
self ownership are checked before protected receipt disclosure. No manager
impersonation or client-selected executing actor exists.

Start validates ownership/eligibility and locks/re-reads Assignment, derives its
exact persisted revision/count, generates Batch identity and a separate internal
Batch-opening operation UUID, and performs opening, opening receipt/audit,
Assignment transition/link, Assignment receipt/audit and deferred integrity validation
in one authorized transaction. Atomic commit leaves exactly one Batch. Any failure
rolls back all evidence, leaving no orphan Batch or independent nested commit.

Create/withdraw/start use durable **Company + operation UUID** receipts binding
actor, kind, target, canonical Location, expected version where applicable,
canonical payload and original accepted result/status. Exact authorized replay
returns original evidence without fresh Recipe eligibility validation, another Batch,
duplicate receipt/audit or current Batch mutation. Failed commands consume no UUID.
Completion, cancellation, corrections, Recipe retirement and server restart do not
change historical replay semantics. Current Batch detail remains a separate read;
original receipts never bypass current authorization.

### Migration, backup and update evidence

The migration chain is exactly **0001–0025**. Implementation-versus-parent Git
comparison shows only new `0025_planned_preparation_assignments.sql`; 0001–0024 and
dependency/lockfiles are unchanged. This docs-only pass changes no migration.
Migration 0025's retained raw SHA-256 is
`c08228a7812e600a57c3850079afcecfd6660d05a959132dd9cf346d79e3baf0`.
There is no migration 0026.

New tables: `production_preparation_assignments` and
`production_preparation_assignment_commands`. Scoped identities, immutable selection,
coherent lifecycle, unique Batch linkage, composite Batch identity/revision/count,
receipt binding and deferred final-state validation constrain evidence. Explicit SQL
NULL/JSON type handling rejects missing/null/wrong-type evidence; narrow runtime
grants and terminal-update guards protect selection and receipts. This preserves
the declared supported-writer/raw-SQL boundary, not independent SQL authentication.

Retained encrypted backup run `1f2e1c628b8f4d83` compares all **41 table count/hash
pairs equal**, including **7 Assignments, 12 Assignment receipts, 9 total Batches,
20 Batch receipts and 4 corrections**. Content comparisons cover IDs/timestamps,
assigned/withdrawn/started states, retained revision and exact Batch linkage,
original/effective counts, receipts/audit and earlier business evidence. Fresh restored
manager/Employee sessions exercise current authority, historical context/exact replay,
wrong Employee/Location/Company denial, session/plugin fencing and runtime grants.
Matching row counts alone are not the restoration claim. Evidence is bounded to the
tested fenced fixture; broader offboarding/old-backup reconciliation remains policy.

Retained update run `f24a8bab07f84a36` and executed migration/recovery cases cover
clean 0001→0025, populated 0024→0025, late failure after grants/ledger with complete
rollback, successful forward update, no-op reapplication, meaningful linked-Batch
smoke and encrypted fenced pre-0025 recovery. P4.12 Suppliers/Orders/receipts,
P4.11 transfers, P4.10 Batch/corrections, Stock/Counts and Task/Knowledge/Planogram
evidence remain preserved. There is no downgrade or automatic restored-writer activation.
Security noted stale update-report prose listing only through 0023; structured
migration/smoke evidence includes 0025. Generated report/tooling text was not changed
in this docs-only closure; that nonblocking reporting follow-up remains open.

### Final-source regression and fingerprint

The [retained final summary](../../.local/p413/final/summary.json) and named logs record:

| Package | PASS |
| --- | ---: |
| API contracts | 298 |
| Server/PostgreSQL | 662 |
| Design system | 2 |
| Flutter | 405 |
| **Total** | **1,367** |

**16/16 phases PASS**; 17 ordinary conditional cases executed explicitly as
**15 host journeys + 2 migration/recovery cases**; Numeric Guided Work **3/3 PASS**.
Source-matched evidence includes actual Flutter/HTTP/PostgreSQL and Chrome
manager/Employee journeys, analyzers/formatters, Flutter Web release, Compose,
crypto, diagnostic redaction, printing, setup, backup/restore, update/recovery and
diff checks. This docs-only closure did not rerun package, browser or database tests.

Historical final implementation inventory: **594 files**, fingerprint
`c1dc569e92976954e762bcb4e1784b31881462bae8a41f76f70553f0c1aaa8ba`.
Verifier started 2026-10-11 21:12:08 UTC, finished 23:33:34 UTC
(23:12:08 CEST on 11 October to 01:33:34 CEST on 12 October).
Before/after manifests are identical, including execution-time source timestamps.
Independent re-review and Security matched that inventory; this closure matched all
594 file hashes before editing documentation. Markdown participates in the inventory,
so the edited documentation tree does not match those original byte hashes.
The fingerprint remains dated pre-closure implementation evidence; no replacement
docs-inclusive fingerprint is presented as the original.

### Focused Security review and evidence limitations

Supplied final verdict: **SECURITY APPROVE**, scan
`85a72b4d-836d-4da9-9834-1b4dd44712c7`, reviewed 2026-10-12 Europe/Berlin.
All **74 changed files** were reviewed; **zero identified security vulnerabilities,
zero security commit blockers, no required security remediation**.
Fresh restricted PostgreSQL: **57 PASS / 0 FAIL / 0 SKIP**
(40 Assignment + 15 UUID + 2 supplemental tests); **28 fault subprobes PASS**
inside supplemental execution, counted separately rather than as extra test cases.
The normal database was not changed.

Fresh Security client tests executed **zero cases**: a temporary-file safeguard
blocked them. No bypass or fresh client success is claimed. Static review and
matched earlier Flutter/controller/actual Chrome evidence support client conclusions;
these are distinct from the independent review's 17 fresh Flutter tests. Full regression,
Chrome, backup and update were not freshly rerun by Security. Restored-state conclusions
are limited to the tested fixture. Approval is scoped to the declared threat model;
it is not a general guarantee that all possible vulnerabilities are absent.

The full sealed report and supplemental 60-conclusion report were read during closure.
Retained external provenance (local artifacts, not newly generated repository files):
`C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/d48856f8eb0ccf4565295616606fe674bc0f2b49_20261011T235256Z_rappabe8/report.md`
and its `artifacts/04_reporting/p413-focused-security-review.md`.
The next section preserves the actual 60-row conclusion table verbatim; its NO answers
mean no identified issue within that review, with client/restore qualifications above.

Nonblocking Security evidence observations remain distinct from vulnerabilities:
E01 documentation lag is reconciled here; E02 update-report prose lag is retained
as an open reporting follow-up; E03 fresh-client safeguard limitation remains disclosed.
Standing M1 proxy/login-limiter pilot gate, M2 CLOSED, M3 local error containment,
M4 deferred global taxonomy, P4.12 INFO I01/I02/I03, P4.5 F01/F02 and P4.9 historical
qualification retain their dispositions. Supported-writer/raw-SQL, memory-only
uncertain tracking, physical-device/accessibility gaps, retention/access/export/deletion,
Employee offboarding/privacy, key custody, RPO/RTO and off-host recovery activation
remain operator/standing boundaries. Bounded acceptance does not authorize unrestricted
real employee-data production use or select P4.14.

### Focused Security conclusions

YES/NO/QUALIFIED applies only to the inspected implementation and declared threat model. A NO is absence of an identified issue here, not a universal guarantee. Static evidence covers all rows; fresh PostgreSQL evidence strengthens server/DB/UUID/replay/race/rollback rows. Client and restored-state conclusions retain the explicit execution qualifications above.

| # | Question | Answer | Evidence / rationale |
| --- | --- | --- | --- |
| 1 | Can a foreign Employee be assigned? | **NO** | People eligibility and scoped Identity port reject nonlocal/foreign employees before insert. |
| 2 | Can an inactive Employee be assigned? | **NO** | Current Employee activity and assignment interval are checked inside the authorized transaction. |
| 3 | Can stale Employee version pass creation? | **NO** | Creation compares expectedEmployeeVersion with the current People projection and returns version_conflict. |
| 4 | Can an ineligible linked Account be selected? | **NO** | Narrow Identity port requires an active linked Account and every assignment/Recipe/Batch execution right. |
| 5 | Can manager authority impersonate Employee start? | **NO** | Manager commands allow only create/withdraw; self start derives the manager's own valid Employee link. |
| 6 | Can another Employee read or start Assignment? | **NO** | Own Employee predicate governs list/detail/context/history/start before receipt lookup. |
| 7 | Can a replacement Account replay the old actor's command? | **NO** | Exact receipts bind actor Account; a replacement may follow Employee-owned work but old actor reuse conflicts. |
| 8 | Can a revoked session access historical Recipe context? | **NO** | Authentication and runAuthorized re-read the unrevoked session before contextual resource resolution. |
| 9 | Can wrong-Location Assignment or Batch IDs leak? | **NO** | Configured/current Location checks and scoped repositories deny foreign IDs without protected content. |
| 10 | Can a registered nonconfigured Location gain access? | **NO** | Configured route, Account and installation Location must all agree; registration alone supplies no authority. |
| 11 | Can a foreign Company Recipe/Employee be selected? | **NO** | People and Recipe repositories bind configured Company; linked selections are composite scoped. |
| 12 | Can a forged or unpublished revision be assigned? | **NO** | Creation and the FK require exact published revision in the selected Company/Recipe. |
| 13 | Can a noncurrent revision be selected at creation? | **NO** | Fresh creation requires currentPublishedRevisionId to equal the requested approved revision. |
| 14 | Can the pinned R1 silently become R2? | **NO** | The immutable persisted revision is used for context and assigned opening, never substituted with current. |
| 15 | Can assigned R1 legitimately start after R2? | **YES** | Only a current eligible own Employee may start persisted approved R1 after R2; catalog gates still apply. |
| 16 | Can standalone Batch opening bypass current revision rules? | **NO** | Standalone open calls _freshRecipe with retainedAssignment=false and retains the current revision check. |
| 17 | Can a public DTO activate the retained-revision exception? | **NO** | Strict DTOs reject authority switches; the retained flag is private and set only after persisted assignment checks. |
| 18 | Can a retired Recipe freshly start? | **NO** | Fresh _freshRecipe requires active Recipe; exact accepted replay is a distinct authorized historical operation. |
| 19 | Can an inactive/nonassorted Article freshly start? | **NO** | Current Article activity and produced effective local Assortment are checked at fresh opening. |
| 20 | Can changed ingredient units be ignored? | **NO** | Each current ingredient unit must match its frozen revision unit. |
| 21 | Can client override the persisted planned count? | **NO** | Start DTO accepts only operationId/expectedVersion; count comes from persisted Assignment. |
| 22 | Can count precision/overflow rules be bypassed? | **NO** | JSON requires integer count 1–9999; DTO bounds and integer database column/check reject coercion/overflow. |
| 23 | Can one Assignment create multiple Batches? | **NO** | Company serialization, assigned v1 guard, version transition and original replay permit one opening. |
| 24 | Can one Batch link multiple Assignments? | **NO** | UNIQUE(company_id,batch_id) prevents reuse of the same scoped Batch by another Assignment. |
| 25 | Can linked Company/Location/Employee/Recipe/count mismatch? | **NO** | Full Company/Location/Employee/Recipe/revision/count Batch tuple is anchored by composite FK. |
| 26 | Can terminal Assignment evidence be mutated? | **NO** | Domain guard, narrow grants and immutable terminal trigger reject later selection/evidence mutation. |
| 27 | Can a withdrawn Assignment start or a started one withdraw? | **NO** | Both terminal choices require assigned v1; started/withdrawn v2 cannot transition again. |
| 28 | Can correction overwrite original Batch completion? | **NO** | Corrections append to existing immutable completion; actual original and effective corrected counts stay separate. |
| 29 | Can Start commit without both receipt families? | **NO** | One TxSession and deferred create/terminal/opening receipt FKs bind both families at commit. |
| 30 | Can Start commit without required audit through supported API? | **NO** | Both audit appends are awaited in the same authorized transaction; a supported API failure rolls everything back. |
| 31 | Can SQL NULL/UNKNOWN bypass new required evidence checks? | **NO** | Lifecycle CHECK wraps IS TRUE; typed command shape and deferred IS DISTINCT FROM comparisons reject missing/null evidence. |
| 32 | Can restricted runtime role change selection fields? | **NO** | Actual narrow column grants omit Employee/Recipe/revision/count/Location and other selection updates. |
| 33 | Can runtime role rewrite/delete command receipts? | **NO** | Receipt UPDATE/DELETE/TRUNCATE grants are absent and immutable evidence triggers reinforce the boundary. |
| 34 | Can runtime role reopen terminal Assignment? | **NO** | Terminal trigger requires OLD.status assigned and version transition to2; even permitted lifecycle columns cannot reopen. |
| 35 | Can two fresh concurrent Starts both commit? | **NO** | One Company lock serializes supported Starts; later distinct operation sees terminal/version conflict. |
| 36 | Can Start/Withdraw produce inconsistent results? | **NO** | Start/withdraw share lock and assigned v1 transition; each serial order has one winner. |
| 37 | Can catalog or identity revocation race bypass current authority? | **NO** | Supported catalog/Employee/Account/link/role/logout writers share Company lock; authorization is re-read after acquisition. |
| 38 | Can replay precede current authorization? | **NO** | Current session/account/capabilities/location/self/resource checks run before protected receipt lookup. |
| 39 | Can exact historical replay incorrectly revalidate current R2? | **NO** | Exact replay returns original accepted snapshot before fresh catalog checks; current R2 is irrelevant. |
| 40 | Can replay create another Batch or duplicate audit? | **NO** | Replay returns from _replay before Batch mutation, receipt acceptance or audit writes. |
| 41 | Can operation conflicts expose stored receipt contents? | **NO** | Binding mismatch produces generic operation_conflict after current scope/ownership checks. |
| 42 | Can definite failure consume operation UUID? | **NO** | Commands and receipts share transaction; errors roll back, enabling the same operation UUID to be retried. |
| 43 | Can P4.13 collide with Purchasing receipt namespace? | **NO** | Assignment, Batch and Purchasing receipts use separate module tables/namespaces. |
| 44 | Can UUID case normalization weaken Location isolation? | **NO** | Complete UUID validation precedes one canonical Location through callbacks, picker, receipts, cursors and audit. |
| 45 | Can cursor reuse expose another Employee's work? | **NO** | Cursor scope binds Company/canonical Location/endpoint/self/Employee/filter; visibility is reapplied in SQL. |
| 46 | Can decoded duplicate JSON alter authority? | **NO** | Lexical duplicate-name check decodes escaped names before jsonDecode; canonical decoder then validates grammar. |
| 47 | Can forged actor/Batch fields reach execution? | **NO** | Unknown DTO members reject actor/Batch/Employee/snapshot fields before execution. |
| 48 | Can delayed Flutter responses cross session boundaries? | **NO** | Opaque identity comparisons fence delayed GET/POST/status/error results, and replacement clears resident/mounted state. |
| 49 | Can uncertain command contents change silently? | **NO** | Unmodifiable scalar-only intent, frozen route/operation/target/session and exact-retry-only state prevent silent edits. |
| 50 | Can failed detail refresh retain stale actionable data? | **NO** | Success keeps immutable confirmation; actionable detail/history are cleared before refresh and need authoritative reload. |
| 51 | Can Recipe/Employee text trigger active browser content? | **NO** | Untrusted Recipe/name/reason text reaches Flutter Text widgets; no HTML/Markdown/DOM/link/fetch interpretation was found. |
| 52 | Can logs/audit expose prohibited business content? | **NO** | Assignment/Batch audit contains IDs/versions/status only; standard logging omits body/token/reason/count/content. |
| 53 | Can restore weaken current authorization? | **QUALIFIED** | Verified restore covers credential/session/plugin fencing, current scoped reads and replay on source-matched fixture; broader restored authorization/operational offboarding is not exhaustively proven. |
| 54 | Can failed update leave partial permissions or schema? | **NO** | Migration runTx covers DDL/grants/ledger; source-matched populated upgrade and late-deferred failure evidence show full rollback. |
| 55 | Can Assignment create Stock/Task/Purchasing effects? | **NO** | Only Production assignment/Batch/receipt and minimized audit writes occur; hashes of populated unrelated modules remain equal. |
| 56 | Is there an undocumented data-retention/privacy expansion? | **NO** | New Employee-owned requests/receipts and immutable history are documented; operator retention/export/offboarding decisions remain open. |
| 57 | Is any HIGH or MEDIUM security vulnerability identified? | **NO** | No HIGH or MEDIUM vulnerability survived the complete focused inspection. |
| 58 | Is any LOW security commit blocker identified? | **NO** | No LOW security vulnerability or security commit blocker was identified. |
| 59 | Are selected accepted limitations still accurately scoped? | **YES** | Supported-writer SQL boundary, memory-only recovery, device/accessibility and operator policy/debt limits remain explicit. |
| 60 | Is focused Security approval justified? | **YES** | Focused approval is supported by complete static review and source-matched evidence, with fresh client execution limitation disclosed. |

### Documentation validation and repository state

Closure validation checked all 100 criterion IDs/definitions and computed **99 PASS /
1 QUALIFIED / 0 FAIL**; all 60 Security conclusion rows exactly match the sealed
supplemental report. All **412 local documentation links and 78 Markdown anchors**
in the 16 changed files resolve. Stale gate wording is confined to explicitly labeled
historical passages; current summaries record accepted implementation and separate
pending docs publication. Older P4.12 records received only contextual historical
notices, preserving their original review/closure chronology.

`git diff --check`, `git diff --stat` and `git status --short` confirm only the intended
16 Markdown files changed, all unstaged. All **458 non-Markdown files** in the retained
implementation inventory still match their original SHA-256 hashes. Production code,
tests, migrations 0001–0025, contracts/OpenAPI, scripts, CI and dependency/lockfiles
remain unchanged. No new untracked/generated report or detected credential material
was added. No normal database operation or full regression rerun occurred.

Branch remains `main`; HEAD and cached/live origin remain
`625bb7ef9643989e2182c966d87839115a0cca6f`. Index/stash are empty; one worktree remains.
No branch, staging, commit, push, migration 0026 or P4.14 selection/implementation
occurred. Accepted implementation is complete; the user-controlled documentation
commit/publication and its own successful exact-head remote CI remain PENDING.
