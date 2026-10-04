# Risks and open questions

Living register, reconciled 2026-10-04. **OPEN** needs a product/technical decision;
**ANSWERED** points to actual decisions; **SUPERSEDED** identifies an obsolete
premise; **OPERATOR DECISION** needs installation/organizational policy;
**DEFERRED** has a future trigger. No status here authorizes implementation.
[ADRs](adr/README.md) own settled architecture; [technical debt](development/technical-debt.md)
owns demonstrated code findings; [vision](vision.md) owns the intended product.

## Original risk register

Risk IDs are retained. Partial implementation mitigates a risk within its tested
boundary; it does not close every future case.

| ID | Classification | Risk and current disposition / decision gate |
| --- | --- | --- |
| R1 | DEFERRED | Shared model vs autonomous sites: current one-Company local authority is decided; per-aggregate headquarters ownership, replication and writer handoff before multi-site sync remain undecided. |
| R2 | DEFERRED | WAN independence vs disconnected devices: local core is self-hosted; allowed device writes, stale grants, replay/conflict and pending status need a separate offline contract. |
| R3 | OPEN | Dynamic priorities vs fair work: explainable rules, blocked prerequisites, preserved breaks and human override are principles; recurrence/recommendation semantics need a real slice. No employee scoring. |
| R4 | DEFERRED | Plugin availability/least privilege: current approved external read clients are bounded. Isolation/network controls before executing third-party code; a first-party POS adapter need not be a plugin. |
| R5 | OPERATOR DECISION | Supported browsers/devices/scanners/printers and update tests before pilot/device claims; current shipped runner is Web. |
| R6 | OPERATOR DECISION | Audit vs minimization: field purpose, access, retention, export/delete/restriction, attachments and backup handling before real employee data. No blanket sensitive snapshots. |
| R7 | OPEN | Corrections preserve provenance/history; existing versions/receipts/snapshots answer current mutations. Completed-work, sales and fiscal correction semantics remain domain-specific. |
| R8 | OPEN | Product breadth risks half-finished ERP/POS/HR/AI. One small complete vertical slice, truthful acceptance and product boundaries remain the gate. |
| R9 | ANSWERED for current slice | ADR 0011 atomically publishes shifts/tasks; ADRs 0013/0014 define pristine cancellation/interval amendment. Begun work, reassignment and async generation remain separate OPEN questions below. |
| R10 | OPERATOR DECISION | Safety/fiscal/country-specific use needs qualified sector/jurisdiction review. Generic numeric tasks do not certify HACCP or regulatory compliance. |
| R11 | OPERATOR DECISION | Low-IT self-hosting: deployment/backup/update tools mitigate; patching, trusted TLS, off-host restore, monitoring and activation responsibility remain operator gates. Recovery is not arbitrary rollback. |
| R12 | OPERATOR DECISION | AGPLv3/components/custom plugin distribution: review licenses before third-party contributions/commercial integration commitments. |
| R13 | ANSWERED for current commands; DEFERRED externally | Atomic replay/evidence exists for supported task/stock commands and local inbox. External side effects, imports, delayed offline commands and cross-node replay need explicit identity/reconciliation contracts. |
| R14 | DEFERRED | Restores are currently fenced with credentials invalidated; rejoining newer counterpart sync/access/delete state before multi-node reopening is still required. |
| R15 | DEFERRED | Finite queue/storage vs offline duration: define supported disconnection period, data rate, replay retention, cursor restart and warning thresholds before offline/sync release. |
| R16 | DEFERRED | Multiple site writers/global employee rules: choose advisory local checks vs binding global allocation before multi-site planning. No unrestricted parallel authority. |
| R17 | OPEN at relevant version change | Snapshot semantics are preserved in current migrations/tests; define future client/plugin/sync compatibility windows and treatment of active work before an incompatible release. |

## Previous questions: answered and remaining parts

| Topic | Classification | Answer or remaining decision / gate |
| --- | --- | --- |
| Multiple Companies per installation | ANSWERED | Current supported model is one Company per installation; Organization/authorization schema and ADR 0012 establish the bounded scope. Shared-schema tenancy would be a new architecture decision. |
| Account/Employee/Roles across sites | DEFERRED | Current local ownership and revocation exist. Headquarters authority, scoped assignments, offline revocation and selective employee replication before multi-site sync remain open. |
| Shift publication and task creation | ANSWERED | ADR 0011, P1b.3; immutable task snapshots in one local transaction. |
| Published-shift pristine cancellation / interval changes | ANSWERED | ADRs 0013/0014, migrations 0011/0012. Interval changes regenerate no tasks. Old blanket prohibition is SUPERSEDED. |
| Published employee/template changes; begun work | OPEN | Current employee/task snapshot assignments remain immutable. Define reconciliation, preserved evidence, eligibility and permitted operations before enabling it. |
| Device offline evidence and user status | DEFERRED | No persistent queue exists. Decide permitted step/evidence types and visible pending/refused behavior before device offline writes. |
| Disconnection/replay/version support | DEFERRED | Align rights expiry, dedup retention, bounded queues and client/snapshot semantics before sync/compatibility expansion. |
| Retention/export of tasks, devices, audit and employee data | OPERATOR DECISION | Purpose, access and actual periods/workflows before real employee use; cleanup must not precede policy. |
| Resolve a blocked task | ANSWERED | Current admin resume/cancel with reason, scope and audit; employee resumes remaining work. This is not a general safety deviation approval. |
| Correct completed tasks / HACCP deviation | OPEN | Completed/cancelled tasks are terminal. A correction is a separate evidence-preserving domain command; qualified safety approval rules before HACCP. |
| Devices/OS/scanners/printers | OPERATOR DECISION | Select supported device matrix and run hardware/accessibility tests before pilot claims. |
| Site RPO/RTO | OPERATOR DECISION | Set acceptable loss/recovery time, key custody, off-host exercises and activation responsibilities. Existing isolated acceptance does not answer target-hardware recovery time. |
| First real plugin/integration contract and review | OPEN | Select actual source/permissions/adapter deployment. Third-party runtime review/isolation before executing code; current read API is not that runtime. |
| Article units/conversion timing | OPEN | Frozen text unit works for current manual Stock. Decide catalog owner, dimensional precision and explicit conversions before unlike-unit receiving/Recipes/sales effects; not a blocker for canonical sales records. |
| More Article fields | OPEN | Categories, supplier links and GTIN validation require real operator data; optional current barcode is opaque. No speculative master-data expansion. |

