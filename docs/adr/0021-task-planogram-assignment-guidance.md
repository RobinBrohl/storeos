# ADR 0021: Task Planogram Assignment guidance

Status: Accepted contract; implemented locally, independent review APPROVE, security remediation complete, targeted security re-review and remote changed-commit CI pending.
Date: 2026-10-05

## Context

The selected P4.7 operator workflow attaches one exact physical deployment to a Task. ADR 0018 distinguishes immutable Planogram publication from deployment; ADR 0020 establishes independent exact Knowledge pins. A Task must keep its original deployment after a Fixture is reassigned or retired, while publication of new work must validate current eligibility. The existing Template detail supplies content and identities but has no bounded retained-layout projection; exposing general employee historical Assignment access would exceed this contract.

## Decision

Task content schema 4 adds required nullable `planogramGuidance` alongside independent nullable `knowledgeGuidance`. Schemas 1–3 retain their strict contracts and stored content. The concrete PlanogramGuidance stores exactly Fixture, Assignment and Revision IDs. Revision freezes structure; Fixture identifies the physical target; Assignment identifies the deployment occurrence. No generic guidance abstraction or copied layout, labels or Stock enters Task persistence.

Selection captures a current active configured-Location deployment. Unchanged editing/cloning retains it. Fresh Template and Shift publication validates the complete tuple, current Assignment, active Fixture/Planogram and Article/Assortment eligibility in the Company transaction. Publishing another revision without assigning it leaves the deployment valid. Reassigning away and back does not revive an older Assignment. Publication never upgrades a pin.

Merchandising owns PlanogramGuidancePort. Tasks owns selection/snapshots; Workforce coordinates authorized Shift publication. Callers authorize stored Task or Template context before passing the stored pin. Repositories never access foreign module tables. Historical reads retain exact layout structure after reassignment or terminal Fixture/Planogram retirement. Retirement blocks fresh work and is not emergency withdrawal; existing blocking/resolution handles impossible work.

Generated JSON-derived columns and a durable composite Assignment FK protect Company, Location, Fixture and Revision identity. Current/active status is never a permanent FK condition. Task/Template correspondence and immutable content remain guarded. Existing restricted runtime privileges remain sufficient.

Retained-layout responses separate immutable identities/structure from explicitly current Fixture descriptors, Article labels/status, optional Stock, lifecycle indicators and query time. Stock failure uses the existing optional-context contract and never substitutes current structure. No historical label claim is made.

Employee reads require current session, active Employee link, configured Location, own visible Shift/Task, Task self-read and merchandising.layouts.read. Manager and Template reads require existing scoped permissions plus merchandising.layouts.read. No new capability or general employee history browser exists. Exact publication replay follows current authorization and precedes fresh availability validation; pristine amendment preserves pins.

Every Planogram work Location must explicitly equal the currently configured execution Location as well as the actor's Location, within the configured Company. The Merchandising port enforces this before fresh validation, stored layout resolution or live enrichment. Retained edit/clone and committed publication replay use the same scope check without revalidating lifecycle. Cross-Location work returns canonical `403 forbidden`; a same-Company Location registry entry alone is insufficient. Runtime configuration is not encoded in durable Assignment integrity.

Opening Assigned layout is read-only: no acknowledgment, audit, receipt, event, step confirmation or completion gate. Mutation audit stores bounded identities only. Flutter uses literal text and opaque session fencing for selectors, previews and Task panels. Knowledge remains independent.

## Alternatives

- A Revision-only pin loses the physical target and deployment occurrence. A Fixture-only pin silently changes instruction when its current Assignment changes. An Assignment-only contract hides the explicit target/revision correspondence the Task contract requires.
- Copying layout and live labels into Tasks duplicates Merchandising/Inventory ownership and misrepresents enrichment as frozen evidence.
- A generic polymorphic reference list adds unsupported capabilities and obscures the distinct Knowledge and deployment lifecycle rules.
- Permanent current/active foreign keys would prevent legitimate retirement and erase historical evidence. Durable identity FKs plus transactional fresh-work validation preserve both rules.
- Extending standalone employee history or returning full layouts in every Template/Task detail would widen access or couple unrelated reads. Three contextual reads authorize stored work first. A bounded current guidance-selection read is necessary because the existing current-layout response does not expose Planogram lifecycle eligibility; it requires Template management and Merchandising read, accepts no historical selectors and leaves standalone rules intact.

## Consequences

Apply migration 0019 before deploying schema-4-aware server/client binaries together. Backup/update/recovery must preserve historical deployments and execution evidence. No Stock writes, print extensions, recurrence, offline queue, multi-site rollout or emergency withdrawal is included.

## Open Questions

No unresolved implementation decision remains within this slice. Independent normal review APPROVE followed the F01/F02 remediation. Codex Security subsequently required bounded Security F01 remediation for omitted configured work Location scope; targeted security re-review and changed-commit remote CI remain pending. Emergency withdrawal, offline writes, multi-site synchronization, rollout acknowledgment and physical device/accessibility acceptance require separate contracts or acceptance.
