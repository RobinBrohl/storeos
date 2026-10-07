# P4.9 — Approved Article Recipe / Composition

**DONE/CLOSED — composition only.** Implementation commit
`e5e6d5c2999bb9f8132161b43ad1537aa403973c` is on main and pushed. Initial independent
CHANGES REQUIRED led to F01–F05 remediation and targeted APPROVE. Final acceptance
is **151 PASS / 1 QUALIFIED / 0 FAIL**, with criterion 152 qualified solely for
historical forensic evidence scope. Focused Codex Security returned **SECURITY APPROVE**;
all five jobs in [exact-commit CI 37581798736](https://github.com/RobinBrohl/storeos/actions/runs/37581798736)
succeeded. No active P4.9 remediation remains. No P4.10 capability is selected or ACTIVE.

## Verified planning baseline

Before any edits: main, clean tree/index, no stash, one intended worktree; HEAD,
cached origin/main and live origin/main all
`e9515d61788bc2bd378ab21f48df9626a17cf8e9`. P4.1–P4.8 were canonically DONE/CLOSED,
with no active remediation or selected/ACTIVE P4.9. Migration chain ended at 0020;
0001–0020 were committed and unchanged. All five jobs in exact-HEAD
[CI 37456182116](https://github.com/RobinBrohl/storeos/actions/runs/37456182116)
succeeded. The preceding P4.9 selection plan and detailed implementation request
are the selected composition-only product contract.

## Delivered vertical slice

[ADR 0023](../adr/0023-approved-article-recipe-composition.md) and
[Production architecture](../architecture/production-recipes.md) describe identity,
lifecycle, declared batch, frozen Article references, exact thousandths, publication
replay, authorization and ownership. Migration 0021 is the only new migration.
Existing migration/dependency/lockfile bytes are preserved.

The normal API provides Company-wide manager Article selection, Recipe creation,
whole-draft saving, saved preview, exact history, replacement/discard, publication
and terminal retirement; employee APIs expose current approved compositions.
Flutter exposes those workflows with dirty-save publication blocking, deliberate
reference reselection, separate current warnings and session-safe controls.
Reading and work navigation create no business evidence.

## Historical implementation verification protocol and evidence surfaces

Final-source results and exact counts are retained in ignored `.local/p49` logs
and the final review response, after all source/test/tool/document edits. A source
fingerprint covers tracked and non-ignored new files before/after verification.
No source edit after that run may reuse its results without rerunning verification.

| Surface | Independent evidence |
| --- | --- |
| Strict contracts / bounds / Web arithmetic | `packages/api_contracts/test/recipe_contracts_test.dart` |
| Lifecycle, snapshot preservation, replay, unit gates and Stock isolation | `apps/server/test/recipe_integration_test.dart` |
| 50/51 lines, order, maximum quantity, forged/duplicate/self references | Same PostgreSQL acceptance, using actual HTTP and saved/released composition |
| Current capability, Company/resource and real plugin denial | Same PostgreSQL acceptance; all thirteen routes and OpenAPI parity |
| Deterministic save/save, save/publish, save/discard, publish/publish, publish/retire, draft/retire, unit/publish and inactivity/publish | Company lock plus observed `pg_locks` queue; both orders; no fixed sleeps |
| Publication revision/pointer/audit faults | Injected test-only trigger failures; full Recipe/audit hashes unchanged |
| Clean/populated migration and late failure | Existing migrations, populated schema 1–4 work/Knowledge/Planogram/Stock/count receipts, catalog absence and rerun |
| Controller/editor safety | `apps/client_flutter/test/recipe_test.dart`; exact retry, deep immutability, invalid transport, dirty state, session replacement/delayed response and literal widgets |
| Real Flutter / HTTP / PostgreSQL | `recipe_client_journey_test.dart` invokes real Flutter adapters/controllers against the runtime API; independent Stock oracle |
| Real Chrome | `recipe_browser_test.dart` and `integration_test/recipe_test.dart`; author/preview/employee reads, unit mismatch/reselection, lost committed response, same-port server restart, exact retry, history, reactivation and retirement |
| Backup | `tool/recipe_acceptance.dart` seeds through authorized API; all three table hashes/counts included in encrypted source/restore comparison; restored visibility/history/replay/employee denial and terminal protections |
| Update/recovery | Pending migrations include 0021; upgraded HTTP seed and authorization/replay checks; pre-update restore/fencing retains existing contract |
| Regression | API/server/PostgreSQL/Flutter/design system tests, analyzers, format, Compose, release Web, four existing Chrome workflows, numeric E2E, encrypted backup/update, crypto and report diagnostics/redaction |

Run `scripts/recipes/Run-P49Checks.ps1` for the bounded PostgreSQL suite;
`-ClientJourney`, `-Browser`, `-BrowserRegressions`, `-Numeric`, `-FullRegression`
select the other repository acceptance paths. `-TestName` supports targeted repair.
Use already installed SDK/Docker/ChromeDriver paths. The wrapper creates a strictly
named disposable database, runs the runtime role and always drops run resources.
Backup/update use existing isolated wrappers with `-SkipPackageResolution`.
No dependencies are installed/upgraded, business evidence is never seeded by
unauthorized database writes, and the normal StoreOS database is untouched by the verified run. This does not
claim retrospective forensic proof of every historical implementation action.

## Historical focused independent/security review preparation

Security was not run during implementation; the later supplied approval is recorded
in the final closure below. Preparation covered Company/Article/Recipe scope,
employee draft/history/operation exclusion, manager picker scope, current replay
authorization and actor/operation binding, frozen/current units, session replacement
and delayed responses, literal browser rendering, runtime grants/terminal guards
and restored authorization. Exact manager history context and explicit Article-ID
reselection are separate from frozen evidence. General runtime SQL grants remain
within the repository supported-writer threat model, not an arbitrary-writer API.

## Scope and historical review gates

No yield, consumption, production run, recursive expansion, conversion, costing,
HACCP, allergens/nutrition, Task pins, acknowledgment, readership, events/outbox,
offline device writes or multi-site synchronization is introduced. P4.1–P4.8
closure stays intact. At the implementation/remediation checkpoint, targeted independent
review, focused security review and changed-commit remote CI were outstanding.
Those gates are complete at final closure below.

## Independent review and bounded remediation — 2026-10-07

Chronology is retained: initial implementation claimed **152/152 local PASS**;
the independent adversarial review returned **CHANGES REQUIRED**. Its supported
core architecture, atomic publication/replay, authorization, immutable evidence,
exact quantities, Company isolation, unit semantics, concurrency, backup/restore
and migration rollback remain intact. That initial claim is historical, not the
final remediation assessment.

| Finding | Review disposition | Bounded correction / evidence |
| --- | --- | --- |
| F01 | MEDIUM product defect: initial discard stranded authoring | Existing new-draft command creates an empty next revision when active with no draft/publication; same Recipe, current active produced snapshot, manage authorization/version/Company lock. Exact initial recovery, discarded evidence, both race orders, real Flutter/HTTP and Chrome authoring coverage. |
| F02 | MEDIUM product defect: stale snapshot cache after reconciliation | Explicit accept clears transient snapshots. Stale and uncertain save widget tests verify resident mg/SKU/name/quantity, rendered labels, next save and publication; real two-editor HTTP journey changes kg to mg and preserves accepted mg. |
| F03 | LOW product defect: duplicate JSON names accepted | Opt-in iterative lexical name detector with decoded string/escape equality, per-object scopes and canonical syntax validation; Recipe writes return bounded 400 invalid_json with zero effects. All six write shapes, nested/escaped duplicates, independent array objects, transport/UTF-8 and unchanged unrelated APIs are covered. |
| F04 | LOW contract defect: copied broad OpenAPI error unions | All thirteen operations inventory actual supported paths. Exact status/code metadata and descriptions have an independent contract test; production HTTP parity probes cover representative business and transport outcomes. Revision-allocation collision is not reachable through the Company-serialized supported writer; creation has no publication receipt conflict. |
| F05 | MEDIUM evidence gap: empty observed Count fixtures | Supported P4.8 APIs seed two real StockLevels, approved Count/two lines, three rounds/observations (including superseded/recount), recording Account/Employee, six receipts, nonzero correction provenance and zero-variance outcome. Actual 0020 prefix is asserted before 0021; all seven Stock/Count tables have nonempty before/after hashes for migration and Recipe lifecycle independently. Existing backup assertions remain. |
| F06 | INFO accepted design | Durable publication identity is Company + operation UUID. Binding conflicts apply within that Company; current authorization precedes foreign receipt access. No global uniqueness change. Criterion 69 is assessed against this supported scope. |
| F07 | INFO accepted evidence limitation | Current/future verification uses disposable databases and records cleanup. Criterion 152 proves the verified remediation run's target discipline; its unqualified historical reading remains QUALIFIED. No retrospective proof is fabricated. |

Migration 0021 must retain SHA-256
`e371771ddfec4c8889d2995caaf3b53a0d8b4d05f8fe82fc410271f50bf37eca`.
At the remediation checkpoint, migrations 0001–0020, dependencies/lockfiles, branch
and baseline HEAD were preserved. No P4.10, commit, stage, push or Codex Security
run was part of that remediation phase; subsequent approval/commit/CI follows below.

The final-source inventory, exact executed counts, sanitized logs/reports, all
152 reassessed criteria (especially 31/34/69/129/148/152), per-operation error sets,
Count hashes and run cleanup are retained in
`.local/p49/remediation-evidence.md` and `.local/p49/remediation-final-summary.json`.
They are separate from the historical implementation reports. Final verification
requires an identical deterministic source inventory before/after every phase;
no inventoried file may be edited after verification starts.

## Final documentation closure — 2026-10-07

### Baseline and exact changed-commit CI

Before closure edits, branch was `main`, working tree and index were clean, no stash
existed, and `C:/dev/storeos` was the sole intended worktree. HEAD, cached
`origin/main` and live `origin/main` all matched implementation commit
`e5e6d5c2999bb9f8132161b43ad1537aa403973c` (Add approved article recipe compositions).
Live origin was checked with read-only `git ls-remote`; GitHub Actions API confirmed
completed/success [CI run 37581798736](https://github.com/RobinBrohl/storeos/actions/runs/37581798736)
for that exact SHA. All required jobs completed successfully:

| Job | Result |
| --- | --- |
| dart | success |
| flutter | success |
| numeric-guided-work-e2e | success |
| backup-restore-acceptance | success |
| update-recovery-acceptance | success |

P4.1–P4.8 canonical closure remains intact. No active P4.9 remediation or
selected/ACTIVE P4.10 capability remains. This is documentation/status
reconciliation only: no implementation, tests, migration, scripts, CI, OpenAPI,
contracts, configuration, dependency or lockfile changes. No branch change, staging,
commit, push or database operation occurs in this closure pass.

### Preserved review and security chronology

1. Selection chose **Approved Article Recipe / Composition — composition only**.
2. Initial implementation claimed **152/152 local PASS**.
3. Independent adversarial review returned **CHANGES REQUIRED**: F01/F02 MEDIUM
   product defects, F03 LOW product defect, F04 LOW documentation/contract defect
   and F05 MEDIUM test/evidence gap, as recorded in the table above.
4. Bounded F01–F05 remediation completed. F06 INFO retains Company-scoped
   operation UUIDs; F07 INFO retains the historical forensic evidence limitation.
5. The targeted independent review supplied for final reconciliation returned
   **APPROVE**, with **151 PASS / 1 QUALIFIED / 0 FAIL**. All F01–F05 are CLOSED.
6. The supplied focused Codex Security result was **SECURITY APPROVE**: **0 confirmed
   vulnerabilities, 0 probable vulnerabilities, 0 required security fixes and no
   security commit blocker**. Its confirmed review boundaries include object
   authorization/Company isolation, frozen integrity, duplicate JSON defense,
   employee confidentiality, publication/replay, recovery drafts, role separation,
   runtime grants/SQL safety, session isolation, content bounds, audit/privacy,
   supported browser rendering, restored authorization and migration security.
7. Implementation was committed and pushed; dynamically verified exact-commit CI
   is green. P4.9 is now canonically **DONE/CLOSED**.

Approval outcomes above come from the final closure request's supplied independent
and security review dispositions. This pass did not conduct another review/security
scan. Repository remediation evidence independently retains the acceptance totals
and executed checks; live Git/GitHub evidence supplies the commit and CI identifiers.

Criterion **152 remains QUALIFIED**, solely because universal retrospective proof
about every historical implementation action against the normal StoreOS database
cannot be reconstructed. Verified acceptance/remediation/review runs used disposable
databases and kept the normal database out of their business writes. This qualification
is no product defect, security vulnerability, active remediation or closure blocker;
it must not be converted into fabricated PASS evidence.

### Delivered operator workflow and composition semantics

Manager selects an active produced Article, creates its stable Company-wide Recipe,
edits the draft, declares one batch, adds ordered ingredient Articles, enters exact
positive quantities and preparation, saves the authoritative draft, reviews it and
publishes that exact saved revision. Employee discovers the current approved Recipe
and reads batch, ordered frozen references, quantities/units and preparation.
Manager can prepare/save/review a replacement while employees continue reading the
prior publication, then publish without changing historical evidence. Discard,
monotonic draft recovery and terminal retirement are supported.

Recipe UUID is separate from Article UUID; exactly one Recipe exists per Company +
produced Article. Article remains product identity. No Location assortment is needed.
Recipe lifecycle is active → retired, terminal with no hard delete. Revision lifecycle
is draft → published or draft → discarded, with stable UUIDs, monotonic numbers,
at most one active draft and immutable terminal revisions/ingredient content.
Previous publications remain published historical evidence, with no separate
historical status. Discarded numbers are never reused.

Ingredients describe **one declared Recipe batch**. Descriptive text such as
“one 30 × 40 cm tray” defines no output quantity, yield, servings, final weight,
production quantity or scaling. Exact decimal-string quantities have up to three
fractional digits, persist as integer thousandths and range from **0.001 through
999999999999.999**. No floating point, rounding or automatic conversion exists.

Server selection/reselection captures ingredient Article ID, SKU, name/display
label and unit; clients cannot authoritatively supply snapshots. Ordinary saves
preserve them, replacement drafts copy them exactly and later Article metadata
never rewrites approved evidence. Explicit reselection performs a current
authoritative lookup and captures fresh labels/unit; the operator reviews the
quantity meaning. Accepting authoritative saved state clears transient selected
snapshot caches, displays the server-saved SKU/name/unit and preserves that state
on the subsequent ordinary save (F02 CLOSED).

Initial discard leaves Recipe active, revision 1 discarded, no active draft and
possibly no publication. Manager may create **empty revision 2 under the same
Recipe identity** (F01 CLOSED). If a current publication exists, the next draft
copies its exact frozen content instead.

Fresh creation needs an active produced Article; new ingredient selection needs
an active same-Company Article. Fresh publication requires active produced and
ingredient Articles plus exact frozen/current ingredient unit equality. Mismatch
returns **422 ingredient_unit_changed**, with zero publication effects. Operator
must explicitly reselect/review/save; no silent refresh, conversion, reinterpretation
or draft modification occurs. Existing publication survives rename, SKU/unit change
and ingredient/produced deactivation. Employee standalone visibility follows current
produced-Article activity and Recipe retirement; manager history remains available.
Frozen revision/batch/preparation/IDs/labels/units/quantities and separately labeled
current Article activity/labels/unit warnings remain distinct.

### Authorization, publication and replay

Capabilities are `production.recipes.read`, `production.recipes.manage` and
`production.recipes.publish`. Admin receives all three; Employee receives read
only. Viewer/Auditor have no Recipe business access; Plugin has no human Recipe
access. Manage does not grant Article mutation; read does not grant Stock access.

Employee receives only current approved visible content, with no active draft,
discarded revisions, management history, aggregate version, publication operation
identity or authoring metadata. Visibility filtering precedes pagination; search
does not disclose draft/discarded/historical-only content. Opening is read-only,
with no acknowledgment/readership evidence. Manager can inspect current publication,
active draft, published/discarded history and exact frozen content with current
divergence context; history is Company/Recipe scoped, bounded/paginated and survives
retirement. Authenticated session replacement clears/fences discovery, reads, lists,
picker/editor/snapshots, history/search/errors and pending/delayed responses.

Fresh publication validates current authentication, Company/resource scope,
publish capability, active Recipe/current draft, expected version, complete saved
content, Article availability and unit equality. One transaction marks the saved
revision published, moves current publication, clears draft, advances version,
records actor/time/operation identity and appends one bounded audit. Previous
publication remains unchanged. Retirement requires publish authority, terminally
retires Recipe, atomically discards an active draft, retains terminal evidence and
manager history, removes employee visibility and appends bounded audit.

Publication identity is **Company + operation UUID** (F06 INFO accepted).
Binding within that Company includes Recipe, revision, publishing Account and
original expected version; mismatch returns `operation_conflict`. Independent
Companies may reuse UUID values. Current authentication/Company/capability/resource
scope precedes receipt access/replay return, including foreign-resource denial.
Exact replay returns original evidence without new revision/version/audit, pointer
movement or lifecycle mutation. Verified late replay works after newer publication,
produced/ingredient deactivation, unit change, retirement and server restart.
It is evidentiary: no reactivation, draft restoration, backward pointer movement,
frozen rewrite or current-Article reevaluation as fresh publication.

Audit contains bounded IDs/revision numbers/versions/transitions/operation/changed
field metadata, not preparation, batch, ingredient quantities or full composition.
No Recipe events/outbox/readership audit exists. Operator content renders literally;
no exercised Recipe content executes HTML/Markdown/scripts or creates active
links/images/content-driven external requests. This claims only the supported
rendering model. Uncertain publication retry remains immutable and session bound;
memory-only uncertain-command recovery remains an accepted limitation.

### Release bounds, migration and absence of side effects

Supported bounds are **50 ingredient lines**, **120 Unicode code points** for batch,
**8 KiB UTF-8** preparation, **32 KiB** canonical composition including frozen
labels and **256 KiB** transport body. Acceptance preserves 50 distinct ingredients,
ordering/exact quantities and successful publication; 51, duplicate and self
ingredients are rejected. These are release bounds, not throughput benchmarks.

F03 is CLOSED: Recipe writes reject duplicate decoded JSON names, including
Unicode-equivalent escaped forms, before last-value-wins decoding; bounded
**400 invalid_json** and zero effects. Enforcement remains opt-in to Recipe writes.
F04 is CLOSED: all **13 Recipe operations** document precise reachable per-operation
errors. Creation excludes publication-only conflicts; reads exclude write-only
validation. Global M3/M4 remain at their existing dispositions.

Migration chain is exactly **0001–0021**, ending at `0021_recipe_compositions.sql`;
no migration 0022 exists. Git comparison to predecessor
`e9515d61788bc2bd378ab21f48df9626a17cf8e9` shows only new 0021, with **0001–0020
unchanged**. Closure leaves **0001–0021 untouched**. Raw 0021 SHA-256 matches
`e371771ddfec4c8889d2995caaf3b53a0d8b4d05f8fe82fc410271f50bf37eca`.
The three tables (`production_recipes`, `production_recipe_revisions`,
`production_recipe_ingredients`) and Inventory-owned projection preserve scoped
FKs/pointers, uniqueness, exact quantity/order/bounds, terminal guards and narrow
runtime grants. No unexpected SECURITY DEFINER or terminal DELETE/TRUNCATE authority
is claimed; privileged/raw SQL remains outside supported-writer business guarantees.

Recipe mutates no StockLevel, StockMovement, StockCount, StockCountLine,
StockCountRound, StockCountObservation or StockCountCommand. TaskTemplate schemas
remain **1–4**; no schema 5, Recipe pin, Shift mutation or Guided Work evidence exists.
F05 CLOSED evidence uses two StockLevels, approved Count, two lines, three rounds,
three observations and six commands/receipts, superseded/recount evidence, nonzero
count_correction provenance and movement-free zero-variance approval. Nonempty
hashes for all seven Stock/Count tables match across actual populated 0020 → 0021
migration and independently across the Recipe workflow; this is not row-count-only
evidence. See retained `.local/p49/remediation-evidence.md` and final results.

### Real acceptance, backup/update/recovery and retained limits

Real Flutter/HTTP/PostgreSQL and Chrome acceptance records produced Article P,
I1 **1.250 kg** and I2 **0.050 kg** for one tray batch, save/publish/read revision 1,
replacement I2 **0.075** while revision 1 remains visible, then I2 **kg → g**.
Fresh publication rejects unit mismatch with zero effects; explicit reselection,
quantity review/save precede publication whose committed response is lost.
Server restart and exact retry return original evidence without duplicate audit,
version or pointer changes. Retirement hides employee content, retains manager
history and late replay leaves Recipe retired/current pointer unchanged.

Encrypted backup/restore preserves active/retired Recipes, current/historical
publication, active draft/discarded revision, frozen snapshots, exact quantities,
ordering, pointers, publication identity and audit. Matching source/restored hashes
and restored employee visibility, manager history, replay, unauthorized denial,
revoked-session/plugin/runtime fencing are retained. Update/recovery covers clean
0001 → 0021, populated 0020 → 0021 with nonempty Count preservation, failed-0021
rollback, rerun/application recovery, old Stock/Counts, Task schemas 1–4,
Knowledge/Planograms, receipts/audit and usable Recipes; isolated recovery stays
fenced. No downgrade or automatic replacement activation is supported.

Final-source remediation recorded **822 package tests PASS** (119 API, 369 server,
332 Flutter, 2 design system), four analyzers/format, release Web/Compose, focused
36 Recipe PostgreSQL tests, 7 Recipe contracts, 18 controller/widget and 6 strict
JSON tests, real journeys/browser regressions/numeric/crypto/diagnostics and
encrypted backup/update. Seven conditional server hosts skipped in the full suite
were exercised in their separate opt-in phases. These are historical software
results; documentation edits do not claim a fresh software rerun.

No costing, nutrition/allergen calculation, label compliance, production batch
execution/produced yield/scaling, Stock consumption/reservation, pack/unit conversion,
alternative Recipes, Task Recipe pinning, offline authoring or multi-site sync is
delivered. Existing M1 proxy/login-limiter pilot gate, M2 CLOSED, M3 local endpoint
containment, M4 broader error debt, supported-writer/raw-SQL boundary, memory-only
recovery, physical-device/accessibility gaps and P4.5 F01/F02 nonblocking follow-ups
retain their dispositions. F06/F07 introduce no active code debt.

Closure validation is documentation diff review, `git diff --check`, status/stat,
stale current-state search and unchanged migration/non-documentation checks.
No software regression rerun is required or performed. Closure edits stay
unstaged/uncommitted on main, with nothing pushed by this pass. Next after the
closure commit is **fresh P4.10 capability selection**, without preselection here.
