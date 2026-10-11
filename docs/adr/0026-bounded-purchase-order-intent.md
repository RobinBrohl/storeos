# ADR 0026: Bounded purchase order intent and durable snapshots

Date: 2026-10-11. Decision: Accepted. P4.12 implementation is DONE/CLOSED: F01 CLOSED, targeted independent APPROVE, focused SECURITY APPROVE and successful implementation-commit CI 38152045998. Documentation closure publication and its own exact-head CI remain pending. See [closure evidence](../development/phase-4-12-bounded-purchase-orders.md#final-documentation-closure--2026-10-11).

## Context

Operators need attributable purchase intent before manually communicating it to a supplier. Existing Article identity and local Assortment belong to Inventory. Stock is physical evidence; Recipe/PreparationBatch declarations and Shift/Task execution have separate contracts. Receiving, prices, contacts, packs, conversion and transmission are unselected.

## Decision

Purchasing owns four tables: Suppliers, Location PurchaseOrders, ordered lines and one Company/operation command namespace. A Supplier has only a name and nullable opaque ordering reference. It can be edited while active and retired permanently. Drafts can be replaced in full, issued internally, cancelled or closed administratively after issue. Issued/cancelled content and terminal evidence remain immutable.

Snapshots retain Supplier id/version/name/reference and Article id/version/SKU/name/unit. Inventory's narrow `PurchasingArticlePort` owns all catalog SQL. New or changed selections require an explicit reselection flag and the current expected version. Retained draft selections preserve saved snapshots. Issue validates the exact saved draft against current active Supplier, active Article and effective local Assortment; a changed unit receives the specific unit conflict. It never refreshes content implicitly.

Quantity is an exact positive decimal string in the existing Article unit, represented as bounded integer thousandths. No arithmetic total, rounding or conversion is introduced. Drafts have 0–50 distinct ordered Article lines; issue requires 1–50. The decoded UTF-8 document sum is bounded at 98,304 bytes and is calculated identically in Dart and PostgreSQL.

Current Company, Account role/capabilities and configured execution Location precede receipt disclosure. Admin alone has the three Purchasing capabilities. Every order route requires route Location = configured server Location = current Account Location; Supplier management is Company scoped and needs no Employee link. Create/save/issue also require Supplier management authority.

The existing Company transaction lock serializes supported writers and rechecks current authority. Each of eight commands binds operation UUID, kind, actor, concrete target, Location where applicable, expected version and canonical intent to its original accepted result. Authorization/resource checks precede exact receipt replay; replay precedes lifecycle/catalog checks. Failed transactions consume no UUID. Receipts, business effects and minimized audit commit together; Purchasing emits no events.

Migration 0024 adds one Account Company attribution anchor and the four tables. Composite FKs, bounded fields, lifecycle guards, parent locks, deferred collection/document/receipt checks and column-level grants protect durable structure. Runtime SQL cannot delete aggregates, mutate lines in place, mutate receipts or truncate Purchasing tables. This does not grant arbitrary raw SQL the application's current catalog validation or actor intent: the established supported-writer boundary remains explicit.

The Flutter workspace retains uncertain commands only in memory, with a deeply frozen route/body/session identity. Only an exact retry is available while uncertain. Confirmed historical evidence remains separate from fresh actionable detail. Same-account and different-account opaque session replacement clear resident and mounted form/dialog state immediately and fence delayed dispatch/results.

## Consequences

Local site operation and operator-owned PostgreSQL evidence remain autonomous. Retired references and historical snapshots survive indefinitely; order references stay reserved across terminal states using deterministic ASCII-only case folding. There is no automatic supplier communication or Stock effect. Device offline writes, multi-site synchronization, receiving, costs and richer Supplier management require separately selected contracts. The three implementation review/CI gates are complete; final documentation closure publication still requires its own successful exact-head CI.

## Alternatives

- Model purchase intent in Stock: rejected because Stock records physical evidence and would conflate order approval with receipt.
- Resolve names and units live at display time: rejected because accepted evidence must retain the exact reviewed document after catalog edits.
- Keep independent per-command operation namespaces: rejected because the selected Company-wide namespace must detect cross-kind and cross-target collisions.
- Add durable client retry storage: deferred to a separate offline-write contract; this slice uses session-bound in-memory recovery.

## Open questions and gates

Independent review, subsequent focused Codex Security and exact implementation-commit remote CI are complete. Nonblocking Security INFO I01–I03 concern SQL NULL/UNKNOWN evidence checks; the current constraints are not hardened. See [traceability and future migration trigger](../development/technical-debt.md#p412-security-info-observations). Any hardening requires an authorized new migration and regression evidence; it does not allocate P4.13. Documentation closure commit/CI remain pending publication. Receiving, Supplier contacts, costs, pack conversion, transmission, offline writes and multi-site synchronization are not selected decisions of this ADR.
