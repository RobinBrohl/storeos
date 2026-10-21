# Q13/Q5 authentication regression closure — 2026-10-21

**Q13/Q5 AUTHENTICATION REGRESSION — CLOSED.** The owner separately authorized
this administrative documentation closure after the independent verdict:
**APPROVE — Q13/Q5 subgate eligible for separately authorized documentation closure.**
No blocking findings or material evidence gaps remain within this narrow scope.
This uncommitted documentation candidate still requires independent documentation
review and separate publication authorization. Option B remains mandatory.

## Exact subgate and retained limits

The closed subgate demonstrates that plugin credentials and unauthorized sessions
cannot access protected core Article/Stock quantity endpoints. It includes exact
safe denials, unchanged persisted business/receipt/audit/outbox evidence, authorized
Admin controls and fresh session authorization before exact replay. It does not
establish executable plugin integration, plugin-specific operational readiness or
broader third-party runtime isolation. The scoped plugin organization control
establishes token issuance/revocation, not execution of plugin code.

All ten endpoint templates below are relative to `/api/v1/platform`:

| Article endpoints | Stock endpoints |
| --- | --- |
| `GET /articles/{id}/quantity` | `GET /locations/{id}/stock/{id}/quantity` |
| `GET /articles/{id}/quantity/history` | `GET /locations/{id}/stock/{id}/quantity/evidence` |
| `POST /articles/{id}/quantity/configure` | `POST /locations/{id}/stock/{id}/quantity/bind` |
| `POST /articles/{id}/quantity/replace` | `POST /locations/{id}/stock/{id}/quantity/preview` |
| `POST /articles/{id}/quantity/suspend` | `POST /locations/{id}/stock/{id}/quantity/correct` |

Correction uses independent nonzero and zero-delta resources: eleven primary
scenarios. Approved/revoked plugin tokens, missing Authorization, malformed/unknown
bearers and logged-out sessions receive 401; a valid viewer without the required
capabilities receives 403; authorized Admin controls receive 200. Denial bodies
are exactly `{"code":"unauthorized","message":"Authentication required."}` or
`{"code":"forbidden","message":"Access denied."}`. Complete projections across
nine persistence/audit/outbox tables remain unchanged on denial. Positive controls
verify durable receipts, permitted effects, one minimized audit, unchanged outbox
and effect-free exact replay. Zero-delta correction preserves balance, version and
movements while retaining its receipt/audit.

## Source, independent review chronology and actual execution

