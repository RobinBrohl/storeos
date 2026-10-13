# P4.16 — File-level implementation plan and gates

Status: **SELECTED / DESIGN IN PROGRESS**, 2026-10-13. This is a plan, not
implementation authorization. All proposed new paths below are future targets;
none of the application, SQL, test or generated-contract files is created here.
Baseline: `8a0198f3430cb7ec636e952522dda7cf930b7fca`, migrations 0001–0027.
The [contract](phase-4-16-bilateral-shift-swaps.md) and
[ADR 0030](../adr/0030-bilateral-shift-consent-and-shared-handoff-claims.md) govern
scope. Recheck clean source and migration availability after authorization.

## Approved architecture baseline and F01 correction

The owner supplied the independent result **ARCHITECTURE APPROVE**. LOW,
nonblocking F01 identified an omitted private Workforce overlap repository in
Step 3. This finalization explicitly includes
`apps/server/lib/src/workforce/shift_repository.dart` and confines the final-roster
query behind the Workforce public owner port. F01 is **RESOLVED by documentation
correction**; no new targeted independent re-review is claimed. Capability and
approved interaction/invariants are unchanged. Database enforcement, runtime
grants, migration/backfill and acceptance remain **NOT IMPLEMENTED / NOT VERIFIED**.
Architecture approval does not authorize implementation.

## Dependencies and implementation order

| Step | Files to add/touch after authorization | Concrete work and exit gate |
| --- | --- | --- |
| 1. Strict transport and domain | New `packages/api_contracts/lib/src/shift_swaps.dart`; export in `packages/api_contracts/lib/api_contracts.dart`; new `apps/server/lib/src/workforce/shift_swap.dart` | Fixed lifecycle/versions, command-specific fields, immutable pair/summary/receipt DTOs and strict parsing. Domain rejects edits, wrong participant/stage and participant approval. Gate: contract/domain cases A02–A04; no generic workflow base class. |
| 2. Persistence and integrity | New `apps/server/migrations/0028_bilateral_shift_swaps.sql`; `apps/server/lib/src/infrastructure/migration_runner.dart`; new Workforce `shift_swap_repository.dart`, `shift_handoff_claim_repository.dart` | Five bounded tables, scoped anchors/FKs, claim hooks for both workflows, immutable guards, Tasks-owned SQL integrity functions, exact deferred completion/receipt/claim/time checks and runtime grants. Gate: populated 0027 preservation/backfill and late rollback, restricted grants and malformed SQL refusal (A14). No historical SQL edit. |
| 3. Public owner ports | New Workforce `shift_swap_service.dart`, `shift_handoff_claim_service.dart`; existing `workforce_service.dart`, `shift_transfer_service.dart`, `shift_transfer_repository.dart`, `apps/server/lib/src/workforce/shift_repository.dart`; `tasks/task_instance_service.dart`, `tasks/task_instance_repository.dart`; `identity/employee_links.dart`; `people/people_service.dart` only if a narrow scoped candidate projection is needed | Shared pending claims; a Workforce-owned overlap query in its private Shift repository excludes exactly the two persisted original Shift identities when evaluating the final exchanged roster, exposed only through the Workforce public owner port; captured links/Account-version eligibility, immutable source-work capture and Tasks-owned paired replacement/lineage. All receive caller TxSession. Gate: privacy/owner-scope, exact references and immediate overlap behavior. No foreign repository access or new employment model. |
| 4. One-way compatibility | `apps/server/lib/src/application/shift_transfer_application.dart` plus Step 2/3 hooks | Preserve all old command payloads/results/history/lineage; use shared busy authority and map conflict to existing transfer_already_pending. Gate: complete existing P4.11 tests plus observed cross-workflow races and legacy exact replay after release (A04/A07/A12/A14). |
| 5. Swap orchestration | New `apps/server/lib/src/application/shift_swap_application.dart`; existing Knowledge/Merchandising public ports as consumers | Request -> offer -> confirm -> independent approval; current auth before replay; validate both legs and final roster; cancel both before replacement publication; atomic receipts/audit/release. Existing `knowledge_guidance_port.dart` and `planogram_guidance_port.dart` should not need lifecycle changes. Gate: A01/A03/A05–A11, including second-leg/deferred failure injection. |
| 6. Permissions, audit and HTTP | `apps/server/lib/src/platform/platform_database.dart`, `audit_repository.dart`; new `http/shift_swap_routes.dart`; composition in `http/platform_app.dart` | Fixed capability entries/role grants, bounded identifier audit fields, strict authenticated endpoints, complete tested errors. Gate: A02/A12, parser 413/415 and dependency/integrity mapping; no route business logic. |
| 7. OpenAPI parity | New `packages/api_contracts/tool/shift_swap_openapi.dart`; bounded additions to `platform.openapi.json`, `openapi.yaml`; package README | Generate only implemented swap operations, DTOs and actual error sets; preserve existing operations. Gate: route/DTO/OpenAPI parity tests and release Flutter Web compile. These generated files stay unchanged in the design pass. |
| 8. Flutter Application/data | New `apps/client_flutter/lib/src/application/shift_swap_controller.dart`; `data/store_api.dart`, `http_store_api.dart`; `app/storeos_app.dart` composition | Deeply immutable session-bound pending intents, exact retry, owned candidates, original confirmation versus fresh detail, replacement fencing. Gate: A12/A13 and negative HTTP/controller cases; no business decisions in widgets. |
| 9. Employee/manager surfaces | New `apps/client_flutter/lib/src/ui/shift_swap_section.dart` and bounded pair/offer dialog as needed; `ui/shift_section.dart`, `platform_home_screen.dart` navigation | A request, B own offer, A exact confirmation, closure/history, manager both-leg approval and lineage, ordinary incoming-work execution. Gate: A01/A02/A13/A16; literal rendering, long labels and framework-exception failures. No general peer-roster tab. |
| 10. Recovery and final evidence | `apps/server/tool/backup_restore_fixture.dart`, `update_recovery_fixture.dart`; `scripts/backup/Run-BackupRestoreAcceptance.ps1`, `Assert-BackupAcceptanceReport.ps1`; `scripts/update/Run-UpdateRecoveryAcceptance.ps1`, `Assert-UpdateAcceptanceReport.ps1`; phase contract/acceptance record and current docs | Include new evidence/claims and populated historical fixtures; prove fenced restore, scoped replay/closure and forward update. Gate: A14/A15 plus existing recovery regressions. No normal database or normally served client assets used for acceptance. |

