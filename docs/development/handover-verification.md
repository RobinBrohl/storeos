# Handover verification and repository audit

Date: 2026-09-29. Baseline: `da2c9e8`. Incoming Git tree: clean.
Handover changes are documentation-only; no migration, permission, event, product
feature, dependency constraint or test assertion was changed.

## Verification environment and results

Windows host, PowerShell 7.4+, Flutter 3.47.5, Dart 3.13.4, Docker 29.8.0 and the
repository's PostgreSQL 17 container. Test commands used a newly created
`storeos_handover_<random>_test` database with the existing restricted runtime role.
Credentials stayed in private local files/environment and were not added to reports.

| Check actually run | Result |
| --- | --- |
| `scripts/dev.ps1 get` | Dependency resolution succeeded; no lockfile changes |
| `scripts/dev.ps1 check` with explicit test database | 233 tests passed: contracts 31, server 92, design system 2, client 108; DB tests were enabled |
| Format checks in all four packages | No formatting changes required |
| Dart/Flutter analyzers in all four packages | No issues |
| Compose validation and `compose up -d --wait db` | Valid configuration; database healthy |
| Migration CLI against the new empty database | All 10 migrations applied; second invocation applied none |
| Bootstrap CLI | First account created; repeated bootstrap refused |
| Real server CLI on isolated loopback port + `dev.ps1 smoke` | Readiness, login, scope, permissions, audit/event/plugin reads, anonymous/foreign denial and logout revocation passed |
| `scripts/Test-DevSetup.ps1` | Fresh setup, stable repeated setup and refusal to regenerate missing configuration passed |
| `infra/backup/Test-BackupCrypto.ps1` | Roundtrip, wrong key, tamper, truncation and reordered chunks passed |
| `scripts/e2e/Run-NumericGuidedWork.ps1` | Real Chrome/Flutter/HTTP/PostgreSQL numeric workflow passed; fixture evidence/audit verification and cleanup passed |
| `flutter build web --release --no-web-resources-cdn` | Build succeeded; bundled renderer/font configuration retained |
| Encrypted database backup and isolated restore | Scripts succeeded; 10 migrations restored, sessions revoked, runtime CONNECT denied; plugin-token revocation verified by script |

The backup exercise read the normal development database and restored only into a new
fenced `storeos_restore_handover_*` target. It contained no numeric attempts, so this
exercise does **not** prove a populated numeric-task restore. Earlier numeric-specific
manual evidence is historical; an automated populated restore journey is proposed next.
No original database/volume or existing scope/secret was deleted or changed.

The browser test starts the real app, creates a numeric exception, changes user for
administrative resume, records an accepted value, confirms/completes, remounts the app
and re-authenticates. It checks two persisted attempts and expected audit actions.
It does not perform literal browser reload or backend-process restart mid-journey.
Separate API integration tests cover service reconstruction, replay, concurrent commands,
authorization, schema-1 upgrade preservation and rollback at numeric write boundaries.

