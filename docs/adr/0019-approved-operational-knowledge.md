# ADR 0019: Approved operational Knowledge

Status: Accepted decision; P4.5 DONE/CLOSED, independent review APPROVE and changed-commit CI green.
Delivery evidence: [final closure](../development/phase-4-5-approved-operational-knowledge.md#final-documentation-closure--2026-10-04).

## Context

Employees need an authoritative instruction they can discover and read while
managers prepare replacements without exposing unfinished content. Approval must
retain the exact published text and its authorizing evidence. Knowledge has no
concrete event consumer or Task evidence integration in this slice.

## Decision

Knowledge owns exactly `knowledge_articles` and `knowledge_revisions`.
`WikiArticle` is a stable Company-scoped identity with a version, terminal
active/retired lifecycle, current published pointer and optional active draft
pointer. Each `WikiRevision` belongs to the same Article/Company, has a unique
monotonic number and transitions from draft to published or discarded. Published
and discarded revisions are immutable. Retirement discards any active draft and
preserves published history; there is no hard-delete workflow.

Publication is approval. In one authorized transaction it freezes the saved
draft, records actor/time/operation/expected and applied versions, advances the
Article pointer/version and appends minimized audit. Save never publishes.
Replacement draft creation copies the current publication without changing
employee visibility. Discard never changes the current publication.

The audience is Company-wide. Fresh server authorization requires
`knowledge.articles.read`, `.manage` or `.publish` as applicable. Admin has all
three; employee has only read; auditor, viewer and plugins have none. Employee
queries expose only the current published revision of an active Article.
Management routes retain draft, discarded, historical and retired evidence.

Content is plain title/body text. Normalize CRLF and CR to LF, preserving other
whitespace and Unicode; reject malformed surrogate sequences and NUL. Title is
at most 120 Unicode code points and has no ASCII control characters. Canonical
size is the sum of UTF-8 bytes of normalized title and body, at most 8192 bytes.
Drafts may be empty. Publication requires both fields to be nonblank. JSON request
bodies have a separate 65536-byte transport ceiling. There is no Markdown/HTML
renderer or external content fetch.

Publication operation UUIDs are unique within Company and retained on the
published revision. After fresh permission and resource-scope checks, exact
replay binds Article, Revision, actor and expected version and returns the
original immutable evidence. It performs no write, audit append, pointer change
or lifecycle change, including after another publication or retirement.
Conflicting reuse returns `operation_conflict`. There is no generic receipt table
and no server replay promise for save/discard/retire/draft creation.

Flutter holds immutable pending commands in memory, bound to opaque live session
identity. Duplicate actions are guarded synchronously. Uncertain publication
allows exact retry; ambiguous save requires authoritative reload and explicit
review. Confirmed writes and subsequent refresh failure remain separate outcomes.
Creation uses stable client Article/Revision UUIDs for explicit reconciliation.

No events/outbox additions, readership tracking, acknowledgments, offline write
queue, attachments, rich text, suggestions, review workflow or Task revision pins
are introduced. A shortcut from Meine Arbeit opens Knowledge while retaining the
work page; reading creates no work evidence.

## Alternatives

Editing a single live row would expose unfinished text and erase approval
history. Task snapshots would couple discovery to execution evidence without an
approved contract. Generic receipts duplicate publication evidence already owned
by the revision. Rich text and full-text search introduce unnecessary scope.

## Consequences

Company writer locking and Article versions serialize supported commands. SQL
constraints enforce same-Company/Article pointers and their revision states;
triggers freeze terminal revisions, prevent deletes and protect retired Articles.
Runtime grants allow only the required insert/select and column updates, denying
delete/truncate. Audit failure rolls back the business transition.

Authorization, pointer/version advancement and audit remain guarantees of the
supported application writer. Arbitrary runtime SQL could deliberately repoint
an active Article to its own earlier published revision without audit/version
advancement. This is the existing accepted raw-SQL threat boundary, not an
alternative supported writer; reconsider before admitting another writer.

Literal case-insensitive title substring search uses PostgreSQL `lower` under the
database collation and `strpos`; `%`, `_` and backslash have no wildcard meaning.
Visibility is filtered before UUID keyset pagination (50 items). History uses
descending revision-number keysets. There is no accent folding or relevance rank.

## Open questions

No unresolved decision blocks this bounded slice. Task revision pinning,
multi-site distribution, suggestions, durable device recovery and richer content
need separately approved contracts. Physical-device and accessibility acceptance
are not established by automated browser checks.
