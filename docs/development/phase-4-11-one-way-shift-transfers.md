# P4.11: One-way Shift transfer before execution

Status: **P4.11 DONE/CLOSED** at implementation commit
`b82dda89374ed9b4182630de4991b0d1569b8ae8` (`Add one-way shift transfer`).
F01/F02/F03 are CLOSED. Targeted independent **APPROVE**, focused **SECURITY
APPROVE** and green exact-commit **CI 38125193187** establish closure.
P4.12 remains UNSELECTED and unimplemented.

The [177-criterion evidence map](phase-4-11-acceptance-evidence.md) gives individual
review locators. Final verdicts, exact counts and matching source fingerprints are
generated under ignored `.local/p411/final/` by the complete verification run.

The historical authoritative selection was the preceding “Plan StoreOS P4.11 selection” chat (`01a116c7-1536-7d73-9742-2f2ca5b374bb`). Baseline `main`, cached and live `origin/main` matched `d44ec9ad14bdbd774369e9106931a5d0e0750595`; the index/tree/stash were clean and only the existing main worktree existed. All five jobs succeeded in exact-HEAD [CI 37634196011](https://github.com/RobinBrohl/storeos/actions/runs/37634196011). The baseline migration chain was exactly 0001–0022. These checks were performed dynamically before implementation.

The slice transfers one complete pristine, future, published Shift to one named eligible colleague through recipient consent and independent manager approval. Source Employee is derived from the current Account↔Employee link. No published Shift or original Task is reassigned in place. Approval cancels originals, creates new exact replacement work and retains immutable Shift/Task lineage in the same transaction as request, command receipt and audit. See [ADR 0025](../adr/0025-one-way-shift-transfer-before-execution.md).

Workforce owns requests/receipts, Tasks owns Task correspondence, and the application coordinator communicates exclusively through public owner ports. Existing Company serialization protects source edits/execution, recipient overlap, employee/account/link changes and guidance changes. Fresh approval revalidates every captured basis. Early database-clock checks avoid unnecessary effects; the deferred transfer-specific approval invariant checks `clock_timestamp() < captured startsAt` last, after replacement materialization, receipt and audit writes at the final approval boundary. Exact guidance pins are retained; unavailable pins reject approval without replacement. Terminal history never reopens, and stale active requests require explicit closure.

Migration `0023_one_way_shift_transfers.sql` is the only new migration. It adds `workforce_shift_transfer_requests`, `workforce_shift_transfer_commands` and `task_transfer_links`, plus composite identity anchors on existing Account↔Employee links and Task instances. Both anchors express lineage/scope without rewriting data. Request guards protect immutable proposal/acceptance/terminal evidence; deferred receipt and approval constraints prevent partial durable approval. Runtime access is SELECT/INSERT plus only request lifecycle UPDATE columns. DELETE/TRUNCATE and receipt/lineage UPDATE are absent; no SECURITY DEFINER is introduced.

Initial permissions are `workforce.transfers.self.read`, `.self.request`, `.self.respond` for Employee, and those three plus `workforce.transfers.manage` for Admin. Viewer, Auditor and Plugin receive none. Approval additionally requires existing Shift management and Task instance read. Configured Company/Location and participant resource checks precede receipt reads. Proposer and accepter Accounts cannot approve even after elevation to Admin.

The eleven operations use `/api/v1/platform`: own Shift recipient picker; own transfer list/create/detail/accept/decline/withdraw; configured-Location manager list/detail/approve/reject. Strict JSON rejects unknown and duplicate decoded names. Bodies are capped at 8 KiB, close reasons at 500 Unicode code points, request and recipient pages at 50, cursor at 2,048 characters and exact Task evidence at ten. Scoped keyset cursors bind endpoint, Company, Location, Employee, filters and picker Shift/version. Candidate authorization and eligibility are filtered before the returned page limit; the existing Company employee maximum remains 200.

Company + operation UUID is the durable namespace. Every successful command binds actor, Location, request, kind, expected version and canonical payload. Replays require current session/capability/scope, then return original results before current lifecycle/business checks. Changed reuse conflicts. Failed commands leave the UUID reusable. Proposal and decline collect no free text; withdrawal and rejection require bounded reasons. Transfer audit carries IDs and lifecycle/version metadata only. Underlying normal Shift/Task publication/cancellation audits remain atomic.

Source Home offers a transfer action for eligible future work, shows exact interval/work/pins and a minimal recipient picker. Recipient history shows exact incoming work and explains that acceptance leaves the schedule unchanged. Manager history exposes consent, source version and exact replacement lineage. Source transfer history contains no replacement execution results and never grants ordinary replacement access. Replacement execution uses normal Guided Work.

Controllers retain immutable session-bound command intent only for uncertain outcomes and retry exactly. Confirmed success remains separately visible when the subsequent detail GET fails; no action uses the confirmed response as current detail. Definitive stale conflicts also clear actionable detail. Same-account session replacement clears transfer state and fences delayed GET/POST outcomes. Colleague names, titles and reasons render as literal Flutter text.

Verification entry point: `scripts/transfers/Run-P411Checks.ps1`. It creates a validated run-owned Compose project using the already installed PostgreSQL image (`--pull never`), uses strictly disposable databases and removes only that project's containers/network/volume. The normal StoreOS services were stopped before acceptance and stay stopped. The wrapper never connects to the normal database. No dependencies are installed or upgraded.

The source contains contract/domain/controller/widget tests; HTTP/PostgreSQL lifecycle, current auth, independent approval, link replacement, strict transport, scoped pagination and replay tests; complete ten-Task lineage; both observed serialized orders of amendment, cancellation, execution/time boundary, recipient overlap, identity changes, guidance changes, withdrawals and rejection; and six approval-stage fault tests comparing full pre-command evidence hashes. Populated actual 0022 migration checks retain nonempty Recipe/PreparationBatch/Stock/Count/Task/guidance/audit evidence, prove late 0023 catalog/data rollback, then exercise all states and receipt kinds through production commands.

Encrypted backup/restore snapshots include requests, receipts, both lineage forms, Task snapshots, selections and audit. The fixture seeds nine requests spanning all six states and 21 receipts spanning all seven command kinds. Restored participants/managers replay originals without business changes, outsiders are denied, and existing Location/session/plugin fencing remains enforced. Update/recovery applies the complete pending chain through 0023 and exercises the same transfer smoke. Recovery remains an isolated pre-update restore, not a down migration.

Restored transfer probes also authenticate real Viewer/Auditor accounts seeded
through Identity APIs, deny both participant and manager routes, deny a registered
other Location before receipt disclosure and deny that Location's manager access
to restored transfer evidence. Probe sessions are revoked before fencing is checked.

Real Flutter and Chrome fixtures use the production server and restricted runtime role with exact schema-4 Knowledge/Planogram pins, confirmation/numeric steps and nonempty unrelated evidence. A gateway loses a committed approval response, restarts the server, checks the exact retried body and confirms conserved Shift/Task/link/receipt/audit hashes. An imminent real interval is set with the supported amendment command after browser compilation; ordinary execution waits for that interval and is authorized by the server. No test-only business write or clock API exists.

Final-source verification records are generated under ignored `.local/p411/`. `Fingerprint-P411Source.ps1` hashes every tracked and nonignored new source file, including docs/tests/tooling. The final verification run requires identical before/after fingerprints, formatter/analyzer/package tests, release web build, Compose validation, real journeys, existing browser/numeric acceptance and encrypted recovery scripts. Opt-in suites are counted separately; skipped ordinary-run opt-ins do not count as verified acceptance. The retained final remediation report records exact final counts and the reassessed 1–177 acceptance ledger on the frozen source; the closure below records their canonical results. At that historical implementation/remediation point, targeted independent review, Codex Security and remote changed-commit CI remained pending; the final closure below supersedes those gates.

No events/outbox, notification delivery, scheduler mutation, offline device write/sync contract, Stock/Count/Recipe/PreparationBatch business effect, recurring roster, two-way swap or adjacent P4.12 capability was added. This documentation closure authorizes no branch change, commit, push, staging or destructive Git action.

## Historical independent review and bounded remediation — 2026-10-08

The initial implementation self-assessed **177 PASS / 0 QUALIFIED / 0 FAIL**.
The independent adversarial review returned **CHANGES REQUIRED**, with
**172 PASS / 4 QUALIFIED / 1 FAIL**. That review remains part of the delivery history:

- **F01 — MEDIUM PRODUCT DEFECT / COMMIT BLOCKER:** approval could complete after
  the source Shift started because only the pre-effect boundary was checked.
- **F02 — LOW DOCUMENTATION DEFECT / NONBLOCKING:** canonical next-work statements
  still described P4.11 as unselected and fresh selection as next.
- **F03 — LOW TEST/EVIDENCE GAP / NONBLOCKING:** the requested identity/guidance
  race matrix was incomplete.

F01 extends the existing deferred `transfer_approval_complete` constraint in the
still-new migration 0023 with `transfer_approval_future`, evaluated after its exact
replacement checks. A separate application clock query would leave intervening
receipt, audit and deferred-validation time uncovered. The deferred invariant is
the smallest existing transaction-boundary mechanism and changes no stored shape,
grants, immutability rules, global Shift publication rule or runtime threat model.
It maps only this named constraint to the existing `422 shift_not_transferable`.
The failed transaction retains the accepted request and pristine published source,
with no cancellation, replacement, lineage, approval receipt/audit or consumed UUID.
Receipt-first exact committed replay performs no request UPDATE, so later replay
after startsAt still returns the original evidence under current authorization.
OpenAPI response vocabulary and reachable status metadata are unchanged.

The regression observes an advisory-lock wait at the final transfer audit INSERT,
after production replacement publication and receipt insertion. It releases while
future for success, or polls authoritative database time through startsAt before
release for full rollback. Clock passage determines only the real time boundary;
observed PostgreSQL locks establish ordering. The success case checks the final
boundary remained future, then restarts and replays after startsAt without effects.
The rejection case compares complete business/audit hashes and reuses the UUID in
a valid manager rejection. The execution-first and approval-first tests also check
the appropriate durable outcome.

F02 replaces only stale current next-work statements in HANDOVER and actual status;
historical clean-main capability-selection chronology remains preserved. P4.12 is
UNSELECTED. At that historical point P4.11 remained implemented locally, with
targeted review, security review and remote changed-commit CI pending; it was
not yet DONE/CLOSED.

F03 adds both observed Company-lock orders for source unlink, Employee deactivation
and Account deactivation. Approval-first preserves exactly one coherent replacement;
mutation-first rejects without transfer effects. Source and recipient replacement-
Account linking and same-Account relinking are tested in both orders of link creation
versus approval. Link creation requires prior revocation: there is no atomic replace-
link endpoint. Both creation orders must reject because captured L1 is already
revoked, and the new L2 never revives captured consent. The existing revoke-versus-
approval matrix proves approval can precede revocation coherently.

Guidance coverage observes both orders for Knowledge publication and retirement,
Fixture retirement, Planogram revision publication and replacement deployment.
New publication keeps old eligible exact pins. Retirement or replacement deployment
first rejects atomically; approval first preserves the exact old snapshot despite
later mutation. Tests assert database evidence, one-to-one lineage, absence of failed
effects and exact replay without duplicate effects. No adjacent product behavior is
added. Fresh focused and final-source results, exact counts and all 177 reassessments
are retained in ignored `.local/p411/` reports after verification. Targeted independent
review, Codex Security and remote changed-commit CI were still pending at that historical remediation point; all are resolved in the final closure below.

Remediation-focused verification passed: 64 transfer HTTP/PostgreSQL tests, 14
guidance tests and one populated 0023 migration test (79 total). Server analysis,
documentation-link validation and the stale-current-wording check passed. Remediation
is complete locally; the complete final-source results and 177-criterion reassessment
are recorded after the frozen-source run in .local/p411/final/acceptance.md.

The first remediation final run passed all 1,133 package tests, analyzers,
formatters, release Web build, Compose and the transfer HTTP journey, then stopped
at Chrome approval. An unchanged isolated retry reproduced the cause: the old
20-second success-journey interval expired during the three browser identity
transitions (one run disabled the approval action; the retry reached the server
and received `shift_not_transferable`). The Chrome success fixture now allocates
60 seconds, waits explicitly for the real replacement execution interval, and
additionally asserts database time is still before captured startsAt after the
approval response. No existing outcome/evidence assertions are removed. The
deterministic before-start/cross-start audit-barrier regressions remain unchanged.
Failed attempts are preserved separately; all final phases are rerun after these
harness edits on a new frozen inventory.

The corrected focused Chrome journey passed, including every terminal/failed-
approval path and full persisted evidence checks. Both affected analyzers passed.
Focused remediation evidence is 79 HTTP/PostgreSQL/migration tests plus this real
Chrome journey. The final-source verification summarized below reran every required phase.

## Final documentation closure — 2026-10-11

**P4.11 ONE-WAY SHIFT TRANSFER BEFORE EXECUTION — DONE/CLOSED.**
Canonical implementation commit: `b82dda89374ed9b4182630de4991b0d1569b8ae8`,
message `Add one-way shift transfer`. Before closure edits, `main` had a clean
working tree/index, no stash and exactly one worktree, `C:/dev/storeos`.
HEAD matched cached and live `origin/main`. P4.1–P4.10 were already DONE/CLOSED.
No active P4.11 remediation or selected/ACTIVE P4.12 capability remains.

### Implementation and exact-commit CI

[CI 38125193187](https://github.com/RobinBrohl/storeos/actions/runs/38125193187)
was dynamically verified as **completed / success**, on `main`, with
`head_sha = b82dda89374ed9b4182630de4991b0d1569b8ae8`. All five required jobs
were **completed / success**: `dart`, `flutter`, `numeric-guided-work-e2e`,
`backup-restore-acceptance` and `update-recovery-acceptance`.
This is the P4.11 implementation-commit result; earlier P4.10 closure CI and
the historical clean-main P4.11 selection baseline prove their own commits.

### Review chronology and remediation closure

| Stage | Result |
| --- | --- |
| Initial implementation | READY FOR REVIEW; self-assessed 177 PASS / 0 QUALIFIED / 0 FAIL; 1,111 package tests and 21 verification phases at that historical point. |
| Independent adversarial review | CHANGES REQUIRED; 172 PASS / 4 QUALIFIED / 1 FAIL. F01 MEDIUM product defect / COMMIT BLOCKER; F02 LOW documentation defect / NONBLOCKING; F03 LOW test/evidence gap / NONBLOCKING. |
| Bounded remediation | F01 CLOSED: final deferred advancing-clock approval check. F02 CLOSED: HANDOVER/status selection wording reconciled. F03 CLOSED: deterministic both-order identity/link and Knowledge/Planogram race coverage. |
| Targeted independent re-review | Supplied verdict APPROVE; final acceptance 177 PASS / 0 QUALIFIED / 0 FAIL. No remaining actionable finding or commit blocker. |
| Focused Codex Security | Supplied verdict SECURITY APPROVE; all 75 changed/new P4.11 files reviewed; no confirmed/probable vulnerability, required security remediation or security commit blocker. |
| Implementation publication | Named commit on main; exact changed-commit CI 38125193187 green across all five required jobs. |

F01 originally allowed approval to begin while future but commit after Shift
start. Migration 0023's deferred approval invariant now evaluates authoritative
PostgreSQL `clock_timestamp()` at final approval/commit validation. Crossing
`startsAt` rolls back the transaction: the source remains published/pristine,
no replacement or Task lineage survives, and no approval receipt/audit survives.
The operation UUID remains reusable and the response is bounded
`422 shift_not_transferable`. Exact committed replay after `startsAt` remains valid.
F03 closes the missing identity/guidance both-order matrix described in the
historical remediation section; no additional product scope was selected.

### Delivered domain contract and hard boundaries

A one-way Shift Transfer records the source Employee's request to transfer one
complete future pristine published Shift to one exact named eligible recipient.
Explicit recipient acceptance is consent only and does not transfer schedule
ownership. Source withdrawal, recipient consent withdrawal, decline and manager
rejection are supported. Independent manager approval atomically cancels the
original Shift/Tasks and publishes new replacement Shift/Tasks for the recipient,
preserving the exact interval, Template revisions, Knowledge pins and Planogram
pins. The original Shift is never reassigned in place. Immutable Shift provenance
and complete one-to-one Task lineage retain both identities. Source, recipient
and manager Flutter workflows, durable receipts and exact replay are delivered.

Fresh proposal and final approval require a published, still-future source Shift,
pristine source Tasks, correct source ownership, an eligible exact recipient,
valid captured identity/link bases, no recipient overlap and exact retained
guidance still eligible for fresh publication. Final future correctness uses
the authoritative advancing database clock at the final approval boundary.

Consent binds the exact captured Account↔Employee linkage basis. Both source
and recipient bases are revalidated. `L1 → revoked → L2` never permits L2 to
inherit or revive L1 consent. Manager approval requires current management
authority and an approving Account different from both proposing and accepting
Accounts. Admin privilege does not bypass independence; transfer management
grants no proxy Guided Work execution.

Exact source Template revisions, Knowledge pins and Planogram pins are never
substituted with latest. Unavailable exact guidance at fresh replacement
publication rejects approval atomically. Later publication, retirement or
redeployment does not rewrite already approved replacement evidence.

The seven command kinds are `propose`, `accept`, `decline`, `source_withdraw`,
`recipient_withdraw`, `manager_reject` and `manager_approve`. Their durable
namespace is Company + operation UUID. Current authorization/resource scope
precedes receipt disclosure; exact committed replay returns the original outcome
before fresh lifecycle/time validation. Approval replay after start does not
republish work. Failed transactions leave no durable receipt.

Transfer provenance creates no execution authorization. Source history may show
transfer/lineage evidence but excludes recipient confirmations, numeric values,
blocking evidence and completion results. The recipient gains ordinary execution
access through replacement ownership after approval. The recipient picker remains
a narrow eligible-recipient picker, not an Employee directory.

Database durability protects immutable proposal identity, interval and
source/recipient identities, retained linkage bases, one active request per
source Shift, immutable terminal requests and receipts, append-only one-to-one
Task links, exact Company/Location scope and the final deferred future constraint.
Runtime grants are narrow: no DELETE/TRUNCATE, receipt/Task-link UPDATE or new
SECURITY DEFINER. No reachable P4.11 business write targets Stock, StockMovement,
StockCount, Recipe, RecipeRevision, PreparationBatch or outbox/events.
Knowledge/Planogram involvement is read/validation only.

Excluded: reciprocal swap, marketplace, partial Shift transfer, interval editing,
Template-selection editing, begun-work transfer, notifications, recurrence,
Recipe Task pinning, PreparationBatch effect, Stock effect and multi-site transfer.

### Focused security conclusions

The supplied SECURITY APPROVE explicitly retains these conclusions within the
supported-path threat model:

- No source Shift IDOR/BOLA or request IDOR/BOLA; no recipient impersonation,
  consent inheritance after relinking or consent resurrection after revocation.
- No manager self-approval bypass or manager proxy execution; no cross-Company
  leak, cross-Location leak, recipient-picker privacy leak or participant-history
  execution leak.
- No protected receipt disclosure, operation UUID aliasing weakness or replay
  republishing.
- No supported-path final-time invariant bypass, frozen transaction-clock bug,
  incomplete rollback path or Task-lineage integrity bypass.
- No runtime terminal-evidence mutation, receipt mutation/deletion or Task-link
  mutation/deletion.
- No SQL injection, unsafe dynamic SQL, SECURITY DEFINER/grant escalation or
  strict-JSON authority ambiguity.
- No cursor cross-user/location leak, exact-pin substitution or identity/guidance
  TOCTOU gap.
- No stale-session disclosure, cross-session pending-command execution,
  active-content/XSS path or sensitive audit/log leak.
- No restore authorization widening, migration/recovery privilege widening or
  Stock/Recipe/PreparationBatch side effect.

Arbitrary privileged DBA/direct runtime SQL remains excluded. This docs-only
closure records the supplied review; it does not claim a new security scan.

### Final acceptance and recovery evidence

Canonical final targeted acceptance is **177 PASS / 0 QUALIFIED / 0 FAIL**.
The retained final remediation run in `.local/p411/final/acceptance.md` records:

| Final-source evidence | Result |
| --- | --- |
| API/contracts | 238 PASS |
| Server/PostgreSQL | 526 PASS |
| Flutter | 367 PASS |
| Design system | 2 PASS |
| Package total | 1,133 PASS |
| Complete verification phases | 21/21 PASS |
| Conditional journeys | 11/11 PASS; counted separately from package tests |
| Numeric browser stages | 3/3 PASS |
| Frozen pre-closure source inventory | 536 files |
| Frozen pre-closure source fingerprint | `e5f3b4f4f5d02906368ad1213a26e889752bb5b0120882deafd5908c8eb92dec` |

The fingerprint identifies the verified final implementation source before
these documentation closure edits; it is not a fingerprint of the edited docs.
Historical initial counts remain 1,111 package tests and 21 verification phases.

Backup/restore preserves transfer requests/states, command receipts, exact
snapshots, Shift lineage and Task lineage, scoped authorization, exact replay
and fencing. Update/recovery proves clean 0001→0023, populated 0022→0023,
legacy evidence preservation, late-failure rollback, transfer smoke/replay and
a fenced recovery point.

The delivered migration chain is **0001 → 0023**; latest is
`0023_one_way_shift_transfers.sql`, containing transfer persistence and the
final deferred approval boundary. Migrations 0001–0022 remain historical and
immutable. This closure leaves every migration unchanged and creates no 0024.

### Standing debt, next step and closure validation

M1 proxy/login-limiter pilot gate, M2 CLOSED, M3 local API/error-contract
containment, M4 broader taxonomy inconsistency, supported-writer/raw-SQL
boundary, memory-only uncertain-command recovery, physical-device/accessibility
gaps, P4.5 F01/F02 nonblocking follow-ups and P4.9 criterion 152 historical-evidence
qualification retain their existing dispositions. No global zero debt is claimed.

**P4.12 remains UNSELECTED.** Next is fresh P4.12 capability selection from clean
main. No Task + Recipe pin, Supplier Master, Purchase Order, Goods Receipt,
Recurrence, HACCP, production planning or other next capability is selected here.

Local closure validation is `git diff --check`, complete documentation diff and
consistency review, changed-path verification, `git status` and `git diff --stat`.
Software regression, migrations and business acceptance are not rerun solely
for Markdown edits. Only documentation remains unstaged/uncommitted; HEAD stays
the implementation commit, with no branch change, staging, commit or push.
Production code, tests, migrations, contracts and dependencies are unchanged.
The normal database is untouched by this closure.
