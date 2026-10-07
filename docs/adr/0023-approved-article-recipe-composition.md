# ADR 0023 — Approved Article Recipe / Composition

Status: Accepted product/architecture contract; implemented locally, independent review remediation complete;
targeted review, security review and remote changed-commit CI pending. P4.9 is not DONE/CLOSED.

## Context

Operators need an approved, Article-linked composition and preparation instruction.
Inventory already owns Company Article identity. Stock owns physical evidence; Tasks
own execution evidence. The selected P4.9 contract is composition only.

## Decision

Production owns a separate Recipe UUID, unique per Company/produced Article, with
stable revision UUIDs and strictly increasing revision numbers. There is one active
draft. A draft becomes published or discarded; both terminal states and their
ingredient rows are immutable. Retirement is terminal and atomically discards a
draft. Recipe identity and all history remain retained. An active Recipe with no draft
copies its current publication into the next draft when one exists. Without a
publication (including after initial discard), the same command creates an empty
draft with the current active produced Article snapshot. The discarded number is
consumed; manage authorization, expected version and Company serialization apply.

Each composition describes ingredients for **one declared Recipe batch**. Batch
text is an operator label, not a structured output quantity or yield. Employee UI
states this basis explicitly. Quantities are positive exact integer thousandths,
transferred as decimal strings; range 0.001–999999999999.999. No floating-point
parsing, yield calculation, recursive expansion or unit conversion is performed.
An ingredient Article with its own Recipe is still one ordinary ingredient.

Revisions freeze the produced Article SKU/name/unit and each ingredient's
Article ID/SKU/name/unit. New references and explicit reselection require an active
Company Article. A normal save and replacement draft preserve frozen references.
Explicit reselection captures current labels/unit; the operator reviews quantity
in that unit. Metadata changes never rewrite approved evidence. Current context
is separately labeled, including inactive ingredients and unit differences.
Fresh publication requires active produced/ingredient Articles and exact equality
of frozen/current ingredient units; mismatch is `ingredient_unit_changed` with
zero publication effects. Existing approved inactive ingredients remain readable.

Employee discovery/read resolves only the current publication of an active Recipe
with an active produced Article. Filtering precedes bounded pagination. Current
or frozen approved produced labels support literal search; drafts/history never
enter discovery. Company-wide reads require no Location assortment. Management
history and exact revision reads remain available after retirement. Employee DTOs
contain no draft/history/operation/actor/aggregate version information.

Fresh publication atomically changes the exact saved revision, current pointer,
active draft pointer, aggregate version and one bounded audit. Exact publication
replay binds Company, Recipe, revision, actor, operation UUID and expected version.
Current authentication/Company/capability checks precede replay. Original evidence
is returned after newer publication, Article deactivation or Recipe retirement,
without writes, duplicate audit, pointer movement or reactivation. Operation UUIDs use a Company-scoped namespace: within the authorized Company,
a different Recipe/revision/actor/expected version conflicts; independent Companies
may use the same UUID. Foreign resources remain inaccessible before receipt lookup.
Other uncertain
mutations require reload/review rather than publication-style replay.

All business commands use existing Company transaction serialization, shared with
Article writers. Domain/Application owns lifecycle decisions; routes/widgets
only transport or present them. Inventory releases the narrow Company Article
context view/port. Production does not read foreign repositories or write Stock,
Task, readership, event or outbox records. There is no Recipe Task pin.

Fixed capabilities are `production.recipes.read/manage/publish`. Admin receives
all three; employee receives read; viewer/auditor/plugin receive none. Recipe
capabilities grant no Article management or Stock access. Configurable roles are
outside this slice. Session replacement clears controller and mounted editor,
query, picker, history, pending and confirmed evidence; delayed responses use an
opaque session identity fence.

Migration 0021 adds three Production tables and the Inventory-owned read view.
Same-Company FKs, pointer ownership/state FKs, uniqueness, exact quantities,
contiguous ordering, composition bounds and terminal guards protect durable
invariants. Grants allow SELECT/INSERT, narrow aggregate/revision column updates
and draft ingredient replacement DELETE guarded by parent state; no ingredient
UPDATE, aggregate/revision DELETE, or TRUNCATE. No SECURITY DEFINER is added.
The supported writer is the authorized application under these grants; privileged
owners and arbitrary SQL clients are not a substitute for business authorization.

### Bounds and canonical bytes

Batch text is at most 120 Unicode code points with no ASCII control characters.
Preparation is at most 8192 UTF-8 bytes after CRLF/CR→LF normalization. NUL and
unpaired surrogates are rejected. There are at most 50 distinct ingredient
Articles and stable line IDs, with positions 1..N. The canonical 32768-byte bound
sums UTF-8 bytes of decoded batch/preparation, produced ID/SKU/name/unit, then
for each ordered line: line ID, decimal position, Article ID/SKU/name/unit and
quantity formatted with exactly three fractional digits. UUIDs are lowercase.
JSON framing/escaping and timestamps are excluded; SQL implements the same sum.
The independent HTTP body limit is 262144 bytes. Unknown/authoritative snapshot
write fields are rejected. Recipe writes reject duplicate decoded JSON object member
names as `invalid_json`, including equivalent Unicode escapes and nested objects.
The strict reader remains bounded by the existing streamed transport limit. Pages contain at most 50 entries; cursors bind Company,
endpoint/Recipe and literal query and are bounded to 2048 characters.

## Alternatives

Embedding Recipe in Article would combine distinct lifecycle/ownership. Automatic
unit refresh would silently change the meaning of an unchanged quantity. A yield,
recursive production graph, Stock consumption or Task pin would require separate
contracts. Those alternatives were not selected.

## Consequences

Operators retain approved evidence while preparing replacements. Renames and unit
changes are explicit current warnings, never silent content updates. Publication
can be recovered after a lost response and server restart. Backup verification
compares all Recipe rows and probes restored reads/replay/authorization under
runtime-role fencing. Update acceptance includes the new migration and protected
legacy evidence. Independent/security/changed-commit review remains outstanding.

## Open Questions

Yield, production runs, costing, consumption, conversions, allergens, nutrition,
HACCP, offline writes, synchronization and new Task guidance need separately
selected contracts. No next capability is selected by this ADR.
