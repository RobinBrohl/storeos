# P1 – Authenticated self-service password change

Status (2026-10-02): local implementation and verification complete (contracts,
real PostgreSQL, real HTTP and Flutter suites); independent review pending;
remote CI pending. Baseline: `0ddcd4f`.

## Goal

An authenticated, active human account holder can change their own password
after proving knowledge of the current password, without administrator
involvement. Password update, audit and revocation of all sessions of the
account commit atomically.

## Exact scope

- New route `POST /api/v1/platform/profile/password` for the session account.
- New fixed capability `identity.self.password` for all four supported roles.
- Current-password verification under the existing company-locked
  `runAuthorized` transaction; version-guarded actor-only update.
- Dedicated, bounded, process-local `PasswordVerificationLimiter`.
- Complete request/response/error contract, Dart contract and OpenAPI in both
  documents, plus a bounded consistency test.
- Flutter dialog with byte-based client validation and session-clearing success
  and ambiguous-failure handling.

Out of scope: password recovery/forgot-password, MFA, password history, expiry
or rotation, a global password-policy framework, admin-reset changes,
distributed rate limiting, the M1 reverse-proxy fix, M2/M3/M4 global cleanup,
offline behavior, migrations, new acceptance harnesses and browser E2E.

## Authorization

`identity.self.password` is granted to `admin` (shared capability list) and
explicitly to `auditor`, `employee` and `viewer`; the unknown-role fallback
remains empty. The route accepts no account, user or employee identifier; the
target is always `principal.id`. Authorization uses `PlatformDatabase.runAuthorized`
as the single primitive, so an active session, matching company/location and
the role capability are re-checked under the company lock. Plugin bearer tokens
are not session tokens and are rejected by `AuthService.authenticate`.

## Password policy (UTF-8 bytes)

- `currentPassword`: 1 to 1024 UTF-8 bytes.
- `newPassword`: 12 to 1024 UTF-8 bytes and different from `currentPassword`.

Length is the UTF-8 byte length (`utf8.encode(value).length`), never
`String.length`, code points or graphemes. The constants
`passwordMinUtf8Bytes`/`passwordMaxUtf8Bytes` and the helpers
`passwordUtf8ByteLength`, `currentPasswordProblem`, `newPasswordProblem` and
`changePasswordProblem` live in `packages/api_contracts` and are used by the
server, the Flutter client and the contract test. The existing server
`requirePassword` (account create/reset) now consumes the same constants with
unchanged behavior (12–1024 bytes).

## API contract

`POST /api/v1/platform/profile/password`, `application/json`, Bearer session:

Request `ChangePasswordRequest`: exactly `currentPassword` and `newPassword`.
No `expectedVersion`, no account identifier; unknown or missing fields are
rejected.

| Status | Code | Semantics |
| --- | --- | --- |
| 204 | – | Hash updated (`version + 1`), all sessions revoked, audit committed; no body |
| 400 | `invalid_request` | Missing/unknown fields, type mismatch, byte bounds, `newPassword == currentPassword` |
| 400 | `invalid_json` | Body is not a JSON object |
| 401 | `unauthorized` | Missing/malformed/revoked/expired session or disabled account |
| 403 | `forbidden` | Company mismatch or role without the capability |
| 413 | `body_too_large` | Body above 16384 bytes |
| 415 | `unsupported_media_type` | Content type is not `application/json` |
| 422 | `invalid_current_password` | Current password does not match; no state changed |
| 429 | `rate_limited` | More than five failed verifications per account in 15 minutes |
| 503 | `database_unavailable` | Infrastructure failure; no state changed |

No 404 and no 409 are emitted by this route.

## Transaction and concurrency

One `runAuthorized` transaction under the company advisory lock:

1. revalidate account, session, role and capability;
2. read the actor's `password_hash` and `version` company-scoped;
3. limiter check for the account id;
4. Argon2id verification of `currentPassword`;
5. hash of `newPassword`;
6. version-guarded `UPDATE` of only the actor row;
7. revoke all sessions of the actor;
8. append `identity.user.password_changed` with `{version}`;
9. commit; only then `limiter.success(accountId)`.

