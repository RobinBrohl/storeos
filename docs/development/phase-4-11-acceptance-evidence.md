# P4.11 acceptance evidence map

Each requested criterion has an individual evidence locator. This map is part of the frozen source. Verdicts, exact counts and the source fingerprint are recorded after final verification in `.local/p411/final/acceptance.md`. Initial self-assessment was 177 PASS / 0 QUALIFIED / 0 FAIL; independent review returned CHANGES REQUIRED with 172 PASS / 4 QUALIFIED / 1 FAIL (F01/F02/F03). Bounded remediation is complete. Targeted review, security review and remote changed-commit CI remain pending. The development record preserves the review chronology.

The proof files are `apps/server/test/shift_transfer_{integration,safety}_cases.dart`, `shift_transfer_guidance_test.dart`, `shift_transfer_migration_test.dart`, `shift_transfer_browser_test.dart`, `apps/server/tool/shift_transfer_acceptance.dart`, `apps/client_flutter/test/shift_transfer_test.dart`, `apps/client_flutter/integration_test/shift_transfer_test.dart` and `packages/api_contracts/test/shift_transfer*_test.dart`. Production ownership and constraints are documented in ADR 0025 and the P4.11 development record.

| ID | Criterion | Evidence locator |
| --- | --- | --- |
| 1 | Workforce owns transfer request. | Workforce request/receipt owner; Tasks lineage owner ports |
| 2 | Tasks owns transfer links. | Workforce request/receipt owner; Tasks lineage owner ports |
| 3 | Stable request UUID. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 4 | Company-scoped request. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 5 | Location-scoped request. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 6 | Client cannot choose source Employee. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 7 | Source derives from current link. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 8 | Source Shift must belong to source Employee. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 9 | Recipient differs from source. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 10 | Recipient named exactly. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 11 | Recipient current eligibility checked at proposal. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 12 | Source Shift published. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 13 | Source Shift future at proposal. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 14 | Source Shift future at final approval boundary. | 0023 deferred transfer_approval_future clock_timestamp guard; observed final-audit barrier before-start success/cross-start complete rollback and UUID reuse |
| 15 | Every source Task pristine. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 16 | Proposal freezes source Shift version. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 17 | Proposal freezes interval. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 18 | Proposal freezes recipient. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 19 | Proposal freezes source/recipient linkage basis. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 20 | Proposal selections cannot change. | ShiftTransferApplication current scope/link/eligibility/future/pristine checks; transfer integration tests |
| 21 | Only one active request per source Shift. | 0023 transfer_active_source partial unique index; pending-request rejection |
| 22 | Recipient can accept. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 23 | Recipient can decline. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 24 | Source can withdraw proposed request. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 25 | Source can withdraw accepted request. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 26 | Recipient can withdraw accepted consent. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 27 | Manager can reject proposed. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 28 | Manager can reject accepted. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 29 | Only accepted can approve. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 30 | Approving Account differs from proposing Account. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 31 | Approving Account differs from accepting Account. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 32 | Acceptance alone changes no schedule. | shift_transfer.dart transition matrix; integration/safety tests; independent source/accepter approval denial |
| 33 | Approval rechecks source version. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 34 | Approval rechecks source lifecycle. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 35 | Approval rechecks pristine Tasks. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 36 | Approval rechecks recipient eligibility. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 37 | Approval rechecks recipient linkage. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 38 | Link replacement invalidates old consent. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 39 | Approval rechecks overlap. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 40 | Approval rechecks Knowledge eligibility. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 41 | Approval rechecks Planogram eligibility. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 42 | Approval never upgrades guidance pins. | _fresh/_bound validation; observed mutation races; exact guidance tests |
| 43 | Approval cancels source Shift. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 44 | Approval cancels source Tasks. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 45 | Approval creates one replacement Shift. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 46 | Replacement has new identity. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 47 | Replacement Employee = named recipient. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 48 | Replacement interval exactly matches source. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 49 | Replacement exact Template selections match. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 50 | Replacement exact Knowledge pins match. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 51 | Replacement exact Planogram pins match. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 52 | Replacement Tasks have new identities. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 53 | Every original Task gets exactly one replacement link. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 54 | Every replacement Task gets exactly one source link. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 55 | Source/replacement Task template revision matches. | Tasks replacement owner port; ten-Task correspondence and schema-4 exact pin tests |
| 56 | Approval is atomic. | Six injected approval-stage failures; full before/after request/Shift/Task/receipt/link/audit hashes |
| 57 | Fault after source cancellation rolls back. | Six injected approval-stage failures; full before/after request/Shift/Task/receipt/link/audit hashes |
| 58 | Fault during replacement creation rolls back. | Six injected approval-stage failures; full before/after request/Shift/Task/receipt/link/audit hashes |
| 59 | Fault during Task link persistence rolls back. | Six injected approval-stage failures; full before/after request/Shift/Task/receipt/link/audit hashes |
| 60 | Fault during audit rolls back. | Six injected approval-stage failures; full before/after request/Shift/Task/receipt/link/audit hashes |
| 61 | Original published work intact after failed approval. | Six injected approval-stage failures; full before/after request/Shift/Task/receipt/link/audit hashes |
| 62 | Approved request immutable. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 63 | Declined request immutable. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 64 | Withdrawn request immutable. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 65 | Rejected request immutable. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 66 | Terminal request cannot reopen. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 67 | Original Shift Employee identity never rewritten. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 68 | Original Task identities never rewritten. | 0023 immutability and scoped constraints; runtime role mutation/DELETE/TRUNCATE denial tests |
| 69 | Source loses executable original work after approval. | Real Flutter/Chrome replacement execution; source Home/history privacy checks |
| 70 | Recipient gains ordinary replacement work. | Real Flutter/Chrome replacement execution; source Home/history privacy checks |
| 71 | Source history does not expose recipient execution results. | Real Flutter/Chrome replacement execution; source Home/history privacy checks |
| 72 | Self participant access scoped. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 73 | Nonparticipant request access denied. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 74 | Manager Location scope enforced. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 75 | Registered nonconfigured Location denied. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 76 | Viewer denied. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 77 | Auditor operational access denied. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 78 | Plugin denied. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 79 | Recipient picker not general directory. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 80 | Request UUID guessing does not leak. | Current authorization/configured Location/participant tests; plugin denial; minimal picker tests |
| 81 | Proposal receipt durable. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 82 | Acceptance receipt durable. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 83 | Decline receipt durable. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 84 | Withdrawal receipt durable. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 85 | Rejection receipt durable. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 86 | Approval receipt durable. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 87 | Operation namespace Company+UUID. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 88 | Receipt binds actor. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 89 | Receipt binds Location. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 90 | Receipt binds request. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 91 | Receipt binds command kind. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 92 | Receipt binds expected version. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 93 | Receipt binds canonical payload. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 94 | Exact replay produces no duplicate effects. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 95 | Approval replay produces no second Shift. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 96 | Approval replay produces no duplicate Tasks. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 97 | Approval replay produces no duplicate Task links. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 98 | Approval replay produces no duplicate audit. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 99 | Conflicting UUID reuse rejected. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 100 | Current auth checked before replay. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 101 | Current Location checked before replay. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 102 | Participant/manager scope checked before replay. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 103 | Failed commands do not consume receipts. | All seven command-kind exact restart replays/conflicts; 21 restored receipts; Company+operation PK and canonical bindings |
| 104 | Strict duplicate JSON rejected. | All six HTTP write-family duplicate/escaped/unknown/malformed/overflow tests; bounded Unicode reason contract tests |
| 105 | Unicode-equivalent duplicate names rejected. | All six HTTP write-family duplicate/escaped/unknown/malformed/overflow tests; bounded Unicode reason contract tests |
| 106 | Unknown fields rejected. | All six HTTP write-family duplicate/escaped/unknown/malformed/overflow tests; bounded Unicode reason contract tests |
| 107 | Body bounds enforced. | All six HTTP write-family duplicate/escaped/unknown/malformed/overflow tests; bounded Unicode reason contract tests |
| 108 | Reason bounds enforced. | All six HTTP write-family duplicate/escaped/unknown/malformed/overflow tests; bounded Unicode reason contract tests |
| 109 | Keyset pagination bounded. | 52-request history and 60-unlinked/52-eligible picker tests; scoped bounded keyset cursors |
| 110 | Cursor Company scoped. | 52-request history and 60-unlinked/52-eligible picker tests; scoped bounded keyset cursors |
| 111 | Cursor Location scoped. | 52-request history and 60-unlinked/52-eligible picker tests; scoped bounded keyset cursors |
| 112 | Employee cursor identity scoped. | 52-request history and 60-unlinked/52-eligible picker tests; scoped bounded keyset cursors |
| 113 | Filtering precedes pagination. | 52-request history and 60-unlinked/52-eligible picker tests; scoped bounded keyset cursors |
| 114 | Session replacement clears transfer state. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 115 | Delayed responses fenced. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 116 | Pending commands session-bound. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 117 | Uncertain command exact retry only. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 118 | Confirmed result/current detail separated. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 119 | Literal rendering. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 120 | No HTML/Markdown execution. | All-kind session replacement/uncertain command tests; widget literal rendering; Chrome resource inspection; immutable evidence contracts |
| 121 | Audit atomic. | Audit allowlist and application minimal metadata; final-audit injected rollback |
| 122 | Audit excludes instruction bodies. | Audit allowlist and application minimal metadata; final-audit injected rollback |
| 123 | Audit excludes free-text reasons. | Audit allowlist and application minimal metadata; final-audit injected rollback |
| 124 | Runtime grants narrow. | 0023 runtime grants/immutable guards/scoped FKs; runtime mutation tests; no SECURITY DEFINER |
| 125 | Receipts immutable. | 0023 runtime grants/immutable guards/scoped FKs; runtime mutation tests; no SECURITY DEFINER |
| 126 | Task links append-only. | 0023 runtime grants/immutable guards/scoped FKs; runtime mutation tests; no SECURITY DEFINER |
| 127 | Terminal evidence protected. | 0023 runtime grants/immutable guards/scoped FKs; runtime mutation tests; no SECURITY DEFINER |
| 128 | No new SECURITY DEFINER unless justified. | 0023 runtime grants/immutable guards/scoped FKs; runtime mutation tests; no SECURITY DEFINER |
| 129 | No Stock write. | Real journey nonempty Stock/Count/Recipe/PreparationBatch hash conservation; owner-port-only application effects; no events/outbox |
| 130 | No Stock Count write. | Real journey nonempty Stock/Count/Recipe/PreparationBatch hash conservation; owner-port-only application effects; no events/outbox |
| 131 | No Recipe write. | Real journey nonempty Stock/Count/Recipe/PreparationBatch hash conservation; owner-port-only application effects; no events/outbox |
| 132 | No PreparationBatch write. | Real journey nonempty Stock/Count/Recipe/PreparationBatch hash conservation; owner-port-only application effects; no events/outbox |
| 133 | No events/outbox. | Real journey nonempty Stock/Count/Recipe/PreparationBatch hash conservation; owner-port-only application effects; no events/outbox |
| 134 | Source amendment vs approval deterministic. | Observed PostgreSQL Company advisory lock queues, both amendment/cancel/execution/overlap/link orders |
| 135 | Source cancellation vs approval deterministic. | Observed PostgreSQL Company advisory lock queues, both amendment/cancel/execution/overlap/link orders |
| 136 | Source execution vs approval deterministic. | Observed Company-lock execution-first/approval-first evidence plus final-audit barrier success while future, cross-start rollback and historical replay after start |
| 137 | Recipient overlap vs approval deterministic. | Observed PostgreSQL Company advisory lock queues, both amendment/cancel/execution/overlap/link orders |
| 138 | Link change vs approval deterministic. | Both observed orders: source/recipient revocation and Employee deactivation, source Account deactivation; source/recipient replacement-Account link creation and same-Account relinking after L1 revocation (both reject; no atomic replacement endpoint), complete failed/successful transfer evidence |
| 139 | Guidance change vs approval deterministic. | Both observed orders: Knowledge publication/retirement, Fixture retirement, Planogram revision publication/replacement deployment; exact old pins, full failed-effect hashes, successful lineage/receipt/audit and duplicate-free replay |
| 140 | Approval/withdrawal deterministic. | Observed source/recipient withdrawal and rejection queues, both orders |
| 141 | Approval/rejection deterministic. | Observed source/recipient withdrawal and rejection queues, both orders |
| 142 | Clean 0001→0023 migration passes. | Clean migration fixtures; populated actual 0022 data/catalog preservation; late failure and real 0023 application |
| 143 | Populated 0022→0023 preserves P4.10 evidence. | Clean migration fixtures; populated actual 0022 data/catalog preservation; late failure and real 0023 application |
| 144 | Populated migration preserves Stock/Count. | Clean migration fixtures; populated actual 0022 data/catalog preservation; late failure and real 0023 application |
| 145 | Populated migration preserves Tasks/guidance. | Clean migration fixtures; populated actual 0022 data/catalog preservation; late failure and real 0023 application |
| 146 | Failed 0023 rollback complete. | Clean migration fixtures; populated actual 0022 data/catalog preservation; late failure and real 0023 application |
| 147 | Backup preserves request states. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 148 | Backup preserves receipts. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 149 | Backup preserves Shift lineage. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 150 | Backup preserves Task links. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 151 | Restored participant auth correct. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 152 | Restored manager auth correct. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 153 | Restored Location denial correct. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 154 | Restored replay correct. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 155 | Restored plugin/session fencing correct. | Encrypted backup/restore and update/recovery; all states/kinds/lineage; participant/manager/replay/scope/session/plugin/runtime fencing |
| 156 | Real Flutter→HTTP→PostgreSQL approval journey passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 157 | Real recipient Guided Work on replacement passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 158 | Decline journey passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 159 | Withdrawal journey passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 160 | Manager rejection passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 161 | Overlap rejection passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 162 | Stale source rejection passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 163 | Unavailable guidance rejection passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 164 | Exact approval replay after restart passes. | Actual Flutter controllers and Chrome production HTTP/PostgreSQL journey, all terminal/failed-approval paths and restarted approval replay |
| 165 | Existing Shift amendment/cancel remains green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 166 | Task schemas 1–4 remain green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 167 | Guided Work regressions green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 168 | Knowledge regressions green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 169 | Planogram regressions green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 170 | Stock/Count hashes unchanged. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 171 | Recipe regressions green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 172 | PreparationBatch regressions green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 173 | Existing Chrome regressions green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 174 | Full final-source regression green. | Run-P411FinalVerification.ps1 complete frozen-source regression, release Web/Compose, explicit host/browser/numeric and recovery phases |
| 175 | Documentation says review/security/CI pending. | P4.11 development record, HANDOVER, actual status and README pending-review/security/CI state |
| 176 | No P4.12 capability added. | Scoped source diff and ADR 0025; no P4.12 implementation |
| 177 | Normal StoreOS database untouched by verified acceptance. | Run-owned Compose project/database isolation; cleanup inventory; stopped normal StoreOS services |
