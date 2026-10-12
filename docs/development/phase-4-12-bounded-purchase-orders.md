# P4.12: Bounded purchase orders with minimal Supplier identity

Historical P4.12 documentation-closure snapshot (2026-10-11): the gate/selection
statements below describe that drafting state. Closure was subsequently published
at d48856f8 with successful CI 38156014870. P4.13 is now DONE/CLOSED — accepted
implementation; its documentation publication/closure-commit CI remains PENDING.
P4.14 UNSELECTED. See [current P4.13 closure](phase-4-13-planned-preparation-assignments.md#final-documentation-closure--2026-10-12)
and [actual status](../roadmap/status.md).

Historical selection/implementation baseline (before review and commit): selected MEDIUM capability, 2026-10-11. Baseline: clean `main` at `604d1d198b158b1907dd000ea435d94dbae0dec1`, matching cached and live origin; exact baseline CI 38126471288 succeeded in all five jobs. P4.1–P4.11 remain DONE/CLOSED. At that implementation handoff, work was unstaged/uncommitted on `main`; P4.13 was and remains UNSELECTED.

Current state: **P4.12 DONE/CLOSED (accepted implementation)** at `f9122f21cde5149685059a184114b6d958a2bd32` (`Add bounded purchase orders`). F01 is **CLOSED**, targeted independent re-review **APPROVE**, focused Codex Security **SECURITY APPROVE**, and exact implementation-commit [CI 38152045998](https://github.com/RobinBrohl/storeos/actions/runs/38152045998) **COMPLETE / SUCCESS**. Current accepted matrix: **93 PASS / 3 QUALIFIED / 0 FAIL**. The documentation-only closure commit and its own exact-head remote CI remain **PENDING PUBLICATION**; no closure SHA, CI run or outcome is claimed. **P4.13 remains UNSELECTED**.

## Independent finding F01 and bounded remediation

The initial implementation self-assessment was **90 PASS / 6 QUALIFIED / 0 FAIL**. Independent adversarial review returned **CHANGES REQUIRED: 89 PASS / 6 QUALIFIED / 1 FAIL**. F01 was a **LOW PRODUCT DEFECT / COMMIT BLOCKER** and is now **CLOSED**, affecting criterion 36 (exact canonical replay). These are separate historical assessments. Local remediation did not approve itself; the subsequent targeted independent APPROVE is recorded in the closure below.

F01 was reproduced before changing the service, using actual production HTTP routes, `PurchasingService`, durable PostgreSQL receipts and the restricted runtime role in a disposable database. A configured Location containing hexadecimal letters accepted uppercase and mixed-case create/save/issue/close/cancel commands, then rejected identical retries with `409 operation_conflict`. Lowercase-to-uppercase replay also failed. The pre-fix focused run retained in `.local/p412/f01/pre-fix-focused.log` had 26 contract/OpenAPI passes and 63 database passes / 18 failures: all 61 existing database cases and two new denial cases passed; 18 new replay cases failed.

The root cause was that `_run` parsed the Location for authorization comparison but passed the original route string onward. Receipt matching compared PostgreSQL's lowercase UUID string with that raw spelling. The bounded fix parses once with the existing `purchasingId` utility inside the authorized transaction and passes that validated canonical Location to the command/query callback. Configured-Location authorization, resource scope, receipt equality, document construction, audit attribution and scoped query/cursor context now share the same identity. Current authentication/capabilities still precede scope and resource checks, which precede receipt lookup; replay still precedes fresh lifecycle/catalog validation. Different Locations remain forbidden before receipt disclosure. Supplier commands retain null Location and their Company namespace. No arbitrary content, pending client command, stored receipt, migration or dependency is rewritten.

[Twenty deterministic F01 cases](../../apps/server/test/purchasing_uuid_replay_cases.dart) cover every Order kind with uppercase, mixed-case and lowercase initial routes, identical retry and all cross-spelling retries. They assert original HTTP status/result and replay flag, canonical persisted Location, receipt/audit counts, unchanged versions, frozen lines and persisted evidence hashes. Create/save/issue replay after close and cancel survives server restart, retired Supplier and inactive Article without catalog revalidation or new effects. Conflicts cover actor, kind, target, expected version and canonical payload; actual foreign Location, missing/revoked authentication and failed Create UUID reuse are checked separately with no result/payload disclosure. Existing cases freshly cover cross-Company denial and all eight Supplier/Order receipts.

Flutter review found no additional change necessary: configured routing derives from session identity, and uncertain commands retain their deeply frozen dispatched route/body/session. Exact retry, session replacement and confirmed historical result/current detail separation remain protected by the existing controller/widget tests and real controller/Chrome journeys. No client workaround was introduced.

Migration 0024 remains byte-identical to the implementation baseline: SHA-256 `41f7dfc231157691db46691ee8e7e6ad0376b0fc2afb8f5c2d7f5c50ea00c2db`. The original final run (1,241 package tests, 16 phases, 13 journeys) is historical, preserved under `.local/p412/pre-f01/final/`; it is not remediation evidence. The complete post-F01 final-source run passed with 1,261 package tests and 16/16 phases in `.local/p412/final/summary.json` and the source manifests. Focused pre/post-fix and Flutter logs remain under `.local/p412/f01/`. The remediated assessment and independent targeted approval each returned **90 PASS / 6 QUALIFIED / 0 FAIL** before the subsequent Security/CI gates resolved criteria 91–93. These ignored handoff files describe their historical pre-approval/pre-commit state; they are not current gate status.

## Contract and implementation

[ADR 0026](../adr/0026-bounded-purchase-order-intent.md) records ownership, immutable snapshots and durable replay. Server Domain/Application/Repository live under `apps/server/lib/src/purchasing/`; the Inventory-owned port is `inventory/purchasing_article_port.dart`. Widgets and HTTP routes present validated intents; they do not make domain decisions. No foreign repository, Stock write, personnel decision, event or outbox write is introduced.

The Supplier lifecycle is active → retired, with edit only while active. Orders are draft → issued → closed/cancelled, or draft → cancelled. Terminal states cannot reopen. Whole draft replacement retains stable line IDs and contiguous order; lines are distinct by Article, 0–50 for drafts and 1–50 for issue. Reference reservation persists Company/Location-wide across every state using ASCII-only folding.

Supplier snapshots contain id/version/name/nullable ordering reference. Article snapshots contain id/version/SKU/name/unit. Retained selections remain frozen; new/changed selections require explicit reselection. Issue checks the saved Supplier version and current active Article version/unit/Assortment. The conflict response preserves saved content and quantities, requiring review and explicit reselection/save. Quantities are positive exact strings through `999999999999.999`; output has three fractional digits. No packs, conversion, prices, tax, totals, delivery dates, contacts, supplier SKU mapping, transmission or receipt workflow exists.

The API has 15 operations under `/api/v1/platform/purchasing`, with strict write fields, decoded duplicate-name rejection, exact query allowlists and bounded keyset cursors. Responses/errors are documented per operation in the OpenAPI index and JSON component file. Limits: Supplier/lifecycle bodies 16,384 bytes; complete draft save 262,144; decoded document 98,304; SQL receipt payload/result 262,144/524,288; pages 50; cursor 2,048 characters. Unicode limits count code points and reject C0/C1 controls and unpaired surrogates. The SQL document bound is independently checked against Dart using maximum valid 50-line Unicode evidence.

Authorization is server-side and Admin only: `purchasing.suppliers.manage`, `purchasing.orders.manage`, `purchasing.orders.issue`. Supplier scope is Company. Order routes require route = configured = current Account Location, including history and replay. Create/save/issue require Supplier capability too. Employee, Viewer, Auditor and Plugin tokens cannot use Purchasing. No Employee account link is required.

One receipt namespace covers Supplier create/edit/retire and Order create/save/issue/cancel/close. Exact canonical intents return original accepted evidence after restart and after catalog retirement/terminal state, without new business/audit effects. Binding collisions return `operation_conflict`; failed/no-change transactions create no receipt. Audit contains eight bounded actions and identifiers/versions/changed-field names only, excluding names, references, quantity, unit labels and reasons. Unexpected integrity failures are sanitized.

Migration `0024_bounded_purchase_orders.sql` appends to unchanged 0001–0023. It adds four tables, the narrow Account Company anchor, composite scope/actor FKs, unique references/Article/line/position, quantity/version/text bounds, immutable lifecycle/receipt guards, locked draft line replacement and deferred final-state/receipt conservation. Runtime grants are SELECT/INSERT plus narrow aggregate columns and draft-line DELETE; no aggregate DELETE/TRUNCATE, line UPDATE or receipt mutation. No SECURITY DEFINER is added.

Flutter exposes one manager workspace: lists/status/Supplier filters, minimal Supplier lifecycle/history, draft creation, local Article picker, line editing/reordering/removal, exact quantities/unit labels, authoritative saved preview/review, issue, terminal reason dialog, outstanding/terminal history and literal copyable text. Pending commands are deeply frozen in memory; only exact retry remains actionable. Confirmed result and current detail are distinct. A failed refresh clears actionable detail. Opaque session replacement clears controllers, mounted fields/dialogs, pickers/cursors, confirmations/errors and pending commands and fences delayed results.

## Verification and reproducibility

Use the pinned Flutter 3.47.5 / Dart 3.13.4 installation. `scripts/purchasing/Run-P412Checks.ps1` starts a uniquely named disposable Compose project on loopback 55432 and always removes only that project's resources. The pre-existing normal StoreOS app/proxy/database containers remain running and unchanged. Secret files are read internally; connection strings and test credentials are excluded from retained public reports.

Modes `focused`, `journey`, `browser`, `hosts`, `migration`, `backup`, `update`, `numeric` and `regression` cover focused contracts/database checks; real controller and Chrome paths; every established opt-in journey; actual populated 0023→0024 plus late structural/grant rollback and encrypted pre-0024 fenced recovery; encrypted current-state backup; legacy 0010→0024 recovery/smoke; numeric browser stages; and all package tests/analyzers/formatters/Web/Compose checks. Run database modes sequentially because they share the disposable loopback port.

The real journey seeds nonempty Stock/count, Preparation/correction, Task/guidance and approved Shift-transfer/lineage evidence through production APIs. It orders two local Articles in quantities 2.5 and 12, rejects a changed unit with no side effects, explicitly reselects/saves, loses a committed issue response, restarts and exactly retries, changes catalog labels/Supplier identity, retires Supplier, closes with a reason and replays the original issue again. Restricted PostgreSQL hashes prove legacy evidence unchanged; Employee and wrong-Location Admin are denied. Chrome checks literal text and no content-driven script or external requests.

Backup fixtures include two Suppliers, six Orders spanning empty/populated draft, outstanding issued, closed, issued-cancelled and draft-cancelled, four saved lines and 20 immutable receipts covering all eight kinds. Historical Supplier snapshots predate edit/retirement and all four Article snapshots predate a production-API catalog label/version change. Existing P4.11/P4.10/Stock/count/guidance fixtures remain nonempty. Restore compares exact identities/content/attribution/hashes, fresh current authorization, historical replay, role/Location denial and grants while retaining session/plugin and runtime CONNECT fencing. The dedicated populated 0023 recovery independently verifies absence of Purchasing and its Account anchor after restoring the encrypted pre-update point.

Final-source evidence is produced by `Run-P412FinalVerification.ps1` under ignored `.local/p412/final/`: source manifests contain SHA-256, length and modification timestamps for every tracked/nonignored source/document; each phase verifies unchanged contents/timestamps. `summary.json` references sanitized logs and exact package/host counts. A failed/omitted phase does not count as PASS. The numbered [acceptance matrix](phase-4-12-acceptance.md) maps the requirement groups to code/tests and distinguishes historical local verification from completed implementation gates and pending documentation publication.

## Historical review handoff and standing debt

The implementation handoff requested that independent review inspect Company-wide Supplier versus configured local Order authority, explicit selection, snapshot immutability, receipt disclosure/binding, strict transport/cursors, database grants/deferred integrity, session replacement and restored authorization. At that handoff, focused Codex Security was to follow independent review and was deliberately not run during implementation; remote changed-commit CI awaited an authorized commit/push. Those implementation gates subsequently completed, as recorded below. This documentation closure pass performs no staging, commit, push, PR or branch change.

Preserve M1's proxy/login-limiter pilot gate, M2 CLOSED, M3's endpoint-local containment, M4's broader taxonomy, the supported-writer/raw-SQL boundary, memory-only uncertain tracking, physical-device/accessibility gaps, P4.5 F01/F02 and P4.9's historical-evidence qualification. These are not closed by P4.12. Issuing is internal approval; administrative closure proves neither delivery nor receipt. Personnel decisions remain with people.

## Final documentation closure — 2026-10-11

### Baseline and implementation publication

This docs-only reconciliation dynamically verified clean `main` at implementation
commit `f9122f21cde5149685059a184114b6d958a2bd32`, subject `Add bounded purchase orders`,
equal to cached and live `origin/main`, with an empty index/stash and exactly one
worktree. Git's live remote command failed with a resolver/thread error; the
read-only GitHub connector verified live `main` instead. P4.1–P4.11 remain
DONE/CLOSED; P4.13 remains UNSELECTED. Implementation changed 70 paths; historical
migrations 0001–0023 and dependency/lockfiles were unchanged from its parent.

Exact implementation-commit [CI run 38152045998](https://github.com/RobinBrohl/storeos/actions/runs/38152045998)
was dynamically verified **completed / success** for that full SHA, with all five
jobs **completed / success**: `dart`, `flutter`, `numeric-guided-work-e2e`,
`backup-restore-acceptance`, `update-recovery-acceptance`. This is P4.12 implementation
CI, distinct from the earlier P4.11 closure baseline and from the future docs CI.

### Review chronology and F01 closure

| Stage | Decision / acceptance | Evidence |
| --- | --- | --- |
| Initial implementation | 90 PASS / 6 QUALIFIED / 0 FAIL | 1,241 package tests; historical pre-F01 evidence only. |
| Independent adversarial review | CHANGES REQUIRED; 89 PASS / 6 QUALIFIED / 1 FAIL | F01, LOW PRODUCT DEFECT, commit blocker YES; criterion 36 exact canonical replay. |
| Bounded F01 remediation | F01 CLOSED; 90 PASS / 6 QUALIFIED / 0 FAIL | 20 added regression tests; 18 reproduced failures before the fix, all 20 passed afterward; complete matching final-source regression. |
| Targeted independent re-review | APPROVE; 90 PASS / 6 QUALIFIED / 0 FAIL | Fresh 128 tests PASS: 26 contracts/OpenAPI, 81 HTTP/PostgreSQL, 21 Flutter controller/session/widget; 20 additional independent HTTP/PostgreSQL probes PASS. No remaining actionable review finding or commit blocker. |
| Focused Codex Security | SECURITY APPROVE | All 70 changed paths inspected; zero confirmed security vulnerabilities, zero security commit blockers, no required remediation within the supported-application-writer threat model. |
| Exact implementation-commit remote CI | COMPLETE / SUCCESS | Run 38152045998, all five jobs successful on the implementation SHA. |
| Current accepted implementation | 93 PASS / 3 QUALIFIED / 0 FAIL | Criteria 91–93 now PASS; 94–96 retain accepted limitations. |

The completed independent re-review and Security decisions above are supplied
review evidence in the closure request, reconciled with repository implementation
and retained final-source records; they were not freshly rerun by this docs pass.

F01's root cause was differing identity treatment: authorization normalized the
Location UUID, but receipt matching used its original route spelling. An accepted
uppercase/mixed-case command could commit and then return `409 operation_conflict`
on identical retry. One validated canonical Location UUID now governs authorization,
resource scope and receipt identity comparison. The fix preserves configured Location
and Company isolation, current authority before replay, canonical payload semantics,
original results, historical replay and Supplier Company-only scope. All five Order
commands (create/save/issue/cancel/close) cover upper/lower/mixed-case routes,
post-terminal history, restart, revoked authority, foreign Location denial,
conflicting bindings and no duplicate effects.

### Focused Security scope and limitations

The Security approval retains F01 canonical UUID isolation, Purchasing Company/
Location authorization and current authority before receipt disclosure. Runtime
grants, strict requests/cursors, session/exact-retry safety and domain isolation were
examined. It does not assert universal absence of vulnerabilities.

Fresh Flutter execution during Security was blocked by an SDK cache lockfile issue;
Security used source inspection and matching earlier Flutter evidence. One delegated
dynamic validation step was blocked and not retried. Neither limitation is presented
as fresh execution or superseded by this docs-only pass. Final implementation CI is
separate successful evidence.

| Observation | Classification / blocker | Unhardened check |
| --- | --- | --- |
| I01 | INFO / NO | Supplier retirement SQL CHECK does not explicitly reject NULL `retired_at`. |
| I02 | INFO / NO | PurchaseOrder terminal SQL CHECK does not explicitly reject NULL `terminal_at`. |
| I03 | INFO / NO | Receipt JSON comparison CHECK does not independently reject JSON null. |

PostgreSQL CHECK accepts SQL NULL/UNKNOWN. For each observation, a known exploit on
the supported Purchasing API path is **NOT ESTABLISHED**, and a complete handcrafted-
SQL transaction exploit is **NOT REPRODUCED**. These are nonblocking defense-in-depth
observations about malformed SQL evidence under the supported-writer boundary,
not reproduced API exploits. Migration 0024 is unchanged and these checks are not
claimed hardened. A bounded future follow-up requires an authorized new migration
and regression evidence; it does not allocate P4.13 or merge I01–I03 into M1–M4.
See [debt traceability](technical-debt.md#p412-security-info-observations).

### Final-source regression and historical fingerprint

Retained post-F01 evidence in `.local/p412/final/summary.json` reports **1,261 package
tests PASS**: 264 API contracts, 607 server/PostgreSQL, 2 design system, 388 Flutter.
All **16/16 final verification phases**, **13/13 opt-in journeys** and **3/3 numeric
browser stages** passed. The 14 conditional tests skipped in the broad server suite
were separately executed; no skipped database test is counted as PASS. Required
analyzers/formatters, release Web build, Compose and repository verification passed.
This docs-only reconciliation does not rerun those suites or imply new execution.

The **PRE-CLOSURE final implementation inventory** is 566 files, 6,890,990 bytes,
SHA-256 `171efd4010395b8f1db0653884a9efce0b391b044bd975f860feb9ce809a1966`.
Retained verification ran from `2026-10-11T12:48:53.6103626Z` to
`2026-10-11T13:16:47.1944289Z`, with content/timestamps unchanged throughout its
phases. These are historical implementation measurements, not a fingerprint or
verification timestamp of the edited closure documents. No new docs-inclusive
fingerprint is substituted for the accepted inventory.

### Delivered workflow, ownership and replay

Manager → create/select Company Supplier → create Location draft → select locally
eligible Articles → enter exact quantities → save authoritative snapshots → review
saved content → issue internally approved immutable Order → inspect outstanding
issued Orders → explicitly cancel/close administratively → inspect retained history.
Issue proves internal approval of ordering intent, not transmission, Supplier
receipt/acceptance, delivery, Goods Receipt or Stock increase. Administrative close
also does not imply delivery.

Purchasing owns Supplier, PurchaseOrder, PurchaseOrderLine, frozen snapshots,
PurchasingCommand receipts, lifecycle and history. Supplier is a stable Company UUID
with no owning Location, bounded name, optional ordering reference, active edits,
irreversible retirement and preserved attribution/history. Orders have stable UUID,
Company + Location scope, unique site reference, whole draft replacement and immutable
issued content. Lifecycle is draft → issued, draft → cancelled, issued → cancelled,
issued → closed; no reopening or issued-content edit. Cancellation is reasoned and
closure administrative. Drafts have 0–50 lines; issue requires 1–50 distinct Articles,
stable line UUIDs, contiguous positions and server-frozen Article snapshots.

Quantities are exact decimal strings represented as integer thousandths, positive
0.001–999999999999.999. No floating-point business calculation, rounding, cross-unit
totals or pack conversion exists. Inventory owns Article/version, unit labels and
effective Location Assortment; Purchasing uses its narrow Inventory-owned Article
port and has no Stock write port. No Purchasing side effects occur in Stock,
StockCount, Recipe, PreparationBatch, Workforce, Shift, Task, Knowledge, Planogram
or outbox/events.

Capabilities `purchasing.suppliers.manage`, `purchasing.orders.manage` and
`purchasing.orders.issue` initially grant Admin only. Supplier resources are Company
scoped; Order resources are Company + configured Location scoped. Current Account
authority and resource scope precede receipt lookup; administrative Purchasing
requires no Employee link. Plugin/Employee/Viewer/Auditor access remains denied.

Eight durable kinds cover Supplier create/edit/retire and Order create/save/issue/
cancel/close in one Company + operation UUID namespace. Exact committed replay
returns original accepted result/status without overwriting newer state, duplicating
audit/receipts, revalidating fresh catalog eligibility or reopening terminal Orders.
Changed bindings conflict. Failed/no-change commands consume no operation UUID;
authorization always precedes receipt disclosure.

### Migration, backup and update acceptance

Chain **0001 → 0024**, latest `0024_bounded_purchase_orders.sql`; no migration 0025.
The four owned tables are `purchasing_suppliers`, `purchasing_orders`,
`purchasing_order_lines`, `purchasing_commands`. Delivered integrity includes Company/
Location composites, a narrow Account attribution anchor, immutable issued evidence,
line/quantity/reference bounds, lifecycle checks, deferred aggregate checks, receipt
integrity and restricted runtime grants, within the explicit INFO/raw-SQL limits.
Historical migrations 0001–0023 remain immutable.

Encrypted backup/restore acceptance contains two Suppliers, six Orders, four order
lines, 20 durable receipts/all eight kinds, active/retired Supplier history, immutable
issued snapshots, exact replay, configured-Location denial, runtime-grant checks and
session/plugin fencing. Previous Stock/Count, Recipe/PreparationBatch, Shift Transfer,
Task/Knowledge/Planogram evidence is preserved. This retained acceptance is separate
from the Security scan's disclosed fresh-execution limitations.

Update/recovery acceptance includes clean 0001→0024, populated 0023→0024, late
migration rollback, successful forward update and encrypted fenced pre-0024 recovery.
Legacy P4.11 transfers, P4.10 preparation, Stock/Count and guidance remain preserved.
There is no downgrade or historical migration edit.

### Closure and remaining publication gate

The accepted implementation is DONE/CLOSED; no active P4.12 remediation remains.
[Acceptance](phase-4-12-acceptance.md) retains criteria 94–96: memory-only uncertain
recovery, physical-device/accessibility gaps and supported-writer/raw-SQL boundary.
M1 proxy/login-limiter pilot gate, M2 CLOSED, M3 endpoint containment, M4 broader
error taxonomy, P4.5 F01/F02 and P4.9 historical qualification retain their dispositions.
I01–I03 remain separately traced nonblocking observations; no global zero-debt claim.

This pass changes Markdown documentation only, leaves implementation HEAD on `main`
and index empty, and does not stage, commit, push, change branches or operate on the
normal StoreOS database. Final documentation closure commit and its own exact-head
remote CI remain **PENDING**. The external final closure/publication decision follows
only after that second CI succeeds. No closure commit SHA/run/outcome is invented;
P4.13 remains UNSELECTED.