Steps 2–4 depend on the strict identity/state contract from Step 1. Step 5 depends
on exact claims and owner ports, not independently committed one-way operations.
HTTP/OpenAPI/Flutter depend on executable coordinator behavior and error sets.
Backup/restore coverage must include both workflows before final review/closure.
File decomposition may change only within these module owners and invariants.
Scope/consent changes need explicit reporting, not hidden implementation drift.

## Planned verification files

| Area | Proposed new tests / existing suites to retain |
| --- | --- |
| Wire/domain/OpenAPI | New `packages/api_contracts/test/shift_swaps_test.dart`, `shift_swap_evidence_test.dart`, `shift_swap_openapi_test.dart`; retain `shift_transfers_test.dart`, `shift_transfer_evidence_test.dart`, `shift_transfer_openapi_test.dart`. |
| PostgreSQL/HTTP | New `apps/server/test/shift_swap_test.dart`, `shift_swap_integration_cases.dart`, `shift_swap_safety_cases.dart`, `shift_swap_guidance_test.dart`, `shift_handoff_claim_test.dart`; retain existing `shift_transfer_test.dart`, integration/safety/guidance cases and ordinary Shift/Tasks suites. |
| Migration/restore | New `apps/server/test/shift_swap_migration_test.dart`, `shift_swap_upgrade_recovery_test.dart`; extend existing `shift_transfer_migration_test.dart` with populated active/stale/terminal preservation; retain Article quantity/count/Purchasing recovery tests. |
| Flutter/Chrome | New `apps/client_flutter/test/shift_swap_test.dart`, `shift_swap_http_journey.dart`, `apps/server/test/shift_swap_browser_test.dart`; retain `shift_transfer_test.dart`, `shift_transfer_http_journey.dart`, `apps/server/test/shift_transfer_browser_test.dart` and numeric Guided Work journeys. |

Use existing restricted PostgreSQL/Flutter/Chrome fixtures to exercise real
components; extend their constructed business data with both consented legs and
competing P4.11 records. Do not call constructed data authentic operator records.
Record an operator walkthrough of the exact pair review without collecting real
employee data unnecessarily. New tests must assert business invariants, not mirror
implementation or weaken existing assertions.

## Review and completion gates

1. **Authorization:** obtain separate implementation authorization; no code work
   starts from selection alone. Recheck baseline and new-migration number.
2. **Migration/compatibility:** populated backfill, exact shared occupancy, old
   receipt/history preservation, restrictive grants and rollback pass before
   depending on claims in live orchestration. Stop on contradictory old evidence.
3. **Functional integration:** execute every contract case A01–A16, with explicit
   test database/opt-ins, both ordinary incoming-work journeys and actual Chrome.
   Observed race/barrier evidence must distinguish before/after outcomes.
4. **Regression/build:** pinned format/analyzers, relevant and affected-package
   regression, release Web build, existing P4.11 and P4.15 regressions, numeric
   browser and backup/update wrappers. Report skips and unverified hardware.
5. **Independent reviews:** functional review of paired consent/privacy/claim
   migration/final schedule/replay; independent focused Security review of auth,
   cross-scope disclosure, receipt binding, grants, SQL NULL/UNKNOWN, backup and
   session fencing. Close required findings and re-review changed evidence.
6. **Publication/closure:** only after separately authorized commit/push/merge,
   verify successful exact implementation-commit CI. Record implementation,
   reviews, CI, acceptance and later documentation closure as separate facts.
   Never mark DONE from this plan or a successful subset.

## Readiness and retained limits

No dependency on Goods Receipt, POS, costing, availability/qualification engines,
notifications, remote access, offline queues or multi-site sync. Existing current
Employee assignment coverage is the eligibility boundary, not labor-law approval.
No new architectural blocker is identified. Claims/lineage/grants/time-boundary
proofs remain required implementation gates, not evidence already established.

Preserve P4.15's six qualifications and [technical debt](technical-debt.md), including
F04. M1 remains a proxied pilot gate; M3/M4 are contained per new endpoint rather
than globally fixed. Retention/offboarding/recovery/device operator gates remain.
This design introduces no cleanup project, dependency upgrade or adjacent feature.
