# P4.16 Stage B3a — Flutter Application/data

## B3A-01 local remediation — 2026-10-16

**B3A-01 FIXED LOCALLY; independent targeted re-review pending.** The current
independent verdict remains **STAGE B3a CHANGES REQUIRED**, for **B3A-01 HIGH**.
The implementation author does not independently close the finding or approve
B3a. **P4.16 remains IN PROGRESS.** Step 9 UI/browser work and Step 10 recovery
are not implemented by this remediation.

### Reviewed baseline and preservation

The independent report is
`C:/Users/Robin/.codex/visualizations/2026/10/16/01a1461c-d074-75b1-a4bf-3762e19ef65d/b3a-review/Review.md`.
Before editing, its `before.json`/`after.json`, all nine reviewed source hashes,
all 29 migration SHA-256/Git blob fingerprints, and all eighteen associated
artifact hashes matched. The original report, fixtures, logs and snapshots were
read and preserved unchanged. The exact original nine-path inventory and hashes
remain in the historical implementation record below and in those independent
snapshots. The review report SHA-256 is
`82B6EC29835CBBA773088959B0CC76548D6783C355DB019B08F6D43470C0F93C`;
the original reproducer SHA-256 is
`E68D29152A5C818729035023FBB852229926F080918E4D014FF3D87866B95D33`.

Branch remains `codex/p416-b3a-flutter-application`, HEAD and cached origin/main
remain `c55c87c91e5c44b4f2dbc080f8ba1790d5f0fca2`. The Git index was and remains
empty. The historical B2 branch and older local main are preserved as described
below. Migrations 0001–0029 remain byte/Git-content identical to the reviewed
baseline. No integrated backend, HTTP route, contract, OpenAPI, dependency,
lockfile, Session/Transfer controller or UI change was made.

### Reproduced race and correction

The unmodified independent deterministic harness was run before implementation
changes: **37 PASS / 8 FAIL**, exactly the eight reported B3A-01 cases. The race
was at the synchronous completion callback, rather than only at the network wait:

1. An immutable uncertain offer or approval command belongs to binding A.
2. `reconcile()` reads an empty authorized history page under A and records the
   unresolved-outcome error.
3. Its `finally` clears `_submitting` and calls `_notify()`.
4. A listener replaces context/Location or expires the session; `_contextChanged`
   changes the binding and clears pending/private state.
5. The old reconciliation resumes after `finally` and unconditionally assigns
   its previously captured command to `_pending`, then notifies again.

This restored original private pair/work evidence and left the controller locked
with a command whose obsolete binding could not be retried. The same trailing
assignment was reachable after caught receipt failures. Early identity guards
did not protect a write after a reentrant completion notification. A return
computed before `finally` could also report an obsolete submission outcome after
the completion callback had fenced that operation.

The correction keeps the existing complete `_SwapBinding` (opaque session/context,
Account, Company, Location and lifetime checks) and adds a controller-local
submission generation. Retry/reconciliation capture their original command and
generation; a newer attempt, context/session invalidation or disposal invalidates
the old owner. Reconciliation additionally checks that it still owns the exact
captured pending object before dispatch/receipt processing. `_confirm` receives
the same ownership predicate for accepted evidence and fresh-detail publication.

Both unresolved and caught-error paths now finish pending/error state **before**
the completion notification. `finally` changes busy state only for its current
owner; no private-state write follows that notification. The returned outcome is
checked again afterward. A listener may start a legitimate explicit retry or
reconciliation; its new pending/submitting state is not overwritten or unlocked
by the older completion. Disposal clears residual cursor/message/busy state.
An already-invalid binding is not republished on unrelated platform busy-state
notifications, preventing obsolete swap notifications after invalidation.

