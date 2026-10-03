-- Owned by inventory. Company-wide article/product master. This slice stores
-- master data only: no stock, supplier, purchasing, batch/MHD, recipe or price
-- data exists here. Articles are never hard-deleted; lifecycle is active/
-- inactive. SKU uniqueness is case-insensitive per company through a
-- deterministic ASCII-only fold (translate), so it does not depend on the
-- database collation or locale; non-ASCII characters compare exactly.
CREATE TABLE {{schema}}.articles (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL,
  sku text NOT NULL,
  sku_key text GENERATED ALWAYS AS (
    translate(sku, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')
  ) STORED NOT NULL,
  barcode text,
  name text NOT NULL,
  description text,
  unit text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  CONSTRAINT articles_scope_unique UNIQUE (id, company_id),
  CONSTRAINT articles_company_fk FOREIGN KEY (company_id)
    REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  CONSTRAINT articles_sku_valid CHECK (
    length(sku) BETWEEN 1 AND 64 AND sku = btrim(sku) AND sku !~ '[[:cntrl:]]'),
  CONSTRAINT articles_name_valid CHECK (
    length(name) BETWEEN 1 AND 120 AND name = btrim(name)
    AND name !~ '[[:cntrl:]]'),
  CONSTRAINT articles_unit_valid CHECK (
    length(unit) BETWEEN 1 AND 32 AND unit = btrim(unit)
    AND unit !~ '[[:cntrl:]]'),
  CONSTRAINT articles_barcode_valid CHECK (
    barcode IS NULL OR (length(barcode) BETWEEN 1 AND 64
      AND barcode = btrim(barcode) AND barcode !~ '[[:cntrl:]]')),
  CONSTRAINT articles_description_valid CHECK (
    description IS NULL OR (length(description) BETWEEN 1 AND 2000
      AND description = btrim(description)))
);
-- Case-insensitive per company for ASCII letters; the application computes the
-- same key from the shared contract helper.
CREATE UNIQUE INDEX articles_company_sku_key
  ON {{schema}}.articles (company_id, sku_key);
-- A barcode identifies one article within the company; multiple NULLs stay
-- allowed. Values are opaque text: no GTIN check-digit or type validation.
CREATE UNIQUE INDEX articles_company_barcode
  ON {{schema}}.articles (company_id, barcode) WHERE barcode IS NOT NULL;
CREATE INDEX articles_company_page ON {{schema}}.articles (company_id, id);
CREATE INDEX articles_company_active_name
  ON {{schema}}.articles (company_id, is_active, name);
