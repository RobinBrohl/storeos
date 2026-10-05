# Actual implementation status

P4.7 Task + exact Planogram Assignment execution pinning is **IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING** on `main`, uncommitted and unstaged. The verified starting HEAD was `a0ed6346f7453c8f4e170aee43af8d775677f97b`, matching cached/live origin; all five exact-HEAD jobs succeeded in [baseline CI 37290533013](https://github.com/RobinBrohl/storeos/actions/runs/37290533013). New migration 0019 adds schema 4 and durable Fixture/Assignment/Revision integrity; migrations 0001–0018 and dependencies/lockfiles are unchanged. Existing P4.1–P4.6 closure remains intact. No P4.8 capability is selected.

See [P4.7 evidence](../development/phase-4-7-task-planogram-guidance.md) and [ADR 0021](../adr/0021-task-planogram-assignment-guidance.md). This is local implementation evidence, not DONE/CLOSED or remote verification of changed code.

P4.6 historical closure:

P4.6 Guided Operation — Task + approved Knowledge revision pinning is
**DONE/CLOSED** at implementation commit
`15679bf3c81f50ca31e4995d5b958d7c27e5284d` on `main`. Before documentation closure,
HEAD matched cached and live `origin/main`; tree/index were clean, with one intended
worktree and no stash. The first independent adversarial review returned
**CHANGES REQUIRED** for exactly one actionable issue: F01, LOW but commit-blocking,
selection-time reuse of publication-only `guidance_unavailable`. Bounded remediation
is complete; targeted independent review **APPROVE**, **64/64 PASS**, focused Codex
Security **SECURITY APPROVE** and all five successful jobs in
[changed-commit CI 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549)
establish closure. No confirmed/probable vulnerability or security commit blocker
remained; no active P4.6 remediation remains. Migration 0018 adds concrete schema-3
pins and bounded Task/Knowledge reference integrity; 0001–0017 and dependencies/
lockfiles remained unchanged at that closure, with no 0019 then. Real Flutter/HTTP/PostgreSQL and Chrome
journeys, backup/restore, update/recovery and full regression are preserved in
[final evidence](../development/phase-4-6-task-knowledge-guidance.md#final-documentation-closure--2026-10-05).
See [ADR 0020](../adr/0020-task-knowledge-guidance.md). Fresh P4.7 selection was the next step at that closure; the current local implementation is recorded above.

P4.5 starting source baseline verified 2026-10-04 against `main` at `ce00a241b967ab9242604e4d043a8241b3593f64`.
HEAD matched cached and live `origin/main`; tree/index were clean before implementation,
with one intended worktree and no stash. P4.4 implementation `cd7669ed`,
migration 0016 and bounded CI portability fix `73dca5a4` are committed. Historical
development/review/CI states are retained in the slice evidence.

P4.5 Approved Operational Knowledge is **DONE/CLOSED** at implementation commit
`93072a476f93e8fb14da357b0a4b747435369376` on `main`. Before closure edits, HEAD
matched cached and live `origin/main`; the tree/index were clean, with no stash and
one intended worktree. Independent adversarial review **APPROVE**, **60/60 PASS**,
and all five successful jobs in [changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360)
establish closure alongside real Flutter/HTTP/PostgreSQL and Chrome journeys,
backup/restore, update/recovery and full regression. Migration 0017 adds exactly
two Knowledge-owned tables; 0001–0016 remained unchanged at that closure and no
dependency/lockfile changes were introduced. No active P4.5 remediation remains.
[Final evidence](../development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04)
and [ADR 0019](../adr/0019-approved-operational-knowledge.md) define the bounded slice.

P4.3 Manual Stock Foundation is **DONE/CLOSED**. Foundation commit
`e8ce8c319e2dd3051b402d252a0666f33b170fa3` and acceptance correction
`f9c8b070f870cabbba3ae7b63bf16190b46aad8e` are committed. The authoritative
independent targeted review supplied for reconciliation is **APPROVE**, with
**28/28 acceptance criteria PASS**, R1/R2/R3 closed and no new actionable findings
or commit blockers. All five jobs in
[CI run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795)
are successful for the correction commit. The [slice record](../development/phase-4-3-manual-stock.md)
preserves the earlier 474/491-test runs, CHANGES REQUIRED review and final closure.

**DONE** means the bounded delivered scope below; **ACTIVE** means current work or
unresolved acceptance; **PLANNED** means no active delivered slice. Implementation,
commit, review and CI are separate facts. [Phase records](../README.md#slice-contracts-and-evidence)
hold dated evidence; [vision](../vision.md) is not an implementation checklist.

## Delivered foundation and bounded slices

| Scope | Delivery | Implementation / commit boundary | Verification evidence |
| --- | --- | --- | --- |
| D0, P0 single-site foundation | DONE | Documentation, four packages, Flutter Web, Dart HTTP, PostgreSQL, setup/migration/bootstrap, logs, CI configuration, TLS example and encrypted backup/isolated restore. | [P0 evidence](../development/phase-0-verification.md); native runners excluded. |
| P1 platform administration | DONE | Company/Location setup, Accounts, fixed roles, audit, organization outbox, external plugin registry/read API. | [P1 evidence](../development/phase-1-verification.md); no executable plugin runtime. |
| P1 self-service password change | DONE | Self-only current-password verification, bounded verification limiter, atomic password/audit/all-session revocation; committed `9aef373`. | [Slice](../development/phase-1-self-service-password-change.md) records independent review and remote CI. |
| P1b.1 employee identity | DONE | Minimal Employee, fixed Location, explicit Account link, self profile and revocation. Migration 0004. | [Evidence](../development/phase-1b-verification.md). |
| P1b.2 task templates | DONE | Location-scoped drafts and immutable published revisions. Migration 0005. | [Evidence](../development/phase-1b-templates-verification.md). |
| P1b.3 shifts/Employee Home | DONE | Single shifts; atomic publication and task snapshots. Migration 0006 / ADR 0011. | [Evidence](../development/phase-1b-shifts-verification.md). |
| P1b.4–P1b.6 guided execution and exceptions | DONE | Start/confirm/complete, command receipts, block/resume and terminal blocked-task cancellation. Migrations 0007–0009. | [Execution](../development/phase-1b-execution-verification.md), [blocking](../development/phase-1b-blocking-verification.md), [cancellation](../development/phase-1b-cancellation-verification.md). |
| P1b.7 numeric Guided Work | DONE | Schema 2, exact thousandths, fixed inclusive bounds, immutable attempts and automatic blocking. Migration 0010. | [Numeric evidence](../development/phase-1b-7-numeric-verification.md), including historical browser/process-replacement E2E. |
| P1b.8 published-shift cancellation | DONE | Only pristine open tasks; Tasks and Workforce cancel atomically. Migration 0011 / ADR 0013; committed `19151f6`. | [Slice](../development/phase-1b-8-shift-cancellation.md) records independent review/re-review and remote CI. |
| P1b.9 published-shift interval amendment | DONE | Only starts/ends before any task begins; no task regeneration or employee/template reassignment. Migration 0012 / ADR 0014; committed `f37dd6b`. M2 overlap exclusion is implemented. | [Slice](../development/phase-1b-9-shift-amendment.md) records review and remote CI. |
| P4.1 Company-wide Article | DONE | SKU, optional opaque barcode, unit label, activation lifecycle, audit and Web UI. Migration 0013 / ADR 0015; `a4aeecd` with `d0fcf43`/`d90dd7e` corrections. | [Slice](../development/phase-4-1-article-master.md) records remote CI run 31 on `d90dd7e`. |
| P4.2 location Assortment | DONE | Membership with independent activation and effective availability; no quantity/price. Migration 0014 / ADR 0016; committed `3bc27d5`. | Historical remote CI is recorded in the prior handover/status and [update follow-up](../development/phase-2-update-recovery-acceptance.md); not rechecked online here. |
| P2 bounded recovery/capacity tooling | DONE | Encrypted restore, opt-in concurrent-work measurement and forward-only update/isolated recovery acceptance. | [Restore](../development/phase-2-restore-acceptance.md), [capacity](../development/phase-2-capacity-measurement.md), [update](../development/phase-2-update-recovery-acceptance.md). [P4.4 acceptance](../development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04) extends migration/recovery and backup evidence through 0016; no automatic replacement activation/downgrade. |
| P4.3 manual Stock | DONE / CLOSED | Foundation `e8ce8c3`; migration 0015 / ADR 0017. Acceptance correction committed `f9c8b07`: immutable scoped retries, immediate session fencing, typed outcomes, definitive 413/415 rejection, separate refresh warnings, retained dialog input, neutral abandonment and faithful fake semantics. Server semantics unchanged. | Independent targeted review APPROVE, 28/28 PASS; changed-commit [CI run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795), all five jobs green. [Slice closure](../development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04); F01/F06/F07 and R1/R2/R3 CLOSED. |
| P4.4 Local Planogram Execution | DONE / CLOSED | Implementation `cd7669ed`; CI portability fix `73dca5a4`; migration 0016 / ADR 0018. Company Planogram, Location Fixture, immutable published Revision, explicit append-only Assignment, target Assortment validation and browser HTML/CSS print. | Full independent review, bounded F01/F02 remediation, targeted APPROVE; 1–49 PASS, 50A PASS, 50B QUALIFIED, 51–68 PASS, no blockers. All five jobs green in [CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802). [Final closure](../development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04) records real journeys, browser print and backup/update/recovery acceptance. |
| P4.5 Approved Operational Knowledge | DONE / CLOSED | Implementation 93072a4; migration 0017 / ADR 0019. Company-scoped WikiArticle, one active draft, immutable published/discarded WikiRevision, current published pointer, terminal retirement and strict publication replay. Plain text, Company-wide audience; no Task evidence or events. | Independent adversarial review APPROVE, 60/60 PASS; all five jobs green in [changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360). [Final closure](../development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04) records real journeys, Chrome workflow, backup/update/recovery and full regression. F01/F02 LOW non-blocking follow-ups. |
| P4.6 Guided Operation — Task + approved Knowledge revision pinning | DONE / CLOSED | Implementation `15679bf`; migration 0018 / ADR 0020. Optional concrete schema-3 Article/Revision pin, frozen Template content, immutable Task snapshot and exact contextual historical read; no copied Knowledge text or readership evidence. | Full independent CHANGES REQUIRED review, bounded F01 remediation, targeted APPROVE, 64/64 PASS, focused Codex Security SECURITY APPROVE; all five jobs green in [changed-commit CI 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549). [Final closure](../development/phase-4-6-task-knowledge-guidance.md#final-documentation-closure--2026-10-05) records real journeys, Chrome, backup/update/recovery and full regression. No active remediation. |
| P4.7 Task + exact Planogram Assignment execution pinning | IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING | Schema 4; one optional concrete Fixture/Assignment/Revision pin, current deployment selection, atomic fresh-work validation and retained contextual reads. Migration 0019 / ADR 0021; uncommitted/unstaged on main. | [Local evidence](../development/phase-4-7-task-planogram-guidance.md); targeted security re-review and changed-commit CI remain pending; independent normal review APPROVE is preserved. |

## Accepted manual Stock boundaries

The server supports strict movement-ID replay with actor/payload checks. The client
preserves that identity in the accepted correction, including duplicate submissions
and exact retries. R1's replacement-status window is fixed with immediate context
publication and independent live-identity checks. No active P4.3 remediation gate
remains absent regression. Raw runtime-role SQL remains outside supported-writer
semantics under the accepted threat model.
Tracking is memory-only: browser reload, logout or client/session replacement cannot
guarantee recovery of an unconfirmed adjustment. No durable offline recovery exists.

## Accepted Local Planogram boundaries

P4.4 is **DONE/CLOSED**, with no active remediation absent regression. F01/F02 are
**CLOSED**; F03 is an **ACCEPTED LIMITATION / NON-BLOCKER** and F04 is
**QUALIFIED BASELINE EVIDENCE / NON-BLOCKER**. Database guarantees cover scope/
ownership, immutable published content, append-only Assignment evidence and cross-
Fixture/Company/Location protection. Supported Assign atomically inserts Assignment,
advances current/latest pointer and Fixture version, and appends audit. Arbitrary
direct runtime SQL can deliberately repoint a Fixture to its own older Assignment
without advancing version, outside that supported-writer guarantee.

Migration 0016 is the P4.4 migration; 0001–0015 have unchanged Git content at that
closure. P4.5 adds 0017 without changing 0001–0016. Historical raw checkout-byte fingerprints are unavailable; CRLF
representations in 0005/0007/0008/0009 are qualified baseline evidence, not a P4.4
defect. No old migration was rewritten or normalized. The failed first
[CI run 37214855513](https://github.com/RobinBrohl/storeos/actions/runs/37214855513)
and its CI configuration root cause remain in the [development history](../development/phase-4-4-local-planograms.md).
Browser print acceptance covers rendering/adapter behavior only. Physical devices,
accessibility, offline queues, HQ rollout, PDF generation, Stock mutation and
Tasks/Guided Work integration are outside this slice. Uncertain command tracking
remains memory-only. See [ADR 0018](../adr/0018-local-planogram-execution.md).

## Accepted Approved Knowledge boundaries

P4.5 is **DONE/CLOSED**, with no active remediation. F01/F02 remain **LOW —
NON-BLOCKING FOLLOW-UP**, not commit blockers; see [technical debt](../development/technical-debt.md#p45-low-non-blocking-follow-ups).
Capabilities are `knowledge.articles.read`, `knowledge.articles.manage` and
`knowledge.articles.publish`. Admin has all three; employee has read only.
Viewer, auditor and approved plugin tokens have none; roles remain fixed.
Standalone employees read only active Articles' current published revisions;
P4.6 adds the narrowly authorized exact Task-context exception below. Search uses only
their current published titles, filters visibility before pagination and treats
%, _ and backslash literally. Draft/discarded/historical titles and retired
Articles do not leak through discovery or employee management access.

Publication is approval. Fresh authorization precedes exact replay, which returns
original evidence without duplicate audit, version/pointer changes or retirement
reversal. Late v1 replay leaves v2 current; replay after retirement leaves the
Article retired. Conflicting operation reuse returns `operation_conflict`.
No hard delete, readership tracking, generic receipt table or events/outbox exist.
At P4.5 closure, Task schema, snapshots, publication and execution were unchanged.
P4.6 is DONE/CLOSED and adds exact assigned-revision evidence.
Knowledge discovery/navigation still creates no readership evidence.
Native-device/accessibility acceptance and durable offline recovery are not claimed.

## Accepted Guided Operation boundaries

P4.6 is **DONE/CLOSED**. Optional KnowledgeGuidance stores only `articleId` and
`revisionId`; schema 3 explicitly permits null, and schemas 1/2/old content remain
unchanged. Draft selection captures an exact approved revision; Template publication
freezes it, fresh Shift publication revalidates and materializes it into immutable
Task content, and execution resolves the stored pin. Publishing Knowledge v2 leaves
retained Template/Task v1 pins and contextual reads at v1.

Retirement after work publication keeps the Article retired and unavailable through
standalone employee discovery, while legitimate contextual v1 reads and Task
execution/completion continue. Retirement before fresh Template/Shift publication
rejects that publication. Retirement is not emergency withdrawal.

Employees need a valid current session, active Employee link, Company/Location/work
visibility, own visible Shift/Task, Task self-read and Knowledge read. Managers need
existing authorized Shift/Task scope plus Knowledge read. The endpoint derives both
IDs from stored Task content; clients cannot select arbitrary historical revisions.
Viewer/auditor/plugin credentials are denied. Guided Template authoring/publication
and Shift publication require their existing Task/Shift authorization plus Knowledge
read where guidance exists. No configurable RBAC or general history browser is added.

Draft create/replacement failure uses `guidance_selection_unavailable`; unusable
retained guidance at fresh Template/Shift publication uses `guidance_unavailable`.
Committed replay requires fresh auth/scope and returns original evidence without
either later-lifecycle availability error: original Template evidence or Shift/Task
IDs, unchanged pins, no duplicate Tasks or audit.

Opening Assigned instruction neither starts/completes work nor confirms a step,
satisfies numeric input, acknowledges reading or creates a receipt/event/audit.
Completion retains immutable Knowledge identity. Text renders literally, without
content-generated active links/images, HTML/script execution or rich Markdown;
this is literal rendering, not a general sanitizer. Mutation audit may contain
`knowledgeArticleId`/`knowledgeRevisionId`, never title/body/full content in audit/logs.
Tasks owns selection and snapshots, Knowledge owns content/lifecycle/exact validation
and contextual resolution, and Workforce owns Shift publication context. Public
ports preserve repository ownership. No Planogram/per-step/multiple/generic guidance,
read acknowledgment, native-device/accessibility acceptance or offline queue is claimed.

## Planned and deferred scope

Next: targeted security re-review of bounded P4.7 Security F01 remediation and remote changed-commit CI. Independent normal review APPROVE is preserved. No active P4.6 remediation remains; P4.8 is not selected.

| Domain | Delivery | Boundary |
| --- | --- | --- |
| P2 device offline / headquarters sync | PLANNED | No client persistent queue, native-device acceptance, distributed authority transfer or selective replication. Local server operation without WAN is separate. |
| Workforce / Tasks / Wiki extension | MIXED | P4.6 exact Task pins are DONE/CLOSED. Recurrence, recommendations, qualification workflows and swaps remain future slices; begun-work reconciliation remains open. |
| Inventory / Stock / Purchasing / Production | PLANNED | Beyond existing Article/Assortment/manual Stock: units/conversions, receiving, inventory counts, batches, Recipe, production and valuation. |
| External POS canonical ingestion | PLANNED | No SalesSource, import/checkpoint, mapping or automatic sales effect implementation exists. Candidate sequencing requires a real source and explicit contract. |
| Configurable RBAC / remote / communications | PLANNED | Current roles are fixed; direct grants, context-restricted remote access, Boards, Chat and notification delivery are vision. |
| HACCP, Pricing, Menu/publishing, reporting/finance | PLANNED | No certified safety module, cost/margin basis, structured Menu/public publisher or finance capability exists. |
| StoreOS checkout/POS, general HR, AI | PLANNED / DEFERRED | Optional long-term domains, separate product and regulatory decisions. No dependency from basic sales ingestion to StoreOS checkout. |

P1 is the highest broadly completed foundation; completing later bounded slices
does not declare entire P2–P12 domains complete. The legacy domain labels remain
navigation, not a locked chronological schedule. See [roadmap](phases.md).

## Evidence limits and pilot decisions

The [2026-10-04 audit](../development/project-health-audit-2026-10-04.md) records
453 passing tests, clean analyzers/format, a Web release build and selected
PowerShell checks on its historical `e8ce8c3` source baseline.
Those checks were not rerun for documentation-only changes. Browser E2E, full
backup/update wrappers, target-hardware capacity and physical device acceptance
were not freshly executed by that audit.

Older CI/review evidence proves its named baseline; CI for the correction commit
is recorded above. Remote numeric browser E2E and backup/update acceptance passed;
this documentation pass did not rerun those checks locally or run Stock browser E2E.
The 2026-10-02 health check is historical and its M2/next-password-change
recommendation is superseded by later implementation. [Technical debt](../development/technical-debt.md)
is the live disposition source.

Before real employee data: decide retention/access/export/deletion/offboarding,
RPO/RTO, key custody/off-host recovery and supported devices. M1 needs resolution
or a tested operator mitigation before a proxied real-user pilot. P4.3 software
acceptance does not close physical-device/accessibility or operator gates. No blanket
production, regulatory, native-device or multi-site readiness claim is made.