The required context-load investigation also reproduced **17 failing assertions**
on the original source: held `/context` or `/organization` initialization, and
replacement during context publication. A session-only epoch did not detect
same-session authorization/Location replacement. `PlatformController` now fences
initialization with its existing opaque context identity, checks before dispatch
and after awaits, and retains the exact identity published **before** listeners
run. It never adopts a newer reentrant identity as the old load's authority.
Explicit context assignment/invalidation always publishes a new identity.
Obsolete initialization cannot replace newer context, organization or errors.
Its exclusively owned busy flag is released without changing unrelated controller
epochs. No global invalidation scheme was added.

### Original eight cases, before and after

The original reviewer fixture was not edited. It was rerun unchanged against the
corrected implementation; all **45 independent probes PASS**, including these
eight cases. The final-source focused run also includes all 45.

| Mode / command | Completion-listener invalidation | Before | Corrected |
| --- | --- | --- | --- |
| Employee / offer | Same-scope context replacement | FAIL | PASS |
| Employee / offer | Viewer / permission removal | FAIL | PASS |
| Employee / offer | Foreign Location | FAIL | PASS |
| Employee / offer | Session expiry | FAIL | PASS |
| Manager / approval | Same-scope context replacement | FAIL | PASS |
| Manager / approval | Viewer / permission removal | FAIL | PASS |
| Manager / approval | Foreign Location | FAIL | PASS |
| Manager / approval | Session expiry | FAIL | PASS |

Every corrected original boundary reports `fenced`, `oldPendingRestored=false`
and `locked=false`. Expired/denied/foreign contexts have no inherited pending or
private evidence. Same-scope replacement remains usable for independently
authorized fresh reads.

### Permanent regressions and legitimate behavior

`test/shift_swap_reconciliation_test.dart` adds **151 deterministic cases**:

- 24 reentrant completion cases: both modes, four original invalidations, and
  absent, denied or throwing receipt lookup.
- 56 held-receipt cases: both modes across expiry, logout, same/different Account,
  Location, context-generation replacement and disposal, with accepted, denied,
  malformed or throwing delayed responses. Assertions cover cleared private
  state/cursors/actionability, no lock, no unauthorized retry, no obsolete
  notification, and preservation of legitimate newly loaded evidence.
- 6 overlap/ownership cases: double reconciliation, exact retry while reconciling,
  and completion listeners explicitly starting a new retry/reconciliation.
- 8 submission-completion cases: confirmed, rejected, uncertain and later-denied
  attempts in both modes recheck their owner after notification.
- 17 context-initialization cases: both modes and held context/organization
  responses after same-scope, denied, foreign-Location or null replacement, plus
  a reentrant context-publication callback. Obsolete loads neither reverse
  invalidation nor emit stale swap notifications.
- 40 replay-preservation cases: every one of eight internal intents crossed with
  later 401/403/404/409/422. Route, UUIDs, canonical immutable body, expected
  version and original pair evidence are conserved; no new UUID is allocated.

Within the same valid session/context, uncertain intent stays pending; absence
or denial does not prove rollback. Exact retry and positive matching receipt
reconciliation remain available, with conflicting commands blocked. A later 401
expires/fences the session and clears its private state; it does not establish
rollback. A new session/context can load current independently authorized server
evidence, but cannot inherit the old in-memory command. Client clearing does not
cancel already-dispatched server execution or assert that it failed to commit.

Accepted original evidence remains separate from fresh actionable detail. A
failed detail refresh retains confirmation and a warning, with no pending retry
or duplicate approval. Existing strict command/result/lineage validation and all
eight public command mappings are unchanged.

### Final verification and retained evidence

Final source: Flutter 3.47.5 / Dart 3.13.4, existing locked dependencies. All final
verification commands completed with exit 0:

| Check | Result |
| --- | --- |
| Focused final Flutter run | **308 PASS / 0 FAIL / 0 SKIP**: 151 new, 45 original independent probes, 70 existing swaps, 17 P4.11 transfers, 14 Session, 7 Platform, 4 HTTP adapter |
| Full eligible Flutter unit/widget suite | **646 PASS / 0 FAIL / 0 SKIP**; includes 151 new and the existing 495, not the external 45-probe file |
| Relevant swap contract/evidence/OpenAPI/Unicode files | **112 PASS / 0 FAIL / 0 SKIP** |
| Flutter analyzer, fatal infos | **PASS**, no issues |
| Non-writing formatter | **PASS**, 110 client lib/test/integration and existing server-test files, zero changes |
| Release Flutter Web, no pub/CDN | **PASS**, Wasm dry run succeeded |
| Unchanged bounded real HTTP/restricted PostgreSQL replay probe | **1 outer PASS + 1 nested Flutter PASS**, no skips; conserved exact request/approval replay and business-evidence hashes |
| Git diff / preservation | **PASS**; empty index, unchanged integrated baseline/migrations and six untouched original paths |

Counts overlap: focused repository cases are included in the full suite; the 45
external probes are separate. The nested HTTP probe is distinguished from its
outer harness. No aggregate acceptance total is inferred. A parallel analyzer
launch was not executed because automatic approval review timed out; its allowed
retry and final-source analyzer passed. Initial candidate disposal/cursor and
obsolete-context notification assertions were fixed without weakening tests.

Retained remediation evidence is under:

```text
C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/artifacts-5420764a3efc21a5bec770757c2d046dfcf033b4bb3bac8cde029f832158e5b7/artifacts/b3a01/
```

It contains `before-original-probes.log`, `before-context-load.log`,
`focused-final.log`, `full-flutter.log`, `contracts.log`, `flutter-analyzer.log`,
`format.log`, `web-release.log`, `http-postgres.log` and `final-snapshot.json`.
The last file includes all ten final source SHA-256 values (including this
document), review-baseline reconciliation, unchanged migration fingerprints and
evidence hashes. Historical independent artifacts and the original ignored
`.local/p416-b3a-final-snapshot.json` are not overwritten.

### Exact remediation delta and final source inventory

Only four paths change relative to the independently reviewed nine-path source:
`shift_swap_controller.dart` (owned reconciliation/retry/completion/disposal),
`platform_controller.dart` (initialization context identity), new
`shift_swap_reconciliation_test.dart` (151 regressions), and this handoff.
The other six original paths remain raw-byte identical. The final Git-visible
inventory is **ten paths: three tracked modifications and seven new files**.
Paths below are relative to `C:/dev/storeos`; hashes are raw checkout SHA-256.

| State | Path | Final SHA-256 |
| --- | --- | --- |
| M, preserved | `apps/client_flutter/lib/src/app/storeos_app.dart` | `1454F9F21B47AF59E019D60ED2A64D6CD90A840DC38CB0D4E9A6F7EEEE281438` |
| M, remediated | `apps/client_flutter/lib/src/application/platform_controller.dart` | `F4B7B3B2089509865BA301C19D051C7839E337F1A30F8A1A5942639D3D22D39D` |
| new, remediated | `apps/client_flutter/lib/src/application/shift_swap_controller.dart` | `5CD26E0A7FD8CA0BD2F60DE3DFC3F748FF607CBF23035BE8FE9C0C96E663AFD5` |
| M, preserved | `apps/client_flutter/lib/src/data/http_platform_api.dart` | `2DBEBCDFAE038D6792041A6460669536519BF0526E6A09FCA13B664C2D9D0840` |
| new, preserved | `apps/client_flutter/test/shift_swap_fixture.dart` | `E698EE576FF73DB4FBCF9B02D17A5F462DD0A1ECCD40CE03DE923746D3319DC7` |
| new, preserved | `apps/client_flutter/test/shift_swap_http_probe.dart` | `79DB61C4A0772DE5564732E9AEF441326DFB225205FCE7F09623B0F1530B5656` |
| new, added | `apps/client_flutter/test/shift_swap_reconciliation_test.dart` | `9CCDCAB02C207BF4878C8C9F5A95845097306855FDE2DAE4F838A52F36CC1675` |
| new, preserved | `apps/client_flutter/test/shift_swap_test.dart` | `AB35D80A6FE40E1487A8296C471716F1BDD3D3C7CDBFD9534E4FB4602316CC82` |
| new, preserved | `apps/server/test/shift_swap_flutter_test.dart` | `04FAEBE94BA8AF1C7D71F3AA9AA38AFA9BF4C4634B3D3FA028FD0DBFF2C6F864` |
| new, updated | `docs/development/phase-4-16-stage-b3a.md` | Document self-hash in retained `final-snapshot.json` |

