# ADR 0029 — Explicit Article quantity semantics and manual targets

Status: Accepted for bounded P4.15 implementation; targeted functional APPROVE and
SECURITY APPROVE reported by the user on 2026-10-13. Publication/remote CI pending.
Date: 2026-10-12.

## Decision

Inventory owns one immutable dimension/base-unit anchor per Article, immutable
full packaging revisions and a terminal reasoned suspension. Only mass (`g`,
`kg`), volume (`mL`, `L`) and count (`piece`) are supported. Packages refer
directly to a positive decimal amount in the same anchor, never another package.
Labels, Article metadata and old records are not semantic declarations.

Stock owns a prospective immutable explicit binding of one frozen Stock unit to
that anchor, without reinterpreting history or rebasing balances. A package binding
freezes its original content even when later package revisions change. Input
packages always use the exact current revision. Measurement ratios are fixed;
Article-specific contents are Inventory facts supplied through a narrow public
read port in the same authorized transaction.

Decimal wire strings and reduced BigInt rationals avoid floating-point and Web
integer overflow in intermediate multiplication. Final targets must fit existing
bounded Stock thousandths exactly. Preview is read-only; a reviewed absolute-target
command recomputes and compares all evidence under optimistic Stock/profile checks.
Stock-specific append-only receipts consume even zero corrections and return the
original committed result on exact authorized replay. Existing adjustment kinds
and old contracts remain intact; typed conversion evidence is separate and immutable.
Relevant audit is atomic and contains identifiers/versions rather than copied
quantities, packaging contents or reasons. No concrete event consumer exists.

## Consequences and alternatives

No new package or universal units framework is needed. Migration 0027 adds
Inventory profiles/revisions/receipts and Stock bindings/conversion receipts,
with composite scope keys, append-only guards and deferred final-state checks.
Old tables, IDs, quantities, versions, snapshots and receipts keep their meaning.
New quantity APIs require current session/Company capability and Stock execution
Location equality. Flutter pending tracking remains memory-only and session fenced.

Inferring meaning from `kg`, `carton` or `bottle` labels was rejected. Updating
Stock's frozen unit or converting historical balances was rejected. Rounding a
nonrepresentable target was rejected. A separate ledger kind duplicating the
existing manual adjustment behavior was rejected. Long-lived review locks and
generic command engines were rejected as unnecessary.

Terminal suspension is intentionally conservative: wrong anchors/bindings cannot
be silently repaired in place. Legacy manual workflows remain available; future
anchor replacement/rebinding needs a distinct, reviewed migration/remediation
contract. This bounded decision does not narrow the long-term product vision.

See the [P4.15 contract](../development/phase-4-15-article-quantities.md),
[ADR 0017](0017-manual-stock-foundation.md) and
[module boundaries](../architecture/module-boundaries.md).
