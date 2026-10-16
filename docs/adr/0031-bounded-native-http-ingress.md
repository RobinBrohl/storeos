# ADR 0031 — Bounded native HTTP ingress

Date: 2026-10-16. Status: **Implemented and locally remediated after independent
CHANGES REQUIRED for INGRESS-01/02; independent targeted re-review pending.**
P4.16 remains IN PROGRESS.

## Context

The B2a targeted re-review independently closed F01–F03 but returned **STAGE B2a
INSUFFICIENT EVIDENCE** for finite retention of indefinitely unfinished uploads.
Two original incomplete-upload assertions remain failed historical evidence. No
material resource-exhaustion vulnerability was demonstrated. The subsequent
read-only architecture assessment returned **DESIGN READY FOR SEPARATE
IMPLEMENTATION AUTHORIZATION**. The owner then authorized this bounded ingress
implementation, subject to feasibility inspection of Dart 3.13.4 / Shelf 1.4.2.
The security-testing interruption remains binding; no new unfinished-upload
network probes, load simulations or scanner-access retries are authorized.

Byte limits constrain JSON accumulation but do not constrain an active socket's
lifetime. Native response writing can drain unread input before sending headers.
Idle keep-alive expiry does not protect a request that has become active.

## Decision

Use public `dart:io` interfaces around `ServerSocket.bind`, `HttpServer.listenOn`
and `Socket`, with Shelf's public `handleRequest` adapter. Production startup and
the shared HTTP/PostgreSQL fixture use `GuardedHttpServer.bind`.

| Control / environment variable | Default | Validation |
| --- | ---: | --- |
| `STOREOS_HTTP_MAX_CONNECTIONS` | 64 | 1–4096 |
| `STOREOS_HTTP_MAX_REQUESTS` | 32 | 1–connections |
| `STOREOS_HTTP_MAX_BODIES` | 16 | 1–requests |
| `STOREOS_HTTP_BODY_SECONDS` | 30 seconds | 1–300 |
| `STOREOS_HTTP_DISCARD_MILLISECONDS` | 1000 ms | 1–body lifetime in ms |
| `STOREOS_HTTP_IDLE_SECONDS` | 15 seconds | 1–300 |

Programmatic policy construction also validates the ordering and finite positive
bounds before binding. Invalid configuration fails startup without logging its
raw values. Existing host configuration, including the default `127.0.0.1`, stays
supported. These are initial deployment policy values, not certified hardware
capacity limits. There is no application admission queue.

### Admission and connection ownership

The `ServerSocket` adapter admits at most 64 accepted sockets **before HTTP header
parsing** and immediately destroys excess sockets. A public `Socket` adapter
intercepts every native `destroy()` call. Release follows a call to the underlying
physical `Socket.destroy()`; neither response construction nor a send-side future
alone releases connection admission. Send-side completion triggers our own
two-direction destroy before release. Idempotent release prevents duplicate permits.

Connection lookup uses public `HttpConnectionInfo` remote address/port and local
port, scoped to this one listener. Missing metadata fails closed. Public metadata
omits the destination address, so duplicate live keys on wildcard bindings are
rejected before HTTP parsing rather than replacing an existing socket owner.
At request delivery, request and body permits are acquired synchronously or the
connection is destroyed. The SDK processes one request at a time per connection; rejected
requests are never put on an application waiting list.

A header timer uses the body-lifetime value: 30 seconds from accept or the end of
the previous response. It is cancelled when complete headers produce a request.
Queued callbacks check timer identity so an old header timer cannot kill later
work. Headerless and partial-header connections therefore also have a finite
lifetime. Native idle timeout additionally manages keep-alive connections; pinned
Dart's periodic implementation may take up to twice the configured idle interval.
Continuously useful connections have no fixed total-age limit.

### Body ownership and termination

Before authentication or Shelf dispatch, `UploadLifecycle` arms both native
`HttpResponse.deadline` and an absolute application timer. In the inspected pinned
SDK, deadline expiry calls `_HttpConnection.destroy`, which calls public
`Socket.destroy()` without awaiting input. Private names here describe inspected
SDK internals; StoreOS calls no private APIs, reflection or runtime patches.

There is exactly one native body subscription. It starts paused; the Shelf-facing
single-subscription stream propagates pause/resume. Empty framed bodies resume
immediately to observe EOF without waiting for authentication. JSON readers check
the remaining byte allowance **before appending** a chunk. No broadcast stream,
unbounded discard buffer or second native subscriber is used.

Transitions are:

- Reading -> complete: only error-free native `onDone` sets complete, cancels both
  guard timers, clears the native deadline and releases the body permit once.
- Reading -> discard: reader cancellation or an unconsumed body at response
  construction transfers ownership to the same subscriber. Chunks are dropped,
  connection reuse is disabled, and a one-second discard timer starts. The original
  absolute timer remains armed, so this cannot extend the original lifetime.
- Reading/discard -> aborted: expiry, input error, connection destruction or
  shutdown sets aborted, advances native deadline to zero and directly destroys
  the physical socket before initiating asynchronous cancellation. It emits
  `UploadAborted`, never successful EOF. Repeated cleanup has no effect.

The zero deadline on abort replaces any retained SDK deadline timer with immediate
native termination; it does not clear protection. The guard's own timer also
protects the lifetime independently of SDK response-completion timer cancellation.

When a handler returns without consuming the body, the adapter allows only the
bounded discard phase before writing its response. Completed rejected inputs can
therefore retain their ordinary 400/413/415 response. Expired unfinished inputs
terminate at transport level. This introduces no promised pre-EOF 413 or new 408.
Aborted body reads propagate before JSON decoding and Application invocation.
No mutation retry is introduced.

