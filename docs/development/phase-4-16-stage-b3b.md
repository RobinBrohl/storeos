# P4.16 Stage B3b — Flutter Shift Swap surfaces (Step 9)

Date: 2026-10-17. **Local, uncommitted Step 9 implementation. P4.16 remains
IN PROGRESS.** Current independent verdict: **STAGE B3b CHANGES REQUIRED**.
**B3B-01 LOW is fixed locally; independent targeted re-review is pending.**
This document does not approve its own implementation. Step 10 has not started.

## B3B-01 local remediation — 2026-10-17

The independent review returned **STAGE B3b CHANGES REQUIRED** for one LOW
functional finding: rapid Employee Home shortcut taps opened two Swap request
pages. The consequence probe found one POST and one accepted business effect.
No security vulnerability or duplicate business mutation was established.
**B3A-01 remains independently CLOSED.** The owner separately authorized this
navigation-only correction, deterministic regressions, verification and handoff.

Independent report:
`C:/Users/Robin/.codex/state/plugins/codex-security/scans/storeos/99c3ba943795b3ebc15cb49d1eeac440f859912e_20261017T095529Z_8drx0ls8/artifacts/Stage-B3b-Review.md`.
Report SHA-256: `5920F4A64BB4D0706400D1D21A08E5BB407E3E708A7EA92AC692F65F836AF227`.
Its adjacent `independent_navigation_review_test.dart` has SHA-256
`1105309D97D52D7F3400AD87FF371CDC4ABD74BBA4C6519614D377EE67F28E87`.
Both original artifacts were read and preserved unchanged.

Before editing, all twelve reviewed paths matched the original final manifest,
all 29 migrations matched raw SHA-256/Git blob fingerprints, and the index was
empty. Branch remains `codex/p416-b3b-shift-swap-ui`; HEAD and cached origin/main
remain `99c3ba943795b3ebc15cb49d1eeac440f859912e`. No unexplained drift or Step 10
work was present. The reviewed manifest, source and handoff were preserved under
`.local/p416-b3b/b3b01/` before edits. Earlier implementation inventories/counts
below are historical; the current remediation inventory is at this file's end.

### Root cause and narrow correction

`swaps.locked` protected source discovery but stopped protecting navigation when
the read completed. The first callback could already be awaiting `Navigator.push`
while the next pointer event still hit Employee Home before the next rendered
frame installed the route barrier. A second callback then saw an unlocked
controller, loaded the same source and pushed another page. Command locks still
prevented duplicate mutation; they did not own the navigation stack.

`PlatformHomeScreen` now acquires an owner-local navigation token synchronously
before its first await. It retains ownership through discovery, route creation,
the pushed route's entire lifetime and the guarded return/refresh. Repeated
activations under the same controller and opaque session/context basis return
without another read or push. A new identity may acquire a new token; an obsolete
callback's `finally` clears only its own token, never the newer owner's guard.
Normal pop, browser back, failed discovery and exceptions release ownership.
The existing identity checks still run after loading, before push, after route
completion and before/after the old-context refresh. Invalidated routes cannot
reactivate their old private section.

The remediation changes exactly three paths relative to the reviewed snapshot:

- `apps/client_flutter/lib/src/ui/platform_home_screen.dart` — scoped guard only.
- `apps/client_flutter/test/shift_swap_shortcut_test.dart` — 24 new deterministic widget regressions.
- `docs/development/phase-4-16-stage-b3b.md` — this remediation record and updated inventory.

No controller command/retry/reconciliation, ShiftSection, ShiftSwapSection,
backend, contract, OpenAPI, migration, dependency or P4.11 implementation changed.
No timer/debounce, global navigation manager, hidden shortcut or new business
command was introduced. All implementation remains local and uncommitted.

### Original failure and route-stack regressions

The unchanged original independent harness was run before the fix using a
temporary import-compatible copy: **4 PASS / 1 FAIL / 0 SKIP**. The failing
expected-one-page assertion observed **three PageRoutes: Home plus two Swap
pages**, rather than two. Its accepted-command consequence branch passed and
confirmed one POST. Log: `b3b01/original-before.log`.