The final post-documentation rerun passed all 233 tests, four analyzers, format checks,
Compose validation, setup/crypto checks and the browser E2E. This gives two successful
independent browser runs during the handover. Both fixture logs confirmed database/audit
postconditions; no orphan test schemas, temporary manifests or stop files remained.
The two handover-owned databases were dropped after verification; test ports 8096,
8095 and 4444 were free. The operating database and encrypted backup were retained.
Local Markdown targets passed across 63 files, and `git diff --check` passed.
Raw local logs use `.local/handover-*.log`; these ignored files are optional diagnostics,
not required repository artifacts. A new machine can reproduce the commands from
[HANDOVER](../HANDOVER.md#how-to-run-storeos).

## Dependency audit

Reviewed all four `pubspec.yaml`/lockfile pairs, source imports, test/lint configuration,
installed package LICENSE files and live `dart pub outdated --json` / Flutter equivalent.
Versions below are locked versions, not just manifest ranges.

| Direct hosted dependency | Version | Use / license observation |
| --- | --- | --- |
| [shelf](https://pub.dev/packages/shelf), [shelf_router](https://pub.dev/packages/shelf_router) | 1.4.2 / 1.1.4 | HTTP/routing; BSD-3-Clause / Apache-2.0 |
| [postgres](https://pub.dev/packages/postgres) | 3.5.17 | Server persistence and real DB tests; BSD-3-Clause |
| [cryptography](https://pub.dev/packages/cryptography) | 2.9.0 | Argon2id passwords; Apache-2.0 |
| [crypto](https://pub.dev/packages/crypto) | 3.0.7 | Token digests and migration checksums; BSD-3-Clause |
| [http](https://pub.dev/packages/http) | 1.6.0 | Client HTTP adapters/test helpers; BSD-3-Clause |
| [cupertino_icons](https://pub.dev/packages/cupertino_icons) | 1.0.9 | No source import/usage found; MIT; unnecessary direct dependency retained |
| `lints`, `flutter_lints`, `test` | 6.1.0 / 6.0.0 / 1.32.0 | Analyzer/test tooling; BSD-3-Clause |

Flutter, flutter_localizations, flutter_test and integration_test come from the pinned
SDK; local contracts/design-system packages are path dependencies. They are all used.
StoreOS carries [AGPLv3](../../LICENSE); bundled Roboto has an
[Apache-2.0 license file](../../apps/client_flutter/assets/fonts/roboto_license.txt).
Preserve third-party notices when distributing builds. This audit is not a complete
transitive-license or commercial plugin-distribution assessment.

`pub outdated` reported no outdated server/contracts packages. The only outdated
direct package was unused `cupertino_icons` (2.0.0 available; a major version outside
the current constraint). No upgrade was made. Flutter reports newer transitive
`material_color_utilities`, `meta` and `test_api`; some are SDK-constrained. None of
the returned entries was flagged discontinued, retracted or affected by an advisory.
That limited registry output is not a vulnerability-free guarantee. No obviously
problematic used direct dependency was identified.

Reproducibility limits: local `dev.ps1 get` uses normal `pub get` while CI/E2E enforce
lockfiles. Docker image tags `postgres:17-alpine`/`caddy:2-alpine` and CI Action major
tags can move. Do not silently upgrade them as part of a feature. The remote CI job
and its pinned Linux Chrome/ChromeDriver pair were not executed during this handover.

## TODO and placeholder audit

Searched source, scripts, infrastructure and documentation case-insensitively for
`TODO`, `FIXME`, `HACK`, `placeholder`, `dummy`, `mock` and `temporary`, excluding
generated/cache/ignored local data. Important classifications:

| Finding | Classification | Disposition |
| --- | --- | --- |
| `.env.example` setup UUID markers | Intentional | Setup substitutes stable IDs; tested, not fake domain data |
| Web `$FLUTTER_BASE_HREF` | Intentional | Flutter build substitution |
| `AuthService.dummyPasswordHash` and test equivalents | Intentional | Password verification work for unknown accounts; not a bypass account |
| `MockClient` / test doubles in client tests | Intentional | Isolated transport/widget tests; real E2E is separate |
| Temporary private fixture manifest | Intentional | Atomic restricted-file creation and cleanup, not unfinished product code |
| Reserved modules/shared/plugin SDK/example directories | Intentional | Documented future layout; no compiled implementation claimed |
| Unused `cupertino_icons`, company-wide lock, direct organization repository use in `PluginService` | Technical debt | Recorded in HANDOVER; no unrelated refactor |
| Device offline queue, native runners, enterprise sync | Incomplete implementation | Explicitly planned/deferred in status, not presented as current capability |

No release-critical TODO/FIXME/HACK implementation marker was found. This is a bounded
scan/review result, not a claim that all future operating risks are solved. Valid
markers and test doubles were not removed.

## Architecture/documentation consistency

The Dart/Flutter/PostgreSQL modular-monolith decisions are reflected in code. HTTP
routes delegate; application coordinators manage scoped transactions; SQL migrations
and real DB tests protect snapshots, evidence and runtime grants. Company-lock
granularity and the P1 plugin-to-organization repository shortcut remain documented
debt; no new architecture decision or module migration was introduced.

Corrected stale entry-point claims that the server had no Workforce/Tasks and that the
bounded employee journey was absent. Added implementation boundaries to target security,
deployment, plugin and orchestration descriptions. New status separates delivered,
partial, planned and intentionally deferred work. ADR decisions and historical
verification reports remain intact; the ADR index now gives English authoring guidance.

## Limits of this verification

- No native Android/desktop build, device/scan test or actual WAN-disconnection exercise.
- No remote GitHub Actions result, representative load benchmark or external security review.
- No automatic retention/deletion/export policy, production failover or post-backup
  revocation reconciliation is supplied by this handover.
- Operator-specific privacy/retention/recovery decisions remain gates before a real-data pilot.
