# Logical domain modules

This directory reserves a possible future package layout. Current Organization,
Identity, People, Workforce, Tasks, Inventory, Stock and platform Audit/Events/Plugins
are implemented as logical boundaries under `apps/server/lib/src/`. Do not move them here merely
to match the target diagram or infer that they are absent because this directory is empty.

Modules own their domain/application rules and persistence and expose documented
ports or events. Separate packages are not required for the modular monolith.
See [module boundaries](../docs/architecture/module-boundaries.md),
[actual status](../docs/roadmap/status.md) and [roadmap](../docs/roadmap/phases.md).