## Product decisions added by reconciliation

| Topic | Classification | Decision required before |
| --- | --- | --- |
| Configurable Roles / direct grants | OPEN | System templates, company role assignments, additive direct grants, scope inheritance/revocation and admin lockout protection before RBAC expansion; explicit deny only if justified. |
| Location-scoped permissions | OPEN | One/multiple-location scopes and consistent manager/employee queries before multi-site execution; see L4/L5. |
| Legal entities / Employee lifecycle | DEFERRED | Explicit legal-entity relationships, employment periods, re-entry and data ownership before HR expansion; never conflate Account/Employee identity. |
| Wiki publication/suggestions | OPEN | Review/approve/publish permissions, immutable approved revisions, suggestion lifecycle and historical task pins before Knowledge slice. |
| Fixture / Planogram assignment | OPEN | Generic fixture zones, revision/effective dates, higher-level assignments, acknowledgement/feedback and local override authority before rollout. |
| Recipe unit/yield/cost basis | OPEN | Ingredient/production units and yield/waste policy before calculation; trustworthy effective purchase/average/standard basis before cost/margin. No invented valuation. |
| Production consumption model | OPEN | Finished-goods stock vs ingredient-on-sale consumption, batch provenance and no double consumption before automatic movements. |
| Pricing and Menu content | OPEN | Authoritative effective price/currency, approvals and deterministic revision print before price-bearing Menu artifacts. |
| Public publishing | OPEN | Artifact format, hosting/update/status/rollback boundary before website publication; operational DB/admin APIs stay private. No selected cloud vendor. |
| Boards / Chat membership and privacy | OPEN | Bounded operational use case and controlled admin access before communication design. Boards may precede Chat. |
| Communication retention / offboarding | OPERATOR DECISION | Purpose, periods, export/delete, membership removal, backups/restored access and notification contact use before real communications. No full chat body in default email. |
| ShiftSwapRequest approval | OPEN | Recipient response, comments, responsible approval, stale-version revalidation and atomic mutation before swaps. Linked cancel/replacement is a candidate, not a decided ADR; begun work/marketplace deferred. |
| Remote employee access | OPEN | Authenticated context allowlist, gateway/VPN trust, identity assurance/MFA/recovery and revocation before remote self-service. Network IP alone is insufficient. |
| No private-device use | ANSWERED as product principle | Private smartphone/app is optional; preserve in-store access and print/email/kiosk alternatives. Concrete delivery/access arrangements remain OPERATOR DECISION. |
| Canonical external-POS source | OPEN | Actual vendor API/export contract, configured Company/Location authority, source identity/checkpoints, retry/gap detection and explicit product mapping before ingest slice. DSFinV-K backfill is not itself a real-time API. |
| Sales Stock effect / cutover / returns | OPEN | Source units, physical opening/cutover, delayed/backfill replay, machine actor, physical returns vs void/reversal and production policy before automatic effects. Unresolved effects can stay visible in earlier ingestion. |
| Sales cost/margin reporting | OPEN | Reliable source amounts/currency/tax and effective cost basis before margins; not required for first canonical import. |
| StoreOS-owned checkout | DEFERRED | Separate product decision, payment/fiscal contracts and qualified review; it is not a prerequisite for external-POS import or basic reporting. |
| AI / autonomy | DEFERRED | Demonstrated benefit, approved scoped sources, uncertainty and human critical decisions before optional activation. |

## Current technical and operator gates

P4.3 software acceptance is DONE/CLOSED; F01/F06/F07 and targeted-review findings
R1/R2/R3 are CLOSED by `f9c8b07`, review APPROVE and green changed-commit CI
([closure evidence](development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04)).
These targeted-review IDs are distinct from the product-risk IDs above.
Memory-only recovery and physical-device/operator boundaries remain. M1 requires
a tested disposition before real-user reverse-proxy deployment. M3/M4 need containment on new APIs and
broader review before external API/SDK commitments. M2 is ANSWERED/closed by
migration 0012; old M2 deferral is SUPERSEDED. See the [live debt register](development/technical-debt.md).

Operator/legal decisions are not closed by a successful test suite. [Compliance](compliance/overview.md)
states review boundaries; deployment/restore documentation states technical procedures.
No document in this pass certifies legal compliance.
