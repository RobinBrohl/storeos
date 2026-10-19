# P4.16 Stage B4 — recovery and final acceptance evidence

## Current independent acceptance and publication gates — 2026-10-18

As of 2026-10-18, Europe/Berlin, B4 functional review and B4 security review are
both **PASS WITH QUALIFICATIONS**. **B4-F01 and B4-RR01 are CLOSED**. A01–A16 are
**16 PASS / 0 QUALIFIED / 0 FAIL within the supported public application
contract**. **A08, A12 and A15 are PASS**. P4.16 remains **IN PROGRESS**.

The [final functional review](../../.local/p416-b4-json-rereview-20261018/Review.md),
[A08 acceptance addendum](../../.local/p416-a08-independent-20261018/Review.md)
and [sealed independent security report](C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/edf844323cfb5ad39edd63dcc6a0d288897e9fb8_20261018T124933Z_wvey1ay5/report.md)
establish these verdicts for the original reviewed snapshot, whose source-manifest
SHA-256 is `4EDBBF7300B25546442E48BD951FDCAF8CE29B0B21E456EC69CF4423312597F7`.
A08 adds 44 observed PostgreSQL queue cases and five occupancy/P4.11 controls;
its 16 deactivation cases overlap retained observations. The current Employee
assignment boundary is the supported deactivation API, without a separate
interval-edit writer. A12 retains its actual server restart/completed-request
response-loss evidence; A15 passes within the documented isolated recovery and
report-integrity contract.

The B4 implementation is eligible for Git integration, subject to the current
publication gates: independent targeted approval of the explicit three-file
CRLF-to-LF canonicalization exception and this documentation-only reconciliation,
then exact candidate-manifest verification and the separately authorized
integration process. These candidate bytes are not claimed byte-identical to
the earlier review snapshot. No integration, exact integration-head CI,
deployment or P4.16 closure has occurred.

Nonblocking evidence erratum: the generated swap/swap control summary displays
one transfer link; the authoritative raw record contains **zero transfer
receipts and zero links**. Each of the four actual P4.11 controls has one link.
The raw evidence and earlier summary remain preserved. All historical skips,
failed invocations, unfinished-upload **0 PASS / 2 FAIL, NOT RERUN**, operational
qualifications and P4.15 Q1–Q6 remain binding; functional PASS does not establish
production deployment readiness.

## Historical local remediation record — before final independent approval

The dated verdicts and matrices below describe their original review snapshots.
Their earlier CHANGES REQUIRED, A08 QUALIFIED, A15 FAIL and review-pending labels
are superseded for current acceptance only by the independent verdicts above.
Original failures, remediation history and qualifications are retained unchanged.

2026-10-18, Europe/Berlin. **B4 FUNCTIONAL RE-REVIEW — CHANGES REQUIRED.**
P4.16 remains **IN PROGRESS**. The independent matrix remains **14 PASS /
1 QUALIFIED / 1 FAIL**: A08 QUALIFIED, A12 PASS with its independent actual
restart/completed-request wire-loss evidence, and A15 FAIL pending targeted
independent re-review. B4-F01 (P2) is independently CLOSED. B4-RR01 (P2) has the
local correction below; independent closure and the separate Security re-review
remain pending. No staging, commit, push, PR, merge, deployment or release.

## B4-RR01 JSON-escaping redaction remediation — 2026-10-18

Local outcome: **B4 JSON REDACTION FIXED LOCALLY**. Both guards previously scanned
raw JSON for sensitive values and patterns, then decoded it only for duplicate
names and semantic checks. Valid JSON escapes could hide a registered synthetic
value in `reviewNote`, a forbidden property name or a connection scheme. The
unknown optional field survived mandatory-field validation. Both real wrappers
therefore retained the report and returned 0 with a sanitized-success claim.

The unchanged [independent re-review](../../.local/p416-b4-targeted-rereview-20261018/Review.md)
and its original scripts, payloads and logs are preserved. Before source edits,
all 21 reviewed paths, 29 migrations, the empty byte-identical index and retained
manifests/evidence matched. The independent reviewer was idle and its completed
snapshot was frozen. The original 74-case driver ran unchanged, with only its
output directory redirected: **68 expected outcomes / six unexpected accepts**.
The unchanged eight-call actual-wrapper driver reproduced both encoded-secret
failures: **exit 0, report retained, owned databases removed**. The raw
serialization uses JSON Unicode escapes for each UTF-16 code unit; decoding
reconstructs the registered synthetic value exactly. Payloads are private
synthetic evidence; values are never printed in diagnostics.

Only five paths change relative to that reviewed snapshot: both
`Assert-*AcceptanceReport.ps1` guards,
`scripts/backup/Test-P416RecoveryReportJsonRedaction.ps1`,
`scripts/backup/Test-P416RecoveryReportCallers.ps1`, and this handoff. No wrapper,
business logic, migration, contract, dependency or approved Stock Count correction
changes. The guards' semantic assertions from `$schema` onward remain unchanged.

The guards strictly parse UTF-8 JSON, retain raw checks, inspect decoded names and
strings throughout objects/arrays, reject ambiguous decoded names, and inspect
JSON-shaped strings through up to four nested encoding layers. Literal backslash
text is not globally JSON-unescaped. Registered values remain ordinal, including
case-distinct values. Raw, URI and Base64 checks remain; one bounded URI view
handles percent-hex case and escaped unreserved characters, and a Base64-only
comparison handles its permitted ASCII whitespace. These views inspect evidence
without rewriting it. Forbidden decoded credential/header/private-field patterns
are refused. Limits are 4 MiB per file, depth 64, 32,768 visited elements/member
names and 8,388,608 UTF-16 code units of aggregate inspected text, including derived views. Malformed,
unsupported, over-limit and decoder failures refuse with static diagnostics;
invalid surrogate property getters returning null also refuse.

A fresh read-only investigator and one fresh read-only candidate reviewer were
used under the security-finding remediation workflow. The candidate reviewer
identified equivalent URI and line-wrapped Base64 gaps. The parent reproduced
all six against the actual guards and corrected them within the same boundary;
the exact same six inputs now refuse. These local checks are not independent
B4/A15 or Security approval.

Final verification, with separate overlapping invocation counts:

- **460 JSON-redaction PASS / 0 FAIL**: 434 refusals and 26 valid controls,
  including mixed Unicode/slash/backslash/control/surrogate encodings, nested
  objects/arrays/member names/serialized JSON, raw/URI/Base64 variants, parser
  and getter failures, missing/wrong-type fields and all resource limits.
  Inputs remain byte-identical; rejection diagnostics contain no probe value.
- Original unchanged driver: **74/74 expected outcomes**, including all
  **16/16 original semantic counterexamples refused** and both valid fixtures.
- **1,885 semantic PASS / 0 FAIL**, existing **8 report PASS / 0 FAIL**, and both
  existing redaction scripts PASS. Historical compatibility remains **171/171**:
  12 complete PASS accepted, 48 historical FAIL accepted only as failures,
  111 old/incomplete PASS refused as current proof.
- Final unchanged actual-wrapper cohort: both real encrypted positives **exit 0**;
  all six proof/result/escaped-secret mutations **exit 1**, with reports removed
  and no sanitized-success claim. The two permanent JSON caller controls also
  require **exit 1**, report removal and no sensitive diagnostic. Each negative
  validates the completed real PASS report before mutation.