Admin reset and self change serialize on the same lock, so the password is
always verified against the committed state and there is no check-then-write
gap. The locked version is used for the guard; a client `expectedVersion` is
deliberately not part of the contract.

## Password verification limiter

`PasswordVerificationLimiter` is a dedicated process-local limiter keyed by
account id only (never by remote address). Policy: fixed 15-minute window,
5 failures per account, blocked verification returns 429 `rate_limited` before
any Argon2 work, success clears the bucket, restart resets state, bounded lazy
pruning after 1000 tracked keys. Wrong-password, throttle and validation
refusals write no audit. The limiter does not revoke sessions and does not
affect login or admin reset; M1 remains deferred.

The limiter is intentionally in-memory and non-transactional:

- a wrong current password records exactly one failure even though the
  database transaction rolls back;
- a blocked check records nothing and performs no writes;
- a successful commit clears the bucket only after the commit returned;
- a database/audit failure after the password update and session revocation
  rolls the transaction back, keeps the limiter state and records no failure.

## Audit, events and secret safety

- Audit action `identity.user.password_changed`, actor/entity = self, company
  and location from the revalidated actor, `changes = {version}` only.
- No current/new password, hash, salt or derived value enters audit, logs,
  responses, receipts or error text; the request DTO has no `toString`
  override. Tests assert secret-free audit and response bodies.
- No domain/outbox event is emitted; identity remains a documented
  non-emitter, matching admin reset.

## Failure and recovery behavior

- Validation failures run before any database work; wrong current password and
  throttling cause zero persistent writes.
- Successful commit revokes the initiating session; the 204 is still returned
  after commit and the token is immediately invalid.
- Concurrent admin reset: serialized; either verification sees the new hash
  (422, no overwrite) or the self change commits first and the stale admin
  reset receives the existing 409 behavior.
- Concurrent self changes from two sessions: exactly one commits; the other
  fails through session revalidation (401).
- Lost response: the client clears local state and returns to login with an
  ambiguous warning (new password if committed, old password otherwise); no
  command receipt and no automatic replay.
- Late failure injection (runtime audit INSERT revoked; failure occurs after
  the password update and session revocation) rolls back hash, version, session
  revocation and audit; the old password still authenticates and the new one
  does not.

## Flutter behavior

The authenticated shell app bar offers "Passwort ändern" to every role with
`identity.self.password`. The dialog asks for the current password, the new
password and a confirmation (obscured, no visibility toggle), validates the
UTF-8 byte policy, confirmation equality and `new != current` locally, disables
submission while busy and shows static errors inline. On success the local
session is cleared, the app returns to login and shows the positive notice; a
wrong current password or throttle keeps the dialog open; a 401 expires the
session; an ambiguous transport failure clears the session with a warning.
No privileged follow-up request is issued with the revoked token.

## Verification (local, 2026-10-02)

- `packages/api_contracts`: 46 tests passed (including the new byte-policy,
  DTO and OpenAPI containment checks).
- `apps/server`: 133 tests passed against an isolated PostgreSQL test database,
  including 9 new self-password cases and the real HTTP smoke matrix
  (204, immediate 401, old/new login, 400/401/415/422/429, secret-free audit).
- `apps/client_flutter`: 127 tests passed, including new controller, HTTP
  adapter and dialog/widget tests.
- `dart format --set-exit-if-changed`, `dart analyze`/`flutter analyze` clean in
  the touched packages.
- Independent review and remote CI are not yet performed.

## Boundaries and debt

M1 (login limiter behind the documented reverse proxy) is unchanged; this
slice's limiter is keyed per account, so it is not degraded by the proxy, but
the login endpoint remains an operator decision. Global M3/M4 cleanup, M2
overlap defense-in-depth, fixture duplication and company-lock granularity
remain deferred. No migration is involved; the capability matrix is code-only.
