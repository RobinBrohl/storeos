# Documentation index

Canonical sources reconciled 2026-10-04. Start with [HANDOVER](HANDOVER.md) after
[AGENTS](../AGENTS.md). Current baseline is `eef2f1e`; P4.6 is implemented locally,
independent review remediation complete / targeted review pending and remote
changed-commit CI pending. See [ADR 0020](adr/0020-task-knowledge-guidance.md)
and [P4.6 evidence](development/phase-4-6-task-knowledge-guidance.md). P4.3 Manual Stock
Foundation is **DONE/CLOSED**, with independent targeted review APPROVE, 28/28 PASS
and all five jobs green in [changed-commit CI run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795).
See the [final closure](development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04).
P4.4 Local Planogram Execution is **DONE/CLOSED**, with targeted review APPROVE,
qualified migration-byte evidence and all five jobs green in
[changed-commit CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802).
The [P4.4 final closure](development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04)
preserves the full review/remediation/failed-CI chronology. No active P4.4 remediation
remains absent regression. P4.5 Approved Operational Knowledge is **DONE/CLOSED**,
with independent adversarial review APPROVE, 60/60 PASS and all five jobs green in
[changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360).
See [final evidence](development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04)
and [ADR 0019](adr/0019-approved-operational-knowledge.md). Current migration chain
ends at 0018; no active P4.5 remediation remains. F01/F02 are LOW non-blocking follow-ups.
P4.6 targeted review/CI remain pending; P4.7 is not selected.
Do not infer delivery from a target architecture description or an Accepted ADR.

## Canonical sources