After the fix, the original expected-one-page case and its three source-work/
disposal probes pass unchanged: **4 PASS / 0 FAIL / 0 SKIP** in
`b3b01/original-after.log`. The command filters `rapid physical|task-stage|reentrant|disposal`.
The old consequence diagnostic explicitly expects the exploit's three routes;
it is preserved, not weakened or treated as a post-fix acceptance assertion.
The new consequence regression instead requires two routes and one accepted POST.

All **24 new widget regressions PASS**. Navigator observers assert actual
PageRoute counts; physical pointer tests retain fatal missed-hit checks for the
original two taps. A third physical pointer event may land on the new route
barrier, so it is delivered at the same screen coordinate. Three synchronous
callback activations are separately tested while the completed source read is
held before push. There are no timing delays or debounce assumptions.

Coverage includes held HTTP discovery, same-frame two/three taps, pre-push and
push-observer reentrancy, repeated callbacks while open, pop/reopen, failed reads,
exceptional preflight, logout/same/different Account/context/Location changes,
parent disposal, browser back, and both old-navigation and old-preflight `finally`
completion after a newer identity already owns navigation. Those ownership cases
hold the newer operation after loading, when controller locks are off, then
assert that repeats cannot add a read or route. P4.11 can still open its separate
transfer page while the Swap guard is held. Navigation-only cases expect zero
POSTs; explicit submission expects exactly one POST and one accepted fixture
receipt, retained after the single page closes.

### Current verification

Pinned Flutter 3.47.5 / Dart 3.13.4; dependencies unchanged. New logs and the
updated manifest are under `.local/p416-b3b/b3b01/`.

| Check | Remediation result | Evidence |
| --- | --- | --- |
| New B3B-01 widget regressions | **24 PASS / 0 FAIL / 0 SKIP** | `shortcut-tests.log` |
| Original expected-one-route + data/disposal probes | **4 PASS / 0 FAIL / 0 SKIP** | `original-after.log` |
| Focused Step 9, B3a/B3A-01, P4.11, Session/Platform | **352 PASS / 0 FAIL / 0 SKIP** | `focused.log`: existing Step 9 69 + new 24 + unchanged focused 259 |
| Full eligible Flutter suite | **739 PASS / 0 FAIL / 0 SKIP** | `full-flutter.log`; includes the focused subset, not additional unique tests |
| Relevant swap/Unicode/P4.11 contracts | **179 PASS / 0 FAIL / 0 SKIP** | `contracts.log` |
| Flutter analyzer, fatal infos | **PASS**, no issues | `analyze.log` |
| Nonwriting formatter | **PASS**, 106 files, 0 changed | `format.log` |
| Flutter Web release / Wasm dry run | **PASS** | `web-release.log`; no pub/CDN |
| Actual Chrome rapid-shortcut extension | **1 outer + 1 inner PASS / 0 FAIL / 0 SKIP** | `chrome.log`; real HTTP/disposable PostgreSQL |

The browser probe uses temporary copies of the existing four-actor integration
and server test files. It adds rapid pointer input and an exactly-one-mounted-
Swap-page assertion, and asserts one accepted request in the gateway's observed
command sequence. Evidence copies and the runner remain under the ignored local
directory; the temporary package files are removed in `finally`. The reviewed
browser sources are unchanged. This is author-run real integration verification,
not an independent approval.

The fresh browser run completed the existing four-actor request/offer/exact-pair/
independent-decision journey, both incoming-work execution journeys and exact
approval retry, with the rapid shortcut extension. Its accepted gateway sequence
contains one request; the deterministic widget consequence test additionally
asserts exactly one attempted POST and one accepted fixture receipt. These are
different assertions, not a claim that retry traffic never occurs. The temporary
package probes, disposable database container and loopback ChromeDriver were
removed after completion. Preserved probe sources: `browser-client.dart` and
`browser-server.dart`; reproducible local wrapper: `run-chrome.ps1`.

