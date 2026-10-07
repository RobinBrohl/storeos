# P4.10 hard acceptance criterion evidence

P4.10 is **DONE/CLOSED**. Each supplied criterion is assessed separately below: **156 PASS / 0 QUALIFIED / 0 FAIL**. This implementation evidence ledger is complemented by targeted independent **APPROVE**, focused **SECURITY APPROVE** and all five jobs green in [exact-commit CI 37632074236](https://github.com/RobinBrohl/storeos/actions/runs/37632074236). F01/F02 remediation and nonblocking F03 documentation follow-up are **CLOSED**.

The initial 156/156 self-assessment preceded independent **CHANGES REQUIRED** for
F01 (MEDIUM product defect) and F02 (MEDIUM evidence gap). Bounded remediation is
complete; targeted review returned APPROVE. Focused Security and exact-commit CI subsequently passed.
Every retained criterion below is reassessed against unchanged reviewed core and
the final-source run. In particular, 50/53/145 now include failed-refresh zero and
2 → 1 evidence, blocked stale corrections and authoritative reload; 140 now includes
source/restored R1 after different published R2 and retirement; 153 requires the
remediation's complete frozen-source regression. Final evidence records 156 PASS / 0 QUALIFIED / 0 FAIL,
931 package tests (including 350 Flutter package tests) and 19/19 final phases PASS. See the development record for chronology and sanitized reports.

Paths and suite details are in [the development record](phase-4-10-preparation-batches.md). Final evidence is `.local/p410/final/summary.json`, source manifests and phase logs.

| # | Criterion | Evidence |
| --- | --- | --- |
| 1 | Production owns PreparationBatch. | Production domain/repository + migration composite keys; identity/pin integration case and independent journey SQL checks |
| 2 | Batch UUID stable. | Production domain/repository + migration composite keys; identity/pin integration case and independent journey SQL checks |
| 3 | Batch Company-scoped. | Production domain/repository + migration composite keys; identity/pin integration case and independent journey SQL checks |
| 4 | Batch Location-scoped. | Production domain/repository + migration composite keys; identity/pin integration case and independent journey SQL checks |
| 5 | Opening derives current Employee server-side. | Self-isolation/current-linkage/configured-Location integration case; strict unknown-authority contract cases; opening journey SQL actor assertions |
| 6 | Opening derives current Account server-side. | Self-isolation/current-linkage/configured-Location integration case; strict unknown-authority contract cases; opening journey SQL actor assertions |
| 7 | Client cannot choose executing Employee. | Self-isolation/current-linkage/configured-Location integration case; strict unknown-authority contract cases; opening journey SQL actor assertions |
| 8 | Route Location must equal configured Location. | Self-isolation/current-linkage/configured-Location integration case; strict unknown-authority contract cases; opening journey SQL actor assertions |
| 9 | Employee must be currently eligible at Location. | Self-isolation/current-linkage/configured-Location integration case; strict unknown-authority contract cases; opening journey SQL actor assertions |
| 10 | Fresh opening requires Recipe active. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 11 | Fresh opening requires exact current published RecipeRevision. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 12 | Fresh opening rejects stale prior publication selection. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 13 | Produced Article must be active. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 14 | Produced Article must be effectively assorted at Location. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 15 | Ingredient Articles must be active. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 16 | Ingredient current units must match frozen Recipe units. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 17 | Fresh unit mismatch rejects with zero open effects. | Fresh opening service gates + deterministic two-order Recipe/Article/Assortment/ingredient/unit opening races; zero-effect rejected-open checks |
| 18 | Existing open Batch retains exact Recipe revision after replacement. | Exact-pin replacement/retirement integration case, self context isolation and real HTTP/Chrome retained R1 journey |
| 19 | Existing open Batch retains exact Recipe after retirement. | Exact-pin replacement/retirement integration case, self context isolation and real HTTP/Chrome retained R1 journey |
| 20 | Existing open Batch retains exact Recipe after Article changes. | Exact-pin replacement/retirement integration case, self context isolation and real HTTP/Chrome retained R1 journey |
| 21 | Contextual Recipe read derives Recipe/revision from Batch evidence. | Exact-pin replacement/retirement integration case, self context isolation and real HTTP/Chrome retained R1 journey |
| 22 | Historical Recipe UUID alone grants no contextual access. | Exact-pin replacement/retirement integration case, self context isolation and real HTTP/Chrome retained R1 journey |
| 23 | Planned count optional. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 24 | Planned count integer only. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 25 | Planned accepted range 1..9999. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 26 | Actual completion required. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 27 | Completion count integer only. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 28 | Completion range 1..9999. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 29 | Zero cannot complete. | 40 strict count/shape contract cases + persisted null/1/9999 plans, completed 9999 and invalid/zero completion boundary cases |
| 30 | Open lifecycle starts version 1. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 31 | Completion transitions open→completed only. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 32 | Employee cancellation transitions open→cancelled only. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 33 | Manager cancellation transitions open→cancelled only. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 34 | Terminal lifecycle cannot reopen. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 35 | Completed cannot be cancelled. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 36 | Cancelled cannot be completed. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 37 | Manager cannot proxy-complete. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 38 | Completion stores original actual count immutably. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 39 | Completion stores completing Account. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 40 | Completion stores server timestamp. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 41 | Cancellation stores actor. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 42 | Cancellation stores server timestamp. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 43 | Cancellation requires reason. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 44 | Terminal Recipe/Employee/Location pin immutable. | Domain lifecycle + migration CHECK/immutable guards; six terminal races, cancellation replay and no-proxy-completion authorization case |
| 45 | Manager correction is append-only. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 46 | Correction does not rewrite original completion. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 47 | Correction numbers contiguous. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 48 | Correction previous count matches prior effective count. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 49 | Correction replacement range 0..9999. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 50 | Correction zero supported explicitly. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 51 | Correction zero does not change completed lifecycle. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 52 | Original completion remains visible after correction. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 53 | Current effective count derives from correction chain. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 54 | Employee cannot append correction. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 55 | Only manager capability can correct. | Serialized correction test + original/effective count and separate zero journey; integrity probes and employee correction denial |
| 56 | Concurrent corrections cannot lost-update. | Deterministic competing-corrections integration case; one winner, contiguous chain and original receipt replay |
| 57 | Open has durable command receipt. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 58 | Complete has durable command receipt. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 59 | Employee cancel has durable command receipt. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 60 | Manager cancel has durable command receipt. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 61 | Correction has durable command receipt. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 62 | Operation namespace Company + UUID. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 63 | Receipt binds actor. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 64 | Receipt binds Location. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 65 | Receipt binds batch. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 66 | Receipt binds command kind. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 67 | Receipt binds canonical payload. | Five durable command receipt paths; actor/kind/resource/payload conflict test; eleven persisted/restored receipts across all five kinds |
| 68 | Exact open replay creates no second batch. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 69 | Open replay works after Recipe retirement. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 70 | Completion replay returns original completion. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 71 | Completion replay after correction still returns original completion. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 72 | Cancellation replay creates no duplicate effect. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 73 | Correction replay creates no duplicate correction. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 74 | Conflicting operation reuse rejected. | Exact-pin/replay and immutable cancellation/conflict cases; service restart replay and recovery replay of all eleven receipts |
| 75 | Current authorization checked before replay. | Self-isolation/current-linkage/Location integration case; authorization before receipt lookup; other Employee detail/context/replay denial |
| 76 | Current Location scope checked before replay. | Self-isolation/current-linkage/Location integration case; authorization before receipt lookup; other Employee detail/context/replay denial |
| 77 | Employee A cannot access Employee B batch. | Self-isolation/current-linkage/Location integration case; authorization before receipt lookup; other Employee detail/context/replay denial |
| 78 | Employee A cannot replay Employee B command. | Self-isolation/current-linkage/Location integration case; authorization before receipt lookup; other Employee detail/context/replay denial |
| 79 | Manager history Location-scoped. | Configured-Location/self/role denial tests, all eleven plugin route denials, contextual Recipe capability gate and no manager-complete operation |
| 80 | Viewer denied. | Configured-Location/self/role denial tests, all eleven plugin route denials, contextual Recipe capability gate and no manager-complete operation |
| 81 | Auditor denied. | Configured-Location/self/role denial tests, all eleven plugin route denials, contextual Recipe capability gate and no manager-complete operation |
| 82 | Plugin denied. | Configured-Location/self/role denial tests, all eleven plugin route denials, contextual Recipe capability gate and no manager-complete operation |
| 83 | Manage does not grant proxy completion. | Configured-Location/self/role denial tests, all eleven plugin route denials, contextual Recipe capability gate and no manager-complete operation |
| 84 | Batch read does not grant general historical Recipe browsing. | Configured-Location/self/role denial tests, all eleven plugin route denials, contextual Recipe capability gate and no manager-complete operation |
| 85 | No StockLevel writes. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 86 | No StockMovement writes. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 87 | No StockCount writes. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 88 | No TaskTemplate schema change. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 89 | No Task guidance pin. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 90 | No Shift mutation. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 91 | No events/outbox. | Production dependency/SQL boundary inspection; unchanged seven nonempty Stock/Count table hashes in HTTP/Chrome journey; no Task/Shift/outbox writes |
| 92 | Opening audit atomic. | Five injected audit-failure rollback cases, failed-operation reuse and exact atomic audit/receipt/business counts |
| 93 | Completion audit atomic. | Five injected audit-failure rollback cases, failed-operation reuse and exact atomic audit/receipt/business counts |
| 94 | Cancellation audit atomic. | Five injected audit-failure rollback cases, failed-operation reuse and exact atomic audit/receipt/business counts |
| 95 | Correction audit atomic. | Five injected audit-failure rollback cases, failed-operation reuse and exact atomic audit/receipt/business counts |
| 96 | Audit failure rolls back business command. | Five injected audit-failure rollback cases, failed-operation reuse and exact atomic audit/receipt/business counts |
| 97 | Audit/logs exclude Recipe text. | Audit metadata whitelist + exact metadata content-exclusion assertions; HTTP logs emit path/status/timing rather than request text |
| 98 | Audit/logs exclude free-text reasons/notes. | Audit metadata whitelist + exact metadata content-exclusion assertions; HTTP logs emit path/status/timing rather than request text |
| 99 | Strict duplicate JSON names rejected. | Strict decoded escaped-name duplicate/body/unknown-field/numeric lexical integration case; bounded Unicode evidence-text contracts |
| 100 | Unicode-equivalent duplicate JSON names rejected. | Strict decoded escaped-name duplicate/body/unknown-field/numeric lexical integration case; bounded Unicode evidence-text contracts |
| 101 | Unknown fields rejected. | Strict decoded escaped-name duplicate/body/unknown-field/numeric lexical integration case; bounded Unicode evidence-text contracts |
| 102 | Transport bound enforced. | Strict decoded escaped-name duplicate/body/unknown-field/numeric lexical integration case; bounded Unicode evidence-text contracts |
| 103 | Notes/reasons bounded. | Strict decoded escaped-name duplicate/body/unknown-field/numeric lexical integration case; bounded Unicode evidence-text contracts |
| 104 | Own pagination bounded. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 105 | Manager pagination bounded. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 106 | Cursor Company-scoped. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 107 | Cursor Location-scoped. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 108 | Self cursor Employee-scoped. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 109 | Malformed cursor bounded. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 110 | Employee list filtered before pagination. | Bounded keyset integration case: 51 rows, 50+1 pages, pre-pagination Employee/status filtering and tampered/malformed cursor rejection |
| 111 | Session replacement clears resident batch state. | 18 remediation-focused Flutter tests: session replacement, delayed read/POST fencing, five immutable exact retries, pending-operation UI restrictions and failed-refresh correction evidence |
| 112 | Delayed old-session responses fenced. | 18 remediation-focused Flutter tests: session replacement, delayed read/POST fencing, five immutable exact retries, pending-operation UI restrictions and failed-refresh correction evidence |
| 113 | Pending command bound to session. | 18 remediation-focused Flutter tests: session replacement, delayed read/POST fencing, five immutable exact retries, pending-operation UI restrictions and failed-refresh correction evidence |
| 114 | Uncertain command exact retry only. | 18 remediation-focused Flutter tests: session replacement, delayed read/POST fencing, five immutable exact retries, pending-operation UI restrictions and failed-refresh correction evidence |
| 115 | Literal browser rendering. | Literal Recipe/reason Flutter widget assertions + real Chrome injection/external-resource checks |
| 116 | Recipe replacement/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 117 | Recipe retirement/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 118 | Article deactivation/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 119 | Assortment/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 120 | Ingredient deactivation/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 121 | Ingredient unit/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 122 | Employee deactivation/open race atomic. | Deterministic two-order Company-lock fresh-open races for publication, retirement, Article, Assortment, ingredient/unit and Employee eligibility |
| 123 | Complete/cancel races atomic. | Six ordered complete/employee-cancel/manager-cancel terminal races; exactly one terminal winner |
| 124 | Correction/correction race atomic. | Queued competing corrections with same expected latest number; exactly one winner and no lost update |
| 125 | Runtime grants narrow. | Runtime and owner integrity probes, narrow table/column grants, immutable terminal/correction/receipt checks and no SECURITY DEFINER catalog assertion |
| 126 | Terminal evidence protected. | Runtime and owner integrity probes, narrow table/column grants, immutable terminal/correction/receipt checks and no SECURITY DEFINER catalog assertion |
| 127 | Correction rows append-only. | Runtime and owner integrity probes, narrow table/column grants, immutable terminal/correction/receipt checks and no SECURITY DEFINER catalog assertion |
| 128 | Receipt rows immutable. | Runtime and owner integrity probes, narrow table/column grants, immutable terminal/correction/receipt checks and no SECURITY DEFINER catalog assertion |
| 129 | No SECURITY DEFINER added unless explicitly justified. | Runtime and owner integrity probes, narrow table/column grants, immutable terminal/correction/receipt checks and no SECURITY DEFINER catalog assertion |
| 130 | Clean migration 0001→0022 passes. | Clean migration chain + populated actual 0021 late-failure 0022 test; deterministic all-legacy-table and catalog/ACL preservation hashes |
| 131 | Populated 0021→0022 preserves Recipe evidence. | Clean migration chain + populated actual 0021 late-failure 0022 test; deterministic all-legacy-table and catalog/ACL preservation hashes |
| 132 | Populated 0021→0022 preserves Stock/Count evidence. | Clean migration chain + populated actual 0021 late-failure 0022 test; deterministic all-legacy-table and catalog/ACL preservation hashes |
| 133 | Populated 0021→0022 preserves Tasks/guidance. | Clean migration chain + populated actual 0021 late-failure 0022 test; deterministic all-legacy-table and catalog/ACL preservation hashes |
| 134 | Failed 0022 rollback complete. | Clean migration chain + populated actual 0021 late-failure 0022 test; deterministic all-legacy-table and catalog/ACL preservation hashes |
| 135 | Backup preserves Batch evidence. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 136 | Backup preserves receipts. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 137 | Backup preserves correction chain. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 138 | Restored Employee authorization correct. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 139 | Restored manager authorization correct. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 140 | Restored contextual Recipe access correct. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 141 | Restored replay correct. | Encrypted backup/restore acceptance: five batches, eleven receipts, two corrections; restored self/manager/other-Employee/context authorization and exact original replay |
| 142 | Revoked sessions/plugin fencing preserved. | Existing revoked-session/plugin recovery probes + eleven preparation plugin route denials and current-authorization-before-replay tests |
| 143 | Real Flutter/HTTP/PostgreSQL journey passes. | Opt-in real Flutter controller / normal HTTP / PostgreSQL preparation journey with server restart and independent SQL verification |
| 144 | Real Chrome P4.10 workflow passes. | Opt-in actual Chrome preparation journey through employee and manager Flutter UI |
| 145 | Correction-zero acceptance passes. | Separate originally completed one -> corrected zero fixture; API/SQL original one, effective zero, completed lifecycle and explicit Flutter/Chrome UI |
| 146 | Count boundary acceptance passes. | Persisted null/1/9999 plans, completion 1/9999, correction 0/1/9999 and rejected boundary/type inputs |
| 147 | Self-authorization acceptance passes. | Other Employee list/detail/context/complete/cancel/replay isolation integration case and restored authorization probes |
| 148 | Location authorization acceptance passes. | Wrong configured-Location denial before evidence/replay; Company/Location cursor binding and local manager routes |
| 149 | Historical Recipe authorization acceptance passes. | Context derives exact pin only after current batch + Recipe capability authorization; unrelated historical UUID never used as an access grant |
| 150 | Stock/Count hashes unchanged by Batch workflow. | Independent deterministic hashes of seven seeded nonempty Stock/Count tables before/after batch commands, restart and replay |
| 151 | Existing Recipe workflow remains green. | Existing Recipe PostgreSQL/contract regression plus dedicated Recipe HTTP and actual Chrome journeys |
| 152 | Existing Chrome regressions remain green. | Dedicated Knowledge, Task-Knowledge, Task-Planogram and Stock Count Chrome journeys; numeric and print browser checks |
| 153 | Full final-source regression green. | Frozen-source final runner: 931 package passes (including 350 Flutter package tests), nine conditional hosts explicitly exercised, four clean analyzers/formatters, release Web/Compose and recovery/tools |
| 154 | Documentation remains pending review/security/CI (historical implementation gate). | PASS: documentation was pending review/security/CI at implementation; targeted APPROVE, SECURITY APPROVE and exact-commit CI 37632074236 now establish DONE/CLOSED; F03 stale documentation follow-up CLOSED |
| 155 | No P4.11 capability added. | Evidence-only scope and public dependencies; no yield, consumption, produced Stock, Task pin, Shift/Workforce, offline queue or sync additions |
| 156 | Normal StoreOS database untouched by verified acceptance runs. | Strict run-owned disposable database wrappers and recovery runners; normal database is never used for migration or business acceptance writes |