- Complete eligible server: **1,054 PASS / 0 FAIL / 23 SKIP**, native exit 0.
  All 23 historical SKIP identities/reasons are preserved. P4.11/P4.15/P4.16
  eligible recovery coverage ran there. Four encrypted legacy recovery opt-ins
  separately completed **4 PASS / 0 FAIL / 0 SKIP**; package SKIPs remain SKIPs.
- Server analyzer: no issues. Nonwriting formatter: **266 files / 0 changed**.
  Ten PowerShell scripts parse; Git whitespace passes. Contracts are unaffected;
  the independent **440 PASS** evidence and unchanged sources remain preserved.

Final source/runtime provenance, all owned-database/container removal, transient
artifact removal, free acceptance ports and emptied disposable test credentials
are independently checked. The operating database remains present. Historical
pre-fix synthetic reports remain explicit untrusted failure evidence; no rejected
final report is published as sanitized. All earlier failures, intermediate
candidate runs, original findings and manifest versions remain unchanged.

Current checkout inventory: **22 uncommitted paths**, with **five remediation
deltas** from the reviewed 21. HEAD/origin/main remain
`edf844323cfb5ad39edd63dcc6a0d288897e9fb8`; all 0001–0029 migration hashes/Git blobs
and the empty, byte-identical index are preserved. Exact current hashes,
immutable source copies, full invocation history and archive fingerprints are
in the [RR01 remediation evidence](C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/artifacts-5420764a3efc21a5bec770757c2d046dfcf033b4bb3bac8cde029f832158e5b7/artifacts/b4-rr01/Remediation.md) and
[new final manifest](C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/artifacts-5420764a3efc21a5bec770757c2d046dfcf033b4bb3bac8cde029f832158e5b7/artifacts/b4-rr01/final-manifest.json).
Earlier handoff sections below retain their dated historical results/inventories.

A08 remains QUALIFIED; A12 remains PASS at its original independent boundary;
A15 remains FAIL. The historical **23 SKIPs**, earlier 21 opt-ins, unfinished-upload
**0 PASS / 2 FAIL, NOT RERUN**, device/operator/privacy/ingress/key-custody/off-host
recovery/RPO/RTO/activation and P4.15 Q1–Q6 qualifications remain. Functional and
Security targeted re-review are required. B4 remains CHANGES REQUIRED and P4.16
IN PROGRESS; no integration or closure is claimed.

## Stock-count regression remediation — 2026-10-18

The full-server failure was independently reproduced using the unchanged test
body from approved HEAD `edf844323cfb5ad39edd63dcc6a0d288897e9fb8`:
**18 PASS / 1 FAIL / 0 SKIP**, stopping at attempt 19. All 372 archived source,
test and lockfile objects matched HEAD. The original and supposedly other count
both had ID `f711e9ea-80a3-4361-8e63-e91fb1548068`. A separate controlled case with
the original UUID larger than all 50 additional UUIDs reproduced the same failure.
The test creates the original first, but the scoped query sorts by ID rather than
creation time. The last page can therefore contain the original count; its own
cursor correctly returns 200, contradicting the test's expected 400.

The only test correction is in `apps/server/test/stock_count_integrity_cases.dart`:
select the first ID in the already verified complete, sorted list that differs
from the original, with no fallback, and explicitly assert the IDs differ. The
original expected-400 cross-count cursor assertion remains strict. Controlled
maximum/minimum original-ID cases and the normal target test pass after the fix.
No production Stock Count, recovery fixture, API contract or migration changes.

Final local outcome: **B4 REGRESSION GREEN — READY FOR RE-REVIEW**. The complete
eligible server suite finished **1,054 PASS / 0 FAIL / 23 SKIP**, native exit 0;
focused Stock Count **29 PASS / 0 FAIL / 0 SKIP**. Server analyzer: no issues;
nonwriting formatter: 266 files, zero changed. Recovery checks rerun: all original
16 contradictions rejected, **1,885 semantic PASS / 0 FAIL**, eight existing report
checks PASS, both redaction scripts PASS, and valid-report compatibility unchanged.
Contracts were unaffected and not rerun; prior **440 PASS** remains hash-verified.
The earlier red full-server counts below remain historical invocation records;
this result supersedes only the current regression status, not independent approval.

The previous [report](../../.local/p416-b4-report-remediation-20261017/Remediation.md),
[manifest](../../.local/p416-b4-report-remediation-20261017/final-manifest.json),
original P2/16-case evidence and every failed invocation remain unchanged.
Fresh verification, exact hashes and the appended manifest version are recorded
in the [stock regression report](../../.local/p416-b4-stock-regression-20261018/Regression.md)
and [final manifest](../../.local/p416-b4-stock-regression-20261018/final-manifest.json).
A08 remains QUALIFIED, A12 PASS with independent restart/completed-wire-loss
evidence, and A15 FAIL pending independent targeted re-review. B4 remains
CHANGES REQUIRED and P4.16 IN PROGRESS; functional and Security re-review remain
gates. The 23 historical server SKIPs, earlier 21 opt-ins, unfinished-upload
0 PASS / 2 FAIL (not rerun), and inherited operational/P4.15 qualifications remain.

## B4-F01 report-integrity remediation — 2026-10-17–18

Local outcome: **B4 REPORT INTEGRITY FIXED LOCALLY**. Targeted independent
re-review is required before changing the original A15/B4 verdict.

The complete original [independent review](../../.local/p416-b4-functional-review-20261017/Review.md)
and its verdict, harness and JSON counterexamples remain unchanged. Before edits,
all 15 reviewed source hashes, 29 migration hashes/Git blobs, 53 supporting sources
and 110 retained evidence hashes matched the original manifest. HEAD/tree and the
empty index matched. The original 15 source files were copied into the remediation
[reviewed snapshot](../../.local/p416-b4-report-remediation-20261017/reviewed-snapshot/).
The independent review chat was idle and no active Security review was observed
at that boundary; source bytes were preserved before mutation.

The root cause was conditional validation: a missing/unknown schema or a changed
result bypassed all B4 semantic checks. Even a recognized PASS only checked a
subset of proofs and iterated the supplied update table set. The actual guards
now validate the supported schema/result/classification before interpreting
success, check JSON types before comparing values, require completed phase
prefixes, bind run-owned database identities, and require explicit cleanup.
PASS additionally requires the complete versioned fixture evidence, source/fence
and historical-preservation proofs, matching counts/digests/sequences, migration
prefix/order/checksums, a no-op second migration run and consistent injection
metadata. The backup contract requires all 56 selected tables, including seven
shared claims (five swap/two transfer), and binds its duplicate swap digest sets.
The update contract distinguishes the 29-migration source from the isolated
10-migration target. Counts describe these named fixtures, not every workflow.
Strict JSON parsing rejects duplicate and case-colliding member names before
PowerShell can select one value. Six fresh raw-JSON contradictions were reproduced
as ACCEPTED before that correction and REJECTED afterward. Each wrapper now
passes its actual tracked run result into the guard; a valid historical FAIL
artifact cannot certify a successful current wrapper run. These two bounded
call-site changes do not change recovery orchestration.

