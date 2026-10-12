# P4.14 acceptance matrix

Delivery: **IMPLEMENTED LOCALLY**. This record freezes local implementation evidence;
independent functional review and targeted F01/F02 re-review returned APPROVE;
both findings are CLOSED. Focused Codex Security returned SECURITY APPROVE and
final remediation verification passed. Implementation-commit CI and final P4.14
closure remain PENDING.
P4.15 is UNSELECTED. Recorded delivery evidence does not mutate or establish Stock.

Evidence keys below are reproducible from repository root with the pinned SDKs.
Every database run uses a unique disposable PostgreSQL project and restricted runtime
credentials. `.local` logs are sanitized local evidence, excluded from Git.

- **BASE**: dynamic branch/HEAD/cached and live origin, clean tree/index/stash,
  one worktree, introduction-blob migration comparison, eight dependency-file checks,
  GitHub run 38229127545 exact SHA and five successful jobs; delivery record baseline.
- **D**: `Run-P414Verification.ps1 -Mode focused`, server
  `purchasing_delivery_test.dart`: 12-unit lifecycle journey, eight ordered terminal
  races, concurrent declarations, namespace races, declaration/terminal faults,
  strict transport and runtime SQL checks.
- **S**: same command, `purchasing_delivery_safety_test.dart`: role/plugin denial,
  all replay bindings, reference reservation, no-change, 52 identities, 50 lines,
  aggregate limit, four revocation races and populated 0025 migration/legacy proof.
- **I**: same command, `purchasing_delivery_integrity_test.dart`: mixed-case scoped
  UUIDs, correction race, both restricted-SQL namespace insertion directions,
  standalone logout races, deferred/projection rollback and complete malformed
  transactions (JSON null/missing/wrong types, incomplete lines, scope and quantities).
  F02 remediation adds canonical positive controls, one-invariant mutations, exact
  SQLSTATE plus constraint/message checks, complete rollback and same-ID control replay.
- **API**: focused API-contract `purchasing_delivery_test.dart` plus retained
  Purchasing/OpenAPI tests: strict DTOs, exact quantities, deep freeze, complete
  new contracts and preservation of every prior operation/schema.
- **UI**: focused client `purchasing_delivery_test.dart` plus retained Purchasing
  tests: guards, immutable retry, denial after uncertainty, confirmed/refresh split,
  same/different opaque sessions, delayed writes and mounted-dialog clearing.
  F01 remediation also proves loaded register/cursor invalidation after declaration
  and Order closure, retained filters, failed-refresh invalidation and replacement-session fencing.
- **HTTP**: `-Mode journey`, actual Flutter controller → production HTTP → restricted
  PostgreSQL, `purchasing_client_journey_test.dart` / `purchasing_http_journey.dart`.
- **CHROME**: `-Mode browser`, actual Chrome / real HTTP / restricted PostgreSQL,
  `integration_test/purchasing_test.dart`. Includes the 50-line form, private observed
  response gates, opaque same/different sessions, refresh failure, and a real WebDriver
  page refresh. Successful reload emits `P4.14_ACTUAL_PAGE_RELOAD_PASS`.
- **BACKUP**: `-Mode backup`, nonempty encrypted backup/restore, deterministic content
  hashes, nine revisions/receipts, protected reads/replay, scope and restricted grants.
- **MIG**: `-Mode migration`, three executed populated encrypted recovery tests,
  including `purchasing_delivery_upgrade_recovery_test.dart` pre-0026 boundary.
- **UPDATE**: `-Mode update`, production MigrationRunner through 0026, preserved
  historical fixtures, delivery smoke, encrypted fenced recovery and consistent prose.
- **FINAL**: `Run-P414FinalVerification.ps1`; final logs, exact package/conditional
  counts and before/after SHA-256/size/UTC timestamp inventories in `.local/p414/final`.
  Full regression, all fifteen prior/new host journeys, three migration cases, numeric
  browser stages, print, crypto, redaction/diagnostics/setup and diff checks are explicit.
- **SRC**: inspection of ADR 0028, shared DTO, Domain/Application/repository/routes,
  migration 0026, audit/grants and client source. Static evidence does not substitute
  for the separately identified executed journeys or external review gates.

