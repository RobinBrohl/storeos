# Durable development rules

- Start with [HANDOVER](docs/HANDOVER.md) and [actual status](docs/roadmap/status.md); read relevant [principles](docs/product-principles.md), [module boundaries](docs/architecture/module-boundaries.md) and [ADRs](docs/adr/) before architecture or domain work.
- StoreOS is a local-first, self-hosted modular monolith: Flutter clients, a Dart backend and PostgreSQL as the primary database. Preserve autonomous site operation and operator data ownership; device offline writes and multi-site sync require separate contracts.
- Keep business logic in Domain/Application, never Flutter widgets, HTTP routes or plugins. Respect ADRs and module ownership; communicate through public ports/events, not foreign tables or repositories.
- Enforce authorization server-side with company, location and resource scope. Minimize employee data, audit relevant business changes atomically and never silently overwrite conflicts or delete critical evidence.
- Apply schema changes through new, tested migrations; never edit applied migration files. Preserve IDs, immutable snapshots and supported contracts.
- Define one small vertical slice including permissions, audit/events and tests. Avoid adjacent features, unrelated refactors and speculative abstractions. Record genuine architectural decisions in an ADR.
- Use English for new technical documentation, ADRs, necessary code comments, API/developer-facing text and commit guidance. Do not translate or rename existing material solely for consistency; see [workflow](docs/development/workflow.md).
- Prefer pinned repository SDK/dependency/API versions over model memory. Inspect actual versions and current official documentation when APIs are version-sensitive; avoid unneeded upgrades.
- Run relevant formatters, analyzers, unit/integration/UI tests and smoke checks after changes. Never weaken or remove tests to make checks pass; report skipped or unverified checks explicitly.
- Never present fake or placeholder features as complete. Completion needs persistence, validation, permissions, relevant audit/events/migrations, error handling, tests, UI and documentation. Personnel decisions remain with people.