The earlier independent four-actor/narrow Chrome and 43 HTTP/PostgreSQL counts
remain historical evidence for their reviewed hashes. No separate rerun of the
43-test HTTP suite, unchanged full backend suite, unrelated browser tests, original
45-case B3a external harness or Step 10 wrappers is claimed by this remediation.
The permanent 221 B3a/B3A-01 cases are rerun in the focused/full suites. Historical
ingress restrictions, font/native/accessibility, OS/proxy/hardware and recovery
qualifications below remain. No prohibited unfinished-upload probe ran.

A setup invocation initially used the wrong working directory and ran no
assertions; the corrected original harness run above establishes the failure.
The first new test run found that the third pointer sequence could hit the new
barrier; the coordinate-based third event now models that physical input without
weakening the route/command assertions. The original two-tap reproduction remains
unchanged and passes. No final check failure is being silently replaced.

**Ready for independent targeted B3B-01 re-review. Stage B3b remains CHANGES
REQUIRED until that independent review.** No independent closure/approval,
commit, push, PR, merge, deployment or Step 10 work is claimed.

## Baseline and authorization

The owner separately authorized B3b only, including UI, bounded controller
integration requirements, test-only fixtures, disposable HTTP/PostgreSQL/Chrome
journeys and this handoff. Backend runtime, routes, migrations, contracts,
OpenAPI, dependencies, release and publication remain unchanged.

