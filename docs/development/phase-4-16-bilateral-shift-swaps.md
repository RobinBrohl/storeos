# P4.16 — Employee-proposed bilateral swap of pristine future Shifts

Status: **SELECTED / DESIGN IN PROGRESS**. Owner selection and documentation-only
authorization: **2026-10-13**. Implementation is **NOT AUTHORIZED**. Nothing in
this contract constitutes implementation, executed acceptance or DONE/CLOSED.

Source baseline: clean local `main`, HEAD and cached `origin/main` at
`8a0198f3430cb7ec636e952522dda7cf930b7fca`. Migrations **0001–0027** exist;
`0028` is the next available migration number at this baseline. Recheck before
implementation; no migration is created by this design pass. The baseline's
[CI 38371738062](https://github.com/RobinBrohl/storeos/actions/runs/38371738062)
was verified successful in the preceding assessment; it is not P4.16 acceptance.

[ADR 0030](../adr/0030-bilateral-shift-consent-and-shared-handoff-claims.md)
records the selected architecture. The [implementation plan](phase-4-16-implementation-plan.md)
orders future work and its gates. [Status](../roadmap/status.md) owns delivery.
P4.1–P4.15 remain DONE/CLOSED within their accepted scopes. P4.11/P4.15 evidence,
qualifications, historical pending/unselected statements and live debt are retained.

## Independent architecture review and documentation finalization

The owner supplied the independent verdict **ARCHITECTURE APPROVE**. Its only
reported finding, LOW/nonblocking F01, omitted the private Workforce overlap
repository from implementation-plan Step 3. The plan now explicitly includes
`apps/server/lib/src/workforce/shift_repository.dart`, with the exact two persisted
original Shift exclusions exposed through the Workforce public owner port only.
F01 is resolved by that bounded documentation correction; no fresh independent
re-review result is asserted and the approved capability/contract is unchanged.

This is approval of architecture/design, **not verified database enforcement**.
No SQL migration, runtime implementation, executed P4.16 acceptance, independent
implementation functional/Security approval or P4.16 CI success is established.
Implementation remains NOT AUTHORIZED. The owner authorizes one local documentation
commit of this finalized design baseline; push/merge and implementation require
separate authorization. The source baseline above remains the implementation base.

## 1. Goal and bounded journey

An Employee exchanges one complete planned Shift with a named colleague through
exact bilateral consent and independent managerial approval. This reduces manual
roster coordination without granting colleague-roster access or editing published
ownership in place. All operations use the local server; WAN independence does
not imply disconnected-device writes.

1. A selects A's own pristine future published Shift and names B.
2. B sees that invitation, selects one of B's own eligible pristine future published
   Shifts and explicitly offers the exact counterpart.
3. A reviews and explicitly confirms the immutable two-Shift pair.
4. An independent authorized manager approves or rejects that exact pair.
5. Approval cancels both originals and publishes two exact replacement Shifts,
   each interval/work set assigned to the other Employee. Both employees execute
   their incoming work through ordinary Employee Home.

Both Employees are distinct, currently active and linked to valid Accounts. All
resources belong to the same configured Company and execution Location. Each
original has the existing supported 1–10 ordered Tasks; maximum paired lineage
is 20 Tasks. No schedule mutation occurs in steps 1–3.

## 2. Privacy, exact pair and identity

The existing P4.11 recipient finder exposes ID/name, not colleague Shifts, and
filters recipients using one-way overlap rules. Do not reuse its endpoint or its
overlap filter unchanged: B's departing Shift can overlap A's interval and still
permit a valid final exchange.

New discovery authorizes A's current own Shift before returning only scoped
Employee ID/display name for currently linked colleagues eligible to receive A's
interval. It returns no Account details, employment dates, Shift counts, intervals,
workloads or reasons another colleague was filtered. The server may privately
evaluate needed People/Identity facts through their ports.

B's counterpart candidates are request-scoped **own** Shifts only. A cannot call
this endpoint. Candidate pages show own Shift ID/version/interval; selected detail
shows own work summary. Feasibility evaluates the prospective pair privately,
without exposing either person's other roster rows. No arbitrary exclusion-ID
list is accepted from clients.

Before offer, B sees only A's deliberately disclosed leg. After offer, A sees only
B's selected leg. Participant summaries contain identity/display information,
Location, intervals, original Shift/version, ordered Task titles and exact Task,
Template/revision and Knowledge/Planogram references. They exclude execution
measurements, blockings, personnel files, Account versions/link IDs, unrelated
roster and instruction bodies. Pin metadata grants no arbitrary historical
Knowledge/Planogram read. Existing own-work guidance reads remain unchanged.

The pair identity is `(Company, requestId, offerVersion=2)`, with immutable A/B leg
facts. B's offer receipt binds the requested A leg and selected B Shift/version;
A's confirmation receipt binds that same stored pair. Request/version references
are sufficient because neither leg is editable after offer. Both receipts retain
the exact accepted pair summary. Changing either Shift, interval, owner or work
set invalidates fresh progression; close and create a new request. A's initial
invitation is not consent to an unknown counterpart.

Capture both Account IDs, current Account versions and Account–Employee link IDs
at request creation. Offer/confirmation/approval revalidate this basis, current
session, Employee activity and incoming assignment coverage. A version/link change
cannot be repaired by returning to the previous role or by replacing an Account.
A newly linked Account may read Employee-owned participant history under current
scope, but cannot inherit consent or replay another Account's command.

## 3. Lifecycle, versions and closure

Persist lowercase wire states; the uppercase names below are their display names.
Every accepted transition advances request version by exactly one. Terminal rows,
accepted consent and original leg facts cannot be edited, deleted or reopened.

| Command | Actor | From | To/version | Evidence and effect |
| --- | --- | --- | --- | --- |
| request | A, current source owner | absent | REQUESTED / 1 | Capture identities and A leg; claim A; no pair consent or schedule change. |
| offer | Captured B Account/link | REQUESTED / 1 | OFFERED / 2 | Capture immutable B leg, exact pair and B consent; atomically claim B. |
| confirm | Captured A Account/link | OFFERED / 2 | CONFIRMED / 3 | Record A consent to the stored pair; keep both claims. |
| decline | Captured B before offer; captured A after offer | REQUESTED / 1 or OFFERED / 2 | DECLINED / 2 or 3 | No schedule change; retain any existing offer/consent; release owned claims. |
| withdraw | Current eligible A source identity; captured B after offering | A: any active state; B: OFFERED or CONFIRMED | WITHDRAWN / previous+1 | Reason required; retain all evidence; release all owned claims. |
| reject | Scoped manager | Any active state | REJECTED / previous+1 | Reason required; usable even with stale participant bindings; release all owned claims. |
| approve | Independent scoped manager | CONFIRMED / 3 | APPROVED / 4 | Exact atomic paired replacement, lineage, receipts, audit and claim release. |

A's current eligible source identity may withdraw stale work after Account replacement,
as in P4.11 source closure; this records a new closing actor, not inherited consent.
B response/withdrawal uses the captured Account/link. Offboarded participants need
authorized manager rejection. Decline collects no personnel note. Withdrawal and
rejection reasons use the existing trimmed plain-text 1–500 Unicode-code-point
bound, reject control characters and remain in protected business evidence.

Keep four concepts separate:

- **Business state/evidence:** durable lifecycle, immutable legs and accepted consents.
- **Actionability:** current derived eligibility plus a bounded reason code and
  available actions; never a persisted replacement for business state. Closure
  can remain available when offer/confirmation/approval is unavailable.
- **Receipts:** immutable accepted command/result evidence, not current detail.
- **Claims:** durable current occupancy of original Shifts, not a schedule lock.

Time crossing, execution, interval amendment/cancellation, link or Account change
and guidance invalidation make progression non-actionable. They do not silently
change state, erase consent or expire claims. No scheduler or automatic expiry is
introduced. A participant closure or manager rejection explicitly frees them.
Ordinary execution and existing amendment/cancellation remain available; claims
arbitrate incompatible handoff workflows rather than disabling normal work.

## 4. Persistence and shared claim authority

The proposed five new tables are bounded to this capability; names are future
implementation targets, not existing tables:

| Owner/table | Key and responsibilities |
| --- | --- |
| Workforce `workforce_shift_swap_requests` | PK `(company_id,id)`; unique scoped request anchor `(company_id,id,location_id)`; participant Employee/Account/link/version basis, lifecycle, offer/confirmation/terminal metadata and immutable receipt references. |
| Workforce `workforce_shift_swap_legs` | PK `(company_id,request_id,leg)` where leg is `a` or `b`; immutable original Shift/version/owner/interval and server-derived ordered work references; narrowly assigned replacement Shift ID at approval. A exists from request; B only from offer. |
| Workforce `workforce_shift_swap_commands` | PK `(company_id,operation_id)` in the swap-command namespace; actor, Location, request, kind, canonical input, accepted version, status and original result. Append-only. |
| Workforce `workforce_shift_handoff_claims` | PK `(company_id,shift_id)`; one typed transfer source or swap leg owner, scoped Location and owner FKs; current occupancy only. |
| Tasks `task_swap_links` | PK `(company_id,request_id,leg,position)`; scoped leg, source/replacement Shift and Task identities, Template/revision/position; unique source and replacement Task within this lineage family; append-only. |

Scoped relational anchors must bind each leg to
`shifts(id,company_id,location_id,employee_id)` for original and incoming replacement
owners; bind both participant Employees and Accounts to the same Company/Location;
and bind captured links to their exact Account/Employee tuple using the released
0023 anchor. Leg/lineage anchors include Company, request, Location, leg and both
Shift IDs. Task FKs use the released Task identity tuple from 0023. Add only the
necessary unique anchors, without rewriting any historical row.

Keep existing Task schemas 1–4 and Template revisions unchanged. No new Task
content schema or republishing is required for swap lineage. Tasks-owned approval
validation also checks source/replacement Employee ownership, exact Task counts,
cancelled source versus pristine replacement versions and full frozen content
equality; a matching Template/revision tuple alone is insufficient.

Receipt/leg/replacement-pointer FKs that are completed within the same approval
transaction must be deferrable, as in 0023. Deferred guards require both legs and
both replacement pointers only for fresh approval; terminal non-approval keeps
null replacements and any previously offered B leg. Do not make later replacement
execution depend on permanent approval-time published/open conditions.

Leg work-reference arrays are server-derived immutable snapshots, at most ten,
with unique Task IDs and contiguous positions 0..N-1. They contain identity/order/
pin references, not copied instructions or execution values. A narrow **Tasks-owned
SQL integrity port** validates exact reference set/content against its own tables;
the Workforce deferred guard calls this port rather than introducing application
foreign-table reads. Dart Application uses the corresponding Tasks public port.
Publication freshness belongs to current authorized use cases; retained reference
integrity must not require permanent current guidance activity.

### Claim invariant and occupancy

For each Company and original Shift, **at most one active incompatible handoff
claim exists**, across P4.11 and P4.16. Claim ownership is exactly one of:

- `(company,transfer_request_id,location,source_shift_id)`; swap owner/leg null.
- `(company,swap_request_id,location,leg,source_shift_id)`; transfer owner null.

Use a strict XOR shape check rejecting SQL NULL/UNKNOWN, scoped FKs and immutable
ownership. Add the required scoped source anchor to the existing transfer request
table in the new migration, retaining `transfer_active_source` unchanged. No second
swap-specific reservation system or Employee/time-slot reservation is introduced.

| Parent state | Exact required claim set |
| --- | --- |
| P4.11 proposed/accepted | Transfer source only. |
| Swap REQUESTED | A only. |
| Swap OFFERED/CONFIRMED | A and B, each bound to the exact leg. |
| Any terminal parent | None. |

Owner lifecycle hooks maintain claims for **both** families in their existing
authorized transaction. Immediate PK uniqueness arbitrates occupancy; deferred
parent/leg/claim guards enforce exact cardinality, scope and ownership and reject
missing, extra, orphaned or wrong-owner claims. Check all affected parents after
claim insertion/deletion; checking uniqueness alone is insufficient. A claim can
be deleted only as part of its owner's terminal transition. Requests/receipts/
lineage retain acquisition and release meaning, so deleting this current-state
projection is not deleting business evidence.

The existing Company advisory lock serializes supported writers. Acquire both
claims/rows in deterministic Shift-ID order when both are involved. A conflicting
claim returns a scoped busy conflict without disclosing another request's details.
Never steal/reassign a claim. Failure acquiring B rolls back B leg, B consent,
request transition, receipt and audit; A's existing invitation/claim survives.
Opposite invitations can claim their separate A legs; neither may steal the
other's leg. Explicit closure of one invitation is required, not automatic merging.

### Minimal P4.11 integration

Use the shared Workforce pending-claim query for one-way source selection/proposal,
and map its database conflict to the existing `409 transfer_already_pending` path.
Keep the old local unique index and add the shared lifecycle hooks/consistency
guards. Old payloads, kinds, DTOs, consent rules, states, receipt namespace, stored
results and Task/Shift lineage remain unchanged. The only new business refusal is
an original Shift occupied by a swap. P4.11 alone retains accepted behavior,
including explicit stale closure and historical replay.

## 5. Authorization, receipts and audit

Proposed fixed capabilities are `workforce.swaps.self.read`,
`workforce.swaps.self.request`, `workforce.swaps.self.respond` and
`workforce.swaps.manage`. Admin receives all; Employee receives the three self
capabilities; Viewer/Auditor/plugin receive no swap business capability. Existing
audit access remains separately authorized. No configurable role/grant system.

Request/colleague discovery and A withdrawal require self.request; offer, confirm,
decline and B withdrawal require self.respond, with exact participant-role checks;
all self commands additionally require self.read and current eligible linkage.
Manager reads/rejection require manage; approval also requires
`workforce.shifts.manage`, `tasks.instances.read` and existing guidance-read rights
where pins exist. Approver Account differs from both consenting Accounts.
This is the existing independent-Account policy, not proof of human-person
independence across unlinked Accounts.

Every resource read/write/replay requires current session, configured Company,
actor/route/resource Location equality and appropriate participant/manager scope.
Resolve Employee and actor from current authenticated context, never client fields.
Current resource authorization precedes receipt lookup and disclosure.

Swap receipts use Company + swap operation UUID. Bind actor, Location, request,
kind and canonical input, including all expected versions. Exact replay returns
the original accepted result before fresh lifecycle/claim/clock/guidance checks.
It performs no request update and no claim resurrection, even after terminal
release and later work. Changed bindings return `409 operation_conflict`.
Failed transactions consume no UUID. P4.11 keeps its existing separate receipt
namespace; shared claims do not imply global cross-family UUID deduplication.

Audit request/offer/confirmation/decline/withdrawal/rejection/approval atomically.
Use IDs, leg identifiers, versions and state transitions; do not duplicate names,
interval summaries, instructions, execution values or user reasons in new swap
audit/log fields. Existing owner-level Shift/Task audit remains atomic. Add only
the needed identifier allowlist entries. No real asynchronous consumer exists,
so no swap event, notification or outbox contract is selected.

## 6. Atomic approval and final validity

One coordinator calls public Workforce, Tasks, People, Identity, Knowledge and
Merchandising ports in **one** `runAuthorized` transaction. Never compose two
HTTP transfers, two independently committed operations or nested authorized
transactions. Work belongs to its existing module, not the coordinator.

Fresh approval, after authorized exact-replay handling:

1. Require CONFIRMED / 3, same immutable pair/consents and independent manager.
2. Re-read both originals and owned claims. Match captured Shift versions, published
   state, Company/Location, owners and exact intervals. Validate the full source
   Task sets against captured references: 1–10 each, open/version 1, no start,
   results, numeric attempts, blockings or execution-command evidence.
3. Revalidate captured links/Account versions, current Employee activity and
   assignment coverage for both incoming intervals. Preserve current supported
   assignment boundaries. This is not a check of a legal employment contract,
   absences, qualifications, breaks or labor-law compliance.
4. Validate the exact guidance using current owner rules. A superseded published
   Knowledge revision can remain usable while its Article is active; retirement
   prevents fresh replacement publication. Planogram guidance requires the exact
   current eligible Assignment and its current Article/Assortment checks. If
   unavailable, reject the exchange; never select a newer pin automatically.
5. Evaluate `published roster - {A,B} + {A interval to B, B interval to A}`.
   Exclude exactly the two persisted departing Shift IDs. Reject third-Shift
   overlaps; half-open adjacent intervals remain valid. Equal/intersecting original
   intervals can be valid because recipients are distinct and both originals leave.
6. Check fresh database `clock_timestamp()` before both captured starts, then
   cancel **both** original Task sets/Shifts through owner ports before publishing
   either replacement. Retain the existing immediate published-overlap exclusion.
7. Create two server-ID replacement drafts with incoming Employee ownership,
   unchanged intervals and exact ordered selections. Materialize Tasks through
   a narrow swap replacement port; verify every full frozen Task content/pin is
   equal to its source. Existing `createTransferReplacement` remains P4.11-specific;
   its lineage FK cannot simply receive a swap request ID.
8. Publish both replacements with existing overlap enforcement; persist complete
   paired Shift lineage, ordered Task links, APPROVED / 4, original result receipt,
   minimized swap audit and release both claims, all in this transaction.
9. At transaction completion, a deferred fresh-approval guard validates both
   original cancellations/version advances, both exact published replacements,
   both complete Task correspondences and content equality, both consents,
   exact decision/receipt and zero terminal claims. It invokes Tasks-owned SQL
   validation, then checks fresh database time last against `min(A.start,B.start)`.

Keep this constraint initially deferred through supported transaction completion;
do not force it early and then perform further approval work. The guarantee is
future work at the final deferred database validation boundary, not client response
time or an exact wall-clock promise about WAL durability. Use database time, not
Flutter/app clocks. Boundary crossing rolls back everything, as in P4.11.

Deferred approval checks run on fresh approval only. Later ordinary replacement
execution/cancellation and historical receipt replay must not reapply permanent
published/open/future conditions. Any failure, including a late audit/receipt or
second-leg failure, leaves the original confirmed request/claims and zero partial
replacement effects. Successful lineage does not grant the old owner ordinary
access to incoming work assigned to the other Employee.

## 7. Planned HTTP and Flutter contract

All roots below are **design only**, relative to `/api/v1/platform`; no router,
DTO, generated OpenAPI or test is added in this documentation pass.

| Operation | Planned route | Strict command intent |
| --- | --- | --- |
| Own colleague discovery | GET `/employee-home/shifts/{id}/swap-colleagues?after=` | Own A Shift; bounded identity page; no colleague roster. |
| Own request list/create | GET/POST `/me/shift-swaps` | POST: requestId, operationId, sourceShiftId, expectedSourceVersion, recipientEmployeeId. |
| Participant detail/history | GET `/me/shift-swaps/{id}` and `/history?after=` | Scoped original evidence versus current actionability. |
| B counterpart candidates/detail | GET `/me/shift-swaps/{id}/counterparts?after=` and `/counterparts/{shiftId}` | Captured B only; own candidate metadata/selected summary. |
| Offer | POST `/me/shift-swaps/{id}/offer` | operationId, expectedVersion=1, counterpartShiftId, expectedCounterpartVersion. |
| Confirm | POST `/me/shift-swaps/{id}/confirm` | operationId, expectedVersion=2; binds the stored offer pair. |
| Decline/withdraw | POST `/me/shift-swaps/{id}/decline` or `/withdraw` | operationId, expectedVersion; reason only for withdrawal. |
| Manager list/detail/history | GET `/locations/{locationId}/shift-swaps`, `/{id}`, `/{id}/history` | Scoped manager projection, no unrelated roster through swap endpoints. |
| Approve/reject | POST `/locations/{locationId}/shift-swaps/{id}/approve` or `/reject` | operationId, expectedVersion; reason only for rejection. |

POST request returns 201; other accepted commands 200; replay returns the original
command's status/result with explicit replay metadata. Reject duplicate decoded
JSON names, unknown fields/query keys, noncanonical types and injected actor,
Employee owner, replacement, snapshot or timestamp fields. Canonicalize UUIDs and
existing explicit UTC/offset instants; no new local-calendar/time-zone policy.
Use request body limit 8192 bytes, reason bounds above, original receipt result
limit 65536 UTF-8 bytes and pages of at most 50. Scoped opaque cursors bind Company,
Location, endpoint, participant/request, filters and relevant captured basis;
limit cursor strings to 2048 characters. Detail contains at most two legs/20 links.

Specify and test every route's actual error set in DTO/OpenAPI work: 400 invalid
request/JSON/cursor; 401 invalid session; 403 missing capability/configured scope;
404 protected resource/participant unavailable; 409 operation/version/claim/overlap
conflict; 422 current Shift/identity/guidance eligibility failure; definitive parser
413/415; 503 dependency unavailability; 500 unexpected integrity defects. Do not
map unrelated database constraints to user errors. Old P4.11 retains its documented
codes, including transfer_already_pending for the added shared busy case.

Flutter adds a request shortcut from own future work; named colleague picker;
incoming invitation/B own counterpart picker; exact two-leg review and B offer/A
confirmation; participant lists/history/closure; manager confirmed-pair review,
rejection, approval and both lineage legs. No global colleague-roster navigation.
Buttons are hints, not authorization; server freshness wins. Display intervals in
the existing explicit UTC convention. Plain text renders literally.

Pending commands freeze route, body, UUID and opaque session/Location identity
before dispatch. Uncertainty permits exact retry only; later denial does not prove
earlier rollback. Same/different Account replacement clears mounted forms, choices,
history and pending state and fences delayed results. Confirmed effects survive
refresh failure; stale actionable detail is cleared. Memory-only tracking is not
offline durability. Reload uses authorized durable requests/receipts/lineage.

## 8. Migration, runtime grants and recovery

Plan **0028_bilateral_shift_swaps.sql** after rechecking the available number.
Never edit 0001–0027. Preserve existing IDs, quantities, frozen units, P4.15 profiles,
bindings/revisions/receipts and all original Shift/Task/P4.11 evidence.

Run the upgrade with existing application writers stopped/drained and the site
fenced; the migration advisory lock alone is different from the Company business
lock and is not a live-write fence. In one rollback-capable migration transaction,
add tables/anchors/guards, backfill one claim for **every** historical active P4.11
source including stale requests, and verify exact ownership/cardinality before
enabling swaps. Do not invent past claims for terminal transfers, revise consent
or repair unexpected data silently. A bad backfill/late guard must roll back all
new DDL and claims and leave populated 0027 evidence/checksums intact.

Update MigrationRunner's runtime-grant branch for 0028: SELECT/INSERT on new
evidence; only lifecycle/one-time consent/decision columns on requests and the
one-time replacement pointer on legs may UPDATE. Receipts, captured leg facts
and Task links are append-only. Claims allow SELECT/INSERT and guarded terminal
DELETE only; no UPDATE/ownership reassignment or TRUNCATE. No SECURITY DEFINER,
broad evidence DELETE or new module writer is justified. Lifecycle hooks run
under the restricted caller grants. Tests must prove unauthorized claim deletion,
missing claims, wrong scope/owner, NULL/UNKNOWN and incomplete approval refusal.
Retain the supported-writer/privileged-owner threat boundary.

Encrypted PostgreSQL backup/isolated restore must preserve new evidence and active
claims alongside old evidence. Restored claims still correspond to restored active
parents, even when fenced/revoked identities make progression unavailable. Reopen
only through the existing authorized recovery process; manager closure and exact
replay require current authorization. No automatic activation, downgrade, sync or
resurrection of revoked consent. Record hashes/counts, integrity and scoped API
reads/replay/closure after restore, not merely successful dump/restore commands.

## 9. Acceptance cases and independent gates

These are **required future cases, NOT EXECUTED**. Use disposable restricted
PostgreSQL, real HTTP, Flutter and actual Chrome; mocks alone are insufficient.

| ID | Required proof |
| --- | --- |
| A01 | A requests; B offers an own Shift; A confirms the exact pair; independent manager approves. No schedule effect before approval; both incoming replacements execute through Employee Home. |
| A02 | B cannot offer another Employee's Shift; A cannot call B's candidate endpoints; guessing peer/foreign IDs/cursors and manager routes is denied without roster or receipt disclosure. Viewer/Auditor/plugin, revoked sessions and other Company/registered Location are denied. |
| A03 | Confirm without B offer, manager approval before A confirmation, changed pair, same Employee/Shift, changed link/Account basis and participant manager approval refuse with zero effects. |
| A04 | Every decline/withdraw/reject path advances one version, retains prior consents, frees exactly owned claims and supports original replay. Terminal edits/reopening/deletion refuse. Stale reads change actionability only; source/manager closure remains possible. |
| A05 | Two intersecting/equal outgoing intervals can exchange; adjacent third intervals are valid; genuine third-Shift overlap rejects. Client-supplied exclusion lists cannot bypass checks. |
| A06 | Maximum ten Tasks per leg: exact ID/Template/revision/order/content and independent Knowledge/Planogram pins are captured, preserved and linked completely. Historical originals remain readable only in authorized history. |
| A07 | Observe Company-lock queues in both orders for transfer/request versus swap request/offer and swap versus swap involving either leg; one occupancy winner, no double claims or partial offer. Opposite invitations require explicit closure. |
| A08 | Source execution, amendment, cancellation, Account deactivate/role ABA, link replacement and Employee assignment changes before/after queued progression produce the expected winner/stale outcome without inherited consent. Ordinary work is not blocked by claims. |
| A09 | Knowledge R2 publication retains valid exact R1; Knowledge retirement and Planogram reassignment/retirement/Article-Assortment invalidation reject fresh approval without repinning. Both source snapshots remain unchanged. |
| A10 | Inject failure during second cancellation/replacement/Task materialization, paired linkage, receipt, audit and deferred guard; original published work/request/claims match pre-command evidence, no partial effects and failed UUID remains usable. |
| A11 | Cross either start behind an observed late barrier after attempted effects; final database-time guard rejects and rolls back. Before-boundary success and authorized historical replay after starts do not rerun fresh guards. |
| A12 | Drop each mutation response, restart server, retry identical command: one transition/effect/audit and original result; changed actor/payload/route UUID conflicts. Terminal replay never recreates released claims. |
| A13 | Same/different Account and Location replacement fence mounted offer/confirmation forms and held responses; uncertain command retains immutable intent through later denial; confirmed failed refresh cannot cause another approval. |
| A14 | Populated 0027 upgrade retains historical P4.11 active/stale/terminal requests, receipts and lineage; backfills only required claims. Fresh install, rollback injection, runtime grants, malformed SQL evidence and NULL/UNKNOWN guards are exercised. |
| A15 | Encrypted isolated restore and forward update/recovery retain both swap/transfer evidence and claims, deny restored stale credentials, and prove current scoped replay/closure. Existing P4.15 evidence hashes/meaning and accepted qualifications remain. |
| A16 | Real Chrome four-actor-role flow (A, B, independent manager and denied observer), both replacement journeys, privacy, stale conflicts, long labels and literal content; fail on framework exceptions. No native-device/accessibility acceptance inferred. |

Required completion gates after separate implementation authorization: pinned
format/analyzers, meaningful domain/contract/HTTP/PostgreSQL/Flutter suites, old
P4.11 regression and all affected package regression, explicit opt-in browser
journeys, release Web build, populated migration/update/recovery and encrypted
restore, independent functional review and independent focused Security review
with required findings closed, then successful exact implementation-commit CI.
Skipped cases remain skipped until separately executed; documentation/ADR approval
is not these gates. Commit/push/merge need separate authorization.

## 10. Exclusions, standing limits and blockers

No partial shifts, begun work, general colleague roster, availability planning,
qualification engine, attendance/payroll, automatic labor-law validation, marketplace,
recurrence, notifications, remote self-service, device offline queues or multi-site
transfers. No generic workflow/receipt engine, event framework, configurable RBAC,
second Shift ownership model or unrelated Stock/Purchasing/Production changes.

P4.15's six qualifications remain: memory-only uncertainty; immutable prospective
semantics and permanent suspension; F04 nonblocking Location-picker debt; physical/
accessibility/operator readiness; plugin-specific execution limits; broader
acceptance boundaries. M1 pilot proxy disposition, contained M3/M4 endpoint debt,
P4.12 INFO observations and all other [live debt](technical-debt.md) keep their
existing disposition. New endpoints must contain M3/M4 locally. Retention,
offboarding/export, recovery custody/RPO/RTO and supported devices remain existing
operator gates, not newly invented P4.16 policy prerequisites.

No architectural contradiction or unresolved owner policy choice is known within
the selected bounded contract. Database/grant/lineage feasibility still requires
the specified executable proofs; this document does not claim they passed.
**Implementation authorization remains required.** Stop and report if those proofs
reveal a contradiction requiring scope/ownership/consent changes; never silently
weaken P4.11 guarantees or claim completeness by omitting a leg.