| # | Requirement | Exact evidence | Result / explanation |
| --- | --- | --- | --- |
| 1 | Required main/HEAD and live origin baseline | BASE; exact SHA in delivery record | PASS |
| 2 | Clean starting tree/index, empty stash, one worktree | BASE | PASS |
| 3 | Exact closure CI and all five jobs | BASE; GitHub run 38229127545 | PASS |
| 4 | Historical migrations match introduction blobs | BASE; 25 files, zero mismatches | PASS |
| 5 | Initial dependency baseline unchanged | BASE; eight tracked files | PASS |
| 6 | One selected bounded P4.14 capability | SRC; ADR 0028 | PASS |
| 7 | Purchasing exclusively owns delivery evidence | SRC; repository touches Purchasing tables only | PASS |
| 8 | No physical Stock or Count mutation | HTTP; nonempty legacy table hashes; BACKUP | PASS |
| 9 | No Task/Shift/Production effects | HTTP; nonempty legacy/Assignment hashes | PASS |
| 10 | No P4.15 or expanded transmission/finance/conversion | SRC; diff and ADR exclusions | PASS |
| 11 | Draft declaration rejected | S; draft-cancellation lifecycle test | PASS |
| 12 | Issued Order accepts originals | D; 12-unit journey | PASS |
| 13 | New identity after terminal closure rejected | D; 12-unit journey | PASS |
| 14 | Issued cancellation serializes with delivery | D; both-order cancel races | PASS |
| 15 | Existing terminal declarations remain correctable | D; close/cancel correction races | PASS |
| 16 | Draft cancellation creates no issued-delivery snapshot | S; not_issued/ledger 0/null snapshot | PASS |
| 17 | Original identity and revision 1 persist | D; original/restart/history journey | PASS |
| 18 | Complete replacement omits prior line contributions | S; 50-line replacement test | PASS |
| 19 | Reasoned correction preserves prior evidence | D; history quantities 5.000 and 4.000 | PASS |
| 20 | Void appends evidence without negative entries | D; void/read/history; migration positive lines | PASS |
| 21 | Correction restores voided identity | D; revision 3 restoration | PASS |
| 22 | Repeated void/no-change correction definitive | S; no_change checks, conserved evidence | PASS |
| 23 | Corrections require expected revision | I; concurrent correction; D stale/terminal races | PASS |
| 24 | Ledger starts at zero | S; draft cancellation and migration legacy proof | PASS |
| 25 | Each accepted revision advances sequence once | D; journey and concurrent replay; I | PASS |
| 26 | Contiguous revision and ledger constraints | I; complete malformed transactions; migration guards | PASS |
| 27 | Order lifecycle version stays independent | D; exact closed Order JSON unchanged after correction | PASS |
| 28 | Frozen exact Order-line selection | D; foreign-line 422; I scoped line FK | PASS |
| 29 | No Article snapshots or unit overrides accepted | API strict unknown fields; D transport test | PASS |
| 30 | Retired/renamed Supplier and changed Article do not reinterpret lines | HTTP/CHROME; retained bag/piece snapshots and supplier history | PASS |
| 31 | Decimal strings only, no floating JSON numbers | API and D malformed quantities | PASS |
| 32 | Positive exact thousandths | API; zero/negative/excess precision/malformed inputs | PASS |
| 33 | Exact three-place output | D/S/I; 0.052, 5.000, 11.000 and max quantity checks | PASS |
| 34 | Overflow-safe intermediate arithmetic | SRC BigInt/numeric; S aggregate ceiling | PASS |
| 35 | Per-line supported aggregate bound | S; max plus 0.001 → quantity_limit | PASS |
| 36 | No unlike-unit Order-wide numeric total | S/CHROME kg/piece 50-line display; SRC | PASS |
| 37 | Effective totals use latest replacement per identity | D complete lifecycle; S omitted lines | PASS |
| 38 | Recorded remainder is nonnegative exact difference | D 12 → 11 / remainder 1 | PASS |
| 39 | Explicit recorded overdelivery | D/CHROME accepted 13 / excess 1 | PASS |
| 40 | Increased overdelivery requires reason | D 422 followed by accepted reason | PASS |
| 41 | Overdelivery is allowed beyond ordered quantity | D/S max-value evidence; CHROME | PASS |
| 42 | No declarations differ from voided-zero evidence | SRC UI declarationCount text; D/S ledger states | PASS |
| 43 | Required trimmed bounded local reference | API text validation; S references | PASS |
| 44 | ASCII-only per-Order reference reservation | S Case-Ä / cASE-Ä conflict | PASS |
| 45 | Correction/void preserve reference | D immutable history; migration guard | PASS |
| 46 | No claim of physical shipment deduplication | SRC operator text and ADR | PASS |
| 47 | Terminal capture shares old command transaction | D terminal faults; I deferred/projection rollback | PASS |
| 48 | Exact terminal Order operation/version/actor/time linkage | MIG/SRC deferred FK and terminal checks; D | PASS |
| 49 | Serialized closure-time ledger boundary | D eight observed delivery/terminal races | PASS |
| 50 | Snapshot remains immutable after later correction | D current 11 / terminal 12; BACKUP | PASS |
| 51 | Terminal Order stays closed with original version/time | D exact Order JSON comparison | PASS |
| 52 | Shortfall does not block administrative closure | D terminal-first empty snapshot races | PASS |
| 53 | No automatic received/closed state | D original partial/full states; SRC unchanged Order model | PASS |
| 54 | Legacy terminal has no invented zero snapshot | S populated 0025 upgrade; MIG/BACKUP | PASS |
| 55 | Current manager authority required without Employee link | D/S restricted admin fixtures | PASS |
| 56 | Employee/viewer/auditor read/write denied | S per-role endpoint checks | PASS |
| 57 | Approved plugin token denied on all eight operations | S approved plugin remains valid for Organization; delivery 401 | PASS |
| 58 | Configured Location and persisted resource isolation | S foreign Location/Order/Delivery; I scoped FKs | PASS |
| 59 | Company authorization precedes protected reads/replay | SRC shared runAuthorized; retained Purchasing foreign-Company test | PASS |
| 60 | UUID representations canonical across all supplied IDs | I mixed-case Location/Order/Delivery/line/operation replay | PASS |
| 61 | Exact retry across UUID representations returns original | I; no new effects / original response | PASS |
| 62 | Old/new Purchasing UUID namespace in supported directions | D observed same-operation races in both orders | PASS |
| 63 | Old/new namespace enforced by restricted SQL | I exact purchasing_operation_namespace constraint both insert directions; higher isolation rejected by purchasing_operation_isolation | PASS |
| 64 | Three receipt kinds retain canonical complete intent | D/API/I receipt correspondence and replay | PASS |
| 65 | Original accepted summary is retained on replay | HTTP/CHROME historical 5 after current 11 | PASS |
| 66 | Replay survives restart and later terminal state | D/HTTP/CHROME actual restart and close replay | PASS |
| 67 | Changed actor/kind/target/version/payload bindings conflict | S binding matrix; D namespace; retained actor replay tests | PASS |
| 68 | Operation conflict reveals no original payload | S explicit response absence check | PASS |
| 69 | Failed operation UUID remains reusable | D declaration/terminal fault retry | PASS |
| 70 | Concurrent declarations accept one fresh baseline | D observed lock queue | PASS |
| 71 | Identical concurrent declaration replays once | D identical race / one ledger revision | PASS |
| 72 | Concurrent corrections cannot silently overwrite | I observed lock queue / ledger conflict | PASS |
| 73 | Capability/Account revocation fences write/replay | S four observed revocation orders | PASS |
| 74 | Session-only logout fences write/replay | I four observed standalone logout orders | PASS |
| 75 | Declaration insertion/line/receipt/audit faults atomic | D four injected fault stages | PASS |
| 76 | Terminal update/old receipt/snapshot/audit faults atomic | D four terminal fault stages | PASS |
| 77 | Late deferred failure rolls back all terminal effects | I deferred snapshot trigger | PASS |
| 78 | Final result projection failure rolls back transition | I projection function fault and valid retry | PASS |
| 79 | Exactly one new migration; old chain unchanged | SRC/BASE/MIG; migration 0026 only | PASS |
| 80 | Scoped composite FKs and positive scaled quantities | I complete foreign line/Location/quantity transactions | PASS |
| 81 | Required SQL NULL and JSON null rejected | D SQL NULL variants; I complete JSON-null transactions | PASS |
| 82 | Missing keys/wrong JSON types rejected at final state | I complete otherwise-linked receipt transactions | PASS |
| 83 | Missing revision lines cannot commit | I missing_lines and D orphan revision transaction | PASS |
| 84 | Immutable history and restricted runtime grants | D actual UPDATE/DELETE/TRUNCATE denial; BACKUP grants | PASS |
| 85 | Strict decoded duplicate/unknown JSON and query fields | D escaped equivalent names and duplicate query; API | PASS |
| 86 | 16,384 streamed body bound and media rejection | D 413/415, no effects | PASS |
| 87 | 1–50 distinct lines and bounded Unicode/reference/reasons | API/D/S; supported 50-line command and invalid sets | PASS |
| 88 | Bounded keyset pages/cursors and stable ordering | S 52 identities / 50+2 / distinct set / 2,049 rejection | PASS |
| 89 | Endpoint/resource/filter cursor bindings | S wrong endpoint/history cursor; SRC canonical scope map | PASS |
| 90 | Both OpenAPI representations and old contracts preserved | API generated eight operations + every baseline schema/path | PASS |
| 91 | Manager register, forms, history and terminal comparison work | CHROME; literal text and 50-line rendered form | PASS |
| 92 | Deep freeze and synchronous command guard | UI exact reference-identical route/body retries | PASS |
| 93 | Later denial does not erase earlier uncertainty | UI 503 → 403 → exact retry | PASS |
| 94 | Opaque same/different sessions fence reads/writes/forms | CHROME observed HTTP gates; UI | PASS |
| 95 | Confirmed result survives failed detail refresh | CHROME injected refresh failure; UI clears actionable detail | PASS |
| 96 | Browser reload reads persisted server evidence | CHROME actual WebDriver refresh marker | PASS |
| 97 | Audit minimizes IDs/sequences and adds no read/events | SRC audit calls/allowlist; HTTP conservation | PASS |
| 98 | Encrypted nonempty restore preserves IDs/content/history/access | BACKUP exact hashes, replay/scope and source conservation | PASS |
| 99 | Populated migration rollback/forward/no-op/pre-0026 recovery | MIG three tests, deferred post-grant fault and fenced restore | PASS |
| 100 | Update report matches actual 0026 smoke/migration outcome | UPDATE structured pass and touched prose; prior qualification preserved | PASS |
| 101 | Prior package/browser/print/operational nonregression | FINAL sixteen phases / 1,451 package passes; bounded remediation 195 focused / 414 client / HTTP / Chrome PASS | PASS — scopes retained; no new full operational rerun claimed |
| 102 | Final source SHA-256/size/UTC timestamp match | FINAL and remediation before/after inventories; approved source unchanged except commit approval documentation | PASS — commit preparation verifies the complete inventory and approval-only documentation delta |
| 103 | Independent adversarial review | User-confirmed functional APPROVE and targeted F01/F02 APPROVE; both CLOSED | PASS |
| 104 | Focused Codex Security | User-confirmed SECURITY APPROVE | PASS |
| 105 | Exact implementation-commit remote CI | Explicit push authorization, then exact-SHA CI required | QUALIFIED — PENDING; no remote implementation CI outcome claimed |
| 106 | Standing physical/device/privacy/recovery boundaries retained | ADR/delivery/debt documentation | QUALIFIED — no physical, native-device, accessibility, retention/export/offboarding, key-custody or RPO/RTO certification claimed |
| 107 | Only justified dependency metadata exception | Client SDK flutter_driver direct-dev classification; identical resolved versions/hashes | PASS |
| 108 | Local delivery record, ADR and live status remain truthful | SRC; IMPLEMENTED LOCALLY / both APPROVE / F01-F02 CLOSED / SECURITY APPROVE / verification PASS / CI and final closure PENDING / P4.15 UNSELECTED | PASS |
| 109 | Normally served client assets protected | Baseline restoration: 39 matching files; FINAL served-client-before/after inventories | QUALIFIED — first release check temporarily overwrote the proxy mount; restored from published HEAD, but original pre-build byte hashes unavailable |