Body permits end at EOF/abort. Dispatched-request permits remain held until the
actual handler/response future finishes, even after disconnect, preventing closed
sockets from admitting unbounded still-running handlers. Already valid business
work is not cancelled or rolled back merely because its connection disappears.
After genuine body EOF there is no upload timer during business processing.


### Body completion before non-consuming command mutations

The independent native ingress review returned **STAGE B2a CHANGES REQUIRED**
for INGRESS-01 (MEDIUM: logout revocation before EOF) and INGRESS-02 (LOW: empty
GET discard/connection churn). Both are locally remediated; independent targeted
re-review remains pending. F01–F03 remain independently CLOSED.

Native request framing is unambiguously empty when public
`!headers.chunkedTransferEncoding && contentLength <= 0`. Absent framing and
explicit zero therefore resume the same subscriber and await genuine native EOF
before Shelf dispatch, without discard or disabling reuse. Headers do not set
completion or clear protection. Positive Content-Length and chunked input retain
body ownership and the absolute upload timer regardless of HTTP method. An empty
chunked entity becomes complete only after its terminating chunk/native EOF.
Unconsumed body-bearing GETs still enter the normal bounded discard path.

The guard supplies its owned UploadLifecycle through trusted Shelf request
context. Body-ignoring stateful adapters drain their single body reader without
buffering or JSON validation, then require successful owned completion before
calling their existing mutation service. Premature reader cancellation, synthetic
reader EOF and discard are rejected even if native EOF arrives later. Normal
reader teardown after successful EOF is distinguished from early cancellation.
The original absolute deadline remains armed throughout consumption; errors,
abort, transport loss and expiry cannot authorize mutation.

Logout authenticates before consuming and calls unchanged AuthService.logout
afterward to revalidate and atomically revoke/audit. The same transport helper
protects event replay and plugin-event acknowledgement, the two other inspected
body-ignoring mutating adapters. Replay authenticates the session before the
gate; acknowledgement retains plugin authentication in its existing transaction
after the body gate. Their service authorization/resource checks remain intact.
Previously accepted arbitrary finite bodies remain accepted, including non-JSON
logout content; no new JSON/media validation or automatic retry is introduced.
Bodyless completed logout remains 204 and keeps a healthy reusable connection.

Upload completion remains independent from handler completion. A completed body
may authorize longer business work after connection loss. Admission, timers,
destroy-before-cancel, exactly-once releases, backpressure and shutdown ownership
are unchanged. Source/component and completed-wire tests support these local
corrections; the existing real-expiry wire/OS/Linux/proxy/hardware qualifications
and independent acceptance boundary remain binding.

### Startup and shutdown

The guard explicitly owns the listener supplied to `HttpServer.listenOn`, since
closing that HTTP server alone does not close the listener. Failed initialization
closes the listener, destroys accepted sockets and closes any created HTTP server.
Shutdown stops acceptance, destroys owned transports/active uploads, cancels the
HTTP subscription and awaits dispatched work. Repeated close calls share one future.
Application startup's `finally` then stops EventBus and closes the database pool.
Existing Windows SIGINT and Linux SIGINT/SIGTERM registration remains in place.

## Compatibility and limits

Endpoint limits stay 8192 bytes for swaps/P4.11, 16384 for defaults/login, 65536 for
Knowledge, and 262144 for Recipe/order-save. No business, permission, audit, consent,
receipt, SQL classification, schema or migration changes are part of this policy.
Ordinary completed requests retain authentication precedence, DTOs, strict names,
Unicode/cursor fixes, security headers and exact original receipt statuses.

Native guard timers require a responsive event loop. Count caps bound retained
objects/concurrent work; they are not a complete availability guarantee. JSON
accumulation remains endpoint bounded and input backpressure reaches the SDK;
native parser/kernel buffers and deployed hardware capacity are not certified.
Future intentional streaming, upgrades or multipart contracts need separate design.

The guard protects Dart backend connections, including direct access. Optional
Caddy client-facing TCP/HTTP2 streams, buffering and timeouts are a separate
deployment qualification. Backend destruction does not establish closure of the
proxy's original client connection. No mandatory proxy or dependency is added.

## Evidence and acceptance boundary

Gate A inspected the pinned SDK/Shelf sources and compiled the public interface
adapters. One completed loopback HTTP exchange verified native destroy interception.
Deterministic tests cover completion, expiry, errors, cancellation/discard, races,
duplicate cleanup, admission exhaustion, backpressure, headerless protection,
shutdown and startup rollback. They call the production `IngressSocket.destroy`
boundary using a finite fake physical transport. Completed loopback regressions
exercise native ingress and each endpoint-size tier, including declared/streamed
overflow and listener rebind after shutdown. See the [B2a evidence
record](../development/phase-4-16-stage-b2a.md#native-ingress-remediation--2026-10-16).

These establish StoreOS lifecycle/control flow and completed-request behavior on
Windows. They do **not** directly establish OS descriptor reclamation or real
unfinished-upload wire-close timing. No new incomplete-upload network test ran.
Linux execution, actual process-signal delivery and proxy frontend termination
remain unverified. A subsequent independent targeted transport review must judge
the static/component proof and any separately permitted wire-level evidence needed
for acceptance. B2a approval and broader P4.16 acceptance are not claimed.

## Alternatives

`Future.timeout` alone cannot cancel native I/O; idle timeouts, byte caps, backlog
and database pool caps do not bound active uploads. A mandatory reverse proxy
would add packaging, bypass prevention and recovery obligations. A Shelf-only
guard cannot own pre-header sockets. The selected native adapter keeps the
self-hosted Dart deployment and existing Shelf/Application boundary.