**Ready for independent targeted B3A-01/B3a re-review.** A skill-required read-only
candidate review found no concrete bypass/regression; it is not the external
independent acceptance gate. The original **CHANGES REQUIRED** verdict remains.

Remaining qualifications are unchanged: A12 full OS-process/PostgreSQL restart
and actual wire-disconnect proof remain **QUALIFIED / NOT EXECUTED**; A13
four-actor Chrome/UI acceptance and real-wire held identity-replacement journeys
remain **QUALIFIED / NOT EXECUTED**. The executed real HTTP probe recreates server
components/listener only and uses completed-response suppression. The complete
unchanged backend suite and expanded backup/update/recovery were not rerun.
No restricted unfinished-upload probe, Step 9 implementation, Step 10 work,
commit, push, merge or deployment occurred. Normal StoreOS services/databases were
untouched. B3a remains **CHANGES REQUIRED** until independent re-review;
P4.16 remains **IN PROGRESS**.

## Historical initial Step 8 implementation record

The following dated implementation record, counts and nine-path hashes are
preserved as history; the remediation inventory and verdict above are current.

2026-10-16: **STAGE B3a IMPLEMENTED LOCALLY**. Only implementation-plan Step 8
is implemented. **P4.16 remains IN PROGRESS.** This is the author's implementation
handoff, ready for independent Step 8 review; independent approval is not claimed.
Employee/manager swap UI, navigation, browser acceptance and recovery remain
separate Steps 9–10.

## Verified integrated baseline and scope

