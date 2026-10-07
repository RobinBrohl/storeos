# P4.10 — Location-scoped preparation batch execution evidence

Status: **P4.10 DONE/CLOSED** at implementation commit
`e637187b17d4617212acf42b99a07500e9488c3d` on `main`.
F01/F02 remediation and nonblocking F03 documentation follow-up are CLOSED.
Targeted independent APPROVE, focused SECURITY APPROVE and green exact-commit
CI establish closure. P4.11 remains UNSELECTED; next is fresh capability
selection from clean main. This final pass changes documentation only and
leaves those edits unstaged/uncommitted; no commit or push is authorized.

## Historical implementation baseline

Before edits, `main` was clean at `7182c07f31779b9af599806a6d0ed445af484f0b`,
equal to cached and live `origin/main`, with one worktree and no stash. Exactly
0001–0021 were committed. P4.1–P4.9 were closed without active remediation;
standing technical debt retains its existing disposition. All five exact-HEAD
jobs passed in [CI 37583520347](https://github.com/RobinBrohl/storeos/actions/runs/37583520347).
The preceding “Plan StoreOS P4.10 workflow” selection and the supplied implementation
request define this slice. Baseline CI does not approve these uncommitted changes.

## Domain and implementation

[ADR 0024](../adr/0024-preparation-batch-evidence.md) records ownership and decisions.
Production owns five commands across three new tables: stable Company/Location
batch identity, original terminal declaration, immutable Company/operation receipt,
and numbered count correction chain. Opening derives Account and current linked
Employee server-side through existing public ports. Configured Location equality,
current authorization and resource access precede replay lookup. Fresh open gates
run under the existing Company transaction shared with Recipe, Article, Assortment
and Employee changes. Published Recipe composition remains immutable and exact.

Optional planned count is null or integer 1–9999. Completion requires integer
1–9999; zero never completes. Manager corrections permit integer 0–9999 and require
a reason, terminal version and latest correction number. They preserve original
completion, lifecycle/version and all prior corrections. A correction to zero is
explicitly displayed as a corrected report. Notes/reasons use bounded trimmed
plain text, never audit/log content. Commands and bounded audit commit atomically;
failures leave operation identity reusable. No events/outbox or Stock/Task effects.

Migration 0022 is the sole new migration. Composite foreign keys bind scope,
published Recipe pin, terminal/open receipt actor and command kind. Lifecycle and
immutable triggers protect opening/terminal data, corrections and receipts;
runtime grants allow SELECT/INSERT and only necessary terminal batch UPDATE
columns, without table-wide UPDATE/DELETE/TRUNCATE or SECURITY DEFINER.
Supported application commands remain the business authorization boundary.

Eleven HTTP operations provide self list/detail/context/open/complete/cancel and
manager list/detail/context/cancel/correct. Strict JSON rejects duplicate decoded
names, unknown fields, client-owned identity/timestamps, floating/scientific counts,
and overlarge bodies. Operation-specific OpenAPI metadata is tested exactly.
Existing Recipe discovery remains the approved selector. Current eligibility is
rechecked at opening. Frozen contextual instruction requires both current batch
access and Recipe read permission; there is no historical UUID browsing grant.

Flutter provides “My preparation batches” and “Preparation history”, exact Recipe
preview, declared-batch forms, retained instructions, terminal evidence, full
correction chain and review confirmation. Text renders literally. Opaque session
identity replacement clears resident state and fences delayed responses; uncertain
commands retain an immutable route/body/operation/session binding for exact retry.
Confirmed commands with failed refresh remain a distinct state. Navigation uses
the drawer when the destination list would exceed available screen height.

## Historical implementation verification and reproducibility

Use the installed pinned Dart 3.13.4 / Flutter 3.47.5 and existing dependencies.
`scripts/recipes/Run-P410Checks.ps1` creates/drops strict disposable PostgreSQL
databases and performs no package resolution. No migration or business acceptance
write targets the normal StoreOS database. No dependency/lockfile changes occur.
Existing migration-chain assertions now include 0022 while retaining old
preservation checks; the thirteen Recipe error assertions retain exact values.
The full Dart suites run at test-file concurrency two: concurrent fixture schema
creation/deletion otherwise intermittently exhausts PostgreSQL's default shared
lock budget (`53200`). Assertions and deterministic in-test command races remain
unchanged; no database configuration or normal database is modified.

| Evidence | Test / tool |
| --- | --- |
| Counts, strict request shapes and exact route errors | `packages/api_contracts/test/preparation_batches_test.dart`, `preparation_openapi_test.dart` |
| Identity/scope, lifecycle, receipts/replay, corrections/zero, atomic audit failures, strict transport, grants and pagination | `apps/server/test/preparation_batch_integration_test.dart` and its integrity/concurrency parts |
| Deterministic two-order fresh-open races and terminal/correction races | `preparation_batch_concurrency_cases.dart`; queued Company locks prove serialization order without timing assumptions |
| Populated actual 0021 → 0022 and late failed-0022 rollback | `preparation_batch_migration_test.dart`; hashes all legacy tables, including Recipe, nonempty Stock/Count, Tasks schemas 1–4, Knowledge, Planograms, audit and receipts; then real batch smoke |
| Session replacement, delayed reads/commands, five exact retries, rejected-form retention, confirmed refresh failure, literal and separate original-one/zero UI | `apps/client_flutter/test/preparation_batch_test.dart` |
| Real Flutter / HTTP / PostgreSQL | `preparation_batch_client_journey_test.dart` + `preparation_batch_http_journey.dart` |
| Actual Chrome UI | `preparation_batch_browser_test.dart` + `integration_test/preparation_batch_test.dart`; retained R1 after visibly different R2 and retirement, planned 3 / actual 2, committed response loss, same-port server restart, exact retry, manager 2 → 1, original replay, separate 1 → 0 UI |
| Backup/restore | Five batches, all five command kinds, eleven receipts and two corrections; exact deterministic table contents plus restored self/other-Employee/manager authorization, contextual pin, replay, zero and runtime/session/plugin fencing |
| Update/recovery | Existing encrypted controlled upgrade through 0022, post-upgrade batch smoke and separate fenced pre-update recovery; actual populated 0021 acceptance is proved by the dedicated migration test |
| Full regression | Four package suites/analyzers/formatters, release Web/Compose, Recipe/Count and four prior Chrome workflows, numeric E2E, encrypted recovery, crypto, report redaction/diagnostics, print and setup |

Preliminary focused verification passes 38 preparation PostgreSQL cases, one
populated migration case, 52 preparation contract/error cases and 11 client cases.
The real HTTP and Chrome preparation journeys pass, including independent read-only
SQL identity/pin/count/receipt/audit checks and unchanged nonempty Stock/Count hashes.
Backup/restore and update/recovery acceptances pass with deterministic evidence.
The final frozen-source run is authoritative for all complete regression results.

The preliminary complete package suites pass **924 tests**: 171 API contracts,
408 server, 343 Flutter and 2 design-system tests. Nine conditional server hosts
are exercised in their dedicated opt-in HTTP/Chrome phases; they are not counted
as passing in the main suite. No test or assertion was removed to obtain these
results. Existing migration expectations were extended to include 0022.

`scripts/recipes/Run-P410FinalVerification.ps1` captures every tracked/nonignored
source/test/tool/doc file hash, size and write time after the last edit. It checks
hash equality and absence of inventoried writes after every phase, then saves
`.local/p410/final/source-before.json`, `source-after.json`, `summary.json` and
sanitized phase logs. These ignored local outputs are review evidence, not source.
No inventoried edit may follow the start of a successful final run.

## Scope and residual gates

No yield, output-unit calculation, fractional counts, ingredient multiplication,
consumption/reservation/produced Stock, costing, lots, traceability, labels,
Task Recipe pin, Shift/Workforce mutation, events/outbox, persistent offline queue,
sync or P4.11 capability is added. Boundary acceptance is not a capacity benchmark.
Memory-only client pending intent is lost on client reload; server receipts remain
durable. Existing M1 proxy/login pilot gate and operator/device/accessibility
policies are unchanged. At the implementation point, independent review,
security review and changed-commit CI were pending; Codex Security was not run
during implementation. The subsequent completed gates are recorded below.

See the [criterion evidence ledger](phase-4-10-preparation-batches-criteria.md)
for separate assessments of the supplied 156 hard acceptance criteria.

## Independent adversarial review and bounded remediation — 2026-10-07

Chronology is retained: the initial local implementation reported a **156/156
self-assessment**. The independent adversarial review returned **CHANGES REQUIRED**:

- **F01 — MEDIUM PRODUCT DEFECT:** a confirmed command followed by failed detail
  refresh could display misleading current evidence. The POST completion fixture
  incorrectly included the full GET projection, masking the bare-response case.
- **F02 — MEDIUM TEST/EVIDENCE GAP:** encrypted backup/restore did not prove
  exceptional historical Recipe context after replacement and retirement.

F01 is remediated entirely in Flutter. Command confirmation retains its result,
kind, batch identity and original completion separately. The controller clears
current detail/instruction and the affected resident history row when POST succeeds;
only a successful authoritative detail GET can restore detail and command forms.
Completion displays its confirmed count, lifecycle/version and actor/time without
inventing an effective count. Correction displays its confirmed number, previous
and replacement counts, actor/time and original completion. Corrected zero explicitly
retains completed lifecycle. Failed detail refresh presents an unavailable warning
and a reload action; follow-up corrections cannot use stale version/chain state.
History-only refresh failure does not invalidate a successful detail GET. Open and
both cancellation paths use the same distinction. Exact uncertain-command retry
binding, routes/bodies/operation identity and session fencing remain unchanged.

The focused suite passes **18 Flutter/controller/widget cases**, including bare
batch POST and actual correction-row shapes, completion 2 with failed GET, correction
2 → 1 and 1 → 0 with failed GET, blocked follow-up correction, later detail/chain
reload and warning clearance, and replacement-session fencing of a delayed reload
from refresh-failed state. The original eleven cases remain; no assertion is removed.

F02 is remediated only in fixture/verifier tooling. During normal HTTP Recipe
seeding, the five existing preparation batches open against Recipe R1 before its
replacement. R2 publishes visibly different batch description, preparation and
ingredient quantities; the Recipe then retires through its business API. Source
pre-backup probes establish retirement and published R1/R2 history, exact R1 pin,
own Employee and scoped-manager contextual reads, standalone Employee exclusion,
and other-Employee detail/context denial. The same probe runs after restore.
Canonical frozen-content SHA-256 includes every R1 label, unit, quantity and order;
R2 hashes differ while source/restored R1 hashes agree. Current retirement warnings
remain separate from frozen content. All eleven exact command replays retain
Recipe/batch/receipt/correction/audit/Stock hashes, with no reactivation or new batch.

The focused encrypted acceptance passes; sanitized evidence is retained in
`.local/backup-acceptance/495617b7fb3f43b5/report.json`. Its `preparation.historicalSource`
and `historicalRestored` record batch/Recipe/R1/R2 IDs, scoped authorization/exclusion,
retirement warning, distinct content hashes and read non-effect. Existing table
hashes prove exact backup content, including both revisions and command/audit evidence.
No Recipe text, ingredients or employee free text is added to the report.

The first strengthened acceptance attempt failed a newly added whole-database
comparison after recovery login. Existing recovery logins legitimately append
`auth.login` audit. The comparison boundary was corrected: exact source/restore
tables and sequences are compared before recovery login; contextual reads and
command replay compare business/audit content within the authenticated probe.
The failed attempt is retained as test-harness chronology, not a product defect;
its disposable databases were removed. No server behavior was changed.

Initial source manifests/logs are preserved under `.local/p410/initial-final/`.
The final frozen-source runner overwrites `.local/p410/final/` only with this
remediation's verification evidence. Its final summary determines whether all
156 criteria are PASS; criterion 153 requires every final-source phase to pass.
The initial full suite total was 924; the seven added client cases make the
expected complete package total **931**, with opt-in hosts separately exercised.
Never interpret pending/failed final phases as PASS.

Historical remediation-point state: **P4.10 IMPLEMENTED LOCALLY / INDEPENDENT REVIEW REMEDIATION
COMPLETE / TARGETED REVIEW PENDING / SECURITY REVIEW PENDING / REMOTE
CHANGED-COMMIT CI PENDING**. No DONE/CLOSED or P4.11 selection is claimed.
Remediation edits only the three Flutter controller/UI/test files, the four
backup-related Dart tools, and affected documentation. Server/domain/API contracts,
capabilities, grants, migrations, command receipts and Stock/Task effects retain
the reviewed implementation bytes. Main/baseline HEAD/index/dependencies remain
unchanged; no commit, push, install, normal-database write or Codex Security run occurs.

## Final documentation closure — 2026-10-07

P4.10 Preparation Batch is **DONE/CLOSED**. Before closure edits, `main` had a
clean tree/index at `e637187b17d4617212acf42b99a07500e9488c3d`
(Add preparation batch execution evidence), equal to cached and live
`origin/main`, with no stash and exactly one intended worktree. The latest
[CI run 37632074236](https://github.com/RobinBrohl/storeos/actions/runs/37632074236)
names that exact implementation commit. All five required jobs completed
successfully: dart, flutter, numeric-guided-work-e2e, backup-restore-acceptance
and update-recovery-acceptance. Baseline CI 37583520347 above is historical.

### Review chronology and final acceptance

| Point | Result and evidence |
| --- | --- |
| Initial implementation | READY FOR REVIEW; 924 package tests (171 API/contracts, 408 server/PostgreSQL, 343 Flutter, 2 design system); 19 final phases. These are historical initial figures. |
| Independent adversarial review | CHANGES REQUIRED; F01 MEDIUM PRODUCT DEFECT and F02 MEDIUM TEST/EVIDENCE GAP. |
| Bounded remediation | F01 CLOSED and F02 CLOSED; 931 package tests; 18/18 remediation-focused Flutter tests; 156 PASS / 0 QUALIFIED / 0 FAIL; 19/19 final-source phases PASS. |
| Targeted independent re-review | Supplied verdict APPROVE; F03 LOW documentation follow-up, explicitly nonblocking. |
| F03 docs-only remediation | CLOSED: stale current status and test-count references reconciled; historical intermediate figures preserved. |
| Focused Codex Security | Supplied verdict SECURITY APPROVE; zero confirmed/probable vulnerabilities, zero required security fixes and zero commit-blocking security defects. |
| Remote implementation CI | Exact implementation commit e637187b17d4617212acf42b99a07500e9488c3d; all five required jobs green in run 37632074236. |

Final package regression is **931 PASS**: **171 API/contracts**, **408
server/PostgreSQL**, **350 Flutter** and **2 design system**. Nine conditional
server hosts were exercised separately in opt-in phases, not counted as passing
main-suite cases. Existing `.local/p410/final/summary.json` records **19/19
phases PASS**; its regression log corroborates package totals. Focused Flutter
verification is **18/18 PASS**. Canonical acceptance is **156 PASS / 0 QUALIFIED /
0 FAIL**. Initial 924-test/19-phase evidence remains historical; it is not
retroactively relabeled as the final remediation run.

F01 separates confirmed command evidence from authoritative current detail:
failed refresh cannot present stale effective count as current, and further
correction is blocked until reload. F02 proves source/restored R1 Batch context
after different R2 publication and Recipe retirement, including own/manager
access, standalone exclusion and other-Employee denial. F03 closes stale docs.
No active P4.10 remediation remains.

### Delivered domain and replay boundary

PreparationBatch records an attributable Employee declaration that a whole
number of repetitions of one exact approved RecipeRevision's declared batch
were prepared. It does not represent kilograms, portions, physical yield,
sellable units, ingredient Stock consumption or produced Stock increase.
Planned count is null or **1..9999**, completion is **1..9999**, and correction
is **0..9999**. Correction zero preserves completed lifecycle and original
completion evidence.

Delivered scope includes Location-scoped execution evidence, exact published
RecipeRevision pin, server-derived Employee/Account identity, optional planning,
immutable original completion/cancellation evidence, append-only manager count
corrections including zero, five durable command receipt kinds and exact replay,
historical Recipe context through an authorized Batch, current/frozen Recipe
separation, Employee self workflow, manager history/cancellation/correction,
strict Company/Location isolation, session fencing, literal rendering,
backup/restore and update/recovery. Migration 0022 is delivered/accepted.
There are **no Stock effects, no Task/Shift effects and no yield/output-unit
semantics**.

Fresh opening requires valid current Recipe/Article/Assortment/Employee state
and the exact current publication. Once opened, the RecipeRevision remains
pinned: replacement does not upgrade it; retirement and Article/Assortment
changes do not rewrite it. Authorized Batch context can still resolve retained
historical instructions. A historical Recipe UUID alone grants no contextual
access.

The five durable kinds are **open**, **complete**, **employee_cancel**,
**manager_cancel** and **count_correct**, namespaced by **Company + operation
UUID**. Current authentication/capability/Location/resource scope precedes
receipt disclosure. Exact retries return original committed evidence.
Completion replay after later count correction still returns the original
completion result; fresh detail returns the current effective corrected count.

### Focused security conclusion and threat-model limit

The supplied focused Codex Security verdict is **SECURITY APPROVE**. No
confirmed/probable vulnerability, required security fix or commit-blocking
security defect was found. Its conclusions cover no IDOR/BOLA, cross-Company
or cross-Location leak, historical Recipe authorization bypass, receipt/replay
information leak requiring remediation, Employee impersonation, manager proxy
completion or correction privilege bypass; no SQL injection, unsafe dynamic SQL,
DB grant escalation or mutable terminal evidence through the runtime role; no
XSS/active-content path, sensitive audit/log leakage, stale-session disclosure,
cross-session pending-command execution, supported-writer TOCTOU authorization
defect, restore authorization widening or Stock/Task side effect.

These conclusions apply to supported application writers. Arbitrary privileged
DBA/direct runtime SQL remains outside that scope; closure does not strengthen
that accepted boundary or imply zero standing debt.

### Migration, standing debt and next step

The committed migration chain is **0001 → 0022**, ending at
`0022_preparation_batches.sql`; no migration 0023 exists. This closure edits
no migration, source, test, contract, dependency or generated report.

M1 proxy/login-limiter pilot gate, M2 CLOSED, M3 local API/error-contract
containment, M4 broader taxonomy inconsistency, supported-writer/raw-SQL limits,
memory-only uncertain-command recovery, physical-device/accessibility gaps,
P4.5 F01/F02 nonblocking follow-ups and P4.9 criterion 152 historical evidence
qualification remain as recorded in [technical debt](technical-debt.md).
P4.10 closes none of those standing items.

**P4.11 remains UNSELECTED**; no P4.11 capability is ACTIVE. Next is fresh P4.11
capability selection from clean main. This docs-only closure runs diff/consistency
checks, without rerunning the 931-test software suite, committing, pushing,
changing branches or writing to the normal database. Final-source reports remain
the retained implementation/remediation evidence; documentation closure is a
subsequent, explicitly scoped change.
