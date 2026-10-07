# ADR 0024 — Location-scoped preparation batch evidence

Status: Accepted; P4.10 **DONE/CLOSED**. F01/F02 remediation and nonblocking F03
documentation follow-up are CLOSED; targeted review APPROVE, focused SECURITY
APPROVE and all five jobs green in [exact-commit CI 37632074236](https://github.com/RobinBrohl/storeos/actions/runs/37632074236)
establish delivery closure. The architectural decision is unchanged.

## Context

Production owns PreparationBatch, PreparationBatchCommand and
PreparationBatchCountCorrection alongside Recipe. A batch binds one configured
Location, current executing Employee and exact published RecipeRevision. It records
an attributable operator declaration of whole repetitions of that revision's
declared Recipe batch. It defines no yield, output quantity/unit or Stock effect.

## Decision

Fresh opening validates current Employee assignment/linkage, configured Location,
active Recipe, exact current publication, active produced/ingredient Articles,
effective local Assortment and unchanged ingredient units inside runAuthorized's
Company transaction. Organization, People, Identity and Inventory public ports
supply their own current context. Production reads only its own repositories.

Opening freezes identity, server time and optional planned count (1..9999).
Completion (1..9999) and reasoned cancellation are mutually exclusive terminal
transitions from open version 1 to version 2. Managers may cancel abandoned open
work, never proxy-complete. Original terminal evidence is immutable.

Manager corrections append contiguous numbered rows, previous effective count,
replacement (0..9999), actor, server time, reason and command identity. They leave
the terminal version and original completion unchanged. Zero means the reported
completion was corrected to zero, not physical production or cancellation.

Company + operation UUID namespaces durable command receipts. Current session,
capability, configured Location and accessible resource scope precede receipt
lookup; exact replay returns original evidence before fresh lifecycle/version and
Recipe gates. Failure creates no receipt. Commands, receipts and bounded audit
commit atomically; no events/outbox consumer exists.

Historical Recipe instructions additionally require production.recipes.read and
authorized batch access before resolving the persisted pin. Replacement,
retirement, Article/Assortment deactivation and unit changes never rewrite frozen
approved content. Current warnings are separate. Retirement blocks fresh work,
not completion of already-open work by a currently eligible operator.

Migration 0022 adds only the three Production tables, constraints, immutable guards
and indexes. Runtime has SELECT/INSERT and narrow open-to-terminal column updates;
no deletion, truncate, receipt/correction update or SECURITY DEFINER. Supported
application commands remain the business authorization boundary.

Flutter fences resident/pending state by opaque session identity, renders text
literally and retains exact immutable commands for uncertain retry. Memory-only
tracking does not provide offline durability. Tasks schemas 1–4, Shift, Workforce,
Stock and Stock Count evidence remain unchanged. No P4.11 scope is selected.

## Alternatives

Stock-producing execution, ingredient consumption, Task Recipe pins and offline
command queues are excluded because each requires a separate domain contract.
Rewriting completion after managerial review would destroy the original
declaration; numbered append-only corrections preserve both claims. General
historical Recipe browsing would widen employee authority; a batch-derived
context preserves access only after current authorization. Separate independent
locks would allow incoherent opening checks; the existing Company writer lock
provides one supported serialization boundary.

## Consequences

Completion is evidence of an operator declaration, never physical Stock evidence.
Historical instructions survive retirement, which is not emergency withdrawal.
Current employee eligibility can revoke self access to frozen historical evidence;
authorized manager history remains available. Uncertain retries survive server
restart through receipts, while client pending state remains memory-only.

## Open questions

No architectural choice or delivery gate remains open within this closed slice.
Review, security and exact-commit CI evidence are recorded in the
[P4.10 closure](../development/phase-4-10-preparation-batches.md#final-documentation-closure--2026-10-07).
Retention/operator/device policies and future yield, Stock, Task, offline or sync
capabilities retain their separate decision processes.
