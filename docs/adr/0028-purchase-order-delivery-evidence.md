# ADR 0028: Purchase Order delivery evidence and immutable terminal reconciliation

Date: 2026-10-12. Decision: accepted for the user-selected P4.14 implementation.
Delivery: IMPLEMENTED LOCALLY. Independent functional review and targeted F01/F02
re-review: APPROVE; both findings CLOSED. Focused Codex Security: SECURITY APPROVE.
Final remediation verification: PASS. Implementation-commit CI and final P4.14
closure remain PENDING. P4.15 is UNSELECTED.

## Context

Managers already issue frozen purchase intent. They need attributable partial
delivery declarations, supplier follow-up and reasoned corrections without
reinterpreting ordered units or asserting physical inventory effects. Administrative
closure and subsequent evidence correction must retain distinct meanings.

## Decision

Purchasing owns four append-only tables in migration 0026: delivery revisions,
revision lines, delivery commands and terminal snapshots. Revision 1 is the stable
identity and permanently reserves its trimmed, ASCII-folded local reference within
the Order. Corrections completely replace a declaration's effective line set;
voids contribute zero. A void can be corrected. Every accepted revision advances
one contiguous Order ledger sequence independently of the existing Order version.

Only issued Orders accept new identities. Existing declarations remain correctable
after issued-order close/cancel. A fresh issued-order terminal command captures
the ledger boundary and per-line totals in its existing authorized transaction.
Later corrections retain terminal state, timestamps, version and snapshot.
Draft cancellations have no issued-delivery lifecycle. Terminal Orders predating
0026 retain no invented snapshot or declarations. No existing row or receipt is
rewritten during migration.

Exact decimal strings mean thousandths in each frozen Order unit. Positive entries
and aggregate line totals are bounded at 999999999999.999. Application validation
uses scaled BigInt intermediates; PostgreSQL recomputation uses numeric intermediates.
Remainder and overdelivery are per-line nonnegative differences. Increasing
overdelivery requires protected business reason evidence. Quantities from different
lines/units are never combined into an Order-wide physical total.

Current session, capability, configured Company/Location and exact Order/Delivery
scope precede protected receipt lookup. Existing fixed `purchasing.orders.manage`
governs reads and declarations/corrections/voids. Existing issue/cancel/close rights
remain unchanged. Managers require no Employee link. No role grants expand.

Old and new Purchasing receipts share the existing Company/operation namespace.
Supported writers acquire the Company lock and scoped Order row lock; narrow
insert guards on both receipt tables prevent cross-table collisions. Exact replay
returns the original revision and summary at acceptance before current version or
lifecycle checks. Changed bindings conflict without disclosure. Failed transactions
consume no UUID. There is no general idempotency framework or fifth receipt table.

Receipt inserts explicitly require the existing read-committed transaction mode.
After waiting for the Company lock, the guard needs a fresh statement snapshot;
repeatable-read snapshots could miss a committed receipt in the other table.
Higher-isolation raw SQL is rejected in both insertion directions rather than
weakening the namespace guarantee. Supported Platform transactions retain their mode.
The namespace guard is explicitly VOLATILE so its inner queries obtain fresh
snapshots; see PostgreSQL 17's [function snapshot semantics](https://www.postgresql.org/docs/17/xfunc-volatility.html)
and [transaction isolation](https://www.postgresql.org/docs/17/transaction-iso.html).

Composite FKs, immutable guards, positive integer quantities, contiguous revisions,
ledger uniqueness and deferred exact receipt/terminal validation reject incomplete
final transactions. Required JSON comparisons use `IS DISTINCT FROM` and lifecycle
predicates explicitly reject UNKNOWN. Runtime receives only SELECT/INSERT on new
evidence. There is no SECURITY DEFINER or new foreign-module writer.

Flutter freezes complete session-bound intent before dispatch. Uncertain commands
permit exact retry only; a later denial does not prove earlier rollback. Confirmed
results survive failed current-detail refresh, which clears actionable state.
The delivery dialog owns its controllers for the lifetime of its route. Opaque
session replacement clears resident and mounted form data and fences delayed work.

## Consequences

**Recorded delivery evidence does not mutate or establish Stock.** It is an
operator declaration of accepted goods, not independent physical receipt, quality,
supplier transmission or invoice evidence. Absence of declarations does not prove
absence of goods. Local references and operation UUIDs cannot deduplicate mistaken
human declarations of the same physical shipment.

The site remains autonomous and PostgreSQL evidence remains operator owned.
Reasons, references and quantities stay in business evidence; minimized audit
records only IDs and sequence metadata. There is no consumer requiring an outbox
event. Stock/Counts, Tasks/Shifts and Production have no effects or coupling.

Physical receiving, returns, conversions, prices, invoices, attachments, integrations,
device offline queues and multi-site synchronization require separate contracts.
Supported-writer/raw-SQL trust, memory-only client recovery, hardware/accessibility,
privacy/retention/export/offboarding, backup-key custody and RPO/RTO remain explicit
standing limits. P4.12 I01–I03 and prior qualifications are preserved.

## Alternatives

- Posting Stock during declaration would require physical provenance and reversal
  contracts that this slice does not select.
- Updating prior declarations would erase attributable evidence.
- Recomputing closure from today's corrected ledger would rewrite historical meaning.
- Backfilling legacy zero-delivery snapshots would invent evidence.
- Separate operation namespaces would allow cross-kind duplication.

See the [delivery record](../development/phase-4-14-purchase-order-deliveries.md)
and [acceptance matrix](../development/phase-4-14-acceptance.md).
