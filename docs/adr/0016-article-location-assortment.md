# ADR 0016: Article–location assortment membership

Status: Accepted. Scope decided 2026-10-03 as part of the P4.2 location
assortment slice.

## Context

P4.1 introduced a company-wide `Article` master (ADR 0015) with a reserved
`UNIQUE (id, company_id)` anchor and explicitly deferred location assortment.
The organization already supports several company-owned locations; employees,
task templates and shifts are location-scoped, while articles intentionally are
not (`docs/architecture/module-boundaries.md:84`). The roadmap names
"Produktstamm, Einheiten, Lieferanten, Bestellungen, Wareneingang, Chargen/MHD,
Bestands-Ledger und Inventur" as later P4 capabilities and does not name a first
multi-site step (`docs/roadmap/phases.md:61-63`). ADR 0015 identifies location
assortment as the documented later step for multiple sites
(`docs/adr/0015-company-wide-article-master.md:16-19,29-34`).

The following questions had to be answered before a location-scoped inventory
record: is the article location-owned or company-wide; what exactly does "carried
at a location" mean; how do association state and global article state interact;
which capability guards it; and what happens to assortment rows when an article
is globally deactivated.

## Decision

**Ownership.** `inventory` owns a new `ArticleLocationAssortment` aggregate, a
per-location membership row linking one company article to one company location.
Article identity stays company-wide; location ownership stays with
`organization`. No existing table or ownership changes.

**Identity and scope.** `id` is a client-supplied UUID, immutable. `company_id`,
`article_id` and `location_id` are immutable and come from the revalidated
session/route; exactly one row per `(company_id, article_id, location_id)`
exists, enforced by `UNIQUE`. Composite foreign keys to
`articles(id, company_id)` and `locations(id, company_id)` bind the company
structurally. Deactivated rows are reactivated, never recreated, and are never
hard-deleted.

**Membership state vs article state.** `article_location_assortment.is_active`
means "this location is configured to carry this article". `articles.is_active`
means "the company article itself is active". They are independent. An
association may remain active when the article is later globally deactivated;
article deactivation never mutates or cascades into assortment rows. Effective
operational availability is the conjunction `association.is_active AND
article.is_active`, computed by consumers and deliberately not stored. A new
association or a reactivation requires `article.is_active = true`
(`409 article_inactive`); deactivation of a membership is always allowed when
version/current state permit. Reactivating a globally inactive article later
makes an already-active membership operationally available again without an
assortment write.

**Location validation.** The route location is validated through the existing
company-scoped `OrganizationService.requireConfiguredLocation` port, which
resolves any named location of the authenticated company (the primitive already
used by employees, templates and shifts). This is an arbitrary company-owned
location lookup, not a single-installation shortcut.

**Authorization.** A new capability `inventory.assortment.manage`, granted to
`admin` only. Managing a location's assortment is a distinct operational
boundary from editing company-wide article identity: capabilities in StoreOS are
separate per business area (`tasks.templates.manage`, `workforce.shifts.manage`,
`people.manage`), and a future branch/location manager must be able to manage a
site's range without changing global article master data. Reads are management
reads in this slice; no speculative read capability exists.

**Integration.** No domain or outbox event and no plugin grant; `inventory`
remains a documented non-emitter (ADR 0008). Later stock movements, receiving
lines and order lines reference `(article_id, location_id)` directly and may
validate against active assortment in the application; they must not reference
the assortment UUID or depend on its lifecycle, because movements are historical
facts that survive assortment changes.

## Alternatives considered

- **Location-owned articles or an `article.location_id` column.** Rejected:
  product identity is company master data; ownership would break multi-location
  reuse and contradict ADR 0015.
- **Implicit availability (all active articles are available everywhere unless
  excluded).** Rejected: it requires negative rows or a hidden default, obscures
  the operator's explicit range, and has no repository evidence.
- **Single `isActive` state coupling article and assortment.** Rejected:
  deactivating an article would silently destroy site configuration or force
  cross-aggregate cascades; the two states answer different business questions.
- **Reusing `inventory.articles.manage`.** Rejected: it would grant assortment
  rights to every article-master administrator and prevent a future
  location-scoped operator role without a permission redesign.
- **Storing effective availability.** Rejected: it is derivable, and storing it
  would require cross-aggregate maintenance without a current consumer.
- **Stock/quantity on the association.** Rejected: out of scope; a ledger is a
  separate future decision with its own movement semantics.

## Consequences

- StoreOS gains an explicit per-location product range without claiming stock,
  purchasing, ordering or price behavior.
- Stock and purchasing can later scope their article pickers to a location's
  active assortment; disabling a membership never orphans historical movements.
- Existing articles are not automatically assigned to any location: absence
  means "not carried here". The Flutter UI starts empty and requires an explicit
  enable.
- A membership may be active while its article is globally inactive; the API and
  UI expose both states and consumers must require the conjunction.
- `inventory.assortment.manage` is a new admin capability; plugin tokens remain
  rejected and no event is emitted.

## Open questions

- When do region- or channel-level assortment scopes become necessary, and who
  owns them?
- Which consumer (ordering, receiving, stock) first turns a membership into an
  operational gate, and does it need a per-location override reason?
- Which retention/export rule applies to assortment membership and its audit?