Validation permits an honest `failed`/`FAIL` artifact to be retained; that never
certifies successful recovery. Historical unversioned FAIL and earlier B4 FAIL
variants are explicitly recognized only as failures, with typed identity, phase,
failure and cleanup checks. Earlier FAIL artifacts can lack later provenance or
negative-proof fields. A missing marker cannot admit a PASS artifact. The actual
wrappers emit only `pass/PASS` or `failed/FAIL`; unsupported SKIP/QUALIFIED report
results and mixed classifications are rejected. Historical review SKIP/QUALIFIED
dispositions remain intact. Digest validation checks format and reported
relationships; it is not independent attestation that a report's claims are true
or that its historical source digests equal today's checkout.
An unexpected restore success during a negative test remains explicit FAIL
evidence; mutually contradictory negative outcomes and promotion to PASS are
rejected. PostgreSQL count evidence must fit its signed 64-bit JSON integer type.

The unchanged original harness was executed before and after the fix. A host
`Join-Path` shim redirected only its hardcoded output directory, preserving the
original reviewer artifacts. All 16 emitted JSON files were byte-identical to
the original corpus: **16 ACCEPTED before / 16 REJECTED after**. Per-case exact
contradictions, expected/observed outcomes, SHA-256 values and source references
are in [original-case-reconciliation.json](../../.local/p416-b4-report-remediation-20261017/original-case-reconciliation.json).

The deterministic [semantic suite](../../scripts/backup/Test-P416RecoveryReportSemantics.ps1)
checks all required fields with deletion/type mutations and additional independent
phase, classification, count/hash, sequence, identity, migration, provenance,
injection and cleanup contradictions. Sanitized fixed JSON inputs are explicitly
unit fixtures. Both redaction scripts retain their raw/URL/Base64 checks and now
use real-schema positive controls; rejection must be specifically for redaction.
The opt-in [actual-caller test](../../scripts/backup/Test-P416RecoveryReportCallers.ps1)
uses a debugger checkpoint at the actual wrapper's validation call, first
validates the completed real report, then corrupts only its sanitized JSON. It
requires child exit 1, the correct validation diagnostic and removal of the
invalid published report. Fault injection uses no production hook and does not
edit wrapper source files.
The final deterministic suite records **1,885 PASS / 0 FAIL**, including honest
failed-artifact compatibility and refusal of invalid result promotion. The
existing eight report checks and both redaction scripts also pass. All 46 retained
historical failed reports remain accepted as failed artifacts; four original and
independent final PASS reports remain valid.
An archive-wide inventory accepts all 12 complete versioned PASS reports (those
four original/independent reports and eight local positive executions). It refuses
107 pre-B4 unversioned PASS artifacts and four intermediate B4 PASS artifacts as
current B4 proof: the latter lack final provenance, negative-recovery metadata or
the later stale-transfer proof. Their bytes and historical PASS labels remain
unchanged; no historical run is reclassified. The final evidence report lists the
exact missing fields and archive inventory. Current recovery fixtures are unchanged.
The first full server invocation also retains an unrelated stock-count fixture
failure: its last pagination item could be the original count, so its supposed
cross-count request was a valid same-count request (200 versus expected 400).
Decoded cursor and route identities prove the collision, and the fixture blob
matches approved HEAD. No stock code/test was changed. The unchanged full suite
was rerun in isolated containers; invocation counts and the original failure
remain separate in the final evidence report. The first retry also retains four
timeout failures across large elapsed-time jumps; their cause is unproven. A later
startup attempt encountered an unavailable Docker engine before any tests began.
These invocation failures are retained separately from final validation results.
The final unchanged full run records **1,053 PASS / 1 FAIL / 23 SKIP**, exit 1:
the stock-count fixture again selected its original count as the supposed other
count. Route and decoded cursor identities prove the collision; its source still
matches approved HEAD. The full regression is **not green** and needs a separate
fixture correction or owner disposition. No stock code, test or timeout was changed.
Contracts record **440 PASS / 0 FAIL**; four serial legacy encrypted cases pass.
Both final encrypted acceptance wrappers pass, and four actual-caller mutations
are refused with child exit 1 and invalid published reports removed.

Fresh execution counts, complete final source SHA-256 inventory, owned-resource
cleanup and invocation history are recorded in the remediation
[report](../../.local/p416-b4-report-remediation-20261017/Remediation.md) and
[final manifest](../../.local/p416-b4-report-remediation-20261017/final-manifest.json),
with its separate checksum. The manifest includes this document's self-hash.
The original B4 manifest and the original review manifest remain historical,
immutable references. The scope is guards, focused tests, bounded test harnesses
and this handoff; production libraries, HTTP contracts, Flutter, migrations,
dependencies and recovery fixtures are unchanged from the reviewed B4 snapshot.
The two wrapper changes only bind validation to their actual tracked run result.

Acceptance dispositions remain **A08 QUALIFIED, A12 PASS, A15 FAIL** until
independent targeted re-review. A08 still lacks the distinct assignment-boundary
queue fixture or an explicit contract-owner disposition. A12's independent actual
server-process restart/completed-request wire-loss proof (23 exact replays,
24 PIDs) is retained; PostgreSQL restart/kill-during-commit/power-loss are separate
unrun qualifications. A15's real live `pg_restore` child termination subproof
remains PASS within its documented boundary; report-integrity closure awaits the
independent reviewer. The 23 server SKIPs, older 21 opt-ins, two historical
unfinished-upload failures (0 PASS/2 FAIL, not rerun), P4.15 Q1–Q6 and all other
operator/device/ingress/key-custody/RPO/RTO qualifications remain binding.
The standalone Flutter unit/widget and design-system suites and Web/Wasm build
were not rerun for this report-tooling correction; the independently verified
unchanged 739 Flutter tests, two design tests and retained Web/Wasm evidence remain
historical, hash-verified evidence. Embedded Flutter HTTP journeys invoked by the
full server suite are included in that server invocation's counts.

## Original implementation record — historical snapshot

The following sections record the original author execution and its original
15-path manifest. Their 13 PASS/3 QUALIFIED matrix, then-pending review wording,
source hashes and earlier A12/A15 gaps are historical. The independent verdict
and dispositions above supersede those acceptance statements without rewriting
the retained original artifacts. No production business logic, route, grant or
migration changed.

## Baseline and authorization

Repository: `C:/dev/storeos`. Approved and freshly fetched `origin/main`:
`edf844323cfb5ad39edd63dcc6a0d288897e9fb8`, tree
`b1241f4f190412ddccaaa10359a1142c1cb079ca`. Initial checkout was clean on
`codex/p416-b3b-shift-swap-ui` at `79603eabcfd6e8d6353680bf7212af74b4c3242d`,
with the same tree. New branch `codex/p416-b4-recovery-acceptance` starts at the
approved main SHA; HEAD remains there and the index remains empty.

