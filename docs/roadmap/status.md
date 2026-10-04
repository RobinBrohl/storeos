# Actual implementation status

P4.4 development baseline verified 2026-10-04 against `main` at `ed91a05ccbe9b61afaf92914c34f844aff64f638`.
HEAD matches cached and live `origin/main`; tree/index were clean before this
P4.4 implementation, with one worktree and no stash. Baseline migrations were 0001–0015; local implementation adds 0016.

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
| P2 bounded recovery/capacity tooling | DONE | Encrypted restore, opt-in concurrent-work measurement and forward-only update/isolated recovery acceptance. | [Restore](../development/phase-2-restore-acceptance.md), [capacity](../development/phase-2-capacity-measurement.md), [update](../development/phase-2-update-recovery-acceptance.md). Dated extensions cover migrations through 0015; no automatic replacement activation/downgrade. |
| P4.3 manual Stock | DONE / CLOSED | Foundation `e8ce8c3`; migration 0015 / ADR 0017. Acceptance correction committed `f9c8b07`: immutable scoped retries, immediate session fencing, typed outcomes, definitive 413/415 rejection, separate refresh warnings, retained dialog input, neutral abandonment and faithful fake semantics. Server semantics unchanged. | Independent targeted review APPROVE, 28/28 PASS; changed-commit [CI run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795), all five jobs green. [Slice closure](../development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04); F01/F06/F07 and R1/R2/R3 CLOSED. |

## Accepted manual Stock boundaries

The server supports strict movement-ID replay with actor/payload checks. The client
preserves that identity in the accepted correction, including duplicate submissions
and exact retries. R1's replacement-status window is fixed with immediate context
publication and independent live-identity checks. No active P4.3 remediation gate
remains absent regression. Raw runtime-role SQL remains outside supported-writer
semantics under the accepted threat model.
Tracking is memory-only: browser reload, logout or client/session replacement cannot
guarantee recovery of an unconfirmed adjustment. No durable offline recovery exists.

P4.4 Local Planogram Execution is **IMPLEMENTED LOCALLY / TARGETED REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING**:
uncommitted on `main` from dynamically verified `ed91a05ccbe9b61afaf92914c34f844aff64f638`.
The user selected the pasted product contract as the complete architecture, replacing
the former unselected-capability statement. Migration 0016 is new; 0001–0015 have
unchanged Git content. Historical literal byte identity is qualified by unavailable
pre-implementation fingerprints and known CRLF checkout representations in 0005/0007/0008/0009.
Independent review F01/F02 are remediated locally; targeted review and remote
changed-commit CI remain pending. F03's raw-SQL pointer limitation is accepted under
the supported-writer boundary. See [ADR 0018](../adr/0018-local-planogram-execution.md)
and [development evidence](../development/phase-4-4-local-planograms.md). P4.3 closure above is unchanged.

## Planned and deferred scope

| Domain | Delivery | Boundary |
| --- | --- | --- |
| P2 device offline / headquarters sync | PLANNED | No client persistent queue, native-device acceptance, distributed authority transfer or selective replication. Local server operation without WAN is separate. |
| Workforce / Tasks / Wiki extension | PLANNED | Recurrence, recommendations, qualification workflows, approved Wiki guidance and swaps are future slices. Begun-work reconciliation remains open. |
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
