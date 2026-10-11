# P4.12 acceptance matrix

Selected capability: bounded purchase orders with minimal Supplier identity. Baseline `main` / `604d1d198b158b1907dd000ea435d94dbae0dec1`. P4.1–P4.11 remain DONE/CLOSED; P4.13 UNSELECTED. Current state: **P4.12 IMPLEMENTED LOCALLY / F01 REMEDIATED / TARGETED RE-REVIEW PENDING / SECURITY REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING**. Implementation remains unstaged/uncommitted; P4.12 is not DONE/CLOSED.

Historical assessments remain distinct: initial implementation **90 PASS / 6 QUALIFIED / 0 FAIL**; independent adversarial review **CHANGES REQUIRED: 89 PASS / 6 QUALIFIED / 1 FAIL**. Criterion 36 failed because accepted uppercase Location UUID routes broke exact replay (F01, **LOW PRODUCT DEFECT / COMMIT BLOCKER**). The [remediation record](phase-4-12-bounded-purchase-orders.md#independent-finding-f01-and-bounded-remediation) documents the actual pre-fix HTTP/PostgreSQL failures and canonical Location fix. The matrix below is the remediated local self-assessment, conditional on a fresh complete final-source pass; targeted re-review has not approved it.

This matrix is evaluated against the final-source run in ignored `.local/p412/final/summary.json`, with its unchanged content/timestamp manifests and phase logs. A PASS below is valid only when the referenced final phase passes and the overall summary reports `pass`; absent, failed or skipped required evidence does not count as PASS. The final report supplies the measured counts. Review readiness does not close the capability. With the complete passing final run: **90 PASS / 6 QUALIFIED / 0 FAIL**, 96 criteria. Qualification reasons are explicit in rows 91–96.

Evidence keys (repository-relative, all final run logs under `.local/p412/final/`):

| Key | Evidence |
| --- | --- |
| A | [Contract implementation](../../packages/api_contracts/lib/src/purchasing.dart), [contract tests](../../packages/api_contracts/test/purchasing_test.dart) |
| D | [Domain](../../apps/server/lib/src/purchasing/purchase_order.dart), [Application](../../apps/server/lib/src/purchasing/purchasing_service.dart), [Repository](../../apps/server/lib/src/purchasing/purchasing_repository.dart) |
| I | [Inventory public port](../../apps/server/lib/src/inventory/purchasing_article_port.dart), [module ownership](../architecture/module-boundaries.md), [ADR 0026](../adr/0026-bounded-purchase-order-intent.md) |
| M | [Migration 0024](../../apps/server/migrations/0024_bounded_purchase_orders.sql), [grant implementation](../../apps/server/lib/src/infrastructure/migration_runner.dart) |
| H | [HTTP routes](../../apps/server/lib/src/http/purchasing_routes.dart), [OpenAPI generator](../../packages/api_contracts/tool/purchasing_openapi.dart), [OpenAPI tests](../../packages/api_contracts/test/purchasing_openapi_test.dart) |
| S | [Database/HTTP contract cases](../../apps/server/test/purchasing_cases.dart), [safety cases](../../apps/server/test/purchasing_safety_cases.dart), [restricted fixture](../../apps/server/test/purchasing_fixture.dart), `focused.log` |
| R | [Observed queue races](../../apps/server/test/purchasing_race_cases.dart), `focused.log` |
| X | [F01 UUID replay regressions](../../apps/server/test/purchasing_uuid_replay_cases.dart), `focused.log`, pre/post-fix logs under `.local/p412/f01/` |
| C | [Controller](../../apps/client_flutter/lib/src/application/purchasing_controller.dart), [widgets](../../apps/client_flutter/lib/src/ui/purchasing_section.dart), [controller/widget tests](../../apps/client_flutter/test/purchasing_test.dart), `regression.log` |
| J | [Real host fixture](../../apps/server/test/purchasing_journey_fixture.dart), [real controller journey](../../apps/client_flutter/test/purchasing_http_journey.dart), [actual Chrome journey](../../apps/client_flutter/integration_test/purchasing_test.dart), `hosts.log` |
| B | [Purchasing recovery fixture](../../apps/server/tool/purchasing_acceptance.dart), [backup fixture](../../apps/server/tool/backup_restore_fixture.dart), [fresh restore authorization](../../apps/server/tool/backup_planogram_acceptance.dart), `backup.log` and referenced sanitized report |
| U | [Actual populated 0023 recovery test](../../apps/server/test/purchasing_upgrade_recovery_test.dart), [legacy update smoke fixture](../../apps/server/tool/update_recovery_fixture.dart), `migration.log`, `update.log` and referenced sanitized report |
| F | [Final verification runner](../../scripts/purchasing/Run-P412FinalVerification.ps1), [isolated checks](../../scripts/purchasing/Run-P412Checks.ps1), all final phase logs, `source-before.json`, `source-after.json`, `summary.json` |

## Requirement decisions

| # | Requirement | Evidence | Status | Decision / limits |
| --- | --- | --- | --- | --- |
| 01 | Purchasing owns only its aggregates/lines/receipts | D, I, M | PASS | Four owned tables; no foreign repository or business writes. |
| 02 | Minimal Supplier identity | A, D, S | PASS | UUID, Company, bounded name and nullable opaque ordering reference. No contacts or personnel association. |
| 03 | Active edit and irreversible retirement | D, S | PASS | Versioned edit, no-change rejection, permanent retirement. |
| 04 | Supplier historical attribution | D, S, B | PASS | Actor/time/version retained; pre-edit snapshots and original receipts survive retirement. |
| 05 | Company scope | D, S, M | PASS | Foreign Company principal is denied for reads, new writes and committed replay; composite scope FKs. |
| 06 | Location-scoped Order | D, H, M, S | PASS | Immutable Location; scope checked for detail/history/lifecycle/replay. |
| 07 | Current Admin authorization | D, S, R | PASS | Exactly three permissions; current Account rights reread inside Company lock. |
| 08 | Employee/Viewer/Auditor/Plugin denial | H, S | PASS | Every operation denies each non-Admin role and Plugin token. |
| 09 | Configured execution Location isolation | D, S, J | PASS | Route = configured = current Account Location; valid wrong-Location Admin denied. |
| 10 | Reference uniqueness through every state | A, M, S | PASS | Company/Location reservation and deterministic ASCII fold; Unicode remains distinct. |
| 11 | Draft lifecycle | D, S | PASS | Create and whole save only before issue/cancel. |
| 12 | Issue lifecycle | D, S | PASS | Issue requires exact saved nonempty draft and eligible current selections. |
| 13 | Cancellation and closure | D, S, R | PASS | Draft/issued cancellation; issued administrative closure; mandatory bounded reason. |
| 14 | Immutable issued content | M, S, J | PASS | Content/lines frozen after issue, including catalog changes. |
| 15 | Immutable terminal evidence | M, S, R | PASS | No reopen or overwrite; first terminal decision wins. |
| 16 | Draft whole replacement | D, M, S | PASS | Parent lock; ordered replacement transaction; retained snapshots preserved. |
| 17 | Draft has 0–50 lines | A, M, S | PASS | Empty draft accepted, maximum 50 valid Unicode lines accepted, 51 rejected. |
| 18 | Issue has 1–50 lines | D, M, S | PASS | Empty issue rejected; valid maximum issued. |
| 19 | Stable line identity, Article uniqueness and ordering | A, M, S | PASS | Distinct IDs/Articles, contiguous positions, reorder and removal supported. |
| 20 | Positive exact quantity bounds | A, M, S | PASS | 0.001 through 999999999999.999; no overflow or zero. |
| 21 | Decimal strings only | A, S | PASS | Reject JSON numbers, exponent, signs, whitespace and excessive precision. |
| 22 | No rounding, totals or unit conversion | A, D, J | PASS | Integer thousandths and canonical three-place strings; 2.5 and 12 preserved. |
| 23 | Server Supplier snapshots | D, M, S | PASS | Only selected identity/version accepted; forged names/attribution rejected. |
| 24 | Server Article snapshots | I, D, S, B | PASS | ID/version/SKU/name/unit captured by server; restored snapshots predate label edit. |
| 25 | Explicit reselection | A, D, S, J | PASS | Retained selection freezes; new/changed Article or Supplier requires explicit flag/current version. |
| 26 | Stale Supplier validation | D, S, R | PASS | Edit and retirement conflict without refreshing the draft. |
| 27 | Stale Article validation | I, D, S, R | PASS | Current metadata/version checked at issue. |
| 28 | Unit-change conflict | D, S, R, J | PASS | Precise `article_unit_changed`, zero effects and explicit reselect/save before issue. |
| 29 | Effective local Assortment | I, S, R | PASS | Active Article and membership required; deactivation race tested in both orders. |
| 30 | Inventory public-port ownership | I, D | PASS | Purchasing never obtains Inventory repository or writes catalog. |
| 31 | Authorized Company transactions | D, R | PASS | Existing Company transaction lock serializes current rights and catalog writers. |
| 32 | Atomic aggregate, receipt and audit | D, M, S | PASS | Failed aggregate/receipt/audit/deferred/result stages roll back completely. |
| 33 | No-change handling | D, S | PASS | Supplier edit/draft save return 409 and conserve receipts/audit/version. |
| 34 | Shared Company + operation UUID | M, D, S | PASS | One namespace covers Supplier and Order kinds; binding collisions denied. |
| 35 | Eight durable commands | D, S, B | PASS | Supplier create/edit/retire, Order create/save/issue/cancel/close exercised. |
| 36 | Exact canonical replay | A, D, S, X, B | PASS | F01 remediated locally: uppercase/mixed/lower Location identity is canonical before scope and receipt comparison. All five kinds return original result/status and `replayed:true`; cross-spelling, restart and historical terminal replay preserve counts/versions/line identities/hashes. Independent targeted approval remains pending. |
| 37 | Conflicting replay | S, D | PASS | Actor, target, kind, Location, expected version and canonical intent collisions rejected. |
| 38 | Authorization before receipt disclosure | D, S, R, B | PASS | Current rights/resource scope precede receipt lookup, including after revocation. |
| 39 | Failed UUID reuse | S, D | PASS | Validation/no-change/injected rollback leave UUID reusable. |
| 40 | Historical replay after terminal/catalog changes | S, J, B | PASS | All kinds replay after restart; original issue survives close and Supplier retirement. |
| 41 | Scoped API routes | H, S | PASS | All 15 operations under bounded Purchasing namespace. |
| 42 | Endpoint-local OpenAPI parity | H | PASS | Requests/responses/errors reachable per operation; old paths/schemas preserved exactly. |
| 43 | Decoded JSON duplicate rejection | H, S | PASS | Unknown/duplicate decoded write fields and malformed media/body rejected. |
| 44 | Unicode and text bounds | A, M, S | PASS | Code points, trim, controls/surrogates and all field maxima verified. |
| 45 | Document/transport byte bounds | A, D, M, H, S | PASS | Decoded UTF-8 document calculation agrees with SQL; endpoint transport and receipt bounds. |
| 46 | Scoped keyset pagination | D, S | PASS | 51-row fixture, page 50, filters before limit, endpoint/filter/resource/Company/Location cursor binding. |
| 47 | Parameterized SQL and literal search | D, I, S | PASS | Named parameters; `%`, `_`, backslash treated literally. Dynamic identifiers are validated owned schema names. |
| 48 | Narrow runtime grants | M, S, B, U | PASS | No aggregate DELETE/TRUNCATE, receipt mutation or line UPDATE; no SECURITY DEFINER. |
| 49 | Immutable database evidence | M, S, B | PASS | Receipt updates/deletes and issued line changes rejected; supported writer boundary explicit in row 96. |
| 50 | Deferred final-state invariants | M, S | PASS | Matching last receipt/result, count/version, actor/scope, positions and document bounds; incomplete replacement rolls back. |
| 51 | Save/save and save/issue races | S, R | PASS | Both serial orders observed through PostgreSQL lock queue; one coherent final document. |
| 52 | Catalog/issue races | R | PASS | Supplier edit/retire and Article metadata/unit/activity/Assortment, both orders. |
| 53 | Terminal-transition races | R | PASS | Close/cancel in both orders, immutable winning evidence. |
| 54 | Account revocation races | R | PASS | New write and committed replay, both orders; rights/session revocation authoritative. |
| 55 | Complete manager workflow | C, J | PASS | Supplier lifecycle/history; lists, pickers, draft editing/reorder/remove, saved review, issue, reason and history. |
| 56 | Same/different Account replacement | C | PASS | Opaque session identity clears memory and mounted widgets, including reason dialog. |
| 57 | Uncertain exact retry | C, J | PASS | Frozen UUID/route/payload/session; exact retry only, mutation controls blocked. |
| 58 | Confirmed result versus current detail | C | PASS | Historical command evidence separate; failed refresh clears actionable stale detail. |
| 59 | Literal untrusted rendering | C, J | PASS | Selectable text; actual Chrome proves no injected script or content-driven external request. |
| 60 | Minimized audit and logs | D, S, F | PASS | Eight allowlisted actions; IDs/versions/field names only; sanitized errors and retained reports. |
| 61 | Real Flutter→HTTP→restricted PostgreSQL | J | PASS | Entire controller workflow against production HTTP and restricted runtime persistence. |
| 62 | Actual Chrome successful workflow | J | PASS | User-facing controls execute complete workflow; host test requires process success. |
| 63 | Lost committed response and restart | J | PASS | Successful issue response replaced with 503, server restarted, exact body replay proves one receipt/audit. |
| 64 | Negative authorization paths | S, J, B | PASS | Wrong roles, Company, Location, forged identity/snapshot and restored access denial. |
| 65 | No Stock or Count mutation | J | PASS | Nonempty Stock/movement/count/observation/correction hashes unchanged. |
| 66 | No Recipe or Preparation mutation | J | PASS | Nonempty retained Recipe/Batch/count-correction hashes unchanged by Purchasing workflow. |
| 67 | No Workforce or Task mutation | J | PASS | Nonempty Shift/Task guidance/approved transfer and lineage hashes unchanged. |
| 68 | No event or outbox effects | D, J | PASS | Purchasing emits no domain/plugin events; populated event/outbox hashes conserved. |
| 69 | Meaningful encrypted backup/restore | B | PASS | Six Order cases, two Suppliers, four old Article lines, 20 receipts/eight kinds plus nonempty legacy evidence. |
| 70 | Restored authorization and replay | B | PASS | Fresh current authentication, all 20 original replays, Employee/Location denial and narrow grants. |
| 71 | Clean migration chain | M, S | PASS | 0001–0024 applied cleanly through production runner. |
| 72 | Actual populated 0023→0024 | U | PASS | Real 0023 prefix with populated legacy evidence; apply once and idempotently, Purchasing smoke. |
| 73 | Late migration rollback | U | PASS | Injected late failure preserves tables/catalog/functions/constraints/grants/ledger/audit; subsequent real application succeeds. |
| 74 | Preserve P4.11/P4.10 evidence | J, B, U | PASS | Nonempty transfer/lineage and Batch/correction identities, context and hashes conserved in journey/recovery. |
| 75 | Complete existing regression | F | PASS | All four package suites, with exact final counts in summary; conditional skips never counted as passes. |
| 76 | Every opt-in host executed | F | PASS | Eleven host files, thirteen HTTP/Chrome journeys; no opt-in skip; migration opt-in separately executed. |
| 77 | Web, analyzers and formatters | F | PASS | Four fatal-info analyzers, four format checks, release Web build and Compose validation. |
| 78 | Final-source content and timestamps | F | PASS | Each phase checks all inventoried tracked/nonignored source/doc hashes, lengths and modification times. |
| 79 | Documentation and honest gate status | F, ADR 0026, HANDOVER/status/debt | PASS | Implemented locally; every external gate pending; no P4.12 closure or P4.13 implementation claimed. |
| 80 | Clean baseline and uncommitted final state | F, final repository probe | PASS | Main/HEAD/cached/live origin unchanged; empty index; old migrations/locks unchanged; normal containers preserved; owned resources cleaned. |
| 81 | Same Account re-login clearing | C | PASS | Clears immediately before held authorization/status response; late POST cannot cross session. |
| 82 | Different Account clearing | C | PASS | Resident Supplier/Order/editor/history/confirmation/pending state and fields cleared. |
| 83 | Delayed GET and POST fencing | C | PASS | Old responses cannot repopulate current session; cached control callbacks also check binding. |
| 84 | Guard before UUID and validation | C | PASS | Synchronous guard prevents second intent/UUID; nested caller mutation cannot change pending body. |
| 85 | Failed refresh blocks subsequent writes | C | PASS | Confirmed evidence remains historical; current Order detail is null until authoritative reload. |
| 86 | Edit/save fault injection | S | PASS | Supplier update, line deletion, Order update, deferred constraint and result projection tested. |
| 87 | Lifecycle fault injection | S | PASS | Issue/cancel/close at aggregate, receipt, audit and deferred stage; 12 rollback/reuse cases. |
| 88 | Query duplicate and allowlist boundaries | H, S | PASS | Decoded duplicate names, unknown parameters, invalid cursor and bounds rejected locally. |
| 89 | Supplier management needs no Employee link | D, S | PASS | Bootstrap Admin performs Supplier/Order workflow without personnel association. |
| 90 | Fenced encrypted pre-update restore | U, B | PASS | Actual 0023 recovery lacks Purchasing/anchor, revokes old sessions/plugin grants and runtime CONNECT; source preserved. |
| 91 | Independent review approval | Handoff | QUALIFIED | Initial review CHANGES REQUIRED; targeted F01 re-review pending. Local remediation does not approve itself. |
| 92 | Focused Codex Security approval | Handoff | QUALIFIED | Mandatory after independent review; deliberately not executed in this implementation pass. |
| 93 | Remote changed-commit CI | Repository state | QUALIFIED | Pending authorized commit/push; baseline CI is not changed-source CI. |
| 94 | Uncertain command recovery after client process loss | C, ADR 0026 | QUALIFIED | Memory-only by selected contract; process loss discards pending intent. No durable client recovery claim. |
| 95 | Physical devices and accessibility | Existing debt | QUALIFIED | Actual Chrome, controller and widget evidence only. Standing physical-device/accessibility gaps retained. |
| 96 | Fully consistent malicious raw SQL from credential holder | M, ADR 0026, technical debt | QUALIFIED | Supported authorized writers are the business boundary. Runtime integrity/grants do not replace application authorization for a fabricated consistent SQL transaction. |

## Completion boundary

Readiness requires every local mandatory phase to pass on unchanged final source. Approval, Security and remote CI are subsequent gates. The six qualifications above must remain visible; no global zero-debt claim, receiving/Stock production, offline write queue or multi-site synchronization is implied. Retain M1 pilot gate, M2 CLOSED, M3 endpoint containment, M4 broader taxonomy, P4.5 F01/F02 and P4.9 criterion 152 dispositions.
