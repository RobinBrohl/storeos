# StoreOS

P4.8 Selected-article inventory counts are **IMPLEMENTED LOCALLY** on main, uncommitted and unstaged. Independent adversarial review returned **CHANGES REQUIRED**. Bounded F01–F04 remediation is **COMPLETE**; targeted review, focused security review and remote changed-commit CI are **PENDING**. Migration 0020 adds immutable Stock-owned rounds/observations and whole approved corrections; P4.1–P4.7 closure remains intact. See [P4.8 contract and evidence](docs/development/phase-4-8-stock-counts.md).


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

P4.7 Task + exact Planogram Assignment execution pinning is **DONE/CLOSED** at implementation commit
`ccfa3df78f141da9577e988a9f8ddfb21ca4df1f` on `main`. Before documentation closure, HEAD matched cached and live
`origin/main`; the tree/index were clean, with no stash and one intended worktree.
Initial independent review **CHANGES REQUIRED** led to bounded LOW F01/F02 remediation
and targeted **APPROVE**; final product acceptance is **80/80 PASS**. Initial Codex Security
**SECURITY CHANGES REQUIRED** identified LOW/CWE-863 configured work-Location scope F01;
bounded runtime authorization remediation is complete and the supplied targeted security
re-review returned **SECURITY APPROVE**. All five exact-HEAD jobs succeeded in
[changed-commit CI 37377829784](https://github.com/RobinBrohl/storeos/actions/runs/37377829784). Migration 0019 completes the 0001–0019 chain;
0001–0018 and dependencies/lockfiles are unchanged. No active P4.7 remediation remains.
Existing P4.1–P4.6 closure remains intact. Next after the documentation closure commit:
P4.8 selection followed that closure; its local implementation is recorded above.

See [P4.7 closure evidence](docs/development/phase-4-7-task-planogram-guidance.md) and [ADR 0021](docs/adr/0021-task-planogram-assignment-guidance.md).

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