Repository: `RobinBrohl/storeos`. The approved
[test commit](https://github.com/RobinBrohl/storeos/commit/86296c46bdef256a960f8b9667fe3c19af9b264f)
is `86296c46bdef256a960f8b9667fe3c19af9b264f`.
[PR #7](https://github.com/RobinBrohl/storeos/pull/7) merged at
`39c51a60fc9b84d685d53e7cb0962f9e5d8083b2` on 2026-10-21 19:26:03 UTC.
Its parents are baseline `f5a285f991ec872b6cce6b18bf83cf9acfc7c512` and the approved
test commit. Approved and merged trees both equal
`d09bf1fd2ae39e1696d822b0740bb80cbfefda6e`; the only addition over baseline is
[`apps/server/test/article_quantity_authentication_test.dart`](https://github.com/RobinBrohl/storeos/blob/39c51a60fc9b84d685d53e7cb0962f9e5d8083b2/apps/server/test/article_quantity_authentication_test.dart),
1,029 lines, 29,863 bytes. Exact raw SHA-256:
`6F56E7ED20F72EBD809807C91D8684A0F9D685C3868BD3ED0E69291898567A36`.

The following sequence preserves the original scope and timing of approval. All
entries are dated 2026-10-21; times are UTC. Private review locators identify the
original task and immutable final message, not a newly performed review.

| Order | Independent disposition / evidence | Original locator |
| --- | --- | --- |
| 1 — 10:19:02; reaffirmed 10:19:23 | **Q13/Q5 INDEPENDENT CODE REVIEW — APPROVE FOR SEPARATELY AUTHORIZED EXECUTION**; no blocking source finding, runtime proof still pending then | “Review Q13/Q5 auth denial tests”; task `01a15df3-f536-73e2-92b6-1026af450d7d`, report message `msg_0eb7dc12060c7d8e016ad8916584848191a97e228213788448` |
| 2 — 10:27:54–10:29:59 | Dedicated execution PASS, independent evidence review pending at execution time | Original `Report.md` and `execution-result.json` in the retained packet below |
| 3 — 10:41:32 | **Q13/Q5 INDEPENDENT EXECUTION EVIDENCE REVIEW — APPROVE FOR GATE CLOSURE**; 31 PASS / 0 FAIL / 0 SKIP, 27 manifest entries verified | “Verify Q13/Q5 execution evidence”; task `01a15e08-700c-71b3-a088-c3b1db225593`, message `msg_06ecfc5bdca7fc62016ad896bc259c8191bd9676be744e0996` |
| 4 — before the 19:26:03 merge | Independent integration **APPROVE**, supplied by the owner; accepted with that provenance and independently corroborated by the final gate review | Owner authorization for this closure; PR #7 exact commit/file/hash and CI. No separate repository integration-review report or precise review timestamp is claimed |
| 5 — 19:26:03 onward | Separately authorized merge; successful exact-main CI completed by 19:54:20 | PR #7 and run 39661599286 below; merge verification is distinct from independent project-gate approval |
| 6 — 20:02:53 | **APPROVE — Q13/Q5 subgate eligible for separately authorized documentation closure.** | “Review Q13/Q5 gate closure”; task `01a1600b-8631-7680-b889-e60a55c53865`, message `msg_0e450f485f31ed16016ad91a53a7988191bcd1a172e2839e59` |
| 7 — subsequent owner authorization | Administrative closure of this authentication regression subgate only | Owner's “StoreOS P4.16 Option B — Q13/Q5 Documentation Closure” instruction; this dated addendum records that decision |

The dedicated wrapper selected authentication (1), quantity integration (12),
platform HTTP smoke (1) and platform security integration (17): **31 PASS / 0 FAIL /
0 SKIP**. Nonwriting format and analyzer checks passed. The successful awaited
authentication lifecycle completed **119 matrix requests + 31 prerequisite quantity
requests**. These requests belong to one registered authentication test; they are
not 150 separately registered tests. The HTTP trace and successful assertions have
different evidentiary roles: request/status sequences versus body/persistence checks.

[Main-CI 39661599286](https://github.com/RobinBrohl/storeos/actions/runs/39661599286)
is a completed successful **push to main, attempt 1**, at exact merge
`39c51a60fc9b84d685d53e7cb0962f9e5d8083b2`. All five jobs succeeded:
`dart` (119435729468), `flutter` (119435729206), `numeric-guided-work-e2e`
(119435729859), `backup-restore-acceptance` (119435729250), and
`update-recovery-acceptance` (119435729335).
The [Dart log](https://github.com/RobinBrohl/storeos/actions/runs/39661599286/job/119435729468)
records the exact checkout, explicitly marks the Q13/Q5 test PASS at 19:47:54 UTC
and ends with **1,070 server PASS / 0 FAIL / 23 SKIP**. Q13/Q5 was not skipped.
These are implementation/integration results; no CI for this uncommitted
documentation candidate is claimed. No functional tests were rerun for this change.

## Retained artifacts and access

Execution evidence remains at the original machine-local root
`C:/dev/storeos/.local/p416-q13q5-execution-20261021/`. It is ignored by Git and is
not available in an ordinary public clone. Reviewers need the original packet or
a separately authorized, hash-verified copy. No credential-bearing raw logs are
published. Exact artifact identities (SHA-256) include:

| File in the original execution packet | SHA-256 |
| --- | --- |
| `Report.md` | `B14E13149A74181327ECE4004316BD763B441CBA5C761396C5B28AD44610DDB6` |
| `before-file-hashes.json` | `58A0BD772E787333C9753DBF64DB8248B6BDD3AE89986F26EFB70FE52A75A086` |
| `validation-sanitized.log` | `247AF00C8CE3C9E4B3CDCC3EAC1DC24F0751EC43286685DA6B2CE572B390E7D2` |
| `q13-http-trace.json` | `8BF7FCBD9D82DAAF9E5156868C1AA1917A681AC185416C80F31B016E958830D6` |
| `reconciliation.json` | `BCE0CA7E790EFABCFEF902A010020990EFCB03A3F425EE6316641E0F9D873B6A` |

All **27 entries** in `before-file-hashes.json` were rechecked against the original
checkout: zero mismatches. All **13 retained execution artifacts** remain present
and unchanged. In addition to the five above, these are `before-containers.txt`,
`after-containers.txt`, `before-git-status.txt`, `after-git-status.txt`,
`disposable-container.json`, `execution-result.json`, `format.log`, and
`test-progress.log`. Accepted evidence establishes disposable-resource/secret cleanup;
the diagnostic observation below remains visible.

The new worktree's ignored `.local/q13q5-documentation-closure-20261021/` packet
contains source/API verification, selected CI log lines, original review-message
exports with their task/turn/message identities, original-checkout fingerprints,
the complete candidate diff and documentation verification. These are reconciliation
records, not new independent approvals. The original review messages remain the
authority. Historical reports and evidence were neither edited nor replaced.

## Accepted nonblocking INFO observations

| Observation | Accepted disposition |
| --- | --- |
| Original execution report still says evidence review pending | Preserve it verbatim; the later independent approval above supersedes only its pending status |
| `EnvironmentRestored: false` in `execution-result.json` | Preserve PowerShell null-to-empty diagnostic and accepted fresh-process absence/cleanup verification; no unresolved credential or resource cleanup gap |
| Aggregated plugin-control trace includes concurrent companion-suite traffic | Attribute plugin issuance/revocation using the Q13-specific raw-log sequence, not aggregate control totals |
| Awaited matrix stops on failure | Only a completed successful lifecycle proves the full matrix; failed/interrupted runs leave later cases unattempted. Accepted execution and Main-CI completed successfully |

## Current register reconciliation and remaining gates

| Gate / qualification | Current disposition |
| --- | --- |
| Q13/Q5 authentication regression | **CLOSED** within the exact subgate above |
| Full P4.15 Q5 — plugin-specific execution | **OPEN / remaining operational requirements unproven**; executable plugin integration, plugin-specific readiness and broader runtime isolation are not established |
| Q13 overall | **OPEN**; inherited Q1–Q4/Q6 and remaining Q5 requirements retain their individual qualifications and owner decisions |
| Q03–Q10 | **OPEN**; no independent closure under their own procedures is asserted. Q05 off-host backup is unrelated to P4.15 Q5 |
| P4.16 | **IN PROGRESS**; Option B remains mandatory; final phase closure is not authorized |
| P4.17 | **UNSELECTED** |
| Pilot / production readiness | **NOT APPROVED** |

P4.15's historical **7 PASS / 6 QUALIFIED / 0 FAIL**, historical 21 opt-ins, current
23 server skips, Q03's **0 PASS / 2 FAIL, NOT RERUN** and INSUFFICIENT EVIDENCE,
F04 Location-picker debt and all other historical findings remain unchanged.
Quantity controller/Chrome and quantity upgrade/recovery invocations skipped in
Main-CI remain skipped. This addendum supplies no broader security, resilience,
device, privacy, operator or deployment qualification.

The authoritative Q13 register was found only in the original uncommitted
[`phase-4-16-closure-candidate.md`](phase-4-16-closure-candidate.md). Its original raw
SHA-256 is `51760352BC09366852EA11338A8CD3486EC7833B37232A541DECA71CE0A22926`.
This documentation worktree preserves that entire source as a historical snapshot
and prepends a dated current Q13 reconciliation. The original file remains untouched.
Its broader P4.16 candidate has not thereby been approved or closed; the other 24
modified documentation paths were not imported. Original `.local` evidence links
in the snapshot resolve against `C:/dev/storeos/`, as explicitly recorded there.

Next: independently review this exact documentation diff, register provenance,
evidence hashes, chronology and retained boundaries. After APPROVE, obtain separate
owner authorization for a narrowly scoped documentation commit/publication and its
exact-revision CI. No staging, commit, push, PR, merge, deployment, other gate closure
or P4.17 selection is performed by this reconciliation.
