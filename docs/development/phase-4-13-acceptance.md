# P4.13 acceptance matrix

State: **IMPLEMENTED LOCALLY; F01 REMEDIATED LOCALLY; TARGETED INDEPENDENT RE-REVIEW PENDING**.
Original criteria 01–92 plus expansions 93–100.
Chronology: initial implementation **96 PASS / 4 QUALIFIED / 0 FAIL**; supplied
independent **CHANGES REQUIRED**, **95 PASS / 4 QUALIFIED / 1 FAIL** for criterion 04,
F01 **MEDIUM PRODUCT DEFECT / COMMIT BLOCKER**. The finding is retained in [P].
Post-remediation local self-assessment:
**96 PASS / 4 QUALIFIED / 0 FAIL**, conditional on the completed frozen verifier
reporting `result: pass` and unchanged source content/timestamps. This record must be
read with `.local/p413/final/summary.json` and its source manifests. Any failed phase
or source edit invalidates the local PASS claims until verification completes again.
No skipped database/browser test is counted as PASS; conditional package skips are
reported separately and executed explicitly in opt-in and migration phases.

Evidence keys: D decision/ownership; M migration; S/X real PostgreSQL/HTTP regression;
U retained pre-fix failures and post-fix UUID spelling/replay/scope/eligibility HTTP tests;
C strict contracts; O all twelve operation status/code/baseline parity; F Flutter state;
J restricted PostgreSQL controller gateway; H actual Chrome; B encrypted recovery probe;
R populated forward/rollback/pre-0025 recovery; V frozen complete verifier; P delivery record.

