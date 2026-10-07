# Production: approved Article composition

P4.10 adds location-scoped PreparationBatch evidence under [ADR 0024](../adr/0024-preparation-batch-evidence.md).
It is **DONE/CLOSED**: F01–F03 CLOSED, targeted APPROVE, 156 PASS / 0 QUALIFIED /
0 FAIL, focused SECURITY APPROVE and all five jobs green in
[exact-commit CI 37632074236](https://github.com/RobinBrohl/storeos/actions/runs/37632074236). Production owns batches, immutable receipts and append-only
count corrections. Identity, People and Organization public ports derive the
current eligible operator and configured Location; Inventory's released Article
and effective Assortment projections supply fresh opening gates under the Company
writer lock. Existing batches retain exact published Recipe instructions after
replacement/retirement. No Stock, Task, Shift or outbox effect is introduced.

P4.9 is **DONE/CLOSED**: F01–F05 remediation complete, targeted independent
APPROVE, 151 PASS / 1 QUALIFIED / 0 FAIL, focused SECURITY APPROVE and green
[exact-commit CI 37581798736](https://github.com/RobinBrohl/storeos/actions/runs/37581798736).
Criterion 152 is qualified only for historical evidence scope; no active remediation
remains. [ADR 0023](../adr/0023-approved-article-recipe-composition.md)
owns the complete architecture/product contract.

`apps/server/lib/src/production` owns Recipe lifecycle, repository and application
service. `inventory/recipe_article_port.dart` owns the released Company Article
context read. Recipe routes authenticate through existing platform authorization.
Transactions share the Company writer lock with Article lifecycle changes.
`packages/api_contracts/lib/src/recipes.dart` defines strict request/response
projections, exact quantities and decoded-content bounds. The public OpenAPI
index includes all thirteen operations with operation-specific `x-error-codes`.
Recipe writes use a bounded duplicate-name lexical check before canonical JSON
decoding; unrelated APIs retain their existing read path.

Three tables retain separate Recipe, revision and ordered ingredient identities.
A publication replaces the current pointer only after validating the entire saved
composition. History retains prior publication, discarded drafts and publication
operation evidence. Exact historical reads include separately labeled live Article
context. The employee projection resolves only the current visible publication.
No Recipe business read uses Article/Stock base tables or foreign repositories;
the released Inventory view is the explicit cross-module contract.

Flutter `RecipeController` handles saved vs dirty composition, immutable pending
requests, uncertain exact publication retry, reload/review for other uncertain
mutations, confirmed-but-refresh-failed outcomes and opaque session fencing.
`RecipeSection` provides manager authoring/history and employee literal reads.
The employee work shortcut is navigation only; it creates no Task or read evidence.

Retirement and deactivation have different durable meanings: Recipe retirement is
terminal; produced Article reactivation restores visibility only while Recipe is
active. Inactive ingredient Articles remain in current approved content with a
current warning and block fresh publication. Frozen/current unit mismatch requires
explicit reselection and quantity review; no conversion occurs.

The normal database is never an acceptance target. The remediation record claims
that it is untouched by the verified current run; historical implementation actions
without before/after evidence cannot be reconstructed (accepted F07 limitation). Run-owned PostgreSQL databases
exercise migration, rollback, runtime grants, publication faults/races, backup and
recovery. See the [development record](../development/phase-4-9-recipe-compositions.md)
for review surfaces and verification commands.
