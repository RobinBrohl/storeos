# Current technical debt

Living disposition register, reconciled 2026-10-04 against source baseline `93072a4`.
The [2026-10-04 audit](project-health-audit-2026-10-04.md) preserves original
findings F01–F19; the [2026-10-02 report](milestone-health-check-2026-10-02.md)
preserves M1–M4/L1–L12 at its old baseline. Product and operator decisions belong
in [risks/open questions](../risks-and-open-questions.md).

**ACTIVE** means unresolved, **CLOSED** requires actual evidence, **DEFERRED**
has a stated trigger. Documentation correction does not close a runtime defect.

## Closed P4.3 acceptance findings

P4.3 is **DONE/CLOSED**. These six findings are resolved by acceptance correction
`f9c8b070f870cabbba3ae7b63bf16190b46aad8e`, independent targeted review **APPROVE**,
**28/28 PASS**, and fully green
[CI run 37199144795](https://github.com/RobinBrohl/storeos/actions/runs/37199144795).
The [phase closure](phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04)
records review provenance and preserves the original audit and CHANGES REQUIRED history.

| ID | State | Resolution evidence |
| --- | --- | --- |
| F01 | CLOSED — `f9c8b07`, review APPROVE, CI green | [StockController](../../apps/client_flutter/lib/src/application/stock_controller.dart) acquires the synchronous guard before validation/UUID creation; immutable actor/session/location/level identity survives navigation and uncertainty. Initial replacement fencing failed independent review R1; the accepted follow-up publishes session changes immediately and checks live identity at request/result boundaries. Held-status regressions pass. |
| F06 | CLOSED — `f9c8b07`, review APPROVE, CI green | [Stock fake/tests](../../apps/client_flutter/test/stock_test.dart) check committed replay/conflicting identity before new-command version/no-op semantics. Committed late replay and unused stale conflict have distinct regressions; movements and audit effects are counted. |
| F07 | CLOSED — `f9c8b07`, review APPROVE, CI green | Dialog uses typed outcomes, retains invalid/failed input, applies shared note bounds and locks uncertain payloads. It auto-closes only for confirmed mutation/replay/no-op; confirmed refresh failure requires acknowledgement and cannot offer write retry. |
| R1 (HIGH) | CLOSED — `f9c8b07`, review APPROVE, CI green | Same-account and different-actor replacement while status is held pending invalidate local retries immediately; old results/failures and old dialog content are fenced. The new regression failed before the fix and passes after it. |
| R2 (MEDIUM) | CLOSED — `f9c8b07`, review APPROVE, CI green | Stock HTTP 413/415 body-parser failures return definitive rejection with no pending retry or location lock; controller/widget regressions pass. |
| R3 (LOW) | CLOSED — `f9c8b07`, review APPROVE, CI green | Local abandonment has a separate decision-required state and explicitly unknown commit wording; no server rejection is claimed. Explicit reload remains required before a new correction. |

The server guards versions and strict movement identity. F01 demonstrates unreliable
client reconciliation in the original audit, not silent ledger overwrite or duplicate
stock corruption. The earlier documentation pass made no code correction; the
subsequent committed correction and accepted closure are recorded in the
[P4.3 phase follow-up](phase-4-3-manual-stock.md). No further P4.3 remediation is
required absent regression. Memory-only recovery and raw runtime-role SQL outside
supported-writer semantics remain accepted limitations, not reopened findings.

## Final P4.4 finding dispositions

P4.4 Local Planogram Execution is **DONE/CLOSED**. Implementation `cd7669ed`,
bounded remediation, independent targeted **APPROVE** and fully green
[CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802)
at portability-fix commit `73dca5a4` establish closure; no P4.4 remediation is active
absent regression. These P4.4 IDs are separate from the older findings below.

| ID | Final disposition | Evidence / retained boundary |
| --- | --- | --- |
| P4.4 F01 MEDIUM | CLOSED | Optional Stock failure isolation preserves assigned instructions; typed unavailable/absent/zero context, real permission-outage HTTP/PostgreSQL/Flutter journeys, targeted APPROVE and green CI. |
| P4.4 F02 MEDIUM | CLOSED | Reachable 404 response sets are documented and matched by all-20 configured-Location and missing-origin HTTP regressions; targeted APPROVE and green CI. M3 remains endpoint-contained, not globally closed. |
| P4.4 F03 MEDIUM | ACCEPTED LIMITATION / NON-BLOCKER | Database scope/ownership, append-only Assignment and immutable published content remain protected. Supported Assign guarantees atomic insertion/current/latest pointer/Fixture version/audit advancement; arbitrary runtime SQL can deliberately select the same Fixture's older Assignment without advancing version. Revisit before another writer or stronger raw-SQL guarantees. |
| P4.4 F04 INFO | QUALIFIED BASELINE EVIDENCE / NON-BLOCKER | 0001–0015 retain identical Git content; 0016 is new. Historical raw checkout-byte fingerprints are unavailable; known CRLF representations in 0005/0007/0008/0009 are baseline qualification, not a P4.4 defect. No old migration was normalized or rewritten. |

The [final closure](phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04)
preserves the CHANGES REQUIRED review, remediation, APPROVE and failed CI history.
Physical printer/device/accessibility and operator gates remain separate.

## P4.5 LOW non-blocking follow-ups

P4.5 Approved Operational Knowledge is **DONE/CLOSED**: independent adversarial
review **APPROVE**, **60/60 PASS** and green exact-implementation CI establish
[closure](phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04).
No active P4.5 remediation remains. These slice-specific findings are retained
follow-ups, not commit blockers; neither was implemented during closure.

| ID | Final disposition | Consequence / follow-up trigger |
| --- | --- | --- |
| P4.5 F01 | LOW — NON-BLOCKING FOLLOW-UP; commit blocker NO | Mounted Knowledge search text may survive session replacement although controller query state resets. Security/session dispatch and stale-response fencing remain correct. On relevant Knowledge UI touch, reset the mounted search controller on identity change and add a mounted-widget replacement regression. |
| P4.5 F02 | LOW — NON-BLOCKING FOLLOW-UP; commit blocker NO | Checked-in browser workflow passes, but literal-rendering/executable-element assertions could be stronger and more self-contained. Production plain-text behavior was independently verified. On browser acceptance touch, persist literal-rendering and absence-of-content-created executable/link-element assertions, including image-handler/entity cases. |

The accepted raw-runtime-SQL/supported-writer boundary, memory-only uncertain-command
recovery, physical-device/accessibility gaps and operator gates remain unchanged.

P4.6 implementation evidence (2026-10-04): its new contextual Task instruction
browser test asserts literal script/link/image-handler/Markdown text, absence of
payload-created link/image/script elements and no payload execution in actual Chrome.
This strengthens the new consumer surface; it does not globally close P4.5 F02 or
alter the untouched mounted Knowledge search follow-up F01. M3/M4 are contained
locally through explicit contextual response sets and named-constraint error mapping;
unexpected integrity failures remain 500, supported infrastructure failures 503.
P4.6 F01 remediation (2026-10-05): the original independent CHANGES REQUIRED review
found one LOW commit blocker in the selection/publication error contract. Draft
create/replacement now uses `guidance_selection_unavailable`; only fresh publication
uses `guidance_unavailable`. OpenAPI inventories the actual touched responses; clone
and exact replay retain their prior behavior. F01 is **CLOSED** by bounded remediation,
targeted review **APPROVE**, **64/64 PASS**, focused Codex Security **SECURITY APPROVE**
and all five jobs green in [changed-commit CI 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549).
P4.6 is **DONE/CLOSED**, with no active remediation. This F01 is distinct from the
still-open P4.5 mounted standalone search follow-up. Global M3/M4 remain open.

## P4.7 closed delivery findings

P4.7 is **DONE/CLOSED** at `ccfa3df`, with **80/80 PASS** and all five jobs successful
in [changed-commit CI 37377829784](https://github.com/RobinBrohl/storeos/actions/runs/37377829784). Initial independent **CHANGES REQUIRED** identified LOW
F01 (unreachable selector 409) and F02 (incomplete backup acceptance evidence).
Both are CLOSED after bounded remediation and targeted **APPROVE**. The backup
finding established incomplete evidence, not restore corruption.

Separate Codex Security **SECURITY CHANGES REQUIRED** found LOW/CWE-863 Security F01,
configured management/Template work-Location scope omission. Explicit runtime
Location authorization now precedes retained reads/enrichment and committed replay;
supplied targeted re-review returned **SECURITY APPROVE**. No cross-Company or employee
IDOR vulnerability was established. No active P4.7 remediation or security commit
blocker remains. See [closure history](phase-4-7-task-planogram-guidance.md#final-documentation-closure--2026-10-05).

M1's proxy/login-limiter pilot gate, closed M2, local containment of M3, broader M4,
P4.5 LOW F01/F02 follow-ups, accepted supported-writer/raw-SQL boundary, memory-only
uncertain-command recovery and physical-device/accessibility/operator gaps retain
their existing dispositions. P4.7's literal Chrome surfaces strengthen local evidence
without closing unrelated global debt.

## Original medium findings

| ID | State | Current disposition / trigger |
| --- | --- | --- |
| M1 / F02 | ACTIVE | [HTTP login](../../apps/server/lib/src/http/server_app.dart), [limiter](../../apps/server/lib/src/application/login_limiter.dart): raw socket IP groups proxied clients. Decide/test mitigation before proxied real users; trusted-proxy parsing must enforce trust, not accept arbitrary headers. Shared limiter state also needed before multiple API processes. |
| M2 | CLOSED | [Migration 0012](../../apps/server/migrations/0012_published_shift_amendment.sql), [ADR 0014](../adr/0014-pre-execution-shift-interval-amendment.md), populated upgrades/raw constraint/race evidence. Published overlap has database exclusion enforcement. Old deferred wording is historical. |
| M3 / F03 | ACTIVE, contained | [OpenAPI](../../packages/api_contracts/platform.openapi.json) and [root contract](../../packages/api_contracts/openapi.yaml): error catalog/statuses and full router consistency gate still incomplete. Every added route needs matching DTO/OpenAPI, explicit tested errors and negative HTTP cases; broader cleanup before external API/SDK consumers. Manual 88-operation parity is not an automatic gate. |
| M4 / F04 | ACTIVE | Broad constraint errors → 400, unmatched route shape, plugin-limit read/write statuses. Carry to endpoint/error-observability work; address before promising a uniform external error contract. |
| F05 | CLOSED in the earlier documentation pass | That pass recorded committed P4.3 with then-open acceptance, bounded interval amendment and ledger; vision/history and CI baselines were separated. P4.3 acceptance is now closed by the evidence above; F10 and unrelated runtime findings stay open. |

## Low and bounded findings

| ID | State | Current consequence / trigger |
| --- | --- | --- |
| L1 / F11 | ACTIVE | PluginService **and IdentityService** read OrganizationRepository. Replace with narrow public ports on relevant module touch; do not extend the shortcut. |
| L2 / F11 | ACTIVE | Six application/Workforce DB-clock query sites remain. Introduce a narrow transaction-time helper on coordinator touch; preserve database-time authority. |
| L3 / F11 | ACTIVE | Session/plugin expiry creation uses app clock, validation DB clock. Align when identity/plugin code changes. |
| L4 / F12 | DEFERRED | Company-wide admin shift reads vs configured-location execution paths. Resolve before multi-location execution/scoped roles; other named Locations already exist. |
| L5 / F12 | DEFERRED | Unscoped existence/receipt probes, with downstream actor/company checks. Scope before a shared-schema multi-Company writer model. Current deployment is one Company per installation. |
| L6 / F13 | CLOSED in touched P4.4 harnesses | P4.4 masks configured raw/URI/Base64 secret representations, Bearer tokens and PostgreSQL URLs in both touched harness failure tails. The actual diagnostic functions pass 10 assertions across both runners; report-redaction checks remain green. Independent review APPROVE and green changed-commit CI complete the bounded acceptance; see [closure](phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04). |
| L7 / F14 | CLOSED | P4.4 adds four real PostgreSQL refusal cases for unknown applied migration, non-prefix, invalid filename and empty SQL, proving pending SQL is not applied. Existing checksum/rollback checks remain green. Independent review APPROVE and green changed-commit CI complete acceptance; see [closure](phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04). |
| L8 | CLOSED in this documentation pass | [Module boundaries](../architecture/module-boundaries.md) now explicitly says no shift/task integration events exist; event examples are future contracts. |
| L9 / F17 | DEFERRED | Organization setup is emittable but not subscribable; no current consumer needs it. Revisit subscription catalog on actual demand. |
| L10 / F15 | ACTIVE on touch | Coordinator/UI density, raw-map parsing, safety fixture duplication and DDL column whitelists. Split/share only with demonstrated need; recheck whitelists for future columns. |
| L11/L12 / F17 | DEFERRED | Plain result/blocking pairing is insert-time; execution receipts use runtime grants rather than an all-role immutability trigger. No supported-writer anomaly demonstrated. Re-prove before second writers or company-lock narrowing. |
| F08 | ACTIVE | [AuthStore readiness](../../apps/server/lib/src/infrastructure/auth_store.dart) checks migrations 0001–0004, not current full binary schema. Migrate-before-start mitigates; correct on deployment/health automation touch without automatic runtime DDL. |
| F09 | ACTIVE on touch | Article/Assortment/Stock filter controls remount empty while retained query filters data. Keep view/controller state coherent on relevant UI touch. |
| F10 | ACTIVE / partial correction committed `f9c8b07` | Stock opening-note OpenAPI descriptions now state required key / nullable value; schema and decoder unchanged. Published-shift UI prohibition copy remains outside this correction. |
| F16 | ACTIVE acceptance gap | No physical device/new goods UI accessibility acceptance; agree supported hardware and verify it before device/pilot claims. |
| F17 legacy versions | DEFERRED | Older expected-version paths lack consistent Web-safe upper bounds. Carry on relevant contract touch; no realistic version-growth failure demonstrated. |
| Recovery-verify transients | OPEN evidence gap | [P4.1 evidence](phase-4-1-article-master.md) records two non-injected recovery-verify failures followed by passing reruns without explained root cause. Revisit when the harness is next exercised; do not reclassify them as capacity injections or claim universal flake-free recovery. |

## Other retained debt and gates

P4.4 review F03 is an **accepted supported-writer limitation**, distinct from the
older M3/F03 API debt above. The current-assignment composite FK protects Fixture,
Company and Location ownership, but arbitrary runtime SQL can repoint a Fixture
to its own older Assignment without advancing version. Only the supported Assign
writer guarantees atomic evidence/pointer/version/audit and exact late replay.
No “latest assignment against arbitrary SQL” guarantee is claimed. Revisit before
adding another writer or strengthening that threat model; [ADR 0018](../adr/0018-local-planogram-execution.md)
and [P4.4 evidence](phase-4-4-local-planograms.md) preserve the independent probe.

Company-wide serialization remains deliberate; narrow it only with measured target
hardware contention and renewed last-admin/revocation/race/evidence proofs. Client
sessions and pending commands are memory-only; persistent offline queues require
a separate contract. Optional unused dependency housekeeping and unpinned
container/action reproducibility remain deferred; no upgrades are implied.

F18 is an operator gate before relevant real-data use: retention/access/export/deletion,
offboarding, RPO/RTO, backup-key custody, off-host restore/activation and devices.
F19 gates future stock effects/margins: explicit source units/machine actor,
provenance, physical cutover, returns/production policy and trustworthy cost basis.
Basic sales ingestion can preserve unresolved effects without inventing these rules.

Earlier proposals for self-password change, M2 exclusion and interval amendment
are SUPERSEDED by implemented slices. The old P4.3-uncommitted baseline is
SUPERSEDED by `e8ce8c3`. Historical review/CI runs remain scoped to their named commits.

## P4.8 closed review gates and accepted limits

Selected-article Stock counts are DONE/CLOSED: bounded F01–F04 remediation is
complete, targeted independent review returned APPROVE, final product acceptance
is 124/124 PASS, focused Codex Security returned SECURITY APPROVE and all five
jobs in [exact-commit CI 37453860163](https://github.com/RobinBrohl/storeos/actions/runs/37453860163) succeeded.
No active P4.8 remediation remains. The original F01–F03 LOW blockers and F04
INFO restore evidence gap remain historical closed findings, not active debt.
F04 was an evidence gap, not a production authorization defect. Count routes contain unexpected database integrity
failures locally as sanitized 500 and known operational failures as 503; this does not
close broad M3/M4. Memory-only uncertain command tracking ends on reload/session
replacement; durable receipts remain authoritative. This accepted limitation is
not a closure blocker. Physical-device/accessibility gaps and the supported-writer
boundary remain. See [slice](phase-4-8-stock-counts.md).

## P4.9 closed review gates and accepted limits

Approved Article Recipe / Composition (composition only) is **DONE/CLOSED** at
`e5e6d5c2999bb9f8132161b43ad1537aa403973c`: initial independent CHANGES REQUIRED,
bounded F01–F05 remediation, supplied targeted APPROVE, **151 PASS / 1 QUALIFIED /
0 FAIL**, supplied focused **SECURITY APPROVE** (zero confirmed/probable
vulnerabilities, zero required fixes, no security commit blocker) and all five jobs
green in [exact-commit CI 37581798736](https://github.com/RobinBrohl/storeos/actions/runs/37581798736).
No active P4.9 remediation remains; the [closure record](phase-4-9-recipe-compositions.md#final-documentation-closure--2026-10-07)
preserves chronology and evidence.

| Finding | Current disposition |
| --- | --- |
| F01 MEDIUM product defect | CLOSED: initial-draft discard recovery allocates the next empty draft under the same active Recipe identity; no number reuse. |
| F02 MEDIUM product defect | CLOSED: authoritative reconciliation clears stale transient snapshots and preserves/display-saves exact server-frozen content. |
| F03 LOW product defect | CLOSED: opt-in Recipe write parsing rejects duplicate decoded JSON names, including escaped equivalents, as bounded 400 invalid_json. |
| F04 LOW documentation/contract defect | CLOSED: all 13 operations retain precise reachable error contracts; global M3/M4 are not reopened or closed by this work. |
| F05 MEDIUM test/evidence gap | CLOSED: nonempty approved Count/observation/recount/correction/zero-variance evidence and all seven Stock/Count hashes are preserved across populated 0020→0021 and Recipe workflow. |
| F06 INFO | ACCEPTED DESIGN / NON-BLOCKER: Company + operation UUID namespace; independent Companies may reuse UUIDs. |
| F07 INFO / criterion 152 | ACCEPTED EVIDENCE LIMITATION / NON-BLOCKER: verified runs used disposable databases; universal historical normal-database proof cannot be reconstructed. Criterion 152 remains the only QUALIFIED item, no product/security defect or active remediation. |

Memory-only uncertain-command recovery, supported-writer/raw-SQL boundaries,
physical-device/accessibility gaps, M1 pilot gate, M2 CLOSED, M3 endpoint containment,
M4 broader error taxonomy and P4.5 F01/F02 nonblocking follow-ups remain unchanged.
P4.10 Preparation Batch is DONE/CLOSED; P4.11 remains UNSELECTED. Next is fresh P4.11 capability selection from clean main.

## P4.10 closed review gates and retained limits

Preparation Batch is **DONE/CLOSED** at implementation
`e637187b17d4617212acf42b99a07500e9488c3d`: initial independent CHANGES REQUIRED,
bounded F01/F02 remediation, targeted APPROVE, nonblocking F03 docs follow-up
CLOSED, **156 PASS / 0 QUALIFIED / 0 FAIL**, focused SECURITY APPROVE and all five
jobs green in [exact-commit CI 37632074236](https://github.com/RobinBrohl/storeos/actions/runs/37632074236).
No active P4.10 remediation remains.

| Finding | Final disposition |
| --- | --- |
| F01 MEDIUM product defect | CLOSED: confirmed command evidence is separate from authoritative current detail; failed refresh clears stale effective counts and blocks further correction until reload. |
| F02 MEDIUM test/evidence gap | CLOSED: source/restored R1 Batch context after R2 publication and Recipe retirement proves own/manager access, standalone exclusion and other-Employee denial. |
| F03 LOW documentation follow-up | CLOSED, nonblocking: current status/test-count references reconciled while historical implementation and review evidence remains labeled. |

M1 proxy/login-limiter pilot gate, M2 CLOSED, M3 local API/error containment,
M4 broader taxonomy, supported-writer/raw-SQL limits, memory-only uncertain-command
recovery, physical-device/accessibility gaps, P4.5 F01/F02 nonblocking follow-ups
and P4.9 criterion 152 historical evidence qualification retain their dispositions.
No zero-debt or broader production-readiness claim is made.