| No. | Criterion | Result | Concrete evidence / disposition |
| --- | --- | --- | --- |
| 01 | baseline | PASS | [P]: exact baseline HEAD, cached/live origin and five-job closure CI. |
| 02 | scope/non-goals | PASS | [D], [P]: selected bounded Production ownership and exclusions. |
| 03 | Production ownership | PASS | [D], [P]: selected bounded Production ownership and exclusions. |
| 04 | manager assignment creation | PASS | [U], [S], [X], [J]: F01 pre-fix HTTP/PG failure retained; canonical lowercase/uppercase/mixed picker and creation, scope/eligibility denials, exact replay and concurrent creation pass after bounded remediation. Targeted independent approval remains pending. |
| 05 | employee identity eligibility | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 06 | configured Location isolation | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 07 | Company isolation | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 08 | manager capability | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 09 | self read capability | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 10 | self start capability | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 11 | current Account–Employee linkage | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 12 | assignment immutable Employee | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 13 | assignment immutable Location | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 14 | exact RecipeRevision pin | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 15 | current revision eligibility at creation | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 16 | retained R1 after R2 publication | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 17 | Recipe retirement handling | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 18 | produced Article activity | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 19 | local Assortment validation | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 20 | ingredient activity/unit validation | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 21 | planned integer count 1–9999 | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 22 | requested vs actual count distinction | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 23 | two-state terminal lifecycle | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 24 | withdrawal before start | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 25 | start after withdrawal denied | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 26 | withdrawal after start denied | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 27 | atomic Batch opening | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 28 | exactly one linked Batch | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 29 | Batch scope/revision/count match | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 30 | standalone Batch nonregression | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 31 | linked Batch completion | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 32 | linked Batch cancellation | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 33 | manager corrections | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 34 | zero effective count | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 35 | historical Recipe read | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 36 | historical Batch read | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 37 | immutable assignment evidence | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 38 | create receipt | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 39 | withdraw receipt | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 40 | start receipt | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 41 | exact historical replay | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 42 | conflicting operation UUID | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 43 | auth before receipt disclosure | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 44 | failed UUID reuse | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 45 | no duplicate audit | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 46 | both-order start/withdraw race | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 47 | concurrent starts | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 48 | Recipe publication race | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 49 | Recipe retirement race | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 50 | Article/Assortment race | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 51 | Employee/link/capability race | PASS | [S], [X], [J]: authorized persisted workflows, retained pin, observed lock ordering, original replay and unchanged evidence. |
| 52 | DB foreign keys/uniqueness | PASS | [M], [X]: scoped keys, null-safe checks, narrow grants and injected rollback/reusable UUIDs. |
| 53 | DB null-safe lifecycle checks | PASS | [M], [X]: scoped keys, null-safe checks, narrow grants and injected rollback/reusable UUIDs. |
| 54 | Batch-link deferred integrity | PASS | [M], [X]: scoped keys, null-safe checks, narrow grants and injected rollback/reusable UUIDs. |
| 55 | narrow runtime grants | PASS | [M], [X]: scoped keys, null-safe checks, narrow grants and injected rollback/reusable UUIDs. |
| 56 | fault atomicity | PASS | [M], [X]: scoped keys, null-safe checks, narrow grants and injected rollback/reusable UUIDs. |
| 57 | strict HTTP DTOs | PASS | [C], [O], [X]: strict input/transport, exact endpoint parity and scoped 50-item cursors. |
| 58 | JSON duplicate rejection | PASS | [C], [O], [X]: strict input/transport, exact endpoint parity and scoped 50-item cursors. |
| 59 | no forged identity/Batch fields | PASS | [C], [O], [X]: strict input/transport, exact endpoint parity and scoped 50-item cursors. |
| 60 | exact OpenAPI status/error parity | PASS | [C], [O], [X]: strict input/transport, exact endpoint parity and scoped 50-item cursors. |
| 61 | bounded pagination/cursors | PASS | [C], [O], [X]: strict input/transport, exact endpoint parity and scoped 50-item cursors. |
| 62 | manager Flutter workflow | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 63 | Employee Flutter workflow | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 64 | deep-frozen uncertain retry | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 65 | session replacement | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 66 | delayed response fencing | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 67 | confirmation/detail separation | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 68 | literal content rendering | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 69 | minimized audit | PASS | [F], [H], [J]: completed workflows, frozen retry, session/refresh fencing and literal text. |
| 70 | controller→HTTP→PostgreSQL | PASS | [J], [H], [X]: real accounts/HTTP/restricted PostgreSQL, cross-owner/Location/Company denial. |
| 71 | actual Chrome journey | PASS | [J], [H], [X]: real accounts/HTTP/restricted PostgreSQL, cross-owner/Location/Company denial. |
| 72 | foreign Employee denial | PASS | [J], [H], [X]: real accounts/HTTP/restricted PostgreSQL, cross-owner/Location/Company denial. |
| 73 | cross-Location denial | PASS | [J], [H], [X]: real accounts/HTTP/restricted PostgreSQL, cross-owner/Location/Company denial. |
| 74 | cross-Company denial | PASS | [J], [H], [X]: real accounts/HTTP/restricted PostgreSQL, cross-owner/Location/Company denial. |
| 75 | no Purchasing effects | PASS | [J]: deterministic populated Purchasing, Stock/Count, Workforce/Tasks, guidance and event hashes unchanged. |
| 76 | no Stock/Count effects | PASS | [J]: deterministic populated Purchasing, Stock/Count, Workforce/Tasks, guidance and event hashes unchanged. |
| 77 | no Workforce/Task effects | PASS | [J]: deterministic populated Purchasing, Stock/Count, Workforce/Tasks, guidance and event hashes unchanged. |
| 78 | no outbox/events | PASS | [J]: deterministic populated Purchasing, Stock/Count, Workforce/Tasks, guidance and event hashes unchanged. |
| 79 | meaningful backup/restore | PASS | [B], [V]: seven assignments/twelve receipts, complete content comparison, fenced restore and effect-free replay. |
| 80 | restored authorization/replay | PASS | [B], [V]: seven assignments/twelve receipts, complete content comparison, fenced restore and effect-free replay. |
| 81 | clean 0025 migration | PASS | [R], [V]: clean/populated forward chain, late catalog/grant/ledger rollback, encrypted pre-0025 recovery. |
| 82 | populated 0024→0025 | PASS | [R], [V]: clean/populated forward chain, late catalog/grant/ledger rollback, encrypted pre-0025 recovery. |
| 83 | late migration rollback | PASS | [R], [V]: clean/populated forward chain, late catalog/grant/ledger rollback, encrypted pre-0025 recovery. |
| 84 | preserved prior history | PASS | [R], [V]: clean/populated forward chain, late catalog/grant/ledger rollback, encrypted pre-0025 recovery. |
| 85 | complete regression | PASS | [V]: four complete packages, release/analyzers/format, fifteen opt-in journeys, operational/diagnostic phases and identical source manifests. |
| 86 | all opt-in journeys | PASS | [V]: four complete packages, release/analyzers/format, fifteen opt-in journeys, operational/diagnostic phases and identical source manifests. |
| 87 | final-source consistency | PASS | [V]: four complete packages, release/analyzers/format, fifteen opt-in journeys, operational/diagnostic phases and identical source manifests. |
| 88 | documentation honest gate state | PASS | [P]: local implementation state and unselected P4.14; historical closure evidence retained. |
| 89 | independent review gate | QUALIFIED | Supplied independent CHANGES REQUIRED (F01) retained. F01 locally remediated; TARGETED INDEPENDENT RE-REVIEW PENDING. No independent approval claimed. |
| 90 | focused Security gate | QUALIFIED | PENDING focused Codex Security; mandatory subsequent gate, not run in this implementation turn. |
| 91 | remote implementation CI gate | QUALIFIED | PENDING user publication and exact changed-commit CI; baseline CI does not verify unstaged P4.13. |
| 92 | accepted standing limitations | QUALIFIED | [P]: supported-writer/raw-SQL, memory-only tracking, hardware/accessibility, operator privacy/retention/export/offboarding/recovery and standing debt retained. |
| 93 | replacement Account retains Employee ownership without prior-actor replay | PASS | [X]: valid replacement link can start pending work, but old actor operation conflicts; revoked and fresh unlinked sessions denied. |
| 94 | deferred migration fault after grants and ledger insertion | PASS | [R]: injected deferred ledger trigger fires after grants; exact pre-update catalog/data/ledger restored. |
| 95 | malformed opening payload/result and start timestamp rejected | PASS | [M], [X]: malformed opening payload, stored result and linked timestamp abort the complete transaction; same UUID retry succeeds. |
| 96 | later reconciliation denial preserves unknown outcome | PASS | [F]: uncertain create/withdraw/start exact binding survives later 403 denial and retries original immutable intent. |
| 97 | eligible projection excludes Account/session private fields | PASS | [S], [B]: picker exposes only ID/displayName/Employee version; minimized audit excludes names/counts/reasons. |
| 98 | own/filter predicates precede 50-item pagination | PASS | [X]: 52 own and foreign requests yield 50 then 2, with scope/filter/endpoint cursor rejection. |
| 99 | mounted same/different Account dialog and held status fencing | PASS | [F]: same/different Account forms/dialogs and delayed read/write/status cannot repopulate cleared state. |
| 100 | restored foreign Company scope remains denied | PASS | [B], [X]: fresh restored sessions cannot access another Company configuration; checks precede receipts. |

[D]: ../adr/0027-planned-preparation-assignment.md
[M]: ../../apps/server/migrations/0025_planned_preparation_assignments.sql
[S]: ../../apps/server/test/preparation_assignment_integration_test.dart
[U]: ../../apps/server/test/preparation_assignment_location_uuid_test.dart
[X]: ../../apps/server/test/preparation_assignment_cases.dart
[C]: ../../packages/api_contracts/test/preparation_assignments_test.dart
[O]: ../../packages/api_contracts/test/preparation_assignment_openapi_test.dart
[F]: ../../apps/client_flutter/test/preparation_assignment_test.dart
[J]: ../../apps/server/test/preparation_assignment_journey_fixture.dart
[H]: ../../apps/client_flutter/integration_test/preparation_assignment_test.dart
[B]: ../../apps/server/tool/preparation_assignment_acceptance.dart
[R]: ../../apps/server/test/preparation_assignment_upgrade_recovery_test.dart
[V]: ../../scripts/preparation/Run-P413FinalVerification.ps1
[P]: phase-4-13-planned-preparation-assignments.md
