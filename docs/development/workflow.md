# Development workflow

## Language and source of truth

Use English for new technical documentation, ADRs, API documentation, developer-facing
text, necessary code comments and commit guidance. Existing German documents and
filenames stay in place unless substantially edited for another valid reason.
German legal/domain terms such as GoBD, KassenSichV, IfSG, MHD and ZUGFeRD remain
where appropriate. This is not a request to translate the existing German product UI.

[Status](../roadmap/status.md) records implementation; [phases](../roadmap/phases.md)
records intended direction. Architecture documents contain implemented subsets and
future contracts. Historical verification notes describe their dated snapshots,
not automatic evidence for today's working tree.

## One development cycle

1. Inspect `git status --short` and recent history. Begin with a clean tree; preserve
   and identify existing work first. Never discard it to obtain cleanliness.
2. Create a feature branch, for example `git switch -c feature/<short-scope>`;
   Codex-created branches use `codex/<short-scope>` by default.
3. Define one small vertical slice: goal, exact scope, exclusions, data ownership,
   permissions, audit/events, migration impact, acceptance criteria and required tests.
4. Read only the relevant architecture, ADRs, implementation and tests after initial
   handover orientation. Do not reload all historical documentation each cycle.
5. Implement only that scope. Preserve existing controller/service/repository
   structure; introduce abstractions or dependencies only for demonstrated needs.
6. Run relevant analyzers and tests with pinned SDKs and committed lockfiles.
   Set `STOREOS_TEST_DATABASE` explicitly: skipped database tests are not acceptance.
7. Review the diff: migrations, authorization, concurrency, idempotency, audit rollback,
   error states and accidental credential/generated-file changes.
8. Validate the actual journey manually or through real browser E2E; widget mocks
   do not establish an HTTP/database/browser integration result.
9. Update only affected documentation and status. Add an ADR only for a real decision.
10. Stage reviewed files and commit with a concise English message. Implementation
    requests do not implicitly authorize an automatic commit or push.
11. Merge only when the defined scope is complete and healthy. Do not begin another
    scope to hide gaps in the current one.

## Verification discipline

Run `./scripts/dev.ps1 check` at repository root after setting a dedicated test database.
It checks formatting, all four analyzers/test suites and Compose configuration.
Separate setup, backup-crypto and browser E2E commands are in
[HANDOVER](../HANDOVER.md#how-to-run-storeos). Use absolute log paths for redirected
PowerShell pipelines: the development script changes directory between packages.
`check` compiles no Web target. A slice that changes shared client contracts under
`packages/api_contracts` must additionally run
`flutter build web --release --no-web-resources-cdn` from `apps/client_flutter`
before push/handoff: VM tests and analyzers do not detect `dart2js`
integer-representability or other Web-only compile errors.

Keep secrets in private files/environment, never in Git, terminal output, reports
or prompts. Run fixtures only against a dedicated test database. Never delete the
normal Compose volume as test cleanup. Repair causes of failures; do not remove
assertions, broaden grants or skip tests merely to obtain green output.
