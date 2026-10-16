# StoreOS handover

## Current P4.16 Stage B2a native ingress — 2026-10-16

P4.16 remains **IN PROGRESS**. F01–F03 are independently **CLOSED**. Latest
independent native review: **STAGE B2a CHANGES REQUIRED**, INGRESS-01 MEDIUM
(logout before EOF) and INGRESS-02 LOW (bodyless GET keep-alive). Both findings
are fixed locally on the same uncommitted B2a branch; targeted independent
re-review remains pending. See [ADR 0031](adr/0031-bounded-native-http-ingress.md)
and the [current evidence](development/phase-4-16-stage-b2a.md#ingress-01--ingress-02-local-remediation--2026-10-16).
No restricted unfinished-upload network probes or scanner retries were run; the
two historical failures and interruption remain recorded. Independent targeted
transport review, wire/proxy qualification, B2b and broader acceptance remain gates.
No migration, business-rule, commit, push, PR or deployment change is authorized.
Earlier dated entries below are historical.

## Current P4.16 Stage B2a — 2026-10-14

P4.16 remains **IN PROGRESS**. The owner authorized local authenticated swap HTTP
transport on verified integrated main `289dc07bc5b8e85b3a3430f45244e13adc9e3a11`;
Stage A/B1 are independently approved, merged and baseline main-CI verified.
Local uncommitted B2a work is on `codex/p416-stage-b2a-swap-http`: all 16 routes,
transaction-scoped withdrawal resolution and scoped two-receipt history pages.
Final dedicated real HTTP/restricted PostgreSQL tests: **47 PASS / 0 FAIL / 0 SKIP**;
contracts: **362 PASS**; full server: **981 PASS / 0 FAIL / 21 explicit opt-in SKIP**.
Analyzers and non-writing format checks pass; index empty, 13 intended paths.
See the [B2a handoff](development/phase-4-16-stage-b2a.md) for exact DTOs, errors,
privacy/replay and evidence. Migration chain remains 0001–0029. Step 7 OpenAPI,
Flutter/browser and expanded recovery remain separate gates. No commit, push, PR,
deployment, B2a independent approval or full P4.16 closure. Next: independent
adversarial B2a review. Earlier dated passages are history.

## Current P4.16 Stage B1 — 2026-10-13

The owner separately authorized Step 5's internal bilateral swap Application
coordinator, directly required owner ports and local tests. The integrated Stage A
baseline is `525abb7c975d08d8c93aeca3ac72e58ccbb38ce3`; local work is uncommitted
on `codex/p416-stage-b1-swap-orchestration`. Internal implementation is verified:
48 direct B1 tests PASS; full restricted PostgreSQL server 890 PASS / 21 explicit
opt-in SKIP / 0 FAIL. See the [Stage B1 handoff](development/phase-4-16-stage-b1.md).
Four fixed swap permissions and minimized audit support are bounded prerequisites
moved forward from Step 6. No new migration, HTTP/OpenAPI/Flutter swap delivery,
expanded recovery acceptance, independent B1 review or P4.16 closure is claimed.
The next gate is independent adversarial Stage B1 review. Earlier Stage A/design
passages retain their dated historical assertions.

## Current P4.16 Stage A — 2026-10-13

The owner separately authorized Steps 1–4, bounded remediation of independently
reproduced F01–F03 and one local implementation commit. **Stage A is independently
approved; the local implementation commit is on `codex/p416-bilateral-shift-swaps` from**
`3b2d66f07ef7f261a74e922e32cbe656d8998837`. Strict DTO/domain foundations, migration
0028, shared handoff claims, owner ports and compatible P4.11 integration are
delivered locally. See the [Stage A handoff](development/phase-4-16-stage-a.md)
for all files, populated upgrade/rollback/concurrency proofs and executed checks.
Full P4.16 is incomplete; Steps 5–10 remain unimplemented and unauthorized.
The independent Stage A review required changes. Database-owned replacement
creation provenance, safely replayable receipt encodings and exact terminal DTO
kinds address its three findings; remediation is verified locally (full server
842 PASS / 21 explicit opt-in SKIP, all three counterexamples refused, both P4.11
controller/Chrome opt-ins PASS). The targeted independent re-review returned
**STAGE A APPROVE: F01–F03 CLOSED, no new findings**, with 114 focused PostgreSQL/
P4.11 tests and 5 additional probes passing. Finalization verifies the exact
60-path scope; only three status/handoff documents are updated from reviewed bytes.
Remote main was fetched and remains at the parent baseline. No full Security
acceptance, exact implementation CI, push, merge, rebase or deployment is claimed.
Nineteen other opt-in cases remain unexecuted with their acceptance gates retained.
The design-only authorization statements below describe the prior
design baseline and are superseded only for this separately authorized Stage A.

## Current P4.16 selection — 2026-10-13

**P4.16 Employee-Proposed Bilateral Swap of Pristine Future Shifts is SELECTED /
DESIGN IN PROGRESS. Implementation is NOT AUTHORIZED.** The owner authorized
selection and documentation only on clean `main` at
`8a0198f3430cb7ec636e952522dda7cf930b7fca` (HEAD/cached origin matched).
Protocol B: A requests with own Shift and named B; B offers an own counterpart;
A confirms the exact immutable pair; an independent manager approves the two-leg
atomic cancellation/replacement. No colleague-roster grant or pre-approval schedule
effect. One Workforce claim authority covers both P4.11 and both swap legs.
See the [contract](development/phase-4-16-bilateral-shift-swaps.md),
[ADR 0030](adr/0030-bilateral-shift-consent-and-shared-handoff-claims.md) and
[file-level plan](development/phase-4-16-implementation-plan.md).

Independent architecture verdict supplied by the owner: **ARCHITECTURE APPROVE**.
LOW/nonblocking F01 is resolved by the documentation-only Step 3 overlap-repository
correction. Database enforcement is **NOT VERIFIED**. No P4.16 implementation,
migration, tests, generated contracts, implementation review or CI result exists.
Migration chain remains 0001–0027; next number is 0028 at this baseline.
No known architectural contradiction blocks the bounded design; executable proof
and separate implementation authorization remain gates. P4.1–P4.15 acceptance and
all P4.15 qualifications/debt are retained. Historical pending/unselected wording
below describes its dated closure context, not the current P4.16 selection.

## Retained P4.15 closure summary

P4.15 Explicit Article Quantity Semantics and Exact Alternate-Unit Manual Stock
Correction is **DONE/CLOSED — accepted implementation** at
`f4ffffaae235307424133c4ed280328df3e33f01`, with the bounded test-only correction
`c132a88feb619268c65fae69d3eeff64d5363218` on `main`. Targeted functional review:
**APPROVE**; F01/F02/F03: **CLOSED**; focused Codex Security: **SECURITY APPROVE**,
no required fixes. Acceptance: **7 PASS / 6 QUALIFIED / 0 FAIL**. Migration chain:
**0001–0027**, with historical migrations preserved.
All five jobs succeeded in [feature CI 38317916154](https://github.com/RobinBrohl/storeos/actions/runs/38317916154).
[Original main CI 38320235803](https://github.com/RobinBrohl/storeos/actions/runs/38320235803)
failed on a false-positive audit-privacy substring assertion; the test-only fix has
successful [exact-commit main CI 38323585842](https://github.com/RobinBrohl/storeos/actions/runs/38323585842),
attempt 1, all five jobs. The failure and correction remain distinct historical evidence.
**Separate documentation-closure commit publication and its own exact-commit CI: PENDING.**
No publication or CI success is claimed for this local documentation commit.
**P4.16 was UNSELECTED at that closure; current design selection is recorded above.**

Memory-only uncertain retries, immutable anchors/bindings, permanent suspension,
F04 nonblocking [debt](development/technical-debt.md#p415-nonblocking-location-picker-debt),
operator/device readiness, plugin-specific execution and broader acceptance boundaries
remain qualified. This delivers reviewed manual targets only; no automatic Goods
Receipt/Stock posting, Recipe/Purchasing conversion, production consumption, POS
ingestion or costing. See the [closure and six qualifications](development/phase-4-15-article-quantities.md#final-documentation-closure--2026-10-13)
and [ADR 0029](adr/0029-explicit-article-quantity-semantics.md).

## Historical P4.14 closure context

The following passage retains its earlier drafting/publication state. Its P4.15
UNSELECTED statement is historical and superseded by the current status above.

P4.14 Purchase Order Delivery Evidence and Reconciliation is **DONE/CLOSED — accepted implementation** at `0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df`.
Independent functional review and targeted F01/F02 re-review: **APPROVE**; both findings **CLOSED**.
Focused Codex Security: **SECURITY APPROVE**. Final remediation verification: **PASS**.
All five jobs succeeded in [exact implementation-commit CI 38277299556](https://github.com/RobinBrohl/storeos/actions/runs/38277299556). Acceptance: **107 PASS / 2 QUALIFIED / 0 FAIL**.
**Documentation-closure publication and its own exact-commit CI remain PENDING**; neither has been completed by this local documentation commit.
Recorded delivery evidence does not mutate or establish Stock. P4.15 is **UNSELECTED**.
See the [P4.14 delivery record](development/phase-4-14-purchase-order-deliveries.md#final-documentation-closure--2026-10-12) for the bounded workflow and verification.
P4.1–P4.14 remain DONE/CLOSED as accepted implementations. P4.13 closure commit 9e9cae3055b324413b93784491055beb20e826c4
and exact closure CI 38229127545 completed successfully; their verified publication
supersedes the pending drafting statements retained below.

## Historical closure context

P4.13 **Planned Preparation Assignment** is **DONE/CLOSED — accepted implementation**
at `625bb7ef9643989e2182c966d87839115a0cca6f` (`Add planned preparation assignments`).
F01 is **CLOSED** after bounded canonical Location UUID remediation and independent
**APPROVE** (153 PASS / 0 FAIL / 0 SKIP). Focused Codex Security returned
**SECURITY APPROVE**; all five jobs succeeded in
[exact implementation-commit CI 38224661628](https://github.com/RobinBrohl/storeos/actions/runs/38224661628).
Current acceptance: **99 PASS / 1 QUALIFIED / 0 FAIL**; final-source regression:
**1,367 package passes**, **16/16 phases**, **15 host journeys + 2 migration/recovery
cases**, Numeric Guided Work **3/3 PASS**. Migration chain **0001–0025**;
0001–0024 and dependencies unchanged. Exact RecipeRevision/Employee/Location/planned
count remain immutable; own explicit start opens one linked Batch atomically.
Requested, original actual and effective corrected counts remain distinct.
No active P4.13 implementation remediation remains. P4.1–P4.12 remain DONE/CLOSED;
P4.12 closure CI 38156014870 was verified before P4.13 implementation.
**Final documentation publication and its own closure-commit CI: PENDING**.
These Markdown edits remain unstaged/uncommitted; no closure SHA/run/outcome is claimed.
**P4.14 UNSELECTED**. See [dated closure](development/phase-4-13-planned-preparation-assignments.md#final-documentation-closure--2026-10-12)
and [acceptance matrix](development/phase-4-13-acceptance.md).

The following P4.12 passage preserves its historical documentation-closure drafting state.
P4.12 closure commit d48856f8 and CI 38156014870 supersede its then-pending publication statements.

P4.12 **Bounded Purchase Orders with Minimal Supplier Identity** is **DONE/CLOSED (accepted implementation)** at `f9122f21cde5149685059a184114b6d958a2bd32` (`Add bounded purchase orders`) on `main`. Initial independent CHANGES REQUIRED led to bounded F01 remediation **CLOSED** and targeted independent **APPROVE**; focused Codex Security returned **SECURITY APPROVE**. All five jobs succeeded in [implementation-commit CI 38152045998](https://github.com/RobinBrohl/storeos/actions/runs/38152045998). Current acceptance: **93 PASS / 3 QUALIFIED / 0 FAIL**, with **1,261 final-source package tests**, **16/16 verification phases**, **13/13 opt-in journeys** and **3/3 numeric browser stages** PASS. Migration chain: **0001–0024**, latest `0024_bounded_purchase_orders.sql`; historical 0001–0023 unchanged, no 0025. P4.1–P4.11 remain DONE/CLOSED; **P4.13 remains UNSELECTED**. The final documentation-only closure commit and its own exact-head remote CI are **PENDING PUBLICATION**; no closure SHA, run or outcome exists yet. See [P4.12 closure evidence](development/phase-4-12-bounded-purchase-orders.md#final-documentation-closure--2026-10-11).

The following P4.11/P4.10 closure records describe their historical closure state.

P4.11 ONE-WAY SHIFT TRANSFER BEFORE EXECUTION is **DONE/CLOSED** at implementation
commit `b82dda89374ed9b4182630de4991b0d1569b8ae8` (`Add one-way shift transfer`)
on `main`. Initial independent **CHANGES REQUIRED** led to F01/F02/F03 closure
and targeted **APPROVE**: **177 PASS / 0 QUALIFIED / 0 FAIL**. Focused Codex
Security returned **SECURITY APPROVE**, with no confirmed/probable vulnerability,
required remediation or security commit blocker. All five jobs succeeded in
[exact-commit CI 38125193187](https://github.com/RobinBrohl/storeos/actions/runs/38125193187).
Final remediation regression: **1,133 package tests**, **21/21 phases**,
**11/11 conditional journeys** and **3/3 numeric browser stages** PASS.
Migration `0023_one_way_shift_transfers.sql` is delivered; the chain is
**0001–0023** at P4.11 closure, with unchanged historical migrations 0001–0022.
No active P4.11 remediation remains. **P4.12 was UNSELECTED at that closure**; its current accepted implementation is recorded above. See [P4.11 final closure](development/phase-4-11-one-way-shift-transfers.md#final-documentation-closure--2026-10-11).

P4.10 Preparation Batch is **DONE/CLOSED** at implementation commit
`e637187b17d4617212acf42b99a07500e9488c3d` on `main`. Initial independent
**CHANGES REQUIRED** led to F01/F02 remediation and targeted **APPROVE**;
nonblocking F03 documentation follow-up is **CLOSED**. Final acceptance is
**156 PASS / 0 QUALIFIED / 0 FAIL**, with **931 package tests**, **18/18**
remediation-focused Flutter tests and **19/19** final-source phases PASS.
Focused Codex Security returned **SECURITY APPROVE**: zero confirmed/probable
vulnerabilities, zero required security fixes and no security commit blocker.
All five jobs succeeded in [exact-commit CI 37632074236](https://github.com/RobinBrohl/storeos/actions/runs/37632074236).
Migration `0022_preparation_batches.sql` is delivered/accepted; the committed
chain at P4.10 closure was 0001–0022; P4.11 now extends it through 0023. Location-scoped declarations pin an exact
published RecipeRevision, retain immutable terminal evidence and append-only
count corrections, and have no Stock, Task/Shift or yield/output-unit effects.
No active P4.10 or P4.11 remediation remains. P4.11 is DONE/CLOSED; P4.12 was unselected at that historical closure; its current accepted implementation is recorded above. See [P4.10 development record](development/phase-4-10-preparation-batches.md) and [ADR 0024](adr/0024-preparation-batch-evidence.md).

P4.9 Approved Article Recipe / Composition (composition only) is **DONE/CLOSED**
at implementation commit `e5e6d5c2999bb9f8132161b43ad1537aa403973c` on `main`.
Initial independent review **CHANGES REQUIRED** led to bounded F01–F05 remediation,
then targeted **APPROVE**, **151 PASS / 1 QUALIFIED / 0 FAIL** and focused Codex
Security **SECURITY APPROVE** (zero confirmed/probable vulnerabilities, zero required
security fixes, no security commit blocker). Criterion 152 is qualified solely for
historical forensic evidence scope; it is no product/security defect or closure blocker.
All five exact-commit jobs succeeded in [CI 37581798736](https://github.com/RobinBrohl/storeos/actions/runs/37581798736).
At P4.9 closure the migration chain ended at `0021_recipe_compositions.sql`; 0001–0020 retain
unchanged Git content. No active P4.9 remediation remains. Next after the closure
commit, fresh P4.10 selection was completed. The final P4.10 closure is recorded above.
See [P4.9 development record](development/phase-4-9-recipe-compositions.md) and [ADR 0023](adr/0023-approved-article-recipe-composition.md).


P4.8 Selected-Article Inventory Count is **DONE/CLOSED** at implementation commit
`cba9bff10a8d32bfcda39ee428436153ca2fc044` on `main`. Initial independent review
**CHANGES REQUIRED** led to bounded F01–F04 remediation, followed by targeted
**APPROVE**, **124/124 PASS / 0 QUALIFIED / 0 FAIL** and focused Codex Security
**SECURITY APPROVE** (zero confirmed/probable vulnerabilities; no security commit blocker).
All five exact-commit jobs succeeded in [CI 37453860163](https://github.com/RobinBrohl/storeos/actions/runs/37453860163).
At P4.8 closure the migration chain ended at `0020_stock_counts.sql`; 0001–0019 and dependencies/lockfiles
are unchanged. No active P4.8 remediation remains. Next after the closure commit:
**fresh P4.9 capability selection** was subsequently completed; current P4.9 delivery is recorded above.
See [P4.8 contract and closure evidence](development/phase-4-8-stock-counts.md#final-documentation-closure--2026-10-06).


P4.7 Task + exact Planogram Assignment execution pinning is **DONE/CLOSED** at implementation commit
`ccfa3df78f141da9577e988a9f8ddfb21ca4df1f` on `main`. Before documentation closure, HEAD matched cached and live
`origin/main`; the tree/index were clean, with no stash and one intended worktree.
Initial independent review **CHANGES REQUIRED** led to bounded LOW F01/F02 remediation
and targeted **APPROVE**; final product acceptance is **80/80 PASS**. Initial Codex Security
**SECURITY CHANGES REQUIRED** identified LOW/CWE-863 configured work-Location scope F01;
bounded runtime authorization remediation is complete and the supplied targeted security
re-review returned **SECURITY APPROVE**. All five exact-HEAD jobs succeeded in
[changed-commit CI 37377829784](https://github.com/RobinBrohl/storeos/actions/runs/37377829784). Migration 0019 completes the 0001–0019 chain;
0001–0018 and dependencies/lockfiles are unchanged. No active P4.7 remediation remains.
Existing P4.1–P4.6 closure remains intact. Next after the documentation closure commit:
P4.8 selection followed that closure; its final closure is recorded above.

See [P4.7 evidence](development/phase-4-7-task-planogram-guidance.md) and [ADR 0021](adr/0021-task-planogram-assignment-guidance.md). Fresh selection/publication requires the exact current eligible Assignment. Historical Task reads keep the stored tuple after reassignment and terminal retirement; opening either guidance panel is read-only. All business acceptance writes used isolated databases; the normal StoreOS database was untouched.

P4.6 closure context:

Start after [AGENTS.md](../AGENTS.md). P4.6 Guided Operation — Task + approved
Knowledge revision pinning is **DONE/CLOSED** at implementation commit
`15679bf3c81f50ca31e4995d5b958d7c27e5284d`. The first independent review returned
**CHANGES REQUIRED** with exactly one LOW commit blocker, F01. Bounded remediation
separates draft selection `guidance_selection_unavailable` from fresh-publication
`guidance_unavailable`; committed replay returns original evidence after current
authorization. Targeted independent review **APPROVE**, **64/64 PASS**, focused
Codex Security **SECURITY APPROVE** and all five jobs green in
[changed-commit CI 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549)
establish closure. Real Flutter/HTTP/PostgreSQL and Chrome journeys, backup/restore,
update/recovery and full regression are recorded. Before closure edits, `main`
was clean and matched cached/live origin, with one worktree and no stash.
At P4.6 closure the migration chain ended at 0018; 0001–0017 were unchanged. See
[P4.6 evidence](development/phase-4-6-task-knowledge-guidance.md#final-documentation-closure--2026-10-05)
and [ADR 0020](adr/0020-task-knowledge-guidance.md). No active P4.6 remediation remains.
That P4.6 closure changed documentation only; no commit, push, branch/dependency change
or database operation occurred in that closure pass. P4.7 was not selected at that time.

P4.5 Approved Operational Knowledge is **DONE/CLOSED**:
independent adversarial review **APPROVE**, **60/60 PASS**, and all five jobs green
in [changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360)
for that exact implementation commit. Its closure migration chain ended at
`0017_approved_operational_knowledge.sql`; 0001–0016 were unchanged at that closure.
No active P4.5 remediation remains. F01/F02 are LOW, non-blocking follow-ups retained
in [technical debt](development/technical-debt.md#p45-low-non-blocking-follow-ups).
See [P4.5 evidence](development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04)
and [ADR 0019](adr/0019-approved-operational-knowledge.md). Browser acceptance does
not establish native-device or accessibility acceptance. That P4.5 closure pass made
no implementation change, commit, push or branch change.

P4.3 Manual Stock Foundation is **DONE/CLOSED**: the committed acceptance correction
has independent targeted review **APPROVE**, **28/28 PASS**, and fully green
[changed-commit CI](https://github.com/RobinBrohl/storeos/actions/runs/37199144795).

P4.4 Local Planogram Execution is **DONE/CLOSED**. Implementation `cd7669ed`
and bounded CI portability fix `73dca5a4` are committed on `main`. Closure combines
the independent full CHANGES REQUIRED review, F01/F02 remediation, targeted
**APPROVE**, acceptance 1–49 PASS / 50A PASS / 50B QUALIFIED / 51–68 PASS,
and fully green [changed-commit CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802)
for portability-fix commit `73dca5a4`. All five jobs succeeded. Migration/update/
recovery, backup/restore, real Flutter/HTTP/PostgreSQL journeys and browser print
acceptance are recorded in the [final closure](development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04).
Browser evidence does not establish physical printer/device or accessibility acceptance.
F01/F02 are **CLOSED**; F03 is an **ACCEPTED LIMITATION / NON-BLOCKER** and F04 is
**QUALIFIED BASELINE EVIDENCE / NON-BLOCKER**. No P4.4 remediation remains active
absent regression. The first failed [CI run 37214855513](https://github.com/RobinBrohl/storeos/actions/runs/37214855513)
is retained as historical CI configuration evidence. No production code change
was required for that fix. [ADR 0018](adr/0018-local-planogram-execution.md) remains unchanged in decision.

Use [actual status](roadmap/status.md) for delivery, [vision](vision.md) for the
product, [roadmap](roadmap/phases.md) for sequencing and [technical debt](development/technical-debt.md)
for live findings. The [2026-10-04 audit](development/project-health-audit-2026-10-04.md)
preserves the earlier audit baseline; the [P4.3 closure](development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04)
records the accepted correction and current-head CI.

## Done and active work

- P0/P1 single-site foundation and platform administration are delivered, including
  fixed roles, local authentication, account self-password change, atomic audit,
  organization outbox and restricted external plugin clients.
- P1b.1–P1b.9 deliver Employee identity, versioned task templates, Employee Home,
  guided confirmation/numeric execution, blocking/resolution, cancellation and
  pre-execution published-shift interval amendment. No general rescheduling or swaps.
- P4.1 Article and P4.2 location Assortment are committed; historical remote CI is
  recorded for these baselines. Article unit remains a label, not a conversion system.
- P4.3 manual Stock is **DONE/CLOSED**: foundation `e8ce8c3`, accepted retry/session/
  dialog/fake correction `f9c8b07`, migration chain ending at `0015_manual_stock.sql`
  ([ADR 0017](adr/0017-manual-stock-foundation.md)). Ledger and adjustment retry
  semantics are accepted; no active P4.3 remediation gate remains absent regression.
- P4.4 Local Planogram Execution is **DONE/CLOSED**: independent Company Planograms,
  local Fixtures, immutable published revisions, explicit append-only Assignments,
  target-Location Assortment validation and browser HTML/CSS print. The migration
  chain at closure ended at `0016_local_planograms.sql`; 0001–0015 retain identical Git content,
  with historical raw checkout-byte evidence qualified rather than asserted.
- P4.5 Approved Operational Knowledge is **DONE/CLOSED**: Company-wide
  instructions, one draft, immutable published/discarded revisions, terminal
  retirement and strict publication replay. Migration 0017 adds two tables;
  0001–0016 retain identical Git content. Independent review APPROVE, 60/60 PASS,
  real Flutter/HTTP/PostgreSQL and Chrome journeys, backup/update/recovery, full
  regression and green changed-commit CI establish closure. At P4.5 closure, no Task
  evidence integration existed; P4.6 adds exact pins. No Knowledge events exist.
  F01/F02 remain LOW, non-blocking follow-ups.
- P4.6 Guided Operation is **DONE/CLOSED**: optional concrete KnowledgeGuidance in
  schema-3 Templates and immutable Task snapshots, exact contextual historical read,
  scoped authorization and literal text rendering. No acknowledgment or execution
  mutation on read. Migration 0018; targeted APPROVE, 64/64 PASS, SECURITY APPROVE
  and green changed-commit CI. Native-device/accessibility acceptance is not claimed.
- Highest broadly completed foundation remains P1; later slices do not mean all
  intervening roadmap domains are complete. P2 has bounded recovery/capacity tooling,
  not device queues, distributed sync, HA or automatic restore activation.

## Architectural invariants

- Local-first, self-hosted Dart modular monolith, PostgreSQL and Flutter.
  Logical modules live under `apps/server/lib/src/`; `modules/` is reserved.
- One configured Company per installation; other named Locations can be registered.
  That does not implement multi-site execution or replication.
- Domain/Application owns business rules; routes and widgets delegate.
  Cross-module work uses public ports and a shared local transaction.
- `runAuthorized` revalidates session, rights and scope under a Company advisory lock.
  State, relevant audit and required events commit together.
- Workforce owns shifts; Tasks owns snapshots/execution/evidence. Publication is
  atomic; no shift/task integration events currently exist without a consumer.
- Inventory owns Article/Assortment. Stock owns immutable movements and level
  projections; it reads the released inventory projection/port, not foreign tables.
  Existing stock survives Article/Assortment deactivation.
- IDs and immutable snapshots/evidence are preserved. Migrations 0001–0024 are
  append-only; no applied file edits, silent overwrite or evidence deletion.
- Personnel decisions remain human. Task activity is not attendance or employee scoring.

Details: [module boundaries](architecture/module-boundaries.md),
[ownership](architecture/data-ownership.md), [ADRs](adr/README.md),
[principles](product-principles.md).

## Active blockers and debt

P4.12 F01 is CLOSED; no actionable independent review finding or security commit blocker remains. Nonblocking Security INFO observations I01–I03 remain explicit [follow-ups](development/technical-debt.md#p412-security-info-observations): SQL NULL/UNKNOWN timestamp and receipt JSON checks are not hardened by this closure. Supported-API exploits are not established; complete handcrafted-SQL transaction exploits were not reproduced.

F01/F06/F07 and targeted-review findings R1/R2/R3 are **CLOSED** by `f9c8b07`,
review APPROVE and changed-commit CI. The [P4.3 record](development/phase-4-3-manual-stock.md)
preserves the original defects, CHANGES REQUIRED review and final acceptance.
Pending recovery remains memory-only; session replacement ends local tracking
without cancelling or reversing a server operation and requires authoritative reload.

M1 remains active before a proxied real-user pilot: the current login limiter sees
the proxy socket address. Arbitrary forwarded headers are not a trusted fix.
M3/M4 global API/error debt remains; every new endpoint must contain it with
complete contracts, explicit errors and negative HTTP tests. External API/SDK work
requires broader review. **M2 is closed by migration 0012**, not deferred.

Other live items include scope consistency before multi-site execution, readiness's
early-schema-only check and maintenance couplings. P4.4 closes the touched
harness diagnostic redaction and migration refusal findings with review and CI
evidence. See [technical debt](development/technical-debt.md) for triggers and evidence;
[risks](risks-and-open-questions.md) separates product/operator decisions.

## How to Run StoreOS

Use [local development](development/local-development.md) for SDK versions, setup,
bootstrap, server/client commands, checks, E2E prerequisites and upgrade conventions.
Use [deployment](architecture/deployment.md), [Docker](../infra/docker/README.md),
[TLS](../infra/reverse_proxy/README.md) and [backup/restore](../infra/backup/README.md)
for operation. The old long handover is preserved as a [historical snapshot](development/handover-snapshot-2026-10-03.md).

Apply all migrations before starting a new binary; `/ready` currently checks only
0001–0004 and is not proof of full schema compatibility. Client sessions and pending
commands are memory-only. Disconnected devices cannot persist offline commands.

A restored database is fenced. Recovery acceptance does not prove automatic
replacement activation, downgrade, target-hardware capacity or all physical devices.
Before real employee data: decide retention/access/export/deletion/offboarding,
RPO/RTO, key custody/off-host restore and supported devices. No compliance certification.

## Next Recommended Work

1. P4.10 Preparation Batch is DONE/CLOSED with no active remediation.
   P4.11 is DONE/CLOSED: F01/F02/F03 CLOSED, targeted APPROVE, SECURITY APPROVE and green exact-commit CI 38125193187. P4.12 is DONE/CLOSED with F01 CLOSED, targeted APPROVE, SECURITY APPROVE and successful implementation CI 38152045998; documentation closure CI 38156014870 successful. P4.13 is DONE/CLOSED — accepted implementation; F01 CLOSED, targeted APPROVE, SECURITY APPROVE and exact implementation CI 38224661628 successful. P4.13 closure publication/CI 38229127545 verified successful. P4.14 DONE/CLOSED — accepted implementation at 0c62bdf977727c8fa9ddf645e09cc1b34c0ab4df; functional and targeted APPROVE, F01/F02 CLOSED, SECURITY APPROVE, verification PASS, implementation CI 38277299556 SUCCESS; documentation-closure publication and its own CI PENDING. P4.15 DONE/CLOSED — accepted implementation; implementation/correction/main CI are recorded above; separate documentation-closure publication and its own CI PENDING. P4.16 SELECTED / DESIGN IN PROGRESS (design only; implementation NOT AUTHORIZED).
2. Resolve M1 when adopting a real-user proxy topology; apply M3 containment to
   every API-adding slice and the remaining debt only at its stated triggers.

No feature, commit, push or branch change is authorized by this handover.
The [workflow](development/workflow.md) defines the development process; new
technical material is English. Avoid unrelated refactors and speculative abstractions.