`git fetch origin` verified remote main at exactly
`c55c87c91e5c44b4f2dbc080f8ba1790d5f0fca2` (B2 merge, parents `289dc07…` and
`ed278fb…`). [Main CI 38943401498](https://github.com/RobinBrohl/storeos/actions/runs/38943401498)
was independently read through GitHub: push/main, that exact head SHA, attempt 1,
completed SUCCESS. All five jobs succeeded: `dart`, `flutter`,
`numeric-guided-work-e2e`, `backup-restore-acceptance`, `update-recovery-acceptance`.
This establishes the integrated baseline, not CI for these uncommitted changes.

The starting tree/index were clean on `codex/p416-stage-b2a-swap-http`, HEAD
`ed278fb14ee8ca0d5046d582eeb2fe51ab7fea1e`. The new branch
`codex/p416-b3a-flutter-application` was created directly from the exact B2 merge.
HEAD and origin/main remain at `c55c87c…`; the historical B2 branch is preserved
at `ed278fb…`. Local main remains its previous `289dc07…`; it was not reset or
used as the feature base. No unrelated work was overwritten.

The owner's separate Step 8 authorization governs this work. Earlier design-only
and pending-review wording in the contract, plan, ADRs, status and B2 handoffs
retains its historical context. The owner's integrated Stage A/B1/B2 status and
the verified merge/CI are recorded here without rewriting those historical files.
All historical B2 approvals, findings and transport qualifications are preserved.

No backend production source, DTO, API/OpenAPI, migration, dependency/lockfile,
P4.11 controller, UI or navigation file changed. `StoreApi`/`HttpStoreApi` and the
`PlatformApi` interface are unchanged. Migrations 0001–0029 have no Git content
differences from the integrated baseline. The index is empty. No commit, push,
PR, merge, deployment or release was performed.

## Controller API and ownership

`ShiftSwapController(session, platform, api, self: true|false)` is a
`ChangeNotifier` with separate self/manager instances. All requests go through
`SessionController.authorized` and the existing generic `PlatformApi` transport.

| API | Responsibility |
| --- | --- |
| `load(more:)`, `filter(state:, way:)` | Own or configured-Location list; strict status/direction; server cursor only |
| `select(requestId)` | Fresh authorized detail, exact requested ID/scope and self/manager projection |
| `loadHistory(requestId, more:)` | Original typed command receipts, two per page, at most four ordered versions |
| `chooseSource(ShiftDto, more:)`, `chooseColleague(employeeId)` | Copy an existing own-work selection; authorize colleague discovery against that Shift; select only a returned identity |
| `loadCounterparts(more:)`, `chooseCounterpart(shiftId)` | Recipient-only request-scoped own candidates, then separate exact selected-leg evidence |
| `canRequest`, `can(kind)` | Current permission, mode, server role/state/availableActions and required evidence hints |
| `request()`, `act(action, reason:)` | Validate and submit one of all eight internal intents |
| `retry()` | Explicit exact route/body retry of the existing pending intent |
| `reconcile()` | Explicit bounded authorized receipt lookup; only a matching accepted receipt resolves uncertainty |
| `dispose()` | Remove both listeners, fence delayed results and clear retained private evidence |

`StoreOsApp` owns both instances and disposes them before Platform/Session.
There is no swap widget, dialog, navigation entry or background fetch/retry.
Read-only state exposes typed request/detail/leg/receipt DTOs and immutable
candidate/colleague rows from the existing strict page DTOs.

Manager routes are `/locations/{boundLocation}/shift-swaps`; self routes are
`/me/shift-swaps`. Colleagues use only
`/employee-home/shifts/{selectedSource}/swap-colleagues`. There is no general
colleague roster or arbitrary peer-Shift endpoint. A candidate picker supplies
no authorization. Account/Employee ownership and eligibility are checked by the
existing server for every read/write/replay.

All DTO-bearing responses use the approved `ShiftSwap*` parsers. History has no
shared page DTO: its local closed envelope validates exactly `items` and
`nextCursor`, at most two strict `ShiftSwapCommandResult` items and a nonempty
cursor of at most 2048 characters. Other page DTOs enforce at most fifty rows.
There is no permissive response fallback. Cross-page exact duplicates are
deduplicated; conflicting duplicate evidence is rejected. Cursor values cannot
be supplied by a caller; filter/resource/session/context changes discard them.
Invalid cursor responses remain errors and do not replace retained evidence
with a claimed empty page. Each new read supersedes older reads through a
generation fence, so held pages cannot publish into newer filters or selections.

## Session and Location fencing

`PlatformController` now binds initialization to the opaque
`SessionController.sessionIdentity`, including same-account replacement. It
publishes `contextIdentity` and `contextSessionIdentity`, clears authorization
state together before notifying on session replacement, and defensively freezes
the current permission list. Replacing context changes its opaque identity even
when Account/Company/Location values are unchanged.

Each swap instance captures the opaque session/context plus Account, Company and
Location. The controller listens to both owners and checks that basis before
dispatch, in each authorized callback, after every network await and before
publishing state. A context with a different configured Location cannot bind
to the current session. Replacement, logout and expiry clear list/detail,
history, selected source/colleague/counterpart, cursors, confirmation and pending
intent. Delayed old reads/writes cannot repopulate them. Disposal prevents delayed
notifications. Self/manager evidence remains in separate controller instances,
and a projection with the wrong participant role is rejected.

No bearer token is stored in pending commands. A replacement session cannot
replay a previous intent. Memory-only clearing does **not** assert that an
unconfirmed server operation was rolled back or provide durable recovery.

## Command identity, consent and exact retry

Every intended command gets one UUID operation ID; request creation also gets
one UUID request ID. `ShiftSwapCommandInput.fromJson` validates and canonicalizes
before dispatch. `PendingSwapCommand` stores the fixed route/kind, original IDs,
expected version, session/context/scope basis, canonical JSON, validated body,
captured original source/pair evidence and immutable submission state. All nested
maps/lists are copied and frozen; lifecycle transitions replace the pending
object. Public state has no setter for route/body/IDs or arbitrary command maps.

Request retains the selected source/version/interval/Employee and selected
colleague. Offer retains the exact candidate version and independently loaded
leg B, including its original work/pins. Confirm retains the existing offered
two-leg request; it never reads a newer picker selection. Approval retains the
confirmed stored pair. No replacement Shift or Task ID is allocated by Flutter.
Receipt validation verifies scope/request/operation/kind/accepted version,
command-specific accepted status, source identity, unchanged original consent,
both original legs/work/pins and offered counterpart/reason as applicable.
Approved lineage is the server's strict two-leg replacement/Task correspondence.

Both participant withdrawals derive internal intent from current authorized
detail but POST to the same public `/withdraw` endpoint. Neither actor nor kind
is sent in JSON. Manager hints require `workforce.swaps.manage` and, for approval,
`workforce.shifts.manage`, `tasks.instances.read`, actionable confirmed evidence
and server `availableActions`. The detail's approval hint incorporates the
backend's independent-Account prerequisites; private Account/link identities are
not exposed to reconstruct that check. The server independently enforces it
again on the command. Self hints use the implemented `.self.read`,
`.self.request` and `.self.respond` capabilities.

Retry reuses the exact route/body/IDs, without UUID allocation. Unknown intent
blocks conflicting commands, ordinary discovery and picker changes. There is
no automatic retry, offline queue, persistence or session-crossing replay.

## Outcomes and accepted result versus fresh detail

| Outcome | State and required next step |
| --- | --- |
| Trustworthy accepted result | Preserve strict original `lastConfirmed`; clear pending; separately request fresh authorized detail |
| Definitive first-attempt rejection | Return `rejected`, retain error and previous accepted result/unrelated list, clear stale action evidence, require reload |
| Timeout, connection loss, unexpected failure, 5xx, malformed/empty/unusable success or mismatched receipt | Return `uncertain`; preserve original immutable intent; outcome explicitly unknown; exact retry or reconciliation only |
| Definitive denial after an earlier uncertain attempt | Return `reconciliationRequired`; retain original intent; denial/absence does not prove previous rollback |
| 401/session expiry, logout, replacement or disposal | Return `fenced` for held writes; clear old session's private state; no replay under the replacement identity |
| Accepted result followed by failed/invalid fresh detail | Return `confirmed`; retain accepted evidence, clear actionable detail and show refresh warning; retry cannot repeat confirmed approval |

`HttpPlatformApi` has one swap-POST-specific success check: HTTP must be 200/201
and agree with the receipt's `statusCode`. It does not rewrite original 201 request
replay to 200 or discard replay metadata. The controller supplies strict receipt
semantics. Other transport/authentication paths are unchanged.

Fresh detail is also checked against the last accepted receipt for that request.
An older version or contradictory consent/pair/terminal lineage is unusable;
it cannot re-enable an already confirmed approval. A receipt remains original
evidence rather than current actionability. Reconciliation reads up to two history
pages and confirms only an exact matching operation/kind/evidence; denied reads,
missing receipts or malformed evidence keep the original outcome unresolved.

## Final verification

Pinned SDK: Flutter **3.47.5**, Dart **3.13.4**; existing resolved locked packages.
All final commands below completed with process exit 0. No assertions, grants or
existing tests were weakened. Logs are ignored local artifacts under `.local/`.

| Check | Final evidence |
| --- | --- |
| Full eligible Flutter unit/widget suite | **495 PASS / 0 FAIL / 0 SKIP**, including 70 new swap controller/HTTP cases, P4.11 transfers, Session/Platform, app composition and affected controllers; `p416-b3a-full-flutter-final.log` |
| Earlier bounded regression run | **114 PASS**, covering swaps, HTTP adapter, transfers, Session/Platform and app/widget regressions before the final added evidence cases; superseded by final full-suite source |
| Relevant swap contracts/evidence/OpenAPI/Unicode tests | **112 PASS / 0 FAIL / 0 SKIP**; `p416-b3a-contracts-final.log` |
| Flutter analyzer | **PASS**, no issues; `p416-b3a-analyze-final.log` |
| New server test analyzer | **PASS**, no issues |
| Non-writing Dart format check | **PASS**, all 111 client Dart files unchanged; new server test unchanged |
| Release Flutter Web | **PASS**, `build web --release --no-pub --no-web-resources-cdn`; Wasm dry run succeeded; `p416-b3a-web-final.log` |
| Real HTTP/PostgreSQL/controller probe | **1 outer test PASS + 1 launched Flutter probe PASS**, no skips; `p416-b3a-backend-final.log` |
| Git boundaries | `diff --check` PASS; index empty; backend runtime/packages/migrations unchanged |

The first sandboxed contract invocation could not copy Dart test temporary
compilation files and did not execute assertions. It was rerun with the required
test-runner access; the final 112-test invocation passed. The Windows `.bat` SDK
entry point also could not obtain its SDK cache lock in the restricted shell;
verification used the installed `dart.exe` and `flutter_tools.snapshot` directly,
without an SDK/dependency change.

New negative evidence covers immutable nested pending values, no changed-body
substitution or new IDs while unresolved, all eight exact retries, original
201/200 replay, first rejection versus later 400/403/404/409/413/415/422 denial,
401 fencing, absence/denial versus positive receipt reconciliation, malformed
JSON/DTOs, wrong operation/kind/scope/version/status, changed source/counterpart/
offered pair/guidance pins, stale detail after accepted approval, failed detail
refresh without duplicate approval, recipient-only selected-detail discovery,
private mode separation, immutable capability/picker data, page bounds/cursors,
deduplication/history order, stale filter responses and unchanged unrelated
list/confirmation after rejected request.

Deterministically held HTTP-adapter responses cover every command across
same-account session replacement, and held GET/POST across different Account,
Location, same-scope context replacement, logout, expiry and disposal. Old
responses produce no delayed private state or notifications.

## A12/A13 executed integration and qualifications

**A12 Application/data real HTTP replay: PASS for the executed cases.** The new
test-only server harness uses the existing isolated restricted-role fixture,
production native listener/ServerApp/auth/routes/Application/PostgreSQL and actual
Flutter controllers with `HttpStoreApi`/`HttpPlatformApi`. Three constructed
actors (source A, recipient B and independent manager) perform request, offer,
confirm and approval. A local gateway consumes each complete request/response,
suppresses the first committed request and approval responses with a synthetic
503, recreates server components/listener on the same database/port, compares
retry body bytes, and verifies original 201/200 replay. Exact replay preserves
hashes/counts of Shifts, selections, Tasks/execution evidence, swap requests/legs/
receipts/claims/lineage, P4.11 evidence and audit. Both originals are cancelled;
both replacement Shift IDs and Task correspondences come from server receipts.
History pages expose all four original accepted versions; approval cannot be
resubmitted after confirmation.

Reproduction from the repository root, using the installed pinned SDK:

```powershell
$env:STOREOS_SWAP_FLUTTER_PROBE = '1'
$env:STOREOS_SWAP_PROBE_DART = 'C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe'
$env:STOREOS_SWAP_PROBE_FLUTTER_SNAPSHOT = 'C:\dev\flutter\bin\cache\flutter_tools.snapshot'
./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @('test/shift_swap_flutter_test.dart')
```

The existing harness creates a new random disposable PostgreSQL container,
database and runtime credential, runs the test and removes that container. Normal
StoreOS services/databases were left running and untouched. Test credentials
were neither printed nor added to source. No unfinished-upload probe ran.

**A12 full OS-process restart: QUALIFIED / NOT EXECUTED.** The executed restart
recreated production server components and native listener within the fixture
process; it did not kill/restart an OS server process or restart PostgreSQL.
Synthetic completed-response loss is not a wire-disconnect timing proof. Durable
browser-reload/offline recovery is not implemented.

**A13 Application/data deterministic fencing: PASS for the executed cases.** The
production controller/session/platform/HTTP-adapter composition is exercised
with held responses and the identity replacements described above. **A13 browser,
four-actor UI and real-wire held identity-replacement journeys: QUALIFIED / NOT
EXECUTED** in Step 8. No Chrome, swap widget or four-actor acceptance is claimed.

Separate skips/non-executed work: full unchanged backend suite and unrelated
safe HTTP suites were not rerun; no prohibited ingress network probes; no real
process-crash recovery, browser/native-device/accessibility/operator acceptance,
backup/restore or update/recovery expansion. The inherited B2 Windows/OS/Linux/
proxy/hardware qualifications and historical approvals remain unchanged. Step 9
must deliver employee/manager UI, literal evidence/pair review and actual browser
journeys including ordinary execution of both incoming replacements. Step 10
must add and execute expanded recovery/backup/update acceptance. Final A01–A16,
independent functional/Security review and authorized publication remain gates.

## Complete changed-file inventory and SHA-256

Exactly **nine paths** are changed: three tracked modifications and six new files.
Paths are relative to `C:/dev/storeos`. SHA-256 values describe raw final checkout
bytes. The external ignored `.local/p416-b3a-final-snapshot.json` stores all nine
hashes, including this handoff's own hash (avoiding a circular self-hash), baseline,
empty-index evidence and all 29 unchanged migration fingerprints/Git blob IDs.

| State | Path | SHA-256 |
| --- | --- | --- |
| M | `apps/client_flutter/lib/src/app/storeos_app.dart` | `1454F9F21B47AF59E019D60ED2A64D6CD90A840DC38CB0D4E9A6F7EEEE281438` |
| M | `apps/client_flutter/lib/src/application/platform_controller.dart` | `5E88321AD418F9161EF375DF4567A3BAA006ADEC0FD9845BC71BF669F29261A2` |
| M | `apps/client_flutter/lib/src/data/http_platform_api.dart` | `2DBEBCDFAE038D6792041A6460669536519BF0526E6A09FCA13B664C2D9D0840` |
| new | `apps/client_flutter/lib/src/application/shift_swap_controller.dart` | `9CDB76709F415F6DBEA28F0E795129F21E1E58CF8B2597EAE92FC9B58B6AB1BC` |
| new | `apps/client_flutter/test/shift_swap_fixture.dart` | `E698EE576FF73DB4FBCF9B02D17A5F462DD0A1ECCD40CE03DE923746D3319DC7` |
| new | `apps/client_flutter/test/shift_swap_http_probe.dart` | `79DB61C4A0772DE5564732E9AEF441326DFB225205FCE7F09623B0F1530B5656` |
| new | `apps/client_flutter/test/shift_swap_test.dart` | `AB35D80A6FE40E1487A8296C471716F1BDD3D3C7CDBFD9534E4FB4602316CC82` |
| new | `apps/server/test/shift_swap_flutter_test.dart` | `04FAEBE94BA8AF1C7D71F3AA9AA38AFA9BF4C4634B3D3FA028FD0DBFF2C6F864` |
| new | `docs/development/phase-4-16-stage-b3a.md` | See external final snapshot for this document's own hash |

The server path is an opt-in verification harness only; it introduces no backend
runtime behavior. `shift_swap_fixture.dart` copies the existing contract test's
strict synthetic evidence builders. All support sources are included above;
generated Web/test output and local run logs are ignored artifacts.

**Ready for independent Step 8 review.** No independent approval or full P4.16
closure is claimed. Stop boundary: local uncommitted Step 8 implementation and
verification only.
