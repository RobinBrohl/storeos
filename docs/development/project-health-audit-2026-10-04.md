# Project health and vision-drift audit — 2026-10-04

Historical record of the comprehensive audit performed earlier in this conversation
against `main` at `e8ce8c319e2dd3051b402d252a0666f33b170fa3`.
This document captures that report; creating it did not rerun the checks.
It is not an independent approval or current-head remote CI result.

**Verdict: HEALTHY WITH TARGETED REMEDIATION.** No CRITICAL or HIGH defect was
demonstrated. No rewrite is justified. The principal immediate defect is the
manual-stock client retry identity, accompanied by dialog/mock-test gaps.

## Evidence and limits

| Check | Result in the preceding audit |
| --- | --- |
| Dart/Flutter tests | 453 passed: 69 contracts, 201 server (including real PostgreSQL and 20 stock cases), 181 Flutter, 2 design-system. |
| Format/analyzers | 174 Dart files, zero format changes; all four package analyzers clean. |
| Web | Release build with `--no-pub --no-web-resources-cdn` passed. |
| Operator regression checks | Six PowerShell crypto/setup/diagnostics/report-redaction checks passed; Compose quiet validation passed. |
| Local documentation links | 391 path references checked, zero missing; anchors/external URLs not covered by that check. |
| Database isolation | Unique audit test database created and removed; normal StoreOS database untouched. |
| Not freshly run | Numeric browser E2E (no configured matching ChromeDriver), full backup/restore and update/recovery wrappers (unconditional dependency resolution conflicted with no-install scope), target-hardware capacity and physical device/accessibility acceptance. |
| Remote evidence | No current-head remote CI verification. Existing phase/CI statements remain baseline-specific historical evidence. |

Reviewed local historical reports included update run `17dfc81e405b4b9a`
(2026-10-03, populated upgrade through 0015 and stock probes), backup run
`a9c793eec38b46e3` (2026-10-01), and successful capacity runs
`0fb83227327047b5` / `eb17283a3fcd4d93`. Reports are under ignored `.local/`
and are not committed artifacts or proof of current-head CI. Explicit capacity
negative-path injections were expected refusals, not spontaneous production failures.

## Findings captured from the audit

| ID | Severity | Finding / original disposition |
| --- | --- | --- |
| F01 | MEDIUM | Stock adjustment replaces pending movement identity before the busy guard; duplicate dialog submission plus lost response/read-back failure can retain an unsent ID. Correct before P4.3 acceptance. |
| F02 | MEDIUM | M1: login limiter groups proxied users by proxy socket IP. Real-user proxy gate. |
| F03 | MEDIUM | M3: API errors under-specified and no global router/OpenAPI drift gate. Current manual inventory matches 88 operations (83 platform JSON + 5 root YAML); contain every new route, broaden before external consumers. |
| F04 | MEDIUM | M4: broad SQLSTATE 23514 → 400, unmatched router response shape and plugin-limit status inconsistency. Correct on relevant endpoint/error work. |
| F05 | MEDIUM | Live docs claimed stock uncommitted, omitted current ledger/amendment and mixed vision/history. Documentation reconciliation needed. |
| F06 | LOW | Stock mock accepts a stale-version retry under another mutation unlike the real service; correct with F01. |
| F07 | LOW | Stock dialog unconditionally closes after a void-returning adjustment, losing invalid input/failure context. Correct with F01. |
| F08 | LOW | Readiness verifies only early platform migrations 0001–0004. Carry to deployment/health automation touch. |
| F09 | LOW | Article/Assortment/Stock filter text resets on remount while controller query remains. Carry to affected UI touch. |
| F10 | LOW | Shift UI copy still says no published edits; Stock OpenAPI describes a required-nullable note as optional. Separate code/contract corrections needed. |
| F11 | LOW | L1–L3: Plugin/Identity foreign repository reads, six application-layer DB-clock queries and application-clock expiry vs DB validation. Carry on touch. |
| F12 | LOW | L4/L5: location-scope divergence and global-ID probes. Resolve before broader location execution/shared-schema tenancy; no current cross-company leak demonstrated. |
| F13 | LOW | L6: backup/update diagnostic tails not masked like capacity; JSON-report checks do not prove tail redaction. No observed secret disclosure. |
| F14 | LOW | L7: targeted migration refusal branch coverage absent. Carry to runner/harness touch. |
| F15 | LOW | L10: large coordinators/UI, fixture duplication and DDL column whitelists. Maintain on touch; no speculative rewrite. |
| F16 | LOW | Physical-device/accessibility acceptance absent for new goods UIs; no specific layout defect demonstrated. |
| F17 | INFO | Setup event not subscribable; evidence pairing/receipt immutability depend partly on supported-writer/grant discipline; legacy version bounds. Defense-in-depth triggers before second writers/lock narrowing. |
| F18 | INFO | Operator retention/access/export/offboarding/recovery/device decisions required before relevant real-data pilot. |
| F19 | INFO | Stock source/unit/cutover/return/production/cost contracts needed before future effects/margins, not before canonical sales ingestion. |

F01 evidence: `stock_controller.dart` assigns the new pending command before
`_run` checks busy; `stock_section.dart` submit is not disabled while awaiting
and always pops the dialog. The server's receipt lookup precedes the version
guard and preserves strict identity; no silent ledger overwrite was shown.
Source paths and current dispositions are in [technical debt](technical-debt.md).

## Vision reconciliation

Local-first ownership, typed public ports and atomic evidence remain appropriate.
Add approved Wiki revisions, generic Fixtures/Planogram revisions and assignments,
Article + versioned Recipe, structured Menu/explicit public publishing, configurable
Roles/grants, bounded Boards/Chat, human-approved swaps and context-restricted remote
self-service to the long-term product definition. These are not existing features.

Canonical external-POS sales ingestion should be available independently of a
StoreOS-owned checkout. Ingestion, mapping/health, physical stock effects and
margin calculation have separate prerequisites. This does not authorize a new
implementation. See [vision](../vision.md) and [roadmap](../roadmap/phases.md).

## Follow-up

The original audit requested documentation reconciliation and focused F01/F06/F07
remediation. [Technical debt](technical-debt.md) tracks subsequent disposition;
this dated finding table preserves the original assessment. The older
[2026-10-02 health check](milestone-health-check-2026-10-02.md) remains intact at
its original baseline and is not the live status source.
