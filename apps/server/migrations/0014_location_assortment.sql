-- Owned by inventory. Location assortment: one durable membership row saying
-- that a company location is configured to carry a company article. This slice
-- stores configuration only: no stock quantity, ledger, valuation, supplier,
-- purchasing, price or conversion data exists here. Membership state
-- (is_active) is independent from the company article's is_active; article
-- deactivation never mutates or deletes assortment rows. Deactivated rows are
-- reactivated, never recreated, and never hard-deleted. Article identity stays
-- company-wide; this table is the location-scoped association.
CREATE TABLE {{schema}}.article_location_assortment (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  article_id uuid NOT NULL,
  location_id uuid NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  -- Exactly one durable association per company article and location. This is
  -- also the database backstop for concurrent enable requests.
  CONSTRAINT article_location_assortment_pair_unique
    UNIQUE (company_id, article_id, location_id),
  -- Both parents are company-bound; the composite keys make a cross-company
  -- association structurally impossible without changing an immutable column.
  CONSTRAINT article_location_assortment_article_fk
    FOREIGN KEY (article_id, company_id)
    REFERENCES {{schema}}.articles(id, company_id) ON DELETE RESTRICT,
  CONSTRAINT article_location_assortment_location_fk
    FOREIGN KEY (location_id, company_id)
    REFERENCES {{schema}}.locations(id, company_id) ON DELETE RESTRICT
);
-- Location-scoped keyset page ordered by association id.
CREATE INDEX article_location_assortment_location_page
  ON {{schema}}.article_location_assortment (company_id, location_id, id);
-- Membership active/inactive filtering within one location page.
CREATE INDEX article_location_assortment_location_active
  ON {{schema}}.article_location_assortment
    (company_id, location_id, is_active, id);
