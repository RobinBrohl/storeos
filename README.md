# StoreOS

StoreOS is a local-first, self-hosted operating system for retail and gastronomy. It connects daily employee work with shared operational data: shifts, guided tasks, Articles, location Assortment and Stock. Operators own their data; the local core needs no vendor cloud account or mandatory telemetry.

The current implementation is a single-site online Flutter Web client, a Dart modular monolith and PostgreSQL. The bounded employee journey and platform administration are delivered. P4.3 Manual Stock Foundation is DONE/CLOSED, including the accepted adjustment retry correction, independent targeted review APPROVE, 28/28 PASS and green changed-commit CI. See [actual status](docs/roadmap/status.md) and the [closure record](docs/development/phase-4-3-manual-stock.md#final-acceptance-closure--2026-10-04) for evidence and remaining operational boundaries.

P4.4 Local Planogram Execution is **DONE/CLOSED**: reusable Company Planograms,
local Fixtures, immutable published revisions, explicit Assignments and browser
HTML/CSS printing. Independent targeted review APPROVE and all five jobs in
[changed-commit CI run 37217071802](https://github.com/RobinBrohl/storeos/actions/runs/37217071802)
complete the [closure evidence](docs/development/phase-4-4-local-planograms.md#final-documentation-closure--2026-10-04).
Browser print verification does not establish physical printer/device acceptance.

P4.5 Approved Operational Knowledge is **DONE/CLOSED**: Company-wide plain-text
instructions, one active draft, immutable published/discarded revisions, terminal
retirement and strict publication replay. Independent adversarial review APPROVE,
60/60 PASS and all five jobs green in [changed-commit CI run 37229964360](https://github.com/RobinBrohl/storeos/actions/runs/37229964360)
complete the [closure evidence](docs/development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04).
P4.6 Guided Operation — Task + approved Knowledge revision pinning is **DONE/CLOSED**:
targeted independent review **APPROVE**, **64/64 PASS**, focused Codex Security
**SECURITY APPROVE**, and all five jobs green in
[changed-commit CI run 37287951549](https://github.com/RobinBrohl/storeos/actions/runs/37287951549).
Implementation `15679bf` delivers exact approved Knowledge revision pins in
schema-3 Templates/Tasks and contextual historical panels. Its closure migration chain ended
at 0018; 0001–0017 were unchanged. See [P4.6 evidence](docs/development/phase-4-6-task-knowledge-guidance.md)
and [ADR 0020](docs/adr/0020-task-knowledge-guidance.md). No active P4.6 remediation remains.
No active P4.5 remediation remains; F01/F02 are LOW non-blocking follow-ups.
Native-device/accessibility acceptance is not claimed.

P4.7 Task + exact Planogram Assignment execution pinning is **IMPLEMENTED LOCALLY / INDEPENDENT REVIEW APPROVE / SECURITY REMEDIATION COMPLETE / TARGETED SECURITY RE-REVIEW PENDING / REMOTE CHANGED-COMMIT CI PENDING** on `main`, uncommitted and unstaged. The verified starting HEAD was `a0ed6346f7453c8f4e170aee43af8d775677f97b`, matching cached/live origin; all five exact-HEAD jobs succeeded in [baseline CI 37290533013](https://github.com/RobinBrohl/storeos/actions/runs/37290533013). New migration 0019 adds schema 4 and durable Fixture/Assignment/Revision integrity; migrations 0001–0018 and dependencies/lockfiles are unchanged. Existing P4.1–P4.6 closure remains intact. No P4.8 capability is selected.

See [P4.7 local evidence](docs/development/phase-4-7-task-planogram-guidance.md) and [ADR 0021](docs/adr/0021-task-planogram-assignment-guidance.md).

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
