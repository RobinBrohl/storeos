# StoreOS

StoreOS is a local-first, self-hosted operating system for retail and gastronomy. It connects daily employee work with shared operational data: shifts, guided tasks, Articles, location Assortment and Stock. Operators own their data; the local core needs no vendor cloud account or mandatory telemetry.

The current implementation is a single-site online Flutter Web client, a Dart modular monolith and PostgreSQL. The bounded employee journey and platform administration are delivered. Manual stock is committed, with client retry/input defects still requiring correction before slice acceptance. See [actual status](docs/roadmap/status.md) for implementation and verification boundaries.

## Start locally

Use the repository-pinned SDK versions and existing lockfiles. The complete commands, bootstrap procedure, checks and secret-file conventions are in [local development](docs/development/local-development.md).

1. Run `./scripts/dev.ps1 setup` to create private local configuration.
2. Resolve packages when needed: `./scripts/dev.ps1 get`.
3. Start PostgreSQL: `./scripts/dev.ps1 db`.
4. Apply migrations: `./scripts/dev.ps1 migrate`.
5. Bootstrap once: `./scripts/dev.ps1 bootstrap`.
6. Start the API: `./scripts/dev.ps1 server`; in a second terminal run `./scripts/dev.ps1 client`.

Keep secrets in local files and out of commits, logs and agent context. LAN TLS, production deployment and restore activation have separate operator procedures and gates.

## Documentation

- [Documentation index](docs/README.md): canonical sources and historical evidence.
- [HANDOVER](docs/HANDOVER.md): what the next developer needs now.
- [Vision](docs/vision.md): long-term product direction and boundaries.
- [Roadmap](docs/roadmap/phases.md) and [status](docs/roadmap/status.md): proposed sequencing and actual delivery.
- [Module boundaries](docs/architecture/module-boundaries.md), [ADRs](docs/adr/README.md) and [development workflow](docs/development/workflow.md): ownership, decisions and contribution rules.
- [Deployment](docs/architecture/deployment.md), [backup/restore](infra/backup/README.md) and [risks/open questions](docs/risks-and-open-questions.md): operation and unresolved decisions.

## Repository

`apps/client_flutter` contains the client; `apps/server` contains the composition root and logical business modules. `packages/api_contracts` shares transport contracts and `packages/design_system` provides the UI foundation. `modules`, `packages/shared` and `packages/plugin_sdk` are reserved boundaries, not evidence of a complete package-based module system or executable plugin runtime.

StoreOS is licensed under [AGPLv3](LICENSE). New technical documentation follows the English-language policy in the workflow. The durable development rules are in [AGENTS.md](AGENTS.md).