`git fetch origin` completed. The fetched `origin/main` is
`99c3ba943795b3ebc15cb49d1eeac440f859912e`, tree
`7777c6170a5350ca505c8cd6fab541d060154298`. GitHub Main CI
[39017643984](https://github.com/RobinBrohl/storeos/actions/runs/39017643984)
was verified through the GitHub connector: push on `main`, exact SHA,
completed/success, attempt 1, all five jobs successful (dart, flutter,
numeric-guided-work-e2e, backup-restore-acceptance, update-recovery-acceptance).
This is baseline CI, not CI for these uncommitted changes.

The starting worktree/index were clean on historical branch
`codex/p416-b3a-flutter-application`, HEAD
`f143254c1365252b454dc5d0a6f1a96b9aa33491`, with the same approved tree.
Local `main` was behind; it was fast-forwarded without a merge commit to the
approved merge SHA. New branch: `codex/p416-b3b-shift-swap-ui`, HEAD still the
approved baseline. The historical B3a branch and its evidence are preserved.
No reset, clean, overwrite, staging, new commit, push, PR, merge commit,
deployment or release.
All 29 migrations retain their recorded raw SHA-256 and Git blob identities.
Before fingerprints: `.local/p416-b3b/migrations-before.json`.

The owner's authorization records B1/B2/B3a as integrated and B3A-01 independently
CLOSED. Older handoff/status entries retain their historical review wording.
No new independent verdict is claimed here.

## Delivered employee and manager behavior

`ShiftSwapSection` uses the two controllers already owned/disposed by StoreOsApp.
Navigation exposes **Meine Schichttausche** under `workforce.swaps.self.read`
and **Schichttausch prüfen** under `workforce.swaps.manage`. Drawer and
NavigationRail retain the existing sections and refresh behavior. Context-keyed
swap sections cannot inherit a mounted form from a replaced authorization context.

Employee Home retains its separate P4.11 transfer shortcut, explicitly labelled
as a one-way handover, and adds **Bilateralen Schichttausch anfragen** using the
existing own future/published/pristine-work shortcut pattern. The server still
decides eligibility. Discovery failures do not open an actionable request form.

The source shortcut calls `chooseSource` and displays only server-disclosed named
colleagues. Own Shift/version/UTC interval and exact Task summaries/pins are shown
before the explicit invitation confirmation. Widgets allocate no UUID, construct
no command payload, accept no arbitrary Employee ID and fetch no general roster.
The dialog explains that an invitation does not change the schedule.

B opens an addressed invitation and explicitly loads request-scoped own
counterparts. Selecting a candidate loads its exact leg B through the controller.
Offer review separates the original A and B work, owners/incoming owners, Shift
IDs/versions, intervals, ordered Task IDs/titles/Template revisions and optional
Knowledge/Planogram pins. A confirms the exact stored pair, rather than any picker
selection. Both dialogs explain independent managerial approval.

Manager decisions first reload the same selected request under current authority;
a superseding request read cancels review. Approval shows both full original legs
and explains atomic cancellation/publication of both Shifts and Tasks. The UI uses
`can()`/server hints; the backend remains authoritative for scope, freshness and
participant independence. Rejection is a separate reasoned action. After accepted
approval, current terminal evidence cannot offer another approval.

Recipient/source decline and the supported withdrawal roles use controller
actions. Both withdrawals use the common public withdrawal action, with no actor
or kind field in JSON. Withdrawal/rejection dialogs validate through the existing
`transferReason` contract: trim, 1–500 Unicode scalar values, no retained controls.
They preserve terminal history and explain that closure causes no schedule change.

List direction/status filters and opaque server pagination are supported, as are
counterpart/colleague/history pages, loading, empty, error and explicit retry/read
states. Current detail and original receipt evidence are labelled separately.
History retains request/offer/confirmation/decision operations and reasons.
Approved detail displays both replacement Shift identities and complete Task
lineage. Replacement work uses ordinary Employee Home/ShiftController execution.

All business-controlled names, titles, reasons, captured text and references use
plain Text/SelectableText, without Markdown, HTML, active content or constructed
historical guidance links. Time labels retain the project's explicit UTC format.

## Two bounded controller integration changes

1. **Own source-work review.** Swap colleague discovery returns identity-only
   candidates, not work snapshots. The previous public API could not supply Task
   titles or exact pins for A's pre-submission review. `sourceWork` and
   `loadSourceWork()` read existing own Shift and Task endpoints through the
   controller's existing authorized, generation-fenced read path. The full Shift
   DTO must still equal the selected source. A bounded complete ordered Task set
   must match its Shift, Employee, selections, identities, versions and content.
   Only immutable DTOs are published after all reads succeed. No new route,
   eligibility algorithm or command/retry semantics are introduced. UI request
   confirmation requires this evidence; a changed/rejected source stays unusable.
2. **Disposal publication.** Five deterministic mounted request/offer/confirm/
   approval/withdrawal dialog tests initially failed: disposal cleared controller
   evidence but ChangeNotifier did not tell still-mounted dialogs. Disposal now
   emits one final notification only after clearing and fencing every private
   field, before disposing the notifier. Reentrant disposal is already guarded;
   later network completions remain silent. The five unchanged reproductions and
   all original B3a tests pass after the correction.

Independent tests cover immutable source work, changed-version refusal, held own
reads across context/Location/logout/expiry/same/different Account/disposal, the
five disposal dialogs, and unchanged B3A-01 reconciliation ownership regressions.
The pending intent, command IDs/body, receipt parser, submission generations and
retry/reconciliation algorithms were not rewritten.

## Modal, context and uncertain-outcome fencing

Every action dialog captures opaque session and Platform context identities,
the controlling controller, exact detail/source/colleague/counterpart and work
objects. Checks run after the fresh manager read, dialog completion, command wait
and navigation awaits. The exact current request/version must still be the one
reviewed. A changed context, same-account relogin, different account, Location,
selection, logout, actual authorization-time expiry or disposal invalidates the
dialog, removes its private content and clears its local reason controller.
Routes are removed by their own route identity. No newer selection is substituted.
The own-work shortcut fences both delayed discovery and navigation completion.

| Controller outcome | UI behavior |
| --- | --- |
| confirmed | Show immutable original receipt; current detail is separate. A failed refresh preserves confirmation and offers an explicit authorized read. |
| rejected | Show the server/controller error; stale action evidence is cleared and fresh detail/new confirmation is required. No acceptance claim is inferred from a refresh warning. |
| uncertain | Warn that execution may already have succeeded; keep original pending intent and block conflicting commands/pickers. |
| reconciliationRequired | Preserve the earlier unresolved command after later definitive denial or missing receipt. Neither denial nor absence proves rollback. |
| fenced | Remove previous private evidence/dialog; do not submit or publish delayed results under a new authority basis. |
| busy | Disable conflicting controls and show controlled progress; duplicate clicks cannot dispatch another command. |

Unresolved intent has two explicit actions: **Exakt denselben Befehl wiederholen**
and **Originalbeleg abgleichen**. Both invoke the existing controller APIs; no new
ID is generated by a widget, no command is automatically retried, and navigation
does not clear a same-context pending command. An accepted command is never
automatically resubmitted. UI dismissal/session clearing does not imply server
rollback. Durable browser-reload/offline recovery remains outside Step 9.

## Historical reviewed implementation verification and acceptance matrix

Pinned tooling: Flutter **3.47.5**, Dart **3.13.4**, Chrome **155.0.8059.80**
and matching-build ChromeDriver **155.0.8059.84**. No dependency/lockfile upgrade.
Logs below are ignored files under `.local/p416-b3b/`.

| Check | Final result | Evidence |
| --- | --- | --- |
| Step 9 additions | **69 PASS / 0 FAIL / 0 SKIP**: 61 widget cases and 8 own-work/controller cases | `step9-final.log`; `navigation-final.log` separately covers drawer/rail, delayed shortcut discovery/navigation and own-read fencing |
| Existing B3a/controller/B3A-01 | **221 PASS**, assertions preserved | `shift_swap_test.dart` and `shift_swap_reconciliation_test.dart`, unchanged; `swap-final.log` |
| Full eligible Flutter suite | **715 PASS / 0 FAIL / 0 SKIP** | `full-flutter-final.log`; includes P4.11 transfers, Session/Platform and existing UI/controller suites |
| Relevant swap/Unicode/P4.11 contracts | **179 PASS / 0 FAIL / 0 SKIP** | `contracts.log` |
| Completed-request real HTTP/restricted PostgreSQL | **43 PASS / 0 FAIL / 0 SKIP** | `http-postgres.log`; lifecycle, privacy, paging and rollback/error suites |
| Four-actor actual Chrome/HTTP/PostgreSQL | **1 outer test + 1 launched browser test PASS** | `chrome-final.log`; independent manager and denied viewer, ten Tasks per leg |
| Flutter analyzer | **PASS**, no issues | `analyze-final.log` |
| Changed server test analyzer, fatal infos | **PASS**, no issues | `server-analyze-final.log` |
| Non-writing formatter | **PASS**, 105 files unchanged | `format-final.log` |
| Local Flutter Web release | **PASS**, including Wasm dry run | `web-release.log`; `--release --no-pub --no-web-resources-cdn` |
| Source boundaries | **PASS**: empty index, unchanged backend runtime/contracts/OpenAPI/dependencies and 29 migrations | final manifest and `git diff --check` |

**FAIL:** no outstanding final-check failure. Corrected historical setup/probe
failures are recorded below and retained in local logs.

**SKIP / NOT EXECUTED:** the full unchanged backend suite, unrelated browser
journeys and Step 10 recovery wrappers were not rerun. No new backend behavior
was changed; affected integration and privacy/error regressions above did run.
The executed suites themselves have zero skipped tests.

**QUALIFIED:** hardware/native/accessibility/OS/proxy/font/recovery limitations
are retained below. Synthetic completed-response loss proves explicit retry and
receipt conservation, rather than TCP-disconnect timing or OS-process recovery.

### What Chrome observed and what the server fixture asserted

The browser uses the real StoreOsApp, production Session/Platform/Shift/Swap
controllers and HTTP adapters. A is a linked Employee with admin capability in
this fixture; that intentionally makes its self-approval refusal an independence
test rather than merely a missing-grant test. B is a linked Employee, the approving
manager is a separate Account, and the observer is a viewer without swap grants.

Chrome performs A's own-work shortcut, named B selection and request; B's incoming
invitation, own counterpart/detail and explicit offer; A's exact stored-pair
review/cancellation/reconfirmation; participant A's unavailable approval hint and
actual server refusal; and independent manager approval. A completed successful
approval response is replaced with a test-only 503; the explicit retry uses the
same operation and body and receives the original replayed receipt. No automatic
retry or new request bypass occurs.

Both employees then find their incoming replacement through **Meine Arbeit**,
load all ten assigned Tasks and start/confirm/complete one Task each using the
ordinary Employee Home execution controls. This proves both execution journeys;
it does not claim that all twenty Tasks were completed. The test waits for the
real database-authorized planned interval; no clock override or execution API
bypass is added.

Additional Chrome checks exercise unauthorized peer-colleague/counterpart reads,
foreign Location, participant admin self-approval 403, literal/normalized long
Unicode names and Task titles, declined/withdrawn/rejected requests, active-state
stale version HTTP 409 followed by a fresh read/new explicit manager decision,
actual server-revoked-session 401 and denied observer navigation. A completed
detail response is held deterministically at the disposable gateway, Platform
context is replaced in the browser, then the old response is released: it cannot
repopulate selected evidence. The script-injection sentinel stays unset and the
integration binding reports no Flutter framework exceptions.

Server-fixture assertions separately verify the restricted runtime role, both
originals still published before fresh approval, exact approval replay body and
unchanged complete database-evidence hash on retry, both originals cancelled,
both replacements assigned to the other Employee, all twenty Task links and the
two completed incoming Tasks. The gateway's arm/held/release endpoints exist
only in this disposable test harness, not in StoreOS runtime routes. Its raw
completed-request/response handling does not rerun an unfinished-upload probe.

The existing real HTTP privacy suite supplies further scoped Company/Location,
revoked/expired/plugin credentials, guessed ID/cursor, independent participant
approval and non-disclosure assertions. Those are **server HTTP assertions**, not
claims that each was separately repeated through a browser control.

| Criterion | Step 9 coverage | Missing or qualified evidence |
| --- | --- | --- |
| A01 | **PASS**: actual request → own counterpart offer → stored-pair confirmation → independent approval, twenty links, both ordinary incoming execution journeys; server asserts no early cancellation/publication | No missing Step 9 journey; broader recovery remains Step 10 |
| A02 | **PASS**: browser discovery/foreign-Location/observer/participant-admin refusal plus real HTTP Company/Location/plugin/revocation/cursor/foreign-resource cases; drawer/rail capability removal tests | Browser does not duplicate every credential and foreign-Company HTTP permutation |
| A13 | **PASS**: forty mounted-dialog cases across five workflows and eight invalidations; own-read fencing matrix; original B3A-01 regressions; unknown/later-denied/receipt reconciliation/confirmed failed refresh/double click; real-browser held detail and revocation | All session/Location/dialog permutations are deterministic widget/controller evidence; only the documented held-context/revocation subset is real-browser wire evidence. No durable recovery claim |
| A16 | **PASS**: actual four-actor Chrome on real HTTP/restricted PostgreSQL, both replacements, privacy, participant separation, exact retry, actual stale 409, closure, long literal/Unicode content and no framework exceptions | Optional fallback glyph coverage, native devices and accessibility remain QUALIFIED; no general cross-browser claim |

### Reproduction

Run the ordinary Flutter tests/analyzer from `apps/client_flutter` with the pinned
SDK and locked dependencies. The safe PostgreSQL suites use the existing runner:

```powershell
./scripts/workforce/Run-P416StageB1Checks.ps1 -TestFiles @(
  'test/shift_swap_http_test.dart',
  'test/shift_swap_http_privacy_test.dart',
  'test/shift_swap_http_pagination_test.dart',
  'test/shift_swap_http_error_test.dart'
)
```

For Chrome, start a matching ChromeDriver on a loopback-only port with a hidden
window. Set `CHROME_EXECUTABLE`, `STOREOS_KNOWLEDGE_DRIVER_PORT`,
`STOREOS_SWAP_BROWSER=1`, `STOREOS_SWAP_PROBE_DART` and
`STOREOS_SWAP_PROBE_FLUTTER_SNAPSHOT`, then invoke the same runner with
`test/shift_swap_browser_test.dart`. The runner creates a random disposable
PostgreSQL container/database/runtime credential, removes its own container in
`finally`, and clears its generated secret files. Stop that test driver afterward.
Do not substitute the normally served client or normal StoreOS database.

## Historical qualifications and stop boundary

The initial Step 9 widget run exposed fixture expiry timers/history ordering and
UTF-8 response setup issues; those fixtures were corrected without weakening
existing tests. The first broad Chrome journey passed. A stronger exact-name
assertion subsequently failed because its expected name included a trailing
space that the existing server rename contract trims; the assertion now checks
the exact normalized name. The final strengthened run supersedes that fixture
failure. Five disposal probes failed before the bounded correction described
above; their original log is retained in `disposal-before.log`.

The SDK entry point initially lacked cache-lock access in the restricted shell;
verification used the installed pinned SDK with approved cache access, without
upgrades. Test output is local/ignored, test credentials are generated privately
and redacted, and disposable containers/drivers are removed after each run.

The no-CDN Chrome development server reported absent optional fallback-font URLs
for some emoji/CJK glyphs. Exact Unicode/literal DTO content and layout are
asserted; complete platform font/glyph coverage is not certified. Native devices,
screen-reader/physical-keyboard accessibility, physical hardware capacity, Linux
and proxy/OS transport timing are not inferred from these Windows tests.

Inherited B2 ingress qualifications and historical interrupted/failed ingress
probes remain unchanged. No prohibited unfinished-upload probe or scanner retry
ran. Full OS-process crash/restart, browser reload/durable pending recovery,
expanded backup/update/restore and Step 10 are not implemented or claimed.
Independent functional/Security approval and final P4.16 acceptance/publication
remain separate gates. Personnel decisions remain with people.

## Historical reviewed twelve-path inventory and SHA-256

The reviewed checkout-byte inventory is preserved below. The reviewed document's
hash is in the historical `.local/p416-b3b/final-manifest.json`, avoiding a circular
self-hash. That preserved manifest includes migration fingerprints and earlier
evidence logs; it does not describe the current remediation snapshot.

Exactly **12 paths**: five tracked modifications and seven new files.

| State | Path | SHA-256 |
| --- | --- | --- |
| new | `apps/client_flutter/integration_test/shift_swap_test.dart` | `612391C8505764B9164AAD192C078E66521A9842C2BE882D6DA48FECBA836E22` |
| M | `apps/client_flutter/lib/src/app/storeos_app.dart` | `FC5A647747B093219519DC490852CF926CF0EEE22A71EF88BB3C7F1BD2B22CD8` |
| M | `apps/client_flutter/lib/src/application/shift_swap_controller.dart` | `A80823FA58A2F4FCB454ECBD0AD9B7F80DE066382B74FF17D9CC3329217F734F` |
| M | `apps/client_flutter/lib/src/ui/platform_home_screen.dart` | `477ACC70C70E0533E556F4DF2C69D94665AEB3A53B201B6E7E80F1E10C2A3ED5` |
| M | `apps/client_flutter/lib/src/ui/shift_section.dart` | `DD12CF1D66C97FE53BB2FEFABAD17EA83151B1632A5AF367EDA4D1FB5CC2D70B` |
| new | `apps/client_flutter/lib/src/ui/shift_swap_section.dart` | `8390F314D0A9066DDD5FCBB332F03291A83EC8F60870147FEA33F625C89E336B` |
| new | `apps/client_flutter/test/shift_swap_navigation_test.dart` | `21A3E6FCA13C6351591F7F12948EB18C55DF96124983B9A6BF641FE0F87E89B7` |
| new | `apps/client_flutter/test/shift_swap_ui_fixture.dart` | `58BDBFB7B476EEE089CBDBB28C063C332CC2FD5FDDEA6056F6EE733FCCF98D69` |
| new | `apps/client_flutter/test/shift_swap_ui_test.dart` | `0552E421682ACA744672855CB360A8B3F7F58EB4B089222DD5D9DCDE15576AF8` |
| new | `apps/server/test/shift_swap_browser_test.dart` | `80F0D27ED63D2926EA490CA8621466EAD62B12D2808D095495078910C0B1BF14` |
| M | `apps/server/test/shift_swap_stage_a_fixture.dart` | `541085E6D6FD55E1CFD14A0E2398A3150C88894A669A3D7529381111C006443D` |
| new | `docs/development/phase-4-16-stage-b3b.md` | See external final manifest for the self-hash |

The reviewed implementation was submitted for independent Step 9 functional and
Security review with these twelve hashes. Its independent result was **STAGE B3b
CHANGES REQUIRED**, as recorded at the beginning of this document.

## Current thirteen-path inventory and SHA-256

Exactly **13 changed paths** relative to the approved baseline: **five tracked
modifications and eight new files**, with an empty index. The B3B-01 delta from
the reviewed snapshot is only the home navigation guard, new shortcut tests and
this handoff. The other ten reviewed source/test files and all thirteen historical
evidence logs still match the original manifest. All 29 migration byte hashes and
Git blobs match. Baseline/HEAD/local main/origin/main and branch remain unchanged.
No backend runtime, API/contract/OpenAPI, dependency, unrelated or Step 10 path
changed. Boundary evidence: `.local/p416-b3b/b3b01/boundary-audit.json`.

The current external manifest is
`.local/p416-b3b/b3b01/final-manifest.json`. It records all thirteen current raw
file hashes, including this handoff, migration fingerprints, the preserved review
and original harness, reproduction/build/browser logs and probe-source hashes.
This handoff's self-hash lives there to avoid a circular hash. The historical
`.local/p416-b3b/final-manifest.json` remains unchanged.

| State | Path | SHA-256 |
| --- | --- | --- |
| new | `apps/client_flutter/integration_test/shift_swap_test.dart` | `612391C8505764B9164AAD192C078E66521A9842C2BE882D6DA48FECBA836E22` |
| M | `apps/client_flutter/lib/src/app/storeos_app.dart` | `FC5A647747B093219519DC490852CF926CF0EEE22A71EF88BB3C7F1BD2B22CD8` |
| M | `apps/client_flutter/lib/src/application/shift_swap_controller.dart` | `A80823FA58A2F4FCB454ECBD0AD9B7F80DE066382B74FF17D9CC3329217F734F` |
| M | `apps/client_flutter/lib/src/ui/platform_home_screen.dart` | `F4B29A57E71418491C0B676EE27A0E48CFBAFE3249AEE7C58E068EE74D6E9B25` |
| M | `apps/client_flutter/lib/src/ui/shift_section.dart` | `DD12CF1D66C97FE53BB2FEFABAD17EA83151B1632A5AF367EDA4D1FB5CC2D70B` |
| new | `apps/client_flutter/lib/src/ui/shift_swap_section.dart` | `8390F314D0A9066DDD5FCBB332F03291A83EC8F60870147FEA33F625C89E336B` |
| new | `apps/client_flutter/test/shift_swap_navigation_test.dart` | `21A3E6FCA13C6351591F7F12948EB18C55DF96124983B9A6BF641FE0F87E89B7` |
| new | `apps/client_flutter/test/shift_swap_shortcut_test.dart` | `044B87D8D3A835D79E7F564B2A24FBBCDB790B1FBF893AFDC2ED071D3DCF72A4` |
| new | `apps/client_flutter/test/shift_swap_ui_fixture.dart` | `58BDBFB7B476EEE089CBDBB28C063C332CC2FD5FDDEA6056F6EE733FCCF98D69` |
| new | `apps/client_flutter/test/shift_swap_ui_test.dart` | `0552E421682ACA744672855CB360A8B3F7F58EB4B089222DD5D9DCDE15576AF8` |
| new | `apps/server/test/shift_swap_browser_test.dart` | `80F0D27ED63D2926EA490CA8621466EAD62B12D2808D095495078910C0B1BF14` |
| M | `apps/server/test/shift_swap_stage_a_fixture.dart` | `541085E6D6FD55E1CFD14A0E2398A3150C88894A669A3D7529381111C006443D` |
| new | `docs/development/phase-4-16-stage-b3b.md` | See current external manifest for the self-hash |

**B3B-01 FIXED LOCALLY. Ready for independent targeted re-review.** Stage B3b
remains **CHANGES REQUIRED** pending that review; B3A-01 remains independently
closed. P4.16 remains **IN PROGRESS**. All changes remain local and uncommitted.
No commit, push, PR, merge, deployment or Step 10 work was performed. Stop here.