| Question | Source | What it owns |
| --- | --- | --- |
| What is StoreOS / how do I start? | [Repository README](../README.md), [local development](development/local-development.md) | Product entry and detailed development commands. |
| What should the next developer know now? | [HANDOVER](HANDOVER.md) | Current baseline, invariants, active blockers and next proposals. |
| What product are we building? | [Vision](vision.md), [principles](product-principles.md) | Long-term definitions, priorities and product boundaries. |
| What exists? | [Actual status](roadmap/status.md) | DONE/ACTIVE/PLANNED, implementation/commit/verification boundaries. |
| What comes next / depends on what? | [Roadmap](roadmap/phases.md) | Near-term proposals and long-term domain dependencies, not exact distant promises. |
| What owns what? | [Overview](architecture/overview.md), [module boundaries](architecture/module-boundaries.md), [domain model](architecture/domain-model.md) | Current logical modules and explicitly planned owners/concepts. |
| Why was an architecture choice made? | [ADR index](adr/README.md) | Stable decision records; accepted decision is not completed implementation. |
| What is still risky or undecided? | [Risks/open questions](risks-and-open-questions.md), [technical debt](development/technical-debt.md) | Product/operator decisions versus live code findings and resolution triggers. |
| How do I operate safely? | [Deployment](architecture/deployment.md), [Docker](../infra/docker/README.md), [TLS](../infra/reverse_proxy/README.md), [backup](../infra/backup/README.md), [backup acceptance](../infra/backup/acceptance.md) | Supported procedures, fencing and operator gates. |
| How do I change the repository? | [Development workflow](development/workflow.md) | Contribution process, English technical-language policy and checks. |
| What was verified in a slice? | [Slice records](#slice-contracts-and-evidence) | Dated contract/test/review/CI evidence at the stated baseline. |
| What needs qualified review? | [Compliance](compliance/overview.md) | Sector/legal review boundaries; no compliance certification. |

In a conflict, use the applicable ADR for settled architecture, principles for
product priorities and status for delivery. Update relevant canonical sources
when behavior changes. Preserve historical runs and add dated follow-ups rather
than retroactively changing review/CI outcomes.

## Architecture detail

- [Workforce orchestration](architecture/workforce-orchestration.md) and [Guided Work](architecture/guided-work.md).
- [Events](architecture/event-system.md) and [plugins](architecture/plugin-system.md).
- [Security](architecture/security.md), [offline/sync](architecture/offline-strategy.md) and [data ownership](architecture/data-ownership.md).

## Current audit and historical records

- [Project health/vision audit 2026-10-04](development/project-health-audit-2026-10-04.md): preceding session audit of `e8ce8c3`, checks, findings and explicit gaps.
- [Live technical debt](development/technical-debt.md): current M/L/F dispositions.
- [Milestone health check 2026-10-02](development/milestone-health-check-2026-10-02.md): historical `512ac64` baseline, original M1–M4/L1–L12 and then-next password recommendation; not today's backlog.
- [Handover verification](development/handover-verification.md): historical 2026-09-29 checks, not latest verification.
- [Preserved handover snapshot](development/handover-snapshot-2026-10-03.md): original long handover, earlier baseline/proposals and preserved details.
- [Implementation review](development/implementation-review-2026-09-27.md): dated foundation review.

## Slice contracts and evidence

Records below describe their own slice/run. Original “pending”, “uncommitted”
and older counts inside evidence are historical unless a current header says
otherwise. [Status](roadmap/status.md) and [live debt](development/technical-debt.md)
resolve current delivery and outstanding findings.

- [phase-0-verification](development/phase-0-verification.md)
- [phase-0](development/phase-0.md)
- [phase-1-self-service-password-change](development/phase-1-self-service-password-change.md)
- [phase-1-verification](development/phase-1-verification.md)
- [phase-1](development/phase-1.md)
- [phase-1b-7-numeric-steps](development/phase-1b-7-numeric-steps.md)
- [phase-1b-7-numeric-verification](development/phase-1b-7-numeric-verification.md)
- [phase-1b-8-shift-cancellation](development/phase-1b-8-shift-cancellation.md)
- [phase-1b-9-shift-amendment](development/phase-1b-9-shift-amendment.md)
- [phase-1b-blocking-review-2026-09-27](development/phase-1b-blocking-review-2026-09-27.md)
- [phase-1b-blocking-verification](development/phase-1b-blocking-verification.md)
- [phase-1b-blocking](development/phase-1b-blocking.md)
- [phase-1b-cancellation-review-2026-09-27](development/phase-1b-cancellation-review-2026-09-27.md)
- [phase-1b-cancellation-verification](development/phase-1b-cancellation-verification.md)
- [phase-1b-cancellation](development/phase-1b-cancellation.md)
- [phase-1b-employee](development/phase-1b-employee.md)
- [phase-1b-execution-review-2026-09-27](development/phase-1b-execution-review-2026-09-27.md)
- [phase-1b-execution-verification](development/phase-1b-execution-verification.md)
- [phase-1b-execution](development/phase-1b-execution.md)
- [phase-1b-review-2026-09-27](development/phase-1b-review-2026-09-27.md)
- [phase-1b-shifts-review-2026-09-27](development/phase-1b-shifts-review-2026-09-27.md)
- [phase-1b-shifts-verification](development/phase-1b-shifts-verification.md)
- [phase-1b-shifts](development/phase-1b-shifts.md)
- [phase-1b-templates-review-2026-09-27](development/phase-1b-templates-review-2026-09-27.md)
- [phase-1b-templates-verification](development/phase-1b-templates-verification.md)
- [phase-1b-templates](development/phase-1b-templates.md)
- [phase-1b-verification](development/phase-1b-verification.md)
- [phase-2-capacity-measurement](development/phase-2-capacity-measurement.md)
- [phase-2-restore-acceptance](development/phase-2-restore-acceptance.md)
- [phase-2-update-recovery-acceptance](development/phase-2-update-recovery-acceptance.md)
- [phase-4-1-article-master](development/phase-4-1-article-master.md)
- [phase-4-2-location-assortment](development/phase-4-2-location-assortment.md)
- [phase-4-3-manual-stock](development/phase-4-3-manual-stock.md)
- [phase-4-4-local-planograms](development/phase-4-4-local-planograms.md)
- [phase-4-5-approved-operational-knowledge](development/phase-4-5-approved-operational-knowledge.md)

## Package entry points

[Server](../apps/server/README.md), [Flutter client](../apps/client_flutter/README.md),
[API contracts](../packages/api_contracts/README.md), [design system](../packages/design_system/README.md),
[reserved modules](../modules/README.md), [shared](../packages/shared/README.md),
[plugin SDK](../packages/plugin_sdk/README.md) and [plugin example](../plugins/examples/README.md).
