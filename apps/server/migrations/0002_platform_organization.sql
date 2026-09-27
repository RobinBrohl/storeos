CREATE TABLE {{schema}}.companies (
  id uuid PRIMARY KEY,
  singleton boolean NOT NULL DEFAULT true UNIQUE CHECK (singleton),
  name text,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT companies_name_valid CHECK (
    name IS NULL OR (length(btrim(name)) BETWEEN 1 AND 120 AND name = btrim(name))
  )
);

CREATE TABLE {{schema}}.locations (
  id uuid PRIMARY KEY,
  company_id uuid NOT NULL REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  name text,
  version bigint NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT locations_name_valid CHECK (
    name IS NULL OR (length(btrim(name)) BETWEEN 1 AND 120 AND name = btrim(name))
  ),
  CONSTRAINT locations_company_id_unique UNIQUE (id, company_id)
);

-- P0 installations already have stable IDs on their bootstrap account.
INSERT INTO {{schema}}.companies (id)
SELECT DISTINCT company_id FROM {{schema}}.accounts;

INSERT INTO {{schema}}.locations (id, company_id)
SELECT DISTINCT location_id, company_id FROM {{schema}}.accounts;

ALTER TABLE {{schema}}.accounts
  ADD COLUMN role text NOT NULL DEFAULT 'viewer',
  ADD COLUMN version bigint NOT NULL DEFAULT 1,
  ADD CONSTRAINT accounts_role_valid CHECK (role IN ('admin', 'auditor', 'viewer')),
  ADD CONSTRAINT accounts_version_positive CHECK (version > 0),
  ADD CONSTRAINT accounts_company_fk FOREIGN KEY (company_id)
    REFERENCES {{schema}}.companies(id) ON DELETE RESTRICT,
  ADD CONSTRAINT accounts_location_company_fk FOREIGN KEY (location_id, company_id)
    REFERENCES {{schema}}.locations(id, company_id) ON DELETE RESTRICT;

UPDATE {{schema}}.accounts AS account
SET role = 'admin'
FROM {{schema}}.bootstrap_state AS bootstrap
WHERE bootstrap.account_id = account.id;

CREATE INDEX accounts_company_location_idx
  ON {{schema}}.accounts (company_id, location_id, role)
  WHERE is_active;

CREATE INDEX locations_company_idx
  ON {{schema}}.locations (company_id, id);