Current approval acceptance: **106 PASS / 3 QUALIFIED / 0 FAIL**. Remaining
qualifications are exact implementation CI (105), standing operator/hardware limits
(106), and the static-client-asset incident (109). Final P4.14 closure remains pending.

Historical initial drafting totals were **102 PASS / 7 QUALIFIED / 0 FAIL**, before
the frozen run completed. Its final report recorded **104 PASS / 5 QUALIFIED / 0 FAIL**.
The subsequently confirmed independent approvals close criteria 103–104; these
updates do not rewrite the old verification inventories or claim a new full-suite run.

## Bounded F01/F02 remediation evidence — 2026-10-12

The initial independent APPROVE had LOW F01/F02 follow-ups. After bounded remediation,
the user confirmed targeted APPROVE with both findings CLOSED, SECURITY APPROVE and
final remediation PASS. Implementation-commit CI and final closure remain pending.
The original frozen-run summary and bounded remediation summary retain their own
source and execution scope; no old verification artifact is overwritten.

- **F01:** confirmed Order/delivery mutations clear register rows and cursor while
  retaining filters. Loaded-register declaration and closure regressions verify
  fresh first-page reads. Failed detail refresh and held responses across opaque
  same/different Account replacement preserve invalidation and session fencing.
- **F02:** canonical complete SQL controls commit and replay. Eleven invariant
  mutations plus the four existing NULL/empty/operation-null receipt probes assert
  their intended SQLSTATE and constraint/column/message, compare complete evidence
  after rollback, and then commit/replay the identical valid intent with the same
  IDs. Permission and orphan-receipt probes also assert their specific rejections.
- **Current bounded outcomes:** `.local/p414-remediation/summary.json` and its logs
  record focused Purchasing tests, all client tests, both affected analyzers, the
  actual controller/HTTP/PostgreSQL journey and actual Chrome/page reload. These
  outcomes do not assert a new sixteen-phase or backup/update acceptance run.
- **Preservation:** before/after inventories verify all migrations/dependencies and
  non-remediation files against this turn's baseline, plus normally served asset
  contents, sizes and timestamps. All disposable projects are cleaned up.

See the [bounded remediation record](phase-4-14-purchase-order-deliveries.md#bounded-low-review-remediation--2026-10-12).