GitHub was read directly: [main CI 39033195990](https://github.com/RobinBrohl/storeos/actions/runs/39033195990)
is push/main, attempt 1, completed SUCCESS on the exact approved SHA/tree. All five
jobs succeeded: dart, flutter, numeric-guided-work-e2e, backup-restore-acceptance,
update-recovery-acceptance. PR #5's merge is the baseline, not a B4 publication.
Initial fetch needed the execution permission required to write `.git/FETCH_HEAD`;
the authorized fetch and branch creation then succeeded. No reset/clean occurred.

The owner authorized local B4 fixtures, bounded acceptance, reconciliation and
handoff only. No commit, staging, push, PR, merge, deployment, release, downgrade,
automatic recovery activation, normal application database change, historical
migration edit, business-rule change or P4.16 closure occurred.

All 29 migration raw-byte SHA-256 and Git blob fingerprints were recorded before
implementation in [baseline.json](../../.local/p416-b4/baseline.json). Final
reconciliation is in [final-manifest.json](../../.local/p416-b4/final-manifest.json).
The final manifest contains the exact changed-file inventory, raw SHA-256 values,
supporting test-source hashes, evidence hashes and final Git state, including this
document's self-hash. The document does not embed a circular self-hash.

## Recovery fixture architecture and inventory

`shift_swap_recovery_acceptance.dart` is acceptance tooling. Its business writes
use the existing real HTTP routes, authenticated actors and restricted runtime
role. Both wrappers retain their strict run-owned source/target names. Owner
access installs schema, bootstraps, takes projections and performs the explicitly
identified rollback-only corruption probes; it never serves the new functional
HTTP proof. No new event contract is introduced; existing atomic audit is retained.

The shared transfer-only verifier now filters its own typed claim rows. This
permits valid swap claims to coexist while retaining all transfer parent/claim
checks. The separate swap verifier checks scoped parent/leg/Shift ownership,
lifecycle versions, exact captured work references, terminal claim release,
replacement provenance, exact paired Task identities/content and missing lineage.
Database keys prevent duplicate claims; runtime ownership UPDATE is denied.

| Constructed swap state | Requests | Version | Captured legs | Active claims | Receipts |
| --- | ---: | ---: | ---: | ---: | ---: |
| requested | 1 | 1 | 1 | 1 | 1 |
| offered | 1 | 2 | 2 | 2 | 2 |
| confirmed | 1 | 3 | 2 | 2 | 3 |
| declined after offer | 1 | 3 | 2 | 0 | 3 |
| A withdrawal after offer | 1 | 3 | 2 | 0 | 3 |
| B withdrawal after offer | 1 | 3 | 2 | 0 | 3 |
| manager rejected after confirmation | 1 | 4 | 2 | 0 | 4 |
| approved | 1 | 4 | 2 | 0 | 4 |
| **Total** | **8** | | **15** | **5** | **23** |

The approved request has two distinct published replacement Shifts and two
complete Task lineage sets (one Task per leg in this recovery fixture). The
existing ten-Task-per-leg suites provide the maximum-size proof. All originals
use valid current Account/Employee links, actual Shift version 2 and separate
future intervals, ten days after construction, away from transfer fixtures.
No impossible production state is inserted to seed this journey.

Concurrent P4.11 inventory remains nine requests, 21 receipts, one Task link and
two active claims, with all six retained lifecycle states. One active proposal is
made legitimately stale by an authorized five-minute original-Shift amendment
after capture; its immutable request/receipt is not rewritten and its claim stays
owned. Exactly one stale active transfer is asserted in source and restore. The whole backup has
30 Shifts, 33 TaskInstances and seven shared claims before explicit restored
closure. Existing numeric attempts/results/blocking/execution evidence remains.

P4.15 now has a nonempty profile, direct package definition, revision, configure
receipt, prospective Stock binding and retained exact g/kg correction. The
correction is deliberately zero delta at the existing physical target; it creates
no movement or balance version advance. Exact replay is checked. All five
quantity tables are included in recovery projections. The separate existing
P4.15 opt-in additionally proves changed profiles, permanent suspension, positive
and zero conversion receipts, retained semantic meaning and scoped replay.

## A15 encrypted backup and isolated restore

Final [backup report 963c470707424f93](../../.local/backup-acceptance/963c470707424f93/report.json):
**PASS**. The supported encrypted `.sodb` mechanism and real `pg_dump`/`pg_restore`
ran against only this run's acceptance databases. The encrypted artifact and
private manifest were deleted after verification; the sanitized report remains.
Source/restore SHA-256 projections and exact counts match across **56 tables**,
including schema_migrations (29), all swap/transfer/claim evidence, original and
replacement Shifts/Tasks, audit and all quantity tables. Identity sequences match.
The source remains unchanged; restored sessions/plugin tokens are revoked and a
real runtime CONNECT attempt is refused before any isolated functional proof.

The new restored proof temporarily grants CONNECT only to this run's isolated
target, starts a loopback HTTP server using the restricted runtime pool, and
authenticates current actors through actual login. It re-fences the target in
`finally`; this is explicit test activation, not automatic production activation.
The existing older contextual-history probes retain their historical owner-backed
architecture; the new swap HTTP/authorization proof does not rely on that role.

Observed outcomes:

- Four pre-restore token attempts (read/replay for an already revoked participant
  and a manager session active at backup time) return 401 after restore.
- All 23 exact command replays return their original accepted evidence with the
  replay marker; reads/replays/denials leave full business and audit hashes intact.
- Current Viewer read/replay is denied. Both participants are denied manager
  routes/decisions. Changed actor, payload and command-route UUID attempts are
  refused; the changed-actor request returns privacy-preserving 404.
- Revoking the restored recipient Account denies both read and historical replay
  with its former credential (401). Reactivating the Account does not revive the
  old consent basis: fresh manager approval of the confirmed pair returns 422.
- Three currently authorized explicit manager closures release exactly 1+2+2
  owned claims. Terminal decision replay adds no effects or claims. An already
  approved request refuses reopening.
- All 23 historical receipts, captured work/consent fields, paired Shift/Task
  evidence, historical transfer records and quantity projections remain unchanged.
  Two P4.11 active claims remain correctly owned after all swap claims are released.

Thus retained historical availability and current actionability are separately
observed. Restored historical role membership alone is not used as authorization.
Final cleanup removed source/restore targets, found the corruption target absent,
preserved normal database existence and left the acceptance port free.

## Forward update and recovery

Final [update report 0202e3f5ebe14c74](../../.local/update-recovery/0202e3f5ebe14c74/report.json):
**PASS**. The original populated 0001–0010 boundary is unchanged. The real runner
applies exactly 0011–0029, validates checksums/prefix and applies nothing on its
second invocation. Existing 0010 projections/sequences survive the forward update.
The restricted HTTP smoke creates transfer, swap and nonempty quantity evidence
only after upgrade, checks swap replay and records distinct upgraded projections.

The encrypted pre-update restore point recovers into an isolated target with
exactly ten migrations, unchanged old projections, revoked sessions/plugin tokens,
no runtime CONNECT and a real denied connection. The current server is never
started against the recovered old schema. That recovery point predates swap,
transfer and quantity tables and cannot contain those later records. Independently
checked source SHA-256 projections retain upgraded swaps, historical transfers
and quantities, as well as exact shared claim ownership. Upgraded encrypted
protection is established by the separate current-schema backup scenario above.

Operational failure after committed upgrade is explicitly different from SQL
migration rollback. The populated 0027/0028 late-injection suites prove rollback;
the wrapper failure hooks prove operational cleanup and retain `migrationCommitted`.
There is no application/database downgrade or replacement activation claim.

## Failure, report integrity and redaction evidence

| Check | Observed result | Evidence |
| --- | --- | --- |
| Wrong key through actual restore | Expected exit 1; isolated target removed; FAIL report retained | [87e3dbcbcdd148fe](../../.local/backup-acceptance/87e3dbcbcdd148fe/report.json) |
| Interrupted encrypted archive (missing terminator; manifest hash recomputed) | Expected exit 1; fail closed; cleanup PASS | [9cea624d29d54096](../../.local/backup-acceptance/9cea624d29d54096/report.json) |
| Authenticated invalid pg_dump archive | Actual restore refusal, expected exit 1; cleanup PASS | [93f1fc13289f4491](../../.local/backup-acceptance/93f1fc13289f4491/report.json) |
| First cleanup attempt injection | FAIL retained, owned source removed by explicit retry; other targets removed | [f64efa961b064b47](../../.local/backup-acceptance/f64efa961b064b47/report.json); final repeat in final manifest |
| Failure after completed isolated restore | Expected exit 1; source/target cleanup PASS | [d4edd10df1354632](../../.local/backup-acceptance/d4edd10df1354632/report.json) |
| Missing receipt/claim, mismatched claim, missing Task link or leg | Five isolated owner-only corruptions independently refused by verifier; each ROLLBACK restores exact hashes | `shift_swap_upgrade_recovery_test.dart`; [focused log](../../.local/p416-b4/focused-first.log) |
| Duplicate claim and runtime ownership reassignment | PostgreSQL refuses; original evidence unchanged | Same recovery integration test |
| Missing claim at approval, deferred guard, malformed scope/SQL NULL/UNKNOWN | Real restricted SQL/Application failures with complete rollback | Existing swap integrity/remediation/safety/migration tests; focused/full logs |
| Unsupported migration state | Unknown, non-prefix, malformed filename, empty SQL and changed checksum refuse | `postgres_integration_test.dart`; full server log |
| Sensitive report and report cleanup/evidence tampering | **8 PASS / 0 FAIL**: two real positive reports plus six rejected mutations | [report-integrity-accepted-final.log](../../.local/p416-b4/report-integrity-accepted-final.log) |
| Known secret representations | Raw, distinctly URL-encoded and Base64 synthetic values refused by both guards; private names/reasons also refused | [backup](../../.local/p416-b4/backup-redaction.log), [update](../../.local/p416-b4/update-redaction.log) |
| Crypto roundtrip and wrong-key/tamper/truncation/reorder | Script PASS; five named checks | [crypto.log](../../.local/p416-b4/crypto.log) |

Five unique negative backup wrapper scenarios passed by producing their expected
FAIL reports and exit 1; they are not reported as successful recoveries. The final
cleanup repeat is additional overlapping verification. Two update operational
failure hooks are recorded separately in
[update-negative-results.json](../../.local/p416-b4/update-negative-results.json).

**QUALIFIED / NOT RUN:** the interruption scenario is an authenticated truncated
archive/stream proof, not killing an operating-system restore process mid-effect.
A live process-kill recovery/restore interruption remains unverified. No failover,
RPO/RTO, descriptor reclamation, hardware or operator readiness follows from these
tests. Known real credentials were consumed only inside existing private-file
configuration; they were never printed or read into agent context to strengthen
assertions. Reports contain only counts, hashes, outcomes and qualifications.

Reports have explicit acceptance schema, run ID/time, source revision/file hashes,
source/restored/upgraded schema distinctions and PASS/FAIL classification. SKIP
and QUALIFIED evidence is explicitly recorded below rather than relabeled PASS.
All owned database/artifact cleanup outcomes remain visible, including injected
failure and recovery. Historical evidence was preserved.

## Regression execution and retained failed attempts

Environment: Windows, PowerShell 7, PostgreSQL 17-alpine, pinned Dart 3.13.4 /
Flutter 3.47.5; locked cached packages, no upgrades. Test SQL uses explicit disposable
`*_test` databases and the restricted runtime role. Backup/update use distinct
strictly named acceptance databases on the existing Compose PostgreSQL server.

| Suite/check | Result | Evidence |
| --- | --- | --- |
| Focused real PostgreSQL swap/P4.11/P4.15/migration/clock/recovery (17 files) | **263 PASS / 0 FAIL / 0 SKIP** | [focused-first.log](../../.local/p416-b4/focused-first.log) |
| New recovery test initial direct execution | **1 PASS / 0 FAIL / 0 SKIP**; included again in focused/full | [recovery-tests-first.log](../../.local/p416-b4/recovery-tests-first.log) |
| Final directly affected recovery fixtures | **2 PASS / 0 FAIL / 0 SKIP**, after stale-transfer addition; overlapping new recovery and existing backup regression | [recovery-tests-final.log](../../.local/p416-b4/recovery-tests-final.log) |
| Full server | **1054 PASS / 0 FAIL / 23 explicit opt-in SKIP** | [server-full.log](../../.local/p416-b4/server-full.log) |
| Four explicit legacy encrypted upgrade/recovery cases | **4 PASS / 0 FAIL / 0 SKIP**, serial dedicated Compose databases; includes P4.15, P4.12/P4.14/P4.13 | [results](../../.local/p416-b4/legacy-compose-final-results.json) |
| API contracts | **440 PASS / 0 FAIL / 0 SKIP** | [contracts-final.log](../../.local/p416-b4/contracts-final.log) |
| Flutter eligible unit/widget suite | **739 PASS / 0 FAIL / 0 SKIP** | [flutter.log](../../.local/p416-b4/flutter.log) |
| Design system | **2 PASS / 0 FAIL / 0 SKIP** | [design-system.log](../../.local/p416-b4/design-system.log) |
| Four analyzers, fatal infos | PASS, no issues | `*-analyze*.log` under `.local/p416-b4/` |
| Nonwriting format | server 266, contracts 68, client 118 files, zero changes; design checked separately | `*-format.log` |
| Release Flutter Web, no pub/CDN, Wasm dry run | PASS | [web-release.log](../../.local/p416-b4/web-release.log) |
| Configured setup, diagnostic/capacity redaction | All three scripts PASS | `dev-setup.log`, `e2e-redaction.log`, `capacity-redaction.log` |
| Current-schema encrypted backup / 0010 forward recovery | Both PASS, final reports linked above | Per-run fingerprints are in reports |
| New report assertions / both redaction / crypto | 8 report cases PASS; three scripts PASS | Named logs above |

Counts overlap: focused/new tests are part of full server; widget/controller subsets
are part of 739; separately launched encrypted opt-ins are not converted into
package passes. No artificial combined total is asserted. Historical 21 opt-in
SKIPs retain their historical disposition; four specifically named recovery cases
have fresh separate evidence. The current full package has 23 explicit skips: the historical 21 plus the later P4.16 browser and Flutter integration opt-ins. Actual Chrome and unrelated browser journeys were
not rerun in B4; applicable independent evidence is hash reconciled below.

Retained B4 invocation failures:

- First backup: compile failure from a missing fixture import; expected cleanup
  completed. [65a5aad393a14c0d](../../.local/backup-acceptance/65a5aad393a14c0d/report.json).
- Next backup: one new assertion expected 409 but actual privacy denial was 404.
  No production change was needed. The corrected expectation passed; original
  [392c7a5cc64b43ff](../../.local/backup-acceptance/392c7a5cc64b43ff/report.json)
  remains FAIL with successful cleanup.
- Initial contract process exited before loading tests under sandbox permissions
  (`-1073741816`, 0 test results); the authorized same suite passed 440.
- Combined legacy opt-ins: **0 PASS / 4 FAIL**, their fixed schema collided in a
  concurrency-2 container invocation. Serial container retry: **0 PASS / 1 FAIL**,
  because existing backup scripts target Compose rather than that container.
  Initial dedicated Compose name: **0 PASS / 1 FAIL**, refused by the fixture's
  exact fixed-schema name guard. The correct `storeos_p416_<16hex>_test` names and
  one fresh Compose database per case then passed all four. Logs/results remain
  under `.local/p416-b4/`; no test assertion or naming guard was weakened.
- A later positive wrapper overlapped another acceptance source on fixed port
  8097. Its functional verification passed, but cleanup correctly reported the
  port still occupied: [101ccf7821314d29](../../.local/backup-acceptance/101ccf7821314d29/report.json)
  remains FAIL. Both runs removed only their own databases. The final positive
  run was serialized after all other backup runs and passed with a free port.

Three additional restore-refusal repetitions explicitly record
`negativeRecoveryProof.restoreRejected=true` and
`unexpectedRestoreSuccess=false`; see
[negative-proof-results.json](../../.local/p416-b4/negative-proof-results.json).
These repeat the wrong-key, truncation and invalid-archive scenarios rather than
adding three new kinds of failure. The copied local runner's final text label
says five; the structured result inventory contains exactly three executions.
The local negative drivers also inherit the last expected native exit 1; their
structured per-scenario assertions, rather than that inherited shell status,
establish the expected-refusal result. The original logs remain unchanged. Final cleanup-injection repeat
[244515494967495d](../../.local/backup-acceptance/244515494967495d/report.json)
explicitly labels `failedStep=cleanup`, retains the initial FAILED attempt and
records the successful owned-source removal retry. Earlier failure reports keep
their original schema/field sets and source hashes.

## A01–A16 traceable acceptance matrix

Source **B4** means baseline `edf844323cfb5ad39edd63dcc6a0d288897e9fb8` plus the
uncommitted test/tool files pinned in the final manifest. Execution **W17** means
2026-10-17 Windows/pinned SDK/real HTTP and restricted PostgreSQL 17. **UI13** means
the independently reviewed 13-file B3b manifest SHA-256
`AE865FFAA97CEC1CDD6C44CF591B7000525585843BBB2312241A3A72C34E9640`;
all 13 current hashes and 34 retained evidence artifact hashes match. The final
independent B3b review hash is
`1B1FF12F0E8D164B4CD249A4C101ED979CEBA20C374FEEA2EB8AC3C72568E250`.
Source and artifact reconciliation files are retained in `.local/p416-b4/`.
**F** = focused log, **S** = full server log, **U** = Flutter log, **I** = final
independent B3b review/Chrome evidence, **B/R** = final backup/update reports.
Review entries describe previous approved layers; fresh B4 changes are not yet
independently approved. PASS applies to named evidence, not general readiness.

| ID | Required invariant | Test/fixture identifier | Source | Date/environment | Evidence/result | Classification | Independent-review status | Remaining limitation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| A01 | Exact A request/B offer/A confirmation/independent approval; both incoming work executions | `shift_swap_application_test`, `shift_swap_application_clock_test`; four-actor `shift_swap_test` Chrome | B4 + UI13 | W17; reviewed Chrome 2026-10-17 Windows | F + I; atomic pairs and both ordinary executions observed | PASS | B1 and B3b approved; B4 pending | Chrome reused by exact hashes; native devices unverified |
| A02 | Current participant/manager/Company/Location/session privacy and replay scope | `shift_swap_http_privacy_test`, `shift_swap_http_remediation_test`; restored HTTP proof | B4 + UI13 | W17 | S + B + I; scoped denials, protected receipts | PASS | B2/B3b approved; restored extension pending | Not every HTTP credential permutation duplicated in Chrome |
| A03 | Stage/pair/identity validity and independent decision Account | Application safety, HTTP privacy; restored Account revoke/reactivate | B4 | W17 | F + S + B; wrong stage/actor/basis refuses without effects | PASS | B1/B2 approved; B4 pending | Independent Account policy does not prove human-person independence |
| A04 | One version per terminal closure, retained consent, owned release, no reopening | Application lifecycle; `verifyRecoverySwaps`, restored closure/replay | B4 | W17 | F + B; 23 old receipts conserved; five exact claims released | PASS | Prior lifecycle approval; B4 pending | No automatic stale expiry or offboarding workflow |
| A05 | Evaluate final roster excluding exactly persisted departing pair | Equal/intersecting/adjacent/third-overlap Application and integrity cases | B4 | W17 | F; both replacements publish or no effects | PASS | B1 approved; B4 regression author-run | No labor-law/absence/qualification approval claim |
| A06 | Exact 1–10 ordered snapshots/pins and both lineage sets | Application ten-task exchange, guidance suites; recovery two links | B4 + UI13 | W17; I reviewed 2026-10-17 | F + B + I; full retained content and exact pins | PASS | B1/B3b approved; B4 pending | Recovery inventory has one Task per leg; maximum size proven separately |
| A07 | Observed Company-lock queues, cross-workflow exclusivity and explicit opposite closure | `observedWriters`; Application transfer/request-A/offer-B both orders, competing B offers, swap/swap/opposite invitations | B4 | W17 | F; observed waiters, one occupancy winner, unchanged loser/no partial offer | PASS | B1/Stage A independently approved; B4 rerun author-run | Observed supported writer queues, not distributed scheduling or throughput certification |
| A08 | Identity/work mutations on both sides of queued progression cannot inherit consent | Sequential stale execution/amend/cancel, Account/link/ABA/assignment safety cases | B4 | W17 | F + S; sequential invalidation and closure pass | QUALIFIED | Prior layers approved; complete queued matrix not established | Missing observed before/after queue permutations for Account deactivate/ABA, link replacement, Employee assignment and ordinary Shift mutation; sequential tests are not substituted |
| A09 | Exact old Knowledge may survive newer publication; current invalid guidance blocks approval | `shift_swap_application_guidance_test`, HTTP error/guidance cases | B4 | W17 | F + S; captured pins unchanged, no automatic repinning | PASS | B1/B2 approved; B4 author regression | Current documented Knowledge/Planogram policies only |
| A10 | Every partial approval effect rolls back and failed UUID remains reusable | Seven `shift_swap_application_safety_test` faults plus review/deferred integrity probes | B4 | W17 | F; second cancellation/replacement/materialization/link/receipt/audit/deferred refusal, whole hashes conserved | PASS | B1/Stage A approved; B4 regression author-run | Faults are explicit isolated test injections |
| A11 | Fresh database-time final barrier, rollback after crossing, original replay after start | `shift_swap_application_clock_test`, `shift_swap_clock_test`, future error/migration cases | B4 | W17 | F + S; actual waiter behind deferred Tasks barrier and clock crossing; pre-boundary success and after-start replay | PASS | B1/Stage A approved; B4 regression author-run | Equal-start fixture crosses both starts; exact client delivery/WAL timing and every staggered-start permutation unverified |
| A12 | Lost responses + full server-process restart preserve original command identity/effects | B3a `shift_swap_http_probe`/server fixture and B3b held-response journey; restored exact replay | UI13 + B4 | Reviewed B3a 2026-10-16; B3b/W17 | I + B; component recreation, response suppression and 23 recovered replays pass | QUALIFIED | B3a/B3b approved for executed scope; B4 pending | Full OS server-process/PostgreSQL restart and actual dropped-wire timing NOT RUN; component restart is not substituted |
| A13 | Session/Location replacement fences forms/results and immutable uncertainty | `shift_swap_reconciliation_test`, UI/dialog/navigation tests, held Chrome detail/revocation | UI13 | W17 Flutter; reviewed Chrome 2026-10-17 | U (739 includes subsets) + I | PASS | B3A-01 CLOSED, B3B-01 CLOSED; final B3b APPROVE | All permutations deterministic; only named held/revoked cases observed in Chrome; memory-only pending state |
| A14 | Populated upgrades, exact historical backfill, rollback, restrictive grants and SQL guards | `shift_swap_migration_test`, `shift_swap_future_migration_test`, integrity/remediation; P4.15 recovery | B4 | W17 | F + S + four explicit encrypted opt-ins; populated proof, not only empty migration application | PASS | Stage A/B1 approved; B4 regression author-run | Supported-writer/privileged-owner boundary remains |
| A15 | Encrypted isolated restore + 0010 forward recovery, current scoped replay/closure and unchanged P4.15 | New recovery test; both final wrappers; negative recovery/report suites | B4 | W17 | B + R + F + legacy opt-ins; core encrypted/scoped preservation PASS | QUALIFIED | Ready for independent B4 review, not yet approved | Interrupted archive tested; actual OS restore-process kill mid-effect NOT RUN. Operator custody/RPO/RTO/activation not accepted |
| A16 | Actual four-actor Chrome, both replacements, privacy/stale/literal/long content, no framework exception | Exact reviewed `integration_test/shift_swap_test.dart` and server browser fixture; final independent navigation Chrome extension | UI13 | 2026-10-17 Windows Chrome/HTTP/restricted PostgreSQL | I; both original executions and independent rapid-shortcut extension PASS; hashes unchanged | PASS (retained) | Final independent B3b APPROVE | Not rerun in B4; optional font fallback, native/accessibility/cross-browser/hardware remain qualified |

Matrix: **13 PASS / 3 QUALIFIED / 0 FAIL**, with the precise NOT RUN proofs in
A08/A12/A15 retained. This is a reconciled evidence matrix, not P4.16 acceptance
closure or a new independent review verdict.

## Previous approvals, remaining qualifications and review readiness

B1/B2/B3a/B3b are integrated in the approved baseline. Earlier handoffs retain
their original pending-review wording and failure chronology. B1's final handoff
records independent APPROVE/F01 CLOSED. B3a's integration record records independent
APPROVE/B3A-01 HIGH CLOSED and its explicit approved LF canonicalization. Final
B3b independent targeted review, read directly and hash checked above, records
APPROVE/B3B-01 LOW CLOSED and B3A-01 remaining CLOSED. The earlier B3b CHANGES
REQUIRED report hash `5920F4A64BB4D0706400D1D21A08E5BB407E3E708A7EA92AC692F65F836AF227`
is preserved separately; it was not rewritten as a prior approval.

No new production recovery blocker was found. B4 is prepared for independent
functional/Security review of the fixture assertions, owner/runtime distinction,
temporary isolated activation/re-fencing, historical preservation, failure cleanup,
report integrity, fingerprints and matrix classifications. No new independent
agent/review verdict is claimed. Remaining proof gaps are explicit above.

The following inherited qualifications remain binding:

- Full OS-process/PostgreSQL restart, actual wire loss/unfinished-upload timing,
  Linux/process-signal, ingress/proxy frontend lifetime, descriptor reclamation,
  hardware capacity, deployment and operator limitations.
- Two historical unfinished-upload assertions: **0 PASS / 2 FAIL**, not rerun.
  No new unfinished-upload network test, scanner-access retry or exhaustion probe.
- Historical 21 opt-in skips/unverified broader journeys are not a blanket PASS.
  Four named recovery opt-ins were separately executed here; package skips stay.
- Native devices/accessibility and optional font fallback; browser evidence does
  not certify physical devices, glyph coverage or all browsers.
- P4.15 Q1–Q6: memory-only client uncertainty; immutable prospective semantics and
  permanent suspension; active nonblocking Location-picker F04; physical/operator
  readiness; plugin-specific limits; broader acceptance qualifications. Existing
  [P4.15 closure](phase-4-15-article-quantities.md#final-documentation-closure--2026-10-13)
  remains unchanged.
- LOW BOM generator follow-up and other existing technical-debt dispositions.
- Retention/offboarding/access/export decisions, recovery key custody/off-host
  recovery, RPO/RTO and supported devices remain human operator gates. Personnel
  decisions remain with people. Database recovery is not production readiness.

## Final source and Git inventory

The index is empty. Exactly 15 intended paths remain uncommitted: 11 modified and
4 new. HEAD and baseline remain `edf844323cfb5ad39edd63dcc6a0d288897e9fb8`.
All 29 migration raw and Git fingerprints match. Production libraries, contracts,
Flutter code/tests, dependencies and served assets have no tracked delta.

Hashes below are raw final checkout SHA-256. The external final manifest pins this
handoff itself, supporting sources, sanitized evidence, migration fingerprints and
Git state; its checksum is in `.local/p416-b4/final-manifest.sha256`.

| State | Repository-relative path | SHA-256 |
| --- | --- | --- |
| ?? | `apps/server/test/shift_swap_upgrade_recovery_test.dart` | `E3E00F3B0C78EE5C5055081C5201A469A237E70F9629B3721E2D9B6C1F675685` |
|  M | `apps/server/tool/backup_restore_fixture.dart` | `8B68AF6B27ECD1616BC35888291A139E938BA62E658BD160EB3C8129651EDC3F` |
| ?? | `apps/server/tool/shift_swap_recovery_acceptance.dart` | `B28913AF339F774DB2A5177A85153532859E16735BF01BF58BB0BA607439FE09` |
|  M | `apps/server/tool/shift_transfer_acceptance.dart` | `B05354CE61A7764A843234E140A9A4DF7D7B07C9E3C7CC705FD1A078939D34E1` |
|  M | `apps/server/tool/update_recovery_fixture.dart` | `9B89229E0150F19185727668A8035A1F051C101FC808695B3B5FDCDA196C977E` |
| ?? | `docs/development/phase-4-16-stage-b4.md` | `Self-hash in final-manifest.json` |
|  M | `docs/HANDOVER.md` | `29CB3166CD9BFF9B4B23B50CCEB35C78AE2F2634CD5A26A2644317752162D98D` |
|  M | `docs/roadmap/status.md` | `1F407C6C359E69A56F4872AFABC9826B8EA9A5E9579BADFDBFDC1CFC7B7F24E5` |
|  M | `scripts/backup/Assert-BackupAcceptanceReport.ps1` | `611DC0878F9B8C8E925805A68453A16222BBB5DF949426846176C671A512142C` |
|  M | `scripts/backup/Run-BackupRestoreAcceptance.ps1` | `E1D38F0F457961A5A76BD7BEFCC9634149384140E6096119ACD48655FE1157E2` |
|  M | `scripts/backup/Test-BackupAcceptanceRedaction.ps1` | `8677CBD33AB174521BF9AE3C92F3FCC6F519AD8CCB876239A3DE3D711BDF7528` |
| ?? | `scripts/backup/Test-P416RecoveryReports.ps1` | `19AC185100D67963DAFA69C103FC2EFAF03957BA96ABCBC0E82B3D2FE88FD8CB` |
|  M | `scripts/update/Assert-UpdateAcceptanceReport.ps1` | `A0CEE599A61F571B8776FBEC91008582F3DC39141D1F3AD321713E24C8F6DE68` |
|  M | `scripts/update/Run-UpdateRecoveryAcceptance.ps1` | `AF60DEC33C7AC53F68E890DF1754A262CEF30DC71320A7AA9A24EDEEA0D10229` |
|  M | `scripts/update/Test-UpdateAcceptanceRedaction.ps1` | `7FB9C99838883AFE543A823360867459AA107880E5A5514C7999075722368FE3` |

## Fixture cleanup remediation stopped at canonicalization gate — 2026-10-18

**B4 AUTHFAILURE STILL BLOCKED.** The local fixture correction is unapproved.
Only `apps/server/tool/backup_planogram_acceptance.dart`, its focused regression
test `apps/server/test/backup_planogram_cleanup_test.dart`, and this appended
entry change the preceding candidate. Production authentication, session TTL,
wrapper timeouts, business assertions, grants, migrations and API contracts are
unchanged. Every logout is attempted; only PostgreSQL-confirmed expired,
unrevoked sessions for an active account in the exact company/location are
expected expiration. Diagnostics explicitly say logout was not performed.
Unexpected errors retain their type/reason and safe original stack. The pool is
closed in finally, and a primary verification-body error retains precedence.

Focused final invocation: **17 PASS / 0 FAIL / 0 SKIP**, comprising 15 cleanup
cases (including real disposable PostgreSQL expiry and pool closure) and the
existing backup-recovery and swap-upgrade recovery tests. Earlier test-tool
permission/launcher errors and the first PostgreSQL setup rejection are
preserved. That initial complete focused attempt was **14 PASS / 1 FAIL / 0
SKIP**: a deliberately expired session incorrectly predated its creation;
the corrected disposable state preserves the schema's expiry constraint.
The historical AuthFailure/open-pool/timeout reproduction remains unchanged.
This invocation proves the new cleanup helper; the full verification body and
actual encrypted callers have not yet been revalidated after this correction.

Canonical preflight then detected a fourth raw-to-Git discrepancy: the changed
Planogram fixture remains CRLF (as before), while its Git blob is LF. Its 709
CRLF pairs transform; all other bytes match. This is additional to the three
pending publication mappings. Work stopped at the requested transformation
gate. No line-ending rewrite or policy exception is self-authorized. The six
actual publication caller cohorts, both positive encrypted wrappers, report
regressions and full eligible server suite are **NOT RUN** in this task.
Historical full-server **1054 PASS / 0 FAIL / 23 SKIP** is not a fresh result.
Original **0 PASS / 1 FAIL / 5 NOT RUN** caller history remains preserved.
Unfinished-upload **0 PASS / 2 FAIL, NOT RERUN** remains historical.

Evidence, exact diff and complete 24-path raw/canonical candidate manifest:
`.local/p416-b4-auth-cleanup-remediation-20261018/`. The original 42-line
publication reconciliation and all preceding handoff bytes remain intact.
Original functional/security approvals apply to their original snapshot;
this changed fixture requires independent review after the canonicalization
gate is resolved and the remaining verification completes. The existing EOF
blank-line finding at JSON-redaction test line155 remains unchanged. A08's
supported deactivation boundary, A12's independent restart evidence, A15's
bounded recovery contract, historical qualifications and P4.15 Q1–Q6 remain
binding. No acceptance status is self-promoted. Real index remains empty and
byte-identical; migrations 0001–0029 remain unchanged. No stage, commit, push,
PR, merge, deployment or closure occurred. P4.16 remains **IN PROGRESS**.

## Local publication validation — 2026-10-18

**B4 PUBLICATION VALIDATION GREEN — TARGETED REVIEW PENDING.** P4.16 remains
**IN PROGRESS**. User-authorized local execution proceeded with the four known
CRLF-to-LF mappings; this does not approve those mappings for publication.
A fresh disposable alternate index proved byte equality after removing only
CRLF's CR bytes. The Planogram fixture has exactly 709 such pairs. Both Dart
representations parse with 3,558 identical token lexemes and 211 identical string
values. Encoding, BOM and final-newline behavior match; .gitattributes is intact.

The original canonical backup/proof caller now completes prepare, encrypted
backup, isolated restore, strict verification and cleanup, then correctly
rejects the deliberate report mutation. All six original backup/update ×
proof/result/JSON-redaction cases pass: their wrapper children exit 1 after a
validated completed PASS, invalid reports are removed, and success/sensitive
diagnostics are absent. All three original drivers exit 0. Both positive
encrypted wrappers exit 0; six directly observed Dart native handles also exit 0.
All 18 negative-case Dart lifetimes are observed below 300 seconds. No wrapper
timeout occurs. Natural full callers did not force expiry; the real disposable
PostgreSQL expiry regression separately confirms strict authentication denial,
expected cleanup, an unrevoked expired session, completed pool.closed and intact
stock/ledger rows. This distinction is retained rather than claiming an
unobserved expired session in the natural full runs.

Fresh checks: focused cleanup 15/0/0 before callers; focused recovery 17/0/0
after callers and again after the style correction; complete eligible server
**1069 PASS / 0 FAIL / 23 SKIP** with all 23 historical skip identities/reasons
unchanged; original contradictory probes16/16; original JSON-redaction corpus
74/74 unchanged inputs/expected outcomes; semantic 1885/0; JSON redaction 460/0
(434 refusals/26 valid controls); report 8/0; both existing redaction scripts;
server analyzer 0 issues; nonwriting formatter 267 files/0 changed; ten PowerShell
scripts parse. Counts overlap. Contracts are unchanged and were not rerun;
historical 440 PASS remains historical. Unsafe unfinished-upload 0 PASS/2 FAIL
was not rerun. Earlier failed caller,14/1 setup diagnostic and all prior reviews
and manifests remain preserved.

The independently confirmed EOF finding is corrected by deleting exactly one
redundant final LF from the JSON-redaction test. Executable PowerShell tokens,
strings and assertions match; the complete 24-path alternate-index whitespace
check passes. Initial final verification also found two fatal analyzer style
infos in the new cleanup regression helper. Exactly two if-body brace pairs
were added, without changing conditions, statements or assertions; the failed
analyzer invocation (before server tests started) is preserved, and the final
focused/analyzer/full suite pass. No fixture, production authentication,
session TTL, wrapper timeout, business assertion, grant, migration or contract
was changed during this continuation. A local orchestration parse error is
retained separately; no product assertion ran in that rejected invocation.

Exact results, commands, process observations, report hashes, source diffs,
cleanup and complete 24-path raw/canonical candidate hashes are under
`.local/p416-b4-publication-validation-20261018/`. All 29 migration fingerprints,
the real empty byte-identical index, the original 42-line reconciliation and
all preceding handoff bytes are retained. The nonblocking swap/swap erratum
still has zero raw transfer receipts/links; no historical report is rewritten.

Independent targeted approval remains required for all four canonical mappings,
fixture cleanup/regression source (including the brace correction), EOF edit and
dated handoff additions. Prior functional/security approvals apply to their
original snapshot. A08's supported deactivation-only boundary, A12's independent
restart evidence, A15's bounded recovery contract, operational/key-custody/
off-host/privacy/device qualifications and P4.15 Q1–Q6 remain binding. No local
check self-approves publication. Separate Git integration authorization, exact
resulting-head checks, deployment/operator and P4.16 closure gates remain.
No real-index staging, commit, push, PR, merge, deployment or closure occurred.
