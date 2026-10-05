# ADR 0020: Task guidance pins an approved Knowledge revision

Status: Accepted implementation decision; P4.6 **DONE/CLOSED**. Original review:
CHANGES REQUIRED, F01 LOW commit blocker; bounded remediation completed, targeted
review APPROVE, 64/64 PASS, focused Codex Security SECURITY APPROVE and green
[changed-commit CI 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549).
No active remediation; [closure evidence](../development/phase-4-6-task-knowledge-guidance.md#final-documentation-closure--2026-10-05).

## Context

Employees need the exact instruction assigned when work was published, including after replacement or retirement. Current Knowledge discovery exposes an active Article's current publication. Using that pointer during Task execution would silently change assigned work evidence.

## Decision

TaskTemplate content schema 3 adds required, nullable `knowledgeGuidance`. The concrete `KnowledgeGuidance` contains only `articleId` and `revisionId`; Company scope comes from its owning Template/Task. Schemas 1/2 retain their exact fields and semantics. Migration 0018 does not rewrite persisted content, execution or receipts.

New/replacement draft selection captures an active Article's current publication. An unchanged retained pin remains editable; copying a published Template into a draft preserves it. Fresh Template and Shift publication validate exact same-Company published revision and active Article inside the authorized business transaction. A newer publication does not invalidate an older explicitly retained published revision while the Article remains active. Publication never silently upgrades a pin.

Invalid create/replacement selection returns bounded 422 `guidance_selection_unavailable`.
Only fresh Template/Shift publication of a retained unusable pin returns 422
`guidance_unavailable`. Retained-pin editing/cloning performs no fresh selection;
committed publication replay performs no availability validation and emits neither error.

Published Template and Task content retain identity immutably. Generated columns derive from source JSON. Composite foreign keys bind revision, Company, Article and published state. The Task insert guard requires correspondence with its published Template. Article activity is a supported fresh-writer rule, never a permanent retained FK requirement. The existing Company transaction lock serializes supported retirement/publication writers. The Task BEFORE-trigger guard excludes derived generated columns, which PostgreSQL computes afterward; immutable source content and all existing transition/evidence checks remain protected.

Tasks/Workforce establish Shift/Task visibility, then pass the stored Task pin into the Knowledge-owned `KnowledgeGuidancePort`. Knowledge never queries Tasks; Tasks repositories never query Knowledge. Employee contextual reads require current session, active Account/Employee link, configured execution Location, own visible published Shift/Task and Knowledge read. Managers require existing authorized Shift/Task scope and Knowledge read. Viewer/auditor roles and plugin credentials gain no access. Reads require no execution time window and preserve existing cancelled-Shift visibility.

Two contextual GET routes accept Shift and Task IDs only. Client query parameters are rejected. The safe projection returns exact revision text/identity/time and separate current superseded/retired indicators. Integrity/infrastructure failure returns a bounded server error, never current-content substitution. Standalone employee discovery remains current-publication-only; no general employee history or new general manager browsing endpoint is added.

Retirement prevents fresh publication. It is **not emergency withdrawal**: existing Tasks retain contextual access and remain executable/completable. Exact committed Template/Shift publication replay returns original evidence before fresh lifecycle validation, after current authorization, without duplicate tasks or audit.

Flutter previews exact selected revisions and requires save before publication. The plain-text Task panel returns to the same execution state. All new caches/callbacks use opaque session identity fencing, including same-account replacement. Reading produces no acknowledgment, Task mutation or readership audit. Relevant existing mutation audit records only bounded Knowledge IDs, never title/body.

## Alternatives

- Resolve the current publication during execution: rejected because it silently changes assigned evidence.
- Copy Knowledge text into Tasks: rejected because Knowledge owns immutable published content.
- Encode active Article lifecycle in retained FKs: rejected because retirement must preserve history.
- Generic/polymorphic instructions, multiple/per-step references, read receipts or completion gates: outside the single concrete consumer contract.
- Events/outbox: no asynchronous consumer exists.

## Consequences

Restores must retain both module histories and constraints. Apply migration 0018 before shipping schema-3-aware server/client binaries together. The existing single-site online contract and autonomous local-server operation remain; no device offline writes or multi-site sync are added.

## Open Questions

Emergency withdrawal/reconciliation, native-device/accessibility acceptance and offline recovery need separate contracts. P4.7 is not selected; next is fresh capability selection after the documentation closure commit.
